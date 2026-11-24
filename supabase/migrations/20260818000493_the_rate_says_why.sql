-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (no coin moves: HQ's per-hour figure is explained, and a purchase is no longer read as a running loss)
-- 0493 - THE RATE SAYS WHY  (no switch, no coin: one read authority for HQ's net per hour, with its lines)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-24: "i am -19.649 / hour. it should say why". Then, told the cause: "why investing causes les money? wtf?"
--   docs/design/hq-corp-2026-11-24.md B4 (the ONE rate authority, brought forward from 0495); dev log docs/dev-log/2026-11-24-rate-why.md.
--
-- THE FINDING (the lead's prod read): her -19,649 an hour is -471,566 over 24 hours: SHARE -461,384 in two rows (she invested),
--   TOW -6,932, OFFICER_WAGE -3,250 (she signed a captain). 0480's rate is every ledger row of the last 24 hours over 24, so a
--   purchase she makes once reads as a loss she runs every hour, and the figure names no cause.
--
-- WHAT SAYS THE OPPOSITE, NAMED: public.hq_board_for's `rate` (0480, lines 416-421): sum(ledger, last 24 h, FOUNDING and probes
--   left out) / 24, one figure, no lines. THIS FILE DELIBERATELY REPLACES THAT RULE FOR THE ONE-TIME KINDS: the headline is her
--   RUNNING income and costs only. The old sum is still served whole (`all_24h`), so nothing is hidden.
--
-- WHAT (DECIDED BY DEFAULT; the owner may reverse any of it):
--   public.company_rate_line(kind) -> (line, one_time): THE ONE MAP of a ledger kind to a plain line. IMMUTABLE. A kind it does not
--     know is `other`, running. The lines and their kinds:
--       RUNNING   trade      BUY SELL PREMIUM BOUNTY REQUEST_ESCROW REQUEST_FILL REQUEST_REFUND   (cargo bought is trading, not a purchase)
--                 contracts  CONTRACT_COLLATERAL CONTRACT_ESCROW CONTRACT_FORFEIT CONTRACT_RETURN CONTRACT_REWARD
--                 dividends  DIVIDEND          rewards   VOYAGE_REWARD CAPITAL_GIFT
--                 sea        LOOT PIRATE_BOUNTY SEA_FIND SEA_LOSS
--                 wages      WAGES             tax       TAX             dock      PORT_FEE
--                 stores     PROVISION         repairs   REPAIR REFIT    tow       TOW
--                 insurance  INSURANCE INSURANCE_PAID                    fines     FINE RANSOM   (a fine or a ransom is not a purchase)
--                 other      every kind not named here (RESCALE, LIQUIDATION, NPC_CARRIED, a kind a later file adds)
--       ONE TIME  invest     SHARE             ships     BUILD           hiring    HIRE OFFICER_WAGE
--                 training   TUITION           gear      GEAR LAND       room      SLOT            gifts     DONATION
--   public.company_rate_for(player) -> jsonb, THE ONE RATE AUTHORITY (STABLE, writes nothing). THE SAME ROWS AND WINDOW as 0480's
--     rate (her ledger, created_at > now() - 24 hours, kind <> FOUNDING, not PROBE_*, by the (player_id, created_at) index) and the
--     same rounding (round(sum / 24.0)):
--       {per_hour, net_24h        her RUNNING lines only (0480 served every kind here)
--        one_time_24h             her one-time lines' sum
--        all_24h                  every line's sum = 0480's old net_24h, to the unit
--        since
--        top                      the lines the headline names: up to two running lines, her largest losses when the figure is
--                                 under zero (else her largest gains), each of that sign
--        lines [{line, total_24h, per_hour, count, one_time}]   running first, then one time; in each the largest loss first}
--     sum(running lines' total_24h) = net_24h and sum(all lines' total_24h) = all_24h, exactly (one grouping feeds all three).
--   world.company_rate() -> the caller's own (null signed out or a merchant). SERVER ONLY for now: no screen asks it alone, and a
--     door with no screen is a door nobody opens (tests/rpc.surface.spec.ts). The lines travel with the board.
--   public.hq_board_for's `rate` is re-pointed (ONE hunk): 'rate', public.company_rate_for(p_player). The keys per_hour, net_24h and
--     since stay; one_time_24h, all_24h, top and lines arrive with the board, no extra request.
-- WHAT ASSERTS THE OLD RATE, CHECKED: 0480's own probe (two SELL rows) runs before this file and is not touched; proof 183 HB_RATE
--   plants SELL and BUY rows, both running, so its 1200 / 50 stands. No frozen assert needs a patch (src/lib/db/frozenAsserts.ts).
-- NOT CHANGED: any command, any coin, any switch, world.report, the ledger, any other key of the board.
-- ROWS: none. No table, no index, no cron, no beat step, no knob. 0 new rows a minute.
-- COST: the same index range scan of her last 24 hours as 0480's rate, grouped once (company_rate_line is a VALUES join, inlined).
-- LOCKS: CREATE FUNCTION x3; CREATE OR REPLACE x1 by a hunk (public.hq_board_for). TIME: a second.
--   BUDGET: statement_timeout 30 s, lock_timeout 5 s; fails above 20 s.
-- ROLLBACK (forward): a migration reversing the one hunk (OLD text below verbatim) and dropping the three functions; the client reads
--   `lines` as optional and draws the plain figure without them.
-- SELF-ASSERT: the hunk once and reversing; no other function moved; the hunked body's grants, volatility, definer, search path and
--   owner unmoved; no world_config row moved; the three new functions server only (public, anon, authenticated, service_role), the
--   map IMMUTABLE and the two reads STABLE. THE PROBE (rolled back by a raised sentinel; it counts only its own rows): a fresh company
--   with planted ledger rows (running, one time, an unknown kind, a PROBE_ row, a row outside the window): every figure as written;
--   the running lines sum to net_24h; all lines sum to all_24h, which is 0480's old expression read in the same statement; the order;
--   `top`; the board lit serves the same object as the authority; world.company_rate() is hers.
-- VERSION: 0493 = 0492 + 1 (prod head 0491 when written; 0492, #854, deploys first).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_fn     constant text := 'public.hq_board_for(uuid)';
  c_new    constant text[] := array['public.company_rate_line(text)', 'public.company_rate_for(uuid)', 'world.company_rate()'];
  c_uid    constant uuid := '00000000-0493-4000-8000-000000000001';
  v_t0        timestamptz := clock_timestamp();
  x           record;
  v_q         text;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_cfg_before text;
  v_lived     boolean := false;
  v_me        uuid;
  v_r         jsonb;
  v_old       numeric;
  v_b         jsonb;
  v_note      text := '';
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.company_rate_for(uuid)') is not null or to_regprocedure('world.company_rate()') is not null
     or to_regprocedure('public.company_rate_line(text)') is not null then
    raise exception '0493 refuses: it has been applied once';
  end if;
  if to_regprocedure(c_fn) is null or to_regprocedure('world.hq_board()') is null or to_regprocedure('cmd.assume_identity(uuid)') is null then
    raise exception '0493 refuses: the HQ board (0480) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  v_pre := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> c_fn::regprocedure::oid;
  select md5(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text)
    into v_meta from pg_proc p where p.oid = c_fn::regprocedure::oid;
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE RULES ──
  execute $f$
create function public.company_rate_line(p_kind text)
returns table (line text, one_time boolean)
language sql
immutable
set search_path = public, pg_temp
as $body$
  -- 0493: THE ONE MAP of a ledger kind to a plain line of the company's rate, and whether that line is a ONE-TIME purchase (left out
  -- of the per-hour figure) or RUNNING income and cost. A kind not named here is `other`, running. The lines: 0493's header.
  select coalesce(m.line, 'other'), coalesce(m.one_time, false)
    from (select 1) one
    left join (values
      ('BUY', 'trade', false), ('SELL', 'trade', false), ('PREMIUM', 'trade', false), ('BOUNTY', 'trade', false),
      ('REQUEST_ESCROW', 'trade', false), ('REQUEST_FILL', 'trade', false), ('REQUEST_REFUND', 'trade', false),
      ('CONTRACT_COLLATERAL', 'contracts', false), ('CONTRACT_ESCROW', 'contracts', false), ('CONTRACT_FORFEIT', 'contracts', false),
      ('CONTRACT_RETURN', 'contracts', false), ('CONTRACT_REWARD', 'contracts', false),
      ('DIVIDEND', 'dividends', false),
      ('VOYAGE_REWARD', 'rewards', false), ('CAPITAL_GIFT', 'rewards', false),
      ('LOOT', 'sea', false), ('PIRATE_BOUNTY', 'sea', false), ('SEA_FIND', 'sea', false), ('SEA_LOSS', 'sea', false),
      ('WAGES', 'wages', false), ('TAX', 'tax', false), ('PORT_FEE', 'dock', false), ('PROVISION', 'stores', false),
      ('REPAIR', 'repairs', false), ('REFIT', 'repairs', false), ('TOW', 'tow', false),
      ('INSURANCE', 'insurance', false), ('INSURANCE_PAID', 'insurance', false),
      ('FINE', 'fines', false), ('RANSOM', 'fines', false),
      ('SHARE', 'invest', true), ('BUILD', 'ships', true), ('HIRE', 'hiring', true), ('OFFICER_WAGE', 'hiring', true),
      ('TUITION', 'training', true), ('GEAR', 'gear', true), ('LAND', 'gear', true), ('SLOT', 'room', true), ('DONATION', 'gifts', true)
    ) m(kind, line, one_time) on m.kind = p_kind
$body$
  $f$;

  execute $f$
create function public.company_rate_for(p_player uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0493: THE ONE RATE AUTHORITY (server only; HQ's board serves it as `rate`). Her ledger's last 24 real hours, FOUNDING and probes
  -- left out (0480's rows and window, by the (player_id, created_at) index), grouped into plain lines (public.company_rate_line).
  -- per_hour and net_24h are her RUNNING lines only; a one-time purchase (investing, a hull, hiring, ...) is served beside them in
  -- one_time_24h and its own lines; all_24h is every row (0480's old net_24h). Writes nothing.
  with g as materialized (
    select k.line, k.one_time, sum(l.ducats_delta) as total, count(*) as n
      from public.ledger l
     cross join lateral public.company_rate_line(l.kind) k
     where l.player_id = p_player and l.created_at > now() - interval '24 hours'
       and l.kind <> 'FOUNDING' and left(l.kind, 6) <> 'PROBE_'
     group by k.line, k.one_time
  ), s as (
    select coalesce(sum(g.total) filter (where not g.one_time), 0) as running,
           coalesce(sum(g.total) filter (where g.one_time), 0) as once,
           coalesce(sum(g.total), 0) as every
      from g
  )
  select jsonb_build_object(
           'per_hour', round(s.running / 24.0),
           'net_24h', s.running,
           'one_time_24h', s.once,
           'all_24h', s.every,
           'since', now() - interval '24 hours',
           -- the lines the headline names: under zero her two largest losses, else her two largest gains
           'top', coalesce((select jsonb_agg(t.line order by t.ord)
                              from (select g.line, row_number() over (order by abs(g.total) desc, g.line) as ord
                                      from g
                                     where not g.one_time and ((s.running < 0 and g.total < 0) or (s.running >= 0 and g.total > 0))
                                     order by abs(g.total) desc, g.line
                                     limit 2) t), '[]'::jsonb),
           'lines', coalesce((select jsonb_agg(jsonb_build_object('line', g.line, 'total_24h', g.total, 'per_hour', round(g.total / 24.0),
                                                                  'count', g.n, 'one_time', g.one_time)
                                               order by g.one_time, g.total, g.line)
                                from g), '[]'::jsonb))
    from s
$body$
  $f$;

  execute $f$
create function world.company_rate()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0493: THE CALLER'S OWN RATE (public.company_rate_for). Null signed out or a merchant. Server only until a screen asks it alone:
-- today the lines travel with world.hq_board()'s `rate`. Writes nothing.
declare
  v_me uuid := public.current_player_id();
begin
  if v_me is null or coalesce((select pl.is_npc from public.players pl where pl.id = v_me), true) then
    return null;
  end if;
  return public.company_rate_for(v_me);
end
$body$
  $f$;

  -- grants: all three server only (service_role too: the platform grants execute on a new function by default, 0459's first push)
  foreach v_q in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_q::regprocedure);
  end loop;
  comment on function public.company_rate_for(uuid) is
    '0493: the one rate authority: her last 24 hours of ledger as plain lines; per_hour and net_24h are running income and costs, one-time purchases are served beside them. Server only; world.hq_board() serves it as rate.';

  -- ── 3. THE HUNK (the OLD text once in the live body; it reverses) ──
  create temp table hunks_0493 (ord int primary key, old text, new text) on commit drop;
  insert into hunks_0493 values
  (1,
$h$    -- THE RATE: her ledger's last 24 real hours (FOUNDING and probes left out, as world.report), by the (player_id, created_at) index
    'rate', (select jsonb_build_object('per_hour', round(coalesce(sum(l.ducats_delta), 0) / 24.0), 'net_24h', coalesce(sum(l.ducats_delta), 0),
                                       'since', now() - interval '24 hours')
               from public.ledger l
              where l.player_id = p_player and l.created_at > now() - interval '24 hours'
                and l.kind <> 'FOUNDING' and left(l.kind, 6) <> 'PROBE_'),
$h$,
$h$    -- THE RATE (0493): the one authority, public.company_rate_for: the same rows and window as 0480's, per_hour and net_24h her
    -- running lines only, her one-time purchases beside them, and every line that makes the figure
    'rate', public.company_rate_for(p_player),
$h$);

  v_def := v_pre;
  for x in select * from hunks_0493 order by ord loop
    v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
    if v_n <> 1 then
      raise exception '0493 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, c_fn, v_n;
    end if;
    v_def := replace(v_def, x.old, x.new);
  end loop;
  execute v_def;
  v_def := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  for x in select * from hunks_0493 order by ord desc loop
    if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
      raise exception '0493 self-assert FAIL: hunk % of % is not in the new body once', x.ord, c_fn;
    end if;
    v_def := replace(v_def, x.new, x.old);
  end loop;
  if v_def <> v_pre then
    raise exception '0493 self-assert FAIL: % does not reverse to its pre-image', c_fn;
  end if;

  -- ── 4. SELF-ASSERT: the catalog, the grants ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> c_fn::regprocedure::oid
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_new) u(q)))) <> v_fn_before then
    raise exception '0493 self-assert FAIL: another function moved';
  end if;
  if (select md5(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text)
        from pg_proc p where p.oid = c_fn::regprocedure::oid) <> v_meta then
    raise exception '0493 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', c_fn;
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('authenticated', u.q::regprocedure, 'execute') or has_function_privilege('anon', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute'))
     or has_function_privilege('authenticated', c_fn, 'execute') or has_function_privilege('anon', c_fn, 'execute')
     or (select p.provolatile from pg_proc p where p.oid = 'public.company_rate_line(text)'::regprocedure) <> 'i'
     or (select count(*) from pg_proc p where p.oid in ('public.company_rate_for(uuid)'::regprocedure, 'world.company_rate()'::regprocedure) and p.provolatile = 's') <> 2
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0493 self-assert FAIL: a new function is reachable by a client or service_role, or is not a read';
  end if;
  -- the map: a purchase is one time, a fine and cargo are running, an unknown kind is Other and running
  if (select (k.line, k.one_time) from public.company_rate_line('SHARE') k) is distinct from ('invest'::text, true)
     or (select (k.line, k.one_time) from public.company_rate_line('OFFICER_WAGE') k) is distinct from ('hiring'::text, true)
     or (select (k.line, k.one_time) from public.company_rate_line('TOW') k) is distinct from ('tow'::text, false)
     or (select (k.line, k.one_time) from public.company_rate_line('BUY') k) is distinct from ('trade'::text, false)
     or (select (k.line, k.one_time) from public.company_rate_line('RANSOM') k) is distinct from ('fines'::text, false)
     or (select (k.line, k.one_time) from public.company_rate_line('A_KIND_NOBODY_WROTE') k) is distinct from ('other'::text, false)
     or (select (k.line, k.one_time) from public.company_rate_line(null) k) is distinct from ('other'::text, false) then
    raise exception '0493 self-assert FAIL: the map of kinds to lines is not as written';
  end if;

  -- ── 5. THE PROBE, rolled back by a raised sentinel (it reads only its own company's rows) ──
  begin
    v_me := public.new_house(c_uid, 'Casa do Porque 0493', 'PRT');
    -- her own rows, all inside the window but the last two: the owner's day in small (she invested twice, was towed, signed a captain)
    insert into public.ledger (player_id, kind, ducats_delta, balance_after, created_at) values
      (v_me, 'SHARE',        -400000, 1, now() - interval '2 hours'),
      (v_me, 'SHARE',         -61384, 1, now() - interval '3 hours'),
      (v_me, 'TOW',            -6932, 1, now() - interval '4 hours'),
      (v_me, 'OFFICER_WAGE',   -3250, 1, now() - interval '5 hours'),
      (v_me, 'SELL',            9000, 1, now() - interval '6 hours'),
      (v_me, 'BUY',            -6600, 1, now() - interval '7 hours'),
      (v_me, 'WAGES',           -480, 1, now() - interval '6 hours'),
      (v_me, 'KIND_OF_0493',     -12, 1, now() - interval '1 hour'),
      (v_me, 'PROBE_0493',     77777, 1, now() - interval '1 hour'),
      (v_me, 'SELL',           99999, 1, now() - interval '24 hours 1 minute');
    -- the authority, and 0480's old expression, read in ONE statement
    select public.company_rate_for(v_me),
           (select coalesce(sum(l.ducats_delta), 0) from public.ledger l
             where l.player_id = v_me and l.created_at > now() - interval '24 hours' and l.kind <> 'FOUNDING' and left(l.kind, 6) <> 'PROBE_')
      into v_r, v_old;
    -- running: trade +2,400, tow -6,932, wages -480, other -12 = -5,024 -> -209 an hour; one time: invest -461,384, hiring -3,250
    if (v_r->>'net_24h')::numeric <> -5024 or (v_r->>'per_hour')::numeric <> round(-5024 / 24.0) or (v_r->>'one_time_24h')::numeric <> -464634
       or (v_r->>'all_24h')::numeric <> -469658 or (v_r->>'all_24h')::numeric <> v_old
       or (v_r->>'since')::timestamptz <> now() - interval '24 hours'
       or (select coalesce(sum((e->>'total_24h')::numeric), 0) from jsonb_array_elements(v_r->'lines') e where not (e->>'one_time')::boolean) <> (v_r->>'net_24h')::numeric
       or (select coalesce(sum((e->>'total_24h')::numeric), 0) from jsonb_array_elements(v_r->'lines') e where (e->>'one_time')::boolean) <> (v_r->>'one_time_24h')::numeric
       or (select coalesce(sum((e->>'total_24h')::numeric), 0) from jsonb_array_elements(v_r->'lines') e) <> v_old
       or (select jsonb_agg(e->>'line' order by k) from jsonb_array_elements(v_r->'lines') with ordinality z(e, k))
            is distinct from '["tow", "wages", "other", "trade", "invest", "hiring"]'::jsonb
       or v_r->'top' is distinct from '["tow", "wages"]'::jsonb
       or (select e from jsonb_array_elements(v_r->'lines') e where e->>'line' = 'invest')
            is distinct from jsonb_build_object('line', 'invest', 'total_24h', -461384, 'per_hour', round(-461384 / 24.0), 'count', 2, 'one_time', true)
       or (select e from jsonb_array_elements(v_r->'lines') e where e->>'line' = 'trade')
            is distinct from jsonb_build_object('line', 'trade', 'total_24h', 2400, 'per_hour', 100, 'count', 2, 'one_time', false) then
      raise exception '0493 self-assert FAIL: the rate is not as written: % (0480''s sum %)', v_r, v_old;
    end if;
    -- a company in profit names her gains
    insert into public.ledger (player_id, kind, ducats_delta, balance_after, created_at) values
      (v_me, 'DIVIDEND', 30000, 1, now() - interval '2 hours');
    if public.company_rate_for(v_me)->'top' is distinct from '["dividends", "trade"]'::jsonb
       or (public.company_rate_for(v_me)->>'net_24h')::numeric <> 24976 then
      raise exception '0493 self-assert FAIL: in profit the headline does not name her gains: %', public.company_rate_for(v_me);
    end if;
    -- the board serves the authority's own object (no trade run priced: hq_board_fleets 0), and world.company_rate() is hers
    update public.world_config set value = 'true'::jsonb where key = 'hq_board_enabled';
    update public.world_config set value = to_jsonb(0) where key = 'hq_board_fleets';
    perform cmd.assume_identity(c_uid);
    select world.hq_board(), public.company_rate_for(v_me), world.company_rate() into v_b, v_r, v_def;
    if (v_b->>'company')::boolean is not true or v_b->'rate' is distinct from v_r or v_def::jsonb is distinct from v_r
       or jsonb_typeof(v_b->'moves') <> 'array' or not (v_b ? 'next' and v_b ? 'threats' and v_b ? 'unpriced' and v_b ? 'clock') then
      raise exception '0493 self-assert FAIL: the board does not serve the one authority, or lost a key: % / %', left(v_b::text, 600), v_r;
    end if;
    -- nobody's rate (no row in the window): zeros and no line, as 0480 served
    if public.company_rate_for('00000000-0493-4000-8000-0000000000ff'::uuid)
         is distinct from jsonb_build_object('per_hour', 0, 'net_24h', 0, 'one_time_24h', 0, 'all_24h', 0, 'since', now() - interval '24 hours',
                                             'top', '[]'::jsonb, 'lines', '[]'::jsonb) then
      raise exception '0493 self-assert FAIL: nobody''s rate is not zeros: %', public.company_rate_for('00000000-0493-4000-8000-0000000000ff'::uuid);
    end if;
    v_note := format('running %s (%s an hour: %s), one time %s, all %s = 0480''s sum; %s lines; the board serves the same object',
      v_r->>'net_24h', v_r->>'per_hour', v_r->'top', v_r->>'one_time_24h', v_r->>'all_24h', jsonb_array_length(v_r->'lines'));
    raise exception using errcode = 'ZX493', message = 'PROBE_ROLLBACK_0493';
  exception when sqlstate 'ZX493' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0493 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name = 'Casa do Porque 0493' or p.auth_uid = c_uid) then
    raise exception '0493 self-assert FAIL: the probe left something behind';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c) <> v_cfg_before then
    raise exception '0493 self-assert FAIL: a world_config row moved';
  end if;

  if clock_timestamp() - v_t0 > interval '20 seconds' then
    raise exception '0493 self-assert FAIL: the file took % (budget 20 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0493 self-assert ok: THE RATE SAYS WHY. One hunk once and reversing; three new functions server only; grants and volatility unmoved; no other function or knob moved. Probe (rolled back): %. % ms.',
    v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
