// ═══════════════════════════════════════════════════════════════════════════════════════════════
// READING A FIELD OUT OF A JSONB PAYLOAD — safely, and in ONE place
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// MACHINERY. It knows nothing about this game: `Record<string, unknown>` in, a number or a string
// or null out. It would be equally at home in a different game, which is the test
// `docs/SECTIONS.md` gives for `src/lib/*`.
//
// ── WHY IT EXISTS (2026-08-23) ─────────────────────────────────────────────────────────────────
// `docs/NO_SPAGHETTI.md` §2 names `num` and `str` as one of four open duplications, measured on
// 2026-08-22, and says the standing instruction is to fold them:
//
//   * `features/command/PreviewPanel.tsx:131,138`
//   * `features/ledger/LedgerScreen.tsx:357,363`
//
// **and they had already drifted**, which is the whole disease: LEDGER's `num` accepts a numeric
// that arrived as a string (*"jsonb numerics can arrive as a JSON number or as a string, depending
// on the transport"*) and COMMAND's did not, so the same payload read two ways on two screens and
// one of the answers was wrong on some transports. The Map tab was about to be the THIRD reader —
// `cmd.preview()`'s SAIL estimate — and §1's threshold is explicit: *"Written a second time → it
// becomes a function. Found a third time → stop the feature and fold it, the same turn."*
//
// THE STRONGER VERSION SURVIVED, both times, because §6 forbids weakening to green:
//   * `num` keeps LEDGER's string-tolerance — the transport-proof one.
//   * `str` keeps LEDGER's empty-string rejection — `''` is a missing value, and a caller that
//     renders `str(...) && <Row/>` should not draw a blank row for it.
// PreviewPanel's argument was `Record<string, unknown> | undefined` (an estimate the server may
// not have returned) and LEDGER's was not, so the parameter here takes the wider of the two and
// both callers compile unchanged.

/** A string field, or null when it is absent, not a string, or empty. */
export function str(payload: Record<string, unknown> | undefined, key: string): string | null {
  const v = payload?.[key]
  return typeof v === 'string' && v !== '' ? v : null
}

/** A numeric field, or null when it is absent or not a finite number.
 *  jsonb numerics can arrive as a JSON number or as a string, depending on the transport. */
export function num(payload: Record<string, unknown> | undefined, key: string): number | null {
  const v = payload?.[key]
  if (typeof v === 'number') return Number.isFinite(v) ? v : null
  if (typeof v === 'string' && v.trim() !== '') {
    const n = Number(v)
    return Number.isFinite(n) ? n : null
  }
  return null
}
