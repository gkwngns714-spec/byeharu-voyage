-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0027 — THE SURGEON, THE BOOKKEEPER AND THE NAVIGATOR'S APPRENTICE
--        The last three inert bonuses in the game are wired to real rules — and NAVIGATION, which
--        two migrations refused to wire, is resolved rather than deferred again.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHAT WAS INERT, AND WHO SAID SO ────────────────────────────────────────────────────────────
--   0015:38   "SURGEON      -> crew loss   NOT READ YET. Attaches in voyage.report_line (0007)."
--   0016:39   "ACCOUNTING   -> the daily trade cap   NOT READ YET. Attaches in
--              world.daily_cap_remaining."
--   0016:35-38 "NAVIGATION  -> speed   NOT READ. Deliberately: 0015's NAVIGATOR officers own
--              speed, and two authorities for one number is the thing this project forbids. It
--              attaches to weather when weather exists."
--
-- All three become false in this file, and every place that says otherwise is corrected here
-- rather than left to rot: `world.officers().specialties_read` and `world.skills().effects_read`
-- are the ONE place this game states which bonuses a rule reads (0023 deleted the duplicate
-- sentences from the catalogue blurbs precisely so that there would be one), and both are
-- superseded below to name all four.
--
-- ── SURGEON: 0015's POINTER WAS OFF BY THIRTY LINES, AND THAT IS WORTH SAYING ──────────────────
-- 0015 and 0017 both recorded that crew loss "lives in voyage.report_line". It does not.
-- `voyage.report_line` (0007:868) is IMMUTABLE and returns TEXT: it can only describe. The hands
-- are actually taken in `voyage.settle` (0007:1000-1010), in the PIRATES branch, by
--
--     crew = greatest(0, floor(sh.crew * (case v_outcome when 'DRIVEN_OFF' then 0.98 ... )))
--
-- A pointer that names the wrong function is how a bonus stays inert for twelve migrations: every
-- reader who went looking found a `case` over prose and concluded the wiring was a design problem.
-- It is not; it is one factor. BOTH functions move here, in one file, because they are two halves
-- of one contract — 0017:50-55's rule — and a surgeon who saves five hands the report never
-- mentions is a bonus the player cannot see working.
--
-- THE ARITHMETIC IS RESTATED AS A COUNT OF HANDS, NOT AS A FRACTION KEPT — AND THAT WAS A DEFECT
-- FOUND BY MEASURING. The first draft of this file shaved the surgeon off the LOSS FRACTION:
-- `floor(crew x (1 - base x (1 - surgeon)))`. Its own self-assert went red on the first apply, and
-- the reason is worth keeping:
--
--     a Barca sails with EIGHT hands. A STRIPPED raid takes floor(8 x 0.70) = 5. With a 7 per cent
--     surgeon aboard, floor(8 x 0.721) = 5. THE SAME FIVE. The bonus rounded away entirely, on the
--     only hull a new captain owns.
--
-- A bonus that does nothing on the starter ship is decoration with extra steps, which is the exact
-- thing this file exists to stop. So the surgeon works on the HANDS, which is what a surgeon does:
--
--     lost = floor( (crew - floor(crew x (1 - base_loss))) x (1 - surgeon) )
--
-- The inner term is 0007's loss to the hand, so with NO surgeon `floor(lost x 1) = lost` and the
-- crew is `crew - lost`, which is `floor(crew x (1 - base_loss))` — 0007 EXACTLY, per hull, proven
-- below rather than argued. With one aboard the saving is rounded IN THE CREW'S FAVOUR, which is a
-- deliberate choice and not an accident of the arithmetic: it means a surgeon is never worth
-- nothing, and he can never save more hands than the raid would have taken. On the starter Barca a
-- 7 per cent surgeon turns a STRIPPED raid's three dead into two, and a DRIVEN_OFF raid's one into
-- none — "the surgeon pulled him through", which is a thing a player can see.
--
-- `public.raid_crew_lost(fleet, crew, base_loss)` is the ONE reading; nothing else multiplies
-- `fleet_officer_bonus(fleet, 'SURGEON')` and nothing else re-derives DESIGN B.6's table.
--
-- ── ACCOUNTING: THE CAP, AND ONLY THE CAP ──────────────────────────────────────────────────────
-- `world.daily_cap_remaining` (0005:453) is DESIGN G.7.1's anti-cornering rule: a house may move
-- `daily_cap_fraction x stock_target` tuns of one good at one port in one game-day. Books kept
-- well enough that a factor will let you move more is exactly what a skill called ACCOUNTING is.
-- One term, multiplied into the allowance, read at the point of use and stored nowhere. It is the
-- same function 0026 deliberately did NOT touch, and that restraint is what makes this composition
-- provable: the cap has exactly one new reader and no argument about which of two new terms moved
-- it.
--
-- ── NAVIGATION: THE TRAP, NAMED AND RESOLVED ──────────────────────────────────────────────────
-- 0016 left NAVIGATION inert with its reason written down, and the reason was RIGHT: wiring a
-- skill to speed with its own function beside `voyage.fleet_speed` would be two authorities for
-- one number. 0016's own escape hatch was "it attaches to weather when weather exists".
--
-- THAT ESCAPE HATCH IS NOW CLOSED, AND 0026 IS WHY. 0026 examined wiring a timed modifier to speed
-- and REJECTED it on a hard fact of this chain: `voyage.depart` FREEZES the fleet's speed into
-- `voyages.speed_profile` (0006:62), so a weather buff would be summed into a stored total the
-- moment a fleet sailed — the one thing docs/SECTIONS.md forbids of a buff — and a gale that blew
-- out mid-crossing would still be pushing the hull along. The freeze is load-bearing: it is what
-- makes offline settlement byte-identical (proof 01). So weather cannot own NAVIGATION either, and
-- deferring it a third time would have been deferring it for ever.
--
-- SO IT IS COMPOSED, THROUGH THE SAME SINGLE AUTHORITY THE OFFICER ALREADY USES:
--
--     voyage.fleet_speed(fleet)  =  slowest hull x formation x (1 + NAVIGATOR) x (1 + NAVIGATION)
--
-- There is still exactly ONE answer to "how fast does she sail", in exactly one function, and this
-- file mints no second one. What it adds is a second TERM, read through the second of the two
-- authorities that already exist for reading a bonus:
--
--     public.fleet_officer_bonus(fleet, 'NAVIGATOR')   0015 — a fact about the FLEET's officers
--     public.player_skill_bonus(player, 'SPEED')       0016 — a fact about the HOUSE's training
--
-- That is the shape 0017 and 0022 already established for the spread: the PURSER and the HAGGLING
-- skill both shave it, they reach it through their own two authorities, and `world.spread_effective`
-- composes them multiplicatively. Nobody calls that two authorities for the spread. The same
-- sentence is true here.
--
-- AND THE COMPOSITION IS PROVEN NOT TO DOUBLE-COUNT, the way 0022 proved purser and bargain do
-- (0022 decision 5). Four checks, all below, all measured:
--   1. `fleet_officer_bonus(fleet,'NAVIGATOR')` is UNCHANGED by studying NAVIGATION — the officer
--      authority cannot see the skill, so the skill cannot be counted inside the officer cap.
--   2. `player_skill_bonus(player,'SPEED')` is UNCHANGED by hiring a navigator — and back.
--   3. `fleet_speed` equals `base x (1 + nav) x (1 + skill)` EXACTLY, so each term appears once.
--   4. It is strictly DIFFERENT from `base x (1 + nav + skill)`, so the two are multiplied and not
--      summed — which is the only way to tell composition from addition by measurement.
--
-- THE CEILING, MEASURED RATHER THAN RECALLED. The two terms are separately capped by knobs that
-- already exist: `officer_bonus_cap_pct` (25) clamps the officers, and `skill_max_level` x
-- `skills.pct_per_level` (5 x 4 = 20 per cent) clamps the skill. So the most a house can ever add
-- is x1.25 x 1.20 = x1.50 of her slowest hull's formation speed. NO THIRD CAP IS ADDED: a combined
-- clamp would be a third place to look when somebody asks why a fleet is not getting faster, and
-- the self-assert prints the reachable ceiling from the knobs rather than from this paragraph.
--
-- ── WHAT THIS FILE SUPERSEDES, AND WHY THEY MOVE TOGETHER ──────────────────────────────────────
--   voyage.settle             (0007:887)  — the crew loss composes onto public.raid_crew_loss, and
--                                           the PIRATES payload gains what the report must print.
--   voyage.report_line        (0007:868)  — so a surgeon is visible in the after-action prose.
--   world.daily_cap_remaining (0005:453)  — ACCOUNTING.
--   voyage.fleet_speed        (0006, re-cut 0015) — NAVIGATION.
--   world.officers            (0015, re-cut 0017) — SURGEON stops reporting itself unread.
--   world.skills              (0016, re-cut 0022) — ACCOUNTING and NAVIGATION stop reporting
--                                           themselves unread. All four effects are read now.
--
-- `voyage.settle` was not retyped. It is 0007's body sliced and three marked hunks replaced —
-- declarations, the crew statement, the payload — so the wage arithmetic, the ration arithmetic and
-- the day-boundary arithmetic that proof 01 matches TO THE CHARACTER are byte-identical by
-- construction rather than by care.
--
-- ── EVERY ONE OF THEM IS A NO-OP WITHOUT ITS INPUT, AND THAT IS PROVEN, NOT CLAIMED ────────────
-- With no surgeon posted, `raid_crew_loss` returns the base loss and `1 - 0.02` is `0.98`. With
-- ACCOUNTING unstudied the allowance is `daily_cap_fraction x stock_target` exactly. With
-- NAVIGATION unstudied the speed is 0015's figure, which is 0006's figure. The self-assert
-- captures REAL daily allowances and REAL quotes through the OLD functions before they are
-- replaced and requires zero drift afterwards, and recomputes the old speed definition inline.
-- `scripts/db/proofs/04` and `05` sail an unofficered, unskilled house, so
-- `BALANCE_MEDIAN_IN_BAND` measures exactly what it measured before this file. NO BALANCE MOVES
-- HERE: all three wirings are strictly opt-in and cost a wage or a tuition to switch on.
--
-- ── GRANTS: THIS FILE NEITHER GRANTS NOR REVOKES ANYTHING ──────────────────────────────────────
-- No new client entry point, no new table, no change to `public.client_rpc_entry_points()`. Every
-- function it re-cuts is re-cut with `create or replace`, which keeps the ACL 0018 set — asserted
-- below by re-reading it rather than assumed. `public.raid_crew_loss` is minted revoked from every
-- client role. So this one CAN go through `supabase db push`; it is the first of the three that
-- does not need the Management API path.
--
-- Depends ONLY on: 0004 (fleets/players), 0005 (daily_cap_remaining, port_goods, trade_daily),
--                  0006 (ship_speed, hazard_roll, voyage_events), 0007 (settle, report_line),
--                  0015 (fleet_officer_bonus, officers, world.officers), 0016 (player_skill_bonus,
--                  skills, world.skills), 0022/0024 (world.skills' effects_read list).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- THE PRE-IMAGES. Real quotes AND real daily allowances, taken through the CURRENT functions
-- before a line of them moves, so "nothing changed for a house with no surgeon and no skills" is a
-- comparison and not a sentence. Scaffolding for two asserts; dropped at the foot of this file.
create temporary table quote_before_0027 as
  select pg.port_id, pg.good_id, s.side, s.qty,
         q.units, q.total, q.avg_price, q.end_stock
    from (select port_id, good_id from public.port_goods order by port_id, good_id limit 40) pg
   cross join (values ('buy'::text, 10::numeric), ('buy', 130), ('sell', 25)) as s(side, qty)
   cross join lateral world.quote(pg.port_id, pg.good_id, s.qty, s.side) q;

create temporary table cap_before_0027 as
  select pg.port_id, pg.good_id,
         world.daily_cap_remaining(null::uuid, pg.port_id, pg.good_id) as cap
    from (select port_id, good_id from public.port_goods order by port_id, good_id limit 200) pg;

-- ── 1. THE SURGEON: THE ONE READING OF WHAT A RAID COSTS IN PEOPLE ────────────────────────────
create or replace function public.raid_crew_lost(p_fleet uuid, p_crew numeric, p_base_loss numeric)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- HANDS, not a fraction. The inner expression is 0007's loss to the hand — `crew` less what
  -- `floor(crew x (1 - base_loss))` left standing — so with no surgeon aboard the outer floor is a
  -- no-op and this returns exactly what the game has always taken. The surgeon then saves a share
  -- of THAT, rounded in the crew's favour, which is what stops a 7 per cent bonus vanishing into
  -- the rounding on an eight-hand Barca. See the header for the measurement that forced this shape.
  select greatest(0, least(coalesce(p_crew, 0),
           floor((coalesce(p_crew, 0) - floor(coalesce(p_crew, 0) * (1 - coalesce(p_base_loss, 0))))
                 * (1 - public.fleet_officer_bonus(p_fleet, 'SURGEON')))))
$$;

comment on function public.raid_crew_lost(uuid, numeric, numeric) is
  'THE ONE answer to "how many hands does this hull bury after a raid of this severity". '
  'voyage.settle composes onto it; nothing else reads fleet_officer_bonus(fleet, ''SURGEON'') and '
  'nothing else re-derives DESIGN B.6''s outcome table, so a change to what a surgeon is worth has '
  'exactly one place to be made. Identical to 0007''s arithmetic with no surgeon aboard.';

revoke all on function public.raid_crew_lost(uuid, numeric, numeric) from public, anon, authenticated;

-- ── 2. THE PROSE, SO THE SURGEON IS VISIBLE — SUPERSEDES 0007:868 ─────────────────────────────
-- Still IMMUTABLE, still a pure function of (day, kind, payload), still executable by PUBLIC for
-- the reason 0018's header gives: it reads no row and discloses nothing. The PIRATES line gains a
-- sentence about the hands, built from the payload voyage.settle now writes.
create or replace function voyage.report_line(p_day int, p_kind text, p_payload jsonb)
returns text
language sql
immutable
as $$
  select case p_kind
    when 'CLEAR'         then format('Day %s. A quiet watch; nothing to report.', p_day)
    when 'STORM'         then format('Day %s. A gale took us on the beam. We ran under bare poles and lost %s points of hull.',
                                     p_day, coalesce(p_payload->>'hull_lost', '?'))
    when 'CALM'          then format('Day %s. The wind died away. We lay becalmed and lost %s hours.',
                                     p_day, coalesce(p_payload->>'delay_hours', '?'))
    when 'PIRATES'       then format('Day %s. Sail sighted to windward. %s%s',
                                     p_day, coalesce(p_payload->>'prose', 'They closed with us.'),
                                     -- 0027: and what it cost in people. Silence about a loss reads
                                     -- as a broken game; silence about a surgeon who prevented one
                                     -- is a bonus the player never sees working.
                                     case
                                       when (p_payload->>'crew_lost')::numeric > 0
                                            and coalesce((p_payload->>'surgeon_pct')::numeric, 0) > 0
                                         then format(' We buried %s of the hands; the surgeon kept the rest.',
                                                     p_payload->>'crew_lost')
                                       when (p_payload->>'crew_lost')::numeric > 0
                                         then format(' We buried %s of the hands.', p_payload->>'crew_lost')
                                       when coalesce((p_payload->>'base_loss')::numeric, 0) > 0
                                            and coalesce((p_payload->>'surgeon_pct')::numeric, 0) > 0
                                         then ' The surgeon brought every man through it.'
                                       else ''
                                     end)
    when 'SHORT_RATIONS' then format('Day %s. Stores are low. The hands are on short rations and their wages are up.', p_day)
    else format('Day %s. %s', p_day, p_kind)
  end
$$;

comment on function voyage.report_line(int, text, jsonb) is
  'THE after-action prose of DESIGN E.6, generated in one place. Supersedes the 0007 definition in '
  'the PIRATES line only, which now names the hands lost and the surgeon who kept the rest — the '
  'crew arithmetic itself lives in voyage.settle, which is where 0015''s "attaches in '
  'voyage.report_line" was pointing thirty lines short of.';


-- ── 3. THE RAID, AND WHO SURVIVES IT — SUPERSEDES 0007:887 (SLICED, NOT RETYPED) ─────────────
create or replace function voyage.settle(p_fleet uuid, p_now timestamptz default now())
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v         public.voyages%rowtype;
  f         public.fleets%rowtype;
  d         int;
  v_cap     int;
  v_bound   timestamptz;
  h         record;
  s         record;
  v_kind    text;
  v_payload jsonb;
  v_wages   bigint;
  v_short   boolean;
  v_delay   numeric;
  v_hull    numeric;
  v_end     numeric;
  v_resolved int := 0;
  v_escort  numeric;
  v_raider  numeric;
  v_ratio   numeric;
  v_outcome text;
  v_prose   text;
  v_lost    numeric;
  -- 0027: the surgeon's numbers. v_base_loss is DESIGN B.6's outcome table unchanged; v_crew0 and
  -- v_crew1 are what the report needs so a captain is told how many hands he lost, and who kept
  -- the rest alive.
  v_base_loss numeric;
  v_crew0     numeric;
  v_crew1     numeric;
begin
  select * into f from public.fleets where id = p_fleet for update;
  if f.id is null then return 0; end if;

  select * into v from public.voyages where fleet_id = p_fleet and status = 'SAILING' for update;
  if v.id is null then
    perform cmd.advance(p_fleet, p_now);
    return 0;
  end if;

  loop
    d := v.last_settled_day + 1;
    v_cap := voyage.total_days(v.id);
    exit when d > v_cap;
    v_bound := voyage.day_ends_at(v.id, d);
    exit when v_bound > p_now;

    -- ── consumption (DESIGN C.5), applied first: the day's stores are drunk before the hazard.
    for s in select sh.id, sh.crew, sh.water_t, sh.food_t from public.ships sh where sh.fleet_id = p_fleet loop
      update public.ships
         set water_t = greatest(0, water_t - s.crew * public.wc_num('water_per_crew_day')),
             food_t  = greatest(0, food_t  - s.crew * public.wc_num('food_per_crew_day'))
       where id = s.id;
    end loop;

    v_end   := voyage.endurance_days(p_fleet);
    v_short := v_end < public.wc_num('short_rations_threshold') * v_cap;

    -- ── wages (DESIGN C.5), x1.5 on short rations
    select coalesce(sum(sh.crew), 0) * public.wc_num('wage_per_crew_day')
           * (case when v_short then public.wc_num('short_rations_wage_mult') else 1 end)
      into v_wages from public.ships sh where sh.fleet_id = p_fleet;
    if v_wages > 0 then
      -- A house that cannot pay does not vanish: the wages are still owed and the purse floors at
      -- zero rather than the transaction dying halfway through a settled day.
      perform public.credit(f.player_id, 'WAGES',
        -least(v_wages, (select ducats from public.players where id = f.player_id)));
    end if;

    -- ── the deterministic hazard (DESIGN B.6)
    select * into h from voyage.hazard_roll(v.id, d);
    v_delay := 0; v_payload := jsonb_build_object('short_rations', v_short, 'wages', v_wages);

    if h.occurred and h.kind = 'STORM' then
      v_kind := 'STORM';
      v_hull := 0;
      for s in select sh.id, sh.durability, c.durability maxd
                 from public.ships sh join public.ship_classes c on c.id = sh.class_id
                where sh.fleet_id = p_fleet loop
        v_lost := round(s.maxd * (0.08 + 0.17 * h.magnitude), 2);
        update public.ships set durability = greatest(0, s.durability - v_lost) where id = s.id;
        v_hull := v_hull + v_lost;
      end loop;
      v_delay   := 36;   -- DESIGN B.6: +1.5 voyage-days
      v_payload := v_payload || jsonb_build_object('hull_lost', v_hull, 'delay_hours', v_delay);

    elsif h.occurred and h.kind = 'CALM' then
      v_kind    := 'CALM';
      v_delay   := round((1 + 3 * h.magnitude) * 24, 2);   -- DESIGN B.6: 1-4 voyage-days
      v_payload := v_payload || jsonb_build_object('delay_hours', v_delay);

    elsif h.occurred and h.kind = 'PIRATES' then
      v_kind := 'PIRATES';
      -- DESIGN B.6: escort_score = Σ(guns + crew×0.02 + hull_class×3). The ENTIRE combat system.
      select coalesce(sum(c.guns + sh.crew * 0.02 + c.tier * 3), 0) into v_escort
        from public.ships sh join public.ship_classes c on c.id = sh.class_id where sh.fleet_id = p_fleet;
      select coalesce(s2.piracy_index, 0) * 40 * (0.5 + h.magnitude) into v_raider
        from public.seas s2 where s2.id = (voyage.leg_at_day(v.id, d)->>'sea_id')::uuid;
      v_ratio := case when v_raider <= 0 then 99 else v_escort / v_raider end;
      if    v_ratio >= 2.0 then v_outcome := 'EVADED';
      elsif v_ratio >= 1.2 then v_outcome := 'DRIVEN_OFF';
      elsif v_ratio >= 0.7 then v_outcome := 'RANSOM';
      elsif v_ratio >= 0.3 then v_outcome := 'PLUNDERED';
      else                      v_outcome := 'STRIPPED';
      end if;
      v_prose := case v_outcome
        when 'EVADED'     then 'They stood off and did not close.'
        when 'DRIVEN_OFF' then 'We fired twice and they sheered away.'
        when 'RANSOM'     then 'We paid them off rather than fight.'
        when 'PLUNDERED'  then 'They came aboard and took what they could carry.'
        else 'They took everything but the ship itself.' end;
      -- 0027: THE SURGEON, AT LAST. DESIGN B.6's outcome table is UNCHANGED — a raid still costs
      -- 2, 10 or 30 per cent of the hands — but it is stated as a LOSS rather than as the fraction
      -- kept, because a loss is the thing a surgeon reduces and the thing the report names.
      -- public.raid_crew_lost is the one authority that decides how many hands this hull actually
      -- buries; with nobody aboard it gives back exactly what 0007's `floor(crew x 0.98 / 0.90 /
      -- 0.70)` always took, per hull, to the hand.
      v_base_loss := case v_outcome when 'DRIVEN_OFF' then 0.02
                                    when 'PLUNDERED'  then 0.10
                                    when 'STRIPPED'   then 0.30
                                    else 0 end;
      select coalesce(sum(sh.crew), 0) into v_crew0
        from public.ships sh where sh.fleet_id = p_fleet;
      if v_outcome in ('DRIVEN_OFF', 'PLUNDERED', 'STRIPPED') then
        update public.ships sh
           set crew = greatest(0, sh.crew - public.raid_crew_lost(p_fleet, sh.crew, v_base_loss)),
               durability = greatest(0, sh.durability * (case v_outcome when 'DRIVEN_OFF' then 0.95
                                                                        when 'PLUNDERED' then 0.80
                                                                        else 1.00 end))
         where sh.fleet_id = p_fleet;
      end if;
      select coalesce(sum(sh.crew), 0) into v_crew1
        from public.ships sh where sh.fleet_id = p_fleet;
      if v_outcome in ('PLUNDERED', 'STRIPPED') then
        -- DESIGN B.6: "The flagship is never captured." The worst case is expensive, not fatal.
        update public.ships set cargo = case when v_outcome = 'STRIPPED' then '{}'::jsonb
                                             else cargo end
         where fleet_id = p_fleet;
      end if;
      v_payload := v_payload || jsonb_build_object('outcome', v_outcome, 'prose', v_prose,
                                                   'escort', round(v_escort, 2), 'raider', round(v_raider, 2),
                                                   -- 0027: what the raid cost in people, so
                                                   -- voyage.report_line can say it in words. Every
                                                   -- one of these is a pure function of the voyage
                                                   -- and the day, so a lazily settled crossing
                                                   -- still reports byte-identically (proof 01).
                                                   'crew_before', v_crew0,
                                                   'crew_lost',   v_crew0 - v_crew1,
                                                   'base_loss',   v_base_loss,
                                                   'surgeon_pct', round(public.fleet_officer_bonus(p_fleet, 'SURGEON') * 100, 2));
    elsif v_short then
      v_kind := 'SHORT_RATIONS';
    else
      v_kind := 'CLEAR';
    end if;

    -- resolved_at is the DETERMINISTIC day boundary, never now(). This is what makes a lazily
    -- settled voyage byte-identical to a tick-by-tick one.
    insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at)
    values (v.id, d, v_kind, v_payload, v_bound)
    on conflict (voyage_id, day_index) do nothing;

    update public.voyages set last_settled_day = d where id = v.id;
    if v_delay > 0 then perform voyage.recompute_eta(v.id); end if;
    select * into v from public.voyages where id = v.id;
    v_resolved := v_resolved + 1;
  end loop;

  -- ── arrival
  if p_now >= v.eta then
    update public.voyages set status = 'ARRIVED', last_settled_day = voyage.total_days(v.id) where id = v.id;
    update public.fleets
       set status = case when (select durability from public.ships where fleet_id = p_fleet and is_flagship) <= 0
                         then 'UNABLE_TO_SAIL' else 'DOCKED' end,
           port_id = v.dest_port_id, version = version + 1
     where id = p_fleet;
    perform public.emit_event(f.player_id, 'VOYAGE_REPORT', jsonb_build_object(
      'fleet', f.name,
      'voyage_id', v.id,
      'from', (select code from public.ports where id = v.origin_port_id),
      'to',   (select code from public.ports where id = v.dest_port_id),
      'total_nm', v.total_nm,
      'lines', (select coalesce(jsonb_agg(voyage.report_line(ve.day_index, ve.kind, ve.payload) order by ve.day_index), '[]'::jsonb)
                  from public.voyage_events ve where ve.voyage_id = v.id)));
    perform cmd.advance(p_fleet, p_now);
  end if;

  return v_resolved;
end $$;

comment on function voyage.settle(uuid, timestamptz) is
  'THE idempotent catch-up of DESIGN D.2. Supersedes the 0007 definition in three marked hunks and '
  'nowhere else — the file was SLICED, not retyped, so the wage, ration and day-boundary '
  'arithmetic proof 01 matches to the character is byte-identical by construction. What changed: a '
  'raid''s crew loss now composes onto public.raid_crew_lost (the SURGEON, 0015''s third inert '
  'specialty), and the PIRATES payload carries what voyage.report_line needs to say so.';

-- ── 4. ACCOUNTING: THE DAILY ALLOWANCE — SUPERSEDES 0005:453 ──────────────────────────────────
-- 0005's body, times one term. With ACCOUNTING unstudied player_skill_bonus returns 0 and this is
-- arithmetically identical to what 0005 defined, which the pre-image above proves on 200 real
-- (port, good) allowances rather than in prose.
--
-- The bonus multiplies the ALLOWANCE, not the amount already moved: a captain who studies
-- bookkeeping is trusted with more, he does not un-trade what he traded this morning.
create or replace function world.daily_cap_remaining(p_player uuid, p_port uuid, p_good uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select greatest(0,
           public.wc_num('daily_cap_fraction') * pg.stock_target
             * (1 + public.player_skill_bonus(p_player, 'TRADE_CAP'))
           - coalesce((select td.qty from public.trade_daily td
                        where td.player_id = p_player and td.port_id = p_port
                          and td.good_id = p_good and td.game_day = world.game_day()), 0))
    from public.port_goods pg
   where pg.port_id = p_port and pg.good_id = p_good
$$;

comment on function world.daily_cap_remaining(uuid, uuid, uuid) is
  'DESIGN G.7.1''s anti-cornering allowance: what this house may still move of this good at this '
  'port today. Supersedes the 0005 definition by one factor — the house''s ACCOUNTING, read '
  'through public.player_skill_bonus (0016) — and is identical to it at skill level 0. The bonus '
  'lifts the allowance and never the tally already spent.';

-- ── 5. NAVIGATION: THE SPEED — SUPERSEDES 0015:158 (WHICH SUPERSEDED 0006) ────────────────────
-- 0015's body, times one term, and NO new function. `voyage.fleet_speed` is still the ONE answer
-- to "how fast does she sail"; what it now reads is a second FACT, through the second of the two
-- bonus authorities that already exist. See the header for why 0016's deferral to weather is no
-- longer available and for the four measurements that prove nav and skill are multiplied rather
-- than counted twice.
create or replace function voyage.fleet_speed(p_fleet uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_min    numeric;
  v_ships  int;
  v_form   numeric;
  v_nav    numeric;
  v_player uuid;
  v_skill  numeric := 0;
begin
  select min(voyage.ship_speed(s.id)), count(*) into v_min, v_ships
    from public.ships s where s.fleet_id = p_fleet;
  if v_ships = 0 then
    raise exception 'E_NO_SHIPS: fleet % has no ships', p_fleet using errcode = 'P0001';
  end if;
  -- DESIGN B.3: M_formation 1.00 for <=3 ships, 0.98 for 4-6, 0.95 for 7+.
  v_form := case when v_ships <= 3 then 1.00 when v_ships <= 6 then 0.98 else 0.95 end;
  -- 0015: the navigators aboard — a fact about the FLEET. Zero when there are none.
  v_nav := public.fleet_officer_bonus(p_fleet, 'NAVIGATOR');
  -- 0027: and the house's NAVIGATION — a fact about the CAPTAIN, read through its own existing
  -- authority. Multiplied, never added: the two are separately capped (officer_bonus_cap_pct and
  -- skill_max_level x pct_per_level) and neither authority can see the other's contribution.
  select f.player_id into v_player from public.fleets f where f.id = p_fleet;
  if v_player is not null then
    v_skill := public.player_skill_bonus(v_player, 'SPEED');
  end if;
  return round(v_min * v_form * (1 + v_nav) * (1 + v_skill), 4);
end $$;

comment on function voyage.fleet_speed(uuid) is
  'THE formation speed, and the only answer to "how fast does she sail": slowest hull, formation '
  'penalty, the NAVIGATORS posted to the fleet (0015) and the house''s NAVIGATION (0027). '
  'Supersedes the 0015 definition by one factor; identical to it with the skill unstudied. The two '
  'bonuses are read through their own single authorities and MULTIPLIED, so neither can be counted '
  'inside the other''s cap.';

-- ── 6. AND THE READS MUST STOP SAYING OTHERWISE — SUPERSEDES 0017:703 AND 0022:846 ────────────
create or replace function world.officers()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  -- 0027: SURGEON joins them. ALL FOUR specialties are read by a rule now — NAVIGATOR by
  -- voyage.fleet_speed (0015), QUARTERMASTER by public.ship_hold_capacity and PURSER by
  -- world.spread_effective (0017/0022), SURGEON by public.raid_crew_lost (this file). This array is
  -- the ONE place the game states which of them work, and it is no longer a list of exceptions.
  v_read   constant text[] := array['NAVIGATOR', 'QUARTERMASTER', 'PURSER', 'SURGEON'];
begin
  return jsonb_build_object(
    'bonus_cap_pct', public.wc_num('officer_bonus_cap_pct'),
    'specialties_read', to_jsonb(v_read),
    'officers', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'code', o.code, 'name', o.name, 'specialty', o.specialty,
               'bonus_pct', o.bonus_pct, 'wage', o.wage_ducats, 'blurb', o.blurb,
               'port', p.code, 'nation', n.code,
               -- Said out loud, per row: a bonus nothing reads must not look like one that works.
               'takes_effect', (o.specialty = any(v_read)),
               'hired', (po.id is not null),
               'fleet', f.name
             ) order by o.specialty, o.code), '[]'::jsonb)
        from public.officers o
        left join public.ports p on p.id = o.home_port_id
        left join public.nations n on n.id = o.nation_id
        left join public.player_officers po
               on po.officer_id = o.id and po.player_id = v_player
        left join public.fleets f on f.id = po.fleet_id));
end $$;

comment on function world.officers() is
  'The roster, and which of them this house has signed. Supersedes the 0017 definition in its '
  '`specialties_read` list only: SURGEON is read by public.raid_crew_lost since 0027, so all four '
  'specialties now report takes_effect true and the flag has stopped being a disclaimer.';

revoke all on function world.officers() from public, anon;
grant execute on function world.officers() to authenticated;

create or replace function world.skills()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  -- 0027: TRADE_CAP and SPEED join them. ALL FOUR effects are read now — ENDURANCE by
  -- voyage.endurance_days (0016), SPREAD by public.haggle_odds (0022), TRADE_CAP by
  -- world.daily_cap_remaining and SPEED by voyage.fleet_speed (this file). No skill in this game
  -- charges tuition for nothing any more.
  v_read   constant text[] := array['ENDURANCE', 'SPREAD', 'TRADE_CAP', 'SPEED'];
begin
  return jsonb_build_object(
    'max_level', public.wc_int('skill_max_level'),
    'base_cost', public.wc_int('skill_study_base_cost'),
    'effects_read', to_jsonb(v_read),
    'skills', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'code', s.code, 'name', s.name, 'effect', s.effect,
               'pct_per_level', s.pct_per_level, 'blurb', s.blurb,
               'level', coalesce(ps.level, 0),
               'next_cost', case when coalesce(ps.level, 0) >= public.wc_int('skill_max_level')
                                 then null
                                 else public.wc_int('skill_study_base_cost') * (coalesce(ps.level, 0) + 1) end,
               'takes_effect', (s.effect = any(v_read))
             ) order by s.code), '[]'::jsonb)
        from public.skills s
        left join public.player_skills ps on ps.skill_id = s.id and ps.player_id = v_player));
end $$;

comment on function world.skills() is
  'What can be learned, and how far this house has learned it. Supersedes the 0022 definition in '
  'its `effects_read` list only: TRADE_CAP is read by world.daily_cap_remaining and SPEED by '
  'voyage.fleet_speed since 0027, so all four skills report takes_effect true.';

revoke all on function world.skills() from public, anon;
grant execute on function world.skills() to authenticated;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_a constant uuid := '00000000-0027-4000-8000-00000000000a';
  c_b constant uuid := '00000000-0027-4000-8000-00000000000b';
  v_pre_rows  int;   v_drift     int;
  v_cap_rows  int;   v_cap_drift int;
  -- house A: the skills
  v_a       uuid; v_fl_a uuid; v_port_a uuid; v_good_a uuid; v_code_a text;
  v_min     numeric; v_base numeric;
  v_sp0     numeric; v_sp1 numeric; v_sp2 numeric;
  v_nav     numeric; v_skill numeric; v_skill_after numeric; v_off_before numeric;
  v_ceiling numeric;
  v_sk      uuid;
  v_st      numeric; v_frac0 numeric; v_moved numeric;
  v_cap0    numeric; v_cap1 numeric; v_acct numeric;
  v_over    numeric; v_carried numeric;
  v_refused boolean := false;
  -- house B: the surgeon
  v_b       uuid; v_fl_b uuid; v_port_b uuid; v_dest uuid; v_ship uuid;
  v_vid     uuid; v_days int; v_day int; v_i int; v_j int;
  v_occ     boolean; v_hkind text;
  v_crew0   numeric; v_crew1 numeric; v_crew2 numeric;
  v_pay     jsonb;   v_out text; v_base_loss numeric;
  v_surg    numeric; v_expect0 numeric; v_expect2 numeric;
  v_line0   text;    v_line2 text;
  v_tries   int := 0;
  v_offs    jsonb;   v_skl jsonb;
  v_left    int;
  -- findings recorded inside the throwaway subtransaction and read after it is gone
  f_noop_price  boolean := false;
  f_noop_cap    boolean := false;
  f_noop_speed  boolean := false;
  f_noop_crew   boolean := false;
  f_speed       boolean := false;
  f_nodouble    boolean := false;
  f_cap         boolean := false;
  f_surgeon     boolean := false;
  f_prose       boolean := false;
  f_reads       boolean := false;
  f_grant       boolean := false;
begin
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- (a) AND (b) NOTHING MOVED FOR A HOUSE WITH NO SURGEON AND NO SKILLS. Two pre-images, taken
  --     through the OLD functions before they were replaced, re-taken now in the same transaction
  --     and therefore at the same clock and the same drift. The cap one matters most: this file
  --     is the only one of the three that touches a function the BUY path reads.
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  select count(*) into v_pre_rows from quote_before_0027;
  select count(*) into v_cap_rows from cap_before_0027;
  if v_pre_rows < 60 or v_cap_rows < 100 then
    raise exception '0027 self-assert FAIL: the pre-images hold % quote(s) and % allowance(s); the no-op comparisons below would be nearly vacuous', v_pre_rows, v_cap_rows;
  end if;
  select count(*) into v_drift
    from quote_before_0027 b
    cross join lateral world.quote(b.port_id, b.good_id, b.qty, b.side) a
   where (a.units, a.total, a.avg_price, a.end_stock)
         is distinct from (b.units, b.total, b.avg_price, b.end_stock);
  if v_drift = 0 then f_noop_price := true; end if;

  select count(*) into v_cap_drift from cap_before_0027 b
   where world.daily_cap_remaining(null::uuid, b.port_id, b.good_id) is distinct from b.cap;
  if v_cap_drift = 0 then f_noop_cap := true; end if;

  begin
    -- ── inside the throwaway subtransaction ────────────────────────────────────────────────────

    -- ══════════════════════════════════════════════════════════════════════════════════════════
    -- NAVIGATION — the trap. One authority, two terms, and four measurements that tell composing
    -- apart from double-counting.
    -- ══════════════════════════════════════════════════════════════════════════════════════════
    v_a := public.new_house(c_a, 'Casa do Piloto 0027', 'PRT');
    select f.id, f.port_id into v_fl_a, v_port_a from public.fleets f where f.player_id = v_a;
    perform cmd.assume_identity(c_a);

    select min(voyage.ship_speed(s.id)) into v_min
      from public.ships s where s.fleet_id = v_fl_a;
    v_base := v_min * 1.00;                        -- one hull, so DESIGN B.3's formation factor
    v_sp0  := voyage.fleet_speed(v_fl_a);

    -- THE NO-OP, recomputed from 0006's own definition inline rather than asserted in prose.
    if v_sp0 = round(v_base, 4)
       and public.player_skill_bonus(v_a, 'SPEED') = 0
       and public.fleet_officer_bonus(v_fl_a, 'NAVIGATOR') = 0 then
      f_noop_speed := true;
    end if;

    -- The SKILL alone.
    select s.id into v_sk from public.skills s where s.code = 'NAVIGATION';
    insert into public.player_skills (player_id, skill_id, level)
    values (v_a, v_sk, public.wc_int('skill_max_level'))
    on conflict (player_id, skill_id) do update set level = public.wc_int('skill_max_level');
    v_skill      := public.player_skill_bonus(v_a, 'SPEED');
    v_sp1        := voyage.fleet_speed(v_fl_a);
    -- CHECK 1: the OFFICER authority cannot see the skill, so the skill can never be counted
    -- inside the officer cap.
    v_off_before := public.fleet_officer_bonus(v_fl_a, 'NAVIGATOR');

    -- And the OFFICER as well.
    perform cmd.hire_officer('DIASNAV', v_fl_a);
    v_nav         := public.fleet_officer_bonus(v_fl_a, 'NAVIGATOR');
    -- CHECK 2: and the SKILL authority cannot see the officer.
    v_skill_after := public.player_skill_bonus(v_a, 'SPEED');
    v_sp2         := voyage.fleet_speed(v_fl_a);

    if v_skill > 0 and v_nav > 0
       and v_sp1 = round(v_base * (1 + v_skill), 4)
       -- CHECK 3: each term appears EXACTLY once ...
       and v_sp2 = round(v_base * (1 + v_nav) * (1 + v_skill), 4)
       and v_sp2 > v_sp1 and v_sp1 > v_sp0 then
      f_speed := true;
    end if;
    if v_off_before = 0 and v_skill_after = v_skill
       -- CHECK 4: ... and they are MULTIPLIED, not summed. This is the measurement that tells
       -- composition apart from addition; without it (1+a)(1+b) and (1+a+b) are the same claim.
       and v_sp2 <> round(v_base * (1 + v_nav + v_skill), 4) then
      f_nodouble := true;
    end if;

    -- The ceiling, from the KNOBS rather than from a number in a comment.
    v_ceiling := (1 + public.wc_num('officer_bonus_cap_pct') / 100.0)
                 * (1 + public.wc_int('skill_max_level')
                        * (select s.pct_per_level from public.skills s where s.code = 'NAVIGATION')
                        / 100.0);

    -- ══════════════════════════════════════════════════════════════════════════════════════════
    -- ACCOUNTING — the daily allowance, asserted as a NUMBER and then as a BEHAVIOUR.
    -- ══════════════════════════════════════════════════════════════════════════════════════════
    select pg.good_id, g.code into v_good_a, v_code_a
      from public.port_goods pg
      join public.goods g on g.id = pg.good_id
      join public.ports p on p.id = pg.port_id
     where pg.port_id = v_port_a and pg.stock > 200 and not (p.culture = any(g.culture_mask))
     order by g.code limit 1;
    if v_good_a is null then
      raise exception '0027 self-assert FAIL: the starting port holds no tradeable good with stock, so the cap probe would be vacuous';
    end if;
    select pg.stock_target into v_st
      from public.port_goods pg where pg.port_id = v_port_a and pg.good_id = v_good_a;

    -- The probe SETS its own precondition: the shipped allowance is far larger than a starter's
    -- hold, so it could never bind and the behavioural half below would prove nothing. Lower it
    -- until it binds at about ten tuns, and put it back afterwards.
    v_frac0 := public.wc_num('daily_cap_fraction');
    update public.world_config set value = to_jsonb(round(10.0 / v_st, 8))
     where key = 'daily_cap_fraction';

    select coalesce((select td.qty from public.trade_daily td
                      where td.player_id = v_a and td.port_id = v_port_a
                        and td.good_id = v_good_a and td.game_day = world.game_day()), 0)
      into v_moved;
    v_cap0 := world.daily_cap_remaining(v_a, v_port_a, v_good_a);
    if v_cap0 = greatest(0, public.wc_num('daily_cap_fraction') * v_st - v_moved) then
      f_noop_cap := f_noop_cap and true;     -- 0005's definition, recomputed inline, unstudied
    else
      f_noop_cap := false;
    end if;

    -- One tun over the allowance is REFUSED, by code, before anything is studied.
    v_over := floor(v_cap0) + 1;
    begin
      perform cmd.do_buy(v_fl_a, jsonb_build_object('good', v_good_a::text, 'qty', v_over));
      v_refused := false;
    exception when others then
      v_refused := (sqlerrm like 'E_DAILY_CAP%');
    end;

    select s.id into v_sk from public.skills s where s.code = 'ACCOUNTING';
    insert into public.player_skills (player_id, skill_id, level)
    values (v_a, v_sk, public.wc_int('skill_max_level'))
    on conflict (player_id, skill_id) do update set level = public.wc_int('skill_max_level');
    v_acct := public.player_skill_bonus(v_a, 'TRADE_CAP');
    v_cap1 := world.daily_cap_remaining(v_a, v_port_a, v_good_a);

    -- ... and now the SAME order goes through, which is the half a number alone cannot show.
    perform cmd.do_buy(v_fl_a, jsonb_build_object('good', v_good_a::text, 'qty', v_over));
    v_carried := public.fleet_cargo_qty(v_fl_a, v_code_a);

    if v_refused and v_acct > 0
       and v_cap1 = greatest(0, public.wc_num('daily_cap_fraction') * v_st * (1 + v_acct) - v_moved)
       and v_cap1 > v_cap0
       and v_carried >= v_over then
      f_cap := true;
    end if;
    update public.world_config set value = to_jsonb(v_frac0) where key = 'daily_cap_fraction';

    -- ══════════════════════════════════════════════════════════════════════════════════════════
    -- THE SURGEON — proven in the REAL path, on a REAL raid, with an A/B on the SAME roll.
    -- ══════════════════════════════════════════════════════════════════════════════════════════
    v_b := public.new_house(c_b, 'Casa do Cirurgiao 0027', 'PRT');
    select f.id, f.port_id into v_fl_b, v_port_b from public.fleets f where f.player_id = v_b;
    select s.id into v_ship from public.ships s where s.fleet_id = v_fl_b;

    -- A leg out of this port, long enough to give a crossing several days of weather. Chosen
    -- DETERMINISTICALLY (the longest under 1,500 nm, ties broken by port code) rather than by heap
    -- order, and bounded above so the settle below does not walk sixty voyage-days.
    select case when l.from_port_id = v_port_b then l.to_port_id else l.from_port_id end
      into v_dest
      from public.legs l
      join public.ports d
        on d.id = case when l.from_port_id = v_port_b then l.to_port_id else l.from_port_id end
     where (l.from_port_id = v_port_b or l.to_port_id = v_port_b)
       and l.distance_nm < 1500
     order by l.distance_nm desc, d.code limit 1;
    if v_dest is null then
      raise exception '0027 self-assert FAIL: no leg under 1500 nm leaves the starting port, so the raid probe has nowhere to sail';
    end if;

    -- THE PRECONDITION THIS PROBE OWNS: every sea at DESIGN B.6's worst authored hazard and full
    -- of raiders, and the clamp lifted out of the way. A raid is then a matter of a short search
    -- rather than of luck, and the search RAISES if it finds nothing instead of passing quietly.
    update public.seas set hazard_base = 0.05, piracy_index = 1.0;
    update public.world_config set value = to_jsonb(1.0) where key = 'hazard_p_max';

    v_day := null;
    for v_i in 1 .. 200 loop
      v_tries := v_i;
      v_vid   := voyage.depart(v_fl_b, array[v_port_b, v_dest]);
      v_days  := voyage.total_days(v_vid);
      for v_j in 1 .. v_days loop
        select h.occurred, h.kind into v_occ, v_hkind from voyage.hazard_roll(v_vid, v_j) h;
        if v_occ and v_hkind = 'PIRATES' then v_day := v_j; exit; end if;
      end loop;
      exit when v_day is not null;
      -- discard the attempt whole: the roll is a pure function of the voyage id, so a new id is
      -- the only way to get a different crossing.
      delete from public.voyages where id = v_vid;
      update public.fleets set status = 'DOCKED', port_id = v_port_b where id = v_fl_b;
    end loop;
    if v_day is null then
      raise exception '0027 self-assert FAIL: no PIRATES day in % departures with every sea at the worst authored hazard; the raid probe examined nothing and must not pass', v_tries;
    end if;

    -- Settle up to the day BEFORE the raid, so the crew count below is the one the raid acts on.
    for v_j in 1 .. (v_day - 1) loop
      perform voyage.settle(v_fl_b, voyage.day_ends_at(v_vid, v_j) + interval '1 second');
    end loop;
    select s.crew into v_crew0 from public.ships s where s.id = v_ship;

    -- THE RAID, with NO surgeon aboard.
    perform voyage.settle(v_fl_b, voyage.day_ends_at(v_vid, v_day) + interval '1 second');
    select ve.payload into v_pay from public.voyage_events ve
     where ve.voyage_id = v_vid and ve.day_index = v_day;
    select s.crew into v_crew1 from public.ships s where s.id = v_ship;
    v_out       := v_pay->>'outcome';
    v_base_loss := (v_pay->>'base_loss')::numeric;
    v_line0     := voyage.report_line(v_day, 'PIRATES', v_pay);

    if v_base_loss = 0 then
      raise exception '0027 self-assert FAIL: the raid resolved % , which costs no hands at all, so the A/B below would compare nothing. Re-tune the probe rather than accepting a vacuous pass', v_out;
    end if;

    -- THE NO-OP: with nobody aboard, raid_crew_loss gives back DESIGN B.6's own figure and the
    -- hulls lose exactly what 0007's `floor(crew * 0.98 / 0.90 / 0.70)` always took.
    v_expect0 := floor(v_crew0 * (1 - v_base_loss));
    if public.raid_crew_lost(v_fl_b, v_crew0, v_base_loss) = v_crew0 - v_expect0
       and v_crew1 = greatest(0, v_expect0)
       and (v_pay->>'crew_lost')::numeric = v_crew0 - v_crew1
       and (v_pay->>'surgeon_pct')::numeric = 0 then
      f_noop_crew := true;
    end if;

    -- ── THE A/B, ON THE SAME ROLL. Wind the voyage back to the morning of the raid, sign a
    --    surgeon, and let the SAME day happen again: the hazard is a pure function of (voyage,
    --    day, secret), so this is the identical raid with one thing changed. Two different
    --    voyages would have been two different raids and would have proved nothing about size.
    delete from public.voyage_events where voyage_id = v_vid and day_index = v_day;
    update public.voyages set status = 'SAILING', last_settled_day = v_day - 1 where id = v_vid;
    update public.fleets  set status = 'SAILING', port_id = null where id = v_fl_b;
    update public.ships   set crew = v_crew0 where id = v_ship;

    perform cmd.assume_identity(c_b);
    perform cmd.hire_officer('ZAHRA', v_fl_b);
    v_surg := public.fleet_officer_bonus(v_fl_b, 'SURGEON');

    perform voyage.settle(v_fl_b, voyage.day_ends_at(v_vid, v_day) + interval '1 second');
    select ve.payload into v_pay from public.voyage_events ve
     where ve.voyage_id = v_vid and ve.day_index = v_day;
    select s.crew into v_crew2 from public.ships s where s.id = v_ship;
    v_line2   := voyage.report_line(v_day, 'PIRATES', v_pay);
    v_expect2 := v_crew0 - floor((v_crew0 - v_expect0) * (1 - v_surg));

    if v_surg > 0
       and v_pay->>'outcome' = v_out                       -- the SAME raid
       and (v_pay->>'base_loss')::numeric = v_base_loss    -- DESIGN B.6's table did not move
       and public.raid_crew_lost(v_fl_b, v_crew0, v_base_loss)
           = floor((v_crew0 - v_expect0) * (1 - v_surg))
       and v_crew2 = greatest(0, v_expect2)
       and v_crew2 > v_crew1                               -- strictly fewer hands lost
       and (v_pay->>'crew_lost')::numeric = v_crew0 - v_crew2
       and (v_pay->>'surgeon_pct')::numeric = round(v_surg * 100, 2) then
      f_surgeon := true;
    end if;

    -- AND THE CAPTAIN IS TOLD. A surgeon who saves five hands in a report that never mentions
    -- them is a bonus the player cannot see working.
    if v_line0 <> v_line2
       and v_line0 like '%hands%'
       and v_line2 like '%surgeon%'
       and v_line0 not like '%surgeon%' then
      f_prose := true;
    end if;

    -- ══════════════════════════════════════════════════════════════════════════════════════════
    -- AND NO CARD CLAIMS TO BE INERT ANY MORE — nor the reverse.
    -- ══════════════════════════════════════════════════════════════════════════════════════════
    v_offs := world.officers();
    v_skl  := world.skills();
    if jsonb_array_length(v_offs->'specialties_read') = 4
       and (v_offs->'specialties_read') ? 'SURGEON'
       and (select bool_and((e->>'takes_effect')::boolean)
              from jsonb_array_elements(v_offs->'officers') e)
       and jsonb_array_length(v_skl->'effects_read') = 4
       and (v_skl->'effects_read') ? 'TRADE_CAP' and (v_skl->'effects_read') ? 'SPEED'
       and (select bool_and((e->>'takes_effect')::boolean)
              from jsonb_array_elements(v_skl->'skills') e)
       -- and the flags are not simply hard-wired true: every specialty and every effect the
       -- catalogue actually holds must appear in the read's list, so a fifth one added tomorrow
       -- without a rule would go red here.
       and not exists (select 1 from public.officers o
                        where not ((v_offs->'specialties_read') ? o.specialty))
       and not exists (select 1 from public.skills s
                        where not ((v_skl->'effects_read') ? s.effect)) then
      f_reads := true;
    end if;

    raise exception '__PROBE_ROLLBACK_0027__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK_0027__' then raise; end if;
  end;
  -- ── the subtransaction is gone; the findings survived it, because plpgsql variables are not
  --    transactional. Assert on them now. ────────────────────────────────────────────────────────

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);

  if not f_noop_price then
    raise exception '0027 self-assert FAIL: % of % pre-image quote(s) moved for a house with no surgeon and no skills. All three wirings are opt-in and none of them was allowed to move the ordinary economy', v_drift, v_pre_rows;
  end if;
  if not f_noop_cap then
    raise exception '0027 self-assert FAIL: % of % pre-image daily allowance(s) moved with ACCOUNTING unstudied, or the unstudied allowance is no longer 0005''s expression recomputed inline', v_cap_drift, v_cap_rows;
  end if;
  if not f_noop_speed then
    raise exception '0027 self-assert FAIL: with nothing studied and nobody posted the fleet reads % kn where 0006''s formation figure is %', v_sp0, round(v_base, 4);
  end if;
  if not f_noop_crew then
    raise exception '0027 self-assert FAIL: with no surgeon aboard a % raid took the fleet from % hands to % where DESIGN B.6''s own table says %, so the supersede is not the no-op it must be', v_out, v_crew0, v_crew1, v_expect0;
  end if;
  if not f_speed then
    raise exception '0027 self-assert FAIL: speed went % -> % (skill %) -> % (skill + navigator %), which is not base x (1 + nav) x (1 + skill) on a base of %', v_sp0, v_sp1, v_skill, v_sp2, v_nav, round(v_base, 4);
  end if;
  if not f_nodouble then
    raise exception '0027 self-assert FAIL: NAVIGATION and the NAVIGATOR are DOUBLE-COUNTING — the officer authority read % before the skill was studied, the skill authority read % after the officer was hired, or the speed equals the SUM form rather than the product. This is the exact defect 0016 refused to risk and it must never be shipped', v_off_before, v_skill_after;
  end if;
  if not f_cap then
    raise exception '0027 self-assert FAIL: the allowance went % -> % on a bonus of % (refused-before = %, carried after = % of % asked); ACCOUNTING is not lifting the daily cap by exactly what player_skill_bonus says it is worth', v_cap0, v_cap1, v_acct, v_refused, v_carried, v_over;
  end if;
  if not f_surgeon then
    raise exception '0027 self-assert FAIL: on the SAME % raid a % surgeon took the fleet from % hands to % where the arithmetic says %, against % with nobody aboard', v_out, round(v_surg * 100, 2), v_crew0, v_crew2, v_expect2, v_crew1;
  end if;
  if not f_prose then
    raise exception '0027 self-assert FAIL: the after-action report reads the same with and without a surgeon aboard — "%" against "%". A bonus the player cannot see working is a bonus that does not exist', v_line0, v_line2;
  end if;
  if not f_reads then
    raise exception '0027 self-assert FAIL: world.officers().specialties_read or world.skills().effects_read still omits an effect a rule now reads, or names one the catalogue does not hold';
  end if;

  -- The rollback really rolled back, knobs and world data included.
  select count(*) into v_left from public.players pl where pl.auth_uid in (c_a, c_b);
  if v_left <> 0 then
    raise exception '0027 self-assert FAIL: % probe house(s) survived the subtransaction', v_left;
  end if;
  select count(*) into v_left from public.seas
   where hazard_base > 0.03 or piracy_index >= 1.0;
  if v_left <> 0 then
    raise exception '0027 self-assert FAIL: % sea(s) were left at the probe''s worst-case weather', v_left;
  end if;
  if public.wc_num('hazard_p_max') <> 0.060 or public.wc_num('daily_cap_fraction') <> 0.35 then
    raise exception '0027 self-assert FAIL: the probe left a knob moved — hazard %, cap fraction %',
      public.wc_num('hazard_p_max'), public.wc_num('daily_cap_fraction');
  end if;

  -- POSTURE. This file grants nothing and revokes nothing, and `create or replace` must not have
  -- quietly changed an ACL: the two client reads still reach their functions, the machinery does
  -- not, and both halves of the lockdown still read zero.
  if has_function_privilege('authenticated', 'world.officers()', 'execute')
     and has_function_privilege('authenticated', 'world.skills()', 'execute')
     and not has_function_privilege('anon', 'world.officers()', 'execute')
     and not has_function_privilege('anon', 'world.skills()', 'execute')
     and not has_function_privilege('authenticated', 'public.raid_crew_lost(uuid, numeric, numeric)', 'execute')
     and not has_function_privilege('anon', 'public.raid_crew_lost(uuid, numeric, numeric)', 'execute')
     and not has_function_privilege('authenticated', 'world.daily_cap_remaining(uuid, uuid, uuid)', 'execute')
     and not has_function_privilege('authenticated', 'voyage.settle(uuid, timestamptz)', 'execute')
     and not has_function_privilege('anon', 'voyage.settle(uuid, timestamptz)', 'execute')
     and not has_function_privilege('authenticated', 'public.fleet_officer_bonus(uuid, text)', 'execute')
     and not has_function_privilege('authenticated', 'public.player_skill_bonus(uuid, text)', 'execute')
     and (select count(*) from public.client_write_grants()) = 0
     and (select count(*) from public.client_executable_writers()) = 0
     and (select count(*) from public.client_rpc_entry_points() e where e.fn is null) = 0
     and (select count(*) from public.caller_evaluated_functions()) = 0 then
    f_grant := true;
  end if;
  if not f_grant then
    raise exception '0027 self-assert FAIL: a re-cut function changed its ACL — the two client reads must still be reachable by authenticated and not by anon, and raid_crew_lost, daily_cap_remaining, settle and both bonus authorities must be reachable by neither';
  end if;

  raise notice '0027 self-assert ok: the last three inert bonuses are wired, and NOTHING is inert in this game any more — world.officers().specialties_read names all 4 specialties and world.skills().effects_read all 4 effects, with every card reporting takes_effect true and every specialty and effect the catalogues hold present in those lists; the SURGEON is proven on a REAL raid found by searching % departure(s) with every sea at the worst authored hazard — the same % raid was replayed on the SAME deterministic roll with a % per cent surgeon signed on, taking the fleet from % hands to % where nobody aboard had left %, exactly % hands less the % the surgeon at % per cent pulled through, and the report changed from "%" to "%" so the player can see it working; with no surgeon the loss is DESIGN B.6''s own table to the hand, which is the supersede being a no-op; ACCOUNTING lifts the daily allowance from % to % tuns at a bonus of % per cent, and the SAME order that was refused E_DAILY_CAP before the tuition went through after it; NAVIGATION is RESOLVED rather than deferred a third time — voyage.fleet_speed is still the ONE answer to how fast she sails and this file mints no second one, the fleet reading % kn unofficered and unstudied (0006''s figure), % with the skill, and % with both, which is EXACTLY base x (1 + % per cent navigator) x (1 + % per cent skill) and is NOT the sum form; the two are proven not to double-count because the officer authority read % per cent before the skill was studied and the skill authority read % per cent after the officer was hired, so neither can be counted inside the other''s cap, and the reachable ceiling from the knobs is x%; the ordinary economy is BYTE-IDENTICAL across % real quotes and % real daily allowances taken before these functions were replaced, of which % and % moved; voyage.settle was SLICED rather than retyped, so the wage, ration and day-boundary arithmetic proof 01 matches to the character is unchanged by construction; and this file grants and revokes NOTHING — 0 client write grants, 0 client-executable writers, 0 read-wall gaps',
    v_tries, v_out, round(v_surg * 100, 2), v_crew0, v_crew2, v_crew1,
    v_crew0 - v_expect0, (v_crew0 - v_expect0) - (v_crew0 - v_crew2), round(v_surg * 100, 2), v_line0, v_line2,
    round(v_cap0, 2), round(v_cap1, 2), round(v_acct * 100, 2),
    v_sp0, v_sp1, v_sp2, round(v_nav * 100, 2), round(v_skill * 100, 2),
    round(v_off_before * 100, 2), round(v_skill_after * 100, 2), round(v_ceiling, 4),
    v_pre_rows, v_cap_rows, v_drift, v_cap_drift;
end $$;

drop table quote_before_0027;
drop table cap_before_0027;
