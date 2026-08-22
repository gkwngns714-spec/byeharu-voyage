import { Button, Card, Notice, PageHeader, Screen, SectionLabel, Skeleton } from '../components/ui'
import { useWorld } from './worldStore'
import type { Refusal } from '../lib/rpc'

// THE TWO NON-READY STATES OF A SCREEN, written once.
//
// Every tab that reads the live world has exactly three renderings: the world is opening, the
// world refused to open, or the world is here. The third one is the screen itself; the other two
// are the same two renderings on every tab, so they live here rather than three times over.
//
// TWO RULES, both from src/lib/db/README.md §1:
//
//   1. A FAILURE IS RENDERED, NEVER SPUN ON. "A spinner that keeps spinning is what a swallowed
//      exception looks like." `phase === 'failed'` gets the refusal's code, its sentence and its
//      fixes on screen — a refusal is DATA (DESIGN F.5), and the player is owed the sentence.
//   2. WHILE IT OPENS, the design system's own Skeleton stands in. Not a spinner, not an empty
//      page that pops: blocks the size of the thing that is coming.
//
// PLACEMENT NOTE, stated plainly rather than left to be discovered: this belongs beside the store
// it gates (`src/live/`), not under `features/fleets/`. It is here because this slice's file
// domain is the three screens; moving it is a one-line import change for whoever owns `src/live/`.

/** The world could not be opened. Show what the chain said, in the chain's own words. */
export function WorldFailed({
  eyebrow,
  title,
  refusal,
}: {
  eyebrow: string
  title: string
  refusal: Refusal | null
}) {
  return (
    <Screen>
      <PageHeader eyebrow={eyebrow} title={title} subtitle="The world did not open." />
      <Card tone="danger">
        <Notice tone="danger">
          <span className="font-mono text-xs uppercase tracking-wider">
            {refusal?.code ?? 'E_UNKNOWN'}
          </span>
          <span className="mt-1 block">
            {refusal?.sentence ?? 'The world did not open, and did not say why.'}
          </span>
        </Notice>
        {refusal && refusal.fixes.length > 0 && (
          <div className="mt-3">
            <SectionLabel>Try</SectionLabel>
            <ul className="space-y-1">
              {refusal.fixes.map((fix) => (
                <li key={fix} className="font-mono text-xs text-ink-muted">
                  → {fix}
                </li>
              ))}
            </ul>
          </div>
        )}
        {refusal?.detail && (
          <p className="mt-3 font-mono text-[11px] text-ink-faint">{refusal.detail}</p>
        )}
        <p className="mt-3 text-sm text-ink-muted">
          Nothing was lost: the world is a database in this tab, and it is still on disk. Reload to
          open it again.
        </p>
      </Card>
    </Screen>
  )
}

/** The world is opening. Blocks where the panels will be — never an endless spinner. */
export function WorldLoading({
  eyebrow,
  title,
  subtitle,
  panels = 2,
}: {
  eyebrow: string
  title: string
  subtitle?: string
  /** How many card-shaped blocks to stand in for. */
  panels?: number
}) {
  return (
    <Screen>
      <PageHeader eyebrow={eyebrow} title={title} subtitle={subtitle} />
      <p className="sr-only" role="status">
        Opening the world.
      </p>
      {Array.from({ length: panels }, (_, i) => (
        <Card key={i}>
          <Skeleton className="h-4 w-40" />
          <Skeleton className="mt-3 h-3 w-full" />
          <Skeleton className="mt-2 h-3 w-5/6" />
          <Skeleton className="mt-2 h-3 w-2/3" />
        </Card>
      ))}
    </Screen>
  )
}

/**
 * THE CLOCK, as a control.
 *
 * `world.fleets()` settles every voyage server-side before it answers, so re-reading is not a
 * refresh in the web sense — it is the only way time passes for the player (README §1, "a read is
 * the catch-up"). One affordance, defined once, so two tabs cannot grow two different words for it.
 *
 * It lives in a PageHeader's action slot deliberately: the reach law forbids putting an action
 * inside a scrolling or height-capped region, and every screen body here is one.
 */
export function ReadAgain({
  read,
  busy,
}: {
  /** What "read again" MEANS on this screen. Defaults to `world.refresh()` — fleets, ledger and
   *  house — which is right for every tab whose subject is the world.
   *
   *  MARKET is the exception that forced this prop, and it is worth stating plainly: its subject is
   *  ONE PORT'S PRICES, fetched by `loadMarket(portId)`. Composing the default there would have put
   *  a button on the prices screen that re-reads everything EXCEPT the prices — so Market carried a
   *  fifth hand-written copy of this control instead. A prop is cheaper than a fifth copy. */
  read?: () => void | Promise<void>
  /** Overrides the store's `busy` when a screen's own read has its own in-flight flag. */
  busy?: boolean
} = {}) {
  // IT TAKES NO `world` ANY MORE. Every caller passed the whole store object in just so this could
  // read two fields off it, which meant a screen using fine-grained selectors (MARKET) had nothing
  // to hand over without subscribing to everything. This component lives in src/live, beside the
  // store, so it simply selects what it needs — and selects PRIMITIVES, not an object, because
  // zustand compares with Object.is and a fresh `{busy, refresh}` would re-render on every write.
  const storeBusy = useWorld((s) => s.busy)
  const refresh = useWorld((s) => s.refresh)
  return (
    <Button
      variant="ghost"
      // `md`, NOT `sm`. This was `size="sm"` on five tabs, and buttonStyles.ts says in as many words
      // that `sm` is the one size that does NOT clear the 44px touch floor — it is for in-row
      // secondary actions. The one control that makes time pass in this game is not that.
      size="md"
      busy={busy ?? storeBusy}
      busyLabel="reading…"
      onClick={() => void (read ? read() : refresh())}
    >
      read again
    </Button>
  )
}
