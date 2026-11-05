-- ═══════════════════════════════════════════════════════════
-- PROOF 28 — A FIGHT HAS TWO SIDES  (migration 0320)
--
--   0320's self-assert fights 1,080 crafted fights under the world's own knobs. This proof holds the old body WHOLE (it is also the forward rollback's text, digest
--   8fc074d4f0a09332b321eb55a600c2fc) and fights a wider matrix: 200 made-up fleets of 1 to 4 hulls, every knob a fight reads moved, the refusals, then a real company's fleet through
--   voyage.fight. No credit, no treasury_post: nothing here touches money. Everything is rolled back by the runner.
--
-- @pass FIGHT_PARITY_WIDE  1,200 fights of made-up fleets, word for word, old body against the skin
-- @pass FIGHT_PARITY_KNOBS each knob a fight reads, moved, word for word
-- @pass FIGHT_REFUSALS     the same refusals, with the same words
-- @pass FIGHT_TWO_SIDES    a side without guns takes nothing, a sunk hull does not fire, range decides who fires, on both sides
-- @pass FIGHT_REAL_FLEET   a real company's fleet through voyage.fight, word for word, old body against the skin
-- @pass FIGHT_ROLLBACK     the old body goes back byte for byte, and the skin after it
-- ═══════════════════════════════════════════════════════════

create temp table pre_0320 (def text) on commit drop;
insert into pre_0320 values ($pre$CREATE OR REPLACE FUNCTION voyage.fight_resolve(p_voyage uuid, p_day integer, p_raider numeric, p_escort numeric, p_ships jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
--             PLUNDERED; 0202: below the last band the crew SURRENDERS (PLUNDERED, never STRIPPED) — a crew that
--             cannot hold the deck yields its cargo rather than die for it. NOT the owner's — confirm.
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
  v_surrender boolean := false;   -- 0202: the boarding fell below the last band, and the crew surrendered
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
    -- 0202: below the last band the crew cannot hold the deck, and surrenders: the raiders take what they can
    -- carry (PLUNDERED) and nobody dies defending a lost deck — a fight never ends STRIPPED
    v_surrender := v_ratio < (v_bands->>2)::numeric;
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
                           || case when v_surrender then ' You surrender; they board and take what they can carry.'
                                   else case v_outcome when 'DRIVEN_OFF' then ' You throw them back.'
                                                       when 'RANSOM'     then ' You pay them off rather than be boarded.'
                                                       else ' They board and take what they can carry.' end end);
    v_sentence := case when v_surrender then 'We surrendered, and they took what they could carry.'
                       else case v_outcome when 'DRIVEN_OFF' then 'They came alongside and we threw them back.'
                                           when 'RANSOM'     then 'They came alongside and we paid them off.'
                                           else 'They came aboard and took what they could carry.' end end;
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
end $function$
$pre$);

create function pg_temp.u_0320(p_k int, p_i int, p_what text) returns numeric language sql immutable as $$
  select ('x' || substr(md5(p_k || ':' || p_i || ':' || p_what), 1, 6))::bit(24)::int / 16777215.0 $$;

-- a made-up fleet: 1 to 4 hulls, every figure fractional, some unarmed, some hurt, some sunk, some with a Gunner, a Boarder, gear
create function pg_temp.hulls_0320(p_k int) returns jsonb language sql as $$
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'id', '00000000-0320-4000-8000-' || lpad((p_k * 10 + i)::text, 12, '0'), 'name', 'Probe ' || p_k || '-' || i,
    'tier', 1 + floor(u.tr * 5)::int,
    'hull', case when u.dead < 0.1 then 0 else round(u.h * u.m * 3000, 2) end, 'maxd', round(u.m * 3000 + 1),
    'crew', floor(u.cr * 160)::int, 'attack', case when u.guns < 0.2 then 0 else round(u.att * 400, 2) end,
    'accuracy', case when u.guns < 0.3 then 0 else round(u.acc * 80, 1) end, 'reach', round(u.rch * 90, 1), 'armour', round(u.arm * 60, 1), 'sighting', round(u.sg * 30, 1),
    'boarder_pct', case when u.bo < 0.3 then round(u.bo, 2) end, 'boarder', case when u.bo < 0.3 then 'Boarder ' || i end,
    'gunner', case when u.gn < 0.3 then 'Gunner ' || i end, 'gear', case when u.gn > 0.7 then jsonb_build_array('Swivel Guns', 'Boarding Gear') end)) order by i)
  from generate_series(1, 1 + p_k % 4) i
  cross join lateral (select pg_temp.u_0320(p_k, i, 'tr') tr, pg_temp.u_0320(p_k, i, 'dead') dead, pg_temp.u_0320(p_k, i, 'h') h, pg_temp.u_0320(p_k, i, 'm') m, pg_temp.u_0320(p_k, i, 'cr') cr,
                             pg_temp.u_0320(p_k, i, 'guns') guns, pg_temp.u_0320(p_k, i, 'att') att, pg_temp.u_0320(p_k, i, 'acc') acc, pg_temp.u_0320(p_k, i, 'rch') rch,
                             pg_temp.u_0320(p_k, i, 'arm') arm, pg_temp.u_0320(p_k, i, 'sg') sg, pg_temp.u_0320(p_k, i, 'bo') bo, pg_temp.u_0320(p_k, i, 'gn') gn) u $$;

