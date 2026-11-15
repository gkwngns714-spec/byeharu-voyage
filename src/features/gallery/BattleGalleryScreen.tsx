import { useMemo, useState } from 'react'
import { Button, Empty } from '../../components/ui'
import type { BattleRead, BattleTicksRead, RpcResult } from '../../lib/rpc'
import { useT } from '../../lib/i18n'
import { BattleScreenFrom, type BattleSource } from '../../live/battle/BattleScreen'

// THE BATTLE SCREEN, FED A FIXTURE (/ui/battle; 0435). Like the gallery: outside sign-in, reads nothing from the world.
// tests/battle.screen.spec.ts hands a timeline in through `window.__BV_BATTLE_FIXTURE__` (written per the contract,
// docs/design/tick-combat.md 9.3) and reads the screen: the hit numbers, the log, the end, and the reduced-motion path.
// The fixture's clock is laid on this device's: the battle began `agoMs` before the first read. `cmd.battle_end` is
// counted in `window.__BV_BATTLE_CALLS__`, and every read after it is the closed battle with its `result`.

const ok = <T,>(value: T): RpcResult<T> => ({ ok: true, value })

interface BattleFixture {
  read: BattleTicksRead
  agoMs?: number
  result?: BattleTicksRead['result']
  old?: BattleRead
}

interface FixtureWindow {
  __BV_BATTLE_FIXTURE__?: BattleFixture
  __BV_BATTLE_CALLS__?: { read: number; end: number }
}

function fixtureSource(fx: BattleFixture): BattleSource {
  const w = window as unknown as FixtureWindow
  const calls = (w.__BV_BATTLE_CALLS__ = { read: 0, end: 0 })
  const started = Date.now() - (fx.agoMs ?? 0)
  let closed = false
  return {
    read: async () => {
      calls.read += 1
      const base: BattleTicksRead = { ...fx.read, started_at: new Date(started).toISOString(), now: new Date().toISOString() }
      return ok(closed ? { ...base, status: 'RESOLVED', result: fx.result ?? null } : base)
    },
    end: async () => {
      calls.end += 1
      closed = true
      return ok({ ok: true as const, status: 'RESOLVED' as const, resolves_at: new Date().toISOString() })
    },
    old: async () => ok(fx.old ?? { on: false }),
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
