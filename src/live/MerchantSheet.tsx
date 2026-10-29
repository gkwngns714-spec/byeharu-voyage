import { Fragment, useMemo, useState, type ReactNode } from 'react'
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
  Clip,
} from '../components/ui'
import { CHART_CHROME, GoToLink } from '../chart'
import { useShellState } from '../app/shellState'
import { formatDucats, formatDucatsDelta, formatInt, formatRealShort } from '../lib/format'
import { fleetCargoByCode, hullFraction, whereabouts } from '../domain/fleet'
import { skippedWords } from '../domain/route'
import type { MerchantCard } from '../lib/rpc'
import { nationNameOf, portNameOf, useWorld } from './worldStore'
import { ShipPanel } from './ShipPanel'
import { HullCountry } from './HullCountry'
import { TradeHistoryPanel, type TradePick } from './TradeHistoryPanel'
import { useT } from '../lib/i18n'

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
// (2026-10-15: or OPEN a second panel beside it — one of her ships, or her trading from the tiles
// and the lap pills. Reading deeper is not an action; nothing there issues an order.)
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
  line: ReactNode
  onClose: () => void
  /** MAP passes 'side' — its slide-in panel at the right edge (screenLayout traySideEdgeClass). */
  mode?: 'docked' | 'side'
}) {
  const [detent, setDetent] = useState<TrayDetent>('peek')
  // HER SHIPS OPEN ONE BY ONE (owner, 2026-10-15): a press slides that ship's panel in over this.
  const [openShip, setOpenShip] = useState<number | null>(null)
  // HER TRADING OPENS FROM HER FIGURES (owner, 2026-10-15: *"click on laps, so far, a lap and so on
  // which tells me what the ship has bought and sold, where it sold"*): the tiles and each lap pill
  // slide out TradeHistoryPanel in the same slot as a ship's panel — one of the two at a time.
  const [trades, setTrades] = useState<TradePick | null>(null)
  const openShipPanel = (i: number) => {
    setTrades(null)
    setOpenShip(i)
  }
  const openTrades = (pick: TradePick) => {
    setOpenShip(null)
    setTrades(pick)
  }
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
          name={
            card ? (
              // 0143 (owner, 2026-10-17): every merchant shows the flag of her company's country —
              // since 2026-10-18 BEFORE HER NAME at the title's size, as your own fleet's tray does
              // (VoyageTray), where the owner looks when he presses a ship.
              <span className="inline-flex max-w-full items-center gap-1.5" data-testid="merchant-sheet-flag">
                <HullCountry nation={card.company.nation_code} compact size="title" />
                <GoToLink to={{ kind: 'fleet', id: card.fleet.id, where: whereabouts(card.fleet) }}>{card.fleet.name}</GoToLink>
              </span>
            ) : (
              '…'
            )
          }
          line={
            card ? (
              <>
                {card.company.name}
                {line ? <> · {line}</> : null}
              </>
            ) : (
              line
            )
          }
          testId="merchant-sheet-name"
        />
      }
      data-testid="merchant-sheet"
      {...CHART_CHROME}
    >
      {!card ? (
        <Skeleton className="mt-2 h-28 w-full" />
      ) : (
        <MerchantBody card={card} portName={(c) => portNameOf(portByCode, c)} goodName={(c) => goodByCode[c]?.name ?? c} goodCategory={(c) => goodByCode[c]?.category ?? ''} onOpenShip={openShipPanel} onOpenTrades={openTrades} />
      )}
    </Tray>
    {ship && <ShipPanel key={openShip} ship={ship} nation={card?.company.nation_code} levelFixed onClose={() => setOpenShip(null)} />}
    {card && trades && (
      <TradeHistoryPanel fleetId={card.fleet.id} pick={trades} onPick={setTrades} onClose={() => setTrades(null)} />
    )}
    </>
  )
}

