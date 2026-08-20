import { useSyncExternalStore, useState } from 'react'
import { Button, Card, SectionLabel } from '../components/ui'
import { bootChannel } from '../lib/db/bootState'
import { RESCUE_KEY, forgetRescue } from '../lib/db/rescue'

// THE ONE PLACE THE GAME ADMITS IT RESET THE WORLD.
//
// ── WHY IT EXISTS (2026-08-20) ─────────────────────────────────────────────────────────────────
// The owner bought cargo, watched the purse go down, came back later and found 8,000 ducats again.
// Nothing had malfunctioned: a migration had been edited, which changes the chain fingerprint, and
// localDb.ts then does what its own header promises — it demolishes the stored world and rebuilds
// it from 0001, because applying new migrations onto an old database produces a schema that exists
// in no repository. That rule is right and it stays.
//
// What was wrong is that it happened WITHOUT A WORD. `bootState` has carried a `rebuilt` flag since
// the day it was written and nothing in the app had ever read it — a fact computed and thrown away.
// A purse silently returning to its opening balance does not read as "the world was rebuilt". It
// reads as the game losing your money, which is exactly how it was reported.
//
// A Card and NOT a Notice: Notice renders a <p>, and this has paragraphs and buttons in it. It is
// also not a toast — losing a voyage is not a thing to mention for four seconds and withdraw. It
// stands until the player dismisses it.

function useBootState() {
  return useSyncExternalStore(bootChannel.subscribe, bootChannel.get, bootChannel.get)
}

export function RebuildNotice() {
  const boot = useBootState()
  const [dismissed, setDismissed] = useState(false)

  if (!boot.rebuilt || dismissed) return null
  const rescued = boot.rescued

  return (
    <Card tone="warning" className="mx-4 mt-3" data-testid="rebuild-notice">
      <SectionLabel className="mb-1">The world was rebuilt</SectionLabel>
      <div className="space-y-1.5 text-sm text-ink-muted">
        <p>
          This build carries a changed migration chain, so the world in this browser was demolished
          and built again from the first migration. A world half-built by one version of the game and
          half by another exists in no repository, so it is never patched in place.
        </p>
        {rescued === null ? (
          <p>There was nothing of yours in the old world, so nothing was lost.</p>
        ) : rescued.stored ? (
          <p>
            Your house went with it — <strong className="text-ink">{rescued.rows} row(s)</strong>{' '}
            across {rescued.tables} table(s), your purse and your ledger among them. They were copied
            out before the demolition and are held in this browser under{' '}
            <code className="font-mono text-xs text-ink">{RESCUE_KEY}</code>. They are NOT put back
            automatically: a rebuild gives every port and every good a new id, so replaying them
            needs a translation that is not written yet.
          </p>
        ) : (
          <p>
            Your house went with it — {rescued.rows} row(s) — and could NOT be copied out first:{' '}
            {rescued.note}.
          </p>
        )}
      </div>
      <div className="mt-3 flex flex-wrap gap-2">
        <Button variant="secondary" onClick={() => setDismissed(true)}>
          I have read this
        </Button>
        {rescued?.stored && (
          <Button
            variant="secondary"
            onClick={() => {
              forgetRescue()
              setDismissed(true)
            }}
          >
            Discard the copy
          </Button>
        )}
      </div>
    </Card>
  )
}
