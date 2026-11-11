import { Button } from '../../components/ui'
import { CHART_CHROME } from '../../chart'
import { formatVoyageDays } from '../../lib/format'
import { useT } from '../../lib/i18n'
import type { RouteLeg } from '../../lib/rpc'
import { LegLines, type LegLine } from '../../live/LegLines'
import type { RouteBuilder, RouteHold } from './useRouteBuilder'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE ROUTE BAR — the Map's route mode, drawn (owner row 209, docs/ROUTE_BUILDER.md §1). useRouteBuilder.ts decides.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
//     Gaivota · Stops 2
//     1 Lisbon → Porto · 1.2 d
//     2 Porto → Bilbao · 2.9 d
//     ? Bilbao → Nantes · 1.4 d · Too far
//     [ Undo ] [ Confirm ] [ Final ] [ Cancel ]
//
// ONE SHAPE AT EVERY WIDTH, AND IT NEVER MOVES (the owner's law: a press never re-flows the page). The bar stands at the
// foot of the chart; the leg list is a box of fixed height that scrolls inside itself, so adding a stop or undoing one
// changes no height. The four buttons share the row in four equal columns: a shut leg's reason takes Confirm's place
// with no change of width. Nothing scrolls sideways. Confirm's reason is the SERVER's code in one or two words.
// "Navigation N" (docs/ROUTE_BUILDER.md §1) is not printed: the level a leg asks is not served, and working it out here
// would be a second copy of the reach rule — decided by default, the reason reads "Too far".

/** A shut leg's reason in one or two words, from the server's code. */
function shutWord(t: ReturnType<typeof useT>, leg: RouteLeg): string {
  switch (leg.shut?.code) {
    case 'E_LEG_TOO_FAR':
      return t('map.routeTooFar')
    case 'E_ENDURANCE':
      return t('map.routeSupplies')
    case 'E_SEA_CLOSED':
      return t('map.routeSeaShut')
    case 'E_NO_COURSE':
      return t('map.routeNoWater')
    default:
      return t('map.routeShut')
  }
}

/** What Confirm reads: its own word when the next stop may be kept, else why not. */
function confirmWord(t: ReturnType<typeof useT>, hold: RouteHold): string {
  switch (hold.kind) {
    case 'open':
    case 'none':
      return t('map.routeConfirm')
    case 'checking':
      return t('map.routeChecking')
    case 'same':
      return t('map.routeSame')
    case 'max':
      return t('map.routeMax', { n: hold.n })
    case 'noWater':
      return t('map.routeNoWater')
    case 'shut':
      return shutWord(t, hold.leg)
  }
}

export function RouteBar({
  fleetName,
  route,
  name,
  onCancel,
  onFinal,
}: {
  fleetName: string
  route: RouteBuilder
  name: (code: string) => string
  onCancel: () => void
  onFinal: () => void
}) {
  const t = useT()
  const { legs, served, hold, kept } = route
  const lines: LegLine[] = legs.map((leg, i) => {
    const s = served?.[i] ?? null
    const pending = i >= kept.length
    return {
      from: leg.from ?? (i === 0 ? route.start : null),
      to: leg.to,
      days: s?.days != null ? formatVoyageDays(s.days) : '—',
      tag: pending && s?.shut ? shutWord(t, s) : null,
      pending,
    }
  })

  return (
    <div
      {...CHART_CHROME}
      className="pointer-events-auto absolute inset-x-0 bottom-0 z-30 rounded-t-sheet bg-surface px-4 pb-3 pt-2 shadow-sheet lg:inset-x-auto lg:bottom-3 lg:left-1/2 lg:w-[26rem] lg:-translate-x-1/2 lg:rounded-sheet"
      role="region"
      aria-label={t('map.routeTitle')}
      data-testid="route-bar"
      data-kept={kept.length}
      data-hold={hold.kind}
    >
      {/* ONE LINE, always: the route's name and its stops, or — in the same place — why Final was refused (the server's sentence). */}
      {route.refusal ? (
        <p className="truncate text-t-body text-warning" role="status" title={route.refusal} data-testid="route-refusal">
          {route.refusal}
        </p>
      ) : (
        <p className="truncate text-t-body font-medium text-ink" data-testid="route-summary">
          {`${t('map.routeTitle')} · ${fleetName} · ${t('map.routeStops', { n: kept.length })}`}
        </p>
      )}
      <div className="mt-1 h-20 overflow-y-auto overflow-x-hidden" data-testid="route-legs-box">
        {lines.length > 0 ? (
          <LegLines legs={lines} name={name} testId="route-legs" itemTestId="route-leg" className="flex flex-col" />
        ) : (
          <p className="text-t-caption text-ink-faint">{t('map.routeTap')}</p>
        )}
      </div>
      <div className="mt-2 grid grid-cols-4 gap-2">
        <Button size="sm" onClick={route.undo} disabled={kept.length === 0 && route.next === null} data-testid="route-undo">
          {t('map.routeUndo')}
        </Button>
        <Button
          size="sm"
          className="min-w-0 truncate"
          onClick={route.confirm}
          disabled={hold.kind !== 'open'}
          data-testid="route-confirm"
          data-reason={hold.kind === 'shut' ? hold.leg.shut?.code : hold.kind}
        >
          {confirmWord(t, hold)}
        </Button>
        <Button
          size="sm"
          variant="primary"
          onClick={onFinal}
          disabled={kept.length === 0}
          busy={route.sending}
          data-testid="route-final"
        >
          {t('map.routeFinal')}
        </Button>
        <Button size="sm" variant="quiet" onClick={onCancel} data-testid="route-cancel">
          {t('map.routeCancel')}
        </Button>
      </div>
    </div>
  )
}
