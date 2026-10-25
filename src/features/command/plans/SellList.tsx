import { Col, Cols, Hint, Row, Skeleton } from '../../../components/ui'
import { PortFlag } from '../../../live/PortFlag'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { formatPrice, formatPriceDelta, formatVoyageDays } from '../../../lib/format'
import type { BoardSellRow, GoodBoard } from '../../../lib/rpc'
import { useDeskPlan, type PlanDraft } from './planDraft'
import { useT } from '../../../lib/i18n'

// THE SELL LIST — "where can I sell X" (docs/COMMAND_REDESIGN.md §2, owner row 190). Every sell row the board
// serves for the picked good, each its own press: open rows first in the board's own order (it is SORTED by
// net, server-side), shut rows last and not pressable, with a 1–2 word reason (row 202). A press sets the plan's
// sell city; the card's figures change in place and nothing here moves.
//
// THE REASON IS THE SERVER'S. A row is shut when the board marks it `sailable: false` (0188: no chain of legs
// within her captain's reach, or her hold cannot carry the stores its longest leg asks — `supplies.fits`, 0225).
// The words: no passage → Too far; the stores do not fit → Cargo full; anything else the server shuts → Shut.
// R2 hands the gate's own code per row; these words then read it instead.
//
// Every row is a `Row` with its figures in `Col`s of the one width scale (owner rows 196–201: every list lines
// up): the price, the days (stood down on a phone: the card says them), the profit.

export function SellList({ plan, board, loading }: { plan: PlanDraft; board: GoodBoard | null; loading: boolean }) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const set = useDeskPlan((s) => s.set)
  const name = (c: string) => portNameOf(portByCode, c)
  const open = (board?.sell ?? []).filter((r) => r.sailable !== false)
  const shut = (board?.sell ?? []).filter((r) => r.sailable === false)
  const reason = (r: BoardSellRow) => (r.stops == null ? t('desk.far') : r.supplies && !r.supplies.fits ? t('desk.holdFull') : t('desk.shut'))
  return (
    <div className="mt-4" data-testid="trade-sell-list">
      <span className="block text-t-caption text-ink-faint">{t('desk.sell')}</span>
      {loading && !board ? (
        Array.from({ length: 5 }, (_, i) => <Skeleton key={i} className="my-1 h-row w-full" />)
      ) : !board || board.sell.length === 0 ? (
        <Hint>{t('desk.noSellers')}</Hint>
      ) : (
        <>
          {open.map((r, i) => (
            <Row
              key={r.port}
              label={
                <>
                  <PortFlag code={r.port} /> {name(r.port)}
                </>
              }
              value={
                <Cols>
                  <Col w="sm">{formatPrice(r.price_each ?? r.mid)}</Col>
                  <Col w="md" phone="hide" className="text-t-caption text-ink-faint">
                    {r.days !== null ? formatVoyageDays(r.days) : '—'}
                  </Col>
                  <Col w="lg" className={r.profit == null ? 'text-ink-faint' : r.profit >= 0 ? 'text-success' : 'text-danger'}>
                    {r.profit != null ? formatPriceDelta(r.profit) : '—'}
                  </Col>
                </Cols>
              }
              tone={plan.sellAt === r.port ? 'accent' : 'default'}
              hairline={i < open.length - 1 || shut.length > 0}
              onClick={() => set({ sellAt: r.port })}
              aria-pressed={plan.sellAt === r.port}
              data-testid="trade-sell-row"
              data-port={r.port}
            />
          ))}
          {shut.length > 0 && (
            <>
              <span className="mt-3 block text-t-caption text-ink-faint">{t('desk.shut')}</span>
              {shut.map((r, i) => (
                <Row
                  key={r.port}
                  label={
                    <>
                      <PortFlag code={r.port} /> {name(r.port)}
                    </>
                  }
                  value={
                    <Cols>
                      <Col w="sm">{formatPrice(r.mid)}</Col>
                      <Col w="lg" className="text-t-caption">
                        {reason(r)}
                      </Col>
                    </Cols>
                  }
                  tone="muted"
                  hairline={i < shut.length - 1}
                  data-testid="trade-sell-shut"
                  data-port={r.port}
                />
              ))}
            </>
          )}
        </>
      )}
    </div>
  )
}
