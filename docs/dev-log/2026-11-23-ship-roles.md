# 2026-11-23 — 0485 a fleet that grows to five ships (dark: `ship_roles_enabled`)

`docs/design/roadmap-2026-11-23.md` slice 17 ("A fleet that grows to five ships": Uncharted Waters, Port Royale), on HQ's board
(`docs/design/hq-command-2026-11-23.md`). The owner, 2026-11-23: "i want this game to be strategical game, where all the work
(activities) are done in HQ - words with graphics. choosing best options available, finding best options."

## What it does (lit)
- **A role is a tag on a hull**: `public.ships.role`, one of `guard`, `fast` or `hold`, or null. It is a new nullable column with no
  default, so no row is rewritten. The tag stays with the hull whatever fleet she sails in. Only a company can set one, so every merchant,
  navy, pirate and cargo hull stays null.
- **The slots.** Her third hull opens the first slot, and each hull after it opens one more, up to three (`ship_roles_free_from` 3).
  Five hulls give three slots. Any hull may take any role, and a role may repeat.
- **Each role works through the one place that already decides the thing.** Nothing is computed a second way.
  - **Fast:** `public.ship_base`, the one place a class meets a hull (0276), is changed by one hunk. A fast hull's speed is x1.10
    (`ship_roles_fast_pct`). Every speed, ETA, trip quote, job plan and contract window reads it from there.
  - **Big cargo** (`hold`): the same hunk. Her hold is x1.20 (`ship_roles_hold_pct`), floored as before. Every capacity, free hold and
    buy cap reads it from there.
  - **Guard:** `public.raid_target` gets three hunks. This is 0427's choice of the merchant a hunting pirate sets upon. A fleet with a
    guard hull, or a fleet in an armada with one, has her miles weighed x2 (`ship_roles_guard_weight`). So:
    - a pirate strikes her only within half its reach, which is a quarter of the water;
    - a nearer unguarded merchant is set upon first.
  - **A hull with no role reads neither knob.** The `case when s.role = ...` is false, so the expression is the pre-image's times 1.
- **One press:** `cmd.set_ship_role(ship, role)`. A null or empty role takes the tag off. The press is refused (in the server's own
  words) when:
  - the hull is not hers (`E_NO_SUCH_SHIP`);
  - her fleet is not in port (`E_NOT_DOCKED`, by `public.fleet_state`, the one rule);
  - no slot is free for an untagged hull (`E_NO_ROLE_SLOT`, a new code with EN and KO words);
  - she carries more than the hull would hold after the change (`E_HOLD_FULL`). The tag then stays as it was.
- **The best role** (`public.ship_role_pick`) is the role she has fewest of. Among those, it is the one her own play asks for most:
  - guard, by the raids her fleets were in (the RAID battles still kept);
  - fast, by her standing jobs and the contracts she carries;
  - hold, by her standing routes.

  Ties go guard, then fast, then hold. The pick's hull is her untagged hull in port with the most attack (guard), speed (fast) or hold
  (hold).
- **HQ's board** (`public.hq_board_for`, three hunks):
  - A **role card** (band 0, beside the yard), "Guard: Gaivota". It shows the reason and the gain, and its act is `cmd.set_ship_role`. It
    stands while a slot is free.
  - The **yard's card** stands until she has five hulls (dark: `hq_board_build_below`, as before). It carries `role`: what the next hull
    should be.
- **The read** `world.ship_roles()` (STABLE, registered) returns:
  - her slots, and each hull's role and whether it can change now;
  - the pick, and the next hull's role;
  - the gains;
  - **the ladder** (`public.ship_role_ladder`): ships (her hulls of five), then routes (her fleets working by themselves, on a standing
    route or job), then captains (her fleets with a captain seated). The first step not done is the goal card's line.

## Client (lit only; dark nothing new is drawn)
- **HQ's fleet rows** (`features/city/board/RoleControl.tsx`): under each row, the three roles as chips for each of her hulls in that
  fleet:
  - the chips are a shield (Guard), the speed glyph (Fast) and the hold (Big cargo);
  - the chip that is on is her role, and pressing it again takes the role off;
  - the best role for her untagged hull wears a small trophy;
  - a hull at sea, or with no slot free, shows dimmed chips;
  - a refusal stands under the row in the server's words.

  The chips show only once she has a slot or a tagged hull.
- **The board** (`MoveCard.tsx`):
  - The role card's title is "Guard: Gaivota". Its chips are the gain (÷2, +10%, +20%) and the reason's count (raids, jobs, routes). The
    press sends the act (`servedPress.ts` → `live/useShipRoles.ts`'s `setShipRole`, the row's own door).
  - The yard card reads "Next ship" with a "Next: Guard" chip.
  - A **Roles** filter chip shows when a role card is served.
- **The goal card** (`GoalCard.tsx`): past the second ship, the second line is the ladder in place of the two tracks:
  - it reads "Ships 3 / 5 · Next: Guard", then "Routes 1 / 2", then "Captains 0 / 2";
  - the ring is that step's share, its mark the step's glyph (ship, route, captain), and the press opens HQ.

  Dark, or with every step done, the tracks stand as before.
- **The read** is `live/useShipRoles.ts`, shared by HQ and the goal card under one key. It is asked when either opens, when a fleet of
  hers acts, and after a press. It is never asked on the beat.
