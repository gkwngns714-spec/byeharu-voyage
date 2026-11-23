import { Figure, Hint, Note, Row } from '../../../components/ui'
import { fleetCrew } from '../../../domain/fleet'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { formatInt } from '../../../lib/format'
import type { BoardBuyRow, BoardSellRow, FleetView, GoodBoard } from '../../../lib/rpc'
import { useT } from '../../../lib/i18n'
import { reachBoard, reachWords } from './planLines'

// THE PLAN'S VOYAGE — the owner, 2026-10-20 (docs/OWNER_REQUESTS.md row 183):
//
//     "In command, when I press plan this trade, it should switch to plan tab and make planning there. It
//      should show map (without npcs or name of the cities that aren't associated with the route/plan, and
//      show how long, provision needed for the current crew, how many crews needed, etc... It should show
//      restrictions – if whether my level, my class, my ship can go to that location."
//
// Under the trade card, on the Trade face:
//
//   THE CHART — since owner row 217 (2026-10-26: *"on command, trade, map should be at top"*) the plan's chart is
//   THE map on top of the Trade page (TradeMap.tsx), drawn from the same legs (usePlanCourse.ts) this lists.
//
//   THE VOYAGE — days at sea as the board serves them (to the buy city, then on to the sell city) and the crew
//   against the ships' minimum (`fleetCrew`, row 179's model: `ship_classes.crew_required`, below which SAIL
//   refuses E_CREW_SHORT). The supplies are not worked out here any more (0225): the trade card prints the
//   board's own `supplies` for the chosen row — public.supply_need's reading, the rule cmd.do_sail buys by.
//
//   CAN YOU GO THERE — the ONE authority, read and printed, never re-judged here:
//     · the reach (0188): the board's `sailable` / `needs` per city, in `reachWords`, THE wording; and her ship classes.
//     · NO SEA ASKS (owner, 2026-11-23: "remove sea limits entirely"; docs/design/hq-command-2026-11-23.md): her title, her
//       waves and what each sea on the way asks are no longer drawn. A refusal the server makes still reads in its own words.
//
//   THE LEGS — each SAIL of the plan, from → to, with its days at sea at the fleet's speed — stand UNDER
//   THE MAP since owner row 191 (TradeMap.tsx `PlanLegs`; docs/COMMAND_REDESIGN.md §3), not here.
//
// A PRESS SELECTS: every row above the legs is always drawn (a dash while a figure is unknown), and the chart
// has a fixed shape, so choosing another city changes figures in place and moves nothing.

export function PlanVoyage({
  fleet,
  board,
  buyRow,
  sellRow,
}: {
  fleet: FleetView
  board: GoodBoard | null
  buyRow: BoardBuyRow | null
  sellRow: BoardSellRow | null
}) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const name = (code: string) => portNameOf(portByCode, code)
  const crew = fleetCrew(fleet)

  // CAN YOU GO THERE — the reach, per city the plan sails to (the board's verdict, in THE wording).
  const reachRows = [buyRow && !buyRow.here ? buyRow : null, sellRow].filter(
    (r): r is BoardBuyRow | BoardSellRow => r !== null,
  )
  const classes = [...new Set(fleet.ships.map((sh) => sh.class))].join(', ')

  return (
    <div className="mt-4" data-testid="plan-voyage">
      {/* CREW NEEDED (2026-11-15 owner: shorter words; 2026-11-23, finding 15: one figure, the ships' minimum; who is aboard is the
          ship panel's "Crew 8 · room 20"), short in the warning tone with the hint under it */}
      <Row
        label={t('desk.crewNow')}
        value={<Figure value={formatInt(crew.required)} tone={crew.short > 0 ? 'warning' : 'ink'} />}
        hairline={false}
        data-testid="plan-crew-min"
      />
      {crew.short > 0 && <Hint>{t('desk.crewShort', { n: formatInt(crew.short) })}</Hint>}

      <section className="mt-4" data-testid="plan-restrictions">
        <Row label={t('desk.yourShips')} value={<Figure value={classes || '—'} />} />
        {board &&
          reachRows.map((r) =>
            r.sailable === false ? (
              <Note key={r.port} tone="danger" className="mt-2" data-testid="plan-unreachable">
                {`${name(r.port)} — ${reachWords(r, reachBoard(board))}`}
              </Note>
            ) : (
              <Hint key={r.port} data-testid="plan-reach">
                {t('desk.reachOk', { port: name(r.port) })}
              </Hint>
            ),
          )}
      </section>

    </div>
  )
}
