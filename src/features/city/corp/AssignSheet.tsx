import { useCallback, useMemo, useRef, useState, type ReactNode } from 'react'
import { create } from 'zustand'
import { Bar, Button, Chip, Countdown, DetailPage, Figure, GroupHeading, Icon, Note, Row, Segmented, Skeleton, Stepper, Tile, TileField, goodIcon } from '../../../components/ui'
import { openHq, type HqAsk } from '../../../app/hqPlace'
import { useShellState } from '../../../app/shellState'
import { fleetPortCode } from '../../../domain/fleet'
import { tradeRows } from '../../../domain/market'
import { formatDaysReal, formatDucats, formatDucatsDelta, formatInt, formatRealShort, formatRelative, instantMs } from '../../../lib/format'
import { useT } from '../../../lib/i18n'
import { cmdLandHome, cmdLandSend, type FleetView, type LandJob, type Refusal } from '../../../lib/rpc'
import { clearFleetJob, setFleetJob, useJobEdits } from '../../../live/useAwayReport'
import { useGoodBoard } from '../../../live/useDesk'
import { litRoles, useShipRoles } from '../../../live/useShipRoles'
import { usePortMarket } from '../../../live/usePortMarket'
import { useWorld } from '../../../live/worldStore'
import { RoleControl } from '../board/RoleControl'
import { PARTY, actionWord, figureWord, stateWord, useWorkers, type ActionNames, type LitLand, type WorkerRow } from './workerRows'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE ONE ASSIGN SHEET, AND A WORKER'S SHEET (docs/design/hq-corp-2026-11-24.md B3, C3; slice H1)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Assign gives ONE worker her work, through the door that exists for her kind, and works nothing out:
//   a fleet    Sea trade: a good, where it is bought and where it is sold = cmd.set_fleet_job(fleet, 'fixed', {good, buy, sell}),
//              quoted before the press by `world.good_board` (the desk's own read: the run's profit, its units, its cost, its time).
//              THE SALE HARBOURS STAND BEST PROFIT FIRST, by the served profit of the run; the losing ones last and muted.
//              0492, where its door is open (`useHomeDoor`): BRING HOME in place of a sale ({good, buy, end: 'store'}: stored in the
//              home warehouse; its quote is the board's own buy row, units and cost), and ONCE / REPEAT / a count of runs (`times`).
//              Or Best run = cmd.set_fleet_job(fleet, 'best'), the run the server picks each time; or, where the Land is lit, Haul
//              home = cmd.set_fleet_job(fleet, 'land'). These three were chips on a fleet row and a card; they are set here only.
//   the party  a job of the Land = cmd.land_send(action), with the terms `world.land` serves for it (units a trip, the trip, XP).
// The figures and the press stand in a foot that is always there, so choosing never moves the press; while the quote is on its way
// the press waits. A refusal is the server's own words, in a place that is always there. Assigned, the sheet closes and her row
// shows the new action.
// A worker's sheet says her action, its bar, what it did (the served runs and coin; the party's terms), and Change (this sheet) and
// Stop (cmd.clear_fleet_job / cmd.land_home).
// Both of a fleet's sheets carry her hulls' role chips (0485, `FleetRoles`), which stood on the deleted fleet rows.
// NOT DRAWN, because it does not work yet: Estates (0499), coin an hour (0495), a bring-home run's time (no read serves it whole).

type AssignAsk = Extract<HqAsk, { sheet: 'assign' }>

/** The step back that closes the sheet (useBackLayer: the close comes through the one door). */
const stepBack = () => window.history.back()

/** A step's heading and its choices. */
function Step({ word, children }: { word: string; children: ReactNode }) {
  return (
    <div className="mb-4">
      <GroupHeading>{word}</GroupHeading>
      {children}
    </div>
  )
}

/** One line of the foot: what it is, and its figure at the edge. */
function FootLine({ word, figure }: { word: ReactNode; figure: ReactNode }) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <span className="min-w-0 break-words text-t-body text-ink">{word}</span>
      <span className="shrink-0">{figure}</span>
    </div>
  )
}

