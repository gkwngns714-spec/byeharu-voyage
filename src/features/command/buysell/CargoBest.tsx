import { Hint, Icon, Skeleton, goodIcon } from '../../../components/ui'
import { fleetCargoByCode } from '../../../domain/fleet'
import { PortFlag } from '../../../live/PortFlag'
import { useGoodBoard, usePriceWhy } from '../../../live/useDesk'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { formatInt, formatPriceDelta, formatPriceFigure, formatVoyageDays } from '../../../lib/format'
import type { BoardSellRow, FleetView } from '../../../lib/rpc'
import { useT } from '../../../lib/i18n'

// HER CARGO, AND WHERE TO SELL IT — the top of the Sell face, under the map (owner row 231, 2026-10-26: *"the command,
// sell tab is not good enough, i can't sell because i can't dock. and i can't move to that location … make the sell
// tab more convenient. come on!"*).
//
// One block per good aboard: its name and units, then
//   · HERE — where she lies, when that city buys it: its bid now (world.price_why, the served price), 0 days;
//   · the few BEST cities she can sail to for it, and the few NEAREST: the served board's own rows (world.good_board
//     for what is aboard — the rows it prices in full, `price_each`; that she can sail, `sailable`): the price, the
//     days, and the PROFIT after wages, supplies and tax (the row's `profit`, served — nothing is added up here).
//     The board prices in full its `good_board_quoted` dearest cities (10) and its `good_board_quoted_near` nearest
//     she can sail to (5, 0251), so "best" is the best of those and "near" the nearest of them. Nearest first.
// One press on a row is that city and that good, ready to go (BuySell.tsx: the city in hand, the map glides to it,
// the panel opens with ONE button — Sell there, or Sail & sell).

/** How many cities a good lists — a few, not a directory: the best few by profit, and the nearest few. */
const BEST = 3
const NEAR = 3

export function CargoBest({
  fleet,
  city,
  picked,
  onPress,
}: {
  fleet: FleetView
  /** The city in hand and the good pressed (the row that matches is lit). */
  city: string | null
  picked: string | null
  onPress: (city: string, good: string) => void
}) {
  const t = useT()
  const aboard = Object.entries(fleetCargoByCode(fleet))
    .filter(([, units]) => units > 0)
    .sort(([a], [b]) => a.localeCompare(b))
  return (
    // THE HEADING BELONGS TO THE CALLER (Trade.tsx wraps this in a `SectionFold` on a phone; the
    // wide desk shows it in the centre pane). The block itself is the goods and their places.
    <section className="mb-4" data-testid="cargo-best">
      {aboard.length === 0 ? (
        <Hint data-testid="cargo-best-empty">{t('desk.holdEmpty')}</Hint>
      ) : (
        <div className="flex flex-col gap-2">
          {aboard.map(([code, units]) => (
            <CargoGood key={code} fleet={fleet} code={code} units={units} city={city} picked={picked} onPress={onPress} />
          ))}
        </div>
      )}
    </section>
  )
}

