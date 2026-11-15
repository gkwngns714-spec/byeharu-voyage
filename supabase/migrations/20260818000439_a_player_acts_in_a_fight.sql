-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0439 - A PLAYER ACTS IN A FIGHT  (the battle screen's action bar presses: Broadside, Chain Shot, Rake, Grapeshot, Brace, Patch, Run, Pay;
--        slice 2 of docs/design/tick-combat.md)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-15: "i want the combat system resemble something like rs3": abilities on cooldowns fed by a bar that builds as you fight,
--   pressed by the player. Genre mechanics only. No PvP, ever. (docs/design/tick-combat.md sections 3, 4, 7, 9.2: THE CONTRACT)
--
-- WHAT WAS ALREADY TRUE (0435, 0436): a RAID or an ATTACK is one timeline (battles.ticks), computed by public.tick_fight from the sheet and run by
--   public.tick_battle_run (THE one (re)run). Every draw is keyed by (tick, hull, what): a re-run with something new from tick T is the same fight
--   before T. Each side's commander is the AI (FIGHT / FLEE / PAY, from the stance kept); a player could only watch.
-- WHAT THIS FILE ADDS:
--   A1. THE DOOR: cmd.battle_act(p_battle, p_fleet, p_code, p_tick) -> {ok, battle, tick, k, resolves_at, ticks}; the core is
--       public.battle_act_for. Refusals: E_NO_HOUSE, E_BAD_CODE (not one of the eight; Pay by any but the ship set upon; Run by a ship that
--       joined: a run is her whole side's), E_NO_BATTLE, E_NOT_YOUR_BATTLE (not her fleet, or her fleet not in it), E_BATTLE_OVER (closed, an
--       old round battle, or the tick past the timeline's last), E_PAST_TICK (p_tick under the server's tick now), E_TOO_SOON (one act per fleet
--       every tick_gcd ticks of the server's clock: the spam cap), E_COOLDOWN (that ability's cooldown in the current timeline; or her guns
--       silent while she runs; or her guns cannot bear at that tick), E_NO_FURY ("Fury 20 / 50").
--       It LANDS at greatest(p_tick, the tick now + 1) (nothing a watcher has seen changes), moved on to her side's global cooldown (tick_gcd
--       after her commander's last ability, the AI's or a player's) if that is later; it is judged against THE CURRENT TIMELINE at that tick
--       (the cooldown, the Fury, a run); written to sheet.acts as {t, s, code, fleet, at}; the timeline re-run (k + 1; the end and every held
--       side's busy_until follow); and refused (rolled back) if the re-run did not use it at its tick.
--   A2. THE ENGINE (public.tick_fight, four hunks): p_opts.acts. At a tick where her side has an act, the commander uses it if it can (the
--       cooldown ready, the Fury, not running unless Brace or Patch, guns that bear for a volley, Pay only the side set upon); else, and at every
--       tick she leaves empty, the AI as before. Pay by an act ends the fight in a RANSOM (`paid`) at its tick, as Pay at the open does; Run is
--       the AI's Run (0432's raid chance, `a_flee`, or 0357's). Still pure: the acts are an argument.
--   A3. THE RE-RUN (public.tick_battle_run, one hunk) passes sheet.acts to the engine, so a join (0436) after an act keeps the act.
--   A4. public.client_rpc_entry_points (one hunk): cmd.battle_act.
-- NO PVP stays true: an act adds no side and no hull; the sides are whoever 0435/0436 let in.
-- LOAD: -- budget: no new rows; an act is one battles row update (sheet + timeline, ~2-5 KB TOASTed) and the fleets' busy_until (1-3 rows) when
--   the end moves, plus one engine run (~5 ms). At most one act a fleet every tick_gcd ticks (1.8 s), i.e. at most ~40 a fleet a fight; players
--   in fights are a handful at a time. No job, no cron, no table, no knob.
-- LOCKS: CREATE OR REPLACE x3 by hunks; CREATE FUNCTION x2. BUDGET: statement_timeout 45 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): revoke execute on cmd.battle_act from authenticated (the bar refuses; every battle is the AI's, as 0435).
-- SELF-ASSERT: every hunk once and reversing; grants, volatility, definer, search path, owner of the hunked functions unmoved; no other function
--   moved; the door open to signed-in players and registered, the core server-only; THE ENGINE on a fixed sheet: an act at tick 30 leaves every
--   event before 30 as it was and is used at 30; THE PROBE, rolled back (runs on every world: a battle written with a fixed sheet between a
--   player's fleet and a company's merchant): every refusal, a valid act at the next tick, k + 1, the past unchanged, the rate cap, the cooldown.
-- VERSION: 0439 = 0438 + 1 (0437 and 0438 are other queued branches; written on the chain to 0436, branch tick-combat + battle-join).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['public.tick_fight(uuid,jsonb,jsonb,jsonb)', 'public.tick_battle_run(uuid)', 'public.client_rpc_entry_points()'];
  c_new    constant text[] := array['public.battle_act_for(uuid,uuid,uuid,text,integer,timestamp with time zone)', 'cmd.battle_act(uuid,uuid,text,integer)'];
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  -- the engine check
  v_ha  jsonb;
  v_hb  jsonb;
  v_f1  jsonb;
  v_f2  jsonb;
  -- the probe
  c_u1  constant uuid := '00000000-0439-4000-8000-000000000001';
  c_u2  constant uuid := '00000000-0439-4000-8000-000000000002';
  c_bat constant uuid := '00000000-0439-4000-8000-0000000000b1';
  v_p1  uuid;
  v_p2  uuid;
  v_fa  uuid;
  v_fb  uuid;
  v_m   uuid;
  v_r   jsonb;
  v_old jsonb;
  v_new jsonb;
  v_k0  int;
  v_t   int;
  v_ns  int;
  v_codes text := '';
  v_note text := '';
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('cmd.battle_act(uuid,uuid,text,integer)') is not null then
    raise exception '0439 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.tick_battle_run(uuid)') is null or to_regprocedure('cmd.battle_join(uuid,uuid,text)') is null then
    raise exception '0439 refuses: 0435 (the tick engine) and 0436 (the join door) are not in this world';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));

  -- ── 2. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0439 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0439 values
  ('public.tick_fight(uuid,jsonb,jsonb,jsonb)', 1,
$h$  v_r      jsonb;
begin$h$,
$h$  v_r      jsonb;
  v_acts   text[];   -- 0439: a player's act per (side, tick), from p_opts.acts
  v_act    jsonb;
begin$h$),
  ('public.tick_fight(uuid,jsonb,jsonb,jsonb)', 2,
$h$  t_end := v_nw * c_w;
$h$,
$h$  t_end := v_nw * c_w;
  -- 0439: THE PLAYERS' ACTS (sheet.acts through public.tick_battle_run: [{t, s 0|1, code}]): her side's commander uses her ability at her tick if it can
  v_acts := array_fill(null::text, array[2 * (t_end + 1)]);
  for v_act in select z from jsonb_array_elements(case when jsonb_typeof(p_opts -> 'acts') = 'array' then p_opts -> 'acts' else '[]'::jsonb end) z loop
    continue when coalesce(v_act ->> 's', '') not in ('0', '1') or not (coalesce(v_act ->> 'code', '') = any (c_codes)) or coalesce(jsonb_typeof(v_act -> 't'), '') <> 'number';
    continue when (v_act ->> 't')::int < 0 or (v_act ->> 't')::int > t_end;
    v_acts[(v_act ->> 's')::int * (t_end + 1) + (v_act ->> 't')::int + 1] := v_act ->> 'code';
  end loop;
$h$),
  ('public.tick_fight(uuid,jsonb,jsonb,jsonb)', 3,
$h$        v_code := null;
        if v_ai[s] = 'FLEE' then$h$,
$h$        v_code := v_acts[(s - 1) * (t_end + 1) + t + 1];   -- 0439: her own act at this tick, used if her side can use it now; else the AI's choice
        if v_code is not null and not (
             s_ready[(s - 1) * 8 + array_position(c_codes, v_code)] <= t
             and s_fury[s] >= coalesce((v_ab -> v_code ->> 'cost')::numeric, 0)
             and (s_run[s] < t or v_code in ('BR', 'PT'))
             and (v_code not in ('BS', 'CH', 'RK', 'GR') or v_canfire)
             and (v_code <> 'PY' or s = 1)) then
          v_code := null;
        end if;
        if v_code is not null then
          null;
        elsif v_ai[s] = 'FLEE' then$h$),
  ('public.tick_fight(uuid,jsonb,jsonb,jsonb)', 4,
$h$        elsif v_code = 'RN' then
          s_run[s] := t + coalesce((v_a ->> 'for')::int, c_w);
        end if;$h$,
$h$        elsif v_code = 'RN' then
          s_run[s] := t + coalesce((v_a ->> 'for')::int, c_w);
        elsif v_code = 'PY' then
          v_outcome := 'RANSOM'; v_paid := true;   -- 0439: the side set upon pays by her act, now: the ransom, as Pay at the open
        end if;$h$),
  ('public.tick_battle_run(uuid)', 1,
$h$  if b.sheet ? 'a_flee' then
    v_opts := v_opts || jsonb_build_object('a_flee', b.sheet -> 'a_flee');
  end if;$h$,
$h$  if b.sheet ? 'a_flee' then
    v_opts := v_opts || jsonb_build_object('a_flee', b.sheet -> 'a_flee');
  end if;
  if jsonb_typeof(b.sheet -> 'acts') = 'array' then
    v_opts := v_opts || jsonb_build_object('acts', b.sheet -> 'acts');   -- 0439: the players' acts (cmd.battle_act), kept through every re-run
  end if;$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('cmd',         'battle_join',           'uuid, uuid, text'),
$h$,
$h$      ('cmd',         'battle_join',           'uuid, uuid, text'),
      -- 0439: her side's commander acts in a fight fought tick by tick (docs/design/tick-combat.md 9.2).
      ('cmd',         'battle_act',            'uuid, uuid, text, integer'),
$h$);

  for v_h in select h.fn from hunks_0439 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0439 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0439 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0439 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0439 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0439 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 3. THE NEW FUNCTIONS ──
  execute $f$
