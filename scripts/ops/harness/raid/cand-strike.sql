create or replace function voyage.fight_resolve(p_voyage uuid, p_day int, p_raider numeric, p_escort numeric, p_ships jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0189: THE FIGHT — the one combat authority. A raid on (voyage, day) by raiders of strength p_raider
-- (DESIGN B.6's piracy × 40 × (0.5 + magnitude)) against a fleet whose escort score is p_escort
-- (voyage.escort_score) and whose hulls are p_ships, an array of
--   {id, name, tier, hull, maxd, crew, attack, accuracy, reach, armour, sighting, boarder_pct, boarder, gunner, gear[]}
-- (voyage.fight builds it from the live fleet; a simulation may pass its own). A pure function of its
-- arguments, the fight_* knobs, armour_turns_pct and the world secret: every chance is a voyage.rng stream
-- of (voyage, day), so the same day fought twice is the same fight, word for word.
--   SIZING UP raiders do not close on a fleet fight_standoff_ratio times their strength or more (DESIGN B.6's
--             EVADED band, escort / raider): EVADED, no shot fired.
--   SIGHTING  the better lookout (her best sighting against the raiders' class) fires the first round alone;
--             a lead may let her slip away before a shot (fight_evade_per_sighting × lead, ≤ fight_evade_max).
--   ROUNDS    fight_ranges, in order. At LONG range only guns whose reach is at least the other side's fire —
--             range decides WHO can fire. A gun hits on accuracy / 100 × the range's share (5–95 %); a hit
--             takes attack × fight_damage_per_attack × (0.75–1.25) of hull, less armour (public.armour_soak).
--             The raiders' shots fall on the hulls by their size. They break off at fight_raider_break of
--             their hull lost: EVADED if they never touched her, DRIVEN_OFF if they did.
--   BOARDING  if they have not broken off: each side's hulls, (crew × fight_hand_value × (1 + the Boarder's
--             share) + tier × 3) × the share of its hull left — DESIGN B.6's crew and size terms, a hand
--             weighed for a fight hand to hand — read against fight_board_bands: DRIVEN_OFF, RANSOM,
--             PLUNDERED, STRIPPED.
-- Returns {outcome, sentence (the day's one line, in DESIGN B.6's voice, true of THIS fight), rounds[] (the battle
-- report, in words), hull_lost {ship id: points}, raiders{…}, first, hits{yours, theirs}}. What an outcome costs in crew and cargo stays DESIGN B.6's, in voyage.settle.
declare
  c        public.ship_classes%rowtype;
  v_ranges jsonb := public.wc('fight_ranges');
  v_k      numeric := public.wc_num('fight_damage_per_attack');
  v_break  numeric := public.wc_num('fight_raider_break');
  v_bands  jsonb := public.wc('fight_board_bands');
  v_n      int := coalesce(jsonb_array_length(p_ships), 0);
  x        jsonb;
  i        int;
  j        int;
  g        int;
  t        int;
  a_id     uuid[] := '{}';
  a_name   text[] := '{}';
  a_att    numeric[] := '{}';
  a_acc    numeric[] := '{}';
  a_reach  numeric[] := '{}';
  a_arm    numeric[] := '{}';
  a_hull0  numeric[] := '{}';
  a_hull   numeric[] := '{}';
  a_maxd   numeric[] := '{}';
  a_crew   numeric[] := '{}';
  a_bpct   numeric[] := '{}';
  a_tier   numeric[] := '{}';
  v_hand   numeric := public.wc_num('fight_hand_value');
  a_taken  numeric[];
  v_one    numeric;
  r_n      numeric;
  r_hull0  numeric;
  r_hull   numeric;
  r_att    numeric;
  r_crew   numeric;
  r_shots  int;
  p_sight  numeric := 0;
  p_reach  numeric := 0;
  v_first  text;
  v_lines  text[] := '{}';
  v_outcome text;
  v_sentence text;
  v_range  text;
  v_mult   numeric;
  v_can    int;
  v_fired  int;
  v_hits   int;
  v_dealt  numeric;
  r_can    boolean;
  r_fired  int;
  r_hits   int;
  v_raw    numeric;
  v_soaked numeric;
  v_d      numeric;
  v_pick   numeric;
  v_acc_sum numeric;
  v_you    text;
  v_they   text;
  v_hit_on text;
  v_tot_you  int := 0;
  v_tot_they int := 0;
  v_fought int := 0;
  v_txt    text;
  b_you    numeric := 0;
  b_crew   numeric := 0;
  b_they   numeric;
  v_ratio  numeric;
begin
  if v_n = 0 then
    raise exception 'E_NO_SHIPS: a fight needs at least one hull' using errcode = 'P0001';
  end if;
  select * into c from public.ship_classes where code = public.wc_text('fight_raider_class');
  if c.id is null then
    -- NO_SPAGHETTI §7C: raiders with no class have no figures; that is a broken knob, not a calm sea
    raise exception 'E_NO_RAIDER_CLASS: fight_raider_class names no ship class' using errcode = 'P0001';
  end if;
  if jsonb_typeof(v_ranges) <> 'array' or jsonb_array_length(v_ranges) = 0 or jsonb_typeof(v_bands) <> 'array'
     or jsonb_array_length(v_bands) <> 3 then
    raise exception 'E_FIGHT_KNOBS: fight_ranges must list at least one round and fight_board_bands three bands'
      using errcode = 'P0001';
  end if;

  -- the fleet, one array per figure (index = her place in p_ships)
  for i in 1 .. v_n loop
    x := p_ships -> (i - 1);
    a_id[i]    := (x->>'id')::uuid;
    a_name[i]  := coalesce(x->>'name', 'Your ship');
    a_att[i]   := greatest(0, coalesce((x->>'attack')::numeric, 0));
    a_acc[i]   := greatest(0, coalesce((x->>'accuracy')::numeric, 0));
    a_reach[i] := greatest(0, coalesce((x->>'reach')::numeric, 0));
    a_arm[i]   := greatest(0, coalesce((x->>'armour')::numeric, 0));
    a_hull0[i] := greatest(0, coalesce((x->>'hull')::numeric, 0));
    a_hull[i]  := a_hull0[i];
    a_maxd[i]  := greatest(1, coalesce((x->>'maxd')::numeric, 1));
    a_crew[i]  := greatest(0, coalesce((x->>'crew')::numeric, 0));
    a_bpct[i]  := greatest(0, coalesce((x->>'boarder_pct')::numeric, 0));
    a_tier[i]  := greatest(0, coalesce((x->>'tier')::numeric, 0));
    p_sight    := greatest(p_sight, coalesce((x->>'sighting')::numeric, 0));
    if a_att[i] > 0 and a_acc[i] > 0 then
      p_reach := greatest(p_reach, a_reach[i]);
    end if;
  end loop;

  -- the raiders: the hazard's strength in hulls of the raiders' class (DESIGN B.6's escort score of one)
  v_one   := c.attack / 10.0 + c.crew_required * 0.02 + c.tier * 3;
  r_n     := greatest(0, coalesce(p_raider, 0)) / v_one;
  r_hull0 := r_n * c.durability;
  r_hull  := r_hull0;
  r_att   := r_n * c.attack;
  r_crew  := r_n * c.crew_required;
  r_shots := greatest(1, ceil(r_n))::int;

  -- SIZING UP: no raiders, or a fleet too strong for them — they never close
  if r_n <= 0 or coalesce(p_escort, 0) >= public.wc_num('fight_standoff_ratio') * p_raider then
    return jsonb_build_object('outcome', 'EVADED', 'sentence', 'They stood off and did not close.',
                              'rounds', to_jsonb(array[case when r_n <= 0 then 'The sail stood off and never closed.'
                                                            else format('Raiders: about %s × %s, %s crew. They looked you over and stood off.',
                                                                        greatest(1, round(r_n)), c.name, round(r_crew)) end]),
                              'hull_lost', '{}'::jsonb, 'first', 'BOTH', 'rounds_fought', 0,
                              'raiders', jsonb_build_object('class', c.code, 'ships', round(r_n, 2), 'crew', round(r_crew), 'damaged_pct', 0),
                              'hits', jsonb_build_object('yours', 0, 'theirs', 0));
  end if;

  v_lines := v_lines || case when r_n < 0.75
                               then format('Raiders: one small %s, %s crew.', c.name, round(r_crew))
                               else format('Raiders: about %s × %s, %s crew.', round(r_n), c.name, round(r_crew)) end;
  -- what works on a raid day: the gear whose trigger is PIRATES (item_use, 0158), and a Gunner at the guns
  select string_agg(format('%s (%s)', e->>'name', (select string_agg(gname, ', ' order by gname)
                                                      from jsonb_array_elements_text(e->'gear') gname)), '; ' order by o)
    into v_txt
    from jsonb_array_elements(p_ships) with ordinality q(e, o)
   where jsonb_typeof(e->'gear') = 'array' and jsonb_array_length(e->'gear') > 0;
  if v_txt is not null then
    v_lines := v_lines || ('Ready for them: ' || v_txt || '.');
  end if;
  select string_agg(format('%s lays the guns on %s.', e->>'gunner', e->>'name'), ' ' order by o)
    into v_txt
    from jsonb_array_elements(p_ships) with ordinality q(e, o)
   where coalesce(e->>'gunner', '') <> '';
  if v_txt is not null then
    v_lines := v_lines || v_txt;
  end if;

  -- SIGHTING
  v_first := case when p_sight > c.sighting then 'YOU' when p_sight < c.sighting then 'THEY' else 'BOTH' end;
  if v_first = 'YOU' then
    if voyage.rng(p_voyage, p_day, 'fight:evade')
         < least(public.wc_num('fight_evade_max'), (p_sight - c.sighting) * public.wc_num('fight_evade_per_sighting')) then
      v_lines := v_lines || 'Your lookout saw them first, and you slipped away before they could close.'::text;
      return jsonb_build_object('outcome', 'EVADED', 'sentence', 'We saw them first and slipped away.',
                                'rounds', to_jsonb(v_lines), 'hull_lost', '{}'::jsonb,
                                'first', v_first, 'rounds_fought', 0,
                                'raiders', jsonb_build_object('class', c.code, 'ships', round(r_n, 2), 'crew', round(r_crew), 'damaged_pct', 0),
                                'hits', jsonb_build_object('yours', 0, 'theirs', 0));
    end if;
    v_lines := v_lines || 'Your lookout saw them first.'::text;
  elsif v_first = 'THEY' then
    v_lines := v_lines || 'They saw you before your lookout saw them.'::text;
  else
    v_lines := v_lines || 'Both sides saw each other at the same moment.'::text;
  end if;

  -- THE ROUNDS
  for g in 1 .. jsonb_array_length(v_ranges) loop
    v_fought := g;
    v_range := v_ranges -> (g - 1) ->> 0;
    v_mult  := (v_ranges -> (g - 1) ->> 1)::numeric;
    -- your guns
    v_can := 0; v_fired := 0; v_hits := 0; v_dealt := 0;
    for i in 1 .. v_n loop
      continue when a_att[i] <= 0 or a_acc[i] <= 0 or a_hull[i] <= 0;
      v_can := v_can + 1;
      continue when g = 1 and v_first = 'THEY';
      continue when v_range = 'LONG' and a_reach[i] < c.reach;
      v_fired := v_fired + 1;
      if voyage.rng(p_voyage, p_day, format('fight:%s:you:%s', g, i))
           < least(0.95, greatest(0.05, a_acc[i] / 100.0 * v_mult)) then
        v_hits := v_hits + 1;
        v_dealt := v_dealt + public.armour_soak(c.armour,
                     a_att[i] * v_k * (0.75 + 0.5 * voyage.rng(p_voyage, p_day, format('fight:%s:you:%s:dmg', g, i))));
      end if;
    end loop;
    -- their guns
    a_taken := array_fill(0::numeric, array[v_n]);
    r_fired := 0; r_hits := 0; v_raw := 0; v_soaked := 0;
    r_can := r_hull > 0 and not (g = 1 and v_first = 'YOU') and (v_range <> 'LONG' or c.reach >= p_reach);
    if r_can then
      for j in 1 .. r_shots loop
        r_fired := r_fired + 1;
        continue when voyage.rng(p_voyage, p_day, format('fight:%s:they:%s', g, j))
                        >= least(0.95, greatest(0.05, c.accuracy / 100.0 * v_mult));
        -- whom it hits: the hulls still afloat, by their size
        v_pick := voyage.rng(p_voyage, p_day, format('fight:%s:they:%s:at', g, j))
                  * (select coalesce(sum(a_maxd[k]), 0) from generate_subscripts(a_hull, 1) k where a_hull[k] > 0);
        t := null;
        v_acc_sum := 0;
        for i in 1 .. v_n loop
          continue when a_hull[i] <= 0;
          v_acc_sum := v_acc_sum + a_maxd[i];
          t := i;
          exit when v_pick < v_acc_sum;
        end loop;
        exit when t is null;
        r_hits := r_hits + 1;
        v_d := r_att / r_shots * v_k * (0.75 + 0.5 * voyage.rng(p_voyage, p_day, format('fight:%s:they:%s:dmg', g, j)));
        v_raw := v_raw + v_d;
        v_d := public.armour_soak(a_arm[t], v_d);
        v_soaked := v_soaked + v_d;
        a_taken[t] := a_taken[t] + v_d;
      end loop;
    end if;
    -- both broadsides land together
    r_hull := greatest(0, r_hull - v_dealt);
    v_hit_on := null;
    for i in 1 .. v_n loop
      continue when a_taken[i] <= 0;
      v_hit_on := coalesce(v_hit_on || ', ', '')
                  || format('%s for %s%% damage', a_name[i], greatest(1, round(least(a_taken[i], a_hull[i]) / a_maxd[i] * 100)));
      a_hull[i] := greatest(0, a_hull[i] - a_taken[i]);
    end loop;
    v_tot_you := v_tot_you + v_hits;
    v_tot_they := v_tot_they + r_hits;

    v_you := case when g = 1 and v_first = 'THEY' then 'you are caught unready'
                  when v_can = 0 then 'you have no guns to answer with'
                  when v_fired = 0 then 'your guns cannot reach them'
                  when v_hits = 0 then format('you miss with %s shot%s', v_fired, case when v_fired = 1 then '' else 's' end)
                  else format('you hit with %s of %s shot%s', v_hits, v_fired, case when v_fired = 1 then '' else 's' end) end;
    v_they := case when g = 1 and v_first = 'YOU' then 'they are caught unready'
                   when not r_can then 'their guns cannot reach you'
                   when r_hits = 0 then 'they miss'
                   else format('they hit %s', v_hit_on)
                        || case when v_raw > v_soaked + 0.005
                                then format(' (armour turned %s%%)', round((1 - v_soaked / v_raw) * 100)) else '' end end;
    v_lines := v_lines || (format('Round %s · %s range — %s; %s.', g, lower(v_range), v_you, v_they)
                           || case when v_hits > 0 then format(' The raiders are %s%% damaged.', round((1 - r_hull / r_hull0) * 100)) else '' end);

    if r_hull0 - r_hull >= v_break * r_hull0 then
      v_outcome := case when (select coalesce(sum(a_hull0[k] - a_hull[k]), 0) from generate_subscripts(a_hull, 1) k) = 0
                        then 'EVADED' else 'DRIVEN_OFF' end;
      v_lines := v_lines || 'They break off and run.'::text;
      v_sentence := 'They broke off and ran.';
      exit;
    end if;
  end loop;

  -- THE BOARDING
  if v_outcome is null then
    for i in 1 .. v_n loop
      b_crew := b_crew + a_crew[i];
      b_you := b_you + (a_crew[i] * v_hand * (1 + a_bpct[i]) + a_tier[i] * 3)
                       * case when a_hull0[i] > 0 then a_hull[i] / a_hull0[i] else 0 end;
    end loop;
    b_they := r_n * (c.crew_required * v_hand + c.tier * 3) * r_hull / r_hull0;
    v_ratio := case when b_they <= 0 then 99 else b_you / b_they end;
    v_outcome := case when v_ratio >= (v_bands->>0)::numeric then 'DRIVEN_OFF'
                      when v_ratio >= (v_bands->>1)::numeric then 'RANSOM'
                      else 'PLUNDERED' end;
    select string_agg(format('%s leads the crew on %s (+%s%%).', e->>'boarder', e->>'name',
                             round((e->>'boarder_pct')::numeric * 100)), ' ' order by o)
      into v_txt
      from jsonb_array_elements(p_ships) with ordinality q(e, o)
     where coalesce(e->>'boarder', '') <> '' and coalesce((e->>'boarder_pct')::numeric, 0) > 0;
    v_lines := v_lines || (format('Close quarters: they come alongside — your %s crew against their %s.', round(b_crew),
                                  round(r_crew * r_hull / r_hull0))
                           || coalesce(' ' || v_txt, '')
                           || case v_outcome when 'DRIVEN_OFF' then ' You throw them back.'
                                             when 'RANSOM'     then ' You pay them off rather than be boarded.'
                                             when 'PLUNDERED'  then ' They board and take what they can carry.'
                                             else ' They board and take everything but the ships.' end);
    v_sentence := case v_outcome when 'DRIVEN_OFF' then 'They came alongside and we threw them back.'
                                 when 'RANSOM'     then 'They came alongside and we paid them off.'
                                 when 'PLUNDERED'  then 'They came aboard and took what they could carry.'
                                 else 'They took everything but the ships themselves.' end;
  end if;

  return jsonb_build_object(
    'outcome', v_outcome,
    'sentence', v_sentence,
    'rounds', to_jsonb(v_lines),
    'hull_lost', coalesce((select jsonb_object_agg(a_id[k]::text, round(a_hull0[k] - a_hull[k], 2))
                             from generate_subscripts(a_id, 1) k where a_hull0[k] > a_hull[k]), '{}'::jsonb),
    'first', v_first,
    'rounds_fought', v_fought,
    'raiders', jsonb_build_object('class', c.code, 'ships', round(r_n, 2), 'crew', round(r_crew),
                                  'damaged_pct', round((1 - r_hull / r_hull0) * 100)),
    'hits', jsonb_build_object('yours', v_tot_you, 'theirs', v_tot_they));
end $$;
