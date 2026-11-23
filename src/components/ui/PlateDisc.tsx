import type { ReactNode } from 'react'

// THE PLATE'S DISC — a house's flag (or a mark) on a 48-px round inset, the head of a plate (2026-11-23, visual pass 3). You's house
// plate drew it by hand; the Account page's header is the same plate, so the recipe lives here once.
export function PlateDisc({ children, className = '', ...rest }: { children: ReactNode; className?: string } & { 'data-testid'?: string }) {
  return (
    <span className={`flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-surface-2 ring-1 ring-edge ${className}`} {...rest}>
      {children}
    </span>
  )
}
