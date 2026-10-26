import { useCallback, useState } from 'react'

// A LIST'S FILTERS AND SORT, REMEMBERED — the pure half of `FilterBar` (the collapsibleState.ts idiom: a key builder
// and a reader that never trusts what it reads), plus the one hook that keeps a list's choice in this browser.
//
// KEY: `byeharu-voyage.filter.v1:<list>` — `list` is the caller's stable LIST id ('stats.cities', 'stats.markets'),
// never a per-row id. A UI preference: no game state, not per-account.
//
// Storage is read and written inside try/catch: a private window refuses it, and then the choice still holds for
// this tab and simply does not outlast it. A stored value the list no longer offers is the caller's to drop
// (`oneOf`): a country that left the list, a sort that was renamed.

export type FilterChoice = Record<string, string>

export function filterStorageKey(list: string): string {
  return `byeharu-voyage.filter.v1:${list}`
}

/** The remembered choice over the defaults: only the defaults' keys, only string values; garbage, absence or a
 *  throwing reader give the defaults. */
export function readFilterChoice<T extends FilterChoice>(read: (key: string) => string | null, list: string, defaults: T): T {
  try {
    const raw = read(filterStorageKey(list))
    if (raw === null) return defaults
    const parsed: unknown = JSON.parse(raw)
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) return defaults
    const out: FilterChoice = { ...defaults }
    for (const k of Object.keys(defaults)) {
      const v = (parsed as Record<string, unknown>)[k]
      if (typeof v === 'string') out[k] = v
    }
    return out as T
  } catch {
    return defaults
  }
}

/** `value` when the list still offers it, else `fallback`. */
export function oneOf<T extends string>(value: string, offered: readonly T[], fallback: T): T {
  return (offered as readonly string[]).includes(value) ? (value as T) : fallback
}

/** A list's filters and sort, kept in this browser per list. */
export function useFilterChoice<T extends FilterChoice>(list: string, defaults: T): [T, (patch: Partial<T>) => void] {
  const [choice, setChoice] = useState<T>(() =>
    readFilterChoice((k) => (typeof localStorage === 'undefined' ? null : localStorage.getItem(k)), list, defaults),
  )
  const change = useCallback(
    (patch: Partial<T>) => {
      setChoice((prev) => {
        const next = { ...prev, ...patch } as T
        try {
          localStorage.setItem(filterStorageKey(list), JSON.stringify(next))
        } catch {
          // storage refused: the choice holds for this tab only
        }
        return next
      })
    },
    [list],
  )
  return [choice, change]
}
