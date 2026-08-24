import type { ReactNode } from 'react'
import { Icon } from './Icon'
import { useExplainDisclosure, type ExplainDisclosure } from './explainState'

// Design-system EXPLAIN — the tappable ⓘ, and the one place a standing explanation is allowed to
// live. THE RULE THIS FILE ENFORCES: THE SCREEN PRINTS WHAT IS TRUE RIGHT NOW; WHY IT IS TRUE IS
// BEHIND A DOT.
//
// ── THE DEFECT THIS CLOSES ──────────────────────────────────────────────────────────────────────
// Every figure in this game came with a permanent paragraph defending it. Measured at 390x844,
// full page, before this file existed:
//
//   PORT     713 words        MARKET   766 words        FLEETS   235 words
//
// and the top of PORT was three numbers wearing seventy words of footnote:
//
//   Market tax  3.0%
//               set by the Mayor, banded 0-8%. Tax relief is not in the V0 chain, so what you
//               pay is what is printed.
//   Spread      2.6%
//               half-spread, derived from commerce — the server's figure, not a client formula
//
// The prose is CORRECT and worth keeping — it is what makes the game legible the first time you
// meet it. It is worthless on the two-hundredth reading, and by then it is what stands between the
// player and the number. A rule you have already learnt is noise.
//
// So: the explanation is not deleted and is not moved to a manual. It is FOLDED. The value keeps
// its line; the reason moves behind an ⓘ the player can tap the day they want it.
//
// ── WHERE THE LINE IS AGAINST Collapsible ───────────────────────────────────────────────────────
// Collapsible.tsx is the app's ONE section fold: a full-width header button that folds a REGION of
// the screen (a roster, a queue, a manifest) and remembers the choice. It is the right tool when
// the thing being folded is CONTENT.
//
//   Collapsible — folds content the player came for. Full-width header, persisted, open by default.
//   Explain     — folds the standing explanation OF content. An inline dot, ephemeral, always
//                 closed by default. Never hides a live figure, a refusal, or a tap affordance.
//
// A fold that is open by default is not a fold, so Explain never persists and never starts open:
// the whole point is that the default screen is quiet.
//
// ── WHAT MAY NOT GO BEHIND THE DOT ──────────────────────────────────────────────────────────────
// Live data (a count, a price, an ETA), a refusal and its fixes, and any hint that discloses an
// affordance the player cannot otherwise find (TABLE_SCROLL_HINT). Hiding those is hiding the
// game. The dot takes standing prose — rules, provenance, units, "why this column is not here" —
// and nothing else.
//
// ONE AMENDMENT, from the owner's concise-and-graphic law (2026-08-24): the rule protects the
// REFUSAL, not its prose. When the server serves the refusal's FIGURES and RefusalNote draws them
// as the bar and the numbers, the refusal is still fully in the open — and its sentence becomes
// standing explanation OF it, which is exactly what this dot is for. With no served figures the
// sentence stays visible, because then it is the refusal.

/**
 * The ⓘ. An inline, real <button> — so Enter/Space work and it lands in the tab order.
 *
 * ── IT DRAWS AT 28px AND IS TAPPED AT 44px ─────────────────────────────────────────────────────
 * navTabs.ts sets this app's floor: "40px each, under the 44px touch floor". A dot big enough to
 * clear that floor VISUALLY would be a blot beside a 13px figure — it would shout louder than the
 * number it annotates, and there are eleven of them on PORT alone.
 *
 * So the two sizes are separated. The circle is 28×28 (`h-7 w-7`) and the HIT AREA is an invisible
 * `::before` inflated 8px on every side — 28 + 8 + 8 = 44 — which is part of the button and
 * forwards its taps to it. `-my-1.5` keeps the drawn circle from pushing a line of text taller,
 * and the halo, having no layout box at all, never does.
 *
 * The halo overlaps ~8px of whatever sits beside the dot, so a dot may not be placed immediately
 * against another control; in this app its neighbour is always static text.
 *
 * `z-20` IS PART OF THE TARGET, not decoration. The halo is transparent and has no layout box, so
 * an ordinary neighbour painted after it wins the hit test over its own tap area — measured on
 * FLEETS, where a sticky table header (`z-10`, tableLayout.ts) took the bottom half of the Ships
 * dot and left a 44x22 target. One step above that sticky layer puts the whole 44x44 back.
 *
 * Never render it inside another button — a nested button is invalid HTML, which is why every
 * header carrying one is a plain heading rather than a Collapsible.
 */
