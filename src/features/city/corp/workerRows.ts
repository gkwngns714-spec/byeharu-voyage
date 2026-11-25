import { useMemo } from 'react'
import { fixOf, wreckFix, type WorkerFix } from '../../../domain/fleet'
import { formatDucatsDelta, formatFixed, formatInt, formatRealShort, instantMs } from '../../../lib/format'
import { properName, translateMaybe, type TKey } from '../../../lib/i18n'
import { worldLand, type ActionBasis, type FleetJobRow, type FleetView, type LandView, type WorkerAction as ServedAction, type WorkerRow as ServedRow } from '../../../lib/rpc'
import { litAway, useAwayReport } from '../../../live/useAwayReport'
import { useServedRead } from '../../../live/useServedRead'
import { litWorkers, useWorkersRead } from '../../../live/useWorkers'
import { portNameOf, useWorld } from '../../../live/worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE ONE ADAPTER FROM THE SERVED WORKER LIST TO HQ'S ROWS (docs/design/hq-corp-2026-11-24.md A2, C1; 0496)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A WORKER is one "character slot": a fleet (with her captain, if one is seated) or the land party. Each is on ONE action, and HQ lists
// them all on one screen. EVERY ROW IS world.workers()' ROW (0496: live/useWorkers.ts): who she is, her state, her action in the one
// shape, the two served stamps of her bar, why she stopped, and COIN AN HOUR AND EXPERIENCE AN HOUR AS SERVED. Nothing is worked out
// here: a rate the server did not serve (`basis` none: a fixed run before two whole runs of hers; the Best run, whose every run is
// another sale) is not drawn, and none is made up from other figures.
// THE CLIENT SHIPS AFTER 0496, so the rows are no longer put together from world.away_report and world.land: that adapter is deleted.
// Three older reads stay, each for what world.workers does not serve:
//   world.fleets        her picture: the flagship's class and the captain seated in her ships;
//   world.away_report   While away's own read (0481): a job's tally and its last run for HER SHEET, and whether standing jobs are lit;
//   world.land          the Land's names (a land's name: the action carries its code).

/** The land party's id as a worker (a fleet's is her own id). */
export const PARTY = 'party'

/** The id world.actions takes for a worker of HQ (`fleet:<uuid>` | `party:<n>`). */
export const servedId = (worker: string): string => (worker === PARTY ? 'party:1' : `fleet:${worker}`)

export type WorkerState = 'idle' | 'stopped' | 'working'

/** The code a job stopped on, or waits on (0499: `last.wait` carries the server's code while she waits for her repair or her crew). */
export function jobCode(job: Pick<FleetJobRow, 'state' | 'paused' | 'last'>): string | null {
  if (job.state === 'stopped') return job.paused
  const w = job.last?.wait
  return job.state === 'waiting' && w !== undefined && w.startsWith('E_') ? w : null
}

/** What a worker is doing, as data: the row and the sheets say it with `actionWord`. */
export type WorkerAction =
  | { kind: 'none' }
  /** 0481 `best`: the server picks her best run each time. */
  | { kind: 'best' }
  /** 0498 the near round (`best` with `within`): the best paying sale near her each run, home when nothing pays. `base`: the harbour
   *  she comes back to (a CODE). */
  | { kind: 'near'; base: string | null }
  /** 0481 `fixed`: one good, bought at one harbour and sold at another (port CODES); 0492 `end` 'store': brought home instead, into
   *  the home warehouse (`sell` is then her home harbour, as served). */
  | { kind: 'fixed'; good: string; buy: string; sell: string; end: 'sell' | 'store' }
  /** 0481 `land`: she carries the Land's goods to a yard. */
  | { kind: 'haul'; to: string | null }
  /** 0519 a job of rounds: the work's code and the base (a port CODE). */
  | { kind: 'round'; work: string; base: string }
  /** No standing job: a voyage sent by hand. */
  | { kind: 'sail'; to: string | null }
  /** The party's job: the good, and the land it is worked on (null: at home). */
  | { kind: 'land'; good: string; region: string | null }

/** One served figure of a row (never a rate). */
export interface WorkerFigure {
  key: 'runs' | 'earned' | 'left' | 'units' | 'trip' | 'xp'
  value: number
}

/** The served rates of her action (0496): each null when the server serves none. */
export interface WorkerRates {
  perHour: number | null
  xpPerHour: number | null
  /** Units an hour she brings to Storage (A2.1 `items_per_hour`: the land party's goods, a bring-home's). */
  itemsPerHour: number | null
  /** Where they come from: her own runs, a quote, a land job's terms, or nothing yet. */
  basis: ActionBasis
}

