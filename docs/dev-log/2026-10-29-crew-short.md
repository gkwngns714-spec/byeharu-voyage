# 2026-10-29: 0272, a crew shortage is paid from the hold

Follows `prodcheck-2026-10-29/crew-short-report.md` (the read-only prod investigation of 2026-10-29 ~06:35-07:00 UTC,
head 0269). That report named the root of the hourly `E_CREW_SHORT` loop; 0272 is the one change it asked for. Nothing
else moves.

**STATUS: BUILT AND PROVED ON THE LOCAL CHAIN** (`osn-crew-short`; PR open, not deployed). The chain applies 0272
after 0270 and 0271 and prints the self-assert receipt below; `proof.mjs standing` and `proof.mjs merchant` are green.
The prod claims are the report's (read-only, head 0269); the claims about 0272's own effect are the self-assert's, run
on the chain's world.

## The root, from prod (read-only; the report's own reads, head 0269)

| | route 1b52a58e-1b69-4043-8aac-4744c6e26948 | route 63ade18d-df43-493d-9cd1-5f655f13c92f |
|---|---|---|
| house | Compania de Palermo (b8250461-…) | Compania de Concepcion (6e6ff343-…) |
| purse | **0 d.** | **0 d.** |
| fleet | a5b3042d-…, **DOCKED at TRP** | c62c3898-…, **DOCKED at BRI** |
| shortfall | **2** (carlat, 10 / required 12) | **1** (carlat, 11 / required 12) |
| lap | **845**, open since 10-28 05:41 | **537** |
| clears | **19** in the window (7 before it), one an hour | **7**, one an hour |
| last failed order | `SAIL TO CAG`, **E_CREW_SHORT** | `SAIL TO TAN`, **E_CREW_SHORT** |
| hire the tail asks | **40 d.** | **20 d.** |
| hold at the quay's bid | **201 d.** | **273 d.** |

The loop, each step its own rule (all verified in the report):

1. The stop tail writes `HIRE <shortfall>` then `SAIL TO <next>` — 0096:1114-1143, and it does fire.
2. `cmd.do_hire` prices the count and refuses `E_INSUFFICIENT_FUNDS` at purse < cost — 0007:675-678.
3. `cmd.advance`'s route rule writes the refused HIRE `skipped` and runs the SAIL behind it — 0092:743-748 — and the
   SAIL fails `E_CREW_SHORT` — 0050:354-362.
4. The halt law clears her hourly; from the third clear of a lap every clear re-plans her (0150's rule, now
   `public.npc_clear_due`, 0270) — but a plan writes lines, never crew, and it sells only at a profit.
5. So the same refused HIRE and the same refused SAIL repeat for ever. `n` is a rolling count (6 h retention), so the
   loop has no end.

The money to sail is already aboard: 5x and 13x the hire, at the quay's own bid.

## What 0272 does

1. **`public.npc_crew_blocked(fleet, from)`** — minted here, beside `public.npc_casks_blocked` (0150:172-209). True
   when: she lies **DOCKED at `from`**; `public.fleet_crew_shortfall(fleet) > 0`; the quay has hands at all
   (`ports.crew_pool > 0`, so `cmd.do_hire` would not refuse `E_CREW_POOL`) — i.e. a hire would restore her; her purse
   is **below** what that hire costs; and her hold, at this quay's own bid (`world.quote …, 'sell'`), is worth **at
   least** that. Stable, security definer, server-only (no client role, no entry point). One definition, one reader.
2. **`public.npc_leg_lines` — the cut-loss for crew**, two hunks: three declarations, and a block seated **after**
   0150's cut-loss for room and **before** the leg's answer. When `npc_crew_blocked` is true it writes
   `SELL <good> ALL` at the quay's bid (`at_profit = false`, no `AT` — 0142's own cut-loss form) for whole stacks,
   **largest bid value first, until the hire's cost is covered**. Partial coverage is not attempted: a stack is never
   split. The stop tail's `HIRE n` then finds the money and the SAIL behind it passes.
3. **`public.npc_clear_due` — one clause**: `plan` gains `or (p_verb = 'SAIL' and p_error_code = 'E_CREW_SHORT')`
   beside 0150's `E_ENDURANCE` clause, so the answer arrives on the **first clear**, not after the count reaches three.
   Its `COMMENT` is re-issued so the catalogue reads the whole rule.

