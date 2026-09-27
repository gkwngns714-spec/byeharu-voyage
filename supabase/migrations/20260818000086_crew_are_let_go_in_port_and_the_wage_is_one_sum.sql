-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0086 — CREW ARE LET GO IN PORT, AND THE WAGE IS ONE SUM
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM (2026-09-13, docs/OWNER_REQUESTS.md row 85) ────────────────────────────
--   "inn, it should be like trade, where you can hire, dismiss crews, and by doing so show how
--    much it will consume everyday"
--
-- ── WHAT THE CHAIN SAID BEFORE THIS FILE, READ OFF THE CHAIN ────────────────────────────────────
--   * HIRING is `cmd.do_hire(fleet, {count})` (0007:632; words sliced 0030, refusals sliced 0050).
--     Its price is `hire_crew_rate` ducats a head out of the port's `crew_pool` and x
--     `crew_urgent_multiplier` beyond it (0007:673); it fills the hulls with the most room first
--     and draws the pool down (0007:681-689); it refuses E_NOT_DOCKED, E_CREW_MAX (more than the
--     berths free, `sum(crew_max - crew)`), E_CREW_POOL and E_INSUFFICIENT_FUNDS; and it writes a
--     HIRED event with the HIRE movement (0007:690).
--   * DISMISSING did not exist. No verb, no function, no event: the grammar's fourteen verbs
--     (0008:233 as widened by 0068/0070/0072/0074) have no word for letting crew go, so a fleet
--     that hired to the berths kept paying for them for ever.
--   * WAGES are charged by `voyage.settle` (0007:887, superseded 0027:237, sliced 0047 §12 and
--     0059) ONCE PER SETTLED VOYAGE-DAY, AT SEA ONLY: `sum(ships.crew) x wage_per_crew_day x
--     (short_rations ? short_rations_wage_mult : 1)`, floored at the purse, through
--     `public.credit(player, 'WAGES', ...)` (0027:300-308). Nothing is charged in port. The two
--     knobs live in world_config (0001:169-170); `wage_per_crew_day` is served on
--     world.snapshot().config (0009:110) — a RATE, which is not a cost.
--   * A DAILY CREW COST was served nowhere. A screen that wanted "what will these crew cost per
--     day" had one option — multiply the knob by the crew itself — and that is a second author of
--     the tick's arithmetic (docs/NO_SPAGHETTI.md §1, question 1: it re-derives).
--
-- ── WHAT THIS FILE ADDS, AND WHERE EACH THING LIVES ─────────────────────────────────────────────
--   public.crew_wages(crew, short)   THE ONE SUM: ducats a fleet of `crew` owes for one voyage-day,
--                                    on full or on short rations, rounded exactly as the tick's
--                                    bigint assignment rounded it. Server-only.
--   voyage.settle                    SLICED (one hunk): the wages line now READS crew_wages.
--                                    The tick and the quote are one function, by construction.
--   cmd.do_dismiss(fleet, {count})   THE VERB. In port only (E_NOT_DOCKED); never below the
--                                    complement a hull needs to sail — `crew_required`, the same
--                                    figure E_CREW_SHORT gates SAIL on (0007:371) — folded PER
--                                    HULL, because a hull above its complement does not lend its
--                                    surplus to one below it (E_CREW_REQUIRED, with figures);
--                                    takes from the hulls with the most to spare first; puts the
--                                    men back on the quay (`crew_pool + count`, the mirror of
--                                    do_hire's draw-down, so a city's idle crew is one count that
--                                    both verbs move); NO REFUND and no money moves — the hire
--                                    fee was the price of the day they signed; writes a DISMISSED
--                                    event {fleet, count, crew}.
--   world.crew_cost(fleet, crew)     THE SERVED READ, for ANY count: {crew, per_day,
--                                    per_day_short_rations}, from crew_wages. `crew` null means
--                                    the crew aboard now. Refuses a fleet that is not yours
--                                    (E_NOT_YOURS, 0009's own word). This is what the Inn's
--                                    caption reads as the stepper moves, and what the tick
--                                    charges — one sum, asserted equal below on a real settled day.
--   the grammar                      DISMISS <count>, parsed exactly as HIRE is (a number of crew,
--                                    an optional leading fleet) — the branch is FOLDED into HIRE's,
--                                    not written beside it; served on cmd.verb_schema right after
--                                    HIRE; dispatched by cmd.execute_order and dry-run by
--                                    cmd.preview beside HIRE's arms; registered as a client entry
--                                    point (world.crew_cost) in public.client_rpc_entry_points.
--
-- ── SUPERSEDE ───────────────────────────────────────────────────────────────────────────────────
-- This file SUPERSEDES the deployed bodies of `voyage.settle(uuid, timestamptz)` (0027:237, as
-- sliced by 0047 §12 and 0059 §3), `cmd.parse(uuid, uuid, text)` (0008, last cut 0074),
-- `cmd.verb_schema()` (0021:249, last cut 0074), `cmd.execute_order(uuid)` (0007:759, last cut
-- 0074), `cmd.preview(uuid, text, jsonb)` (0008:387, last cut 0074) and
-- `public.client_rpc_entry_points()` (0018, last cut 0083) by SLICING them: `pg_temp.recut`
-- replaces hunks that must occur exactly once in the DEPLOYED body and refuses otherwise, and
-- assert (a) rebuilds each body from its captured pre-image with the declared hunks swapped back
-- and compares byte for byte. No ACL is re-declared for a sliced body; assert (h) proves each ACL
-- byte-identical to the one this file found.
--
-- IT IS A NO-OP WHERE NOTHING NEW IS SAID. A chain that never says DISMISS and never asks
-- world.crew_cost charges the same wages to the ducat: `crew_wages` is the tick's own expression
-- moved into a function, and assert (b) recomputes the old expression from the knobs and demands
-- equality on both rations, then (f) settles a REAL voyage-day and demands the WAGES row equal the
-- figure world.crew_cost served for that crew before she sailed.
--
-- EVERYTHING THAT MUST MOVE TOGETHER MOVES HERE. A verb with no parser row is unreachable; a
-- parser row with no dispatch arm is an order that fails at execution; a served cost with a
-- second arithmetic in the tick is 0017:50-55's scar. So the sum, the tick's slice, the verb, the
-- read, the grammar and the entry point land in this one transaction.
--
-- ── WHAT DOES NOT MOVE ──────────────────────────────────────────────────────────────────────────
--   * cmd.do_hire. Its price, its pool draw-down and its four refusals are untouched — dismissing
--     is a new verb, not a negative hire.
--   * Short rations. The x1.5 rule is still the tick's to decide (v_short); crew_wages only
--     spells the multiplication, and world.crew_cost serves BOTH figures so no screen has to guess
--     which one the day will charge.
--   * The wage knob on world.snapshot().config. Still served; a rate is a fact of the world.
--
-- Depends ONLY on: 0007 (do_hire, ships.crew, ports.crew_pool, emit_event), 0008 (parse,
--                  verb_schema, preview, execute_order), 0027/0047/0059 (the deployed
--                  voyage.settle), 0050 (cmd.refuse / cmd.figures), 0018/0083
--                  (client_rpc_entry_points), 0004 (current_player_id, credit, ledger, events).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. The slice tool: replace hunks that must occur exactly once, else refuse (0047 §0) ────────
-- A pg_temp function dies with the session and never enters the deployed catalogue, so every
-- migration that slices carries its own copy — docs/DEV_LOG.md D25.
create or replace function pg_temp.recut(p_fn regprocedure, p_drop boolean, variadic p_edits text[])
returns void
language plpgsql
as $fn$
declare
  v_def text := pg_get_functiondef(p_fn);
  v_i   int := 1;
  v_n   int;
begin
  while v_i < array_length(p_edits, 1) loop
    v_n := (length(v_def) - length(replace(v_def, p_edits[v_i], ''))) / length(p_edits[v_i]);
    if v_n <> 1 then
      raise exception '0086 slice: hunk % of % occurs % time(s) in %, expected exactly 1 — the deployed body is not what this migration was generated against.',
        (v_i + 1) / 2, (array_length(p_edits, 1)) / 2, v_n, p_fn;
    end if;
    v_def := replace(v_def, p_edits[v_i], p_edits[v_i + 1]);
    v_i := v_i + 2;
  end loop;
  if p_drop then
    execute format('drop function %s', p_fn::text);
  end if;
  execute v_def;
end $fn$;

-- ── PRE-IMAGES, captured before the first statement moves anything ─────────────────────────────
create temporary table defs_before_0086 as
  select fn,
         pg_get_functiondef(fn::regprocedure) as def,
         (select p.proacl::text from pg_proc p where p.oid = fn::regprocedure) as acl
    from unnest(array[
      'voyage.settle(uuid, timestamptz)',
      'cmd.parse(uuid, uuid, text)',
      'cmd.verb_schema()',
      'cmd.execute_order(uuid)',
      'cmd.preview(uuid, text, jsonb)',
      'public.client_rpc_entry_points()']) as fn;

-- ── 1. THE ONE SUM ─────────────────────────────────────────────────────────────────────────────
-- The tick's own expression (0027:300-302), moved into a function so a second reader can ask it.
-- bigint, rounded HERE, once: voyage.settle assigned the numeric product into a bigint variable,
-- and that assignment cast rounds half away from zero exactly as round() does — so the number the
-- Inn quotes and the number the day charges are the same number, not two roundings of one.
create or replace function public.crew_wages(p_crew int, p_short boolean)
returns bigint
language plpgsql
stable
set search_path = public, pg_temp
as $cw$
begin
  if p_crew is null or p_crew < 0 then
    raise exception 'crew_wages: a crew count is zero or more (got %)', p_crew;
  end if;
  return round(p_crew * public.wc_num('wage_per_crew_day')
               * (case when p_short then public.wc_num('short_rations_wage_mult') else 1 end))::bigint;
end $cw$;

comment on function public.crew_wages(int, boolean) is
  '0086: THE one sum of a voyage-day''s wages for a crew of N — full rations or short. '
  'voyage.settle charges it and world.crew_cost quotes it, so what the Inn prints before hiring '
  'is what the day at sea charges, by construction.';

revoke all on function public.crew_wages(int, boolean) from public, anon, authenticated;

-- ── 2. THE TICK READS THE ONE SUM — one hunk, nothing else ─────────────────────────────────────
select pg_temp.recut('voyage.settle(uuid, timestamptz)'::regprocedure, false,
  $s0$    select coalesce(sum(sh.crew), 0) * public.wc_num('wage_per_crew_day')
           * (case when v_short then public.wc_num('short_rations_wage_mult') else 1 end)
      into v_wages from public.ships sh where sh.fleet_id = p_fleet;$s0$,
  $s1$    -- 0086: THE ONE SUM. public.crew_wages is what the Inn quotes for any crew count, so the
    -- figure a player reads before hiring is the figure this day charges — by construction.
    select public.crew_wages(coalesce(sum(sh.crew), 0)::int, v_short)
      into v_wages from public.ships sh where sh.fleet_id = p_fleet;$s1$);

-- ── 3. THE VERB ────────────────────────────────────────────────────────────────────────────────
create or replace function cmd.do_dismiss(p_fleet uuid, p_args jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $dd$
declare
  f       public.fleets%rowtype;
  v_count int := (p_args->>'count')::int;
  v_spare int;
  v_left  int;
  v_after int;
  r       record;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.status <> 'DOCKED' then
    perform cmd.refuse('E_NOT_DOCKED', format('%s is %s and crew are let go in port only', f.name, f.status));
  end if;
  if v_count is null or v_count <= 0 then
    raise exception 'E_PARSE: DISMISS needs a positive number of crew' using errcode = 'P0001';
  end if;

  -- WHAT MAY GO. Every hull keeps the complement it needs to sail — crew_required, the figure
  -- E_CREW_SHORT gates SAIL on (0007:371) — and only the crew above it can be let go. Folded PER
  -- HULL: a hull over its complement does not lend its surplus to a hull under it.
  select coalesce(sum(greatest(0, s.crew - c.crew_required)), 0)::int into v_spare
    from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.fleet_id = p_fleet;
  if v_count > v_spare then
    perform cmd.refuse('E_CREW_REQUIRED', 'the ships need the rest of the crew to sail',
      cmd.figures(v_spare, v_count, 'crew'));
  end if;

  -- The mirror of do_hire's fill: take from the hulls with the most to spare first, never below
  -- any hull's complement. Ordered, so two runs on one fleet take from the same hulls.
  v_left := v_count;
  for r in select s.id, (s.crew - c.crew_required)::int as spare
             from public.ships s join public.ship_classes c on c.id = s.class_id
            where s.fleet_id = p_fleet and s.crew > c.crew_required
            order by spare desc, s.is_flagship asc, s.name asc, s.id asc loop
    exit when v_left <= 0;
    update public.ships set crew = crew - least(v_left, r.spare) where id = r.id;
    v_left := v_left - least(v_left, r.spare);
  end loop;

  -- BACK ON THE QUAY. ports.crew_pool is the one count of who can be hired in a city and
  -- cmd.do_hire draws it down (0007:689); the men a fleet lets go join it again — for anyone.
  update public.ports set crew_pool = crew_pool + v_count where id = f.port_id;

  select coalesce(sum(crew), 0)::int into v_after from public.ships where fleet_id = p_fleet;

  -- NO REFUND, AND NO MONEY MOVES: the hire fee was the price of the day they signed, and their
  -- wages simply stop being counted tomorrow. The event is the record.
  perform public.emit_event(f.player_id, 'DISMISSED', jsonb_build_object(
    'fleet', f.name, 'count', v_count, 'crew', v_after));

  return jsonb_build_object('dismissed', v_count, 'crew', v_after,
                            'wages_per_day', public.crew_wages(v_after, false));
end $dd$;

comment on function cmd.do_dismiss(uuid, jsonb) is
  '0086: DISMISS <count> — let crew go, in port only, never below any hull''s crew_required, '
  'back onto the port''s crew_pool, no refund. Writes a DISMISSED event. The mirror of do_hire, '
  'and a separate verb rather than a negative hire because the two have different prices: one '
  'costs ducats, the other costs nothing.';

revoke all on function cmd.do_dismiss(uuid, jsonb) from public, anon, authenticated;

-- ── 4. THE SERVED READ ─────────────────────────────────────────────────────────────────────────
create or replace function world.crew_cost(p_fleet uuid, p_crew int default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $cc$
declare
  v_player uuid := public.current_player_id();
  v_now    int;
  v_crew   int;
begin
  if v_player is null then
    raise exception 'E_NO_PLAYER: there is no house signed in' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.fleets where id = p_fleet and player_id = v_player) then
    raise exception 'E_NOT_YOURS: that is not your fleet' using errcode = 'P0001';
  end if;
  if p_crew is not null and p_crew < 0 then
    raise exception 'E_PARSE: a crew count is zero or more' using errcode = 'P0001';
  end if;
  select coalesce(sum(crew), 0)::int into v_now from public.ships where fleet_id = p_fleet;
  v_crew := coalesce(p_crew, v_now);
  -- Both rations, so the screen never has to guess which one a day at sea will charge.
  return jsonb_build_object(
    'crew', v_crew,
    'per_day', public.crew_wages(v_crew, false),
    'per_day_short_rations', public.crew_wages(v_crew, true));
end $cc$;

comment on function world.crew_cost(uuid, int) is
  '0086: what a crew of N aboard this fleet costs per voyage-day at sea — {crew, per_day, '
  'per_day_short_rations}, from public.crew_wages, the sum voyage.settle charges. N null means '
  'the crew aboard now. The Inn reads it as its stepper moves; the client multiplies nothing.';

grant execute on function world.crew_cost(uuid, int) to authenticated;

-- ── 5. ONE MORE WORD ───────────────────────────────────────────────────────────────────────────
-- DISMISS parses EXACTLY as HIRE does — a number of crew, an optional leading fleet — because it
-- is the same sentence in the other direction, so the branch is folded into HIRE's rather than
-- written beside it (0070 §5's reasoning for STORE/TAKE).
select pg_temp.recut('cmd.parse(uuid, uuid, text)'::regprocedure, false,
  $g0$  if v_verb not in ('SAIL','BUY','SELL','PROVISION','HIRE','REPAIR','MAKE','STORE','TAKE','BUILD','FIT','UNFIT','CANCEL','CLEAR') then$g0$,
  $g1$  if v_verb not in ('SAIL','BUY','SELL','PROVISION','HIRE','DISMISS','REPAIR','MAKE','STORE','TAKE','BUILD','FIT','UNFIT','CANCEL','CLEAR') then$g1$,
  $g2$  if v_verb in ('SAIL','PROVISION','HIRE','REPAIR') and n >= i then$g2$,
  $g3$  if v_verb in ('SAIL','PROVISION','HIRE','DISMISS','REPAIR') and n >= i then$g3$,
  $g4$  elsif v_verb = 'HIRE' then
    while i <= n and cmd.parse_number(t[i]) is null loop i := i + 1; end loop;
    if i > n then
      raise exception 'E_PARSE: HIRE needs a number of crew' using errcode = 'P0001';
    end if;$g4$,
  $g5$  elsif v_verb in ('HIRE', 'DISMISS') then
    -- 0086: DISMISS reads exactly as HIRE does — a number of crew — the same sentence in the
    -- other direction, so one branch reads both.
    while i <= n and cmd.parse_number(t[i]) is null loop i := i + 1; end loop;
    if i > n then
      raise exception 'E_PARSE: % needs a number of crew', v_verb using errcode = 'P0001';
    end if;$g5$);

select pg_temp.recut('cmd.verb_schema()'::regprocedure, false,
  $v0$     "note":"A port holds only so many idle men. Once they are taken, the rest want two and a half times the wage."},$v0$,
  $v1$     "note":"A port holds only so many idle men. Once they are taken, the rest want two and a half times the wage."},
    {"verb":"DISMISS","args":[
       {"name":"count","type":"number","required":true},
       {"name":"fleet","type":"fleet","required":false}],
     "help":"Let crew go, here in port.",
     "note":"Never below the crew the ships need to sail. Nothing is refunded; their wages stop."},$v1$);

select pg_temp.recut('cmd.execute_order(uuid)'::regprocedure, false,
  $e0$               when 'HIRE'      then cmd.do_hire(o.fleet_id, o.args)$e0$,
  $e1$               when 'HIRE'      then cmd.do_hire(o.fleet_id, o.args)
               when 'DISMISS'   then cmd.do_dismiss(o.fleet_id, o.args)$e1$);

select pg_temp.recut('cmd.preview(uuid, text, jsonb)'::regprocedure, false,
  $p0$               when 'HIRE'      then cmd.do_hire((v_parsed->>'fleet_id')::uuid, v_parsed->'args')$p0$,
  $p1$               when 'HIRE'      then cmd.do_hire((v_parsed->>'fleet_id')::uuid, v_parsed->'args')
               when 'DISMISS'   then cmd.do_dismiss((v_parsed->>'fleet_id')::uuid, v_parsed->'args')$p1$);

-- The server-side mirror of src/lib/rpc/catalog.ts (README §3): a read the client is meant to
-- call is named here, so client_executable_writers() and the catalogue spec agree on the doors.
select pg_temp.recut('public.client_rpc_entry_points()'::regprocedure, false,
  $c0$      ('world',       'reach',               'uuid'),$c0$,
  $c1$      ('world',       'reach',               'uuid'),
      -- 0086: what a crew of N costs per day at sea — the Inn's caption, for any count.
      ('world',       'crew_cost',           'uuid, int'),$c1$);

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_probe     constant uuid := '00000000-0086-4000-8000-000000000086';
  v_old       text;
  v_new       text;
  v_back      text;
  v_rate      numeric := public.wc_num('wage_per_crew_day');
  v_mult      numeric := public.wc_num('short_rations_wage_mult');
  v_n         int;
  v_hire      int;
  v_dismiss   int;
  v_schema    jsonb;
  v_player    uuid;
  v_fleet     uuid;
  v_port      uuid;
  v_dest      text;
  v_path      jsonb;
  v_voyage    uuid;
  v_crew0     int;
  v_crew1     int;
  v_crew2     int;
  v_req       int;
  v_max       int;
  v_spare     int;
  v_pool0     int;
  v_pool1     int;
  v_purse0    bigint;
  v_purse1    bigint;
  v_purse2    bigint;
  v_quote     bigint;
  v_wages     bigint;
  v_cost      jsonb;
  v_prev      bigint;
  v_res       jsonb;
  v_pv        jsonb;
  v_msg       text;
  v_detail    text;
  v_figs      jsonb;
  v_short     boolean;
  v_bad       boolean := false;
  v_class2_id uuid;
  v_req2      int;
  v_dur2      numeric;
  v_ship2     uuid;
  v_flag      uuid;
  f_hull      boolean := false;
  f_parity    boolean := true;
  f_sum       boolean := false;
  f_grammar   boolean := false;
  f_hire      boolean := false;
  f_dismiss   boolean := false;
  f_guard     boolean := false;
  f_sea       boolean := false;
  f_tick      boolean := false;
  f_monotone  boolean := true;
  f_posture   boolean := false;
begin
  -- (a) PARITY BY CONSTRUCTION, verified: swapping every declared hunk back OUT of each live body
  --     must reproduce its pre-image to the character — nothing moved but the hunks.
  select def into v_old from defs_before_0086 where fn = 'voyage.settle(uuid, timestamptz)';
  v_new  := pg_get_functiondef('voyage.settle(uuid, timestamptz)'::regprocedure);
  v_back := replace(v_new,
    $s1$    -- 0086: THE ONE SUM. public.crew_wages is what the Inn quotes for any crew count, so the
    -- figure a player reads before hiring is the figure this day charges — by construction.
    select public.crew_wages(coalesce(sum(sh.crew), 0)::int, v_short)
      into v_wages from public.ships sh where sh.fleet_id = p_fleet;$s1$,
    $s0$    select coalesce(sum(sh.crew), 0) * public.wc_num('wage_per_crew_day')
           * (case when v_short then public.wc_num('short_rations_wage_mult') else 1 end)
      into v_wages from public.ships sh where sh.fleet_id = p_fleet;$s0$);
  if v_back <> v_old or v_new = v_old then f_parity := false; end if;

  select def into v_old from defs_before_0086 where fn = 'cmd.parse(uuid, uuid, text)';
  v_new  := pg_get_functiondef('cmd.parse(uuid, uuid, text)'::regprocedure);
  v_back := replace(v_new,
    $g1$  if v_verb not in ('SAIL','BUY','SELL','PROVISION','HIRE','DISMISS','REPAIR','MAKE','STORE','TAKE','BUILD','FIT','UNFIT','CANCEL','CLEAR') then$g1$,
    $g0$  if v_verb not in ('SAIL','BUY','SELL','PROVISION','HIRE','REPAIR','MAKE','STORE','TAKE','BUILD','FIT','UNFIT','CANCEL','CLEAR') then$g0$);
  v_back := replace(v_back,
    $g3$  if v_verb in ('SAIL','PROVISION','HIRE','DISMISS','REPAIR') and n >= i then$g3$,
    $g2$  if v_verb in ('SAIL','PROVISION','HIRE','REPAIR') and n >= i then$g2$);
  v_back := replace(v_back,
    $g5$  elsif v_verb in ('HIRE', 'DISMISS') then
    -- 0086: DISMISS reads exactly as HIRE does — a number of crew — the same sentence in the
    -- other direction, so one branch reads both.
    while i <= n and cmd.parse_number(t[i]) is null loop i := i + 1; end loop;
    if i > n then
      raise exception 'E_PARSE: % needs a number of crew', v_verb using errcode = 'P0001';
    end if;$g5$,
    $g4$  elsif v_verb = 'HIRE' then
    while i <= n and cmd.parse_number(t[i]) is null loop i := i + 1; end loop;
    if i > n then
      raise exception 'E_PARSE: HIRE needs a number of crew' using errcode = 'P0001';
    end if;$g4$);
  if v_back <> v_old or v_new = v_old then f_parity := false; end if;

  select def into v_old from defs_before_0086 where fn = 'cmd.verb_schema()';
  v_new  := pg_get_functiondef('cmd.verb_schema()'::regprocedure);
  v_back := replace(v_new,
    $v1$     "note":"A port holds only so many idle men. Once they are taken, the rest want two and a half times the wage."},
    {"verb":"DISMISS","args":[
       {"name":"count","type":"number","required":true},
       {"name":"fleet","type":"fleet","required":false}],
     "help":"Let crew go, here in port.",
     "note":"Never below the crew the ships need to sail. Nothing is refunded; their wages stop."},$v1$,
    $v0$     "note":"A port holds only so many idle men. Once they are taken, the rest want two and a half times the wage."},$v0$);
  if v_back <> v_old or v_new = v_old then f_parity := false; end if;

  select def into v_old from defs_before_0086 where fn = 'cmd.execute_order(uuid)';
  v_new  := pg_get_functiondef('cmd.execute_order(uuid)'::regprocedure);
  v_back := replace(v_new,
    $e1$               when 'HIRE'      then cmd.do_hire(o.fleet_id, o.args)
               when 'DISMISS'   then cmd.do_dismiss(o.fleet_id, o.args)$e1$,
    $e0$               when 'HIRE'      then cmd.do_hire(o.fleet_id, o.args)$e0$);
  if v_back <> v_old or v_new = v_old then f_parity := false; end if;

  select def into v_old from defs_before_0086 where fn = 'cmd.preview(uuid, text, jsonb)';
  v_new  := pg_get_functiondef('cmd.preview(uuid, text, jsonb)'::regprocedure);
  v_back := replace(v_new,
    $p1$               when 'HIRE'      then cmd.do_hire((v_parsed->>'fleet_id')::uuid, v_parsed->'args')
               when 'DISMISS'   then cmd.do_dismiss((v_parsed->>'fleet_id')::uuid, v_parsed->'args')$p1$,
    $p0$               when 'HIRE'      then cmd.do_hire((v_parsed->>'fleet_id')::uuid, v_parsed->'args')$p0$);
  if v_back <> v_old or v_new = v_old then f_parity := false; end if;

  select def into v_old from defs_before_0086 where fn = 'public.client_rpc_entry_points()';
  v_new  := pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure);
  v_back := replace(v_new,
    $c1$      ('world',       'reach',               'uuid'),
      -- 0086: what a crew of N costs per day at sea — the Inn's caption, for any count.
      ('world',       'crew_cost',           'uuid, int'),$c1$,
    $c0$      ('world',       'reach',               'uuid'),$c0$);
  if v_back <> v_old or v_new = v_old then f_parity := false; end if;

  if not f_parity then
    raise exception '0086 self-assert FAIL: a sliced body is not its pre-image with exactly the declared hunks made — something besides the hunks moved, or nothing moved at all';
  end if;

  -- (b) THE ONE SUM IS THE TICK'S OWN ARITHMETIC. The live settle reads crew_wages exactly once
  --     and no longer spells the knob itself; crew_wages equals the old expression recomputed
  --     from the knobs on both rations; a negative count bites.
  v_new := pg_get_functiondef('voyage.settle(uuid, timestamptz)'::regprocedure);
  v_n   := (length(v_new) - length(replace(v_new, 'public.crew_wages(', ''))) / length('public.crew_wages(');
  begin
    perform public.crew_wages(-1, false);
  exception when others then
    v_bad := true;
  end;
  if v_n = 1
     and position('wage_per_crew_day' in v_new) = 0
     and public.crew_wages(0, false) = 0
     and public.crew_wages(37, false) = round(37 * v_rate)::bigint
     and public.crew_wages(37, true)  = round(37 * v_rate * v_mult)::bigint
     and public.crew_wages(37, true)  > public.crew_wages(37, false)
     and v_bad then
    f_sum := true;
  end if;
  if not f_sum then
    raise exception '0086 self-assert FAIL: the tick reads crew_wages % time(s) (expected 1) and still names the knob at position %; or crew_wages(37) = % / % on full/short rations against the knobs'' % / % — the quote and the charge are two sums',
      v_n, position('wage_per_crew_day' in v_new), public.crew_wages(37, false), public.crew_wages(37, true),
      round(37 * v_rate), round(37 * v_rate * v_mult);
  end if;

  -- (c) THE GRAMMAR SPEAKS THE WORD, right after HIRE, with HIRE's own two arguments.
  v_schema := cmd.verb_schema();
  select min(ord) filter (where e->>'verb' = 'HIRE'), min(ord) filter (where e->>'verb' = 'DISMISS')
    into v_hire, v_dismiss
    from jsonb_array_elements(v_schema) with ordinality t(e, ord);
  if v_hire is not null and v_dismiss = v_hire + 1
     and (select e->'args' from jsonb_array_elements(v_schema) e where e->>'verb' = 'DISMISS')
         = (select e->'args' from jsonb_array_elements(v_schema) e where e->>'verb' = 'HIRE')
     and jsonb_array_length(v_schema) = 15 then
    f_grammar := true;
  end if;
  if not f_grammar then
    raise exception '0086 self-assert FAIL: cmd.verb_schema serves HIRE at % and DISMISS at % of % verbs, or their argument lists differ — the word is not served, or not where the strip reads it', v_hire, v_dismiss, jsonb_array_length(v_schema);
  end if;

  -- ── THE PROBE. A house of its own, rolled back with everything it touched. ───────────────────
  begin
    v_player := public.new_house(c_probe, 'Casa da Maruja', 'PRT');
    perform cmd.assume_identity(c_probe);
    select id, port_id into v_fleet, v_port from public.fleets where player_id = v_player;

    -- THE PROBE OWNS ITS PRECONDITIONS (README §3): a full purse, a quay with men on it, stores
    -- for a long passage so the settled day is on FULL rations.
    update public.players set ducats = 8000 where id = v_player;
    update public.ports set crew_pool = 50 where id = v_port;
    update public.ships s
       set water_t = round(s.crew * public.wc_num('water_per_crew_day') * 45, 3),
           food_t  = round(s.crew * public.wc_num('food_per_crew_day') * 45, 3)
     where s.fleet_id = v_fleet;

    select coalesce(sum(s.crew), 0), coalesce(sum(c.crew_required), 0), coalesce(sum(c.crew_max), 0)
      into v_crew0, v_req, v_max
      from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = v_fleet;
    if v_crew0 <> v_req or v_max - v_req < 4 then
      raise exception '0086 self-assert FAIL: the probe''s new hull carries % crew against a complement of % and % berths — the probe needs a hull at its complement with at least 4 berths free, and this one is not it', v_crew0, v_req, v_max;
    end if;
    select ducats into v_purse0 from public.players where id = v_player;
    select crew_pool into v_pool0 from public.ports where id = v_port;

    -- (d) THE READ, FOR ANY COUNT: null means the crew aboard now; the per-day figure is the one
    --     sum; it never falls as the count rises; and the short-rations figure sits above it.
    v_cost := world.crew_cost(v_fleet);
    if (v_cost->>'crew')::int <> v_crew0 or (v_cost->>'per_day')::bigint <> public.crew_wages(v_crew0, false) then
      raise exception '0086 self-assert FAIL: world.crew_cost(fleet) reads % for a hull carrying % crew — it is not the crew aboard priced by the one sum', v_cost, v_crew0;
    end if;
    v_prev := null;
    for v_n in 0..v_max loop
      v_cost := world.crew_cost(v_fleet, v_n);
      if (v_cost->>'crew')::int <> v_n
         or (v_cost->>'per_day')::bigint <> public.crew_wages(v_n, false)
         or (v_cost->>'per_day_short_rations')::bigint < (v_cost->>'per_day')::bigint
         or (v_prev is not null and (v_cost->>'per_day')::bigint < v_prev) then
        f_monotone := false;
      end if;
      v_prev := (v_cost->>'per_day')::bigint;
    end loop;
    if not f_monotone then
      raise exception '0086 self-assert FAIL: world.crew_cost(fleet, n) is not the one sum for every n in 0..%, or it fell as n rose, or short rations quoted less than full — the caption would move the wrong way under the stepper', v_max;
    end if;

    -- (e) HIRE THREE, through the one door. Crew up by three, one HIRED event, the purse down by
    --     three at the pool rate (the pool is 50, so nobody is urgent), the pool down by three.
    v_res := cmd.issue(v_fleet, 'HIRE 3', null, null);
    select coalesce(sum(crew), 0) into v_crew1 from public.ships where fleet_id = v_fleet;
    select ducats into v_purse1 from public.players where id = v_player;
    select crew_pool into v_pool1 from public.ports where id = v_port;
    if coalesce(v_res->>'ok', 'false') = 'true'
       and v_crew1 = v_crew0 + 3
       and v_purse1 = v_purse0 - round(3 * public.wc_num('hire_crew_rate'))::bigint
       and v_pool1 = v_pool0 - 3
       and (select count(*) from public.events where player_id = v_player and kind = 'HIRED'
             and (payload->>'count')::int = 3) = 1 then
      f_hire := true;
    end if;
    if not f_hire then
      raise exception '0086 self-assert FAIL: HIRE 3 through cmd.issue answered [%: %], crew % -> %, purse % -> %, pool % -> % — the verb this file mirrors does not behave as its header says',
        v_res->>'error_code', v_res->>'error_message', v_crew0, v_crew1, v_purse0, v_purse1, v_pool0, v_pool1;
    end if;

    -- (f-i) THE DRY RUN MOVES NOTHING: previewing DISMISS 1 answers the estimate and leaves the
    --       crew, the pool and the event count exactly where they were.
    v_pv := cmd.preview(v_fleet, 'DISMISS 1', null);
    if coalesce(v_pv->>'ok', 'false') <> 'true'
       or (v_pv->'estimate'->>'dismissed')::int <> 1
       or (v_pv->'estimate'->>'crew')::int <> v_crew1 - 1
       or (v_pv->'estimate'->>'wages_per_day')::bigint <> public.crew_wages(v_crew1 - 1, false)
       or (select coalesce(sum(crew), 0) from public.ships where fleet_id = v_fleet) <> v_crew1
       or (select crew_pool from public.ports where id = v_port) <> v_pool1
       or (select count(*) from public.events where player_id = v_player and kind = 'DISMISSED') <> 0 then
      raise exception '0086 self-assert FAIL: cmd.preview of DISMISS 1 answered % — or it MOVED the crew, the pool or the record, which a dry run may never do', v_pv;
    end if;

    -- (f) DISMISS ONE, through the one door. Crew down by one, one DISMISSED event, the purse
    --     UNCHANGED (no refund), the pool up by one.
    v_res := cmd.issue(v_fleet, 'DISMISS 1', null, null);
    select coalesce(sum(crew), 0) into v_crew2 from public.ships where fleet_id = v_fleet;
    select ducats into v_purse2 from public.players where id = v_player;
    if coalesce(v_res->>'ok', 'false') = 'true'
       and v_crew2 = v_crew1 - 1
       and v_purse2 = v_purse1
       and (select crew_pool from public.ports where id = v_port) = v_pool1 + 1
       and (select count(*) from public.ledger where player_id = v_player and kind not in ('FOUNDING', 'HIRE')) = 0
       and (select count(*) from public.events where player_id = v_player and kind = 'DISMISSED'
             and (payload->>'count')::int = 1 and (payload->>'crew')::int = v_crew2) = 1 then
      f_dismiss := true;
    end if;
    if not f_dismiss then
      raise exception '0086 self-assert FAIL: DISMISS 1 through cmd.issue answered [%: %], crew % -> %, purse % -> % (a refund would show here), pool % -> % — the verb does not do what its header says',
        v_res->>'error_code', v_res->>'error_message', v_crew1, v_crew2, v_purse1, v_purse2, v_pool1, (select crew_pool from public.ports where id = v_port);
    end if;

    -- (g) THE GUARD BITES: one more than the surplus is refused E_CREW_REQUIRED, with the two
    --     figures (spare / asked, in crew) riding in DETAIL as cmd.figures writes them — off the
    --     verb directly, and the same code back through the one door; nothing moved either time.
    select coalesce(sum(greatest(0, s.crew - c.crew_required)), 0)::int into v_spare
      from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = v_fleet;
    if v_spare <> 2 then
      raise exception '0086 self-assert FAIL: after HIRE 3 and DISMISS 1 the surplus above the complement is %, not 2 — the fold is wrong before the guard is even tried', v_spare;
    end if;
    begin
      perform cmd.do_dismiss(v_fleet, jsonb_build_object('count', v_spare + 1));
      v_msg := '(no refusal)';
    exception when others then
      get stacked diagnostics v_msg = message_text, v_detail = pg_exception_detail;
    end;
    v_figs := cmd.refusal_caught(v_msg, v_detail)->'figures';
    v_res  := cmd.issue(v_fleet, format('DISMISS %s', v_spare + 1), null, null);
    if v_msg like 'E_CREW_REQUIRED:%'
       and (v_figs->>'have')::numeric = v_spare and (v_figs->>'need')::numeric = v_spare + 1 and v_figs->>'unit' = 'crew'
       and coalesce(v_res->>'ok', 'true') = 'false' and v_res->>'error_code' = 'E_CREW_REQUIRED'
       and (select coalesce(sum(crew), 0) from public.ships where fleet_id = v_fleet) = v_crew2 then
      f_guard := true;
    end if;
    if not f_guard then
      raise exception '0086 self-assert FAIL: dismissing one more than the surplus answered "%" with figures % off the verb and [%] through cmd.issue — the complement guard did not bite, or bit with the wrong numbers',
        v_msg, v_figs, v_res->>'error_code';
    end if;

    -- (g2) PER HULL, NOT PER FLEET — and this needs TWO hulls, because on one hull the two folds
    --      are the same number and a per-fleet fold would pass (g) unseen: scripts/db/
    --      breaktest-0086.mjs found exactly that on its first run. A second hull is put aboard
    --      two ABOVE its complement and the flagship set one BELOW hers (a probe precondition,
    --      set directly and rolled back). Per hull the surplus is 2; per fleet it nets to 1. So
    --      DISMISS 2 must be ACCEPTED, must take both from the second hull and none from the
    --      flagship, and DISMISS 1 more must then be refused with figures 0 / 1.
    select c.id, c.crew_required, c.durability into v_class2_id, v_req2, v_dur2
      from public.ship_classes c join public.ships s on s.class_id = c.id
     where s.fleet_id = v_fleet and s.is_flagship
     limit 1;   -- the flagship's own class: one row by construction, a fleet has one flagship
    insert into public.ships (player_id, fleet_id, class_id, name, durability, crew,
                              water_t, food_t, store_ratio, is_flagship)
    values (v_player, v_fleet, v_class2_id, 'Probe Segunda', v_dur2, v_req2 + 2,
            2.400, 1.800, public.wc_num('store_ratio_default'), false)
    returning id into v_ship2;
    select id into v_flag from public.ships where fleet_id = v_fleet and is_flagship;
    update public.ships s set crew = c.crew_required - 1
      from public.ship_classes c where c.id = s.class_id and s.id = v_flag;
    begin
      perform cmd.do_dismiss(v_fleet, jsonb_build_object('count', 2));
      v_msg := '(accepted)';
    exception when others then
      v_msg := sqlerrm;
    end;
    v_detail := null;
    begin
      perform cmd.do_dismiss(v_fleet, jsonb_build_object('count', 1));
      v_detail := '(accepted)';
    exception when others then
      get stacked diagnostics v_detail = message_text;
    end;
    if v_msg = '(accepted)'
       and (select s.crew from public.ships s where s.id = v_ship2) = v_req2
       and (select s.crew - c.crew_required from public.ships s join public.ship_classes c on c.id = s.class_id where s.id = v_flag) = -1
       and v_detail like 'E_CREW_REQUIRED:%' then
      f_hull := true;
    end if;
    if not f_hull then
      raise exception '0086 self-assert FAIL: with one hull 2 above its complement and the flagship 1 below hers, DISMISS 2 answered "%" (second hull now %, flagship %) and DISMISS 1 more answered "%" — the surplus is being folded per FLEET, letting an over-crewed hull lend to an under-crewed one',
        v_msg, (select s.crew from public.ships s where s.id = v_ship2),
        (select s.crew from public.ships s where s.id = v_flag), coalesce(v_detail, '(nothing)');
    end if;
    -- Put the probe back as (g) left it — one hull, two above its complement — for the passage.
    delete from public.ships where id = v_ship2;
    update public.ships s set crew = c.crew_required + 2
      from public.ship_classes c where c.id = s.class_id and s.id = v_flag;

    -- (h) AT SEA THE VERB REFUSES, AND THE TICK CHARGES THE QUOTE. The quote is taken BEFORE she
    --     sails, for the crew she sails with; a real voyage-day is then settled and the WAGES
    --     row must equal it to the ducat. The passage is Lisbon's roads to Funchal's — open
    --     Atlantic, two served roadsteads — so the probe proposes no course of its own devising.
    -- The refused DISMISS above is a FAILED order at the head of the queue, and a failed order
    -- HALTS the queue (DESIGN F.3) — a SAIL issued behind it would sit pending with the fleet
    -- still docked. The first apply of this file found exactly that. Clear it first.
    perform cmd.clear(v_fleet, false);
    v_quote := (world.crew_cost(v_fleet)->>'per_day')::bigint;
    select p.code into v_dest from public.ports p where p.name = 'Funchal';
    select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon),
                             jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
      into v_path
      from public.sea_reaches a, public.sea_reaches b
     where a.port_id = v_port and b.code = v_dest;
    v_res := cmd.issue(v_fleet, format('SAIL TO %s', v_dest), null, v_path);
    if coalesce(v_res->>'ok', 'false') <> 'true' or v_res->'order'->>'status' <> 'done'
       or (select status from public.fleets where id = v_fleet) <> 'SAILING' then
      raise exception '0086 self-assert FAIL: the probe''s passage to % answered [%: %] with the order % and the fleet % — she did not sail, so there is no settled day to measure the tick on',
        v_dest, v_res->>'error_code', v_res->>'error_message', v_res->'order'->>'status',
        (select status from public.fleets where id = v_fleet);
    end if;
    select id into v_voyage from public.voyages where fleet_id = v_fleet and status = 'SAILING';

    begin
      perform cmd.do_dismiss(v_fleet, jsonb_build_object('count', 1));
      v_msg := '(no refusal)';
    exception when others then
      v_msg := sqlerrm;
    end;
    if v_msg like 'E_NOT_DOCKED:%' then f_sea := true; end if;
    if not f_sea then
      raise exception '0086 self-assert FAIL: a fleet at sea was allowed to let crew go ("%") — crew leave in port only', v_msg;
    end if;

    perform voyage.settle(v_fleet, voyage.day_ends_at(v_voyage, 1));
    select -l.ducats_delta into v_wages
      from public.ledger l where l.player_id = v_player and l.kind = 'WAGES'
     order by l.created_at desc, l.id desc limit 1;
    -- The day's own row: voyage.settle writes {short_rations, wages, …} to public.voyage_events
    -- per settled day (0027:399) — the VOYAGE_REPORT event comes only with the arrival.
    select (e.payload->>'short_rations')::boolean into v_short
      from public.voyage_events e where e.voyage_id = v_voyage and e.day_index = 1;
    if v_wages is not null and v_wages = v_quote and v_wages > 0 and v_short = false
       and (select (e.payload->>'wages')::bigint from public.voyage_events e
             where e.voyage_id = v_voyage and e.day_index = 1) = v_quote
       and (select last_settled_day from public.voyages where id = v_voyage) = 1 then
      f_tick := true;
    end if;
    if not f_tick then
      raise exception '0086 self-assert FAIL: the settled day charged % in wages (short rations: %) against the % world.crew_cost quoted before she sailed — the quote and the tick are not one sum',
        coalesce(v_wages::text, '(no WAGES row)'), coalesce(v_short::text, '(no day row)'), v_quote;
    end if;

    raise exception '__PROBE_ROLLBACK_0086__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK_0086__' then raise; end if;
  end;

  if (select count(*) from public.players where auth_uid = c_probe) <> 0 then
    raise exception '0086 self-assert FAIL: the probe house survived its subtransaction';
  end if;

  -- (i) POSTURE, both halves, plus every sliced ACL byte-identical to what this file found.
  if not has_function_privilege('anon', 'cmd.do_dismiss(uuid, jsonb)', 'execute')
     and not has_function_privilege('authenticated', 'cmd.do_dismiss(uuid, jsonb)', 'execute')
     and not has_function_privilege('anon', 'public.crew_wages(int, boolean)', 'execute')
     and not has_function_privilege('authenticated', 'public.crew_wages(int, boolean)', 'execute')
     and has_function_privilege('authenticated', 'world.crew_cost(uuid, int)', 'execute')
     and not has_function_privilege('anon', 'world.crew_cost(uuid, int)', 'execute')
     and (select count(*) from public.client_rpc_entry_points() e
           where e.schema_name = 'world' and e.function_name = 'crew_cost' and e.fn is not null) = 1
     and (select count(*) from public.client_rpc_entry_points() e where e.fn is null) = 0
     and (select count(*) from public.client_write_grants()) = 0
     and (select count(*) from public.client_executable_writers()) = 0
     and (select count(*) from public.caller_evaluated_functions()) = 0
     and not exists (select 1 from defs_before_0086 d
                      where d.acl is distinct from
                            (select p.proacl::text from pg_proc p where p.oid = d.fn::regprocedure)) then
    f_posture := true;
  end if;
  if not f_posture then
    raise exception '0086 self-assert FAIL: a door moved — do_dismiss or crew_wages reachable by a client, crew_cost not reachable by authenticated (or reachable by anon), the entry point unregistered, a sliced ACL changed, or the grant family off zero (write grants %, executable writers %, caller gaps %)',
      (select count(*) from public.client_write_grants()), (select count(*) from public.client_executable_writers()),
      (select count(*) from public.caller_evaluated_functions());
  end if;

  raise notice '0086 self-assert ok: CREW ARE LET GO IN PORT, AND THE WAGE IS ONE SUM. Six bodies were sliced, not retyped — swapping the hunks back reproduces every pre-image to the character, and no ACL moved. voyage.settle now reads public.crew_wages (once; the knob is no longer spelled in the tick) and crew_wages recomputes the tick''s old expression to the ducat on both rations (37 crew: % full, % short). The grammar serves 15 verbs with DISMISS right after HIRE, carrying HIRE''s own arguments. On a probe house: HIRE 3 raised the crew by 3, took % d. and 3 men off the quay and wrote one HIRED; a dry run of DISMISS 1 moved nothing; DISMISS 1 lowered the crew by 1, put 1 man back on the quay, moved NO money and wrote one DISMISSED; one more than the 2 spare was refused E_CREW_REQUIRED with figures 2 / 3 crew, off the verb and through cmd.issue alike; on TWO hulls the surplus folded per hull — a second hull 2 above its complement beside a flagship 1 below hers let exactly 2 go, both from the second hull, and refused a third; at sea the verb refused E_NOT_DOCKED; and a REAL settled day at sea charged exactly the % d. world.crew_cost quoted for that crew before she sailed. world.crew_cost(fleet, n) is the one sum for every n in 0..berths and never falls as n rises. Probe rolled back; 0 client write grants, 0 executable writers',
    public.crew_wages(37, false), public.crew_wages(37, true), round(3 * public.wc_num('hire_crew_rate')), v_quote;
end $$;

drop table defs_before_0086;