create function public.battle_act_for(p_player uuid, p_battle uuid, p_fleet uuid, p_code text, p_tick int, p_now timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0439 (docs/design/tick-combat.md 7, 9.2): HER SIDE'S COMMANDER ACTS, the one writer. Raises the refusals 'E_CODE: sentence' (cmd.refuse); the door
-- (cmd.battle_act) answers them as the envelope and rolls back. p_now null: the clock is read once the battle's row is held.
-- The act LANDS at greatest(p_tick, the tick now + 1), moved on to her side's global cooldown if that is later, and is judged against the CURRENT
-- timeline at that tick (the past is fixed by construction): the ability's cooldown, her side's Fury, a run in progress. It is written to sheet.acts
-- {t, s, code, fleet, at} and the timeline re-run (public.tick_battle_run: k + 1; the end and every held side's busy_until follow). If the re-run did
-- not use it at its tick (her guns could not bear), it is refused. One act a fleet every tick_gcd ticks of the server's clock (E_TOO_SOON).
-- Answers {ok, battle, tick (where it landed), k, resolves_at, ticks (the new timeline: the client swaps it in at the same tick)}.
declare
  c_codes constant text[] := array['BS', 'CH', 'RK', 'GR', 'BR', 'PT', 'RN', 'PY'];
  b       public.battles%rowtype;
  v_now   timestamptz;
  v_ms    numeric;
  v_gcd   int;
  v_ab    jsonb;
  v_ev    jsonb;
  v_acts  jsonb;
  v_side  text;
  v_how   text;
  v_s     int;
  v_tnow  int;
  v_t     int;
  v_tn    int;
  v_n     int;
  v_last  int;
  v_cd    int;
  v_fury  numeric;
  v_cost  numeric;
  v_tl    jsonb;
  v_until timestamptz;
  i       int;
begin
  if p_code is null or not (p_code = any (c_codes)) then
    perform cmd.refuse('E_BAD_CODE', 'an ability is BS, CH, RK, GR, BR, PT, RN or PY');
  end if;
  select * into b from public.battles where id = p_battle for update;
  if b.id is null or b.sheet is null or b.kind not in ('RAID', 'ATTACK') then
    perform cmd.refuse('E_NO_BATTLE', 'there is no such battle');
  end if;
  select bs.side, bs.how into v_side, v_how
    from public.battle_sides bs join public.fleets f on f.id = bs.fleet_id
   where bs.battle_id = p_battle and bs.fleet_id = p_fleet and f.player_id = p_player;
  if v_side is null then
    perform cmd.refuse('E_NOT_YOUR_BATTLE', 'no fleet of yours is in that battle');
  end if;
  v_now := coalesce(p_now, clock_timestamp());
  if b.status <> 'FIGHTING' or b.ticks is null or v_now >= b.resolves_at then
    perform cmd.refuse('E_BATTLE_OVER', 'that battle is over');
  end if;
  v_ms := public.wc_num('tick_ms');
  v_gcd := greatest(1, coalesce(public.wc_int('tick_gcd'), 3));
  v_ab := b.ticks -> 'ab';
  v_ev := coalesce(b.ticks -> 'e', '[]'::jsonb);
  v_n := (b.ticks ->> 'n')::int;
  v_tnow := greatest(0, floor(extract(epoch from v_now - b.started_at) * 1000 / v_ms)::int);
  if p_tick is null or p_tick < v_tnow then
    perform cmd.refuse('E_PAST_TICK', format('Tick %s / %s', coalesce(p_tick, -1), v_tnow));
  end if;
  v_s := case v_side when 'DEFENDER' then 0 else 1 end;
  if p_code = 'PY' and (v_s <> 0 or v_how <> 'OPENED') then
    perform cmd.refuse('E_BAD_CODE', 'only the ship set upon pays');
  end if;
  if p_code = 'RN' and v_how <> 'OPENED' then
    perform cmd.refuse('E_BAD_CODE', 'a run is her whole side''s: only a ship that began the fight may order it');
  end if;
  v_acts := case when jsonb_typeof(b.sheet -> 'acts') = 'array' then b.sheet -> 'acts' else '[]'::jsonb end;
  -- THE SPAM CAP: one act a fleet every tick_gcd ticks of the server's clock
  if exists (select 1 from jsonb_array_elements(v_acts) a where a ->> 'fleet' = p_fleet::text and (a ->> 'at')::int > v_tnow - v_gcd) then
    perform cmd.refuse('E_TOO_SOON', format('one act every %s ticks', v_gcd));
  end if;

  -- WHERE IT LANDS: the next tick at the earliest, then her side's global cooldown (her commander's last ability before it, and any act of her side near it)
  v_t := greatest(p_tick, v_tnow + 1, case when v_s = 1 then 2 else 0 end);   -- the side that closes first acts at tick 2 (0435)
  for i in 1 .. 8 loop
    select max((e ->> 0)::int) into v_last from jsonb_array_elements(v_ev) e
     where e ->> 2 = 'U' and (e ->> 1)::int = v_s and (e ->> 0)::int < v_t;
    v_tn := greatest(v_t, coalesce(v_last + v_gcd, v_t));
    select max((a ->> 't')::int) into v_last from jsonb_array_elements(v_acts) a
     where (a ->> 's')::int = v_s and (a ->> 't')::int > v_tn - v_gcd and (a ->> 't')::int < v_tn + v_gcd;
    v_tn := greatest(v_tn, coalesce(v_last + v_gcd, v_tn));
    exit when v_tn = v_t;
    v_t := v_tn;
  end loop;
  if v_t > v_n then
    perform cmd.refuse('E_BATTLE_OVER', format('the fight ends at tick %s', v_n));
  end if;

  -- JUDGED AGAINST THE CURRENT TIMELINE AT THAT TICK (every event before it is what the re-run will keep)
  v_cd := coalesce((v_ab -> p_code ->> 'cd')::int, 0);
  select max((e ->> 0)::int) into v_last from jsonb_array_elements(v_ev) e
   where e ->> 2 = 'U' and (e ->> 1)::int = v_s and e ->> 3 = p_code and (e ->> 0)::int < v_t;
  if v_last is not null and v_last + v_cd > v_t then
    perform cmd.refuse('E_COOLDOWN', format('Ready %s / %s', v_t - v_last, v_cd));
  end if;
  select max((e ->> 0)::int) into v_last from jsonb_array_elements(v_ev) e
   where e ->> 2 = 'U' and (e ->> 1)::int = v_s and e ->> 3 = 'RN' and (e ->> 0)::int < v_t;
  if p_code not in ('BR', 'PT') and v_last is not null and v_last + coalesce((v_ab -> 'RN' ->> 'for')::int, 20) >= v_t then
    perform cmd.refuse('E_COOLDOWN', 'her guns are silent while she runs');
  end if;
  select (e ->> 4)::numeric into v_fury from jsonb_array_elements(v_ev) with ordinality q(e, o)
   where e ->> 2 = 'U' and (e ->> 1)::int = v_s and (e ->> 0)::int < v_t order by o desc limit 1;
  v_fury := coalesce(v_fury, 0);
  v_cost := coalesce((v_ab -> p_code ->> 'cost')::numeric, 0);
  if v_fury < v_cost then
    perform cmd.refuse('E_NO_FURY', format('Fury %s / %s', round(v_fury), round(v_cost)));
  end if;

  -- THE ACT, AND THE RE-RUN
  v_acts := v_acts || jsonb_build_array(jsonb_build_object('t', v_t, 's', v_s, 'code', p_code, 'fleet', p_fleet, 'at', v_tnow));
  update public.battles set sheet = jsonb_set(sheet, '{acts}', v_acts) where id = p_battle;
  v_tl := public.tick_battle_run(p_battle);
  if not exists (select 1 from jsonb_array_elements(v_tl -> 'e') e
                  where (e ->> 0)::int = v_t and (e ->> 1)::int = v_s and e ->> 2 = 'U' and e ->> 3 = p_code) then
    perform cmd.refuse('E_COOLDOWN', 'her guns cannot bear now');
  end if;
  select bt.resolves_at into v_until from public.battles bt where bt.id = p_battle;
  return jsonb_build_object('ok', true, 'battle', p_battle, 'tick', v_t, 'k', (v_tl ->> 'k')::int, 'resolves_at', v_until, 'ticks', v_tl);
end
$body$;
$f$;
  revoke all on function public.battle_act_for(uuid, uuid, uuid, text, integer, timestamptz) from public, anon, authenticated;

  execute $f$
create function cmd.battle_act(p_battle uuid, p_fleet uuid, p_code text, p_tick integer)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0439 (docs/design/tick-combat.md 9.2): THE ACTION BAR'S DOOR. A fleet of the signed-in company in a battle fought tick by tick orders her side's
-- commander to use an ability (BS CH RK GR BR PT RN PY) at a tick (the next at the earliest). The core is public.battle_act_for; a refusal is the
-- envelope, as every cmd door, and nothing is written. {ok, battle, tick, k, resolves_at, ticks} or E_NO_HOUSE, E_BAD_CODE, E_NO_BATTLE,
-- E_NOT_YOUR_BATTLE, E_BATTLE_OVER, E_PAST_TICK, E_TOO_SOON, E_COOLDOWN, E_NO_FURY.
declare
  v_player uuid := public.current_player_id();
  v_det    text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE', 'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    return public.battle_act_for(v_player, p_battle, p_fleet, p_code, p_tick, null);
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end
$body$;
$f$;
  revoke all on function cmd.battle_act(uuid, uuid, text, integer) from public, anon;
  grant execute on function cmd.battle_act(uuid, uuid, text, integer) to authenticated;
  comment on function cmd.battle_act(uuid, uuid, text, integer) is
    '0439: the door of public.battle_act_for for the signed-in company: her side''s commander uses an ability at a tick (a refusal is the envelope, as every cmd door).';

  -- ── 4. SELF-ASSERT: the catalog, the door ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_new) u(q)))) <> v_fn_before then
    raise exception '0439 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0439 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked function moved';
  end if;
  if has_function_privilege('anon', 'public.battle_act_for(uuid,uuid,uuid,text,integer,timestamp with time zone)'::regprocedure, 'execute')
     or has_function_privilege('authenticated', 'public.battle_act_for(uuid,uuid,uuid,text,integer,timestamp with time zone)'::regprocedure, 'execute')
     or exists (select 1 from public.client_rpc_entry_points() e where e.fn = 'public.battle_act_for(uuid,uuid,uuid,text,integer,timestamp with time zone)'::regprocedure)
     or not has_function_privilege('authenticated', 'cmd.battle_act(uuid,uuid,text,integer)'::regprocedure, 'execute')
     or has_function_privilege('anon', 'cmd.battle_act(uuid,uuid,text,integer)'::regprocedure, 'execute')
     or not exists (select 1 from public.client_rpc_entry_points() e
                     where e.schema_name = 'cmd' and e.function_name = 'battle_act' and e.arg_types = 'uuid, uuid, text, integer' and e.fn is not null)
     or exists (select 1 from public.client_executable_writers()) then
    raise exception '0439 self-assert FAIL: the door is not open to a signed-in player and registered, or the core is open to clients';
  end if;

  -- ── 5. THE ENGINE on a fixed sheet: an act at tick 30 is used there and moves nothing before it ──
  v_ha := jsonb_build_array(jsonb_build_object('id', '00000000-0439-4000-8000-0000000000a1', 'name', 'a1', 'tier', 2, 'hull', 100000, 'maxd', 100000, 'crew', 40,
            'attack', 6, 'accuracy', 50, 'reach', 20, 'armour', 0, 'sighting', 0, 'boarder_pct', 0));
  v_hb := jsonb_build_array(jsonb_build_object('id', '00000000-0439-4000-8000-0000000000a2', 'name', 'b1', 'tier', 2, 'hull', 100000, 'maxd', 100000, 'crew', 60,
            'attack', 6, 'accuracy', 50, 'reach', 20, 'armour', 0, 'sighting', 10, 'boarder_pct', 0));
  v_f1 := public.tick_fight(c_bat, v_ha, v_hb, '{}'::jsonb);
  v_f2 := public.tick_fight(c_bat, v_ha, v_hb, '{"acts": [{"t": 30, "s": 0, "code": "BR"}]}'::jsonb);
  if (v_f1 ->> 'n')::int < 40 then
    raise exception '0439 self-assert FAIL: the fixed sheet ended at tick % (it is built to run to the boarding)', v_f1 ->> 'n';
  end if;
  if (select coalesce(jsonb_agg(e order by o), '[]'::jsonb) from jsonb_array_elements(v_f1 -> 'e') with ordinality q(e, o) where (e ->> 0)::int < 30)::text
     <> (select coalesce(jsonb_agg(e order by o), '[]'::jsonb) from jsonb_array_elements(v_f2 -> 'e') with ordinality q(e, o) where (e ->> 0)::int < 30)::text then
    raise exception '0439 self-assert FAIL: an act at tick 30 changed the fight before it';
  end if;
  if not exists (select 1 from jsonb_array_elements(v_f2 -> 'e') e where e ->> 0 = '30' and e ->> 1 = '0' and e ->> 2 = 'U' and e ->> 3 = 'BR')
     or exists (select 1 from jsonb_array_elements(v_f1 -> 'e') e where e ->> 2 = 'U' and e ->> 3 = 'BR' and (e ->> 1)::int = 0) then
    raise exception '0439 self-assert FAIL: the act at tick 30 was not used there (or the AI braced unhurt)';
  end if;

  -- ── 6. THE PROBE, rolled back by a raised sentinel: a battle written with the fixed sheet, a player's fleet against a company's merchant ──
  begin
    select nf.fleet_id into v_m from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id order by nf.fleet_id limit 1;
    if v_m is null then
      raise exception '0439 self-assert FAIL: no company merchant in this world to probe on';
    end if;
    v_p1 := public.new_house(c_u1, 'Casa Uno 0439', 'PRT', 'LIS', 'Uno 0439', 'galion', 'Uno 0439', null, false);
    v_p2 := public.new_house(c_u2, 'Casa Dos 0439', 'PRT', 'LIS', 'Dos 0439', 'galion', 'Dos 0439', null, false);
    select f.id into v_fa from public.fleets f where f.player_id = v_p1;
    select f.id into v_fb from public.fleets f where f.player_id = v_p2;
    insert into public.battles (id, kind, site, started_at, resolves_at, status, sheet, round_seconds, rounds_done, next_round_at)
    values (c_bat, 'ATTACK', '{"lat": 0, "lon": 0}'::jsonb, clock_timestamp() - interval '6.3 seconds', clock_timestamp() + interval '60 seconds', 'FIGHTING',
            jsonb_build_object('a', v_ha, 'b', v_hb), 12, 0, clock_timestamp() + interval '60 seconds');
    insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at, how)
    values (c_bat, v_fa, 'ATTACKER', clock_timestamp(), clock_timestamp(), 'OPENED'), (c_bat, v_m, 'DEFENDER', clock_timestamp(), clock_timestamp(), 'OPENED');
    v_old := public.tick_battle_run(c_bat);
    v_k0 := (v_old ->> 'k')::int;
    v_ns := (select count(*) from public.battle_sides s where s.battle_id = c_bat);

    perform cmd.assume_identity(c_u1);
    v_r := cmd.battle_act(c_bat, v_fa, 'ZZ', 12);
    if v_r ->> 'error_code' is distinct from 'E_BAD_CODE' then raise exception '0439 self-assert FAIL: a bad code: %', v_r; end if;
    v_r := cmd.battle_act(gen_random_uuid(), v_fa, 'BR', 12);
    if v_r ->> 'error_code' is distinct from 'E_NO_BATTLE' then raise exception '0439 self-assert FAIL: no battle: %', v_r; end if;
    v_r := cmd.battle_act(c_bat, v_m, 'BR', 12);
    if v_r ->> 'error_code' is distinct from 'E_NOT_YOUR_BATTLE' then raise exception '0439 self-assert FAIL: not her fleet: %', v_r; end if;
    perform cmd.assume_identity(c_u2);
    v_r := cmd.battle_act(c_bat, v_fb, 'BR', 12);
    if v_r ->> 'error_code' is distinct from 'E_NOT_YOUR_BATTLE' then raise exception '0439 self-assert FAIL: her fleet is not in it: %', v_r; end if;
    perform cmd.assume_identity(c_u1);
    v_r := cmd.battle_act(c_bat, v_fa, 'BR', 3);
    if v_r ->> 'error_code' is distinct from 'E_PAST_TICK' then raise exception '0439 self-assert FAIL: a past tick: %', v_r; end if;
    v_r := cmd.battle_act(c_bat, v_fa, 'BR', 9999);
    if v_r ->> 'error_code' is distinct from 'E_BATTLE_OVER' then raise exception '0439 self-assert FAIL: a tick past the end: %', v_r; end if;
    v_r := cmd.battle_act(c_bat, v_fa, 'PY', 12);
    if v_r ->> 'error_code' is distinct from 'E_BAD_CODE' then raise exception '0439 self-assert FAIL: the side that closed paid: %', v_r; end if;
    v_r := cmd.battle_act(c_bat, v_fa, 'GR', 12);
    if v_r ->> 'error_code' is distinct from 'E_NO_FURY' then raise exception '0439 self-assert FAIL: Grapeshot without the Fury: %', v_r; end if;
    v_codes := 'E_BAD_CODE E_NO_BATTLE E_NOT_YOUR_BATTLE E_PAST_TICK E_BATTLE_OVER E_NO_FURY (' || (v_r ->> 'error_message') || ')';
    if (select coalesce((b.ticks ->> 'k')::int, -1) from public.battles b where b.id = c_bat) <> v_k0 then
      raise exception '0439 self-assert FAIL: a refused act re-ran the timeline';
    end if;

    -- a valid act: Brace (the AI never braces unhurt), at the next tick
    v_r := cmd.battle_act(c_bat, v_fa, 'BR', 12);
    if not coalesce((v_r ->> 'ok')::boolean, false) or (v_r ->> 'tick')::int < 12 or (v_r ->> 'k')::int <> v_k0 + 1 then
      raise exception '0439 self-assert FAIL: a valid act was not taken: %', v_r - 'ticks';
    end if;
    v_t := (v_r ->> 'tick')::int;
    select b.ticks into v_new from public.battles b where b.id = c_bat;
    if (select coalesce(jsonb_agg(e order by o), '[]'::jsonb) from jsonb_array_elements(v_old -> 'e') with ordinality q(e, o) where (e ->> 0)::int < v_t)::text
       <> (select coalesce(jsonb_agg(e order by o), '[]'::jsonb) from jsonb_array_elements(v_new -> 'e') with ordinality q(e, o) where (e ->> 0)::int < v_t)::text
       or not exists (select 1 from jsonb_array_elements(v_new -> 'e') e where (e ->> 0)::int = v_t and e ->> 1 = '1' and e ->> 2 = 'U' and e ->> 3 = 'BR')
       or (v_new ->> 'k')::int <> v_k0 + 1 or (v_r -> 'ticks' ->> 'k')::int <> v_k0 + 1 then
      raise exception '0439 self-assert FAIL: the act changed the past, or is not in the timeline at tick %', v_t;
    end if;
    -- the spam cap, then (three ticks on) the cooldown
    v_r := cmd.battle_act(c_bat, v_fa, 'CH', v_t + 20);
    if v_r ->> 'error_code' is distinct from 'E_TOO_SOON' then raise exception '0439 self-assert FAIL: a second act at once: %', v_r - 'ticks'; end if;
    update public.battles b set started_at = b.started_at - interval '2.4 seconds', resolves_at = b.resolves_at - interval '2.4 seconds' where b.id = c_bat;
    v_r := cmd.battle_act(c_bat, v_fa, 'BR', v_t + 10);
    if v_r ->> 'error_code' is distinct from 'E_COOLDOWN' then raise exception '0439 self-assert FAIL: Brace again inside its cooldown: %', v_r - 'ticks'; end if;
    if (select count(*) from public.battle_sides s where s.battle_id = c_bat) <> v_ns then
      raise exception '0439 self-assert FAIL: an act added a side';
    end if;
    v_note := format('refused %s; Brace at tick %s (asked 12), k %s -> %s, the past the same; E_TOO_SOON; E_COOLDOWN "%s"', v_codes, v_t, v_k0, v_new ->> 'k', v_r ->> 'error_message');
    raise exception sqlstate 'BV439';
  exception when sqlstate 'BV439' then null;
  end;
  if v_note = '' then
    raise exception '0439 self-assert FAIL: the probe did not run to its end';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0439 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0439 self-assert ok: A PLAYER ACTS IN A FIGHT. % hunks once each and reversing; no other function moved; the door open and registered, the core server-only; the engine: an act at tick 30 used there, nothing before it moved. Probe (rolled back): %; % ms.',
    (select count(*) from hunks_0439), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0439;
end $m$;
