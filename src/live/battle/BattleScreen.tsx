import { useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore, type ReactNode } from 'react'
import { Button, Empty, Skeleton, useBackLayer } from '../../components/ui'
import { cmdBattleEnd, worldBattleTicks, worldFight } from '../../lib/rpc'
import type { BattleEndReceipt, BattleRead, BattleShipCard, BattleTicksRead, RpcResult, TickAbilityCode, TickTimeline } from '../../lib/rpc'
import { BATTLE_ACT_REFUSALS, cmdBattleAct, type BattleActReceipt } from '../../lib/rpc/battleAct'
import { formatInt } from '../../lib/format'
import { useT } from '../../lib/i18n'
import { FightLog } from '../FightLog'
import { parseFightLog } from '../fightLines'
import { BattleLog } from './BattleLog'
import { BattleStage } from './BattleStage'
import { eventLine, resultLine } from './lines'
import { sideLevel } from './shipCards'
import { ShipsPanel } from './ShipsPanel'
import { BAR_CODES, barLock, cooldownAt, lastTick, playableTimeline, readEvents, runChanceAt, stateAt, type BarLock, type BattleEvent } from './timeline'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE BATTLE SCREEN (0435, docs/design/tick-combat.md 9 and 11; owner 2026-11-15: a wide battle screen, ships enlarged,
// circling, every detail in the log, no "wait a minute then wait more").
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Opened from the red circle on the map (the map passes its Join button through `actions`, drawn beside Log). A wide
// sheet over a dark backdrop.
// IT CLOSES FOUR WAYS (owner 2026-11-15: "after i press combat to view, i can't close it"): the big ✕ at the top right,
// Escape, a press on the backdrop, and the browser's Back (the screen puts one step on the history when it opens, and every
// close takes that step back, so Back never leaves the map). The map draws it BESIDE the chart's surface, never in it: in
// it, the surface took the press on Close for its own gesture and the button never heard a click.
// THE VIEW IS SMALL ON PURPOSE (the owner: "too much words. simplify all"): each side's name with its hull bar and a thin
// Fury bar, the stage, ONE status line (./lines.ts), and Log (the short lines, shut until pressed). The end is one line.
// THE DATA is one read, `world.battle_ticks(battle)`: the whole fight is on it as a timeline (the server ran it at the
// open). PLAYBACK runs it tick by tick (600 ms) from the server's tick now, so a reader who opens late jumps to where the
// fight is; Replay plays it again from tick 0. While it is fought the read is asked again every 10 s, and a new timeline
// (a re-run: `k` changed) is swapped in at the same tick (the past is the same by construction, section 10). When the
// playback reaches the end of a battle still FIGHTING it asks `cmd.battle_end` ONCE and reads once more, for the loot.
// AN OLD BATTLE (`ticks` null: fought round by round) is drawn with its sides, its result and the round log
// (`world.fight`, the FightLog the map's sheet draws).
// THE ACTION BAR is drawn ONLY for her own fleet in a battle still fought (0439, slice 2); a watcher sees none. Eight
// icons with one word each and the cooldown sweeps of her side: a button is grey while its
// cooldown sweeps, while her bar lacks its Fury (the cost lit when she has it), while she runs (only Brace and Patch), or when
// it is not hers to order (Pay: only the ship set upon; Run: only a ship that began the fight). A press (or the keys 1-8 on
// a desk) asks `cmd.battle_act` for the next tick; the answer is the re-run timeline, swapped in at the same tick (no jump:
// the past is the same). A refusal shows its short word under the bar.
// EACH SIDE'S SHIPS (0450; owner 2026-11-16: "in fight, i want to see levels, their stats, their crew state, equipments ...
// fighting graphics (ships), make it smaller, and fight scene more wider"): under each side's name, "Lv 5 · Ships 4" opens
// that side's ships (./ShipsPanel.tsx: level, class, hull, crew, guns, the fight's stats, what is fitted, her captains; the
// figures frozen on the battle sheet). The side set upon on the left, the side that closed on the right; open on a desk,
// shut on a phone until pressed. The sheet is nearly the whole window on a desk, the stage has its full width, and the
// ships on it are drawn at six tenths (./BattleStage.tsx). THE RUN BUTTON SAYS ITS CHANCE (the server's `rc`).

const POLL_MS = 10_000

/** Where the screen's data comes from: the server, or (the /ui/battle gallery and its spec) a fixture. */
export interface BattleSource {
  read: (battleId: string) => Promise<RpcResult<BattleTicksRead>>
  end: (battleId: string) => Promise<RpcResult<BattleEndReceipt>>
  old: (battleId: string) => Promise<RpcResult<BattleRead>>
  /** Her side's commander acts (0439); absent: the bar is watch-only. */
  act?: (battleId: string, fleetId: string, code: TickAbilityCode, tick: number) => Promise<RpcResult<BattleActReceipt>>
}

const SERVER: BattleSource = { read: worldBattleTicks, end: cmdBattleEnd, old: worldFight, act: cmdBattleAct }

/** How long a refusal's word stays under the bar. */
const REFUSAL_MS = 3_000

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

/** The battle screen. `actions` (the map's Join button) is drawn beside Log. */
export function BattleScreen({ battleId, onClose, actions }: { battleId: string; onClose: () => void; actions?: ReactNode }) {
  return <BattleScreenFrom source={SERVER} battleId={battleId} onClose={onClose} actions={actions} />
}

/** The same screen over any source (the gallery feeds it a fixture). */
export function BattleScreenFrom({ source, battleId, onClose, actions }: { source: BattleSource; battleId: string; onClose: () => void; actions?: ReactNode }) {
  const t = useT()
  const close = useCloseWays(onClose)
  useBackLayer(close)
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
      // the same timeline (same k) keeps its object, so playback does not restart; a read older than an act's answer keeps the newer
      if (old?.ticks && v.ticks && old.ticks.k >= v.ticks.k) return { ...v, ticks: old.ticks }
      return v
    })
    return v
  }, [])
  const load = useCallback(() => source.read(battleId).then(apply), [source, battleId, apply])
  // an act's answer: the re-run timeline, in place of the old one at the same tick
  const swap = useCallback((ticks: TickTimeline, resolvesAt: string | undefined) => {
    setRead((old) => (old ? { ...old, ticks, resolves_at: resolvesAt ?? old.resolves_at } : old))
  }, [])

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
      className="fixed inset-0 z-[70] bg-black/70"
      data-testid="battle-backdrop"
      onClick={(e) => {
        if (e.target === e.currentTarget) close()
      }}
    >
      <div
        className="absolute inset-x-0 bottom-0 top-10 flex flex-col overflow-hidden rounded-t-sheet bg-app text-ink shadow-2xl lg:inset-x-[1vw] lg:inset-y-[2vh] lg:rounded-sheet"
        role="dialog"
        aria-modal="true"
        aria-label={t('battle.title')}
        data-testid="battle-screen"
      >
        <button
          type="button"
          onClick={close}
          aria-label={t('battle.close')}
          data-testid="battle-close"
          className="absolute right-2 top-2 z-10 grid size-12 place-items-center rounded-full bg-surface-2 text-2xl leading-none text-ink shadow-lg hover:bg-accent-soft"
        >
          <span aria-hidden="true">✕</span>
        </button>
        {failed ? (
          <Empty className="m-4 mr-16">{t('battle.noBattle')}</Empty>
        ) : !read ? (
          <div className="flex flex-1 flex-col gap-3 p-4 pt-16" aria-label={t('battle.loading')}>
            <Skeleton className="h-2/3 w-full" />
            <Skeleton className="h-10 w-full" />
          </div>
        ) : tl && origin !== null ? (
          <TickBattle read={read} tl={tl} origin={origin} source={source} battleId={battleId} reload={load} swap={swap} actions={actions} />
        ) : (
          <OldBattle read={read} source={source} battleId={battleId} />
        )}
      </div>
    </div>
  )
}

