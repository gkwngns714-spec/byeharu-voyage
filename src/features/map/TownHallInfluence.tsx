import { useState } from 'react'
import { Bar, Button, Figure, Note, Row, Stepper, Tray, type TrayDetent, type TrayMode } from '../../components/ui'
import { useServedRead } from '../../live/useServedRead'
import { useSettled } from '../../live/useSettled'
import { HullCountry } from '../../live/HullCountry'
import { nationNameOf, useWorld } from '../../live/worldStore'
import { cmdDonate, cmdPreviewDonate, ok } from '../../lib/rpc'
import type { CityInfluence, DonateReceipt, Refusal, SnapshotPort } from '../../lib/rpc'
import { formatDucats, formatInt, formatPct } from '../../lib/format'

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
}: {
  port: SnapshotPort
  influence: CityInfluence
  docked: boolean
  trayMode?: TrayMode
}) {
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
            <span>No country</span>
          )
        }
        value={
          <span className="text-t-caption text-ink-muted">
            {influence.home ? 'Home city' : 'Contested'}
          </span>
        }
        data-testid="townhall-holder"
      />
      {influence.home && influence.holder && (
        <Row
          label={`Home city of ${nationNameOf(nationByCode, influence.holder)}: it never changes country.`}
          tone="muted"
          hairline={false}
          data-testid="townhall-home"
        />
      )}
      {shown.length === 0 ? (
        <Row label="Nobody has given here yet." tone="muted" hairline={false} data-testid="townhall-influence-none" />
      ) : (
        shown.map((s) => (
          <Row key={s.nation} label={<HullCountry nation={s.nation} />} hairline={false} data-testid="townhall-influence-share">
            <Bar pct={s.share * 100} label={`${nationNameOf(nationByCode, s.nation)} influence`} figure={<Figure value={formatPct(s.share)} size="body" />} className="mt-1" />
          </Row>
        ))
      )}
      {you && (
        <Row
          label="Your influence"
          value={<Figure value={formatInt(you.points)} />}
          data-testid="townhall-influence-you"
        >
          {influence.open && (
            <div className="text-t-caption tabular-nums text-ink-muted" data-testid="townhall-given-today">
              {`${formatDucats(you.given_today)} / ${formatDucats(you.cap)} given today`}
            </div>
          )}
        </Row>
      )}
      {canGive ? (
        <div className="pt-2">
          <Button onClick={() => setGiving(true)} data-testid="townhall-donate">
            Donate
          </Button>
        </div>
      ) : (
        <Row
          label={!influence.open ? 'Not taking gifts yet.' : !docked ? 'Dock here to donate.' : 'You have given all you may today.'}
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
    { question: String(settled) },
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
      title={`Donate to ${port.name}`}
      mode={mode}
      data-testid="townhall-donate-tray"
      action={
        <Button
          variant="primary"
          className="w-full"
          disabled={estimate === null}
          busy={sending}
          busyLabel="Donating…"
          onClick={send}
          data-testid="townhall-donate-send"
        >
          {`Donate ${formatDucats(coin)}`}
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
          unit="coin"
          label="coin to give"
          presets={[{ label: 'Max', value: room }]}
          data-testid="townhall-donate-stepper"
        />
      </div>
      {estimate && (
        <Row
          label="Your influence after"
          value={<Figure value={formatInt(estimate.points)} />}
          hairline={false}
          data-testid="townhall-donate-points"
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
