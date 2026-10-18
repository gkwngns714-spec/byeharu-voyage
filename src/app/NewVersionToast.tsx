import { useEffect, useState } from 'react'
import { Icon } from '../components/ui'
import { BUILD_ID, newestBuildId } from '../lib/version'

// THE ONE PLACE THE GAME SAYS A NEWER BUILD IS LIVE (2026-10-19).
//
// ── WHY ────────────────────────────────────────────────────────────────────────────────────────
// The owner kept a tab open across deploys, so he was playing an old build and reported a defect
// that had already been fixed. He should always know when a newer version is live. This is that
// sentence, and nothing else: no changelog, no version number on screen, no modal.
//
// ── WHAT IT DOES ───────────────────────────────────────────────────────────────────────────────
// It asks src/lib/version.ts for the published build's id every five minutes, when the window
// regains focus, and when the tab becomes visible again — the three moments a player comes back
// to a tab that may have gone stale. Not on mount: a tab that has just loaded IS the published
// build, and a check there would only ever catch a CDN edge that is still handing out the
// previous index.html, which a reload cannot fix either. When the published id differs from
// BUILD_ID the toast shows. Tapping it reloads; the ✕ dismisses it for this session (the id it
// was dismissed for is kept in sessionStorage, so a reload does not bring it back, and a NEWER
// build after that does).
//
// ── WHAT IT IS, ON SCREEN ──────────────────────────────────────────────────────────────────────
// docs/UI_DIRECTION.md §4.3's SECOND elevation — the floating corner glass (72%-alpha surface,
// 16px blur, `--shadow-float`), `fixed` in the top-right corner, so it sits over whatever is there
// and MOVES NOTHING (the owner's law that a press never restructures the page holds for a banner
// too: it is not in the flow, so nothing under it can shift). Above every tray (`z-60`: a side
// tray stands at z-50 on the same edge). One line of t-label, the whole glass is the button; the
// ✕ is a 44px target of its own. The words are docs/WORDS.md's row for it.
//
// ── A FAILED CHECK SHOWS NOTHING ───────────────────────────────────────────────────────────────
// newestBuildId() returns null on any failure, and null is "no news" here. A player on a train
// never sees an error for a file that could not be read.

const DISMISSED_KEY = 'bv.newVersion.dismissed'
const EVERY_MS = 5 * 60_000

function readDismissed(): string | null {
  try {
    return sessionStorage.getItem(DISMISSED_KEY)
  } catch {
    return null
  }
}

function writeDismissed(id: string) {
  try {
    sessionStorage.setItem(DISMISSED_KEY, id)
  } catch {
    // A session that cannot keep storage forgets the dismissal on reload. That is the lesser
    // answer, and a truthful one: the newer build is still live.
  }
}

export function NewVersionToast() {
  const [newer, setNewer] = useState<string | null>(null)
  const [dismissed, setDismissed] = useState<string | null>(readDismissed)

  useEffect(() => {
    let alive = true
    let asking = false
    // Focus and visibilitychange both fire on one tab switch; one question is enough.
    const check = async () => {
      if (asking) return
      asking = true
      const id = await newestBuildId()
      asking = false
      if (alive && id !== null && id !== BUILD_ID) setNewer(id)
    }
    const onFocus = () => void check()
    const onVisible = () => {
      if (document.visibilityState === 'visible') void check()
    }
    const every = window.setInterval(() => void check(), EVERY_MS)
    window.addEventListener('focus', onFocus)
    document.addEventListener('visibilitychange', onVisible)
    return () => {
      alive = false
      window.clearInterval(every)
      window.removeEventListener('focus', onFocus)
      document.removeEventListener('visibilitychange', onVisible)
    }
  }, [])

  if (newer === null || newer === dismissed) return null

  return (
    <div
      role="status"
      data-testid="new-version"
      data-build={newer}
      className="fixed right-3 top-10 z-60 flex max-w-[calc(100%-1.5rem)] items-center overflow-hidden rounded-tile bg-surface/70 shadow-float backdrop-blur-lg"
    >
      <button
        type="button"
        onClick={() => window.location.reload()}
        className="min-h-11 flex-1 truncate px-4 text-left text-t-label text-ink hover:bg-surface-2/60"
      >
        New version — tap to refresh
      </button>
      <button
        type="button"
        aria-label="Dismiss"
        onClick={() => {
          writeDismissed(newer)
          setDismissed(newer)
        }}
        className="flex h-11 w-11 shrink-0 items-center justify-center text-ink-muted hover:text-ink"
      >
        <Icon name="close" size={16} />
      </button>
    </div>
  )
}
