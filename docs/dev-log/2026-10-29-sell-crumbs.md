# 2026-10-29: 0273, a sale is the whole stack

Follows 0272 (`docs/dev-log/2026-10-29-crew-short.md`). 0272's cut-loss writes `SELL <good> ALL` for every good of
the stuck merchants' holds — and every SELL is skipped `E_NO_CARGO`, so the loop it was built to close stays open.
0273 is the one change that lets the SELL execute. Nothing else moves.

**STATUS: BUILT AND PROVED ON THE LOCAL CHAIN** (`osn-sell-crumbs`; PR open, not deployed). The chain applies 0273
after 0272 and prints the self-assert receipt below; `proof.mjs standing` and `proof.mjs merchant` are green. The prod
claims are read-only reads of 2026-10-29 (head 0272); the claims about 0273's own effect are the self-assert's, run on
the chain's world.

## The root, from prod (read-only, head 0272)

Two merchants have been stuck for ever, and the bug is fleet-wide, not two routes.

| | route 1b52a58e-1b69-4043-8aac-4744c6e26948 | route 63ade18d-df43-493d-9cd1-5f655f13c92f |
|---|---|---|
| fleet | a5b3042d-…, **DOCKED at TRP** (70dec312-…) | c62c3898-…, **DOCKED at BRI** (e453e54b-…) |
| hull | 1 × carlat, crew **10 / 12** | 1 × carlat, crew **11 / 12** |
| purse | **0 d.** | **0 d.** |
| hire the tail asks | **40 d.** | **20 d.** |
| hold, all sub-ton | coral .02, camels .20, falconet .47, gunpowder .42, marble .93, verdigris .81, whale-oil .93 t | cannon .08, falconet .24, gunpowder .55, henna .50, honey .50, majolica .96, marble .78, sassafras-root .09, sealskins .85, tuna .29, whale-oil .78 t |
| hold at the quay's bid | **197 d.** | **269 d.** |
| `npc_crew_blocked` | TRUE (read 2026-10-29) | TRUE (read 2026-10-29) |

Fleet-wide: **62,600 skipped SELL orders with `E_NO_CARGO` in 6 h across 828 NPC fleets.** Their routes carry the
normal "sell everything" line — `public.standing_route_lines`: kind `SELL`, `good_id NULL`, `qty NULL`,
`at_profit TRUE` — which `cmd.standing_route_lines` expands to one `SELL <good> ALL AT >= <basis>` per good aboard
(0092:431-448). Every stack is sub-ton (0.08-0.98 t), so `floor()` refuses each one.

The chain, one refusal per step (all verified in the read):

1. `world.quote` (STABLE) prices every stack fine at its **true** quantity — Tripoli's hold totals 197 d. at the bid,
   Bridgetown's 269 d. — because it steps in `trade_step_tuns` chunks and its last chunk carries the fraction.
2. `cmd.resolve_qty` (0007:296-325, **never re-cut since**) returns `floor(v_max)` for `qty_mode` ALL/HALF/PCT on
   BOTH sides. `v_max` is `public.fleet_cargo_qty` — the stack's true tonnage, e.g. 0.93 — and `floor(0.93) = 0`.
3. `cmd.do_sell` (0022:799-803): `v_qty := least(cmd.resolve_qty(...), v_have)` is 0, and `v_have <= 0 or v_qty <= 0`
   raises `E_NO_CARGO`.
4. So 0272's cut-loss SELLs are written `skipped E_NO_CARGO` by `cmd.advance`'s route rule (0092 hunk B), the HIRE is
   skipped `E_INSUFFICIENT_FUNDS`, the SAIL fails `E_CREW_SHORT` — every hour, for ever.

**How the crumbs form**: `fleet_load` stows whole tuns only (0007/0017/0081: `floor(free / bulk)`), so every sub-ton
stack is a REMNANT — a sale that left a fraction (e.g. `SELL ALL` of 3.4 t sold `floor(3.4) = 3` and stranded 0.4),
or a store/trim that took a slice. The stranded fraction is then unsellable for ever: the next `SELL ALL` floors it
to 0. The hold fills with crumbs and the merchant can never raise a ducat from it.

## The live body (read-only, head 0272)

`public.cmd.resolve_qty(uuid,text,text,jsonb)`: md5 **`999e9f6baa9083cfd29e4920fed00886`**, `provolatile 's'`,
`security definer`, `proconfig {"search_path=public, pg_temp"}`. Its tail is exactly:

