import { useMemo, useState } from 'react'
import { Button, DetailPage, Field, Figure, Note, Row, Skeleton, SummaryRow } from '../../components/ui'
import { formatDucats, formatInt, formatUnitPrice } from '../../lib/format'
import { cmdRequestCancel, cmdRequestPlace, type MarketGood, type PortRequests, type SnapshotPort } from '../../lib/rpc'
import { useT } from '../../lib/i18n'
import { fold, foldedMatch } from '../../lib/text'
import { MarketLeft } from '../../live/MarketLeft'
import { useMarketPick } from '../../live/marketPick'
import { RequestBoard } from '../../live/RequestBoard'
import { useRequests } from '../../live/useRequests'

// THE REQUEST PAGE — the owner's flow, one page (2026-10-31: *"Request i press, a page shows up,
// where i search trade good - press it, shows up chart, choose price to buy, and then the put the
// money in it. - the order is made"*).
//
// Search → press a good → its chart (the same MarketLeft the city's left region draws) → the price
// and the quantity → the payment → Place. The PAGE IS NOT THE GATE: cmd.request_place refuses
// anywhere but the home city on the SERVER (E_NOT_HOME); this page is only ever opened from the
// Request face, which the server's own `home` flag has already said belongs to the house.
//
// The payment shown is qty × price: both numbers are the PLAYER'S OWN (not a served price), so the
// multiplication is exact arithmetic on the two values she typed — and it is only ever a display;
// the escrow that is actually taken is the server's answer, and a refusal arrives typed under it.
export function RequestPage({
  port,
  goods,
  onClose,
}: {
  port: SnapshotPort
  goods: readonly MarketGood[]
  onClose: () => void
}) {
  const t = useT()
  const pin = useMarketPick((s) => s.pick)
  const [q, setQ] = useState('')
  const [good, setGood] = useState<MarketGood | null>(null)
  const [price, setPrice] = useState('')
  const [qty, setQty] = useState('1')
  const [sending, setSending] = useState(false)
  const [refusal, setRefusal] = useState<{ code: string | null; sentence: string } | null>(null)

  const shown = useMemo(() => {
    const f = fold(q.trim())
    return [...goods]
      .filter((g) => foldedMatch(f, g.name, g.code, g.category))
      .sort((a, b) => a.name.localeCompare(b.name))
  }, [goods, q])

  const choose = (g: MarketGood) => {
    setGood(g)
    pin(port.id, g)
    // the current ask is the honest starting price — the player may lower or raise it
    setPrice(String(Math.ceil(g.buy)))
    setRefusal(null)
  }

  const nQty = Number(qty)
  const nPrice = Number(price)
  const payable =
    Number.isFinite(nQty) && Number.isFinite(nPrice) && nQty > 0 && nPrice > 0
      ? Math.round(nQty * nPrice)
      : null

  const place = () => {
    if (!good || payable === null || sending) return
    setSending(true)
    setRefusal(null)
    void cmdRequestPlace(port.id, good.good_id, nQty, nPrice).then((r) => {
      setSending(false)
      if (r.ok) onClose()
      else setRefusal({ code: r.refusal.code, sentence: r.refusal.sentence })
    })
  }

  return (
    <DetailPage title={t('city.request')} onClose={onClose} data-testid="city-request-page">
      <div className="mx-auto w-full max-w-2xl">
        <Field
          value={q}
          onChange={(e) => setQ(e.target.value)}
          onClear={() => setQ('')}
          aria-label={t('city.requestSearch')}
          placeholder={t('city.requestSearch')}
          spellCheck={false}
          autoCorrect="off"
        />
        {good === null ? (
          <div className="mt-2" data-testid="city-request-goods">
            {shown.map((g) => (
              <SummaryRow
                key={g.good_id}
                title={g.name}
                figure={formatUnitPrice(g.buy)}
                onClick={() => choose(g)}
                data-testid={`city-request-good-${g.code}`}
              />
            ))}
          </div>
        ) : (
          <div className="mt-2">
            {/* THE CHART STANDS AT ITS OWN HEIGHT (2026-11-02, the HQ-on-a-phone slice): it was a 256-px box (`h-64`) around a card that is 276-420 px (the chart, its
                legend, the span picker, Range, In stock) — at 1280 the price and quantity inputs sat over the picker, at 390 the picker straddled the box's edge, and
                at 320 the rows were cut out of reach. The page's body is the one scroller; nothing in it needs a fixed window. */}
            <div data-testid="city-request-chart">
              <MarketLeft port={port} good={good} />
            </div>
            <div className="mt-2 grid grid-cols-2 gap-2">
              <Field
                value={price}
                onChange={(e) => setPrice(e.target.value)}
                onClear={() => setPrice('')}
                aria-label={t('city.requestPrice')}
                placeholder={t('city.requestPrice')}
                inputMode="numeric"
                spellCheck={false}
              />
              <Field
                value={qty}
                onChange={(e) => setQty(e.target.value)}
                onClear={() => setQty('')}
                aria-label={t('city.requestQty')}
                placeholder={t('city.requestQty')}
                inputMode="numeric"
                spellCheck={false}
              />
            </div>
            <Row
              label={t('city.requestPay')}
              value={<Figure value={payable === null ? '—' : formatDucats(payable)} tone={payable === null ? 'faint' : 'ink'} />}
            />
            {refusal !== null && (
              <Note tone="danger" code={refusal.code ?? undefined} className="mt-2">
                {refusal.sentence}
              </Note>
            )}
            <div className="mt-2">
              <Button onClick={place} disabled={payable === null || sending} data-testid="city-request-place">
                {t('city.requestPlace')}
              </Button>
            </div>
            <Row label={t('common.back')} chevron onClick={() => setGood(null)} hairline={false} />
          </div>
        )}
      </div>
    </DetailPage>
  )
}

