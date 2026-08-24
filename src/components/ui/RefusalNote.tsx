import type { ReactNode } from 'react'
import type { Refusal } from '../../lib/rpc'
import { Badge } from './Badge'
import { Explain } from './Explain'
import { Meter } from './Meter'

// Design-system REFUSAL — the one concise rendering of "the server said no".
//
// THE OWNER'S LAW (2026-08-24, on E_ENDURANCE's four-clause paragraph): *"too long. make it very
// concise. This concise concept will have to be applied to all aspects of the game. Always show in
// graphics, concisely."* A refusal is two numbers and a verb wearing a paragraph; the player needs
//
//     ▁▁▁▂  2.9 / 33 days     [ PROVISION ]
//
// — a bar, the figures, the fix. This component is where that shape lives, ONCE, so the map's
// send flow, the composer's check and every refusal to come cannot drift into three renderings.
//
// ── WHERE THE NUMBERS COME FROM, AND WHERE THEY NEVER COME FROM ────────────────────────────────
// `refusal.figures` — SERVED beside the sentence by the refusing migration (lib/rpc/result.ts).
// The sentence is the server's prose and is NEVER parsed for numbers: a client that regexes
// "2.9" out of a paragraph is a second author of the refusal, one wording change from lying.
// Until the serving migration lands, `figures` is absent everywhere and this renders the
// FALLBACK: code badge and the sentence, compact — the same forward contract `spec.note ??
// spec.help` used while 0021 rolled out.
//
// ── THE EXPLAIN BOUNDARY, AMENDED WITH THE LAW ─────────────────────────────────────────────────
// Explain.tsx rules that a refusal may not go behind the dot, because hiding the refusal is
// hiding the game. That rule is about the REFUSAL, not about its prose: when the served figures
// stand in the sentence's place, the refusal is still fully visible — as the bar and the numbers
// — and the sentence becomes standing explanation OF it, which is exactly what the dot is for.
// With no figures, the sentence is the only carrier and stays in the open.
//
// ── WHAT THE CALLER SUPPLIES ───────────────────────────────────────────────────────────────────
// `children` are the fix ACTIONS (buttons), built by the caller from `refusal.fixes` through
// domain/order's `fixAction` — the design system draws chrome and cannot import a domain rule.
// A caller with nowhere to send a fix passes none, and the note is complete without them.

export function RefusalNote({
  refusal,
  children,
  testId,
}: {
  refusal: Refusal
  /** The fixes, as the caller's own buttons. Optional — the note stands without them. */
  children?: ReactNode
  testId?: string
}) {
  const f = refusal.figures
  return (
    <div className="space-y-1.5" data-testid={testId}>
      {f ? (
        // THE GRAPHIC FACE: the bar is have-over-need, danger-toned because this is a refusal;
        // the two figures are the hero and the unit rides small beside them (UI_DIRECTION §4
        // rule 2). No code badge here — E_ENDURANCE is schema, and the player never reads the
        // schema; the code and the server's sentence are behind the dot for whoever wants them.
        <div className="flex items-center gap-2">
          <Meter
            pct={f.need > 0 ? (f.have / f.need) * 100 : 0}
            tone="danger"
            className="min-w-0 flex-1"
          />
          <span className="shrink-0 font-mono text-sm tabular-nums text-ink">
            {trim(f.have)} / {trim(f.need)}
            <span className="ml-1 text-[10px] text-ink-faint">{f.unit}</span>
          </span>
          <Explain label={refusal.code} panelClassName="w-full">
            {refusal.code} — {refusal.sentence}
          </Explain>
        </div>
      ) : (
        // THE FALLBACK: no served figures yet, so the sentence is the only honest carrier of the
        // reason and it stays visible — compact, never a paragraph of chrome around it.
        <div className="space-y-1">
          <span className="flex flex-wrap items-center gap-2">
            <Badge tone="danger">{refusal.code}</Badge>
            {refusal.source === 'fault' && <Badge tone="warning">fault</Badge>}
          </span>
          <p className="text-xs leading-snug text-ink">{refusal.sentence}</p>
        </div>
      )}
      {children}
    </div>
  )
}

/** 2.9 stays 2.9; 33.0 prints 33 — the owner's own spelling ("2.9 / 33 days"). */
function trim(n: number): string {
  return String(Number(n.toFixed(1)))
}
