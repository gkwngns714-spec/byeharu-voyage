import { useEffect, type RefObject } from 'react'

// THE PRESS-OUTSIDE, AND ITS KEYBOARD TWIN — the one way a floating thing goes away.
//
// Written a second time on 2026-10-20 (the fleet picker's dropdown, after the route editor's port
// field), so it became a function the same turn (docs/NO_SPAGHETTI.md §1). Both callers want the
// same two roads out: a `click` that lands OUTSIDE the box, and Escape from wherever the focus has
// gone. It is `click`, not blur or pointerdown: `click` is the event that says a press COMPLETED on
// one element; a blur fires on the mousedown with the mouseup still to come, and closing on it
// swallowed the pick the finger was making (src/live/PortField.tsx, the head of the file).
//
// In its own file rather than Popover.tsx: the react-refresh rule keeps a component file to
// components, and a hook is not one.

export function useDismiss(open: boolean, box: RefObject<HTMLElement | null>, onDismiss: () => void): void {
  useEffect(() => {
    if (!open) return
    const onClick = (e: MouseEvent) => {
      if (box.current && !box.current.contains(e.target as Node)) onDismiss()
    }
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onDismiss()
    }
    document.addEventListener('click', onClick)
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('click', onClick)
      document.removeEventListener('keydown', onKey)
    }
  }, [open, box, onDismiss])
}
