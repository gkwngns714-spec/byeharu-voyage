// W2 levels_are_lit: THE 30-MINUTE AFTER-CHECK, READ-ONLY on prod.
//
//   node scripts/ops/harness/levels/after-check.mjs before <file.json>   run BEFORE the owner lights levels_bite
//   node scripts/ops/harness/levels/after-check.mjs after  <file.json>   run about 30 minutes AFTER, same file
//
// Every statement runs inside `begin transaction read only`; only STABLE functions are called
// (world.ship_stats, world.ship_slots, public.player_progress, public.title_level, public.earned_caps).
// `after` ends with PASS or FAIL. FAIL means: put levels_bite back to false (the rollback is one knob).
//
// Checks (each printed):
//   1. levels_bite is true after, false before.
//   2. Every human hull: every fitted rack count is still <= the open slots (nothing fitted is shut out).
//   3. Every human hull: handling, accuracy, sighting moved by exactly (level - 1) x its knob; the other
//      eight stats are identical to the snapshot. (A hull that earned experience in between is compared
//      at her new level, so the snapshot stores xp and the check re-reads it.)
//   4. Every human: title_level, trading level, exploration level, earned_caps unchanged.
//   5. public.player_progress on the busiest human: median Execution Time of 5 reads under 50 ms (the W2 cost bound).
//   6. Arrivals beats (public.arrivals_beats) over the last 30 minutes: avg <= 3 s, p95 < 5 s, no error.
import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const [mode, file] = process.argv.slice(2);
if (!['before', 'after'].includes(mode) || !file) {
  console.error('usage: after-check.mjs before|after <snapshot.json>');
  process.exit(64);
}
const dir = mkdtempSync(join(tmpdir(), 'w2-'));
let n = 0;
function q(sql) {
  const f = join(dir, `q${n++}.sql`);
  writeFileSync(f, 'begin transaction read only;\n' + sql + '\n');
  const r = spawnSync('npx', ['--yes', 'supabase@2.120.0', 'db', 'query', '--linked', '-f', f], { encoding: 'utf8', shell: process.platform === 'win32' });
  const s = (r.stdout || '') + (r.stderr || '');
  const i = s.indexOf('{');
  try { return JSON.parse(s.slice(i, s.lastIndexOf('}') + 1)).rows; }
  catch { console.error('QUERY FAILED:\n' + s.slice(0, 1500)); process.exit(70); }
}

const SNAP = `
select jsonb_build_object(
  'bite', public.wc('levels_bite'),
  'knobs', (select jsonb_object_agg(key, value) from public.world_config where key in
     ('level_points_per_step','ship_level_handling_per_level','ship_level_accuracy_per_level','ship_level_sighting_per_level')),
  'humans', (select jsonb_agg(jsonb_build_object('id', p.id, 'title', public.title_level(p.id),
       'trading', pp->'trading'->>'level', 'exploration', pp->'exploration'->>'level',
       'caps', public.earned_caps(p.id)) order by p.id)
     from public.players p cross join lateral (select public.player_progress(p.id) pp) q where not p.is_npc),
  'ships', (select jsonb_agg(jsonb_build_object('id', s.id, 'xp', coalesce(sx.xp, 0),
       'stats', world.ship_stats(s.id), 'open', world.ship_slots(s.id)->'open',
       'used', (select coalesce(jsonb_object_agg(z.r, z.c), '{}'::jsonb)
                  from (select ip.rack r, count(*) c from public.fitted_units f
                          join public.item_profile ip on ip.item_code = f.item_code
                         where f.ship_id = s.id group by 1) z)) order by s.id)
     from public.ships s join public.players p on p.id = s.player_id
     left join public.ship_xp sx on sx.ship_id = s.id where not p.is_npc)) as j`;

const snap = q(SNAP)[0].j;
if (mode === 'before') {
  writeFileSync(file, JSON.stringify(snap));
  console.log(`snapshot written: ${snap.humans.length} humans, ${snap.ships.length} human hulls, levels_bite=${snap.bite}`);
  process.exit(snap.bite === false ? 0 : 1);
}

const was = JSON.parse(readFileSync(file, 'utf8'));
const lvl = (xp, step) => Math.max(1, Math.min(20, Math.floor(Math.sqrt(Math.max(Number(xp), 0) / step)) + 1));
const fails = [];
const say = (ok, msg) => { console.log((ok ? 'ok   ' : 'FAIL ') + msg); if (!ok) fails.push(msg); };