function CargoGood({
  fleet,
  code,
  units,
  city,
  picked,
  onPress,
}: {
  fleet: FleetView
  code: string
  units: number
  city: string | null
  picked: string | null
  onPress: (city: string, good: string) => void
}) {
  const t = useT()
  const good = useWorld((s) => s.goodByCode[code] ?? null)
  const portByCode = useWorld((s) => s.portByCode)
  const docked = fleet.status === 'DOCKED' ? fleet.port : null
  const board = useGoodBoard(good?.id ?? null, fleet.id, fleet.version, null, null)
  const b = board.view
  // where she lies, when that city buys it (the board has its row): its bid now, the served price
  const hereRow = b && docked ? (b.sell.find((r) => r.port === docked) ?? null) : null
  const hereBid = usePriceWhy(hereRow && docked ? (portByCode[docked]?.id ?? null) : null, hereRow ? (good?.id ?? null) : null)
  const priced: BoardSellRow[] = (b?.sell ?? []).filter((r) => r.port !== docked && r.price_each != null && r.sailable === true)
  // the served profit first; where none is served (her cost unknown), the served price
  const top = [...priced]
    .sort((x, y) => (y.profit ?? -Infinity) - (x.profit ?? -Infinity) || (y.price_each ?? 0) - (x.price_each ?? 0))
    .slice(0, BEST)
  const byDays = (x: BoardSellRow, y: BoardSellRow) => (x.days ?? Infinity) - (y.days ?? Infinity) || x.port.localeCompare(y.port)
  const near = priced.filter((r) => !top.includes(r)).sort(byDays).slice(0, NEAR)
  // one list, nearest first: the near cities and the best ones, each with its days and profit
  const best = [...top, ...near].sort(byDays)
  const here = hereRow && hereBid.view ? hereBid.view.bid : null
  const none = b !== null && best.length === 0 && here === null && !hereBid.loading
  return (
    <div className="rounded-md bg-surface-2 p-2" data-testid="cargo-good" data-good={code}>
      <div className="mb-1 flex items-baseline justify-between gap-2">
        <span className="flex min-w-0 items-center gap-1.5">
          <Icon name={goodIcon(code, good?.category ?? '')} size={16} className="shrink-0 text-ink-muted" />
          <span className="truncate text-t-label font-medium text-ink">{good?.name ?? code}</span>
        </span>
        <span className="shrink-0 text-t-caption tabular-nums text-ink-muted">{t('desk.aboardN', { n: formatInt(units) })}</span>
      </div>
      {!b ? (
        <Skeleton className="h-8 w-full" />
      ) : none ? (
        <Hint className="mt-0" data-testid="cargo-best-none">
          {t('desk.noPlace')}
        </Hint>
      ) : (
        <ul className="flex flex-col">
          {docked && here !== null && (
            <PlaceRow
              port={docked}
              name={t('desk.here')}
              price={here}
              days={null}
              profit={null}
              on={city === docked && picked === code}
              onPress={() => onPress(docked, code)}
            />
          )}
          {best.map((r) => (
            <PlaceRow
              key={r.port}
              port={r.port}
              name={portNameOf(portByCode, r.port)}
              price={r.price_each as number}
              days={r.days}
              profit={r.profit ?? null}
              on={city === r.port && picked === code}
              onPress={() => onPress(r.port, code)}
            />
          ))}
        </ul>
      )}
    </div>
  )
}

/** One city for one good: name · price · days · profit — one line, one press. */
function PlaceRow({
  port,
  name,
  price,
  days,
  profit,
  on,
  onPress,
}: {
  port: string
  name: string
  price: number
  days: number | null
  profit: number | null
  on: boolean
  onPress: () => void
}) {
  return (
    <li>
      <button
        type="button"
        onClick={onPress}
        aria-pressed={on}
        className={[
          'grid w-full grid-cols-[minmax(0,1fr)_auto_auto_auto] items-baseline gap-x-3 rounded px-1.5 py-1.5 text-left transition active:scale-[0.99]',
          on ? 'bg-accent-soft ring-1 ring-accent' : 'hover:bg-surface-1',
        ].join(' ')}
        data-testid="cargo-place"
        data-port={port}
      >
        <span className="truncate text-t-caption text-ink" data-testid="cargo-place-name">
          <PortFlag code={port} /> {name}
        </span>
        <span className="text-t-caption font-semibold tabular-nums text-ink" data-testid="cargo-place-price">
          {formatPriceFigure(price)}
        </span>
        <span className="text-t-caption tabular-nums text-ink-muted" data-testid="cargo-place-days">
          {days === null ? '' : formatVoyageDays(days)}
        </span>
        <span
          className={`text-t-caption tabular-nums ${profit === null ? 'text-ink-faint' : profit >= 0 ? 'text-success' : 'text-danger'}`}
          data-testid="cargo-place-profit"
        >
          {profit === null ? '—' : formatPriceDelta(profit)}
        </span>
      </button>
    </li>
  )
}
