// ═══════════════════════════════════════════════════════════════════════════════════════════════
// RETIRED. Migration 0003 is APPLIED TO PRODUCTION and therefore frozen — this script exists only
// to refuse, out loud, the mistake it was once used for.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// This script used to write supabase/migrations/20260818000003_… from data/*.json. That was
// correct exactly until 0003 shipped. On 2026-08-24 it was run again after production had applied
// 0003: the file changed under a version the deploy ledger already recorded, so production kept
// the original 70 goods and 214 harbours while every fresh rebuild silently got 243 — and nothing
// anywhere went red. "Never edit an applied migration" (supabase/migrations/README.md §1) is the
// rule this violated; the repair cost a reverted file, a growth migration and a standing guard.
//
// HOW A WORLD CHANGE SHIPS NOW:
//   1. edit the data (scripts/roster/* → node scripts/build-ports.mjs, data/goods.json,
//      scripts/build-sea-routes.mjs …) and, for a NEW port, add its pinned code to PORT_CODES in
//      scripts/lib/world-derive.mjs (the derivation refuses an unpinned port and suggests a code)
//   2. node scripts/build-world-growth.mjs <next-version> <name_in_plain_words>
//      — it measures the APPLIED world by running the real chain, diffs it against the data, and
//      emits the delta with a self-assert that pins the end state to the data by set equality
//   3. npm run db:apply && npm run db:proof — the world guard (scripts/db/world-guard.mjs) fails
//      any apply whose world does not equal data/*.json, so forgetting step 2 cannot stay green
//
// The derivation itself (codes, cultures, nations, dev columns, goods columns, leg canonicalising)
// lives in scripts/lib/world-derive.mjs — ONE authority, composed by the growth generator and the
// guard. Nothing is lost by this refusal: the full seed emitter this file once carried is in git
// (last working copy at commit 1ae5ca5), and the only legitimate reason to want it back is a world
// RESTART, which is an owner decision, not a script run.

console.error(
  'REFUSED: migration 0003 has been applied to production and is frozen for ever.\n' +
    'Editing or regenerating an applied migration forks the world: production keeps the old seed\n' +
    'while fresh rebuilds get the new one, and everything stays green while they diverge — which\n' +
    'is exactly what happened on 2026-08-24 and took a day to repair.\n\n' +
    'To change the world: edit data/*.json (and PORT_CODES for a new port), then\n' +
    '  node scripts/build-world-growth.mjs <next-version> <name_in_plain_words>\n' +
    'and let npm run db:apply / db:proof certify the result against the data.',
)
process.exit(1)
