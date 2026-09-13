import { useSyncExternalStore, useState } from 'react'
import { Button, Note } from '../components/ui'
import { bootChannel } from '../lib/db/bootState'

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
// ── STEP 3: THREE PARAGRAPHS, TWO ⓘ DOTS AND TWO BUTTONS BECAME ONE LINE ────────────────────────
// docs/UI_DIRECTION.md §6, "Shell", names this file by name: "`RebuildNotice` becomes one `Note`:
// *The world was rebuilt from the first migration.* [OK]". It was a bordered warning Card with a
// letter-spaced section label, up to four paragraphs, two `Explain` dots and two buttons — §2's
// count of "unnecessary info" in a single component, on a bar that stands over every screen.
//
// WHAT WAS CUT, AND WHERE IT WENT. The news a player can act on is that the world was rebuilt. Why
// a half-built world is never patched in place is a standing rule about how this game is BUILT and
// belongs in the repository, not on a quay. The rescue copy's row and table counts, its storage
// key and the fingerprint mismatch are a developer's facts, so they take the route §5 gives every
// code: `Note`'s `code` prop, which writes to `console.debug` and never to the screen.
//
// AND THE SECOND BUTTON WENT WITH THEM. "Discard the copy" called `forgetRescue()` to delete a
// blob no screen reads and no migration replays. §5: "a `Note` that needs two buttons is a
// decision, which belongs in a tray with its own primary" — and this is not a decision, it is
// news. The copy is still TAKEN (lib/db/rescue.ts is untouched); it is simply no longer a thing
// the player is asked about before they have understood the sentence above it.
//
// It is still not a toast: losing a voyage is not a thing to mention for four seconds and
// withdraw. It stands until the player dismisses it.

function useBootState() {
  return useSyncExternalStore(bootChannel.subscribe, bootChannel.get, bootChannel.get)
}

export function RebuildNotice() {
  const boot = useBootState()
  const [dismissed, setDismissed] = useState(false)

  if ((!boot.rebuilt && boot.imageRefused === null) || dismissed) return null

  // ── A REFUSED PRE-BUILT WORLD (2026-08-25) ──────────────────────────────────────────────────
  // The world may arrive pre-built, generated during `npm run build` from the chain in the
  // repository at that moment. If the one that arrived says it was built from a DIFFERENT chain
  // than the one this build carries, the boot throws it away and applies the chain instead — the
  // game is correct either way. But that is D23's defect exactly: two worlds, both plausible, and
  // "nothing red happened anywhere". So it is red here, on the screen, and not only in a console
  // nobody has open. A rebuild is the louder of the two and says so; the mismatch itself is a
  // fault in the BUILD, and it goes to the log with its evidence attached.
  const rebuilt = boot.rebuilt
  const line = rebuilt
    ? 'The game world was rebuilt from scratch.'
    : 'A ready-made world that did not match this build was discarded, and the world was built here.'

  return (
    <Note
      tone="warning"
      data-testid={rebuilt ? 'rebuild-notice' : 'image-refused-notice'}
      className="mx-gutter mt-2"
      code={[
        rebuilt ? 'world rebuilt from 0001' : null,
        boot.rescued === null
          ? null
          : `rescue: ${boot.rescued.rows} row(s) across ${boot.rescued.tables} table(s), ` +
            `stored=${boot.rescued.stored}${boot.rescued.note ? ` (${boot.rescued.note})` : ''}`,
        boot.imageRefused === null ? null : `image refused: ${boot.imageRefused}`,
      ]
        .filter(Boolean)
        .join(' · ')}
      action={
        <Button variant="quiet" onClick={() => setDismissed(true)}>
          OK
        </Button>
      }
    >
      {line}
    </Note>
  )
}
