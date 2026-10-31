import { useState } from 'react'
import { Button, Figure, Note, Row, Skeleton, Stepper, Tray, type TrayDetent, type TrayMode } from '../components/ui'
import { useServedRead } from './useServedRead'
import { useSettled } from './useSettled'
import { useTownHall } from './useTownHall'
import { useWorld } from './worldStore'
import { cmdInvest, cmdPreviewInvest, ok } from '../lib/rpc'
import type { CityWork, InvestReceipt, Refusal, SnapshotPort, TownHallGift, TownHallView } from '../lib/rpc'
import { formatDucats, formatInt, formatPct, formatRelative } from '../lib/format'
import { useShellState } from '../app/shellState'
import { TownHallInfluence } from './TownHallInfluence'
import { InvestorRow } from './CityInvestors'
import { WORK_NAME } from './workNames'
import { duesWords } from '../domain/port'
import { useT, t as tNow } from '../lib/i18n'

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


/** The served answer or the served refusal, folded into one value (useOrderPreview's shape). */
interface Served<V> {
  view: V | null
  refusal: Refusal | null
}

export function CityTownHall({ port, trayMode }: { port: SnapshotPort; trayMode?: TrayMode }) {
  const t = useT()
  const read = useTownHall(port.kind === 'HARBOUR' ? port.id : null)
  const [investing, setInvesting] = useState<CityWork | null>(null)

  if (port.kind !== 'HARBOUR') return <Note tone="neutral">{t('town.noHall')}</Note>
  const hall = read.view?.view ?? null
  if (!hall) {
    return read.view?.refusal ? (
      <Note tone="danger" code={read.view.refusal.code} figures={read.view.refusal.figures}>
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
        label={t('town.treasury')}
        value={<Figure value={formatDucats(hall.purse.ducats)} size="figure" />}
        data-testid="townhall-treasury"
      />
      <Row
        label={purseLine(hall)}
        tone="muted"
        hairline={false}
        data-testid="townhall-purse-line"
      />

      {/* 0144: who holds the city, each country's influence, Donate (docs/INFLUENCE.md §7.1). */}
      <Heading>{t('town.influence')}</Heading>
      <TownHallInfluence port={port} influence={hall.influence} docked={hall.you.docked} trayMode={trayMode} />

      <Heading>{t('town.works')}</Heading>
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
                t('town.built')
              ) : canInvest && w.offered > 0 ? (
                <Button size="sm" onClick={() => setInvesting(w)} data-testid={`townhall-invest-${w.kind}`}>
                  {t('town.invest')}
                </Button>
              ) : undefined
            }
            data-testid={`townhall-work-${w.kind}`}
          >
            {!built && w.share_price !== null && (
              <div className="text-t-caption tabular-nums text-ink-muted">
                {t('town.sold', { sold: formatInt(w.subscribed), total: formatInt(w.subscribed + w.offered), price: formatDucats(w.share_price) })}
              </div>
            )}
            {mine && (
              <div className="text-t-caption tabular-nums text-ink-muted" data-testid={`townhall-held-${w.kind}`}>
                {t('town.youHold', { n: formatInt(mine.shares), owed: mine.owed > 0 ? t('town.owed', { amount: formatDucats(mine.owed) }) : '' })}
              </div>
            )}
          </Row>
        )
      })}
      {/* WHY NOTHING CAN BE PRESSED — one line, never a dead button per row. */}
      {!canInvest && (
        <Row
          label={t(hall.enabled ? 'town.dockToInvest' : 'town.notSelling')}
          tone="muted"
          hairline={false}
          data-testid="townhall-invest-none"
        />
      )}

      {/* 0278 (docs/WEEKLY_ROLLOVER.md): the board is the city's giving over ALL time — money stays;
          only the History tab is monthly. Shares and `you.holdings` are untouched as well. */}
      <Heading>{t('town.investors')}</Heading>
      {hall.investors.length === 0 ? (
        <Row label={t('town.nobody')} tone="muted" hairline={false} data-testid="townhall-investors-none" />
      ) : (
        hall.investors.map((x, i) => <InvestorRow key={`${x.name}:${i}`} investor={x} />)
      )}

      {/* 0234: the capital's gifts to broke merchants (docs/CLOSED_ECONOMY.md §5.3) — only once it has given one. */}
      {hall.gifts && hall.gifts.length > 0 && <Gifts gifts={hall.gifts} />}

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
  if (!hall.enabled) return tNow('town.notOpen')
  const bid =
    hall.purse.bid_factor < 1 ? tNow('town.short', { pct: formatPct(hall.purse.bid_factor) }) : tNow('town.buysUp')
  const line = tNow('town.taxLine', { bid, pct: formatPct(hall.purse.tax_rate) })
  // 0237 (§4c): what this harbour asks YOUR company — "Tax 2× (rival) · Dock fee 50" — while the economy is closed
  return hall.dues ? `${line} · ${duesWords(hall.dues)}` : line
}

