import { useId, useState } from 'react'

// Explain's open/closed state — beside Explain.tsx exactly as collapsibleState.ts sits beside
// Collapsible.tsx and overlayLayout.ts beside OverlayPanel.tsx. It lives here and not in the
// component file for the reason the lint rule states: a module that exports both a component and a
// non-component breaks Fast Refresh, so the house pattern is chrome in the .tsx, logic in the .ts.
//
// DELIBERATELY NOT PERSISTED, unlike a Collapsible fold. A fold remembers which SECTIONS a player
// keeps open, which is a preference worth carrying between visits. An explanation is a question
// asked once and answered; remembering it open would put the paragraph back on the screen for
// good, which is the whole defect Explain.tsx exists to close.

/** Open/close state for one explanation, plus the id wiring its dot to its panel for a11y. */
export function useExplainDisclosure() {
  const panelId = useId()
  const [open, setOpen] = useState(false)
  return { open, panelId, onToggle: () => setOpen((v) => !v) }
}

export type ExplainDisclosure = ReturnType<typeof useExplainDisclosure>
