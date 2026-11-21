import { useEffect } from 'react'
import { glassBesideRailClass } from '../../../components/ui'

// THE TRADE'S TOAST (owner row 229: "make it like a true game") — one short line after a trade or a trip queued
// ("Bought 10 Pepper −1,230 🪙"), low on the glass, gone by itself. No sound. It says what the server already
// did; it never stands in for the cargo or the purse, which change in place. Reduced motion: the global rule in
// index.css collapses its fade to nothing.
//
// It is centred on THE GLASS BESIDE THE RAIL (screenLayout.ts `glassBesideRailClass`, THE SHELL): the whole window on a phone,
// what the rail leaves from `lg` — the page's middle, not the window's (it stood half a rail left of the page at 1280).
//
// LOW ON THE GLASS, CLEAR OF THE HEADER (2026-11-22 play-test): at the top it covered the page's header (the ship's name and her
// arrival time on a phone, "Cargo" at 1,280). It now stands where the arrival card stands: over the phone's bar (bottom-24), and
// low on the page beside the rail (lg:bottom-10).

const SHOWN_MS = 3200

export function TradeToast({ text, onGone }: { text: string | null; onGone: () => void }) {
  useEffect(() => {
    if (text === null) return
    const id = window.setTimeout(onGone, SHOWN_MS)
    return () => window.clearTimeout(id)
  }, [text, onGone])
  return (
    <div className={`pointer-events-none ${glassBesideRailClass()} bottom-24 z-60 flex lg:bottom-10 justify-center px-4`} aria-live="polite" role="status">
      {text !== null && (
        <span
          className="bv-fade-in max-w-full break-words rounded-control bg-surface-2 px-4 py-2 text-t-label font-semibold text-ink shadow-float"
          data-testid="trade-toast"
        >
          {text}
        </span>
      )}
    </div>
  )
}
