import { useSyncExternalStore } from 'react'
import { WIDE_QUERY } from './screenLayout'

// THE ONE READING OF "IS THIS A WIDE GLASS?" — `screenLayout.ts`'s WIDE_QUERY, as a hook, so the
// Tray can drop its inline height (a side panel has no detents) on the same breakpoint the CSS
// switches on. `matchMedia` is the source; React is told only when the answer changes.

const subscribe = (onChange: () => void) => {
  const mq = window.matchMedia(WIDE_QUERY)
  mq.addEventListener('change', onChange)
  return () => mq.removeEventListener('change', onChange)
}
const read = () => window.matchMedia(WIDE_QUERY).matches

export function useWide(): boolean {
  return useSyncExternalStore(subscribe, read, () => false)
}