say(was.bite === false && snap.bite === true, `levels_bite: before ${was.bite}, now ${snap.bite}`);

// 2. nothing fitted is shut out
let over = 0;
for (const s of snap.ships) for (const [r, c] of Object.entries(s.used)) if (c > (s.open[r] ?? 0)) over++;
say(over === 0, `fitted racks above open slots: ${over} (want 0)`);

// 3. stats move by exactly the knobs
const step = Number(snap.knobs.level_points_per_step);
const per = { handling: Number(snap.knobs.ship_level_handling_per_level), accuracy: Number(snap.knobs.ship_level_accuracy_per_level), sighting: Number(snap.knobs.ship_level_sighting_per_level) };
let badStat = 0, checked = 0;
const wasShip = new Map(was.ships.map((s) => [s.id, s]));
for (const s of snap.ships) {
  const b = wasShip.get(s.id); if (!b) continue;
  const l = s.xp > 0 ? lvl(s.xp, step) : 1;
  const lb = 1;                              // before the switch every hull read as level 1
  for (const k of Object.keys(s.stats)) {
    const want = b.stats[k] == null ? null : Number(b.stats[k]) + (k in per ? (l - lb) * per[k] : 0);
    const got = s.stats[k] == null ? null : Number(s.stats[k]);
    checked++;
    if (want === null ? got !== null : Math.abs(got - want) > 1e-9) { badStat++; console.log(`  stat ${k} of ${s.id}: want ${want} got ${got}`); }
  }
}
say(badStat === 0, `ship stats off from snapshot + (level-1) x knob: ${badStat} of ${checked} (want 0). Only valid if no gear was fitted or worn in between.`);

// 4. titles and caps
let badTitle = 0;
const wasHuman = new Map(was.humans.map((h) => [h.id, h]));
for (const h of snap.humans) {
  const b = wasHuman.get(h.id); if (!b) continue;
  if (JSON.stringify([h.title, h.trading, h.exploration, h.caps]) !== JSON.stringify([b.title, b.trading, b.exploration, b.caps])) { badTitle++; console.log(`  changed: ${h.id} ${JSON.stringify(b)} -> ${JSON.stringify(h)}`); }
}
say(badTitle === 0, `humans whose title, trading level, exploration level or fleet caps changed: ${badTitle} (want 0; a human who traded in between can move honestly, read the lines)`);

// 5. cost of player_progress for the busiest human
const busy = q(`select e.player_id from public.events e join public.players p on p.id = e.player_id
                 where e.kind = 'VOYAGE_REPORT' and not p.is_npc group by 1 order by count(*) desc limit 1`)[0];
// Five reads and their median: one read on a fresh connection is noise. Dark on 2026-11-06 19:46 UTC,
// five reads gave 17.9, 16.2, 39.3, 60.1, 16.0 ms, so a single read can pass 50 with the switch off.
const reads = [];
for (let i = 0; i < 5; i++) {
  const ex = q(`explain (analyze, timing on) select public.player_progress('${busy.player_id}'::uuid)`)
    .map((r) => r['QUERY PLAN']).find((t) => t.startsWith('Execution Time'));
  reads.push(Number(/([0-9.]+) ms/.exec(ex)[1]));
}
const ms = [...reads].sort((a, b) => a - b)[2];
say(ms < 50, `player_progress(busiest human) median ${ms} ms of ${reads.join(', ')} (bound 50 ms; dark median 17.9 ms)`);

// 6. the arrivals beat (public.arrivals_beats.ms; the cron row is a one-minute loop and says nothing)
const arr = q(`select count(*) n, round(avg(ms)::numeric, 1) avg_ms, round((percentile_cont(0.95) within group (order by ms))::numeric, 1) p95_ms,
                 count(*) filter (where error is not null) errors
                 from public.arrivals_beats where at >= now() - interval '30 minutes'`)[0];
say(Number(arr.n) > 0 && Number(arr.errors) === 0 && Number(arr.avg_ms) <= 3000 && Number(arr.p95_ms) < 5000, `arrivals beats, last 30 min: ${JSON.stringify(arr)} (bound avg <= 3000 ms, p95 < 5000 ms, no error)`);

console.log(fails.length ? `FAIL (${fails.length}): set levels_bite back to false` : 'PASS');
process.exit(fails.length ? 1 : 0);
