import { useEffect } from 'react'
import { create } from 'zustand'
import { worldWorldEvents, type WorldEvent } from '../lib/rpc'
import { instantMs } from '../lib/format'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE WORLD EVENTS (0469) — `world.world_events()`, ONE read for every screen that shows them (the Trade line, the quay, the map).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The server decides everything: which events, where, when each starts and ends, and whether it is on now (`live`). This module only
// asks, and keeps the last answer, while at least one screen that shows them is mounted:
//   · switched on (`on`) ..... every 60 s, and again just after the soonest start or end it served (so a famine opens on time)
//   · dark (`on` false) ...... every 5 min: a world with no events is barely asked
// and never while the tab is hidden. A failed read keeps the last answer. Dark, the list is empty and every screen draws nothing.

const LIT_MS = 60_000
const DARK_MS = 300_000
/** After a served edge, this long before it is asked about (the server's clock and ours differ by a beat). */
const EDGE_GRACE_MS = 1_500

export const NO_EVENTS: readonly WorldEvent[] = []

interface WorldEventsState {
  on: boolean
  events: readonly WorldEvent[]
}

export const useWorldEventsStore = create<WorldEventsState>(() => ({ on: false, events: NO_EVENTS }))

let users = 0
let timer: ReturnType<typeof setTimeout> | null = null
let asking = false

/** The soonest start or end still ahead of `nowMs` in `events`, in ms from now (null: none). Exported for the spec. */
export function nextEdgeInMs(events: readonly WorldEvent[], nowMs: number): number | null {
  let best: number | null = null
  for (const e of events) {
    for (const at of [e.live ? null : instantMs(e.starts_at), instantMs(e.ends_at)]) {
      if (at === null) continue
      const left = at - nowMs
      if (left > 0 && (best === null || left < best)) best = left
    }
  }
  return best
}

function schedule(ms: number) {
  if (timer !== null) clearTimeout(timer)
  timer = users > 0 ? setTimeout(() => void ask(), ms) : null
}

async function ask() {
  if (asking || users === 0) return
  if (typeof document !== 'undefined' && document.visibilityState === 'hidden') {
    schedule(LIT_MS)
    return
  }
  asking = true
  try {
    const res = await worldWorldEvents()
    if (res.ok) {
      const on = res.value.on === true
      const events = on ? (res.value.events ?? NO_EVENTS) : NO_EVENTS
      const prev = useWorldEventsStore.getState()
      // the answer touches the screens only when it changed
      if (prev.on !== on || JSON.stringify(prev.events) !== JSON.stringify(events)) useWorldEventsStore.setState({ on, events })
      const serverNow = instantMs(res.value.now ?? null) ?? Date.now()
      const edge = on ? nextEdgeInMs(events, serverNow) : null
      schedule(on ? Math.min(LIT_MS, edge === null ? LIT_MS : edge + EDGE_GRACE_MS) : DARK_MS)
    } else {
      schedule(on() ? LIT_MS : DARK_MS)
    }
  } catch {
    schedule(on() ? LIT_MS : DARK_MS)
  } finally {
    asking = false
  }
}

const on = () => useWorldEventsStore.getState().on

/** The events running or announced (empty while dark), asked while the calling screen is mounted. */
export function useWorldEvents(): readonly WorldEvent[] {
  useEffect(() => {
    users += 1
    if (users === 1) void ask()
    return () => {
      users -= 1
      if (users === 0 && timer !== null) {
        clearTimeout(timer)
        timer = null
      }
    }
  }, [])
  return useWorldEventsStore((s) => s.events)
}

/** The events at one harbour, by port code (none while dark). */
export function eventsAt(events: readonly WorldEvent[], portCode: string | null): WorldEvent[] {
  return portCode === null ? [] : events.filter((e) => e.port_code === portCode)
}
