# 2026-11-16: a route in reach, and a report on return (content plan, slice B)

The design is `docs/design/content-plan-2026-11.md` §5.3 no. 2 and §5.4 slice B. Client only: no migration, no knob.

## What was built

1. **Make route, on the arrival card** (`src/live/ArrivalRepeat.tsx`). When one fleet comes in at a harbour from another
   harbour and the card's served profit is above 0, the card offers **Make route** (KO 항로 만들기). One press turns the
   trip into a standing route and starts it on her: the two harbours, where she lies first, each selling everything,
   each buying what she bought there and sold at the other (`tripRoute`, `src/live/standingRouteDraft.ts`, from her own
   BOUGHT and SOLD events). It goes through the one path the route editor's Start takes, now one function
   (`src/live/startRoute.ts` → `cmd.standing_route_save`, `cmd.standing_route_assign`). The server's refusal is printed
   in the card above the button; the button stays where it was and reads **On route** after the start. Edit is on the
   route's own page. Whether it is offered is decided once, when the card comes up.
2. **The route where her name stands** (`src/features/command/buysell/TradeStatus.tsx`): Trade's fleet line says
   `On route · Next lap 18:31` (the route's own words, `routeStateWord`). A line of its own on the wide strip; on a phone
   the second line in port, when the board's city does not take it. The Fleets row already said `On route`.
3. **While away** (`src/app/AwayCard.tsx`, `src/domain/route/away.ts`). One card at the head of the glass on return:
   each route's laps closed and their net, a route that needs her (stopped, blocked, paused by the game), and the
   purse's move. Close takes it away; nothing under it moves.

## How "away" is defined (decided by default)

This device did not have the game open and in view for **ten minutes or more**. The device keeps a mark in
localStorage (`bv:last-seen:<mode>:<company id>`): the time, the purse, and each route's all-time lap counters
(`earnings.total.laps` / `.net`). It is written on every world read while the page is in view and when it is hidden.
On a load, or when a hidden tab comes back, the first read compares against the mark. The laps and net are the
difference of the server's own all-time counters, so they agree with the route's page and History however many laps
closed (the book serves only the last ten). No mark (a new player, a new browser): the mark is kept and nothing is
said. Nothing moved: no card.

## Left out of the design

- The card names only routes and the purse. Skills finished, a ship at the yard, shares paid and fairs (the design's
  wider list) are not in it: the yard (slice C) does not exist yet, and the others were left for a later piece.
- "Away" is per device: a player who looked on her phone is still "away" on her laptop.
- The trip's buys carry no price cap and buy as many as fit (the editor's defaults).
