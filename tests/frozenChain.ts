// THE FROZEN PRE-GROWTH CHAIN — one cut-off and one filter, for every spec that needs a real world
// but not the whole one.
//
// GROWTH_SPLIT is the production baseline of 2026-08-24: everything below it had been applied to
// production before the growth shipped. It does NOT move when later migrations land (they join the
// growth half); it would only move with a documented new baseline, which is a deploy-history fact.
//
// WHY A PREFIX AT ALL (2026-10-13). After 0105's merchant roster, one full apply of the chain in
// Node PGlite cost ~40-45 min under CI load (PR #94, run 38371308971). The specs that build on this
// prefix prove a CODE PATH — the applier, the boot, the rebuild decision, the image fallback — and
// a prefix walks every line of it. The whole chain is applied from zero, every self-assert with it,
// by `disposable-chain` on a real Supabase and by the world-image build.
import { loadChain } from '../src/lib/db/chainSource.node.mjs'

export const GROWTH_SPLIT = '20260818000041'

/** The files of `files` that sit below the growth baseline, in order. */
export function beforeGrowth<T extends { name: string }>(files: readonly T[]): T[] {
  return files.filter((f) => f.name.slice(0, 14) < GROWTH_SPLIT)
}

/** The frozen pre-growth chain read from disk — a `loadChain` to hand to openLocalDb. */
export async function frozenChain() {
  return beforeGrowth(await loadChain())
}
