# 2026-10-30 — 0283: a hull starts at her rolled max (commission_ship floors like ship_base)

**The slice:** ONE migration — `supabase/migrations/20260818000283_durability_starts_at_her_max.sql`.
No client, no test, no other function. It makes the stored starting durability of a new hull the exact
answer `public.ship_base` gives, instead of the unfloored product that starts a fractional-roll hull
above her own max.

**State while this is written:** AUTHORED and GATED on the local cached chain (receipt below), then
committed and pushed as a PR. **NOT deployed** — the main session deploys; the prod head must be
`20260818000282` and 0283 is the next number.

## 1. The root, measured

`public.commission_ship` (re-cut by 0276,
`20260818000276_every_new_ship_rolls_her_own.sql:460-464`) inserts a new hull's durability as

```
c.durability * (v_roll->>'durability')::numeric,
```

the EXACT product — a numeric with a fractional part whenever the md5-derived roll's third decimal is
not a multiple of 0.005 for an integer class durability. `public.ship_base(ship)` — the ONE authority
for her max (0276:377-397) — returns

```
floor(c.durability * s.roll_hull)
```

so that hull starts ABOVE her own max.

**CI, two runs on main, 2026-10-30:** `tests/rpc.surface.spec.ts:460`
(`expect(s.durability).toBe(s.max_durability)`) is red with **durability 405.6 against max_durability
405**, and **469.2 against 469**. The test is the founding `Gaivota` (Barca, class durability 400): a
roll of 1.014 stores 405.6, while `world.ship_view` serves `max_durability` = `ship_base` = 405.

**Prod (read-only, 2026-10-30, head 20260818000282):** 917 ships; every `roll_hull = 1.000`; **0**
stand above her max; **103** stand below it from wear (`durability < ship_base`). The defect is
therefore LATENT in today's world and guaranteed for the next hull whose roll product is fractional.

**Design:** `docs/SHIP_STORES_AND_VARIETY.md` §2.2 — a hull's starting durability IS her rolled max.

## 2. The one hunk

In `public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid)`:

```
          c.durability * (v_roll->>'durability')::numeric,
```
becomes
```
          floor(c.durability * (v_roll->>'durability')::numeric),
```

Nothing else moves: `public.ship_base` is not re-cut (it is the authority); every other function in
`public`, `cmd`, `world`, `voyage` is unmoved by md5; the function's ACL
(`{postgres=X/postgres,service_role=X/postgres}`), volatility (`volatile`), `SECURITY DEFINER` and
`search_path` (`public, pg_temp`) are asserted unmoved; no table, row, grant, knob, switch or client
moves. No existing ship is touched — every hull afloat carries `roll_hull = 1.000`, and for her the
product and its floor are the same integer.

## 3. The self-assert and its probe (how it can fail)

- **As found**: the live `pg_get_functiondef` text, its md5, ACL, volatility, `prosecdef` and
  `proconfig` are snapshotted; one md5 over every OTHER function in `public`, `cmd`, `world`, `voyage`.
- **The re-cut**: the old substring must occur exactly once and the new one zero times in the live
  body; the file executes the live text with only that substitution; the re-read body must equal the
  expected text (plain and md5); ACL / volatility / definer / config and the other-functions md5 must
  be unmoved.
- **The probe** (its own subtransaction, rolled back by the `ZX283` sentinel): a throwaway player,
  fleet and hull through the real doors (`public.form_fleet`, `public.commission_ship`). A fixed barca
  seed whose product is fractional is found by scanning 50 fixed ids through `public.ship_roll` — if
  none is fractional the probe RAISES rather than passing vacuously. The stored durability must equal
  `floor(product)` and equal `public.ship_base`'s durability; the stored `roll_hull` must equal the
  roll the probe computed; the product must be strictly above the floored value, so the old body would
  have stored a hull above her own max. After the rollback, the probe's own player / fleet / ship ids
  must not exist.
- **Receipt**: the closing `raise notice '0283 self-assert ok: …'` names the pre-image and new md5s,
  the function count under the other-functions md5, the fractional seed / roll / product, the stored
  durability and `ship_base`'s answer, and the prod-side latency.

## 4. The gate (local, cached chain — not a from-zero replay)

```
BYEHARU_PREFIX_CACHE=required node scripts/db/proof.mjs standing
```

