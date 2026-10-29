-- 0279 — A CHART SHOWS ITS NEWS   (owner row 216: every chart record kept, and a point on the chart
--        for every happening, with a press that says what caused it — "real time, news-like")
--
-- THE ROOT. The owner (2026-10-26): "i want all the chart recods to be saved, and when an update or a
-- happening is made, it should make a point on the chart, and i will be able to press it to see what
-- caused it (major event, real time news-like feature)". The design is docs/NEWS_AND_MARKERS.md; this
-- file is its slice N3 ("a chart shows its news"), the markers read + the client dots, COMPOSED OUT OF
-- WHAT THE WRITERS ALREADY FEED. The design's `public.world_news` table is NOT built: public.events
-- (0004, append-only, with payloads) IS the news log the existing writers already write, so a marker is
-- an EVENT ROW read through one mapping — no second event log, no duplicated marker registry, no writer
-- hunks. The words live in the client's i18n dict (one authority per concept, src/lib/i18n/dict/news.ts);
-- the client computes no figure the server can serve (qty, totals, names and the window are all served).
--
-- THE MAPPING — which events are markers (docs/NEWS_AND_MARKERS.md §2.2, the kinds whose writers exist):
--   ECONOMY_SWITCH (0240/0268, the economy switch)          -> the design's UPDATE kind:   imp 3, world
--   SOLD (0007, cmd.do_sell), total >= 250,000              -> BIG_SALE:                   imp 2, port+good+company
--   BOUGHT (0007, cmd.do_buy), total >= 250,000             -> BIG_BUY:                    imp 2, port+good+company
--   NPC_REFOUNDED (0097, the merchant upkeep's crossing pass) -> the design's MERCHANT_BROKE pass (the
--       refound IS the record of the crossing; the writer's own cooldown and weekly cap are the anti-spam):
--                                                                                          imp 2, company
-- The threshold 250,000 is the design's §2.2 constant, held in public.news_kinds.min_total — NOT a
-- world_config knob (none is added); N4's writer hunk will re-cut it to the news_big_trade knob.
-- The design kinds whose writers do not exist yet (NEW_HARBOUR, RELATIONS, WANTS, PRICE_SPIKE, RESTOCK,
-- PIRATES, and the E-slices' gifts) produce NO markers until their slices land — said plainly below.
-- The design's §3.1 chart table is the read's own WHERE: price = own port+good ∪ world (imp 3), city =
-- port ∪ world, world = world imp 3, merchants = world ∪ the merchant pass. Marks sit on the SAME
-- wall-clock axis the charts already draw (the events' own created_at) — no second clock is minted
-- (world.game_day / world.week_of stay 0275's authority, untouched).
--
-- WHERE A TRADE'S PORT COMES FROM. SOLD / BOUGHT payloads carry names, not ids (0007:544). The port of a
-- trade marker is read from the ledger's 0277 point columns (ledger.port_id, filled by 0277's BEFORE
-- INSERT trigger at insert time, the fleet's docked port). Rows written before 0277 carry no port and
-- stand on no city chart — they still READ (the read never raises on them). The good is matched by the
-- payload's served NAME against public.goods (unique in the seed; a duplicate resolves to the lowest
-- code, deterministically). Company = the event's player_id (players.id is the design's company_id).
--
-- THE READ (docs/NEWS_AND_MARKERS.md §5): world.news_marks(p_chart, p_port, p_good, p_from, p_to) ->
-- at most 300 rows, newest kept: id, at, kind, importance, scope, port_id, good_id, company_id, detail
-- (the template's words as SERVED values: company, good code+name, qty, total, avg_price, city code+name
-- for trades; company, amount, week for the refound; the payload itself for the switch). stable, security
-- definer, one entry-points row (+1). The client fills the dict templates with these and properName
-- (src/lib/i18n/names) and never recomputes a figure.
--
-- SUPERSEDE (supabase/migrations/README.md:43-48). This file re-cuts ONE live function by a hunk sliced
-- from its body (asserted to occur exactly once and to reverse to its pre-image; ACL / volatility /
-- definer / config unchanged): public.client_rpc_entry_points — one hunk, the new read's row inserted
-- at the head of the reads (the 0104 trick: a row appended at the tail by another file cannot move it).
-- NOTE FOR THE CHAIN RUNNER: 0273-0278 land before this file. If any of them hunks
-- client_rpc_entry_points, re-slice this hunk's pre-image against the then-live body before the run —
-- the occurs==1 assert fails loud if it moved.
--
-- WHAT IS NOT PROVEN (said plainly; the dev-log says it again). A trade of 250,000+ made through the
-- real cmd verbs is not probed (a probe house's barca cannot hold one); the big-trade marker rows are
-- planted through the one authorities for events and money — public.emit_event + public.credit with the
-- writer's own payload shape, the chain's probe idiom (0216, 0224). The small REAL trade through
-- cmd.do_buy proves the writers, the threshold and 0277's port fill. Markers do not update every second
-- while a chart is open: they are re-read with the chart's window (the design's §3.2 rule); the live
-- News feed with news_head is N2's slice, not this one. A marker from before 0277 (no port) stands on no
-- city chart. Names of player companies in markers are public — the design's (D).
--
-- PROD CHECKS (before the push; read-only; in the PR body): the ledger carries the three point columns
-- (0277 applied); counts of the four mapped kinds on prod, incl. rows older than 72 h; the live
-- entry-points body carries this hunk's two pre-image lines exactly once (a SELECT with position()); the
-- entry-points count. AFTER THE DEPLOY: entry-points count = before + 1 with the new row granted to
-- authenticated only; one timed world.news_marks('world', null, null, -7 d, now) — the economy-switch
-- rows as imp-3 markers; one price-chart window on a busy port; the client after-check in the dev-log.
--
-- VERSION: 0279 (prod head 0272 at authoring; 0273-0278 apply before this one, in number order).

-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.emit_event(uuid,text,jsonb)') is null
     or to_regprocedure('public.new_house(uuid,text,text,text,text,text,text,bigint,boolean)') is null
     or to_regclass('public.events') is null then
    raise exception '0279 refuses: 0004, 0096 or the events table is not in this world';
  end if;
  if (select count(*) from pg_attribute
       where attrelid = 'public.ledger'::regclass
         and attname in ('port_id', 'fleet_id', 'voyage_id') and not attisdropped) <> 3 then
    raise exception '0279 refuses: the ledger point columns are not in this world (0277)';
  end if;
  if to_regprocedure('world.news_marks(text,uuid,uuid,timestamptz,timestamptz)') is not null
     or to_regclass('public.news_kinds') is not null then
    raise exception '0279 refuses: world.news_marks or public.news_kinds already exists — this has been applied once';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0279(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. AS FOUND ────────────────────────────────────────────────────────────────────────────────
-- the one live body this file re-cuts, and the functions it must leave byte for byte: the event and
-- money authorities, the append-only law, the stats read family this file composes beside, and the game
-- clock it does not touch.
create temp table defs_before_0279 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.client_rpc_entry_points()')) f(fn);

create temp table kept_0279 on commit drop as
select f.fn from (values ('public.emit_event(uuid,text,jsonb)'), ('public.credit(uuid,text,bigint,uuid)'),
                         ('public.forbid_mutation()'), ('public.ledger_sum(uuid)'),
                         ('public.new_house(uuid,text,text,text,text,text,text,bigint,boolean)'),
                         ('public.fleet_load(uuid,text,numeric)'), ('world.game_day(timestamptz)'),
                         ('world.stats_now()'), ('world.stats_overview(integer,text)'),
                         ('world.stats_city(uuid,text)'), ('world.stats_merchants(text)')) f(fn);

create temp table before_0279 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select md5(string_agg(md5(replace(pg_get_functiondef(k.fn::regprocedure), E'\r', '')), ',' order by k.fn))
          from kept_0279 k) as kept_md5;

-- ── 1. THE ONE REGISTRY of which events are chart news (server-only, like stats_flow_words) ─────
create table public.news_kinds (
  kind       text primary key,
  importance smallint not null check (importance between 1 and 3),   -- 3 headline, 2 notable, 1 local
  scope      text not null check (scope in ('world', 'power', 'port', 'good', 'company')),  -- the widest place it shows
  min_total  bigint null check (min_total is null or min_total > 0)  -- the design's §2.2 anti-spam, fixed (N4 -> knob)
);
comment on table public.news_kinds is
  '0279 (owner row 216): THE one registry of which append-only public.events rows are chart news. The '
  'design''s world_news table is not built — public.events IS the news log the writers already feed, so a '
  'marker is an event row read through this mapping; never a second event log, never a duplicated marker '
  'registry. No words here: the templates live in the client''s i18n dict (one authority per concept).';

insert into public.news_kinds (kind, importance, scope, min_total) values
  ('ECONOMY_SWITCH', 3, 'world',   null),   -- 0240/0268: the design's UPDATE kind ("Update: Economy …")
  ('SOLD',           2, 'port',    250000), -- cmd.do_sell: BIG_SALE (the design's §2.2 threshold)
  ('BOUGHT',         2, 'port',    250000), -- cmd.do_buy:  BIG_BUY
  ('NPC_REFOUNDED',  2, 'company', null);   -- 0097's upkeep crossing: the design's MERCHANT_BROKE pass

alter table public.news_kinds enable row level security;
revoke all on table public.news_kinds from public, anon, authenticated;

-- the read's range scans ride this partial index: only the four mapped kinds ever enter it
create index if not exists events_news_at
  on public.events (created_at desc)
  where kind in ('ECONOMY_SWITCH', 'SOLD', 'BOUGHT', 'NPC_REFOUNDED');

-- ── 2. THE READ (docs/NEWS_AND_MARKERS.md §5) ──────────────────────────────────────────────────
create function world.news_marks(
  p_chart text,
  p_port uuid default null,
  p_good uuid default null,
  p_from timestamptz default null,
  p_to   timestamptz default null
)
returns table (
  id uuid, at timestamptz, kind text, importance int, scope text,
  port_id uuid, good_id uuid, company_id uuid, detail jsonb
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if p_chart not in ('price', 'city', 'world', 'merchants') then
    raise exception 'E_BAD_CHART: no chart %', p_chart using errcode = '22023';
  end if;
  return query
  select m.id, m.at, m.kind, m.importance, m.scope, m.port_id, m.good_id, m.company_id, m.detail
    from (
      select e.id,
             e.created_at as at,
             e.kind,
             nk.importance::int,
             nk.scope,
             l.port_id,
             g.id as good_id,
             e.player_id as company_id,
             case e.kind
               -- the template's words as SERVED values; the client fills its dict templates and properName
               when 'SOLD' then jsonb_build_object(
                 'company', p.company_name, 'good', g.code, 'good_name', g.name,
                 'qty', (e.payload->>'qty')::numeric, 'total', (e.payload->>'total')::numeric,
                 'avg_price', (e.payload->>'avg_price')::numeric, 'city', pt.code, 'city_name', pt.name)
               when 'BOUGHT' then jsonb_build_object(
                 'company', p.company_name, 'good', g.code, 'good_name', g.name,
                 'qty', (e.payload->>'qty')::numeric, 'total', (e.payload->>'total')::numeric,
                 'avg_price', (e.payload->>'avg_price')::numeric, 'city', pt.code, 'city_name', pt.name)
               when 'NPC_REFOUNDED' then jsonb_build_object(
                 'company', p.company_name, 'amount', (e.payload->>'amount')::numeric,
                 'week', (e.payload->>'week')::int)
               else e.payload   -- ECONOMY_SWITCH, and any future kind: the payload is already its detail
             end as detail
        from public.events e
        join public.news_kinds nk on nk.kind = e.kind
        -- 0277's point columns: the trade's port (null for rows written before 0277 — they still read)
        left join lateral (
               select l2.port_id
                 from public.ledger l2
                where l2.ref_event_id = e.id and l2.kind in ('SELL', 'BUY')
                order by l2.created_at desc, l2.id desc
                limit 1) l on true
        -- the payload names the good; goods.name is unique in the seed, and a duplicate resolves to the
        -- lowest code — deterministic, never a fan-out
        left join lateral (
               select g2.id, g2.code, g2.name
                 from public.goods g2
                where g2.name = e.payload->>'good'
                order by g2.code
                limit 1) g on true
        left join public.ports pt on pt.id = l.port_id
        left join public.players p on p.id = e.player_id
       where (p_from is null or e.created_at >= p_from)
         and (p_to is null or e.created_at <= p_to)
         and (nk.min_total is null or coalesce((e.payload->>'total')::numeric, 0) >= nk.min_total)
         and case p_chart
               -- docs/NEWS_AND_MARKERS.md §3.1, the chart table, verbatim
               when 'price' then (nk.scope = 'world' and nk.importance = 3)
                              or (p_port is not null and l.port_id = p_port
                                  and (p_good is null or g.id = p_good or g.id is null))
               when 'city' then (nk.scope = 'world' and nk.importance = 3)
                            or (p_port is not null and l.port_id = p_port and nk.importance >= 2)
               when 'world' then nk.scope = 'world' and nk.importance = 3
               when 'merchants' then (nk.scope = 'world' and nk.importance >= 2) or e.kind = 'NPC_REFOUNDED'
             end
       order by e.created_at desc, e.id desc
       limit 300
    ) m
  order by m.at asc;
end $$;

comment on function world.news_marks(text, uuid, uuid, timestamptz, timestamptz) is
  '0279 (owner row 216): the chart''s news markers — every mapped event in the window, newest 300 kept, as '
  'one row per event (id, at, kind, importance, scope, refs, and the template''s words as served values in '
  'detail). The window is inclusive; p_chart filters per docs/NEWS_AND_MARKERS.md §3.1. Public news, so any '
  'signed-in player reads it; the words are the client''s i18n dict''s. stable, asked when a chart''s window '
  'changes, never per second (the live feed is N2''s slice).';

revoke all on function world.news_marks(text, uuid, uuid, timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function world.news_marks(text, uuid, uuid, timestamptz, timestamptz) to authenticated;

-- ── 3. THE HUNK: one entry-points row, at the head of the reads ─────────────────────────────────
create temp table hunks_0279 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0279 values
('public.client_rpc_entry_points()', 1,
$h$      -- the reads (world)
      ('world'::text, 'snapshot'::text,      ''::text),$h$,
$h$      -- the reads (world)
      -- 0279 (owner row 216): a chart's news markers — every mapped event in the window, public, newest 300.
      ('world',       'news_marks',           'text, uuid, uuid, timestamptz, timestamptz'),
      ('world'::text, 'snapshot'::text,      ''::text),$h$);

do $$
declare
  d record;
  h record;
  v_def text;
  v_n int;
begin
  for d in select * from defs_before_0279 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0279 where fn = d.fn order by n loop
      v_n := pg_temp.occurs_0279(v_def, h.old);
      if v_n <> 1 then
        raise exception '0279 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against (re-slice against the body live after 0278)', h.n, d.fn, v_n;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $$;

-- ── 4. SELF-ASSERT: the probe, rolled back; every count is of the probe's own rows only ─────────
do $$
declare
  v_uid      constant uuid := '00000000-0279-4000-8000-000000000001';
  v_ev_old   constant uuid := '00000000-0279-4000-8000-0000000000aa';
  v_player   uuid;
  v_fleet    uuid;
  v_good     uuid;
  v_code     text;
  v_gname    text;
  v_port     uuid;
  v_other    uuid;
  v_small    uuid;   -- the real small trade's event (under the threshold)
  v_ev_sold  uuid;   -- the probe's big-trade and news events
  v_ev_bought uuid;
  v_ev_sw    uuid;
  v_ev_npc   uuid;
  v_ev_voy   uuid;
  v_from     timestamptz := now() - interval '7 days';
  v_to       timestamptz := now() + interval '1 day';
  v_old_at   timestamptz := now() - interval '3 days';
  -- findings, recorded inside the throwaway subtransaction and asserted after it is rolled back
  f_small_port boolean := false;      -- 0277's trigger filled the small trade's ledger port
  f_price      boolean := false;      -- the price chart serves exactly the two big trades, with words
  f_city       boolean := false;      -- city chart = the switch + the two trades
  f_world      boolean := false;      -- world chart = the switch rows only, old rows inclusive
  f_merchants  boolean := false;      -- merchants chart = switch + the refound
  f_other_port boolean := false;      -- another port's price chart serves none of the probe rows
  f_threshold  boolean := false;      -- the small real trade is not a marker
  f_voy_not    boolean := false;      -- an unmapped kind is never a marker
  f_map        boolean := false;      -- every served mark maps to one mapped event row (anti-proof)
  f_bad_chart  boolean := false;      -- a bad chart raises
  f_upd        boolean := false;      -- UPDATE on events refused
  f_del        boolean := false;      -- DELETE on events refused
  f_kept       boolean := false;      -- the kept functions are byte for byte
  f_entry      boolean := false;      -- entry points: +1, the new row resolves, grants right
  f_acl        boolean := false;      -- the read: stable, definer, authenticated only
  f_idx        boolean := false;      -- the partial index covers exactly the registry's kinds
  v_marks      uuid[];
  v_prow       record;
  v_times      numeric[] := '{}';
  v_t0         timestamptz;
  v_left       int;
begin
  begin
    -- ── inside the throwaway subtransaction ────────────────────────────────────────────────────
    v_player := public.new_house(v_uid, 'Casa 0279 Probe', 'PRT', 'LIS');
    select f.id into v_fleet from public.fleets f where f.player_id = v_player order by f.id limit 1;
    select pg.port_id, pg.good_id, g.code, g.name into v_port, v_good, v_code, v_gname
      from public.port_goods pg
      join public.ports p on p.id = pg.port_id
      join public.goods g on g.id = pg.good_id
     where p.code = 'LIS' and pg.stock > 50 and not public.culture_refuses(p.culture, g.culture_mask)
       and exists (select 1 from public.port_offered_goods(pg.port_id) o where o.good_id = pg.good_id)
     order by g.code limit 1;
    if v_good is null then
      raise exception '0279 self-assert FAIL: Lisbon offers no good with stock over 50 for the probe to trade';
    end if;
    select p.id into v_other from public.ports p where p.code = 'OPO';

    -- (a) A REAL small trade through the real verb: writers still write, and 0277's trigger fills the port.
    perform public.fleet_load(v_fleet, v_code, 60, 1);
    perform cmd.do_buy(v_fleet, jsonb_build_object('good', v_good, 'qty', 2));
    select e.id into v_small from public.events e
     where e.player_id = v_player and e.kind = 'BOUGHT' order by e.created_at desc limit 1;
    select (count(*) = 1) into f_small_port
      from public.ledger l
     where l.ref_event_id = v_small and l.kind = 'BUY' and l.port_id = v_port;

    -- (b) The big-trade markers, through the ONE authorities for events and money (the writer's own
    --     payload shape, the chain's probe idiom — a probe barca cannot hold a 250,000 trade).
    v_ev_sold := public.emit_event(v_player, 'SOLD', jsonb_build_object(
      'fleet', 'Gaivota', 'good', v_gname, 'qty', 500, 'avg_price', 600, 'total', 300000));
    perform public.credit(v_player, 'SELL', 300000, v_ev_sold);
    v_ev_bought := public.emit_event(v_player, 'BOUGHT', jsonb_build_object(
      'fleet', 'Gaivota', 'good', v_gname, 'qty', 400, 'avg_price', 750, 'total', 300000));
    perform public.credit(v_player, 'BUY', -300000, v_ev_bought);

    -- (c) The world and company markers, through the one authority for events.
    v_ev_sw := public.emit_event(null, 'ECONOMY_SWITCH', jsonb_build_object(
      'closed', true, 'at', now(), 'world_total', 999999, 'invested_seeded', 0, 'invested', 0));
    v_ev_npc := public.emit_event(v_player, 'NPC_REFOUNDED', jsonb_build_object(
      'company', 'Casa 0279 Probe', 'amount', 12000, 'week', 1));

    -- (d) ANTI-PROOF: an unmapped kind is never a marker.
    v_ev_voy := public.emit_event(v_player, 'VOYAGE_REPORT', jsonb_build_object('to', 'OPO', 'total_nm', 100, 'probe', '0279'));

    -- (e) AN OLD ROW: a mapped event backdated (insert is the append-only law's permitted half; the
    --     fixed id is the probe's own — the real authority emit_event cannot backdate, and an old row
    --     must read with inclusive bounds).
    insert into public.events (id, player_id, kind, payload, created_at)
    values (v_ev_old, null, 'ECONOMY_SWITCH', jsonb_build_object('closed', false, 'probe', '0279-old'), v_old_at);

    -- (f) THE READS. Six timed, all counted by the probe's own ids only — the world may already hold
    --     real rows of every mapped kind (this file applies on prod).
    v_t0 := clock_timestamp();
    select array_agg(m.id order by m.id) into v_marks
      from world.news_marks('price', v_port, v_good, v_from, v_to) m
     where m.id in (v_ev_sold, v_ev_bought, v_ev_sw, v_ev_npc, v_ev_old, v_small, v_ev_voy);
    v_times := v_times || round(extract(epoch from clock_timestamp() - v_t0) * 1000, 2);
    -- the design's §3.1: the price chart shows the port's own trades AND the world's imp-3 rows
    f_price := v_marks = (select array_agg(u order by u) from unnest(array[v_ev_sold, v_ev_bought, v_ev_sw, v_ev_old]) u);
    select * into v_prow from world.news_marks('price', v_port, v_good, v_from, v_to) m
     where m.id = v_ev_sold;
    if v_prow is null or v_prow.importance <> 2 or v_prow.scope <> 'port'
       or v_prow.port_id <> v_port or v_prow.good_id <> v_good or v_prow.company_id <> v_player
       or v_prow.detail->>'company' <> 'Casa 0279 Probe' or v_prow.detail->>'good' <> v_code
       or v_prow.detail->>'city' <> 'LIS' or (v_prow.detail->>'total')::numeric <> 300000
       or (v_prow.detail->>'qty')::numeric <> 500 or v_prow.detail->>'city_name' <> 'Lisbon' then
      f_price := false;
    end if;

    v_t0 := clock_timestamp();
    select array_agg(m.id order by m.id) into v_marks
      from world.news_marks('city', v_port, null, v_from, v_to) m
     where m.id in (v_ev_sold, v_ev_bought, v_ev_sw, v_ev_npc, v_ev_old, v_small, v_ev_voy);
    v_times := v_times || round(extract(epoch from clock_timestamp() - v_t0) * 1000, 2);
    f_city := v_marks = (select array_agg(u order by u) from unnest(array[v_ev_sold, v_ev_bought, v_ev_sw, v_ev_old]) u);

    v_t0 := clock_timestamp();
    select array_agg(m.id order by m.id) into v_marks
      from world.news_marks('world', null, null, v_from, v_to) m
     where m.id in (v_ev_sold, v_ev_bought, v_ev_sw, v_ev_npc, v_ev_old, v_small, v_ev_voy);
    v_times := v_times || round(extract(epoch from clock_timestamp() - v_t0) * 1000, 2);
    f_world := v_marks = (select array_agg(u order by u) from unnest(array[v_ev_sw, v_ev_old]) u);

    v_t0 := clock_timestamp();
    select array_agg(m.id order by m.id) into v_marks
      from world.news_marks('merchants', null, null, v_from, v_to) m
     where m.id in (v_ev_sold, v_ev_bought, v_ev_sw, v_ev_npc, v_ev_old, v_small, v_ev_voy);
    v_times := v_times || round(extract(epoch from clock_timestamp() - v_t0) * 1000, 2);
    f_merchants := v_marks = (select array_agg(u order by u) from unnest(array[v_ev_sw, v_ev_old, v_ev_npc]) u);

    v_t0 := clock_timestamp();
    -- another port's price chart: the probe's trades are absent, the world's imp-3 rows stand on it too
    select count(*) = 0 into f_other_port
      from world.news_marks('price', v_other, null, v_from, v_to) m
     where m.id in (v_ev_sold, v_ev_bought, v_ev_npc, v_small, v_ev_voy);
    f_other_port := f_other_port and exists (
      select 1 from world.news_marks('price', v_other, null, v_from, v_to) m
       where m.id in (v_ev_sw, v_ev_old));
    v_times := v_times || round(extract(epoch from clock_timestamp() - v_t0) * 1000, 2);

    v_t0 := clock_timestamp();
    select count(*) = 0 into f_threshold
      from world.news_marks('price', v_port, v_good, v_from, v_to) m
     where m.id = v_small;
    v_times := v_times || round(extract(epoch from clock_timestamp() - v_t0) * 1000, 2);

    -- a marker with no matching mapped event is impossible: every served probe mark IS one probe event
    -- of a mapped kind, the unmapped probe event serves nothing, and the mapped set is complete
    f_voy_not := not exists (select 1 from world.news_marks('price', v_port, v_good, v_from, v_to) m where m.id = v_ev_voy)
              and not exists (select 1 from world.news_marks('world', null, null, v_from, v_to) m where m.id = v_ev_voy)
              and not exists (select 1 from world.news_marks('merchants', null, null, v_from, v_to) m where m.id = v_ev_voy);
    select count(*) = 0 into f_map
      from world.news_marks('price', v_port, v_good, v_from, v_to) m
      left join public.events e on e.id = m.id
      left join public.news_kinds nk on nk.kind = e.kind
     where m.id not in (v_ev_sold, v_ev_bought, v_ev_sw, v_ev_old) or e.id is null or nk.kind is null;

    -- the old row reads with INCLUSIVE bounds at its own instant
    if not exists (select 1 from world.news_marks('world', null, null, v_old_at, v_old_at) m where m.id = v_ev_old) then
      f_world := false;
    end if;

    -- POSITIVE CONTROL: a bad chart raises.
    begin
      perform world.news_marks('nonsense', null, null, null, null);
    exception when others then
      if sqlerrm like 'E_BAD_CHART%' then f_bad_chart := true; end if;
    end;

    -- POSITIVE CONTROLS: the append-only law still bites the events table.
    begin
      update public.events set payload = '{}'::jsonb where id = v_ev_sw;
    exception when others then f_upd := true;
    end;
    begin
      delete from public.events where id = v_ev_sw;
    exception when others then f_del := true;
    end;

    raise exception '__PROBE_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK__' then raise; end if;
  end;
  -- ── the subtransaction is gone; the findings survive because plpgsql variables are not
  --    transactional. Assert on them. ────────────────────────────────────────────────────────────

  if not f_price then
    raise exception '0279 self-assert FAIL: the price chart did not serve exactly the two big trades with the served words (% / % / %)',
      f_price, v_prow, (select coalesce(string_agg(m.id::text || ':' || m.kind, ','), '') from world.news_marks('price', v_port, v_good, v_from, v_to) m);
  end if;
  if not f_city then
    raise exception '0279 self-assert FAIL: the city chart did not serve the switch and the two trades';
  end if;
  if not f_world then
    raise exception '0279 self-assert FAIL: the world chart did not serve exactly the two switch rows, the old row inclusive';
  end if;
  if not f_merchants then
    raise exception '0279 self-assert FAIL: the merchants chart did not serve the switch and the refound';
  end if;
  if not f_other_port then
    raise exception '0279 self-assert FAIL: another port''s price chart served a probe row';
  end if;
  if not f_threshold then
    raise exception '0279 self-assert FAIL: a small real trade became a marker — the 250,000 threshold does not bite';
  end if;
  if not f_voy_not or not f_map then
    raise exception '0279 self-assert FAIL: an unmapped event served, or a served mark has no matching mapped event';
  end if;
  if not f_bad_chart then
    raise exception '0279 self-assert FAIL: a bad chart was accepted';
  end if;
  if not f_upd or not f_del then
    raise exception '0279 self-assert FAIL: UPDATE or DELETE on the append-only events table was accepted';
  end if;
  if not f_small_port then
    raise exception '0279 self-assert FAIL: the real trade''s ledger row carries no port (0277''s fill)';
  end if;

  -- the rollback really rolled back: no probe rows survive in the world
  select count(*) into v_left from public.players where id = v_player;
  if v_left <> 0 then
    raise exception '0279 self-assert FAIL: the probe player survived its subtransaction';
  end if;
  select count(*) into v_left from public.events where id in (v_small, v_ev_sold, v_ev_bought, v_ev_sw, v_ev_npc, v_ev_voy, v_ev_old);
  if v_left <> 0 then
    raise exception '0279 self-assert FAIL: % probe event row(s) survived the subtransaction', v_left;
  end if;

  -- the kept functions are byte for byte (the stats series, the event and money authorities, the clock)
  select (b.kept_md5 =
          (select md5(string_agg(md5(replace(pg_get_functiondef(k.fn::regprocedure), E'\r', '')), ',' order by k.fn))
             from kept_0279 k)) into f_kept from before_0279 b;
  if not f_kept then
    raise exception '0279 self-assert FAIL: a kept function moved — the series or an authority changed';
  end if;

  -- the registry: exactly one new entry point, resolving, granted to authenticated only
  select (select count(*) from public.client_rpc_entry_points()) = b.entry_points + 1
     and (select count(*) from public.client_rpc_entry_points() e
           where e.schema_name = 'world' and e.function_name = 'news_marks'
             and e.arg_types = 'text, uuid, uuid, timestamptz, timestamptz' and e.fn is not null) = 1
     and (select count(*) from public.client_rpc_entry_points() e where e.fn is null) = 0
    into f_entry from before_0279 b;
  if not f_entry then
    raise exception '0279 self-assert FAIL: the entry points did not gain exactly the news_marks row';
  end if;

  -- the read's own posture
  select (p.provolatile = 's' and p.prosecdef
          and has_function_privilege('authenticated', 'world.news_marks(text, uuid, uuid, timestamptz, timestamptz)', 'execute')
          and not has_function_privilege('anon', 'world.news_marks(text, uuid, uuid, timestamptz, timestamptz)', 'execute')
          and not has_function_privilege('public', 'world.news_marks(text, uuid, uuid, timestamptz, timestamptz)', 'execute'))
    into f_acl from pg_proc p where p.oid = 'world.news_marks(text, uuid, uuid, timestamptz, timestamptz)'::regprocedure;
  if not f_acl then
    raise exception '0279 self-assert FAIL: the read is not stable, definer, authenticated-only';
  end if;

  -- the partial index covers exactly the registry's kinds (no drift between the two)
  select count(*) = 0 into f_idx from public.news_kinds nk
   where pg_get_indexdef('public.events_news_at'::regclass) not like '%''' || nk.kind || '''%';
  if not f_idx then
    raise exception '0279 self-assert FAIL: the events_news_at index does not cover every registry kind';
  end if;

  -- the walls
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0279 self-assert FAIL: a wall moved';
  end if;

  raise notice '0279 self-assert ok: news_marks serves the probe''s five mapped happenings (2 big trades, 1 switch now, 1 switch 3 days old, 1 refound) on exactly the design''s charts; a small real trade, an unmapped event and another port''s chart serve nothing; the old row reads at its own instant (bounds inclusive); UPDATE and DELETE on events refused; the real trade''s ledger port filled (0277); the stats family and the money/event authorities are byte for byte; entry points +1; the read stable, definer, authenticated-only; 6 timed reads: % ms; probe rolled back leaving 0 rows',
    array_to_string(v_times, ' / ');
end $$;
