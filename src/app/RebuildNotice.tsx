import { useSyncExternalStore, useState } from 'react'
import { Button, Card, Explain, SectionLabel } from '../components/ui'
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

  if ((!boot.rebuilt && boot.imageRefused === null) || dismissed) return null
  const rescued = boot.rescued

  // ── A REFUSED PRE-BUILT WORLD (2026-08-25) ──────────────────────────────────────────────────
  // The world may now arrive pre-built, generated during `npm run build` from the chain in the
  // repository at that moment. If the one that arrived says it was built from a DIFFERENT chain
  // than the one this build carries, the boot throws it away and applies the chain instead — the
  // game is correct either way. But that is D23's defect exactly: two worlds, both plausible, and
  // "nothing red happened anywhere". So it is red here, on the screen, and not only in a console
  // nobody has open.
  if (!boot.rebuilt && boot.imageRefused !== null) {
    return (
      <Card tone="warning" className="mx-4 mt-3" data-testid="image-refused-notice">
        <SectionLabel className="mb-1">The pre-built world was refused</SectionLabel>
        <div className="space-y-1.5 text-sm text-ink-muted">
          <p>
            This build downloaded a ready-made world that does not match its own migrations, so it
            was discarded and the world was built here instead. Nothing of yours was at risk — but
            this build is shipping two different worlds, and that is a fault to report.
            <Explain label="what did not match" dotClassName="ml-1">
              {boot.imageRefused}
            </Explain>
          </p>
        </div>
        <div className="mt-3 flex flex-wrap gap-2">
          <Button variant="secondary" onClick={() => setDismissed(true)}>
            I have read this
          </Button>
        </div>
      </Card>
    )
  }

  return (
    <Card tone="warning" className="mx-4 mt-3" data-testid="rebuild-notice">
      <SectionLabel className="mb-1">The world was rebuilt</SectionLabel>
      <div className="space-y-1.5 text-sm text-ink-muted">
        <p>
          {/* THE REASONING MOVED BEHIND THE DOT, THE NEWS STAYED. Why a half-built world is never
              patched in place is a standing rule about how this game is built
              (docs/UI_DIRECTION.md §4 rule 4); that the world was rebuilt is what a player who has
              just lost a voyage needs on the screen. */}
          This build changed the migration chain, so the world in this browser was rebuilt from the
          first migration.
          <Explain label="why it was rebuilt rather than patched" dotClassName="ml-1">
            A world half-built by one version of the game and half by another exists in no
            repository, so it is never patched in place.
          </Explain>
        </p>
        {rescued === null ? (
          <p>Nothing of yours was in the old world, so nothing was lost.</p>
        ) : rescued.stored ? (
          /* THE LIMITATION IS THE HEADLINE AND THE STORAGE KEY IS NOT. `byeharu-voyage.rescue.v1`
             is where the copy sits and a player cannot do anything with it, so it moved behind the
             dot with the reason it is not replayed — the two facts that belong together. What the
             player must read without tapping is that their house went, and that a copy was kept. */
          <p>
            Your house went with it — <strong className="text-ink">{rescued.rows} row(s)</strong>{' '}
            across {rescued.tables} table(s). A copy was taken first, and it is NOT put back
            automatically.
            <Explain label="the copy that was kept" dotClassName="ml-1">
              It is held in this browser under{' '}
              <code className="font-mono text-xs text-ink">{RESCUE_KEY}</code>. A rebuild gives
              every port and every good a new id, so replaying it needs a translation that is not
              written yet.
            </Explain>
          </p>
        ) : (
          <p>
            Your house went with it — {rescued.rows} row(s) — and could NOT be copied out first:{' '}
            {rescued.note}.
          </p>
        )}
        {/* A rebuild that ALSO refused a mispaired pre-built world says both things. The rebuild is
            the player's news; the refusal is a fault in the build, and it must not be swallowed by
            the louder message next to it. */}
        {boot.imageRefused !== null && (
          <p>
            It also downloaded a ready-made world that did not match its own migrations, and
            discarded it.
            <Explain label="what did not match" dotClassName="ml-1">
              {boot.imageRefused}
            </Explain>
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
