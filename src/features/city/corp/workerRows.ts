import { useMemo } from 'react'
import { fleetSignal } from '../../../domain/fleet'
import { formatDucatsDelta, formatInt, formatRealShort, instantMs } from '../../../lib/format'
import { properName, translateMaybe, type TKey } from '../../../lib/i18n'
import { worldLand, type FleetJobRow, type FleetView, type LandView } from '../../../lib/rpc'
import { litAway, useAwayReport } from '../../../live/useAwayReport'
import { useServedRead } from '../../../live/useServedRead'
import { portNameOf, useWorld } from '../../../live/worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE ONE ADAPTER FROM SERVED READS TO WORKER ROWS (docs/design/hq-corp-2026-11-24.md A2, C1; slice H1)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A WORKER is one "character slot": a fleet (with her captain, if one is seated) or the land party. Each is on ONE action, and HQ lists
// them all on one screen. Every row is made HERE, from three reads that exist today, and nothing is worked out:
//   world.fleets        her fleets: where each is (domain/fleet's one where-rule), the voyage under way and its two served stamps;
//   world.away_report   0481, lit: each fleet's standing job, its state, the runs it started and the coin her fleet made since she last
//                       read the report (dark: null, and no job is drawn);
//   world.land          0455, lit: the party's job, its frozen terms (units a trip, the trip, XP a turn) and when it is home next
//                       (dark: null, and no party row is drawn).
// A JOB'S TALLY (its runs, her fleet's coin since she last read the report) is carried for her SHEET; on HQ's page it stands once, in
// While away, and her row does not repeat it.
// NO RATE IS COMPUTED HERE: coin an hour and XP an hour arrive with 0495's `world.workers()`, and until then a row shows the served
// figures above and no per-hour figure. A progress bar's two ends are served stamps; the row draws between them.

/** The land party's id as a worker (a fleet's is her own id). */
export const PARTY = 'party'

export type WorkerState = 'idle' | 'stopped' | 'working'

/** What a worker is doing, as data: the row and the sheets say it with `actionWord`. */
export type WorkerAction =
  | { kind: 'none' }
  /** 0481 `best`: the server picks her best run each time. */
  | { kind: 'best' }
  /** 0481 `fixed`: one good, bought at one harbour and sold at another (port CODES); 0492 `end` 'store': brought home instead, into
   *  the home warehouse (`sell` is then her home harbour, as served). */
  | { kind: 'fixed'; good: string; buy: string; sell: string; end: 'sell' | 'store' }
  /** 0481 `land`: she carries the Land's goods to a yard. */
  | { kind: 'haul'; to: string | null }
  /** No standing job: a voyage sent by hand, or orders queued in port. */
  | { kind: 'sail'; to: string | null }
  | { kind: 'orders' }
  /** The party's job: the good, and the land it is worked on (null: at home). */
  | { kind: 'land'; good: string; region: string | null }

/** One served figure of a row (never a rate). */
export interface WorkerFigure {
  key: 'runs' | 'earned' | 'left' | 'units' | 'trip' | 'xp'
  value: number
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
  /** Why a stopped job stopped, in the server's words. */
  why: string | null
}

export type LitLand = Extract<LandView, { company: true }>
export type LitJobs = ReadonlyMap<string, FleetJobRow>

function fleetRow(f: FleetView, jobs: LitJobs | null): WorkerRow {
  const job = jobs?.get(f.id) ?? null
  const v = f.voyage
  const from = v ? instantMs(v.departed_at) : null
  const to = v ? instantMs(v.eta) : null
  const bar = from !== null && to !== null && to > from ? { fromMs: from, toMs: to } : null
  const seat = f.ships.flatMap((s) => s.seats?.list ?? []).find((s) => s.captain !== null)?.captain ?? null
  const base = {
    id: f.id,
    kind: 'fleet' as const,
    name: f.name,
    bar,
    assignable: jobs !== null,
    hull: f.ships[0]?.class_code ?? null,
    captain: seat ? { code: seat.code, name: seat.name, grade: seat.grade } : null,
  }
  if (job) {
    const p = job.params
    const action: WorkerAction =
      job.kind === 'best'
        ? { kind: 'best' }
        : job.kind === 'fixed' && p.good && p.buy && p.sell
          ? { kind: 'fixed', good: p.good, buy: p.buy, sell: p.sell, end: p.end === 'store' ? 'store' : 'sell' }
          : job.kind === 'land'
            ? { kind: 'haul', to: p.to ?? null }
            : { kind: 'none' }
    return {
      ...base,
      state: job.state === 'stopped' ? 'stopped' : 'working',
      waiting: job.state === 'waiting',
      action,
      // 0492: a job of a set number of runs says how many are still to start (served)
      figures: typeof p.left === 'number' ? [{ key: 'left', value: p.left }] : [],
      tally: [
        { key: 'runs', value: job.runs },
        { key: 'earned', value: job.earned },
      ],
      // the server's sentence, else its code's plain words (dict/codes.ts); never the code itself
      why: job.state === 'stopped' ? (job.last?.sentence ?? (job.paused ? translateMaybe('en', 'codes', job.paused) : null)) : null,
    }
  }
  // no standing job: where she is, by the one where-rule (domain/fleet `fleetSignal`)
  const signal = fleetSignal(f)
  const state: WorkerState = signal === 'stuck' ? 'stopped' : signal === 'sailing' || f.queue.length > 0 ? 'working' : 'idle'
  const action: WorkerAction = signal === 'sailing' ? { kind: 'sail', to: v?.to ?? null } : state === 'working' ? { kind: 'orders' } : { kind: 'none' }
  return { ...base, state, waiting: false, action, figures: [], tally: [], why: null }
}

