import { useMemo, useState } from 'react'
import type { ReactNode } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Badge,
  Button,
  Card,
  CardHeader,
  Notice,
  PageHeader,
  Screen,
  SectionLabel,
  TD,
  TH,
  Table,
} from '../../components/ui'
import { formatInt, formatPct, formatPctPoints, formatTuns } from '../../lib/format'
import { useWorld } from '../../fixtures/useWorld'
import type { PortCode } from '../../fixtures/types'
import { useCommandDraft } from '../command/commandDraft'
import { Sparkline } from './Sparkline'
import type { MarketRow, PriceBand } from './prices'
import {
  BUY_BAND_MAX,
  NEIGHBOUR_RADIUS_NM,
  SELL_BAND_MIN,
  buildMarketRows,
  effectiveTaxRate,
  spreadOf,
} from './prices'

// MARKET — E.4, "the most important table in the game" and the reading room the whole loop starts
// in.
//
// %NBR IS THE COLUMN THE GAME IS PLAYED FROM. It is this port's mid as a percentage of the mean
// mid across every port within 600 nm that trades the good. Below 90 you buy; above 110 you sell;
// "the rest is your judgement". The table is therefore SORTED INTO THOSE THREE BLOCKS BY DEFAULT,
// with BUY at the top — so a player who knows nothing can see, in one glance, the two rows that
// pay. That ordering is the tutorial.
//
// TAPPING A ROW FILLS THE CMD INPUT. The draft is a shared Zustand store (features/command/
// commandDraft.ts), so MARKET writes a STRING and CMD reads it — one draft, one authority, and no
// structured order object anywhere.
//
// MOBILE: seven columns will not fit 390px, so the table scrolls INSIDE its own box (the Table
// primitive's rule) and the page never moves sideways. The tap target is the FIRST column, so it
// is reachable without scrolling the table at all.

type SortKey = 'nbr' | 'name' | 'price' | 'stock'
type Filter = 'all' | 'buy' | 'sell'

export function MarketScreen() {
  const model = useWorld()
  const navigate = useNavigate()
  const handOff = useCommandDraft((s) => s.handOff)
  const draftFleetId = useCommandDraft((s) => s.fleetId)

  const [portCode, setPortCode] = useState<PortCode>(model.world.currentPort)
  const [sort, setSort] = useState<SortKey>('nbr')
  const [filter, setFilter] = useState<Filter>('all')

  const port = model.portOf(portCode)
  const taxRelief = model.world.player.taxRelief

  const rows = useMemo(
    () => buildMarketRows(model.priceIndex, portCode, taxRelief),
    [model.priceIndex, portCode, taxRelief],
  )

  const neighbours = model.priceIndex.neighbours.get(portCode) ?? []

  const sorted = useMemo(() => {
    const cmp: Record<SortKey, (a: MarketRow, b: MarketRow) => number> = {
      nbr: (a, b) => (a.nbr ?? 100) - (b.nbr ?? 100),
      name: (a, b) => a.good.name.localeCompare(b.good.name),
      price: (a, b) => b.mid - a.mid,
      stock: (a, b) => b.stockRatio - a.stockRatio,
    }
    return [...rows].sort(cmp[sort])
  }, [rows, sort])

  const shown = sorted.filter((r) => filter === 'all' || r.band === filter)
  const blocks: { band: PriceBand; label: string; rows: MarketRow[] }[] = [
    { band: 'buy', label: `BUY  (< ${BUY_BAND_MAX}%)`, rows: shown.filter((r) => r.band === 'buy') },
    { band: 'sell', label: `SELL (> ${SELL_BAND_MIN}%)`, rows: shown.filter((r) => r.band === 'sell') },
    { band: 'hold', label: 'hold', rows: shown.filter((r) => r.band === 'hold') },
  ]

  const fleetHere = model.fleetViews.find(
    (v) => v.fleet.portCode === portCode || v.progress?.destination === portCode,
  )

  const fill = (row: MarketRow) => {
    const verb = row.band === 'sell' ? 'SELL' : 'BUY'
    const qty = verb === 'SELL' ? 'ALL' : String(Math.max(10, Math.floor(fleetHere?.holdFree ?? 50)))
    handOff(`${verb} ${row.good.name} ${qty}`, fleetHere?.fleet.id ?? draftFleetId)
    navigate('/command')
  }

  return (
    <Screen wide>
      <PageHeader
        eyebrow="Trade"
        title={`Market · ${port.name}`}
        subtitle={`Prices against the ${neighbours.length} ports within ${NEIGHBOUR_RADIUS_NM} nm.`}
      />

      <Card>
        <div className="space-y-3">
          <div>
            <SectionLabel>Port</SectionLabel>
            <div className="flex flex-wrap gap-1.5">
              {model.world.ports.map((p) => (
                <button
                  key={p.code}
                  type="button"
                  onClick={() => setPortCode(p.code)}
                  className={[
                    'min-h-11 rounded-md px-3 font-mono text-xs transition',
                    p.code === portCode
                      ? 'bg-accent text-app'
                      : 'border border-edge bg-surface-2 text-ink-muted hover:text-ink',
                  ].join(' ')}
                >
                  {p.name}
                </button>
              ))}
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-4">
            <div className="flex flex-wrap items-center gap-1.5">
              <SectionLabel className="mb-0">Sort</SectionLabel>
              {(['nbr', 'name', 'price', 'stock'] as const).map((k) => (
                <Chip key={k} active={sort === k} onClick={() => setSort(k)}>
                  {k === 'nbr' ? '%↑' : k}
                </Chip>
              ))}
            </div>
            <div className="flex flex-wrap items-center gap-1.5">
              <SectionLabel className="mb-0">Filter</SectionLabel>
              {(['all', 'buy', 'sell'] as const).map((f) => (
                <Chip key={f} active={filter === f} onClick={() => setFilter(f)}>
                  {f}
                </Chip>
              ))}
            </div>
          </div>
        </div>
      </Card>

      <Card>
        <CardHeader
          eyebrow="Percent of neighbours"
          title="Goods"
          subtitle="Tap a good to load the order onto Command."
          aside={<Badge tone="accent">{shown.length} rows</Badge>}
        />
        <Table>
          <thead>
            <tr>
              <TH>Good</TH>
              <TH align="num">Buy</TH>
              <TH align="num">Sell</TH>
              <TH align="num">%NBR</TH>
              <TH>Stock</TH>
              <TH>7-day</TH>
              <TH>Note</TH>
            </tr>
          </thead>
          <tbody>
            {blocks.map((block) =>
              block.rows.length === 0 ? null : (
                <BlockRows key={block.band} label={block.label} band={block.band} rows={block.rows} onFill={fill} />
              ),
            )}
          </tbody>
        </Table>

        <dl className="mt-4 space-y-1 font-mono text-[11px] text-ink-faint">
          <div>
            tax {formatPct(effectiveTaxRate(port, taxRelief), 1)} (you) · Mayor's rate{' '}
            {formatPct(port.marketTaxRate, 1)} · spread {formatPct(spreadOf(port), 1)} at
            dev_commerce {port.devCommerce}
          </div>
          <div>
            neighbours: {neighbours.map((c) => model.portOf(c).name).join(', ') || 'none within range'}
          </div>
          <div>
            Orders execute in 10-tun steps, each repricing — buying raises the price you are still
            buying at (G.2).
          </div>
        </dl>
      </Card>

      {rows.every((r) => r.history7.length === 0) && (
        <Notice tone="neutral" className="text-xs">
          No seven-day series is recorded for {port.name} in the V0 fixture — a price history is a
          record of what happened and cannot be recomputed from present state. Lisboa and Cádiz
          carry one.
        </Notice>
      )}

      <Card tone="accent">
        <CardHeader
          eyebrow="How to read it"
          title="Below ninety, buy. Above a hundred and ten, sell."
        />
        <p className="text-sm text-ink-muted">
          The %NBR column is this port's price as a percentage of what the same good fetches in the
          ports within {NEIGHBOUR_RADIUS_NM} nm of it. It is the whole game in one column: it tells
          you nothing about whether a price is high, and everything about whether it is high{' '}
          <em>here</em>. Salt in {port.name} is not cheap because salt is cheap; it is cheap because
          somebody two days' sail away will pay more for it.
        </p>
      </Card>
    </Screen>
  )
}

