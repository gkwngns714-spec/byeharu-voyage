import { Dot, Figure, SheetSection, StatCell } from '../../components/ui'
import { fleetHoldUsed, whereabouts } from '../../domain/fleet'
import { formatCountdown, formatDucats, formatInt, formatTons } from '../../lib/format'
import { useT } from '../../lib/i18n'
import { useWorld } from '../../live/worldStore'

// RIGHT NOW — the figures on this tab that are not a rollup, and they move while you watch.
//
// THE OWNER, 2026-10-20 (request 187): *"I want stats to be in real time — by seconds updated."*
// The split that answers it is in statsPulse.ts; this is the live half. Every number here is read
// out of the store the shell ALREADY polls (AppShell's beat: three seconds at the current clock),
// so the band costs no read, no write and no second poller — it is the world's own beat, printed.
// Each figure counts to its new value (Counter), which is the moving number request 188 asks for.
//
// WHY THESE FOUR. They are the ones a live read can honestly carry: your purse and your fleets are
// re-read every beat by the shell, and the countdown is arithmetic on the server's own age. The
// world's money, the goods and the cities are SUMS over every market and every harbour — the job
// writes them every fifteen minutes, and a figure that cannot move faster than that is better read
// as a chart than as a ticker (docs/OWNER_REQUESTS.md row 187).

export function LiveNow({ dueMs }: { dueMs: number | null }) {
  const t = useT()
  // Selected as primitives, one selector each (worldStore's rule): a selector that built an object
  // would re-render this band on every market fetch in the world.
  const ducats = useWorld((s) => s.ducats)
  const fleets = useWorld((s) => s.fleets)

  // ONE classification per fleet (domain/fleet's `whereabouts`, the authority every screen and the
  // chart read), then counted. These are FLEETS, not hulls: a fleet is what sails.
  const where = fleets.map((f) => whereabouts(f).kind)
  const atSea = where.filter((k) => k === 'sailing').length
  const inPort = where.filter((k) => k === 'docked').length
  const carried = fleets.reduce((n, f) => n + fleetHoldUsed(f), 0)

  return (
    <SheetSection
      heading={
        <span className="flex items-center gap-2">
          <Dot tone="success" label={t('stats.live')} />
          {t('stats.rightNow')}
        </span>
      }
      trailing={
        dueMs === null ? undefined : (
          <span className="text-t-caption text-ink-faint">
            {t('stats.nextIn')} <Figure value={formatCountdown(dueMs)} />
          </span>
        )
      }
      data-testid="stats-live"
    >
      <div className="grid grid-cols-2 gap-x-4 gap-y-3 lg:grid-cols-4">
        <StatCell
          label={t('stats.purse')}
          value={ducats ?? 0}
          format={formatDucats}
          tone="accent"
          text={ducats === null ? '—' : undefined}
          data-testid="stats-live-purse"
        />
        <StatCell label={t('stats.fleetsAtSea')} value={atSea} format={formatInt} />
        <StatCell label={t('stats.fleetsInPort')} value={inPort} format={formatInt} />
        <StatCell label={t('stats.cargoCarried')} value={carried} format={(v) => formatTons(v)} />
      </div>
    </SheetSection>
  )
}
