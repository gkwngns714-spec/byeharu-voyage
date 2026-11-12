import { Button, KEEP_WORDS_CLASS } from '../../components/ui'
import { CHART_CHROME } from '../../chart'
import { formatVoyageDays } from '../../lib/format'
import { useT } from '../../lib/i18n'
import type { RouteLeg } from '../../lib/rpc'
import { LegLines, type LegLine } from '../../live/LegLines'
import type { RouteBuilder, RouteHold, RouteRepeat } from './useRouteBuilder'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE ROUTE BAR — the Map's route mode, drawn (owner row 209, docs/ROUTE_BUILDER.md §1). useRouteBuilder.ts decides.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
//     Gaivota · Stops 2
//     1 Lisbon → Porto · 1.2 d
//     2 Porto → Bilbao · 2.9 d
//     ? Bilbao → Nantes · 1.4 d · Too far
//     [ Undo ] [ Confirm ] [ Final ] [ Repeat ] [ Cancel ]
//
// ONE SHAPE AT EVERY WIDTH, AND IT NEVER MOVES (the owner's law: a press never re-flows the page). The bar stands at the
// foot of the chart; the leg list is a box of fixed height that scrolls inside itself, so adding a stop or undoing one
// changes no height. The five buttons share the row in five equal columns: a shut leg's reason takes Confirm's place
// with no change of width — or "Via N" (B3) when the server names N harbours that open it, and then it presses.
// Repeat (B4) hands the kept stops to the one route editor as a loop; while the leg that closes the loop is shut it
// reads that leg's reason in its own place. Nothing scrolls sideways. Confirm's reason is the SERVER's code in one or two words.
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
    case 'via':
      return t('map.routeVia', { n: hold.stops.length })
    case 'shut':
      return shutWord(t, hold.leg)
  }
}

/** What Repeat reads: its own word, or why the loop cannot close. */
function repeatWord(t: ReturnType<typeof useT>, repeat: RouteRepeat): string {
  switch (repeat.kind) {
    case 'max':
      return t('map.routeMax', { n: repeat.n })
    case 'noWater':
      return t('map.routeNoWater')
    case 'shut':
      return shutWord(t, repeat.leg)
    default:
      return t('map.routeRepeat')
  }
}

export function RouteBar({
  fleetName,
  route,
  name,
  onCancel,
  onFinal,
  onRepeat,
}: {
  fleetName: string
  route: RouteBuilder
  name: (code: string) => string
  onCancel: () => void
  onFinal: () => void
  /** Repeat: the loop's stops (her harbour first), for the route editor. */
  onRepeat: (stops: readonly string[]) => void
}) {
  const t = useT()
  const { legs, served, hold, kept, repeat } = route
  const lines: LegLine[] = legs.map((leg, i) => {
    const s = served?.[i] ?? null
    const pending = i >= kept.length
    return {
      from: leg.from ?? (i === 0 ? route.start : null),
      to: leg.to,
      days: s?.days != null ? formatVoyageDays(s.days) : '—',
      tag: s?.shut ? shutWord(t, s) : null,
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
      data-judged={served !== null || undefined}
      data-blocked={route.blocked || undefined}
    >
      {/* The route's line: whose it is and its stops, or — in the same place — why Final was refused (the server's sentence).
          THE FLEET'S NAME IS PRINTED WHOLE (2026-11-11, the full-names slice): the line was one `truncate` line, which cut a
          24-character fleet name at 390 px. It keeps its words now and takes a second line when it must. */}
      {route.refusal ? (
        <p className="truncate text-t-body text-warning" role="status" title={route.refusal} data-testid="route-refusal">
          {route.refusal}
        </p>
      ) : (
        <p data-name="" className={`${KEEP_WORDS_CLASS} text-t-body font-medium text-ink`} data-testid="route-summary">
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
      <div className="mt-2 grid grid-cols-5 gap-1.5">
        <Button size="sm" onClick={route.undo} disabled={kept.length === 0 && route.next === null} data-testid="route-undo">
          {t('map.routeUndo')}
        </Button>
        <Button
          size="sm"
          className="min-w-0 truncate"
          onClick={route.confirm}
          disabled={hold.kind !== 'open' && hold.kind !== 'via'}
          data-testid="route-confirm"
          data-reason={hold.kind === 'shut' || hold.kind === 'via' ? hold.leg.shut?.code : hold.kind}
          data-via={hold.kind === 'via' ? hold.stops.length : undefined}
        >
          {confirmWord(t, hold)}
        </Button>
        <Button
          size="sm"
          variant="primary"
          onClick={onFinal}
          disabled={kept.length === 0 || route.blocked}
          busy={route.sending}
          data-testid="route-final"
        >
          {t('map.routeFinal')}
        </Button>
        <Button
          size="sm"
          className="min-w-0 truncate"
          onClick={() => repeat.kind === 'open' && onRepeat(repeat.stops)}
          disabled={repeat.kind !== 'open'}
          data-testid="route-repeat"
          data-reason={repeat.kind === 'shut' ? repeat.leg.shut?.code : repeat.kind}
        >
          {repeatWord(t, repeat)}
        </Button>
        <Button size="sm" variant="quiet" onClick={onCancel} data-testid="route-cancel">
          {t('map.routeCancel')}
        </Button>
      </div>
    </div>
  )
}
