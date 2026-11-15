import { useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore, type ReactNode } from 'react'
import { Button, Empty, Skeleton, useBackLayer } from '../../components/ui'
import { cmdBattleEnd, worldBattleTicks, worldFight } from '../../lib/rpc'
import type { BattleEndReceipt, BattleRead, BattleTicksRead, RpcResult, TickAbilityCode, TickTimeline } from '../../lib/rpc'
import { formatInt } from '../../lib/format'
import { useT } from '../../lib/i18n'
import { FightLog } from '../FightLog'
import { parseFightLog } from '../fightLines'
import { BattleLog } from './BattleLog'
import { BattleStage } from './BattleStage'
import { BAR_CODES, cooldownAt, lastTick, playableTimeline, readEvents, stateAt, tickClock, type BattleEvent } from './timeline'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE BATTLE SCREEN (0435, docs/design/tick-combat.md 9 and 11; owner 2026-11-15: a wide battle screen, ships enlarged,
// circling, every detail in the log, no "wait a minute then wait more").
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Opened from the red circle on the map (the map passes its Join bar through `actions`, drawn in the header). A wide
// overlay: full width on a desk, the whole glass on a phone.
// THE DATA is one read, `world.battle_ticks(battle)`: the whole fight is on it as a timeline (the server ran it at the
// open). PLAYBACK runs it tick by tick (600 ms) from the server's tick now, so a reader who opens late jumps to where the
// fight is; Replay plays it again from tick 0. While it is fought the read is asked again every 10 s, and a new timeline
// (a re-run: `k` changed) is swapped in at the same tick (the past is the same by construction, section 10). When the
// playback reaches the end of a battle still FIGHTING it asks `cmd.battle_end` ONCE and reads once more, for the loot.
// AN OLD BATTLE (`ticks` null: fought round by round) is drawn with its sides, its result and the round log
// (`world.fight`, the FightLog the map's sheet draws).
// THE ACTION BAR shows the eight abilities with the cooldown sweeps of the reader's side (or the side set upon): slice 1
// is watch-only, so every button is disabled (slice 2, `cmd.battle_act`, presses them).

const POLL_MS = 10_000

/** Where the screen's data comes from: the server, or (the /ui/battle gallery and its spec) a fixture. */
export interface BattleSource {
  read: (battleId: string) => Promise<RpcResult<BattleTicksRead>>
  end: (battleId: string) => Promise<RpcResult<BattleEndReceipt>>
  old: (battleId: string) => Promise<RpcResult<BattleRead>>
}

const SERVER: BattleSource = { read: worldBattleTicks, end: cmdBattleEnd, old: worldFight }

const motionQuery = () => (typeof window === 'undefined' ? null : window.matchMedia('(prefers-reduced-motion: reduce)'))
function useReducedMotion(): boolean {
  return useSyncExternalStore(
    (cb) => {
      const q = motionQuery()
      q?.addEventListener('change', cb)
      return () => q?.removeEventListener('change', cb)
    },
    () => motionQuery()?.matches ?? false,
    () => false,
  )
}

/** The battle screen. `actions` (the map's Join bar) is drawn in the header. */
export function BattleScreen({ battleId, onClose, actions }: { battleId: string; onClose: () => void; actions?: ReactNode }) {
  return <BattleScreenFrom source={SERVER} battleId={battleId} onClose={onClose} actions={actions} />
}

/** The same screen over any source (the gallery feeds it a fixture). */
export function BattleScreenFrom({ source, battleId, onClose, actions }: { source: BattleSource; battleId: string; onClose: () => void; actions?: ReactNode }) {
  const t = useT()
  useBackLayer(onClose)
  const [read, setRead] = useState<BattleTicksRead | null>(null)
  const [failed, setFailed] = useState(false)
  // the device time at which tick 0 began: the server's time into the fight at the first read, laid on this device's clock
  const [origin, setOrigin] = useState<number | null>(null)

  const apply = useCallback((r: RpcResult<BattleTicksRead>) => {
    if (!r.ok || !r.value.on) {
      setFailed(true)
      return null
    }
    const v = r.value
    const into = v.started_at && v.now ? Date.parse(v.now) - Date.parse(v.started_at) : 0
    const at = Date.now() - (Number.isFinite(into) ? Math.max(0, into) : 0)
    setOrigin((o) => o ?? at)
    setRead((old) => {
      // the same timeline (same k) keeps its object, so playback does not restart
      if (old?.ticks && v.ticks && old.ticks.k === v.ticks.k) return { ...v, ticks: old.ticks }
      return v
    })
    return v
  }, [])
  const load = useCallback(() => source.read(battleId).then(apply), [source, battleId, apply])

  useEffect(() => {
    let live = true
    void source.read(battleId).then((r) => {
      if (live) apply(r)
    })
    return () => {
      live = false
    }
  }, [source, battleId, apply])

  // asked again while it is fought: a re-run (a join) comes in as a new k
  const fighting = read?.status === 'FIGHTING'
  useEffect(() => {
    if (!fighting) return
    const id = window.setInterval(() => void load(), POLL_MS)
    return () => window.clearInterval(id)
  }, [fighting, load])

  const tl = useMemo(() => playableTimeline(read?.ticks), [read?.ticks])

  return (
    <div
      className="fixed inset-0 z-[70] flex flex-col bg-app text-ink lg:inset-x-0 lg:inset-y-[4vh] lg:rounded-sheet lg:shadow-2xl"
      role="dialog"
      aria-modal="true"
      aria-label={t('battle.title')}
      data-testid="battle-screen"
    >
      <BattleHeader read={read} onClose={onClose} actions={actions} />
      {failed ? (
        <Empty className="m-4">{t('battle.noBattle')}</Empty>
      ) : !read ? (
        <div className="flex flex-1 flex-col gap-3 p-4" aria-label={t('battle.loading')}>
          <Skeleton className="h-2/3 w-full" />
          <Skeleton className="h-10 w-full" />
        </div>
      ) : tl && origin !== null ? (
        <TickBattle read={read} tl={tl} origin={origin} source={source} battleId={battleId} reload={load} />
      ) : (
        <OldBattle read={read} source={source} battleId={battleId} />
      )}
    </div>
  )
}

function BattleHeader({ read, onClose, actions }: { read: BattleTicksRead | null; onClose: () => void; actions?: ReactNode }) {
  const t = useT()
  return (
    <header className="flex flex-wrap items-center gap-x-3 gap-y-2 px-4 py-3">
      <h2 className="text-t-title">{t('battle.title')}</h2>
      {read?.kind && <span className="text-t-caption text-ink-muted">{t(read.kind === 'RAID' ? 'fight.raid' : 'fight.battle')}</span>}
      <div className="ml-auto flex flex-wrap items-center gap-2">
        {actions}
        <Button size="sm" onClick={onClose} data-testid="battle-close">
          {t('battle.close')}
        </Button>
      </div>
    </header>
  )
}

/** The sides' display names: the first fleet of each side, else the side's word. Side 0 = DEFENDER. */
function sideNamesOf(read: BattleTicksRead, t: ReturnType<typeof useT>): [string, string] {
  const name = (side: 'DEFENDER' | 'ATTACKER', word: string) => {
    const fleets = (read.sides ?? []).filter((s) => s.side === side)
    return fleets.length > 0 ? fleets.map((f) => f.name).join(', ') : word
  }
  return [name('DEFENDER', t('fight.sideD')), name('ATTACKER', t('fight.sideA'))]
}

/** Playback: a clock in fractional ticks, from the server's time into the fight at the read (live) or from 0 (replay). */
function usePlayback(tl: TickTimeline, start: number, endTick: number) {
  const ms = tl.ms
  // the device time at which tick 0 began: the FIRST read's, so a later read never moves the clock; Replay resets it
  const origin = useRef(start)
  const stop = endTick + 3
  const clock = useCallback(() => Math.min(stop, Math.max(0, (Date.now() - origin.current) / ms)), [ms, stop])
  const [tick, setTick] = useState(0)
  const [run, setRun] = useState(0)

  useEffect(() => {
    let raf = 0
    let last = -1
    const frame = () => {
      const k = Math.floor(clock())
      if (k !== last) {
        last = k
        setTick(k)
      }
      if (k < stop) raf = requestAnimationFrame(frame)
    }
    raf = requestAnimationFrame(frame)
    return () => cancelAnimationFrame(raf)
  }, [clock, stop, run])

  const replay = useCallback(() => {
    origin.current = Date.now()
    setTick(0)
    setRun((r) => r + 1)
  }, [])
  return { tick, clock, replay }
}

function TickBattle({
  read,
  tl,
  origin,
  source,
  battleId,
  reload,
}: {
  read: BattleTicksRead
  tl: TickTimeline
  /** the device time at which tick 0 began, from the first read */
  origin: number
  source: BattleSource
  battleId: string
  reload: () => Promise<BattleTicksRead | null>
}) {
  const t = useT()
  const reduced = useReducedMotion()
  const events = useMemo(() => readEvents(tl), [tl])
  const endTick = useMemo(() => lastTick(tl, events), [tl, events])
  const { tick, clock, replay } = usePlayback(tl, origin, endTick)
  const shown = Math.min(tick, endTick)
  const state = useMemo(() => stateAt(tl, events, shown), [tl, events, shown])
  const names = sideNamesOf(read, t)

  // THE END: once, when playback reaches it and the battle is still open on the server; then one read for the loot
  const asked = useRef(false)
  const [closing, setClosing] = useState(false)
  useEffect(() => {
    if (asked.current || tick < endTick || read.status !== 'FIGHTING') return
    asked.current = true
    setClosing(true)
    void source
      .end(battleId)
      .then(() => reload())
      .finally(() => setClosing(false))
  }, [tick, endTick, read.status, source, battleId, reload])

  // whose bar the action row shows: the reader's own side, else the side set upon
  const mineSide = (read.sides ?? []).find((s) => s.mine || s.fleet === read.mine)?.side === 'ATTACKER' ? 1 : 0

  const outcome = state.outcome ?? tl.out
  const result = read.result ?? null
  const endWords = (
    <>
      <div className="text-t-title" data-testid="battle-outcome" data-outcome={outcome}>
        {t(`battle.out_${outcome}` as never)}
      </div>
      {state.boarded?.surrender && <div className="text-t-label text-danger">{t('battle.surrendered')}</div>}
      {result?.loot ? <div className="text-t-label text-accent">{t('battle.loot', { n: formatInt(result.loot) })}</div> : null}
      {result?.crew_lost ? <div className="text-t-label text-ink-muted">{t('battle.crewLost', { n: formatInt(result.crew_lost) })}</div> : null}
      {closing && <div className="text-t-caption text-ink-faint">{t('battle.closing')}</div>}
    </>
  )

  return (
    <div className="flex min-h-0 flex-1 flex-col lg:flex-row" data-motion={reduced ? 'reduced' : 'full'} data-tick={shown} data-testid="battle-body">
      <div className="flex shrink-0 flex-col lg:min-h-0 lg:flex-[2] lg:shrink">
        <FuryRow state={state} names={names} />
        <div className="relative min-h-[42vh] flex-1 lg:min-h-[14rem]">
          <BattleStage tl={tl} events={events} state={state} tick={shown} clock={clock} reduced={reduced} endWords={endWords} />
        </div>
        <div className="flex items-center gap-2 px-4 pt-2 text-t-caption text-ink-muted">
          <span className="tabular-nums" data-testid="battle-clock">
            {tickClock(shown, tl.ms)} / {tickClock(endTick, tl.ms)}
          </span>
          <span className="ml-auto">{tick >= endTick ? t('battle.end') : t('battle.live')}</span>
          <Button size="sm" onClick={replay} data-testid="battle-replay">
            {t('battle.replay')}
          </Button>
        </div>
        <ActionBar tl={tl} state={state} side={mineSide} tick={shown} events={events} />
      </div>
      <section className="flex min-h-40 flex-1 flex-col px-4 pb-4 lg:min-h-0 lg:max-w-[26rem]">
        <h3 className="py-2 text-t-label text-ink-muted">{t('battle.log')}</h3>
        <div className="min-h-0 flex-1 overflow-y-auto">
          <BattleLog tl={tl} events={events} tick={shown} sideNames={names} result={result} />
        </div>
      </section>
    </div>
  )
}

function FuryRow({ state, names }: { state: ReturnType<typeof stateAt>; names: [string, string] }) {
  const t = useT()
  return (
    <div className="grid grid-cols-2 gap-4 px-4 pb-2">
      {([0, 1] as const).map((s) => {
        const sd = state.sides[s]
        const hull = state.ships[s].reduce((n, x) => n + x.hull, 0)
        const max = state.ships[s].filter((x) => x.up).reduce((n, x) => n + x.ship.m, 0)
        const running = sd.runFrom !== null && sd.rollAt === null
        const braced = sd.bracedUntil > state.tick
        return (
          <div key={s} className={`flex min-w-0 flex-col gap-1 ${s === 1 ? 'items-end text-right' : ''}`} data-testid={`battle-side-${s}`}>
            <div className="flex max-w-full flex-wrap items-baseline gap-x-2 text-t-label">
              <span className={`break-words font-semibold ${s === 0 ? 'text-info' : 'text-danger'}`}>{names[s]}</span>
              <span className="text-t-caption text-ink-muted">{t(s === 0 ? 'fight.sideD' : 'fight.sideA')}</span>
              {sd.escaped && <span className="text-t-caption text-success">{t('battle.escaped')}</span>}
              {running && <span className="text-t-caption text-warning">{t('battle.running')}</span>}
              {braced && <span className="text-t-caption text-info">{t('battle.braced')}</span>}
            </div>
            <div className="text-t-caption text-ink-muted tabular-nums">
              {t('battle.hull')} {formatInt(Math.round(hull))}
              {max > 0 ? ` / ${formatInt(Math.round(max))}` : ''}
            </div>
            <div className="flex w-full items-center gap-2" title={t('battle.fury')}>
              <span className="text-t-caption text-accent">{t('battle.fury')}</span>
              <div className="h-2 flex-1 overflow-hidden rounded-chip bg-surface-2">
                <div
                  className="h-full rounded-chip bg-accent transition-[width] duration-300"
                  style={{ width: `${Math.max(0, Math.min(100, sd.fury))}%` }}
                  data-testid={`battle-fury-${s}`}
                  data-fury={Math.round(sd.fury)}
                />
              </div>
              <span className="w-8 text-t-caption tabular-nums">{Math.round(sd.fury)}</span>
            </div>
          </div>
        )
      })}
    </div>
  )
}

function ActionBar({ tl, state, side, tick, events }: { tl: TickTimeline; state: ReturnType<typeof stateAt>; side: 0 | 1; tick: number; events: BattleEvent[] }) {
  const t = useT()
  const sd = state.sides[side]
  const litNow = new Set<TickAbilityCode>(events.filter((e) => e.kind === 'use' && e.s === side && e.t === tick).map((e) => (e as { code: TickAbilityCode }).code))
  return (
    <div className="grid grid-cols-4 gap-2 px-4 py-2 sm:grid-cols-8" data-testid="battle-actions" title={t('battle.soon')}>
      {BAR_CODES.map((code) => {
        const cd = cooldownAt(tl, sd, code, tick)
        const deg = Math.round(cd.share * 360)
        return (
          <button
            key={code}
            type="button"
            disabled
            data-code={code}
            data-lit={litNow.has(code) ? '1' : '0'}
            className="relative min-h-11 overflow-hidden rounded-control bg-surface-2 px-1 py-2 text-t-caption text-ink-muted disabled:cursor-not-allowed data-[lit='1']:bg-accent-soft data-[lit='1']:text-accent"
          >
            {deg > 0 && (
              <span
                aria-hidden="true"
                className="absolute inset-0"
                style={{ background: `conic-gradient(color-mix(in srgb, var(--color-bg) 55%, transparent) ${deg}deg, transparent 0deg)` }}
              />
            )}
            <span className="relative">{t(`battle.ab_${code}`)}</span>
          </button>
        )
      })}
    </div>
  )
}

function OldBattle({ read, source, battleId }: { read: BattleTicksRead; source: BattleSource; battleId: string }) {
  const t = useT()
  const [old, setOld] = useState<BattleRead | null>(null)
  useEffect(() => {
    let live = true
    void source.old(battleId).then((r) => {
      if (live && r.ok) setOld(r.value)
    })
    return () => {
      live = false
    }
  }, [source, battleId])
  const names = sideNamesOf(read, t)
  const log = old ? parseFightLog(old.log, { open: true }) : null
  const outcome = read.result?.outcome
  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto px-4 pb-4" data-testid="battle-old">
      <div className="text-t-caption text-ink-muted">{t('battle.oldBattle')}</div>
      <div className="grid grid-cols-2 gap-4">
        {names.map((n, s) => (
          <div key={s} className={s === 1 ? 'text-right' : ''}>
            <div className={`break-words text-t-body ${s === 0 ? 'text-info' : 'text-danger'}`}>{n}</div>
            <div className="text-t-caption text-ink-muted">{t(s === 0 ? 'fight.sideD' : 'fight.sideA')}</div>
          </div>
        ))}
      </div>
      {outcome && (
        <div className="text-t-title" data-testid="battle-outcome" data-outcome={outcome}>
          {t(`battle.out_${outcome}` as never) || outcome}
        </div>
      )}
      {read.result?.loot ? <div className="text-t-label text-accent">{t('battle.loot', { n: formatInt(read.result.loot) })}</div> : null}
      {log && <FightLog log={log} loss={null} watch />}
    </div>
  )
}
