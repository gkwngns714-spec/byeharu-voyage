-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0294 — A GOOD HAS A CLASS
--        Every trade good carries a PREMIUM CLASS, 1 (basic) to 5 (luxury), cut from its base value by
--        ONE knob, ONE rule and ONE reader, and served as `class` beside `rarity` on the three
--        payloads that already serve a good's rarity. Three function bodies are re-cut (hunks sliced
--        from their LIVE bodies, each hunk occurring exactly once, the whole set reversing to the
--        pre-image); nothing else in public/cmd/world/voyage moves.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ──────────────────────────────────────────────────────────────────────────
--   2026-11-01: "new trade goods - distinctive class showing what is more premium."  Read with rows
--   37 / 52 / 67 (a real, regional, sorted catalogue) and 177 (a good shows what sort it is and how
--   rare it is). Decided by default, and the owner may reverse it: the class is a FIVE-step scale by
--   a good's VALUE, so a premium good is unmistakable in every list a good appears in.
--
-- ── THREE IDEAS LIVE ON ONE GOODS ROW. THIS FILE ADDS ONLY THE THIRD, AS ITS OWN CONCEPT ───────
--   * SCARCITY  public.good_rarity (0032 / 0051): how few harbours produce it -- common ... exotic.
--   * PRODUCTION TIER  goods.tier (0280 / 0281): 0 raw, 1-3 made in the Forge.
--   * PREMIUM CLASS  (this file): how much a ton of it is worth -- basic ... luxury.
--   They answer three different questions and are never folded into one: gold is dear AND common,
--   glassware is cheap-ish AND exotic.
--
-- ── THE RULE: ONE KNOB, ONE RULE, ONE READER ───────────────────────────────────────────────────
--   world_config.good_class_edges = [45, 140, 350, 950]    four ascending base-value edges (jsonb).
--   public.good_class(base_value, edges)   THE RULE: 1 + the number of edges at or below base_value.
--                                          IMMUTABLE, strict, pure -- it reads no table.
--   public.good_class_edges()              THE ONE READER of the knob, as numbers (through public.wc,
--                                          the one knob reader). STABLE.
--   public.good_class(base_value)          the leaf a server caller asks: the rule over the knob.
--   All three have a search_path set and are server-only (revoked from every client role): the class
--   reaches a client as a served FIELD, exactly as the rarity word does.
--   WHY THE RULE TAKES ITS EDGES. world.snapshot() serves 629 goods in one read. A knob read inside a
--   per-good call is 629 reads of world_config; measured on PGlite, the one-argument leaf costs ~8 ms over
--   the 629 goods (a paired A/B on the whole read: +14 ms) where the rule over edges read ONCE costs
--   ~1 ms (docs/dev-log/2026-11-01-good-class.md).
--   So the snapshot hands the rule its edges through an uncorrelated sub-select (the planner reads that
--   once per statement); the market (a few rows a quay) and the request board (a few rows) ask the leaf.
--   There is still one rule and one reader: the leaf is the rule applied to the reader's answer.
--   MEASURED (2026-11-01). On PROD, read-only, over the 629 goods (min 4.00, max 3300.00 after 0285's
--   x5 re-base): class 1 = 86 goods (4.00 .. 44.00), 2 = 215 (45.00 .. 137.00), 3 = 162 (141.00 ..
--   345.00), 4 = 108 (379.50 .. 925.50), 5 = 58 (1050.00 .. 3300.00). The SAME sizes come out of
--   data/goods.json (the midpoint of each good's baseValue range), whose authored `valueBand` 1-5 the
--   prod goods table does NOT carry: 593 of 629 goods (94.3 %) land in their authored band. An
--   exhaustive search over every possible cut finds 598 (95.1 %) at the irregular edges 53 / 135.5 /
--   379.5 / 1050; the round edges above cost five goods and read as numbers a person can say.
--   Tuning is the knob (owner-only): the served class follows at the next read, no deploy.
--
-- ── WHERE IT IS SERVED (the three places that already serve `rarity`, found by grepping every
--    'rarity' in the LIVE functions of public / cmd / world / voyage -- the design named two) ─────
--     world.snapshot().goods[]       the catalogue the Codex, cargo, storage and Forge lists read
--     world.market(port).goods[]     the Market rows (Buy / Sell)
--     world.contracts(port).contracts[]   the Request board
--   Each gets ONE new line beside its 'rarity' line, and no other line moves.
--   The Forge read (world.goods_forge), the cargo lines and the storage lines carry a good by CODE
--   and never served its rarity either: a client reads their class from the catalogue by code, the
--   same lookup it already makes for their name and category.
--
-- ── THE RE-CUTS (hunks sliced from PRODUCTION's live bodies, read at head 0289, re-read at 0290) ─
--   world.snapshot()      md5 80bfdc4ffece54edd9b34f99212f8e68   STABLE  definer
--   world.market(uuid)    md5 1231c1189362ad389930d69bb651a1c3   VOLATILE definer (its tick_market_drift)
--   world.contracts(uuid) md5 187749905486b9359704b517d41ca217   VOLATILE definer (its tick_contracts)
--   Each hunk is the one line `'rarity', public.good_rarity(g.id),` (occurring exactly once in each
--   body) plus the new lines after it. pg_temp.recut refuses the whole file if any hunk does not occur
--   exactly once, so a body that drifted since this was written cannot be sliced wrong.
--
-- ── WHAT DOES NOT MOVE ─────────────────────────────────────────────────────────────────────────
--   The md5 of every OTHER function in public / cmd / world / voyage (asserted against a pre-image
--   taken in this transaction); every re-cut function's ACL, volatility, definer flag and config;
--   the client RPC registry (no new door); the walls (0 client write grants / executable writers /
--   caller-evaluated functions); both owner switches; every table row but the one new knob. No
--   existing field is renamed, moved or removed: a client that ignores `class` reads the payload
--   exactly as before, and a client newer than a server that has no `class` renders nothing for it.
--
-- ── SELF-ASSERT (rolled back where it writes; asserts the RULE, never a seed) ──────────────────
--   (a) every hunk is present exactly once in the new body and the whole set reverses to the pre-image;
--       each re-cut function's ACL / volatility / definer / config is as found.
--   (b) the knob is four ascending positive numbers; the reader returns them; the rule is IMMUTABLE
--       and strict, the reader and the leaf STABLE; none is a definer, none is executable by anon or
--       authenticated, each has a search_path.
--   (c) the leaf maps the knob's OWN edges exactly: just below edge i is class i, edge i itself is
--       class i + 1, zero and a value far above every edge are classes 1 and 5, NULL is NULL -- all
--       derived from the stored knob, so tuning it later cannot make this a false claim; and the rule
--       over the reader's edges answers the leaf for EVERY good.
--   (d) every served good carries a class 1-5 equal to good_class(base_value), joined to the goods
--       table for EVERY good (snapshot), every row of three harbours' markets, and the request
--       board's rows (probe requests planted at the class boundaries -- the dearest good below each
--       edge and the cheapest at or above it -- and rolled back). Stripping `class` from the
--       snapshot's goods leaves the pre-image payload byte for byte.
--   (e) the reverse -- the three pre-image bodies back, the three new functions dropped, the knob
--       deleted -- restores the snapshot payload byte for byte; the registry and the function set are
--       as found.
--   (f) every function in public / cmd / world / voyage other than the three is md5-unmoved, and the
--       only functions added are the three above; the walls and the owner switches are as found.
--
-- ── PROD CHECKS (read-only; one pure SELECT per call) -- run before the deploy ─────────────────
--   the head (20260818000290 live at the time of writing; whatever it is, it must be 0293 when this
--   deploys); the live md5 / volatility of the three bodies above (read at head 0289, re-read before
--   the deploy: 0290-0293 re-cut none of them); no public.good_class* function and no world_config
--   key 'good_class_edges'; every hunk's anchor occurs exactly once in each LIVE body; the 629-good
--   value spread by class (86 / 215 / 162 / 108 / 58).
-- ROLLBACK (forward): re-cut the three bodies back with the hunks reversed, drop the three functions,
--   delete the knob row. The self-assert proves that reverse restores the snapshot payload exactly.
-- DEPLOY ORDER (coordinator, 2026-11-02): 0290 is live (the head). 0291 (the laps' autovacuum, PR #443),
--   0292 (the port_goods rewrite) and 0293 (the Stats period fix) deploy FIRST; THIS FILE is 0294 and the
--   LAST migration. The numbers 0291-0293 are not in this branch (their files arrive with their own PRs):
--   check-versions allows gaps and the chain applies in filename order, so the gap is deliberate. It
--   needs nothing from 0291-0293 and re-cuts none of the functions they touch. Renumber the file AND
--   its '0294' self-assert strings only if the order moves again.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('world.snapshot()') is null
     or to_regprocedure('world.market(uuid)') is null
     or to_regprocedure('world.contracts(uuid)') is null
     or to_regprocedure('public.good_rarity(uuid)') is null
     or to_regprocedure('public.wc(text)') is null then
    raise exception '0294 refuses: a function this migration builds on is missing (snapshot / market / contracts / good_rarity / wc)';
  end if;
  if to_regprocedure('public.good_class(numeric)') is not null
     or to_regprocedure('public.good_class(numeric,numeric[])') is not null
     or to_regprocedure('public.good_class_edges()') is not null
     or exists (select 1 from public.world_config where key = 'good_class_edges') then
    raise exception '0294 refuses: public.good_class / good_class_edges or the good_class_edges knob already exists -- this has been applied once';
  end if;
end $guard$;

-- The one hunk slicer every structural file uses: exactly one occurrence or it refuses.
create or replace function pg_temp.recut(p_fn regprocedure, p_drop boolean, variadic p_edits text[])
returns void
language plpgsql
as $fn$
declare
  v_def text := pg_get_functiondef(p_fn);
  v_i   int := 1;
  v_n   int;
begin
  while v_i < array_length(p_edits, 1) loop
    v_n := (length(v_def) - length(replace(v_def, p_edits[v_i], ''))) / length(p_edits[v_i]);
    if v_n <> 1 then
      raise exception '0294 slice: hunk % of % occurs % time(s) in %, expected exactly 1 - the deployed body is not what this migration was generated against.',
        (v_i + 1) / 2, (array_length(p_edits, 1)) / 2, v_n, p_fn;
    end if;
    v_def := replace(v_def, p_edits[v_i], p_edits[v_i + 1]);
    v_i := v_i + 2;
  end loop;
  if p_drop then execute format('drop function %s', p_fn::text); end if;
  execute v_def;
end $fn$;

-- ── 0. THE PRE-IMAGE ────────────────────────────────────────────────────────────────────────────
create temp table defs_pre_0294 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       md5(replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '')) as md5,
       coalesce(p.proacl::text, '') as acl,
       p.provolatile as vol,
       p.prosecdef as secdef,
       coalesce(p.proconfig::text, '') as cfg
  from (values ('world.snapshot()'),
               ('world.market(uuid)'),
               ('world.contracts(uuid)')) f(fn)
  join pg_proc p on p.oid = f.fn::regprocedure;

create temp table pre_0294 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) as fns,
       (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
           and p.oid not in ('world.snapshot()'::regprocedure, 'world.market(uuid)'::regprocedure,
                             'world.contracts(uuid)'::regprocedure)) as others_md5,
       (select value from public.world_config where key = 'economy_closed') as economy_closed,
       (select value from public.world_config where key = 'city_treasury_enabled') as city_treasury_enabled,
       world.snapshot() as snap;

