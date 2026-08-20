import { Button, Card, Notice, PageHeader, Screen, SectionLabel, Skeleton } from '../components/ui'
import type { LiveWorld } from './worldStore'
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
export function ReadAgain({ world }: { world: LiveWorld }) {
  return (
    <Button
      variant="ghost"
      size="sm"
      busy={world.busy}
      busyLabel="reading…"
      onClick={() => void world.refresh()}
    >
      read again
    </Button>
  )
}
