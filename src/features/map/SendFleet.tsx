import { useState, type ReactNode } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button, Hint, Row, SheetSection, Skyline, skylineOf, Tray, TrayTitle, seaName, type TrayDetent } from '../../components/ui'
import { useWorld } from '../../live/worldStore'
import { PortFlag } from '../../live/PortFlag'
import { CHART_CHROME, GoToLink } from '../../chart'
import { SendFleetRow } from './SendFleetRow'
import { SendArmadaRow } from './SendArmadaRow'
import { useArmadas } from '../../live/armadas'
import { canGo, type SailDest } from './sendRules'
import { useSendFleet } from './useSendFleet'
import { useLocale, useT } from '../../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CITY PANEL — a tapped place: its name and flag, who is in port and who is coming, and the map's one act.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// docs/design/simplify-2026-11-24.md S5: one simple harbour face. The six tabs it used to carry (Info, Town Hall, Market, Port,
// Inn, Giving) repeated HQ's city and are DELETED; to trade, hire or invest there, HQ opens on that city (`HQ here`).
//
//     Lisbon                                [Send fleet] [HQ here]
//     Portugal · 27 merchants · 2 in port
//       In port · Incoming, yours and the merchants' (CityHarbour)
//     [                 Send Gaivota                     ]
//
// A point of OPEN SEA has no harbour: it is only somewhere to send a fleet.
//
// THE SEND IS NOT LOST. The owner's flow, step for step (useSendFleet.ts quotes it): tap a place →
// the panel opens with the place's name, one line, and `Send fleet` → press it and her fleets are
// listed with the passage's verdict on each row — at the top of the harbour's body → press one, the insurance press unfolds under it → the one pinned button sends her.
// `Send fleet` stands in the title. Nothing navigates; the chart is still the ground.
//
// THE RULES (useSendFleet.ts carries them): this file composes nothing, judges nothing, and owns
// no grammar. It is the markup of a decision made elsewhere.
//
// `CHART_CHROME` for the two reasons every piece of chrome on this chart carries it: a press here
// never pans, and the label planner keeps a harbour's name from under it.
export function SendFleet({
  dest,
  sea = null,
  line,
  harbour,
  unseen = false,
  onClose,
}: {
  dest: SailDest
  /** The sea this place is in, named on the title's line while the Map's Seas filter is on; null otherwise. */
  sea?: { name: string } | null
  /** The one line under the name — `Portugal · 27 merchants · 2 in port`, `Open sea`. */
  line: ReactNode
  /** The harbour's ships — in port and incoming (CityHarbour), built by MapScreen, which holds
   *  the harbour's read. Unused at sea. */
  harbour: ReactNode
  /** 0504 — a city she knows but does not have in sight (src/chart/fog.ts): its name and the sending, and nothing about it. */
  unseen?: boolean
  onClose: () => void
}) {
  const t = useT()
  const locale = useLocale()
  const [detent, setDetent] = useState<TrayDetent>('peek')
  const open = detent !== 'peek'
  const flow = useSendFleet(dest, open)
  // 0367: an armada is sent as ONE row (SendArmadaRow), and her fleets are not listed again under her: a fleet of an armada sails on the armada's order only.
  const armadas = useArmadas()
  const inArmada = new Set(armadas.armadas.flatMap((a) => a.fleets))
  const fleets = inArmada.size === 0 ? flow.fleets : flow.fleets.filter((f) => !inArmada.has(f.id))
  const navigate = useNavigate()
  const culture = useWorld((s) => (dest.kind === 'port' ? s.portByCode[dest.code]?.culture : undefined))

  const picked = fleets.find((f) => f.id === flow.picked) ?? null
  const sendable = picked !== null && canGo(flow.standingOf(picked))
  // The dead end is named only when the player ARRIVED at it — not in the frame after their own
  // send emptied the list, when her row already says she is under way.
  const nowhere = fleets.length > 0 && !fleets.some((f) => canGo(flow.standingOf(f))) && flow.act?.state !== 'sent'
  const busy = picked !== null && flow.act?.state === 'busy' && flow.act.fleetId === picked.id

  // HER FLEETS, each with the passage's verdict — once `Send fleet` is pressed: at the top of the
  // harbour for a city, alone for a point of open sea.
  const sendSection = open && (
    <SheetSection heading={t('map.yourFleets')} data-testid="map-send-fleets">
      {/* WHY THE TRACK WILL NOT TOUCH THE QUAY (0076): the marker leaves the triangle for a point
          up to 67.7 nm out, and a player who was not told reads that as a bug. Said only where a
          passage is being chosen — above the lists it was the first line of every city (2026-10-15,
          "stupid useless info"). The wording is domain/passage's. */}
      {flow.roads && <Hint data-testid="map-send-roads">{flow.roads}</Hint>}
      {flow.fleets.length === 0 && (
        <Row tone="muted" hairline={false} label={t('map.noFleetsYet')} data-testid="map-send-none" />
      )}

      {/* THE DEAD END, NAMED (OWNER_REQUESTS row 49: "i can't send a fleet in map"): a list in
          which nothing can be pressed says so ONCE, at the top, before the player hunts for the
          press. */}
      {nowhere && (
        <Row
          tone="muted"
          label={
            fleets.every((f) => flow.standingOf(f) === 'lies')
              ? t('map.nothingLies', { count: fleets.length, dest: flow.destName })
              : t('map.nothingAll', { dest: flow.destName })
          }
          data-testid="map-send-nowhere"
        />
      )}

      {dest.kind === 'port' && armadas.armadas.map((a) => <SendArmadaRow key={a.id} armada={a} dest={dest} open={open} />)}
      {fleets.map((f) => (
        <SendFleetRow key={f.id} fleet={f} flow={flow} />
      ))}
    </SheetSection>
  )

  return (
    <Tray
      mode="side"
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={
        <TrayTitle
          name={
            // 2026-10-18 (the owner): the flag of the nation that holds the city, beside its name.
            <span className="inline-flex max-w-full items-center gap-1.5">
              {dest.kind === 'port' && !unseen && <PortFlag code={dest.code} size="title" />}
              <GoToLink to={dest.kind === 'port' ? { kind: 'port', code: dest.code } : { kind: 'point', at: dest.at }}>
                {flow.destName}
              </GoToLink>
            </span>
          }
          line={
            sea ? (
              <span data-testid="map-place-sea">
                {line} · {seaName(locale, { zoneName: sea.name })}
              </span>
            ) : (
              line
            )
          }
          testId="map-place-name"
          trailing={
            <span className="flex shrink-0 items-center gap-1.5">
              {!open && (
                <Button variant="primary" size="sm" onClick={() => setDetent('half')} data-testid="map-send-fleet">
                  {t('map.sendFleet')}
                </Button>
              )}
              {dest.kind === 'port' && !unseen && (
                <Button variant="secondary" size="sm" onClick={() => navigate(`/city?port=${dest.code}`)} data-testid="map-hq-here">
                  {t('map.hqHere')}
                </Button>
              )}
            </span>
          }
        />
      }
      action={
        sendable ? (
          <Button
            variant="primary"
            className="w-full"
            busy={busy}
            busyLabel={t('map.sending')}
            onClick={() => flow.send(picked)}
            data-testid="map-send-ratio-send"
          >
            {t('map.sendLine', { name: picked.name, insured: flow.insureOf(picked) ? t('map.insuredTag') : '' })}
          </Button>
        ) : undefined
      }
      data-testid="map-detail-tray"
      data-unseen={unseen || undefined}
      {...CHART_CHROME}
    >
      {dest.kind === 'port' ? (
        <>
          {/* THE HARBOUR'S PICTURE (2026-11-23, the visual overhaul's slice 4, principle 7): its regional skyline at dusk, above
              the lists, from the served culture (components/ui/Skyline.tsx `skylineOf`, the one table). Decoration; the head
              above says where. */}
          {!unseen && (
            <div className="mb-2 overflow-hidden rounded-tile border border-edge" data-testid="map-harbour-skyline-band">
              <Skyline kind={skylineOf(culture)} height={64} data-testid="map-harbour-skyline" />
            </div>
          )}
          {sendSection}
          {harbour}
        </>
      ) : (
        sendSection
      )}
    </Tray>
  )
}