-- ── 1. THE KNOB ─────────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('good_class_edges', '[45, 140, 350, 950]'::jsonb,
   '0294: the four base-value edges, ascending, that cut a trade good''s premium class. A good''s class is 1 plus the number of edges at or below its goods.base_value (1 basic, 2 standard, 3 fine, 4 superior, 5 luxury). Read by public.good_class_edges ALONE and served as `class` beside `rarity`. Measured 2026-11-01 over the 629 goods: sizes 86 / 215 / 162 / 108 / 58, 94 % of goods in their authored valueBand. Owner-tunable; the served class follows at the next read.');

-- ── 2. THE READER, THE RULE AND THE LEAF ────────────────────────────────────────────────────────
-- THE READER: the knob as numbers. The only function that reads good_class_edges.
create or replace function public.good_class_edges()
returns numeric[]
language sql
stable
set search_path = public, pg_temp
as $$
  select array_agg(e.v::numeric order by e.ord)
    from jsonb_array_elements_text(public.wc('good_class_edges')) with ordinality as e(v, ord)
$$;

-- THE RULE: pure. One plpgsql expression, not a SQL function, because the planner will not inline a
-- SQL function that carries a SET clause and a called SQL function costs ~3 us a row against ~1 us here.
create or replace function public.good_class(p_base_value numeric, p_edges numeric[])
returns smallint
language plpgsql
immutable
strict
set search_path = public, pg_temp
as $$
begin
  -- 1 + the number of edges at or below the value. Four edges, five classes; a short or empty edge
  -- array makes a NULL comparison and so a NULL class, which a client reads as "the world did not say".
  return (1 + (p_base_value >= p_edges[1])::int + (p_base_value >= p_edges[2])::int
            + (p_base_value >= p_edges[3])::int + (p_base_value >= p_edges[4])::int)::smallint;
