// THE ORDER LINE — the string, derived from what the player picked. Pure; no React, no world.
//
// F.4: "Submit sends the string, not a structured object. There is exactly one parser." So the
// composer never sends its intent object anywhere: at the moment of issue this file turns the
// picked arguments into the exact line `cmd.issue(fleet_id, raw_text, expected_version)` receives,
// and the screen shows that line, read-only, while it assembles. The player learns the language by
// watching it write itself.
//
// EVERYTHING HERE IS DRIVEN BY THE SERVER'S OWN SCHEMA (`world.snapshot().verbs`, which is
// `cmd.verb_schema()`). There is no verb table on this side of the wire any more — grammar.ts and
// parse.ts were deleted with the typing box. What is encoded below is not a grammar; it is the
// three facts about how `cmd.parse()` (migration 0008) READS a line, each of which would otherwise
// have to be discovered by a player getting E_PARSE:
//
//   1. A leading fleet name is consumed only by SAIL / PROVISION / HIRE / REPAIR, and only in the
//      FIRST position. So a fleet argument is emitted only when the schema lists it first.
//   2. BUY and SELL take NO fleet at all: their parser skips the words FOR/FROM as noise and then
//      demands a number, so `BUY sal 50 FOR Gaivota` is a parse error. The fleet travels as
//      cmd.issue()'s own `fleet_id` argument — which is where it belongs, and where it always is.
//   3. Ports and goods are emitted as CODES (`CAD`, `black-pepper`). cmd.resolve_port/good match a
//      code exactly before anything else, and a display name like "Banda Aceh" is two tokens to a
//      parser that splits on whitespace.
//
// If the server ever adds a verb or an argument, this file needs no edit: it walks whatever
// schema arrived.

import type { VerbArg, VerbSpec } from '../../lib/rpc'

/**
 * CANCEL and CLEAR are served in the same schema as the other six, but their only argument is a
 * row of the queue — so they are MADE on the queue, where that row is, not in the composer. There
 * is exactly one way to cancel and one way to clear in the UI, which is the point.
 */
export const QUEUE_VERBS: readonly string[] = ['CANCEL', 'CLEAR']

export function isQueueVerb(verb: string): boolean {
  return QUEUE_VERBS.includes(verb.toUpperCase())
}

/** The verbs the composer offers: the server's list, minus the two the queue owns. */
export function composableVerbs(verbs: readonly VerbSpec[]): VerbSpec[] {
  return verbs.filter((v) => !isQueueVerb(v.verb))
}

export function findVerb(verbs: readonly VerbSpec[], verb: string | null): VerbSpec | undefined {
  if (!verb) return undefined
  return verbs.find((v) => v.verb === verb.toUpperCase())
}

/**
 * The argument an enum VALUE stands in for, if any. `PROVISION`'s `mode` offers `FULL` and `DAYS`,
 * and `DAYS` is the name of the next argument — choosing it is choosing to say a number of days.
 * The relationship is in the schema; reading it here is what keeps it a single relationship
 * rather than a per-verb rule.
 */
function revealedArg(spec: VerbSpec, arg: VerbArg, value: string | undefined): VerbArg | undefined {
  if (arg.type !== 'enum' || !value) return undefined
  return spec.args.find((a) => a !== arg && a.name.toUpperCase() === value.toUpperCase())
}

/**
 * THE SAME RELATIONSHIP, READ FROM THE OTHER END: the enum argument (and which of its values)
 * that NAMES this argument. `days` is named by `mode`'s value `DAYS`; an argument nothing names
 * gets `undefined`.
 *
 * This is the one reading of "these two arguments are halves of one question" — `revealedArg`
 * above walks it value→argument for the line, this walks it argument→enum for the composer.
 * The composer needs it because BOTH halves are on screen at once (the owner, 2026-08-23: *"in
 * provision, full and days, they does not have to be folded"*): answering the named argument IS
 * choosing the enum value, so the composer writes both, and `orderText` below refuses to emit a
 * named argument whose enum currently says something else.
 */
export function enumNaming(
  spec: VerbSpec,
  arg: VerbArg,
): { enumArg: VerbArg; value: string } | undefined {
  for (const a of spec.args) {
    if (a.type !== 'enum' || a === arg) continue
    const value = (a.values ?? []).find((v) => v.toUpperCase() === arg.name.toUpperCase())
    if (value !== undefined) return { enumArg: a, value }
  }
  return undefined
}

/** True when the enum that names this argument currently says its name — the condition under
 *  which the argument MEANS anything. An argument nothing names always means something. */
function namedByItsEnum(spec: VerbSpec, arg: VerbArg, args: Record<string, string>): boolean {
  const naming = enumNaming(spec, arg)
  if (!naming) return true
  const said = args[naming.enumArg.name] ?? String(naming.enumArg.default ?? '')
  return said.toUpperCase() === naming.value.toUpperCase()
}

/**
 * The arguments the composer shows a picker for, in the schema's order.
 *
 * Fleet arguments are never among them: the fleet is picked ONCE, at the top of the screen, and it
 * is what `cmd.issue()` is called with. Asking for it twice would be two authorities for the one
 * question "whose order is this?".
 *
 * An enum-revealed argument (`days`) is ALWAYS among them. It used to appear only once the enum
 * had been asked for it, which put PROVISION's day stepper behind a chip — the fold the owner
 * refused: *"in provision, full and days, they does not have to be folded."* Both halves stand
 * open; the guard against a meaningless value moved to where it belongs, the LINE (`orderText`
 * skips a named argument whose enum says something else) and the completeness check below.
 */
