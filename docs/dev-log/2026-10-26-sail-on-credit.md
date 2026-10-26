# 2026-10-26 — Sail on credit: costs never block a voyage; sales pay the debt; capitals help players too (owner row 230, `osn-sail-on-credit`)

> *"right now i cannot move to a location because i have no money for supplies and wages. These fees will have to be
> paid when things are sold. If sold and don't have money due to these fees, you will receive donation from your
> capital."* (owner, 2026-10-26, docs/OWNER_REQUESTS.md row 230)

- `supabase/migrations/20260818000241_she_sails_on_credit.sql` (prod head 0240 + 1; deploys first, other in-flight
  slices renumber after it).
- Client: the purse bar, the Trade card, the map's send row, the ledger's gift line (EN + KO).

## What stopped him (prod, read-only, ~08:20 UTC)

His company: **purse 0**, Gaivota **docked at Banten (BAN)**, **45,085 of cargo at cost**, **267 owed to Banten** in
dock fees, 6.4 owed in wages, no port time. Every SAIL buys its own stores (0225: `cmd.do_sail` →
`cmd.do_provision`), and with a purse of 0 that purchase refused **E_INSUFFICIENT_FUNDS "the purse will not cover the
stores"**, so no SAIL could leave. Merchants hit the same refusal (two failed merchant SAILs at 08:07 UTC).

**Wages never stopped a SAIL.** Since 0128 a sea-day's wage is owed (`fleet_wages`) and paid only out of a sale's
profit (`pay_wages`), the owner's own rule ("pay wages only when a profit is made"). That ledger is left as it is. Folding
it into the new debts would change who gets paid and when, and it already never refuses.

## What changes (lit only = while the economy is closed, as prod is now)

| | Before | Now |
|---|---|---|
| A SAIL's own stores, purse short | refused E_INSUFFICIENT_FUNDS | the purse pays what it can; the rest is **owed to that city** (kind PROVISION) |
| Dock fee, purse short | owed to that harbour (0237), paid only from a sale **there** | owed the same way, paid from **any** sale |
| A sale | paid this harbour's dock fee debt | pays **every** debt: this harbour's first, then the oldest, each to the city it is owed to |
| Still short after selling | players got nothing; merchants' hourly pass only | a **player** whose worth (purse + cargo at cost − debts) is under 20 % of 8,000 gets **8,000 from her capital** (cooldown 24 h, 3 a week); asked after every sale of hers and every harbour she makes |
| After any capital gift | — | the gift pays what she owes first |
| A PROVISION she orders herself | refuses when short | unchanged (decided by default: credit is for the voyage) |
| Economy open | — | every path as before |

- **One debt ledger.** `port_fee_debts` (0237) gains `kind` (PORT_FEE, PROVISION) in its key. It is not renamed,
  because only its two readers use it and both are re-cut here. One writer of owing (`public.debt_owe`) and one payer
  (`public.port_fee_collect`, re-cut whole).
- **The city is owed and paid later.** No city fronts the money. An owed ducat is not money: nothing is created, and the
  city is paid when she pays.
- **Merchants obey the same rules.** Their SAILs run the same `cmd.do_sail`, so their stores go on credit too, and their
  hourly gift now pays their debts first. Their hourly pass still covers merchants only. Players are helped only when
  asked for one at a time, so no idle account is paid.
