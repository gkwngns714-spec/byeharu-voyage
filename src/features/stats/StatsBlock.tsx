import type { ReactNode } from 'react'

// A BLOCK OF A STATS FACE — one heading line and the figures under it, on the glass (owner,
// 2026-11-01: *"everything is folded in stats this is soo wrong. make it compact showing everything
// possible."*). The figure beside the title is the block's headline (the net of the day), not a second
// copy of anything below it; `aside` is the block's own small chart, on the heading's line, so the shape
// of the thing costs no row of its own. It is `shrink-0`: a block is as tall as its figures, and it is
// the face's FIGURE REGION (a `ListPanel`'s `above`) that gives way on a short glass.

export function Block({
  title,
  figure,
  aside,
  children,
  className = '',
  ...rest
}: {
  title: ReactNode
  figure?: ReactNode
  aside?: ReactNode
  children: ReactNode
  className?: string
} & { 'data-testid'?: string }) {
  return (
    <section className={`shrink-0 ${className}`} {...rest}>
      <div className="mb-0.5 flex items-center gap-3">
        <h2 className="flex shrink-0 items-baseline gap-2 text-t-label font-semibold text-ink">
          {title}
          {figure !== undefined && <span className="font-normal tabular-nums">{figure}</span>}
        </h2>
        {aside}
      </div>
      {children}
    </section>
  )
}
