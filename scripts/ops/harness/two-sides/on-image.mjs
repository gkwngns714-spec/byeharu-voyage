// on-image.mjs <browser-pNNNN image .tar.gz>: 0320 and the WHOLE of proof 28 on a real kept world image (older than the head, none of whose later files touch a fight), rolled back. Local only.
import { readFile } from 'node:fs/promises'
import { gunzipSync } from 'node:zlib'
import { PGlite } from '@electric-sql/pglite'
const db = await PGlite.create({ loadDataDir: new Blob([gunzipSync(await readFile(process.argv[2]))], { type: 'application/x-tar' }) })
const file = (await readFile('supabase/migrations/20260818000320_a_fight_has_two_sides.sql', 'utf8')).replaceAll('\r', '')
const proof = (await readFile('scripts/db/proofs/28_fight_sides.sql', 'utf8')).replaceAll('\r', '')
const notices = []
const t = Date.now()
await db.exec('begin')
try {
  await db.exec(`${file}\n${proof}`, { onNotice: (n) => notices.push(n.message ?? String(n)) })
  console.log(`GREEN ${Date.now() - t} ms\n${notices.filter((n) => /self-assert ok|PASS:/.test(n)).join('\n')}`)
} catch (e) { console.log(`FAIL ${String(e?.message ?? e).slice(0, 1500)}`); process.exitCode = 1 }
await db.exec('rollback')
await db.close()
