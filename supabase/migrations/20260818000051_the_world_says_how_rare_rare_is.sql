-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0051 — THE WORLD SAYS HOW RARE RARE IS
--        The rarity thresholds stop being three numbers somebody chose for a 70-good catalogue and
--        become a LADDER OFF THE WORLD'S OWN PRODUCER DENSITY. `exotic` means exotic at 243 goods,
--        and it will still mean exotic at 2,430.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE ASK ────────────────────────────────────────────────────────────────────────────────────
-- docs/RESUME.md, under KNOWN, WRITTEN DOWN, NOT LOST:
--
--   "Rarity thresholds do not scale. Fixed at <=2/<=5/<=12 producers, calibrated for 70 goods. At
--    243 the catalogue is 54.7% exotic — exotic has become the default and therefore means
--    nothing."
--
-- The owner's decision: fix it — make rarity mean something at any catalogue size.
--
-- ── THE DEFECT, MEASURED ───────────────────────────────────────────────────────────────────────
-- Measured on this machine 2026-08-25, by applying the whole chain to PGlite (PostgreSQL 18.3) and
-- asking `public.good_rarity` for every row of `public.goods`:
--
--     243 goods, 238 ports, 1,310 port_specialties rows
--     exotic 133 (54.7%) / rare 58 (23.9%) / uncommon 27 (11.1%) / common 25 (10.3%)
--
-- 0032 measured its own world at 6 / 20 / 22 / 22 over 70 goods and 834 specialty rows, and called
-- that "a thin apex over three broad bands". The apex is now the majority. Nothing about 0032's
-- reasoning was wrong; what was wrong is that its answer was three ABSOLUTE producer counts, and
-- an absolute count is a statement about a particular world. The catalogue went 70 -> 243 while
-- the specialty rows went 834 -> 1,310, so the average number of harbours that make a good fell
-- from 11.9 to 5.4 — and three cuts placed at 2 / 5 / 12 slid up the distribution until the top
-- one swallowed it.
--
-- AND THE ASSERT WAS PART OF THE DEFECT. 0032's shape check required only that "no tier holds more
-- than 60% of the catalogue". 54.7% walked under it. A guard that a meaningless rule can satisfy
-- reports coverage it never had — the exact failure docs/CORE_REUSE.md:1443-1451 exists to name.
-- It is re-cut below, and it is re-cut so that it FAILS on the world as it stands today.
--
-- ── THE MECHANISM ──────────────────────────────────────────────────────────────────────────────
-- Rarity is still DERIVED, still from `public.port_specialties`, still "how many ports make it",
-- still never from price. Only the yardstick changes: the cuts are no longer numbers, they are
-- FRACTIONS OF THE WORLD'S OWN MEAN PRODUCER COUNT.
--
--     mu  := (specialty rows) / (goods that have a source at all)        `public.rarity_scale()`
--            — the average number of harbours that make a good in THIS world. Today mu = 5.391.
--
--     producers <= max(1, mu/4)  -> 'exotic'    made in a quarter of the harbours an ordinary
--                                               good is made in, or fewer
--     producers <= max(2, mu/2)  -> 'rare'      half
--     producers <= max(3, mu)    -> 'uncommon'  about as many as an ordinary good
--     otherwise                  -> 'common'    more than ordinary; you are never far from a source
--
-- WHY A LADDER, AND WHY THE RUNGS HALVE. Producer counts in this world are heavily right-skewed
-- (measured: min 1, median 2, mean 5.4, max 52). On a skewed count the meaningful step is a
-- FACTOR, not a difference — "made in half as many harbours" is a sentence about scarcity; "made
-- in three fewer harbours" is a sentence about nothing in particular. So each rung down halves.
-- The top rung is mu itself, because mu is precisely what "ordinary" means here.
--
-- WHY THE FLOOR max(1, .) / max(2, .) / max(3, .). Without it the rule breaks in the SPARSE
-- direction, and that is the direction this world is actually travelling. A good that exists is
-- made in at least one harbour, so once mu < 4 the apex boundary mu/4 falls below 1 and NOTHING
-- can reach it: `exotic` empties. Measured, on a sub-world built from half this world's ports
-- (206 goods, 670 specialty rows, mu = 3.25): the unfloored ladder gives exotic 0 / rare 88 /
-- uncommon 69 / common 49. Three tiers below `common` need three distinguishable whole numbers of
-- producing ports, and the smallest three whole numbers are 1, 2 and 3. That is the floor. It is
-- structural arithmetic, not a calibration: it does not mention this world at all.
--
-- The ladder is therefore STRICTLY INCREASING at every scale (checked below over a sweep from
-- mu = 1 to mu = 1000), so all four tiers stay reachable however thin the world gets.
--
-- ── WHAT IT MEASURES, ON THIS WORLD ────────────────────────────────────────────────────────────
--     mu = 1310 / 243 = 5.391  ->  cuts at 1.348 / 2.695 / 5.391
--     exotic 47 (19.3%) / rare 86 (35.4%) / uncommon 58 (23.9%) / common 52 (21.4%)
--
-- The apex cannot be thinner than 47 on this world, and that is not a shortcoming of the rule: 47
-- goods are made in exactly ONE harbour, and splitting that block would mean ranking two identical
-- facts differently — authoring, which is the thing 0032 refused and this file keeps refusing.
--
-- ── THE PROPERTY THE OLD RULE LACKED, AND THIS ONE HAS ─────────────────────────────────────────
-- SCALE-FREEDOM. Multiply every producer count in the world by k and mu by k, and every good keeps
-- its tier. Measured over the real catalogue at k = 2, 3, 7, 17 and 50: the histogram is
-- 47 / 86 / 58 / 52 at every one of them. The 0032 law over the same rescaled catalogue:
--
--     k=2   exotic  47 / rare 86 / uncommon 65 / common  45
--     k=3   exotic   0 / rare 47 / uncommon 135 / common 61
--     k=7   exotic   0 / rare  0 / uncommon  47 / common 196
--     k=17  exotic   0 / rare  0 / uncommon   0 / common 243   (100% of the catalogue, one tier)
--
-- That is the whole defect in one line, and the self-assert below sweeps exactly this property —
-- with the 0032 rule kept beside it as a POSITIVE CONTROL, so a sweep that has gone blind cannot
-- pass by finding nothing.
--
-- The same arithmetic run backwards is the strongest evidence the shape is right. 0032's own
-- header records its world: 70 goods, 834 specialty rows, so mu = 11.914 and this rule's cuts fall
-- at 2.979 / 5.957 / 11.914 — whole-number cuts of <=2 / <=5 / <=11. 0032 chose <=2 / <=5 / <=12
-- BY HAND. Two of the three thresholds are reproduced exactly and the third is off by one. This
-- file is not overturning 0032's judgement; it is deriving it, so that it survives the next growth.
--
-- ── THE SECOND SCALE THIS FILE CAN HONESTLY ASSERT, AND THE ONE IT CANNOT ─────────────────────
-- Guard (d) below re-tiers the WHOLE catalogue at five further world scales and requires every
-- good to keep its tier, so the histogram above is PROVEN at six catalogue scales rather than
-- measured at one. That is the property 0032 was missing.
--
-- What this file cannot honestly do is assert the shape against a differently-SHAPED world, because
-- the transaction holds exactly one world and inventing a second would be pinning a seed with extra
-- steps. The nearest honest thing — a real sub-world, the goods and specialty rows of half this
-- world's ports — was measured and deliberately NOT made into an assert: at 206 goods over 670
-- specialty rows its mu is 3.25 and its producer counts collapse onto a handful of small integers,
-- so no four-tier rule can partition it at all (0032's law puts 146 of its 206 goods — 70.9% — in
-- exotic there). A world that thin holds fewer than four distinguishable degrees of scarcity, and
-- asserting four inhabited tiers over it would be asserting a fiction. What this file guarantees
-- for such a world instead is guard (e): all four tiers stay REACHABLE at every scale from mu = 1
-- to mu = 1000 — the most a tiering rule can promise about a world whose data may not carry four
-- tiers' worth of information.
--
-- ── WHAT IT COSTS, MEASURED ────────────────────────────────────────────────────────────────────
-- The yardstick is derived and not stored, so `public.good_rarity` now reads two aggregates per
-- good on top of the producer count it already read. Measured on this machine 2026-08-25 (PGlite
-- 0.5.5 / PostgreSQL 18.3, median of five reads after a warm-up, with the yardstick hard-coded to
-- the same value as the control):
--
--     world.snapshot()      1,437 ms  ->   2,377 ms   (+940 ms, +65%)
--     world.market(port)   21,513 ms  ->  21,030 ms   (unchanged within run-to-run spread)
--
-- The market read does not move because its cost is the neighbourhood walk 0019 fenced, not the
-- tier. The snapshot read pays 0.9 s ONCE per session for the static world. That is the price of a
-- rule that is derived rather than pinned, and it is the right price to pay: a stored yardstick
-- would be a cache of a fact the tables already hold, and an invalidation rule is a second
-- authority. If that second is ever worth reclaiming the answer is an index on
-- port_specialties(good_id) — which would pay for the 243 producer counts 0032 already reads too —
-- and not a stored number.
--
-- ── ALTERNATIVES REJECTED ──────────────────────────────────────────────────────────────────────
--   * RE-CALIBRATE THE ABSOLUTE NUMBERS to today's catalogue (<=1 / <=2 / <=5). It produces the
--     identical histogram today — and it is the same defect wearing new numbers. The next growth
--     falsifies it silently, exactly as this one did, and the only warning would be a player
--     noticing that everything is exotic again. docs/NO_SPAGHETTI.md §6: derive it, or find it —
--     never pin the seed. Three pinned integers ARE the seed.
--
--   * A SHARE OF THE PORT COUNT (producers / total ports, cut at 1% / 3% / 8%). Rejected because
--     it does not fix the measured defect. The collapse did not come from the port count: ports
--     went 214 -> 238 (+11%) while the catalogue went 70 -> 243 (+247%). 1% of 238 ports is 2.38,
--     so the apex boundary lands back at "<= 2 producers" — which is today's 133-good exotic block
--     unchanged, at 54.7%. It answers "what share of the world makes it", and the question the
--     tier exists to answer is "how does this compare to the other things I could be carrying".
--
--   * A RANK QUANTILE OVER THE CATALOGUE (exotic = the bottom 15% by producer count, and so on).
--     This was the strongest rival and it is worth saying why it lost. (i) It cannot be read
--     cheaply: the boundaries are order statistics, so every call must read the WHOLE producer-
--     count distribution — 243 of those per `world.snapshot()` and another 243 per `world.market()`
--     — against two aggregate counts for `rarity_scale()`. (ii) It buys nothing for the price,
--     because the distribution is one enormous tie: 86 of 243 goods have exactly 2 producers and
--     47 have exactly 1, so a quantile boundary lands INSIDE a tie block and the realised tier
--     share jumps in steps of 19 and 35 percentage points regardless of the target. (iii) A tie
--     block wide enough to straddle two targets collapses a tier to zero with no warning, so it
--     needs a distinct-boundary repair on top — which is the floor above, arrived at by a longer
--     road. The mean gives the same partition today, degrades the same way, and costs two counts.
--
--   * DERIVE FROM PRICE. Rejected by 0032 and still rejected, verbatim and for the same reason:
--     in this world every port trades every good, so a good that is merely expensive is not rare.
--     Gold is dear and common. What is scarce is a cheap SOURCE.
--
-- ── SUPERSEDES ─────────────────────────────────────────────────────────────────────────────────
-- All three of these were cut by 0032
-- (`20260818000032_a_good_is_as_rare_as_the_ports_that_make_it.sql`).
--
--   * public.rarity_from_producers(int) — 0032:71. DROPPED, not replaced: the law now needs the
--     world's scale beside the producer count, and adding an argument would create an OVERLOAD
--     rather than a replacement, leaving the old absolute rule alive beside the new one and every
--     caller free to choose between them (docs/NO_SPAGHETTI.md §3, "when create or replace is not
--     enough"). The drop is asserted below: `to_regprocedure('public.rarity_from_producers(int)')`
--     must read null when this migration finishes. It held no grants to re-issue — 0032 revoked
--     them all, and the replacement is revoked identically.
--   * public.rarity_from_producers(int, numeric) — NEW, and still THE ONE PLACE THE THRESHOLDS
--     EXIST. Nothing else in the schema names a tier boundary.
--   * public.rarity_scale() — NEW, and the one place the world's producer density is derived. It
--     reads `public.port_specialties` and nothing else — the same single authored fact the tier is
--     read from, and the same one 0005 prices from.
--   * public.good_rarity(uuid) — 0032:87. RE-CUT: same name, same argument, same return, same
--     volatility, same search_path, and still the one authority a payload asks. Its body gains one
--     term — it now hands the law the world's scale as well as the producer count.
--
-- NOT RE-CUT, AND THAT IS THE POINT: `world.snapshot()` (0032:117) and `world.market(uuid)`
-- (0032:180) are not touched by this file. They ask `public.good_rarity(g.id)`, whose signature and
-- volatility are unchanged, so the new tiers reach the wire through the callers 0032 already built
-- without a line of them moving. That is 0032's design being right, and the self-assert reads both
-- deployed bodies back to confirm each still asks the one authority exactly once — a second rule
-- inlined into a payload is the failure mode this check exists for.
--
-- IS IT A NO-OP WHERE THE NEW INPUT IS ABSENT? No, and it must not be read as one. The new input
-- is the world's scale, which is never absent — it is derived from the very rows the old rule
-- already read. This migration deliberately RE-TIERS THE CATALOGUE: 171 of 243 goods change tier
-- (measured off the wire by the assert below, which also refuses a run in which none moved). The
-- 86 goods with exactly two producing ports go exotic -> rare, the 58 with three to five go
-- rare -> uncommon, and the 27 with six to twelve go uncommon -> common; the 47 single-source
-- goods stay exotic and the 25 with thirteen or more stay common.
-- Everything else on both payloads is proven byte-identical to what 0032 served, by capturing the
-- old payloads before the replace and requiring the new ones, stripped of `rarity`, to equal them.
--
-- ── VOLATILITY AND SEARCH_PATH, TRACED BEFORE THE SHAPE WAS CHOSEN ─────────────────────────────
-- The brief for this slice warned that a law which must read a table cannot stay `immutable`, and
-- that every caller's volatility moves with it. That is why the world's scale arrives as an
-- ARGUMENT rather than being read inside the law:
--
--   public.rarity_from_producers(int, numeric)  IMMUTABLE, no search_path  (unchanged posture: it
--       touches no table, so it is still a pure function of its arguments — the table read was
--       lifted OUT of it, not pushed into it)
--   public.rarity_scale()                       STABLE, set search_path = public, pg_temp   (NEW —
--       the only new object that reads the world)
--   public.good_rarity(uuid)                    STABLE, set search_path = public, pg_temp
--       (UNCHANGED — it already read port_specialties, so calling one more stable function costs
--       it no volatility)
--   world.snapshot()   STABLE  security definer   — untouched, and still legal: stable may call
--       stable.
--   world.market(uuid) VOLATILE security definer  — untouched.
--
-- SO NOTHING MOVED. Grepped before committing to this shape: no index, generated column, CHECK
-- constraint, view or partial predicate anywhere in the chain references either function — the
-- only mentions of `rarity_from_producers` / `good_rarity` in supabase/migrations are 0032 itself
-- and a prose comment at 0036:31. Had the law been made `stable`, `world.snapshot()` would still
-- have been legal, but the law would have stopped being usable in any future index or generated
-- column, and it would have re-read the whole scale once per good. Neither cost is paid.
--
-- ── WHAT THIS DELIBERATELY DOES NOT TOUCH ──────────────────────────────────────────────────────
-- PRICES. 0032's sentence stands unamended and is repeated here because it is now easier to break:
-- `world.mid_price` (0005) is not a caller of these functions and must not become one — scarcity
-- already reaches the price through the affinity gradient 0005 derives from the very same
-- port_specialties rows. Wiring rarity into pricing would push one authored fact through two doors.
-- THE CLIENT. `src/components/ui/rarityTiers.ts` reads the four words and knows no thresholds; the
-- four words are unchanged, so nothing on the client moves. The formula stays server-only.
-- THE LEAK INSTRUMENT. 0032 re-ran its `world_secret` check because it re-cut the function that
-- builds the payload. This file does not, and it proves something stronger in its place: every
-- field of both payloads except `rarity` is required to be byte-identical to what 0032 served, and
-- `rarity` itself is required to be one of four literal words on every row.
--
-- Depends on: 0032 (the rarity law and its two callers), 0005/0009 (port_specialties, the authored
-- fact), 0001/0018 (the posture instruments re-asserted at the end).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. THE OLD PAYLOADS, captured before anything is replaced ──────────────────────────────────
-- The parity proof below reads these. The subject port is deterministic: first port by code, never
-- heap order (docs/NO_SPAGHETTI.md §4). Within this transaction now() is frozen, so the market's
-- drift slot cannot roll between this capture and the re-read, and parity is exact, not probable.
create temporary table payload_before_0051 as
select world.snapshot() as snap,
       world.market((select id from public.ports order by code limit 1)) as market;

-- ── 1. THE SCALE — the one place the world's producer density is derived ───────────────────────
-- Read from port_specialties ALONE, and averaged over the goods that have a source at all rather
-- than over `public.goods`. A good nobody makes is not part of the scale other goods are measured
-- against; counting it would drag mu down and quietly re-tier the whole catalogue. (On the world
-- as it stands the two definitions agree exactly — every one of the 243 goods has at least one
-- producing port — so this is a choice about the future, made on purpose.)
-- `create`, not `create or replace`: this file claims the function is NEW, and a bare create is
-- that claim enforced by the engine rather than asserted in prose.
create function public.rarity_scale()
returns numeric
language sql
stable
set search_path = public, pg_temp
as $$
  select count(*)::numeric / nullif(count(distinct good_id), 0)
    from public.port_specialties
$$;

comment on function public.rarity_scale() is
  'THE WORLD''S PRODUCER DENSITY (0051): specialty rows divided by the goods that have a source at '
  'all — the average number of harbours that make a good in this world. The yardstick '
  'public.rarity_from_producers measures every good against, so the rarity tiers rescale with the '
  'world instead of being recalibrated after it. Read from public.port_specialties and nothing '
  'else: the tier and its yardstick come from ONE authored fact.';

-- ── 2. THE LAW — thresholds live here and nowhere else ─────────────────────────────────────────
-- Dropped rather than replaced: the extra argument would otherwise create an overload and leave
-- 0032's absolute rule callable beside this one (docs/NO_SPAGHETTI.md §3).
drop function public.rarity_from_producers(int);

create function public.rarity_from_producers(p_producers int, p_mean numeric)
returns text
language plpgsql
immutable
as $$
begin
  -- Guards, not asserts: these are the shapes for which the question has no answer, and a silent
  -- null here would fall through `case` to 'common' and label an unanswerable good ordinary.
  if p_producers is null or p_producers < 0 then
    raise exception '0051: rarity_from_producers asked for % producing ports — a count of harbours is never null and never negative', p_producers;
  end if;
  if p_mean is null or p_mean <= 0 then
    raise exception '0051: rarity_from_producers asked at scale % — a world that makes nothing has no yardstick to be rare against', p_mean;
  end if;
  return case
    -- Each rung down HALVES the harbours, because on a right-skewed count the meaningful step is a
    -- factor. The floors 1 / 2 / 3 keep the three rungs distinguishable in whole ports however
    -- sparse the world becomes; without them the apex empties as soon as mu falls below 4.
    when p_producers <= greatest(1, p_mean / 4) then 'exotic'
    when p_producers <= greatest(2, p_mean / 2) then 'rare'
    when p_producers <= greatest(3, p_mean)     then 'uncommon'
    else                                             'common'
  end;
end $$;

comment on function public.rarity_from_producers(int, numeric) is
  'THE RARITY LAW (0051, superseding 0032''s absolute thresholds): producer count and the world''s '
  'mean producer count -> tier. <= max(1, mu/4) exotic, <= max(2, mu/2) rare, <= max(3, mu) '
  'uncommon, else common. The one place the thresholds exist, and they are FRACTIONS, so growing '
  'the catalogue does not silently retune them. Scale-free: multiply producers and mu by the same '
  'k and every good keeps its tier. Change a fraction in a superseding migration and every serving '
  'of rarity moves with it.';

-- ── 3. THE ONE AUTHORITY a payload asks — same signature, same volatility, one more term ───────
create or replace function public.good_rarity(p_good uuid)
returns text
language sql
stable
set search_path = public, pg_temp
as $$
  select public.rarity_from_producers(
    (select count(*)::int from public.port_specialties ps where ps.good_id = p_good),
    public.rarity_scale())
$$;

comment on function public.good_rarity(uuid) is
  'How rare a good is (0032, rescaled by 0051): the count of ports that produce it, measured '
  'against public.rarity_scale() — the world''s own mean producer count — by '
  'public.rarity_from_producers. Served as the `rarity` field on snapshot.goods[] and '
  'market.goods[]; clients read the word, never the rule.';

-- Server-only, exactly as 0032 left them: the tier reaches a client as a served FIELD, and neither
-- the formula nor the yardstick crosses the wire.
revoke all on function public.rarity_scale()                     from public, anon, authenticated;
revoke all on function public.rarity_from_producers(int, numeric) from public, anon, authenticated;
revoke all on function public.good_rarity(uuid)                  from public, anon, authenticated;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_goods    int;
  v_specs    int;
  v_mu       numeric;
  v_mu_check numeric;
  v_probe    numeric;
  v_n        int;
  v_bad      int;
  v_ctl      int;
  v_moved    int;
  v_exotic   int;
  v_rare     int;
  v_uncommon int;
  v_common   int;
  v_top      int;
  v_min_code text;
  v_max_code text;
  v_min_good uuid;
  v_max_good uuid;
  v_port     uuid;
  v_snap     jsonb;
  v_market   jsonb;
  v_stripped jsonb;
  v_def      text;
  v_grants   int;
  v_writers  int;
  v_pin      record;
begin
  -- (a) NON-VACUOUS FLOOR. Every assert below quantifies over goods and specialty rows; an empty
  --     world would green all of them while proving nothing.
  select count(*) into v_goods from public.goods;
  select count(*) into v_specs from public.port_specialties;
  if v_goods = 0 or v_specs = 0 then
    raise exception '0051 self-assert FAIL: % good(s) and % specialty row(s) — nothing below can prove anything', v_goods, v_specs;
  end if;

  -- The producer counts, computed ONCE. Every check that follows reads this, so none of them can
  -- disagree with another about what the world holds.
  create temporary table producers_0051 as
  select g.id, g.code, count(ps.port_id)::int as n
    from public.goods g
    left join public.port_specialties ps on ps.good_id = g.id
   group by g.id, g.code;

  -- (b) THE YARDSTICK IS WHAT THE HEADER SAYS IT IS — recomputed here from the table, not trusted
  --     from the function. A scale read from the wrong column would still be a number.
  v_mu := public.rarity_scale();
  select count(*)::numeric / nullif(count(distinct good_id), 0) into v_mu_check
    from public.port_specialties;
  if v_mu is null or v_mu <= 0 or v_mu is distinct from v_mu_check then
    raise exception '0051 self-assert FAIL: rarity_scale() said %, the tables say % (% specialty rows over % sourced goods)',
      v_mu, v_mu_check, v_specs, (select count(distinct good_id) from public.port_specialties);
  end if;

  -- (c) THE LAW ITSELF, PINNED AT ITS BOUNDARIES — and pinned as ARITHMETIC, not as a world.
  --     Every row below is a (scale, producers) pair whose answer follows from the fractions in
  --     this file's header alone; not one of them mentions the seeded catalogue. mu = 8 and mu = 20
  --     are chosen because the ladder lands on whole ports there (2/4/8 and 5/10/20), so every
  --     boundary is probed from BOTH sides and an off-by-one cannot pass. mu = 1 and mu = 3.9 probe
  --     the SPARSE regime where the floors bind and the ladder is 1/2/3.
  for v_pin in
    select * from (values
      (8.0,  0, 'exotic'), (8.0,  2, 'exotic'), (8.0,  3, 'rare'),     (8.0,  4, 'rare'),
      (8.0,  5, 'uncommon'), (8.0, 8, 'uncommon'), (8.0, 9, 'common'), (8.0, 500, 'common'),
      (20.0, 5, 'exotic'), (20.0, 6, 'rare'),   (20.0, 10, 'rare'),   (20.0, 11, 'uncommon'),
      (20.0, 20, 'uncommon'), (20.0, 21, 'common'),
      (1.0,  0, 'exotic'), (1.0,  1, 'exotic'), (1.0,  2, 'rare'),     (1.0,  3, 'uncommon'),
      (1.0,  4, 'common'),
      (3.9,  1, 'exotic'), (3.9,  2, 'rare'),   (3.9,  3, 'uncommon'), (3.9,  4, 'common')
    ) as t(mu, n, tier)
  loop
    if public.rarity_from_producers(v_pin.n, v_pin.mu) <> v_pin.tier then
      raise exception '0051 self-assert FAIL: at scale % a good with % producing port(s) tiers as %, the law says %',
        v_pin.mu, v_pin.n, public.rarity_from_producers(v_pin.n, v_pin.mu), v_pin.tier;
    end if;
  end loop;

  -- (d) SCALE-FREEDOM — THE PROPERTY 0032's LAW LACKED AND THIS FILE EXISTS TO ADD. Grow the whole
  --     world by a factor k and every good must keep its tier. Swept over the REAL catalogue, so
  --     it is the actual distribution being rescaled and not a hand-picked ladder of numbers.
  select count(*) into v_bad
    from producers_0051 p
    cross join (values (2), (3), (7), (17), (50)) as s(k)
   where public.rarity_from_producers(p.n * s.k, v_mu * s.k)
         is distinct from public.rarity_from_producers(p.n, v_mu);
  if v_bad <> 0 then
    raise exception '0051 self-assert FAIL: % (good, scale) pair(s) change tier when the whole world is multiplied by k — the law is not scale-free, which is the entire defect it was written to remove',
      v_bad;
  end if;

  -- (d2) POSITIVE CONTROL FOR (d). A sweep that has gone blind finds nothing and reads exactly like
  --      a sweep that found nothing. 0032's absolute law is run through the same sweep, inline and
  --      as a throwaway expression — it is not created as an object, so no second rule survives
  --      this transaction — and it MUST disagree with itself at k = 17. Measured: it puts all 243
  --      goods in `common` there.
  select count(*) into v_ctl
    from producers_0051 p
   where (case when p.n * 17 <= 2 then 'exotic' when p.n * 17 <= 5 then 'rare'
               when p.n * 17 <= 12 then 'uncommon' else 'common' end)
         is distinct from
         (case when p.n <= 2 then 'exotic' when p.n <= 5 then 'rare'
               when p.n <= 12 then 'uncommon' else 'common' end);
  if v_ctl = 0 then
    raise exception '0051 self-assert FAIL: the scale-freedom sweep is BLIND — 0032''s absolute thresholds survived a 17x world unchanged under it, so its zero above proves nothing';
  end if;

  -- (e) ALL FOUR TIERS STAY REACHABLE AT EVERY SCALE. This is what the floors 1/2/3 buy, and the
  --     un-floored ladder fails it below mu = 4 (measured, header). Reachability is asked in WHOLE
  --     producing ports and FROM ONE UPWARD: a good cannot be made in 0.8 harbours, and a good
  --     made in no harbour at all is not a source anyone can go and find, so it cannot be the
  --     thing that keeps a tier alive.
  foreach v_probe in array array[1, 2, 3, 3.99, 4, 5, 8, 12, 100, 1000]::numeric[]
  loop
    --  The probe must reach PAST the top rung, and the top rung is greatest(3, mu) — not mu — or
    --  the sweep runs out of ports before `common` starts and reports the law's floor as the law's
    --  fault. (It did, on the first run of this file: mu = 1 puts `common` at 4 producing ports and
    --  a range of ceil(mu) + 2 stopped at 3.)
    select count(distinct public.rarity_from_producers(t.p, v_probe)) into v_n
      from generate_series(1, greatest(3, ceil(v_probe))::int + 2) as t(p);
    if v_n <> 4 then
      raise exception '0051 self-assert FAIL: at scale mu = % only % of the four tiers can be reached by any whole number of producing ports — a tier no good can occupy is a tier that does not exist',
        v_probe, v_n;
    end if;
  end loop;

  -- (f) THE CATALOGUE'S SHAPE, and THIS IS THE ASSERT 0032 HAD TOO LOOSE. 0032 allowed any tier up
  --     to 60% and 54.7% walked under it. Four tiers means an even share is 25%, so:
  --       * the APEX may not exceed an even share — an apex holding more than a quarter of the
  --         catalogue is not an apex;
  --       * NO tier may exceed 40%, which is already 1.6x an even share.
  --     Both numbers are arithmetic on "four tiers", not measurements of this world. Both FAIL on
  --     the world as it stands under 0032's law (exotic 133 = 54.7%), which is the point: this
  --     guard would have caught the defect the moment the catalogue grew.
  select count(*) filter (where t = 'exotic'),  count(*) filter (where t = 'rare'),
         count(*) filter (where t = 'uncommon'), count(*) filter (where t = 'common')
    into v_exotic, v_rare, v_uncommon, v_common
    from (select public.good_rarity(id) as t from public.goods) x;
  if least(v_exotic, v_rare, v_uncommon, v_common) < 1 then
    raise exception '0051 self-assert FAIL: a tier is uninhabited (exotic %, rare %, uncommon %, common % of % goods)',
      v_exotic, v_rare, v_uncommon, v_common, v_goods;
  end if;
  if v_exotic * 4 > v_goods then
    raise exception '0051 self-assert FAIL: the apex holds %/% goods — more than a quarter of the catalogue, so `exotic` is not an apex',
      v_exotic, v_goods;
  end if;
  v_top := greatest(v_exotic, v_rare, v_uncommon, v_common);
  if v_top * 5 > v_goods * 2 then
    raise exception '0051 self-assert FAIL: one tier holds %/% goods — more than 40%%, so the tiering carries too little information to be worth serving',
      v_top, v_goods;
  end if;
  raise notice '0051 rarity over % goods at mu = %: exotic %, rare %, uncommon %, common %',
    v_goods, round(v_mu, 3), v_exotic, v_rare, v_uncommon, v_common;

  -- (g) THE ENDS OF THE SCALE MEAN WHAT THE WORDS SAY (0032's instrument, kept). The scarcest good
  --     in the world must be exotic and the most-made must be common — ties broken by code, never
  --     heap order — so the derivation actually straddles its own boundaries on this world.
  select id, code into strict v_min_good, v_min_code from producers_0051 order by n asc, code asc limit 1;
  select id, code into strict v_max_good, v_max_code from producers_0051 order by n desc, code asc limit 1;
  if public.good_rarity(v_min_good) <> 'exotic' then
    raise exception '0051 self-assert FAIL: the scarcest good (%) tiers as %, not exotic',
      v_min_code, public.good_rarity(v_min_good);
  end if;
  if public.good_rarity(v_max_good) <> 'common' then
    raise exception '0051 self-assert FAIL: the most-produced good (%) tiers as %, not common',
      v_max_code, public.good_rarity(v_max_good);
  end if;

  -- (h) THE OLD ABSOLUTE LAW IS GONE, not overloaded beside the new one. Requirement 4 of this
  --     slice, and the reason the function was dropped rather than replaced.
  if to_regprocedure('public.rarity_from_producers(int)') is not null then
    raise exception '0051 self-assert FAIL: public.rarity_from_producers(int) is still callable — 0032''s absolute thresholds survive beside the new law and a caller could choose between them';
  end if;
  if to_regprocedure('public.rarity_from_producers(int,numeric)') is null then
    raise exception '0051 self-assert FAIL: public.rarity_from_producers(int, numeric) does not exist — the law this file claims to install is not there';
  end if;

  -- (i) THE UNTOUCHED CALLERS STILL ASK THE ONE AUTHORITY, ONCE EACH. This file does not re-cut
  --     world.snapshot() or world.market(); the deployed bodies are read back to prove they still
  --     route through public.good_rarity and that nobody has inlined a second tiering beside it.
  v_def := pg_get_functiondef('world.snapshot()'::regprocedure);
  select count(*) into v_n from regexp_matches(v_def, 'public\.good_rarity\(', 'g');
  if v_n <> 1 then
    raise exception '0051 self-assert FAIL: world.snapshot() names public.good_rarity % time(s), not once — the catalogue is being tiered by something other than the one authority', v_n;
  end if;
  v_def := pg_get_functiondef('world.market(uuid)'::regprocedure);
  select count(*) into v_n from regexp_matches(v_def, 'public\.good_rarity\(', 'g');
  if v_n <> 1 then
    raise exception '0051 self-assert FAIL: world.market(uuid) names public.good_rarity % time(s), not once', v_n;
  end if;

  -- (j) THE WIRE SAYS WHAT THE AUTHORITY SAYS — snapshot, every row, not a sample.
  v_snap := world.snapshot();
  select count(*) into v_n from jsonb_array_elements(v_snap -> 'goods');
  if v_n <> v_goods then
    raise exception '0051 self-assert FAIL: snapshot serves % goods, the table holds %', v_n, v_goods;
  end if;
  select count(*) into v_bad
    from jsonb_array_elements(v_snap -> 'goods') elem
   where elem ->> 'rarity' is distinct from public.good_rarity((elem ->> 'id')::uuid)
      or elem ->> 'rarity' not in ('common', 'uncommon', 'rare', 'exotic');
  if v_bad <> 0 then
    raise exception '0051 self-assert FAIL: % snapshot good(s) serve a rarity that is not one of the four words the one authority answers', v_bad;
  end if;

  -- (k) THE CATALOGUE ACTUALLY RE-TIERED. The header claims this migration is NOT a no-op; a run in
  --     which nothing moved would mean the law never reached the payload, and every check above
  --     would still be green. Counted off the wire, old payload against new.
  select count(*) into v_moved
    from jsonb_array_elements((select snap from payload_before_0051) -> 'goods') o
    join jsonb_array_elements(v_snap -> 'goods') n2 on n2 ->> 'id' = o ->> 'id'
   where o ->> 'rarity' is distinct from n2 ->> 'rarity';
  if v_moved = 0 then
    raise exception '0051 self-assert FAIL: not one of % goods changed tier — this file claims to re-tier the catalogue and the wire says it did nothing', v_goods;
  end if;
  raise notice '0051 re-tiered % of % goods on the wire', v_moved, v_goods;

  -- (l) AND IT MOVED NOTHING ELSE — snapshot. The old payload was captured BEFORE any replace; the
  --     new one, stripped of `rarity`, must equal it exactly. Prose claiming "nothing else changed"
  --     is not evidence (docs/NO_SPAGHETTI.md §3 point 3).
  select jsonb_set(v_snap, '{goods}',
           (select jsonb_agg(elem - 'rarity' order by idx)
              from jsonb_array_elements(v_snap -> 'goods') with ordinality as t(elem, idx)))
    into v_stripped;
  if v_stripped <> (select jsonb_set(snap, '{goods}',
                             (select jsonb_agg(elem - 'rarity' order by idx)
                                from jsonb_array_elements(snap -> 'goods') with ordinality as t(elem, idx)))
                      from payload_before_0051) then
    raise exception '0051 self-assert FAIL: world.snapshot() minus `rarity` differs from what 0032 served — this supersede changed more than it declared';
  end if;

  -- (m) THE SAME TWO PROOFS FOR THE MARKET READ. now() is frozen in this transaction, so the drift
  --     slot cannot roll between the capture and this read and parity is exact, not probabilistic.
  select id into strict v_port from public.ports order by code limit 1;
  v_market := world.market(v_port);
  select count(*) into v_n from jsonb_array_elements(v_market -> 'goods');
  if v_n = 0 then
    raise exception '0051 self-assert FAIL: world.market() serves no goods — the market asserts would be vacuous';
  end if;
  select count(*) into v_bad
    from jsonb_array_elements(v_market -> 'goods') elem
   where elem ->> 'rarity' is distinct from public.good_rarity((elem ->> 'good_id')::uuid)
      or elem ->> 'rarity' not in ('common', 'uncommon', 'rare', 'exotic');
  if v_bad <> 0 then
    raise exception '0051 self-assert FAIL: % market row(s) serve a rarity that is not one of the four words the one authority answers', v_bad;
  end if;
  select jsonb_set(v_market, '{goods}',
           (select jsonb_agg(elem - 'rarity' order by idx)
              from jsonb_array_elements(v_market -> 'goods') with ordinality as t(elem, idx)))
    into v_stripped;
  if v_stripped <> (select jsonb_set(market, '{goods}',
                             (select jsonb_agg(elem - 'rarity' order by idx)
                                from jsonb_array_elements(market -> 'goods') with ordinality as t(elem, idx)))
                      from payload_before_0051) then
    raise exception '0051 self-assert FAIL: world.market() minus `rarity` differs from what 0032 served — this supersede changed more than it declared';
  end if;

  -- (n) THE POSTURE IS UNMOVED. The tier is served as a FIELD; neither the formula nor its
  --     yardstick is callable by a client, and the two halves of the write posture still read zero
  --     (supabase/migrations/README.md §3 — 0001 for tables, 0018 for security-definer writers).
  if has_function_privilege('anon',          'public.rarity_scale()', 'execute')
     or has_function_privilege('authenticated', 'public.rarity_scale()', 'execute')
     or has_function_privilege('anon',          'public.rarity_from_producers(int,numeric)', 'execute')
     or has_function_privilege('authenticated', 'public.rarity_from_producers(int,numeric)', 'execute')
     or has_function_privilege('anon',          'public.good_rarity(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.good_rarity(uuid)', 'execute') then
    raise exception '0051 self-assert FAIL: a client role may execute a rarity helper — neither the formula nor its yardstick may cross the wire';
  end if;
  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0051 self-assert FAIL: client_write_grants() found % write grant(s) after this migration', v_grants;
  end if;
  select count(*) into v_writers from public.client_executable_writers();
  if v_writers <> 0 then
    raise exception '0051 self-assert FAIL: client_executable_writers() found % client-executable writer(s)', v_writers;
  end if;

  drop table producers_0051;
  drop table payload_before_0051;

  raise notice '0051 self-assert ok: the thresholds are fractions of the world''s own mean producer count (mu = %), the law is scale-free over the whole catalogue at k = 2/3/7/17/50 with 0032''s absolute rule failing the same sweep as the control, all four tiers are reachable at every scale from mu = 1 to mu = 1000, % goods tier as exotic % / rare % / uncommon % / common % with the apex under a quarter and no tier over 40%%, 0032''s rarity_from_producers(int) is gone rather than overloaded, snapshot and market each ask the one authority exactly once, % goods re-tiered on the wire and every other field of both payloads is byte-identical to what 0032 served',
    round(v_mu, 3), v_goods, v_exotic, v_rare, v_uncommon, v_common, v_moved;
end $$;
