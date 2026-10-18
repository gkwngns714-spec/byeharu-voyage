# 2026-10-18 — 0177: COMMAND DESK D7, the books add up — the Profit face — `osn-desk-d7`

`docs/COMMAND_DESK.md` §3.8, §7.5, §10 row D7. **Not deployed.** The number 0177 is provisional: prod head was 0176
when written.

## Server — `world.books(days)`

The read is registered for signed-in players only. It returns the caller's ledger — the record every coin moves
through — over the last `days` game days (default 7, held to 1..30), newest first:

- **Per day:** each ledger kind summed under its one player word. The words are mapped once, in the function:
  Sold · Bought · Supplies · Wages · Repairs · Profit tax · Invested · Dividends · Hired · Tuition · Donations · Tows.
  Any other kind keeps its own name, so nothing is dropped.
- **Nets:** each day's net is the sum of its lines. The head carries today's net and the window's.
- **Derived per read:** nothing is stored, under the 0014 rule.
- **Starting money is capital, not profit:** FOUNDING is left out. The first local drive read "+8,000" for a new
  company's first day.
- **Per fleet:** not here. The ledger names no fleet; `world.fleet_trades` has the per-fleet laps.
- **Cost on prod** (read-only, the busiest ledger — a merchant with 238 rows across 8 game days): 26 ms.

**Proof (own probe company, rolled back):**
- a new company reads 0 today;
- a sale (+500), a purchase (−200) and wages (−30) through `public.credit` move today's net by exactly the purse's
  change (+270), each under its word;
- every net is the sum of its lines;
- the window is held to 1..30;
- the registry grows by one and reverses to its pre-image; the walls hold.

**Read-only on prod:** the registry hunk occurs exactly once (head 0176), and `world.books` does not exist yet.

## Client — the Profit face

The desk's faces are now Markets · Plans · City · Invest · **Profit**: the five COMMAND_DESK D1 named.

- **Head:** Today (a hero figure, green or red) and the 7 days.
- **Seven bars,** one a game day, up green for a gain and down red for a loss from the one zero line.
- **The books, day by day:** "Today", "1 day ago", and so on, each day's net beside its heading and its lines under
  their words.

**Also fixed:** `tests/duplication.spec` caught D6's holding row as a near-copy of the good page's row recipe. The
Invest holdings now use the `Row` primitive.

## Verify (once)

- Build on the cached prefix (168 restored, 0177 applied). `tsc -b` and `eslint .` are clean.
- `rpc.books` (new) and `rpc.surface`: 31 passed.
- Against `localhost:4260`: `desk.city.spec` (now with Invest and Profit) and `desk.layout`: 7 passed.
- After the FOUNDING change: `rpc.books` 1 passed and `desk.city` 3 passed.
- `duplication`, `words`, `verbHomes`, `sections` and `rpc.holdings`: 24 passed.
- Shots: `docs/dev-log/2026-10-18-command-desk-d7/` — Profit after one buy on the City face, and Invest, each at
  1440 and 390.
