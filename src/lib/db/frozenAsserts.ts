// ═══════════════════════════════════════════════════════════════════════════════════════════════
// frozenAsserts — the ONE place a FROZEN migration's self-assert is read differently on PGlite
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// WHY THIS EXISTS (2026-10-27). Two self-asserts in files that production applied long ago fail
// for reasons that are not the chain's:
//
//   * 0108 (d5) requires world.route_board() to average <= 400 ms over 10 calls. That is a
//     stopwatch, and on wasm PostgreSQL it decides by the machine: PC gkwng measured 426 and
//     451 ms, so every from-zero replay there (a pruned prefix cache, `npm run build`) died at
//     0108 while CI's runners passed. A wall-clock threshold on shared hardware is a flake
//     (tests/map.lag.spec.ts's header says the same of the client).
//   * 0019 (g) plays the quay's top row BUY -> SAIL -> SELL. The voyage's hazard dice are seeded
//     from its id (0006 voyage.rng), which is gen_random_uuid(), so about one boot in a few dozen
//     rolled a PIRATES / STRIPPED day (0007 voyage.settle empties the hold) and the SELL answered
//     E_NO_CARGO: "the quay predicted 6818 out / 7706 in and the orders moved 6818 / <NULL>"
//     (PR #343, run 40292383876, cold boot; green on re-run). What it proves is that the price
//     OFFERED is the price CHARGED; the sea leaving the cargo alone is another question, and
//     0034/0092/0093/0096 close that door the same way inside their own probes.
//
// WHY NOT EDIT THE FILES. An applied migration is history (supabase/migrations/README.md §1), and
// editing one moves every prefix-cache key after it, prunes every kept snapshot and sends CI from
// zero — the owner's law is that a pull request's CI never does that. So the files stay byte for
// byte, and the APPLIER reads these two asserts differently instead:
//
//   * Only text inside the file's LAST `do $$ … $$` block (the self-assert) may be touched, and
//     only a self-assert's PROBE, which rolls itself back: the database a patched file leaves
//     behind is the one the unpatched file leaves behind. Snapshots, images and their keys are
//     unchanged (the prefix key and fingerprintChain() hash the FILE, which nobody alters).
//   * Every patch names the exact text it replaces, and that text must occur EXACTLY ONCE — a
//     patch that no longer fits is a loud failure, never a silent no-op.
//   * Each patch keeps the assert able to fail.
//   * Real PostgreSQL (CI's disposable-chain on Supabase, and production) applies the files as
//     written, through `supabase db push`, which never reads this module; 0108's 400 ms holds there.
//
// This is not a place for new migrations' problems: a migration that is not yet applied anywhere
// is fixed in its own file. A patch belongs here only when the file is frozen (<= prod head).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export interface FrozenAssertPatch {
  /** The migration's full filename. */
  file: string
  /** Exact text inside the file's final `do $$` block; must occur exactly once in the file. */
  find: string
  /** What the applier executes in its place. */
  replace: string
  /** One line, for the log and the reader. */
  why: string
}

export const FROZEN_ASSERT_PATCHES: readonly FrozenAssertPatch[] = [
  {
    file: '20260818000019_the_quay_names_the_port_that_pays.sql',
    find: '    v_played   := world.trade_routes(v_lis, v_fleet, 1, null);\n',
    replace:
      "    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';\n" +
      '    v_played   := world.trade_routes(v_lis, v_fleet, 1, null);\n',
    why: '0019 (g): no hazard on the probe voyage (random voyage id -> PIRATES/STRIPPED -> E_NO_CARGO); inside the rolled-back probe',
  },
  {
    file: '20260818000108_the_board_prints_what_a_lane_asks_of_you.sql',
    find: '    if v_ms > 400 then\n',
    replace: '    if v_ms > 1200 then\n',
    why: '0108 (d5): 400 ms -> 1,200 ms a call on PGlite (426/451 ms measured on a slower PC); real Postgres keeps 400',
  },
]

const BY_FILE = new Map(FROZEN_ASSERT_PATCHES.map((p) => [p.file, p]))

/** Where the file's final `do $$` block starts, or -1. */
function lastDoBlock(sql: string): number {
  return Math.max(sql.lastIndexOf('\ndo $$\n'), sql.startsWith('do $$\n') ? 0 : -1)
}

/**
 * The SQL the applier executes for `file`: the file's own text, or — for a frozen migration with a
 * patch above — that text with its one self-assert line replaced. Throws when a patch no longer fits.
 */
export function sqlToApply(file: { name: string; sql: string }): string {
  const patch = BY_FILE.get(file.name)
  if (!patch) return file.sql
  const at = file.sql.indexOf(patch.find)
  const again = at === -1 ? -1 : file.sql.indexOf(patch.find, at + 1)
  const block = lastDoBlock(file.sql)
  if (at === -1 || again !== -1 || block === -1 || at < block) {
    throw new Error(
      `FROZEN ASSERT PATCH NO LONGER FITS: ${file.name} — the text it replaces must occur exactly once, ` +
        `inside the file's final do $$ block (found at ${at}, again at ${again}, last do-block at ${block}). ` +
        'A frozen migration changed, or the patch is stale: fix src/lib/db/frozenAsserts.ts.',
    )
  }
  return file.sql.slice(0, at) + patch.replace + file.sql.slice(at + patch.find.length)
}
