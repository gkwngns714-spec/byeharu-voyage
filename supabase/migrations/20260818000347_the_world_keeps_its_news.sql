-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0347 — THE WORLD KEEPS ITS NEWS, AND A CHART SHOWS ITS NEWS: one news table, its writers, the News read and the chart dots read. LIT
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Owner, 2026-10-26 (docs/OWNER_REQUESTS.md row 216): "i want all the chart recods to be saved, and when an update or a happening is made, it should make a point on the chart, and i will be
-- able to press it to see what caused it (major event, real time news-like feature)". Design: docs/NEWS_AND_MARKERS.md, slices N2 (the_world_keeps_its_news) and N3 (a_chart_shows_its_news)
-- in one file. N1 (records kept: 0226, 0246, 0316) is live. N4-N6 (big trades, price spikes, pirates, the E-slices' kinds) are NOT here.
--
-- WHAT THIS FILE ADDS
--   public.news_kinds(kind, importance, scope, en, ko)   THE KINDS ARE ROWS: one per kind, its importance (3 headline, 2 notable, 1 local), the widest place it shows, and its one headline
--                                                        template in each language ("New harbour: {city}"). A new kind is a row, never code. Seeded: UPDATE, NEW_HARBOUR, RELATIONS.
--   public.world_news                                     APPEND-ONLY (public.news_append_only, 0004's refusal): id, at, kind, importance, scope, the refs (port, good, company, power), key (idempotence), detail.
--                                                        detail.words fills the template's {names}: a string, {"en","ko"}, or {"kind","key","name"} (a proper name the client localises);
--                                                        detail.before / detail.after when a figure moved. Headlines are never stored.
--   public.news_post(kind, port, good, company, power, key, detail)   THE ONE WRITER (security definer, no client). Importance and scope are the kind's row. A key already posted is a no-op (null).
--   public.news_update(number, title en, title ko)        a migration's own "Update: {title}" row, key 'update:<number>'. This file posts its own.
--   public.news_place(port) / news_nation(nation) / news_stance_word(stance)   the words a writer puts in detail (server-only, stable / immutable).
--   public.news_item(row)                                 THE ONE SHAPE of a news item, read by both reads.
--   THE WRITERS (each in the transaction that causes it): an AFTER INSERT trigger on public.ports for a new HARBOUR (NEW_HARBOUR), an AFTER INSERT/UPDATE/DELETE trigger on
--     public.power_relations for a changed stance (RELATIONS). NOTHING in the live game writes either table (measured: no function body inserts into ports or writes power_relations;
--     both are written only by migrations), so neither trigger fires in the tick, a trade or a voyage: no live play and no tick cost moves. THAT IS WHY THIS FILE SHIPS LIT, with no switch.
--   world.news_feed(filter, after, before, limit)         THE NEWS FACE's read: newest first, at most 50; 'world' (importance 2+) or 'cities' (ports where the caller holds shares, has a
--                                                        fleet, or is heading). Answers {items, head}.
--   world.news_marks(chart, port, good, from, to)         THE DOTS' read: the news a chart is about inside its window (bounds inclusive), at most 300, newest first. 'price' (city P, good G):
--                                                        P's own news of G or of no good (any importance) + world importance 3. 'city' (P): P's news of no good, P's news of a good at importance
--                                                        2+, world 3. 'world': world 3. 'merchants': world 3 + company news 2+. A union of index range scans, never an OR over the table.
-- THE HUNKS (sliced from the LIVE bodies of head 0345, each asserted to occur once and to reverse to its pre-image; ACL, volatility, definer and settings unmoved):
--   world.stats_now            + 'news_head' (the newest news id, one index probe): the News face asks news_feed only when it moves. No second poll.
--   public.client_rpc_entry_points  + world.news_feed, world.news_marks (anchored on the stats_now row, not at the head or the tail, so another file's row cannot move it).
-- DECIDED BY DEFAULT: the table holding the kinds is news_kinds (the design's news_words), because it carries each kind's importance and scope beside its words. The 'goods' filter
--   waits for the first kind that names a good (N4): no kind here does. The card has no link to the city or company yet.
-- SELF-ASSERT: a probe in a sub-block rolled back whole (its kind, its rows at fixed instants in 2001, a probe harbour, a probe stance change), asserted gone after; it counts only its own
--   rows (ids above a mark taken in-block). It never deletes from world_news. Then this file's own UPDATE row, counted by its own key. Six timed reads printed.
-- BUDGET: statement_timeout 45 s, lock_timeout 5 s. The table is new and empty; the hunked bodies are a read and a registry. Locks: ports and power_relations take a trigger
--   (ShareRowExclusive, brief) and one probe row each, rolled back.
-- ROLLBACK (forward, owner only): a new migration dropping the two triggers stops every writer; swapping the two hunks back (each OLD text is here verbatim) removes the reads.
-- news: this file posts its own UPDATE row (public.news_update('0347', ...)), as every later file must (tests/news.lint.spec.ts).
-- VERSION: 0347 - prod head 0345 (read 2026-11-11); 0346 (the route builder) lands before it.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

set local statement_timeout = '45s';
set local lock_timeout = '5s';

-- ── 0. GUARD and the PRE-IMAGES, kept in a temp table for the self-assert at the end ──
create temp table pre_0347 (k text primary key, v text) on commit drop;

do $g$
begin
  if to_regclass('public.world_news') is not null or to_regclass('public.news_kinds') is not null
     or to_regprocedure('public.news_post(text,uuid,uuid,uuid,text,text,jsonb)') is not null
     or to_regprocedure('world.news_feed(text,bigint,bigint,integer)') is not null
     or to_regprocedure('world.news_marks(text,uuid,uuid,timestamp with time zone,timestamp with time zone)') is not null then
    raise exception '0347 refuses: something of it is already in this world';
  end if;
  if to_regprocedure('world.stats_now()') is null or to_regprocedure('public.client_rpc_entry_points()') is null
     or to_regprocedure('public.forbid_mutation()') is null or to_regclass('public.power_relations') is null
     or to_regprocedure('public.current_player_id()') is null or to_regclass('public.city_shares') is null
     or not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'ports' and column_name = 'kind') then
    raise exception '0347 refuses: 0004 / 0123 / 0196 / 0224 (the bodies it cuts, the tables it watches) are not all in this world';
  end if;
  insert into pre_0347 values
    ('fn', (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
              from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
               and p.oid not in ('world.stats_now()'::regprocedure, 'public.client_rpc_entry_points()'::regprocedure))),
    ('meta', (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
                from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p'))),
    ('cfg', (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c)),
    ('rel', (select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname))
               from pg_class c join pg_namespace n on n.oid = c.relnamespace
              where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p'))),
    ('trig', (select md5(string_agg(t.tgrelid::regclass::text || ':' || t.tgname || ':' || t.tgenabled::text, ',' order by t.tgrelid::regclass::text, t.tgname))
                from pg_trigger t where not t.tgisinternal)),
    ('relations', (select md5(coalesce(string_agg(r.a::text || r.b::text || r.stance || r.why, ',' order by r.a, r.b), '')) from public.power_relations r)),
    ('ports', (select count(*)::text from public.ports)),
    ('entry', (select count(*)::text from public.client_rpc_entry_points()));
end $g$;

-- ── 1. THE KINDS (rows, not code) ──
create table public.news_kinds (
  kind       text primary key check (kind ~ '^[A-Z][A-Z0-9_]*$'),
  importance smallint not null check (importance between 1 and 3),
  scope      text not null check (scope in ('world', 'power', 'port', 'good', 'company')),
  en         text not null check (length(en) between 3 and 80),
  ko         text not null check (length(ko) between 2 and 80)
);
comment on table public.news_kinds is
  '0347 (docs/NEWS_AND_MARKERS.md section 2): one row per news kind: its importance (3 headline, 2 notable, 1 local), the widest place it shows, and its ONE headline template '
  'in each language; {name} is filled from world_news.detail->words by the client. A new kind is a row here and a call to public.news_post in the transaction that causes it.';
alter table public.news_kinds enable row level security;
revoke all on table public.news_kinds from public, anon, authenticated;

insert into public.news_kinds (kind, importance, scope, en, ko) values
  ('UPDATE',      3, 'world', 'Update: {title}',              '업데이트: {title}'),
  ('NEW_HARBOUR', 3, 'world', 'New harbour: {city}',          '새 항구: {city}'),
  ('RELATIONS',   3, 'world', '{a} and {b}: now {stance}',    '{a}–{b}: {stance}');

-- ── 2. THE NEWS (append-only) ──
create table public.world_news (
  id         bigint generated always as identity primary key,
  at         timestamptz not null default clock_timestamp(),
  kind       text not null references public.news_kinds(kind),
  importance smallint not null check (importance between 1 and 3),
  scope      text not null check (scope in ('world', 'power', 'port', 'good', 'company')),
  port_id    uuid null references public.ports(id),
  good_id    uuid null references public.goods(id),
  company_id uuid null,
  power      text null,
  key        text null unique,
  detail     jsonb not null default '{}'::jsonb check (jsonb_typeof(detail) = 'object')
);
comment on table public.world_news is
  '0347 (docs/NEWS_AND_MARKERS.md section 2): every happening the world tells, append-only (public.news_append_only). Written ONLY by public.news_post, inside the transaction that '
  'causes it; read only through world.news_feed and world.news_marks. company_id is a players.id (company names in news are public). key makes a post idempotent.';
create index world_news_scope_at on public.world_news (scope, at desc);
create index world_news_port_at on public.world_news (port_id, at desc) where port_id is not null;
create index world_news_good_at on public.world_news (good_id, at desc) where good_id is not null;
alter table public.world_news enable row level security;
revoke all on table public.world_news from public, anon, authenticated;
-- 0004's forbid_mutation reads old.player_id (its one exemption), which a news row has not: the same refusal, its own body.
create function public.news_append_only()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $f$
begin
  raise exception '% is append-only: % is not permitted', tg_table_name, tg_op using errcode = '42501';
end $f$;
revoke all on function public.news_append_only() from public, anon, authenticated;
create trigger world_news_append_only
  before update or delete on public.world_news
  for each row execute function public.news_append_only();

-- ── 3. THE ONE WRITER, and the words writers put in detail ──
create function public.news_post(p_kind text, p_port uuid, p_good uuid, p_company uuid, p_power text, p_key text, p_detail jsonb)
returns bigint
language sql
volatile security definer
set search_path = public, pg_temp
as $f$
  -- 0347: THE one writer of public.world_news. The kind's row gives the importance and the scope; a key already posted is a no-op (null).
  insert into public.world_news (kind, importance, scope, port_id, good_id, company_id, power, key, detail)
  select k.kind, k.importance, k.scope, p_port, p_good, p_company, p_power, p_key, coalesce(p_detail, '{}'::jsonb)
    from public.news_kinds k
   where k.kind = p_kind
  on conflict (key) do nothing
  returning id
$f$;

create function public.news_update(p_number text, p_en text, p_ko text)
returns bigint
language sql
volatile security definer
set search_path = public, pg_temp
as $f$
  -- 0347: a migration's own "Update: {title}" row. Idempotent by its key, so a chain replayed from zero posts each once.
  select public.news_post('UPDATE', null, null, null, null, 'update:' || p_number,
                          jsonb_build_object('words', jsonb_build_object('title', jsonb_build_object('en', p_en, 'ko', p_ko)), 'number', p_number))
$f$;

create function public.news_place(p_port uuid)
returns jsonb
language sql
stable security definer
set search_path = public, pg_temp
as $f$
  -- 0347: a port as a news word: the client localises it by the served name (properName 'port').
  select jsonb_build_object('kind', 'port', 'key', p.name, 'name', p.name) from public.ports p where p.id = p_port
$f$;

create function public.news_nation(p_nation uuid)
returns jsonb
language sql
stable security definer
set search_path = public, pg_temp
as $f$
  -- 0347: a nation as a news word: the client localises it by its code (properName 'nation').
  select jsonb_build_object('kind', 'nation', 'key', n.code, 'name', n.name) from public.nations n where n.id = p_nation
$f$;

create function public.news_stance_word(p_stance text)
returns jsonb
language sql
immutable
set search_path = public, pg_temp
as $f$
  -- 0347: how two powers stand (0196's stances, and peace for no row), in both languages.
  select case p_stance
           when 'ally'  then '{"en": "allies", "ko": "동맹"}'::jsonb
           when 'rival' then '{"en": "rivals", "ko": "적대"}'::jsonb
           when 'war'   then '{"en": "at war", "ko": "전쟁"}'::jsonb
           else              '{"en": "at peace", "ko": "평화"}'::jsonb
         end
$f$;

-- ── 4. THE WRITERS (triggers: each in the transaction that causes it) ──
create function public.news_on_harbour()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $f$
-- 0347: a new HARBOUR is headline news. Only a migration inserts ports today.
begin
  perform public.news_post('NEW_HARBOUR', new.id, null, null, null, 'harbour:' || new.id::text,
                           jsonb_build_object('words', jsonb_build_object('city', public.news_place(new.id))));
  return null;
end $f$;

create function public.news_on_relations()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $f$
-- 0347: two powers' stance changed (a row added, its stance moved, or removed: peace). Only a migration writes power_relations today.
declare
  v_a   uuid := case when tg_op = 'DELETE' then old.a else new.a end;
  v_b   uuid := case when tg_op = 'DELETE' then old.b else new.b end;
  v_was text := case when tg_op = 'INSERT' then 'peace' else old.stance end;
  v_now text := case when tg_op = 'DELETE' then 'peace' else new.stance end;
begin
  if tg_op = 'UPDATE' and (old.a, old.b) is distinct from (new.a, new.b) then
    v_was := 'peace';
  elsif v_was is not distinct from v_now then
    return null;
  end if;
  perform public.news_post('RELATIONS', null, null, null, null, null,
                           jsonb_build_object('words', jsonb_build_object('a', public.news_nation(v_a), 'b', public.news_nation(v_b),
                                                                          'stance', public.news_stance_word(v_now)),
                                              'before', public.news_stance_word(v_was), 'after', public.news_stance_word(v_now)));
  return null;
end $f$;

create trigger ports_news_harbour
  after insert on public.ports
  for each row when (new.kind = 'HARBOUR') execute function public.news_on_harbour();
create trigger power_relations_news
  after insert or update or delete on public.power_relations
  for each row execute function public.news_on_relations();

-- ── 5. THE READS ──
create function public.news_item(w public.world_news)
returns jsonb
language sql
stable security definer
set search_path = public, pg_temp
as $f$
  -- 0347: THE one shape of a news item, read by world.news_feed and world.news_marks. The templates are the kind's; the client fills {names} from detail.words.
  select jsonb_build_object('id', w.id, 'at', w.at, 'kind', w.kind, 'importance', w.importance, 'scope', w.scope,
                            'port_id', w.port_id, 'good_id', w.good_id, 'company_id', w.company_id, 'power', w.power,
                            'en', k.en, 'ko', k.ko, 'detail', w.detail)
    from public.news_kinds k
   where k.kind = w.kind
$f$;

create function world.news_feed(p_filter text, p_after bigint, p_before bigint, p_limit int)
returns jsonb
language plpgsql
stable security definer
set search_path = public, pg_temp
as $f$
-- 0347: THE News face's read. Newest first, at most 50 (p_limit 1..50), ids above p_after and below p_before. 'world': importance 2 and up. 'cities': the news of the ports where the
-- caller holds city shares, has a fleet, or has a fleet heading (any importance). Answers {items, head}: head is the newest id of all, the same figure world.stats_now serves.
declare
  v_lim   int := least(greatest(coalesce(p_limit, 50), 1), 50);
  v_me    uuid;
  v_ports uuid[];
  v_items jsonb;
begin
  if p_filter is null or p_filter not in ('world', 'cities') then
    raise exception 'E_BAD_FILTER: the news is world or cities, not %', coalesce(p_filter, 'null') using errcode = 'P0001';
  end if;
  if p_filter = 'world' then
    select coalesce(jsonb_agg(public.news_item(x) order by x.id desc), '[]'::jsonb) into v_items
      from (select w.* from public.world_news w
             where w.importance >= 2 and (p_after is null or w.id > p_after) and (p_before is null or w.id < p_before)
             order by w.id desc limit v_lim) x;
  else
    v_me := public.current_player_id();
    select coalesce(array_agg(distinct q.port_id), '{}') into v_ports
      from (select s.port_id from public.city_shares s where s.player_id = v_me
            union select f.port_id from public.fleets f where f.player_id = v_me and f.port_id is not null
            union select v.dest_port_id from public.voyages v where v.player_id = v_me and v.status = 'SAILING') q;
    select coalesce(jsonb_agg(public.news_item(x) order by x.id desc), '[]'::jsonb) into v_items
      from (select w.* from public.world_news w
             where w.port_id = any (v_ports) and (p_after is null or w.id > p_after) and (p_before is null or w.id < p_before)
             order by w.id desc limit v_lim) x;
  end if;
  return jsonb_build_object('filter', p_filter, 'items', v_items, 'head', (select max(n.id) from public.world_news n));
end $f$;

create function world.news_marks(p_chart text, p_port uuid, p_good uuid, p_from timestamptz, p_to timestamptz)
returns jsonb
language plpgsql
stable security definer
set search_path = public, pg_temp
as $f$
-- 0347: THE dots of a chart: the news it is about between p_from and p_to (both inclusive; a null bound is open: the start of the record, the newest row), at most 300, newest first.
-- Each branch is an index range scan ((scope, at) or (port_id, at)); their union is the set. docs/NEWS_AND_MARKERS.md section 3.1.
declare
  v_from  timestamptz := coalesce(p_from, '-infinity'::timestamptz);
  v_to    timestamptz := coalesce(p_to, 'infinity'::timestamptz);
  v_items jsonb;
begin
  if p_chart is null or p_chart not in ('price', 'city', 'world', 'merchants') then
    raise exception 'E_BAD_CHART: a chart is price, city, world or merchants, not %', coalesce(p_chart, 'null') using errcode = 'P0001';
  end if;
  if p_chart in ('price', 'city') and p_port is null then
    raise exception 'E_BAD_CHART: a % chart names its city', p_chart using errcode = 'P0001';
  end if;
  select coalesce(jsonb_agg(public.news_item(x) order by x.at desc, x.id desc), '[]'::jsonb) into v_items
    from (select u.* from (
            select w.* from public.world_news w
             where w.scope = 'world' and w.importance >= 3 and w.at >= v_from and w.at <= v_to
            union
            select w.* from public.world_news w
             where p_chart in ('price', 'city') and w.port_id = p_port and w.at >= v_from and w.at <= v_to
               and (case when p_chart = 'price' then w.good_id is null or w.good_id = p_good
                         else w.good_id is null or w.importance >= 2 end)
            union
            select w.* from public.world_news w
             where p_chart = 'merchants' and w.scope = 'company' and w.importance >= 2 and w.at >= v_from and w.at <= v_to) u
          order by u.at desc, u.id desc limit 300) x;
  return jsonb_build_object('chart', p_chart, 'from', v_from, 'to', v_to, 'items', v_items);
end $f$;

revoke all on function public.news_post(text, uuid, uuid, uuid, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.news_update(text, text, text) from public, anon, authenticated;
revoke all on function public.news_place(uuid) from public, anon, authenticated;
revoke all on function public.news_nation(uuid) from public, anon, authenticated;
revoke all on function public.news_stance_word(text) from public, anon, authenticated;
revoke all on function public.news_on_harbour() from public, anon, authenticated;
revoke all on function public.news_on_relations() from public, anon, authenticated;
revoke all on function public.news_item(public.world_news) from public, anon, authenticated;
revoke all on function world.news_feed(text, bigint, bigint, int) from public, anon;
revoke all on function world.news_marks(text, uuid, uuid, timestamptz, timestamptz) from public, anon;
grant execute on function world.news_feed(text, bigint, bigint, int) to authenticated;
grant execute on function world.news_marks(text, uuid, uuid, timestamptz, timestamptz) to authenticated;

-- ── 6. THE HUNKS, the PROBE and the SELF-ASSERT ──
do $m$
declare
  v_t0     timestamptz := clock_timestamp();
  v_h      record;
  v_def    text;
  v_pre    text;
  v_n      int;
  v_mark   bigint;
  v_id     bigint;
  v_id2    bigint;
  v_port   uuid;
  v_port2  uuid;
  v_good   uuid;
  v_good2  uuid;
  v_probe  uuid;
  v_code   text;
  v_rel    record;
  v_res    jsonb;
  v_ids    bigint[];
  v_r      bigint[] := '{}';
  v_t      timestamptz := '2001-02-03 04:00:00+00';
  v_ms     text := '';
  v_ts     timestamptz;
  v_lo     bigint;
  v_hi     bigint;
  c_new_fns constant text[] := array['public.news_post(text,uuid,uuid,uuid,text,text,jsonb)', 'public.news_update(text,text,text)', 'public.news_place(uuid)',
                                     'public.news_nation(uuid)', 'public.news_stance_word(text)', 'public.news_on_harbour()', 'public.news_on_relations()',
                                     'public.news_item(public.world_news)', 'public.news_append_only()', 'world.news_feed(text,bigint,bigint,integer)',
                                     'world.news_marks(text,uuid,uuid,timestamp with time zone,timestamp with time zone)'];
  c_new_rels constant text[] := array['public.news_kinds', 'public.news_kinds_pkey', 'public.world_news', 'public.world_news_pkey', 'public.world_news_id_seq',
                                      'public.world_news_key_key', 'public.world_news_scope_at', 'public.world_news_port_at', 'public.world_news_good_at'];
  c_new_trigs constant text[] := array['world_news_append_only', 'ports_news_harbour', 'power_relations_news'];
begin
  -- THE HUNKS (each occurs exactly once in the live body, and reverses)
  create temp table hunks_0347 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0347 values
  ('world.stats_now()', 1,
$h$           'counted_at', l.counted_at, 'counted_through', l.counted_through, 'drift', l.drift)
$h$,
$h$           'counted_at', l.counted_at, 'counted_through', l.counted_through, 'drift', l.drift,
           'news_head', (select max(n.id) from public.world_news n))   -- 0347: the newest news id (one index probe): the News face asks world.news_feed when it moves
$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('world',       'stats_now',             ''),
$h$,
$h$      ('world',       'stats_now',             ''),
      -- 0347: the News face's read and a chart's dots (docs/NEWS_AND_MARKERS.md).
      ('world',       'news_feed',             'text, bigint, bigint, int'),
      ('world',       'news_marks',            'text, uuid, uuid, timestamptz, timestamptz'),
$h$);

  for v_h in select h.fn from hunks_0347 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    declare
      x record;
    begin
      for x in select * from hunks_0347 h where h.fn = v_h.fn order by h.ord loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0347 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
      for x in select * from hunks_0347 h where h.fn = v_h.fn order by h.ord desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0347 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0347 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;

  -- THE PROBE (a sub-block rolled back whole; it counts only its own rows, ids above a mark taken here)
  select p.id into v_port from public.ports p where p.kind = 'HARBOUR' order by p.code limit 1;
  select p.id into v_port2 from public.ports p where p.kind = 'HARBOUR' and p.id <> v_port order by p.code limit 1;
  select g.id into v_good from public.goods g order by g.code limit 1;
  select g.id into v_good2 from public.goods g where g.id <> v_good order by g.code limit 1;
  if v_port is null or v_port2 is null or v_good is null or v_good2 is null then
    raise exception '0347 self-assert FAIL: the probe needs two harbours and two goods';
  end if;
  begin
    v_mark := coalesce((select max(w.id) from public.world_news w), 0);
    v_lo := v_mark;
    insert into public.news_kinds (kind, importance, scope, en, ko) values ('PROBE_0347', 1, 'port', 'Probe at {city}', '시험 {city}');

    -- one post, one row; the same key again is a no-op
    v_id := public.news_post('PROBE_0347', v_port, v_good, null, null, 'probe:0347:1', jsonb_build_object('words', jsonb_build_object('city', public.news_place(v_port))));
    v_id2 := public.news_post('PROBE_0347', v_port, v_good, null, null, 'probe:0347:1', '{}'::jsonb);
    if v_id is null or v_id2 is not null or (select count(*) from public.world_news w where w.id > v_mark) <> 1
       or (select w.importance::text || w.scope from public.world_news w where w.id = v_id) <> '1port' then
      raise exception '0347 self-assert FAIL: a post did not write exactly one row with its kind''s importance and scope, or its key did not make a second post a no-op';
    end if;
    -- append-only
    begin
      update public.world_news set importance = 3 where id = v_id;
      raise exception '0347 self-assert FAIL: an UPDATE of world_news was let through';
    exception when insufficient_privilege then null;
    end;
    begin
      delete from public.world_news where id = v_id;
      raise exception '0347 self-assert FAIL: a DELETE from world_news was let through';
    exception when insufficient_privilege then null;
    end;

    -- a probe HARBOUR inserts one NEW_HARBOUR row naming it
    v_code := (select c from (select chr(81) || chr(65 + i / 26) || chr(65 + i % 26) as c from generate_series(0, 675) i) z
                where not exists (select 1 from public.ports p where p.code = z.c) order by c limit 1);
    v_mark := coalesce((select max(w.id) from public.world_news w), 0);
    insert into public.ports
    select (jsonb_populate_record(null::public.ports, to_jsonb(p) || jsonb_build_object('id', gen_random_uuid(), 'code', v_code, 'name', 'Probe Harbour 0347'))).*
      from public.ports p where p.id = v_port
    returning id into v_probe;
    if (select count(*) from public.world_news w where w.id > v_mark) <> 1
       or not exists (select 1 from public.world_news w where w.id > v_mark and w.kind = 'NEW_HARBOUR' and w.port_id = v_probe and w.importance = 3 and w.scope = 'world'
                         and w.detail->'words'->'city'->>'name' = 'Probe Harbour 0347') then
      raise exception '0347 self-assert FAIL: a probe harbour did not write exactly one NEW_HARBOUR row naming it';
    end if;

    -- a probe STANCE change writes one RELATIONS row with before and after; a change of its words alone writes none
    select r.* into v_rel from public.power_relations r order by r.a, r.b limit 1;
    if v_rel.a is null then
      raise exception '0347 self-assert FAIL: the probe needs a power_relations row';
    end if;
    v_mark := coalesce((select max(w.id) from public.world_news w), 0);
    update public.power_relations set why = why || ' (probe 0347)' where a = v_rel.a and b = v_rel.b;
    if exists (select 1 from public.world_news w where w.id > v_mark) then
      raise exception '0347 self-assert FAIL: a change of a relation''s words alone wrote news';
    end if;
    update public.power_relations set stance = case when v_rel.stance = 'war' then 'rival' else 'war' end where a = v_rel.a and b = v_rel.b;
    if (select count(*) from public.world_news w where w.id > v_mark) <> 1
       or not exists (select 1 from public.world_news w where w.id > v_mark and w.kind = 'RELATIONS'
                         and w.detail->'before'->>'en' = (public.news_stance_word(v_rel.stance))->>'en'
                         and w.detail->'after'->>'en' = (public.news_stance_word(case when v_rel.stance = 'war' then 'rival' else 'war' end))->>'en'
                         and w.detail->'words'->'a'->>'kind' = 'nation') then
      raise exception '0347 self-assert FAIL: a probe stance change did not write exactly one RELATIONS row with its before and after';
    end if;

    -- every placeholder of every kind a real writer wrote above has its word, in both languages
    if exists (select 1 from public.world_news w join public.news_kinds k on k.kind = w.kind
                cross join lateral (select m[1] as name from regexp_matches(k.en || ' ' || k.ko, '\{([a-z_]+)\}', 'g') m) ph
               where w.id > v_lo and not (w.detail->'words' ? ph.name)) then
      raise exception '0347 self-assert FAIL: a template names a word its writer did not put in detail';
    end if;

    -- THE MARKS: probe rows at fixed instants in 2001 (no hour-of-day dependence), on the probe ports and goods
    v_mark := coalesce((select max(w.id) from public.world_news w), 0);
    insert into public.world_news (at, kind, importance, scope, port_id, good_id, company_id, detail) values
      (v_t,                          'PROBE_0347', 1, 'port',    v_port,  v_good,  null, '{}'),   -- r1 own good, at the window's first instant
      (v_t + interval '1 minute',    'PROBE_0347', 1, 'port',    v_port,  null,    null, '{}'),   -- r2 own port, no good
      (v_t + interval '2 minutes',   'PROBE_0347', 2, 'port',    v_port,  v_good2, null, '{}'),   -- r3 own port, another good, notable
      (v_t + interval '3 minutes',   'PROBE_0347', 1, 'port',    v_port,  v_good2, null, '{}'),   -- r4 own port, another good, local
      (v_t + interval '4 minutes',   'PROBE_0347', 3, 'world',   null,    null,    null, '{}'),   -- r5 world headline
      (v_t + interval '5 minutes',   'PROBE_0347', 2, 'world',   null,    null,    null, '{}'),   -- r6 world notable
      (v_t + interval '6 minutes',   'PROBE_0347', 3, 'port',    v_port2, v_good,  null, '{}'),   -- r7 another port
      (v_t + interval '7 minutes',   'PROBE_0347', 2, 'company', null,    null,    v_port, '{}'), -- r8 a company's
      (v_t + interval '10 minutes',  'PROBE_0347', 3, 'world',   null,    null,    null, '{}'),   -- r9 world headline at the window's last instant
      (v_t + interval '1 day',       'PROBE_0347', 3, 'world',   null,    null,    null, '{}');   -- r10 outside the window
    select array_agg(w.id order by w.id) into v_r from public.world_news w where w.id > v_mark;
    v_hi := v_r[10];

    v_ts := clock_timestamp();
    v_res := world.news_marks('price', v_port, v_good, v_t, v_t + interval '10 minutes');
    v_ms := v_ms || 'price ' || round(extract(epoch from clock_timestamp() - v_ts) * 1000, 2) || ' ms';
    select array_agg((i->>'id')::bigint order by (i->>'id')::bigint) into v_ids from jsonb_array_elements(v_res->'items') i;
    if v_ids is distinct from array[v_r[1], v_r[2], v_r[5], v_r[9]] then
      raise exception '0347 self-assert FAIL: the price chart''s marks are % not own + world headlines inside the window %', v_ids, array[v_r[1], v_r[2], v_r[5], v_r[9]];
    end if;
    if (v_res->'items'->0->>'id')::bigint <> v_r[9] or v_res->'items'->0->>'en' <> 'Probe at {city}' or v_res->'items'->0->>'ko' <> '시험 {city}' then
      raise exception '0347 self-assert FAIL: the marks are not newest first, or an item does not carry its kind''s two templates';
    end if;

    v_ts := clock_timestamp();
    v_res := world.news_marks('city', v_port, null, v_t, v_t + interval '10 minutes');
    v_ms := v_ms || ', city ' || round(extract(epoch from clock_timestamp() - v_ts) * 1000, 2) || ' ms';
    select array_agg((i->>'id')::bigint order by (i->>'id')::bigint) into v_ids from jsonb_array_elements(v_res->'items') i;
    if v_ids is distinct from array[v_r[2], v_r[3], v_r[5], v_r[9]] then
      raise exception '0347 self-assert FAIL: the city chart''s marks are % not its own (goods at 2+) + world headlines', v_ids;
    end if;

    v_ts := clock_timestamp();
    v_res := world.news_marks('world', null, null, v_t, v_t + interval '10 minutes');
    v_ms := v_ms || ', world ' || round(extract(epoch from clock_timestamp() - v_ts) * 1000, 2) || ' ms';
    select array_agg((i->>'id')::bigint order by (i->>'id')::bigint) into v_ids from jsonb_array_elements(v_res->'items') i;
    if v_ids is distinct from array[v_r[5], v_r[9]] then
      raise exception '0347 self-assert FAIL: the world chart''s marks are % not the world headlines', v_ids;
    end if;

    v_ts := clock_timestamp();
    v_res := world.news_marks('merchants', null, null, v_t, v_t + interval '10 minutes');
    v_ms := v_ms || ', merchants ' || round(extract(epoch from clock_timestamp() - v_ts) * 1000, 2) || ' ms';
    select array_agg((i->>'id')::bigint order by (i->>'id')::bigint) into v_ids from jsonb_array_elements(v_res->'items') i;
    if v_ids is distinct from array[v_r[5], v_r[8], v_r[9]] then
      raise exception '0347 self-assert FAIL: the merchants chart''s marks are % not the world headlines + company news', v_ids;
    end if;

    begin
      perform world.news_marks('pie', null, null, null, null);
      raise exception '0347 self-assert FAIL: an unknown chart was answered';
    exception when raise_exception then
      if sqlerrm not like 'E_BAD_CHART%' then raise; end if;
    end;
    begin
      perform world.news_marks('price', null, v_good, null, null);
      raise exception '0347 self-assert FAIL: a price chart of no city was answered';
    exception when raise_exception then
      if sqlerrm not like 'E_BAD_CHART%' then raise; end if;
    end;

    -- THE FEED: newest first, importance 2+ for the world, paged by id
    v_ts := clock_timestamp();
    v_res := world.news_feed('world', v_mark, null, 50);
    v_ms := v_ms || ', feed world ' || round(extract(epoch from clock_timestamp() - v_ts) * 1000, 2) || ' ms';
    select array_agg((i->>'id')::bigint order by o) into v_ids from jsonb_array_elements(v_res->'items') with ordinality t(i, o);
    if v_ids is distinct from array[v_r[10], v_r[9], v_r[8], v_r[7], v_r[6], v_r[5], v_r[3]] or (v_res->>'head')::bigint <> v_hi then
      raise exception '0347 self-assert FAIL: the world feed is % (head %), not the notable rows newest first', v_ids, v_res->>'head';
    end if;
    v_res := world.news_feed('world', v_mark, v_r[8], 2);
    select array_agg((i->>'id')::bigint order by o) into v_ids from jsonb_array_elements(v_res->'items') with ordinality t(i, o);
    if v_ids is distinct from array[v_r[7], v_r[6]] then
      raise exception '0347 self-assert FAIL: an older page of the feed is % not the two below its bound', v_ids;
    end if;
    v_ts := clock_timestamp();
    v_res := world.news_feed('cities', v_mark, null, 50);
    v_ms := v_ms || ', feed cities ' || round(extract(epoch from clock_timestamp() - v_ts) * 1000, 2) || ' ms';
    if jsonb_typeof(v_res->'items') <> 'array' or jsonb_array_length(v_res->'items') <> 0 then
      raise exception '0347 self-assert FAIL: the cities feed of no caller is not empty: %', v_res;
    end if;
    begin
      perform world.news_feed('stars', null, null, null);
      raise exception '0347 self-assert FAIL: an unknown filter was answered';
    exception when raise_exception then
      if sqlerrm not like 'E_BAD_FILTER%' then raise; end if;
    end;

    -- THE LIVE HEAD: world.stats_now serves the newest id
    if (world.stats_now()->>'news_head')::bigint is distinct from v_hi then
      raise exception '0347 self-assert FAIL: world.stats_now serves news_head % not %', world.stats_now()->>'news_head', v_hi;
    end if;

    raise exception using errcode = 'P0001', message = 'rollback_0347_probe';
  exception when raise_exception then
    if sqlerrm <> 'rollback_0347_probe' then raise; end if;
  end;

  -- THE PROBE IS GONE: its rows, its kind, its harbour, its stance
  if exists (select 1 from public.world_news w where w.id > v_lo and w.id <= v_hi)
     or exists (select 1 from public.news_kinds k where k.kind = 'PROBE_0347')
     or exists (select 1 from public.ports p where p.name = 'Probe Harbour 0347')
     or (select count(*)::text from public.ports) <> (select v from pre_0347 where k = 'ports')
     or (select md5(coalesce(string_agg(r.a::text || r.b::text || r.stance || r.why, ',' order by r.a, r.b), '')) from public.power_relations r) <> (select v from pre_0347 where k = 'relations') then
    raise exception '0347 self-assert FAIL: the probe left a trace';
  end if;

  -- THIS FILE'S OWN UPDATE ROW, counted by its own key; a second post is a no-op
  perform public.news_update('0347', 'News', '소식');
  if public.news_update('0347', 'News', '소식') is not null
     or (select count(*) from public.world_news w where w.key = 'update:0347') <> 1
     or not exists (select 1 from public.world_news w where w.key = 'update:0347' and w.kind = 'UPDATE' and w.importance = 3 and w.scope = 'world'
                       and w.detail->'words'->'title'->>'ko' = '소식') then
    raise exception '0347 self-assert FAIL: this file''s UPDATE row is not one row, or posting it again was not a no-op';
  end if;

  -- THE CATALOG
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid not in ('world.stats_now()'::regprocedure, 'public.client_rpc_entry_points()'::regprocedure)
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_new_fns) x))) <> (select v from pre_0347 where k = 'fn') then
    raise exception '0347 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_new_fns) x))) <> (select v from pre_0347 where k = 'meta') then
    raise exception '0347 self-assert FAIL: an ACL, a volatility, a definer flag or a setting moved (the re-cut bodies included)';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c)
       <> (select v from pre_0347 where k = 'cfg') then
    raise exception '0347 self-assert FAIL: a world_config row moved: this file adds no knob and no switch';
  end if;
  if (select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname))
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p')
         and n.nspname || '.' || c.relname <> all (c_new_rels)) <> (select v from pre_0347 where k = 'rel')
     or (select count(*) from unnest(c_new_rels) r where to_regclass(r) is not null) <> cardinality(c_new_rels) then
    raise exception '0347 self-assert FAIL: a relation other than this file''s two tables and their indexes appeared or went';
  end if;
  if (select md5(string_agg(t.tgrelid::regclass::text || ':' || t.tgname || ':' || t.tgenabled::text, ',' order by t.tgrelid::regclass::text, t.tgname))
        from pg_trigger t where not t.tgisinternal and t.tgname <> all (c_new_trigs)) <> (select v from pre_0347 where k = 'trig')
     or (select count(*) from pg_trigger t where not t.tgisinternal and t.tgname = any (c_new_trigs) and t.tgenabled = 'O') <> 3 then
    raise exception '0347 self-assert FAIL: a trigger other than this file''s three moved, or one of its three is not enabled';
  end if;
  if (select string_agg(p.provolatile::text || case when p.prosecdef then 'd' else '-' end, '' order by f.o)
        from unnest(c_new_fns) with ordinality f(fn, o) join pg_proc p on p.oid = f.fn::regprocedure) is distinct from 'vdvdsdsdi-vdvdsdv-sdsd' then
    raise exception '0347 self-assert FAIL: the new functions'' volatility / definer flags are not as written: %',
      (select string_agg(p.oid::regprocedure::text || '=' || p.provolatile::text || case when p.prosecdef then 'd' else '-' end, ' ' order by p.oid::regprocedure::text)
         from pg_proc p where p.oid = any (array(select x::regprocedure::oid from unnest(c_new_fns) x)));
  end if;
  if exists (select 1 from unnest(c_new_fns) f where f not like 'world.%' and (has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')))
     or exists (select 1 from unnest(c_new_fns) f where f like 'world.%' and (has_function_privilege('anon', f, 'execute') or not has_function_privilege('authenticated', f, 'execute')))
     or has_table_privilege('anon', 'public.world_news', 'select, insert, update, delete') or has_table_privilege('authenticated', 'public.world_news', 'select, insert, update, delete')
     or has_table_privilege('anon', 'public.news_kinds', 'select, insert, update, delete') or has_table_privilege('authenticated', 'public.news_kinds', 'select, insert, update, delete') then
    raise exception '0347 self-assert FAIL: a client can reach the writer or the tables, or cannot reach the two reads';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select v::int + 2 from pre_0347 where k = 'entry')
     or (select count(*) from public.client_rpc_entry_points() e where e.function_name in ('news_feed', 'news_marks') and e.fn is not null) <> 2
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0347 self-assert FAIL: the registry is not two doors more, or a wall moved (the posture must read zero)';
  end if;

  raise notice '0347 self-assert ok: THE WORLD KEEPS ITS NEWS. public.world_news (append-only) + public.news_kinds (3 kinds), one writer (news_post), two writers live (NEW_HARBOUR on ports, RELATIONS on power_relations; neither table is written by the game), world.news_feed + world.news_marks (2 doors), world.stats_now + news_head; % hunks over % bodies, each once and reversing. Probe rolled back: a post and its key, append-only, a harbour, a stance, the four charts'' sets, the feed''s order and page, the live head. Timed: %. This file''s UPDATE row posted once. % ms.',
    (select count(*) from hunks_0347), (select count(distinct h.fn) from hunks_0347 h), v_ms, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0347;
end $m$;
