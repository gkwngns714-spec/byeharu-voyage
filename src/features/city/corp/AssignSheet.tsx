import { useCallback, useMemo, useRef, useState } from 'react'
import { create } from 'zustand'
import { Bar, Button, Countdown, DetailPage, Figure, Icon, Note, Row, Segmented, Skeleton, Stepper, Tile, TileField, goodIcon } from '../../../components/ui'
import { openHq, type HqAsk } from '../../../app/hqPlace'
import { useShellState } from '../../../app/shellState'
import { formatDucats, formatDucatsDelta, formatInt, formatRealShort, formatRelative, instantMs } from '../../../lib/format'
import { useT } from '../../../lib/i18n'
import { cmdLandHome, cmdLandSend, type FleetJobParams, type FleetView, type Refusal, type WorkerAction as ServedAction } from '../../../lib/rpc'
import { clearFleetJob, setFleetJob, useJobEdits } from '../../../live/useAwayReport'
import { litRounds, useRounds } from '../../../live/useRounds'
import { litRoles, useShipRoles } from '../../../live/useShipRoles'
import { litActions, useActionsRead, useWorkEdits, type LitActions } from '../../../live/useWorkers'
import { useWorld } from '../../../live/worldStore'
import { RoleControl } from '../board/RoleControl'
import { WorkerFixButton } from '../../../live/FixButton'
import { Foot, FootLine, Step } from './assignParts'
import { RoundAssign } from './RoundAssign'
import { RoundCard } from './RoundCard'
import { PARTY, actionWord, figureWord, rateWords, servedId, stateWord, useWorkers, type ActionNames, type WorkerRow } from './workerRows'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE ONE ASSIGN SHEET, AND A WORKER'S SHEET (docs/design/hq-corp-2026-11-24.md B3, C3; 0496)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Assign gives ONE worker her work, through the door that exists for her kind. WHAT IT OFFERS IS world.actions(worker)'s ANSWER, read
// ONCE when the sheet opens (live/useWorkers.ts): each option in the one shape, only what the server would take, with its figures.
// THE SHEET WORKS NOTHING OUT. A run's units, its cost, what it leaves, its time and its coin an hour are drawn as served; the press
// sends the option's own `job` (cmd.set_fleet_job) or `action` (cmd.land_send).
//   a fleet    THE RUNS from where she lies (or is bound for), best coin an hour first (the served `per_hour`). Each is priced for the
//              units her purse, the quay's stock and the day's allowance let her buy, so no run is offered that she cannot pay for.
//              A RUN SET TO REPEAT READS ITS DAY'S COIN AN HOUR (the served `day`: every run after the first is priced into the runs
//              before it, until the day's allowance stops her), which can be far under one run's profit, or a loss: so the foot says
//              one run's profit AND the hour's, and how many runs a day there are.
//              0492, where the server offers it: BRING HOME in place of a sale (the served `store` options: stored in the home
//              warehouse), and ONCE / REPEAT / a count of runs (`times`; the door's own switch, see `useHomeDoor`).
//              TRADE NEARBY (0498, where the server offers it: `sea:near`) is the FIRST choice: the best paying sale near her each
//              run, home when nothing pays. No rate is served for it, so none is drawn.
//              Or Best run = the served `sea:best` (the run the server picks each time; no rate is served for it); or, where the Land
//              is lit, Haul home = cmd.set_fleet_job(fleet, 'land') (world.actions serves no haul option: the door is as it was).
//   the party  the jobs of the Land the server would take now (a job she has no level for is not offered), each with its served
//              units a trip, its trip and its experience an hour.
// A door shut for every option (`closed`: a standing route, the party out, dark) says so in the server's words, and nothing is offered.
// A READ THAT TOOK TOO LONG (`closed` E_SLOW: the server's last resort, never a shorter list) says so in its plain words with ONE press,
// Try again, which asks world.actions once more.
// The figures and the press stand in a foot that is always there, so choosing never moves the press; while the read is on its way the
// press waits. A refusal is the server's own words, in a place that is always there. Assigned, the sheet closes and her row shows the
// new action.
// A worker's sheet says her action, its bar, her served rates, what it did (the served runs and coin; the party's terms), and Change
// (this sheet) and Stop (cmd.clear_fleet_job / cmd.land_home).
// Both of a fleet's sheets carry her hulls' role chips (0485, `FleetRoles`), which stood on the deleted fleet rows.
// THE CLIENT SHIPS AFTER 0496, so the reads this sheet made before it are deleted here: world.good_board (a run's profit),
// world.buy_capacity (what she can buy where she lies), the quay's market (its goods), and world.land's jobs. With them went the
// "over purse" mark: it stood on a quote the server could not cap at a harbour she did not lie at, and no such quote is drawn now.
// NOT DRAWN, because it does not work yet: Estates (0499).

