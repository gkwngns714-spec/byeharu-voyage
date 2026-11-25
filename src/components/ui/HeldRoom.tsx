import { useLayoutEffect, useRef, useState, type ReactNode } from 'react'
import { Skeleton } from './Skeleton'

// THE ROOM A BLOCK HAD LAST TIME, HELD WHILE ITS READ IS ASKED (2026-11-25, the owner's law: nothing on a page moves by itself).
//
// Some blocks cannot know their height before their own read answers: a list as long as the server makes it (HQ's Best moves), a card
// that is there only when something happened (a choice open at sea, news from away, the country race). Drawn when the answer lands,
// each pushed everything under it down, a moment after the page was on the glass.
//
// The height cannot be reserved from nothing, but it is nearly always what it was the last time this glass drew the page. So the
// block's settled height is remembered (per block, per glass width, in this browser), and while the read is asked that room is held:
// the block's own waiting face, and a quiet skeleton for the rest of it. The answer then fills a place that is already there.
//
//   · Only the HEIGHT is remembered, never the answer: nothing old is printed as if it were now.
//   · A block that was not there last time holds nothing, and draws nothing: no gap (an empty holder takes no place in its list).
//   · The first visit on a glass has nothing to hold, and an answer that differs from last time's changes the block once: that is
//     the world's news, not a late read.

const KEY = 'bv:room:'

function recall(key: string): number | null {
  try {
    const raw = window.localStorage.getItem(KEY + key)
    const n = raw === null ? Number.NaN : Number(raw)
    return Number.isFinite(n) && n >= 0 ? n : null
  } catch {
    return null
  }
}

function remember(key: string, px: number): void {
  try {
    window.localStorage.setItem(KEY + key, String(px))
  } catch {
    // no storage (a private window): nothing is held next time, as on a first visit
  }
}

export function HeldRoom({
  name,
  asking,
  className = '',
  children,
}: {
  /** Which block this is: one name per block per page (`hq-moves`). */
  name: string
  /** The block's read has not answered yet: hold the room. False: what stands is the answer, and its height is remembered. */
  asking: boolean
  /** How the block's own children are laid out (a gap between several cards). */
  className?: string
  children?: ReactNode
}) {
  // the glass width is part of the name: a block is taller on a phone than on a desk
  const [key] = useState(() => `${name}:${typeof window === 'undefined' ? 0 : window.innerWidth}`)
  const [held] = useState(() => recall(key))
  const box = useRef<HTMLDivElement>(null)

  useLayoutEffect(() => {
    const el = box.current
    if (asking || !el) return
    const keep = () => remember(key, el.getBoundingClientRect().height)
    keep()
    const seen = new ResizeObserver(keep)
    seen.observe(el)
    return () => seen.disconnect()
  }, [asking, key])

  const hold = asking && held !== null && held > 0
  return (
    <div
      ref={box}
      className={`flex min-w-0 flex-col empty:hidden ${className}`}
      style={hold ? { minHeight: held } : undefined}
      aria-busy={hold || undefined}
      data-held-room={name}
    >
      {children}
      {hold && <Skeleton className="min-h-0 w-full flex-1 rounded-tile" />}
    </div>
  )
}
