import { useState } from 'react'
import { Bar, Button, Figure, Note, Row, Stepper, Tray, type TrayDetent, type TrayMode } from '../components/ui'
import { useServedRead } from './useServedRead'
import { useSettled } from './useSettled'
import { HullCountry } from './HullCountry'
import { nationNameOf, useWorld } from './worldStore'
import { cmdDonate, cmdPreviewDonate, cmdSetTax, ok } from '../lib/rpc'
import type { CityInfluence, DonateReceipt, Refusal, SnapshotPort } from '../lib/rpc'
import { formatDucats, formatInt, formatPct, formatDate } from '../lib/format'
import { useT } from '../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TOWN HALL'S INFLUENCE (0144, docs/INFLUENCE.md I2 and §7.1)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-17: "make the city have more influence [for that country] by investing and
// spending money to that city". ONE served block (`world.town_hall(port).influence`): who holds
// the city, whether it is a home city, one bar per country with at least 1 % (the share is served,
// never computed here), your own influence, and DONATE — the Invest shape: a stepper, the server's
// dry run of exactly that gift (`cmd.preview_donate`), one button. Only while a fleet of yours
// lies docked here (`you.docked`, the Town Hall's test) and the race is on (`open`).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** A share under this is not drawn as a bar (it would be a sliver). */
const SHOWN_SHARE = 0.01

interface Served<V> {
  view: V | null
  refusal: Refusal | null
}

export function TownHallInfluence({
  port,
  influence,
  docked,
  trayMode,
  showTax = true,
  compact = false,
}: {
  port: SnapshotPort
  influence: CityInfluence
  docked: boolean
  trayMode?: TrayMode
  /** The City page's in-place Town Hall panel shows the influence WITHOUT the tax rows (owner,
   *  2026-10-31: "no need market info. tax info. influence yes"). The map's Town Hall and the
   *  desk's Invest keep them: they never pass this. */
  showTax?: boolean
  /** The City page's NARROW panel (owner: "you know that this game is also for mobile right?"):
   *  the holder row keeps the flag and the name but drops the Home city / Contested word (the page
   *  header already says Home city), and the home-of caption rows go — the same served facts, two
   *  lines less in a 136-171 px panel. */
  compact?: boolean
}) {
  const t = useT()
  const nationByCode = useWorld((s) => s.nationByCode)
  const [giving, setGiving] = useState(false)
  const shown = influence.shares.filter((s) => s.share >= SHOWN_SHARE)
  const you = influence.you
  const room = you ? Math.max(0, you.cap - you.given_today) : 0
  const canGive = influence.open && docked && you !== null && room >= you.min

  return (
    <div data-testid="townhall-influence">
      <Row
        label={
          influence.holder ? (
            <HullCountry nation={influence.holder} />
          ) : (
            <span>{t('books.noCountry')}</span>
          )
        }
        value={
          compact ? undefined : (
            <span className="text-t-caption text-ink-muted">
              {t(influence.home ? 'books.homeCity' : 'books.contested')}
            </span>
          )
        }
        data-testid="townhall-holder"
      />
      {!compact && influence.home && influence.holder && (
        <Row
          label={t('books.homeOf', { nation: nationNameOf(nationByCode, influence.holder) })}
          tone="muted"
          hairline={false}
          data-testid="townhall-home"
        />
      )}
      {shown.length === 0 ? (
        <Row label={t('books.nobodyGiven')} tone="muted" hairline={false} data-testid="townhall-influence-none" />
      ) : (
        shown.map((s) => (
          <Row
            key={s.nation}
            label={<HullCountry nation={s.nation} />}
            value={<Figure value={formatPct(s.share)} size="body" />}
            hairline={false}
            data-testid="townhall-influence-share"
          >
            <Bar pct={s.share * 100} label={`${nationNameOf(nationByCode, s.nation)} influence`} className="mt-1" />
          </Row>
        ))
      )}
      {/* 0147: the mayor — the holder's top giver who sails for it (D8) — and the rate they set. */}
      {showTax && influence.mayor && (
        <Row
          label={t('books.mayor', { name: influence.mayor.name })}
          value={
            influence.mayor.tax_rate !== null ? (
              <span className="text-t-caption text-ink-muted">{t('books.tax', { pct: formatPct(influence.mayor.tax_rate, 1) })}</span>
            ) : undefined
          }
          tone="muted"
          hairline={false}
          data-testid="townhall-mayor"
        />
      )}
      {showTax && you && you.mayor && <MayorTax port={port} setAt={influence.mayor?.tax_set_at ?? null} />}
      {showTax && you && influence.open && (
        <Row
          label={t('books.yourTax', {
            pct: formatPct(you.tax_rate, 1),
            half: you.nation !== null && you.nation === influence.holder ? t('books.half') : '',
          })}
          tone="muted"
          hairline={false}
          data-testid="townhall-your-tax"
        />
      )}
      {you && (
        <Row
          label={t('books.yourInfluence')}
          value={<Figure value={formatInt(you.points)} />}
          data-testid="townhall-influence-you"
        >
          {influence.open && (
            <div className="text-t-caption tabular-nums text-ink-muted" data-testid="townhall-given-today">
              {t('books.givenToday', { given: formatDucats(you.given_today), cap: formatDucats(you.cap) })}
            </div>
          )}
        </Row>
      )}
      {influence.next_count && (
        <Row
          label={t('books.nextCount', {
            time: formatDate(Date.parse(influence.next_count), { hour: '2-digit', minute: '2-digit', hour12: false }),
          })}
          tone="muted"
          hairline={false}
          data-testid="townhall-next-count"
        />
      )}
      {canGive ? (
        <div className="pt-2">
          <Button onClick={() => setGiving(true)} data-testid="townhall-donate">
            {t('books.donate')}
          </Button>
        </div>
      ) : (
        <Row
          label={t(!influence.open ? 'books.notTaking' : !docked ? 'books.dockToDonate' : 'books.givenAll')}
          tone="muted"
          hairline={false}
          data-testid="townhall-donate-none"
        />
      )}
      {giving && you && (
        <DonateTray key={port.id} port={port} min={you.min} room={room} mode={trayMode} onClose={() => setGiving(false)} />
      )}
    </div>
  )
}

