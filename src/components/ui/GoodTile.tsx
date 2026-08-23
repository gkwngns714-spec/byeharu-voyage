import type { ReactNode } from 'react'
import { Icon } from './Icon'
import { goodIcon } from './goodIcons'
import { RarityMark } from './Rarity'
import { fineClass } from './typography'

// THE GOOD TILE — one trade good as a BLOCK, not a sentence.
//
// The owner, 2026-08-23: "make trade goods in blocks as well, not all alligned in sentences —
// horizontally." The row form read name · category · index · price strung across one line; this is
// the same served facts as a tile a thumb can land on: the good's own drawn mark and its name as
// the title, its rarity mark in the corner, and the figures aligned beneath, so a wall of goods
// scans as a field rather than reading as a column of sentences.
//
// ── WHERE IT LIVES, DECIDED BEFORE THE SECOND CALLER (docs/NO_SPAGHETTI.md §7B) ────────────────
// This is the design system's tile, not MARKET's. MARKET's goods panel and the COMPENDIUM's goods
// face both compose it today; the good picker on COMMAND (features/command/ArgPickers.tsx) is the
// named next caller — when that row converts, it imports THIS and passes its own figures. What a
// tile SHOWS is the caller's business (children); what a tile IS — the header of icon + name +
// rarity, the block chrome, the 44px floor — is spelt here and only here.
//
// ── WHAT IT REFUSES TO DO ──────────────────────────────────────────────────────────────────────
//   · It never truncates the name. `São Vicente` must not become `São Vice…` — the name wraps and
//     the tile grows, which the grid absorbs.
//   · It computes nothing. Every figure inside it arrives composed by the caller, already the
//     server's (worldStore.ts rule 3). The tile is chrome.
//   · It does not decide the grid. `goodTileGridClass()` is the one spelling of the field the
//     tiles sit in — two columns at 390px (measured: three crushes the figures), more as the
//     glass widens.

export function GoodTile({
  code,
  category,
  name,
  rarity,
  muted = false,
  onTap,
  tapTitle,
  children,
  testId,
}: {
  /** The good's CODE (`black-pepper`) — what `goodIcon` keys the drawn mark from. */
  code: string
  /** The served category, the icon table's fallback for a good landed undrawn. */
  category: string
  name: string
  /** The SERVED rarity tier (0032), rendered by the one mark. Absent renders nothing. */
  rarity: string | null | undefined
  /** A good the port will not trade: struck through, dimmed, and NOT tappable — there is no
   *  order to hand over, so there is no button to press. */
  muted?: boolean
  /** Makes the WHOLE tile the tap target (≥44px by construction). Omitted = a plain block. */
  onTap?: () => void
  /** The pointer's sentence for the tap — never printed, so the tile stays a block of figures. */
  tapTitle?: string
  /** The figures, aligned beneath the title. Composed by the caller; every one the server's. */
  children?: ReactNode
  testId?: string
}) {
  const head = (
    <span className="flex w-full items-start gap-1.5">
      <Icon name={goodIcon(code, category)} size={18} className="mt-0.5 shrink-0 text-ink-muted" />
      <span
        className={
          muted
            ? 'min-w-0 text-sm text-ink-faint line-through'
            : 'min-w-0 text-sm font-medium text-ink'
        }
      >
        {name}
      </span>
      <RarityMark rarity={rarity} size={11} className="ml-auto mt-1 shrink-0" />
    </span>
  )

  const body = children && <span className="flex w-full flex-col gap-1">{children}</span>

  if (muted || !onTap) {
    return (
      <div
        data-testid={testId}
        className="bv-cut flex min-h-11 flex-col gap-1.5 border border-edge/60 bg-surface p-2.5"
      >
        {head}
        {body}
      </div>
    )
  }

  return (
    <button
      type="button"
      onClick={onTap}
      title={tapTitle}
      data-testid={testId}
      className="bv-cut flex min-h-11 flex-col gap-1.5 border border-edge bg-surface-2 p-2.5 text-left transition hover:border-accent/60"
    >
      {head}
      {body}
    </button>
  )
}

/** One aligned figure line inside a tile: a small dim label, the value pushed to the far edge.
 *  The label is a NAME, never a sentence (the owner's label law); the value is the hero
 *  (docs/UI_DIRECTION.md §4 rule 2). One spelling here so MARKET's tiles and the COMPENDIUM's
 *  cannot drift apart line by line. */
export function GoodTileLine({ label, children }: { label: string; children: ReactNode }) {
  return (
    <span className="flex w-full items-center justify-between gap-2">
      {/* The fine-print voice (typography.ts), uppercased — not a re-spelling of it. */}
      <span className={fineClass('shrink-0 uppercase tracking-wider')}>{label}</span>
      <span className="flex min-w-0 items-center justify-end gap-1 text-right font-mono text-xs text-ink">
        {children}
      </span>
    </span>
  )
}
