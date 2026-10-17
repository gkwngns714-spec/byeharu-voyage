# 2026-10-18 — 0166: S17, the famous ships (Wave D) — `osn-s17-famous`

`docs/SHIPS_AND_SKILLS.md` §8 row S17 (§4.1 the famous tech, §4.3 Wave D, §4.4 the famous requirements, §6.2's
Famous rung; `docs/SKILLS_AND_CAPTAINS.md` §9: S17 unchanged). **Not deployed; dark** (every new subject has
requirements and `skills_bite` is off). Number provisional (prod head 0164, K9 takes 0165, so S17 is 0166).
Built on main `20845c3` (S16 merged). Hunks checked to occur exactly once in production's live bodies
(`cmd.do_build` 0154, `world.building_yard` 0159; read-only `pg_get_functiondef` through `db query --linked`,
2026-10-18); neither S16 nor K9 touches either body.

- **11 famous hulls** — `scripts/build-ships.mjs` Wave D (`WAVE_D`): archetype × line × ONE famous uplift by role
  (`TECH.F`), measured against §4.3's eleven rows: every famous hull speed × 1.03; trade hold × 1.25, hull × 1.15,
  attack × 1.10, handling +2, armour +6, sighting +1, +1 Low; combat attack × 1.40, hull × 1.20, handling +4, armour
  +10, accuracy +8, sighting +1, +1 High; explorer speed × 1.06 more, hull × 1.10, handling +10, armour +2, accuracy
  +4, sighting +5, +1 Mid; labour × 4; goods × 2.2 + lignum vitae (9 a medium template, × the size factor) + sea
  charts 2; deck by T2's one rule. One new archetype, the heavy explorer, solved from the San Juan Bautista row.
  Every stat, crew, hull, draft and rack cell of the table reproduces; the deck cells of the capitals, flagships and
  the Golden Hind and the goods / labour of the ten hulls the shed caps do not — the generator wins (written under
  the table in §4.3). The shed rule's floor now keeps at least 1 of a good (two sea charts would otherwise floor to
  nothing); no Wave A-C hull moves (all 89 compared byte for byte with main's generated file).
  Requirements: ⟨size⟩ Hulls V + Famous Ships I + the role's T2 specialisation III (33 rows).
- **The history line** is the hull's `hull_recipes.note` (one sentence each, the ship's history); the build yard
  already serves `note`, and its tray now prints it for a famous ship (`src/features/port/PortYard.tsx`,
  `data-testid="yard-history"`). The **Famous** badge was already in `src/live/HullTech.tsx` (S15 wrote it for
  tech `F`).
- **11 pieces of famous gear** — `scripts/build-gear.mjs` `FAMOUS` (the one home of "which famous ship's gear this
  is": the ships generator reads `hull` from it): the Famous rung (meta 8, grade 5) of one base type each, the G1's
  buys × 3.00 (speed / cargo space × 2.00), spends × 1.00, Drake's Culverins' accuracy +12 (§6.4, asserted 180 / 45 /
  +12); Deck and Hands × 1.6; needs the module skill V + Famous Ships I; made at a tier-3 workshop of the base
  type's T2 recipe × 1.5. Each is its hull's ONE fitting (`hull_recipe_items`, 11 rows), spent when she is laid
  down. The world guard now holds the generated hulls' fittings as it holds the live three's.
- **One of each to a house** — `public.famous_held(player, class)`, the one sentence ("Golden Hind is a famous
  ship, and a company keeps only one of each: yours is the Pelican.", or null), read by `cmd.do_build` (refuses
  `E_FAMOUS_HELD` after the skills check; a famous hull takes the company's `players` row first so two orders
  of one company cannot both pass) and `world.building_yard` (folded into `buildable`, served as `famous_held`
  only where it applies — every other entry is its pre-image to the byte). The yard tray prints it.
- **Proof** (in the migration, its own company, rolled back): dark, all 11 refused `E_NEEDS_SKILL` with the dark
  reason; lit with the skills, all 11 built for their labour; with a Golden Hind kept, a second refused in the one
  sentence (the yard serves the same and closes her), a Turgut Reis's Kadırga and a second barca still built, the
  Hind's one piece of gear spent; Drake's Culverins dark refused, lit refused "needs Famous Ships I" with figures,
  then made. Counts are of this file's own 11 + 11 codes only (0163's lesson).

## NOT the owner's — confirm

1. **The famous gear is MADE, not given.** §6.2 says the Famous rung is "made at —, comes with the famous hull".
   §8 says "famous gear as `hull_recipe_items`", and 0072 (b) (the owner's row 58) refuses a hull fitting that no
   city can make. So each piece is made at a tier-3 workshop (needs its module skill V + Famous Ships I), and the
   hull's recipe spends it. A company could make more pieces than it has famous ships and fit them elsewhere —
   nothing here stops that.
2. **Which base type each piece is, its name and its recipe** (T2 recipe × 1.5) — only Drake's Culverins is in the
   plan; the other ten are chosen to the hull's added rack and history.
3. **A second buy only on Drake's Culverins** — §6.4 names one; the other ten carry the rung's multipliers only.
4. **The famous uplift numbers** are read off §4.3's table (it states only "labour × 4, lignum vitae + sea charts").
5. **`E_FAMOUS_HELD`** is a new refusal code and the lock on the company's row is a new step in the door (only for a
   famous hull).
6. **The history line is the yard tray's only.** The Codex's ship tray does not print it: the snapshot does not
   carry `hull_recipes.note`, and re-cutting `world.snapshot` for one sentence was not in the row.

## Verification (once, fresh worktree, real `npm ci`, no `.env.local`)

- **Cached-prefix build** (`npm run build`): restored 155/156 from the prefix cache, applied 0166 alone in 78 s
  (whole build 1 m 36 s); world guard ok (103 ship classes, 225 items, generators re-run = files = database). Receipt:
  `0166 self-assert ok: A FAMOUS SHIP IS ONE TO A HOUSE … DARK: 3220 old yard entries and 14981 old workshop entries as
  before; … 11 refused through the door. LIT (rolled back): 11 BUILT for their labour; a second Golden Hind refused
  "Golden Hind is a famous ship, and a company keeps only one of each: yours is the Pelican." (the yard says the same
  and closes her), a Turgut Reis's Kadırga and a second barca still built; Drake's Culverins refused "E_NEEDS_SKILL:
  Drake's Culverins needs Famous Ships I", then made. 2 bodies reverse, no entry point. READS: ship_view over 892
  merchant hull(s) 1718 ms → 1620 ms; speed+hold over 892 merchant hull(s) 552 ms → 495 ms` (wasm; noise).
- `tsc -b` 0, `eslint .` 0.
- **Specs the CI selector picks** (`scripts/ci/select-specs.mjs`, 13 files, growth test deferred to main as CI
  does) against `vite preview --port 4242` on `localhost`: 105 passed, 3 failed, 0 skipped. One failure was this
  slice's — `rpc.surface.spec.ts:100` pinned "11 capitals, 4 flagships" (a seed-shaped assert); it now counts sizes
  5 and 6 from `data/ships.generated.json` and checks one famous ship a line, and passes. The other two are on main
  already and touch nothing here: `duplication.spec.ts:183` (a class recipe shared by `live/CrewBonuses.tsx:18` and
  `live/ShipPanel.tsx:329`) and `duplication.spec.ts:356` (0160 / 0161 re-cut functions without "supersede" in their
  headers — deployed files, not edited here).
