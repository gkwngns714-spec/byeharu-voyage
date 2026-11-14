import { useEffect, useMemo, useState } from 'react'
import type { ViewBox } from '../lib/geo'
import { paperOf } from './chartView'
import { FINE_COAST_INDEX } from './fineCoast.generated'
import { fineLevelFor, indexLevel, plainTilePaths, shoreOfTiles, tilePaths, tilesCover, tilesOver, type CoastPaths, type FineLevelIndex, type TilePaths } from './fineCoastBuild'
import type { ShoreInHand } from './landfall'

// THE FINE COAST, FETCHED (./fineCoastBuild.ts says what it is and why).
//
// WHEN. Nothing is fetched until a chart is zoomed inside a level's limit (0.03 degrees a pixel for
// the middle level, 0.006 for the fine one). Then only the tiles under the coast's wide sheet
// (`paperOf` the view: the view and a quarter of it on each side) are asked for, each once a
// session; the browser's cache keeps them after that.
//
// WHAT THE CHART IS HANDED. The two strings for those tiles joined, ONLY when every one of them has
// arrived: a coast drawn from some tiles and not others would show land as sea. Until then it is the
// last whole set, for as long as that set still covers the glass (a pan reaches for a new tile a
// quarter of a glass before the glass gets there, which is the time the fetch has), and failing that
// null, which is the 110m coast the chart always has.
//
// THE STRINGS CHANGE ONLY WHEN THE SET OF TILES DOES, never on a frame of a pan: the tiles are far
// larger than the sheet's grid step, and the answer is memoised on the set's name. So the coast's
// sheet (ChartCanvas, `CoastSheet`) is repainted no more often than it was.

const LEVELS: readonly FineLevelIndex[] = FINE_COAST_INDEX.levels.map(indexLevel)
const LEVEL_BY_NAME = new Map(LEVELS.map((level) => [level.name, level]))

/** Every tile read this session, by "level/id". A failed fetch is remembered as null: that tile's
 *  neighbourhood stays on the 110m coast for the session and nothing is retried in a loop. */
const cache = new Map<string, TilePaths | null>()
const pending = new Map<string, Promise<void>>()

function tileUrl(level: FineLevelIndex, id: string): string {
  return `${import.meta.env.BASE_URL}coast/${level.name}/${id}.json?v=${FINE_COAST_INDEX.version}`
}

/** The tile if it is in hand (a tile with no file is made on the spot), null if its fetch failed,
 *  undefined if it has a file that has not arrived. */
function tileNow(level: FineLevelIndex, id: string): TilePaths | null | undefined {
  const key = `${level.name}/${id}`
  if (cache.has(key)) return cache.get(key)
  const kind = level.kindOf(id)
  if (kind === 'file') return undefined
  const plain = plainTilePaths(level, id, kind)
  cache.set(key, plain)
  return plain
}

function loadTile(level: FineLevelIndex, id: string): Promise<void> {
  const key = `${level.name}/${id}`
  let job = pending.get(key)
  if (!job) {
    job = fetch(tileUrl(level, id))
      .then((response) => {
        if (!response.ok) throw new Error(`coast tile ${key}: ${response.status}`)
        return response.json()
      })
      .then((json: unknown) => {
        cache.set(key, tilePaths(level, id, json))
      })
      .catch(() => {
        cache.set(key, null)
      })
      .finally(() => {
        pending.delete(key)
      })
    pending.set(key, job)
  }
  return job
}

/** The fine coast in hand: what is drawn, and the same tiles as the shore a harbour is set on. */
export interface FineCoast extends CoastPaths {
  readonly shore: ShoreInHand
}

interface Shown extends FineCoast {
  readonly level: FineLevelIndex
  readonly ids: ReadonlySet<string>
}

/** The set's name back into its level and ids. */
function parseWanted(wanted: string): { level: FineLevelIndex; ids: string[] } | null {
  const [name, list] = wanted.split(':')
  const level = LEVEL_BY_NAME.get(name)
  return level && list ? { level, ids: list.split(' ') } : null
}

/** The coast for this view from the fine tiles, or null: draw the 110m coast. */
export function useFineCoast(box: ViewBox, unitsPerPx: number): FineCoast | null {
  const level = fineLevelFor(LEVELS, unitsPerPx)
  // The set of tiles, as a name: the same string on every frame until the wide sheet reaches a new tile.
  const wanted = level ? `${level.name}:${tilesOver(level, paperOf(box)).join(' ')}` : ''
  // Counts tiles landing: it re-renders the chart, and re-keys the join below.
  const [arrivals, setArrivals] = useState(0)

  useEffect(() => {
    const set = parseWanted(wanted)
    if (!set) return
    let live = true
    for (const id of set.ids) {
      if (tileNow(set.level, id) !== undefined) continue
      void loadTile(set.level, id).then(() => {
        if (live) setArrivals((n) => n + 1)
      })
    }
    return () => {
      live = false
    }
  }, [wanted])

  // Whole or nothing.
  const whole = useMemo<Shown | null>(() => {
    void arrivals
    const set = parseWanted(wanted)
    if (!set) return null
    let d = ''
    let coastD = ''
    for (const id of set.ids) {
      const tile = tileNow(set.level, id)
      if (!tile) return null
      d += tile.d
      coastD += tile.coastD
    }
    // Open water has no land at all, and an empty body would read as "no coast yet" to the layer,
    // which then draws nothing, the islets and the regions' water with it. A lone move is no ink.
    const at = set.level
    const ids = new Set(set.ids)
    return { d: d === '' ? 'M0 0' : d, coastD, level: at, ids, shore: shoreOfTiles(at, ids, (id) => tileNow(at, id)?.rings) }
  }, [wanted, arrivals])

  // The last whole set, kept for the frames in which the next one is still on its way (derived from
  // the previous render, set only on a change).
  const [held, setHeld] = useState<Shown | null>(null)
  if (whole && whole !== held) setHeld(whole)

  if (!level) return null
  if (whole) return whole
  return held && tilesCover(held.level, held.ids, box) ? held : null
}
