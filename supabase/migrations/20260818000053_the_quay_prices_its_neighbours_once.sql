-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0053 — THE QUAY PRICES ITS NEIGHBOURS ONCE
--        world.market() asked the price authority 9,720 times to draw one screen, and paid four
--        world_config lookups on every one of them. It asks once now, and the served numbers do
--        not move by a digit.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE DEFECT, AS MEASURED (2026-08-25, this machine, PGlite 0.5.5 / PostgreSQL 18.3) ─────────
-- MARKET is the screen a captain opens most. 0019's header records what it cost when the
-- catalogue held 70 goods:
--
--     world.market(LIS) BEFORE 0019   ~800 ms   (four %NBR walks per good)
--     world.market(LIS) after         ~245 ms   (one, behind a CTE fence)
--
-- The catalogue then went 70 -> 243 goods and 834 -> 1,310 specialty rows (0041, 0051's header),
-- and nobody was watching this number. Measured today, on the chain as it stands at 0052, by
-- applying it whole and timing the read after a warm call:
--
--     world.market(BOR)  1,442 ms   Bordeaux — 42 ports inside the 600 nm neighbourhood, the worst
--     world.market(BIL)  1,250 ms   Bilbao — 39
--     world.market(LIS)    881 ms   Lisbon — 24
--     world.market(MLE)    845 ms   8, the world's median
--     world.market(CLL)    584 ms   0 — an island with no neighbour at all, and still half a second
--
-- A THIRD OF A SECOND FOR AN ISLAND WITH NO NEIGHBOURS is the tell: the cost is not the
-- neighbourhood, it is what is asked of every good in it. And the same call on the same build
-- read 1,066 ms in one run and 2,740 ms in another twenty minutes later. Wall clock on this
-- machine is not a measurement instrument — other work was running — which is why the guard this
-- file lands is a count of WORK DONE and never a millisecond (see THE GUARDS).
--
-- I WAS ASKED TO REPRODUCE ~21,500 ms AND I COULD NOT. In the Node PGlite harness that
-- `npm run db:apply` and every SQL proof use, the worst port in the world measures 1.07 s and the
-- median 0.56 s. I am not able to say where 21.5 s came from and I will not invent a reason; the
-- two things I could not rule out are the BROWSER runtime — PGlite in a tab is the shipping engine
-- for local play, and `tests/appReady.fixture.ts:52` records this same 243-good world cold-booting
-- in 78.8 s there — and machine load, of which the 1,066 / 2,740 ms spread above is direct
-- evidence. What follows does not depend on which: the fix takes 243 world.pct_of_neighbours
-- calls, 9,720 world.mid_price calls and the 38,880 world_config reads inside them OUT of every
-- market read, and a call that is not made is not slow in any runtime.
--
-- ── THE PLAN'S VERDICT, IN MY OWN WORDS ────────────────────────────────────────────────────────
-- `explain (analyze, buffers)` on `select world.market(BOR)`, and then on its body hand-lifted so
-- the CTEs are visible:
--
--     Result … (actual time=1362.458..1362.489 rows=1) Buffers: shared hit=336872
--       CTE nbr  ->  Bitmap Heap Scan on port_goods pg (actual time=6.543..1026.299 rows=243)
--                      Buffers: shared hit=305396
--
-- 336,872 buffer hits to serve 243 rows, and 305,396 of them — 91% — are inside the `nbr` CTE,
-- which is 1,026 ms of the 1,185 ms the body spends. THE WHOLE COST IS %NBR. Everything else the
-- screen does is noise beside it: `world.price` over 243 goods is 33 ms, `public.good_rarity` 87,
-- the drift tick 12.
--
-- The CTE fence 0019 built is NOT the problem and is kept. It does exactly what its comment says —
-- it turns four neighbourhood walks per good into one. The problem is what ONE walk now costs, and
-- what it is a walk THROUGH. `world.pct_of_neighbours(port, good)` (0019:529) is a scalar, so the
-- fence calls it 243 times, and each call runs:
--
--     select avg(world.mid_price(o.id, p_good, pg.stock)) … 238 ports, ~40 of which stock the good
--
-- Two separate multiplications, and I measured which one matters rather than assuming:
--
--     the 243 neighbourhood scans (238 ports x 243 goods of haversine)          3 ms
--     the 9,720 world.mid_price() calls, neighbourhood computed once          514 ms
--       of which: the FOUR public.wc_num() knob reads inside each             321 ms
--     the identical arithmetic, set-based, the four knobs read once            42 ms
--
-- So the neighbourhood is free and the price authority is not. `world.mid_price` (0005:326) is a
-- plpgsql function, and a plpgsql function is a call: 9,720 of them, each opening a three-table
-- join and each re-reading `price_elasticity`, `mid_dev_discount`, `price_band_lo` and
-- `price_band_hi` out of `world_config` — 38,880 further plpgsql calls through `public.wc`
-- (0001:182) for four numbers that do not change while the statement runs. 62% OF THE MID'S COST
-- IS RE-READING FOUR CONSTANTS. At 70 goods that was 2,800 calls and invisible. At 243 it is the
-- screen.
--
-- ── THE MECHANISM ──────────────────────────────────────────────────────────────────────────────
-- Nothing about §G.1 changes, nothing about §E.4 changes, and no number moves. What changes is
-- WHERE the loop is: the rule is asked once for a set instead of once per row.
--
--   1. world.mid_from_terms(...) — NEW, and THE §G.1 mid arithmetic, now written in exactly one
--      place. It is a pure function of its eleven arguments: the six terms off the row, the stock,
--      and the four knobs. `language sql immutable parallel safe`, and — deliberately — NOT
--      `security definer` and with NO `set search_path`, because those two are precisely what
--      PostgreSQL's `inline_function()` refuses to inline. Inlined, calling it per row in a set
--      query costs nothing: the planner substitutes the expression. `voyage.gc_distance_nm`
--      (0002:34) is the standing precedent for that posture in this chain — a pure arithmetic
--      function that touches no table, qualifies no schema because it names only built-in
--      operators, and is inlined into every plan that uses it.
--
--   2. world.pct_of_neighbours_at(port, good default null) — NEW, and THE §E.4 body. It derives
--      the neighbourhood ONCE, reads the five knobs ONCE, and computes every good's index in a
--      single grouped pass. The nullable second argument NARROWS it to one good. That is 0019's
--      own shape for `world.trade_routes(p_to)`, and 0019's own words for why: "It is the same
--      shortlist, the same quotes and the same sail gate over a set of one, because a second
--      function for it would have been a second author of all three at once."
--
--   3. The three re-cuts below compose those two. Not one of them keeps a copy of anything.
--
-- ── SUPERSEDES ─────────────────────────────────────────────────────────────────────────────────
-- Three deployed functions are re-cut. Every one of them is a NO-OP ON VALUES — that is the whole
-- claim of this file, and §THE GUARDS proves it against pre-images captured in this same
-- transaction rather than asserting it in prose.
--
--   * world.mid_price(uuid, uuid, numeric) — SUPERSEDES 0005:326. Same name, same arguments, same
--     return, same `stable security definer set search_path = public, pg_temp`, same grants (it
--     has none, and none are re-issued). It still fetches the row, still raises E_NO_SUCH_GOOD on
--     a port that does not trade the good, still reads the four knobs. The six-factor product and
--     the §G.7.3 band are no longer WRITTEN there — they are handed to world.mid_from_terms. Cost
--     to this caller: unchanged, because the callee is inlined into it.
--
--   * world.pct_of_neighbours(uuid, uuid) — SUPERSEDES 0019:529 (which itself superseded 0009:39
--     in one respect). Same name, arguments, return, volatility, security and grants. Its body is
--     now one line: the narrowed call to world.pct_of_neighbours_at. The radius, the haversine,
--     the average and the round left it — they did not multiply, they MOVED.
--     THE ONE BEHAVIOURAL EDGE, NAMED: on the old body a NULL p_good fell through to a null
--     v_here and returned null. `p_good => null` is the WIDE call on the new authority, so the
--     scalar carries `where p_good is not null` to keep the old answer. No caller passes null;
--     the clause is there so that the narrowing argument's contract cannot be read two ways.
--
--   * world.market(uuid) — SUPERSEDES 0032:189 (which superseded 0029:132, 0019:568, 0009:115).
--     ONE HUNK MOVES: the `nbr` CTE stops calling the scalar per good and reads the set authority
--     once. Nothing else in that body is retyped — it is SLICED out of the DEPLOYED definition
--     with `pg_temp.recut`, the tool 0050:120 established, which refuses unless the hunk occurs
--     exactly once in `pg_get_functiondef`. A drifted deployment therefore refuses rather than
--     half-applies. The 0019 comment above the CTE is sliced with it, because it quotes a
--     measurement ("1,303 ms with the lateral, 245 ms with this CTE") that this file makes false,
--     and a comment that lies is worse than no comment.
--
-- ── ONE AUTHORITY — the argument, since a performance slice is where second paths get born ─────
-- docs/NO_SPAGHETTI.md §3 forbids buying speed with a second copy of a rule. Nothing here is a
-- copy:
--   * NO CACHE TABLE, NO MATERIALISED VIEW, NO STORED PRICE. §G's founding rule — 0005's title,
--     "every price is derived, never stored" — is untouched. A cached %NBR would be a number that
--     can disagree with the market it describes the moment the drift walks, which is every ten
--     game-minutes.
--   * NO SECOND PRICING PATH. world.mid_price does not compute a mid any more; it FETCHES and
--     DELEGATES. world.pct_of_neighbours_at delegates to the same function. There is exactly one
--     expression in the schema that turns terms into a mid, and it is world.mid_from_terms. The
--     guard proves that behaviourally — all 54,432 (port, good) mids and a five-point hypothetical
--     stock sweep must equal the pre-image to the digit — and textually: world.mid_price's
--     deployed body must no longer contain `power(` at all.
--   * NO SECOND %NBR. world.pct_of_neighbours' deployed body must contain neither
--     `gc_distance_nm` nor `mid_price` when this file finishes. The scalar and the set are one
--     body with a narrowing argument, which is composition; two bodies would not be.
--   * AND THE PRICE RULE IS PROVEN, NOT ASSERTED. Values are the thing another slice is measuring
--     on top of right now, so parity is not sampled: it is every mid in the world, the full
--     world.market payload byte-for-byte at six ports chosen to include the extremes, and every
--     one of 243 %NBR answers at each of them.
--
-- ── THE ALTERNATIVES, AND WHY NOT ──────────────────────────────────────────────────────────────
--   * AN INDEX. Rejected, and measured first: there is nothing to index. The neighbourhood filter
--     is a haversine over 238 rows — a sequential scan is the right plan and it costs 3 ms across
--     all 243 goods. The per-good lookups already ride `port_goods_pkey` (Bitmap Index Scan,
--     0.009 ms x 42 in the plan above). An index here would cost write amplification on every
--     drift tick — 54,432 rows every ten game-minutes, which is every thirty REAL seconds at
--     0045's compression — and buy nothing.
--   * WIDENING THE CTE FENCE / DROPPING IT. Rejected: the fence is load-bearing and 0019 measured
--     why. Removing `materialized` restores 1,303 ms of lateral re-evaluation on top of this.
--   * MAKING public.wc CHEAP INSTEAD. Tempting — 321 ms of the 514 is knob reads — but it changes
--     a chain-wide authority (0001) for a benefit local to one screen, and it does not remove the
--     9,720 plpgsql calls around them. Measured ceiling for that route: ~700 ms at BOR, against
--     the 241 ms measured for the route taken. Rejected on both counts.
--   * CACHING %NBR PER SLOT IN A TABLE. Rejected under §3 above. It is also unnecessary now.
--   * FIXING public.good_rarity TOO. NOT DONE, and named rather than hidden: it is 87 ms of the
--     ~240 that remain, now the largest single item in the read, because 0051 made it derive the
--     world's scale and 0032's callers ask it once per good. It is a real cost and it is a
--     DIFFERENT slice — 0051 is a day old, it is the newest authority in this area, and the brief
--     for this one is the regression, which is %NBR. It is written down here so the next hand does
--     not have to measure it again.
--
-- ── WHAT IT COSTS, MEASURED ────────────────────────────────────────────────────────────────────
-- Before and after, in ONE process — chain applied to 0052, measured, this file applied, measured
-- again — so the ratio is not a wall-clock lottery (2026-08-25):
--
--     port  neighbours   before     after
--     BOR      42      1,442 ms    241 ms
--     BIL      39      1,250 ms    218 ms
--     GOA      36      1,420 ms    223 ms
--     LIS      24        881 ms    250 ms
--     MLE       8        845 ms    247 ms
--     CLL       0        584 ms    188 ms
--
--     world.pct_of_neighbours_at(BOR), all 243 goods    57 ms   (was 1,026 ms as 243 scalars)
--     world.pct_of_neighbours(BOR, one good)            11 ms   (was 5 ms — the narrowed call pays
--                                                                one CTE setup and one SRF it did
--                                                                not pay before. Its callers are
--                                                                0019's self-assert and proofs/04,
--                                                                never a loop a player waits on;
--                                                                the trade for the read a player
--                                                                DOES wait on is taken knowingly)
--
-- A SECOND CONTROLLED RUN, same procedure, read 1,095 -> 336 ms at BOR where this one read
-- 1,442 -> 241. That is a factor of 3.3 and a factor of 6.0 for the same change on the same data,
-- and it is exactly why no millisecond is asserted below. The invariant across both runs is the
-- WORK: 331,470 buffers -> 40,530 for one read of Bordeaux, 8.2x, and buffers do not care what
-- else the machine is doing.
--
-- The read is also now flat in the shape of the port instead of proportional to how many
-- neighbours it has, which was the real defect: an island with no neighbour at all and the busiest
-- roadstead in Biscay now cost about the same.
--
-- ── THE GUARDS — the property, never the clock ─────────────────────────────────────────────────
-- This project already regrets two flaky wall-clock gates, so no millisecond is asserted. What is
-- asserted is the WORK DONE and the SHAPE that makes it small:
--
--   (a) VALUE IDENTITY, four ways, all against pre-images captured before anything is replaced:
--       every one of 54,432 mids in the world; a 7,290-row hypothetical-stock sweep (0, 1, half,
--       triple, 1e9) because world.quote steps stock through the book and the current-stock rows
--       alone would leave the §G.7.3 band unproven; the FULL world.market payload, byte for byte,
--       at six ports chosen to include the crowdedest neighbourhood and an empty one; and 268
--       answers from the SCALAR door, which has callers of its own that the payload never touches.
--   (b) THE WORK, RELATIVELY: `explain (analyze, buffers)` on the SAME call, before the re-cut and
--       after, in this transaction. The new body must touch at most a THIRD of the buffers the
--       old one did. A ratio has no units and no machine in it, so it cannot go flaky the way a
--       millisecond does — and it fails the instant the read goes back to walking the
--       neighbourhood once per good. **The ratio is only reachable through the index section 0
--       creates**: on PostgreSQL 17 without it the same body costs 127x and this guard reads the
--       change as a regression, which is exactly what it did on 2026-08-25 before section 0
--       existed. Measured ratio on a clean apply: 8.2x; the guard demands 3x,
--       because the break-test harness reads 5.8x for the very same file and a guard is sized on
--       the worst honest reading. The old shape scores about 1x, so 3x still refuses it outright.
--   (c) THE SHAPE, read back off the DEPLOYED catalogue: world.market names
--       world.pct_of_neighbours_at exactly once and world.pct_of_neighbours not at all;
--       world.pct_of_neighbours names the set authority once and contains no haversine and no
--       mid; world.mid_price names world.mid_from_terms once and contains no `power(`.
--   (d) THE INLINE PRECONDITION: world.mid_from_terms must be SQL, IMMUTABLE, NOT security
--       definer and carry NO proconfig. Those four are exactly what PostgreSQL requires to inline
--       an SQL function, and the reflex in this chain is to write `security definer set
--       search_path` on everything — which would silently return 9,720 real function calls to the
--       read while every value stayed correct. The guard names the reason in its own message.
--   (e) THE POSTURE: 0 client write grants, 0 client-executable writers, and neither new function
--       executable by anon or authenticated.
--
-- Every one of those guards was made to fire on purpose before this file was committed;
-- scripts/db/breaktest-0053.mjs is that harness, and it lives there rather than here because
-- commit bfd37c7 is where a break-test contaminated the migration it was proving.
--
-- Depends on: 0001 (wc/wc_num, the lockdown, client_write_grants), 0002 (gc_distance_nm, ports),
--             0005 (mid_price, price, the §G.1 terms), 0009/0019 (%NBR and its radius knob),
--             0010 (tick_market_drift), 0018 (client_executable_writers), 0029/0032 (the deployed
--             world.market body this file slices), 0050 (pg_temp.recut, the slice tool).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. THE SLICE TOOL — replace hunks that must occur exactly once, else refuse ────────────────
-- 0050:120's tool, carried here because a pg_temp function lives and dies with its own
-- transaction and cannot be inherited (tests/duplication.spec.ts:370 records exactly that).
create or replace function pg_temp.recut(p_fn regprocedure, p_drop boolean, variadic p_edits text[])
returns void
language plpgsql
as $$
declare
  v_def text := pg_get_functiondef(p_fn);
  v_i   int := 1;
  v_n   int;
begin
  while v_i < array_length(p_edits, 1) loop
    v_n := (length(v_def) - length(replace(v_def, p_edits[v_i], ''))) / length(p_edits[v_i]);
    if v_n <> 1 then
      raise exception '0053 slice: hunk % of % occurs % time(s) in %, expected exactly 1 — the deployed body is not what this migration was generated against.',
        (v_i + 1) / 2, (array_length(p_edits, 1)) / 2, v_n, p_fn;
    end if;
    v_def := replace(v_def, p_edits[v_i], p_edits[v_i + 1]);
    v_i := v_i + 2;
  end loop;
  if p_drop then
    execute format('drop function %s', p_fn::text);
  end if;
  execute v_def;
end $$;

-- ── 0. THE ACCESS PATH THE NEIGHBOURHOOD WALK HAS ALWAYS NEEDED ───────────────────────────────
-- ADDED 2026-08-26, after this file passed on PGlite and FAILED on the engine production runs.
--
-- MEASURED ON POSTGRESQL 17.6 — `supabase/config.toml` pins `major_version = 17`, and the
-- apply-proof job's disposable Supabase is the only PostgreSQL 17 this project can reach:
--
--     world.pct_of_neighbours_at(BOR), body LIFTED INLINE as a plain query     4,400 buffers
--     the same body, called as a FUNCTION                                    298,087 buffers
--     the same call, with this index in place                                  2,352 buffers
--     one whole world.market(BOR) read, with this index                       23,158 buffers
--                                        ... against the old body's          271,229 buffers
--
-- THE 127x IS NOT THE BODY AND IT IS NOT THE INLINING. `world.mid_from_terms` never appears as a
-- node in the lifted plan, so the planner IS substituting it, exactly as guard (d) requires. The
-- cost is `public.port_goods`, whose primary key is (port_id, good_id): the join `pg.good_id =
-- h.good_id` inside `them` has NO index to walk, and the plan PostgreSQL 17 chooses for the
-- function's cached, generically-parameterised body rescans the whole 54,432-row table where a
-- single good has about forty rows. PostgreSQL 18 — PGlite, where this file was written and
-- measured at 8.2x — hash-joins once and never pays it. That is the entire distance between
-- "8.2x" and "the read got slower", and it was invisible until the file met a real 17.
--
-- So this index is NOT a knob added to make a guard pass. It is the access path DESIGN §E.4's
-- neighbourhood walk has needed since 0005 created the table, and its absence was masked by a
-- development engine that could plan around it. It is created BEFORE the pre-images below, so
-- both sides of the buffer comparison are measured with it and the ratio stays honest.
create index if not exists port_goods_good_id_idx on public.port_goods (good_id);
comment on index public.port_goods_good_id_idx is
  'The good-side access path for DESIGN E.4. port_goods'' primary key is (port_id, good_id), so '
  '"every port that stocks THIS good" — what world.pct_of_neighbours_at asks once per quay — had '
  'no index at all. Measured on PostgreSQL 17.6: 298,087 buffers without it, 2,352 with. Do not '
  'drop it; 0053''s self-assert checks it is still there.';
analyze public.port_goods;

-- ── 1. THE PRE-IMAGES, captured before anything is replaced ────────────────────────────────────
-- Within this transaction now() is frozen and the drift slot cannot roll, so parity below is
-- EXACT rather than probable — 0051:240's argument, and the reason the whole payload can be
-- compared including its `clock` object.
--
-- The subject ports are chosen deterministically AND to include the extremes of the thing this
-- file changes: the port with the most neighbours, the one with the fewest, and the first four by
-- code. Heap order is never trusted (docs/NO_SPAGHETTI.md §4).
create temporary table subjects_0053 as
  with nbrs as (
    select p.id, p.code,
           (select count(*) from public.ports o
             where o.id <> p.id
               and voyage.gc_distance_nm(p.lat::float8, p.lon::float8, o.lat::float8, o.lon::float8)
                   <= public.wc_num('neighbour_radius_nm')) as n
      from public.ports p
     where exists (select 1 from public.port_goods pg where pg.port_id = p.id)
  )
  select id, code, n from (
      (select id, code, n from nbrs order by n desc, code limit 1)
    union
      (select id, code, n from nbrs order by n asc,  code limit 1)
    union
      (select id, code, n from nbrs order by code limit 4)
  ) s;

-- The market drift is wound ONCE here so that neither `explain analyze` below pays for an update
-- the other did not — the tick is idempotent by slot (0010:115), and this makes both sides of the
-- buffer comparison measure the READ and nothing else.
select public.tick_market_drift(now());

create temporary table market_before_0053 as
select s.code, world.market(s.id) as payload from subjects_0053 s;

create temporary table mids_before_0053 as
select pg.port_id, pg.good_id, world.mid_price(pg.port_id, pg.good_id, pg.stock) as mid
  from public.port_goods pg;

-- world.quote steps the stock down through the book (§G.2), so mid_price is asked for stocks the
-- warehouse does not hold. Parity on today's stock alone would leave the §G.7.3 band — the only
-- part of the expression that fires at the extremes — completely unproven.
create temporary table sweep_before_0053 as
select pg.port_id, pg.good_id, s.st, world.mid_price(pg.port_id, pg.good_id, s.st) as mid
  from public.port_goods pg
  cross join lateral (values (0::numeric), (1::numeric), (pg.stock / 2), (pg.stock * 3), (1e9::numeric)) s(st)
 where pg.port_id in (select id from subjects_0053);

-- The SCALAR door, kept separately from the payload parity above because it has callers of its
-- own (0019's self-assert, scripts/db/proofs/04) that the payload would not exercise. Every good
-- at the busiest quay, plus a cross-port sample, rather than every good at every subject: the
-- payload comparison already carries `pct_nbr` for all 243 goods at all six ports, and asking the
-- scalar 1,458 times would add twenty seconds to the chain to re-prove it.
create temporary table pct_before_0053 as
  select s.code, pg.good_id, world.pct_of_neighbours(s.id, pg.good_id) as pct
    from subjects_0053 s
    join public.port_goods pg on pg.port_id = s.id
   where s.id = (select id from subjects_0053 order by n desc, code limit 1)
union all
  select s.code, x.good_id, world.pct_of_neighbours(s.id, x.good_id)
    from subjects_0053 s
    cross join lateral (
      select pg.good_id from public.port_goods pg
        join public.goods g on g.id = pg.good_id
       where pg.port_id = s.id order by g.code limit 5) x
   where s.id <> (select id from subjects_0053 order by n desc, code limit 1);

-- The work the OLD read does, in buffers rather than in milliseconds. See THE GUARDS (b).
create temporary table buffers_0053 (phase text primary key, blocks bigint);
do $$
declare
  v_id   uuid := (select id from subjects_0053 order by n desc, code limit 1);
  v_json json;
begin
  execute format('explain (analyze, buffers, format json) select world.market(%L::uuid)', v_id) into v_json;
  insert into buffers_0053 values ('before',
    coalesce((v_json -> 0 -> 'Plan' ->> 'Shared Hit Blocks')::bigint, 0)
  + coalesce((v_json -> 0 -> 'Plan' ->> 'Shared Read Blocks')::bigint, 0));
end $$;

-- ── 2. THE §G.1 MID, WRITTEN ONCE ──────────────────────────────────────────────────────────────
-- `create`, not `create or replace`: this file claims the function is NEW, and a bare create is
-- that claim enforced by the engine rather than asserted in prose (0051:252's convention).
--
-- THE POSTURE IS THE POINT AND IT IS NOT AN OVERSIGHT. No `security definer`, no
-- `set search_path`: PostgreSQL's inline_function() refuses both, and an un-inlined callee here
-- would put all 9,720 calls back. It touches no table, no schema-qualified object and no knob —
-- it is a pure function of its eleven arguments, exactly like voyage.gc_distance_nm (0002:34),
-- and the only names in its body are built-in numeric operators. Everything that reads the world
-- stays with the callers, where the volatility belongs.
create function world.mid_from_terms(
  p_base         numeric,   -- goods.base_value
  p_affinity     numeric,   -- port_goods.affinity
  p_stock_target numeric,   -- port_goods.stock_target
  p_stock        numeric,   -- the stock to price AT — today's, or a hypothetical one from the book
  p_drift        numeric,   -- port_goods.drift
  p_season       numeric,   -- port_goods.season_mod
  p_dev          int,       -- ports.dev_commerce
  p_elasticity   numeric,   -- wc price_elasticity
  p_dev_discount numeric,   -- wc mid_dev_discount
  p_band_lo      numeric,   -- wc price_band_lo
  p_band_hi      numeric    -- wc price_band_hi
) returns numeric
language sql
immutable
parallel safe
as $$
  -- DESIGN G.1, term by term, and §G.7.3's hard band around it. Moved here verbatim from
  -- 0005:355-365; not one operator, coefficient or rounding is different. Officer purchasing and
  -- sales bonuses are still NOT applied — §K.1 keeps officers out of the mid, and this file does
  -- not open that door either.
  select round(least(greatest(
             p_base
           * p_affinity
           * power(p_stock_target / greatest(p_stock, 1), p_elasticity)
           * (1 + p_drift)
           * (1 + p_season)
           * (1 - p_dev_discount * p_dev),
           p_band_lo * p_base), p_band_hi * p_base), 4)
$$;

comment on function world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, int, numeric, numeric, numeric, numeric) is
  'THE §G.1 mid, and the only place in the schema that expression is written (0053). A pure '
  'function of its arguments: the six terms off the row, the stock being priced at, and the four '
  'knobs. IMMUTABLE, no security definer, no search_path — deliberately, because those are what '
  'PostgreSQL needs in order to INLINE it, and inlining is what lets world.pct_of_neighbours_at '
  'price a whole neighbourhood without paying 9,720 function calls. world.mid_price is its '
  'row-at-a-time caller; do not add a second one that reads the world.';

revoke all on function world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, int, numeric, numeric, numeric, numeric) from public, anon, authenticated;

-- ── 3. SUPERSEDES 0005:326 — the mid fetches and delegates; it no longer computes ──────────────
create or replace function world.mid_price(p_port uuid, p_good uuid, p_stock numeric)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_base   numeric;
  v_aff    numeric;
  v_target numeric;
  v_drift  numeric;
  v_season numeric;
  v_dev    int;
begin
  select g.base_value, pg.affinity, pg.stock_target, pg.drift, pg.season_mod, p.dev_commerce
    into v_base, v_aff, v_target, v_drift, v_season, v_dev
    from public.port_goods pg
    join public.goods g on g.id = pg.good_id
    join public.ports p on p.id = pg.port_id
   where pg.port_id = p_port and pg.good_id = p_good;

  if v_base is null then
    raise exception 'E_NO_SUCH_GOOD: no market row for port % good %', p_port, p_good using errcode = 'P0001';
  end if;

  -- The arithmetic left this body in 0053; it did not multiply. This is the row-at-a-time door to
  -- the one expression, and it costs exactly what it cost before, because the callee is inlined.
  return world.mid_from_terms(v_base, v_aff, v_target, p_stock, v_drift, v_season, v_dev,
                              public.wc_num('price_elasticity'), public.wc_num('mid_dev_discount'),
                              public.wc_num('price_band_lo'),    public.wc_num('price_band_hi'));
end $$;

comment on function world.mid_price(uuid, uuid, numeric) is
  'One (port, good) mid at a stated stock (DESIGN G.1). SUPERSEDES 0005:326: same signature, same '
  'volatility, same security, same values to the digit — the six-factor product and the §G.7.3 '
  'band moved into world.mid_from_terms so that they are written once. This function''s job is now '
  'the row fetch, E_NO_SUCH_GOOD, and the four knobs.';

-- ── 4. §E.4 %NBR, AS A SET — the neighbourhood once, the knobs once, every good in one pass ────
-- The nullable p_good NARROWS the same body to one good rather than forking a second one. That is
-- world.trade_routes(p_to)'s shape (0019), for 0019's reason.
create function world.pct_of_neighbours_at(p_port uuid, p_good uuid default null)
returns table (good_id uuid, pct numeric)
language sql
stable
security definer
set search_path = public, pg_temp
-- PLAN THIS FOR THE PORT IT IS ASKED ABOUT, EVERY TIME. Measured on PostgreSQL 17.6 (section 0):
-- the first few calls are planned against the actual uuid and cost 2,352 buffers; after the fifth,
-- PostgreSQL's plancache compares a GENERIC plan and keeps it, and the generic plan — which cannot
-- know which port, so it cannot estimate the forty-odd rows a good has — rescans the whole 54,432
-- row table and costs 298,087. Values never move, so nothing goes red; the read simply becomes two
-- orders of magnitude more expensive on the sixth call of a session and stays there. PGlite's
-- PostgreSQL 18 never showed this, which is why the file shipped measuring 8.2x.
set plan_cache_mode = 'force_custom_plan'
as $$
  -- The five knobs, read ONCE per call instead of once per (good, neighbour). `materialized` is
  -- load-bearing on all three fences below for 0019's reason: without it the planner substitutes
  -- the expression at every reference and the "once" stops being once.
  with k as materialized (
    select public.wc_num('neighbour_radius_nm') as radius,
           public.wc_num('price_elasticity')    as elasticity,
           public.wc_num('mid_dev_discount')    as dev_discount,
           public.wc_num('price_band_lo')       as band_lo,
           public.wc_num('price_band_hi')       as band_hi
  ),
  -- "prices vs ports within N nm" (DESIGN E.4). Great-circle, not leg distance: this is a
  -- NEIGHBOURHOOD, not a route, and a port two short legs away is still a neighbour. 0019's
  -- words, and 0019's rule — the radius is still the knob, never a literal.
  nbr as materialized (
    select o.id, o.dev_commerce
      from public.ports here
      join public.ports o on o.id <> here.id
     cross join k
     where here.id = p_port
       and voyage.gc_distance_nm(here.lat::float8, here.lon::float8, o.lat::float8, o.lon::float8)
           <= k.radius
  ),
  -- This quay's own mid, per good. A good this port does not trade has no row here and therefore
  -- no answer at all — which is what the scalar returned on a null v_here.
  here as materialized (
    select pg.good_id,
           world.mid_from_terms(g.base_value, pg.affinity, pg.stock_target, pg.stock,
                                pg.drift, pg.season_mod, p.dev_commerce,
                                k.elasticity, k.dev_discount, k.band_lo, k.band_hi) as mid
      from public.port_goods pg
      join public.goods g on g.id = pg.good_id
      join public.ports p on p.id = pg.port_id
     cross join k
     where pg.port_id = p_port
       and (p_good is null or pg.good_id = p_good)
  ),
  -- And the neighbourhood's, averaged. Same multiset the scalar averaged, same authority for each
  -- member — world.mid_from_terms, inlined, so this is column arithmetic rather than 9,720 calls.
  them as (
    select h.good_id,
           avg(world.mid_from_terms(g.base_value, pg.affinity, pg.stock_target, pg.stock,
                                    pg.drift, pg.season_mod, n.dev_commerce,
                                    k.elasticity, k.dev_discount, k.band_lo, k.band_hi)) as mid
      from here h
      join public.port_goods pg on pg.good_id = h.good_id
      join nbr n on n.id = pg.port_id
      join public.goods g on g.id = pg.good_id
     cross join k
     group by h.good_id
  )
  -- A port with no neighbour that stocks the good, and a neighbourhood that averages to zero,
  -- both answer null — 0009's rule, unchanged.
  select h.good_id,
         case when t.mid is null or t.mid = 0 then null
              else round(h.mid / t.mid * 100, 1) end
    from here h
    left join them t on t.good_id = h.good_id
$$;

comment on function world.pct_of_neighbours_at(uuid, uuid) is
  'DESIGN E.4 %NBR for a whole quay in one pass (0053), and THE body of that rule. The '
  'neighbourhood and the five knobs are derived once per call instead of once per good, which is '
  'the whole of what this file bought world.market. The second argument NARROWS it to one good; '
  'null means every good this port trades. world.pct_of_neighbours(port, good) is the narrowed '
  'call under its old name, and it is the only scalar door — do not write a second one.';

revoke all on function world.pct_of_neighbours_at(uuid, uuid) from public, anon, authenticated;

-- ── 5. SUPERSEDES 0019:529 — the scalar keeps its name and its answer, and loses its body ──────
create or replace function world.pct_of_neighbours(p_port uuid, p_good uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- `where p_good is not null` is not defensive noise: on the set authority a null good is the
  -- WIDE call, and the body this supersedes answered null. The old answer is kept deliberately.
  select a.pct
    from world.pct_of_neighbours_at(p_port, p_good) a
   where p_good is not null
$$;

comment on function world.pct_of_neighbours(uuid, uuid) is
  'DESIGN E.4 %NBR for one (port, good). SUPERSEDES 0019:529: same signature, same volatility, '
  'same security, same answer on every input — the radius, the haversine, the average and the '
  'round moved into world.pct_of_neighbours_at, which this now composes. It is a LOCAL PRICE '
  'INDEX and it is honest about that; it is not, and was never able to be, a prediction of profit '
  '— world.trade_routes is. (0019''s sentence, kept with 0019''s meaning.)';

revoke all on function world.pct_of_neighbours(uuid, uuid) from public, anon;
grant execute on function world.pct_of_neighbours(uuid, uuid) to authenticated;

-- ── 6. SUPERSEDES 0032:189 — one hunk of world.market, sliced out of the deployed body ─────────
-- Nothing else in that function is retyped, so nothing else in it can drift. The tool refuses
-- unless the hunk occurs exactly once in pg_get_functiondef.
select pg_temp.recut('world.market(uuid)'::regprocedure, false,
  -- The comment goes with the code it describes: it quotes a measurement this file makes false.
  '  -- MATERIALIZED, and that word is load-bearing. `cross join lateral (select
  -- world.pct_of_neighbours(...))` reads as one call per good and is NOT: the planner pulls the
  -- sublink up and substitutes the expression at every reference, so four references cost four
  -- neighbourhood walks — which is precisely what 0009 was doing by hand. Measured on this chain:
  -- 1,303 ms with the lateral, 245 ms with this CTE. A fence is the only thing that makes "once"
  -- mean once. (0019''s words, kept with 0019''s body.)
  with nbr as materialized (
    select pg.good_id, world.pct_of_neighbours(p_port, pg.good_id) as pct
      from public.port_goods pg
     where pg.port_id = p_port
  ),',
  '  -- MATERIALIZED, and that word is still load-bearing: without the fence the planner
  -- substitutes the expression at every reference and "once" stops meaning once (0019). What
  -- changed in 0053 is WHAT is fenced. The scalar world.pct_of_neighbours walked the
  -- neighbourhood and priced it per GOOD — 243 walks and 9,720 world.mid_price calls to draw one
  -- screen, measured at 1,026 ms of a 1,185 ms body at Bordeaux. world.pct_of_neighbours_at is
  -- the same §E.4 rule asked ONCE for the whole quay: 57 ms, same numbers to the digit.
  with nbr as materialized (
    select a.good_id, a.pct from world.pct_of_neighbours_at(p_port) a
  ),');

comment on function world.market(uuid) is
  'One quay''s prices (0019), their CLOCK (0029: winds public.tick_market_drift before pricing — '
  'the read is the catch-up — and serves clock.now / clock.next_change_at), each row''s rarity '
  'from public.good_rarity (0032), and since 0053 its %NBR from world.pct_of_neighbours_at — one '
  'pass over the neighbourhood instead of one per good. SUPERSEDES 0032:189 by slice; the served '
  'payload is byte-identical.';

-- ── 7. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_subjects  int;
  v_goods     int;
  v_mids      int;
  v_sweep     int;
  v_pcts      int;
  v_bad       int;
  v_code      text;
  v_id        uuid;
  v_json      json;
  v_after     bigint;
  v_before    bigint;
  v_def       text;
  v_n         int;
  v_grants    int;
  v_writers   int;
  v_narrow    int;
  v_nbr_max   int;
  v_nbr_min   int;
begin
  -- ── (0) THE PRE-IMAGES ARE REAL. Every comparison below is worthless over an empty set, and a
  --        vacuous assert reads as coverage it never had (README §3).
  select count(*) into v_subjects from subjects_0053;
  select count(*) into v_goods    from public.goods;
  select count(*) into v_mids     from mids_before_0053;
  select count(*) into v_sweep    from sweep_before_0053;
  select count(*) into v_pcts     from pct_before_0053;
  select max(n), min(n) into v_nbr_max, v_nbr_min from subjects_0053;
  if v_subjects < 5 or v_goods < 100 or v_mids < 10000 or v_sweep < 500 or v_pcts < 200 then
    raise exception '0053 self-assert FAIL: the pre-images are too thin to prove anything — % subject port(s), % good(s), % mid(s), % sweep row(s), % %%NBR row(s)',
      v_subjects, v_goods, v_mids, v_sweep, v_pcts;
  end if;
  -- and they must span the thing this file changes, or "the payload did not move" is a claim
  -- about six ports that all look alike.
  if v_nbr_max < 10 or v_nbr_min <> 0 then
    raise exception '0053 self-assert FAIL: the subject ports do not span the neighbourhood extremes — busiest has % neighbour(s), quietest has % (expected a crowded one and one with none)',
      v_nbr_max, v_nbr_min;
  end if;

  -- ── (a1) EVERY MID IN THE WORLD IS THE MID IT WAS. 54,432 of them, at today's stock.
  select count(*) into v_bad
    from mids_before_0053 b
    join public.port_goods pg on pg.port_id = b.port_id and pg.good_id = b.good_id
   where world.mid_price(b.port_id, b.good_id, pg.stock) is distinct from b.mid;
  if v_bad <> 0 then
    raise exception '0053 self-assert FAIL: % of % mid(s) moved — world.mid_from_terms is not the expression 0005 was computing, and this file has changed the economy', v_bad, v_mids;
  end if;

  -- ── (a2) AND AT STOCKS THE WAREHOUSE DOES NOT HOLD, because world.quote steps the book through
  --         them and §G.7.3's band only fires at the extremes.
  select count(*) into v_bad
    from sweep_before_0053 b
   where world.mid_price(b.port_id, b.good_id, b.st) is distinct from b.mid;
  if v_bad <> 0 then
    raise exception '0053 self-assert FAIL: % of % hypothetical-stock mid(s) moved — the §G.7.3 band or the elasticity term is not what 0005 wrote', v_bad, v_sweep;
  end if;

  -- ── (a3) THE SCALAR DOOR STILL ANSWERS WHAT IT ANSWERED — every good at the busiest quay, and
  --         a cross-port sample. Its callers (0019's own assert, proofs/04) go through this name.
  select count(*) into v_bad
    from pct_before_0053 b
    join subjects_0053 s on s.code = b.code
   where world.pct_of_neighbours(s.id, b.good_id) is distinct from b.pct;
  if v_bad <> 0 then
    raise exception '0053 self-assert FAIL: % of % %%NBR answer(s) moved — the set authority is not averaging the multiset 0019 averaged', v_bad, v_pcts;
  end if;

  -- ── (a4) THE NARROWED CALL AND THE WIDE CALL ARE ONE BODY, not two that happen to agree today.
  --         Every good at the busiest quay — 243 narrowed calls against one wide one. Running it
  --         at all six would be 1,458 narrowed calls for twenty more seconds of chain and no more
  --         proof: what is under test is the p_good branch, not the port.
  select id into v_id from subjects_0053 order by n desc, code limit 1;
  select count(*) into v_bad
    from world.pct_of_neighbours_at(v_id) w
   where w.pct is distinct from world.pct_of_neighbours(v_id, w.good_id);
  if v_bad <> 0 then
    raise exception '0053 self-assert FAIL: % row(s) where the wide call and the narrowed call disagree — the nullable good is not narrowing the same rule', v_bad;
  end if;

  -- ── (a5) THE WHOLE PAYLOAD, BYTE FOR BYTE. now() is frozen in this transaction and the drift
  --         slot was wound before the capture, so `clock` is compared too rather than excused.
  select count(*) into v_bad
    from market_before_0053 b
    join subjects_0053 s on s.code = b.code
   where world.market(s.id)::text is distinct from b.payload::text;
  if v_bad <> 0 then
    select b.code into v_code
      from market_before_0053 b
      join subjects_0053 s on s.code = b.code
     where world.market(s.id)::text is distinct from b.payload::text
     order by b.code limit 1;
    raise exception '0053 self-assert FAIL: world.market() serves a different payload at % of % port(s) — first is % — this was to be a performance slice and it has moved the game', v_bad, v_subjects, v_code;
  end if;
  -- non-vacuity of (a5): the payloads compared must actually carry the goods.
  select min(jsonb_array_length(b.payload -> 'goods')) into v_n from market_before_0053 b;
  if v_n < 100 then
    raise exception '0053 self-assert FAIL: the payload parity ran against payloads carrying only % good(s) — it proved nothing', v_n;
  end if;

  -- ── (b) THE WORK, RELATIVELY. Same call, same transaction, buffers not milliseconds. A ratio
  --        has no machine in it, which is why this is the gate and no wall clock is.
  execute format('explain (analyze, buffers, format json) select world.market(%L::uuid)', v_id) into v_json;
  v_after := coalesce((v_json -> 0 -> 'Plan' ->> 'Shared Hit Blocks')::bigint, 0)
           + coalesce((v_json -> 0 -> 'Plan' ->> 'Shared Read Blocks')::bigint, 0);
  select blocks into v_before from buffers_0053 where phase = 'before';
  if v_before is null or v_before < 10000 then
    raise exception '0053 self-assert FAIL: the BEFORE buffer reading is % — the instrument is not measuring the old read, so the comparison below would pass vacuously', v_before;
  end if;
  -- 3x, not the 8.2x measured on a clean apply. scripts/db/breaktest-0053.mjs reads 5.8x for the
  -- unmutated file, because it runs after a dozen rolled-back transactions and the page cache is
  -- not the same one — so the honest ceiling is the WORST honest reading, not the best. The old
  -- shape scores about 1x, so 3x still refuses it outright: this is a floor under the change, not
  -- a target to hit.
  if v_after * 3 > v_before then
    raise exception '0053 self-assert FAIL: one world.market() read still touches % buffer(s) against the old body''s % — less than the 3x this file exists to buy. The read has gone back to walking the neighbourhood once per good.', v_after, v_before;
  end if;

  -- ── (b2) THE ACCESS PATH IS STILL THERE. The ratio above is only reachable through
  --         port_goods_good_id_idx: without it the identical body costs 127x on PostgreSQL 17
  --         (section 0's measurements) while every value it answers stays correct — which is the
  --         quietest way this file could ever be undone.
  if not exists (
        select 1 from pg_proc p
         where p.oid = 'world.pct_of_neighbours_at(uuid,uuid)'::regprocedure
           and p.proconfig @> array['plan_cache_mode=force_custom_plan']) then
    raise exception '0053 self-assert FAIL: world.pct_of_neighbours_at is no longer pinned to a custom plan — PostgreSQL 17 will switch it to a generic plan on the sixth call of a session and the read costs 127x while every value it answers stays correct';
  end if;
  if to_regclass('public.port_goods_good_id_idx') is null then
    raise exception '0053 self-assert FAIL: public.port_goods_good_id_idx does not exist — the neighbourhood walk has no good-side access path and the read silently costs two orders of magnitude more on PostgreSQL 17';
  end if;

  -- ── (c) THE SHAPE, read back off the DEPLOYED catalogue, not off this file.
  v_def := pg_get_functiondef('world.market(uuid)'::regprocedure);
  select count(*) into v_n from regexp_matches(v_def, 'world\.pct_of_neighbours_at\(', 'g');
  select count(*) into v_bad from regexp_matches(v_def, 'world\.pct_of_neighbours\(', 'g');
  if v_n <> 1 or v_bad <> 0 then
    raise exception '0053 self-assert FAIL: the deployed world.market names world.pct_of_neighbours_at % time(s) and the per-good scalar % time(s) — expected exactly 1 and 0', v_n, v_bad;
  end if;

  v_def := pg_get_functiondef('world.pct_of_neighbours(uuid,uuid)'::regprocedure);
  select count(*) into v_n from regexp_matches(v_def, 'world\.pct_of_neighbours_at\(', 'g');
  if v_n <> 1 or strpos(v_def, 'gc_distance_nm') > 0 or strpos(v_def, 'mid_') > 0 then
    raise exception '0053 self-assert FAIL: the deployed world.pct_of_neighbours composes the set authority % time(s) (expected 1) and still carries a haversine of its own (%) or a mid of its own (%) — that is a second author of §E.4',
      v_n, strpos(v_def, 'gc_distance_nm') > 0, strpos(v_def, 'mid_') > 0;
  end if;

  v_def := pg_get_functiondef('world.mid_price(uuid,uuid,numeric)'::regprocedure);
  select count(*) into v_n from regexp_matches(v_def, 'world\.mid_from_terms\(', 'g');
  if v_n <> 1 or strpos(v_def, 'power(') > 0 then
    raise exception '0053 self-assert FAIL: the deployed world.mid_price names world.mid_from_terms % time(s) (expected 1) and still carries a power() of its own (%) — the §G.1 expression would then be written in two places',
      v_n, strpos(v_def, 'power(') > 0;
  end if;

  -- ── (d) THE INLINE PRECONDITION. These four are exactly what PostgreSQL's inline_function()
  --        requires; the reflex in this chain is `security definer set search_path` on everything,
  --        and applying it here would silently put 9,720 real calls back into every market read
  --        while every value stayed correct. That is the failure this guard exists to name.
  select count(*) into v_bad
    from pg_proc p
    join pg_language l on l.oid = p.prolang
   where p.oid = 'world.mid_from_terms(numeric,numeric,numeric,numeric,numeric,numeric,int,numeric,numeric,numeric,numeric)'::regprocedure
     and (l.lanname <> 'sql' or p.provolatile <> 'i' or p.prosecdef or p.proconfig is not null);
  if v_bad <> 0 then
    raise exception '0053 self-assert FAIL: world.mid_from_terms is no longer inlinable — it must be language sql, IMMUTABLE, NOT security definer and carry no SET clause, or the planner stops substituting it and world.pct_of_neighbours_at pays a real function call per neighbour again';
  end if;

  -- ── (e) POSTURE. Nothing here is a write and nothing here is a new client door.
  select count(*) into v_grants  from public.client_write_grants();
  select count(*) into v_writers from public.client_executable_writers();
  select count(*) filter (where t.ok) into v_bad from (
    select has_function_privilege('anon', 'world.pct_of_neighbours_at(uuid,uuid)', 'execute') as ok
    union all select has_function_privilege('authenticated', 'world.pct_of_neighbours_at(uuid,uuid)', 'execute')
    union all select has_function_privilege('anon', 'world.mid_from_terms(numeric,numeric,numeric,numeric,numeric,numeric,int,numeric,numeric,numeric,numeric)', 'execute')
    union all select has_function_privilege('authenticated', 'world.mid_from_terms(numeric,numeric,numeric,numeric,numeric,numeric,int,numeric,numeric,numeric,numeric)', 'execute')
    union all select has_function_privilege('anon', 'world.pct_of_neighbours(uuid,uuid)', 'execute')
  ) t;
  if v_grants <> 0 or v_writers <> 0 or v_bad <> 0 then
    raise exception '0053 self-assert FAIL: % client write grant(s), % client-executable writer(s), and % of the 5 doors that must stay shut are open', v_grants, v_writers, v_bad;
  end if;
  -- and the one door that must stay OPEN, or the market screen loses its index.
  if not has_function_privilege('authenticated', 'world.pct_of_neighbours(uuid,uuid)', 'execute') then
    raise exception '0053 self-assert FAIL: the supersede dropped authenticated''s EXECUTE on world.pct_of_neighbours';
  end if;

  select count(*) into v_narrow from world.pct_of_neighbours_at(v_id);

  raise notice '0053 self-assert ok: the %%NBR walk is asked ONCE for a quay instead of once per good, and nothing it answers moved — all % mid(s) in the world are byte-identical to the pre-image and so are % hypothetical-stock mid(s) across five stock levels including 0 and 1e9, all % %%NBR answer(s) at % subject port(s) spanning % neighbour(s) down to %, and the FULL world.market payload at every one of those ports compares equal as text with its clock included; the wide call and the narrowed call are one body, agreeing on every one of % good(s) at the busiest quay; the work fell from % to % buffer(s) for one read of that quay (the guard demands 3x and no millisecond is asserted anywhere, because two flaky wall-clock gates were enough); the deployed catalogue says the same — world.market names world.pct_of_neighbours_at once and the per-good scalar not at all, world.pct_of_neighbours carries neither a haversine nor a mid of its own, world.mid_price names world.mid_from_terms once and no longer holds a power(), and world.mid_from_terms is still sql/IMMUTABLE/not-security-definer/no-SET, which is exactly what the planner needs to keep inlining it; % client write grant(s), % client-executable writer(s), 0 new client doors',
    v_mids, v_sweep, v_pcts, v_subjects, v_nbr_max, v_nbr_min, v_narrow, v_before, v_after, v_grants, v_writers;
end $$;

drop table subjects_0053;
drop table market_before_0053;
drop table mids_before_0053;
drop table sweep_before_0053;
drop table pct_before_0053;
drop table buffers_0053;