end $$;

-- THE LEAF a server caller asks: the rule over the reader's answer.
create or replace function public.good_class(p_base_value numeric)
returns smallint
language sql
stable
strict
set search_path = public, pg_temp
as $$
  select public.good_class(p_base_value, public.good_class_edges())
$$;

comment on function public.good_class_edges() is
  '0294: world_config.good_class_edges as numbers -- THE one reader of that knob (through public.wc). Server-only.';
comment on function public.good_class(numeric, numeric[]) is
  '0294: THE RULE of a trade good''s premium class, 1 (basic) to 5 (luxury): 1 plus the number of edges at or below its '
  'base value. Pure; world.snapshot() hands it the edges read once for all 629 goods. Server-only.';
comment on function public.good_class(numeric) is
  '0294: a trade good''s premium class -- public.good_class over public.good_class_edges(). Served as `class` beside '
  '`rarity` on market.goods[] and contracts.contracts[] (snapshot.goods[] hands the rule its edges once); a client prints '
  'the number and never derives it. Server-only.';

revoke all on function public.good_class_edges() from public, anon, authenticated;
revoke all on function public.good_class(numeric, numeric[]) from public, anon, authenticated;
revoke all on function public.good_class(numeric) from public, anon, authenticated;

-- ── 3. THE THREE SERVING POINTS ─────────────────────────────────────────────────────────────────
-- Each gets new lines directly after its 'rarity' line. The anchor is that one line, which occurs
-- exactly once in each live body.
select pg_temp.recut('world.snapshot()'::regprocedure, false,
  $g0$        'rarity', public.good_rarity(g.id),$g0$,
  $g1$        'rarity', public.good_rarity(g.id),
        -- 0294: the premium class (1 basic .. 5 luxury) by the ONE rule public.good_class; a client prints it, never derives it.
        -- The knob is read once for all the goods (an uncorrelated sub-select), not once per good.
        'class', public.good_class(g.base_value, (select public.good_class_edges())),$g1$);

