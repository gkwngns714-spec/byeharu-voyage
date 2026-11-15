import { useMemo, useState } from 'react'
import { Button, Empty } from '../../components/ui'
import type { BattleRead, BattleTicksRead, RpcResult, TickAbilityCode, TickEvent, TickTimeline } from '../../lib/rpc'
import { useT } from '../../lib/i18n'
import { BattleScreenFrom, type BattleSource } from '../../live/battle/BattleScreen'

// THE BATTLE SCREEN, FED A FIXTURE (/ui/battle; 0435). Like the gallery: outside sign-in, reads nothing from the world.
// tests/battle.screen.spec.ts hands a timeline in through `window.__BV_BATTLE_FIXTURE__` (written per the contract,
// docs/design/tick-combat.md 9.3) and reads the screen: the hit numbers, the log, the end, and the reduced-motion path.
// The fixture's clock is laid on this device's: the battle began `agoMs` before the first read. `cmd.battle_end` is
// counted in `window.__BV_BATTLE_CALLS__`, and every read after it is the closed battle with its `result`.
// `cmd.battle_act` (0439) is the fixture's own small server: each press is recorded in `__BV_BATTLE_CALLS__.act`; the next
// code of `actRefuse` (if any) refuses it, else the act lands at its tick as a `U` event of her side (Fury by the table) and
// the timeline comes back as k + 1, every event before the tick unchanged.

const ok = <T,>(value: T): RpcResult<T> => ({ ok: true, value })

interface BattleFixture {
  read: BattleTicksRead
  agoMs?: number
  result?: BattleTicksRead['result']
  old?: BattleRead
  /** refusal codes the act door answers, in turn, before it takes an act */
  actRefuse?: string[]
}

interface FixtureWindow {
  __BV_BATTLE_FIXTURE__?: BattleFixture
  __BV_BATTLE_CALLS__?: { read: number; end: number; act: { code: string; tick: number }[] }
}

function fixtureSource(fx: BattleFixture): BattleSource {
  const w = window as unknown as FixtureWindow
  const calls: NonNullable<FixtureWindow['__BV_BATTLE_CALLS__']> = (w.__BV_BATTLE_CALLS__ = { read: 0, end: 0, act: [] })
  const started = Date.now() - (fx.agoMs ?? 0)
  const refuse = [...(fx.actRefuse ?? [])]
  let ticks: TickTimeline | null | undefined = fx.read.ticks
  let closed = false
  return {
    read: async () => {
      calls.read += 1
      const base: BattleTicksRead = { ...fx.read, ticks, started_at: new Date(started).toISOString(), now: new Date().toISOString() }
      return ok(closed ? { ...base, status: 'RESOLVED', result: fx.result ?? null } : base)
    },
    end: async () => {
      calls.end += 1
      closed = true
      return ok({ ok: true as const, status: 'RESOLVED' as const, resolves_at: new Date().toISOString() })
    },
    old: async () => ok(fx.old ?? { on: false }),
    act: async (_battle: string, fleet: string, code: TickAbilityCode, tick: number) => {
      calls.act.push({ code, tick })
      const no = refuse.shift()
      if (no) return { ok: false, refusal: { code: no, sentence: no, fixes: [], source: 'server' } }
      if (!ticks) return { ok: false, refusal: { code: 'E_BATTLE_OVER', sentence: 'E_BATTLE_OVER', fixes: [], source: 'server' } }
      const s = fx.read.sides?.find((x) => x.fleet === fleet)?.side === 'ATTACKER' ? 1 : 0
      const before = ticks.e.filter((e) => e[0] < tick)
      const fury = Number([...before].reverse().find((e) => e[1] === s && e[2] === 'U')?.[4] ?? 0)
      const ab = ticks.ab[code]
      const after = Math.max(0, Math.min(100, fury + (ab?.gain ?? 0) - (ab?.cost ?? 0)))
      const use: TickEvent = [tick, s, 'U', code, after]
      ticks = { ...ticks, k: ticks.k + 1, e: [...before, use, ...ticks.e.filter((e) => e[0] >= tick)] }
      return ok({ battle: fx.read.battle ?? 'fixture', tick, k: ticks.k, resolves_at: new Date(started + (ticks.n + 2) * ticks.ms).toISOString(), ticks })
    },
  }
}

export function BattleGalleryScreen() {
  const t = useT()
  const fx = (window as unknown as FixtureWindow).__BV_BATTLE_FIXTURE__
  const source = useMemo(() => (fx ? fixtureSource(fx) : null), [fx])
  const [open, setOpen] = useState(true)
  if (!source || !fx) return <Empty className="m-4">{t('battle.noBattle')}</Empty>
  if (!open)
    return (
      <div className="p-4">
        <Button onClick={() => setOpen(true)} data-testid="battle-open">
          {t('battle.title')}
        </Button>
      </div>
    )
  return <BattleScreenFrom source={source} battleId={fx.read.battle ?? 'fixture'} onClose={() => setOpen(false)} />
}
