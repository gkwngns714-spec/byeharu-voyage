// THE REACT DOOR to the locale: one subscription, read through useSyncExternalStore.

import { useSyncExternalStore } from 'react'
import { getLocale, subscribeLocale, type Locale } from './locale'
import { tFor, type T } from './translate'

export function useLocale(): Locale {
  return useSyncExternalStore(subscribeLocale, getLocale, getLocale)
}

/** The `t` for this viewer's locale. Its identity changes exactly when the locale does. */
export function useT(): T {
  return tFor(useLocale())
}
