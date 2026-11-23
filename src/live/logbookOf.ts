import type { LedgerEvent, LogbookArrival, LogbookFound, LogbookSale, LogbookSetDone } from '../lib/rpc'

// 0478 (roadmap 2026-11-23 slice 9): THE LOGBOOK'S WORD ON AN EVENT, as the arrival card reads it. The server adds `logbook` to a
// VOYAGE_REPORT (a first harbour, `found`, and the sets it finished) and to a SOLD event (a first sale of a good) only while the logbook
// is lit and only when something is new; dark, or nothing new, the key is absent and these answer null. Nothing is computed here: the
// payload is checked for shape and handed on.

const isObj = (x: unknown): x is Record<string, unknown> => typeof x === 'object' && x !== null && !Array.isArray(x)
const num = (x: unknown): number => (typeof x === 'number' && Number.isFinite(x) ? x : 0)
const str = (x: unknown): string | null => (typeof x === 'string' && x !== '' ? x : null)

function setsOf(x: unknown): LogbookSetDone[] {
  if (!Array.isArray(x)) return []
  return x.flatMap((s): LogbookSetDone[] => {
    if (!isObj(s) || (s.set !== 'region' && s.set !== 'kind') || !str(s.code)) return []
    return [{ set: s.set, code: str(s.code)!, name: str(s.name) ?? str(s.code)!, rep: num(s.rep) }]
  })
}

function foundOf(x: unknown): LogbookFound | null {
  if (!isObj(x) || !str(x.port)) return null
  return {
    port: str(x.port)!,
    region: str(x.region),
    region_name: str(x.region_name),
    n: num(x.n),
    of: num(x.of),
    harbours: num(x.harbours),
    sea: str(x.sea),
    sea_new: x.sea_new === true,
    specialty: Array.isArray(x.specialty) ? x.specialty.filter((c): c is string => typeof c === 'string') : [],
  }
}

/** A VOYAGE_REPORT's logbook word: the first harbour and the sets finished, or null when it carries none. */
export function arrivalLogbookOf(e: LedgerEvent): LogbookArrival | null {
  if (e.kind !== 'VOYAGE_REPORT' || !isObj(e.payload.logbook)) return null
  const found = foundOf(e.payload.logbook.found)
  const sets = setsOf(e.payload.logbook.sets)
  if (!found && sets.length === 0) return null
  return { ...(found ? { found } : {}), ...(sets.length ? { sets } : {}) }
}

/** A SOLD event's logbook word: the good sold for the first time, or null. */
export function saleLogbookOf(e: LedgerEvent): LogbookSale | null {
  if (e.kind !== 'SOLD' || !isObj(e.payload.logbook)) return null
  const l = e.payload.logbook
  if (!str(l.good) || !str(l.kind)) return null
  const sets = setsOf(l.sets)
  return { good: str(l.good)!, kind: str(l.kind)!, n: num(l.n), of: num(l.of), goods: num(l.goods), ...(sets.length ? { sets } : {}) }
}