type AssignAsk = Extract<HqAsk, { sheet: 'assign' }>

/** The step back that closes the sheet (useBackLayer: the close comes through the one door). */
const stepBack = () => window.history.back()

/** A served coin an hour, toned by its sign. */
function Rate({ perHour, text }: { perHour: number; text: string }) {
  return (
    <span className={`tabular-nums ${perHour < 0 ? 'text-danger' : 'text-success'}`} data-testid="corp-assign-rate" data-per-hour={perHour}>
      {text}
    </span>
  )
}

export function AssignSheet({ ask, onClose }: { ask: AssignAsk; onClose: () => void }) {
  const t = useT()
  const fleet = useWorld((s) => s.fleets.find((f) => f.id === ask.worker) ?? null)
  const landLit = useWorld((s) => s.snapshot?.config.land_enabled === true)
  const { names } = useWorkers()
  // THE ONE READ OF THE SHEET, asked once when it opens
  const read = useActionsRead(servedId(ask.worker))
  const view = litActions(read.view)
  // COMBAT, EXPEDITION OR TRADING (slide 5): the served works of rounds (0518 on) give a fleet the first two; dark, trading is the sheet as it was
  const rounds = litRounds(useRounds(fleet?.id ?? null, fleet !== null).view)
  const kinds = (['combat', 'sea'] as const).filter((k) => rounds?.works.some((w) => w.kind === k))
  const [asked, setAct] = useState<'trading' | 'combat' | 'sea'>('trading')
  const act = fleet !== null && asked !== 'trading' && kinds.includes(asked) ? asked : 'trading'
  const title = ask.worker === PARTY ? t('corp.party') : (fleet?.name ?? '')
  return (
    <DetailPage title={t('corp.assign')} word={title} onClose={onClose} data-testid="hq-sheet-assign">
      {fleet !== null && kinds.length > 0 && (
        <Step word={t('corp.action')}>
          <Segmented<'trading' | 'combat' | 'sea'>
            segments={[{ id: 'trading', label: t('corp.trading') }, ...kinds.map((k) => ({ id: k, label: t(k === 'combat' ? 'corp.combat' : 'corp.expedition') }))]}
            value={act}
            onChange={setAct}
            label={t('corp.action')}
            columns={(kinds.length + 1) as 2 | 3}
          />
        </Step>
      )}
      {fleet !== null && act !== 'trading' && rounds ? (
        <RoundAssign key={act} fleet={fleet} kind={act} lit={rounds} names={names} onDone={stepBack} />
      ) : !view ? (
        read.loading || read.view === null ? (
          <Skeleton className="h-28 w-full" />
        ) : (
          <Note tone="neutral">{t('corp.noRun')}</Note>
        )
      ) : view.closed?.code === 'E_SLOW' ? (
        <div data-testid="corp-assign-slow">
          <Note tone="neutral" data-testid="corp-assign-closed">
            {view.closed.sentence}
          </Note>
          <Button variant="primary" className="mt-3 w-full" busy={read.stale} disabled={read.stale} onClick={read.again} data-testid="corp-assign-retry">
            {t('corp.tryAgain')}
          </Button>
        </div>
      ) : ask.worker === PARTY ? (
        <LandAssign key={read.tries} view={view} names={names} />
      ) : fleet ? (
        <SeaAssign key={read.tries} ask={ask} fleet={fleet} view={view} names={names} haul={landLit} />
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

/** 0492'S DOOR, AS THE CLIENT KNOWS IT. A run count is the server's switch (`assign_home_enabled`), and no read serves that switch
 *  today. So a count is offered until the door itself says it is not open (`E_NOT_IN_USE`); from then on, for this visit, it is not
 *  drawn. A snapshot that one day serves the switch settles it without a press. The plain choice (Sell, Repeat) sends no count, so it
 *  is never refused for one. BRING HOME needs no such guess: it is offered where world.actions serves it. */
const useHomeDoor = create<{ shut: boolean; close: () => void }>()((set) => ({ shut: false, close: () => set({ shut: true }) }))

type Mode = 'near' | 'fixed' | 'best' | 'haul'
type End = 'sell' | 'store'
type Runs = 'repeat' | 'once' | 'count'

/** The most runs the count's slider reaches (the server takes up to 999). */
const MAX_RUNS = 99

/** A served time of one completion, in the game's short real-time words. */
const timeOf = (a: ServedAction): string => (a.interval_s !== null ? formatRealShort(a.interval_s * 1000) : '')

/** The served options in the order of the served coin an hour, the best first (one without a rate last); ties keep the served order. */
function byPerHour(options: readonly ServedAction[]): ServedAction[] {
  return options
    .map((o, i) => ({ o, i }))
    .sort((a, b) => (b.o.per_hour ?? -Infinity) - (a.o.per_hour ?? -Infinity) || a.i - b.i)
    .map((x) => x.o)
}

function SeaAssign({ ask, fleet, view, names, haul }: { ask: AssignAsk; fleet: FleetView; view: LitActions; names: ActionNames; haul: boolean }) {
  const t = useT()
  const goodByCode = useWorld((s) => s.goodByCode)
  const served = useWorld((s) => s.snapshot?.config.assign_home_enabled)
  const shut = useHomeDoor((s) => s.shut)
  const countOpen = served ?? !shut
  const key = `assign:${fleet.id}`
  const pending = useJobEdits((s) => s.pending !== null)
  const refused = useJobEdits((s) => s.refused[key] ?? null)
  // the choice the last press sent: its refusal stands only while that choice does
  const [tried, setTried] = useState<string | null>(null)

  // WHAT THE SERVER OFFERS HER NOW
  const best = view.options.find((o) => o.id === 'sea:best') ?? null
  const near = view.options.find((o) => o.id === 'sea:near') ?? null
  const runs = useMemo(() => byPerHour(view.options.filter((o) => o.id.startsWith('sea:fixed:') && o.end !== 'store')), [view.options])
  const loads = useMemo(() => view.options.filter((o) => o.id.startsWith('sea:fixed:') && o.end === 'store'), [view.options])

  const [endAsked, setEnd] = useState<End>('sell')
  // a board card (or a link) names its run: the sheet opens on it when the server offers that very run
  const asked = ask.good && ask.buy && ask.sell ? `sea:fixed:${ask.good}:${ask.buy}:${ask.sell}:sell` : null
  // the sheet opens on Trade nearby where the server offers it, unless a card named a run
  const [mode, setMode] = useState<Mode>(() => (near && !(asked && view.options.some((o) => o.id === asked)) ? 'near' : 'fixed'))
  const [picked, setPicked] = useState<string | null>(() => (asked && view.options.some((o) => o.id === asked) ? asked : null))
  const [runsAsked, setRuns] = useState<Runs>('repeat')
  const [count, setCount] = useState(2)
  const end: End = loads.length > 0 ? endAsked : 'sell'
  const many: Runs = countOpen ? runsAsked : 'repeat'
  const list = end === 'store' ? loads : runs
  const option = mode === 'fixed' ? (list.find((o) => o.id === picked) ?? null) : null

  // the run a card filled in may stand far down the list: it is brought into view once, when the list first stands
  const shown = useRef(false)
  const showFilled = useCallback((el: HTMLButtonElement | null) => {
    if (!el || shown.current) return
    shown.current = true
    el.scrollIntoView({ block: 'center' })
  }, [])

  const times = many === 'repeat' ? null : many === 'once' ? 1 : count
  const choiceOf = (n: number | null) => `${mode}:${picked}:${end}:${n}`
  const choice = choiceOf(times)
  const refusal = !pending && tried === choice ? refused : null
  const send = async () => {
    let ok = false
    if (mode === 'near' && near?.job) ok = await setFleetJob(fleet.id, near.job.kind, near.job.params as FleetJobParams, key)
    else if (mode === 'best' && best?.job) ok = await setFleetJob(fleet.id, best.job.kind, best.job.params as FleetJobParams, key)
    else if (mode === 'haul') ok = await setFleetJob(fleet.id, 'land', {}, key)
    else if (option?.job) {
      // the served job as it stands; a count rides only when she chose one (0492), and a counted sale names its end
      const counted = times === null ? {} : end === 'store' ? { times } : { end, times }
      ok = await setFleetJob(fleet.id, option.job.kind, { ...(option.job.params as FleetJobParams), ...counted }, key)
    }
    if (ok) return stepBack()
    // the door says counts are not open: they leave the sheet, and its sentence stands over the plain choice
    if (useJobEdits.getState().refused[key]?.code === 'E_NOT_IN_USE' && times !== null) {
      useHomeDoor.getState().close()
      setTried(choiceOf(null))
    } else setTried(choice)
  }
  const ready = view.closed === null && (mode === 'haul' || (mode === 'near' ? near !== null : mode === 'best' ? best !== null : option !== null))
  const modes = (near ? 1 : 0) + 2 + (haul ? 1 : 0)
  const rate = option && many === 'repeat' && option.per_hour !== null ? option.per_hour : null

  return (
    <div data-testid="corp-assign-sea" data-fleet={fleet.id} data-home-open={countOpen} data-at={view.at ?? undefined} data-options={view.options.length}>
      {view.closed ? (
        <Note tone="danger" data-testid="corp-assign-closed">
          {view.closed.sentence}
        </Note>
      ) : (
        <>
          <Step word={t('corp.work')}>
            <Segmented<Mode>
              segments={[
                ...(near ? [{ id: 'near' as const, label: t('corp.near') }] : []),
                { id: 'fixed', label: t('corp.trade') },
                { id: 'best', label: t('corp.bestRun') },
                ...(haul ? [{ id: 'haul' as const, label: t('corp.haul') }] : []),
              ]}
              value={mode}
              onChange={setMode}
              label={t('corp.work')}
              columns={modes > 3 ? 2 : (modes as 2 | 3)}
            />
          </Step>
          {mode === 'fixed' && (
            <>
              {loads.length > 0 && (
                <Step word={t('corp.end')}>
                  <Segmented<End>
                    segments={[
                      { id: 'sell', label: t('corp.sell') },
                      { id: 'store', label: t('corp.home') },
                    ]}
                    value={end}
                    onChange={(e) => {
                      setEnd(e)
                      setPicked(null)
                    }}
                    label={t('corp.end')}
                    columns={2}
                  />
                </Step>
              )}
              <Step word={`${t('corp.run')}${view.at ? ` · ${names.port(view.at)}` : ''}`}>
                {list.length === 0 ? (
                  <Note tone="neutral" data-testid="corp-assign-norun">
                    {t('corp.noRun')}
                  </Note>
                ) : (
                  <div className="flex flex-col gap-1" data-testid="corp-assign-runs" data-end={end}>
                    {list.map((o) => {
                      const on = o.id === picked
                      const losing = (o.per_hour ?? o.net ?? 0) < 0
                      return (
                        <button
                          key={o.id}
                          ref={o.id === asked && on ? showFilled : undefined}
                          type="button"
                          aria-pressed={on}
                          onClick={() => setPicked(o.id)}
                          className={`flex min-h-11 w-full items-center justify-between gap-3 rounded-control px-3 text-left transition ${on ? 'bg-accent-soft ring-1 ring-inset ring-accent' : 'bg-surface hover:bg-surface-2'}`}
                          data-testid="corp-assign-run"
                          data-id={o.id}
                          data-good={o.good}
                          data-port={o.sell}
                          data-per-hour={o.per_hour ?? undefined}
                          data-net={o.net ?? undefined}
                          data-units={o.units}
                          data-cost={o.inputs.coin}
                          data-interval={o.interval_s ?? undefined}
                          data-losing={losing}
                        >
                          <span className={`flex min-w-0 items-center gap-2 text-t-body ${losing ? 'text-ink-muted' : 'text-ink'}`}>
                            <Icon name={goodIcon(o.good ?? '', goodByCode[o.good ?? '']?.category ?? '')} size={18} aria-hidden className="shrink-0" />
                            <span className="min-w-0 break-words">{end === 'store' ? names.good(o.good ?? '') : `${names.good(o.good ?? '')} → ${names.port(o.sell ?? '')}`}</span>
                          </span>
                          <span className="flex shrink-0 items-center gap-3 text-t-caption tabular-nums">
                            <span className="text-ink-muted">{timeOf(o)}</span>
                            {end === 'store' ? (
                              <span className="text-ink">{formatInt(o.units ?? 0)}</span>
                            ) : o.per_hour !== null ? (
                              <span className={losing ? 'text-danger' : 'text-success'}>{t('corp.perHour', { n: formatDucatsDelta(o.per_hour) })}</span>
                            ) : null}
                          </span>
                        </button>
                      )
                    })}
                  </div>
                )}
              </Step>
              {countOpen && (
                <Step word={t('corp.count')}>
                  <Segmented<Runs>
                    segments={[
                      { id: 'repeat', label: t('corp.repeat') },
                      { id: 'once', label: t('corp.once') },
                      { id: 'count', label: t('corp.count') },
                    ]}
                    value={many}
                    onChange={setRuns}
                    label={t('corp.count')}
                    columns={3}
                  />
                  {many === 'count' && <Stepper className="mt-2" value={count} onChange={setCount} min={2} max={MAX_RUNS} label={t('corp.count')} data-testid="corp-assign-count" />}
                </Step>
              )}
            </>
          )}
          <FleetRoles fleet={fleet.id} />
        </>
      )}
      <Foot
        refusal={refusal}
        figures={
          view.closed ? null : mode === 'near' && near ? (
            <div data-testid="corp-assign-near" data-id={near.id} data-basis={near.basis} data-within={near.within} data-base={near.base}>
              <FootLine word={actionWord({ kind: 'near', base: near.base ?? null }, t, names)} figure={<span className="text-t-caption text-ink-muted">{t('corp.nearNote')}</span>} />
            </div>
          ) : mode === 'best' ? (
            <FootLine word={t('corp.bestRun')} figure={<span className="text-t-caption text-ink-muted">{t('corp.bestNote')}</span>} />
          ) : mode === 'haul' ? (
            <FootLine word={t('corp.haul')} figure={null} />
          ) : option ? (
            <div
              data-testid="corp-assign-quote"
              data-id={option.id}
              data-end={end}
              data-basis={option.basis}
              data-profit={option.net ?? undefined}
              data-units={option.units}
              data-cost={option.inputs.coin}
              data-interval={option.interval_s ?? undefined}
              data-per-hour={option.per_hour ?? undefined}
              data-day-runs={option.day?.runs}
            >
              <FootLine
                word={actionWord({ kind: 'fixed', good: option.good ?? '', buy: option.buy ?? '', sell: option.sell ?? '', end }, t, names)}
                figure={
                  end === 'store' ? (
                    <span data-testid="corp-assign-stored" title={t('corp.stored')}>
                      <Figure size="figure" tone="ink" value={formatInt(option.units ?? 0)} />
                    </span>
                  ) : (
                    <span data-testid="corp-assign-profit" title={t('corp.profit')}>
                      <Figure size="figure" tone={(option.net ?? 0) < 0 ? 'danger' : 'success'} value={formatDucatsDelta(option.net ?? 0)} />
                    </span>
                  )
                }
              />
              <FootLine
                word={
                  <span className="text-t-caption tabular-nums text-ink-faint">
                    {[end === 'sell' && option.units !== undefined ? `${t('corp.units')} ${formatInt(option.units)}` : null, `${t('corp.cost')} ${formatDucats(option.inputs.coin)}`].filter(Boolean).join(' · ')}
                  </span>
                }
                figure={
                  <span className="text-t-caption tabular-nums text-ink-muted" data-testid="corp-assign-time" title={t('corp.time')}>
                    {timeOf(option)}
                  </span>
                }
              />
              {rate !== null && (
                <FootLine
                  word={
                    <span className="text-t-caption tabular-nums text-ink-faint" data-testid="corp-assign-day">
                      {option.day ? `${t('corp.repeat')} · ${t('corp.aDay', { n: formatInt(option.day.runs) })}` : t('corp.repeat')}
                    </span>
                  }
                  figure={
                    <span className="text-t-caption">
                      <Rate perHour={rate} text={t('corp.perHour', { n: formatDucatsDelta(rate) })} />
                    </span>
                  }
                />
              )}
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

function LandAssign({ view, names }: { view: LitActions; names: ActionNames }) {
  const t = useT()
  const refresh = useWorld((s) => s.refresh)
  const goods = useWorld((s) => s.goodByCode)
  const [picked, setPicked] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  // only what the server would take now, in the served order
  const jobs = view.options.filter((o) => o.action !== undefined)
  const job = jobs.find((o) => o.id === picked) ?? null
  const send = () => {
    if (busy || !job?.action) return
    setBusy(true)
    setRefusal(null)
    void (async () => {
      const r = await cmdLandSend(job.action!)
      if (r.ok) {
        useWorkEdits.getState().touch()
        await refresh()
        stepBack()
      } else setRefusal(r.refusal)
      setBusy(false)
    })()
  }
  const rate = job ? rateWords({ perHour: job.per_hour, xpPerHour: job.xp_per_hour, itemsPerHour: job.items_per_hour, basis: job.basis }, t) : null
  return (
    <div data-testid="corp-assign-land" data-options={jobs.length}>
      {view.closed ? (
        <Note tone="danger" data-testid="corp-assign-closed">
          {view.closed.sentence}
        </Note>
      ) : (
        <Step word={t('corp.job')}>
          {jobs.length === 0 ? (
            <Note tone="neutral" data-testid="corp-assign-norun">
              {t('corp.noRun')}
            </Note>
          ) : (
            <TileField>
              {jobs.map((o) => (
                <Tile
                  key={o.id}
                  tap="whole"
                  state="rest"
                  aria-pressed={o.id === picked}
                  className={o.id === picked ? 'ring-1 ring-inset ring-accent' : ''}
                  mark={<Icon name={goodIcon(o.good ?? '', goods[o.good ?? '']?.category ?? '')} size={22} className="text-accent" />}
                  name={names.good(o.good ?? '')}
                  meta={names.region(o.home ? null : (o.region ?? null))}
                  figure={o.xp_per_hour !== null ? <span className="text-t-label tabular-nums text-ink">{t('corp.xpHour', { n: formatInt(o.xp_per_hour) })}</span> : undefined}
                  onClick={() => {
                    setPicked(o.id)
                    setRefusal(null)
                  }}
                  data-testid="corp-assign-job"
                  data-job={o.action}
                  data-xp-hour={o.xp_per_hour ?? undefined}
                />
              ))}
            </TileField>
          )}
        </Step>
      )}
      <Foot
        refusal={refusal}
        figures={
          job && (
            <div data-testid="corp-assign-terms" data-job={job.action} data-xp-hour={job.xp_per_hour ?? undefined} data-items-hour={job.items_per_hour ?? undefined} data-interval={job.interval_s ?? undefined} data-units={job.outputs.items[0]?.units}>
              <FootLine
                word={actionWord({ kind: 'land', good: job.good ?? '', region: job.home ? null : (job.region ?? null) }, t, names)}
                figure={
                  <span className="text-t-body tabular-nums text-ink" title={t('corp.units')}>
                    {`${t('corp.units')} ${formatInt(job.outputs.items[0]?.units ?? 0)}`}
                  </span>
                }
              />
              <FootLine
                word={
                  <span className="text-t-caption tabular-nums text-ink-faint">
                    <span data-testid="corp-assign-goods">{rate?.goods ?? ''}</span>
                    {rate?.goods && rate?.xp ? ' · ' : ''}
                    <span data-testid="corp-assign-xp">{rate?.xp ?? ''}</span>
                  </span>
                }
                figure={
                  <span className="text-t-caption tabular-nums text-ink-muted" data-testid="corp-assign-trip" title={t('corp.trip')}>
                    {`${t('corp.trip')} ${timeOf(job)}`}
                  </span>
                }
              />
            </div>
          )
        }
        press={
          <Button variant="primary" className="w-full" busy={busy} disabled={busy || !job || view.closed !== null} onClick={send} data-testid="corp-assign-go">
            {t('corp.assign')}
          </Button>
        }
      />
    </div>
  )
}

/** A worker's sheet: her action and its bar, her served rates, what it did, Change and Stop. */
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
        useWorkEdits.getState().touch()
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
  const rate = rateWords(row?.rates ?? null, t)

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
          {(rate.coin !== null || rate.goods !== null || rate.xp !== null) && (
            <Row
              label={t('corp.hourly')}
              value={
                <span className="flex items-center gap-3 tabular-nums" data-testid="corp-sheet-rates" data-basis={row.rates?.basis} data-per-hour={row.rates?.perHour ?? undefined} data-xp-hour={row.rates?.xpPerHour ?? undefined}>
                  {rate.coin !== null && <span className={(row.rates?.perHour ?? 0) < 0 ? 'text-danger' : 'text-success'}>{rate.coin}</span>}
                  {rate.goods !== null && <span>{rate.goods}</span>}
                  {rate.xp !== null && <span className="text-ink-muted">{rate.xp}</span>}
                </span>
              }
            />
          )}
          {[...row.tally, ...row.figures].map((f) => {
            const w = figureWord(f)
            return <Row key={f.key} label={t(w.word)} value={<span className="tabular-nums">{w.text}</span>} />
          })}
          {last && lastAt !== null && last.ok && last.to && last.from !== last.to && (
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
          {row.kind === 'fleet' && <RoundCard fleet={worker} nowMs={nowMs} />}
          {row.kind === 'fleet' && <FleetRoles fleet={worker} />}
          {row.why && (
            <Note tone="danger" data-testid="corp-sheet-why">
              {row.why}
            </Note>
          )}
          {/* 0499: the one press that mends it (Repair at the server's price, Storage); a leg too far is mended by Change, below */}
          {row.fix !== null && row.fix !== 'assign' && (
            <div className="mt-2 flex flex-col gap-2">
              <WorkerFixButton fix={row.fix} worker={worker} className="w-full" />
            </div>
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