/** THE WAYS OUT. Opening puts one step on the browser's history; Back takes it and closes. Every other close (✕, Escape,
 *  the backdrop) takes that same step back, so the history is left as it was and Back after a close leaves nothing open. */
function useCloseWays(onClose: () => void): () => void {
  const closeRef = useRef(onClose)
  useEffect(() => {
    closeRef.current = onClose
  })
  useEffect(() => {
    const state = window.history.state as { bvBattle?: boolean } | null
    if (!state?.bvBattle) window.history.pushState({ ...(state ?? {}), bvBattle: true }, '')
    const onPop = () => closeRef.current()
    window.addEventListener('popstate', onPop)
    return () => window.removeEventListener('popstate', onPop)
  }, [])
  return useCallback(() => {
    if ((window.history.state as { bvBattle?: boolean } | null)?.bvBattle) window.history.back()
    else closeRef.current()
  }, [])
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
  swap,
  actions,
}: {
  read: BattleTicksRead
  tl: TickTimeline
  /** the device time at which tick 0 began, from the first read */
  origin: number
  source: BattleSource
  battleId: string
  reload: () => Promise<BattleTicksRead | null>
  swap: (ticks: TickTimeline, resolvesAt: string | undefined) => void
  actions?: ReactNode
}) {
  const t = useT()
  const reduced = useReducedMotion()
  const [logOpen, setLogOpen] = useState(false)
  // each side's ships: open on a desk, shut on a phone until its line is pressed
  const [shipsOpen, setShipsOpen] = useState<[boolean, boolean]>(() => {
    const wide = typeof window !== 'undefined' && window.matchMedia('(min-width: 1024px)').matches
    return [wide, wide]
  })
  const toggleShips = useCallback((s: 0 | 1) => setShipsOpen((o) => (s === 0 ? [!o[0], o[1]] : [o[0], !o[1]])), [])
  const events = useMemo(() => readEvents(tl), [tl])
  const endTick = useMemo(() => lastTick(tl, events), [tl, events])
  const { tick, clock, replay } = usePlayback(tl, origin, endTick)
  const shown = Math.min(tick, endTick)
  const state = useMemo(() => stateAt(tl, events, shown), [tl, events, shown])
  const names = sideNamesOf(read, t)

  // THE END: once, when playback reaches it and the battle is still open on the server; then one read for the loot
  const asked = useRef(false)
  useEffect(() => {
    if (asked.current || tick < endTick || read.status !== 'FIGHTING') return
    asked.current = true
    void source.end(battleId).then(() => reload())
  }, [tick, endTick, read.status, source, battleId, reload])

  // whose bar the action row shows: the reader's own side, else the side set upon
  const mineSide = (read.sides ?? []).find((s) => s.mine || s.fleet === read.mine)?.side === 'ATTACKER' ? 1 : 0
  const act = useActions({ read, tl, state, side: mineSide, tick: shown, endTick, clock, source, battleId, reload, swap })

  const outcome = state.outcome ?? tl.out
  const result = read.result ?? null
  // THE END, one line: "Plundered · 1,200 gold", "Escaped", "Driven off", "Sunk"
  const endWords = (
    <div className="text-t-title" data-testid="battle-outcome" data-outcome={outcome}>
      {resultLine(t, outcome, result, state)}
    </div>
  )
  // THE ONE STATUS LINE: the newest event, said short; the end's line stands on the stage instead
  const newest = state.ended ? null : (events.findLast((e) => e.t <= shown) ?? null)
  const status = newest ? eventLine(newest, { t, tl, events }, true, result, state) : ''

  return (
    <div className="flex min-h-0 flex-1 flex-col lg:flex-row" data-motion={reduced ? 'reduced' : 'full'} data-tick={shown} data-testid="battle-body">
      <div className="flex min-h-0 flex-1 flex-col">
        <SideRow state={state} names={names} cards={read.ships} open={shipsOpen} onToggle={toggleShips} />
        {(shipsOpen[0] || shipsOpen[1]) && (
          <div className="grid max-h-[28vh] shrink-0 gap-x-4 gap-y-2 overflow-y-auto px-4 pb-2 lg:max-h-[38vh] lg:grid-cols-2" data-testid="battle-ships">
            {([0, 1] as const).map((s) => (
              <div key={s} className="min-w-0 empty:hidden lg:empty:block">
                {shipsOpen[s] && <ShipsPanel side={s} ships={state.ships[s]} cards={s === 0 ? read.ships?.a : read.ships?.b} />}
              </div>
            ))}
          </div>
        )}
        <div className="relative min-h-[30vh] flex-1 lg:min-h-[12rem]">
          <BattleStage tl={tl} events={events} state={state} tick={shown} clock={clock} reduced={reduced} endWords={endWords} sides={read.sides} />
        </div>
        <div className="flex min-h-14 flex-wrap items-center gap-2 px-4 py-2">
          <div className="min-w-0 flex-1 break-words text-t-title" role="status" data-testid="battle-status">
            {status}
          </div>
          {tick >= endTick && (
            <button
              type="button"
              onClick={replay}
              aria-label={t('battle.replay')}
              data-testid="battle-replay"
              className="grid size-11 place-items-center rounded-full bg-surface-2 text-xl leading-none text-ink hover:bg-accent-soft"
            >
              <span aria-hidden="true">↻</span>
            </button>
          )}
          {actions}
          <Button size="sm" onClick={() => setLogOpen((o) => !o)} aria-expanded={logOpen} data-testid="battle-log-toggle">
            {t('battle.log')}
          </Button>
        </div>
        {act && <ActionBar tl={tl} state={state} side={mineSide} tick={shown} events={events} act={act} />}
      </div>
      {logOpen && (
        <section className="max-h-[28vh] shrink-0 overflow-y-auto px-4 pb-4 lg:max-h-none lg:w-[20rem] lg:pt-16">
          <BattleLog tl={tl} events={events} tick={shown} result={result} state={state} />
        </section>
      )}
    </div>
  )
}

