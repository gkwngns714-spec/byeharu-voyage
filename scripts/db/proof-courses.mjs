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

export async function installProofCourses(db, { log = console.log } = {}) {
  const raster = (
    await db.query(`select cols, rows, cell_deg::float8 as cell_deg, bits_per_cell,
                           replace(encode(cells, 'base64'), e'\\n', '') as cells_base64
                      from public.sea_raster where id = 1`)
  ).rows[0]
  if (!raster) throw new Error('proof-courses: the chain serves no sea raster — is 0038 applied?')
  const ports = (
    await db.query(`select code, lat::float8 as lat, lon::float8 as lon from public.ports order by code`)
  ).rows
  const fingerprint = createHash('md5')
    .update(raster.cells_base64)
    .update(ports.map((p) => `${p.code}:${p.lat}:${p.lon}`).join('|'))
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
    const courses = {}
    for (let i = 0; i < ports.length; i++) {
      const a = ports[i]
      const flood = floodFrom(nav, a, COVER_NM)
      if (!flood) throw new Error(`proof-courses: ${a.code} cannot reach water`)
      for (let j = i + 1; j < ports.length; j++) {
        const b = ports[j]
        const r = floodPathTo(flood, a, b)
        if (!r || r.nm > COVER_NM) continue
        courses[`${a.code}|${b.code}`] = r.path.map(([lat, lon]) => [
          Number(lat.toFixed(4)),
          Number(lon.toFixed(4)),
        ])
      }
    }
    const byCode = new Map(ports.map((p) => [p.code, p]))
    for (const [ac, bc] of SPECIALS) {
      const a = byCode.get(ac)
      const b = byCode.get(bc)
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
