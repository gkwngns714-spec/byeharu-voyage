import { useState } from 'react'
import { Button, Figure, Note, Row, Skeleton, Stepper, Tray, type TrayDetent, type TrayMode } from '../../components/ui'
import { useServedRead } from '../../live/useServedRead'
import { useSettled } from '../../live/useSettled'
import { useWorld } from '../../live/worldStore'
import { cmdInvest, cmdPreviewInvest, ok, worldTownHall } from '../../lib/rpc'
import type { CityWork, InvestReceipt, Refusal, SnapshotPort, TownHallView, WorkKind } from '../../lib/rpc'
import { formatDucats, formatInt, formatPct } from '../../lib/format'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TOWN HALL — the city's fourth building: its purse, its works, Invest, and who invested
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-15: *"by clicking a city, there should be another building called town hall,
// where you click and can invest, and see who or what npcs invested."*
//
// ONE READ, `world.town_hall(port)` (0122/0123, docs/ECONOMY_LOOP.md §5): the purse, the last full
// day's book, the four works with what the next level offers, the investors by name, and what YOU
// hold here and whether a fleet of yours lies docked. Nothing here is computed: the share price,
// the shares on offer, whether you may press Invest (`you.docked`, the same test `cmd.invest`
// makes) are all served.
//
// INVEST is the Inn's shape: a stepper, the server's dry run of exactly that count
// (`cmd.preview_invest`, the real buy rolled back — the cost printed is the cost charged, or the
// refusal the press would get), and ONE button. Its tray stands `side-next`, beside the panel.
//
// DARK (the city purses ship off, 0122): the read says `enabled: false`, nothing is offered, and
// the tab says so in one line.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const WORK_NAME: Record<WorkKind, string> = {
  docks: 'Docks',
  market: 'Market',
  production: 'Workshops',
  inn: 'Inn',
}

/** The served answer or the served refusal, folded into one value (useOrderPreview's shape). */
interface Served<V> {
  view: V | null
  refusal: Refusal | null
}

function useTownHall(portId: string | null) {
  return useServedRead<Served<TownHallView>>(portId, async () => {
    const r = await worldTownHall(portId as string)
    return ok(r.ok ? { view: r.value, refusal: null } : { view: null, refusal: r.refusal })
  })
}

export function CityTownHall({ port, trayMode }: { port: SnapshotPort; trayMode?: TrayMode }) {
  const read = useTownHall(port.kind === 'HARBOUR' ? port.id : null)
  const [investing, setInvesting] = useState<CityWork | null>(null)

  if (port.kind !== 'HARBOUR') return <Note tone="neutral">No town hall here.</Note>
  const hall = read.view?.view ?? null
  if (!hall) {
    return read.view?.refusal ? (
      <Note tone="danger" code={read.view.refusal.code}>
        {read.view.refusal.sentence}
      </Note>
    ) : (
      <Skeleton className="mt-3 h-28 w-full" />
    )
  }

  const held = new Map(hall.you.holdings.map((h) => [h.kind, h]))
  const canInvest = hall.enabled && hall.you.docked

  return (
    <div data-testid="townhall">
      <Row
        label="Treasury"
        value={<Figure value={formatDucats(hall.purse.ducats)} size="figure" />}
        data-testid="townhall-treasury"
      />
      <Row
        label={purseLine(hall)}
        tone="muted"
        hairline={false}
        data-testid="townhall-purse-line"
      />

      <Heading>Works</Heading>
      {hall.works.map((w) => {
        const mine = held.get(w.kind)
        const built = w.level >= w.level_max
        return (
          <Row
            key={w.kind}
            label={
              <span>
                {WORK_NAME[w.kind]}{' '}
                <span aria-label={`level ${w.level} of ${w.level_max}`} className="tracking-widest text-ink-faint">
                  {'●'.repeat(w.level) + '○'.repeat(Math.max(0, w.level_max - w.level))}
                </span>
              </span>
            }
            value={
              built ? (
                'Built'
              ) : canInvest && w.offered > 0 ? (
                <Button size="sm" onClick={() => setInvesting(w)} data-testid={`townhall-invest-${w.kind}`}>
                  Invest
                </Button>
              ) : undefined
            }
            data-testid={`townhall-work-${w.kind}`}
          >
            {!built && w.share_price !== null && (
              <div className="text-t-caption tabular-nums text-ink-muted">
                {`${formatInt(w.subscribed)} of ${formatInt(w.subscribed + w.offered)} sold · ${formatDucats(w.share_price)} a share`}
              </div>
            )}
            {mine && (
              <div className="text-t-caption tabular-nums text-ink-muted" data-testid={`townhall-held-${w.kind}`}>
                {`You hold ${formatInt(mine.shares)}${mine.owed > 0 ? ` · ${formatDucats(mine.owed)} owed` : ''}`}
              </div>
            )}
          </Row>
        )
      })}
      {/* WHY NOTHING CAN BE PRESSED — one line, never a dead button per row. */}
      {!canInvest && (
        <Row
          label={hall.enabled ? 'Dock here to invest.' : 'Not selling shares yet.'}
          tone="muted"
          hairline={false}
          data-testid="townhall-invest-none"
        />
      )}

      <Heading>Investors</Heading>
      {hall.investors.length === 0 ? (
        <Row label="Nobody yet." tone="muted" hairline={false} data-testid="townhall-investors-none" />
      ) : (
        hall.investors.map((x, i) => (
          <Row
            key={`${x.name}:${x.kind}:${i}`}
            label={
              <span>
                {x.name}
                <span className="block text-t-caption text-ink-muted">
                  {`${x.merchant ? 'Merchant · ' : ''}${WORK_NAME[x.kind]} · ${formatInt(x.shares)} shares`}
                </span>
              </span>
            }
            value={<Figure value={formatDucats(x.paid)} />}
            data-testid="townhall-investor"
          />
        ))
      )}

      <DayBook hall={hall} />

      {investing && (
        <InvestTray
          key={`${port.id}:${investing.kind}`}
          port={port}
          work={investing}
          mode={trayMode}
          onClose={() => setInvesting(null)}
        />
      )}
    </div>
  )
}