export interface WorkerRow {
  id: string
  kind: 'fleet' | 'party'
  /** A fleet's own name; null for the party (its word is the dictionary's). */
  name: string | null
  state: WorkerState
  /** A standing job that has nothing to do right now (her action stands, no bar). */
  waiting: boolean
  action: WorkerAction
  /** The two served stamps the progress bar is drawn between, or null (nothing under way). */
  bar: { fromMs: number; toMs: number } | null
  /** Her action's rates as served; null while she has no action. */
  rates: WorkerRates | null
  /** The served figures HER SHEET lists (the party's units a trip, its trip and its experience; a counted job's runs left). */
  figures: WorkerFigure[]
  /** WHAT HER STANDING JOB DID since she last read While away (its runs, her fleet's coin). Her SHEET's figures: on HQ's page these
   *  stand once, in While away (board/JobsAway.tsx), so her row does not print them. */
  tally: WorkerFigure[]
  /** Her Assign door works (her kind of work is lit on this server). */
  assignable: boolean
  /** A fleet's flagship class code, for her picture. */
  hull: string | null
  /** The first captain seated in her ships, served (0157). */
  captain: { code: string; name: string; grade: string } | null
  /** Why a stopped job stopped (0499: or waits on a code), in the server's words. */
  why: string | null
  /** The one press that mends it (domain/fleet `fixOf`), or null. A repair or a hire is offered only while she lies docked (the yard and the Inn
   *  take her there). */
  fix: WorkerFix | null
  /** 0497: her job is NOT stopped but waits (its run would leave no profit now): the served code, its sentence, and when the server
   *  asks it again. Null when she does not wait for a price. */
  wait: { code: string; sentence: string; retryMs: number } | null
  /** 0516: stopped by her own settings (a stop she set): the server's sentence, said on her row in place of the action (its press may be
   *  Repair, which opens no sheet). Null for every other stop. */
  stopSaid: string | null
}

export type LitLand = Extract<LandView, { company: true }>
export type LitJobs = ReadonlyMap<string, FleetJobRow>

/** Her action as the row says it, from the served shape. */
function actionOf(a: ServedAction | null, w: ServedRow): WorkerAction {
  if (!a) return w.kind === 'fleet' && w.worker_state === 'sea' ? { kind: 'sail', to: w.progress?.to_port ?? null } : { kind: 'none' }
  if (a.id === 'sea:best') return { kind: 'best' }
  if (a.id === 'sea:near') return { kind: 'near', base: a.base ?? null }
  if (a.id.startsWith('sea:fixed:') && a.good && a.buy && a.sell) return { kind: 'fixed', good: a.good, buy: a.buy, sell: a.sell, end: a.end === 'store' ? 'store' : 'sell' }
  if (a.id.startsWith('round:')) return { kind: 'round', work: a.id.split(':')[1], base: a.id.split(':')[2] }
  if (a.id.startsWith('sea:haul:')) return { kind: 'haul', to: a.sell ?? null }
  if (a.id.startsWith('land:') && a.good) return { kind: 'land', good: a.good, region: a.home ? null : (a.region ?? null) }
  return { kind: 'none' }
}

/** The served figures of her action that are not rates. */
function figuresOf(a: ServedAction | null): WorkerFigure[] {
  if (!a) return []
  const out: WorkerFigure[] = []
  if (typeof a.left === 'number') out.push({ key: 'left', value: a.left })
  if (a.id.startsWith('land:')) {
    const units = a.outputs.items[0]?.units
    if (typeof units === 'number') out.push({ key: 'units', value: units })
    if (a.interval_s !== null) out.push({ key: 'trip', value: a.interval_s })
    const xp = a.xp[0]?.xp
    if (typeof xp === 'number') out.push({ key: 'xp', value: xp })
  }
  return out
}

/** One row of HQ from one row of world.workers(). `fleet`: her fleet as world.fleets serves it (her picture); `job`: her standing job
 *  as While away reads it (her sheet's tally); `lit`: standing jobs are lit on this server. */