- **Reads:** `world.player` gains `owed` (when > 0) and `on_credit` (true while lit). `cmd.do_sail` (so the SAIL
  preview's estimate) gains `on_credit`. `cmd.do_sell` gains `debt_paid` and `gift`. While the economy is open and
  nothing is owed, no read changes.
- **Client:**
  - Purse bar: **"Owed 1,240" / "빚 1,240"** beside the purse.
  - **"Gift +8,000" / "지원금 +8,000"** for two minutes after a capital gift.
  - Trade card: **"On credit −1,240" / "외상 −1,240"** under Supplies. "No money" now counts only the cargo she must pay
    for.
  - Map send row: **"On credit −1,240" / "외상 −1,240"** from the SAIL's dry run.
  - Ledger: **"Gift from Lisbon: 8,000." / "리스본 지원금 8,000."**

### Decided by default (the owner may reverse)
- No debt cap.
- A PROVISION order still refuses when the purse is short.
- A player's broke rule counts her cargo and her debts (not just cash, unlike merchants), so a player with a full
  hold is not paid.
- The gift is asked for after every sale of hers and at every harbour she makes (an empty hold could never sell).
- Wages stay in their own ledger, which already never refuses.

## Proof (local)

- Cached-prefix apply: 229 restored, 0241 applied. The self-assert:
  - `0241 self-assert ok: SHE SAILS ON CREDIT. Seven bodies re-cut by sixteen hunks (do_provision, do_sail, do_sell, port_call, port_fee_collect, capital_gift_pass, world.player), each reversed, ACL unmoved; six functions server-only; the debts table keyed (player, port, kind), no client grant; registry unchanged; walls 0. DARK: a broke company's SAIL at Lisbon refused E_INSUFFICIENT_FUNDS as before, no debt, no new key. LIT: the preview and the SAIL passed, her stores (5520) owed to Lisbon; at Funchal her dock fee (50013) owed, no gift with a full hold; world.player owed 55533; the sale paid 804 of it (Funchal first); still short, Lisbon gave 8000 and it paid the debt down to 46729; no second gift; the probe's money summed to 0. Rolled back.`
  - The probe is a Portuguese company at Lisbon with purse 0 and 40 t aboard at a dear cost. Her stores are priced
    ×10,000 inside the probe, so the debt outruns the sale.
  - **Closed:** Σ her ledger (minus founding and probe rows) + Σ the cities' flows the probe wrote = **0**.
  - Self-assert rules kept: only probe rows are read (flows above an in-block mark at this transaction's now(), the
    probe company's own rows). Everything is rolled back, and that is asserted. Nothing is DELETEd from an append-only
    table. No `set role`. No tick is run. No hour of day is read.
- `npx tsc -b` 0, `npx eslint .` 0, `npm run build` 0 (no `.env.local` in the worktree).
- Specs on `vite preview --port 4224` (`localhost`, English locale): `rpc.capitalGift`, `rpc.portDues`,
  `fleet.supplies`, `desk.plantab`, `shell.kstClock`, `trade.loop`. **12 passed.**

## PROD CHECKS (pure SELECTs, one per block; every function called is `s`). Taken on prod 2026-10-26 ~08:30 UTC, head 0240, before deploy.

1. Head.
```sql
select max(version) as head from supabase_migrations.schema_migrations
```
`20260818000240`. After deploy: `20260818000241`.

2. Each of the 16 hunks' OLD text occurs exactly once in the live body. The query is generated from the migration's
   `hunks_0241` rows: `(fn, n, needle)` values, then
   `(length(d) - length(replace(d, needle, ''))) / length(needle)` over
   `replace(pg_get_functiondef(fn::regprocedure), E'\r', '')`.
   **All 16 read 1** (do_provision ×4, do_sail ×3, do_sell ×3, capital_gift_pass ×2, port_call ×2,
   port_fee_collect ×1, world.player ×1).

3. The debts today.
```sql
select count(*) n, coalesce(sum(ducats),0) owed, count(distinct player_id) companies from public.port_fee_debts
```
5 rows, 826 owed, 3 companies (all PORT_FEE; they become kind PORT_FEE by the column default).

4. The key the migration replaces.
```sql
select conname from pg_constraint where conrelid='public.port_fee_debts'::regclass and contype='p'
```
`port_fee_debts_pkey`.

5. The switches and knobs.
```sql
select public.economy_closed() closed, public.city_treasury_on() purses, public.wc_int('starting_ducats') start, public.wc_num('merchant_broke_pct') pct, (select capital_port_code from public.nations where code='PRT') prt_capital
```
closed true, purses true, start 8000, pct 0.2, Portugal's capital LIS.

6. Lisbon's surplus: who pays a Portuguese gift.
```sql
select public.city_surplus(p.id) lis_surplus from public.ports p where p.code='LIS' and p.kind='HARBOUR'
```
−428,370. Lisbon is under its reserve, so a gift is called from Portugal's richest harbour (CROWN_CALL), as 0234 does.

7. The owner's fleet now (player `c85b31cb-8274-4801-999d-6c40f57ddf74`).
```sql
select pl.company_name, pl.ducats, pl.is_npc, n.code nation, n.capital_port_code, (select json_agg(json_build_object('fleet',f.name,'status',f.status,'port',p.code,'ready_at',f.ready_at,'cargo',public.fleet_stock_at_cost(f.id),'owed_wages',(select w.owed from public.fleet_wages w where w.fleet_id=f.id))) from public.fleets f left join public.ports p on p.id=f.port_id where f.player_id=pl.id) fleets, (select json_agg(json_build_object('port',p.code,'d',d.ducats)) from public.port_fee_debts d join public.ports p on p.id=d.port_id where d.player_id=pl.id) debts from public.players pl left join public.nations n on n.id=pl.nation_id where pl.id='c85b31cb-8274-4801-999d-6c40f57ddf74'
```
JOOHOON HA (PRT, capital LIS):
- purse **0**;
- Gaivota **DOCKED at BAN**, cargo **45,085** at cost, 6.4 wages owed, no port time;
- debts **BAN 267**.

**What blocks him:** the stores of any SAIL, which his 0 purse cannot pay (E_INSUFFICIENT_FUNDS).

**After deploy:**
- His SAIL leaves, and its stores are owed to Banten.
- His next sale pays Banten's 267 dock fee, then the stores.
- His worth (≈ 45,085 − debts) is far above 1,600, so no gift is due to him.

8. Merchants' failed orders (the same refusal).
```sql
select o.verb, pl.is_npc, o.error_code, left(o.error_message,80) msg, o.executed_at from public.orders o join public.players pl on pl.id=o.player_id where o.status='failed' order by o.executed_at desc nulls last
```
2 merchant SAILs failed E_INSUFFICIENT_FUNDS "the purse will not cover the stores" at 08:07 UTC.

### After deploy (for the main session)
- Hunk check (2) reads 0 for every OLD text.
- `select count(*) from public.port_fee_debts where kind = 'PROVISION'` grows from 0 as broke fleets sail.
- No new `failed` SAIL with E_INSUFFICIENT_FUNDS.
- New money still 0 (Stats).
- The owner's SAIL from Banten succeeds.

## Rollback (forward)
- Reverse the 16 hunks (each OLD text is in the file verbatim).
- Drop `credit_on`, `debt_owe`, `company_owed`, `player_worth`, `player_gift`, `company_debt_key`.
- Fold PROVISION debts per (player, port) into one row, restore the (player, port) key, and drop `kind`.