```sql
  return case coalesce(p_args->>'qty_mode', 'ALL')
           when 'ALL'  then floor(v_max)
           when 'HALF' then floor(v_max / 2)
           when 'PCT'  then floor(v_max * (p_args->>'qty_pct')::numeric / 100)
           else floor(v_max)
         end;
```

The migration's two hunks are sliced from this body (declarations + the return case), each asserted to occur exactly
once and to reverse to the pre-image, and the pre-image tail is asserted to be prod's own.

## What 0273 does

**Re-cut `public.cmd.resolve_qty` ONLY.** The `p_args ? 'qty'` early return and the buy/sell `v_max` selection stand
where 0007 put them; the mode now computes one quantity on the RAW `v_max` and the whole-tun rounding applies to the
**buy side alone**:

```sql
  v_mode := coalesce(p_args->>'qty_mode', 'ALL');
  v_qty  := case v_mode
              when 'HALF' then v_max / 2
              when 'PCT'  then v_max * (p_args->>'qty_pct')::numeric / 100
              else v_max
            end;
  return case when p_side = 'sell' then v_qty else floor(v_qty) end;
```

A SALE is the exact tonnage she carries; a PURCHASE stays in whole tuns exactly as today. ACL, volatility, definer
and config are asserted unmoved; no other function, knob, switch, grant or client entry point moves. 0272's
`npc_leg_lines` / `npc_crew_blocked` are untouched — the cut-loss lines they write now execute.

## The arithmetic, proven not assumed

The self-assert runs old and new side by side over the grid
`v_max ∈ {0.02, 0.465, 0.93, 1, 1.5, 2, 3, 3.4, 7.9}` × `{ALL, HALF, PCT 30, PCT 75}` — 36 points:

- **A BUY is identical for every `v_max` and every mode.** Both bodies compute the same expression of the RAW
  `v_max` (`v_max`, `v_max / 2`, `v_max × pct / 100`) and floor once at the end. Proved on the grid, in situ on the
  planted fleet (`resolve_qty` old = new for ALL/HALF/PCT), and row-by-row (`do_buy` old vs new digests identical:
  purse, cargo, port stock, ledger rows, events).
- **A SELL is identical exactly when its resolved quantity is a whole tun** — every `ALL` of a whole-tun stack, and
  every HALF/PCT whose product comes out whole. Proved on the grid (`old = new ⇔ new` is whole) and row-by-row
  (`SELL ALL` of a whole 4 t: identical digests).
- **Where they differ, the new body is the fix**: `SELL ALL` of 0.93 t — old `floor(0.93) = 0` → `E_NO_CARGO`, new
  **0.93**; `SELL ALL` of 3.4 t — old **3** (stranding a 0.4 t crumb that is then unsellable for ever), new **3.4**;
  `SELL HALF` of 3 t — old **1**, new **1.5** (a sale is exact; only a purchase rounds). `SELL PCT 30` of 0.93 — old
  0, new **0.279**.
- The lemmas hold throughout: `floor(v / 2) = floor(floor(v) / 2)` on every grid point, and the PCT product keeps
  its operand order (`v_max × pct / 100` of the RAW `v_max`, never a pre-floored copy).

Said plainly: the brief's phrase "identical for every sell stack ≥ 1 tun" holds only for whole-tun stacks in ALL mode
(and whole products); HALF of a 3 t stack now sells 1.5, not 1. The brief's own fix code is followed exactly — that
is what the code does — and the self-assert proves the truth table rather than the slogan.

## The probes (all rolled back; the self-assert counts only its own rows)

On the chain's sample merchant (one hull, a harbour stop that is not the lap's first — 0272's sample shape), each
case re-plants her state and rolls back whole:

- **(a) SELL ALL of 0.93 t** — OLD raises `E_NO_CARGO`; NEW sells **0.93**, credits the quote's total, the stack
  empties, the port stock is restored (+0.93).
- **(b) SELL HALF of 0.93** — OLD `E_NO_CARGO`; NEW sells **0.465**, 0.465 stays aboard, stock +0.465.
- **(c) SELL PCT 30 of 0.93** — OLD `E_NO_CARGO`; NEW sells **0.279**, 0.651 stays aboard, stock +0.279.
- **(d) SELL ALL of 3.4 t** — OLD sells **3** and strands a **0.4** t crumb (the crumb generator, seen); NEW sells
  **3.4**, the stack empties, stock +3.4. The rows differ — asserted.