/** Each side: its name, its hull bar, under it a thin Fury bar, and the line that opens its ships ("Lv 5 · Ships 4"). */
function SideRow({
  state,
  names,
  cards,
  open,
  onToggle,
}: {
  state: ReturnType<typeof stateAt>
  names: [string, string]
  cards: { a: BattleShipCard[]; b: BattleShipCard[] } | undefined
  open: [boolean, boolean]
  onToggle: (s: 0 | 1) => void
}) {
  const t = useT()
  return (
    <div className="grid grid-cols-2 gap-4 pb-1 pl-4 pr-16 pt-3">
      {([0, 1] as const).map((s) => {
        const sd = state.sides[s]
        const up = state.ships[s].filter((x) => x.up)
        const hull = up.reduce((n, x) => n + Math.max(0, x.hull), 0)
        const max = up.reduce((n, x) => n + x.ship.m, 0)
        const pct = max > 0 ? Math.max(0, Math.min(100, (hull / max) * 100)) : 0
        const lv = sideLevel(s === 0 ? cards?.a : cards?.b)
        const n = formatInt(state.ships[s].length)
        return (
          <div key={s} className="flex min-w-0 flex-col gap-1">
            <div className="flex min-w-0 flex-col gap-1" data-testid={`battle-side-${s}`}>
              <span className={`break-words text-t-label font-semibold ${s === 0 ? 'text-info' : 'text-danger'}`}>{names[s]}</span>
              <div className="h-3 overflow-hidden rounded-chip bg-surface-2" role="img" aria-label={`${t('battle.hull')} ${Math.round(pct)}%`}>
                <div
                  className={`h-full rounded-chip transition-[width] duration-300 ${pct > 50 ? 'bg-success' : pct > 25 ? 'bg-warning' : 'bg-danger'}`}
                  style={{ width: `${pct}%` }}
                  data-testid={`battle-side-hp-${s}`}
                  data-pct={Math.round(pct)}
                />
              </div>
              <div className="h-1 overflow-hidden rounded-chip bg-surface-2" role="img" aria-label={`${t('battle.fury')} ${Math.round(sd.fury)}`}>
                <div
                  className="h-full rounded-chip bg-accent transition-[width] duration-300"
                  style={{ width: `${Math.max(0, Math.min(100, sd.fury))}%` }}
                  data-testid={`battle-fury-${s}`}
                  data-fury={Math.round(sd.fury)}
                />
              </div>
            </div>
            <button
              type="button"
              onClick={() => onToggle(s)}
              aria-expanded={open[s]}
              data-testid="battle-ships-toggle"
              data-side={s}
              className="flex min-h-8 items-center gap-1 self-start rounded-control px-1 text-t-caption text-ink-muted hover:bg-surface-2 hover:text-ink"
            >
              <span>{lv !== null ? t('battle.shipsOf', { lv: formatInt(lv), n }) : t('fight.shipsN', { n })}</span>
              <span aria-hidden="true">{open[s] ? '▴' : '▾'}</span>
            </button>
          </div>
        )
      })}
    </div>
  )
}

