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

export interface Refusal {
  /** `E_HOLD_FULL`, `E_STALE`, `E_NO_SUCH_PORT`, … or `E_SERVER` / `E_TRANSPORT` for a fault. */
  code: string
  /** A sentence for a player. Never empty. */
  sentence: string
  /** DESIGN F.5's "→ do this instead". May be empty; never null. */
  fixes: string[]
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

/** `E_HOLD_FULL: the fleet has room for 5 tuns` → code and sentence, split once, here. */
const RAISED_RE = /^(E_[A-Z0-9_]+):\s*([\s\S]*)$/

/** A payload the chain returned. `ok:false` in it is a refusal; anything else is the value. */
export function fromPayload<T>(payload: unknown): RpcResult<T> {
  if (payload && typeof payload === 'object' && (payload as { ok?: unknown }).ok === false) {
    const p = payload as {
      error_code?: unknown
      error_message?: unknown
      fixes?: unknown
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