// THE REQUESTS FACE OF THE HQ MARKET — two ideas, two headings (2026-11-11, remaster S7).
// "City requests" are the harbour's delivery jobs (world.contracts, the ONE RequestBoard Trade >
// City draws and the Map tray draws, read-only here: nobody delivers from HQ). "Your orders" are
// the player's own requests (world.requests, passed in by the caller, which already reads it for
// `home`) with the New request door under them.
export function RequestsFace({
  port,
  goods,
  own,
  aboard,
}: {
  port: SnapshotPort
  goods: readonly MarketGood[]
  own: PortRequests | null
  aboard: Readonly<Record<string, number>>
}) {
  const t = useT()
  const jobs = useRequests(port.id)
  const [requestPage, setRequestPage] = useState(false)
  const [cancelling, setCancelling] = useState<string | null>(null)
  return (
    <div className="mt-2" data-testid="city-market-requests">
      <div className="text-t-caption text-ink-faint" data-testid="city-jobs-heading">
        {t('city.jobsHeading')}
      </div>
      <RequestBoard
        requests={jobs.view?.contracts ?? null}
        loading={jobs.loading}
        aboard={aboard}
        docked={false}
        pick={null}
        onPick={() => undefined}
      />
      <div className="mt-4 text-t-caption text-ink-faint" data-testid="city-own-heading">
        {t('city.ownHeading')}
      </div>
      {own === null ? (
        <Skeleton className="h-20 w-full" />
      ) : own.requests.length === 0 ? (
        <Note tone="neutral">{t('city.requestNone')}</Note>
      ) : (
        own.requests.map((r) => (
          <div key={r.id} className="border-b border-edge py-1" data-testid={`city-open-request-${r.id}`}>
            <Row label={`${r.name} ×${formatInt(r.qty)}`} value={<Figure value={formatUnitPrice(r.unit_price)} />} />
            {/* THE LINE WRAPS (2026-11-02, the HQ-on-a-phone slice): word, sum held and Cancel are 190 px and the panel's room 139 at 390, 104 at 320 — the
                Cancel stood 43 px past the panel's edge at 390 and 78 at 320, cut off and unpressable. Under the sum, at the right edge, when they do not fit. */}
            <div className="flex min-h-11 flex-wrap items-center gap-x-2">
              <span className="text-t-caption text-ink-faint">{t('city.requestPay')}</span>
              <Figure value={formatDucats(r.escrow)} />
              <Button
                className="ml-auto"
                onClick={() => {
                  setCancelling(r.id)
                  void cmdRequestCancel(r.id).finally(() => setCancelling(null))
                }}
                disabled={cancelling === r.id}
              >
                {t('city.requestCancel')}
              </Button>
            </div>
          </div>
        ))
      )}
      <SummaryRow title={t('city.requestNew')} onClick={() => setRequestPage(true)} data-testid="city-request-new" />
      {requestPage && <RequestPage port={port} goods={goods} onClose={() => setRequestPage(false)} />}
    </div>
  )
}
