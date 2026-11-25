# 2026-11-25 — `wreck-can-sell`: 0497 (dark: `wreck_sells_enabled`), proof 204

Off `origin/main` (prod head 0496). Server only. Nothing touched production: no prod read was run by the builder. No knob but the
new switch (false).

## The owner's own company (the lead's prod reads, 25 Nov 01:45 UTC)

Purse 0. Her one fleet, Gaivota, `UNABLE_TO_SAIL` at Diego Garcia (a market, an inn, a warehouse; no shipyard), hull 0, 899 black
coral aboard. Her queue: `SAIL BAN`, `SAIL MAL`, `SAIL MAC`, `SELL black-coral ALL`, all pending. Her Best job is not stopped.

## What she can do today (read in the bodies, then played locally in exactly that state)

- **Sell: no.** `cmd.do_sell` (and `do_store`, `do_take`) ask status `DOCKED`. It is worse than a refusal: `cmd.preview` answers
  `{queued: true}`, `cmd.issue` answers ok, and the order waits for ever, because `cmd.advance` runs nothing for an
  `UNABLE_TO_SAIL` fleet. Cargo 899, purse 0, a green press.
- Her pending orders and her job do not block it, and Clear does not free it: a SELL sent after Clear only queues again.
- **Tow: no.** `cmd.tow` takes her to the nearest yard (Colombo, 958 nm) for 958 x `tow_fee_per_nm` (15) x her running-cost factor:
  14,366 here. Purse 0: `E_TOW_FUNDS`, "Money 0 / 14,366". No credit.
- So she is stuck for ever, with a hold worth half a million coin.

## What 0497 does (lit; dark every body answers as before, asserted to the letter)

- **`public.fleet_alongside(fleet)`**: does she lie where a cargo is landed? The one reading the three cargo doors now ask instead
  of each asking `status <> 'DOCKED'`: DOCKED as before; or, lit, a PLAYER's fleet that is `UNABLE_TO_SAIL`, lies in a port and has
  a ship. Not alongside: a wreck at sea, an empty fleet (0321), a merchant's fleet (`public.npc_tend_route` tows her). Her state is
  still the one rule's (`public.fleet_state_of`: wrecked); this asks only whether a quay is under her.
- **`cmd.do_sell`, `cmd.do_store`, `cmd.do_take`** ask it (one hunk each). Everything after that line is untouched: the same
  quote, tax, wages, dock fee, day limit and city purse.
- **`cmd.advance`** (three hunks): a wreck alongside runs her queue's SELL / STORE / TAKE orders in their order and steps over the
  rest without running or cancelling them. Her SAILs stay pending; a tow clears them, as before. No standing route refills a
  wreck's queue.
- **The truth** (`public.wreck_order_refusal`, asked by `cmd.preview` and `cmd.issue`): a wreck's order that cannot run (BUY, SAIL,
  HIRE, REPAIR, or anything while she lies in no port) is refused, `E_NOT_DOCKED`, "Gaivota is wrecked: she can sell or store her
  cargo here, and nothing else until a tow and a repair". It is not queued. Her SELL's dry run is a real quote.
- Eight hunks over six bodies, four new server-only functions, one knob.

## Her queue, lit

Nothing runs at the moment the switch is lit. Her next press (any order she sends) calls `cmd.advance`, which runs the
`SELL black-coral ALL` already waiting in her queue, then her own. Proof 204 plays it: she presses Sell for one coral; the waiting
SELL ALL sells the day's limit first, and her own one-coral order is then refused by the quay's day limit ("Day limit 0 / 1 tons").
That second line is true but will read oddly; said plainly.

## Proof 204 (local world; prod's quay will quote differently)

| | |
|---|---|
| Dark | dry run `{queued: true}`; the press answers ok, the order stays pending; the tow: `E_TOW_FUNDS` "Money 0 / 14,366" |
| Lit, the dry run | 210 coral for 508,571 coin (the day's limit; 899 aboard) |
| Lit, one press | 210 sold, purse 508,571; `SAIL BAN / MAL / MAC` still pending; she still wrecked at Diego Garcia |
| BUY, SAIL, HIRE, REPAIR | refused in plain words, nothing queued |
| STORE 2, TAKE 2 | both run at Diego Garcia's warehouse |
| Then | the tow to Colombo, 14,366; she lies DOCKED there, queue cleared, 689 coral aboard; the repair costs 752 |
| Others | a docked fleet sells as before; a wreck at sea, a merchant's wreck, an empty fleet: not alongside |

## Cost for a normal fleet

A docked dry run of a SELL, mean of 20 in the migration's own scene: 2.60 ms before the hunks, 2.50 dark, 1.85 lit (noise: the
answer is identical, asserted). One function call more in each cargo door (her fleet row by key, one knob read). `cmd.advance`
asks nothing new unless her status is `UNABLE_TO_SAIL`. No job-plan path is touched.

## The self-assert on worlds that are not the chain's (, a private copy of the cache)

The self-assert runs on production when it deploys.  applies the chain to 0496,
then for each of 13 worlds: perturb, run 0497 whole, roll back.

- **Passes in 12:** the chain as it is; prod's switches lit; every quay at a tenth, ten times (glutted), none, and a thousand times
  its stock; a closed economy with the home quay broke for the sale; the home quay with no market row at all; no hands and no
  merchant in any port; real wrecks and queues standing (the owner's company to the row: her four pending orders, a Best job, two
  other companies' wrecks, an empty fleet), alone and with prod's switches and a glut; wages owed and a dock fee on every fleet.
- **It found one fault, fixed:** the first version RAISED when no good sold at the probe's home quay (a broke purse, missing rows),
  so the push would have been refused in such a world. Now the law is read on the quay's own refusal there: the wreck's dry run and
  her order are refused exactly as a docked fleet's are (, ), never queued.
- **One known refusal, not this file's:** with the economy closed and Lisbon's purse under 40,000,  itself
  refuses (), and the probe founds its company that way, as every migration's probe does. Nothing is applied in
  that case.  reads the two facts ().

## Checked

- 0497's self-assert on the snapshot at 0496: passed (268 ms). Proof 204: 6/6.
- Neighbouring proofs, `tsc -b`, eslint, `db.budget`, `news.lint`: see the commit.
- The before / after reads: `scripts/ops/harness/a-wreck-can-sell/` (their selects run on the local world).

## Decided by default (the owner may reverse)

- Dark behind `wreck_sells_enabled`: it changes what a press does for a live player, so the lead lights it.
- TAKE is allowed as STORE is (a wreck may take stored goods up to sell them on the quay).
- A merchant's wreck is left exactly as it is.
- A plan of several lines for a wreck (`cmd.issue_lines`) still queues: no screen sends one to a wreck, and a job's plan asks
  DOCKED already.
- The refusal reuses `E_NOT_DOCKED` (a code every screen already words) with its own sentence.

## Not verified

- Prod: nothing was read by the builder. Diego Garcia's real bid for black coral, the day's limit there, her running-cost factor.
- `vite build`, `tests/rpc.surface.spec.ts` and the browser specs were not run (a build prunes the shared snapshot cache).
- No client change here: whether the live client's Sell face opens for a fleet that is `UNABLE_TO_SAIL` was not driven. That is
  the client half, on its own branch.
- The switch is not lit and the owner's fleet is not freed by this deploy alone.