function BlockRows({
  label,
  band,
  rows,
  onFill,
}: {
  label: string
  band: PriceBand
  rows: readonly MarketRow[]
  onFill: (row: MarketRow) => void
}) {
  return (
    <>
      <tr>
        <td colSpan={7} className="border-b border-edge px-2 pb-1 pt-4">
          <span
            className={[
              'font-mono text-[11px] uppercase tracking-wider',
              band === 'buy' ? 'text-success' : band === 'sell' ? 'text-accent' : 'text-ink-faint',
            ].join(' ')}
          >
            ▾ {label}
          </span>
        </td>
      </tr>
      {rows.map((row) => (
        <tr key={row.good.code}>
          <TD>
            <button
              type="button"
              onClick={() => onFill(row)}
              title={`${band === 'sell' ? 'SELL' : 'BUY'} ${row.good.name} — load onto Command`}
              className="min-h-11 w-full text-left"
            >
              <span className="block text-sm text-accent underline-offset-4 hover:underline">
                {row.good.name}
              </span>
              <span className="block font-mono text-[10px] text-ink-faint">{row.good.english}</span>
            </button>
          </TD>
          <TD align="num">{formatInt(row.ask)}</TD>
          <TD align="num">{formatInt(row.bid)}</TD>
          <TD align="num">
            <span
              className={
                row.band === 'buy' ? 'text-success' : row.band === 'sell' ? 'text-accent' : 'text-ink-muted'
              }
            >
              {row.nbr === null ? '—' : formatPctPoints(row.nbr)}
            </span>
          </TD>
          <TD>
            <span
              className="font-mono text-xs text-ink-muted"
              title={`${formatTuns(row.row.stock)} of a ${formatTuns(row.row.stockTarget)} target · daily cap ${formatTuns(row.dailyCap)}`}
            >
              {row.stockBand}
            </span>
          </TD>
          <TD>
            <span
              className={
                row.band === 'buy' ? 'text-success' : row.band === 'sell' ? 'text-accent' : 'text-ink-faint'
              }
            >
              <Sparkline values={row.history7} />
            </span>
          </TD>
          <TD>
            <span className="font-mono text-[11px] text-ink-faint">
              {row.event ? (
                <Badge tone={row.event.kind === 'PLUNGING' ? 'danger' : 'accent'}>
                  {row.event.kind} {row.event.kind === 'SOARING' ? '↑' : ''}
                </Badge>
              ) : row.stockRatio < 0.5 ? (
                'scarce'
              ) : row.stockRatio > 1.2 ? (
                'glut'
              ) : (
                ''
              )}
            </span>
          </TD>
        </tr>
      ))}
    </>
  )
}

function Chip({
  active,
  onClick,
  children,
}: {
  active: boolean
  onClick: () => void
  children: ReactNode
}) {
  return (
    <Button variant={active ? 'primary' : 'secondary'} onClick={onClick}>
      {children}
    </Button>
  )
}