export function visibleArgs(spec: VerbSpec): VerbArg[] {
  return spec.args.filter((arg) => arg.type !== 'fleet')
}

/** Required, in the schema's words — the arguments the line cannot be issued without. A named
 *  argument is only missing while its enum is actually asking for it. */
export function missingArgs(spec: VerbSpec, args: Record<string, string>): VerbArg[] {
  return visibleArgs(spec).filter(
    (a) => a.required && !args[a.name] && namedByItsEnum(spec, a, args),
  )
}

export function isComplete(spec: VerbSpec, args: Record<string, string>): boolean {
  return missingArgs(spec, args).length === 0
}

/**
 * THE LINE. What the server will be sent, character for character.
 *
 * @param fleetName the commanding fleet's name, emitted only where rule 1 above allows it. A name
 *        with whitespace in it is left out entirely rather than sent as two tokens — the order is
 *        still aimed correctly, because cmd.issue() carries the fleet's id.
 */
export function orderText(
  spec: VerbSpec,
  args: Record<string, string>,
  fleetName?: string | null,
): string {
  const parts: string[] = [spec.verb]
  const consumed = new Set<VerbArg>()

  for (const arg of spec.args) {
    if (consumed.has(arg)) continue

    if (arg.type === 'fleet') {
      // Rule 1: only a LEADING fleet is parsed, so only a leading fleet is written.
      if (spec.args[0] === arg && fleetName && !/\s/.test(fleetName)) parts.push(fleetName)
      continue
    }

    const value = args[arg.name]
    if (value === undefined || value === '') continue

    // A named argument rides out on its enum's own emission (the `revealed` branch below), and
    // ONLY when the enum is asking for it. With both halves of PROVISION on screen at once, a
    // player can say 30 days and then choose FULL — the 30 stays visible for changing their mind,
    // and this line is what keeps it out of "PROVISION Gaivota FULL 30", which is not a sentence
    // cmd.parse() reads.
    if (!namedByItsEnum(spec, arg, args)) continue

    const revealed = revealedArg(spec, arg, value)
    if (revealed) {
      // "PROVISION Gaivota 30 DAYS" — the number carries the meaning and the word follows it, which
      // is how cmd.parse() reads it and how a person says it.
      const inner = args[revealed.name]
      if (inner === undefined || inner === '') continue
      if (arg.keyword) parts.push(arg.keyword)
      parts.push(inner, value.toUpperCase())
      consumed.add(revealed)
      continue
    }

    if (arg.keyword) parts.push(arg.keyword)
    parts.push(arg.op ? `${arg.op}${value}` : value)
  }

  return parts.join(' ')
}

// ── FIXES (F.5) ────────────────────────────────────────────────────────────────────────────────
//
// A refusal arrives with `fixes`: real orders, e.g. `PROVISION Gaivota FULL`, `SELL <good> ALL`,
// `CLEAR Gaivota`, `(reload and try again)`. Every one of them has to be TAPPABLE, and tapping it
// has to leave the player holding the corrected order — not a string in a box they must edit.
//
// So a fix is read back through the same schema that writes a line. A `<placeholder>` is a hole the
// player must fill: everything before it loads, and the composer opens its picker on the hole.

export type FixAction =
  /** Load this into the composer. Arguments the fix left as `<placeholders>` are simply unset. */
  | { kind: 'compose'; verb: string; args: Record<string, string> }
  /** The fix is a queue control, so tapping it acts on the queue directly. */
  | { kind: 'queue'; verb: 'CANCEL' | 'CLEAR'; index: number | null }
  /** Not an order at all — `(reload and try again)`. Rendered as words, with no button. */
  | { kind: 'none' }

export function fixAction(fix: string, verbs: readonly VerbSpec[]): FixAction {
  const tokens = fix.trim().split(/\s+/).filter(Boolean)
  if (tokens.length === 0) return { kind: 'none' }
  const head = tokens[0].toUpperCase()

  if (head === 'CANCEL' || head === 'CLEAR') {
    const index = tokens.slice(1).map((t) => Number(t)).find((n) => Number.isFinite(n) && n > 0)
    return { kind: 'queue', verb: head, index: index ?? null }
  }

  const spec = findVerb(verbs, head)
  if (!spec) return { kind: 'none' }

  const args: Record<string, string> = {}
  let i = 1
  for (const arg of spec.args) {
    if (i >= tokens.length) break
    if (arg.keyword && tokens[i].toUpperCase() === arg.keyword.toUpperCase()) i += 1
    if (i >= tokens.length) break
    // A placeholder ends the read: `SAIL Gaivota TO <a nearer port>` is three tokens of prose, and
    // guessing at them would put words in the server's mouth.
    if (tokens[i].startsWith('<')) break
    if (arg.type === 'fleet') {
      i += 1
      continue
    }
    args[arg.name] = arg.op ? tokens[i].replace(/^[<>]=?/, '') : tokens[i]
    i += 1
  }
  return { kind: 'compose', verb: spec.verb, args }
}
