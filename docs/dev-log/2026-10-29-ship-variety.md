# 2026-10-29 — 0276: every new ship rolls her own stats (owner row 222)

**The slice:** the VARIETY half of `docs/SHIP_STORES_AND_VARIETY.md` — V1 + V3 in one migration
(`supabase/migrations/20260818000276_every_new_ship_rolls_her_own.sql`) + the client half in the
same branch. The STORES half (row 221, the design's V2) is a separate slice, NOT built here.

**State while this is written:** AUTHORED and GATED (the cached chain gate is green — §9), then
committed and pushed as a PR; NOT deployed (0273/0274/0275 land before 0276, in number order).
The 21 hunks were sliced from the LIVE prod bodies (head 0272, read-only `pg_get_functiondef`
via the linked CLI) and each is verified to occur exactly once in its body by a pure-text checker
(deleted before commit). The roll math is verified against an offline md5 simulator and against an
in-memory PGlite smoke (deleted; see §8 for the one bug it caught).

## 1. What was built, in eight lines

1. `ships.roll_speed / roll_hold / roll_stores / roll_hull / roll_crew / roll_handling` —
   numeric(4,3), default **1.000** (so every existing hull keeps her class figures, no backfill).
2. `public.ship_variety` — the bands AS ROWS: poor_cut/fine_cut, poor/fine spans, normal ±,
   grade_cut, per (class_code, stat); `''` = the default band, a class overrides stat by stat.
   Adding a class needs no code and no row. No band number lives in a function body.
3. `public.ship_roll_u(tag, seed)` — one uniform from md5(salt ‖ seed ‖ tag) — the salt is the
   fixed server-side seed. No `random()`: the same id always draws the same factors, anywhere, for
   ever, and a probe reproduces them from the id alone.
4. `public.ship_roll(seed, class)` — the six factors: one tier draw (below poor_cut → Poor
   1−(0.080..0.200); above fine_cut → Fine 1+(0.080..0.200); between → the bell 1 ± 0.120 over
   three uniforms).
5. `public.commission_ship` (the ONE ship insert, 0096) — rolls before the insert and writes the
   six columns. The seed is her own id (drawn before the insert); the signature gains
   `p_ship uuid default null` so a PROBE can name a fixed id (live play passes nothing). A famous
   hull (class_profile.tech 'F') reads 1.000 always; a founding hull (crewed AND flagship —
   new_house, and an NPC house's first) has every factor raised to 1.000 at least; the crew factor
   is clamped so her crew max is never below what the class needs (§2.1).
6. `public.ship_base(ship) → (hold, speed, durability, crew_max, handling)` — class × her roll,
   the ONE place a class column meets a ship. Hold/hull/handling floored to whole numbers, speed
   to 0.01 kn (their class scales — this is also what keeps pre-existing hulls byte-identical).
   **The stores line joins when the row-221 slice lands** (`ship_classes.stores` × roll_stores,
   beside these five) — said in the function's own comment so the next author finds it.
7. Twelve readers re-cut onto ship_base (below). The self-assert scans every body in the four
   schemas and proves no other body reads a rolled class column joined to a ship.
8. The client prints, it never rolls: `world.ship_view` serves `roll`, `grade`, and the class's
   own `class_*` figures; `world.building_yard` serves `variety_pct`; the ship panel draws the
   brackets and the grade word, the yard says the blind range before you build and toasts the
   grade after.

**Existing ships keep their current stats — said plainly:** this file backfills NOTHING. Every
hull afloat keeps roll 1.000 (the default), and the self-assert proves `world.ship_stats` and
`world.ship_view` answer their pre-images byte for byte, for every hull and every fleet in the
world. Only hulls commissioned after the deploy roll.

## 2. The twelve re-cuts (hunks sliced from the LIVE bodies, md5 of prod head 0272)

Each hunk asserts it occurs exactly once and reverses to its pre-image; ACL, volatility, definer
and search_path are asserted unmoved; the md5 of every OTHER function in the four schemas is
asserted unmoved.

| body | live md5 | what moves |
|---|---|---|
| public.commission_ship(uuid,uuid,text,text,boolean,boolean) | fdac25223f0b50f10adee2c2d0a2b6a6 | signature + the roll before the insert (the signature change is on purpose: the probe's id) |
| world.ship_stats(uuid) | 80020bfefd0710735395e6cd01052bd3 | the base of hold/speed/handling/durability reads ship_base (BOTH branches) |
| world.ship_view(uuid) | ec16c93af4245452d04bda11514740cb | rated figures read her base; NEW keys roll / grade / class_* |
| cmd.do_hire(uuid,jsonb) | fdccbbefd46d24fe9fc7fa47c26fc5ef | berths + the fill loop read her rolled crew max |
| cmd.do_repair(uuid,jsonb) | 4cc82ed3ebe418fa918c3027e029bda5 | the repair ceiling is her rolled max |
| public.fleet_repair_due(uuid,numeric) | a04f2e8893c5deac261cb821bbce964f | the points to mend read her rolled max |
| public.ship_set_bonus(uuid) | 517565654ba51c0f0177718e38867406 | the set's per-cent base (hold/speed/handling/durability) is her base |
| voyage.ship_speed_at(uuid,numeric) | 1a69dbf1c2cb58c26c394cc472d9f2c7 | the hull-speed factor divides by her rolled max |
| voyage.settle(uuid,timestamptz) | c604656b7178ea85703d9e5be5703369 | STORM and SHOAL_WATER take her rolled max |
| voyage.fight(uuid,int,uuid,numeric) | f41234621c1574ebe90adb8fa7ec7b7b | the hull handed to fight_resolve carries her rolled max (fight_resolve reads only the RAIDERS' class — untouched) |
| world.building_yard(uuid) | f12581b2e70c9fd9cfe5567023cacdb4 | each hull gains variety_pct (the yard stays on the class: it is the catalogue) |
| world.ship_budget(uuid) | 6ff6d2df77831425bf5a7c7a5cf12c21 | her Hands max reads her rolled crew max (Deck stays the class's) |

The design's §2.2 table also named class_budget, do_repair's walk, fight_resolve and sail_refusal:
prod's live bodies read differently than the design assumed — class_budget is CLASS-scoped (no
ship join; the ship-scoped consumer is world.ship_budget, re-cut above), fight_resolve reads only
the raiders' class, and sail_refusal reads no rolled column (its hull figures come through the
re-cut bodies). The no-other-reader scan (below) is the real guard, not the design's list.

## 3. The band rows (the data)

| field | value | meaning |
|---|---|---|
| poor_cut / fine_cut | 0.050 / 0.950 | one tier draw below / above this makes the hull Poor / Fine |
| poor_lo / poor_hi | 0.080 / 0.200 | Poor factors: 1 − (0.080..0.200) → [0.80, 0.92] |
| fine_lo / fine_hi | 0.080 / 0.200 | Fine factors: 1 + (0.080..0.200) → [1.08, 1.20] |
| normal_pc | 0.120 | the bell: 1 ± 0.120 (three uniforms) |
| grade_cut | 0.070 | mean ≥ 1.07 → fine; ≤ 0.93 → poor; else no word |

Simulated over the fixed seeds 00000000-0276-4000-8000-00000000%06x, i = 1..1000 (offline md5,
reproducible): **Poor 47, Fine 50, standard 903**; every factor within [0.800, 1.200]; every
standard factor within [0.886, 1.113]. The self-assert's bands are 30–70 (the design's test).

## 4. The probe plan (what the self-assert proves, and HOW it can fail)

Every assert below names a property and has a positive control, so a vacuous pass is impossible.

- **(a) parity** — each of the twelve bodies, hunks reversed, equals its pre-image to the
  character; ACL/volatility/definer/search_path unmoved. Fails if a hunk no longer matches the
  deployed body (the chain is the check).
- **(b) nothing else moved** — one md5 over every other function in public/cmd/world/voyage;
  entry points and the grant wall as found.
- **(c) no backfill** — NOT EXISTS a ship laid down before this file whose roll ≠ 1.000 (positive
  control: the world HAS ships).
- **(d) byte-identity** — for EVERY hull: world.ship_stats = its pre-image as text; ship_view =
  its pre-image once roll/grade/class_* are stripped, and it DOES serve all seven (positive); for
  EVERY fleet: the ships array (world.fleets' source) = its pre-image with the keys stripped.
- **(e) the roll probes** (one sub-block, rolled back whole):
  - three probe hulls of one class (barca) with FIXED ids — 00000000-0276-4000-8000-%012x 0x101
    (standard, mean 1.027), 0x102 (Poor, mean 0.847), 0x010 (Fine, mean 1.157): the stored six
    columns equal ship_roll(id) to the digit; the same seed answers the same factors twice;
    two hulls of one class differ; every factor within the band rows (1 − poor_hi .. 1 +
    fine_hi); every EFFECTIVE stat inside her class's bounds (whole stats between
    floor(class × (1 − poor_hi)) and floor(class × (1 + fine_hi)), speed ± 0.01, crew max
    between what the class needs and floor(class × (1 + fine_hi))); a re-read of the same ship
    answers the same view while the clock demonstrably moves (anti-proof: no random(), no clock,
    in the read path); the grades read null / poor / fine.
  - a founding hull (crewed AND flagship) with id 0x001 (raw draw: hold 0.962, crew 0.922): every
    factor = greatest(raw, 1.000), the crew factor then clamped to ceil(needed/max to 3 dp) — and
    the raw draw is asserted to have had something to clamp (positive control).
  - a famous hull (first class_profile.tech 'F') with id 0x103 (its raw draw: normal, hold 0.975):
    all six read 1.000 although that seed's raw draw is NOT 1.000 — the skip is proven, not lucky.
- **(f) a thousand fixed seeds** — Poor and Fine each 30–70 (measured 47/50), every factor inside
  the bands, every standard factor inside ± normal_pc.
- **(g) the no-other-reader wall** — the AFTER scan (any body joining ship_classes with ships and
  naming c.hold/c.speed_kn/c.durability/c.crew_max/c.handling) allows only ship_base, ship_view
  and commission_ship; the BEFORE scan is asserted to have seen every named re-cut target (the
  scan can see).
- **(h) the one insert** — no live body other than commission_ship inserts into public.ships
  (positive control: commission_ship itself does), so the roll has one door.
- **(i) the wall** — the six new readings are server-only; the band table is readable by no
  client; the six default band rows are exactly as authored.

Nothing is DELETEd from append-only tables (nothing here touches events/ledger at all); every
probe sub-block rolls back; no count or sum of a growing table is asserted.

## 5. PROD CHECKS

**Before the push (read-only; in the PR body):**
1. The twelve live bodies are the ones the hunks were cut against — the md5s in §2
   (`md5(replace(pg_get_functiondef(oid), E'\r', ''))`, prod head must be 0272 or later before
   0276, and NO intermediate migration may have re-cut any of the twelve — the migration's own
   guard and hunk-once asserts enforce this at deploy).
2. `ships` has no roll_* column yet, and no `ship_variety` table exists (the guard).

**After the deploy:** no live figure moves — every roll is 1.000 and (d) proves the reads are
byte-identical, so nothing can drift. The first reading that anything moved is a NEW hull.

## 6. The after-check (30 minutes after the deploy, then once at 3 days)

- **30 min:** the deploy receipts green; `select count(*) from ships where roll_hold <> 1.000`
  returns the number of hulls commissioned since the push (0 expected in a quiet half-hour); spot
  one such hull (if any): her world.ship_view serves a roll equal to ship_roll(her id), her grade
  word matches the mean, and her stats sit inside the band bounds.
- **3 days:** watch human ducats/hour after V3 (the design's §6 risk): a Fine fleet earns about
  10–20 % more per real hour, the same scale as a skill level. If it reads unbalanced, the band
  ROWS are the knob (the owner decides; no code). No economy switch or world_config key was
  added by this slice.

## 7. Forward rollback (ready, not applied)

One forward migration: re-cut the twelve bodies back (every NEW hunk is in this file, verbatim,
and the parity proof shows they reverse to the pre-image), then `drop function` ship_base,
ship_roll, ship_roll_u, ship_grade, ship_variety_row, ship_variety_band and `drop table`
ship_variety, then `drop column` the six roll_* (a hull commissioned in the window loses her roll
and reads her class figures — say so in the rollback's header). Nothing else needs undoing: this
slice wrote no event, no ledger line, no config row, and no client state.

## 8. What the smoke caught, and what was changed because of it

An in-memory PGlite smoke (stub tables + the six new functions + the twelve re-cut bodies) ran
BEFORE the gates and caught one real bug: `(public.ship_base(s.id)).field` is a set-returning
call and Postgres forbids SRFs inside aggregates — `cmd.do_hire`'s berth sum and
`public.fleet_repair_due`'s sum/max would have failed at deploy. Both now read the base through a
scalar subselect (`(select sb.crew_max from public.ship_base(s.id) sb)`). The smoke also verified
the roll end-to-end: six fixed seeds equal the offline md5 simulator to the digit, the same seed
answers twice, ship_base and ship_grade compute as designed. It also exposed two self-assert
portability bugs fixed by eye: the reader scan now compares CANONICAL names
(schema || identity arguments — `regprocedure::text` renders with or without the schema
depending on search_path), and two `select * into %rowtype` targets over joins became
`select c.*`.

The smoke and the two scratch extractors were DELETED (the coordinator's rule: author-only
worktrees must not commit scratch tools; a PGlite boot on this PC collides with the chain).

## 9. The gate (run 2026-10-29, cached chain — `node scripts/db/proof.mjs standing`)

`chain: 262 migration(s) — 261 restored from the prefix cache (preamble-p0261-515581ffabcac2a2d2200326), 1 applied here — 262 with a self-assert receipt (268 receipt line(s)); chain key b47ce013af736370, 26.8 s` · world-guard ok · `proofs: 11_standing_route.sql — 5/5 PASS markers in 0.4 s` (ROUTE_CLIENT_PATH, ROUTE_AFK_LAPS, ROUTE_BOOKS_BALANCE, ROUTE_DARK, ROUTE_0096_DOOR).

The verbatim receipt:

> `0276 self-assert ok: EVERY NEW SHIP ROLLS HER OWN STATS. Twelve bodies reverse to their pre-images hunk by hunk (ACL, volatility, definer and search_path unmoved; commission_ship's signature gains the probe's id on purpose and stays server-only), every other function's md5 unmoved, the registry and the grant wall as found. No backfill: all 908 pre-existing hulls keep roll 1.000, and their world.ship_stats and world.ship_view answer the pre-image to the digit (908, hulls; 850, fleets), the new keys served on every hull. Probes rolled back: three hulls of one class with fixed ids — the stored roll equals ship_roll(id) to the digit, the same seed answers the same factors twice, two hulls differ, every factor within the band rows and every effective stat within her class's bounds, grades read null/poor/fine; a founding hull's factors are raised to 1.000 (raw draw had something to clamp); a famous hull reads 1.000 although her seed's raw draw is not. A thousand fixed seeds: Poor 47, Fine 50, standard 903, every factor within the bands, every standard factor within the normal ±. No other body reads a rolled class column joined to a ship (the before-scan saw every named reader), no other body inserts a ship. The new readings are server-only; the band table is client-dark. Probes took 1.0 ms.`

(The tier counts match the offline simulator to the seed — §3.)

**What the gate found, and what was fixed for it** (each was a defect in this file, not in the world):

1. The "nothing else moved" md5 joined the SIX NEW functions after their creation and so always
   differed — the before/after sets now exclude them by name (as commission_ship already was).
2. The three probe hulls shared ONE fleet and hit the live house-cap trigger E_FLEET_SHIP_MAX
   (2 ships a fleet) — each probe hull now has her own house and fleet.
3. The probe passed the house's auth_uid where the players PK was wanted (fleets_player_id_fkey)
   — the insert returns `id` again.
4. Three probe houses shared one company_name (players_company_name_key) — one name each.
5. The famous hull reused the Fine hull's fixed id (ships_pkey) — her own id 0x103 (raw draw:
   normal, hold 0.975 — the 1.000 is the legend, not luck).
6. The 1,000-seed "standard ±" check had a missing AND-precedence parenthesis and missed the
   fine-band exclusion — both bands are now excluded explicitly.
7. `pg_get_function_identity_arguments` returns argument NAMES, not bare types — the reader scans
   and their comparison lists now use `oidvectortypes(p.proargtypes)` everywhere, so the canonical
   name never depends on search_path or argument names.
8. The re-cut created the 7-argument commission_ship BESIDE the old 6-argument overload; the old
   one is now dropped after the re-cut (its six-argument callers resolve through the new default,
   and the one-insert scan stays exact).

## 10. The CI round (PR #392) — what CI found, and what was fixed for it

CI went red in two places, both real and both this slice's:

1. **`pglite-gate (the rest)` — proof 04** (`scripts/db/proofs/04_first_session.sql`): the
   FIRST_SESSION_OVERSIZED_REFUSED beat derived the room from the CLASS hold and the laden-speed
   beat rated the ship against the CLASS speed. A founding hull's roll is never below 1.000, so
   her hold and speed can read up to +20 % over the class's — the "+20" overflow could slip
   through, and a Fine hull's laden speed can exceed the class rating. Both now read HER OWN
   figures (`public.ship_hold_capacity` / `public.ship_base`), keeping each beat's intent.
   The same sweep fixed proofs 05 and 09, which hired `c.crew_max − s.crew` hands for a founding
   hull whose rolled berths can exceed the class's — they now hire to her own `ship_base` max.
2. **Acceptance shard 3/3 — `tests/format.spec.ts`**: `rollMark(1.005)` returned null because
   `1.005 − 1 = 0.004999…` in floats — the half point of the per cent was never reached. The
   function now rounds at the factor's own 3-decimal scale FIRST (`Math.round((f − 1) × 1000) /
   10`), which is the stored scale; the spec's boundary cases were corrected to the stored
   factors (1.004 → null, 1.005 → +1 %). The test was not weakened: it pins the same bracket
   semantics on the real inputs the server can serve.
   The same sweep found `tests/rpc.surface.spec.ts` pinned a founding Gaivota's served hold to
   exactly 60 × hold_scale — with the founding clamp that is now the LOWER bound; it asserts the
   band (classHold .. classHold × 1.2, the class figure read from the database, not copied).
   `tests/map.hulls.spec.ts` hard-codes ship figures too, but those are CLIENT-SIDE fixture
   objects the chart draws — never served — so they are untouched.

The full local proof run after these fixes: **12 file(s), 83/83 PASS markers, exit 0** — including
proof 04's FIRST_SESSION_OVERSIZED_REFUSED and FIRST_SESSION_SAILS, 05's balance, 09's walks, and
the 50 s merchant soak (12/12) — on the cached chain (261 restored + 0276 applied). The pure
`tests/format.spec.ts` rollMark test passes locally (the other seven local failures in that file
are the machine's Korean locale, known to pass on CI).

## 11. Deviations from the design doc, said plainly (D)

1. `ship_roll(seed, class)` is STABLE, not IMMUTABLE — it reads the band ROWS (the hard
   constraint wins over the design's word). Determinism is unaffected: the factors are stored at
   the commission, and a probe reproduces them from the id and the rows.
2. The tier is ONE draw per ship (the design's §2.1), so a Poor hull has every factor poor and a
   Fine hull every factor fine; the grade word can still differ from the tier (a lucky standard
   hull whose mean crosses ±0.07 grades fine/poor — the design's own grade rule).
3. Hold/hull/handling floor to whole numbers and speed to 0.01 kn in ship_base (the design's
   §2.1 "Clamps"), which is what keeps pre-existing hulls byte-identical — 32 × 1.000 must print
   '32', not '32.000'.
4. Founding clamp = "crewed AND flagship" (new_house's call, and an NPC house's first hull) — the
   design's "a new player's first hull", without a signature change beyond the probe's id.
5. `commission_ship` gains `p_ship uuid default null` — only the self-assert names it, for fixed
   probe ids; the design's probe "a probe build gives a row roll = ship_roll(its id)" needs it.
6. The yard line is one number per class (`variety_pct` = the widest normal_pc × 100) — the
   design's "±12 %" as data.
7. No Playwright tile spec was added: tests/map.shipPanel.spec.ts already renders the panel
   against the built world (all rolls 1.000 — it stays green and pins the byte-identity from the
   client's side); the % format has its own unit cases in tests/format.spec.ts (rollMark).
