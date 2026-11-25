import { useCallback, useState } from 'react'
import { DetailPage, Icon } from '../../../components/ui'
import { formatClock, formatDucatsDelta, formatInt, instantMs } from '../../../lib/format'
import { useT, type TKey } from '../../../lib/i18n'
import type { HqRate, HqRateCargo, HqRateLine } from '../../../lib/rpc'
import { useWorkers } from '../corp/workerRows'
import type { Board } from './useBoard'

// THE RATE SAYS WHY (owner, 2026-11-24: "i am -19.649 / hour. it should say why"; then "why investing causes les money? wtf?").
// 0493's one authority (public.company_rate_for, served as world.hq_board().rate) groups her last 24 hours of ledger into plain lines.
// The headline is her RUNNING income and costs only; a purchase made once (investing, a hull, hiring) stands under it in a neutral
// tone, never as an hourly loss. Under the figure: one fixed-height line naming the biggest causes (the server's `top`). A press on
// the figure opens, over HQ, the sheet of every line in two groups, Running and One time.
// EVERY FIGURE IS THE SERVER'S: this file formats and picks rows; it adds, divides and ranks nothing.
// v1's board (the switch dark) and a server before 0493 serve no lines: the plain figure, as before.

const LINE_WORD: Record<string, TKey> = {
  trade: 'hq.rateTrade',
  contracts: 'hq.rateContracts',
  dividends: 'hq.rateDividends',
  rewards: 'hq.rateRewards',
  sea: 'hq.rateSea',
  wages: 'hq.rateWages',
  tax: 'hq.rateTax',
  dock: 'hq.rateDock',
  stores: 'hq.rateStores',
  repairs: 'hq.rateRepairs',
  tow: 'hq.rateTow',
  insurance: 'hq.rateInsurance',
  fines: 'hq.rateFines',
  other: 'hq.rateOther',
  invest: 'hq.rateInvest',
  ships: 'hq.rateShips',
  hiring: 'hq.rateHiring',
  training: 'hq.rateTraining',
  gear: 'hq.rateGear',
  room: 'hq.rateRoom',
  gifts: 'hq.rateGifts',
  cargo_lost: 'hq.rateCargoLost',
}
/** A line's word; a line the server names later reads as Other until it has its own. */
const wordOf = (line: string): TKey => LINE_WORD[line] ?? 'hq.rateOther'

/** A signed figure with no coin mark, for the short lines: 2400 -> "+2,400", -6932 -> "−6,932". */
const signed = (n: number) => (n > 0 ? `+${formatInt(n)}` : formatInt(n))
/** What a purchase took, as a plain amount ("Invested 461,384"); coin that came in keeps its plus. */
const spent = (n: number) => (n < 0 ? formatInt(-n) : signed(n))
const toneOf = (n: number) => (n < 0 ? 'text-danger' : n > 0 ? 'text-success' : 'text-ink-muted')

/** A slot one caption line high, held whether its words are here yet or not: nothing under the strip moves when they arrive. */
const HELD_LINE = 'flex h-[1.125rem] min-w-0 flex-wrap content-start gap-x-1 overflow-hidden text-t-caption tabular-nums text-ink-muted md:justify-end'

