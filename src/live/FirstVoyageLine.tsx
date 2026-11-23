import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Clip, Icon, useWide } from '../components/ui'
import { useGoTo } from '../chart'
import { useRouteSeed } from '../features/map/routeSeed'
import { openOfficeCity } from '../features/command/officeView'
import { formatInt, formatRealShort } from '../lib/format'
import { properName, useT } from '../lib/i18n'
import { worldFirstVoyages, type FirstVoyages } from '../lib/rpc'
import { useServedRead } from './useServedRead'
import { portNameOf, useWorld } from './worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// FIRST VOYAGES — the starter chain's one line on the Trade desk, under the goal card (0476; roadmap 2026-11-23 slice 8).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The server owns the chain (world.first_voyages): which step she is on, her figure for it, what it pays, and on the deliver step the
// hold job to take. Reading it pays a step met (once, server-side); so it is asked when her purse moves (a sale, a delivery, a hire, an
// order), and the shell's purse is read again when a step was paid. Dark (first_voyages_enabled off), an old company or the chain done:
// the read says so and this line is not drawn at all — the desk is exactly as before.
//
// THE PRESS IS THE STEP'S "GO" (slice 3: a job is one press). Deliver: the trip is planned as the request board's "Buy at Bristol" plans
// it (live/RequestBoard.tsx, #800): her fleet, the job's source, then the job's harbour, handed to the Map's route builder as a draft
// (features/map/routeSeed.ts) — nothing is sent, Final is still hers. Trading: the You page (her levels). Captain: the Inn. Hull: the
// yard. Profit: no press (the desk's own cards are the way).

const LINE = 'flex min-h-11 min-w-0 shrink-0 items-center gap-2 rounded-control px-3 text-left text-t-caption'

export function FirstVoyageLine() {
  const t = useT()
  const wide = useWide()
  const navigate = useNavigate()
  const purse = useWorld((s) => s.ducats)
  const fleets = useWorld((s) => s.fleets)
  const portByCode = useWorld((s) => s.portByCode)
  const goodByCode = useWorld((s) => s.goodByCode)
  // asked again when her purse moves: every step's progress comes with a coin moving (and a paid step moves it too)
  const read = useServedRead<FirstVoyages>('first-voyages', worldFirstVoyages, { name: 'worldFirstVoyages', trigger: purse ?? 0 })
  const v = read.view

  // a step just paid: the shell's purse read again, and "Done +2,000" shown for a few seconds over the next step
  const [paid, setPaid] = useState<number | null>(null)
  const seen = useRef<string | null>(null)
  useEffect(() => {
    const just = v?.just ?? []
    if (just.length === 0) return
    const key = just.map((j) => j.step).join(',')
    if (seen.current === key) return
    seen.current = key
    setPaid(just.reduce((a, j) => a + j.ducats, 0))
    void useWorld.getState().refresh()
    const timer = window.setTimeout(() => setPaid(null), 8000)
    return () => window.clearTimeout(timer)
  }, [v])

  if (!v || !v.on || !v.open || !v.code || v.step == null || v.of == null) return null

  const job = v.code === 'deliver' ? (v.job ?? null) : null
  const fleet = job ? (fleets.find((f) => f.port === job.from.code) ?? fleets[0] ?? null) : null
  const portName = (code: string) => properName('port', portNameOf(portByCode, code), portNameOf(portByCode, code))
  const words = (() => {
    switch (v.code) {
      case 'deliver':
        return job
          ? t('trade.fvDeliver', {
              qty: formatInt(job.qty),
              good: properName('good', job.good.code, goodByCode[job.good.code]?.name ?? job.good.name),
              city: portName(job.port.code),
            })
          : t('trade.fvDeliverAny')
      case 'profit':
        return t('trade.fvProfit', { have: formatInt(Math.max(0, v.have ?? 0)), need: formatInt(v.need ?? 0) })
      case 'trading':
        return t('trade.fvTrading', { n: formatInt(v.need ?? 0) })
      case 'captain':
        return t('trade.fvCaptain')
      case 'hull':
        return t('trade.fvHull')
    }
  })()
  const from = job ? t('trade.holdFrom', { city: portName(job.from.code), time: formatRealShort(job.sail_seconds * 1000) }) : null

  const go: (() => void) | null =
    v.code === 'deliver'
      ? job && fleet
        ? () => {
            useRouteSeed.getState().plan(fleet.id, fleet.port === job.from.code ? [job.port.code] : [job.from.code, job.port.code])
            const { openMap } = useGoTo.getState()
            if (openMap) openMap()
            else navigate('/map')
          }
        : null
      : v.code === 'trading'
        ? () => navigate('/you')
        : v.code === 'captain'
          ? () => navigate(openOfficeCity('inn'))
          : v.code === 'hull'
            ? () => navigate(openOfficeCity('building_yard'))
            : null

  const body = (
    <>
      <span className="shrink-0 text-ink-faint" data-testid="first-voyage-step">
        {paid !== null ? t('trade.fvPaid', { ducats: formatInt(paid) }) : t('trade.fvStep', { n: v.step, of: v.of })}
      </span>
      <span className="min-w-0 flex-1 text-ink">
        <Clip>{from ? `${words} · ${from}` : words}</Clip>
      </span>
      <span className="shrink-0 tabular-nums text-ink-faint" data-testid="first-voyage-pays">
        {v.waiting ? t('trade.fvWaiting') : t('trade.fvPays', { ducats: formatInt(v.ducats ?? 0) })}
      </span>
      {go && <Icon name="chevron" size={14} />}
    </>
  )
  const place = wide ? 'mx-3 mb-2 w-[22rem] min-[90rem]:mx-6' : 'mb-1'
  const attrs = { 'data-testid': 'first-voyage', 'data-code': v.code, 'data-step': v.step, 'data-of': v.of } as const
  return go ? (
    <button type="button" onClick={go} className={`${LINE} ${place} bg-surface-2`} {...attrs}>
      {body}
    </button>
  ) : (
    <div className={`${LINE} ${place} bg-surface-2`} {...attrs}>
      {body}
    </div>
  )
}
