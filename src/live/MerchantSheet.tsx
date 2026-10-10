import { useMemo, useState } from 'react'
import {
  CargoRows,
  Figure,
  Hint,
  OfficerTile,
  Row,
  SheetSection,
  ShipTile,
  SkillTile,
  Skeleton,
  TileField,
  Tray,
  type TrayDetent,
} from '../components/ui'
import { CHART_CHROME } from '../chart'
import { useShellState } from '../app/shellState'
import { formatDucats, formatDucatsDelta, formatClock, formatInt, formatRealShort } from '../lib/format'
import { hullFraction } from '../domain/fleet'
import { skippedWords } from '../domain/route'
import type { MerchantCard } from '../lib/rpc'
import { portNameOf, useWorld } from './worldStore'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE MERCHANT SHEET — one merchant fleet, READ-ONLY (owner rows 110-111, docs/NPC_TRADERS.md §8.3)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner: *"by clicking the npc ship, it will show how much it is earning per day or so"* and
// *"i will be able to click on fleet, see ships, captains, skills etc."* MAP opens it on a tapped
// hull, PORT from "Merchants in port"; it is live-data React for the reason PortField is.
//
//   peek  the fleet and its company, and the caller's one line (where she is going, or when she sails)
//   half  what she EARNS — a real day's laps summed by the server (`public.route_earnings`), the
//         average lap, the last seven laps themselves — her route, the company's fortune, the blurb
//         (and NOT a figure the server will not stand behind: a lap average needs two closed laps,
//          because a lap closes before the home sale — see `RouteEarnings.lap`)
//   full  her SHIPS, CARGO, OFFICERS and the company's SKILLS — the same tiles FLEETS, the Codex
//         and the Academy print — and what her last lap passed over, in words
//
// NOTHING HERE IS AN ACTION. No Button, no Stepper, no hand-off, no fleet selection: the map stays
// an output device (DESIGN E.5) and the only thing a player can do with this sheet is close it.
// Every figure is served; nothing is summed on this side of the wire (worldStore rule 3).
export function MerchantSheet({
  card,
  line,
  onClose,
}: {
  /** The card, read by the caller through `useMerchantCard` — ONE read per screen, because MAP
   *  also draws the open merchant's leg from the same answer. Null while the first read is out. */
  card: MerchantCard | null
  /** The one line beside her name at peek — the caller's (MAP: `fleetLine`, or when she sails). */
  line: string
  onClose: () => void
}) {
  const [detent, setDetent] = useState<TrayDetent>('peek')
  const portByCode = useWorld((s) => s.portByCode)
  const goodByCode = useWorld((s) => s.goodByCode)

  return (
    <Tray
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={
        <span className="flex min-h-9 items-center justify-between gap-3">
          <span className="min-w-0 truncate">
            <span data-testid="merchant-sheet-name">{card?.fleet.name ?? '…'}</span>
            {card && <span className="ml-2 text-t-caption text-ink-muted">{card.company.name}</span>}
            <span className="ml-2 text-t-caption text-ink-faint">{line}</span>
          </span>
        </span>
      }
      data-testid="merchant-sheet"
      {...CHART_CHROME}
    >
      {!card ? (
        <Skeleton className="h-28 w-full" />
      ) : (
        <MerchantBody card={card} portName={(c) => portNameOf(portByCode, c)} goodName={(c) => goodByCode[c]?.name ?? c} goodCategory={(c) => goodByCode[c]?.category ?? ''} />
      )}
    </Tray>
  )
}

