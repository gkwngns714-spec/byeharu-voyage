# BANK — one national bank per nation, in the capital city only

**Status: DESIGN (2026-11-05). Nothing here is built. No migration, no code.** Prod head at writing: **0305**.
Slices are numbered by slice name; migration numbers are reserved at build time (next free after whatever is in flight).

**The owner (2026-11-05):** an institution like a bank, where cities can hold cash and be given a mortgage.
Decisions given: **one bank per nation; the bank exists in the capital city only.**
Every "decided by default" below is mine; the owner reverses afterwards.

Standing rules this design keeps: closed economy (no minted gold, `mint_guard` untouched), no switch flipped
without the owner, one place per concept (no second ledger), a city never goes below zero (0122), no forced
hand-in of merchant surplus (0184), the 11-02 direction (look and feel stay as the new page pattern; no density work).

---

## 0. The answer in ten lines

1. **23 banks**, one per row of `public.nations`, seated at `nations.capital_port_code`. No bank anywhere else.
2. A bank is a **pool**: depositors hold *units*; the vault holds cash; loans out are an asset of the pool.
3. **Deposit / withdraw** only while docked at that nation's capital (players), same door for merchants later (off in v1).
4. **Mortgage = a loan to a city of the same nation**, decided by a rule once a day, never by a click. A player cannot borrow in v1.
5. A loan moves existing gold: vault -> city purse. Repayment moves it back, plus interest. **Nothing is minted.**
6. **Interest is the depositors' yield**: the interest collected is shared among units. No interest is ever created.
7. A loss (a city that cannot pay) is written off against the pool: the unit price falls. Nobody is liquidated, no city is seized.
8. A loan is **not investment**: it does not feed `port_treasury.invested`, so it cannot be used to farm restock or max stock.
9. Everything ships **dark**: `bank_enabled` false. Off = today's game, byte for byte.
10. Five slices, each with a red-then-green proof (§8).

---

## 1. Why it fits what is already built

| Existing | What the bank adds |
|---|---|
| Closed economy since 10-26; merchants hand surplus above `npc_invest_above x capital` to city shares | A second, liquid place for surplus gold that earns a yield and is withdrawable |
| City purses x100, capitals x500 (0302, OWNER_GRANT) | Idle cash in capitals can be lent to the nation's poorer cities |
| City population (0304): INVEST / FAMINE / WAR signals, daily POPULATION_TAX | A real trigger and a real repayment source for loans |
| Debt deferred in ECONOMY_LOOP round 3 ("build the purse and investment first") | This is that deferred debt, with rules |

---

## 2. Data (all rows, no code constants)

| Object | Shape |
|---|---|
| `banks` | `(nation_id pk, port_id unique -> the capital, units numeric, vault bigint, created_at)`. 23 rows, created by the first slice from `nations`. `port_id` must equal `nations.capital_port_code`'s port; a trigger refuses any other. |
| `bank_accounts` | `(nation_id, player_id, units numeric, primary key (nation_id, player_id))`. RLS: a player reads only their own rows. |
| `bank_loans` | `(id, nation_id, port_id, principal bigint, outstanding bigint, rate_per_day numeric, term_days int, opened_at, due_at, arrears_days int, state OPEN/PAID/WRITTEN_OFF)`. One OPEN loan per city at a time. |
| `bank_flows` | append-only (trigger refuses UPDATE/DELETE): `(id, nation_id, kind, amount, player_id null, port_id null, loan_id null, at)`. Kinds: `DEPOSIT`, `WITHDRAW`, `LOAN`, `REPAY`, `INTEREST`, `WRITE_OFF`, `SEED`. |

**Unit price** = `(vault + sum(outstanding of OPEN loans)) / units` (1.0 when `units = 0`). A deposit buys `amount / price` units;
a withdrawal sells units at the price. The price rises with interest, falls with a write-off. One reader `public.bank_unit_price(nation)`.

