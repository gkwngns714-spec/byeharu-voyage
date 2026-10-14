// THE SHIPPED WORLD WITH THE MERCHANTS SWITCHED ON — the seam the merchant browser spec uses
// (docs/NPC_TRADERS.md §11, the tests/routesOn.fixture.ts pattern).
//
// The build ships merchants dark (0097 `npc_traders_enabled = false`) and the page has no seam to
// flip it, so this opens the build's pre-built world image in Node, turns routes on, LAYS UP one
// Lisbon-homed merchant through the route core (so PORT at Lisbon has a merchant in port, every
// time), runs THE switch — `public.npc_traders_switch(true)`, which plans and starts every other
// merchant through the one executor — and serves the result in place of `db/world-<fp>.tar.gz`.
// The chain fingerprint inside the image is untouched, so the boot's pairing check passes. From
// there the local backend plays pg_cron's part (`tick_arrivals` before every traffic read), so the
// merchants are at sea when the page opens and keep sailing while it is open.

import { test, type Page } from '@playwright/test'
import { createHash } from 'node:crypto'
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { asWorldImageFile } from '../src/lib/db/worldImage'

/** Built once per worker. */
let npcOnImage: Buffer | null = null

// ── AND ONCE PER CHAIN, ON DISK (2026-10-12) ───────────────────────────────────────────────────
// The in-memory cache above is per WORKER, so every `npx playwright test` paid for this fixture
// again: opening the shipped image, laying up a merchant, running the switch over 837 fleets and
// warping six legs is ~9 MINUTES, measured. The night-chart spec was written, corrected and
// re-run five times in one sitting and spent the better part of an hour re-deriving a world that
// had not changed. That is not a test being thorough, it is a test being re-computed.
//
// SO IT IS KEYED AND KEPT. Two things decide the key, and a third — its AGE — decides whether a
// kept copy is still the present (`NPC_ON_MAX_AGE_MS`, 2026-10-14: the merchants sail on `now()`):
//
//   THE SOURCE IMAGE'S FILE NAME, which carries `fingerprintChain(files)` — so a chain that moved
//   by so much as a comment names a different file, misses, and is rebuilt. This is the same
//   property `scripts/db/build-image.mjs` relies on and states.
//
//   THE SHA OF THIS FILE'S OWN SOURCE, so changing what the fixture DOES to that world — a
//   different lay-up, another warp leg, a new knob — misses too. Hashing the file beats a version
//   constant somebody has to remember to bump, which is the version constant that is always one
//   edit out of date.
//
// Under node_modules/.cache, so `npm ci` throws it away with every other build artefact and no
// CI runner inherits one. A miss costs exactly what this always cost.
const CACHE_DIR = path.resolve('node_modules', '.cache', 'byeharu-npc-on')

function cachePathFor(imageName: string): string {
  const self = readFileSync(fileURLToPath(import.meta.url))
  const sha = createHash('sha256').update(self).digest('hex').slice(0, 12)
  return path.join(CACHE_DIR, `${imageName.replace(/\.tar\.gz$/, '')}.fixture-${sha}.tar.gz`)
}

/** The merchant fleet laid up at Lisbon, so PORT has one in port. */
export const LAID_UP_AT_LISBON = 'Carreira da Guiné'

/** How old a kept merchants-on world may be before it is rebuilt — see the check in `npcOn`. */
const NPC_ON_MAX_AGE_MS = 90 * 60_000

