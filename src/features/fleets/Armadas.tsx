import { useState } from 'react'
import { Button, Clip, DetailPage, FactsLine, Field, IconDisc, ListPanel, Note, Row, SheetSection } from '../../components/ui'
import { formatDucats, formatInt, formatKnots, formatOfTotal } from '../../lib/format'
import type { ArmadaView, Armadas as ArmadasRead, FleetView, Refusal } from '../../lib/rpc'
import { armadaTotals, cmdArmadaDisband, cmdArmadaForm, fleetsOf, useArmadas } from '../../live/armadas'
import { portNameOf, useWorld } from '../../live/worldStore'
import { whereabouts, whereLine } from '../../domain/fleet'
import { useT } from '../../lib/i18n'

// ARMADAS, ON THE FLEETS PAGE (0367, docs/ARMADA.md; owner row 323: "with more than one fleet, max 6 fleet - an armada").
// An armada is two to six of her fleets that sail on one order, at the slowest fleet's speed, and meet a raid as one side. This is where one is formed and disbanded.
//
//   · the list: one row an armada: her name, where she is, her fleets by name (whole, never cut) and what they add up to;
//   · a press opens her page (`DetailPage`, a fixed layer: nothing behind it moves): the totals, her fleets with the flagship fleet marked, and Disband;
//   · "New armada" opens the page on which she picks the fleets (the first picked is the flagship fleet), names the armada and presses Form.
//
// EVERY RULE IS THE SERVER'S (`cmd.armada_form`: docked in one port, a ship in each, no orders waiting, no trade route, 2 to `max` fleets). This page offers what the world
// read already shows to be possible (docked fleets, grouped by the first pick's port) and prints the server's refusal when it says no. The figures are sums of the fleets'
// served totals (`armadaTotals`, src/live/armadas.ts); the speed is the server's (`speed_kn`, the slowest fleet's).
//
// Sending an armada is the map's act (src/features/map/SendArmadaRow.tsx), as sending a fleet is.

export function Armadas() {
  const t = useT()
  const read = useArmadas()
  const fleets = useWorld((s) => s.fleets)
  const [openId, setOpenId] = useState<string | null>(null)
  const [forming, setForming] = useState(false)
  const open = read.armadas.find((a) => a.id === openId) ?? null
  // Switched off (or a server before 0367) and nothing to show: the page is what it was.
  // A company of one fleet has no armada to show and none to form (the world store asks for none): the page is what it was.
  if (!read.on && read.armadas.length === 0) return null
  if (fleets.length < 2) return null
  return (
    <>
      <ListPanel
        look="card"
        columns="fit"
        className="mt-4"
        title={read.armadas.length === 0 ? t('fleets.armadas') : t('fleets.armadaCount', { n: formatInt(read.armadas.length), count: read.armadas.length })}
        data-testid="armadas-list"
      >
        {read.armadas.map((a) => (
          <ArmadaRow key={a.id} armada={a} members={fleetsOf(a, fleets)} selected={openId === a.id} onOpen={() => setOpenId(a.id)} />
        ))}
        {read.on && (
          <Row
            mark={<IconDisc name="plus" tone="accent" />}
            label={t('fleets.armadaNew')}
            chevron
            tone={forming ? 'accent' : 'default'}
            onClick={() => setForming(true)}
            hairline={false}
            data-testid="armada-new"
          />
        )}
      </ListPanel>
      {open !== null && <ArmadaPage armada={open} members={fleetsOf(open, fleets)} onClose={() => setOpenId(null)} />}
      {forming && <NewArmadaPage read={read} onClose={() => setForming(false)} />}
    </>
  )
}

/** Where an armada is, in the page's words: the port she lies in, at sea, or apart. */
function useWhere(): (a: ArmadaView, members: readonly FleetView[]) => string {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  return (a, members) => {
    if (a.state === 'APART') return t('fleets.armadaApart')
    const lead = members[0]
    return lead ? whereLine(whereabouts(lead), (code) => portNameOf(portByCode, code)) : ''
  }
}