function MerchantBody({
  card,
  portName,
  goodName,
  goodCategory,
}: {
  card: MerchantCard
  portName: (code: string) => string
  goodName: (code: string) => string
  goodCategory: (code: string) => string
}) {
  // THE ONE CLOCK (src/app/shellState.ts): the Fortune line counts a span from it, never from a
  // Date.now() read during a render.
  const { nowMs } = useShellState()
  const e = card.earnings
  const cargo = useMemo(() => {
    const sum = new Map<string, number>()
    for (const s of card.ships) for (const [code, qty] of Object.entries(s.cargo)) sum.set(code, (sum.get(code) ?? 0) + qty)
    return [...sum.entries()]
      .filter(([, qty]) => qty > 0)
      .map(([code, qty]) => ({ code, name: goodName(code), category: goodCategory(code), qty }))
      .sort((a, b) => a.name.localeCompare(b.name))
  }, [card.ships, goodName, goodCategory])
  const skipped = card.route?.last_skipped ?? []

  return (
    <div data-testid="merchant-sheet-body">
      <SheetSection>
        {/* WHAT SHE EARNS. A real day, because that is the day the player lives in; before a whole
            day of laps is held the figure is what it is — the laps SINCE a named hour — and it says
            so, rather than calling a partial window "today". A truthful lesser answer, never an
            extrapolation. */}
        <Row
          data-testid="merchant-earnings-day"
          label={e && e.day_full ? 'A day' : 'So far'}
          value={
            <Figure
              value={e ? `${e.day_full ? '≈ ' : ''}${formatDucats(e.day)}` : '—'}
              unit={
                e && e.day_full
                  ? 'a day'
                  : e && e.day_since
                    ? `since ${formatClock(Date.parse(e.day_since))}`
                    : undefined
              }
            />
          }
        />
        {/* A LAP IS NOT GUESSED FROM ONE LAP. The server returns `lap` null until two have closed,
            because a lap closes on arrival home BEFORE the home sale, so the first lap is a
            purchase with no sale and reads as a huge loss (RouteEarnings.lap carries the whole
            derivation). While that is the case the row says what is true: she is on her first lap. */}
        <Row
          data-testid="merchant-earnings-lap"
          label="A lap"
          value={
            <Figure
              value={e && e.lap !== null ? `≈ ${formatDucats(e.lap)}` : e && e.laps_done > 0 ? 'first lap under way' : 'no lap yet'}
              unit={e && e.lap !== null ? `over ${e.lap_basis} laps` : undefined}
            />
          }
        />
        {e && e.laps_recent.length > 0 && (
          <Row
            label={
              <span>
                Last laps <span className="text-ink-faint">newest first</span>
              </span>
            }
            value={
              <span className="text-t-caption tabular-nums" data-testid="merchant-laps-recent">
                {e.laps_recent.map((n) => formatDucatsDelta(n)).join(' · ')}
              </span>
            }
          />
        )}
        {card.route && (
          <Row
            label={<span className="block text-t-caption text-ink-muted">{card.route.stops.map(portName).join(' → ')}</span>}
            value={<Figure value={formatInt(e?.laps_done ?? 0)} unit={(e?.laps_done ?? 0) === 1 ? 'lap' : 'laps'} />}
            data-testid="merchant-route"
          />
        )}
        <Row
          label="Fortune"
          value={
            <Figure
              value={formatDucats(card.company.fortune)}
              unit={
                // A CLOCK TIME IS ONLY HONEST WITHIN TODAY. A refound may be days old, and
                // "last 14:32" read as though it had happened this afternoon. The span is the
                // same form the rest of the sheet counts in.
                card.company.refounded > 0
                  ? `refounded ${card.company.refounded === 1 ? 'once' : `${card.company.refounded} times`}${
                      card.company.refounded_at
                        ? `, last ${formatRealShort(nowMs - Date.parse(card.company.refounded_at))} ago`
                        : ''
                    }`
                  : undefined
              }
            />
          }
          hairline={false}
        />
        <Hint data-testid="merchant-blurb">{card.company.blurb}</Hint>
      </SheetSection>

      <SheetSection heading="Ships">
        <TileField>
          {card.ships.map((s) => (
            <ShipTile
              key={s.name}
              name={s.name}
              className={s.class}
              flagship={s.is_flagship}
              hullPct={hullFraction(s)}
              crew={s.crew}
              crewMax={s.crew_max}
              crewRequired={s.crew_required}
              speedKn={s.speed}
              // A merchant's stores are not served, so her hold in use is her cargo alone.
              holdUsed={s.cargo_tuns}
              holdTotal={s.hold}
              fittings={s.fittings}
              testId="merchant-ship-tile"
            />
          ))}
        </TileField>
      </SheetSection>

      <SheetSection heading="Cargo">
        <CargoRows rows={cargo} totalTons={card.ships.reduce((n, s) => n + s.cargo_tuns, 0)} testId="merchant-cargo-row" />
      </SheetSection>

      <SheetSection heading="Officers">
        {card.officers.length === 0 ? (
          <Row label={`No officers — ${card.company.master} keeps the ship himself.`} tone="muted" hairline={false} />
        ) : (
          <TileField>
            {card.officers.map((o) => (
              <OfficerTile
                key={o.name}
                name={o.name}
                specialty={o.specialty}
                bonusPct={o.bonus_pct}
                homePort={o.home_port ? portName(o.home_port) : null}
                testId="merchant-officer-tile"
              />
            ))}
          </TileField>
        )}
        <Row label="Master" value={card.company.master} hairline={false} />
      </SheetSection>

      <SheetSection heading="Skills">
        <TileField>
          {card.skills.map((sk) => (
            <SkillTile key={sk.code} code={sk.code} name={sk.name} level={sk.level} max={sk.max} />
          ))}
        </TileField>
      </SheetSection>

      {skipped.length > 0 && (
        <SheetSection heading="Last lap">
          {skipped.map((s, i) => (
            <Row key={`${s.line}-${i}`} label={skippedWords(s, goodName, portName)} tone="muted" hairline={i < skipped.length - 1} />
          ))}
        </SheetSection>
      )}
    </div>
  )
}
