import { useMemo, useState } from 'react'
import {
  CargoRows,
  Figure,
  Hint,
  IconDisc,
  OfficerTile,
  Row,
  SheetSection,
  ShipTile,
  SkillTile,
  Skeleton,
  Tile,
  TileField,
  Tray,
  TrayTitle,
  type TrayDetent,
} from '../components/ui'
import { CHART_CHROME } from '../chart'
import { useShellState } from '../app/shellState'
import { formatDucats, formatDucatsDelta, formatInt, formatRealShort } from '../lib/format'
import { fleetCargoByCode, hullFraction } from '../domain/fleet'
import { skippedWords } from '../domain/route'
import type { MerchantCard } from '../lib/rpc'
import { portNameOf, useWorld } from './worldStore'
import { ShipPanel } from './ShipPanel'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE MERCHANT SHEET — one merchant fleet, READ-ONLY (owner rows 110-111, docs/NPC_TRADERS.md §8.3)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner: *"by clicking the npc ship, it will show how much it is earning per day or so"* and
// *"i will be able to click on fleet, see ships, captains, skills etc."* MAP opens it on a tapped
// hull and from a city's list, PORT from "Merchants"; it is live-data React for the reason
// PortField is.
//
// RESTYLED 2026-10-13 — the owner: *"the pop-up page when clicking a ship or a city is not good in
// terms of friendliness and style. change it so that it is modern, user friendly and somewhat
// sophisticated."* Measured on the sheet as it was: the name, the company and the line on ONE
// truncated line; eight label/value rows of the same weight in one column; and every tile on it
// `surface` on a `surface` tray, so Ships, Officers and Skills had no shape. What changed, and only
// this: the head is `TrayTitle` (a name, a caption line, two steps of the type ladder); what she
// EARNS is two figure tiles side by side rather than two rows; the route, her laps and her fortune
// are one grouped panel with a mark each; tiles and panels step up one tone inside a tray
// (trayContext.ts). Not one figure moved or was added, except the company's total level beside the
// Skills heading — the same sum the city's list prints (0113).
//
//   peek  the fleet; under it the company and the caller's one line (where she is going, or when she sails)
//   half  what she EARNS — a real day's laps summed by the server (`public.route_earnings`), the
//         average lap — then her route and laps, the company's fortune, the blurb
//         (and NOT a figure the server will not stand behind: a lap average needs two closed laps,
//          because a lap closes before the home sale — see `RouteEarnings.lap`)
//   full  her SHIPS, CARGO, OFFICERS and the company's SKILLS — the same tiles FLEETS, the Codex
//         and the Academy print — and what her last lap passed over, in words
//
// NOTHING HERE IS AN ACTION. No Button, no Stepper, no hand-off, no fleet selection: the map stays
// an output device (DESIGN E.5) and the only thing a player can do with this sheet is close it.
// Every figure is served; nothing is summed on this side of the wire (worldStore rule 3) — the
// level beside Skills is four served levels added, which is the one sum the server also serves
// (0113) and the sheet prints it so the list and the sheet say one number.
export function MerchantSheet({
  card,
  line,
  onClose,
  mode,
}: {
  /** The card, read by the caller through `useMerchantCard` — ONE read per screen, because MAP
   *  also draws the open merchant's leg from the same answer. Null while the first read is out. */
  card: MerchantCard | null
  /** The one line under her name at peek — the caller's (MAP: `fleetLine`, or when she sails). */
  line: string
  onClose: () => void
  /** MAP passes 'side' — its slide-in panel at the right edge (screenLayout traySideEdgeClass). */
  mode?: 'docked' | 'side'
}) {
  const [detent, setDetent] = useState<TrayDetent>('peek')
  // HER SHIPS OPEN ONE BY ONE (owner, 2026-10-15): a press slides that ship's panel in over this.
  const [openShip, setOpenShip] = useState<number | null>(null)
  const portByCode = useWorld((s) => s.portByCode)
  const goodByCode = useWorld((s) => s.goodByCode)

  const ship = card && openShip !== null ? card.ships[openShip] : undefined
  return (
    <>
    <Tray
      mode={mode}
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={
        <TrayTitle
          name={card?.fleet.name ?? '…'}
          line={card ? [card.company.name, line].filter(Boolean).join(' · ') : line}
          testId="merchant-sheet-name"
        />
      }
      data-testid="merchant-sheet"
      {...CHART_CHROME}
    >
      {!card ? (
        <Skeleton className="mt-2 h-28 w-full" />
      ) : (
        <MerchantBody card={card} portName={(c) => portNameOf(portByCode, c)} goodName={(c) => goodByCode[c]?.name ?? c} goodCategory={(c) => goodByCode[c]?.category ?? ''} onOpenShip={setOpenShip} />
      )}
    </Tray>
    {ship && <ShipPanel key={openShip} ship={ship} onClose={() => setOpenShip(null)} />}
    </>
  )
}

