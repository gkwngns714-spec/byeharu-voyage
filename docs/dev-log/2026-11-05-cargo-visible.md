# 2026-11-05 - Cargo ships you can see, dark (migration 0310)

Migration `supabase/migrations/20260818000310_cargo_ships_you_can_see.sql` · proof `scripts/db/proofs/20_cargo_seen.sql` (and proof 18's two lines)
· mutation harness `scripts/ops/harness/cargo-ships/proof-0310.mjs` · design spec `tests/cargo.design.spec.ts`. Prod head when cut: 0309 (#489 is live). **Not deployed** (PR only). Dark: no ship, no switch, nothing changes in play.

## The order
V4 of `docs/CITY_CONVOYS.md`, owner-approved 2026-11-05: *"cargo ship? with different graphics. npc like merchants but different."*

## What I found that the brief did not say
**The client does not read `world.sea_traffic`.** It has read `world.sea_roster` since 0118. Fixing only `sea_traffic` would have drawn no ship at all. So both reads serve her. `sea_traffic` is fixed as well because it is the read that was named and the leak is real, but no client calls it.

## What was built
| Concept | The one place |
|---|---|
| Whose ships the sea shows, ink, kind | `public.sea_houses()`: both reads join it where they joined `npc_houses`, under the same alias |
| The hull | `hullPath` in `src/chart/glyphs.ts`, a 13th silhouette `cargo`, named by `CARGO_HULL` |
| A row becomes that hull | `mapTrafficOf` in `src/chart/liveWorld.ts`, from the served `kind` |
| Never thinned | `shipMarks` in `src/chart/shipMarks.ts` |
| Her card | `world.cargo_ship_card(fleet)`, `src/live/CargoSheet.tsx`, read through `useCargoShipCard` |
| Funds on the way | `public.funds_on_way(port)`, one term of `world.town_hall`; `src/live/FundsOnWay.tsx`, used by both halls |
| Funds at sea, ship count | `public.cargo_figures()`, one term of `world.stats_now`; a fifth card in Stats' live band; the Codex gate |

**The renderer is not forked.** `FleetsLayer.tsx` still has one `hullPath(`, one `HullGroup`, and never names her hull. Its only change is that she wears nation ink with the Regions filter off (`inked`), plus a `data-cargo-ship` hook on her alone.
**The crown is part of the path:** a second subpath wound the other way, so the default fill rule cuts it out of her deck. No attribute, no second `<path>`.

**The V2 list, closed:**
- `sea_traffic`'s `total` and `omitted`: she is now a row of the same total. No change to the count.
- `at_sea_merchants`: `stats_live_track` and `stats_live_fold` both leave her out. She stays in `at_sea`, because she is at sea.

## Decided by default (the owner may reverse any)
- **`kind` is on a cargo ship's row only, not on every row.** The brief said both "a kind per row" and "dark = byte-identical". Those cannot both hold, so byte-identical won: a merchant's row has no new key, and no `kind` means merchant.
- **A roster delta also carries a cargo ship that reached her eta since the last ask.** A merchant's delta is driven by her route; a cargo ship has none. Without this a ship idle at home stays drawn as sailing until the next full read.
- **Her ink is her nation's merchants' ink** (each of the 10 realms has exactly one on prod). A nation with no merchants would get `east`. None exists today.
- **Codex:** she is not a row of the list, because she is no class a company can buy and the list is served classes. A card at the top of the side column shows the hull, how many exist and one line, **only once a ship exists**. The face asks `world.stats_now` once on mount to know that, so the Codex makes one more read while dark. Nothing on screen changes.
- **The hall's line** shows only when a ship with funds is bound here, the city is short, and the switch is on. The figure is what she would pay it, not all she carries. It says how long while this is her next stop, otherwise how many stops first. A city only sees the nearest ship.
- **Stats:** the dev-logs do not require a line, section 5 of `CITY_CONVOYS.md` does, and it was cheap, so: "Funds at sea", served only while a ship exists. It is a part of Set aside, not a new sum.
- **`ShipTile`** gained an optional `hull` picture. Only `CargoSheet` passes one. She sails crewless by design, so her tile says 0/19 and is not shown as short of hands.
- **`sea_traffic_max` still caps `sea_traffic`,** so at the world view her rows can fall outside the 240, and `omitted` counts them. The client read has no cap.
- **Not done:** the open cargo ship draws no track on the map, and `world.port_merchants` does not list her. Neither was asked.

## The pictures
`docs/dev-log/2026-11-05-cargo-visible/`. A hull is the same CSS size at every zoom (`glyphs.ts`), so "map zoom sizes" are device pixels: `hulls-1x.png`, `hulls-2x.png` (the owner's laptop). Each has a merchant barca, carrack, galleon and flagship above three cargo ships, bow up, on a course, and 4× larger, on the chart's sea with the chart's keyline. They come from `hullPath` in an SVG page, not from the running map.

What they show, honestly:
- She is 18 x 14.4 px against the flagship's 16.6 x 9.5. She reads plainly as the biggest and widest thing on the water at 1×, and she is not mistaken for a merchant.
- **The crown:** at 2× it reads as a small crown. **At 1× it is a dark notch on her after deck**, not a crown you could name; on a course at 1× it is a smudge. It still marks her as different.
- **Her blunt bow gives her heading less clearly than a merchant's point.** Size and shape do the work, not the bow. Turned 62° you can tell which end is the stern from the step, at 2× more easily than at 1×.
- The pictures do not show her riding light or the day and night mix. The hole in her deck will show whatever is under her, which at night is her blue lamp.

`sheet-390.png`, `sheet-320.png`: the real `CargoSheet` with a **stub card, an empty world store and a Korean browser locale**, in a throwaway page, tray raised to full. So cities print as codes (`OPO`) and the mixed English is the stub's. They show layout only. No page scroll at either size (document scroll size equals the window at 390x844 and 320x568).

## PROD CHECKS (pure SELECTs from a file, one statement per file, before deploy)
Run 2026-11-05 about 05:30 UTC.

1. Head, and the seven bodies the hunks were cut against:
```sql
select (select max(version) from supabase_migrations.schema_migrations) as head,
  md5(replace(pg_get_functiondef('world.sea_traffic(jsonb)'::regprocedure), E'\r', '')) as sea_traffic,
  md5(replace(pg_get_functiondef('world.sea_roster(timestamp with time zone)'::regprocedure), E'\r', '')) as sea_roster,
  md5(replace(pg_get_functiondef('public.stats_live_track()'::regprocedure), E'\r', '')) as stats_live_track,
  md5(replace(pg_get_functiondef('public.stats_live_fold(timestamp with time zone,boolean)'::regprocedure), E'\r', '')) as stats_live_fold,
  md5(replace(pg_get_functiondef('world.town_hall(uuid)'::regprocedure), E'\r', '')) as town_hall,
  md5(replace(pg_get_functiondef('world.stats_now()'::regprocedure), E'\r', '')) as stats_now,
  md5(replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '')) as entry_points
```
-> `20260818000309`, `a6f56858c1778c5a24d58e475034ab42`, `1c60e295a5f1efcf67bdaec671ead652`, `f11bce7f21b81fe55891f0253299a344`, `31379397f9c729c57250a41e50cb2b0b`, `40d8315a9f46aa580af669e03e91b456`, `00b70324f22fd246657281acdabf18a4`, `d61f4faeab485ef8fb1394a5e1cfb6f7`. The cached local world gives these same seven.

2. Names free and the self-assert's facts:
```sql
select to_regprocedure('public.sea_houses()') is null and to_regprocedure('public.funds_on_way(uuid)') is null
  and to_regprocedure('public.cargo_figures()') is null and to_regprocedure('world.cargo_ship_card(uuid)') is null as names_free,
  (select count(*) from public.ports p where p.code like 'QV_') as ports,
  (select count(*) from public.nations n where n.code = 'QX0') as nations,
  (select count(*) from public.cargo_ships) as ships,
  (select value from public.world_config where key = 'convoys_enabled') as lit,
  public.npc_traders_on() as traders,
  (select string_agg(p.provolatile::text, '' order by p.oid) from pg_proc p
    where p.oid in ('world.sea_roster(timestamp with time zone)'::regprocedure, 'world.sea_traffic(jsonb)'::regprocedure, 'world.town_hall(uuid)'::regprocedure, 'world.stats_now()'::regprocedure)) as reads,
  (select count(*) from (select 1 from public.npc_houses h group by h.player_id having count(*) > 1) x) as dup_houses,
  (select count(*) from public.players p where p.company_name like 'Crown Cargo %') as cargo_names
```
-> true, 0, 0, 0, false, true, `ssss`, 0, 0. Ten realms, one ink each.

3. What the self-assert reads, for its budget (both stable):
```sql
select jsonb_array_length(world.sea_roster(null) -> 'fleets') as roster_rows,
  (select jsonb_array_length(t -> 'fleets') from world.sea_traffic('{"south": 34, "north": 42, "west": -14, "east": -2}'::jsonb) t) as window_rows
```
-> 837, 209. The whole CLI call took 5.0 s against 3.6 s for `select 1`, so about 1.4 s for one of each. The self-assert makes about four whole-roster reads and five window reads, so a few seconds against its 45 s budget. An estimate from that one call.

Deploy: `~/bin/bv-deploy.sh <pr>`. After it, still dark (all `s`, safe to select):
```sql
select public.cargo_figures() as figures, (select count(*) from public.sea_houses()) as houses, (select count(*) from public.npc_houses) as npc_houses,
  jsonb_array_length(world.sea_roster(null) -> 'fleets') as roster, (select count(*) from public.client_rpc_entry_points() e where e.function_name = 'cargo_ship_card' and e.fn is not null) as card
```
-> `{}`, houses = npc_houses, roster about 837, 1.

## Before anyone lights it (owner only; not this slice)
V4 was listed as a condition in `docs/dev-log/2026-11-05-cargo-funds.md`. It is met once this is live. The rest of that file's warning stands: lighting stops instant aid at the next `:37`, cities late on a circuit wait up to 5 hours, and no player may hold a `Crown Cargo %` name (0 today).

## Tests
- **Red first:** `tests/cargo.design.spec.ts` written before the code. First run: it could not load, no `CARGO_HULL`. With the glyphs in: 11 pass, 2 red on the missing words. Then 13 of 13.
- **Mutations** (`BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/cargo-ships/proof-0310.mjs`, cached world at 0309, 294 of 294 restored, no from-zero replay): **23 broken files, each red for its intended reason, the real file green,** 350 to 380 ms on PGlite.
- **What the red pass caught:** three mutations first PASSED. "stats_now has no figures" and the funds checks used `<>` on a value that could be null, so a missing key passed; they are now `is distinct from`. "Promises the capital" passed because the capital was rich, so the probe now drains it. "Helper open to clients" was a bad mutation: a revoke removed does nothing here, so it now grants.
- **The first apply caught:** the self-assert's dark comparison was comparing two empty answers, because `npc_traders_on` also needs `standing_routes_enabled`. Dark compares now force both on, as prod has them.
- **Proof 20** (`node scripts/db/proof.mjs 20_`, 8/8 markers), lit over the whole local world, rolled back: merchant rows the same array as before any ship existed; 50 ships with kind, one hull, nation ink; a window round her serves her; the card says 98,000 d. to OPO, then five stops, 24 left, and refuses a merchant; next stop 49,000 d., the stop after waits; a city not short, the capital and the switch off say nothing; funds at sea inside Set aside; the real fold with her at sea, drift 0; a real `voyage.settle` arrival in the next delta and not the one after (the eta is moved behind the proof's fixed clock for that one check).
- Proofs 18 (6/6, its two lines rewritten: she is now served on purpose), 19 (9/9), 03 grants (12/12).
- `tsc -b`, `eslint` on the touched files, `vite build` clean. `tests/i18n.keys.spec.ts`, `tests/duplication.spec.ts`, and the 29 registry tests of `tests/rpc.surface.spec.ts` pass; that spec's RPC pin was moved on purpose.

## Not verified
- **No cargo ship has been seen in the running game.** The hull was never drawn on the real map, a tap on her never opened the sheet, and `MapScreen`'s branch has only been compiled.
- **The hall line, the Stats card and the Codex card have not been seen rendered.** The server side is proved; the React is compiled only. The sheet was seen with a stub card only.
- **The merchant path in a browser:** `MapScreen` and `FleetsLayer` changed. The specs that drive them need a served build and were not run here. CI's acceptance is the net.
- `disposable-chain`: CI runs it on this PR. The self-assert's real time on prod.
- The roster's cost once ships sail: at most 50 more rows, and hers carry whole leg courses. Not measured.
- Weather, bunching, the wait at lighting: as in the funds dev-log.