export function ExplainDot({
  open,
  panelId,
  onToggle,
  label = 'this',
  className = '',
}: ExplainDisclosure & {
  /** Names the thing being explained, for screen readers: "Explain: Market tax". */
  label?: string
  className?: string
}) {
  return (
    <button
      type="button"
      onClick={onToggle}
      aria-expanded={open}
      aria-controls={panelId}
      aria-label={`Explain: ${label}`}
      title={`Explain: ${label}`}
      className={`relative z-20 -my-1.5 inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-full align-middle transition-colors before:absolute before:-inset-2 before:content-[''] ${
        open ? 'bg-accent-soft text-accent' : 'text-ink-faint hover:text-accent active:text-accent'
      } ${className}`}
    >
      <Icon name="info" size={15} />
    </button>
  )
}

/**
 * The revealed prose. Unmounts while closed — the same contract Collapsible keeps, so a screen
 * reader is never handed text the sighted player cannot see, and so a measurement of the default
 * screen measures the QUIET screen.
 *
 * Marked with a rule down its left edge: the panel is an aside about the line above it, and the
 * rule is what says so without spending a word on it.
 *
 * `font-sans` IS EXPLICIT, not inherited: index.css's house rule is that mono is for figures and
 * sans is for prose, and a panel opened from inside a mono value cell (DetailRow with `mono`, a
 * table footnote) would otherwise render its sentences in JetBrains Mono.
 *
 * A `<span class="block">` AND NOT A `<div>`, deliberately. The panel opens wherever its dot is —
 * inside a <p> ("Bound for Cádiz at 4.9 kn ⓘ"), inside an <h3> section label, inside a <dd>. A
 * <div> is flow content and is invalid in the first two; React says so out loud ("<div> cannot be
 * a descendant of <p>") and the browser silently reparents it, which breaks the layout it was
 * measured in. A span is phrasing content and is valid in all of them, and `block` gives it the
 * box it needs. This is the same move CollapsibleCard makes inside its header button.
 */
export function ExplainPanel({
  open,
  panelId,
  children,
  className = '',
}: Omit<ExplainDisclosure, 'onToggle'> & { children: ReactNode; className?: string }) {
  if (!open) return null
  return (
    <span
      id={panelId}
      className={`mt-1 block border-l border-accent/30 pl-2.5 font-sans text-xs leading-relaxed text-ink-faint ${className}`}
    >
      {children}
    </span>
  )
}

/**
 * Dot + panel, wired, for the common case: a value cell or the end of a card body, where the dot
 * may sit inline and the panel may flow as a block directly beneath it.
 *
 * Returns a FRAGMENT, so it inherits the parent's flow — in a `<dd>` the dot trails the value and
 * the panel drops below it; in a flex column it becomes two items. Where the dot and the panel
 * must live in DIFFERENT boxes (a title row and the block under it — PageHeader, CardHeader),
 * compose `useExplainDisclosure` + `ExplainDot` + `ExplainPanel` yourself instead.
 */
export function Explain({
  children,
  label,
  dotClassName = '',
  panelClassName = '',
}: {
  children: ReactNode
  label?: string
  dotClassName?: string
  panelClassName?: string
}) {
  const disclosure = useExplainDisclosure()
  return (
    <>
      <ExplainDot {...disclosure} label={label} className={dotClassName} />
      <ExplainPanel {...disclosure} className={panelClassName}>
        {children}
      </ExplainPanel>
    </>
  )
}