/** The armada's figures on one wrapping line: sums of her fleets' served totals, and the server's speed. */
function ArmadaFacts({ armada, members }: { armada: ArmadaView; members: readonly FleetView[] }) {
  const t = useT()
  const s = armadaTotals(members)
  return (
    <FactsLine data-testid="armada-totals">
      <span data-testid="armada-total-fleets">{t('fleets.count', { n: formatInt(s.fleets), count: s.fleets })}</span>
      <span data-testid="armada-total-ships">
        {t('fleets.ships')} <span className="tabular-nums text-ink">{formatInt(s.ships)}</span>
      </span>
      <span data-testid="armada-total-attack">
        {t('fleets.attack')} <span className="tabular-nums text-ink">{formatInt(s.attack)}</span>
      </span>
      <span data-testid="armada-total-hull">
        {t('fleets.hullSum')} <span className="tabular-nums text-ink">{formatOfTotal(s.hull, s.hullMax)}</span>
      </span>
      <span data-testid="armada-total-crew">
        {t('fleets.crew')} <span className="tabular-nums text-ink">{formatOfTotal(s.crew, s.crewMax)}</span>
      </span>
      <span data-testid="armada-total-wages">
        {t('fleets.wages')} <span className="tabular-nums text-ink">{t('fleets.perDay', { amount: formatDucats(Math.round(s.wagesDay)) })}</span>
      </span>
      {armada.speed_kn > 0 && (
        <span data-testid="armada-total-speed">
          {t('fleets.armadaSpeed')} <span className="tabular-nums text-ink">{formatKnots(armada.speed_kn)}</span>
        </span>
      )}
    </FactsLine>
  )
}

function ArmadaRow({ armada, members, selected, onOpen }: { armada: ArmadaView; members: readonly FleetView[]; selected: boolean; onOpen: () => void }) {
  const where = useWhere()
  return (
    <Row
      mark={<IconDisc name="ship" tone={armada.state === 'APART' ? 'warning' : armada.state === 'SEA' ? 'accent' : 'success'} label={armada.state.toLowerCase()} />}
      label={
        <span className="flex flex-wrap items-baseline justify-between gap-x-3">
          <Clip className="max-w-full">{armada.name}</Clip>
          <span className="min-w-0 max-w-full text-t-body text-ink">{where(armada, members)}</span>
        </span>
      }
      chevron
      tone={selected ? 'accent' : 'default'}
      onClick={onOpen}
      data-testid="armada-row"
    >
      {/* HER FLEETS BY NAME, WHOLE: the line wraps between names and cuts none. */}
      <span className="block break-words text-t-caption text-ink-muted" data-testid="armada-row-fleets">
        {members.map((f) => f.name).join(', ')}
      </span>
      <ArmadaFacts armada={armada} members={members} />
    </Row>
  )
}

function ArmadaPage({ armada, members, onClose }: { armada: ArmadaView; members: readonly FleetView[]; onClose: () => void }) {
  const t = useT()
  const refresh = useWorld((s) => s.refresh)
  const portByCode = useWorld((s) => s.portByCode)
  const [busy, setBusy] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)
  const disband = () => {
    if (busy) return
    setBusy(true)
    setRefusal(null)
    void (async () => {
      const r = await cmdArmadaDisband(armada.id)
      setBusy(false)
      if (r.ok) {
        await refresh()
        onClose()
      } else {
        setRefusal(r.refusal)
      }
    })()
  }
  return (
    <DetailPage title={armada.name} onClose={onClose} data-testid="armada-page">
      <ArmadaFacts armada={armada} members={members} />
      <p className="mt-2 text-t-caption text-ink-muted" data-testid="armada-note">
        {t(armada.state === 'APART' ? 'fleets.armadaApartNote' : 'fleets.armadaNote')}
      </p>
      <SheetSection heading={t('fleets.roomFleets')} data-testid="armada-fleets">
        {members.map((f, i) => (
          <Row
            key={f.id}
            mark={<IconDisc name="ship" tone={f.id === armada.flagship ? 'accent' : 'muted'} />}
            label={<span className="break-words">{f.name}</span>}
            value={f.id === armada.flagship ? <span className="text-t-caption text-accent">{t('fleets.armadaFlagship')}</span> : undefined}
            hairline={i < members.length - 1}
            data-testid="armada-fleet"
          >
            <span className="block text-t-caption text-ink-muted">
              {whereLine(whereabouts(f), (code) => portNameOf(portByCode, code))} · {t('fleets.ships')} {formatInt(f.ships.length)}
            </span>
          </Row>
        ))}
      </SheetSection>
      <Button variant="secondary" className="mt-4 w-full" busy={busy} onClick={disband} data-testid="armada-disband">
        {t('fleets.armadaDisband')}
      </Button>
      {refusal && (
        <Note tone="danger" code={refusal.code} figures={refusal.figures}>
          {refusal.sentence}
        </Note>
      )}
    </DetailPage>
  )
}