function MerchantBody({
  card,
  portName,
  goodName,
  goodCategory,
  onOpenShip,
}: {
  card: MerchantCard
  portName: (code: string) => string
  goodName: (code: string) => string
  goodCategory: (code: string) => string
  onOpenShip: (index: number) => void
}) {
  // THE ONE CLOCK (src/app/shellState.ts): the Fortune line counts a span from it, never from a
  // Date.now() read during a render.
  const { nowMs } = useShellState()
  const e = card.earnings
  const cargo = useMemo(() => {
    return Object.entries(fleetCargoByCode(card))
      .map(([code, qty]) => ({ code, name: goodName(code), category: goodCategory(code), qty }))
      .sort((a, b) => a.name.localeCompare(b.name))
  }, [card, goodName, goodCategory])
  const skipped = card.route?.last_skipped ?? []
  const level = card.skills.reduce((n, sk) => n + sk.level, 0)

  return (
    <div data-testid="merchant-sheet-body">
      {/* WHAT SHE EARNS — the two figures the owner asked for first, side by side as tiles, each
          the ONE figure its block is about (`t-figure`). */}
      <TileField className="mt-2">
        {/* A real day, because that is the day the player lives in; before a whole day of laps is
            held the figure is what it is — the laps SINCE a named hour — and it says so, rather
            than calling a partial window "today". A truthful lesser answer, never an extrapolation.
            A SPAN, NOT A CLOCK TIME: `day_since` can be up to 24 h old, and "since 13:05" read as
            this afternoon. */}
        <Tile
          name={e && e.day_full ? 'A day' : 'So far'}
          meta={e && e.day_full ? 'a real day of laps' : e && e.day_since ? `over the last ${formatRealShort(nowMs - Date.parse(e.day_since))}` : 'no lap closed yet'}
          figure={<Figure size="figure" value={e ? `${e.day_full ? '≈ ' : ''}${formatDucats(e.day)}` : '—'} />}
          data-testid="merchant-earnings-day"
        />
        {/* A LAP IS NOT GUESSED FROM ONE LAP. The server returns `lap` null until two have closed,
            because a lap closes on arrival home BEFORE the home sale, so the first lap is a
            purchase with no sale and reads as a huge loss (RouteEarnings.lap carries the whole
            derivation). While that is the case the tile says what is true. `laps_done` counts
            CLOSED laps, so `1` means her first lap is behind her and the second is under way. */}
        <Tile
          name="A lap"
          meta={e && e.lap !== null ? `over the last ${e.lap_basis} laps` : undefined}
          figure={
            e && e.lap !== null ? (
              <Figure size="figure" value={`≈ ${formatDucats(e.lap)}`} />
            ) : (
              <Figure value={e && e.laps_done > 0 ? 'one lap closed' : 'first lap under way'} tone="muted" />
            )
          }
          data-testid="merchant-earnings-lap"
        />
      </TileField>

      <SheetSection surface>
        {card.route && (
          <Row
            mark={<IconDisc name="compass" />}
            label={
              <span className="block min-w-0">
                <span className="block truncate">{card.route.name}</span>
                <span className="block truncate text-t-caption text-ink-faint">{card.route.stops.map(portName).join(' → ')}</span>
              </span>
            }
            value={<Figure value={formatInt(e?.laps_done ?? 0)} unit={(e?.laps_done ?? 0) === 1 ? 'lap' : 'laps'} />}
            data-testid="merchant-route"
          />
        )}
        {e && e.laps_recent.length > 0 && (
          <Row
            mark={<IconDisc name="history" />}
            label={
              <span className="block min-w-0">
                <span className="block">Last laps</span>
                <span className="block text-t-caption text-ink-faint">newest first</span>
              </span>
            }
          >
            {/* ONE PILL A LAP, wrapping on their own line under the label — as one joined string
                in the value column they wrapped into each other (owner, 2026-10-15, on Yol
                Portobelo: "the lines are overlapping with one another"). */}
            <span className="mt-1.5 flex flex-wrap gap-1.5" data-testid="merchant-laps-recent">
              {e.laps_recent.map((n, i) => (
                <span
                  key={i}
                  className={[
                    'whitespace-nowrap rounded-chip px-2 py-0.5 text-t-caption leading-snug tabular-nums',
                    n > 0 ? 'bg-success/15 text-success' : n < 0 ? 'bg-danger/15 text-danger' : 'bg-surface-2 text-ink-muted',
                  ].join(' ')}
                >
                  {formatDucatsDelta(n)}
                </span>
              ))}
            </span>
          </Row>
        )}
        <Row
          mark={<IconDisc name="coin" />}
          label={
            <span className="block min-w-0">
              <span className="block">Fortune</span>
              {/* A CLOCK TIME IS ONLY HONEST WITHIN TODAY. A refound may be days old, and
                  "last 14:32" read as though it had happened this afternoon. The span is the
                  same form the rest of the sheet counts in. */}
              {card.company.refounded > 0 && (
                <span className="block truncate text-t-caption text-ink-faint">
                  {`refounded ${card.company.refounded === 1 ? 'once' : `${card.company.refounded} times`}${
                    card.company.refounded_at ? `, last ${formatRealShort(nowMs - Date.parse(card.company.refounded_at))} ago` : ''
                  }`}
                </span>
              )}
            </span>
          }
          value={<Figure value={formatDucats(card.company.fortune)} />}
          hairline={false}
        />
      </SheetSection>
      <Hint className="mt-3" data-testid="merchant-blurb">
        {card.company.blurb}
      </Hint>

      <SheetSection heading="Ships">
        {/* ONE SHIP A ROW, full width: in the auto-fill tile grid her figures ran out of the box
            (owner, 2026-10-15: "words are outside the box"). */}
        <div className="flex flex-col gap-2">
          {card.ships.map((s, i) => (
            <button
              key={s.name}
              type="button"
              onClick={() => onOpenShip(i)}
              className="block w-full text-left"
              data-testid="merchant-ship-open"
            >
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
              // A merchant's supplies are not served, so her hold in use is her cargo alone.
              holdUsed={s.cargo_tuns}
              holdTotal={s.hold}
              fittings={s.fittings}
              testId="merchant-ship-tile"
            />
            </button>
          ))}
        </div>
      </SheetSection>

      <SheetSection heading="Cargo" surface>
        <CargoRows rows={cargo} totalTons={card.ships.reduce((n, s) => n + s.cargo_tuns, 0)} testId="merchant-cargo-row" />
      </SheetSection>

      <SheetSection heading="Officers" trailing={<span className="text-t-caption text-ink-muted">{`master ${card.company.master}`}</span>}>
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
      </SheetSection>

      {/* THE COMPANY'S FOUR LEVELS (docs/WORDS.md: the word is Skills), and their sum beside the
          heading — the same number the city's list prints for her (0113). */}
      <SheetSection
        heading="Skills"
        trailing={
          <span className="text-t-caption text-ink-muted" data-testid="merchant-level">
            level <span className="text-t-body tabular-nums text-ink">{formatInt(level)}</span>
          </span>
        }
      >
        <TileField>
          {card.skills.map((sk) => (
            <SkillTile key={sk.code} code={sk.code} name={sk.name} level={sk.level} max={sk.max} />
          ))}
        </TileField>
      </SheetSection>

      {skipped.length > 0 && (
        <SheetSection heading="Last lap" surface>
          {skipped.map((s, i) => (
            <Row key={`${s.line}-${i}`} label={skippedWords(s, goodName, portName)} tone="muted" hairline={i < skipped.length - 1} />
          ))}
        </SheetSection>
      )}
    </div>
  )
}
