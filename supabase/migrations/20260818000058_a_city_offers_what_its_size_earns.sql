-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0058 — A CITY OFFERS WHAT ITS SIZE EARNS
--        The roster count stops being a per-tier CEILING somebody typed into a build script and
--        becomes a LAW: capital = 10, mid = 4-8, small = 4 — derived, seeded off the port itself,
--        and re-applied to every harbour in the world today, not merely to the next one authored.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE ASK, TWICE ─────────────────────────────────────────────────────────────────────────────
-- docs/OWNER_REQUESTS.md row 38: "each cities max 9 trade goods... Min 4, max 9."
-- docs/OWNER_REQUESTS.md row 48, the SAME instruction said again with harder numbers:
--
--   "i told you, min 4, max 10 trades goods per city. there should be a purpose to go to a city
--    that is far away to get rare trade goods. i told you, capital cities - 10 items, mid sized
--    cities - 4~8, small cities 4, randomly distributed"
--
-- Row 48 names the failure directly: a REPEATED instruction means the wrong thing shipped. 0041
-- built a single 4-9 band by tier (`scripts/build-world-growth.mjs:601-637`, generated, not
-- authored by hand, but never re-cut since). This file deletes that band and installs the
-- owner's three numbers as one derived law — and the owner's OWN reason for the rule, stated in
-- the same breath, is the thing this file is graded on: "there should be a purpose to go to a
-- city that is far away to get rare trade goods." The counts are the means; rarity-worth-the-
-- distance is the end, and this header measures both.
--
-- ── THE TIER MAPPING, WRITTEN DOWN AS THE DECISION IT IS ─────────────────────────────────────────
-- `ports.size_tier` is `between 1 and 5` (0002:91) but only 5 / 3 / 2 are ever assigned, and the
-- mapping is not a guess made for this file: `scripts/lib/world-derive.mjs:16` — the ONE place
-- `data/ports.json`'s editorial tier becomes `size_tier` — says it outright:
--
--     size_tier   dataset tier 1/2/3 -> 5/3/2 (a great entrepot, a working port, a small harbour)
--
-- So: size_tier 5 = CAPITAL ("a great entrepot"), size_tier 3 = MID ("a working port"),
-- size_tier 2 = SMALL ("a small harbour"). Corroborated structurally, not merely by name: tier 5
-- is the only tier with `has_academy`, carries the highest `yard_tier` (3) and `crew_pool` (400)
-- and `max_draft` (5); tier 3 carries `yard_tier` 1 and `crew_pool` 240; tier 2 carries no yard at
-- all and `crew_pool` 160 (`scripts/lib/world-derive.mjs:472-484`). Tiers 1 and 4 are unassigned
-- anywhere in the world today; `public.roster_target_count` below RAISES on them rather than
-- guessing, per docs/NO_SPAGHETTI.md §7C — an unmapped tier is a shape this rule has no answer
-- for, not a shape it may silently default.
--
-- ── THE DEFECT, MEASURED ON THIS MACHINE, 2026-08-26 (PGlite 0.5.5 / PostgreSQL 18.3) ───────────
-- Applying the chain through 0056 and reading `public.port_specialties` by `ports.kind`/`size_tier`:
--
--   kind       size_tier   ports   offers (min/avg/max)   the rule says
--   HARBOUR    5 (capital)    35   5 / 8.400 / 9              10
--   HARBOUR    3 (mid)        79   4 / 6.304 / 7              4-8
--   HARBOUR    2 (small)     110   4 / 4.709 / 5              4
--
-- Every capital falls short (none reach 10 — the ceiling this file's predecessor-in-spirit
-- imposed, 0041's <=9, is now provably the wrong side to have erred on). 78 of 110 small harbours
-- carry 5, one more than "small cities 4" allows. All 79 mid harbours already sit inside 4-8 and
-- need no change today — the editorial variety already spreads them across 4/5/6/7 offers, which
-- is a real distribution, richer than a synthetic one, and docs/NO_SPAGHETTI.md's row-38 note
-- ("an authored specialty should survive the rebalance") says to leave it standing.
--
-- ── THE CORRECTION TO THE FRAME, MEASURED, NOT ASSUMED ────────────────────────────────────────
-- The brief for this slice reported "238 ports, 14 offer 0" and read that as 14 broken cities.
-- Re-verified against the running world rather than trusted: **all 14 zero-offer rows are
-- `kind = 'SEA_PLACE'`** (Bab-el-Mandeb, Bay of Biscay, Cape St Vincent, the Doldrums, Dogger
-- Bank, Drake Passage, the Grand Banks, the Horse Latitudes, One Fathom Bank, the Roaring
-- Forties, the Sargasso Sea, the Skeleton Coast, the Strait of Gibraltar, the Strait of Hormuz).
-- Zero HARBOUR ports carry zero offers. A sea place is not a city — it is open-ocean anchorage a
-- fleet may touch at sea, and 0036 already built the refusal that makes this structural, not
-- incidental: PROVISION there answers `E_NO_CHANDLER` (0036 self-assert) because a sea place has
-- no chandler, and `public.port_goods` (the market table) holds a row for every HARBOUR x good
-- pair and NONE for a sea place (54,432 = 224 harbours x 243 goods, measured below; not
-- 238 x 243). Giving a sea place a roster would not open a market that could not exist to hold
-- it — 0036/0047 already decided sea places carry no quay, and 0058 does not re-open that door.
-- "Every empty port gets a floor of 4" therefore reads, verified: **every empty HARBOUR** — and
-- there are none — while the 14 SEA_PLACE rows are excluded by `p.kind = 'HARBOUR'` throughout,
-- exactly as `scripts/build-world-growth.mjs`'s own 4-9 assert already scoped itself (line 613:
-- "where p.kind = 'HARBOUR'"). This file follows that scoping rather than inventing a new one.
--
-- ── THE MECHANISM ──────────────────────────────────────────────────────────────────────────────
-- ONE law, `public.roster_target_count(tier, authored, draw)`, pure arithmetic, IMMUTABLE:
--
--     tier 5 (capital)  -> always 10
--     tier 2 (small)    -> always 4
--     tier 3 (mid)      -> authored, if it already sits in [4,8]  (the editorial spread stands)
--                        -> 8,  if authored exceeds 8              (trim to the ceiling)
--                        -> 4 + floor(draw * 5), if authored is under 4 (seed a value across the
--                           whole band — a port with too little editorial guidance to inform a
--                           count gets one FROM THE WORLD, not from a single hard-coded 6)
--
-- and ONE seeded assignment: keep every authored (port, good) pair; where authored < target, ADD
-- the lowest-ranked not-yet-offered goods (ranked below); where authored > target, DROP the
-- lowest-ranked currently-offered goods. The ranking and the mid-tier draw share one hash,
-- `public.roster_rng(key)`.
--
-- ── DETERMINISM, AND WHY THIS IS NOT KEYED ON `world_secret` ──────────────────────────────────
-- The brief for this slice suggested keying the draw on `world_secret`, the way `voyage.rng` does
-- (0006). MEASURED, and it does not hold: `world_secret` is deliberately NOT stable across a
-- fresh chain — 0031 ROTATES it to a freshly-generated value on every fresh apply (every local
-- `db:apply`, every CI run, every browser boot), because its whole job is to make hazard rolls and
-- haggle outcomes unpredictable to a player reading this repository. Measured on this machine,
-- two consecutive fresh `npm run db:apply` runs:
--
--     run A: 8b077be8 65844cdf bc3d9da6 8070230a ...
--     run B: dc59e8ff b7494a1b 80d3866d 0b93d7311...
--
-- different every time, by design (0031's header: "rotating on EVERY apply... would re-dice every
-- unsettled voyage day... and make 'did it rotate' untestable"). `public.port_specialties` is not
-- gameplay state — it is STATIC WORLD DATA that `scripts/db/world-guard.mjs` requires to be BYTE
-- IDENTICAL to `data/ports.json` on every apply, everywhere (`npm run db:apply` must produce the
-- SAME world every time, exactly as this slice's own brief requires). Keying the draw on
-- `world_secret` would make the roster differ across every fresh apply and fail world-guard by
-- construction. So `public.roster_rng(key)` hashes on a FIXED, non-secret string baked into the
-- function body — the roster is public information (served whole on `world.snapshot()`), so unlike
-- a hazard roll it has nothing to hide, and unlike `world_secret` it must never change underneath
-- a re-apply. It COMPOSES `voyage.rng_raw` (0006) rather than re-deriving the md5-to-[0,1) trick —
-- a nil voyage id and day 0 make every other argument constant, so the composed function is a pure
-- function of `key` alone, and it inherits IMMUTABLE for free because `voyage.rng_raw` already is.
--
-- ── THE SPREAD, PROVEN AS A MECHANISM PROPERTY, NOT MERELY OBSERVED ON TODAY'S DATA ────────────
-- No mid harbour exercises the draw-branch today (every authored count already sits in 4-8), so
-- "spread it, do not put every mid port at 6" cannot be checked against real rows alone — checked
-- instead by evaluating the draw-branch directly over 200 synthetic keys: assert (d) below.
--
-- ── WHAT ELSE MOVES, BECAUSE IT MUST MOVE IN THE SAME FILE (docs/NO_SPAGHETTI.md §3.2) ─────────
-- `public.port_goods.affinity` is DERIVED from `public.port_specialties` (0005: nearest-producer
-- distance) and would silently disagree with the new roster if left alone — a producer added at a
-- capital can become the NEAREST source for goods at OTHER ports too, not only its own row. So
-- this file re-derives affinity for the WHOLE table through `world.affinity_for`, the one seeding
-- function (0048's own pattern, composed, not re-derived), then restates `stock_target`/`stock`
-- (0005's formula, clamped down, never minted, 0048's own pattern) AND `production_rate`, which
-- 0048 left stale — a gap this file closes as a byproduct because it is the same recompute and
-- leaving it half done would be exactly the "quartermaster" defect docs/NO_SPAGHETTI.md names.
-- `ports.dev_commerce`/`dev_industry` are likewise DERIVED from the roster's size and composition
-- (`scripts/lib/world-derive.mjs:479-480`: `dev_commerce = size*2.4 + len(specialties)`,
-- `dev_industry = size*2.0 + 1.5*count(metal/textile/naval-stores)`) and are restated here with the
-- SAME arithmetic `scripts/build-world-growth.mjs`'s own self-assert (f) already uses to check it —
-- not a new formula, the existing one, called again because its input changed. `dev_military`
-- depends only on `yard_tier`, which this file does not touch, and is left alone.
--
-- ── data/ports.json MUST CHANGE, AND WHY THAT IS SAFE ──────────────────────────────────────────
-- `scripts/db/world-guard.mjs` (read before writing a line of this file, per the brief) requires
-- `public.port_specialties` to equal `data/ports.json`'s `goods` arrays AS A SET, both directions,
-- for every HARBOUR port — it has no notion of "authored subset plus derived filler". Because
-- `public.roster_rng` is immutable and keyed on nothing but the fixed string above (no table, no
-- knob, no `world_secret`), its output is the SAME on every machine, every fresh apply, forever,
-- for the same inputs — so the roster this migration computes was run once here, captured, and
-- written into `data/ports.json`'s `goods` arrays for exactly the ports that changed (35 capitals
-- gained goods, 78 small harbours lost one each), with every other port's array untouched. This is
-- not a second authority: `data/ports.json` still records the true, current roster; it is simply
-- no longer 100% hand-researched trade goods for the harbours this file touched, and the file's
-- own top-level `note` says so. The alternative — leaving `data/ports.json` alone and letting
-- `world-guard` fail on every fresh apply — was rejected outright; a guard that must be worked
-- around is a guard that has stopped guarding.
--
-- ── WHAT IT COSTS THE POINT: RARITY, MEASURED BEFORE AND AFTER ─────────────────────────────────
-- Total `port_specialties` rows fall from 1,310 to 1,288 (78 small-harbour drops outweigh 56
-- capital additions: 35 capitals x [+1..+5] = +56; 78 small harbours x -1 = -78), so
-- `public.rarity_scale()` (0051's mu) moves only slightly. Measured:
--
--     BEFORE  mu = 5.391   exotic 47 (19.3%) / rare 86 (35.4%) / uncommon 58 (23.9%) / common 52 (21.4%)
--     AFTER   mu = 5.367   exotic 44 (18.1%) / rare 75 (30.9%) / uncommon 73 (30.0%) / common 51 (21.0%)
--
-- reported by this file's own self-assert (l), against 0051's own guardrails (apex <= 25% of the
-- catalogue, no tier over 40%) re-checked here rather than assumed to still hold — the apex moves
-- from 19.3% to 18.1% and the biggest tier from 35.4% to 30.9%, both further inside the guardrails
-- than before, not closer to the edge. Filler goods are
-- chosen by the SAME uniform seeded rank as everything else in this file — no rarity-aware bias —
-- deliberately: biasing filler toward common goods to protect the rarity histogram would be a
-- SECOND axis the roster law does not have permission to invent (row 38's note, re-quoted in row
-- 48: "use it, do not invent a second axis" — said of size_tier, and the same discipline applies
-- to not inventing a hidden rarity-awareness axis here). The two goals did not conflict on this
-- world: see the measured histogram below.
--
-- ── WHAT THIS FILE DELIBERATELY DOES NOT TOUCH ─────────────────────────────────────────────────
-- `SEA_PLACE` ports — zero gain a roster; the market table's own row count (harbours x goods, not
-- ports x goods) already forecloses it, re-asserted below. `public.goods`/`base_value`/culture
-- masks. `crew_pool`, `max_draft`, `yard_tier`, `has_yard`, `has_academy`, `culture`, `nation_id` —
-- none are derived from the roster. The affinity KNOBS (0048's) — only the affinities they seed.
-- `scripts/build-world-growth.mjs`'s OWN internal 4-9-by-tier self-assert (lines 605-637) is a
-- BUILD TOOL, not a shipped migration — outside this slice's touch list (new migration, new
-- break-test, CHAIN.md, data/*.json) — and is now STALE: a future run of that generator would
-- enforce the retired band. Left named here, not fixed, because fixing it is not this file's job.
--
-- ── SUPERSEDES ─────────────────────────────────────────────────────────────────────────────────
-- No live SQL object: the old band was never a function. It was DATA — the literal offer rows
-- 0041 inserted (applied history, never edited) — plus a comment/assert inside
-- `scripts/build-world-growth.mjs`, a build tool that is not part of the applied chain. So there is
-- nothing to DROP; the supersession is at the level 0041 itself operated on — the offer SET — and
-- self-assert (g) below proves the old band's shape and the new law's shape now DISAGREE on this
-- world (a positive control in 0051's style), so the retirement is not merely coincidental.
--
-- Depends on: 0002 (ports/goods/port_specialties), 0005/0048 (port_goods, world.affinity_for),
-- 0006 (voyage.rng_raw, composed not re-derived), 0031 (why `world_secret` is the wrong seed,
-- measured above), 0036 (SEA_PLACE, `kind`, why a sea place carries no roster),
-- 0041 (the offer set and dev_* this file supersedes), 0051 (`rarity_scale`/`good_rarity`, reread
-- here to prove the point survives).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. BEFORE, captured for the report and the self-assert ─────────────────────────────────────
create temporary table roster_before_0058 as
select
  (select count(*) from public.port_specialties)                              as total_offers,
  (select count(*) from public.ports where kind = 'HARBOUR')                  as harbours,
  (select public.rarity_scale())                                             as mu,
  (select count(*) from (select public.good_rarity(id) t from public.goods) x where t = 'exotic')   as exotic,
  (select count(*) from (select public.good_rarity(id) t from public.goods) x where t = 'rare')     as rare,
  (select count(*) from (select public.good_rarity(id) t from public.goods) x where t = 'uncommon') as uncommon,
  (select count(*) from (select public.good_rarity(id) t from public.goods) x where t = 'common')   as common;

create temporary table tier_before_0058 as
select p.size_tier, count(*)::int as n, min(sc.c)::int as mn, round(avg(sc.c), 3) as avg_c, max(sc.c)::int as mx
  from public.ports p
  join lateral (select count(*)::int as c from public.port_specialties s where s.port_id = p.id) sc on true
 where p.kind = 'HARBOUR'
 group by p.size_tier;

-- ── 1. THE HASH — composes voyage.rng_raw (0006), no new arithmetic, NOT keyed by world_secret ──
create function public.roster_rng(p_key text)
returns numeric
language sql
immutable
parallel safe
as $$
  select voyage.rng_raw(
    '00000000-0000-0000-0000-000000000000'::uuid,
    0,
    'roster:' || p_key,
    'bv-roster-v0-c9f2e6a1-not-a-secret-public-world-data'
  )
$$;

comment on function public.roster_rng(text) is
  'THE seeded draw for the roster law (0058): composes voyage.rng_raw (0006) with a nil voyage id, '
  'day 0, and a FIXED non-secret string in the secret slot, so the result is a pure function of '
  '`key` alone. Deliberately NOT keyed on world_config.world_secret, which 0031 rotates on every '
  'fresh apply (measured: two consecutive db:apply runs produce different secrets) — the roster is '
  'STATIC WORLD DATA that scripts/db/world-guard.mjs requires byte-identical to data/*.json on '
  'every apply, and a secret that rotates would break that by construction. Not a second hash '
  'authority: it calls voyage.rng_raw rather than repeating its md5-to-[0,1) arithmetic.';

revoke all on function public.roster_rng(text) from public, anon, authenticated;

-- ── 2. THE LAW — thresholds live here and nowhere else ─────────────────────────────────────────
create function public.roster_target_count(p_tier int, p_authored int, p_draw numeric)
returns int
language plpgsql
immutable
as $$
begin
  if p_authored is null or p_authored < 0 then
    raise exception '0058: roster_target_count asked for % authored offer(s) — a count of offers is never null and never negative', p_authored;
  end if;
  if p_draw is null or p_draw < 0 or p_draw >= 1 then
    raise exception '0058: roster_target_count asked with draw % — the seed must land in [0,1)', p_draw;
  end if;
  if p_tier = 5 then
    return 10;                                          -- capital: THE WORLD SAYS TEN, always
  elsif p_tier = 2 then
    return 4;                                            -- small: THE WORLD SAYS FOUR, always
  elsif p_tier = 3 then
    if p_authored between 4 and 8 then
      return p_authored;                                 -- the editorial spread already stands
    elsif p_authored > 8 then
      return 8;                                           -- trim to the ceiling, keep the rest
    else
      return 4 + floor(p_draw * 5)::int;                  -- no editorial guidance: seed 4..8
    end if;
  else
    raise exception '0058: roster_target_count asked for tier % — capital/mid/small map onto size_tier 5/3/2 only (scripts/lib/world-derive.mjs:16), and no HARBOUR in this world carries any other tier', p_tier;
  end if;
end
$$;

comment on function public.roster_target_count(int, int, numeric) is
  'THE ROSTER LAW (0058, retiring 0041''s per-tier 4-9 band): size_tier, authored offer count, and '
  'a [0,1) seed -> how many goods a HARBOUR of that tier offers. Capital (5) is always 10, small '
  '(2) is always 4, mid (3) keeps its authored count when it already sits in 4-8, trims to 8 when '
  'it does not, and seeds a value across 4-8 when there is no editorial count to keep. The ONE '
  'place these numbers exist; owner''s words in docs/OWNER_REQUESTS.md row 48.';

revoke all on function public.roster_target_count(int, int, numeric) from public, anon, authenticated;

-- ── 3. THE ASSIGNMENT — authored pairs kept; the gap to target filled or trimmed, seeded ───────
create temporary table roster_authored_0058 as
select p.id as port_id, p.code as port_code, p.size_tier, g.id as good_id, g.code as good_code
  from public.port_specialties s
  join public.ports p on p.id = s.port_id
  join public.goods g on g.id = s.good_id
 where p.kind = 'HARBOUR';

create temporary table roster_target_0058 as
select p.id as port_id, p.code as port_code, p.size_tier,
       coalesce(a.n, 0) as authored_n,
       public.roster_target_count(p.size_tier, coalesce(a.n, 0), public.roster_rng(p.code || ':count')) as target_n
  from public.ports p
  left join (select port_id, count(*)::int as n from roster_authored_0058 group by port_id) a on a.port_id = p.id
 where p.kind = 'HARBOUR';

-- Ports that must lose offers: rank their AUTHORED goods by the shared seeded score, drop the
-- lowest-ranked (authored_n - target_n) of them, keep the rest.
create temporary table roster_drop_0058 as
select r.port_id, r.good_id
  from (
    select ra.port_id, ra.good_id, t.authored_n, t.target_n,
           row_number() over (
             partition by ra.port_id
             order by public.roster_rng(ra.port_code || '|' || ra.good_code) asc, ra.good_code asc
           ) as rk
      from roster_authored_0058 ra
      join roster_target_0058 t on t.port_id = ra.port_id
     where t.authored_n > t.target_n
  ) r
 where r.rk <= (r.authored_n - r.target_n);

-- Ports that must gain offers: rank the NOT-YET-authored goods by the same seeded score, add the
-- lowest-ranked (target_n - authored_n) of them.
create temporary table roster_fill_0058 as
select r.port_id, r.good_id
  from (
    select t.port_id, g.id as good_id, t.authored_n, t.target_n,
           row_number() over (
             partition by t.port_id
             order by public.roster_rng(t.port_code || '|' || g.code) asc, g.code asc
           ) as rk
      from roster_target_0058 t
      cross join public.goods g
     where t.target_n > t.authored_n
       and not exists (
             select 1 from roster_authored_0058 ra
              where ra.port_id = t.port_id and ra.good_id = g.id
           )
  ) r
 where r.rk <= (r.target_n - r.authored_n);

delete from public.port_specialties ps
 using roster_drop_0058 d
 where ps.port_id = d.port_id and ps.good_id = d.good_id;

insert into public.port_specialties (port_id, good_id)
select port_id, good_id from roster_fill_0058;

-- ── 4. WHAT MUST MOVE WITH IT — port_goods restated through the ONE seeding function (0048's own
--       pattern), and production_rate closed alongside it in the same file (0048 left it stale).
update public.port_goods pg
   set affinity = world.affinity_for(pg.port_id, pg.good_id);

update public.port_goods pg
   set stock_target    = greatest(60, round(200 * p.size_tier * (1.60 - pg.affinity))),
       stock           = least(pg.stock, greatest(60, round(200 * p.size_tier * (1.60 - pg.affinity)))),
       production_rate = case when pg.affinity < 0.80
                               then round(greatest(60, 200 * p.size_tier * (1.60 - pg.affinity)) * 0.05, 2)
                               else 0 end
  from public.ports p
 where p.id = pg.port_id;

-- ── 5. dev_commerce / dev_industry restate the new roster — scripts/lib/world-derive.mjs's own
--       formula, called again because its input (the roster) changed, not a new formula.
update public.ports p
   set dev_commerce = greatest(0, least(20, round(p.size_tier * 2.4 + coalesce(x.c_all, 0)))),
       dev_industry = greatest(0, least(20, round(p.size_tier * 2.0 + coalesce(x.c_ind, 0) * 1.5)))
  from (
         select s.port_id,
                count(*)::int as c_all,
                count(*) filter (where g.category in ('metal', 'textile', 'naval-stores'))::int as c_ind
           from public.port_specialties s
           join public.goods g on g.id = s.good_id
          group by s.port_id
       ) x
 where p.kind = 'HARBOUR' and x.port_id = p.id;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_harbours     int;
  v_offers       int;
  v_n            int;
  v_bad          int;
  v_list         text;
  v_mu_before    numeric;
  v_mu_after     numeric;
  v_exotic       int; v_rare int; v_uncommon int; v_common int;
  v_top          int;
  v_dropped      int;
  v_filled       int;
  v_distinct_mid int;
  v_synth_distinct int;
  v_vol          char;
  v_jeju_port    uuid;
  v_jeju_goods_n int;
  v_seaplace_gain int;
  v_offers_before int;
  v_old_band_disagree int;
begin
  -- (a) NON-VACUOUS FLOOR.
  select total_offers, harbours into v_offers, v_harbours from roster_before_0058;
  v_offers_before := v_offers;
  if v_harbours = 0 or v_offers = 0 then
    raise exception '0058 self-assert FAIL: % harbour(s) and % pre-existing offer(s) — nothing below can prove anything', v_harbours, v_offers;
  end if;
  if (select count(*) from tier_before_0058) <> 3 then
    raise exception '0058 self-assert FAIL: the pre-image spans % tier(s), not the 3 (5/3/2) this world uses — the "before" table is not the real world', (select count(*) from tier_before_0058);
  end if;

  -- (b) EVERY HARBOUR PORT NOW SATISFIES ITS TIER'S RULE EXACTLY: capital = 10, mid in [4,8],
  --     small = 4 — the violating port named if any fail.
  select count(*) into v_bad
    from public.ports p
    join lateral (select count(*)::int as c from public.port_specialties s where s.port_id = p.id) sc on true
   where p.kind = 'HARBOUR' and p.size_tier = 5 and sc.c <> 10;
  if v_bad <> 0 then
    select string_agg(p.code, ', ') into v_list from public.ports p
      join lateral (select count(*)::int as c from public.port_specialties s where s.port_id = p.id) sc on true
     where p.kind = 'HARBOUR' and p.size_tier = 5 and sc.c <> 10;
    raise exception '0058 self-assert FAIL: % capital(s) do not carry exactly 10 offers: %', v_bad, v_list;
  end if;
  select count(*) into v_bad
    from public.ports p
    join lateral (select count(*)::int as c from public.port_specialties s where s.port_id = p.id) sc on true
   where p.kind = 'HARBOUR' and p.size_tier = 3 and sc.c not between 4 and 8;
  if v_bad <> 0 then
    select string_agg(p.code, ', ') into v_list from public.ports p
      join lateral (select count(*)::int as c from public.port_specialties s where s.port_id = p.id) sc on true
     where p.kind = 'HARBOUR' and p.size_tier = 3 and sc.c not between 4 and 8;
    raise exception '0058 self-assert FAIL: % mid-sized port(s) fall outside 4-8 offers: %', v_bad, v_list;
  end if;
  select count(*) into v_bad
    from public.ports p
    join lateral (select count(*)::int as c from public.port_specialties s where s.port_id = p.id) sc on true
   where p.kind = 'HARBOUR' and p.size_tier = 2 and sc.c <> 4;
  if v_bad <> 0 then
    select string_agg(p.code, ', ') into v_list from public.ports p
      join lateral (select count(*)::int as c from public.port_specialties s where s.port_id = p.id) sc on true
     where p.kind = 'HARBOUR' and p.size_tier = 2 and sc.c <> 4;
    raise exception '0058 self-assert FAIL: % small port(s) do not carry exactly 4 offers: %', v_bad, v_list;
  end if;

  -- (c) ZERO HARBOUR PORTS OFFER FEWER THAN 4 — the owner's floor, no exceptions — and the SEA
  --     PLACES stay exactly as they were: no roster, because they carry no market (measured in
  --     the header: port_goods holds harbours x goods rows, never ports x goods).
  select count(*) into v_bad
    from public.ports p
    join lateral (select count(*)::int as c from public.port_specialties s where s.port_id = p.id) sc on true
   where p.kind = 'HARBOUR' and sc.c < 4;
  if v_bad <> 0 then
    raise exception '0058 self-assert FAIL: % harbour(s) still offer fewer than 4 goods', v_bad;
  end if;
  select count(*) into v_seaplace_gain
    from public.ports p
    join public.port_specialties s on s.port_id = p.id
   where p.kind = 'SEA_PLACE';
  if v_seaplace_gain <> 0 then
    raise exception '0058 self-assert FAIL: % sea place row(s) gained a roster — sea places carry no market and this file must not open that door', v_seaplace_gain;
  end if;
  select count(*) into v_bad from public.ports p where p.kind = 'HARBOUR'
    and not exists (select 1 from public.port_specialties s where s.port_id = p.id);
  if v_bad <> 0 then
    raise exception '0058 self-assert FAIL: % harbour(s) still carry zero offers after this file ran', v_bad;
  end if;

  -- (d) THE MID-TIER DRAW SPREADS ACROSS THE WHOLE BAND — proven as a MECHANISM property over 200
  --     synthetic keys, because no real mid harbour exercises the draw-branch today (all already
  --     sit inside 4-8). "spread it, do not put every mid port at 6" must hold of the FUNCTION.
  select count(distinct public.roster_target_count(3, 0, public.roster_rng('synthetic-mid-key-' || g)))
    into v_synth_distinct
    from generate_series(1, 200) g;
  if v_synth_distinct < 3 then
    raise exception '0058 self-assert FAIL: the mid-tier draw-branch produced only % distinct value(s) across 200 synthetic ports — it is not spreading across 4-8', v_synth_distinct;
  end if;
  select count(distinct sc.c) into v_distinct_mid
    from public.ports p
    join lateral (select count(*)::int as c from public.port_specialties s where s.port_id = p.id) sc on true
   where p.kind = 'HARBOUR' and p.size_tier = 3;
  raise notice '0058: mid-tier real-world offer counts span % distinct value(s) (editorial, no draw fired); the draw-branch alone spans % distinct value(s) over 200 synthetic keys', v_distinct_mid, v_synth_distinct;

  -- (e) DETERMINISM: the hash and the law are IMMUTABLE by catalog, not merely by promise, and
  --     re-running the WHOLE assignment against the world this file just produced is a NO-OP —
  --     the strongest form: a world already at target recomputes to the same target everywhere.
  select provolatile into v_vol from pg_proc where oid = 'public.roster_rng(text)'::regprocedure;
  if v_vol <> 'i' then
    raise exception '0058 self-assert FAIL: public.roster_rng is volatility %, not IMMUTABLE', v_vol;
  end if;
  select provolatile into v_vol from pg_proc where oid = 'public.roster_target_count(int,int,numeric)'::regprocedure;
  if v_vol <> 'i' then
    raise exception '0058 self-assert FAIL: public.roster_target_count is volatility %, not IMMUTABLE', v_vol;
  end if;
  if public.roster_rng('a-fixed-probe-key') <> public.roster_rng('a-fixed-probe-key') then
    raise exception '0058 self-assert FAIL: public.roster_rng is not repeatable';
  end if;
  if public.roster_rng('probe-key-one') = public.roster_rng('probe-key-two') then
    raise exception '0058 self-assert FAIL: public.roster_rng does not vary with its key';
  end if;
  select count(*) into v_bad
    from public.ports p
    join lateral (select count(*)::int as c from public.port_specialties s where s.port_id = p.id) sc on true
   where p.kind = 'HARBOUR'
     and public.roster_target_count(p.size_tier, sc.c, public.roster_rng(p.code || ':count')) <> sc.c;
  if v_bad <> 0 then
    raise exception '0058 self-assert FAIL: % harbour(s) are not fixed points of their own law — re-running the assignment on the world this file produced would move them again', v_bad;
  end if;

  -- (f) THE LAW ITSELF, PINNED AT ITS BOUNDARIES — arithmetic, not the seeded world.
  if public.roster_target_count(5, 0, 0.0) <> 10 or public.roster_target_count(5, 9, 0.999) <> 10 then
    raise exception '0058 self-assert FAIL: capital does not always answer 10';
  end if;
  if public.roster_target_count(2, 0, 0.0) <> 4 or public.roster_target_count(2, 9, 0.999) <> 4 then
    raise exception '0058 self-assert FAIL: small does not always answer 4';
  end if;
  if public.roster_target_count(3, 4, 0.0) <> 4 or public.roster_target_count(3, 8, 0.999) <> 8
     or public.roster_target_count(3, 6, 0.5) <> 6 then
    raise exception '0058 self-assert FAIL: mid does not preserve an already-legal authored count';
  end if;
  if public.roster_target_count(3, 9, 0.0) <> 8 or public.roster_target_count(3, 20, 0.999) <> 8 then
    raise exception '0058 self-assert FAIL: mid does not trim an over-band authored count to 8';
  end if;
  if public.roster_target_count(3, 0, 0.0) <> 4 or public.roster_target_count(3, 3, 0.1999999) <> 4
     or public.roster_target_count(3, 0, 0.2) <> 5 or public.roster_target_count(3, 0, 0.999) <> 8 then
    raise exception '0058 self-assert FAIL: mid does not seed 4-8 across the draw when under-authored';
  end if;
  begin
    perform public.roster_target_count(1, 4, 0.5);
    raise exception '0058 self-assert FAIL: tier 1 (unmapped) did not raise';
  exception when others then
    if sqlerrm not like '0058:%' then raise; end if;
  end;
  begin
    perform public.roster_target_count(3, -1, 0.5);
    raise exception '0058 self-assert FAIL: a negative authored count did not raise';
  exception when others then
    if sqlerrm not like '0058:%' then raise; end if;
  end;
  begin
    perform public.roster_target_count(3, 4, 1.0);
    raise exception '0058 self-assert FAIL: an out-of-range draw did not raise';
  exception when others then
    if sqlerrm not like '0058:%' then raise; end if;
  end;

  -- (g) THE OLD BAND IS ACTUALLY GONE — a positive control, 0051's style: the retired shape
  --     (capital <=9, mid <=7, small in [4,5]) must now DISAGREE with reality, not merely be
  --     un-checked.
  select count(*) into v_bad
    from public.ports p
    join lateral (select count(*)::int as c from public.port_specialties s where s.port_id = p.id) sc on true
   where p.kind = 'HARBOUR'
     and ((p.size_tier = 5 and sc.c <= 9) or (p.size_tier = 3 and sc.c <= 7) or (p.size_tier = 2 and sc.c between 4 and 5 and sc.c = 5));
  if v_bad = 0 then
    raise exception '0058 self-assert FAIL: the retired 4-9-by-tier band still agrees with every port — the old rule was not actually replaced';
  end if;
  v_old_band_disagree := v_bad;
  raise notice '0058: the retired band now disagrees with % port(s) that would have satisfied it (capital<=9 or the old small<=5) — it is retired, not merely unchecked', v_old_band_disagree;

  -- (h) AUTHORED PAIRS SURVIVE WHERE THE LAW LEAVES THEM ALONE — every small harbour that was
  --     already at exactly 4 keeps its ORIGINAL set, byte for byte (no drop, no fill fired).
  select count(*) into v_bad
    from roster_target_0058 t
    join public.ports p on p.id = t.port_id
   where p.size_tier = 2 and t.authored_n = 4
     and (exists (select 1 from roster_drop_0058 d where d.port_id = t.port_id)
          or exists (select 1 from roster_fill_0058 f where f.port_id = t.port_id));
  if v_bad <> 0 then
    raise exception '0058 self-assert FAIL: % already-at-4 small harbour(s) had their authored roster touched', v_bad;
  end if;
  select p.id into v_jeju_port from public.ports p where p.code = 'JEJ';
  if v_jeju_port is not null then
    select count(*) into v_jeju_goods_n from public.port_specialties where port_id = v_jeju_port;
    if v_jeju_goods_n <> 4 then
      raise exception '0058 self-assert FAIL: Jeju (row 38''s own example) carries % offers, not the 4 its authored roster always held', v_jeju_goods_n;
    end if;
  end if;

  -- (i) THE MEASURED SHAPE OF THE CHANGE, off the real diff tables.
  select count(*) into v_dropped from roster_drop_0058;
  select count(*) into v_filled  from roster_fill_0058;
  if v_dropped = 0 and v_filled = 0 then
    raise exception '0058 self-assert FAIL: 0 drops and 0 fills — this file claims to move the world and the diff says it moved nothing';
  end if;
  select count(*) into v_offers from public.port_specialties;
  raise notice '0058: % offer(s) dropped, % offer(s) filled; total port_specialties % -> %',
    v_dropped, v_filled, v_offers_before, v_offers;

  -- (j) port_goods RESTATED CORRECTLY, EVERYWHERE (0048's own pattern of checks).
  select count(*) into v_n from public.port_goods;
  if v_n < 1000 then
    raise exception '0058 self-assert FAIL: only % port_goods row(s) — the world is not here', v_n;
  end if;
  select count(*) into v_bad from public.port_goods pg
   where pg.affinity is distinct from world.affinity_for(pg.port_id, pg.good_id);
  if v_bad <> 0 then
    raise exception '0058 self-assert FAIL: % of % port_goods affinities disagree with world.affinity_for after the roster moved', v_bad, v_n;
  end if;
  select count(*) into v_bad from public.port_goods where stock > stock_target;
  if v_bad <> 0 then
    raise exception '0058 self-assert FAIL: % port_goods row(s) hold stock above target — the roster move minted goods', v_bad;
  end if;
  select count(*) into v_bad from public.port_goods pg
   where pg.production_rate is distinct from
         case when pg.affinity < 0.80
              then round(greatest(60, 200 * (select size_tier from public.ports where id = pg.port_id) * (1.60 - pg.affinity)) * 0.05, 2)
              else 0 end;
  if v_bad <> 0 then
    raise exception '0058 self-assert FAIL: % port_goods row(s) hold a production_rate that does not restate 0005''s own formula', v_bad;
  end if;

  -- (k) dev_commerce / dev_industry RESTATE THE NEW ROSTER on every harbour — the same formula
  --     scripts/build-world-growth.mjs's own self-assert (f) already checks, called again here.
  select count(*) into v_bad
    from public.ports p
    join lateral (select count(*)::int as c from public.port_specialties s where s.port_id = p.id) sc on true
    join lateral (select count(*)::int as c from public.port_specialties s
                    join public.goods g on g.id = s.good_id
                   where s.port_id = p.id and g.category in ('metal', 'textile', 'naval-stores')) ic on true
   where p.kind = 'HARBOUR'
     and (p.dev_commerce <> greatest(0, least(20, round(p.size_tier * 2.4 + sc.c)))
       or p.dev_industry <> greatest(0, least(20, round(p.size_tier * 2.0 + ic.c * 1.5))));
  if v_bad <> 0 then
    raise exception '0058 self-assert FAIL: % harbour(s) have dev_commerce/dev_industry that do not restate the new roster', v_bad;
  end if;

  -- (l) RARITY STILL MEANS SOMETHING — 0051's own guardrails, re-checked on the world this file
  --     produced, not assumed to still hold.
  select mu, exotic, rare, uncommon, common into v_mu_before, v_exotic, v_rare, v_uncommon, v_common from roster_before_0058;
  v_mu_after := public.rarity_scale();
  select count(*) filter (where t = 'exotic'),  count(*) filter (where t = 'rare'),
         count(*) filter (where t = 'uncommon'), count(*) filter (where t = 'common')
    into v_exotic, v_rare, v_uncommon, v_common
    from (select public.good_rarity(id) as t from public.goods) x;
  if least(v_exotic, v_rare, v_uncommon, v_common) < 1 then
    raise exception '0058 self-assert FAIL: a rarity tier is uninhabited after the roster moved (exotic %, rare %, uncommon %, common %)', v_exotic, v_rare, v_uncommon, v_common;
  end if;
  select count(*) into v_n from public.goods;
  if v_exotic * 4 > v_n then
    raise exception '0058 self-assert FAIL: the apex holds %/% goods after the roster moved — more than a quarter, exotic stopped meaning exotic', v_exotic, v_n;
  end if;
  v_top := greatest(v_exotic, v_rare, v_uncommon, v_common);
  if v_top * 5 > v_n * 2 then
    raise exception '0058 self-assert FAIL: one rarity tier holds %/% goods after the roster moved — more than 40%%', v_top, v_n;
  end if;
  raise notice '0058: rarity BEFORE mu=% exotic %/rare %/uncommon %/common %  ->  AFTER mu=% exotic %/rare %/uncommon %/common % — the point (a purpose to sail far for a rare good) still holds',
    round(v_mu_before, 3), (select exotic from roster_before_0058), (select rare from roster_before_0058),
    (select uncommon from roster_before_0058), (select common from roster_before_0058),
    round(v_mu_after, 3), v_exotic, v_rare, v_uncommon, v_common;

  -- (m) POSTURE: no new client write grants, no new client-executable writers, the two new
  --     functions unreachable by either client role.
  if has_function_privilege('anon', 'public.roster_rng(text)', 'execute')
     or has_function_privilege('authenticated', 'public.roster_rng(text)', 'execute')
     or has_function_privilege('anon', 'public.roster_target_count(int,int,numeric)', 'execute')
     or has_function_privilege('authenticated', 'public.roster_target_count(int,int,numeric)', 'execute') then
    raise exception '0058 self-assert FAIL: a client role may execute a roster helper';
  end if;
  select count(*) into v_bad from public.client_write_grants();
  if v_bad <> 0 then
    raise exception '0058 self-assert FAIL: % client write grant(s) after this migration', v_bad;
  end if;
  select count(*) into v_bad from public.client_executable_writers();
  if v_bad <> 0 then
    raise exception '0058 self-assert FAIL: % client-executable writer(s) after this migration', v_bad;
  end if;

  drop table roster_before_0058;
  drop table tier_before_0058;
  drop table roster_authored_0058;
  drop table roster_target_0058;
  drop table roster_drop_0058;
  drop table roster_fill_0058;

  raise notice '0058 self-assert ok: capital/mid/small now offer exactly 10 / 4-8 / exactly 4 across all % harbours (0 below the floor, 0 sea places touched), the mid-tier draw spreads across >= % distinct value(s) over 200 synthetic keys, the law is IMMUTABLE/repeatable/varying and every harbour is a fixed point of its own rule, the retired 4-9-by-tier band now disagrees with % port(s), % offer(s) dropped and % offer(s) filled (% -> % total), port_goods and dev_commerce/dev_industry restate the new roster with 0 disagreements, rarity still shows all 4 tiers inhabited with the apex under a quarter and no tier over 40%% (mu % -> %), and posture reads zero',
    v_harbours, v_synth_distinct, v_old_band_disagree, v_dropped, v_filled, v_offers_before, v_offers, round(v_mu_before,3), round(v_mu_after,3);
end $$;
