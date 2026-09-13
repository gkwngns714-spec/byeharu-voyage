// ═══════════════════════════════════════════════════════════════════════════════════════════════
// proof-courses.mjs — the PROOFS' OWN COURSE PROPOSALS, so a proof can sail like a player sails.
//
// Under 0039 the server never finds a path: the CLIENT proposes a course and the server verifies
// and measures it (docs/NAVIGATION_PLAN.md §3). A proof that sails is playing the client's part,
// so it needs proposals of its own — produced by THE one pathfinder (src/lib/sea) over the very
// raster the applied chain serves, exactly as the browser produces them. This module:
//
//   * builds courses between every pair of places within ~1,900 sailed nm (the trade-scan radius
//     plus margin — every first voyage, one-hop soak and round trip the proofs sail), plus the
//     named long hauls proof 09 walks (Lisbon→Nagasaki, the Arctic control);
//   * CACHES them in scripts/db/.proof-courses.json (gitignored), fingerprinted by the raster and
//     the port set — a stale cache regenerates rather than proposing over water that moved;
//   * installs them into the database as a TEST FIXTURE (schema `proof`, like the Supabase
//     preamble: never deployed, invisible to the proofs' public-table digest):
//       proof.course(a, b)      the stored proposal, reversed when only the mirror is held
//       proof.sail(fleet, dest) cmd.issue('SAIL TO <dest>', course from where she lies)
//       proof.issue(fleet, txt) cmd.issue, attaching a course when the text is a SAIL — for the
//                               soak, whose orders are composed as text
//
// The fixture proposes; the SERVER still refuses land, measures the miles and applies every gate —
// nothing here can make an illegal voyage legal, only a legal one findable.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { fileURLToPath } from 'node:url'
import path from 'node:path'
import { navFromServed, floodFrom, floodPathTo, findPath } from '../../src/lib/sea/index.ts'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const CACHE = path.join(HERE, '.proof-courses.json')

/** Pairs beyond the radius that a proof sails by name. */
const SPECIALS = [
  ['LIS', 'NAG'], // proof 09's Arctic control: the honest road to Japan
]

const COVER_NM = 1900

/** Bumped whenever the SHAPE of a stored proposal changes, so a cache built under the old shape is
 *  regenerated rather than trusted. The raster/port fingerprint below cannot see this: 0076 moved
 *  every course end from the quay to the ROADSTEAD without moving one water cell or one port.
 *  0085 moved 25 roadsteads onto their channels without moving a cell or a port either — the
 *  fingerprint now covers the served roadsteads too, and the shape is bumped for the same reason. */
const SHAPE = '0085-served-roadstead'

/**
 * THE ROADSTEAD a place is reached from is READ, never re-derived. Until 0085 this file kept its
 * own copy of the rule — a `roadsteadOf` snapping the served raster with `snapToNav` and taking the
 * cell centre — which was a SECOND author of "where is this port reached from" beside the one the
 * chain seeds into public.sea_reaches (docs/NO_SPAGHETTI.md §1, question 3: can it disagree? It
 * did, for the 25 places 0085 moved onto their channels, and every proposal to them would have
 * been refused E_OFF_COURSE). Now the endpoints are the served `roadstead_lat/lon`, exactly the
 * numbers cmd.do_sail verifies a course against, and `proof.courses` stays what it always was:
 * findable, never legal — the server still refuses land and measures the miles.
 */