**The hire price is not restated.** `public.crew_hire_cost(fleet, n)` — minted in 0154 (file
`20260818000154_a_skill_is_paid_where_the_game_charges.sql:331-369`), revoked from every client role — is THE one
reading of what hiring `n` hands costs a fleet where she lies: the pool split, the `hire_crew_rate`, the
`crew_urgent_multiplier`, the merchants' `npc_crew_pool_floor` and the Etiquette discount. Its own comment says
"cmd.do_hire charges it and draws the pool by its split". Both the coverage test and the cut-loss ask it. No rate,
floor, multiplier or discount is spelled in 0272, so the plan and the refused HIRE cannot disagree.

**What does not move:** the halt law, the clear (one `NPC_CLEARED`, `cmd.clear_for`, `cmd.advance` — same calls, same
order), advance's skipped-HIRE handling, `cmd.do_hire`, `public.crew_hire_cost`, the stop tail and its `HIRE` line,
`cmd.standing_route_lines`, the quay, `crew_pct` / `crew_terms`, every knob, every ACL, every client entry point.
The self-assert proves it: every hunk reverses, ACL/volatility/definer/config unmoved, and **every function in the four
schemas except the two re-cut** keeps the same md5 (one md5 over the lot — `npc_plan`, `world.quote`,
`cmd.standing_route_tail`, `cmd.do_hire` and the rest included by construction), exactly one function minted, the quay
takers the same set, the client entry points the same count.

## The self-assert's probes (all rolled back; only the probe's own rows)

- **(a) The hunks and the walls.** As above: 2 hunks in `npc_clear_due`, 2 in `npc_leg_lines`, each once, each
  reversing to its pre-image; no function moved; `public.npc_crew_blocked` is the only one minted; no client role may
  execute it; no new quay taker.
- **(b) The fix's own shape,** on the new bodies: `E_CREW_SHORT` appears in the plan rule exactly once; the cut-loss
  asks `npc_crew_blocked` and `crew_hire_cost` once each; it stands after `npc_casks_blocked` and before the return.
- **(c) Probe A, the rule** (7 planted cases on a real route, rolled back): a SAIL refused **E_CREW_SHORT plans on the
  first clear**; E_ENDURANCE too; the third clear too (seeded by two planted `NPC_CLEARED` events, `n` read back = 3);
  an ordinary refusal (`E_NO_CARGO`, `SELL / E_INSUFFICIENT_FUNDS`) at `n < 3` does not. The old rule is recomputed
  beside it and the two must agree on every case but the one this file adds.
- **(d) Probe B, the cut-loss, the real one.** One merchant the step can reach: a **single-hull** docked merchant (both
  live cases are one carlat), MOVED to a stop of her own loop that is **not the lap's first** — a cursor of 0 is the
  lap boundary, where 0101 sends a merchant home to rest and 0114 re-plans her, neither of which is under test; the
  chain's fresh world leaves every merchant at her own stop 0, and prod's stuck merchants lie mid-loop (TRP, BRI) —
  at a harbour with hands for sale and a good it bids on, and no failed order of her own. The stuck shape is planted
  on her inside each case's rolled-back subtransaction: `crew = crew_required − 2`, purse 0, her hold stocked at cost
  1,000,000 (so the at-profit SELL is refused `E_PRICE_LIMIT`), casks full (so the SAIL never fails `E_ENDURANCE`),
  hulls at full durability (so the stop's REPAIR can never spend the money), preset gone (so no `PROVISION` line
  stands between the sale and the hire), a failed `SAIL TO …` with `E_CREW_SHORT` at the head, and **two**
  `NPC_CLEARED` events already on the lap — so this is the third clear and 0270's rule re-plans on **both** sides: the
  only difference measured is the cut-loss.
  - **OLD** (the pre-image bodies re-installed, the way 0270 renames its old body): the HIRE is `skipped`
    `E_INSUFFICIENT_FUNDS`, the SAIL `failed` `E_CREW_SHORT`, her fleet **DOCKED**, her crew unchanged — the bug.
  - **NEW**: a `SELL … ALL` at the bid is `done`, the `HIRE` is `done`, the `SAIL` is `done`, her fleet **SAILING**,
    `fleet_crew_shortfall = 0`, and her purse still equals the sum of her ledger.
  - **Controls**, each OLD against NEW, digests equal where the rule must not act: **purse covers the hire** (no sale,
    the hire paid from her purse, she sails); **the hold cannot cover it** (a quarter of the hire's value in the hold —
    a fractional parcel, since one tun of the probe's good alone is worth more than the hire — no sale, and the OLD
    outcome exactly: HIRE skipped, SAIL refused); **at full complement** (no HIRE line at all, no sale, she sails).
  - A fourth check inside each shape: `npc_crew_blocked` is false at a quay she does not lie at.
- **(e) The probe left nothing**: no `probe_0272` order and no `PROBE_0272` ledger row survives.