select pg_temp.recut('world.market(uuid)'::regprocedure, false,
  $m0$        'rarity', public.good_rarity(g.id),$m0$,
  $m1$        'rarity', public.good_rarity(g.id),
        -- 0294: the same class as snapshot.goods[], from the same rule.
        'class', public.good_class(g.base_value),$m1$);

select pg_temp.recut('world.contracts(uuid)'::regprocedure, false,
  $c0$        'rarity', public.good_rarity(g.id),$c0$,
  $c1$        'rarity', public.good_rarity(g.id),
        -- 0294: the same class as snapshot.goods[], from the same rule.
        'class', public.good_class(g.base_value),$c1$);

-- ── 4. SELF-ASSERT ──────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_def     record;
  v_h       record;
  v_cur     text;
  v_rev     text;
  v_bad     int;
  v_edges   jsonb;
  v_e       numeric[];
  v_i       int;
  v_n       int;
  v_port    uuid;
  v_snap    jsonb;
  v_mkt     jsonb;
  v_ctr     jsonb;
  v_probe   uuid[];
  v_ids     uuid[];
  v_day     int;
  v_sizes   text;
  v_vmin    numeric;
  v_vmax    numeric;
begin
  create temp table hunks_0294 (fn text, old_text text, new_text text);

  insert into hunks_0294 values
  ('world.snapshot()',
   $g0$        'rarity', public.good_rarity(g.id),$g0$,
   $g1$        'rarity', public.good_rarity(g.id),
        -- 0294: the premium class (1 basic .. 5 luxury) by the ONE rule public.good_class; a client prints it, never derives it.
        -- The knob is read once for all the goods (an uncorrelated sub-select), not once per good.
        'class', public.good_class(g.base_value, (select public.good_class_edges())),$g1$),
  ('world.market(uuid)',
   $m0$        'rarity', public.good_rarity(g.id),$m0$,
   $m1$        'rarity', public.good_rarity(g.id),
        -- 0294: the same class as snapshot.goods[], from the same rule.
        'class', public.good_class(g.base_value),$m1$),
  ('world.contracts(uuid)',
   $c0$        'rarity', public.good_rarity(g.id),$c0$,
   $c1$        'rarity', public.good_rarity(g.id),
        -- 0294: the same class as snapshot.goods[], from the same rule.
        'class', public.good_class(g.base_value),$c1$);

  -- (a) EVERY HUNK IS THE ONLY ONE, THE WHOLE SET REVERSES TO THE PRE-IMAGE, AND NOTHING ELSE ABOUT THE
  --     THREE FUNCTIONS MOVED (ACL, volatility, definer flag, config).
  for v_def in select * from defs_pre_0294 loop
    v_cur := replace(pg_get_functiondef(v_def.fn::regprocedure), E'\r', '');
    v_rev := v_cur;
    select count(*) into v_n from hunks_0294 where fn = v_def.fn;
    if v_n <> 1 then
      raise exception '0294 self-assert FAIL: % has % hunk(s) declared, expected exactly 1', v_def.fn, v_n;
    end if;
    for v_h in select * from hunks_0294 where fn = v_def.fn loop
      if (length(v_cur) - length(replace(v_cur, v_h.new_text, ''))) / length(v_h.new_text) <> 1 then
        raise exception '0294 self-assert FAIL: the new hunk of % is not present exactly once', v_def.fn;
      end if;
      v_rev := replace(v_rev, v_h.new_text, v_h.old_text);
    end loop;
    if v_rev <> v_def.def then
      raise exception '0294 self-assert FAIL: % does not reverse to its pre-image', v_def.fn;
    end if;
    if v_cur = v_def.def then
      raise exception '0294 self-assert FAIL: % was not re-cut at all', v_def.fn;
    end if;
  end loop;
  for v_def in
    select d.fn
      from defs_pre_0294 d
      join pg_proc p on p.oid = d.fn::regprocedure
     where coalesce(p.proacl::text, '') is distinct from d.acl
        or p.provolatile is distinct from d.vol
        or p.prosecdef is distinct from d.secdef
        or coalesce(p.proconfig::text, '') is distinct from d.cfg
  loop
    raise exception '0294 self-assert FAIL: the ACL / volatility / definer flag / config of % moved', v_def.fn;
  end loop;

  -- (b) THE KNOB, THE READER, THE RULE AND THE LEAF AS DECLARED
  v_edges := public.wc('good_class_edges');
  if jsonb_typeof(v_edges) <> 'array' or jsonb_array_length(v_edges) <> 4 then
    raise exception '0294 self-assert FAIL: good_class_edges is % -- it must be an array of exactly four numbers', v_edges;
  end if;
  select array_agg(x.v::numeric order by x.ord) into v_e
    from jsonb_array_elements_text(v_edges) with ordinality as x(v, ord);
  if v_e[1] <= 0 or v_e[1] >= v_e[2] or v_e[2] >= v_e[3] or v_e[3] >= v_e[4] then
    raise exception '0294 self-assert FAIL: the edges % are not four positive, strictly ascending numbers', v_e;
  end if;
  if public.good_class_edges() is distinct from v_e then
    raise exception '0294 self-assert FAIL: public.good_class_edges() answers % for the knob %', public.good_class_edges(), v_edges;
  end if;
  if not exists (select 1 from public.world_config where key = 'good_class_edges' and length(btrim(description)) > 0) then
    raise exception '0294 self-assert FAIL: the knob has no description';
  end if;
  if (select count(*) from pg_proc p
       where p.oid in ('public.good_class_edges()'::regprocedure, 'public.good_class(numeric,numeric[])'::regprocedure,
                       'public.good_class(numeric)'::regprocedure)
         and not p.prosecdef and coalesce(p.proconfig::text, '') like '%search_path%'
         and p.prorettype in ('smallint'::regtype, 'numeric[]'::regtype)) <> 3 then
    raise exception '0294 self-assert FAIL: the reader, the rule and the leaf are not three invoker functions with a search_path';
  end if;
  if (select p.provolatile from pg_proc p where p.oid = 'public.good_class(numeric,numeric[])'::regprocedure) <> 'i'
     or not (select p.proisstrict from pg_proc p where p.oid = 'public.good_class(numeric,numeric[])'::regprocedure)
     or (select p.provolatile from pg_proc p where p.oid = 'public.good_class(numeric)'::regprocedure) <> 's'
     or not (select p.proisstrict from pg_proc p where p.oid = 'public.good_class(numeric)'::regprocedure)
     or (select p.provolatile from pg_proc p where p.oid = 'public.good_class_edges()'::regprocedure) <> 's' then
    raise exception '0294 self-assert FAIL: the rule must be IMMUTABLE and strict, the leaf STABLE and strict, the reader STABLE';
  end if;
  if has_function_privilege('anon', 'public.good_class(numeric)', 'execute')
     or has_function_privilege('authenticated', 'public.good_class(numeric)', 'execute')
     or has_function_privilege('anon', 'public.good_class(numeric,numeric[])', 'execute')
     or has_function_privilege('authenticated', 'public.good_class(numeric,numeric[])', 'execute')
     or has_function_privilege('anon', 'public.good_class_edges()', 'execute')
     or has_function_privilege('authenticated', 'public.good_class_edges()', 'execute') then
    raise exception '0294 self-assert FAIL: a client role can execute the class functions -- the class reaches a client as a served field only';
  end if;

  -- (c) THE LEAF MAPS THE KNOB'S OWN EDGES EXACTLY (derived from the stored knob, never a typed seed)
  for v_i in 1..4 loop
    if public.good_class(v_e[v_i] - 0.01) <> v_i then
      raise exception '0294 self-assert FAIL: just below edge % (%) the class is %, expected %', v_i, v_e[v_i], public.good_class(v_e[v_i] - 0.01), v_i;
    end if;
    if public.good_class(v_e[v_i]) <> v_i + 1 then
      raise exception '0294 self-assert FAIL: at edge % (%) the class is %, expected %', v_i, v_e[v_i], public.good_class(v_e[v_i]), v_i + 1;
    end if;
  end loop;
  if public.good_class(0) <> 1 or public.good_class(-5) <> 1 or public.good_class(v_e[1] / 2) <> 1 then
    raise exception '0294 self-assert FAIL: a value below the first edge is not class 1';
  end if;
  if public.good_class(v_e[4] * 1000) <> 5 or public.good_class(v_e[4] + 0.01) <> 5 then
    raise exception '0294 self-assert FAIL: a value above the last edge is not class 5';
  end if;
  if public.good_class(null) is not null or public.good_class(null, v_e) is not null then
    raise exception '0294 self-assert FAIL: a NULL base value must answer NULL, not a guess';
  end if;
  if public.good_class(100, '{45,140}'::numeric[]) is not null then
    raise exception '0294 self-assert FAIL: a short edge array must answer NULL (the world did not say), not a class';
  end if;
  -- the rule over the reader's edges (what the snapshot asks) is the leaf, for EVERY good, and both
  -- equal an independent count of the knob's edges at or below the value
  select count(*) into v_bad
    from public.goods g
   where public.good_class(g.base_value, v_e) is distinct from public.good_class(g.base_value)
      or public.good_class(g.base_value)::int is distinct from
         1 + (select count(*)::int from jsonb_array_elements_text(v_edges) q(v) where q.v::numeric <= g.base_value);
  if v_bad <> 0 then
    raise exception '0294 self-assert FAIL: % good(s) where the rule, the leaf and an independent count of the edges disagree', v_bad;
  end if;

  -- (d) EVERY SERVED GOOD CARRIES ITS CLASS. snapshot: joined to the goods table for EVERY good.
  v_snap := world.snapshot();
  if jsonb_array_length(v_snap->'goods') <> (select count(*) from public.goods) then
    raise exception '0294 self-assert FAIL: the snapshot serves % goods, the table holds %', jsonb_array_length(v_snap->'goods'), (select count(*) from public.goods);
  end if;
  select count(*) into v_bad
    from jsonb_array_elements(v_snap->'goods') e
    left join public.goods g on g.id = (e->>'id')::uuid
   where g.id is null
      or jsonb_typeof(e->'class') is distinct from 'number'
      or (e->>'class')::int not between 1 and 5
      or (e->>'class')::int is distinct from public.good_class(g.base_value)::int;
  if v_bad <> 0 then
    raise exception '0294 self-assert FAIL: % snapshot good(s) do not carry class = good_class(base_value) within 1-5', v_bad;
  end if;
  -- ...and NOTHING ELSE about the payload moved: strip `class` and the pre-image comes back byte for byte.
  if jsonb_set(v_snap, '{goods}', (select jsonb_agg(e - 'class' order by o) from jsonb_array_elements(v_snap->'goods') with ordinality as x(e, o)))::text
       <> (select snap::text from pre_0294) then
    raise exception '0294 self-assert FAIL: apart from `class`, the snapshot payload is not the pre-image';
  end if;

  -- the markets of three harbours (volatile: the drift catch-up writes, so each is read inside a
  -- sub-transaction that is rolled back) -- every row, joined to the goods table.
  v_mkt := '[]'::jsonb;
  for v_port in select p.id from public.ports p where p.kind = 'HARBOUR' order by p.code limit 3 loop
    begin
      v_mkt := v_mkt || coalesce(world.market(v_port)->'goods', '[]'::jsonb);
      raise exception using errcode = 'ZX294', message = 'rollback';
    exception when sqlstate 'ZX294' then
      null;
    end;
  end loop;
  if jsonb_array_length(v_mkt) < 3 then
    raise exception '0294 self-assert FAIL: three harbours'' markets serve % rows -- the assert would prove nothing', jsonb_array_length(v_mkt);
  end if;
  select count(*) into v_bad
    from jsonb_array_elements(v_mkt) e
    left join public.goods g on g.id = (e->>'good_id')::uuid
   where g.id is null
      or jsonb_typeof(e->'class') is distinct from 'number'
      or (e->>'class')::int not between 1 and 5
      or (e->>'class')::int is distinct from public.good_class(g.base_value)::int;
  if v_bad <> 0 then
    raise exception '0294 self-assert FAIL: % market row(s) do not carry class = good_class(base_value) within 1-5', v_bad;
  end if;

  -- the request board: probe requests planted AT THE CLASS BOUNDARIES (the dearest good below each edge
  -- and the cheapest good at or above it), read through the door, and rolled back.
  select array_agg(distinct x.gid) into v_probe
    from (select (select g.id from public.goods g where g.base_value < v_e[i] order by g.base_value desc, g.code limit 1) as gid
            from generate_series(1, 4) i
          union all
          select (select g.id from public.goods g where g.base_value >= v_e[i] order by g.base_value, g.code limit 1)
            from generate_series(1, 4) i) x
   where x.gid is not null;
  if coalesce(cardinality(v_probe), 0) < 4 then
    raise exception '0294 self-assert FAIL: only % boundary good(s) found -- the request probe would prove nothing', coalesce(cardinality(v_probe), 0);
  end if;
  select p.id into v_port from public.ports p where p.kind = 'HARBOUR' order by p.code limit 1;
  begin
    v_day := world.game_day();
    with ins as (
      insert into public.trade_contracts (id, port_id, good_id, posted_day, seq, qty, premium_pct, mid_at_post,
                                          premium_per_unit, premium_ducats, expires_day, status)
      select ('00000000-0294-4000-8000-0000000000' || lpad(u.k::text, 2, '0'))::uuid, v_port, u.gid, v_day, 9000 + u.k::int,
             1, 0.1000, 1.00, 0.10, 1, v_day + 3, 'open'
        from unnest(v_probe) with ordinality as u(gid, k)
      returning id)
    select array_agg(id) into v_ids from ins;
    v_ctr := world.contracts(v_port);
    raise exception using errcode = 'ZX294', message = 'rollback';
  exception when sqlstate 'ZX294' then
    null;
  end;
  if exists (select 1 from public.trade_contracts where id = any(v_ids)) then
    raise exception '0294 self-assert FAIL: the probe requests survived their rollback';
  end if;
  select count(*) into v_n
    from jsonb_array_elements(v_ctr->'contracts') e
   where (e->>'id')::uuid = any(v_ids);
  if v_n <> cardinality(v_ids) then
    raise exception '0294 self-assert FAIL: the request board served % of the % probe requests', v_n, cardinality(v_ids);
  end if;
  select count(*) into v_bad
    from jsonb_array_elements(v_ctr->'contracts') e
    left join public.goods g on g.code = e->>'good'
   where g.id is null
      or jsonb_typeof(e->'class') is distinct from 'number'
      or (e->>'class')::int not between 1 and 5
      or (e->>'class')::int is distinct from public.good_class(g.base_value)::int;
  if v_bad <> 0 then
    raise exception '0294 self-assert FAIL: % request row(s) do not carry class = good_class(base_value) within 1-5', v_bad;
  end if;

  -- (e) THE REVERSE: the three pre-image bodies back, the three new functions dropped, the knob deleted
  --     -- in a sub-transaction -- restores the snapshot payload byte for byte, the registry and the
  --     function set.
  begin
    for v_def in select * from defs_pre_0294 loop
      execute v_def.def;
    end loop;
    drop function public.good_class(numeric);
    drop function public.good_class(numeric, numeric[]);
    drop function public.good_class_edges();
    delete from public.world_config where key = 'good_class_edges';
    if world.snapshot()::text <> (select snap::text from pre_0294) then
      raise exception '0294 self-assert FAIL: the reverse does not restore the snapshot payload';
    end if;
    if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from pre_0294) then
      raise exception '0294 self-assert FAIL: the reverse does not restore the registry';
    end if;
    if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> (select fns from pre_0294) then
      raise exception '0294 self-assert FAIL: the reverse does not restore the function set';
    end if;
    raise exception using errcode = 'ZX294', message = 'reverse ok';
  exception when sqlstate 'ZX294' then
    null;
  end;
  if to_regprocedure('public.good_class(numeric)') is null
     or to_regprocedure('public.good_class(numeric,numeric[])') is null
     or to_regprocedure('public.good_class_edges()') is null
     or not exists (select 1 from public.world_config where key = 'good_class_edges') then
    raise exception '0294 self-assert FAIL: the rolled-back reverse took the new objects with it';
  end if;

  -- (f) NOTHING ELSE MOVED: every other function md5-unmoved, exactly three functions added, the
  --     registry, the walls and both owner switches as found.
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> (select fns from pre_0294) + 3 then
    raise exception '0294 self-assert FAIL: the function set is not the pre-image plus the three class functions';
  end if;
  if (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid not in ('world.snapshot()'::regprocedure, 'world.market(uuid)'::regprocedure,
                           'world.contracts(uuid)'::regprocedure, 'public.good_class(numeric)'::regprocedure,
                           'public.good_class(numeric,numeric[])'::regprocedure, 'public.good_class_edges()'::regprocedure))
     is distinct from (select others_md5 from pre_0294) then
    raise exception '0294 self-assert FAIL: a function other than the three re-cuts moved';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from pre_0294) then
    raise exception '0294 self-assert FAIL: the client registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0294 self-assert FAIL: a client wall moved';
  end if;
  if (select value from public.world_config where key = 'economy_closed') is distinct from (select economy_closed from pre_0294)
     or (select value from public.world_config where key = 'city_treasury_enabled') is distinct from (select city_treasury_enabled from pre_0294) then
    raise exception '0294 self-assert FAIL: an owner switch moved';
  end if;

  -- the receipt prints what the rule MADE of the catalogue (computed here, never asserted against a seed)
  select string_agg(s.n::text, ' / ' order by s.c), min(s.lo), max(s.hi)
    into v_sizes, v_vmin, v_vmax
    from (select public.good_class(g.base_value) as c, count(*) as n, min(g.base_value) as lo, max(g.base_value) as hi
            from public.goods g group by 1) s;

  raise notice '0294 self-assert ok: A GOOD HAS A CLASS. One knob (world_config.good_class_edges = %), one reader (public.good_class_edges), one rule (public.good_class(value, edges): 1 plus the number of edges at or below the value; IMMUTABLE, strict) and its leaf (public.good_class(value)), all server-only, cut the catalogue into class sizes % (base values % to %). Served as `class` beside `rarity` by exactly three re-cut bodies -- world.snapshot().goods[] (the edges read once), world.market().goods[], world.contracts().contracts[] -- each hunk present once and the set reversing to the pre-image, ACL / volatility / definer / config unmoved; the snapshot minus `class` is the pre-image payload byte for byte. The leaf maps the knob''s own edges exactly (below = i, at = i + 1, NULL = NULL, a short edge array = NULL), the rule over the reader''s edges answers the leaf for every good, and every snapshot good, every market row of three harbours and the planted request-board rows at the class boundaries carry class = good_class(base_value). The reverse restores the snapshot payload, the registry and the function set. Every other function in public / cmd / world / voyage is md5-unmoved (% functions before, three added), the registry is % rows, the walls are 0 and both owner switches are as found',
    v_edges, v_sizes, v_vmin, v_vmax,
    (select fns from pre_0294), (select entry_points from pre_0294);
end $$;
