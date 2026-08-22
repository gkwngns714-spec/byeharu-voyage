import type { ReactNode } from 'react'
import { Button, Collapsible, Icon, OverlayPanel, type OverlaySlot } from '../../components/ui'
import { CHART_CHROME } from './useChartSurface'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A CORNER PANEL — the map's ONE panel shape, and there are only ever two of them on screen.
//
// THE OWNER'S STANDING MAP RULES, and DESIGN §E.5's "two panels, both in corners, both foldable to
// a chevron": panels live in the CORNERS, never the centre; everything folds; everything the
// player did not ask for can be dismissed; minimal words; no jargon.
//
// THE REACH LAW (docs/CORE_REUSE.md §1.5 — "an action may never live inside a region that can
// scroll or clip it") is why this component is shaped the way it is:
//   · The header row — the fold toggle and the dismiss — is NEVER capped and NEVER scrolls. It is
//     outside the content region entirely.
//   · Only the CONTENT may scroll, and it is information. A caller passes a scroll cap on the body
//     and cannot pass one that could clip the header.
//   · Both controls are 44 px targets.
// byeharu shipped a button with 8 of its 44 pixels on screen because a rail was capped at the call
// site. This panel has no call site that can do that.
//
// It composes the design system rather than re-implementing it: OverlayPanel for the corner chrome
// and Collapsible for the fold. The map does not own a second disclosure.
//
// ── A CORNER IS A SLOT, NOT A STRING (2026-08-22) ──────────────────────────────────────────────
// This took a free-text `positionClassName` and each caller invented its own: `left-3 top-3` here,
// `bottom-11 right-3` there — the `11` a hand-tuned guess at how tall the caption bar in MapScreen
// happens to be, tuned separately from the `bottom-9` a second element used to clear the SAME bar.
// The design system already had exactly four corners (`overlayLayout.ts:OVERLAY_SLOTS`) and none
// of them were being used. The prop is now that `slot`, and the caption's band is reserved ONCE,
// by the chrome layer in MapScreen, so no panel here knows the caption exists.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export function MapPanel({
  slot,
  title,
  aside,
  onDismiss,
  storageKey,
  defaultOpen = true,
  bodyClassName = '',
  widthClassName,
  compact = false,
  testId,
  children,
}: {
  /** WHICH CORNER — the caller's ONE positioning decision, and it may only be one of the four the
   *  design system names. It resolves through `overlayLayout.ts`, the same table every other piece
   *  of chart chrome reads, so no caller can invent a fifth corner or a hand-tuned inset. */
  slot: OverlaySlot
  title: ReactNode
  /** A count or a status, printed at the right of the header. Never interactive (it sits inside
   *  the fold button, and a button inside a button is invalid). */
  aside?: ReactNode
  /** Present = the panel can be sent away entirely, not just folded. */
  onDismiss?: () => void
  storageKey?: string
  defaultOpen?: boolean
  bodyClassName?: string
  widthClassName?: string
  /** Phone-sized surface: the panel shrinks to its content instead of holding a fixed column, so
   *  a corner panel stays a corner panel. See COMPACT_WIDTH_PX. */
  compact?: boolean
  testId?: string
  children: ReactNode
}) {
  return (
    <OverlayPanel
      inert={false}
      // THE CORNER COMES FROM THE SLOT, not from this file: `OverlayPanel` already turns a slot
      // into `absolute z-10 <anchor>`, and it did so the whole time this component was overriding
      // it with a string. All that is left to say here is how wide the panel is.
      slot={slot}
      // CHART CHROME: inside the chart's box, but not the chart. Every gesture handler on the
      // surface skips anything under this marker, so pressing a panel can never pan or select.
      {...CHART_CHROME}
      className={widthClassName ?? (compact ? 'w-auto min-w-28 max-w-[55vw]' : 'w-48 max-w-[45vw]')}
      data-testid={testId}
    >
      {/* `relative` + an absolutely-placed dismiss keeps the two controls as SIBLINGS (no nested
          button) while they still read as one header row. */}
      <div className="relative">
        <Collapsible
          defaultOpen={defaultOpen}
          storageKey={storageKey}
          data-testid={testId ? `${testId}-fold` : undefined}
          headerClassName={onDismiss ? 'pr-11' : ''}
          contentClassName={`mt-1 ${bodyClassName}`}
          chevronSize={14}
          header={
            <span className="flex min-w-0 flex-1 items-baseline justify-between gap-2">
              <span className="truncate font-mono text-[10px] uppercase tracking-wider text-ink-faint">
                {title}
              </span>
              {aside && <span className="shrink-0 font-mono text-[10px] text-ink-faint">{aside}</span>}
            </span>
          }
        >
          {children}
        </Collapsible>

        {onDismiss && (
          <Button
            variant="ghost"
            size="icon"
            aria-label="Close"
            onClick={onDismiss}
            className="absolute right-0 top-0 -mr-1 -mt-1"
            data-testid={testId ? `${testId}-close` : undefined}
          >
            <Icon name="close" size={14} />
          </Button>
        )}
      </div>
    </OverlayPanel>
  )
}