export async function npcOn(): Promise<Buffer> {
  if (npcOnImage) return npcOnImage
  const dir = path.resolve('dist', 'db')
  const name = existsSync(dir) ? readdirSync(dir).find((f) => /^world-.*\.tar\.gz$/.test(f)) : undefined
  if (!name) throw new Error(`no world image under ${dir} — run \`npm run build\` first`)

  const cached = cachePathFor(name)
  // A KEPT WORLD GOES STALE BY THE CLOCK, NOT ONLY BY ITS KEY (2026-10-14). The merchants sail on
  // `now()`, so a world dumped hours ago opens with every one of 837 fleets owed hours of voyages at
  // 960x, and the page's first `tick_arrivals` swallows the tab: CI run 38485001228 served a
  // 14-hour-old copy and map.night saw no hull for 60 s with one RPC sent. Older than this, rebuild.
  if (existsSync(cached) && Date.now() - statSync(cached).mtimeMs > NPC_ON_MAX_AGE_MS) rmSync(cached)
  if (existsSync(cached)) {
    npcOnImage = readFileSync(cached)
    return npcOnImage
  }
  const { PGlite } = await import('@electric-sql/pglite')
  const pg = await PGlite.create({ loadDataDir: asWorldImageFile(new Uint8Array(readFileSync(path.join(dir, name)))) })
  try {
    const r = await pg.query(`update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled' returning key`)
    if (r.rows.length !== 1) throw new Error('world_config has no standing_routes_enabled row')
    // HELD WITH THE 'player' PAUSE (0115). Nothing lays a merchant up any more, and npc_tend lifts
    // a 'laid_up' pause at once, so the switch below would put her to sea. 'player' is the one
    // pause the upkeep never lifts, and the harbour still reads ANY pause lying here as `laid_up`
    // (world.port_merchants, 0104), so PORT's list shows her exactly as before.
    const laid = await pg.query<{ r: { ok: boolean } }>(
      `select cmd.standing_route_pause_for(nf.player_id, nf.route_id, true, 'player', 'Held in port for the browser spec.') as r
         from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id where f.name = $1`,
      [LAID_UP_AT_LISBON],
    )
    if (laid.rows.length !== 1 || !laid.rows[0].r.ok) throw new Error(`could not lay up ${LAID_UP_AT_LISBON}`)
    // THE ROSTER THIS FIXTURE SAILS IS CAPPED AT THE SCALE IT WAS MEASURED AT (2026-10-14, 0114).
    // Under 0097's one-buyer rule the switch started ~316 of the 837 merchants and the rest were
    // laid up for want of cargo; 0114 lets three merchants buy one good at one harbour, so nearly
    // every one of them starts — and this file's switch plus six-leg warp, single-threaded on
    // PGlite, went from ~9 minutes to past the 40-minute test timeout (PR #97, shard 3,
    // map.hulls). The browser specs read how merchants are DRAWN, not how many there are, so the
    // fixture sails the first 320 of the roster through `npc_fleet_max` — the live lever 0097
    // names for exactly this — and the image keeps that value.
    const capped = await pg.query(`update public.world_config set value = to_jsonb(320) where key = 'npc_fleet_max' returning key`)
    if (capped.rows.length !== 1) throw new Error('world_config has no npc_fleet_max row')
    const sw = await pg.query<{ j: { enabled: boolean; tend: { started: number } } }>(`select public.npc_traders_switch(true) as j`)
    if (!sw.rows[0].j.enabled || sw.rows[0].j.tend.started < 10) {
      throw new Error(`the switch did not put the merchants to sea: ${JSON.stringify(sw.rows[0].j)}`)
    }
    // A FEW LAPS ALREADY SAILED, so the sheet has earnings to print. The merchants' passages are
    // rewound as the cron would see them and the arrivals tick runs — the executor does the rest —
    // with the merchant pace lifted only for this warp and put back after it (a fixture knob, the
    // same lever proof 12 uses), so the page opens on merchants mid-passage with laps behind them.
    await pg.exec(`update public.standing_routes sr set laps_per_game_day = 0
                     from public.players p where p.id = sr.player_id and p.is_npc`)
    // AND THE FORTNIGHT AT HOME IS LIFTED FOR THE WARP TOO (0101, 2026-10-11). The pace was the
    // only thing holding a route between laps when this warp was written; 0101 added a FLOOR on
    // the same hold — a merchant lies at her home stop for `route_rest_voyage_days` voyage-days
    // after a lap closes — and `laps_per_game_day = 0` does not lift a floor. So the warp closed
    // lap 1 on every route and then every route was held for the rest, and the assert below
    // ("no merchant route with two closed laps") went red on a CORRECT chain. The knob is the one
    // lever, lifted here and put back before the image is dumped, exactly as the pace is; the
    // holds already written by the switch are cleared with it, because a hold written a moment ago
    // outlives the knob that wrote it.
    const rest = await pg.query<{ v: number }>(`select public.wc_num('route_rest_voyage_days')::float8 as v`)
    await pg.exec(`update public.world_config set value = to_jsonb(0) where key = 'route_rest_voyage_days';
                   update public.standing_routes sr set hold_until = null
                     from public.players p where p.id = sr.player_id and p.is_npc`)
    // SIX legs, not three (2026-10-10). Three let the short loops close ONE lap, and one closed lap
    // is exactly what `public.route_earnings` refuses to average — a lap closes on arrival home
    // BEFORE the home sale, so lap 1 is a purchase with no sale (NPC_TRADERS §7.4). Every screenshot
    // this fixture fed therefore read `A lap: first lap under way`, which is the honest answer and a
    // useless picture of the feature the owner asked for. Six legs close a second lap on the
    // three-stop loops. Still few enough that the market is not rewritten: the sinks are not
    // regenerated by a warp that takes no time (a warp that regenerated them too would rewrite every
    // market row and swell the image the page must load — measured: 170 MB against the shipped 9 MB).
    // The daily cap rolls over per leg, as a real leg's hours would roll it.
    for (let i = 1; i <= 6; i++) {
      await pg.exec(`
        update public.voyages v set departed_at = v.departed_at - (v.eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
          from public.fleets f join public.players p on p.id = f.player_id and p.is_npc
         where v.fleet_id = f.id and v.status = 'SAILING';
        select public.tick_arrivals(now());
        delete from public.trade_daily where player_id in (select id from public.players where is_npc);`)
    }
    await pg.exec(`update public.standing_routes sr set laps_per_game_day = public.wc_int('npc_laps_per_game_day')
                     from public.players p where p.id = sr.player_id and p.is_npc`)
    await pg.query(`update public.world_config set value = to_jsonb($1::numeric) where key = 'route_rest_voyage_days'`,
                   [rest.rows[0].v])
    const restBack = await pg.query<{ v: number }>(`select public.wc_num('route_rest_voyage_days')::float8 as v`)
    if (restBack.rows[0].v !== rest.rows[0].v) {
      throw new Error(`the fortnight knob was not put back: ${restBack.rows[0].v} vs ${rest.rows[0].v}`)
    }
    const laps = await pg.query<{ n: number }>(
      `select count(*)::int as n from public.standing_route_laps x join public.npc_fleets nf on nf.route_id = x.route_id where x.closed_at is not null`,
    )
    if (laps.rows[0].n < 5) throw new Error(`the warp closed only ${laps.rows[0].n} merchant laps`)
    // AND AT LEAST ONE MERCHANT HAS A LAP AVERAGE TO SHOW, which needs two closed laps on one route:
    // the thing the screenshots are taken for.
    const twice = await pg.query<{ n: number }>(
      `select count(*)::int as n from (select x.route_id from public.standing_route_laps x
         join public.npc_fleets nf on nf.route_id = x.route_id
        where x.closed_at is not null group by x.route_id having count(*) >= 2) y`,
    )
    if (twice.rows[0].n < 1) throw new Error('the warp left no merchant route with two closed laps')
    npcOnImage = Buffer.from(await (await pg.dumpDataDir('gzip')).arrayBuffer())
    // Written only after every assertion above has held, so a cache entry is always a world that
    // passed this fixture's own checks — never a half-warped one from a run that threw.
    mkdirSync(CACHE_DIR, { recursive: true })
    writeFileSync(cached, npcOnImage)
  } finally {
    await pg.close()
  }
  return npcOnImage
}

/** Serve the merchants-on world to `page` in place of the shipped image. */
export async function serveNpcOn(page: Page): Promise<void> {
  // A COLD BUILD IS NOT THE TEST. Every migration moves the cache key, and on CI the first test to
  // ask builds this world from scratch (~20 min, 2026-10-13 run 38362106885) inside its own
  // 10-minute budget and dies before it looks at the chart. The build gets its own 30 minutes on
  // top of the test's budget.
  test.info().setTimeout(test.info().timeout + 30 * 60_000)
  const image = await npcOn()
  await page.route('**/db/world-*.tar.gz', (route) => route.fulfill({ body: image, contentType: 'application/gzip' }))
}