export async function installProofCourses(db, { log = console.log } = {}) {
  const raster = (
    await db.query(`select cols, rows, cell_deg::float8 as cell_deg, bits_per_cell,
                           replace(encode(cells, 'base64'), e'\\n', '') as cells_base64
                      from public.sea_raster where id = 1`)
  ).rows[0]
  if (!raster) throw new Error('proof-courses: the chain serves no sea raster — is 0038 applied?')
  const ports = (
    await db.query(`select p.code, p.lat::float8 as lat, p.lon::float8 as lon,
                           sr.roadstead_lat::float8 as rlat, sr.roadstead_lon::float8 as rlon
                      from public.ports p
                      left join public.sea_reaches sr on sr.port_id = p.id
                     order by p.code`)
  ).rows
  // A place served no roadstead cannot be sailed from or to; refused here, where the cause is,
  // rather than as a far-off E_OFF_COURSE in whichever proof reaches it first.
  for (const p of ports) {
    if (!Number.isFinite(p.rlat) || !Number.isFinite(p.rlon)) {
      throw new Error(`proof-courses: ${p.code} is served no roadstead (${p.rlat}, ${p.rlon}) — is 0076 applied?`)
    }
  }
  const fingerprint = createHash('md5')
    .update(SHAPE)
    .update(raster.cells_base64)
    .update(ports.map((p) => `${p.code}:${p.lat}:${p.lon}:${p.rlat}:${p.rlon}`).join('|'))
    .digest('hex')

  let cache = null
  if (existsSync(CACHE)) {
    try {
      cache = JSON.parse(readFileSync(CACHE, 'utf8'))
    } catch {
      cache = null
    }
    if (cache && cache.fingerprint !== fingerprint) {
      log('proof-courses: cache is stale for this raster/port set — regenerating')
      cache = null
    }
  }

  if (!cache) {
    const t0 = performance.now()
    const nav = navFromServed(raster)
    // 0076: ROADSTEAD to ROADSTEAD, because that is the passage cmd.do_sail verifies. A proposal
    // that still began at the quay would be refused E_OFF_COURSE for every place whose roadstead
    // lies further from it than `course_join_nm` (15 nm, 0047:106) — a large minority of them.
    // 0085: the roadstead is the SERVED one, read above, not a snap of our own.
    const roads = new Map(ports.map((p) => [p.code, { lat: p.rlat, lon: p.rlon }]))
    const courses = {}
    for (let i = 0; i < ports.length; i++) {
      const a = ports[i]
      const ra = roads.get(a.code)
      const flood = floodFrom(nav, ra, COVER_NM)
      if (!flood) throw new Error(`proof-courses: ${a.code}'s roadstead cannot reach water`)
      for (let j = i + 1; j < ports.length; j++) {
        const b = ports[j]
        const r = floodPathTo(flood, ra, roads.get(b.code))
        if (!r || r.nm > COVER_NM) continue
        courses[`${a.code}|${b.code}`] = r.path.map(([lat, lon]) => [
          Number(lat.toFixed(4)),
          Number(lon.toFixed(4)),
        ])
      }
    }
    for (const [ac, bc] of SPECIALS) {
      const a = roads.get(ac)
      const b = roads.get(bc)
      if (!a || !b) throw new Error(`proof-courses: special pair ${ac}-${bc} names a missing port`)
      const key = ac < bc ? `${ac}|${bc}` : `${bc}|${ac}`
      if (courses[key]) continue
      const r = findPath(nav, a, b)
      if (!r) throw new Error(`proof-courses: no course for special pair ${ac}-${bc}`)
      courses[key] = r.path.map(([lat, lon]) => [Number(lat.toFixed(4)), Number(lon.toFixed(4))])
    }
    cache = { fingerprint, courses }
    writeFileSync(CACHE, JSON.stringify(cache), 'utf8')
    log(
      `proof-courses: ${Object.keys(courses).length} course(s) computed in ` +
        `${((performance.now() - t0) / 1000).toFixed(0)} s and cached`,
    )
  }

  await db.exec(`
    create schema if not exists proof;
    create table if not exists proof.courses (a text, b text, course jsonb, primary key (a, b));
  `)
  await db.query(
    `insert into proof.courses (a, b, course)
     select split_part(e.key, '|', 1), split_part(e.key, '|', 2), e.value
       from jsonb_each($1::jsonb) e
     on conflict (a, b) do update set course = excluded.course`,
    [JSON.stringify(cache.courses)],
  )
  await db.exec(`
    create or replace function proof.course(p_a text, p_b text)
    returns jsonb
    language sql
    stable
    as $$
      -- canonical a<b is stored; the mirror is the reversed polyline — the same water backwards.
      select coalesce(
        (select course from proof.courses where a = p_a and b = p_b),
        (select (select jsonb_agg(t.e order by t.ord desc)
                   from jsonb_array_elements(course) with ordinality t(e, ord))
           from proof.courses where a = p_b and b = p_a))
    $$;

    create or replace function proof.sail(p_fleet uuid, p_dest text)
    returns jsonb
    language plpgsql
    as $$
    -- A proof's SAIL, proposed like a player's: the course from where she lies (or, queued at
    -- sea, from where the current voyage ends) to the destination. When no course is held, the
    -- issue goes course-less and the server's straight-line fallback answers — or refuses, which
    -- for a proof is the honest outcome, never a hidden one.
    declare
      v_from text;
    begin
      select coalesce(
               (select p.code from public.fleets f join public.ports p on p.id = f.port_id where f.id = p_fleet),
               (select p.code from public.voyages v join public.ports p on p.id = v.dest_port_id
                 where v.fleet_id = p_fleet and v.status = 'SAILING'))
        into v_from;
      return cmd.issue(p_fleet, 'SAIL TO ' || p_dest, null,
                       case when v_from is null then null else proof.course(v_from, p_dest) end);
    end $$;

    create or replace function proof.issue(p_fleet uuid, p_text text)
    returns jsonb
    language plpgsql
    as $$
    -- The soak composes orders as TEXT; a SAIL among them gets its course attached here. This is
    -- a prefix check in a test fixture, not a second grammar: the text still goes through the one
    -- parser, and everything that is not a SAIL passes through untouched.
    declare
      v_dest text;
    begin
      if upper(p_text) like 'SAIL %' then
        v_dest := (regexp_split_to_array(btrim(p_text), '\\s+'))[array_upper(regexp_split_to_array(btrim(p_text), '\\s+'), 1)];
        return proof.sail(p_fleet, v_dest);
      end if;
      return cmd.issue(p_fleet, p_text);
    end $$;
  `)

  const n = (await db.query(`select count(*)::int c from proof.courses`)).rows[0].c
  const spot = (await db.query(`select proof.course('LIS', 'CAD') is not null as ok`)).rows[0].ok
  if (n < 100 || !spot) {
    throw new Error(
      `proof-courses: the fixture is vacuous (${n} course(s), LIS-CAD ${spot ? 'held' : 'MISSING'})`,
    )
  }
  log(`proof-courses: fixture installed — ${n} course(s), LIS↔CAD spot-checked`)
  return n
}
