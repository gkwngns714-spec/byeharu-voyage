# 2026-11-22: Named world events: a famine, a festival, a blockade (0469, proof 172)

The design: `docs/design/playable-2026-11-22.md` P2 ("named world events (famine, blockade, festival) on the fair's rails") and
`docs/design/content-plan-2026-11.md` item 8. Ships **dark** behind `world_events_enabled` (false). Lighting it is the owner's.

## What a player sees, lit

- **Trade**, at the top of the list: one line per event running or announced, e.g. "Famine · Seville · Food ×2 · ends in 4 h" or
  "Blockade · Cadiz · Fees +20% · starts in 40 min". Pressing a line makes that harbour the city in hand, so its cards are one press away.
- **The Trade cards** of a famine or festival harbour say "Wanted ×2" (or ×1.75) on each good it wants, as a drawn city want does.
- **The quay** (Office › City) shows the events at that harbour under the Fair's row.
- **The map** rings each event's harbour: a famine amber, a festival in the accent colour, a blockade red with a double ring.
  A ring is solid while the event runs and dashed while it is announced.
- **The News** gets a world headline the moment an event is named, an hour before it starts: "Famine in Seville" / "Seville 기근".

Dark, the read answers `{"on": false}` and none of these draws anything. Every screen is as it was.

## The events and what they do

| Event | Effect (on `buff_kinds`) | Goods | What it does | Length |
|---|---|---|---|---|
| Famine | WANT, magnitude 100 | food, grain | the city pays ×2 for them, up to 25 % of its stock target each want-period (2 h) | 6 h |
| Festival | WANT, magnitude 75 | drink, gems, art | the city pays ×1.75, the same cap | 4 h |
| Blockade | TOLL, magnitude 20 | every good | the port's cut rises by 20 points of the price: buying costs about 10 % more, selling pays about 10 % less | 4 h |

## The rails (one authority per concept)

- An event **is a row** of `buff_kinds` (0026), off the Fair's calendar (`season_seconds` null), and a row of `active_buffs` with a
  start and an end, at a harbour (0036's trigger), with `source = 'event:<slot>'`.
- A **want** goes through `world.want_left`, THE one reader of a city's want (0255). The event's want is served beside the drawn want
  and the higher one wins. So the quote's walk, the sale's tally, the short city's rule (0263), the market rows' `wanted`, the Trade cards
  and every merchant house's sale read it with no change of theirs. A want needs a closed economy, as 0255's do (the city pays from its purse).
- A **toll** goes through `world.spread`, the port's published cut, so every quote, trade and merchant house pays it.
- **One writer**, `public.tick_world_events`, runs at the end of `public.tick_buff_calendar`. That is the `byeharu-voyage:buff-calendar`
  job (every 10 min), and the reads that wind it (`world.fleets`, `world.buffs`). No new cron.
- The merchant houses react through the market as they already do: their sales at a famine harbour get the same want and use up the
  same cap as a player's, and their trades at a blockaded harbour pay the same cut.

## Rates (the budget)

- One draw an hour (`world_event_slot_seconds` 3600) at chance 0.5 (`world_event_chance`). At most 3 running or announced at once
  (`world_event_max`). Named 1 h before they start (`world_event_lead_seconds`). That is about 0.5 events an hour, and about 2.8 at once
  at steady state.
- Rows per event: 1 `active_buffs` insert, 1 `world_news` insert, and up to about 130 `port_goods.want_period` marker updates for a
  famine (only rows never marked before; the quote walk asks `want_left` only on a marked row). Each row is deleted 24 h after its
  event ends (`world_event_keep_hours`). **About 0.02 inserts and under 1.2 row updates a minute** on average.
- Dark: one `world_config` read for each `tick_buff_calendar` call and each `want_left` call. Lit with no event named: one md5 and
  one small count. A try-lock (it never waits) keeps two callers in one slot from naming two events.

## Decided by default (the owner may reverse)

- **Blockade = a toll, not a closed port.** Refusing trades at a port would stall merchant houses mid-loop. A big toll on the cut is a
  clear "do not trade here, or pay for it" through the one place every price reads.
- **A harbour is drawn uniformly** among the harbours holding no event. For a famine or festival, it must also show at least 3 of
  its goods on the quay, so the cards carry the want.
- **The switch stops everything at once,** including events already named: the want, the toll and the read are all gated on it.
- **Luxuries = drink, gems, art.**

## Proofs

- 0469's self-assert: the hunks reverse, no other function moved. Dark, byte for byte: every harbour's `world.spread` and every Lisbon
  `world.want_left`. A rolled-back probe: dark nothing acts; lit a famine ×2 / 25 % cap and a sale priced up, a blockade +0.20, the
  read lists them, one event a slot with its news, none past the most-at-once, and switched off it is dark again at once.
- Proof 172 (`scripts/db/proofs/172_named_world_events.sql`), 7/7 locally: WE_DARK, WE_NAME (through the job's own call), WE_FAMINE
  (market rows and a sale quoted 34.60 against 16.50), WE_FESTIVAL, WE_BLOCKADE (Cadiz 0.0200 to 0.2200, in the market's port line
  too), WE_LIMITS (the most at once, the 24 h keep), WE_OFF.
- Harness: `scripts/ops/harness/world-events/before-0469.sql`, `after-0469.sql` (read-only, one statement each).
