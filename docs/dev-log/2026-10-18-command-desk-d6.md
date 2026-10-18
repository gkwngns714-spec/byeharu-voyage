# 2026-10-18 — 0176: COMMAND DESK D6, what you hold — the Invest face — `osn-desk-d6`

`docs/COMMAND_DESK.md` §3.7, §7.5, §10 row D6. **Not deployed.** The number 0176 is provisional: prod head was 0175
when written.

## Server — `world.holdings()`

The read is registered for signed-in players only. For the caller's company it returns:
- **Rows:** one per (city, work) held — the share register's own row (`public.city_shares`: shares, paid, and owed
  — the coupons the city holds), the work's level, and a share's price there now. The price comes through
  `public.works_share_price`, the leaf `world.town_hall` prints.
- **Totals:** held (Σ paid) and owed (Σ accrued).
- **Dividends collected:** from the ledger (kind DIVIDEND), today and in the last full game day (`world.game_day`).
  The query uses the ledger's `(player_id, created_at)` index over the last real day; prod has 1,125 DIVIDEND rows a
  day in total.
- **Enabled:** whether city purses are on.

**Proof (own probe company, rolled back):**
- an empty company reads empty;
- two planted register rows read back exactly (shares, paid, owed, level, share price);
- held 800, owed 17, and today's dividends 123 — the credited amount;
- Lisbon's rows equal `world.town_hall`'s `you.holdings`;
- the registry grows by one and reverses to its pre-image; the walls hold.

**Read-only on prod:** the registry hunk occurs exactly once (head 0175), and `world.holdings` does not exist yet.

## Client — the Invest face

The desk's faces are now Markets · Plans · City · **Invest**.

- **Your holdings:**
  - three figures: Held · Paid today · Owed to you;
  - one line: *"Yesterday the cities paid you N 🪙. What they owe is paid when a fleet of yours docks there."*;
  - a row per holding: the city's flag and name with its work word, shares, level and a share's price now; what you
    paid on the right, and what is owed.
- **The Town Hall:** the one hall (`live/CityTownHall`), shown for the city pressed or else the city the fleet is
  at. It carries the purse and the day's money lines served since 0172 / 0174 (Grant · Earnings · the crown · Paid
  by its people), its works, Invest, and influence.
- **Work names:** the one map (Docks · Market · Workshops · Inn) moved to `live/workNames.ts`, so the hall and the
  desk print one word.
- **RPC:** `worldHoldings` with its type and wrapper. `rpc.surface`'s pin moved.

## Verify (once)

- Build on the cached prefix (167 restored, 0176 applied). `tsc -b` and `eslint .` are clean.
- `rpc.holdings.spec` (new) and `rpc.surface`: 31 passed.
- Against `localhost:4260`: `desk.city.spec` (now with the Invest face), `map.townhall` and `desk.layout`: 8 passed.
- `verbHomes`, `sections`, `duplication` and `words`: 22 passed.
- Shots: `docs/dev-log/2026-10-18-command-desk-d6/desk-invest-{1440,390}.png`. The local world's purse is dark, so its
  holdings and money lines are empty there; prod prints them.
