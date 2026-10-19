CREATE OR REPLACE FUNCTION voyage.settle(p_fleet uuid, p_now timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  v_report  uuid;     -- 0122: the VOYAGE_REPORT the wages flow references
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
  -- 0059: what a fair wind made up, and what went over the side.
  v_gain      numeric;
  v_stores    numeric;
  v_bonus     jsonb;     -- 0155 (K3): the sailing bonus's answer, for the report
  v_fight     jsonb;     -- 0189: the fight's answer (voyage.fight) while combat_bite is on, else null
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
    -- 0086: THE ONE SUM. public.crew_wages is what the Inn quotes for any crew count, so the
    -- figure a player reads before hiring is the figure this day charges — by construction.
    -- 0114: a merchant company pays npc_cost_mult of the day's wages (public.running_cost_mult).
    -- 0154 (K2): the day's wage is public.fleet_wage — THE one reading (crew_wages × running_cost_mult, less
    -- Pursership while skills_bite), the figure world.crew_cost quotes for this fleet.
    v_wages := public.fleet_wage(p_fleet, v_short);
    if v_wages > 0 then
      -- 0128: OWED, NOT PAID (owner, 2026-10-15: "pay wages only when a profit is made"). The day's
      -- wage joins what the fleet owes her crew (public.owe_wages: carried, capped); cmd.do_sell pays
      -- it out of profit (public.pay_wages).
      perform public.owe_wages(p_fleet, v_wages);
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
        -- 0154 (K2): the one storm rule (Weather Lore at departure); 0168 (S4): less what her armour turns
        v_lost := public.armour_turns(s.id, voyage.storm_hull_lost(v.id, s.maxd, h.magnitude));
        update public.ships set durability = greatest(0, s.durability - v_lost) where id = s.id;
        v_hull := v_hull + v_lost;
      end loop;
      v_delay   := voyage.day_delay_for(v.id, h.kind, h.magnitude, voyage.delay_before_day(v.id, d));   -- 0125: DESIGN B.6 +1.5 days, the one table (0154: for this voyage)
      v_payload := v_payload || jsonb_build_object('hull_lost', v_hull, 'delay_hours', v_delay);

    elsif h.occurred and h.kind = 'CALM' then
      v_kind    := 'CALM';
      v_delay   := voyage.day_delay_for(v.id, h.kind, h.magnitude, voyage.delay_before_day(v.id, d));   -- 0125: DESIGN B.6 1-4 days, the one table (0154: less Light-air)
      v_payload := v_payload || jsonb_build_object('delay_hours', v_delay);

    elsif h.occurred and h.kind = 'PIRATES' then
      v_kind := 'PIRATES';
      -- DESIGN B.6's escort score — 0168 (S4): voyage.escort_score, the one reading (the class's own figure
      -- while combat_bite is off; what she carries, attack / 10, while it is on). The ENTIRE combat system.
      v_escort := voyage.escort_score(p_fleet);
      select coalesce(s2.piracy_index, 0) * 40 * (0.5 + h.magnitude) into v_raider
        from public.seas s2 where s2.id = (voyage.leg_at_day(v.id, d)->>'sea_id')::uuid;
      -- 0189: THE FIGHT. While combat_bite is on, voyage.fight decides — sighting, rounds of range, accuracy,
      -- attack and armour, then the boarding — and says what each hull lost to the shot, written here whatever
      -- the outcome. While it is off, DESIGN B.6's ratio table, as before.
      v_fight := case when public.combat_bite_on() then voyage.fight(v.id, d, p_fleet, v_raider) end;
      if v_fight is not null then
        v_outcome := v_fight->>'outcome';
        update public.ships sh
           set durability = greatest(0, sh.durability - (v_fight->'hull_lost'->>sh.id::text)::numeric)
         where sh.fleet_id = p_fleet and v_fight->'hull_lost' ? sh.id::text;
      else
      v_ratio := case when v_raider <= 0 then 99 else v_escort / v_raider end;
      if    v_ratio >= 2.0 then v_outcome := 'EVADED';
      elsif v_ratio >= 1.2 then v_outcome := 'DRIVEN_OFF';
      elsif v_ratio >= 0.7 then v_outcome := 'RANSOM';
      elsif v_ratio >= 0.3 then v_outcome := 'PLUNDERED';
      else                      v_outcome := 'STRIPPED';
      end if;
      end if;
      -- 0189: while the fight decides, its own sentence ("They came alongside and we threw them back."): true of
      -- THIS fight, where the table's "We fired twice …" would contradict the rounds printed beneath it
      v_prose := coalesce(v_fight->>'sentence', case v_outcome
        when 'EVADED'     then 'They stood off and did not close.'
        when 'DRIVEN_OFF' then 'We fired twice and they sheered away.'
        when 'RANSOM'     then 'We paid them off rather than fight.'
        when 'PLUNDERED'  then 'They came aboard and took what they could carry.'
        else 'They took everything but the ship itself.' end);
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
               -- 0168 (S4): the raid's hull loss less what her armour turns (public.armour_turns; at 0, the loss itself)
               -- 0189: while the fight decides (v_fight), it has written the hull already — the crew loss only
               durability = case when v_fight is not null then sh.durability
                            else greatest(0, sh.durability - public.armour_turns(sh.id,
                              sh.durability - sh.durability * (case v_outcome when 'DRIVEN_OFF' then 0.95
                                                                              when 'PLUNDERED' then 0.80
                                                                              else 1.00 end))) end
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
                                                   'surgeon_pct', round(public.crew_pct(p_fleet, null, 'crew_saved') * 100, 2))
                   -- 0189: the battle report, in words, and what the fight was (only when one was fought)
                   || case when v_fight is null then '{}'::jsonb
                           else jsonb_build_object('rounds', v_fight->'rounds',
                                                   'fight', (v_fight - 'rounds' - 'outcome' - 'sentence' - 'hull_lost')
                                                            || jsonb_build_object('hull_lost',
                                                                 (select coalesce(sum(hl.value::numeric), 0)
                                                                    from jsonb_each_text(v_fight->'hull_lost') hl))) end;
    elsif h.occurred and h.kind = 'FAIR_WIND' then
      -- 0059. THE FIRST GOOD DAY AT SEA, and the mirror of CALM's arm: it SUBTRACTS delay hours.
      -- BOUNDED BY WHAT SHE HAS ALREADY LOST, and that bound is not tidiness. voyages.delay_hours
      -- is `check (delay_hours >= 0)` (0006:67) and voyage.recompute_eta writes the sum of every
      -- event's delay into it, so an unbounded gain would abort a settlement on a CHECK and, worse,
      -- land a fleet before she could have sailed. voyage.delay_before_day is the EXISTING single
      -- authority for "how much delay had this voyage accrued before day N" (0006:475) — composed
      -- onto here rather than the events summed a second time. By induction the running total never
      -- goes below zero. A voyage that has lost nothing makes up nothing, and the report says so.
      --
      -- AND IT IS BOUNDED ABOVE BY LESS THAN ONE VOYAGE-DAY (6 to 22.8 hours), which is the second
      -- invariant and was MEASURED rather than reasoned about: voyage.day_ends_at(d) is
      -- `departed_at + (d x 24 + delay_before_day(d)) x k`, so a gain of 24 hours or more moves day
      -- d+1's boundary TO OR BEFORE day d's and the schedule inverts — settle then resolves two
      -- checkpoints where the player was told there was one. The first draft of this file gained up
      -- to 48 hours and its own probe caught exactly that. A fair wind compresses the schedule; it
      -- never folds it.
      v_kind    := 'FAIR_WIND';
      v_gain    := -voyage.day_delay_for(v.id, h.kind, h.magnitude, voyage.delay_before_day(v.id, d));   -- 0125: the one table (0154: for this voyage)
      v_delay   := -v_gain;
      v_payload := v_payload || jsonb_build_object('hours_gained', v_gain, 'delay_hours', v_delay);

    elsif h.occurred and h.kind = 'FOUL_WATER' then
      -- 0059. The casks are broached and what is in them goes over the side. It takes water_t — the
      -- thing every SAIL is gated on through voyage.endurance_days — so a bad sea costs her reach
      -- rather than her paint. Shaped exactly like STORM's arm, one hull at a time, because the
      -- fleet sails in company and each drinks from her own casks.
      v_kind := 'FOUL_WATER';
      v_stores := 0;
      for s in select sh.id, sh.water_t from public.ships sh where sh.fleet_id = p_fleet loop
        v_lost := round(s.water_t * (0.10 + 0.25 * h.magnitude), 3);
        update public.ships set water_t = greatest(0, s.water_t - v_lost) where id = s.id;
        v_stores := v_stores + v_lost;
      end loop;
      v_payload := v_payload || jsonb_build_object('stores_lost', v_stores);

    elsif h.occurred and h.kind = 'SHOAL_WATER' then
      -- 0059. Grounding killed more ships than gunfire. STORM's arm at a lighter coefficient (4-15
      -- per cent of rated durability against STORM's 8-25), and it reuses STORM's own `hull_lost`
      -- payload key on purpose: one payload vocabulary, so the report reads the same way whatever
      -- took the planking. It costs no hours — she came off, and she sailed on.
      v_kind := 'SHOAL_WATER';
      v_hull := 0;
      for s in select sh.id, sh.durability, c.durability maxd
                 from public.ships sh join public.ship_classes c on c.id = sh.class_id
                where sh.fleet_id = p_fleet loop
        -- 0189: less what her armour turns (public.armour_turns; at 0, the loss itself)
        v_lost := public.armour_turns(s.id, round(s.maxd * (0.04 + 0.11 * h.magnitude), 2));
        update public.ships set durability = greatest(0, s.durability - v_lost) where id = s.id;
        v_hull := v_hull + v_lost;
      end loop;
      v_payload := v_payload || jsonb_build_object('hull_lost', v_hull);

    elsif h.occurred and h.kind in ('DERELICT', 'CONSORT') then
      -- 0059. THEY TOUCH NO SHIP AT ALL — 0055's words, and the reason is that neither has anyone
      -- to touch it with: an event has no SUBJECT (PLATFORM §3 seam 2 is unbuilt), so a derelict
      -- cannot hand over a named cargo and a consort cannot be a named ship. DERELICT writes no
      -- `salvage` key, which is not an omission: voyage.report_line's fallback arm prints "a little
      -- cordage" for exactly this, and 0055's assert (f) already proved it reads. The slice that
      -- gives an event a subject is the named writer of that key.
      v_kind := h.kind;

    elsif h.occurred then
      -- NO_SPAGHETTI §7C. Without this an occurred kind with no arm falls through to the `else`
      -- below and is recorded as a QUIET WATCH — a hazard silently deleted from the game, green
      -- everywhere. Unreachable today (all eight in-mix kinds are handled) and it is the guard for
      -- the ninth.
      raise exception 'E_KIND_ARM: % befell voyage % on day % and voyage.settle has no arm for it — a drawn kind with no arm would be written down as a quiet watch', h.kind, v.id, d
        using errcode = 'P0001';

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

    update public.voyages set last_settled_day = d where id = v.id;   -- 0128: a sea-day pays no wage
    if v_delay <> 0 then perform voyage.recompute_eta(v.id); end if;
    select * into v from public.voyages where id = v.id;
    v_resolved := v_resolved + 1;
  end loop;

  -- ── arrival
  if p_now >= v.eta then
    update public.voyages set status = 'ARRIVED', last_settled_day = voyage.total_days(v.id) where id = v.id;
    -- 0047: she docks at a HARBOUR or a SEA PLACE; at a bare point of water she comes to ANCHOR,
    -- holding the exact coordinate her course ends at. UNABLE_TO_SAIL still outranks both, and an
    -- open-water end keeps its position either way.
    update public.fleets
       set status = case when (select durability from public.ships where fleet_id = p_fleet and is_flagship) <= 0
                         then 'UNABLE_TO_SAIL'
                         when v.dest_port_id is null then 'ANCHORED'
                         else 'DOCKED' end,
           port_id = v.dest_port_id,
           lat = case when v.dest_port_id is null then (v.path->(jsonb_array_length(v.path)-1)->'b'->>0)::numeric end,
           lon = case when v.dest_port_id is null then (v.path->(jsonb_array_length(v.path)-1)->'b'->>1)::numeric end,
           version = version + 1
     where id = p_fleet;
    -- 0036 SEA PLACE: landfall in open water is an EVENT — the only thing that is out there.
    insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at)
    select v.id, voyage.total_days(v.id) + 1, 'LANDFALL',
           jsonb_build_object('place', sp.name, 'remark', sp.approach), v.eta
      from public.ports sp
     where sp.id = v.dest_port_id and sp.kind = 'SEA_PLACE'
    on conflict (voyage_id, day_index) do nothing;
    -- 0155 (K3, D6): THE SAILING BONUS — a passage of at least skill_sp_arrival_min_nm adds skill_sp_per_arrival
    -- skill points to the skill in training (public.skill_sp_grant_for: capped a day; nothing for a merchant, who
    -- has no queue). The knob at 0 is OFF, and then nothing below is read or written.
    if public.wc_num('skill_sp_per_arrival') > 0 and v.total_nm >= public.wc_num('skill_sp_arrival_min_nm') then
      v_bonus := public.skill_sp_grant_for(f.player_id, public.wc_num('skill_sp_per_arrival'));
    end if;
    v_report := public.emit_event(f.player_id, 'VOYAGE_REPORT', jsonb_build_object(
      'fleet', f.name,
      'voyage_id', v.id,
      'from', (select code from public.ports where id = v.origin_port_id),
      'to',   (select code from public.ports where id = v.dest_port_id),
      -- 0047: an open-water end has no code; the report carries the point instead, and a screen
      -- prints the coordinate rather than inventing a name for nowhere.
      'from_point', case when v.origin_port_id is null then v.path->0->'a' end,
      'to_point',   case when v.dest_port_id  is null then v.path->(jsonb_array_length(v.path)-1)->'b' end,
      'total_nm', v.total_nm,
      'lines', (select coalesce(jsonb_agg(voyage.report_line(ve.day_index, ve.kind, ve.payload) order by ve.day_index), '[]'::jsonb)
                  from public.voyage_events ve where ve.voyage_id = v.id))
      -- 0155: the bonus's own words, when it was asked
      || case when v_bonus is null then '{}'::jsonb else jsonb_build_object('training', v_bonus) end
      -- 0189: `fights` — for each day fought in rounds, the index of its line in `lines` (the same order) and
      -- its rounds; absent when none was, so a report without a fight is the report it always was
      || (select case when count(*) = 0 then '{}'::jsonb
                      else jsonb_build_object('fights', jsonb_agg(jsonb_build_object('line', z.n - 1, 'rounds', z.payload->'rounds')
                                                                  order by z.n)) end
            from (select ve.payload, row_number() over (order by ve.day_index) as n
                    from public.voyage_events ve where ve.voyage_id = v.id) z
           where z.payload ? 'rounds'));
    -- 0122: the leg's wages reach the HARBOUR she made (a sea place or open water has no purse).
    if v.wages_paid > 0
       and exists (select 1 from public.ports hp where hp.id = v.dest_port_id and hp.kind = 'HARBOUR') then
      perform public.treasury_post(v.dest_port_id, 'WAGES', v.wages_paid, f.player_id, v_report);
    end if;
    -- 0123: the coupons a city set aside for this house are collected at the harbour she makes.
    if v.dest_port_id is not null and public.city_treasury_on() then   -- dark: nothing read, nothing written
      perform public.collect_coupons(f.player_id, v.dest_port_id, v_report);
    end if;
    -- 0127: WHAT THE VOYAGE TAUGHT HER — public.voyage_xp (her miles, the pirates she saw off) to every
    -- hull in the fleet, and to every officer posted to it who was aboard when she departed
    -- (officer_xp.aboard_since, else her signing). THE ONE WRITER of a player's experience. A
    -- merchant's is constant (owner, 2026-10-15): one read of players.is_npc, and nothing is written.
    if not (select p.is_npc from public.players p where p.id = f.player_id) then
      insert into public.ship_xp (ship_id, xp)
      select sh.id, public.voyage_xp(v.id) from public.ships sh where sh.fleet_id = p_fleet
      on conflict (ship_id) do update set xp = public.ship_xp.xp + excluded.xp;
      -- 0158 (S13): WHAT THE VOYAGE WORE — public.wear_units_for, the one writer of wear (miles, pirates
      -- days, storm days, by what works each item). Players only: this block; a merchant's gear never wears.
      perform public.wear_units_for(p_fleet, v.id);
      -- 0160 (K6): HER THREE TRACKS — the voyage's miles to Exploration and the pirates seen off to Combat
      -- (public.voyage_xp_tracks), through the one writer (her cabin's rate per track; Leadership while skills
      -- bite; only captains aboard when she departed; a merchant's have no row). And HOME: a captain whose fleet
      -- makes port in her home region is no longer homesick (her clock is the voyage's arrival instant).
      perform public.captain_xp_credit(p_fleet, x.exploration, 0, x.combat, v.departed_at)
         from public.voyage_xp_tracks(v.id) x;
      -- 0161 (K8): and the company's promotion items, at the arrival port (anchored at sea, the points wait)
      perform public.promotion_credit(f.player_id, v.dest_port_id, 'exploration', x.exploration),
              public.promotion_credit(f.player_id, v.dest_port_id, 'combat', x.combat)
         from public.voyage_xp_tracks(v.id) x;
      update public.captain_state st set home_seen_at = v.eta
        from public.captain_seats cs
        join public.ships sh2 on sh2.id = cs.ship_id
        join public.player_officers po on po.id = cs.player_officer_id
        join public.officers o on o.id = po.officer_id
        join public.ports hp on hp.id = o.home_port_id
       where st.player_officer_id = cs.player_officer_id and sh2.fleet_id = p_fleet
         and hp.region_id = (select ap.region_id from public.ports ap where ap.id = v.dest_port_id);
    end if;
    -- 0034 STANDING ORDER: fires HERE, the one place a fleet makes port — after she docks,
    -- before her queued orders run, so a queued onward SAIL departs provisioned.
    perform cmd.run_standing_provision(p_fleet);
    perform cmd.advance(p_fleet, p_now);
  end if;

  return v_resolved;
end $function$
