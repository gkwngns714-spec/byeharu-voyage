# 2026-10-18 — the sinks are deleted, and famous gear waits (migration 0184, `osn-merchant-redesign`)

**The order.** The owner, 2026-10-18 ~13:25 UTC: *"no need to hand in surplus... wtf. no they don't need to build
ships. … yes famous gear can be made, but later. there will be other items that needs to be gained in act of pirating,
trading, and all. i will set them later."*

0180's sinks (a) the purse ceiling and (d) the hull building were chosen by default, not by him. He rejected them, so
they are **deleted, not adapted**. Recorded in `docs/OWNER_REQUESTS.md` rows 152 and 153, with the tuition grant: never offer
either again.

## 1. What prod held first (read-only, 13:30–13:45 UTC, head 0181)

Every probe was `begin transaction read only; … rollback;`, and every function called was `s` or `i` in
`pg_proc.provolatile` (`pg_get_functiondef`, `made_only_in`, `requirements_met`).

- **Who reads 0180's sinks:** `npc_tend_route` (calls `npc_build_for`), `npc_tend_houses` (calls
  `npc_give_above_ceiling`), `npc_tend_sum` (adds `built`, `ceiling`, `ceiling_given`). Nothing else.
- **What 0180 left in the books:** 510 `MERCHANT_SURPLUS` ledger rows and 510 `SURPLUS_GIVEN` events. They stay:
  the books are append-only. (The 87 `MERCHANT_SURPLUS` treasury flows seen at 13:30 had been compacted by the flows'
  own retention window by 13:45; this file deletes nothing.)
- **Hulls laid down by merchants since 07:00:** 3 `HULL_LAID_DOWN` events. They stay their companies' ships.
- **Famous gear:** 0 famous ships, 0 famous pieces held or fitted, 0 companies with Famous Ships I. `skills_bite` is
  on, so any company that learned Famous Ships I could have made a piece at a tier-3 workshop and laid a famous hull
  down. **So yes: the 11 famous ships were buildable in principle.** They need their piece, so they become
  unbuildable too.

## 2. The migration

1. **Sink (a) deleted.** `npc_give_above_ceiling` and `npc_purse_ceiling` are dropped, and so is the knob
   `npc_purse_ceiling`. `npc_tend_houses` is its pre-0180 body again.
2. **Sink (d) deleted.** `npc_build_for` is dropped. `npc_tend_route` and `npc_tend_sum` lose 0180's parts and keep
   0181's `waiting`.
   - **Kept:** 0180's "a BUY line is never born refused" in `npc_leg_lines` (untouched).
   - **Client:** the Town Hall's "Merchants' surplus" row is deleted (`src/live/CityTownHall.tsx`). Nothing will write
     that kind again, so the row would be dead code.
3. **Famous gear is made nowhere, for now.**
   - **The data:** `scripts/build-gear.mjs` `FAMOUS_MADE = false` writes each Famous piece `made: false` in
     `data/gear.generated.json`. Its recipe stays authored, for the day the owner sets how a piece is won.
   - **The table:** `public.item_unmade` holds those 11 rows (`--sql-0184` gives the VALUES). The world guard holds it
     equal to the data, both directions, with a positive control (a dropped row must be seen).
   - **The sentence:** `public.item_not_made(item)` is THE one sentence ("Drake's Culverins is not made in any
     workshop yet"). `public.made_only_in` reads it first, so `cmd.do_make` refuses `E_NOT_MADE_HERE` and
     `world.workstation` serves `makeable: false` with the sentence. Neither body changed.
4. **A famous ship waits with her gear.** `public.hull_unmade(class)` is derived from the hull's parts (never a list
   of hulls): "Golden Hind cannot be laid down yet: Drake's Culverins is not made in any workshop yet". `cmd.do_build`
   refuses `E_NOT_BUILDABLE` with it, before every other yard rule. `world.building_yard` folds it into `buildable`
   and serves it as `unmade`; the yard tray prints it (`src/live/PortYard.tsx`, `data-testid="yard-unmade"`).

**Hunks:** 12, in six live bodies: `npc_tend_route` (3), `npc_tend_houses` (3), `npc_tend_sum` (1), `made_only_in`
(1), `world.building_yard` (3), `cmd.do_build` (1). Each was checked read-only on prod (head 0181) to occur exactly once.
In the file, each is asserted to occur once, each body to reverse to its pre-image, and every ACL to be unchanged.
Re-checked read-only on prod at head 0182 after the rebase: all 12 still occur once. 0182 touched `tick_arrivals` and `tick_reconcile` only, and 0183 (#222, the desk) touches `world.good_board` / `price_outlook` / `watchlist` / `price_history`, so no hunk overlaps either.

**Self-assert receipt** (the head-0181 image):

> 0184 self-assert ok: A MERCHANT KEEPS WHAT SHE EARNS, AND FAMOUS GEAR WAITS. (1)+(2) npc_give_above_ceiling,
> npc_purse_ceiling and npc_build_for dropped with the knob; no live body reads them; … (3) 11 famous pieces made
> nowhere: the workshop door refuses "Drake's Culverins is not made in any workshop yet" (a G1 anchor-and-cable, the
> control, reaches E_NO_MATERIALS), the workshop serves all 11 closed with the sentence. (4) 11 of 103 hulls cannot be
> laid down — exactly the famous ones, derived from their parts: the yard door refuses "Golden Hind cannot be laid down
> yet: …" (armfluit, the control, passes to E_WRONG_YARD), the yard serves 11 of its 11 famous closed and no other.

**The probe counts only its own rows.** It uses one merchant fleet (the roster's first) and lays her at the first
harbour with a tier-3 workshop and a yard itself, inside a block that is rolled back. Every count is of the 11 rows
this file writes or of the hull recipes.

**Its selections, run read-only on prod:** the fleet is Carreira da Índia (SAILING; the probe docks her itself), the
harbour ARP, the G1 control `anchor-and-cable`. The Golden Hind's one part is `drakes-culverins`, and the 11 famous
hulls have 11 parts.

## 3. Found on the way, not fixed here (a separate decision)

**`cmd.do_make` does not check `item_kinds.kind`.** The three promotion items (`sea-chart`, `trade-seal`,
`battle-honour`) are `ws_tier` 1 with no recipe, so `do_make` would hand one out for nothing at any workshop. Only
`world.workstation` filters them (`kind = 'fitting'`). Prod has 0 `MADE` events for them, so nobody has found it.

## 4. Verify (once each; worktree `~/dev/bv-redesign` off main `440dfb8`, real `npm ci`, the main clone's `node_modules/.cache` plus bv-replan's p0171–p0173 prefix snapshots, no `.env.local`)

- **0184 on the head-0181 image:** self-assert ok (receipt above), applied in 355 ms.
- **0184 on the prod-shaped world** (prod's knobs, stocks, purses, treasuries and loops): with every merchant fleet
  SAILING, applied in 588 ms; with every one DOCKED, in 733 ms.
- **Cached-prefix build** (`BYEHARU_PREFIX_CACHE=required npm run build`): restored 173/174 and applied 1 (0184). The
  world guard reported "11 items made nowhere", and its positive control saw the dropped row.
- **Generators:** `node scripts/build-gear.mjs --check` and `node scripts/build-ships.mjs --check` both equal their
  files.
- **tsc -b**: 0. **eslint .**: 0. **db:check-versions**: 174 distinct, no collisions.
- **Proofs on the built image:** 12 files, 85/85 PASS markers (proof 12, the merchants, included).
- **Number:** prod head is 0182, and #222 deploys as 0183 first, so this file is 0184. Re-read the head before pushing.