**Cash available to withdraw** = `vault` only (loans out are not cash). A withdrawal larger than the vault is **capped to the vault**
and the rest of the units stay; no run can drain what is lent out. Stated to the player before they confirm.

---

## 3. Deposit and withdraw

- `cmd.bank_deposit(p_amount)` / `cmd.bank_withdraw(p_units)`: refuse `E_NOT_DOCKED` unless the player's fleet is docked at that nation's capital;
  refuse `E_BANK_OFF` while dark; refuse under `bank_min_ducats` (default 1,000, as `invest_min_ducats`).
- Money moves through the **existing** player purse writer (the same door `invest_for` uses), never a new one. The vault changes only in the bank's own
  functions, each writing one `bank_flows` row in the same transaction. The vault balance is the sum of its flows (reconciled, like `treasury_flows`).
- Merchants: **off in v1** (`bank_npc_deposit` false). Their surplus rule is untouched. Slice B6 (later, owner's go) lets a company above `npc_invest_above x capital`
  choose the bank instead of a city share.

---

## 4. Mortgage to a city

**Who:** a harbour of the same nation, including the capital itself is **excluded** (it is the lender's seat; its purse is large already).
**When:** once a day with the other daily settings (00:00 UTC), in its own cron job (`byeharu-voyage:bank`), not inside the beat.

**Underwriting rule (all values are knobs, defaults mine):**

1. The city has no OPEN loan and no loan written off in the last `bank_cooldown_days` (30).
2. **Need:** purse < `bank_low_water_days` (3) x the city's average daily payout over the last 7 days (buys + wants premiums, from `treasury_flows`).
3. **Size:** `min(need_to_reach_target, cap)` where target = `bank_target_days` (7) x average daily payout, and
   `cap = bank_cap_tax_days` (20) x the city's daily POPULATION_TAX. A city that cannot service a loan from its tax is not lent more than it can repay.
4. **Free cash:** the loan never takes the vault below `bank_reserve_pct` (20 %) of vault + loans. If the vault is short, the day's loans are served
   smallest-need-first until the reserve line; the rest wait a day. No queue is stored.
5. **Terms:** simple interest `bank_rate_per_day` (0.30 %/day), `bank_term_days` (30). Installment per day = principal / term + interest on the outstanding.

**Collection:** each day, after lending, the same job takes the installment from the city purse via `treasury_post` (moved, never minted).
If the purse holds less, it takes what it can (never below zero) and `arrears_days` += 1. After `bank_default_days` (10) in arrears the loan is
`WRITTEN_OFF`: outstanding leaves the pool's assets (the unit price falls), the city is blocked for the cooldown, and an event is emitted.
No seizure of stock, works or shares.

**Why this cannot mint:** a loan = vault -> city purse; an installment = city purse -> vault; interest is part of the installment, so it is
already someone's gold. Σ(players + cities + merchants + vaults) is constant across every bank operation. That is the proof, §8.

---

## 5. Where it lives in the game (client)

- The **capital's** City page gains a seventh building, **Bank** (the six-building grid stays for every other city; a non-capital shows no bank and a one-line "Banks are in capital cities").
- The Bank face (page pattern, 24 px figures, one main | side page): your balance and units, the unit price, deposit / withdraw, the bank's vault, loans out,
  and the list of cities with a loan (principal, outstanding, days late).
- The **non-capital** City hall shows its loan (if any): principal, outstanding, next installment, days late. Words: plain and short, EN + KO in the dictionary.
- Stats: a Bank row per nation (vault, loans out, unit price) and the flow kinds in the money log.

---

## 6. Knobs (rows in `world_config`; all added by B1, all inert while `bank_enabled` is false)

| Key | Default | Meaning |
|---|---|---|
| `bank_enabled` | false | the switch (owner only) |
| `bank_min_ducats` | 1,000 | smallest deposit |
| `bank_rate_per_day` | 0.003 | simple interest on outstanding |
| `bank_term_days` | 30 | loan length |
| `bank_reserve_pct` | 0.20 | the vault never lends below this share |
| `bank_low_water_days` / `bank_target_days` | 3 / 7 | when a city qualifies / how far it is topped up |
| `bank_cap_tax_days` | 20 | max loan = this many days of the city's POPULATION_TAX |
| `bank_default_days` | 10 | days in arrears before write-off |
| `bank_cooldown_days` | 30 | wait after a loan closes or is written off |
| `bank_seed_per_nation` | 0 | one-time vault seed (§7) |
| `bank_npc_deposit` | false | merchants may use the bank (B6) |

---

## 7. Opening the vault (owner decision)

A bank opens with an empty vault and `units = 0`; lending starts only once depositors have brought gold. Two choices:

- **A (default):** empty. Slow start, nothing moved by us.
- **B:** each capital lends its own purse once: `treasury_post(capital, 'BANK_SEED', -x)` into the vault, `x = bank_seed_per_nation`; the capital owns those units.
  Gold is moved, not minted. The capital purses are 500x, so this is the fastest way to a working bank. Needs the owner's number.

---

## 8. Slices and proofs (strict order, each its own PR; deploy with `~/bin/bv-deploy.sh`)

| Slice | Content | Proof (red first) |
|---|---|---|
| **B1** `a_bank_in_every_capital` | `banks` (23 rows), `bank_accounts`, `bank_loans`, `bank_flows`, knobs, `bank_unit_price`, append-only trigger, `bank_enabled` false, RLS | 23 rows, each `port_id` = its nation's capital; non-capital insert refused; flows UPDATE/DELETE refused; every reader dark = empty |
| **B2** `deposit_and_withdraw` | the two commands, the reconcile of vault = Σ flows | in-block lit: deposit then withdraw returns the same gold at price 1.0; not docked at the capital -> `E_NOT_DOCKED`; Σ supply unchanged; vault cap on withdraw |
| **B3** `the_bank_lends_and_collects` | `byeharu-voyage:bank` daily job: underwrite, lend, collect, write off; `treasury_post` kinds BANK_LOAN / BANK_REPAY (moved) | probe city below low water gets exactly the §4 amount; installment never overdraws a purse; 10 days in arrears -> write-off, unit price falls by outstanding / units; reserve line held; Σ supply constant to the ducat |
| **B4** `the_bank_you_can_see` | Bank building + face, loan lines in the City hall, Stats row, flow words as **moved** in `stats_flow_words`, dict EN + KO | red-then-green `tests/bank.design.spec.ts` (page pattern); no page scroll 390x844 / 320x568; money log ratio stays 1.0000 |
| **B5** `bank_after_check` | docs, dev-log with prod checks, 24 h after-check of the cron job (runs, failures, seconds) | `scripts/ops/health.sh` gains the `byeharu-voyage:bank` line |
| B6 (later, owner go) | merchants deposit | paired run: merchant purses and lap results unchanged except the sink |

**Prod checks before each deploy:** pure SELECTs only (check volatility); read `treasury_post` and the player-purse writer bodies on prod before writing B2/B3,
since this doc names them from the earlier designs and has not re-read their current bodies.
**Cost rule:** the daily job touches at most 245 cities; measure its per-call cost on prod-like I/O before enabling (the 0301 lesson: nothing slow inside the beat).

---

## 9. Not in v1

Player loans; interest on deposits other than the pool share; seizure or liquidation; bank-to-bank lending; foreign deposits (a player banks only at the capital of the nation where they dock);
any change to restock, max stock, prices or the economy switches.

## 10. Open questions for the owner

1. Vault opening: **A** empty or **B** seeded from the capital (and how much)?
2. Rate and term defaults (0.30 %/day, 30 days) fine, or lower?
3. Should a city's loan ever be forgiven by a war or famine event, or always written off by the arrears rule only?
4. Capital cities themselves: never borrow (my default), or may a capital borrow from another nation's bank (no, in v1)?