do $p$
declare
  c_seed constant uuid := '00000000-0320-4000-8000-0000000000f1';
  v_pre  text := (select def from pre_0320);
  v_k    int;
  v_d    int;
  v_r    numeric;
  v_h    jsonb;
  v_esc  numeric;
  v_old  jsonb;
  v_new  jsonb;
  v_n    int := 0;
  v_ends jsonb := '{}'::jsonb;
  v_kn   record;
  v_e1   text;
  v_e2   text;
  v_f    jsonb;
  c_one  constant jsonb := '[{"id":"00000000-0320-4000-8000-0000000000c1","name":"Probe","tier":2,"hull":5000,"maxd":5000,"crew":30,"attack":100,"accuracy":70,"reach":40,"armour":10,"sighting":10}]';
  c_dull constant jsonb := '[{"id":"00000000-0320-4000-8000-0000000000c2","name":"Dull","tier":2,"hull":5000,"maxd":5000,"crew":30,"attack":0,"accuracy":0,"reach":0,"armour":10,"sighting":10}]';
  c_sunk constant jsonb := '[{"id":"00000000-0320-4000-8000-0000000000c3","name":"Sunk","tier":2,"hull":0,"maxd":5000,"crew":30,"attack":100,"accuracy":70,"reach":40,"armour":10,"sighting":10}]';