/** Pick the fleets (the first picked leads), name the armada, press once. */
function NewArmadaPage({ read, onClose }: { read: ArmadasRead; onClose: () => void }) {
  const t = useT()
  const refresh = useWorld((s) => s.refresh)
  const fleets = useWorld((s) => s.fleets)
  const portByCode = useWorld((s) => s.portByCode)
  const [picked, setPicked] = useState<string[]>([])
  const [name, setName] = useState('')
  const [busy, setBusy] = useState(false)
  const [refusal, setRefusal] = useState<Refusal | null>(null)

  const taken = new Set(read.armadas.flatMap((a) => a.fleets))
  // What the world read shows to be possible: a fleet with a ship, docked, in no armada. The server judges the rest (orders waiting, a trade route).
  const free = fleets.filter((f) => !taken.has(f.id) && f.status === 'DOCKED' && f.ships.length > 0 && f.port !== null)
  const port = fleets.find((f) => f.id === picked[0])?.port ?? null
  const toggle = (f: FleetView) => {
    setRefusal(null)
    setPicked((p) => (p.includes(f.id) ? p.filter((id) => id !== f.id) : p.length >= read.max ? p : [...p, f.id]))
  }
  const form = () => {
    if (busy || picked.length < 2) return
    setBusy(true)
    setRefusal(null)
    void (async () => {
      const r = await cmdArmadaForm(picked, name.trim())
      setBusy(false)
      if (r.ok) {
        await refresh()
        onClose()
      } else {
        setRefusal(r.refusal)
      }
    })()
  }

  return (
    <DetailPage title={t('fleets.armadaNew')} onClose={onClose} data-testid="armada-new-page">
      <p className="text-t-body text-ink-muted" data-testid="armada-new-what">
        {t('fleets.armadaWhat', { max: formatInt(read.max) })}
      </p>
      {free.length < 2 ? (
        <Note tone="neutral" data-testid="armada-new-need">
          {t('fleets.armadaNeed')}
        </Note>
      ) : (
        <div data-testid="armada-new-pick">
          <SheetSection heading={t('fleets.armadaPick', { n: formatInt(picked.length), max: formatInt(read.max) })} data-testid="armada-new-fleets">
            {free.map((f, i) => {
              const on = picked.includes(f.id)
              // A fleet in another port than the first pick cannot join it: the row says where she is and takes no press.
              const elsewhere = port !== null && f.port !== port
              return (
                <Row
                  key={f.id}
                  mark={<IconDisc name="ship" tone={on ? 'accent' : 'muted'} />}
                  label={<span className="break-words">{f.name}</span>}
                  value={
                    <span className="text-t-caption text-ink-muted">
                      {on && picked[0] === f.id ? t('fleets.armadaFlagship') : portNameOf(portByCode, f.port ?? '')}
                    </span>
                  }
                  tone={on ? 'accent' : elsewhere ? 'muted' : 'default'}
                  onClick={elsewhere ? undefined : () => toggle(f)}
                  hairline={i < free.length - 1}
                  data-testid="armada-new-fleet"
                  data-picked={on ? 'true' : 'false'}
                />
              )
            })}
          </SheetSection>
          <div className="mt-4">
            <Field
              icon={null}
              value={name}
              maxLength={24}
              placeholder={t('fleets.armadaName')}
              onChange={(e) => setName(e.target.value)}
              aria-label={t('fleets.armadaName')}
              data-testid="armada-new-name"
            />
            <Button variant="primary" className="mt-3 w-full" busy={busy} disabled={picked.length < 2 || name.trim().length < 3} onClick={form} data-testid="armada-new-form">
              {t('fleets.armadaForm')}
            </Button>
          </div>
        </div>
      )}
      {refusal && (
        <Note tone="danger" code={refusal.code} figures={refusal.figures}>
          {refusal.sentence}
        </Note>
      )}
    </DetailPage>
  )
}
