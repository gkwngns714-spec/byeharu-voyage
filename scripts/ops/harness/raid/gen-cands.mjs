// gen-cands.mjs — candidate bodies of voyage.fight_resolve, each a text edit of 0189's body (as live), written to cand-*.sql
import { readFileSync, writeFileSync } from 'node:fs'
const src = readFileSync('C:/Users/gkwng/dev/bv-raid/supabase/migrations/20260818000189_a_raid_is_fought_in_rounds.sql', 'utf8').replace(/\r\n/g, '\n')
const a = src.indexOf('create or replace function voyage.fight_resolve'), b = src.indexOf('end $$;', a) + 'end $$;'.length
const body = src.slice(a, b)
const once = (s, x, y) => { const n = s.split(x).length - 1; if (n !== 1) throw new Error(`occurs ${n}: ${x.slice(0, 60)}`); return s.replace(x, y) }
const SIZE_OLD = `  r_n     := greatest(0, coalesce(p_raider, 0)) / v_one;
`
// K3: the raiders who close are sized to the prey — no more hulls than fight_prey_ratio × her boarding strength needs
const preySized = (s) => once(s, SIZE_OLD, `  r_n     := greatest(0, coalesce(p_raider, 0)) / v_one;
  -- K3: sized to the prey
  b_crew := 0;
  for i in 1 .. v_n loop
    b_crew := b_crew + a_crew[i] * v_hand * (1 + a_bpct[i]) + a_tier[i] * 3;
  end loop;
  r_n := least(r_n, public.wc_num('fight_prey_ratio') * b_crew / (c.crew_required * v_hand + c.tier * 3));
  b_crew := 0;
`)
// K4: hopeless at the boarding (below the last band) — she strikes: PLUNDERED, not STRIPPED
const strike = (s) => once(s, `                      when v_ratio >= (v_bands->>2)::numeric then 'PLUNDERED'
                      else 'STRIPPED' end;`, `                      else 'PLUNDERED' end;`)
// K1: the boarding read in DESIGN B.6's own measure (attack / 10 + crew × 0.02 + tier × 3, × hull left), both sides
const designBoard = (s) => once(once(s,
  `      b_you := b_you + (a_crew[i] * v_hand * (1 + a_bpct[i]) + a_tier[i] * 3)`,
  `      b_you := b_you + (a_att[i] / 10.0 + a_crew[i] * 0.02 * (1 + a_bpct[i]) + a_tier[i] * 3)`),
  `    b_they := r_n * (c.crew_required * v_hand + c.tier * 3) * r_hull / r_hull0;`,
  `    b_they := r_n * v_one * r_hull / r_hull0;`)
const out = { prey: preySized(body), strike: strike(body), design: designBoard(body), design_prey: preySized(designBoard(body)) }
for (const [k, v] of Object.entries(out)) writeFileSync(`cand-${k}.sql`, v + '\n')
console.log('wrote', Object.keys(out).join(', '))
// K5: outnumbered at the boarding (their fighting hands >= fight_strike_ratio x hers) — she strikes and pays: RANSOM
const strikeRansom = (s) => once(s, `    v_outcome := case when v_ratio >= (v_bands->>0)::numeric then 'DRIVEN_OFF'`,
  `    v_outcome := case when v_ratio < (v_bands->>1)::numeric and r_crew * r_hull / r_hull0 >= public.wc_num('fight_strike_ratio') * b_crew then 'RANSOM'
                      when v_ratio >= (v_bands->>0)::numeric then 'DRIVEN_OFF'`)
// K6: a target that cannot win gives up at sight (escort < fight_giveup x raider): RANSOM, no rounds
const giveUp = (s) => once(s, `  v_lines := v_lines || case when r_n < 0.75`, `  if coalesce(p_escort, 0) < public.wc_num('fight_giveup') * p_raider then
    return jsonb_build_object('outcome', 'RANSOM', 'sentence', 'We struck to them and paid.', 'rounds', '["struck"]'::jsonb, 'hull_lost', '{}'::jsonb, 'first', 'BOTH', 'rounds_fought', 0,
      'raiders', jsonb_build_object('class', c.code, 'ships', round(r_n, 2), 'crew', round(r_crew), 'damaged_pct', 0), 'hits', jsonb_build_object('yours', 0, 'theirs', 0));
  end if;
  v_lines := v_lines || case when r_n < 0.75`)
writeFileSync('cand-strikeransom.sql', strikeRansom(body) + '\n'); writeFileSync('cand-giveup.sql', giveUp(body) + '\n')
console.log('wrote strikeransom, giveup')
