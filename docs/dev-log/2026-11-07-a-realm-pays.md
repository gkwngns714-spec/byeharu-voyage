# A realm pays for its navy (migration 0335, owner row 285, question 9, dark)

Owner, on question 9 of `docs/dev-log/2026-11-06-a-country-has-a-navy.md`: *"use your recommended defaults"*. So a capital that cannot pay for its navy draws on its realm, the richest city first.

**State: built, dark, PR open, not deployed.** `navy_enabled` stays false. No line of the new rule runs until the owner lights it. No switch is touched.

## What it does, lit

- **The payer is one function: `public.capital_draw`.** It adds nothing that moves gold. It hands `public.crown_call` (0307) one roster line: the capital, and what it needs. So the order, the locks and the limits are the ones every call already has. Gold moves to the capital by `CROWN_CALL`, moved, nothing minted, nothing owed. The capital then pays as 0331 wrote.
- **Build: all or nothing.** A hull is one payment. `public.capital_can_draw` asks first, with no lock. If a busy city still leaves the realm short, the draw rolls its own call back. Without that, every minute would walk 10 % of the realm's room into a capital that still could not build.
- **Hourly pay: as far as the realm goes.** The need is every ship at work. The ships it covers are paid, lowest number first, as 0331. The rest go home and lie up. No debt.
- **Wake: moves no gold.** She needs only `capital_can_draw` for her next slice. The next hour's pay fetches it.
- **A rich capital calls nothing and reads no city** to decide so.
- **One read of who can give.** `public.crown_donors` is lifted out of `public.crown_call`, same statement, so "can the realm pay" and "who pays" cannot disagree.

`crown_call_share` 0, 0307's rollback, stops this too: no room, no donor.

## What it does to the 31 of 75

Prod, read only, 2026-11-07, head 0334. Galion 1,156,000 d.; a slice 2,500 d. an hour. **Ships** is the formula on today's purse; `navy_realms` is empty, so nothing on prod holds this number yet.

| Power | Purse | Ships | Capital | Surplus | Realm's room | Richest, room | A hull now? |
|---|---:|---:|---|---:|---:|---|---|
| PRT | 4,393 M | 15 | LIS | 308,139,906 | 408.4 M | OLD 378.4 M | Capital alone |
| FRA | 3,360 M | 13 | MRS | 163,526 | 335.8 M | GOA 335.8 M | **New** |
| ESP | 2,429 M | 11 | SVQ | 486,692,961 | 193.6 M | PLO 75.2 M | Capital alone |
| NLD | 1,604 M | 10 | AMS | -10,182 | 160.3 M | COP 125.8 M | **New** |
| MNG | 648 M | 7 | GUA | 125,799 | 64.7 M | MAL 47.3 M | **New** |
| OTT | 348 M | 5 | IST | 233,387 | 34.7 M | VLL 21.7 M | **New** |
| JPN | 289 M | 5 | SAK | 237,645,044 | 4.7 M | HOI 4.3 M | Capital alone |
| MUG | 115 M | 4 | KAR | 104,959 | 8.6 M | BSR 4.0 M | **New** |
| ENG | 73 M | 3 | LON | 429,033 | 7.1 M | DUB 6.2 M | **New** |
| JOS | 4 M | 2 | BUS | 224,841 | 34,816 | THA 28,275 | **No** |

**By arithmetic on that table, 73 of 75 hulls can be paid for, in nine of ten realms.** That is not a run: no simulation over the days of building, and purses move. Joseon stays at none: its capital and room come to 259,657 d., far under a hull, and its realm's purse has fallen from 12 M to 4 M since 2026-11-06. The owner should see this one (below).

## Where this differs from the brief, or chooses

