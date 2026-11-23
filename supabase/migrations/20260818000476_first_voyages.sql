-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0476 - FIRST VOYAGES  (dark: the owner's switch first_voyages_enabled, false; lit, a new company is offered a short chain of five starter
--        jobs, each paid once from her capital in coin and Reputation, and the next job named with where to sail)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE DESIGN: docs/design/roadmap-2026-11-23.md slice 8 ("First voyages: a short starter chain"; on slice 3, "a job is one press");
--   docs/design/playable-2026-11-22.md section 6, findings 4 and 12; docs/dev-log/2026-11-23-first-voyages.md.
--
-- WHY: the first hour has jobs (0466 hold jobs, 0473 their source harbour), a profit, a level, a captain to hire and a second hull to order,
--   but nothing that says "do this next, and this is what it pays". Uncharted Waters' guild jobs and RuneScape's tutorial quest do. These
--   are jobs, not a story: one short line each (owner row 311, decided by default that the stuff now exists).
--
-- WHAT (DECIDED BY DEFAULT; the owner may reverse any of it; every figure is a knob):
--   THE CHAIN, one knob (first_voyages_steps), in this order (each step's condition is read from what she has done since she was founded,
--   so a step already met pays the moment it becomes the step):
--     1 deliver  deliver a request (a PREMIUM row in her ledger: a hold job's or a city's bonus). The read names THE JOB TO TAKE: of the
--                open hold jobs (0466) with a source (0473), the one whose trip from HER CAPITAL to its source and on to its harbour is the
--                shortest a Barca sails, with first_voyages_job_margin (2) times that trip still inside the time the job stands.
--     2 profit   10,000 of trade profit (her ledger's rows public.ledger_is_trade counts, 0474's one definition; never under 0).
--     3 trading  Trading 3 (her paid Trading mark, public.house_level_marks: the level she has been told she reached).
--     4 captain  hire a captain at the Inn (a public.player_officers row). The brief's "hire job": decided by default to be the Inn's hire.
--     5 hull     the second hull: two ships, counting a hull on order (0465's public.hull_orders not launched).
--   THE PAY, once a step, per company, ever (public.first_voyages: one row a step, its primary key the guard): coin 2,000 / 3,000 / 3,000 /
--     3,000 / 5,000 (16,000 in all, each under first_voyages_ducats_max 5,000) from HER CAPITAL by the capital's own payer (public.capital_pays,
--     the gift's: what it holds above its reserve, the gap called from her realm; a realm that cannot pay: the step waits and is asked again,
--     nothing written) while the city purses are lit; dark purses, public.city_pays (a credit). Kind VOYAGE_REWARD, a MOVED word (no new gold;
--     not trade: 0474's Week and the gift's worth do not count it as profit). Reputation 20 / 30 / 30 / 30 / 50 (each under
--     first_voyages_reputation_max 50), kind first_voyage (not under the day's cap), keyed 'first_voyage:<step>' so the book books it once.
--   WHO: a company (not a merchant) founded under first_voyages_days (7) real days ago. Older, the chain is not offered (open false): an old
--     company is not paid five rewards at once for what it did before.
--   THE READ, world.first_voyages() (the client's one door, registered): dark {"on": false}. Lit, it pays every step now met, in order, then
--     answers {on, open, step, of, code, have, need, ducats, reputation, waiting, job, just}: `just` the steps it paid in this read. It is a
--     read that writes, as world.contracts winds its board: a step is paid when she next looks, not by a job over every company.
-- ONE AUTHORITY EACH: what a step's figure is, public.first_voyage_have (stable, server only: the read and the proof ask it); which job,
--   public.first_voyage_job (stable, server only); the one writer of public.first_voyages and of the pay, world.first_voyages.
-- NOT CHANGED: any existing body but the registry (one line), the hold jobs, the delivery, the sale, the levels, the Inn, the yard, the
--   gift, the Week. No knob of another feature moves.
-- ROWS: dark none. Lit: at most five public.first_voyages rows a company, ever, and with each one ledger row, one Reputation book row and
--   (purses lit) one or two treasury_flows rows; about 25 rows over a new company's first hours. Nothing a minute.
--   -- budget: one new table of five rows a company (no job, no cron, no index past its key, no fillfactor or autovacuum setting).
--   COST of the read: five small reads of one company's rows (her ledger by ledger_player_created, her mark, her captains, her ships, her
--   orders); on step 1 also the open hold jobs (about 500) against two sea_reaches rows. Measured in proof 179.
-- LOCKS: CREATE TABLE (new, no foreign key: one would lock public.players); CREATE FUNCTION x3; CREATE OR REPLACE x1 by a hunk
--   (public.client_rpc_entry_points); two catalog rows (a word, a Reputation kind) and six knobs. TIME: a second. BUDGET: statement_timeout
--   45 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): QUICK, first_voyages_enabled false (the read answers {"on": false}, nothing is paid; paid rows stay, inert).
--   Full: a new migration reversing the one hunk (OLD text below verbatim), dropping the three functions and the table, deleting the knobs;
--   VOYAGE_REWARD and first_voyage stay as words (the ledger and the book keep their rows).
-- SELF-ASSERT: the hunk once and reversing; no other function moved; the registry's grants unmoved; the knobs, the word, the kind; the table
--   and the server-only functions unreachable by a client, world.first_voyages registered for authenticated alone. THE PROBE (rolled back):
--   dark the read is {"on": false} and pays nothing; lit (purses dark) a fresh company's chain: each step waits until its condition is met
--   by her own rows, then pays its coin and Reputation once (a second read pays nothing), in order, to the end; an old company is offered
--   nothing. Proof 179 plays it with the purses lit and the capital paying, the job named against posted hold jobs, and the read's cost.
-- VERSION: 0476 = 0475 + 1 (0475, #803, hunks world.best_sales and public.first_hour_near_seconds: neither here; this file reads
--   ledger_is_trade from 0474 and hull_orders from 0465 and changes neither).
-- news: none (dark: nothing changes for a player until the owner lights first_voyages_enabled)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['public.client_rpc_entry_points()'];
  c_new    constant text[] := array['public.first_voyage_have(uuid,text)', 'public.first_voyage_job(uuid)', 'world.first_voyages()'];
  c_uid    constant uuid := '00000000-0476-4000-8000-000000000001';
  c_old    constant uuid := '00000000-0476-4000-8000-000000000002';
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_note      text := '';
  v_lived     boolean := false;
  v_me        uuid;
  v_old       uuid;
  v_lis       uuid;
  v_r         jsonb;
  v_p0        bigint;
  v_paid      bigint := 0;
  v_rep       bigint := 0;
  v_want      jsonb;
  v_off       uuid;
  v_sell      bigint;
  v_steps     jsonb;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = 'first_voyages_enabled') or to_regclass('public.first_voyages') is not null then
    raise exception '0476 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.ledger_is_trade(text)') is null or to_regclass('public.hull_orders') is null
     or to_regclass('public.house_level_marks') is null or to_regclass('public.player_officers') is null
     or not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'trade_contracts' and column_name = 'source_port_id')
     or to_regprocedure('public.capital_pays(uuid,uuid,uuid,text,bigint,uuid,boolean,jsonb)') is null
     or to_regprocedure('public.reputation_credit(uuid,text,integer,text,jsonb)') is null
     or to_regprocedure('cmd.assume_identity(uuid)') is null then
    raise exception '0476 refuses: 0474 (ledger_is_trade), 0473 (a job''s source), 0465 (the yard order), 0356 (the marks), 0352 (Reputation) or 0234 (the capital pays) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));

  -- ── 2. THE KNOBS, THE WORD, THE KIND, THE TABLE ──
  insert into public.world_config (key, value, description) values
    ('first_voyages_enabled', 'false'::jsonb,
     '0476: THE SWITCH (the owner''s). true: a company founded under first_voyages_days ago is offered the starter chain (first_voyages_steps), each step paid once when she next reads it (world.first_voyages). false: the read answers {"on": false} and nothing is paid; rows already paid stay.'),
    ('first_voyages_steps', '[{"code": "deliver", "need": 1, "ducats": 2000, "reputation": 20},
                              {"code": "profit", "need": 10000, "ducats": 3000, "reputation": 30},
                              {"code": "trading", "need": 3, "ducats": 3000, "reputation": 30},
                              {"code": "captain", "need": 1, "ducats": 3000, "reputation": 30},
                              {"code": "hull", "need": 2, "ducats": 5000, "reputation": 50}]'::jsonb,
     '0476: THE CHAIN, in order: each step a code public.first_voyage_have reads (deliver: requests delivered; profit: trade profit; trading: her Trading mark; captain: captains hired; hull: ships with hulls on order), the figure it must reach, and its pay (coin from her capital, Reputation). Each pay is cut to first_voyages_ducats_max / first_voyages_reputation_max.'),
    ('first_voyages_days', to_jsonb(7), '0476: the chain is offered to a company founded under this many real days ago (players.created_at); older, never.'),
    ('first_voyages_ducats_max', to_jsonb(5000), '0476: no step pays more coin than this, whatever first_voyages_steps says.'),
    ('first_voyages_reputation_max', to_jsonb(50), '0476: no step pays more Reputation than this, whatever first_voyages_steps says.'),
    ('first_voyages_job_margin', to_jsonb(2), '0476: the deliver step names a hold job only while this many times a Barca''s trip (her capital, the job''s source, the job''s harbour) fits in the time the job still stands.');
  insert into public.stats_flow_words (kind, side, word, ord)
    values ('VOYAGE_REWARD', 'moved', 'Voyage reward', (select coalesce(max(w.ord), 0) + 1 from public.stats_flow_words w));
  insert into public.reputation_kinds (code, sign, capped, word) values ('first_voyage', 1, false, 'First voyage');

  -- retention: none, bounded by five rows a company, ever (one a step of first_voyages_steps, the primary key); no row is updated or deleted
  create table public.first_voyages (
    player_id  uuid        not null,
    step       smallint    not null check (step between 1 and 20),
    code       text        not null,
    ducats     bigint      not null check (ducats >= 0),
    reputation int         not null check (reputation >= 0),
    done_at    timestamptz not null default now(),
    primary key (player_id, step)
  );
  comment on table public.first_voyages is
    '0476: THE STARTER CHAIN PAID. One row a step a company has been paid for (first_voyages_steps), written once by world.first_voyages, its '
    'primary key the guard that a step pays once. No foreign key on purpose: one would lock public.players at creation, and a company is never deleted.';
  alter table public.first_voyages enable row level security;
  revoke all on table public.first_voyages from public, anon, authenticated;

  -- ── 3. THE RULES ──
  execute $f$