## The local chain (PGlite; 0270, 0271 and 0272 applied in order)

- `chain: 261 migration(s) — 260 restored from the prefix cache …, 1 applied here — 261 with a self-assert receipt
  (267 receipt line(s)); chain key 74f8d40bffd1a871, 23.7 s`; world guard ok.
- The 0272 self-assert receipt, verbatim:

```
0272 self-assert ok: A CREW SHORTAGE IS PAID FROM THE HOLD. npc_leg_lines and npc_clear_due reverse to their pre-images hunk by hunk, ACLs unmoved, every other function in the four schemas unmoved (md5), public.npc_crew_blocked the one function minted, the quay takers and the client entry points unmoved, and the traders' switch exactly where the world had it ({"npc_traders_enabled": false, "standing_routes_enabled": false} reads back as it was). The rule on 7 planted clears: a SAIL refused E_CREW_SHORT plans on the FIRST clear, E_ENDURANCE too, the third clear too, an ordinary refusal at n < 3 not. The cut-loss, her step OLD vs NEW on merchant 7e6e35a5-eea3-4655-8251-74129a294cb6: OLD leaves HIRE skipped and SAIL refused E_CREW_SHORT with her docked; NEW sells at the bid, pays the HIRE, sails, crew restored and the ledger reconciled; 3 controls (purse covers, hold short, at full complement) left identical rows. Rolled back.
```

- **The switches after the apply, read from the committed world:** `npc_traders_enabled = false`,
  `standing_routes_enabled = false` — where the fresh world has them (see the CI red below).

### The CI red this slice caused, and the fix (2026-10-29)

The first push went red on acceptance shard 2/3, on exactly the dark-refusal specs
(`tests/rpc.surface.spec.ts:1902` `expect(dark.enabled).toBe(false)` — a standing route round-trips; `:1960`
`expect(dark.merchants).toBe(false)` — `world.route_board`; `:2049` `expect(dark.ok).toBe(false)` — `world.fleet_trades`).

**Cause, proved:** the world the shards build shipped with the traders' switch **ON**. The self-assert called
`pg_temp.traders_on_0272()` at the block's own level (probe B's setup): each probe case below it rolls back its own
subtransaction, but that call did not sit in one, so its `UPDATE public.world_config` survived to the end of the block
and was **committed with the migration**. The local proof never saw it because `proof.mjs` discards the world it
applies; CI's acceptance world is the committed one.

**Fix (probe plumbing only; no rule, no claim touched).** The outer call is gone — every probe case turns the switches
on INSIDE its own rolled-back subtransaction (`pg_temp.state_0272`), and nothing else needs them on. And the
self-assert now carries the durable guard that would have caught it: it snapshots both switch values at the top of the
block and, in check (e), raises `0272 self-assert FAIL: the migration left the traders switch ON …` unless they still
equal that reading. Verified after the fix by applying the chain and querying the committed world, above.

- `node scripts/db/proof.mjs standing`: `✓ 11_standing_route.sql — 5/5 PASS markers`, `PROOFS PASSED: 1 file(s), 5/5`.
- `node scripts/db/proof.mjs merchant`: `PROOFS PASSED: 1 file(s), 6/6 PASS markers`.
- **The pre-images ARE prod's, measured:** at head 0271 the chain's own bodies hash to
  `65b27dcf73ded8b8ce4b4a1204380999` for `public.npc_leg_lines` and
  `ff1eed323e3e11b6935079247046f4f5` for `public.npc_clear_due` — the two figures the deploy's prod check names — so
  the hunks are cut against exactly the bodies production runs.

### What the factory had to be told (probe plumbing only; no claim weakened)

Three probe-only corrections were needed, and none of them changes a rule or an assertion's meaning:

