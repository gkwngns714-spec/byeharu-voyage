import { useEffect, useRef, useState } from 'react'
import { Bar, Button, Figure, Icon, Note, Row } from '../../components/ui'
import { formatDaysReal, formatInt, formatPriceDelta } from '../../lib/format'
import { cmdArmadaSail, cmdPreviewArmadaSail } from '../../lib/rpc'
import type { ArmadaSailed, ArmadaView, Refusal } from '../../lib/rpc'
import { proposeCourse, sailOrigin, sailTarget } from '../../domain/passage'
import { fleetsOf } from '../../live/armadas'
import { portNameOf, useWorld } from '../../live/worldStore'
import type { SailDest } from './sendRules'
import { useT } from '../../lib/i18n'

// ONE SEND FOR AN ARMADA (0367, docs/ARMADA.md section 4; owner row 323). In the city panel's send list an armada is ONE row above the fleets: her name, her fleets by
// name, the time of the passage and what the order costs for all of them. Her fleets are not listed again under her: a fleet of an armada sails on the armada's order only.
//
// THE FIGURES ARE THE ORDER'S OWN. Opening the list asks the server to run the real order and throw it away (`cmd.preview_armada_sail`): every fleet through the one mover,
// her own supplies bought, her own gates. What comes back is the arrival all of them share, the armada's speed and what left the purse; a refusal comes back under the name
// of the fleet that was refused, with her figures. The press then sends the same order for real (`cmd.armada_sail`): every fleet or none.
//
// THE PRESS LAW: the row selects, and the one button unfolds under it, as a fleet's insurance press does. Nothing navigates.
//
// NOT HERE (docs/ARMADA.md section 12): insurance from this row (an armada is sent uninsured), a point of open sea, a turn at sea.

type Verdict = { kind: 'ok'; quote: ArmadaSailed } | { kind: 'refused'; refusal: Refusal }

export function SendArmadaRow({ armada, dest, open }: { armada: ArmadaView; dest: Extract<SailDest, { kind: 'port' }>; open: boolean }) {
  const t = useT()
  const fleets = useWorld((s) => s.fleets)
  const portByCode = useWorld((s) => s.portByCode)
  const seaNav = useWorld((s) => s.seaNav)
  const refresh = useWorld((s) => s.refresh)
  const members = fleetsOf(armada, fleets)
  const [verdict, setVerdict] = useState<Verdict | null>(null)
  const [picked, setPicked] = useState(false)
  const [busy, setBusy] = useState(false)
  const [sent, setSent] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)

  const here = armada.state === 'PORT' && armada.port === dest.code
  const sendable = armada.state === 'PORT' && !here && !sent
  // The course is plotted from where the flagship fleet lies; the server verifies and measures it for every fleet. Kept in a ref so the dry run below is asked once an
  // armada and a destination, not again on every world read.
  const plot = (): [number, number][] | null => {
    const lead = members[0]
    const from = lead ? sailOrigin(lead, portByCode) : null
    const to = sailTarget({ dest: dest.code }, portByCode)
    return seaNav && from && to ? proposeCourse(seaNav, from, to) : null
  }
  const plotRef = useRef(plot)
  useEffect(() => {
    plotRef.current = plot
  })

  useEffect(() => {
    if (!open || !sendable || !seaNav) return
    let alive = true
    void (async () => {
      const r = await cmdPreviewArmadaSail(armada.id, dest.code, plotRef.current(), false)
      if (!alive) return
      setVerdict(r.ok ? { kind: 'ok', quote: r.value } : { kind: 'refused', refusal: r.refusal })
    })()
    return () => {
      alive = false
    }
  }, [open, sendable, seaNav, armada.id, dest.code])

  const send = () => {
    if (busy) return
    setBusy(true)
    setRefusal(null)
    void (async () => {
      const r = await cmdArmadaSail(armada.id, dest.code, plotRef.current(), false)
      if (r.ok) {
        setSent(true)
        setPicked(false)
        await refresh()
      } else {
        setRefusal(r.refusal)
      }
      setBusy(false)
    })()
  }

  const quote = sendable && verdict?.kind === 'ok' ? verdict.quote : null
  const nm = quote?.voyages[0]?.total_nm ?? null
  const days = quote && nm !== null && quote.speed_kn > 0 ? nm / quote.speed_kn / 24 : null
  const names = members.map((f) => f.name).join(', ')
  const line = sent
    ? t('map.armadaSent', { dest: dest.name })
    : here
      ? t('map.dockedHere')
      : armada.state === 'APART'
        ? t('fleets.armadaApart')
        : armada.state === 'SEA'
          ? t('map.alreadyHeading')
          : verdict === null
            ? t('map.checkingRoute')
            : portNameOf(portByCode, armada.port ?? '')
  const said = refusal ?? (sendable && verdict?.kind === 'refused' ? verdict.refusal : null)

  return (
    <div data-testid="map-send-armada" data-armada={armada.name} data-state={sent ? 'SENT' : armada.state}>
      <Row
        mark={<Icon name="ship" size={20} className={picked ? 'text-accent' : 'text-ink-faint'} />}
        label={<span className="break-words">{armada.name}</span>}
        value={days !== null ? <Figure value={<span data-testid="map-send-armada-passage">{formatDaysReal(days)}</span>} /> : undefined}
        tone={picked ? 'accent' : sendable ? 'default' : 'muted'}
        hairline={!picked}
        onClick={sendable ? () => setPicked((p) => !p) : undefined}
        data-testid={sendable ? 'map-send-armada-head' : 'map-send-armada-still'}
      >
        <span className="block text-t-caption text-ink-faint" data-testid="map-send-armada-note">
          {line}
        </span>
        <span className="block break-words text-t-caption text-ink-muted" data-testid="map-send-armada-fleets">
          {t('map.armadaLine', { count: formatInt(members.length), names })}
        </span>
        {quote && (
          <span className="block text-t-caption text-ink-muted" data-testid="map-send-armada-cost" data-cost={quote.cost}>
            {t('map.armadaCost', { amount: formatPriceDelta(quote.cost > 0 ? -quote.cost : 0) })}
          </span>
        )}
        {quote && quote.on_credit > 0 && (
          <span className="block text-t-caption text-warning" data-testid="map-send-armada-on-credit">
            {t('map.onCredit', { amount: formatPriceDelta(-quote.on_credit) })}
          </span>
        )}
      </Row>
      {said && (
        <div className="py-2">
          <Note
            tone="danger"
            code={said.code}
            figures={said.figures}
            data-testid="map-send-armada-refusal"
            figure={
              said.figures ? (
                <Bar
                  pct={said.figures.need > 0 ? (said.figures.have / said.figures.need) * 100 : 0}
                  tone="danger"
                  label={t('map.haveNeed', { unit: said.figures.unit })}
                  figure={<Figure value={`${said.figures.have} / ${said.figures.need}`} unit={said.figures.unit} />}
                />
              ) : undefined
            }
          >
            {said.sentence}
          </Note>
        </div>
      )}
      {picked && sendable && verdict?.kind === 'ok' && (
        <Button variant="primary" className="mb-2 w-full" busy={busy} busyLabel={t('map.sending')} onClick={send} data-testid="map-send-armada-send">
          {t('map.sendLine', { name: armada.name, insured: '' })}
        </Button>
      )}
    </div>
  )
}