- **Words** (EN / KO, `dict/hq.ts`; docs/WORDS.md row): Guard / 호위, Fast / 쾌속, Big cargo / 대형 화물, Roles / 역할, "{role}: {ship}",
  Next ship / 다음 배, "Next: {role}", "{n} raids / jobs / routes", Speed +{n}%, Cargo +{n}%, "Pirates strike within ÷{n}", and
  "Ships / Routes / Captains {n} / {of}". "Big hold" is not on screen: WORDS.md says cargo, never hold.
- **Spec:** `tests/hq.board.spec.ts` "a hull's role (0485, lit)" runs at 320 and 1280. The fixture opens a slot at the first hull
  (`ship_roles_free_from` 1). The spec checks:
  - the role card names Guard and the row marks it best;
  - the card's press sets it and the card leaves;
  - the row's Fast chip changes the role;
  - nothing scrolls sideways and every press is at least 44 px.

## Measured
- **Local chain (PGlite).**
  - The self-assert takes **129 ms**, with 8 hunks once and reversing.
  - Proof 188 (5 markers) takes 0.2 s.
  - The scenes, played by `public.raid_target` itself:
    - a pirate with her two fleets at 100 miles either side sets upon the unguarded one;
    - a fleet alone at 150 miles (reach 240) is passed over guarded (150 x 2 = 300), and struck unguarded or dark.
  - The board's role card in proof 188 is "Gaivota: guard", gain 2. The yard's card is a barca at LIS for 26,421, next hull guard.
  - `public.ship_base` x500 takes **7 ms untagged and 12 ms tagged** (two knob reads for a tagged hull). One lit `raid_target` takes 2 ms.
- **Prod (`before-0485`, the one read, 2026-11-23 12:22 UTC).**
  - The gate, read in the same statement: beat mean **176 ms** over 5 minutes (285 beats), **765 MB**, 0 sessions waiting on the disk.
  - Head **20260818000483**: 0484 was not yet on prod.
  - No `ship_roles_*` knob, no column, no function.
  - Each of the seven hunks on `ship_base`, `raid_target` and `hq_board_for` occurs once, and no new text is present. The registry's
    hunk is anchored on 0484's own `nation_race` line, so it reads 0 until 0484 lands. The self-assert checks it again at deploy and
    refuses otherwise.
  - Pre-image md5 on prod:
    - `ship_base` dc62cd9737495b8565ad5cbf4c13414d;
    - `raid_target` b360c71247f1402f6db88f1381125237;
    - `hq_board_for` 4280a08f476f4dfba3d5e34261b92b0b (0483's: 0484 hunks it too);
    - `client_rpc_entry_points` a5914b9e8a2fcdb034247232830d9e1a (0483's).
  - The probe's selections (Lisbon, the barca class, the armada tables) are all present.
  - **19 companies: 16 with one hull, 3 with two. None has three yet**, so lit, no one has a slot until a third hull is launched. The
    role card and the row chips wait for it, and the yard's card names the third hull's role.
  - **The room:** `fleet_room_bite` is true, with `fleet_max` 2 fleets and `fleet_ship_base` 2 hulls a fleet. That is four hulls before
    earned room (Seamanship or Command, Trading rungs, bought steps). The ladder's five is a goal that the room must open.
  - **Raids:** `raid_companies_enabled` is true, `attack_reach_nm` 240, and `pirate_strike_tries_per_run` 16. 5,675 RAID battles are
    kept, 2 of them with a company's fleet.
  - **Cost:** `public.ship_base` x200 on the newest company hulls took **2.16 ms** (11 µs a call; the hunk adds nothing for a null role).
    One `raid_target` took **57.9 ms**. That is today's cost; dark it adds one knob read a call, and lit one indexed probe a candidate.

## Load
- **No table, no cron job, no beat step.** No `-- budget:` line is needed.
- **Dark:**
  - `raid_target` reads one more knob a call (at most 16 a minute);
  - the board reads one knob;
  - `ship_base` adds nothing.
- **Lit:**
  - one ships row is updated a press;
  - `ship_base` reads two knobs for a tagged hull only;
  - `raid_target` makes one `ships (fleet_id)` index probe for each candidate it orders;
  - a board read or a roles read makes a handful of indexed reads of her own rows.
- **Expected extra rows a minute: 0**, apart from the presses.

## Decided by default (the owner may reverse)
- **The figures:**
  - fast +10 % speed and big cargo +20 % hold, through `ship_base`, so they reach every quote;
  - a guard weighs her miles x2;
  - slots from the third hull, up to three;
  - the ladder's ships step is five.
- **The guard works on the pirate ships' strikes (0427's battles), not on a voyage's anonymous PIRATES day.** `voyage.hazard_roll` is a
  pure function of (voyage, day, secret), and the game rests on that. A hull's role would make it read a row that can change.
- **"Sails with" means the same fleet, or a fleet in her armada.** A convoy is not counted.
- **A role changes only in port**, so a voyage under way keeps the speed and the hold it left with.
- **Any hull may take any role**, and roles may repeat. The pick steers toward the role she has fewest of.
- **The pick's reasons are her own rows:** the RAID battles still kept (48 h), her standing jobs and carried contracts, and her standing
  routes.
- **The board's role card is band 0**, beside the yard: a free slot is one press and costs no coin.
- **The words:** "Big cargo" on screen (WORDS.md: cargo, never hold); `hold` stays the server's key.

## Prod checks
- Before: `scripts/ops/harness/ship-roles/before-0485.sql` (done, the one read). Its registry anchor reads 1 once 0484 is live.
- After (and 30 minutes after lighting): `scripts/ops/harness/ship-roles/after-0485.sql`.