export function RateWhy({ board }: { board: Board }) {
  const t = useT()
  const [open, setOpen] = useState(false)
  const close = useCallback(() => setOpen(false), [])
  const { rows } = useWorkers()
  if (board.perHour === null) return null
  // A FRESH RUN HAS NO RATE YET: what she put into her first cargo is not an hourly loss. Said while the figure is under nought and
  // every fleet at work is on her first runs (the server serves no rate for her: basis none).
  const working = rows.filter((r) => r.kind === 'fleet' && r.state === 'working')
  const fresh = board.perHour < 0 && working.length > 0 && working.every((r) => r.rates?.basis === 'none')
  const rate = board.rate
  const lines = rate?.lines
  if (!rate || !lines) {
    return (
      <span
        className={`flex min-h-11 items-center text-t-figure tabular-nums ${toneOf(board.perHour)}`}
        title={t(board.served ? 'hq.rateDay' : 'hq.rateToday')}
        data-testid="hq-bridge-rate"
        data-span={board.served ? '24h' : 'today'}
      >
        {t('hq.perHour', { n: formatDucatsDelta(board.perHour) })}
      </span>
    )
  }
  const byLine = new Map(lines.map((l) => [l.line, l]))
  const top = (rate.top ?? []).flatMap((code) => {
    const l = byLine.get(code)
    return l && !l.one_time ? [l] : []
  })
  const once = lines.filter((l) => l.one_time)
  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-haspopup="dialog"
        aria-expanded={open}
        title={t('hq.rateDay')}
        data-testid="hq-bridge-rate"
        data-span="24h"
        data-per-hour={rate.per_hour}
        className="-mx-1 flex h-11 min-w-0 items-center gap-2 rounded-control px-1 text-left tabular-nums transition hover:bg-surface-2"
      >
        <span className={`flex items-center gap-1 text-t-figure ${fresh ? 'text-ink-muted' : toneOf(rate.per_hour)}`} data-testid="hq-rate-figure" data-fresh={fresh}>
          {fresh ? t('hq.measuring') : t('hq.perHour', { n: formatDucatsDelta(rate.per_hour) })}
          <Icon name="chevron" size={14} aria-hidden />
        </span>
        <span className="whitespace-nowrap text-t-caption text-ink-faint">{t('hq.rateLast')}</span>
      </button>
      <span className={HELD_LINE} data-testid="hq-rate-causes">
        {top.map((l, i) => (
          <span key={l.line} className="whitespace-nowrap" data-line={l.line}>
            {`${t(wordOf(l.line))} ${signed(l.total_24h)}${i < top.length - 1 ? ' ·' : ''}`}
          </span>
        ))}
      </span>
      {/* her biggest purchase of the day (the server's order: the largest first), neutral; the rest are in the sheet */}
      {once.length > 0 && (
        <span className={HELD_LINE} data-testid="hq-rate-once" data-line={once[0].line}>
          <span className="whitespace-nowrap">{`${t(wordOf(once[0].line))} ${spent(once[0].total_24h)}`}</span>
          <span className="whitespace-nowrap">{`· ${t('hq.rateOnceLow')}`}</span>
        </span>
      )}
      {open && <RateSheet rate={rate} lines={lines} onClose={close} />}
    </>
  )
}

/** THE SHEET: the game's one pop-up page (components/ui DetailPage), over HQ. Its back arrow and Escape close it; the page behind is
 *  not re-flowed. The browser's back is DetailPage's own (useBackLayer), for every page at once. */
function RateSheet({ rate, lines, onClose }: { rate: HqRate; lines: HqRateLine[]; onClose: () => void }) {
  const t = useT()
  const running = lines.filter((l) => !l.one_time)
  const once = lines.filter((l) => l.one_time)
  return (
    <DetailPage
      title={t('hq.rateWhy')}
      figure={
        <span className={toneOf(rate.per_hour)} data-testid="hq-rate-sheet-figure" data-per-hour={rate.per_hour}>
          {formatDucatsDelta(rate.per_hour)}
        </span>
      }
      word={t('hq.rateLast')}
      onClose={onClose}
      data-testid="hq-rate-sheet"
    >
      <Group testid="hq-rate-running" heading={t('hq.rateRunning')} total={rate.net_24h} perHour={rate.per_hour} lines={running} />
      {once.length > 0 && rate.one_time_24h !== undefined && (
        <Group testid="hq-rate-onetime" heading={t('hq.rateOnce')} total={rate.one_time_24h} perHour={null} lines={once} />
      )}
      {rate.cargo && rate.all_24h !== undefined && <Cargo cargo={rate.cargo} all={rate.all_24h} />}
    </DetailPage>
  )
}

const ROW = 'grid grid-cols-[minmax(0,1fr)_5.5rem_6.5rem] items-baseline gap-x-2 py-1.5 tabular-nums'

