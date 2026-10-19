-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0204 — THE RAIDS ARE FOUGHT, A THIRD TIME  (re-lights 0189: combat_bite true, armour_turns_pct 0.5;
--        after 0201's rollback and 0202's balance; judged by the PAIRED after-check, not a window against a window)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- The owner, 2026-10-18 ~13:40 UTC: "yes lets do a automatic fight, so that range and accuracy is an important
-- factor. … yes shoals and damage too." 0189 built the fight dark. This file throws its two switches, one
-- UPDATE each, the method of docs/dev-log/2026-10-18-lighting-skills.md: measured before (the dark world vs
-- the lit one on production's own fleets, docs/dev-log/2026-10-18-auto-fight.md), a probe of its own here,
-- the bounds below, a rollback, and a 30-minute after-check once live.
--
-- WHAT LIGHTING TURNS ON (every reader is 0168's, 0189's or 0202's; no body changes here):
--   combat_bite      a raid is FOUGHT (voyage.fight, in rounds: sighting, range, accuracy, attack, armour,
--                    boarding) and its rounds are written to the day and the VOYAGE_REPORT (`fights`), which
--                    the History tray already prints (0189's client). The escort reads what she carries
--                    (0168, S4); a seated Gunner / Boarder adds to her accuracy, reach / attack (K10); their
--                    cards stop saying "Works when combat arrives." Below the last boarding band the crew
--                    SURRENDERS (0202): a fought raid ends PLUNDERED, never STRIPPED.
--   armour_turns_pct 0.5: armour turns half its share of a storm's, a shoal's and a fight's hull loss
--                    (public.armour_soak: loss × (1 − armour / 100 × 0.5)) — SHIPS_AND_GEAR §5's probe value.
--
-- THE THIRD TIME — WHAT THE FIRST TWO TAUGHT:
--   0192 lit, 0195 rolled back: the arrivals average broke its 3 s bound (3.18 s). Cause measured since: the dark
--     baseline had risen with 0182's re-plan batch, and lit, every world.ship_stats read ran the K10 crew loop for
--     nothing. 0198 (perf, dark) and 0199 (the batch keeps a strict 300 ms budget) answered it.
--   0200 lit (20:48 UTC 2026-10-18), 0201 rolled back: the 30-minute WINDOW after-check (20:50–21:20) broke the two
--     raid bounds — lost share 43.8 % against 35.0 % dark (+5 allowed), crew lost per raid 12.50 % against 6.43 %
--     (+1 allowed). Arrivals held (2.42 s). Two things were then measured (dev-log, "0202 — the raid balance"):
--     (1) the window was not like for like: DESIGN B.6's dark table on the SAME 16 raids reads lost 50.0 % and
--         crew 12.71 % — the fight did no worse than the table there; the window simply met heavier raids on
--         smaller hulls than the 19 dark raids before it. Resampled from production's real raid mix, a 16-raid
--         window against a 19-raid window passes a CORRECT engine only ~52–67 % of the time;
--     (2) on all 236 real raids replayed 20×, 0189 lit held both bounds overall (lost 25.2 % vs 27.1 %; crew 7.13 %
--         vs 6.48 %) but a lone hull of ≤ 12 hands buried more (crew 11.28 % vs 9.76 %, STRIPPED 13.4 % vs 6.4 %):
--         every one a boarding below the last band. 0202 (DARK, live) is the balance: that crew surrenders —
--         PLUNDERED, never STRIPPED. Same raids × 20 under 0202: lost 25.2 %, crew 5.47 %, STRIPPED 0.
--   So this file re-lights the SAME switches on 0202's body, and its after-check is the PAIRED one.
--
-- THE PAIRED AFTER-CHECK (bv-harness/raid-scratch/after-check.sh <start> <end>, read-only on prod; its SQL is
-- paired.sql's): every PIRATES day resolved inside the window, its recorded (lit) outcome against DESIGN B.6's
-- dark table on that SAME raid (the fleet's class-figure escort, the day's own raider strength). Bounds:
--   paired lost (PLUNDERED + STRIPPED) share  ≤ the dark table's on the same raids + 5 points;
--   paired crew lost per raid                 ≤ the dark table's on the same raids + 1 point;
--   arrivals (cron job 1) avg ≤ 3 s and p95 < 5 s over the window;
--   every PIRATES day in the window carries `rounds`.
-- Also printed, not bounded: reconcile (cron job 3) durations, E_ENDURANCE refusals and REPAIR orders in the window.
-- On 0200's own window the paired check reads lost 43.8 % vs 50.0 % and crew 12.50 % vs 12.71 %: both held. Under
-- 0202 it holds both bounds 85 % of the time on a 16-raid window, resampled; a longer window raises that.
--
-- MEASURED, NOT ASSERTED (production's real fleets are not this file's probe rows — notices only): 200 merchant
-- fleets × 4 raider strengths, the old roll vs the fight; a storm's loss at a middling sea for every hull.
-- ASSERTED (its own probe company, rolled back; this file counts only its own rows): a passage of raids is fought
-- in rounds, none of its days ends STRIPPED (0202), and the report hangs the fights under their days; a passage
-- of shoals loses less with the knob at 0.5 than at 0.
--
-- No row moves but the two knobs; no ALTER, no body, no grant. No top-level LOCK / SET LOCAL / BEGIN / SET ROLE.
-- ROLLBACK (a forward migration, never a raw UPDATE on prod — 0201's file, renumbered):
--   update public.world_config set value = 'false'::jsonb where key = 'combat_bite';
--   update public.world_config set value = '0'::jsonb where key = 'armour_turns_pct';
-- Nothing written lit is unreadable dark: a day's `rounds` and a report's `fights` stay in their rows and the
-- tray keeps printing them; a dark day simply has none.
-- VERSION: 0204 (prod head 0202 at writing; 0203 — the routes fix, #252 — lands first). Applies on 0203, dark.
-- No other deploy goes inside its after-check window.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  perform set_config('random_page_cost', '1.1', true);
  if to_regprocedure('voyage.fight(uuid, integer, uuid, numeric)') is null then
    raise exception '0204 refuses: 0189 (the fight) is not in this world';
  end if;
  if position('v_surrender' in pg_get_functiondef('voyage.fight_resolve(uuid, integer, numeric, numeric, jsonb)'::regprocedure)) = 0 then
    raise exception '0204 refuses: 0202 (the surrender) is not in this world — the fight is not lit on 0189''s body again';
  end if;
  if (select value from public.world_config where key = 'combat_bite') <> 'false'::jsonb
     or (select value from public.world_config where key = 'armour_turns_pct') <> '0'::jsonb then
    raise exception '0204 refuses: combat_bite / armour_turns_pct are not dark — this file''s pre-image is the dark world';
  end if;
end $guard$;

-- ── 1. BEFORE (measured on the world's own fleets; reported, never asserted) ──────────────────
create temp table sample_0204 on commit drop as
select f.id as fleet_id, r.raider, voyage.escort_score(f.id) as escort_dark,
       case when voyage.escort_score(f.id) / r.raider >= 2.0 then 'EVADED'
            when voyage.escort_score(f.id) / r.raider >= 1.2 then 'DRIVEN_OFF'
            when voyage.escort_score(f.id) / r.raider >= 0.7 then 'RANSOM'
            when voyage.escort_score(f.id) / r.raider >= 0.3 then 'PLUNDERED'
            else 'STRIPPED' end as old_outcome,
       null::text as new_outcome, null::numeric as new_hull, null::numeric as maxd
  from (select f.id from public.fleets f join public.players pl on pl.id = f.player_id
         where pl.is_npc and exists (select 1 from public.ships s where s.fleet_id = f.id) order by f.id limit 200) f
 cross join (values (4.0), (9.0), (16.0), (24.0)) r(raider);

create temp table storm_0204 on commit drop as
select s.id as ship_id, round(c.durability * (0.08 + 0.17 * 0.5), 2) as loss_dark, null::numeric as loss_lit
  from public.ships s join public.ship_classes c on c.id = s.class_id;

-- ── 2. THE SWITCHES ────────────────────────────────────────────────────────────────────────────
update public.world_config set value = 'true'::jsonb,
       description = '0168 (S4 + K10) / 0189 / 0202 / 0204: THE switch of combat — ON since 0204. A raid is fought in rounds '
                     '(voyage.fight); the escort reads what she carries; a seated Gunner / Boarder counts; below the last '
                     'boarding band the crew surrenders (0202). Off: DESIGN B.6''s ratio table.'
 where key = 'combat_bite';
update public.world_config set value = '0.5'::jsonb,
       description = '0168 / 0204: the share of a storm''s, a shoal''s or a fight''s hull loss armour turns — loss × (1 − armour / 100 × '
                     'this) (public.armour_soak). 0.5 since 0204; 0 = off (the loss itself).'
 where key = 'armour_turns_pct';

-- ── 3. AFTER (the same sample, lit; reported) ──────────────────────────────────────────────────
do $$
declare
  v_t0 timestamptz := clock_timestamp();
begin
  update sample_0204 sm
     set new_outcome = x.j->>'outcome',
         new_hull = (select coalesce(sum(h.value::numeric), 0) from jsonb_each_text(x.j->'hull_lost') h),
         maxd = (select sum(c.durability) from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = sm.fleet_id)
    from (select s2.fleet_id, s2.raider,
                 voyage.fight(('00000000-0204-4000-8000-' || lpad((row_number() over (order by s2.fleet_id, s2.raider))::text, 12, '0'))::uuid,
                              1, s2.fleet_id, s2.raider) as j
            from sample_0204 s2) x
   where x.fleet_id = sm.fleet_id and x.raider = sm.raider;
  update storm_0204 st set loss_lit = public.armour_turns(st.ship_id, st.loss_dark);
  raise notice '0204 measure: % fights over % merchant fleets in % ms', (select count(*) from sample_0204),
    (select count(distinct fleet_id) from sample_0204), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $$;

-- ── 4. THE PROBE (its own company; rolled back) ────────────────────────────────────────────────
create or replace function pg_temp.probe_0204()
returns jsonb
language plpgsql
as $$
declare
  c_p   constant uuid := '00000000-0204-4000-8000-000000000001';
  v_lis uuid := (select id from public.ports where code = 'LIS');
  v_fnc uuid := (select id from public.ports where code = 'FNC');
  v_p   uuid;
  v_pf  uuid;
  v_voy uuid;
  v_leg jsonb;
  v_out jsonb := '{}'::jsonb;
  v_k   text;
begin
  foreach v_k in array array['PIRATES', 'SHOAL_WATER'] loop
    begin
      v_p := public.new_house(c_p, 'Casa da Peleja 0204', 'PRT', 'LIS');
      select id into v_pf from public.fleets where player_id = v_p;
      perform public.credit(v_p, 'PROBE_0204', 10000000);
      perform public.commission_ship(v_p, v_pf, 'nau', 'Prova Nau', false, true);
      -- the probe's raiders always close, and at close range (the passage's own seas breed small ones)
      update public.world_config set value = '1000'::jsonb where key = 'fight_standoff_ratio';
      update public.world_config set value = '1'::jsonb where key = 'hazard_p_max';
      update public.voyage_event_kinds set mix_base = case when code = v_k then 1 else 0.0001 end where in_sea_mix;
      select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
        into v_leg from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_fnc;
      v_voy := voyage.depart(v_pf, voyage.segments_from_course(v_leg), v_lis, v_fnc, now() - interval '30 days');
      update public.voyages vo set path = (select jsonb_agg(e || jsonb_build_object('hazard_mult', 1000) order by o)
                                             from jsonb_array_elements(vo.path) with ordinality t(e, o))
       where vo.id = v_voy;
      perform voyage.settle(v_pf, now());
      v_out := v_out || jsonb_build_object(v_k, jsonb_build_object(
        'events', (select coalesce(jsonb_agg(jsonb_build_object('day', ve.day_index, 'kind', ve.kind, 'payload', ve.payload) order by ve.day_index), '[]'::jsonb)
                     from public.voyage_events ve where ve.voyage_id = v_voy),
        'report', (select e.payload from public.events e where e.player_id = v_p and e.kind = 'VOYAGE_REPORT'
                                                           and e.payload->>'voyage_id' = v_voy::text),
        -- each shoal day: what the knob at 0 would have taken (DESIGN's formula on every hull), and what armour_soak leaves
        'shoal', (select coalesce(jsonb_agg(jsonb_build_object('day', ve.day_index, 'lit', (ve.payload->>'hull_lost')::numeric,
                     'dark', (select sum(round(c.durability * (0.04 + 0.11 * h.magnitude), 2)) from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = v_pf),
                     'soaked', (select sum(round(round(c.durability * (0.04 + 0.11 * h.magnitude), 2) * greatest(0, 1 - world.ship_stat(s.id, 'armour') / 100.0 * 0.5), 2))
                                  from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = v_pf))
                     order by ve.day_index), '[]'::jsonb)
                    from public.voyage_events ve cross join lateral voyage.hazard_roll(ve.voyage_id, ve.day_index) h
                   where ve.voyage_id = v_voy and ve.kind = 'SHOAL_WATER')));
      raise exception 'PROBE_ROLLBACK_0204';
    exception when others then
      if sqlerrm <> 'PROBE_ROLLBACK_0204' then raise; end if;
    end;
  end loop;
  return v_out;
end $$;

create temp table probe_0204 (j jsonb) on commit drop;
do $$
declare
  v_try   int := 0;
  v_state text;
  v_msg   text;
begin
  loop
    v_try := v_try + 1;
    begin
      insert into probe_0204 select pg_temp.probe_0204();
      exit;
    exception when lock_not_available or deadlock_detected then
      get stacked diagnostics v_msg = message_text, v_state = returned_sqlstate;
    end;
    if v_try >= 5 then
      raise exception '0204 self-assert FAIL: LOCK CONTENTION, not a result — the probe could not get its locks in 5 tries (%: %). Re-run the push.',
        v_state, v_msg;
    end if;
    perform pg_sleep(0.2);
  end loop;
end $$;

-- ── 5. SELF-ASSERT (the switches and the probe's own rows; the world's own rows are reported only) ─
do $$
declare
  v_pr   jsonb := (select j from probe_0204);
  v_x    jsonb;
  v_n    int;
  v_m    int;
  v_strip int;
  v_lit  numeric;
  v_dark numeric;
  v_s    record;
  v_st   record;
begin
  if (select value from public.world_config where key = 'combat_bite') <> 'true'::jsonb
     or (select value from public.world_config where key = 'armour_turns_pct') <> '0.5'::jsonb then
    raise exception '0204 self-assert FAIL: the switches are not thrown';
  end if;
  -- (a) a passage of raids, lit: every raid day of the probe's own voyage fought in rounds; the report's fights at
  --     their days' lines
  v_x := v_pr->'PIRATES';
  select count(*), count(*) filter (where e->'payload' ? 'rounds'), count(*) filter (where e->'payload'->>'outcome' = 'STRIPPED')
    into v_n, v_m, v_strip
    from jsonb_array_elements(v_x->'events') e where e->>'kind' = 'PIRATES';
  if v_n = 0 or v_m <> v_n
     or jsonb_array_length(coalesce(v_x->'report'->'fights', '[]'::jsonb)) <> v_n
     or exists (select 1 from jsonb_array_elements(v_x->'report'->'fights') f
                 where (v_x->'report'->'lines'->>((f->>'line')::int)) not like 'Day %. Sail sighted%') then
    raise exception '0204 self-assert FAIL: lit, % of % raid day(s) were fought in rounds, or the report''s fights miss their lines: %', v_m, v_n, v_x->'report';
  end if;
  -- (a2) 0202 is lit with it: none of the probe's fought days ends STRIPPED (the crew surrenders: PLUNDERED)
  if v_strip <> 0 then
    raise exception '0204 self-assert FAIL: % of the probe''s % fought raid day(s) ended STRIPPED — 0202''s surrender is not what the fight does: %', v_strip, v_n, v_x->'events';
  end if;
  -- (b) a passage of shoals: every shoal day took what armour_soak leaves of the knob-0 loss, and less than it
  select coalesce(sum((d->>'lit')::numeric), 0), coalesce(sum((d->>'dark')::numeric), 0) into v_lit, v_dark
    from jsonb_array_elements(v_pr->'SHOAL_WATER'->'shoal') d;
  if not (v_dark > 0 and v_lit < v_dark) or exists (select 1 from jsonb_array_elements(v_pr->'SHOAL_WATER'->'shoal') d
                                                     where (d->>'lit')::numeric <> (d->>'soaked')::numeric
                                                        or not ((d->>'lit')::numeric < (d->>'dark')::numeric)) then
    raise exception '0204 self-assert FAIL: shoals lost % hull with armour at 0.5 against % at 0: %', v_lit, v_dark, v_pr->'SHOAL_WATER'->'shoal';
  end if;
  -- (c) the wall: no entry point, no client write
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0204 self-assert FAIL: the grant wall or the read wall moved';
  end if;

  select count(*) n,
         round(100.0 * count(*) filter (where old_outcome in ('EVADED', 'DRIVEN_OFF')) / count(*), 1) old_win,
         round(100.0 * count(*) filter (where new_outcome in ('EVADED', 'DRIVEN_OFF')) / count(*), 1) new_win,
         round(100.0 * count(*) filter (where old_outcome in ('PLUNDERED', 'STRIPPED')) / count(*), 1) old_lost,
         round(100.0 * count(*) filter (where new_outcome in ('PLUNDERED', 'STRIPPED')) / count(*), 1) new_lost,
         round(100.0 * count(*) filter (where old_outcome = 'STRIPPED') / count(*), 1) old_stripped,
         round(100.0 * count(*) filter (where new_outcome = 'STRIPPED') / count(*), 1) new_stripped,
         round(100.0 * avg(new_hull / nullif(maxd, 0)), 2) new_hull_pct
    into v_s from sample_0204;
  select count(*) n, round(sum(loss_dark)) dark, round(sum(loss_lit)) lit into v_st from storm_0204;
  raise notice '0204 self-assert ok: THE RAIDS ARE FOUGHT, A THIRD TIME — combat_bite true, armour_turns_pct 0.5, on 0202''s body. PROBE (own company, rolled back): % raid day(s) fought in rounds, none STRIPPED, the report''s fights at their lines; shoals % → % hull (armour 0 → 0.5). MEASURED, not asserted — % merchant fights (200 fleets × raiders 4 / 9 / 16 / 24): won (evaded + driven off) % → %, lost (plundered + stripped) % → %, stripped % → %, hull lost % of the fleet''s; a storm at a middling sea over % hull(s): % → % hull points. Judge it by the PAIRED after-check (after-check.sh).',
    v_n, v_dark, v_lit, v_s.n, v_s.old_win, v_s.new_win, v_s.old_lost, v_s.new_lost, v_s.old_stripped, v_s.new_stripped,
    v_s.new_hull_pct, v_st.n, v_st.dark, v_st.lit;
end $$;
