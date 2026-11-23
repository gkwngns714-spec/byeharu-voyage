# 2026-11-23 — 0483 courier contracts between companies and houses (dark: `contracts_enabled`)

`docs/design/roadmap-2026-11-23.md` slice 14 ("Contracts between companies and houses", EVE's courier contracts), on HQ's board
(`docs/design/hq-command-2026-11-23.md`). The owner, 2026-11-23: "i want this game to be strategical game, where all the work
(activities) are done in HQ - words with graphics. choosing best options available, finding best options."

## What it does (lit)
- **A contract** (`public.courier_contracts`): carry this lot from A to B within a window, for a reward, against a collateral. Posted by a
  merchant house, a city or a company. Its life: open → taken → delivered or failed; or open → lapsed (untaken in 6 hours) or cancelled
  (a company takes her own post down).
- **Houses post on their own.** A cron job, `byeharu-voyage:contracts`, runs `public.tick_courier_contracts()` every 2 minutes. While the
  open house and city contracts number under ceil(houses / 20) (prod: 869 houses, so 44), it posts up to 3 a run
  (`public.courier_draw`). Each draw picks:
  - who: a house with no live contract of its own (its home harbour is A), or, with the city purses lit, a city for a quarter of draws;
  - the good: one A offers;
  - B: a harbour 150 to 1,500 sailed miles away that trades the good, does not make it, and whose culture takes it;
  - the lot: 20 to 120 tons, at most 30,000 at A's mid;
  - the reward: the lot's value x 6-12 %, plus 1 % a 100 miles;
  - the collateral: the lot at the dearer mid of A and B, x 1.25;
  - the window: the trip at 8 knots, x 3, at least 30 minutes.

  The reward is held at posting (a house's purse, `CONTRACT_ESCROW`; a city's treasury). Nothing else runs on the beat.
- **A company takes one from HQ in one press** (`cmd.take_contract`, the card's act). Her fleet must lie idle in a harbour (nothing
  queued, no standing route or job). The take:
  1. holds her collateral (`CONTRACT_COLLATERAL`);
  2. loads the goods: aboard now when she lies at A, otherwise into her Storage at A;
  3. sends ONE plan through `cmd.issue_lines` with stored courses (`public.fleet_job_sails`, the path `public.sale_lines` writes):
     `SAIL B`, or `SAIL A / TAKE <good> <units> / SAIL B`.

  All of it or none: a refused plan rolls the take back and its refusal is the answer.
- **Delivery.** Her fleet lies at B with the units aboard, and she came in by the deadline (now, or a voyage that ended at B in the
  window). The tick delivers it within 2 minutes, or she presses the Deliver card. The units leave her hold, and the reward
  (`CONTRACT_REWARD`) and her collateral (`CONTRACT_RETURN`) are paid to her. A company poster's goods land in her Storage at B; a full
  shed never refuses a delivery.
- **Failure.** The deadline passes, or she gives up (`cmd.fail_contract`). The collateral goes to the poster (`CONTRACT_FORFEIT`), and
  the reward goes back to the poster (`CONTRACT_RETURN`). The units still hers to give (her hold first, then her shed at A) are returned:
  to a company poster's Storage at A, or to the house or city. The rest (sold, raided) are lost. The outcome row says how many of each.
- **Post a contract.** The Requests face's "New request" door becomes "Post a contract" when lit (`ContractPage.tsx`, three steps: a good
  in her shed here, the harbour it goes to, then units, reward, collateral and hours). `cmd.post_contract` takes the goods out of her
  Storage and holds the reward. "Your contracts" (posted and carried) stand above the door, each with its state and its one press
  (Take down, Give up).
- **The money** moves through `public.credit` and `public.treasury_post` alone. The five kinds are money moved
  (`public.stats_flow_words`), so the economy-closed guard never refuses them. The money log has words for them, EN and KO.