function partyRow(land: LitLand): WorkerRow {
  const p = land.party
  const pr = p.progress
  const terms = p.terms
  const out = p.action !== null && terms !== null
  // the trip under way ends at the served `next_home_at` and lasts the frozen terms' `trip`; called home, it is home at `home_at`
  const homeAt = out ? instantMs(pr.state === 'returning' ? pr.home_at : pr.next_home_at) : null
  const fromMs = homeAt === null || !terms ? null : pr.state === 'returning' ? instantMs(land.now) : homeAt - terms.trip * 1000
  return {
    id: PARTY,
    kind: 'party',
    name: null,
    state: !out ? 'idle' : pr.stopped ? 'stopped' : 'working',
    waiting: false,
    action: out && p.good ? { kind: 'land', good: p.good, region: terms.home ? null : p.region } : { kind: 'none' },
    bar: homeAt !== null && fromMs !== null && homeAt > fromMs ? { fromMs, toMs: homeAt } : null,
    figures: out
      ? [
          { key: 'units', value: terms.p },
          { key: 'trip', value: terms.trip },
          { key: 'xp', value: terms.xp },
        ]
      : [],
    tally: [],
    assignable: true,
    hull: null,
    captain: null,
    why: null,
  }
}

/** Every worker of hers, in the served order (her fleets by their founding, then the party). */
export function workerRows(fleets: readonly FleetView[], jobs: LitJobs | null, land: LitLand | null): WorkerRow[] {
  return [...fleets.map((f) => fleetRow(f, jobs)), ...(land ? [partyRow(land)] : [])]
}

const ORDER: Record<WorkerState, number> = { idle: 0, stopped: 1, working: 2 }

/** Idle first, then stopped, then working; inside each, the served order. */
export function sortWorkers(rows: readonly WorkerRow[]): WorkerRow[] {
  return rows
    .map((r, i) => ({ r, i }))
    .sort((a, b) => ORDER[a.r.state] - ORDER[b.r.state] || a.i - b.i)
    .map((x) => x.r)
}

/** The state's word. */
export function stateWord(r: Pick<WorkerRow, 'state' | 'waiting'>): TKey {
  return r.state === 'idle' ? 'corp.idle' : r.state === 'stopped' ? 'corp.stopped' : r.waiting ? 'corp.waiting' : 'corp.working'
}

/** The names an action is said with: a good's, a harbour's and a land's, each the catalogue's. */
export interface ActionNames {
  good: (code: string) => string
  port: (code: string) => string
  region: (code: string | null) => string
}

/** A worker's action in a few words: "Pepper · Lisbon → Setubal · Sell", "Iron · Iberia", "Best run". */
export function actionWord(a: WorkerAction, t: (key: TKey) => string, n: ActionNames): string {
  switch (a.kind) {
    case 'best':
      return t('corp.bestRun')
    case 'fixed':
      return `${n.good(a.good)} · ${n.port(a.buy)} → ${n.port(a.sell)} · ${t(a.end === 'store' ? 'corp.store' : 'corp.sell')}`
    case 'haul':
      return a.to ? `${t('corp.haul')} · ${n.port(a.to)}` : t('corp.haul')
    case 'sail':
      return a.to ? `${t('corp.sailing')} · ${n.port(a.to)}` : t('corp.sailing')
    case 'orders':
      return t('corp.orders')
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

/** The Land's one read for HQ (world.land of Mining, the read the Land tab keeps): lit for her company, else null. */
export function useCorpLand(): { land: LitLand | null; loading: boolean } {
  const read = useServedRead<LandView>('land:mining', () => worldLand('mining'), { name: 'worldLand' })
  const v = read.view
  return { land: v && v.enabled && v.company ? v : null, loading: read.loading }
}

/** Her workers, from the three reads; `ready` once each has answered (so the list is ordered once, on what is true). */
export function useWorkers(): { rows: WorkerRow[]; jobs: LitJobs | null; land: LitLand | null; ready: boolean; names: ActionNames } {
  const fleets = useWorld((s) => s.fleets)
  const portByCode = useWorld((s) => s.portByCode)
  const goodByCode = useWorld((s) => s.goodByCode)
  const awayRead = useAwayReport()
  const away = litAway(awayRead.view)
  const jobs = useMemo<LitJobs | null>(() => (away ? new Map(away.jobs.map((j) => [j.fleet, j])) : null), [away])
  const { land, loading } = useCorpLand()
  const rows = useMemo(() => workerRows(fleets, jobs, land), [fleets, jobs, land])
  const names = useMemo<ActionNames>(
    () => ({
      good: (code) => properName('good', code, goodByCode[code]?.name ?? code),
      port: (code) => portNameOf(portByCode, code),
      region: (code) => (land ? (land.regions[code ?? land.home.region] ?? code ?? land.home.name) : (code ?? '')),
    }),
    [goodByCode, portByCode, land],
  )
  return { rows, jobs, land, ready: !awayRead.loading && !loading, names }
}