create function public.first_voyage_have(p_player uuid, p_code text)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0476: THE ONE READING of a starter step's figure for a company, from what she has done since she was founded. deliver: requests
  -- delivered (a PREMIUM row in her ledger, one is enough); profit: her trade profit (public.ledger_is_trade, 0474), never under 0; trading:
  -- her paid Trading mark (public.house_level_marks; no row is 1); captain: captains hired (public.player_officers); hull: her ships and
  -- hulls on order (public.hull_orders not launched). An unknown code: null (a step that can never be met).
  select case p_code
    when 'deliver' then (select count(*) from (select 1 from public.ledger l where l.player_id = p_player and l.kind = 'PREMIUM' and l.ducats_delta > 0 limit 1) d)
    when 'profit'  then greatest(0, coalesce((select sum(l.ducats_delta) from public.ledger l where l.player_id = p_player and public.ledger_is_trade(l.kind)), 0))
    when 'trading' then coalesce((select m.level from public.house_level_marks m where m.player_id = p_player and m.track = 'trading'), 1)
    when 'captain' then (select count(*) from public.player_officers o where o.player_id = p_player)
    when 'hull'    then (select count(*) from public.ships s where s.player_id = p_player)
                      + (select count(*) from public.hull_orders h where h.player_id = p_player and h.launched_at is null)
  end::numeric
