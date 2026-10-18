// gen-0202-courses.mjs <world-image.tar.gz> — the seed of migration 0202's public.npc_courses: every directed leg of
// the merchant roster's loops as the chain founds them (a fresh world image, built by `npm run db:image` at 0199),
// one course per (from, to) — the fewest points, then the text — as [from_code, to_code, course], sorted.
// The migration embeds this output verbatim between its $seed$ quotes; re-run to reproduce it.
import { readFile } from 'node:fs/promises'
import { gunzipSync } from 'node:zlib'
import { PGlite } from '@electric-sql/pglite'

const image = process.argv[2]
if (!image) throw new Error('usage: node scripts/db/gen-0202-courses.mjs <world-image.tar.gz>')
const db = await PGlite.create({ loadDataDir: new Blob([gunzipSync(await readFile(image))], { type: 'application/x-tar' }) })
const { rows } = await db.query(`
  with ms as (select s.port_id, s.course, lead(s.port_id) over w nxt, first_value(s.port_id) over w first_port
                from public.standing_route_stops s join public.standing_routes sr on sr.id = s.route_id
                join public.players p on p.id = sr.player_id and p.is_npc
              window w as (partition by s.route_id order by s.ord)),
  legs as (select distinct on (a.code, b.code) a.code fa, b.code tb, m.course
             from ms m join public.ports a on a.id = m.port_id join public.ports b on b.id = coalesce(m.nxt, m.first_port)
            where a.id <> b.id
            order by a.code, b.code, jsonb_array_length(m.course), m.course::text)
  select jsonb_agg(jsonb_build_array(fa, tb, course) order by fa, tb) as seed from legs`)
process.stdout.write(JSON.stringify(rows[0].seed))
process.exit(0)