/** 0234: "Gave Casa X · 2 h ago … 5,000" — the capital's newest gifts, as served. */
function Gifts({ gifts }: { gifts: TownHallGift[] }) {
  const t = useT()
  const { nowMs } = useShellState()
  return (
    <div data-testid="townhall-gifts">
      <Heading>{t('town.giftsGiven')}</Heading>
      {gifts.map((g, i) => (
        <Row
          key={`${g.name}:${g.at}:${i}`}
          label={
            <span>
              {t('town.gave', { name: g.name })}
              <span className="block text-t-caption text-ink-muted">{formatRelative(Date.parse(g.at), nowMs)}</span>
            </span>
          }
          value={<Figure value={formatDucats(g.ducats)} />}
          data-testid="townhall-gift"
        />
      ))}
    </div>
  )
}

/** The last full day's money, in a few short rows — only the ones that moved. */
function DayBook({ hall }: { hall: TownHallView }) {
  const t = useT()
  const rows: [string, number][] = [
    [t('town.d_tradeIn'), hall.day.in.BUY ?? 0],
    [t('town.d_tradeOut'), hall.day.out.SELL ?? 0],
    // 0174: of what it paid for cargo, the part its people paid (the distance premium).
    [t('town.d_people'), hall.day.in.IMPORT_DEMAND ?? 0],
    [t('town.d_tax'), hall.day.in.TAX ?? 0],
    [t('town.d_wages'), hall.day.in.WAGES ?? 0],
    [t('town.d_shares'), hall.day.in.SHARE ?? 0],
    [t('town.d_gifts'), hall.day.in.DONATION ?? 0],
    [t('town.d_coupons'), hall.day.out.DIVIDEND ?? 0],
    // 0172: the grant, the city's own earnings, and what passes between it and its capital.
    [t('town.d_grant'), hall.day.in.GRANT ?? 0],
    [t('town.d_earnings'), hall.day.in.EARNINGS ?? 0],
    // 0234: a capital's call on its realm (CROWN_CALL) is crown money too.
    [t('town.d_fromCrown'), (hall.day.in.CROWN_TAX ?? 0) + (hall.day.in.CROWN_AID ?? 0) + (hall.day.in.CROWN_CALL ?? 0)],
    [t('town.d_toCrown'), (hall.day.out.CROWN_TAX ?? 0) + (hall.day.out.CROWN_AID ?? 0) + (hall.day.out.CROWN_CALL ?? 0)],
    // 0234: what a capital gave broke merchants.
    [t('town.d_capitalGifts'), hall.day.out.CAPITAL_GIFT ?? 0],
  ]
  const moved = rows.filter(([, n]) => n !== 0)
  if (!hall.enabled || moved.length === 0) return null
  return (
    <div data-testid="townhall-day">
      <Heading>{t('town.yesterday')}</Heading>
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
  const t = useT()
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
      title={t('town.investIn', { work: WORK_NAME[work.kind] })}
      mode={mode}
      data-testid="townhall-invest-tray"
      action={
        <Button
          variant="primary"
          className="w-full"
          disabled={estimate === null || shares < 1}
          busy={sending}
          busyLabel={t('town.investing')}
          onClick={send}
          data-testid="townhall-invest-send"
        >
          {estimate ? t('town.investAmount', { amount: formatDucats(estimate.cost) }) : t('town.invest')}
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
          unit={t('trade.sharesUnit')}
          label={t('town.sharesToBuy')}
          presets={[{ label: t('town.max'), value: work.offered }]}
          data-testid="townhall-invest-stepper"
        />
      </div>
      {estimate && (
        <Row
          label={t(estimate.completed ? 'town.costCompletes' : 'town.cost')}
          value={<Figure value={formatDucats(estimate.cost)} />}
          hairline={false}
          data-testid="townhall-invest-cost"
        />
      )}
      {shown && (
        <Note tone="danger" code={shown.code} figures={shown.figures}>
          {shown.sentence}
        </Note>
      )}
    </Tray>
  )
}