/** The bar's icons: one an ability, read at a glance; its one word stands under it. */
const ABILITY_ICON: Record<TickAbilityCode, string> = { BS: '💥', CH: '⛓️', RK: '🎯', GR: '🍇', BR: '🛡️', PT: '🔧', RN: '💨', PY: '💰' }

/** What her own fleet may do from the bar (null: a watcher, a closed battle, or no door). */
interface ActControl {
  locks: Record<TickAbilityCode, BarLock>
  /** a press is on its way, or her own last act is under the spam cap (one a gcd) */
  waiting: boolean
  refusal: string | null
  press: (code: TickAbilityCode) => void
}

type ActRefusalKey = `battle.act_${(typeof BATTLE_ACT_REFUSALS)[number] | 'E_OTHER'}`

/** The dictionary key of a refusal's short word: its own for every code the contract names, else the one fallback. */
function actRefusalKey(code: string): ActRefusalKey {
  return (BATTLE_ACT_REFUSALS as readonly string[]).includes(code) ? (`battle.act_${code}` as ActRefusalKey) : 'battle.act_E_OTHER'
}

/** Her fleet's bar (0439): the locks for the next tick, the press (and the keys 1-8), the refusal's word. */
function useActions({
  read,
  tl,
  state,
  side,
  tick,
  endTick,
  clock,
  source,
  battleId,
  reload,
  swap,
}: {
  read: BattleTicksRead
  tl: TickTimeline
  state: ReturnType<typeof stateAt>
  side: 0 | 1
  tick: number
  endTick: number
  clock: () => number
  source: BattleSource
  battleId: string
  reload: () => Promise<BattleTicksRead | null>
  swap: (ticks: TickTimeline, resolvesAt: string | undefined) => void
}): ActControl | null {
  const mine = read.mine ? ((read.sides ?? []).find((s) => s.fleet === read.mine) ?? null) : null
  const doAct = source.act
  const live = !!doAct && !!mine && read.status === 'FIGHTING' && !state.ended && tick < endTick
  const [busy, setBusy] = useState(false)
  const [lastAt, setLastAt] = useState(-1_000)
  const [refusal, setRefusal] = useState<string | null>(null)
  const setUpon = mine?.side === 'DEFENDER' && mine.how === 'OPENED'
  const opened = mine?.how === 'OPENED'
  const sd = state.sides[side]
  const locks = useMemo(
    () => Object.fromEntries(BAR_CODES.map((c) => [c, barLock(tl, sd, c, tick, { setUpon, opened })])) as Record<TickAbilityCode, BarLock>,
    [tl, sd, tick, setUpon, opened],
  )
  const waiting = busy || tick < lastAt + (tl.gcd || 3)
  const fleet = mine?.fleet ?? null

  useEffect(() => {
    if (!refusal) return
    const id = window.setTimeout(() => setRefusal(null), REFUSAL_MS)
    return () => window.clearTimeout(id)
  }, [refusal])

  const press = useCallback(
    (code: TickAbilityCode) => {
      if (!doAct || !fleet || busy) return
      const now = Math.floor(clock())
      setBusy(true)
      setRefusal(null)
      void doAct(battleId, fleet, code, now + 1)
        .then((r) => {
          if (!r.ok) {
            setRefusal(r.refusal.code)
            return
          }
          setLastAt(now)
          const next = playableTimeline(r.value.ticks)
          if (next) swap(next, r.value.resolves_at)
          else void reload()
        })
        .finally(() => setBusy(false))
    },
    [doAct, fleet, busy, clock, battleId, swap, reload],
  )

  // the keys 1-8 (a desk): the bar's order; never while typing, never with a modifier
  useEffect(() => {
    if (!live) return
    const onKey = (e: KeyboardEvent) => {
      if (e.ctrlKey || e.metaKey || e.altKey || e.repeat || !/^[1-8]$/.test(e.key)) return
      const el = e.target instanceof HTMLElement ? e.target : null
      if (el && (el.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName))) return
      const code = BAR_CODES[Number(e.key) - 1]
      e.preventDefault()
      if (!waiting && locks[code] === 'ready') press(code)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [live, waiting, locks, press])

  if (!live) return null
  return { locks, waiting, refusal, press }
}

function ActionBar({
  tl,
  state,
  side,
  tick,
  events,
  act,
}: {
  tl: TickTimeline
  state: ReturnType<typeof stateAt>
  side: 0 | 1
  tick: number
  events: BattleEvent[]
  act: ActControl
}) {
  const t = useT()
  const sd = state.sides[side]
  const litNow = new Set<TickAbilityCode>(events.filter((e) => e.kind === 'use' && e.s === side && e.t === tick).map((e) => (e as { code: TickAbilityCode }).code))
  return (
    <div className="px-4 pb-3">
      <div className="grid grid-cols-4 gap-2 sm:grid-cols-8" data-testid="battle-actions">
        {BAR_CODES.map((code, i) => {
          const cd = cooldownAt(tl, sd, code, tick)
          const deg = Math.round(cd.share * 360)
          const cost = Number(tl.ab?.[code]?.cost) || 0
          const lock = act.locks[code]
          // 0450: what her run would roll now, the server's own figure
          const chance = code === 'RN' ? runChanceAt(tl, side, tick) : null
          return (
            <button
              key={code}
              type="button"
              disabled={act.waiting || lock !== 'ready'}
              onClick={() => act.press(code)}
              aria-keyshortcuts={String(i + 1)}
              data-code={code}
              data-lit={litNow.has(code) ? '1' : '0'}
              data-lock={lock}
              data-afford={sd.fury >= cost ? '1' : '0'}
              className={`relative flex min-h-14 flex-col items-center justify-center gap-0.5 overflow-hidden rounded-control bg-surface-2 px-1 py-1 text-t-caption text-ink enabled:hover:bg-accent-soft disabled:cursor-not-allowed data-[lit='1']:bg-accent-soft data-[lit='1']:text-accent ${
                lock === 'fury' || lock === 'role' || lock === 'running' ? 'opacity-40' : ''
              }`}
            >
              {deg > 0 && (
                <span
                  aria-hidden="true"
                  className="absolute inset-0"
                  style={{ background: `conic-gradient(color-mix(in srgb, var(--color-bg) 55%, transparent) ${deg}deg, transparent 0deg)` }}
                />
              )}
              <span aria-hidden="true" className="relative text-xl leading-none">
                {ABILITY_ICON[code]}
              </span>
              <span className="relative">
                {t(`battle.ab_${code}`)}
                {chance !== null && (
                  <span className="tabular-nums" data-testid="battle-run-chance" data-chance={chance}>
                    {' '}
                    {formatInt(chance)}%
                  </span>
                )}
              </span>
            </button>
          )
        })}
      </div>
      {act.refusal && (
        <div className="pt-1 text-t-caption text-danger" role="status" data-testid="battle-act-refusal" data-code={act.refusal}>
          {t(actRefusalKey(act.refusal))}
        </div>
      )}
    </div>
  )
}

/** An old round-by-round battle (`ticks` null): who against whom, how it ended in one line, its rounds behind Log. */
function OldBattle({ read, source, battleId }: { read: BattleTicksRead; source: BattleSource; battleId: string }) {
  const t = useT()
  const [old, setOld] = useState<BattleRead | null>(null)
  const [logOpen, setLogOpen] = useState(false)
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
    <div className="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto px-4 pb-4 pt-3" data-testid="battle-old">
      <div className="grid grid-cols-2 gap-4 pr-12">
        {names.map((n, s) => (
          <div key={s} className={`break-words text-t-label font-semibold ${s === 0 ? 'text-info' : 'text-danger'}`}>
            {n}
          </div>
        ))}
      </div>
      {outcome && (
        <div className="text-t-title" data-testid="battle-outcome" data-outcome={outcome}>
          {resultLine(t, outcome, read.result ?? null)}
        </div>
      )}
      {log && (
        <div>
          <Button size="sm" onClick={() => setLogOpen((o) => !o)} aria-expanded={logOpen} data-testid="battle-log-toggle">
            {t('battle.log')}
          </Button>
        </div>
      )}
      {log && logOpen && <FightLog log={log} loss={null} watch />}
    </div>
  )
}
