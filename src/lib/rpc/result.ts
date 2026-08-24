// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A REFUSAL IS DATA — the one shape both backends produce, for every way a call can not succeed
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// DESIGN §F.5: the game never answers with a bare code. Every refusal carries a CODE the client
// can branch on, a SENTENCE a player can read, and FIXES — "→ do this instead". The chain builds
// all three (`cmd.fixes()`), and this file's whole job is to get them across the boundary intact,
// whichever boundary it is.
//
// So: no exceptions for game outcomes. `cmd.issue()` returning `ok:false, E_HOLD_FULL` is a
// legitimate answer from a working server, not a fault; throwing it would make every caller wrap
// every call in try/catch and would tempt someone to `String(err)` the sentence back out of a
// stack trace. Faults become the same shape as refusals so that a screen has ONE thing to render
// and cannot forget the other one.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import type { ParsedCommand, QueuedOrder } from './types'

/**
 * THE FIGURES BEHIND AN ARITHMETIC REFUSAL — what the owner's concise law (2026-08-24: *"make it
 * very concise … Always show in graphics"*) needs to draw `▁▁▂ 2.9 / 33 days` instead of the
 * paragraph. SERVED, beside the sentence, by the refusing migration itself; the client NEVER
 * parses a sentence for numbers — a sentence is the server's prose, not a wire format.
 *
 * SERVED SINCE MIGRATION 0050 (2026-08-25): `voyage.sail_refusal` returns the whole refusal as one
 * value, `cmd.refuse` raises it with the figures in PG_EXCEPTION_DETAIL, and `cmd.execute_order` /
 * `cmd.preview` / `cmd.issue` / `cmd.queue` carry them across as `figures`. Still OPTIONAL, and
 * that is not laziness: a refusal with no arithmetic behind it (E_NO_STOCK, E_NOT_DOCKED,
 * E_NO_YARD …) has no two numbers to draw, and every renderer falls back to the sentence.
 */
export interface RefusalFigures {
  /** What she has — 2.9 (days of stores), 40 (tuns free), … */
  have: number
  /** What the order needs, same unit. */
  need: number
  /** The unit both figures are in: `days`, `t`, `ducats`, `crew`. A NAME, not a sentence. */
  unit: string
}

export interface Refusal {
  /** `E_HOLD_FULL`, `E_STALE`, `E_NO_SUCH_PORT`, … or `E_SERVER` / `E_TRANSPORT` for a fault. */
  code: string
  /** A sentence for a player. Never empty. */
  sentence: string
  /** DESIGN F.5's "→ do this instead". May be empty; never null. */
  fixes: string[]
  /** The served numbers behind the sentence, when the refusal is arithmetic. See RefusalFigures. */
  figures?: RefusalFigures
  /**
   * `server`    — the chain refused, in the words the chain chose.
   * `raised`    — the chain raised an exception carrying `E_CODE: sentence` (the parser's codes).
   * `fault`     — Postgres or the transport failed. Not a game outcome; show it as a fault.
   */
  source: 'server' | 'raised' | 'fault'
  /** SQLSTATE, HTTP status or whatever else the layer below named the failure. */
  detail?: string
  /** Present on refusals from cmd.*: the queue as it stands after the refusal. */
  queue?: QueuedOrder[]
  parsed?: ParsedCommand
}

export type RpcResult<T> = { ok: true; value: T } | { ok: false; refusal: Refusal }

export function ok<T>(value: T): RpcResult<T> {
  return { ok: true, value }
}

export function refused<T>(refusal: Refusal): RpcResult<T> {
  return { ok: false, refusal }
}

/** The served `figures` object, or undefined for anything that is not exactly its shape — a
 *  malformed payload degrades to the sentence, never to a NaN drawn as a bar. */
function readFigures(raw: unknown): RefusalFigures | undefined {
  if (!raw || typeof raw !== 'object') return undefined
  const f = raw as { have?: unknown; need?: unknown; unit?: unknown }
  if (typeof f.have !== 'number' || !Number.isFinite(f.have)) return undefined
  if (typeof f.need !== 'number' || !Number.isFinite(f.need)) return undefined
  if (typeof f.unit !== 'string' || f.unit === '') return undefined
  return { have: f.have, need: f.need, unit: f.unit }
}

