# 2026-10-18 — 0167: S18, merchants of every flag — `osn-s18-merchants`

`docs/SHIPS_AND_SKILLS.md` §8 row S18 (§5.1 "S18 seeds their hull skills the same way, once", §6.9;
`docs/SKILLS_AND_CAPTAINS.md` §9). **Not deployed.** Stacked on S17 (#184, 0166); number 0167 (prod head 0164, K9 0165, S17 0166;
renumber if the head moves). Hunks checked to occur exactly once in production's live bodies (`public.npc_found`,
`public.npc_fit_loadout`; read-only `pg_get_functiondef`, re-checked at prod head 0164, 2026-10-18). **This one touches live
merchant data**: 62 merchant hulls change class when it is pushed.

- **The one rule**: `scripts/build-ships.mjs` `merchant` (`MERCHANT` bounds), loaded as `public.npc_line_hulls` and
  held by the world guard (with a planted-drift control). For each live class and each other line it picks the
  line's T1 hull that meets all of these: cargo space within ±10 %, speed within ±5 %, **no more crew required and
  at least as many allowed** (so a merchant's crew, her wages and her endurance stay exactly as they are), and
  every rack and Deck at least the live class's (so every pattern still fits). The nearest one wins. Read by ONE
  sentence, `public.npc_hull_for(class, port)`: the line hull of the country that holds the port today, or the
  class itself.
- **The five line hulls the bounds admit**: barca → Crayer (ENG) and Barque (FRA); caravela latina → Caravelle
  normande (FRA); nau → Levant Merchantman (ENG) and Navire marchand (FRA). No other line has one: a fluit is
  +25 % cargo space on a nau, a junk +15 %, an urca or a jounseon needs more crew, a dhow carries fewer.
- **Founded so**: `npc_found` commissions `npc_hull_for(class, her house's home)` at all three sites. After
  `npc_fix_level`, it calls `public.npc_fix_hull_skills` (the four live skills still set her hulls' level).
- **Her gear**: `npc_fit_loadout` reads the patterns of the live class a line hull stands in for. Nothing is
  copied into `data/npc-loadouts.json` (a `_s18` note says so).
- **Converted once**: every merchant hull whose house's home country has a line hull for her class gets the new
  `class_id`, and her hull points are kept in proportion. A hull whose cargo would not fit the new hold is left as
  she is and counted (none were in the local world). Each change is recorded in `public.npc_hull_conversions`,
  which a rollback restores from. Crew, gear, seats, cargo, voyage and orders are untouched.
- **Hull skills, fixed once**: `npc_fix_hull_skills(player)` raises every hull-skill level her hulls ask for,
  through `raise_skill` at her home harbour. Each level is endowed first (credit `FOUNDING`), as `npc_found`
  endows its founding tuition, so her purse ends where it began. No queue row.
- **Captains**: `npc_found` already seats through `seat_captain_for`, because `post_officer_to` has called the
  seat core since 0157. Nothing moves, and `crew_pct` per merchant fleet is asserted unmoved.
- **Client seam**: the voyage tray's hull strip named a class it had no word for by its code ("1 carnorm"). It
  now prints the served class name (`src/features/map/VoyageTray.tsx`).

## Proof (in the migration; cached-prefix build, local world = a fresh chain)

```
0167 self-assert ok: … THE RULE: 5 line hull(s) (barca → crayer (ENG), nau → levanter (ENG), barca → barque (FRA),
carlat → carnorm (FRA), nau → navire (FRA)). CONVERTED: 62 merchant hull(s) (barca → barque 11, barca → crayer 6,
carlat → carnorm 37, nau → levanter 4, nau → navire 4), 0 left as they were (cargo would not fit), across 58 merchant
fleet(s) — every merchant fleet's speed within ± 5 %, cargo space within ± 10 %, crew (wages) exactly as before,
status and captains unmoved; every converted hull's crew, gear, seats and cargo inside her new hull. HULL SKILLS: 57
house(s) fixed once (157500 d. endowed and paid to their home harbours), no queue row, merchant purses unmoved.
FOUNDED (rolled back): at BRS an English company sails ["crayer", "carlat", "levanter"] with {"ENG_LIGHT": 3,
"ENG_SMALL": 1, "ENG_MEDIUM": 1}; at ACC a Portuguese one the live three. NO PLAYER ROW MOVED. LAPS before …
READS: ship_view over 892 merchant hull(s) 1797 ms → 1573 ms; speed+hold 457 ms → 509 ms
```

The local image has no closed merchant laps (merchants are dark there), so the lap pre-image reads 0. On prod
the receipt prints the zero-net share and mean lap hours of every merchant fleet's last ten laps. The
after-figure is the same query a day after the push:

```sql
select count(*) laps, round(100.0*count(*) filter (where net<=0)/greatest(count(*),1),1) zero_net_pct,
       round(avg(extract(epoch from closed_at-started_at)/3600.0)::numeric,2) mean_hours
  from (select l.*, row_number() over (partition by l.route_id order by l.closed_at desc) rn
          from public.standing_route_laps l join public.npc_fleets nf on nf.route_id=l.route_id
         where l.closed_at is not null) l where rn<=10;
```

## NOT the owner's — confirm

1. **The crew condition** (no more crew required, at least as many allowed). §8 bounds only cargo space and
   speed. This condition is the brief's "wages within ±10 %" made exact (wages unchanged) and keeps any merchant
   from being stranded short of hands. It is also why only English and French merchants change.
2. **"The sea shows Dutch fluits in the Baltic, junks off China" does not happen** under §8's own bounds. Widening
   the cargo space bound to 25 % would admit the fluit and the junk, but it would also move lap economics past the
   ±10 % the row asserts. The owner decides.
3. **157,500 d. is new money**, endowed to 57 merchant houses and paid on to their home harbours' purses as hull
   skill tuition (the founding pattern). The alternative is that merchants pay from their own purses, which would
   cut what they can buy.
4. Hull skill levels are exactly what the hulls' build requirements ask (e.g. English Light III + Medium I for a
   Levant Merchantman). They are dark: nothing reads them while `skills_bite` is off.
5. The house's home port (not each fleet's first stop) decides the country.

## Verification (once, fresh worktree, real `npm ci`, no `.env.local`)

- Cached-prefix `npm run build`: 155/157 restored, 0166 + 0167 applied in 74 s, world guard ok (including the new
  merchant line hulls check and its planted-drift control); both receipts printed (above).
- `tsc -b` 0, `eslint .` 0, `build-ships --check`, `db:check-versions` ok.
- The CI selector's 30 specs (growth test deferred, as CI does), run on `vite preview --port 4243` on `localhost`
  (built before the renumber; the renumber touched only file names and comments): **228 passed, 2 failed, 0
  skipped**. Both failures are already red on main and are not from this slice: `duplication.spec.ts:183` and `:356`
  (the same two as S17's run).