1. **`public.crown_call`, not `public.capital_pays`.** `capital_pays` pays a company's purse and WAITS on a realm harbour's lock. A navy ship has no purse and the job must not wait. Its own read of who pays stands. It differs on purpose (surplus, not room) and 0324 already says that call dies.
2. **The richest city is measured by room, not by balance.** `crown_call_room` is what a city may give in one run, so a city with a higher balance and a large reserve may rank lower. The brief says the way `convoy_rich_enabled` serves cargo: that is its measure too.
3. **The richest city pays the capital, not the yard.** The ledger therefore shows `CROWN_CALL` then `BUILD_NAVY` (four rows). The other way, a hull could not be shared by two cities and a city's limits would be judged in a second place.
4. **The call is instant, and that is a decision for the owner to see.** This does not read `public.rich_cities_on()`. The owner's *"not instantly. it should see on the map"* was written of gold going to poor cities, and lit, `crown_aid` and `capital_pays` stop calling. A navy's pay has always moved at once, so I kept that. Lit together, `CROWN_CALL` rows still appear. 0324's "no `CROWN_CALL` lit" now means "for a city's aid". **The slice that deletes the off arm of `crown_aid` must keep `public.crown_call`:** it has a second caller. The file's header says so.
5. **A capital under its reserve is made whole first.** That is `crown_call`'s rule, kept. Today it is AMS's 10,182 d. A capital far under its reserve would pull that whole gap at the first hourly pay, as far as the city limits allow, before a ship is paid. No capital is near that today. Not a new path: `crown_aid` does the same when a city is short.
6. **`public.crown_call` itself is re-cut**, a live function, for the lift. Same statement. `RP_FOLD` compares it to 0307's statement on every capital.

## Spaghetti, named, not folded

`public.cargo_origins` (0324) holds a third writing of nearly the same read, with a course test, a limit and the capital included. `public.capital_pays` holds a fourth, by surplus. This slice lowers the count by one and adds none. I left `cargo_origins` because it is dark code outside this slice's rule and its shape differs; `public.crown_donors` is where it should fold. `capital_pays`'s call is already marked to die.

## Hot bodies re-cut (8 hunks, each once, each reversing, read on prod at head 0334)

`crown_call` (2), `navy_add` (4), `navy_pay` (2). New: `crown_donors`, `capital_can_draw`, `capital_draw`. No table, knob, kind, word or job. No client change: `CROWN_CALL` already has its word. The Codex line *"Paid by its capital"* stays true.

## Cost

PGlite, this PC, `--cost`. **The scale:** 0331's dev-log uses about × 6.7 for prod. The prod column is that arithmetic, not a measurement. A prod timing read was refused by the permission system and I did not go round it.

| Call | PGlite | Projected prod |
|---|---:|---:|
| `capital_can_draw`, the capital alone | 0.2 ms | 1 ms |
| `capital_can_draw`, the realm read | 15.5 ms | 0.1 s |
| `capital_draw`, one donor | up to 16 ms | 0.1 s |

**Steady state:** after a day's hulls only a realm that cannot pay is read each minute, today JOS, so about 0.1 s a minute, read only and no lock. Worst minute: nine realms at their day's add, but a run stops at its first hull. Pay adds one read and one call, one country a run.

**Rows:** at most about 340 `CROWN_CALL` rows a day on top of 0331's 1,300: two an hour for each of seven capitals, more when two cities give.

## Proof

- `scripts/db/proofs/42_a_realm_pays.sql`: 13 markers, the real job and real purses on Portugal's realm, economy CLOSED as prod, `RP_OPEN` with it open. No ship sails; proof 37 sails them.
- `scripts/ops/harness/realm-pays/proof-0335.mjs`: red first, four dark scenes equal before and after, real file green, **31 mutations each red for its own reason** on the world at head 0334, proofs 17, 32, 37, 39, 40 green on it.
- `RP_BUSY` is the one that matters most: on paper the realm can pay, its richest city is busy, the second city's call is rolled back, no row.
- Self-assert: catalog, then the draw on a probe nation of its own rolled-back harbours, a richer harbour outside it. Purses are written on the probe's own rows, so no minted kind is credited and it reads the same with the economy open or closed. About 170 ms locally on the small world.
- `before.sql` on prod at head 0334: all 8 hunks once, `new_fns` 0, `navy_on` false, `navy_rows` 0, `probe_codes` 0, `CROWN_CALL` moved.
- `npm run db:apply`, whole chain from zero on PGlite, this PC: 319 migrations, 331 receipts, the world guard ok, 0335's self-assert 167 ms.
- `tsc -b`, `eslint`, `tests/sections.spec.ts` and `tests/duplication.spec.ts` clean.

