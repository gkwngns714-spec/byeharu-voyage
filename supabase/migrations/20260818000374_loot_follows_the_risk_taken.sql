-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0374 - LOOT FOLLOWS THE RISK TAKEN: what an attack earns counts for the share of her own hull the attacker lost in that fight. DARK (attacks are not lit)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
-- WHY (owner row 324, "make everything work. open them if everything is built and is workable"; docs/COMBAT_LOG.md 3.6 and R11, "lighting attacks is free gold").
--   The attack sim on what really sails (scripts/ops/harness/attacks/sim.mjs, 300 fights a cell, the real engine on real hulls; docs/dev-log/2026-11-13-attacks-ready.md):
--     * the old unarmed cargo ship: ANY fleet with a gun is paid in 9 fights of 10 and loses no hull at all (one Kobaya, 70,000 d.: 90 %);
--     * the armed navire, with all her hands or with none: two galleons, or one line ship of 0366, are paid in 100 fights of 100 and lose under 2 % of their hull (about 180 d. of repair)
--       for 15,000 to 60,000 d. a battle, at level 1 and at level 5, and with a navy ship coming up for round 3;
--     * a Nau is paid in 8 of 10 and loses a tenth of her hull; a small fleet is beaten 8 times in 10.
--   So a strong fleet had a risk-free income up to loot_per_company_day (240,000 d.), and every fleet had one from an unarmed ship. Nothing a beaten attacker loses is gold.
-- WHAT. One rule, in the one place gold leaves a ship for a player (public.loot_take):
--     what is aboard counts for  least(1, greatest(loot_risk_floor, the share of her own hull the attacker lost in the fight / loot_risk_full))
--   and public.loot_due takes its share of that under the caps it always had (loot_share or ransom_share, loot_per_ship, what is left of loot_per_company_day, what is aboard).
--   loot_risk_full 0.075: a fight that cost the attacker 7.5 % of her hull (half of fight_raider_break, where she would have broken off) pays the whole share; a fight that cost her 2 % pays
--   about a quarter; a fight that cost her nothing pays nothing. So an unarmed ship yields nothing, a walkover yields little, and the fleet that fights close to its own limit takes the most.
--   loot_risk_floor 0: the least a won fight pays, as a share. THE OWNER'S LEVERS: loot_risk_full 0 turns the rule off (the loot of 0327, exactly); a floor of 1 does the same.
--   The risk is read from the battle's own kept result (battles.result.hull: b_start and b are the side that closed), which public.battle_resolve writes before it calls
--   public.attack_close: nothing is recomputed and no dice are thrown.
-- NEW: public.loot_risk(jsonb) STABLE, server-only: the factor of one fight's answer. Two knobs. RE-CUT: public.loot_take, one line, and public.battle_sheet_freeze, one line (each OLD text once in its live body, reversing).
--   AND THE ONE READING OF "MAY ATTACKS BE LIT": public.attack_ready() STABLE, server-only: {ready, lived, checks{...}, cargo{...}, why[]}. The lighting file (0375) refuses unless it
--   says ready, and scripts/ops/harness/attacks/before-light.sql prints it on production first, so the guard and the check before it cannot disagree. Its checks:
--     loot_rule_on      this file's rule is on (loot_risk_full above 0, loot_risk_floor under 1)           clock_sane   battle_round_seconds is 30 to 120
--   and, in a world where the crown's cargo ships sail (`lived`: public.cargo_ships has a row; a world built from this chain has none and nothing there to protect):
--     regard_lit        an attack costs standing (0319)                 npc_levels_lit, levels_written   crown hulls fight at their level (0344), written on 9 cargo hulls in 10
--     convoy_armed_lit  the cargo ship is the armed navire (0328)       navy_lit                         her country answers (0331, 0333)
--     cargo_safe        the UNARMED cargo ships at sea are at most a tenth of the cargo ships at sea (the old hull is taken by any fleet with a gun: the sim).
--   public.loot_due, public.attack_close, public.battle_resolve and the engine are not touched; the regard, the hands lost, WANTED and the wreck are as they were.
-- AND A FAULT OF 0357 FOUND BY DRIVING THE BATTLE IN A BROWSER (tests/battle.live.spec.ts, 2026-11-13): A CALLED SHIP ALREADY THERE WAS PUT ON THE SHEET TWICE.
--   A navy ship lying in the harbour nearest the battle when she is called has arrives_at = the press. public.battle_sheet_freeze froze her on the sheet at the open (every side
--   with arrives_at <= now), with no mark of her fleet; public.battle_advance then found a CALLED ship "not on the sheet" (it looks for her fleet's mark) and added her again for
--   round 1. She fought as two ships: the card said "Ships 3, Crew 320" for a cargo ship and ONE galleon, and the side set upon fired a galleon's broadside twice.
--   THE FIX, one line of public.battle_sheet_freeze: a CALLED ship is never frozen at the open. public.battle_advance, the one place a called ship joins, puts her on the sheet
--   for the first round she is there for (round 1 if she is there already), once, marked. An ESCORT (0333) is frozen at the open as before: battle_advance never adds one.
--   Proof 74 CALLED_ONCE: red on the old line (3 hulls for 2 ships), green on the new.
-- DARK: attack_enabled is false on prod and this file does not write it. public.loot_take is reached only at the close of a battle a company opened, so nothing changes for anyone
--   until attacks are lit (0375). No player-visible change now:
-- news: none
-- ROLLBACK (forward, owner only): update public.world_config set value = '0'::jsonb where key = 'loot_risk_full' is the rule off at once. The file reversed is
--   scripts/ops/harness/attacks/rollback-0374.sql (the hunk swapped back, the function and the two knobs dropped).
-- SELF-ASSERT: ONE DO block, statement_timeout 30 s, lock_timeout 5 s. The catalog (the function STABLE and server-only, the hunk once and reversing, public.loot_due's body unmoved),
--   and arithmetic on crafted answers (no hull lost 0, 3.75 % a half, 7.5 % and more the whole, no fight 1, the rule off 1, the floor). No game step, no table counted.
--   THE REAL BATTLES ARE PROOF 74's (scripts/db/proofs/74_loot_follows_the_risk.sql), under any world's dice.
-- VERSION: 0374, cut on the bodies at head 0367. 0369 to 0373 are the lights that go before it (ship stores, fleet room, raid orders, NPC levels, regard): none names public.loot_take.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0     timestamptz := clock_timestamp();
  v_def0   text;
  v_def    text;
  v_due0   text;
  v_n      int;
  v_frz0   text;
  c_frz    constant text := 'public.battle_sheet_freeze(uuid,timestamp with time zone)';
  c_frz_old constant text := $o$            where bs.battle_id = p_battle and bs.arrives_at <= p_now
$o$;
  c_frz_new constant text := $n$            where bs.battle_id = p_battle and bs.arrives_at <= p_now
              and bs.how <> 'CALLED'   -- 0374: a called ship joins through public.battle_advance alone (round 1 if she is there already), once and marked: frozen here too she fought as two
$n$;
  c_fn     constant text := 'public.loot_take(uuid,uuid,text,timestamp with time zone)';
  c_old    constant text := $o$  v_take := public.loot_due(p_outcome, v_left, public.loot_today(p_player, p_now));
$o$;
  c_new    constant text := $n$  -- 0374: LOOT FOLLOWS THE RISK TAKEN (public.loot_risk): what is aboard counts for the share of her own hull the attacker lost in this fight, whole at loot_risk_full.
  -- Read from the kept result of the battle this ship was set upon in (public.battle_resolve writes it before the close). The caps are public.loot_due's, as they were.
  v_take := public.loot_due(p_outcome,
                            floor(v_left * public.loot_risk((select b.result from public.battle_sides bs join public.battles b on b.id = bs.battle_id
                                                               where bs.fleet_id = p_fleet and bs.side = 'DEFENDER' and bs.how = 'OPENED' and b.kind = 'ATTACK'
                                                               order by b.started_at desc, b.id desc limit 1)))::bigint,
                            public.loot_today(p_player, p_now));
$n$;
  r        record;
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from unnest(array[c_fn, c_frz, 'public.battle_advance(uuid,timestamp with time zone)', 'public.loot_due(text,bigint,bigint)', 'public.attack_close(uuid,jsonb,timestamp with time zone)',
                                        'public.battle_resolve(uuid,timestamp with time zone)', 'public.wc_num(text)']) f where to_regprocedure(f) is null)
     or to_regclass('public.battles') is null or to_regclass('public.battle_sides') is null then
    raise exception '0374 refuses: the attack (0327) and its battles (0323, 0357) are not in this world';
  end if;
  if to_regprocedure('public.attack_ready()') is not null or to_regprocedure('public.loot_risk(jsonb)') is not null or exists (select 1 from public.world_config c where c.key in ('loot_risk_full', 'loot_risk_floor')) then
    raise exception '0374 refuses: it has been applied once';
  end if;
  v_def0 := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  v_n := (length(v_def0) - length(replace(v_def0, c_old, ''))) / length(c_old);
  if v_n is distinct from 1 then
    raise exception '0374 refuses: the line it re-cuts occurs % time(s) in public.loot_take, not once: the body is not the one this file was written against', v_n;
  end if;
  if position('b.result' in v_def0) > 0 then
    raise exception '0374 refuses: public.loot_take already reads a battle''s result';
  end if;
  v_due0 := md5(replace(pg_get_functiondef('public.loot_due(text,bigint,bigint)'::regprocedure), E'\r', ''));
  v_frz0 := replace(pg_get_functiondef(c_frz::regprocedure), E'\r', '');
  v_n := (length(v_frz0) - length(replace(v_frz0, c_frz_old, ''))) / length(c_frz_old);
  if v_n is distinct from 1 or position('bs.how <> ''CALLED''' in v_frz0) > 0 then
    raise exception '0374 refuses: the line it re-cuts occurs % time(s) in public.battle_sheet_freeze, not once (or the fix is already there)', v_n;
  end if;

  -- ── 1. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('loot_risk_full', '0.075'::jsonb,
     '0374: LOOT FOLLOWS THE RISK TAKEN. The share of her own hull an attacker must lose in a fight for its loot to be whole (public.loot_risk); under it the loot is in proportion, and a fight that cost her no hull pays loot_risk_floor. 0.075 is half of fight_raider_break, where she would break off. 0 turns the rule off: the loot of 0327. Owner only.'),
    ('loot_risk_floor', '0'::jsonb,
     '0374: the least share of the loot a won fight pays, whatever it cost the attacker (public.loot_risk). 0: a fight that cost her no hull pays nothing, so an unarmed ship yields nothing. 1 turns the rule off. Owner only.');

  -- ── 2. THE FACTOR OF ONE FIGHT ──
  execute $f$
create function public.loot_risk(p_fight jsonb)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0374: LOOT FOLLOWS THE RISK TAKEN. The share of the loot a fight's answer (public.fight_sides, as public.battle_resolve keeps it in battles.result) has earned: the share of her own
  -- hull the side that closed lost (hull.b_start - hull.b over hull.b_start), over loot_risk_full, never under loot_risk_floor and never over 1. No fight to read, a side with no hull,
  -- or the rule off (loot_risk_full 0 or less): 1, the loot of 0327. Read by public.loot_take alone. A pure reading of its argument and two knobs.
  select case when p_fight is null or public.wc_num('loot_risk_full') <= 0 or coalesce((p_fight #>> '{hull,b_start}')::numeric, 0) <= 0 then 1::numeric
              else least(1::numeric, greatest(least(1::numeric, greatest(0::numeric, public.wc_num('loot_risk_floor'))),
                     greatest(0::numeric, (p_fight #>> '{hull,b_start}')::numeric - coalesce((p_fight #>> '{hull,b}')::numeric, (p_fight #>> '{hull,b_start}')::numeric))
                       / (p_fight #>> '{hull,b_start}')::numeric / public.wc_num('loot_risk_full'))) end
$body$;
$f$;
  comment on function public.loot_risk(jsonb) is
    '0374: loot follows the risk taken: the share of the loot one fight''s answer has earned, from the share of her own hull the attacker lost, whole at loot_risk_full, never under loot_risk_floor. 1 with no fight or the rule off. Read by public.loot_take. Server-only.';
  revoke all on function public.loot_risk(jsonb) from public, anon, authenticated;

  -- ── 2b. MAY ATTACKS BE LIT: the one reading (0375's guard, and before-light.sql on production) ──
  execute $f$
create function public.attack_ready()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0374: MAY attack_enabled BE LIT. One reading for the lighting file's guard and for the prod check before it. `lived`: the crown's cargo ships sail in this world
  -- (public.cargo_ships has a row). The cargo ships are a few hundred rows; nothing that grows is read.
  with c as (
    select f.status in ('SAILING', 'ANCHORED') and x.laid_up_at is null as at_sea, k.attack > 0 as guns,
           exists (select 1 from public.ship_xp e where e.ship_id = sh.id) as levelled
      from public.cargo_ships x
      join public.fleets f on f.id = x.fleet_id
      join public.ships sh on sh.fleet_id = x.fleet_id and sh.is_flagship
      join public.ship_classes k on k.id = sh.class_id),
  n as (
    select count(*) as ships, count(*) filter (where c.at_sea) as at_sea, count(*) filter (where c.at_sea and not c.guns) as unarmed_at_sea,
           count(*) filter (where not c.guns) as unarmed, count(*) filter (where c.levelled) as levelled
      from c),
  k as (
    select n.*, n.ships > 0 as lived,
           coalesce(public.wc_num('loot_risk_full') > 0 and public.wc_num('loot_risk_floor') < 1, false) as loot_rule_on,
           coalesce(public.wc_num('battle_round_seconds') between 30 and 120, false) as clock_sane,
           public.regard_on() as regard_lit,
           public.wc('npc_ship_level_enabled') = 'true'::jsonb as npc_levels_lit,
           n.levelled >= 0.9 * n.ships as levels_written,
           public.cargo_armed_on() as convoy_armed_lit,
           public.navy_on() as navy_lit,
           n.unarmed_at_sea <= 0.10 * greatest(1, n.at_sea) as cargo_safe
      from n)
  select jsonb_build_object(
           'ready', k.loot_rule_on and k.clock_sane
                    and (not k.lived or (k.regard_lit and k.npc_levels_lit and k.levels_written and k.convoy_armed_lit and k.navy_lit and k.cargo_safe)),
           'lived', k.lived,
           'checks', jsonb_build_object('loot_rule_on', k.loot_rule_on, 'clock_sane', k.clock_sane, 'regard_lit', k.regard_lit, 'npc_levels_lit', k.npc_levels_lit,
                                        'levels_written', k.levels_written, 'convoy_armed_lit', k.convoy_armed_lit, 'navy_lit', k.navy_lit, 'cargo_safe', k.cargo_safe),
           'cargo', jsonb_build_object('ships', k.ships, 'at_sea', k.at_sea, 'unarmed_at_sea', k.unarmed_at_sea, 'unarmed', k.unarmed, 'levelled', k.levelled),
           'why', to_jsonb(array_remove(array[
             case when not k.loot_rule_on then 'the loot rule of 0374 is off (loot_risk_full is 0, or loot_risk_floor is 1): every won fight would pay the whole share' end,
             case when not k.clock_sane then 'battle_round_seconds is not between 30 and 120' end,
             case when k.lived and not k.regard_lit then 'regard_enabled is off: an attack would cost no standing' end,
             case when k.lived and not k.npc_levels_lit then 'npc_ship_level_enabled is off: crown hulls would fight at level 1' end,
             case when k.lived and k.npc_levels_lit and not k.levels_written then 'the crown hulls'' level is not written yet on 9 cargo hulls in 10: wait for the ten-minute job (byeharu-voyage:crown-hull-level)' end,
             case when k.lived and not k.convoy_armed_lit then 'convoy_armed_enabled is off: the cargo ship would be the old unarmed hull' end,
             case when k.lived and not k.navy_lit then 'navy_enabled is off: no country would answer an attack' end,
             case when k.lived and not k.cargo_safe then format('%s of the %s cargo ships at sea are unarmed: more than a tenth', k.unarmed_at_sea, k.at_sea) end], null)))
    from k
$body$;
$f$;
  comment on function public.attack_ready() is
    '0374: may attack_enabled be lit: {ready, lived, checks, cargo, why}. The one reading: 0375''s guard and scripts/ops/harness/attacks/before-light.sql. Server-only.';
  revoke all on function public.attack_ready() from public, anon, authenticated;

  -- ── 3. THE ONE LINE OF public.loot_take, AND THE ONE LINE OF public.battle_sheet_freeze ──
  execute replace(v_def0, c_old, c_new);
  execute replace(v_frz0, c_frz_old, c_frz_new);

  -- ── 4. THE SELF-ASSERT ──
  v_def := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  if (length(v_def) - length(replace(v_def, c_new, ''))) / length(c_new) is distinct from 1 or replace(v_def, c_new, c_old) is distinct from v_def0 then
    raise exception '0374 self-assert FAIL: the hunk is not in public.loot_take once, or does not reverse to the body it was cut from';
  end if;
  v_def := replace(pg_get_functiondef(c_frz::regprocedure), E'\r', '');
  if (length(v_def) - length(replace(v_def, c_frz_new, ''))) / length(c_frz_new) is distinct from 1 or replace(v_def, c_frz_new, c_frz_old) is distinct from v_frz0 then
    raise exception '0374 self-assert FAIL: the hunk is not in public.battle_sheet_freeze once, or does not reverse to the body it was cut from';
  end if;
  if has_function_privilege('anon', c_frz, 'execute') or has_function_privilege('authenticated', c_frz, 'execute') then
    raise exception '0374 self-assert FAIL: public.battle_sheet_freeze can be called by a client';
  end if;
  if md5(replace(pg_get_functiondef('public.loot_due(text,bigint,bigint)'::regprocedure), E'\r', '')) is distinct from v_due0 then
    raise exception '0374 self-assert FAIL: public.loot_due moved: this file does not edit it';
  end if;
  if (select p.provolatile from pg_proc p where p.oid = 'public.loot_risk(jsonb)'::regprocedure) is distinct from 's'
     or has_function_privilege('anon', 'public.loot_risk(jsonb)', 'execute') or has_function_privilege('authenticated', 'public.loot_risk(jsonb)', 'execute')
     or has_function_privilege('anon', c_fn, 'execute') or has_function_privilege('authenticated', c_fn, 'execute') then
    raise exception '0374 self-assert FAIL: public.loot_risk is not STABLE, or it or public.loot_take can be called by a client';
  end if;
  if (select p.provolatile from pg_proc p where p.oid = 'public.attack_ready()'::regprocedure) is distinct from 's'
     or has_function_privilege('anon', 'public.attack_ready()', 'execute') or has_function_privilege('authenticated', 'public.attack_ready()', 'execute')
     or not (public.attack_ready() ?& array['ready', 'lived', 'checks', 'cargo', 'why'])
     or (public.attack_ready() #>> '{checks,loot_rule_on}')::boolean is distinct from true then
    raise exception '0374 self-assert FAIL: public.attack_ready is not STABLE and server-only, or does not answer its five keys with the loot rule on: %', public.attack_ready();
  end if;
  if public.wc_num('loot_risk_full') <> 0.075 or public.wc_num('loot_risk_floor') <> 0 then
    raise exception '0374 self-assert FAIL: the knobs are not 0.075 and 0';
  end if;
  -- arithmetic, on crafted answers: (her hull at the start, her hull at the end, the factor wanted)
  for r in select * from (values (1000::numeric, 1000::numeric, 0::numeric), (1000, 962.5, 0.5), (1000, 925, 1), (1000, 800, 1), (1000, 985, 0.2), (5600, 5499.2, 0.24), (1000, 1010, 0)) t(h0, h1, want) loop
    if public.loot_risk(jsonb_build_object('outcome', 'PLUNDERED', 'hull', jsonb_build_object('a', 0, 'b', r.h1, 'a_start', 500, 'b_start', r.h0))) is distinct from r.want then
      raise exception '0374 self-assert FAIL: a fleet of % that ended at % earns % of the loot, not %', r.h0, r.h1,
        public.loot_risk(jsonb_build_object('hull', jsonb_build_object('b', r.h1, 'b_start', r.h0))), r.want;
    end if;
  end loop;
  if public.loot_risk(null) <> 1 or public.loot_risk('{}'::jsonb) <> 1 or public.loot_risk('{"hull": {"b": 0, "b_start": 0}}'::jsonb) <> 1
     or public.loot_risk('{"hull": {"b_start": 1000}}'::jsonb) <> 0 then
    raise exception '0374 self-assert FAIL: no fight, an empty answer or a side with no hull is not 1, or an answer with no end hull is not 0';
  end if;
  -- the floor, and the rule off (the knobs are put back; this block's own rows only)
  update public.world_config set value = '0.2'::jsonb where key = 'loot_risk_floor';
  if public.loot_risk('{"hull": {"b": 1000, "b_start": 1000}}'::jsonb) <> 0.2 or public.loot_risk('{"hull": {"b": 962.5, "b_start": 1000}}'::jsonb) <> 0.5 then
    raise exception '0374 self-assert FAIL: a floor of 0.2 is not the least a fight pays';
  end if;
  update public.world_config set value = '0'::jsonb where key in ('loot_risk_floor', 'loot_risk_full');
  if public.loot_risk('{"hull": {"b": 1000, "b_start": 1000}}'::jsonb) <> 1 then
    raise exception '0374 self-assert FAIL: loot_risk_full 0 is not the rule off';
  end if;
  if (public.attack_ready() ->> 'ready')::boolean or (public.attack_ready() #>> '{checks,loot_rule_on}')::boolean or jsonb_array_length(public.attack_ready() -> 'why') < 1 then
    raise exception '0374 self-assert FAIL: with the loot rule off public.attack_ready still says ready: %', public.attack_ready();
  end if;
  update public.world_config set value = '0.075'::jsonb where key = 'loot_risk_full';
  -- what the caps then make of it, by public.loot_due itself: 100,000 aboard, a boarding
  if public.loot_due('PLUNDERED', floor(100000 * public.loot_risk('{"hull": {"b": 5499.2, "b_start": 5600}}'::jsonb))::bigint, 0) <> floor(24000 * public.wc_num('loot_share'))
     or public.loot_due('PLUNDERED', floor(100000 * public.loot_risk('{"hull": {"b": 280, "b_start": 280}}'::jsonb))::bigint, 0) <> 0
     or public.loot_due('RANSOM', floor(100000 * public.loot_risk('{"hull": {"b": 1620, "b_start": 1800}}'::jsonb))::bigint, 0) <> public.ransom_take(100000) then
    raise exception '0374 self-assert FAIL: the loot of a walkover, of a fight that cost nothing and of a hard-won ransom is not what the rule says';
  end if;
  if clock_timestamp() - v_t0 > interval '20 seconds' then
    raise exception '0374 self-assert FAIL: it took % (the limit is 20 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0374: may attacks be lit, as this world stands: %', public.attack_ready();
  raise notice '0374 self-assert ok: LOOT FOLLOWS THE RISK TAKEN. public.attack_ready and public.loot_risk (STABLE, server-only) and two knobs (loot_risk_full 0.075, loot_risk_floor 0); one line of public.loot_take and one of public.battle_sheet_freeze re-cut, each once and reversing; public.loot_due unmoved. No hull lost pays nothing, 3.75 %% a half, 7.5 %% and more the whole; no fight and the rule off pay as 0327 did. attack_enabled %. % ms.',
    public.attack_on(), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