begin
  if md5(v_pre) <> '8fc074d4f0a09332b321eb55a600c2fc' then
    raise exception 'PROOF 28 FAIL: the held pre-image is not the old body: %', md5(v_pre);
  end if;
  execute replace(v_pre, 'CREATE OR REPLACE FUNCTION voyage.fight_resolve(', 'CREATE FUNCTION pg_temp.old_0320(');

  -- THE WIDE MATRIX, under the world's knobs
  for v_k in 1 .. 200 loop
    v_h := pg_temp.hulls_0320(v_k);
    v_esc := round(pg_temp.u_0320(v_k, 0, 'esc') * 60, 2);
    foreach v_r in array array[0.5, 3, 9.7, 25, 77, 333]::numeric[] loop
      v_d := v_k + (v_r * 10)::int;
      v_old := pg_temp.old_0320(c_seed, v_d, v_r, v_esc, v_h);
      v_new := voyage.fight_resolve(c_seed, v_d, v_r, v_esc, v_h);
      v_n := v_n + 1;
      v_ends := jsonb_set(v_ends, array[v_old ->> 'outcome'], to_jsonb(coalesce((v_ends ->> (v_old ->> 'outcome'))::int, 0) + 1));
      if v_old::text is distinct from v_new::text then
        raise exception 'PROOF 28 FAIL: a fight changed (fleet %, strength %): old % new %', v_k, v_r, v_old, v_new;
      end if;
    end loop;
  end loop;
  if not (v_ends ?& array['EVADED', 'DRIVEN_OFF', 'RANSOM', 'PLUNDERED']) then
    raise exception 'PROOF 28 FAIL: the matrix met too few endings: %', v_ends;
  end if;
  raise notice 'PASS: FIGHT_PARITY_WIDE — % fights word for word, %', v_n, v_ends;

  -- EACH KNOB MOVED: only armed raider classes (0320's header names the one corner an unarmed class moves)
  v_n := 0;
  for v_kn in
    select * from (values
      ('armour_turns_pct', '0'::jsonb), ('armour_turns_pct', '0.9'), ('fight_raider_break', '0.5'), ('fight_raider_break', '1'), ('fight_raider_class', '"nau"'), ('fight_raider_class', '"galion"'),
      ('fight_ranges', '[["CLOSE", 1]]'), ('fight_ranges', '[["LONG", 0.4], ["MEDIUM", 0.7], ["MEDIUM", 0.9], ["CLOSE", 1.1]]'), ('fight_board_bands', '[2.5, 1.1, 0.5]'),
      ('fight_evade_per_sighting', '0.5'), ('fight_evade_max', '0.9'), ('fight_standoff_ratio', '0.4'), ('fight_hand_value', '0.33'), ('fight_damage_per_attack', '1.7')) k(key, val)
  loop
    update public.world_config c set value = v_kn.val where c.key = v_kn.key;
    for v_k in 201 .. 240 loop
      v_h := pg_temp.hulls_0320(v_k);
      foreach v_r in array array[4.4, 18, 120]::numeric[] loop
        v_old := pg_temp.old_0320(c_seed, v_k, v_r, 9.5, v_h);
        v_new := voyage.fight_resolve(c_seed, v_k, v_r, 9.5, v_h);
        v_n := v_n + 1;
        if v_old::text is distinct from v_new::text then
          raise exception 'PROOF 28 FAIL: % = % changed a fight (fleet %, strength %): old % new %', v_kn.key, v_kn.val, v_k, v_r, v_old, v_new;
        end if;
      end loop;
    end loop;
  end loop;
  raise notice 'PASS: FIGHT_PARITY_KNOBS — % fights word for word, 14 knob values, each on top of the last', v_n;

  -- THE REFUSALS
  begin perform pg_temp.old_0320(c_seed, 1, 10, 0, '[]'::jsonb); exception when others then v_e1 := sqlerrm; end;
  begin perform voyage.fight_resolve(c_seed, 1, 10, 0, '[]'::jsonb); exception when others then v_e2 := sqlerrm; end;
  if v_e1 is distinct from v_e2 or v_e1 not like 'E_NO_SHIPS%' then
    raise exception 'PROOF 28 FAIL: no ships: % against %', v_e1, v_e2;
  end if;
  update public.world_config set value = '[]'::jsonb where key = 'fight_ranges';
  v_e1 := null; v_e2 := null;
  begin perform pg_temp.old_0320(c_seed, 1, 1, 500, c_one); exception when others then v_e1 := sqlerrm; end;
  begin perform voyage.fight_resolve(c_seed, 1, 1, 500, c_one); exception when others then v_e2 := sqlerrm; end;
  if v_e1 is distinct from v_e2 or v_e1 not like 'E_FIGHT_KNOBS%' then
    raise exception 'PROOF 28 FAIL: a broken knob on a standing-off fleet: % against %', v_e1, v_e2;
  end if;
  update public.world_config set value = '[["LONG",0.6],["LONG",0.6],["LONG",0.6],["MEDIUM",0.8],["MEDIUM",0.8],["CLOSE",1.0]]'::jsonb where key = 'fight_ranges';
  update public.world_config set value = '"no_such_class"'::jsonb where key = 'fight_raider_class';
  v_e1 := null; v_e2 := null;
  begin perform pg_temp.old_0320(c_seed, 1, 10, 0, c_one); exception when others then v_e1 := sqlerrm; end;
  begin perform voyage.fight_resolve(c_seed, 1, 10, 0, c_one); exception when others then v_e2 := sqlerrm; end;
  if v_e1 is distinct from v_e2 or v_e1 not like 'E_NO_RAIDER_CLASS%' then
    raise exception 'PROOF 28 FAIL: no class: % against %', v_e1, v_e2;
  end if;
  update public.world_config set value = '"xebec"'::jsonb where key = 'fight_raider_class';
  raise notice 'PASS: FIGHT_REFUSALS — no ships, a broken knob and a broken class, the same words';

  -- TWO SIDES, each rule from both ends
  update public.world_config set value = '0.99'::jsonb where key = 'fight_raider_break';
  update public.world_config set value = '0.5'::jsonb where key = 'armour_turns_pct';
  update public.world_config set value = '0.7'::jsonb where key = 'fight_damage_per_attack';
  for v_d in 1 .. 20 loop
    v_f := public.fight_sides(c_seed, v_d, c_one, c_dull);
    if v_f -> 'hull_lost' -> 'a' <> '{}'::jsonb or v_f -> 'hits' ->> 'b' <> '0' then
      raise exception 'PROOF 28 FAIL: a side with no guns did damage: %', v_f;
    end if;
    v_f := public.fight_sides(c_seed, v_d, c_dull, c_one);
    if v_f -> 'hull_lost' -> 'b' <> '{}'::jsonb or v_f -> 'hits' ->> 'a' <> '0' then
      raise exception 'PROOF 28 FAIL: a side with no guns did damage: %', v_f;
    end if;
    v_f := public.fight_sides(c_seed, v_d, c_one, c_sunk || c_one);
    if (v_f -> 'rounds' -> 0 -> 'b' ->> 'can')::int <> 1 then
      raise exception 'PROOF 28 FAIL: a sunk hull fired: %', v_f -> 'rounds' -> 0;
    end if;
    v_f := public.fight_sides(c_seed, v_d, c_sunk || c_one, c_one);
    if (v_f -> 'rounds' -> 0 -> 'a' ->> 'can')::int <> 1 then
      raise exception 'PROOF 28 FAIL: a sunk hull fired: %', v_f -> 'rounds' -> 0;
    end if;
    -- range decides who fires, whichever side has the longer gun
    v_f := public.fight_sides(c_seed, v_d, jsonb_set(c_one, '{0,reach}', '80'), c_one);
    if (v_f -> 'rounds' -> 1 -> 'b' ->> 'fired')::int <> 0 or (v_f -> 'rounds' -> 1 -> 'a' ->> 'fired')::int <> 1 then
      raise exception 'PROOF 28 FAIL: a short gun fired at long range (b): %', v_f -> 'rounds' -> 1;
    end if;
    v_f := public.fight_sides(c_seed, v_d, c_one, jsonb_set(c_one, '{0,reach}', '80'));
    if (v_f -> 'rounds' -> 1 -> 'a' ->> 'fired')::int <> 0 or (v_f -> 'rounds' -> 1 -> 'b' ->> 'fired')::int <> 1 then
      raise exception 'PROOF 28 FAIL: a short gun fired at long range (a): %', v_f -> 'rounds' -> 1;
    end if;
    v_f := public.fight_sides(c_seed, v_d, c_one, jsonb_set(c_one, '{0,shots}', '3'));
    if (v_f -> 'rounds' -> 1 -> 'b' ->> 'fired')::int <> 3 then
      raise exception 'PROOF 28 FAIL: a squadron of three fired %', v_f -> 'rounds' -> 1;
    end if;
  end loop;
  raise notice 'PASS: FIGHT_TWO_SIDES — no guns, sunk hulls, range and squadrons, each from both ends';
end
$p$;

-- END OF THE PURE PROOF (scripts/ops/harness/two-sides/proof-0320.mjs runs what is above on its small world)
do $p$
declare
  c_uid  constant uuid := '00000000-0320-4000-8000-0000000000d1';
  c_fr   constant regprocedure := 'voyage.fight_resolve(uuid,integer,numeric,numeric,jsonb)'::regprocedure;
  c_seed constant uuid := '00000000-0320-4000-8000-0000000000f2';
  v_pre  text := (select def from pre_0320);
  v_skin text := replace(pg_get_functiondef(c_fr), E'\r', '');
  v_p    uuid;
  v_f    uuid;
  v_r    numeric;
  v_d    int;
  v_a    jsonb := '{}'::jsonb;
  v_b    jsonb := '{}'::jsonb;
  v_n    int := 0;
begin
  update public.world_config set value = 'true'::jsonb where key = 'combat_bite';
  update public.world_config set value = '[["LONG",0.6],["LONG",0.6],["LONG",0.6],["MEDIUM",0.8],["MEDIUM",0.8],["CLOSE",1.0]]'::jsonb where key = 'fight_ranges';
  v_p := public.new_house(c_uid, 'Casa da Luta 0320', 'PRT', 'LIS');
  select f.id into v_f from public.fleets f where f.player_id = v_p limit 1;
  if v_f is null then
    raise exception 'PROOF 28 FAIL: the probe house has no fleet';
  end if;
  foreach v_r in array array[3, 8, 16, 40]::numeric[] loop
    for v_d in 1 .. 60 loop
      v_a := v_a || jsonb_build_object(v_r || ':' || v_d, voyage.fight(c_seed, v_d, v_f, v_r));
      v_n := v_n + 1;
    end loop;
  end loop;
  execute v_pre;
  if md5(replace(pg_get_functiondef(c_fr), E'\r', '')) <> '8fc074d4f0a09332b321eb55a600c2fc' then
    raise exception 'PROOF 28 FAIL: the old body did not go back byte for byte';
  end if;
  foreach v_r in array array[3, 8, 16, 40]::numeric[] loop
    for v_d in 1 .. 60 loop
      v_b := v_b || jsonb_build_object(v_r || ':' || v_d, voyage.fight(c_seed, v_d, v_f, v_r));
    end loop;
  end loop;
  execute v_skin;
  if replace(pg_get_functiondef(c_fr), E'\r', '') <> v_skin then
    raise exception 'PROOF 28 FAIL: the skin did not go back';
  end if;
  if v_a::text is distinct from v_b::text then
    raise exception 'PROOF 28 FAIL: a real fleet''s fight changed';
  end if;
  raise notice 'PASS: FIGHT_REAL_FLEET — % days of a real company''s fleet through voyage.fight, word for word', v_n;
  raise notice 'PASS: FIGHT_ROLLBACK — the old body back by digest, the skin back after it';
end
$p$;