/** 0501: HER CARGO AT COST, neutral (never red: goods she holds are not a loss), and the sum the sheet comes to. The server's
 *  figures: Running + One time + Cargo = All coin (her ledger's 24 hours). Lost cargo is recorded from 0501's deploy on: until the
 *  whole window lies after it, the sheet says from when. */
function Cargo({ cargo, all }: { cargo: HqRateCargo; all: number }) {
  const t = useT()
  const since = instantMs(cargo.exact_since)
  return (
    <section className="pt-3" data-testid="hq-rate-cargo" data-total={cargo.net_24h} data-at-cost={cargo.at_cost}>
      <div className={`${ROW} border-b border-edge text-t-caption text-ink-muted`}>
        <h2 className="text-t-label font-semibold text-ink">{t('hq.rateCargo')}</h2>
        <span />
        <span className="text-right">{t('hq.rateColDay')}</span>
      </div>
      <div className={`${ROW} text-t-caption`} data-testid="hq-rate-cargo-line">
        <span className="text-t-body text-ink">{`${t('hq.rateCargo')} ${formatInt(cargo.at_cost)}`}</span>
        <span className="text-right text-ink-muted">{t('hq.rateAtCost')}</span>
        <span className="text-right text-ink">{signed(cargo.net_24h)}</span>
      </div>
      {!cargo.exact && since !== null && (
        <p className="pb-1 text-t-caption text-ink-faint" data-testid="hq-rate-cargo-since">
          {t('hq.rateCargoSince', { t: formatClock(since) })}
        </p>
      )}
      <div className={`${ROW} border-t border-edge text-t-caption font-semibold`} data-testid="hq-rate-all" data-total={all}>
        <span className="text-ink">{t('hq.rateAll')}</span>
        <span />
        <span className="text-right text-ink">{signed(all)}</span>
      </div>
    </section>
  )
}

/** One group: its heading, then every line (its word and count, per hour or the One time tag, its total over the 24 hours), then the
 *  group's own figures, the server's. A purchase is neutral, never red. */
function Group({ testid, heading, total, perHour, lines }: { testid: string; heading: string; total: number; perHour: number | null; lines: HqRateLine[] }) {
  const t = useT()
  const tone = (n: number) => (perHour === null ? 'text-ink' : toneOf(n))
  return (
    <section className="pt-3" data-testid={testid} data-total={total}>
      <div className={`${ROW} border-b border-edge text-t-caption text-ink-muted`}>
        <h2 className="text-t-label font-semibold text-ink">{heading}</h2>
        <span className="text-right">{perHour === null ? '' : t('hq.rateColHour')}</span>
        <span className="text-right">{t('hq.rateColDay')}</span>
      </div>
      {lines.length === 0 && <p className="py-2 text-t-caption text-ink-faint">{t('hq.rateNone')}</p>}
      {lines.map((l) => (
        <div key={l.line} className={`${ROW} text-t-caption`} data-testid="hq-rate-line" data-line={l.line} data-total={l.total_24h} data-one-time={l.one_time}>
          <span className="flex min-w-0 flex-wrap items-baseline gap-x-1.5 text-t-body text-ink">
            {t(wordOf(l.line))}
            <span className="text-t-caption text-ink-faint">{t('hq.rateTimes', { n: formatInt(l.count) })}</span>
          </span>
          {l.one_time ? (
            <span className="text-right text-ink-muted" data-testid="hq-rate-tag">
              {t('hq.rateOnce')}
            </span>
          ) : (
            <span className={`text-right ${tone(l.per_hour)}`}>{signed(l.per_hour)}</span>
          )}
          <span className={`text-right ${tone(l.total_24h)}`}>{signed(l.total_24h)}</span>
        </div>
      ))}
      <div className={`${ROW} border-t border-edge text-t-caption font-semibold`} data-testid={`${testid}-sum`}>
        <span />
        <span className={`text-right ${perHour === null ? '' : tone(perHour)}`}>{perHour === null ? '' : signed(perHour)}</span>
        <span className={`text-right ${tone(total)}`}>{signed(total)}</span>
      </div>
    </section>
  )
}
