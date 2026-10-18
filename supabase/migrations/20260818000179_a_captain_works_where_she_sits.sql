-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0179 — A CAPTAIN WORKS WHERE SHE SITS  (crew_bite false → true: the captains' traits bite)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE ASK ─────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-10-17: the captains of 대항해시대 오리진, *"apply it to the game as well"*. K4–K9 shipped
-- the captains (grades, kits of traits, cabins, three levels, homesickness, languages, promotion) DARK
-- behind ONE switch, world_config `crew_bite` (0157). docs/SKILLS_AND_CAPTAINS.md §8 "Lighting order":
-- … skills_bite (0178, LIVE 2026-10-18 ~03:55 UTC) … → crew_bite. This file is that step and nothing else.
--
-- ── WHAT THE SWITCH TURNS ON (every reader is LIVE already; none is touched here) ────────────────
--   public.crew_terms, the one arithmetic behind public.crew_pct (§4.4). Dark: each seated captain's JOB
--   (her first trait) at her value, live effects only — fleet_officer_bonus's old sum. Lit:
--     * every ACTIVE trait counts (a captain uses 2–5 of the traits she knows), each × its effect's mult;
--     * × her cabin's rate: 100 % in the Captain's cabin or a cabin of her trait's focus, else
--       cabin_off_focus_pct (50 %) — D9, [UWO §3.5];
--     * lifted to her grade's floor once promoted above her birth grade (K8);
--     * × the homesick factor after homesick_after_hours (72 h) away from her home region:
--       1 − max(0, 20 − the fleet's Surgeon care − Hospitality) / 100 (D13);
--     * the non-live effects start to count: supplies (Provisioner → voyage.endurance_days), storm (Pilot
--       → voyage.storm_hull_lost, at departure), category_spread (goods traders → world.spread_effective);
--   public.crew_speaker → public.haggle_odds: a seated captain who speaks the port's language adds
--   language_haggle_points (5) to the bargain odds (D14; never a gate). world.ship_seats drops its
--   "Cabin rates are not in use yet." note (the ship panel prints the server's note; the spec follows).
--   NOT this file: levels_bite (captains' and hulls' levels stay 1), combat_bite (Gunner / Boarder, S4),
--   armour_turns_pct, gear_wear_bite.
--
-- ── WHO IT REACHES ON PRODUCTION (read-only, 2026-10-18, head 0178) ─────────────────────────────
--   * MERCHANTS: 511 signings, every one seated, each with exactly ONE active trait — her job — and every
--     one in a full-rate seat (210 exploration-in-exploration, 299 trading-in-trading, 2 in the Captain's
--     cabin); none has a captain_state row, so none is ever homesick or above her birth grade (O8). Their
--     jobs' effects are speed, spread, hold, crew_saved (all live) and the Surgeon's homesick_relief (read
--     only for a homesick captain). So every merchant answer is the pre-image, lit — asserted below for
--     every live merchant fleet, as K5's row requires ("crew_pct = old bonus, dark and lit").
--   * PLAYERS: 1 signing, not seated, so lit adds nothing to any player fleet today. From the flip on, a
--     captain a player seats works at her cabin's rate with every trait she uses, misses home, and speaks.
--
-- ── THE BOUNDS (asserted, dark → lit) ────────────────────────────────────────────────────────────
--   Every live MERCHANT fleet: speed, cargo space, stores, wage, the captains' per cents for speed, spread,
--   hold, crew_saved, supplies and storm, and every live-effect crew term (row by row) EXACTLY the pre-image; 300
--   sampled merchant quay spreads exactly the pre-image. Players: reported, not bounded (a rate below 100 %
--   or homesickness is the rule working, by the owner's O2 / O6).
--
-- ── THE COST ────────────────────────────────────────────────────────────────────────────────────
--   Measured on the cached world (skills lit, PGlite, before this file): merchant speed + cargo space
--   734 → 891 ms, endurance + wage 189 → 248 ms (crew_pct('supplies') walks the lit terms), ship_view
--   1,623 → 1,648 ms. Printed again below on the database it runs on (notice only).
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
-- A forward migration with `update public.world_config set value = 'false'::jsonb where key = 'crew_bite';`.
-- Nothing is written by the lit path that the dark path cannot read (no table changes here).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $$
begin
  perform set_config('statement_timeout', '10min', true);
  perform set_config('lock_timeout', '5s', true);
  perform set_config('random_page_cost', '1.1', true);   -- prod's planner page cost (0149's header)
  if public.crew_bite_on() then
    raise exception '0179 self-assert FAIL: crew_bite is already on — this file throws it, and its pre-image must be the dark world';
  end if;
  if not exists (select 1 from public.world_config where key = 'crew_bite') then
    raise exception '0179 self-assert FAIL: there is no crew_bite row to throw (0157 seeded it)';
  end if;
  if public.combat_bite_on() then
    raise exception '0179 self-assert FAIL: combat_bite is on — this file was measured with it off';
  end if;
end $$;

-- ── 1. THE ANSWERS (taken dark, then lit) ───────────────────────────────────────────────────────
create or replace function pg_temp.fleet_answers_0179()
returns table (fleet_id uuid, is_npc boolean, speed numeric, endurance numeric, wage bigint, hold numeric,
               c_speed numeric, c_spread numeric, c_hold numeric, c_saved numeric, c_supplies numeric, c_storm numeric,
               terms text)
language sql
as $$
  select f.id, p.is_npc,
         voyage.fleet_speed(f.id),
         voyage.endurance_days(f.id),
         public.fleet_wage(f.id, false),
         (select sum(public.ship_hold_capacity(s.id)) from public.ships s where s.fleet_id = f.id),
         public.crew_pct(f.id, null, 'speed'),
         public.crew_pct(f.id, null, 'spread'),
         public.crew_pct(f.id, null, 'hold'),
         public.crew_pct(f.id, null, 'crew_saved'),
         public.crew_pct(f.id, null, 'supplies'),
         public.crew_pct(f.id, null, 'storm'),
         (select string_agg(t.player_officer_id::text || ':' || t.trait || ':' || t.effect || ':' || round(t.value_pct, 8)::text, ','
                            order by t.player_officer_id, t.trait, t.effect)
            from public.crew_terms(f.id) t
            -- the live effects' terms (a Surgeon's homesick_relief term appears lit, but it is read only
            -- for a homesick captain: never a merchant, O8; its answer is crew_saved / the factor, both above)
           where exists (select 1 from public.crew_effects ce where ce.code = t.effect and ce.live))
    from public.fleets f
    join public.players p on p.id = f.player_id
   where exists (select 1 from public.ships s where s.fleet_id = f.id)
$$;

create temp table spread_keys_0179 on commit drop as
select f.port_id, g.id as good_id, f.id as fleet_id
  from public.fleets f
  join public.players p on p.id = f.player_id and p.is_npc
 cross join lateral (select id from public.goods order by md5(id::text || f.id::text) limit 3) g
 where f.port_id is not null
 order by md5(f.id::text || g.id::text)
 limit 300;

create or replace function pg_temp.timing_0179()
returns jsonb
language plpgsql
as $$
declare
  v_t0   timestamptz;
  v_a    numeric;
  v_b    numeric;
  v_ms   numeric;
  v_x    numeric;
  i      int;
begin
  for i in 1 .. 2 loop
    v_t0 := clock_timestamp();
    select sum(voyage.fleet_speed(f.id)) + sum((select sum(public.ship_hold_capacity(s.id)) from public.ships s where s.fleet_id = f.id))
      into v_x
      from public.fleets f join public.players p on p.id = f.player_id and p.is_npc
     where exists (select 1 from public.ships s where s.fleet_id = f.id);
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
    v_a := least(coalesce(v_a, v_ms), v_ms);
    v_t0 := clock_timestamp();
    select sum(voyage.endurance_days(f.id)) + sum(public.fleet_wage(f.id, false))
      into v_x
      from public.fleets f join public.players p on p.id = f.player_id and p.is_npc
     where exists (select 1 from public.ships s where s.fleet_id = f.id);
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
    v_b := least(coalesce(v_b, v_ms), v_ms);
  end loop;
  return jsonb_build_object('speed_hold_ms', v_a, 'endurance_wage_ms', v_b);
end $$;

create temp table dark_fleets_0179 on commit drop as select * from pg_temp.fleet_answers_0179();
create temp table dark_spread_0179 on commit drop as
select k.*, world.spread_effective(k.port_id, k.good_id, k.fleet_id) as v from spread_keys_0179 k;
create temp table timing_0179 (k text primary key, v jsonb) on commit drop;
insert into timing_0179 values ('dark', pg_temp.timing_0179());

-- ── 2. THE SWITCH ───────────────────────────────────────────────────────────────────────────────
update public.world_config
   set value = 'true'::jsonb,
       description = coalesce(description || ' ', '')
                     || 'THROWN TRUE by 0179 (2026-10-18), the owner''s order to apply the captains to the game: every '
                     || 'active trait, cabin rates, grade floors, homesickness, languages and the supplies / storm / '
                     || 'category effects now count.'
 where key = 'crew_bite';

create temp table lit_fleets_0179 on commit drop as select * from pg_temp.fleet_answers_0179();
create temp table lit_spread_0179 on commit drop as
select k.*, world.spread_effective(k.port_id, k.good_id, k.fleet_id) as v from spread_keys_0179 k;
insert into timing_0179 values ('lit', pg_temp.timing_0179());

-- ── 3. THE PROBE: own throw-away house, one Navigator who speaks Lisbon's language (rolled back) ──
create temp table probe_0179 (j jsonb) on commit drop;
do $$
declare
  c_uid   constant uuid := '00000000-0179-4000-8000-000000000001';
  v_lis   uuid := (select id from public.ports where code = 'LIS');
  v_code  text;
  v_p     uuid;
  v_f     uuid;
  v_s     uuid;
  v_cls   text;
  v_po    uuid;
  v_good  uuid;
  v_off   int;
  v_r     jsonb;
  v_out   jsonb := '{}'::jsonb;
begin
  begin
    if not public.crew_bite_on() then
      raise exception '0179 self-assert FAIL: crew_bite did not read true after the UPDATE';
    end if;
    -- a Navigator (her job: speed, focus exploration) who speaks Lisbon's language; the cheapest-coded one
    select o.code into v_code
      from public.officers o
      join public.captain_job cj on cj.officer_id = o.id and cj.job = 'NAVIGATOR'
     where exists (select 1 from public.captain_languages cl join public.port_language pl on pl.language = cl.language
                    where cl.officer_id = o.id and pl.port_id = v_lis)
     order by o.code limit 1;
    if v_code is null then
      raise exception '0179 self-assert FAIL: no Navigator speaks Lisbon''s language — the roster moved, not this file';
    end if;
    v_p := public.new_house(c_uid, 'Casa da Prova 0179', 'PRT', 'LIS');
    select id into v_f from public.fleets where player_id = v_p;
    select s.id, c.code into v_s, v_cls from public.ships s join public.ship_classes c on c.id = s.class_id
     where s.fleet_id = v_f order by s.is_flagship desc limit 1;
    perform public.credit(v_p, 'PROBE_0179', 10000000);
    v_r := public.sign_officer(v_p, v_code, v_f);
    if not coalesce((v_r->>'ok')::boolean, false) then
      raise exception '0179 self-assert FAIL: the probe could not sign %: %', v_code, v_r;
    end if;
    select po.id into v_po from public.player_officers po join public.officers o on o.id = po.officer_id
     where po.player_id = v_p and o.code = v_code;
    perform public.captain_traits_set_for(v_p, v_code, array['NAVIGATOR']);
    -- an off-focus seat for an exploration trait on her hull: the first non-captain seat that is not exploration
    select n.seat into v_off from generate_series(2, 8) n(seat)
     where n.seat <= (select cc.cabins from public.class_cabins cc where cc.class_code = v_cls)
       and public.cabin_focus(v_cls, n.seat) not in ('captain', 'exploration')
     order by n.seat limit 1;
    select id into v_good from public.goods order by code limit 1;

    -- (i) the Captain's cabin, home: lit = dark = her job's value (levels dark, so × 1)
    v_r := public.seat_captain_for(v_p, v_code, v_s, 1);
    v_out := v_out || jsonb_build_object('code', v_code, 'class', v_cls, 'off_seat', v_off,
      'job_pct', (select cj.job_pct from public.captain_job cj join public.officers o on o.id = cj.officer_id where o.code = v_code),
      'off_rate', public.wc_num('cabin_off_focus_pct'), 'pen', public.wc_num('homesick_penalty_pct'),
      'lang_pts', public.wc_num('language_haggle_points'),
      'cap_lit', public.crew_pct(v_f, null, 'speed'),
      'odds_fleet_lit', public.haggle_odds(v_p, v_lis, v_good, v_f), 'odds_none_lit', public.haggle_odds(v_p, v_lis, v_good),
      'speaker_lit', (select count(*) from public.crew_speaker(v_f, v_lis)),
      'note_lit', world.ship_seats(v_s)->>'note');
    -- (ii) an off-focus cabin
    v_r := public.seat_captain_for(v_p, v_code, v_s, v_off);
    v_out := v_out || jsonb_build_object('seat_r', v_r, 'off_lit', public.crew_pct(v_f, null, 'speed'));
    -- (iii) homesick, in the Captain's cabin again, 73 h from home and no Surgeon
    v_r := public.seat_captain_for(v_p, v_code, v_s, 1);
    update public.captain_state set home_seen_at = now() - interval '73 hours' where player_officer_id = v_po;
    v_out := v_out || jsonb_build_object('homesick_lit', public.crew_pct(v_f, null, 'speed'));
    -- DARK, the same three states (the switch put back inside this rolled-back block)
    update public.world_config set value = 'false'::jsonb where key = 'crew_bite';
    v_out := v_out || jsonb_build_object('homesick_dark', public.crew_pct(v_f, null, 'speed'),
      'odds_fleet_dark', public.haggle_odds(v_p, v_lis, v_good, v_f),
      'speaker_dark', (select count(*) from public.crew_speaker(v_f, v_lis)),
      'note_dark', world.ship_seats(v_s)->>'note');
    update public.captain_state set home_seen_at = now() where player_officer_id = v_po;
    v_out := v_out || jsonb_build_object('cap_dark', public.crew_pct(v_f, null, 'speed'));
    v_r := public.seat_captain_for(v_p, v_code, v_s, v_off);
    v_out := v_out || jsonb_build_object('off_dark', public.crew_pct(v_f, null, 'speed'));
    update public.world_config set value = 'true'::jsonb where key = 'crew_bite';
    raise exception 'PROBE_ROLLBACK_0179:%', v_out::text;
  exception when others then
    if sqlerrm not like 'PROBE_ROLLBACK_0179:%' then raise; end if;
    insert into probe_0179 values (substr(sqlerrm, length('PROBE_ROLLBACK_0179:') + 1)::jsonb);
  end;
end $$;

-- ── 4. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  j     jsonb := (select j from probe_0179);
  v_m   record;
  v_pl  record;
  v_sp  record;
  v_job numeric;
  v_td  jsonb := (select v from timing_0179 where k = 'dark');
  v_tl  jsonb := (select v from timing_0179 where k = 'lit');
begin
  if not public.crew_bite_on() then
    raise exception '0179 self-assert FAIL: crew_bite is not on after the probe';
  end if;
  if exists (select 1 from public.players where auth_uid = '00000000-0179-4000-8000-000000000001') then
    raise exception '0179 self-assert FAIL: the probe house survived its rolled-back block';
  end if;

  -- (a) EVERY LIVE MERCHANT FLEET: every answer and every crew term the exact pre-image (K5's row)
  select count(*) as n,
         count(*) filter (where (l.speed, l.endurance, l.wage, l.hold, l.c_speed, l.c_spread, l.c_hold, l.c_saved, l.c_supplies, l.c_storm, l.terms)
                                is distinct from
                                (d.speed, d.endurance, d.wage, d.hold, d.c_speed, d.c_spread, d.c_hold, d.c_saved, d.c_supplies, d.c_storm, d.terms)) as moved,
         count(*) filter (where d.terms is not null) as crewed
    into v_m
    from dark_fleets_0179 d join lit_fleets_0179 l using (fleet_id)
   where d.is_npc;
  if v_m.moved > 0 then
    raise exception '0179 self-assert FAIL: % of % merchant fleet(s) moved lit (speed, stores, wage, cargo space, a captains'' per cent or a crew term) — K5: crew_pct = the old bonus, dark and lit',
      v_m.moved, v_m.n;
  end if;
  select count(*) as n, count(*) filter (where d.v is distinct from l.v) as moved into v_sp
    from dark_spread_0179 d join lit_spread_0179 l using (port_id, good_id, fleet_id);
  if v_sp.moved > 0 then
    raise exception '0179 self-assert FAIL: % of % sampled merchant quay spreads moved lit', v_sp.moved, v_sp.n;
  end if;
  -- (b) PLAYERS: reported
  select count(*) as n,
         count(*) filter (where (l.speed, l.endurance, l.wage, l.hold, l.terms) is distinct from (d.speed, d.endurance, d.wage, d.hold, d.terms)) as moved
    into v_pl
    from dark_fleets_0179 d join lit_fleets_0179 l using (fleet_id)
   where not d.is_npc;

  -- (c) THE PROBE, against the plan (D9, D13, D14)
  v_job := (j->>'job_pct')::numeric;
  if (j->>'cap_lit')::numeric is distinct from (j->>'cap_dark')::numeric
     or (j->>'cap_lit')::numeric <> least(v_job, (select ce.cap_pct from public.crew_effects ce where ce.code = 'speed')) / 100.0 then
    raise exception '0179 self-assert FAIL: in the Captain''s cabin her speed reads % lit / % dark, not her job''s % %%', j->>'cap_lit', j->>'cap_dark', v_job;
  end if;
  if j->>'off_seat' is null then
    raise exception '0179 self-assert FAIL: the probe''s % has no off-focus cabin for an exploration trait', j->>'class';
  end if;
  if (j->>'off_dark')::numeric is distinct from (j->>'cap_dark')::numeric
     or abs((j->>'off_lit')::numeric - (j->>'cap_lit')::numeric * (j->>'off_rate')::numeric / 100) > 0.00000001 then
    raise exception '0179 self-assert FAIL: in an off-focus cabin (seat %) her speed reads % lit / % dark — want % × % %% lit, whole dark (%)',
      j->>'off_seat', j->>'off_lit', j->>'off_dark', j->>'cap_lit', j->>'off_rate', j->'seat_r';
  end if;
  if (j->>'homesick_dark')::numeric is distinct from (j->>'cap_dark')::numeric
     or abs((j->>'homesick_lit')::numeric - (j->>'cap_lit')::numeric * (1 - (j->>'pen')::numeric / 100)) > 0.00000001 then
    raise exception '0179 self-assert FAIL: homesick 73 h, her speed reads % lit / % dark — want % × (1 − % %%) lit, whole dark',
      j->>'homesick_lit', j->>'homesick_dark', j->>'cap_lit', j->>'pen';
  end if;
  if (j->>'speaker_lit')::int <> 1 or (j->>'speaker_dark')::int <> 0
     or (j->>'odds_fleet_dark')::numeric is distinct from (j->>'odds_none_lit')::numeric
     or (j->>'odds_fleet_lit')::numeric <= (j->>'odds_none_lit')::numeric then
    raise exception '0179 self-assert FAIL: her language at Lisbon — speaker % lit / % dark, odds % with her fleet lit, % dark, % without (want + % points lit only)',
      j->>'speaker_lit', j->>'speaker_dark', j->>'odds_fleet_lit', j->>'odds_fleet_dark', j->>'odds_none_lit', j->>'lang_pts';
  end if;
  if j->>'note_lit' is not null or j->>'note_dark' is distinct from 'Cabin rates are not in use yet.' then
    raise exception '0179 self-assert FAIL: the cabins note reads "%" lit, "%" dark', j->>'note_lit', j->>'note_dark';
  end if;

  raise notice '0179 self-assert ok: A CAPTAIN WORKS WHERE SHE SITS — crew_bite thrown true. MERCHANTS (% fleets, % with captains): 0 moved (speed, stores, wage, cargo space, the six captains'' per cents, every live-effect crew term row by row); 0 of % sampled quay spreads moved. PLAYERS (% fleets): % moved. PROBE (own house, % on a %, rolled back): Captain''s cabin speed % (job % %%, dark and lit); off-focus cabin % → % lit (× % %%), % dark; homesick 73 h % lit (× % %%), % dark; speaks Lisbon''s language: odds % → % with her fleet lit, unchanged dark; the cabins note gone. READ COST over the live merchants (fastest of 2, notice only): speed + cargo space % → % ms, endurance + wage % → % ms.',
    v_m.n, v_m.crewed, v_sp.n, v_pl.n, v_pl.moved,
    j->>'code', j->>'class', j->>'cap_lit', v_job, j->>'off_seat', j->>'off_lit', j->>'off_rate', j->>'off_dark',
    j->>'homesick_lit', 100 - (j->>'pen')::numeric, j->>'homesick_dark', j->>'odds_none_lit', j->>'odds_fleet_lit',
    v_td->>'speed_hold_ms', v_tl->>'speed_hold_ms', v_td->>'endurance_wage_ms', v_tl->>'endurance_wage_ms';
end $$;
