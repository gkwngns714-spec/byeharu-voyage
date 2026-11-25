# 2026-11-25: `no-ruinous-run`: 0502 (dark: `run_guard_enabled`), proof 212

On `origin/stack-jobs-never-lose` (0498) with `origin/wreck-can-sell` (0497) merged. Server only. Nothing touched production.

## The design, in ten lines

1. One reading, `public.run_need(player, fleet, from, lines)`: what a plan's own lines ask of her purse and her hull.
2. `need` = stores (`world.trip_cost`) + dock fees + missing crew (`crew_hire_cost`) + a whole repair (`fleet_repair_cost`) + one storm's safe default (`sea_choice_options`, while choices at sea are lit).
3. The dock fees are asked of `public.port_fee` at every call for the cargo aboard AND about to be bought: `world.trip_cost` charges the cargo aboard now, so a run that buys was quoted too little.
4. The purse is judged AFTER the BUY. A BUY that leaves less than `need` is cut to the units that leave it, if they still pay their way.
5. No units do, or nothing is bought and the purse is under `need`: `{wait: purse}`, "purse 8,240, fees and repair need 12,174".
6. Danger: the expected share of a hull the passage costs (the sea's chance a day, its mix, a storm 0.165, a shoal 0.095, a raid 0.05 or 0.50 when outgunned) over `run_guard_hull_share` (0.5) of the hull she has: `{wait: danger}`, "too dangerous for her hull".
7. Asked where a run STARTS: a fixed job at its buy harbour, a Best job's first four sales, a land haul leaving. Never at the sale, never on the way back.
8. A Best job takes the first of the four that stands; none: it waits with the best one's reason.
9. The wait is 0498's: 600 s at least, never stopped, resumes by itself, its sentence on her worker row.
10. Dark: every plan is the plan it was, asserted.

## Her real case (proof 212, local world, the switches of a closed economy and choices at sea lit)

Her 899 coral at the cost that makes Diego Garcia's dock fee the 3,233 she paid (208,640 here); purse 8,240; hull fresh; five sails.

| Term | Coin |
|---|---|
| Dock fees, five harbours (DGA 3,233) | 6,401 |
| Whole repair (hers was 736) | 762 |
| One storm's safe default (hers was 5,000) | 5,000 |
| Stores | 11 |
| **Need, against 8,240** | **12,174: she waits at the Island of Mozambique** |

**Stopped by:** the purse rule. Had the BUY been in the same plan, it would have been CUT to what leaves the need (899 to 877 at local prices), so she would have sailed with the fees, the storm and the repair in hand.

**Not stopped by:**
- The danger bound: her whole chain's expected hull loss reads 0.048 of a hull, far under 0.5. The wreck itself was dice (what hit her was not read: no prod access). A run that can afford its way can still wreck her.
- The tow (14,366 to Colombo) is not in the reserve: she would hold a repair's coin, not a tow's. 0497's sale pays it.
- A shorter plan: the Island of Mozambique to Palma alone needs 7,055 and would have started. So would her own orders, which this never judges.
- A second storm on the chain, a raid's ransom, a forced home.
- While she waits, 899 coral stay aboard until she sells them by hand or prices, purse or another sale change.

## Checked

- Self-assert on the snapshot (about 0.1 to 0.3 s); proof 212: 8/8; proofs 200 and 184 again: 9/9, 7/7. `tsc -b`, `db.budget`, `news.lint`.
- `scripts/ops/harness/no-ruinous-run/perturb.mjs`: 15 worlds that are not the chain's: 13 pass, 2 known (a founding Lisbon cannot pay; Lisbon with no market row at all, which 0498's probe refuses too).
- A purse of 400 waits; 8,240 at Lisbon buys 4 quicksilver (free 279 after the need); 40,000 buys 20.
- Cost: one read over her five sails 27 ms; a Best job asks four at most; nothing while dark.

## Decided by default (the owner may reverse)

- A cut run, not a refused one, where a smaller cargo is safe. The reserve is a whole repair. A company under about 760 coin waits.
- Cargo already aboard is guarded too (her case): the earlier design would have carried it and ruined her again.
- Wages are not in the need: they are owed, and paid out of the sale's profit.
- The raid's 0.50 is a judgement, not a measure.
- The design file `docs/design/no-ruinous-run-2026-11-25.md` is folded in here.

## Not verified

- Coin an hour before and after with the guard lit (a measured window, the lead's). Prod: nothing was read.
- 0501 (not seen). Over near-round and fit-to-sail (their branch's files, applied locally before 0502) the self-assert passes; the before / after reads ran locally.
- `vite build` and `rpc.surface` were not run. No client work: the row draws the served sentence.