/** The foot: the figures, the refusal's place and the press, standing under the choices on every glass. */
function Foot({ figures, refusal, press }: { figures: ReactNode; refusal: Refusal | null; press: ReactNode }) {
  return (
    <div className="sticky -bottom-6 -mx-gutter bg-bg px-gutter pb-6 pt-3" data-testid="corp-assign-foot">
      <div className="flex min-h-16 flex-col justify-center gap-0.5" data-testid="corp-assign-figures">
        {figures}
      </div>
      <div className="min-h-6">
        {refusal && (
          <Note tone="danger" code={refusal.code} figures={refusal.figures} data-testid="corp-assign-refusal">
            {refusal.sentence}
          </Note>
        )}
      </div>
      {press}
    </div>
  )
}

export function AssignSheet({ ask, onClose }: { ask: AssignAsk; onClose: () => void }) {
  const t = useT()
  const fleet = useWorld((s) => s.fleets.find((f) => f.id === ask.worker) ?? null)
  const { land, jobs, names } = useWorkers()
  const title = ask.worker === PARTY ? t('corp.party') : (fleet?.name ?? '')
  return (
    <DetailPage title={t('corp.assign')} word={title} onClose={onClose} data-testid="hq-sheet-assign">
      {ask.worker === PARTY ? (
        land ? (
          <LandAssign land={land} names={names} />
        ) : (
          <Skeleton className="h-28 w-full" />
        )
      ) : fleet && jobs ? (
        <SeaAssign ask={ask} fleet={fleet} names={names} home={land?.home.port ?? null} haul={land !== null} />
      ) : (
        <Skeleton className="h-28 w-full" />
      )}
    </DetailPage>
  )
}

/** 0485: HER HULLS' ROLES (board/RoleControl.tsx: a hull's three roles as chips, one press each), on both of a fleet's sheets. They
 *  stood on the fleet rows the worker list replaced. Dark (world.ship_roles): nothing is drawn. */
function FleetRoles({ fleet }: { fleet: string }) {
  const roles = litRoles(useShipRoles().view)
  if (!roles) return null
  return (
    <div className="mb-4">
      <RoleControl fleet={fleet} roles={roles} />
    </div>
  )
}

/** How many harbours the Buy at list offers (the board's first, in its own order). */
const HARBOURS = 8

/** 0492'S DOOR, AS THE CLIENT KNOWS IT. Bring home and a run count are the server's switch (`assign_home_enabled`), and no read
 *  serves that switch today. So they are offered until the door itself says they are not open (`E_NOT_IN_USE`); from then on, for
 *  this visit, they are not drawn. A snapshot that one day serves the switch settles it without a press. The plain choice (Sell,
 *  Repeat) sends neither name, so it is never refused for them. */
const useHomeDoor = create<{ shut: boolean; close: () => void }>()((set) => ({ shut: false, close: () => set({ shut: true }) }))

type Mode = 'fixed' | 'best' | 'haul'
type End = 'sell' | 'store'
type Runs = 'repeat' | 'once' | 'count'

/** The most runs the count's slider reaches (the server takes up to 999). */
const MAX_RUNS = 99