function rowOf(w: ServedRow, fleet: FleetView | null, job: FleetJobRow | null, lit: boolean): WorkerRow {
  const a = w.action
  const from = w.progress?.from ? instantMs(w.progress.from) : null
  const to = w.progress?.to ? instantMs(w.progress.to) : null
  const seat = fleet?.ships.flatMap((s) => s.seats?.list ?? []).find((s) => s.captain !== null)?.captain ?? null
  // no action: she is idle unless her ONE state (public.fleet_state, served) says she sails or cannot act
  const state: WorkerState =
    w.state === 'stopped'
      ? 'stopped'
      : w.state !== 'idle'
        ? 'working'
        : w.kind === 'fleet' && w.worker_state === 'sea'
          ? 'working'
          : w.kind === 'fleet' && w.worker_state !== 'port'
            ? 'stopped'
            : 'idle'
  return {
    id: w.kind === 'fleet' ? (w.fleet ?? w.id.replace(/^fleet:/, '')) : PARTY,
    kind: w.kind,
    name: w.kind === 'fleet' ? w.name : null,
    state,
    waiting: w.state === 'waiting',
    action: actionOf(a, w),
    bar: from !== null && to !== null && to > from ? { fromMs: from, toMs: to } : null,
    rates: a ? { perHour: a.per_hour, xpPerHour: a.xp_per_hour, itemsPerHour: a.items_per_hour, basis: a.basis } : null,
    figures: figuresOf(a),
    tally: job
      ? [
          { key: 'runs', value: job.runs },
          { key: 'earned', value: job.earned },
        ]
      : [],
    assignable: w.kind === 'party' || lit,
    hull: fleet?.ships[0]?.class_code ?? null,
    captain: seat ? { code: seat.code, name: seat.name, grade: seat.grade } : null,
    // the server's sentence, else its code's plain words (dict/codes.ts); never the code itself
    why: w.stop ? (w.stop.sentence ?? translateMaybe('en', 'codes', w.stop.code) ?? null) : null,
    stopSaid: w.stop?.code === 'E_STOP_DAMAGE' || w.stop?.code === 'E_STOP_PROFIT' ? w.stop.sentence : null,
    wait: w.wait && instantMs(w.wait.retry_at) !== null ? { code: w.wait.code, sentence: w.wait.sentence, retryMs: instantMs(w.wait.retry_at)! } : null,
    // the one press that mends it, from the served stop's code (`fixOf`); a repair or a hire only while she lies docked
    // 0497: and where no code names one, the press her own served state asks for (a wreck in a port; a towed hull at a yard)
    fix: (() => {
      const press = fixOf(w.stop?.code ?? w.wait?.code)
      const mine = (press === 'repair' || press === 'hire') && !(w.kind === 'fleet' && fleet?.status === 'DOCKED') ? null : press
      return w.kind === 'fleet' ? (wreckFix(fleet) ?? mine) : mine
    })(),
  }
}

/** Every worker of hers, in the served order (her fleets by their founding, then the party). */
export function workerRows(served: readonly ServedRow[], fleets: readonly FleetView[], jobs: LitJobs | null): WorkerRow[] {
  const byId = new Map(fleets.map((f) => [f.id, f]))
  return served.map((w) => rowOf(w, w.fleet ? (byId.get(w.fleet) ?? null) : null, w.fleet ? (jobs?.get(w.fleet) ?? null) : null, jobs !== null))
}

const ORDER: Record<WorkerState, number> = { idle: 0, stopped: 1, working: 2 }

/** Idle first, then stopped, then working; inside each, the served order. */
export function sortWorkers(rows: readonly WorkerRow[]): WorkerRow[] {
  return rows
    .map((r, i) => ({ r, i }))
    .sort((a, b) => ORDER[a.r.state] - ORDER[b.r.state] || a.i - b.i)
    .map((x) => x.r)
}

/** The state's word. A job that waits for a price (0497's `low`) says so: "Prices low". */
export function stateWord(r: Pick<WorkerRow, 'state' | 'waiting' | 'wait'>): TKey {
  return r.state === 'idle' ? 'corp.idle' : r.state === 'stopped' ? 'corp.stopped' : r.wait?.code === 'low' ? 'corp.pricesLow' : r.wait?.code === 'range' ? 'corp.outOfRange' : r.waiting ? 'corp.waiting' : 'corp.working'
}

/** The names an action is said with: a good's, a harbour's and a land's, each the catalogue's. */
export interface ActionNames {
  good: (code: string) => string
  port: (code: string) => string
  region: (code: string | null) => string
}

