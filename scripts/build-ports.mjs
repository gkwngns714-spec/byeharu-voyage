// ═══════════════════════════════════════════════════════════════════════════════════════════════
// RETIRED (2026-09-14). data/ports.json is the AUTHORED roster and this script would overwrite it
// with a copy that has been stale since migration 0058 — so it exists only to refuse, out loud.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// This script used to compose data/ports.json from scripts/roster/*.mjs (the editorial fields)
// plus scripts/coords.cache.json (the Wikidata coordinates). That was correct exactly until the
// roster's `goods` arrays stopped being the authority: 0058 rebalanced them to the owner's count
// law, 0062 restored the researched lists and gave every offer its geography, 0065 spread the
// catalogue so no good sits in four cities — all three edited data/ports.json directly, and
// docs/REGIONAL_GOODS.md §I says so: *"`data/ports.json` is the authorship"*. The roster files
// were never brought along. Measured 2026-09-14: the roster still says Acapulco sells silk-cloth
// and porcelain, which 0062 moved off its quay; running this script would have put them back,
// world-guard would have gone red against the applied chain, and the "fix" would have been a
// migration carrying a regression. Two authors for one roster is spaghetti (docs/NO_SPAGHETTI.md
// §1); the copy that lost is this one.
//
// WHAT THE ROSTER FILES ARE NOW: the FETCH MANIFEST for scripts/fetch-coords.mjs — id, enwiki
// title (or a pinned qid) and country, so a NEW port's coordinate can be resolved and cross-
// checked. Their `goods` fields are inert; new entries carry none (scripts/roster/americas.mjs,
// the Pacific Americas growth, is the first written that way).
//
// HOW A NEW PORT SHIPS NOW (the 2026-09-14 growth is the worked example, docs/DEV_LOG.md):
//   1. add its manifest entry to scripts/roster/<area>.mjs and run node scripts/fetch-coords.mjs
//      — the coordinate is still never typed by hand; it lands in scripts/coords.cache.json
//   2. write its record into data/ports.json in the file's shape, taking lat/lon/source from the
//      cache, and its pinned code into PORT_CODES (scripts/lib/world-derive.mjs)
//   3. node scripts/check-ports.mjs — the offline validator (count law, native-or-entrepot, no
//      good in four cities, bbox)
//   4. node scripts/build-world-growth.mjs <version> <name> — the growth migration; then
//      node scripts/build-sea-migration.mjs — its roadstead and sailed distances, cut AFTER the
//      growth because it reads the ports out of the applied chain
//   5. npm run db:apply && npm run db:proof
//
// The last working copy of the composer is in git (commit 1573fa4).

console.error(
  'REFUSED: data/ports.json is the authored roster since migration 0058, and scripts/roster/*.mjs\n' +
    'has been a stale copy of it since then. Composing the file from the roster would silently\n' +
    'undo 0058/0062/0065 and fail world-guard against the applied chain.\n\n' +
    'To add a port: manifest entry in scripts/roster/*.mjs → node scripts/fetch-coords.mjs →\n' +
    'write the record into data/ports.json from scripts/coords.cache.json → pin its code in\n' +
    'scripts/lib/world-derive.mjs → node scripts/check-ports.mjs → build-world-growth.mjs and\n' +
    'build-sea-migration.mjs. See the header of this file.',
)
process.exit(1)