function SeaAssign({ ask, fleet, names, home, haul }: { ask: AssignAsk; fleet: FleetView; names: ActionNames; home: string | null; haul: boolean }) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const goodByCode = useWorld((s) => s.goodByCode)
  const served = useWorld((s) => s.snapshot?.config.assign_home_enabled)
  const shut = useHomeDoor((s) => s.shut)
  const homeOpen = served ?? !shut
  const key = `assign:${fleet.id}`
  const pending = useJobEdits((s) => s.pending !== null)
  const refused = useJobEdits((s) => s.refused[key] ?? null)
  // the choice the last press sent: its refusal stands only while that choice does
  const [tried, setTried] = useState<string | null>(null)

  const [mode, setMode] = useState<Mode>('fixed')
  const [buy, setBuy] = useState<string | null>(ask.buy ?? fleetPortCode(fleet))
  const [good, setGood] = useState<string | null>(ask.good ?? null)
  const [sell, setSell] = useState<string | null>(ask.sell ?? null)
  const [endAsked, setEnd] = useState<End>('sell')
  const [runsAsked, setRuns] = useState<Runs>('repeat')
  const [count, setCount] = useState(2)
  const end: End = homeOpen ? endAsked : 'sell'
  const runs: Runs = homeOpen ? runsAsked : 'repeat'

  const buyPort = buy ? (portByCode[buy] ?? null) : null
  const quay = usePortMarket(mode === 'fixed' ? (buyPort?.id ?? null) : null)
  const goods = useMemo(() => tradeRows(quay.market?.goods ?? [], {}, goodByCode).filter((r) => r.buy !== null && r.goodId), [quay.market, goodByCode])
  const goodId = good ? (goodByCode[good]?.id ?? null) : null
  const board = useGoodBoard(mode === 'fixed' ? goodId : null, fleet.id, fleet.version, null, buyPort?.id ?? null)
  const view = board.view && board.view.good === good && !board.stale ? board.view : null
  // THE HARBOURS THAT BUY IT, BEST PROFIT FIRST (each row's profit is the server's, for the whole run): the ones that pay stand in
  // the order of what they leave, and the ones that lose stand last. Nothing is worked out to rank them; no rate is made here.
  const sales = useMemo(
    () =>
      (view?.sell ?? [])
        .filter((r) => r.quoted && r.port !== buy && (r.profit ?? r.net) !== null)
        .map((r) => ({ r, p: r.profit ?? r.net ?? 0 }))
        .sort((a, b) => b.p - a.p),
    [view, buy],
  )
  const buys = (view?.buy ?? []).slice(0, HARBOURS)
  // the sale a card filled in may stand far down a list ordered by profit: it is brought into view once, when the list first stands
  const shown = useRef(false)
  const showFilled = useCallback((el: HTMLButtonElement | null) => {
    if (!el || shown.current) return
    shown.current = true
    el.scrollIntoView({ block: 'center' })
  }, [])
  const sale = sales.find((x) => x.r.port === sell) ?? null
  // bring home: what the run buys at A and what it costs (the board's own `buy` row); it earns nothing until the goods are sold
  const load = (view?.buy ?? []).find((r) => r.port === buy) ?? null
  // the server refuses a run that buys at her home and brings it home (E_SAME_DEST): not offered
  const atHome = home !== null && buy === home

  const times = runs === 'repeat' ? null : runs === 'once' ? 1 : count
  const choiceOf = (e: End, n: number | null) => `${mode}:${good}:${buy}:${e === 'store' ? 'home' : sell}:${e}:${n}`
  const choice = choiceOf(end, times)
  const refusal = !pending && tried === choice ? refused : null
  const send = async () => {
    let ok = false
    if (mode === 'best') ok = await setFleetJob(fleet.id, 'best', {}, key)
    else if (mode === 'haul') ok = await setFleetJob(fleet.id, 'land', {}, key)
    else if (good && buy && (end === 'store' || sell)) {
      // the plain run sends today's three names and nothing else; `end` and `times` ride only when she chose them (0492)
      const counted = times === null ? {} : { times }
      ok = await setFleetJob(fleet.id, 'fixed', end === 'store' ? { good, buy, end, ...counted } : { good, buy, sell: sell!, ...(times === null ? {} : { end }), ...counted }, key)
    }
    if (ok) return stepBack()
    // the door says bring home and counts are not open: they leave the sheet, and its sentence stands over the plain choice
    if (useJobEdits.getState().refused[key]?.code === 'E_NOT_IN_USE' && (end === 'store' || times !== null)) {
      useHomeDoor.getState().close()
      setTried(choiceOf('sell', null))
    } else setTried(choice)
  }
  const ready = mode !== 'fixed' || (end === 'store' ? load !== null && load.units > 0 && !atHome : sale !== null)

  return (
    <div data-testid="corp-assign-sea" data-fleet={fleet.id} data-home-open={homeOpen}>
      <Step word={t('corp.work')}>
        <Segmented<Mode>
          segments={[
            { id: 'fixed', label: t('corp.trade') },
            { id: 'best', label: t('corp.bestRun') },
            ...(haul ? [{ id: 'haul' as const, label: t('corp.haul') }] : []),
          ]}
          value={mode}
          onChange={setMode}
          label={t('corp.work')}
          columns={haul ? 3 : 2}
        />
      </Step>
      {mode === 'fixed' && (
        <>
          <Step word={`${t('corp.buyAt')} · ${buy ? names.port(buy) : ''}`}>
            <div className="flex min-h-11 flex-wrap gap-2" data-testid="corp-assign-buys">
              {buy && !buys.some((r) => r.port === buy) && (
                <Chip on data-testid="corp-assign-buy">
                  {names.port(buy)}
                </Chip>
              )}
              {buys.map((r) => (
                <Chip
                  key={r.port}
                  on={r.port === buy}
                  onClick={() => {
                    if (r.port === buy) return
                    setBuy(r.port)
                    setSell(null)
                  }}
                  data-testid="corp-assign-buy"
                >
                  {names.port(r.port)}
                </Chip>
              ))}
            </div>
          </Step>
          <Step word={t('corp.good')}>
            {quay.market === undefined ? (
              quay.refusal ? (
                <Note tone="danger" code={quay.refusal.code}>
                  {quay.refusal.sentence}
                </Note>
              ) : (
                <Skeleton className="h-11 w-full" />
              )
            ) : (
              <div className="flex flex-wrap gap-2" data-testid="corp-assign-goods">
                {goods.map((g) => (
                  <Chip
                    key={g.code}
                    on={g.code === good}
                    onClick={() => {
                      setGood(g.code)
                      setSell(null)
                    }}
                    data-testid="corp-assign-good"
                  >
                    <Icon name={goodIcon(g.code, g.category ?? '')} size={18} aria-hidden />
                    <span data-good={g.code}>{names.good(g.code)}</span>
                  </Chip>
                ))}
              </div>
            )}
          </Step>
          {good && homeOpen && (
            <Step word={t('corp.end')}>
              <Segmented<End>
                segments={[
                  { id: 'sell', label: t('corp.sell') },
                  { id: 'store', label: t('corp.home') },
                ]}
                value={end}
                onChange={setEnd}
                label={t('corp.end')}
                columns={2}
              />
            </Step>
          )}
          {good && end === 'sell' && (
            <Step word={t('corp.sellAt')}>
              {!view ? (
                <Skeleton className="h-11 w-full" />
              ) : sales.length === 0 ? (
                <Note tone="neutral" data-testid="corp-assign-nosale">
                  {t('corp.noSale')}
                </Note>
              ) : (
                <div className="flex flex-col gap-1" data-testid="corp-assign-sales">
                  {sales.map(({ r, p }) => (
                    <button
                      key={r.port}
                      ref={r.port === ask.sell && r.port === sell ? showFilled : undefined}
                      type="button"
                      aria-pressed={r.port === sell}
                      onClick={() => setSell(r.port)}
                      className={`flex min-h-11 w-full items-center justify-between gap-3 rounded-control px-3 text-left transition ${r.port === sell ? 'bg-accent-soft ring-1 ring-inset ring-accent' : 'bg-surface hover:bg-surface-2'}`}
                      data-testid="corp-assign-sale"
                      data-port={r.port}
                      data-profit={p}
                      data-losing={p < 0}
                    >
                      <span className={`min-w-0 break-words text-t-body ${p < 0 ? 'text-ink-faint' : 'text-ink'}`}>{names.port(r.port)}</span>
                      <span className="flex shrink-0 items-center gap-3 text-t-caption tabular-nums">
                        <span className={p < 0 ? 'text-ink-faint' : 'text-ink-muted'}>{r.days !== null ? formatDaysReal(r.days) : ''}</span>
                        <span className={p < 0 ? 'text-ink-faint' : 'text-success'}>{formatDucatsDelta(p)}</span>
                      </span>
                    </button>
                  ))}
                </div>
              )}
            </Step>
          )}
          {good && end === 'store' && atHome && (
            <Note tone="neutral" data-testid="corp-assign-athome">
              {t('corp.atHome')}
            </Note>
          )}
          {good && homeOpen && (
            <Step word={t('corp.count')}>
              <Segmented<Runs>
                segments={[
                  { id: 'repeat', label: t('corp.repeat') },
                  { id: 'once', label: t('corp.once') },
                  { id: 'count', label: t('corp.count') },
                ]}
                value={runs}
                onChange={setRuns}
                label={t('corp.count')}
                columns={3}
              />
              {runs === 'count' && <Stepper className="mt-2" value={count} onChange={setCount} min={2} max={MAX_RUNS} label={t('corp.count')} data-testid="corp-assign-count" />}
            </Step>
          )}
        </>
      )}
      <FleetRoles fleet={fleet.id} />
      <Foot
        refusal={refusal}
        figures={
          mode === 'best' ? (
            <FootLine word={t('corp.bestRun')} figure={<span className="text-t-caption text-ink-muted">{t('corp.bestNote')}</span>} />
          ) : mode === 'haul' ? (
            <FootLine word={t('corp.haul')} figure={null} />
          ) : end === 'store' && good && buy && load && !atHome ? (
            <div data-testid="corp-assign-quote" data-end="store" data-units={load.units}>
              <FootLine
                word={`${names.good(good)} · ${names.port(buy)} → ${home ? names.port(home) : t('corp.home')} · ${t('corp.store')}`}
                figure={
                  <span data-testid="corp-assign-stored" title={t('corp.stored')}>
                    <Figure size="figure" tone="ink" value={formatInt(load.units)} />
                  </span>
                }
              />
              <FootLine
                word={<span className="text-t-caption tabular-nums text-ink-faint">{`${t('corp.cost')} ${formatDucats(load.cost)}`}</span>}
                figure={<span className="text-t-caption tabular-nums text-ink-muted">{t('corp.units')}</span>}
              />
            </div>
          ) : end === 'sell' && sale ? (
            <div data-testid="corp-assign-quote" data-end="sell" data-profit={sale.p}>
              <FootLine
                word={actionWord({ kind: 'fixed', good: good!, buy: buy!, sell: sale.r.port, end: 'sell' }, t, names)}
                figure={
                  <span data-testid="corp-assign-profit" title={t('corp.profit')}>
                    <Figure size="figure" tone={sale.p < 0 ? 'danger' : 'success'} value={formatDucatsDelta(sale.p)} />
                  </span>
                }
              />
              <FootLine
                word={
                  <span className="text-t-caption tabular-nums text-ink-faint">
                    {[sale.r.units !== null ? `${t('corp.units')} ${formatInt(sale.r.units)}` : null, sale.r.cost !== null ? `${t('corp.cost')} ${formatDucats(sale.r.cost)}` : null].filter(Boolean).join(' · ')}
                  </span>
                }
                figure={
                  <span className="text-t-caption tabular-nums text-ink-muted" data-testid="corp-assign-time" title={t('corp.time')}>
                    {sale.r.days !== null ? formatDaysReal(sale.r.days) : ''}
                  </span>
                }
              />
            </div>
          ) : null
        }
        press={
          <Button variant="primary" className="w-full" busy={pending} disabled={pending || !ready} onClick={() => void send()} data-testid="corp-assign-go" data-end={mode === 'fixed' ? end : undefined} data-times={times ?? undefined}>
            {t('corp.assign')}
          </Button>
        }
      />
    </div>
  )
}

