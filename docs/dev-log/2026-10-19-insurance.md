# 2026-10-19 — 0211: a cargo can be insured (insurance v1) — `osn-insurance-v1` — WIP, NOT FOR DEPLOY

## HAND-OFF (2026-10-19, PC switch; the agent was stopped mid-work)

**State: server migration written, NOT proven. No client, no specs, no sim, no PR.**

### Done
- `supabase/migrations/20260818000211_a_cargo_can_be_insured.sql` — the whole server design (header §1–§8):
  - `voyage.risk_quote(voyage)`: the expected loss share. It is the interface PIRATES_AND_HAVENS.md (PR #268, Z7) names, so Z1 can re-cut it. It composes `voyage.hazard_roll`'s `p_hazard` (only that column), `voyage.sea_mix`'s PIRATES share and the knob `insurance_raid_loss` 0.084.
  - `public.insurance_price`: ⌈value × risk × 0.9 × (1 + `insurance_margin`)⌉, with the margin set to 0.10 for now (`_gen.mjs` arg).
  - `voyage.raid_takes`: PLUNDERED takes 25–50 % of each good by the roll `'plunder'`; STRIPPED takes all of it.
  - `public.insure_voyage`: called by `cmd.do_sail` at departure. It charges the city the ship sails from. Merchants are always insured.
  - `public.insurance_claim`: pays from the city's surplus, less the 10 % deductible. Any shortfall is recorded.
  - `public.insured_voyages`, with RLS and no client grants.
  - `world.insurance()`: registered for authenticated.
  - Hunks:
    - `cmd.parse`: `SAIL X INSURED`.
    - `verb_schema`: enum `insurance` = INSURED.
    - `do_sail`: the result carries `insurance`, so the preview quotes it.
    - `settle`: the PIRATES arm.
    - `npc_tend_houses`: the refound is removed.
    - `npc_tend_sum`.
    - `close_lap`: the new `insurance` column comes off the net.
    - `world.books`.
    - `npc_fleet_card`: `insurance` replaces `refounded`.
    - `client_rpc_entry_points`.
  - Retired: the knobs `npc_purse_floor_pct` and `npc_refound_cooldown_game_days`, and `public.npc_worth`. All three go at the end of the file.
- **Every hunk matches the local chain image of main (0208), each exactly once.** A Python check confirmed it. The local apply got past the hunk loop: hunks applied, reversed, and ACLs unchanged.
- The generator sources are in `docs/dev-log/insurance-wip/`:
  - `mig.src.sql` and `probes.src.sql`;
  - `gen.mjs`, which fills `@@L:fn:a-b@@` from a dump of live bodies (`_dump.mjs`-style, `node_modules/.cache/ins-dump/all.sql`).
  - Regenerate with `node gen.mjs <margin>` from the repo root, after copying the files to `_mig.src.sql`, `_probes.src.sql` and `_gen.mjs`.
  - **The committed migration is the generated output.** Fix the sources and regenerate it, or edit the migration directly.

### Measured on prod (read-only, 2026-10-19 ~08:00 UTC)
- A plundering raid takes nothing. Since 0007, PLUNDERED leaves the cargo: `cargo = case when STRIPPED then '{}' else cargo end`.
- With the fight lit (since 01:20 UTC):
  - 348 raids in 211,909 sea-days;
  - 78 PLUNDERED (22.4 %), 0 STRIPPED.
  - So no cargo is ever lost today. This is why the migration makes PLUNDERED take cargo (DESIGN B.6). Decided by default.
- Refounds:
  - 1,372 in the 7 days to 07:00 UTC, with several million coin a day going from cities to merchants;
  - after 0208 (07:05) only 1.
- All 400 raids in the last 3 days hit merchants; none hit players.

### Where the probe stood when stopped
- Fixed so far:
  - the barca's casks were already full (E_HOLD_FULL is now tolerated);
  - a variable `i` clashed with an alias;
  - `voyage_event_kinds` mix is all-or-nothing: a kind is now taken out of the mix with `in_sea_mix = false, is_rolled = false, mix_* = null`;
  - `seas.piracy_index` has a check (≤ 1): the probe uses piracy 1.
- The last apply was interrupted at 10 min. P1 alone had passed its sub-block; the asserts never ran. **Next: re-run the local apply** (`node _dump.mjs` with the prefix cache: p0200 is cached locally) and work through the asserts. The likely next failures:
  1. P2 lit: is every day PLUNDERED? The asserted precondition may meet RANSOM if the boarding ratio is ≥ 0.7. If so, use more raiders or the dark table only.
  2. The apply time. P6 runs `npc_tend_houses` twice, which means `npc_invest` over 821 houses.

### Not started (the rest of the brief)
1. Paired merchant sim: `scripts/ops/harness/arrfast` on origin/osn-arrivals-fast plus a prod-state export. Measure premiums vs payouts, lap nets, lay-ups and city purse flow. Then tune `insurance_margin`.
   - Also a break-even check on prod history, read-only: Σ `risk_quote`-style expected loss vs realised PLUNDERED × 0.375 over the lit window.
2. Timing: `risk_quote` and `do_sail` ×8 in one session (the probe prints `quote_ms`). Prod read-only timing of the risk arithmetic over real voyages.
3. Prod read-only checks: the hunks occur once in prod's live bodies; LIS, FNC and the probe ids are free.
4. Client:
   - the plan builder: an "Insure the cargo" toggle with the price from `cmd.preview(... INSURED)`; it writes ` INSURED` on the laden SAIL lines in `planLines.ts`;
   - the map's SendFleet toggle (`args.insurance='INSURED'`);
   - Plans face: an "Insured voyages" section from `world.insurance()`;
   - `headline.ts`: INSURED and INSURANCE_PAID;
   - MerchantSheet: the `insurance` line in place of `refounded`; `types.ts`;
   - WORDS.md: "Insurance", "Insure the cargo", "Insurance paid", and never "premium" (that word is the requests');
   - DESIGN F.2/F.5: SAIL [INSURED], `E_NO_INSURER`.
5. Specs: `tests/insurance*.spec.ts`, `rpc.surface` allow-list (+world.insurance), the `db.chain.spec` LAST pin.
6. The OWNER_REQUESTS row, then the PR.

## Decided by default (the owner may reverse each)
See the migration header "DECIDED BY DEFAULT":
- cargo only, one voyage per policy;
- the insurer is the port the ship sails from;
- the price ignores the fleet's guns in v1;
- merchants insure every laden voyage;
- PLUNDERED takes 25–50 %;
- a ruined merchant is not rescued and sails on with what she has;
- player routes are not insured.