function Heading({ children }: { children: string }) {
  return <h3 className="pb-1 pt-4 text-t-caption uppercase tracking-wider text-ink-faint">{children}</h3>
}

/** The one quiet line under the treasury: what the city does with its purse, and its tax. */
function purseLine(hall: TownHallView): string {
  if (!hall.enabled) return 'Not open yet.'
  const bid = hall.purse.bid_factor < 1 ? `Short of money · bids ${formatPct(hall.purse.bid_factor)}` : 'Buys up to its purse'
  return `${bid} · Tax ${formatPct(hall.purse.tax_rate)} on profit`
}

/** The last full day's money, in a few short rows — only the ones that moved. */
function DayBook({ hall }: { hall: TownHallView }) {
  const rows: [string, number][] = [
    ['Trade in', hall.day.in.BUY ?? 0],
    ['Trade out', hall.day.out.SELL ?? 0],
    ['Tax', hall.day.in.TAX ?? 0],
    ['Wages', hall.day.in.WAGES ?? 0],
    ['Shares', hall.day.in.SHARE ?? 0],
    ['Coupons', hall.day.out.DIVIDEND ?? 0],
  ]
  const moved = rows.filter(([, n]) => n !== 0)
  if (!hall.enabled || moved.length === 0) return null
  return (
    <div data-testid="townhall-day">
      <Heading>Yesterday</Heading>
      {moved.map(([label, n]) => (
        <Row key={label} label={label} value={<Figure value={formatDucats(n)} />} />
      ))}
    </div>
  )
}

/** INVEST: a count of shares, the server's dry run of exactly that count, and one button. */
function InvestTray({
  port,
  work,
  mode,
  onClose,
}: {
  port: SnapshotPort
  work: CityWork
  mode?: TrayMode
  onClose: () => void
}) {
  const [detent, setDetent] = useState<TrayDetent>('half')
  const [shares, setShares] = useState(() => Math.min(work.offered, 10))
  const [sending, setSending] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const refresh = useWorld((s) => s.refresh)

  // Only a count that has stood still is asked: the slider reports every step of a drag.
  const settled = useSettled(shares)
  const check = useServedRead<Served<InvestReceipt>>(
    `${port.id}:${work.kind}`,
    async () => {
      const r = await cmdPreviewInvest(port.id, work.kind, settled)
      return ok(r.ok ? { view: r.value, refusal: null } : { view: null, refusal: r.refusal })
    },
    { question: String(settled) },
  )
  const current = settled === shares && !check.stale ? check.view : null
  const estimate = current?.view ?? null
  const dryRefusal = current?.refusal ?? null

  const send = () => {
    if (sending) return
    setSending(true)
    setRefusal(null)
    void (async () => {
      const r = await cmdInvest(port.id, work.kind, shares)
      setSending(false)
      if (r.ok) {
        onClose()
        await refresh()
      } else {
        setRefusal(r.refusal)
      }
    })()
  }

  const shown = refusal ?? dryRefusal
  return (
    <Tray
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={`Invest in ${WORK_NAME[work.kind]}`}
      mode={mode}
      data-testid="townhall-invest-tray"
      action={
        <Button
          variant="primary"
          className="w-full"
          disabled={estimate === null || shares < 1}
          busy={sending}
          busyLabel="Investing…"
          onClick={send}
          data-testid="townhall-invest-send"
        >
          {estimate ? `Invest ${formatDucats(estimate.cost)}` : 'Invest'}
        </Button>
      }
    >
      <div className="py-3">
        <Stepper
          value={shares}
          onChange={setShares}
          min={1}
          max={work.offered}
          step={1}
          unit="shares"
          label="shares to buy"
          presets={[{ label: 'Max', value: work.offered }]}
          data-testid="townhall-invest-stepper"
        />
      </div>
      {estimate && (
        <Row
          label={estimate.completed ? 'Cost · completes the level' : 'Cost'}
          value={<Figure value={formatDucats(estimate.cost)} />}
          hairline={false}
          data-testid="townhall-invest-cost"
        />
      )}
      {shown && (
        <Note tone="danger" code={shown.code}>
          {shown.sentence}
        </Note>
      )}
    </Tray>
  )
}