function MerchantBody({
  card,
  portName,
  goodName,
  goodCategory,
  onOpenShip,
  onOpenTrades,
}: {
  card: MerchantCard
  portName: (code: string) => string
  goodName: (code: string) => string
  goodCategory: (code: string) => string
  onOpenShip: (index: number) => void
  onOpenTrades: (pick: TradePick) => void
}) {
  const t = useT()
  // THE ONE CLOCK (src/app/shellState.ts): the Fortune line counts a span from it, never from a
  // Date.now() read during a render.
  const { nowMs } = useShellState()
  const nationByCode = useWorld((s) => s.nationByCode)
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
          name={t(e && e.day_full ? 'port.aDay' : 'port.soFar')}
          meta={e && e.day_full ? t('port.realDay') : e && e.day_since ? t('port.overLast', { span: formatRealShort(nowMs - Date.parse(e.day_since)) }) : t('port.noLap')}
          figure={<Figure size="figure" value={e ? `${e.day_full ? '≈ ' : ''}${formatDucats(e.day)}` : '—'} />}
          // A PRESS OPENS WHAT THE FIGURE IS MADE OF: the day's laps, totalled, and the goods she
          // traded at each harbour (TradeHistoryPanel).
          tap={e ? 'whole' : 'none'}
          onClick={() => onOpenTrades({ kind: 'day' })}
          data-testid="merchant-earnings-day"
        />
        {/* A LAP IS NOT GUESSED FROM ONE LAP. The server returns `lap` null until two have closed,
            because a lap closes on arrival home BEFORE the home sale, so the first lap is a
            purchase with no sale and reads as a huge loss (RouteEarnings.lap carries the whole
            derivation). While that is the case the tile says what is true. `laps_done` counts
            CLOSED laps — 0275 (docs/WEEKLY_ROLLOVER.md): of THIS week, the weekly reset's own
            counter (the all-time figure rides `laps_done_all`). */}
        <Tile
          name={t('port.aLap')}
          meta={e && e.lap !== null ? t('port.overLaps', { n: e.lap_basis }) : undefined}
          figure={
            e && e.lap !== null ? (
              <Figure size="figure" value={`≈ ${formatDucats(e.lap)}`} />
            ) : (
              <Figure value={t(e && e.laps_done > 0 ? 'port.oneLap' : 'port.firstLap')} tone="muted" />
            )
          }
          // A press opens her newest closed lap, stop by stop — or, before one has closed, the lap
          // under way.
          tap={e ? 'whole' : 'none'}
          onClick={() => onOpenTrades(e && e.laps_done > 0 ? { kind: 'lap', index: 0 } : { kind: 'open' })}
          data-testid="merchant-earnings-lap"
        />
      </TileField>

      <SheetSection surface>
        {card.route && (
          <Row
            mark={<IconDisc name="compass" />}
            label={
              <span className="block min-w-0">
                <Clip>{card.route.name}</Clip>
                <span className="block break-words text-t-caption text-ink-faint">
                  {card.route.stops.map((code, i) => (
                    <Fragment key={`${code}-${i}`}>
                      {i > 0 && ' → '}
                      <GoToLink to={{ kind: 'port', code }}>{portName(code)}</GoToLink>
                    </Fragment>
                  ))}
                </span>
              </span>
            }
            value={<Figure value={formatInt(e?.laps_done ?? 0)} unit={t('port.laps', { count: e?.laps_done ?? 0 })} />}
            data-testid="merchant-route"
          />
        )}
        {e && e.laps_recent.length > 0 && (
          <Row
            mark={<IconDisc name="history" />}
            label={
              <span className="block min-w-0">
                <span className="block">{t('port.lastLaps')}</span>
                <span className="block text-t-caption text-ink-faint">{t('port.newestFirst')}</span>
              </span>
            }
          >
            {/* ONE PILL A LAP, wrapping on their own line under the label — as one joined string
                in the value column they wrapped into each other (owner, 2026-10-15, on Yol
                Portobelo: "the lines are overlapping with one another"). */}
            <span className="mt-1.5 flex flex-wrap gap-1.5" data-testid="merchant-laps-recent">
              {/* EACH PILL OPENS ITS LAP (owner, 2026-10-15): `laps_recent` and world.fleet_trades'
                  `laps` are the same seven, newest first, so pill i is lap i in the panel. */}
              {e.laps_recent.map((n, i) => (
                <button
                  key={i}
                  type="button"
                  onClick={() => onOpenTrades({ kind: 'lap', index: i })}
                  aria-label={t('port.lapPill', { n: formatInt(e.laps_done - i), net: formatDucatsDelta(n) })}
                  className={[
                    'whitespace-nowrap rounded-chip px-2 py-0.5 text-t-caption leading-snug tabular-nums transition',
                    'hover:ring-1 hover:ring-current focus-visible:ring-1 focus-visible:ring-current',
                    n > 0 ? 'bg-success/15 text-success' : n < 0 ? 'bg-danger/15 text-danger' : 'bg-surface-2 text-ink-muted',
                  ].join(' ')}
                  data-testid="merchant-lap-pill"
                >
                  {formatDucatsDelta(n)}
                </button>
              ))}
            </span>
          </Row>
        )}
        <Row
          mark={<IconDisc name="coin" />}
          label={
            <span className="block min-w-0">
              <span className="block">{t('port.fortune')}</span>
              {/* 0213: THE REFOUND IS RETIRED. What stands behind her cargo is insurance: the losses it
                  paid her, and what the insuring cities could not cover. Nothing until a claim. */}
              {card.company.insurance && card.company.insurance.claims > 0 && (
                <span className="block break-words text-t-caption text-ink-faint" data-testid="merchant-insurance">
                  {t('port.insurancePaid', {
                    times: card.company.insurance.claims === 1 ? t('port.once') : t('port.times', { n: formatInt(card.company.insurance.claims) }),
                    paid: formatDucats(card.company.insurance.paid),
                    short: card.company.insurance.short > 0 ? t('port.citiesShort', { amount: formatDucats(card.company.insurance.short) }) : '',
                  })}
                </span>
              )}
              {/* 0123: where her surplus went — her largest stake, and how many cities more. */}
              {card.company.invested && card.company.invested.length > 0 && (
                <span className="block break-words text-t-caption text-ink-faint" data-testid="merchant-invested">
                  {t('port.investedAt', { amount: formatDucats(card.company.invested[0].paid) })}
                  <GoToLink to={{ kind: 'port', code: card.company.invested[0].port }}>{card.company.invested[0].name}</GoToLink>
                  {card.company.invested.length > 1 ? ` +${card.company.invested.length - 1}` : ''}
                </span>
              )}
              {/* 0234: her newest capital gift — her starting money, from her country's capital. */}
              {card.company.last_gift && (
                <span className="block break-words text-t-caption text-ink-faint" data-testid="merchant-gift">
                  {t('port.giftFrom', { amount: formatDucats(card.company.last_gift.ducats) })}
                  <GoToLink to={{ kind: 'port', code: card.company.last_gift.port }}>{card.company.last_gift.name}</GoToLink>
                </span>
              )}
              {/* 0145: where her country's race is — her largest influence, the city and the country. */}
              {card.company.influence && card.company.influence.length > 0 && (
                <span className="block break-words text-t-caption text-ink-faint" data-testid="merchant-influence">
                  {t('port.influenceAt', { n: formatInt(card.company.influence[0].points) })}
                  <GoToLink to={{ kind: 'port', code: card.company.influence[0].port }}>{card.company.influence[0].name}</GoToLink>
                  {t('port.forNation', { nation: nationNameOf(nationByCode, card.company.influence[0].nation) })}
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

      <SheetSection heading={t('port.ships')}>
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

      <SheetSection heading={t('port.cargo')} surface>
        <CargoRows rows={cargo} totalTons={card.ships.reduce((n, s) => n + s.cargo_tuns, 0)} testId="merchant-cargo-row" />
      </SheetSection>

      <SheetSection heading={t('port.captains')} trailing={<span className="text-t-caption text-ink-muted">{t('port.master', { name: card.company.master })}</span>}>
        {card.officers.length === 0 ? (
          <Row label={t('port.noCaptains', { name: card.company.master })} tone="muted" hairline={false} />
        ) : (
          <TileField>
            {card.officers.map((o) => (
              <OfficerTile
                key={o.name}
                name={o.name}
                role={o.specialty.toLowerCase()}
                bonusPct={o.bonus_pct}
                homePort={o.home_port ? <GoToLink to={{ kind: 'port', code: o.home_port }}>{portName(o.home_port)}</GoToLink> : null}
                testId="merchant-officer-tile"
              />
            ))}
          </TileField>
        )}
      </SheetSection>

      {/* THE COMPANY'S FOUR LEVELS (docs/WORDS.md: the word is Skills), and their sum beside the
          heading — the same number the city's list prints for her (0113). */}
      <SheetSection
        heading={t('port.skills')}
        trailing={
          <span className="text-t-caption text-ink-muted" data-testid="merchant-level">
            {t('port.level')} <span className="text-t-body tabular-nums text-ink">{formatInt(level)}</span>
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
        <SheetSection heading={t('port.lastLap')} surface>
          {skipped.map((s, i) => (
            <Row key={`${s.line}-${i}`} label={skippedWords(s, goodName, portName)} tone="muted" hairline={i < skipped.length - 1} />
          ))}
        </SheetSection>
      )}
    </div>
  )
}