- **(d′) SELL ALL of a whole 4 t** — OLD and NEW identical rows, 4 sold, the stack empties.
- **(f) SELL ALL with an empty hold** — `E_NO_CARGO` on both bodies.
- **(e) BUY ALL / HALF / PCT 30** — `cmd.resolve_qty` answers the same value on both bodies (in situ), and the whole
  `do_buy` leaves identical rows (purse, cargo, port stock, ledger, events).
- **(g) THE NORMAL LINE through the real queue** — prod's own `standing_route_lines` row (kind SELL, `good_id` NULL,
  `qty` NULL, `at_profit` TRUE) over a sub-ton hold, run through `cmd.advance`'s queue-dry refill:
  `cmd.standing_route_lines` render → `cmd.parse` → `cmd.enqueue` → `cmd.advance`. OLD: every SELL `skipped
  E_NO_CARGO`, no SELL credit, the hold intact, she sails with the crumbs (prod's 62,600 in miniature). NEW: each
  SELL executes for the **exact tonnage**, the ledger is credited the quote's totals, the stacks empty, the port
  stock restored; then she sails.
- **(h) THE RULE THAT MUST NOT MOVE** — the same line with the bid BELOW the basis (`at_profit` floor): on a sub-ton
  hold OLD refuses `E_NO_CARGO` (never reaches the price) and NEW refuses `E_PRICE_LIMIT` (the whole stack would
  sell, the floor stops it) — nothing is sold, the order is `skipped`, the hold intact; on a whole 2 t stack both
  bodies refuse `E_PRICE_LIMIT` and leave **identical rows**. `at_profit` semantics are unchanged.
- **THE SEAM** (never ship half a slice): the same merchant, docked below complement, purse 0, a sub-ton hold
  covering the hire at the bid (dearest-per-tun stacks of 0.93 t, at least two, as prod's holds carry), a failed
  `SAIL TO …` refused `E_CREW_SHORT` — her whole step (`public.npc_tend_route`: the clear, 0272's cut-loss, the
  advance), OLD vs NEW. **OLD reproduces the loop**: every cut-loss SELL `skipped E_NO_CARGO`, the HIRE `skipped
  E_INSUFFICIENT_FUNDS`, the SAIL `failed E_CREW_SHORT`, her docked, purse 0. **NEW closes it**: the cut-loss SELLs
  execute at the bid, the HIRE is paid, the SAIL departs, the crew is restored, the purse holds the sale's remainder
  (≥ 0) and reconciles with the ledger. The control (old against old) is identical.

## The receipt (verbatim)

```
0273 self-assert ok: A SALE IS THE WHOLE STACK. cmd.resolve_qty reverses to its pre-image hunk by hunk (md5 999e9f6baa9083cfd29e4920fed00886, prod's own; its tail pinned), ACL / volatility / definer / config unmoved, every other function in the four schemas unmoved (md5), no function minted, the quay takers and the client entry points unmoved. The arithmetic grid (44 points): a buy is identical for every v_max and every mode; a sell is identical exactly when its resolved quantity is a whole tun — 0.93 sells 0.93 (today 0), 3.4 sells 3.4 (today 3, stranding a crumb), HALF of 3 sells 1.5 (today 1); floor(v/2) = floor(floor(v)/2) throughout. Direct probes on merchant 84f76e31-9166-42b5-a93b-55377d2d7372: SELL ALL / HALF / PCT 30 of 0.93 t (old E_NO_CARGO, new sells the exact tonnage, the stack empties, the stock restored, the purse credited the quote's total), ALL of 3.4 (old 3 + a 0.4 crumb, new 3.4), ALL of a whole 4 t (identical rows), an empty hold (E_NO_CARGO both), BUY ALL / HALF / PCT (resolve equal, identical rows). The queue (prod's normal line, kind SELL good_id null qty null at_profit true, rendered → parsed → enqueued → advanced): old skips every SELL E_NO_CARGO and credits nothing; new executes each SELL for the exact tonnage and credits the quote's totals; a bid below the basis still refuses (sub-ton: old E_NO_CARGO, new E_PRICE_LIMIT, the hold intact; a whole 2 t: E_PRICE_LIMIT and identical rows). The seam, her step OLD vs NEW on merchant 84f76e31-9166-42b5-a93b-55377d2d7372 (20 d. hire, a sub-ton hold worth 1799 d. at the bid in 2 stacks): OLD leaves every cut-loss SELL skipped E_NO_CARGO, the HIRE skipped E_INSUFFICIENT_FUNDS and the SAIL refused E_CREW_SHORT with her docked; NEW sells at the bid, pays the HIRE, sails, the crew restored, the purse 367 d. and the ledger reconciled; the control identical. Rolled back.
```

## Local gates

- The cached chain gate (`node scripts/db/proof.mjs …`): `chain: 262 migration(s) — 261 restored from the prefix
  cache (preamble-p0261-515581ffabcac2a2d2200326), 1 applied here — 262 with a self-assert receipt (268 receipt
  line(s)); chain key a3d3106f4d9732ad` — 0273 applied after 0272, its self-assert above. The world-guard is green
  (the applied world EQUALS data/*.json).
- `node scripts/db/proof.mjs standing` — `PROOFS PASSED: 1 file(s), 5/5 PASS markers seen`
  (11_standing_route.sql, 0.4 s: ROUTE_CLIENT_PATH, ROUTE_AFK_LAPS, ROUTE_BOOKS_BALANCE, ROUTE_DARK,
  ROUTE_0096_DOOR).
- `node scripts/db/proof.mjs merchant` — `PROOFS PASSED: 1 file(s), 6/6 PASS markers seen`
  (12_merchant_companies.sql, 48.2 s: MERCHANT_CLIENT_WALL, MERCHANT_AFK_LAP, MERCHANT_BOOKS, MERCHANT_RANK,
  MERCHANT_EARNINGS, MERCHANT_DARK).

Note: the from-zero `npm run db:apply` was attempted first and died at frozen 0133's wall-clock read-timing assert
("regressed dark: 1032.0 ms → 1542.0 ms") while another agent's playwright suite shared the CPU — a load flake in a
frozen file 140 files before 0273, not a schema failure; the cached gate above is the repo's own lean gate and does
not re-run the restored prefix's timing asserts.

## PROD CHECKS (before the push; read-only)

- The live `cmd.resolve_qty` body is the one the hunks were cut against: md5
  **`999e9f6baa9083cfd29e4920fed00886`**, stable, security definer, `search_path public, pg_temp` (read
  2026-10-29, head 0272).
- The two stuck routes still read `npc_crew_blocked` TRUE: a5b3042d-… at TRP (short 2, hire 40 d., purse 0) and
  c62c3898-… at BRI (short 1, hire 20 d., purse 0).
- Do not push while a re-cut PR is open against another body.

## The after-check (after the deploy)

- **Routes 1b52a58e-… and 63ade18d-…**: the cut-loss SELLs execute (orders `SELL done`, no more `SELL skipped
  E_NO_CARGO` for them), the HIRE is paid (`HIRE done`), the SAIL departs (`SAIL done`, fleet SAILING), the hulls
  come back to `crew_required` (shortfall 0), the purses leave 0 (they hold the sale's remainder, ≥ 0).
- **World-wide**: the skipped-SELL `E_NO_CARGO` count falls from the 62,600 / 6 h measured before the fix (the
  hourly `E_NO_CARGO` skip rate over all NPC fleets); the two routes' hourly `NPC_CLEARED` falls to none.

## Forward rollback

A new migration restoring `cmd.resolve_qty` from the pre-image. The pre-image is `0007:296-325` in this repo (frozen)
and prod's live body md5 `999e9f6b…`; the migration's `old_bodies_0273` carries the exact text it captured at apply
time, which is asserted to be prod's own tail. The restoring migration re-cuts the two hunks of 0273 in reverse —
`create or replace function cmd.resolve_qty` from the captured pre-image, hunks asserted as before, plus 0272-style
guard and receipts.

## Not proven / said plainly

- A merchant with NEITHER coin NOR saleable cargo is still not helped (0272's own stated limit) — the cut-loss has
  nothing to sell; needs its own owner decision.
- A multi-hull fleet: 0272's cut-loss sells whole stacks and the HIRE restores the most-room hull first; a hire that
  leaves another hull short re-plans on the next clear and sells again (0272's loop, now with working SELLs).
- Selling at the bid forsakes the profit an at-profit SELL would have taken — 0272's stated trade, unchanged.