1. **The probe merchant must be moved to a MID-LAP stop.** The chain's fresh world docks every merchant at her own
   stop 0; a cursor of 0 is the lap boundary, where 0101 sends her home to rest (`hold_until` = closed_at + the
   fortnight's rest) and 0114 re-plans her — so her step rendered no lines at all. Prod's stuck merchants lie mid-loop
   (TRP, BRI), which is the shape the probe now builds.
2. **One hull, as both live cases are.** `cmd.do_hire` fills the hull with the MOST ROOM first, so on a fleet of equal
   hulls `HIRE <total shortfall>` restores one hull and leaves the others short; the probe's first draft (three hulls)
   therefore showed a SAIL still refused after a *successful* hire. That distribution is 0007's and is untouched here —
   see "not proven".
3. **`world.quote` raises `E_NO_SUCH_GOOD` on a port/good pair with no market row.** The rule, the cut-loss and the
   probe's good picker now join `public.port_goods` first; an untraded good is worth nothing at that quay.

The "hold cannot cover it" control is built by loading a FRACTIONAL parcel (a quarter of the hire's value), because on
this quay one tun of the cheapest good alone is worth more than the hire.

## What is NOT proven (said plainly)

- **The multi-hull and no-cargo shapes, and merchant behaviour on prod.** The probe proves the rule and the cut-loss on
  the chain's world; what the two live routes do after the deploy is the after-check below, not this file.
- **A house with neither coin nor saleable cargo is not helped.** `npc_crew_blocked` is false, and the loop continues
  exactly as today. That needs its own owner decision (a bounded city-paid crew aid, or a visible `error` pause).
- **A multi-hull fleet is not restored by hiring the shortfall.** `cmd.do_hire` fills the hull with the MOST ROOM
  first (0007's own distribution, untouched here), so on a fleet of equal hulls `HIRE <total shortfall>` restores one
  hull and leaves the others short. Both live cases are a single carlat, which is the shape the probe builds; a
  multi-hull stuck merchant would still loop as today. That distribution is its own slice if the owner wants it.
- **`world.quote` raises `E_NO_SUCH_GOOD` on a port/good pair with no market row** (found while proving). Both the rule
  and the cut-loss join `public.port_goods` before quoting, so an untraded good counts as worth nothing at that quay
  rather than aborting her plan.
- **The cut-loss covers the HIRE, not a `PROVISION` that may run between the sale and the hire in the same stop.**
  `cmd.do_provision` is all-or-nothing (0007:602-607), so a stop whose store top-up the sale also pays may spend it
  before the HIRE. The first clear re-plans (the new clause guarantees it) and sells again while the hold still
  covers, and once the store level is met the drain cannot repeat; but on that one clear the HIRE can still be short.
- **Selling at the bid forsakes the profit** the at-profit SELL would have taken. That is the point of a cut-loss, and
  it is why the rule fires only when she is below complement, broke, and her hold covers it.
- **How many stacks leave her hold** is the fewest (largest bid value first) that cover the cost; the choice is
  "decided by default" — the owner may prefer a fixed good ordering.
- **Nothing about merchant behaviour after the fix** is measured yet: whether the two live routes actually sail, and
  whether their laps close, is the after-check below.

## The after-check (prod, read-only, after 0270, 0271 and 0272 are deployed)

For routes `1b52a58e-…` and `63ade18d-…` (and any other route that was clearing `E_CREW_SHORT`):

- `NPC_CLEARED` per route per hour: **should fall to none** within one clear (the first clear re-plans and sells).
- `players.ducats`: **should stop reading 0** (the sale's proceeds less the hire).
- `fleet_crew_shortfall`: **0**; their hulls back at `crew_required`.
- Their laps: `standing_route_laps.closed_at` should start moving again; `stops_done` rising.
- The world-wide count of `E_CREW_SHORT` clears (the report's `19_cleared_codes.sql`) should fall towards 0; that
  query, `41_cargo_value.sql` and `36_failed_codes.sql` in `~/dev/prodcheck-2026-10-29/` are the read-out.
- A forward rollback is the usual one: a new migration restoring `public.npc_leg_lines` and `public.npc_clear_due` from
  the pre-images this file carries (`old_bodies` in the source), if a merchant sells a hold for a hire that was not
  needed.

## Prod checks before the push (read-only, in the PR body)

- The live bodies are the ones the hunks were cut against: `pg_get_functiondef` (or md5) of
  `public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)` and `public.npc_clear_due(uuid,uuid,int,text,text)`.
- `public.crew_hire_cost(fleet, n)` is still the one price `cmd.do_hire` reads (its body's `select (q->>'normal')::int,
  (q->>'urgent')::int, (q->>'cost')::bigint … from public.crew_hire_cost(`).
- The two stuck routes still read purse 0, a shortfall of 1-2, and their holds 5-13x the hire at the bid.

## Overhead

| what | cost | where |
|---|---|---|
| `npc_crew_blocked` on a leg whose `from` is not her port | one PK read of `public.fleets` | inside the plan (as before: `npc_plan` already reads her fleet) |
| `npc_crew_blocked` when she IS at the port but not short, or her purse covers it | 1-2 small reads; no quote | inside the plan |
| `npc_crew_blocked` when she is blocked (rare: broke + short + docked) | one `world.quote` per good aboard (<= 12), plus one per good again in the cut-loss | inside the plan — and the plan itself is the 0.4-1.1 s the 0270 slice moved off the quay |
| the rule (`npc_clear_due`) | one extra string test on the same JSON it already returns | nothing measurable |

No new quay taker; no new lock; no new write path.
