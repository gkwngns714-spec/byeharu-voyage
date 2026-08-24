// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE ORDER — the game's order language, and the one order being made
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A SECTION, NOT A SCREEN. These three files used to live inside `features/command/` and
// `features/market/`, which made the Command tab the owner of a thing four screens need: Port
// hands orders over, Market hands orders over, Fleets selects the fleet an order belongs to, and
// Command composes it. Every one of those was reaching across a screen boundary into another
// screen's internals — the shape spaghetti starts in.
//
// `handOff.ts` is the proof it had gone wrong: it was written as an ADAPTER whose stated reason to
// exist was that "commandDraft.ts is owned by the CMD tab". An adapter that exists only to survive
// a boundary is a sign the boundary is in the wrong place. It is still here — it is a useful,
// named intent — but it is no longer a border crossing.
//
// ── WHAT THIS SECTION OWNS ─────────────────────────────────────────────────────────────────────
//   draft.ts    the ONE order being composed right now (fleet, verb, a value per argument name)
//   text.ts     the ONE composer from picks to the exact line `cmd.issue()` receives, walking the
//               server's own verb schema — there is one parser (on the server) and one composer
//   handOff.ts  a named INTENT another section can hand in, without touching the draft's shape
//   estimate.ts the ONE reading of what `cmd.preview()` said a SAIL would be. COMMAND draws the
//               full readout under the composer and MAP prints the passage beside "Sail here";
//               two readers of one estimate is fine, two READINGS of it is the disease
//
// ── WHAT IT MAY DEPEND ON ──────────────────────────────────────────────────────────────────────
// `lib/rpc` types and `lib/json`'s payload readers, and nothing else in the app. It knows no
// screen, no store beyond its own, and no other section. That is what makes it safe for every
// screen to import.
export { useCommandDraft, type CommandIntent, type CommandDraftState } from './draft'
export {
  QUEUE_VERBS,
  argValue,
  composableVerbs,
  enumNaming,
  findVerb,
  fixAction,
  isComplete,
  isQueueVerb,
  missingArgs,
  orderText,
  visibleArgs,
  type FixAction,
} from './text'
export { handOffTrade, type TradeIntent } from './handOff'
export { sailEstimate, type SailEstimate } from './estimate'
