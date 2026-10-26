import { useEffect } from 'react'

// THE TRADE'S TOAST (owner row 229: "make it like a true game") — one short line after a trade or a trip queued
// ("Bought 10 Pepper −1,230 🪙"), at the top of the glass, gone by itself. No sound. It says what the server already
// did; it never stands in for the cargo or the purse, which change in place. Reduced motion: the global rule in
// index.css collapses its fade to nothing.

const SHOWN_MS = 3200

export function TradeToast({ text, onGone }: { text: string | null; onGone: () => void }) {
  useEffect(() => {
    if (text === null) return
    const id = window.setTimeout(onGone, SHOWN_MS)
    return () => window.clearTimeout(id)
  }, [text, onGone])
  return (
    <div className="pointer-events-none fixed inset-x-0 top-16 z-60 flex justify-center px-4" aria-live="polite" role="status">
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