$body$
  $f$;

  execute $f$
create function public.first_voyage_job(p_player uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0476: THE JOB THE DELIVER STEP NAMES: of the open hold jobs with a source harbour (0466, 0473), the one whose trip from her capital to
  -- its source and on to its harbour is the shortest a Barca sails (public.sea_reaches), with first_voyages_job_margin times that trip still
  -- inside the time the job stands. Null when none does (or she has no capital). Its seconds are a Barca's (hold_request_speed_kn), as
  -- world.contracts' `from`. A read: nothing is reserved; the next read may name another.
  select jsonb_build_object(
           'id', c.id,
           'port', jsonb_build_object('code', jp.code, 'name', jp.name),
           'from', jsonb_build_object('code', sp.code, 'name', sp.name),
           'good', jsonb_build_object('code', g.code, 'name', g.name),
           'qty', floor(c.premium_ducats / c.premium_per_unit)::int,
           'nm', round(t.nm),
           'sail_seconds', round(t.nm / public.wc_num('hold_request_speed_kn') * 3600 / public.wc_num('time_compression'))::int,
           'expires_at', public.clock_start('game_day', c.expires_day))
    from public.players pl
    join public.nations n on n.id = pl.nation_id
    join public.ports cp on cp.code = n.capital_port_code and cp.kind = 'HARBOUR'
    join public.sea_reaches rc on rc.port_id = cp.id
    join public.trade_contracts c on c.status = 'open' and c.size = 'hold' and c.source_port_id is not null and c.premium_per_unit > 0
    join public.ports sp on sp.id = c.source_port_id
    join public.ports jp on jp.id = c.port_id
    join public.goods g on g.id = c.good_id
    join public.sea_reaches rs on rs.port_id = c.source_port_id
   cross join lateral (select case when sp.id = cp.id then 0 else (rc.reaches ->> sp.code)::numeric end
                            + (rs.reaches ->> jp.code)::numeric as nm) t
   where pl.id = p_player
     and t.nm is not null
     and t.nm / public.wc_num('hold_request_speed_kn') * 3600 / public.wc_num('time_compression') * public.wc_num('first_voyages_job_margin')
         < extract(epoch from public.clock_start('game_day', c.expires_day) - now())
   order by t.nm, c.id
   limit 1
$body$
  $f$;

  execute $f$
create function world.first_voyages()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0476: THE STARTER CHAIN, the client's one door. Dark (first_voyages_enabled false): {"on": false}, nothing read or paid. Lit, for the
-- signed-in company founded under first_voyages_days ago: PAYS every step now met, in order (public.first_voyage_have against the step's
-- need), each ONCE (its public.first_voyages row is the guard, written under her row's lock): coin from her capital (public.capital_pays
-- while the purses are lit, kind VOYAGE_REWARD; a realm that cannot pay: the step waits, nothing written), Reputation (kind first_voyage,
-- keyed). Then answers the step she is on: {on, open, step, of, code, have, need, ducats, reputation, waiting, job (deliver: the hold job to
-- take, public.first_voyage_job), just (the steps this read paid)}. A merchant, an old company, or the chain done: open false.
declare
  v_me    uuid := public.current_player_id();
  v_pl    public.players%rowtype;
  v_steps jsonb := coalesce(public.wc('first_voyages_steps'), '[]'::jsonb);
  v_of    int;
  v_done  int;
  v_s     jsonb;
  v_code  text;
  v_have  numeric;
  v_need  numeric;
  v_duc   bigint;
  v_rep   int;
  v_cap   uuid;
  v_res   jsonb;
  v_just  jsonb := '[]'::jsonb;
  v_wait  boolean := false;
begin
  if public.wc('first_voyages_enabled') is distinct from 'true'::jsonb then
    return jsonb_build_object('on', false);
  end if;
  select * into v_pl from public.players p where p.id = v_me;
  if v_pl.id is null or v_pl.is_npc or v_pl.created_at < now() - make_interval(days => public.wc_int('first_voyages_days')) then
    return jsonb_build_object('on', true, 'open', false);
  end if;
  v_of := jsonb_array_length(v_steps);
  select cp.id into v_cap from public.nations n join public.ports cp on cp.code = n.capital_port_code and cp.kind = 'HARBOUR' where n.id = v_pl.nation_id;

  loop
    select coalesce(max(fv.step), 0) into v_done from public.first_voyages fv where fv.player_id = v_me;
    exit when v_done >= v_of;
    v_s    := v_steps -> v_done;
    v_code := v_s ->> 'code';
    v_need := (v_s ->> 'need')::numeric;
    v_have := public.first_voyage_have(v_me, v_code);
    exit when v_have is null or v_have < v_need;
    v_duc := least(greatest(coalesce((v_s ->> 'ducats')::bigint, 0), 0), public.wc_int('first_voyages_ducats_max'));
    v_rep := least(greatest(coalesce((v_s ->> 'reputation')::int, 0), 0), public.wc_int('first_voyages_reputation_max'));
    begin
      perform 1 from public.players p where p.id = v_me for update;   -- the house first, as every payer locks
      insert into public.first_voyages (player_id, step, code, ducats, reputation)
      values (v_me, v_done + 1, v_code, v_duc, v_rep)
      on conflict (player_id, step) do nothing;
      if found then
        if v_duc > 0 then
          if public.city_treasury_on() then
            v_res := public.capital_pays(v_cap, v_pl.nation_id, v_me, 'VOYAGE_REWARD', v_duc, null, false, null);
            if v_res ? 'waiting' then
              raise exception using errcode = 'ZV476', message = 'her capital cannot pay yet';
            end if;
          else
            perform public.city_pays(v_cap, v_me, 'VOYAGE_REWARD', v_duc, null);
          end if;
        end if;
        perform public.reputation_credit(v_me, 'first_voyage', v_rep, 'first_voyage:' || (v_done + 1)::text,
                                         jsonb_build_object('step', v_done + 1, 'code', v_code));
        v_just := v_just || jsonb_build_array(jsonb_build_object('step', v_done + 1, 'code', v_code, 'ducats', v_duc, 'reputation', v_rep));
      end if;   -- not found: another read paid it a moment ago; the loop reads the chain again
    exception when sqlstate 'ZV476' then
      v_wait := true;
    end;
    exit when v_wait;
  end loop;

  if v_done >= v_of then
    return jsonb_build_object('on', true, 'open', false, 'done', v_of, 'of', v_of, 'just', v_just);
  end if;
  return jsonb_build_object(
    'on', true, 'open', true, 'step', v_done + 1, 'of', v_of, 'code', v_code,
    'have', v_have, 'need', v_need, 'waiting', v_wait,
    'ducats', least(greatest(coalesce((v_s ->> 'ducats')::bigint, 0), 0), public.wc_int('first_voyages_ducats_max')),
    'reputation', least(greatest(coalesce((v_s ->> 'reputation')::int, 0), 0), public.wc_int('first_voyages_reputation_max')),
    'job', case when v_code = 'deliver' then public.first_voyage_job(v_me) end,
    'just', v_just);
end
$body$
  $f$;
  revoke all on function public.first_voyage_have(uuid, text) from public, anon, authenticated;
  revoke all on function public.first_voyage_job(uuid) from public, anon, authenticated;
  revoke all on function world.first_voyages() from public, anon;
  grant execute on function world.first_voyages() to authenticated;
  comment on function world.first_voyages() is
    '0476: the starter chain (dark {"on": false}): pays each step now met once, in order, and answers the step she is on and, on the deliver step, the hold job to take. A read that writes, as world.contracts winds. Client door.';

  -- ── 4. THE HUNK (it occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0476 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0476 values
  ('public.client_rpc_entry_points()', 1,
$h$      ('world',       'pirate_bounties',       ''),$h$,
$h$      ('world',       'pirate_bounties',       ''),
      -- 0476: the starter chain (dark: {"on": false})
      ('world',       'first_voyages',         ''),$h$);

  for v_h in select h.fn from hunks_0476 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0476 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0476 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0476 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0476 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0476 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 5. SELF-ASSERT: the catalog, the knobs, the word, the kind, the door ──
  v_steps := public.wc('first_voyages_steps');
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_new) u(q)))) <> v_fn_before then
    raise exception '0476 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0476 self-assert FAIL: the grants, volatility, definer, search path or owner of the registry moved';
  end if;
  if public.wc('first_voyages_enabled') <> 'false'::jsonb or public.wc_int('first_voyages_days') <> 7
     or public.wc_int('first_voyages_ducats_max') <> 5000 or public.wc_int('first_voyages_reputation_max') <> 50
     or public.wc_num('first_voyages_job_margin') <> 2
     or jsonb_array_length(public.wc('first_voyages_steps')) <> 5
     or (select array_agg(e ->> 'code' order by o) from jsonb_array_elements(v_steps) with ordinality j(e, o))
        <> array['deliver', 'profit', 'trading', 'captain', 'hull']
     or (select sum((e ->> 'ducats')::bigint) from jsonb_array_elements(v_steps) e) <> 16000
     or exists (select 1 from jsonb_array_elements(v_steps) e
                 where (e ->> 'ducats')::bigint > 5000 or (e ->> 'reputation')::int > 50
                    or public.first_voyage_have(gen_random_uuid(), e ->> 'code') is null)
     or not exists (select 1 from public.stats_flow_words w where w.kind = 'VOYAGE_REWARD' and w.side = 'moved')
     or not exists (select 1 from public.reputation_kinds k where k.code = 'first_voyage' and k.sign = 1 and not k.capped)
     or public.ledger_is_trade('VOYAGE_REWARD') then
    raise exception '0476 self-assert FAIL: the knobs are not as written, a step''s pay is past its cap or its code unknown, VOYAGE_REWARD is not a moved word (or is trade), or first_voyage is not an uncapped earning kind';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e
       where (e.schema_name, e.function_name, e.arg_types) = ('world', 'first_voyages', '')
         and e.fn is not null and has_function_privilege('authenticated', e.fn, 'execute') and not has_function_privilege('anon', e.fn, 'execute')) <> 1
     or has_function_privilege('authenticated', 'public.first_voyage_have(uuid,text)', 'execute')
     or has_function_privilege('authenticated', 'public.first_voyage_job(uuid)', 'execute')
     or has_table_privilege('authenticated', 'public.first_voyages', 'select,insert,update,delete')
     or has_table_privilege('anon', 'public.first_voyages', 'select')
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0476 self-assert FAIL: world.first_voyages is not registered for authenticated alone, or a client reaches a server-only function or the table';
  end if;

  -- ── 6. THE PROBE, rolled back by a raised sentinel: purses dark, Reputation lit, a fresh company and an old one ──
  begin
    v_me  := public.new_house(c_uid, 'Casa da Viagem 0476', 'PRT');   -- founded as a sign-up is, then the purses go dark for the probe
    v_old := public.new_house(c_old, 'Casa Velha 0476', 'PRT');
    update public.world_config set value = 'false'::jsonb where key = 'city_treasury_enabled';
    update public.world_config set value = 'true'::jsonb where key = 'reputation_on';
    update public.players set created_at = now() - interval '8 days' where id = v_old;
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    perform cmd.assume_identity(c_uid);

    -- (a) DARK: {"on": false}, nothing paid
    v_p0 := (select p.ducats from public.players p where p.id = v_me);
    perform public.credit(v_me, 'PREMIUM', 500, null);
    if world.first_voyages() is distinct from '{"on": false}'::jsonb or exists (select 1 from public.first_voyages)
       or (select p.ducats from public.players p where p.id = v_me) <> v_p0 + 500 then
      raise exception '0476 self-assert FAIL: dark, the read is not {"on": false} or it paid';
    end if;

    -- (b) LIT: each step pays once, in order, when her own rows meet it
    update public.world_config set value = 'true'::jsonb where key = 'first_voyages_enabled';
    v_r := world.first_voyages();   -- step 1 met already (the PREMIUM row): paid; step 2 waits
    if v_r -> 'just' <> '[{"step": 1, "code": "deliver", "ducats": 2000, "reputation": 20}]'::jsonb
       or (v_r ->> 'step')::int <> 2 or v_r ->> 'code' <> 'profit' or (v_r ->> 'open')::boolean is distinct from true then
      raise exception '0476 self-assert FAIL: lit, the deliver step did not pay once and hand on to profit: %', v_r;
    end if;
    v_r := world.first_voyages();
    if jsonb_array_length(v_r -> 'just') <> 0 or (v_r ->> 'step')::int <> 2 then
      raise exception '0476 self-assert FAIL: lit, a second read paid again or moved the chain: %', v_r;
    end if;
    -- her trade rows so far (a founding may have bought stores): 9,999 of profit in all, then one more
    v_sell := 9999 - coalesce((select sum(l.ducats_delta) from public.ledger l where l.player_id = v_me and public.ledger_is_trade(l.kind)), 0);
    perform public.credit(v_me, 'SELL', v_sell, null);
    if jsonb_array_length(world.first_voyages() -> 'just') <> 0 then
      raise exception '0476 self-assert FAIL: lit, 9,999 of profit paid the 10,000 step';
    end if;
    perform public.credit(v_me, 'SELL', 1, null);
    v_r := world.first_voyages();
    if v_r -> 'just' -> 0 ->> 'code' <> 'profit' or v_r ->> 'code' <> 'trading' or (v_r ->> 'have')::int <> 1 then
      raise exception '0476 self-assert FAIL: lit, 10,000 of profit did not pay and hand on to trading at 1: %', v_r;
    end if;
    insert into public.house_level_marks (player_id, track, level) values (v_me, 'trading', 3)
      on conflict (player_id, track) do update set level = 3;
    select o.id into v_off from public.officers o order by o.code limit 1;
    insert into public.player_officers (player_id, officer_id) values (v_me, v_off) on conflict do nothing;
    v_r := world.first_voyages();   -- trading and captain both met: both paid in one read, in order; the hull waits (one ship)
    if (select array_agg(e ->> 'code' order by o) from jsonb_array_elements(v_r -> 'just') with ordinality j(e, o)) <> array['trading', 'captain']
       or v_r ->> 'code' <> 'hull' or (v_r ->> 'have')::int <> 1 then
      raise exception '0476 self-assert FAIL: lit, Trading 3 and a captain did not pay in order and hand on to the hull at one ship: %', v_r;
    end if;
    insert into public.hull_orders (player_id, port_id, class_code, labour, materials, fee, price, ordered_at, ready_at)
    values (v_me, v_lis, 'barca', 15000, 2566, 30991, 48557, now(), now() + interval '30 minutes');
    v_r := world.first_voyages();
    if v_r -> 'just' -> 0 ->> 'code' <> 'hull' or (v_r ->> 'open')::boolean or (v_r ->> 'done')::int <> 5 then
      raise exception '0476 self-assert FAIL: lit, the hull on order did not pay and close the chain: %', v_r;
    end if;
    if jsonb_array_length(world.first_voyages() -> 'just') <> 0 then
      raise exception '0476 self-assert FAIL: lit, the closed chain paid again';
    end if;
    select coalesce(sum(l.ducats_delta), 0) into v_paid from public.ledger l where l.player_id = v_me and l.kind = 'VOYAGE_REWARD';
    select coalesce(sum(b.delta), 0) into v_rep from public.reputation_book b where b.player_id = v_me and b.kind = 'first_voyage';
    if v_paid <> 16000 or (select count(*) from public.ledger l where l.player_id = v_me and l.kind = 'VOYAGE_REWARD') <> 5
       or v_rep <> 160 or (select count(*) from public.first_voyages fv where fv.player_id = v_me) <> 5
       or (select p.ducats from public.players p where p.id = v_me) <> v_p0 + 500 + v_sell + 1 + 16000 then
      raise exception '0476 self-assert FAIL: lit, the chain paid % coin and % Reputation (16,000 and 160 wanted) or the purse is off', v_paid, v_rep;
    end if;
    -- the job reading answers a row of its shape or null, and reads under its budget (hold jobs as the image has them)
    v_want := public.first_voyage_job(v_me);
    if v_want is not null and (v_want ->> 'sail_seconds' is null or v_want -> 'from' ->> 'code' is null or v_want -> 'port' ->> 'code' is null) then
      raise exception '0476 self-assert FAIL: the job reading served a row without its harbours or its time: %', v_want;
    end if;

    -- (c) AN OLD COMPANY: nothing offered, nothing paid (she has a PREMIUM row too)
    perform public.credit(v_old, 'PREMIUM', 500, null);
    perform cmd.assume_identity(c_old);
    v_r := world.first_voyages();
    if v_r <> '{"on": true, "open": false}'::jsonb or exists (select 1 from public.first_voyages fv where fv.player_id = v_old) then
      raise exception '0476 self-assert FAIL: an old company was offered or paid the chain: %', v_r;
    end if;
    v_note := format('dark nothing; lit five steps paid once each in order (16,000 coin, 160 Reputation), a second read nothing, an old company nothing; job %s',
                     coalesce((v_want -> 'good' ->> 'code') || ' ' || (v_want -> 'from' ->> 'code') || '->' || (v_want -> 'port' ->> 'code') || ' ' || (v_want ->> 'sail_seconds') || ' s', 'none open in this image'));
    raise exception using errcode = 'ZX476', message = 'PROBE_ROLLBACK_0476';
  exception when sqlstate 'ZX476' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0476 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like 'Casa % 0476' or p.auth_uid in (c_uid, c_old))
     or exists (select 1 from public.first_voyages)
     or public.wc('first_voyages_enabled') is distinct from 'false'::jsonb
     or public.current_player_id() is not null then
    raise exception '0476 self-assert FAIL: the probe left something behind';
  end if;

  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0476 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0476 self-assert ok: FIRST VOYAGES (dark). % hunk once and reversing; grants and volatility unmoved; no other function moved; the table, three functions, six knobs (first_voyages_enabled false), VOYAGE_REWARD moved, first_voyage kind. Probe (rolled back): %. % ms.',
    (select count(*) from hunks_0476), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
