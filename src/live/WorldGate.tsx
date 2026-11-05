import { Card, Hint, Note, PageSplit, Row, Sheet, Skeleton } from '../components/ui'
import type { Refusal } from '../lib/rpc'
import { useT } from '../lib/i18n'

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
export function WorldFailed({ title, refusal }: { title: string; refusal: Refusal | null }) {
  const t = useT()
  return (
    // A DOOR IS A PAGE (2026-11-05, owner row 267): the tab behind it is a `Sheet layout="page"`, so the door stands on the SAME grid
    // — MAIN | SIDE from 1,024, one column below — and nothing jumps when the world arrives. tests/gates.design.spec.ts holds it.
    <Sheet title={title} layout="page">
      <PageSplit
        main={
          <Card data-testid="gate-failed">
            {/* THE ONE NOTE: the sentence a player is owed. The code goes to console.debug (Note's own
                rule), never to the screen — §2 item 13, a code is for a log. */}
            <Note tone="danger" code={refusal?.code ?? 'E_UNKNOWN'}>
              {refusal?.sentence ?? t('port.noLoad')}
            </Note>
            {refusal && refusal.fixes.length > 0 && (
              <div className="mt-4">
                <h2 className="text-t-body font-semibold text-ink">{t('port.try')}</h2>
                {refusal.fixes.map((fix, i) => (
                  <Row key={fix} label={fix} hairline={i < refusal.fixes.length - 1} />
                ))}
              </div>
            )}
          </Card>
        }
        side={
          // THE DETAIL IS A DEVELOPER'S NOTE, one tap away rather than on the screen: a PL/pgSQL line
          // number on the one screen that appears when the game is already broken reads as the game
          // being MORE broken — and a bug report with it is worth ten without.
          <Card data-testid="gate-detail">
            <Hint more={refusal?.detail ? <span className="font-mono break-words">{refusal.detail}</span> : undefined} moreTitle={t('port.serverSaid')}>
              {t('port.nothingLost')}
            </Hint>
          </Card>
        }
      />
    </Sheet>
  )
}

/** The world is opening. Rows where the rows will be — never an endless spinner, and no chrome
 *  the screen itself does not draw: it was an eyebrow, a subtitle and three bordered cards, the
 *  §2 item 15 / §4.3 chrome the redesign deleted everywhere else, flashing on every cold load. */
const skeletonRow = (i: number) => (
  <div key={i} className="flex min-h-row items-center justify-between gap-3">
    <Skeleton className="h-4 w-40" />
    <Skeleton className="h-4 w-16" />
  </div>
)

export function WorldLoading({ title, rows = 6 }: { title: string; rows?: number }) {
  const t = useT()
  return (
    <Sheet title={title} layout="page">
      <p className="sr-only" role="status">
        {t('port.opening')}
      </p>
      <PageSplit
        main={<Card data-testid="gate-loading">{Array.from({ length: rows }, (_, i) => skeletonRow(i))}</Card>}
        side={<Card data-testid="gate-loading-side">{Array.from({ length: 3 }, (_, i) => skeletonRow(i))}</Card>}
      />
    </Sheet>
  )
}