function LandAssign({ land, names }: { land: LitLand; names: ActionNames }) {
  const t = useT()
  const refresh = useWorld((s) => s.refresh)
  const goods = useWorld((s) => s.goodByCode)
  const [job, setJob] = useState<LandJob | null>(null)
  const [busy, setBusy] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  // the jobs she may take now first (the server's `open`), each group in the served order
  const jobs = useMemo(() => [...land.jobs.filter((j) => j.open), ...land.jobs.filter((j) => !j.open)], [land.jobs])
  const send = () => {
    if (busy || !job) return
    setBusy(true)
    setRefusal(null)
    void (async () => {
      const r = await cmdLandSend(job.code)
      if (r.ok) {
        await refresh()
        stepBack()
      } else setRefusal(r.refusal)
      setBusy(false)
    })()
  }
  return (
    <div data-testid="corp-assign-land">
      <Step word={t('corp.job')}>
        <TileField>
          {jobs.map((j) => (
            <Tile
              key={j.code}
              tap="whole"
              state={j.open ? 'rest' : 'muted'}
              aria-pressed={job?.code === j.code}
              className={job?.code === j.code ? 'ring-1 ring-inset ring-accent' : ''}
              mark={<Icon name={goodIcon(j.good, goods[j.good]?.category ?? '')} size={22} className={j.open ? 'text-accent' : 'text-ink-faint'} />}
              name={names.good(j.good)}
              meta={names.region(j.home ? null : j.region)}
              figure={<span className={`text-t-label tabular-nums ${j.open ? 'text-ink' : 'text-ink-faint'}`}>{j.open ? `${formatInt(j.xp)} ${t('corp.xp')}` : t('corp.level', { n: formatInt(j.level) })}</span>}
              onClick={() => {
                setJob(j)
                setRefusal(null)
              }}
              data-testid="corp-assign-job"
              data-job={j.code}
              data-open={j.open}
            />
          ))}
        </TileField>
      </Step>
      <Foot
        refusal={refusal ?? (job && !job.open ? (job.short as Refusal | null) : null)}
        figures={
          job && (
            <div data-testid="corp-assign-terms" data-job={job.code}>
              <FootLine
                word={actionWord({ kind: 'land', good: job.good, region: job.home ? null : job.region }, t, names)}
                figure={
                  <span className="text-t-body tabular-nums text-ink" title={t('corp.units')}>
                    {`${t('corp.units')} ${formatInt(job.p)}`}
                  </span>
                }
              />
              <FootLine
                word={<span className="text-t-caption tabular-nums text-ink-faint">{`${t('corp.turn')} ${formatRealShort(job.a * 1000)} · ${formatInt(job.xp)} ${t('corp.xp')}`}</span>}
                figure={
                  <span className="text-t-caption tabular-nums text-ink-muted" data-testid="corp-assign-trip" title={t('corp.trip')}>
                    {`${t('corp.trip')} ${formatRealShort(job.trip * 1000)}`}
                  </span>
                }
              />
            </div>
          )
        }
        press={
          <Button variant="primary" className="w-full" busy={busy} disabled={busy || !job || !job.open} onClick={send} data-testid="corp-assign-go">
            {t('corp.assign')}
          </Button>
        }
      />
    </div>
  )
}