/**
 * The same figures when they arrive on an EXCEPTION rather than in a payload. The chain's one
 * raiser (`cmd.refuse`, migration 0050) puts them in `DETAIL`, which PostgREST and PGlite both
 * hand over as `details` — structured data the server wrote, never prose. A `details` that is
 * anything else (a real PostgreSQL "Key (id)=(…) already exists") fails the shape check and the
 * refusal degrades to its sentence, which is the same forward contract the payload path uses.
 *
 * THIS IS NOT PARSING A SENTENCE. `message` is never touched here.
 */
function readRawFigures(details: unknown): RefusalFigures | undefined {
  if (typeof details !== 'string' || details === '' || details[0] !== '{') return undefined
  try {
    return readFigures(JSON.parse(details))
  } catch {
    return undefined
  }
}

/** `E_HOLD_FULL: the fleet has room for 5 tuns` → code and sentence, split once, here. */
const RAISED_RE = /^(E_[A-Z0-9_]+):\s*([\s\S]*)$/

/** A payload the chain returned. `ok:false` in it is a refusal; anything else is the value. */
export function fromPayload<T>(payload: unknown): RpcResult<T> {
  if (payload && typeof payload === 'object' && (payload as { ok?: unknown }).ok === false) {
    const p = payload as {
      error_code?: unknown
      error_message?: unknown
      fixes?: unknown
      figures?: unknown
      queue?: unknown
      parsed?: unknown
    }
    return refused({
      code: typeof p.error_code === 'string' && p.error_code ? p.error_code : 'E_REFUSED',
      sentence:
        typeof p.error_message === 'string' && p.error_message
          ? p.error_message
          : 'The server refused that, without saying why.',
      fixes: Array.isArray(p.fixes) ? p.fixes.filter((f): f is string => typeof f === 'string') : [],
      figures: readFigures(p.figures),
      source: 'server',
      queue: Array.isArray(p.queue) ? (p.queue as QueuedOrder[]) : undefined,
      parsed: (p.parsed as ParsedCommand | undefined) ?? undefined,
    })
  }
  return ok(payload as T)
}

/**
 * Anything thrown, in either backend, as the same shape.
 *
 * A `raise exception 'E_AMBIGUOUS: "s" could be Safi, Sevilla'` from the parser is a REFUSAL that
 * happens to travel as an exception — cmd.issue()/preview() catch those themselves, but a direct
 * call to a resolver does not, and neither does a cloud round trip. It is recognised by its shape
 * so that the same words reach the player either way.
 */
export function fromError(err: unknown): Refusal {
  const e = (err ?? {}) as {
    message?: unknown
    code?: unknown
    details?: unknown
    hint?: unknown
    status?: unknown
    name?: unknown
  }
  const raw = typeof e.message === 'string' && e.message ? e.message : String(err)
  const detailParts = [
    typeof e.code === 'string' ? `sqlstate ${e.code}` : null,
    typeof e.status === 'number' ? `http ${e.status}` : null,
    typeof e.details === 'string' && e.details ? e.details : null,
    typeof e.hint === 'string' && e.hint ? e.hint : null,
  ].filter(Boolean) as string[]

  const m = RAISED_RE.exec(raw)
  if (m) {
    return {
      code: m[1],
      sentence: m[2].trim() || raw,
      fixes: [],
      figures: readRawFigures(e.details),
      source: 'raised',
      detail: detailParts.join('; ') || undefined,
    }
  }

  return {
    code: faultCode(e),
    sentence: raw,
    fixes: [],
    source: 'fault',
    detail: detailParts.join('; ') || undefined,
  }
}

function faultCode(e: { code?: unknown; name?: unknown }): string {
  if (typeof e.code === 'string') {
    if (e.code === '42501') return 'E_FORBIDDEN'
    if (e.code === '42883' || e.code === 'PGRST202') return 'E_NO_SUCH_RPC'
    if (e.code.startsWith('23')) return 'E_CONSTRAINT'
  }
  if (e.name === 'TypeError' || e.name === 'AbortError') return 'E_TRANSPORT'
  return 'E_SERVER'
}

/** For a spec or a caller that has already proved the call succeeds. Throws with the sentence. */
export function expectOk<T>(result: RpcResult<T>): T {
  if (result.ok) return result.value
  const { code, sentence, fixes } = result.refusal
  throw new Error(`${code}: ${sentence}${fixes.length ? ` (try: ${fixes.join(' | ')})` : ''}`)
}
