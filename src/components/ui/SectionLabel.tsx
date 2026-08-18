import type { ReactNode } from 'react'

// Design-system micro section label (the uppercase group heading used inside panels).
// Mono + letterspaced — the ledger's column-heading voice.

export function SectionLabel({ children, className = '' }: { children: ReactNode; className?: string }) {
  return (
    <h3 className={`mb-2 font-mono text-xs uppercase tracking-wider text-ink-faint ${className}`}>{children}</h3>
  )
}
