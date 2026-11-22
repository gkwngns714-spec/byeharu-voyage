import { useEffect, useRef, useState } from 'react'
import { Button, FLOAT_CARD_CLASS, glassBesideRailClass } from '../components/ui'
import { AWAY_MS, awayLand, awayReport, parseSeenMark, routeCaption, routeTitle, seenMark, type AwayReport } from '../domain/route'
import { formatDucatsDelta, formatInt } from '../lib/format'
import { properName, useLocale, useT } from '../lib/i18n'
import { worldLand } from '../lib/rpc'
import { levelName } from '../live/levelWords'
import { useWorld } from '../live/worldStore'
import { ShipPicture } from '../features/fleets/ShipPicture'

// WHILE YOU WERE AWAY (2026-11-16, the content plan's slice B; docs/design/content-plan-2026-11.md §5.3 no. 2). The route
// trades by itself, and when she came back nothing said what it did. One card says it, once, on her return.
//
// "AWAY", decided by default: THIS DEVICE did not have the game open and in view for ten minutes or more (`AWAY_MS`). The
// device keeps a MARK (localStorage, one per backend and company): the time, the purse, and each route's all-time lap
// counters, written on every world read while the page is in view and once more when it is hidden. On a load, or when a
// hidden tab comes back into view, the first read with the routes book compares now against the mark (domain/route
// `awayReport`): the laps each route closed and their net (the server's own counters, so they agree with the route's page
// and with History's lap lines however many closed), a route that needs her (stopped, blocked, paused by the game), and
// the purse's move. Nothing to say, no card. A device that has no mark (a new player, a new browser) keeps one and says
// nothing: there is no "since" to tell.
//
// THE LAND (0458): while the world serves the land lit, a return that is away also asks the Land tab's own read once
// (`world.land`) and the report gains one line, "Party: 86 Iron · Mining 31" (domain/route `awayLand`). Dark, nothing is asked.
//
// An overlay at the TOP of the glass (the arrival card stands at its foot, so the two never cover each other): fixed,
// out of the flow, nothing under it moves; it stays until Close (a report she came back to waits for her).

const markKey = (mode: string, player: string) => `bv:last-seen:${mode}:${player}`

function readMark(key: string) {
  try {
    return parseSeenMark(localStorage.getItem(key))
  } catch {
    return null
  }
}

function writeMark(key: string, s: ReturnType<typeof useWorld.getState>) {
  try {
    localStorage.setItem(key, JSON.stringify(seenMark(Date.now(), s.ducats, s.routes)))
  } catch {
    // a blocked or full storage: the next return simply has no mark to compare against, and says nothing
  }
}