**What the runs found:**
- The first apply died on the self-assert: `port_allegiance` wants a great power, so the probe nation is one now. `npm run db:apply` takes no cache, so that was a 42-minute answer on this PC. The harness's own cache stood at 96 files; it has `--snapshot` now and holds 318.
- Proof 37 red, for a right reason: its capital-alone scene had a rich yard in the realm. Moved deliberately, with a dated comment: that scene now reads the realm bare. Nothing was loosened.
- My own first mutations found five holes: a busy-capital stub that hid the capital's lock; a fold with no tie and no empty city; a rich-capital branch nothing proved. The proof now holds each. One was a line that did nothing: `capital_draw`'s early return repeated `crown_call`'s own test, so it was deleted.
- `scripts/ops/harness/armed-cargo/dark-scene.sql` went red once at random on an unordered `jsonb_agg(s.crew)`: `[17,0,0]` against `[0,17,0]`, ship order, not money. It now sorts. No function it reads was touched by this file.

## Decided by default

- `capital_draw` lives on the capital, not the navy: a second payer may want it. It carries no navy word.
- The yard is found before any gold moves.
- No own switch. `navy_enabled` is the switch; `crown_call_share` is the valve.
- Pay's need counts a ship at the capital, as 0331 counts her. Her slice stays there, so the next call is smaller by it. `RP_PAY` proves it cannot climb.

## Owner must see

1. **Joseon gets no ship**, lit, on today's purses. Its realm has fallen to 4 M d. Options, none built: accept it, or let a realm's small ships carry a cheaper class. Nothing here lowers the bar.
2. **Point 4 above:** lit, navy money crosses the realm instantly, unseen on the map.
3. **Still open from 0331:** attacking a navy ship.

## Not verified

- Anything lit on prod. Nothing here has run on prod beyond the read-only `before.sql` and one read of the purses.
- 73 of 75: arithmetic on one reading, not a simulation of the build days.
- The prod cost: projected from PGlite. The self-assert's time on a populated world is not measured either: it reads harbours five times over, and a local world is small.
- Two real sessions on a donor's lock: the busy city and capital are stubbed; PGlite has one session. Real-Postgres behaviour of the file is CI's `disposable-chain`.
- How fast `CROWN_CALL` drains a thin city over weeks. MUG and ENG are the ones to watch, and a city's income was not modelled.
- **Proof 41 is red locally on this PC, with or without this file** (`PROOF 41 FAIL: the merchant did not settle every day`, reproduced through `wanted/proof-0334.mjs`). CI runs it green with this file, 20 of 20. I did not find why it differs here.
- **Proof 01 went red once on CI** at commit 068c8dde (`no voyage in 120 attempts carried a hazard`), then green on the next commit, with no change near it. Its own text calls that 1 in 70 million. I did not find the cause, and 0335 touches no hazard.
- `tests/db.chain.spec.ts` was not run locally: CI's job.

## Rows for the coordinator (not written here)

**docs/OWNER_REQUESTS.md row 285:** `PART BUILT - question 9 answered: migration 0335, a capital draws on its realm, the richest city first, dark behind navy_enabled, PR open, not deployed. OPEN: Joseon cannot pay; attacking a navy ship; W19.`

**docs/WORK_QUEUE.md, one line at the top:** `2026-11-07 **A REALM PAYS FOR ITS NAVY (owner row 285, question 9) - migration 0335, DARK, PR open, NOT deployed, follows 0334:** a capital that cannot pay draws by CROWN_CALL on its realm, richest city first: hull whole or not at all, pay as far as it goes, a wake moves no gold. By arithmetic 73 of 75 hulls, Joseon none. Keep public.crown_call when the off arm of crown_aid dies. Dev-log docs/dev-log/2026-11-07-a-realm-pays.md.`

## PROD CHECKS

- Before deploy: `npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/realm-pays/before.sql`. Every `times` 1, `new_fns` 0, `navy_on` false, `navy_rows` 0, `probe_codes` 0, `call_kind` moved, head the number before 0335.
- After deploy: `scripts/ops/harness/realm-pays/after.sql`. Head 0335, `navy_on` false, `navy_rows` 0, `navy_flows` 0, `crown_call_cut` true, three functions `s`, `v`, `s`. `realms` gives each country's `hull` for the table above.
- `bash scripts/ops/health.sh`.

## Rollback

Forward, owner only: `navy_enabled` false, the whole navy. Gold already moved stays where it went.