/** A worker's action in a few words: "Pepper · Lisbon → Setubal · Sell", "Iron · Iberia", "Best run". */
export function actionWord(a: WorkerAction, t: (key: TKey, vars?: Record<string, string | number>) => string, n: ActionNames): string {
  switch (a.kind) {
    case 'best':
      return t('corp.bestRun')
    case 'near':
      return a.base ? t('corp.nearOf', { port: n.port(a.base) }) : t('corp.near')
    case 'fixed':
      return `${n.good(a.good)} · ${n.port(a.buy)} → ${n.port(a.sell)} · ${t(a.end === 'store' ? 'corp.store' : 'corp.sell')}`
    case 'round':
      return `${t(a.work === 'pirates' ? 'corp.combat' : 'corp.expedition')} · ${n.port(a.base)}`
    case 'haul':
      return a.to ? `${t('corp.haul')} · ${n.port(a.to)}` : t('corp.haul')
    case 'sail':
      return a.to ? `${t('corp.sailing')} · ${n.port(a.to)}` : t('corp.sailing')
    case 'land':
      return `${n.good(a.good)} · ${n.region(a.region)}`
    case 'none':
      return t('corp.idle')
  }
}

/** A row's served figure, formatted (the figure's word is its accessible name). */
export function figureWord(f: WorkerFigure): { word: TKey; text: string } {
  switch (f.key) {
    case 'runs':
      return { word: 'corp.runs', text: `×${formatInt(f.value)}` }
    case 'earned':
      return { word: 'corp.earned', text: formatDucatsDelta(f.value) }
    case 'left':
      return { word: 'corp.left', text: formatInt(f.value) }
    case 'units':
      return { word: 'corp.units', text: formatInt(f.value) }
    case 'trip':
      return { word: 'corp.trip', text: formatRealShort(f.value * 1000) }
    case 'xp':
      return { word: 'corp.xp', text: formatInt(f.value) }
  }
}

/** Served rates as the row and the sheets draw them, each null where the server serves none (`basis` none; a null figure).
 *  WORK THAT BRINGS GOODS TO STORAGE AND MOVES NO COIN (the land party: net 0, basis terms) HAS NO COIN FIGURE: it is said in goods an
 *  hour (the served `items_per_hour`) and XP an hour, never "0 / h". The figures are the server's: only their words are made here. */
export function rateWords(r: WorkerRates | null, t: (key: TKey, vars?: Record<string, string | number>) => string): { coin: string | null; goods: string | null; xp: string | null } {
  if (!r || r.basis === 'none') return { coin: null, goods: null, xp: null }
  const goods = r.itemsPerHour !== null && r.itemsPerHour > 0 ? r.itemsPerHour : null
  const noCoin = r.perHour === null || (r.perHour === 0 && (goods !== null || r.basis === 'terms'))
  return {
    coin: noCoin ? null : t('corp.perHour', { n: formatDucatsDelta(r.perHour!) }),
    goods: goods !== null ? t('corp.goodsHour', { n: formatFixed(goods, goods < 100 ? 1 : 0) }) : null,
    xp: r.xpPerHour !== null ? t('corp.xpHour', { n: formatInt(r.xpPerHour) }) : null,
  }
}

/** The Land's names for HQ (world.land of Mining, the read the Land tab keeps): lit for her company, else null. world.workers and
 *  world.actions serve a land's CODE; its name is this catalogue's. */
export function useCorpLand(): { land: LitLand | null; loading: boolean } {
  const read = useServedRead<LandView>('land:mining', () => worldLand('mining'), { name: 'worldLand' })
  const v = read.view
  return { land: v && v.enabled && v.company ? v : null, loading: read.loading }
}

/** Her workers, from world.workers(); `ready` once it has answered (so the list is ordered once, on what is true). */
export function useWorkers(): { rows: WorkerRow[]; jobs: LitJobs | null; land: LitLand | null; ready: boolean; names: ActionNames } {
  const fleets = useWorld((s) => s.fleets)
  const portByCode = useWorld((s) => s.portByCode)
  const goodByCode = useWorld((s) => s.goodByCode)
  const read = useWorkersRead()
  const served = litWorkers(read.view)
  const awayRead = useAwayReport()
  const away = litAway(awayRead.view)
  const jobs = useMemo<LitJobs | null>(() => (away ? new Map(away.jobs.map((j) => [j.fleet, j])) : null), [away])
  const { land } = useCorpLand()
  const rows = useMemo(() => workerRows(served?.workers ?? [], fleets, jobs), [served, fleets, jobs])
  const names = useMemo<ActionNames>(
    () => ({
      good: (code) => properName('good', code, goodByCode[code]?.name ?? code),
      port: (code) => portNameOf(portByCode, code),
      region: (code) => (land ? (land.regions[code ?? land.home.region] ?? code ?? land.home.name) : (code ?? '')),
    }),
    [goodByCode, portByCode, land],
  )
  return { rows, jobs, land, ready: !read.loading && !awayRead.loading, names }
}