/** A worker's sheet: her action and its bar, what it did, Change and Stop. */
export function WorkerSheet({ worker, onClose }: { worker: string; onClose: () => void }) {
  const t = useT()
  const { nowMs } = useShellState()
  const { rows, jobs, names } = useWorkers()
  const refresh = useWorld((s) => s.refresh)
  const row: WorkerRow | null = rows.find((r) => r.id === worker) ?? null
  const key = `worker:${worker}`
  const pending = useJobEdits((s) => s.pending !== null)
  const jobRefusal = useJobEdits((s) => s.refused[key] ?? null)
  const [busy, setBusy] = useState(false)
  const [landRefusal, setLandRefusal] = useState<Refusal | null>(null)
  const job = jobs?.get(worker) ?? null
  const last = job?.last ?? null
  const lastAt = last ? instantMs(last.at) : null

  const stop = () => {
    if (worker !== PARTY) {
      void clearFleetJob(worker, key).then((ok) => ok && stepBack())
      return
    }
    if (busy) return
    setBusy(true)
    setLandRefusal(null)
    void (async () => {
      const r = await cmdLandHome()
      if (r.ok) {
        await refresh()
        stepBack()
      } else setLandRefusal(r.refusal)
      setBusy(false)
    })()
  }
  const refusal = worker === PARTY ? landRefusal : jobRefusal
  // Stop works on a standing job, and on a party that is out and not yet called home
  const stoppable = worker === PARTY ? row?.state !== 'idle' : job !== null
  const fill = row?.bar ? Math.max(0, Math.min(100, ((nowMs - row.bar.fromMs) / (row.bar.toMs - row.bar.fromMs)) * 100)) : 0

  return (
    <DetailPage title={row?.name ?? t('corp.party')} word={row ? t(stateWord(row)) : undefined} onClose={onClose} data-testid="hq-sheet-worker">
      {!row ? (
        <Skeleton className="h-28 w-full" />
      ) : (
        <div className="mx-auto w-full max-w-2xl" data-worker={row.id} data-state={row.state}>
          <Row label={<span data-testid="corp-sheet-action">{actionWord(row.action, t, names)}</span>} hairline={false}>
            <Bar pct={fill} tone={row.state === 'stopped' ? 'danger' : 'accent'} label={t('corp.trip')} className="mt-1" figure={row.bar ? <Countdown untilMs={row.bar.toMs} nowMs={nowMs} className="text-t-caption tabular-nums text-ink-muted" /> : undefined} />
          </Row>
          {row.captain && <Row mark={<Icon name="captain" size={20} className="text-accent" />} label={row.captain.name} value={<span className="text-t-caption text-ink-muted">{row.captain.grade}</span>} />}
          {[...row.tally, ...row.figures].map((f) => {
            const w = figureWord(f)
            return <Row key={f.key} label={t(w.word)} value={<span className="tabular-nums">{w.text}</span>} />
          })}
          {last && lastAt !== null && last.ok && last.to && (
            <Row
              label={t('corp.last')}
              value={last.profit !== undefined ? <Figure tone={last.profit < 0 ? 'danger' : 'success'} value={formatDucatsDelta(last.profit)} /> : undefined}
              data-testid="corp-sheet-last"
            >
              <span className="block break-words text-t-caption text-ink-faint">
                {[last.good ? names.good(last.good) : null, last.from ? `${names.port(last.from)} → ${names.port(last.to)}` : names.port(last.to), formatRelative(lastAt, nowMs)].filter(Boolean).join(' · ')}
              </span>
            </Row>
          )}
          {row.kind === 'fleet' && <FleetRoles fleet={worker} />}
          {row.why && (
            <Note tone="danger" data-testid="corp-sheet-why">
              {row.why}
            </Note>
          )}
          <div className="mt-2 min-h-6">
            {refusal && (
              <Note tone="danger" code={refusal.code} figures={refusal.figures} data-testid="corp-sheet-refusal">
                {refusal.sentence}
              </Note>
            )}
          </div>
          <div className={`mt-2 grid gap-2 ${row.kind === 'fleet' ? 'grid-cols-3' : 'grid-cols-2'}`}>
            <Button variant="primary" disabled={!row.assignable || (worker === PARTY && row.state !== 'idle')} onClick={() => openHq({ sheet: 'assign', worker })} data-testid="corp-sheet-change">
              {row.state === 'idle' || (row.kind === 'fleet' && !job) ? t('corp.assign') : t('corp.change')}
            </Button>
            <Button variant="secondary" busy={busy || (pending && worker !== PARTY)} disabled={busy || pending || !stoppable} onClick={stop} data-testid="corp-sheet-stop">
              {t('corp.stop')}
            </Button>
            {row.kind === 'fleet' && (
              <Button variant="secondary" onClick={() => openHq({ sheet: 'fleet', fleet: worker })} data-testid="corp-sheet-ship">
                {t('corp.ship')}
              </Button>
            )}
          </div>
        </div>
      )}
    </DetailPage>
  )
}