export function AwayCard() {
  const t = useT()
  const locale = useLocale()
  const portByCode = useWorld((s) => s.portByCode)
  const goodByCode = useWorld((s) => s.goodByCode)
  const fleets = useWorld((s) => s.fleets)
  // her flagship's class, for the fleet's picture (a fleet no longer served draws the smallest)
  const fleetClass = (id: string | undefined) => fleets.find((f) => f.id === id)?.ships[0]?.class_code ?? null
  const [report, setReport] = useState<AwayReport | null>(null)
  // whether this visit (a load, or a return to view) has been compared against the mark yet
  const compared = useRef(false)

  useEffect(() => {
    const keyOf = (s: ReturnType<typeof useWorld.getState>) => (s.mode && s.player ? markKey(s.mode, s.player.id) : null)
    const read = (s: ReturnType<typeof useWorld.getState>) => {
      if (s.phase !== 'ready' || s.routes === null || s.ducats === null) return
      const key = keyOf(s)
      if (key === null || document.visibilityState !== 'visible') return
      if (!compared.current) {
        compared.current = true
        const then = readMark(key)
        const now = Date.now()
        const { ducats, routes } = s
        if (then && now - then.at >= AWAY_MS && s.snapshot?.config.land_enabled === true) {
          // the land is lit: its line comes from the Land tab's read, asked once for this return
          void worldLand('mining').then((r) => {
            const found = awayReport(then, now, ducats, routes, r.ok ? awayLand(r.value) : null)
            if (found) setReport(found)
          })
        } else {
          const found = then ? awayReport(then, now, ducats, routes) : null
          if (found) setReport(found)
        }
      }
      writeMark(key, s)
    }
    const onVisibility = () => {
      const s = useWorld.getState()
      const key = keyOf(s)
      if (document.visibilityState === 'hidden') {
        if (key !== null && s.phase === 'ready' && s.routes !== null && s.ducats !== null) writeMark(key, s)
      } else {
        // back in view: the next read (AppShell reads on this same event) is compared against the mark
        compared.current = false
      }
    }
    read(useWorld.getState())
    const off = useWorld.subscribe(read)
    document.addEventListener('visibilitychange', onVisibility)
    return () => {
      off()
      document.removeEventListener('visibilitychange', onVisibility)
    }
  }, [])

  if (report === null) return null
  return (
    <div className={`pointer-events-none ${glassBesideRailClass()} top-10 z-60 flex justify-center px-4`} data-testid="away-card-wrap">
      <div
        role="status"
        aria-live="polite"
        data-testid="away-card"
        data-money={report.money ?? undefined}
        className={FLOAT_CARD_CLASS}
      >
        <p className="text-t-label font-semibold">{t('feed.awayTitle')}</p>
        {report.routes.map((r) => (
          <div key={r.id} className="mt-1" data-testid="away-route" data-laps={r.laps} data-net={r.net} data-stuck={r.stuck ? 'true' : 'false'}>
            {/* EACH FLEET'S ROUTE EARNINGS (2026-11-23, the roadmap's slice 6): the fleet that ran it, with her picture, and the route
                under it; a route no fleet runs keeps its own name */}
            <p className="flex items-center justify-between gap-3 text-t-body">
              <span className="flex min-w-0 items-center gap-2">
                <ShipPicture code={fleetClass(r.route.fleet?.id)} size="mark" />
                <span className="min-w-0 break-words" data-testid="away-route-fleet">{r.route.fleet?.name ?? routeTitle(r.name, r.stops, portByCode)}</span>
              </span>
              {r.laps > 0 && (
                <span className={`shrink-0 font-semibold tabular-nums ${r.net < 0 ? 'text-danger' : r.net > 0 ? 'text-success' : ''}`} data-testid="away-route-net">
                  {formatDucatsDelta(r.net)}
                </span>
              )}
            </p>
            <p className="text-t-caption text-ink-muted">
              {r.route.fleet && <span className="break-words" data-testid="away-route-title">{routeTitle(r.name, r.stops, portByCode)} · </span>}
              {r.laps > 0 && <span data-testid="away-route-laps">{t('feed.awayLaps', { n: formatInt(r.laps), count: r.laps })}</span>}
              {r.laps > 0 && r.stuck && ' · '}
              {r.stuck && (
                <span className="text-danger" data-testid="away-route-stuck">
                  {routeCaption(r.route)}
                </span>
              )}
            </p>
          </div>
        ))}
        {report.land && (
          <p className="mt-1 flex justify-between gap-3 text-t-body" data-testid="away-land" data-n={report.land.n}>
            <span>{t('land.party')}</span>
            <span className="min-w-0 break-words text-right font-semibold tabular-nums">
              {`${formatInt(report.land.n)} ${report.land.good ? properName('good', report.land.good, goodByCode[report.land.good]?.name ?? report.land.good) : ''} · ${levelName(locale, report.land.skill)}${report.land.level === null ? '' : ` ${formatInt(report.land.level)}`}`}
            </span>
          </p>
        )}
        {report.money !== null && (
          <p className="mt-1 flex justify-between gap-3 text-t-body" data-testid="away-money">
            <span>{t('feed.awayMoney')}</span>
            <span className={`shrink-0 font-semibold tabular-nums ${report.money < 0 ? 'text-danger' : 'text-success'}`}>{formatDucatsDelta(report.money)}</span>
          </p>
        )}
        <div className="mt-3 flex gap-2">
          <Button variant="secondary" size="sm" className="flex-1" data-testid="away-close" onClick={() => setReport(null)}>
            {t('feed.close')}
          </Button>
        </div>
      </div>
    </div>
  )
}