/** THE MAYOR'S TAX (0147): 0 to 20 %, once a day — the server refuses anything else and says why. */
function MayorTax({ port, setAt }: { port: SnapshotPort; setAt: string | null }) {
  const t = useT()
  const [pct, setPct] = useState(10)
  const [busy, setBusy] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const refresh = useWorld((s) => s.refresh)
  const send = async () => {
    setBusy(true)
    setRefusal(null)
    const r = await cmdSetTax(port.id, pct / 100)
    setBusy(false)
    if (r.ok) await refresh()
    else setRefusal(r.refusal)
  }
  return (
    <div className="py-2" data-testid="townhall-mayor-tax">
      <Stepper value={pct} onChange={setPct} min={0} max={20} step={1} unit="%" label={t('books.profitTax')} />
      <div className="mt-2">
        <Button size="sm" busy={busy} busyLabel={t('books.setting')} onClick={() => void send()} data-testid="townhall-mayor-tax-set">
          {t(setAt ? 'books.setTaxOnce' : 'books.setTax', { pct })}
        </Button>
      </div>
      {refusal && (
        <Note tone="danger" code={refusal.code} figures={refusal.figures} className="mt-2">
          {refusal.sentence}
        </Note>
      )}
    </div>
  )
}

/** DONATE: an amount, the server's dry run of exactly that gift, and one button. */
function DonateTray({
  port,
  min,
  room,
  mode,
  onClose,
}: {
  port: SnapshotPort
  min: number
  room: number
  mode?: TrayMode
  onClose: () => void
}) {
  const t = useT()
  const [detent, setDetent] = useState<TrayDetent>('half')
  const [coin, setCoin] = useState(() => Math.min(room, Math.max(min, 1000)))
  const [sending, setSending] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const refresh = useWorld((s) => s.refresh)
  const settled = useSettled(coin)
  const check = useServedRead<Served<DonateReceipt>>(
    port.id,
    async () => {
      const r = await cmdPreviewDonate(port.id, settled)
      return ok(r.ok ? { view: r.value, refusal: null } : { view: null, refusal: r.refusal })
    },
    { question: String(settled), name: 'cmdPreviewDonate', cache: false },
  )
  const current = settled === coin && !check.stale ? check.view : null
  const estimate = current?.view ?? null
  const shown = refusal ?? current?.refusal ?? null

  const send = () => {
    if (sending) return
    setSending(true)
    setRefusal(null)
    void (async () => {
      const r = await cmdDonate(port.id, coin)
      setSending(false)
      if (r.ok) {
        onClose()
        await refresh()
      } else setRefusal(r.refusal)
    })()
  }

  return (
    <Tray
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={t('books.donateTo', { port: port.name })}
      mode={mode}
      data-testid="townhall-donate-tray"
      action={
        <Button
          variant="primary"
          className="w-full"
          disabled={estimate === null}
          busy={sending}
          busyLabel={t('books.donating')}
          onClick={send}
          data-testid="townhall-donate-send"
        >
          {t('books.donateN', { amount: formatDucats(coin) })}
        </Button>
      }
    >
      <div className="py-3">
        <Stepper
          value={coin}
          onChange={setCoin}
          min={min}
          max={room}
          step={100}
          unit={t('books.coin')}
          label={t('books.coinToGive')}
          presets={[{ label: t('books.max'), value: room }]}
          data-testid="townhall-donate-stepper"
        />
      </div>
      {estimate && (
        <Row
          label={t('books.after')}
          value={<Figure value={formatInt(estimate.points)} />}
          hairline={false}
          data-testid="townhall-donate-points"
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
