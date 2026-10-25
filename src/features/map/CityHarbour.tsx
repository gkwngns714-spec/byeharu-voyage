import { useMemo, type ReactNode } from 'react'
import { IconDisc, Row, SheetSection, Skeleton, Clip } from '../../components/ui'
import { formatInt } from '../../lib/format'
import { MerchantRow } from '../../live/MerchantRow'
import { merchantParts } from '../../live/merchantLine'
import { harbourSides } from '../../live/merchantGroups'
import type { PortMerchant } from '../../lib/rpc'
import { GoToLink, PlaceLine, type FleetOnChart, type MapPort } from '../../chart'
import { fleetParts } from './fleetLine'
import { useT } from '../../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CITY PANEL'S PORT TAB — the ships lying here, and the ships bound here
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-15: *"by clicking on part [port] it should show incomming ships, resting
// ships."* Two sections, and nothing else:
//
//     In port                                        5
//       [⚓] Gaivota                       yours      ›
//       [⛵] Carreira da Guiné    12     2 h 14 min   ›
//            Casa de Aveiro · 3 ships     level  Resting
//     Incoming                                       3
//       [⛵] Gaivota II                      yours     ›
//            to Lisbon · 11m
//       [⛵] Costeiros do Sul     4         Ending     ›
//            Casa de Faro · 2 ships · to Lisbon · 11m
//
// YOURS FIRST in each section, because a player's own hull is the thing they are looking for;
// then the merchants, split by the ONE where-rule (src/live/merchantGroups.ts `harbourSides`,
// which asks src/domain/fleet/where.ts). A merchant away on the far side of her loop is in
// neither list — the owner's "stupid useless info". A row opens what a tap on that hull on the
// chart opens: your fleet's panel, or the merchant's read-only sheet. This file decides nothing;
// it is the markup of two served lists.
//
// This file retires `CityMerchants.tsx` (In port · Leaving · Arriving · Passing · Away, 2026-10-14).
export function CityHarbour({
  portCode,
  merchants,
  landed,
  here,
  bound,
  portsByCode,
  nowMs,
  onOpenMerchant,
  onOpenFleet,
}: {
  portCode: string
  /** The harbour's whole read (`world.port_merchants`), handed down by MapScreen. */
  merchants: readonly PortMerchant[]
  /** Whether the harbour's read has ANSWERED for this harbour. Until it has, "nobody here" is not
   *  known, so it is never printed (2026-10-16: the tray said "No ships in port or bound here."
   *  while the read was still on the wire, and tests/map.merchants.spec.ts took that for an answer
   *  whenever a busy machine made the read slower than its wait). */
  landed: boolean
  /** Your fleets lying here, and bound here — the chart model's (`fleetsAtPort` / `fleetsBoundFor`). */
  here: readonly FleetOnChart[]
  bound: readonly FleetOnChart[]
  portsByCode: ReadonlyMap<string, MapPort>
  nowMs: number
  onOpenMerchant: (fleetId: string) => void
  onOpenFleet: (fleetId: string) => void
}) {
  const t = useT()
  const sides = useMemo(() => harbourSides(merchants, portCode), [merchants, portCode])
  const portName = (code: string) => portsByCode.get(code)?.name ?? code

  const inPortCount = here.length + sides.inPort.length
  const incomingCount = bound.length + sides.incoming.length

  if (inPortCount + incomingCount === 0) {
    if (!landed) return <Skeleton className="h-11 w-full" data-testid="map-harbour-loading" />
    return <Row label={t('map.noShips')} tone="muted" hairline={false} data-testid="map-harbour-empty" />
  }

  return (
    <div data-testid="map-harbour" data-landed={landed ? 'true' : 'false'}>
      {inPortCount > 0 && (
        <Section heading={t('map.inPort')} count={inPortCount} testId="map-harbour-in-port">
          {here.map((f, i) => (
            <OwnRow
              key={f.fleet.id}
              f={f}
              right={<span className="text-t-caption text-accent">yours</span>}
              onOpen={onOpenFleet}
              hairline={i < inPortCount - 1}
            />
          ))}
          {sides.inPort.map((m, i) => (
            <MerchantRow
              key={m.id}
              m={m}
              here
              nowMs={nowMs}
              onOpen={onOpenMerchant}
              hairline={here.length + i < inPortCount - 1}
            />
          ))}
        </Section>
      )}
      {incomingCount > 0 && (
        <Section heading={t('map.incoming')} count={incomingCount} testId="map-harbour-incoming">
          {bound.map((f, i) => (
            <OwnRow
              key={f.fleet.id}
              f={f}
              // `to Lisbon · 11m` — her ETA, in the one where-line (fleetLine.ts).
              line={<PlaceLine parts={fleetParts(f, portsByCode, nowMs)} />}
              right={<span className="text-t-caption text-accent">yours</span>}
              onOpen={onOpenFleet}
              hairline={i < incomingCount - 1}
            />
          ))}
          {sides.incoming.map((m, i) => (
            <MerchantRow
              key={m.id}
              m={m}
              here={false}
              // HER ETA, in the one where-line every fleet is printed with (`to Lisbon · 11m`).
              detail={<PlaceLine parts={merchantParts(m, portName, nowMs)} />}
              nowMs={nowMs}
              onOpen={onOpenMerchant}
              hairline={bound.length + i < incomingCount - 1}
            />
          ))}
        </Section>
      )}
    </div>
  )
}

function Section({
  heading,
  count,
  testId,
  children,
}: {
  heading: string
  count: number
  testId: string
  children: ReactNode
}) {
  return (
    <SheetSection
      heading={heading}
      trailing={
        <span className="text-t-caption tabular-nums text-ink-muted" data-testid="map-harbour-count">
          {formatInt(count)}
        </span>
      }
      surface
      data-testid={testId}
    >
      {children}
    </SheetSection>
  )
}

/** A fleet of yours: her name, where she is in the one where-line, and a right-hand fact. */
function OwnRow({
  f,
  line,
  right,
  onOpen,
  hairline,
}: {
  f: FleetOnChart
  line?: ReactNode
  right?: ReactNode
  onOpen: (fleetId: string) => void
  hairline: boolean
}) {
  return (
    <Row
      mark={<IconDisc name={f.dockedAtCode ? 'anchor' : 'ship'} tone="accent" />}
      label={
        <span className="block min-w-0">
          <Clip className="text-t-body text-ink">
            <GoToLink to={{ kind: 'fleet', id: f.fleet.id }}>{f.fleet.name}</GoToLink>
          </Clip>
          {line !== undefined && <span className="block break-words text-t-caption text-ink-faint">{line}</span>}
        </span>
      }
      value={right}
      chevron
      hairline={hairline}
      onClick={() => onOpen(f.fleet.id)}
      data-testid="map-harbour-own"
    />
  )
}