## HQ's board
- `public.hq_board_for` gains ONE hunk: `v_moves := v_moves || public.courier_moves(p_player, v_purse)`. It returns nothing when dark.
- Cards of kind `contract`, band 1, ranked with trade runs and requests by coin an hour (the same ORDER BY):
  - **Take** (the `pact` glyph, "Carry porcelain to Porto"): for each of her idle fleets, each open contract not hers whose trip (to A,
    then A to B, at her fleet's speed) fits the window, whose collateral her purse covers, and whose lot her hold takes (and, away from A,
    her shed at A). Score: the reward x 3,600 / the trip's seconds. Risk: `public.hq_course_risk` over her port, A and B. At most 6.
    Chips: the fleet, the good and units, the time, "Load at" A (when she is elsewhere), the collateral (gold), the risk mark.
  - **Deliver** ("Deliver porcelain"): her taken contracts that deliver now. Score: the reward x 3,600 / 900 s, as a request.
- A Contracts filter chip shows when a contract card is served.

## Measured
- **Local chain (PGlite).**
  - The self-assert takes ~240 ms.
  - Proof 186 (7 markers) takes ~0.8 s.
  - One lit tick with 15 open contracts and 3 posts: **27 ms**. Six ticks posting 3 each: 23-61 ms.
  - Her cards (`public.courier_moves`) with one idle fleet at Lisbon and 15 open: **4 ms**.
  - The served board's card in proof 186: 10 porcelain LIS→OPO, +800 in 197 s.
- **Prod (`before-0483`, the one read, 2026-11-23 ~10:20 UTC).**
  - The gate, read in the same statement: beat mean 179 ms over 5 minutes (285 beats), 765 MB, 0 sessions waiting on the disk.
  - Head 20260818000482; no `contracts_*` knob; the hunks' new text absent; none of the five money-log kinds; money-log `ord` max 62.
  - The probe's selections: porcelain at Lisbon, OPO (158.5 nm, stored course, a shed), the richest house's purse 317,079,288, Lisbon's
    shed 750 tons.
  - 869 houses, all at harbours (cap 44). Switches: city treasury, economy closed, sea courses, HQ board, fleet jobs and standing routes
    all lit.
  - 20 `voyage.reach_from` calls: 9.4 ms (5,340 rows). Five draws' reads priced 5 of 5.
  - Only the read's tail was captured (the CLI output was cut), so `absent`, `anchors`, `bodies` and `draw_ms` were not seen. The
    self-assert checks each hunk's anchor once against prod's live body at deploy and refuses otherwise. The chain's pre-0483 md5:
    `hq_board_for` 8c4b05522af982dcab3e0d96558ce599, `client_rpc_entry_points` 4ba23ba5d43c5d39653f8ad63fd19a1e.

## Load (budget lines in the file)
- **One new table**, `public.courier_contracts`: about 45 live rows. A settled row is kept 3 days and then deleted by the tick (200 a run
  at most), so about 550 rows at the most.
- **One new cron job**, every 2 minutes:
  - dark, one knob read and 0 rows;
  - lit, at most 3 posts, 50 lapses and 100 settles a run. On a normal day that is about 10 rows a run (a post: its row plus one ledger
    or treasury row; a settle: its row plus 1-2 ledger rows).
- **No step on the arrivals beat.**
- **A board read** adds one `voyage.reach_from` per idle fleet (~0.5 ms on prod by the read above) and the live contracts.

## Decided by default (the owner may reverse)
- The names are `courier_*` (the table, the functions, the read), because `public.contract_draw` / `world.contracts` already belong to
  the city requests (`trade_contracts`). The player word is **contract** (docs/WORDS.md row; `tests/words.spec.ts` allows exactly these
  words, so a port's ask is still a "request").
- **House goods are the house's own:** they are not taken out of A's market stock (no `port_goods` write), and on delivery they leave the
  game with the house.
- **A carrier holds at most 2 contracts; a company posts at most 3.** An untaken contract lapses after 6 hours.
- **The window starts at the take.** A card shows only when her fleet's trip (to A, then to B) fits it.
- **Delivery is automatic** (the tick, within 2 minutes of her arrival), as well as by the card's press. Arrival by the deadline counts
  even when the tick runs after it.
- **A failed contract reclaims the units** from her hold first, then from her shed at A. That can include her own units of the same good,
  up to the contract's count.
- **The window and collateral:** a company sets 1-48 hours and any collateral (0 or more).
- **A fleet on a standing route or job cannot take a contract** (`E_ROUTE_TAKEN`), so a job's SELL ALL never sells contract goods.

## Prod checks
- Before: `scripts/ops/harness/contracts/before-0483.sql` (done, the one read).
- After (and 30 minutes after lighting): `scripts/ops/harness/contracts/after-0483.sql`.