`check-versions`: `OK: 271 migration(s) … 271 distinct version(s), no collisions, all filenames
well-formed.` The duplication spec (including "every migration proves itself…" and "a migration that
re-cuts an existing function declares the supersede…"): **11/11 pass**.

Gate (verbatim):

```
chain: 271 migration(s) — 270 restored from the prefix cache (preamble-p0270-087e415d485e7249d70282e8), 1 applied here — 271 with a self-assert receipt (277 receipt line(s)); chain key 33a5e0ff3abe8c28, 17.3 s
world-guard ok: the applied world EQUALS data/*.json (the planted-bend positive control fired)
✓ 11_standing_route.sql  — 5/5 PASS markers in 1.6 s
PROOFS PASSED: 1 file(s), 5/5 PASS markers seen
```

The migration's own receipt (recorded in the p0271 prefix-cache manifest, applied in 242 ms):

> `0283 self-assert ok: A HULL STARTS AT HER ROLLED MAX. public.commission_ship's one insert now stores floor(c.durability * her roll) — the exact answer public.ship_base gives — and nothing else moved: the body equals its pre-image with only that one substitution (as found md5 43640ad5239e5c93ef138945f58a3363, new md5 ffcd410853b0c497924207abf8c09799), ACL / volatility / definer / config unmoved, and every other function in public/cmd/world/voyage unmoved by md5 (661, functions). Probe, rolled back: barca seed 00000000-0283-4000-8000-000000000001 rolled durability 1.043, product 417.200 (fractional) — the pre-fix product was above the floored value; commissioned through the real door, the hull stores 417.00 = ship_base's 417 = floor(product); no probe row survived. Prod 2026-10-30 (head 0282): 917 ships, every roll_hull 1.000, 0 above her max — latent then, fixed for the next fractional roll.`

**Gate-found defect, fixed before commit:** the first run failed at 0283 with SQLSTATE 42601
("unexpected end of function definition") because the replacement needle omitted floor()'s closing
parenthesis (`...::numeric,` instead of `...::numeric),`). The needle was corrected, check-versions
re-passed, and the rerun above is green; the broken draft never reached prod.

## 5. PROD CHECKS (run before the push; read-only; the PR body carries this)

Head must read `20260818000282`; the live `commission_ship` body md5
`43640ad5239e5c93ef138945f58a3363`, with the unfloored product occurring exactly once and the floored
form zero times; its ACL `{postgres=X/postgres,service_role=X/postgres}`, volatile, `SECURITY DEFINER`,
`search_path = public, pg_temp`; `public.ship_base` body md5
`dc62cd9737495b8565ad5cbf4c13414d`, volatility `stable`; 917 ships, `roll_hull <> 1.000` = 0, above her
max = 0 (103 below from wear). The exact read-only file:

```sql
begin transaction read only;
with d as (
  select replace(pg_get_functiondef('public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid)'::regprocedure), E'\r', '') as def
)
select
  (select max(version) from supabase_migrations.schema_migrations) as head,
  md5(d.def) as commission_md5,
  md5(replace(pg_get_functiondef('public.ship_base(uuid)'::regprocedure), E'\r', '')) as ship_base_md5,
  (length(d.def) - length(replace(d.def, 'c.durability * (v_roll->>''durability'')::numeric', ''))) / length('c.durability * (v_roll->>''durability'')::numeric') as old_occurs,
  (length(d.def) - length(replace(d.def, 'floor(c.durability * (v_roll->>''durability'')::numeric', ''))) / length('floor(c.durability * (v_roll->>''durability'')::numeric') as new_occurs,
  (select p.provolatile from pg_proc p where p.oid = 'public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid)'::regprocedure) as commission_vol,
  (select p.prosecdef from pg_proc p where p.oid = 'public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid)'::regprocedure) as commission_secdef,
  (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid)'::regprocedure) as commission_acl,
  (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = 'public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid)'::regprocedure) as commission_cfg,
  (select p.provolatile from pg_proc p where p.oid = 'public.ship_base(uuid)'::regprocedure) as ship_base_vol,
  (select c.durability from public.ship_classes c where c.code = 'barca') as barca_durability,
  (select count(*) from public.ships) as ships_n,
  (select count(*) from public.ships where roll_hull <> 1.000) as rolled_n,
  (select count(*) from public.ships s where s.durability > (select sb.durability from public.ship_base(s.id) sb)) as above_max,
  (select count(*) from public.ships s where s.durability < (select sb.durability from public.ship_base(s.id) sb)) as below_max,
  (select count(*) from public.ships s where s.durability <> (select sb.durability from public.ship_base(s.id) sb)) as off_base
from d;
rollback;
```

Result, **2026-10-30** (head `20260818000282`): `commission_md5 43640ad5239e5c93ef138945f58a3363`,
`commission_vol v`, `commission_secdef true`, `commission_acl
{postgres=X/postgres,service_role=X/postgres}`, `commission_cfg {"search_path=public, pg_temp"}`
`old_occurs 1`, `new_occurs 0`; `ship_base_md5 dc62cd9737495b8565ad5cbf4c13414d`, `ship_base_vol s`;
`barca_durability 400`; `ships_n 917`, `rolled_n 0`, `above_max 0`, `below_max 103`, `off_base 103`.

**After the deploy:** no existing ship moves. The next hull commissioned with a fractional roll stores
`floor(class × roll)` = her `ship_base` durability. Watch:

```sql
select count(*) from public.ships s
 where s.durability > (select sb.durability from public.ship_base(s.id) sb);
```

— must stay 0; and for hulls created after the push,
`s.durability = (select sb.durability from public.ship_base(s.id) sb)` for every one.

## 6. Forward rollback (ready, not applied)

One new migration that replaces the floored line with the pre-image product
(`c.durability * (v_roll->>'durability')::numeric,`), re-cut by the same one-substring method, with
the same ACL / volatility / definer / config / other-function md5 asserts. Existing hulls keep their
floored values (no backfill); only hulls commissioned after the rollback would return to the product,
and the rollback's own probe must show the same fractional seed storing above `ship_base` again.

## 7. Files

- `supabase/migrations/20260818000283_durability_starts_at_her_max.sql` — the one slice.
This dev-log. No test, no client, no queue/owner row (this defect has no owner-instruction row; it was
found by CI).
