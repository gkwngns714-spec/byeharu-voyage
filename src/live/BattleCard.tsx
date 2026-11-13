import { useEffect, useRef, useState } from 'react'
import { cmdBattleStance, worldBattle } from '../lib/rpc'
import type { BattleRead, BattleStanceWord, Refusal } from '../lib/rpc'
import { BattleView } from './BattleView'
import { useWorld } from './worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A BATTLE FOUGHT ROUND BY ROUND (0357, owner row 315: "when pressed fight, it keeps on fighting, when flee, it tries
// to flee ... showing logs, damages"; docs/COMBAT_LOG.md 3.3, 3.4, 5.2).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SERVER JUDGES EVERYTHING. `world.battle(fleet)` serves her fleet's battle: the clock, her stance, the stances
// she may take, and the log so far from her deck. `cmd.battle_stance` judges the press, and the stance takes hold from
// the NEXT round, which the caption says. Nothing here computes a round, a chance or an outcome.
// THE LOG IS THE ONE `FightLog`: the component a raid's log is drawn by, growing a round at a time.
// THE POLL: every 5 s, only while this card is mounted and the battle is being fought; never otherwise. `on` false
// (attacks are dark, or the fleet has no such battle) draws nothing and stops asking.
// THE CLOCK is the server's: each read carries its own `now`, and the countdown runs against it, not the device's.
// A WATCHED BATTLE KEEPS TIME: when a round falls due the card sends her own stance again. The door writes nothing
// for a stance she already holds and fights every round that is due, so the log does not wait for the minute job.
// `BattleView` (src/live/BattleView.tsx) is the face, with no clock and no network of its own.

const POLL_MS = 5000

export function BattleCard({ fleetId, className = '' }: { fleetId: string; className?: string }) {
  const refresh = useWorld((s) => s.refresh)
  // a read, with the device's clock at the moment it landed: the server's clock now is its `now` plus what has passed since
  const [got, setGot] = useState<{ fleet: string; value: BattleRead; at: number } | null>(null)
  const [tick, setTick] = useState(() => Date.now())
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const busy = useRef(false)
  const nudged = useRef<string | null>(null)
  const closed = useRef<string | null>(null)

  const now = got?.fleet === fleetId ? got : null
  const read = now?.value ?? null
  const fighting = read?.on === true && read.status === 'FIGHTING'
  const asking = now === null || fighting
  const battle = read?.battle ?? null
  const stance = read?.stance ?? null
  const nextAt = fighting ? (read?.next_at ?? null) : null
  const over = read?.on === true && battle !== null && !fighting

  useEffect(() => {
    if (!asking) return
    let live = true
    const ask = () =>
      void worldBattle(fleetId).then((r) => {
        if (live && r.ok) setGot({ fleet: fleetId, value: r.value, at: Date.now() })
      })
    ask()
    const id = window.setInterval(ask, POLL_MS)
    return () => {
      live = false
      window.clearInterval(id)
    }
  }, [fleetId, asking])

  useEffect(() => {
    if (!fighting) return
    const id = window.setInterval(() => setTick(Date.now()), 1000)
    return () => window.clearInterval(id)
  }, [fighting])

  const serverNow = now && read?.now ? Date.parse(read.now) + Math.max(0, tick - now.at) : tick

  const send = (to: string, word: BattleStanceWord, pressed: boolean) => {
    if (busy.current) return
    busy.current = true
    if (pressed) setRefusal(null)
    void (async () => {
      const r = await cmdBattleStance(to, word)
      // a press she made is answered in words; a nudge that finds the battle over is not a refusal to show
      if (!r.ok && pressed) setRefusal(r.refusal)
      const again = await worldBattle(fleetId)
      if (again.ok) setGot({ fleet: fleetId, value: again.value, at: Date.now() })
      busy.current = false
    })()
  }

  // a round fell due while she watched: her own stance again, once a round, so the door fights it now
  const due = nextAt !== null && serverNow >= Date.parse(nextAt) + 500
  useEffect(() => {
    if (!due || !battle || !stance || nextAt === null || nudged.current === nextAt || busy.current) return
    nudged.current = nextAt
    busy.current = true
    void (async () => {
      await cmdBattleStance(battle, stance)
      const again = await worldBattle(fleetId)
      if (again.ok) setGot({ fleet: fleetId, value: again.value, at: Date.now() })
      busy.current = false
    })()
  }, [due, battle, stance, nextAt, fleetId])

  // closed: the fleet is free again, and the world's own read says so
  useEffect(() => {
    if (!over || closed.current === battle) return
    closed.current = battle
    void refresh()
  }, [over, battle, refresh])

  if (!read) return null
  return <BattleView read={read} nowMs={serverNow} refusal={refusal} onStance={(s) => battle && s !== stance && send(battle, s, true)} className={className} />
}
