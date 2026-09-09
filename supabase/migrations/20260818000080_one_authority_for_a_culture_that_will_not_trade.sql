-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0080 — ONE AUTHORITY FOR "THIS CULTURE WILL NOT TRADE THIS GOOD"
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- `public.goods.culture_mask` is, in 0002's own words, *"cultures that will NOT trade this good
-- (wine and pork in Islamic-culture ports). Empty array = traded everywhere."* Asking it is one
-- sentence — `port.culture = any(good.culture_mask)` — and that sentence is written **SIX times in
-- five deployed function bodies**:
--
--   cmd.do_buy           if v_culture = any(g.culture_mask) then
--   cmd.do_sell          if v_culture = any(g.culture_mask) then
--   cmd.haggle           if v_port.culture = any(g.culture_mask) then
--   world.market         'available', not (pr.culture = any(g.culture_mask)),
--   world.trade_routes   and not (p.culture = any(g.culture_mask))        -- the origin, a BUY
--   world.trade_routes   where not (d.culture = any(h.culture_mask))      -- the destination, a SELL
--
-- `docs/RESUME.md` has carried this under **"Named spaghetti, still not fixed"** since 2026-08-26,
-- and 0061 named it in its own header and deliberately refused to become the sixth writer of it:
-- *"folding five live bodies in a migration whose subject is the roster would triple the blast
-- radius on a live game… The fold is named here so it cannot be lost."* This file is that fold,
-- and it is the whole of its subject. `docs/NO_SPAGHETTI.md` §1 is the law it answers.
--
-- **THE COUNT WAS RIGHT AND THE SITE COUNT WAS NOT.** Read off the applied chain rather than off
-- the source files: five functions, but `world.trade_routes` carries the rule TWICE — once for the
-- port she loads at and once for the port she sells at — so there are SIX sites, not five. Two
-- other live bodies mention `culture_mask` and are correctly left alone, because neither applies
-- the rule: `world.snapshot()` SERVES the column to the client, and `world.trade_routes`'s `here`
-- CTE SELECTS it so the second site can ask about it. A fold that swept those up would have
-- changed what the client is served.
--
-- ── SUPERSEDE ──────────────────────────────────────────────────────────────────────────────────
-- This file SUPERSEDES the deployed bodies of `cmd.do_buy` (last cut by 0061), `cmd.do_sell`,
-- `cmd.haggle` (0022), `world.market` (0061) and `world.trade_routes` (0061), by SLICING them:
-- `pg_temp.recut` replaces a hunk that must occur exactly once and refuses otherwise, so what
-- lands is the deployed definition with six substrings swapped and every other byte untouched —
-- asserted below against the pre-image, not claimed here. No signature moves, so nothing is
-- dropped and every ACL survives `create or replace` — this file issues NO grant statement at
-- all and asserts instead that not one ACL moved (section 3 says what that cost to learn). **The change is a no-op in behaviour by construction:** `public.culture_refuses(c, m)`
-- is `c = any(m)` and nothing else, `immutable`, so it carries the same answer for every input
-- INCLUDING null — a null culture makes both forms null, and both `if` and `not (…)` treat that
-- the same way they did yesterday. Assert (c) proves the equality over all 117,152 (port, good)
-- pairs of the real world rather than arguing it here.
--
-- ── WHY A FUNCTION AND NOT A VIEW OR A COLUMN ──────────────────────────────────────────────────
-- The rule is a PREDICATE over two values the callers already hold in their hands. A view would
-- make five joins out of six comparisons; a materialised `port_goods.culture_ok` column would be a
-- derived copy of a fact `goods.culture_mask` already states, free to drift the moment a mask is
-- edited — which is 0058's roster defect wearing different clothes. `language sql` + `immutable` +
-- no `security definer` is the shape 0061 chose for `public.port_offers` and for the same reason:
-- PostgreSQL's `inline_function()` refuses a definer function, and `world.market` asks this once
-- per good per port. Inlined, the planner sees exactly the expression it saw before this file ran.
--
-- ── WHAT DOES NOT MOVE ─────────────────────────────────────────────────────────────────────────
--   * The MASKS themselves. Not one row of `public.goods` is written. This is mechanism, not
--     content, and assert (f) re-reads the world's totals to prove it.
--   * The asymmetry 0061 defends: BUY is gated by the roster and SELL is not. Untouched here —
--     this file only folds the CULTURE rule, which has always gated both sides.
--   * `world.snapshot()`'s payload, byte for byte. It serves `culture_mask` and applies nothing.
--   * Prices, stock, drift, affinity, fairs, rarity, the roster, the raster.
--
-- ── A FINDING THIS FILE MEASURED AND DELIBERATELY DID NOT FIX ──────────────────────────────────
-- Folding a rule means reading every place it is asked, and doing that turned up something the
-- repo did not know: **the culture rule is unreachable on the quay.** 254 (port, good) pairs are
-- culture-refused and every one of them is stocked in `port_goods` — and NOT ONE is on its port's
-- roster, so `world.market` serves `available = true` on every row it shows, at all 224 harbours.
-- 69 harbours have a culture some good refuses and none of them ever sees the flag.
--
-- The cause is a collision between two files that were both right on their own: 0062 made the
-- roster origin-based — a good is offered where it comes FROM, or at a named entrepot — and a
-- culture that refuses a good is not a culture that produces it. So 0061's ROSTER gate now
-- strictly shadows 0002's CULTURE gate for BUY and for the market screen. The rule stays live
-- exactly where 0061 deliberately left selling un-rostered: `cmd.do_sell`, `cmd.haggle`, and
-- `world.trade_routes`'s DESTINATION filter, which is that same sale seen from the quay.
--
-- It is REPORTED in the receipt and asserted nowhere, on purpose. Pinning `0 unavailable rows` as
-- correct would write a design decision into a guard, and this is the owner's question, not a
-- migration's: DESIGN B.4 wanted wine and pork refused in Islamic ports and the player can still
-- never be SOLD them — but they can no longer be seen to be refused either.
--
-- Depends on: 0002 (`goods.culture_mask` and its comment, the definition this file folds),
-- 0022 (the deployed `cmd.do_sell` / `cmd.haggle` bodies), 0061 (the deployed `cmd.do_buy`,
-- `world.market` and `world.trade_routes` bodies this file slices, and the `port_offers`
-- precedent), 0065 (the catalogue this file's world-wide equivalence assert reads).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. The slice tool: replace hunks that must occur exactly once, else refuse (0050:120) ──────
-- Its own copy, by necessity: a pg_temp function lives in this connection's temporary schema and
-- cannot be seen from any other transaction (tests/duplication.spec.ts:365-380 says why that is
-- the one schema a supersede guard does not read).
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
      raise exception '0080 slice: hunk % of % occurs % time(s) in %, expected exactly 1 — the deployed body is not what this migration was generated against.',
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

-- ── 0b. THE PRE-IMAGES, captured before anything is cut ────────────────────────────────────────
-- Every assert about "exactly the declared hunks and nothing else" compares against these. Taken
-- from the catalogue, so they are the DEPLOYED bodies and not this file's idea of them.
create temporary table defs_before_0080 as
select p.oid::regprocedure::text as fn,
       pg_get_functiondef(p.oid)  as def,
       coalesce(p.proacl::text, '') as acl
  from pg_proc p
 where p.oid in ('cmd.do_buy(uuid,jsonb)'::regprocedure,
                 'cmd.do_sell(uuid,jsonb)'::regprocedure,
                 'cmd.haggle(uuid,uuid,text)'::regprocedure,
                 'world.market(uuid)'::regprocedure,
                 'world.trade_routes(uuid,uuid,numeric,int,uuid)'::regprocedure,
                 'world.snapshot()'::regprocedure);

create temporary table world_before_0080 as
select (select count(*) from public.goods)                                as goods,
       (select count(*) from public.goods where culture_mask <> '{}')     as masked_goods,
       (select count(*) from public.ports where kind = 'HARBOUR')         as harbours,
       (select count(*) from public.port_goods)                           as market_rows,
       (select count(*) from public.port_specialties)                     as roster_rows,
       (select count(*) from public.ports p join public.goods g on true
         where p.culture = any(g.culture_mask))                           as refused_pairs;

-- ── 1. THE AUTHORITY ───────────────────────────────────────────────────────────────────────────
-- `create`, not `create or replace`: this file claims the function is NEW (0051:252's convention).
create function public.culture_refuses(p_culture text, p_mask text[])
returns boolean
language sql
immutable
parallel safe
as $$
  select p_culture = any(p_mask)
$$;

comment on function public.culture_refuses(text, text[]) is
  'THE one answer to "will this culture trade this good?" — false, or null on a null culture, '
  'means it will. public.goods.culture_mask names the cultures that will NOT trade a good (0002), '
  'and until 0080 that comparison was written six times across cmd.do_buy, cmd.do_sell, '
  'cmd.haggle, world.market and world.trade_routes (twice: the port she loads at, and the port '
  'she sells at). IMMUTABLE and free of SECURITY DEFINER so PostgreSQL inlines it — world.market '
  'asks it once per good per port. It is a predicate over two values, never a lookup: the caller '
  'already holds the culture and the mask, and a function that fetched them would be a second '
  'authority on WHICH culture and WHICH mask.';

-- No privileges of its own: every path that reaches it is already inside a SECURITY DEFINER
-- function (all five callers are), which is 0061's ruling for public.port_offers, verbatim.
revoke all on function public.culture_refuses(text, text[]) from public, anon, authenticated;

-- ── 2. THE SIX SITES, SLICED ───────────────────────────────────────────────────────────────────
-- Each hunk is quoted WITHOUT its leading whitespace, so the slice cannot fail on an indentation
-- byte, and `recut` proves each one occurs exactly once in the body it is cutting.

select pg_temp.recut('cmd.do_buy(uuid,jsonb)'::regprocedure, false,
  $h$if v_culture = any(g.culture_mask) then$h$,
  $h$if public.culture_refuses(v_culture, g.culture_mask) then$h$);

select pg_temp.recut('cmd.do_sell(uuid,jsonb)'::regprocedure, false,
  $h$if v_culture = any(g.culture_mask) then$h$,
  $h$if public.culture_refuses(v_culture, g.culture_mask) then$h$);

select pg_temp.recut('cmd.haggle(uuid,uuid,text)'::regprocedure, false,
  $h$if v_port.culture = any(g.culture_mask) then$h$,
  $h$if public.culture_refuses(v_port.culture, g.culture_mask) then$h$);

select pg_temp.recut('world.market(uuid)'::regprocedure, false,
  $h$'available', not (pr.culture = any(g.culture_mask)),$h$,
  $h$'available', not public.culture_refuses(pr.culture, g.culture_mask),$h$);

-- BOTH sites, in one call, so the file cannot land having folded half of this body.
select pg_temp.recut('world.trade_routes(uuid,uuid,numeric,int,uuid)'::regprocedure, false,
  $h$and not (p.culture = any(g.culture_mask))$h$,
  $h$and not public.culture_refuses(p.culture, g.culture_mask)$h$,
  $h$where not (d.culture = any(h.culture_mask))$h$,
  $h$where not public.culture_refuses(d.culture, h.culture_mask)$h$);

-- ── 3. THE GRANTS ARE NOT TOUCHED, AND THAT IS THE POINT ───────────────────────────────────────
-- `create or replace function` PRESERVES a function's ACL, so a slice needs no grant statements at
-- all — and issuing them anyway is not a harmless belt-and-braces. The first draft of this file
-- re-stated the postures it believed 0061 had landed, and got it wrong in BOTH directions:
--
--   * it copied `do_buy`'s `revoke … from public, anon, authenticated` onto `cmd.haggle`. **The
--     client calls `cmd.haggle` DIRECTLY** — it is not reached through `cmd.issue` the way the
--     `do_` verbs are — so that line took the bargain away from every player.
--     `scripts/db/proofs/06_haggle.sql`'s HAGGLE_CLIENT_PATH caught it on the next run:
--     `permission denied for function haggle` (42501).
--   * it re-issued 0061's `grant execute on world.trade_routes to authenticated`. **0071 REVOKED
--     that grant on purpose** (`:176`) — the owner's row 64 said "no nearby price info needed", so
--     the function stays for proof 04 and the client's door was shut. Restating a ten-migration-old
--     grant would have silently reverted a later deliberate decision, and nothing would have failed.
--
-- One habit, two defects, and the second is the frightening one because no gate was watching it.
--
-- So the posture is CHECKED rather than re-declared: assert (e) compares every re-cut function's
-- `proacl` against the pre-image captured in 0b, byte for byte. That is a stronger claim than any
-- grant statement could make — "nothing moved" instead of "these are the grants I think are
-- right" — and it cannot revoke anything while making it.

-- ── 4. THE SELF-ASSERT ─────────────────────────────────────────────────────────────────────────
do $$
declare
  v_left      int;
  v_callers   text[];
  v_disagree  bigint;
  v_true      bigint;
  v_control   bigint;
  v_def       text;
  v_want      text;
  v_r         record;
  v_rows              bigint;
  v_refused_stocked   bigint;
  v_refused_rostered  bigint;
begin
  -- (a) THE FOLD IS COMPLETE. Not one deployed body still asks the question for itself. The
  --     pattern matches `= any(<alias>.culture_mask)` in any spacing, which is the only shape the
  --     rule has ever been written in; public.culture_refuses cannot match it, because its own
  --     body names `p_mask` and no column at all.
  select count(*) into v_left
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage')
     and p.prosrc ~ '=\s*any\s*\(\s*[a-z_]+\.culture_mask\s*\)';
  if v_left <> 0 then
    raise exception '0080 self-assert FAIL: % function body(ies) still write the culture rule out longhand — the fold is not a fold if a copy survives', v_left;
  end if;

  -- (b) …AND THE CALLERS ARE THE FIVE NAMED IN THE HEADER, no more and no fewer. Fewer would mean
  --     a slice silently did nothing; more would mean this file grew a caller nobody declared.
  select array_agg(n.nspname || '.' || p.proname order by n.nspname, p.proname) into v_callers
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where p.prosrc like '%culture_refuses%' and p.proname <> 'culture_refuses';
  if v_callers is distinct from array['cmd.do_buy','cmd.do_sell','cmd.haggle','world.market','world.trade_routes'] then
    raise exception '0080 self-assert FAIL: the callers of public.culture_refuses are %, not the five this file declares', v_callers;
  end if;

  -- (c) THE PREDICATE IS THE SAME PREDICATE, over the whole real world — every (port, good) pair,
  --     both forms, and they must agree on every one. This is the equivalence the header claims,
  --     measured rather than argued.
  select count(*) filter (where public.culture_refuses(p.culture, g.culture_mask)
                             is distinct from (p.culture = any(g.culture_mask))),
         count(*) filter (where public.culture_refuses(p.culture, g.culture_mask))
    into v_disagree, v_true
    from public.ports p cross join public.goods g;
  if v_disagree <> 0 then
    raise exception '0080 self-assert FAIL: the folded predicate disagrees with the one it replaced on % pair(s)', v_disagree;
  end if;
  -- NOT VACUOUS: if no pair in the world were ever refused, the comparison above would be two
  -- constants and would prove nothing.
  if v_true = 0 then
    raise exception '0080 self-assert FAIL: no (port, good) pair in the world is culture-refused, so the equivalence above compared nothing';
  end if;
  if v_true <> (select refused_pairs from world_before_0080) then
    raise exception '0080 self-assert FAIL: % refused pairs after this file, % before — the rule changed what it answers', v_true, (select refused_pairs from world_before_0080);
  end if;

  -- (c2) THE POSITIVE CONTROL — the comparison in (c) CAN fail. A deliberately wrong rule (the
  --      mask read as an ALLOW list rather than a refuse list, which is the mistake the column
  --      comment exists to prevent) must be caught by the very same query.
  select count(*) into v_control
    from public.ports p cross join public.goods g
   where (not (p.culture = any(g.culture_mask)) and g.culture_mask <> '{}')
     is distinct from (p.culture = any(g.culture_mask));
  if v_control = 0 then
    raise exception '0080 self-assert FAIL: the equivalence check did not notice an inverted rule, so it is not a check';
  end if;

  -- (d) EACH BODY IS ITS OWN PRE-IMAGE WITH EXACTLY THE DECLARED HUNKS SWAPPED IN. This is what
  --     makes "nothing else moved" a fact instead of an intention: the whole definition is
  --     reconstructed from the captured one and compared byte for byte.
  for v_r in
    select fn, def from defs_before_0080
     where fn <> 'world.snapshot()'
  loop
    v_want := replace(replace(replace(replace(replace(v_r.def,
      'if v_culture = any(g.culture_mask) then',
      'if public.culture_refuses(v_culture, g.culture_mask) then'),
      'if v_port.culture = any(g.culture_mask) then',
      'if public.culture_refuses(v_port.culture, g.culture_mask) then'),
      '''available'', not (pr.culture = any(g.culture_mask)),',
      '''available'', not public.culture_refuses(pr.culture, g.culture_mask),'),
      'and not (p.culture = any(g.culture_mask))',
      'and not public.culture_refuses(p.culture, g.culture_mask)'),
      'where not (d.culture = any(h.culture_mask))',
      'where not public.culture_refuses(d.culture, h.culture_mask)');
    select pg_get_functiondef(v_r.fn::regprocedure) into v_def;
    if v_def <> v_want then
      raise exception '0080 self-assert FAIL: % is not its pre-image with only the declared hunks swapped in (% chars before, % after, % expected)',
        v_r.fn, length(v_r.def), length(v_def), length(v_want);
    end if;
  end loop;

  -- (d2) world.snapshot() IS UNTOUCHED, byte for byte. It mentions culture_mask twice and applies
  --      the rule neither time; a fold that reached it would have changed the client's payload.
  select pg_get_functiondef('world.snapshot()'::regprocedure) into v_def;
  if v_def <> (select def from defs_before_0080 where fn = 'world.snapshot()') then
    raise exception '0080 self-assert FAIL: world.snapshot() moved, and it serves the client its goods';
  end if;

  -- (e) THE POSTURE, AS A PRE-IMAGE COMPARISON. Not one ACL may differ from what this file found,
  --     in either direction: a slice that quietly revokes is how the bargain was nearly taken away
  --     from every player (see section 3), and a slice that quietly grants is worse.
  for v_r in select fn, acl from defs_before_0080 loop
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_r.fn::regprocedure), '')
       is distinct from v_r.acl then
      raise exception '0080 self-assert FAIL: the ACL of % moved — was [%], is now [%]', v_r.fn, v_r.acl,
        coalesce((select p.proacl::text from pg_proc p where p.oid = v_r.fn::regprocedure), '');
    end if;
  end loop;

  -- …and the doors are named explicitly, open AND shut, so the comparison above cannot pass by
  -- having been wrong in the same way before and after.
  if not has_function_privilege('authenticated', 'cmd.haggle(uuid,uuid,text)', 'execute') then
    raise exception '0080 self-assert FAIL: cmd.haggle lost its grant — the client calls it directly and the bargain would be gone';
  end if;
  if not has_function_privilege('authenticated', 'world.market(uuid)', 'execute') then
    raise exception '0080 self-assert FAIL: world.market lost its grant when it was re-cut — the MARKET screen would go dark';
  end if;
  -- world.trade_routes is CLOSED to the client and must stay closed. 0071 revoked that grant on
  -- purpose — the quay's comparison was the same answer as the neighbour index by a longer road,
  -- and the owner's row 64 said "no nearby price info needed" — keeping the FUNCTION because proof
  -- 04 runs it as postgres, and taking away the door. This file's own first draft re-stated a
  -- grant here and would have re-opened it; asserting the closure is what makes that impossible.
  if has_function_privilege('authenticated', 'world.trade_routes(uuid,uuid,numeric,int,uuid)', 'execute') then
    raise exception '0080 self-assert FAIL: authenticated can execute world.trade_routes — 0071 closed that door and this file has re-opened it';
  end if;
  if has_function_privilege('anon', 'world.market(uuid)', 'execute')
     or has_function_privilege('authenticated', 'cmd.do_buy(uuid,jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.culture_refuses(text,text[])', 'execute') then
    raise exception '0080 self-assert FAIL: a client role can execute something this file said it could not';
  end if;
  select count(*) into v_left from public.client_write_grants();
  if v_left <> 0 then
    raise exception '0080 self-assert FAIL: % client write grant(s) after this migration', v_left;
  end if;

  -- (f) THE WORLD IS THE SAME WORLD. Mechanism, not content: no mask, no price, no roster row was
  --     written, and the quay still answers through the folded rule on a real refused pair.
  if (select goods from world_before_0080) <> (select count(*) from public.goods)
     or (select market_rows from world_before_0080) <> (select count(*) from public.port_goods)
     or (select roster_rows from world_before_0080) <> (select count(*) from public.port_specialties)
     or (select harbours from world_before_0080) <> (select count(*) from public.ports where kind = 'HARBOUR') then
    raise exception '0080 self-assert FAIL: this file wrote content; it is only allowed to move mechanism';
  end if;

  -- (g) READ BACK THROUGH THE RE-CUT BODY, not through the predicate. For every row the quay
  --     actually serves at the harbours where this rule could possibly matter, the served
  --     `available` flag must equal what the one authority answers for that (port, good).
  select count(*) into v_rows
    from (select id, culture from public.ports
           where kind = 'HARBOUR'
             and culture = any(select unnest(culture_mask) from public.goods)
           order by code limit 5) pr
   cross join lateral jsonb_array_elements(world.market(pr.id)->'goods') r
   join public.goods g on g.id = (r->>'good_id')::uuid
   where (r->>'available')::boolean
         is distinct from not public.culture_refuses(pr.culture, g.culture_mask);
  if v_rows <> 0 then
    raise exception '0080 self-assert FAIL: world.market served % row(s) whose available flag disagrees with public.culture_refuses', v_rows;
  end if;
  select count(*) into v_rows
    from (select id from public.ports where kind = 'HARBOUR'
             and culture = any(select unnest(culture_mask) from public.goods)
           order by code limit 5) pr
   cross join lateral jsonb_array_elements(world.market(pr.id)->'goods') r;
  if v_rows = 0 then
    raise exception '0080 self-assert FAIL: the quay read-back examined no rows at all';
  end if;

  -- (h) THE FINDING, MEASURED AND REPORTED RATHER THAN ASSERTED. It is NOT this file's to fix and
  --     it must not be pinned as correct, so nothing here raises: the numbers go in the receipt so
  --     the next reader meets them. The culture rule is UNREACHABLE on the quay. 0062 made the
  --     roster origin-based — a good is offered where it comes FROM — and a culture that refuses a
  --     good is not a culture that produces it, so the roster gate (0061) now strictly shadows the
  --     culture gate (0002 / DESIGN B.4) on everything the market serves. It stays live on the
  --     SELL side, which 0061 deliberately left un-rostered, and on world.trade_routes's
  --     DESTINATION filter, which is the same sale seen from the quay.
  select count(*) into v_refused_stocked
    from public.ports p
    join public.goods g on public.culture_refuses(p.culture, g.culture_mask)
    join public.port_goods pg on pg.port_id = p.id and pg.good_id = g.id;
  select count(*) into v_refused_rostered
    from public.ports p
    join public.goods g on public.culture_refuses(p.culture, g.culture_mask)
    join public.port_specialties s on s.port_id = p.id and s.good_id = g.id;

  raise notice '0080 self-assert ok: ONE AUTHORITY FOR A CULTURE THAT WILL NOT TRADE. The sentence "port.culture = any(good.culture_mask)" stood SIX times in FIVE deployed bodies — cmd.do_buy, cmd.do_sell, cmd.haggle, world.market, and world.trade_routes which carried it twice (the port she loads at, and the port she sells at). It is now public.culture_refuses and nowhere else: 0 bodies still write it longhand and the callers are exactly the five named. Proven a NO-OP three ways rather than argued: both forms agree on all % (port, good) pairs of the real world, % of them genuinely refused, and an INVERTED rule is caught by that same query on % pairs so the comparison is not two constants; each of the five bodies is its own PRE-IMAGE with only the declared hunks swapped in, byte for byte; and world.snapshot(), which mentions culture_mask twice and applies it neither time, is untouched. Read back through the re-cut body, every row five real harbours serve carries the available flag the one authority answers. Posture PROVEN UNMOVED rather than re-declared: every one of the six functions carries the byte-identical ACL this file found; cmd.haggle (which the client calls directly, unlike the do_ verbs) and world.market still execute for authenticated, world.trade_routes stays SHUT to the client exactly as 0071 shut it, cmd.do_buy and anon have nothing, public.culture_refuses is revoked from every client role, 0 client write grants; no mask, price, roster row or harbour was written. FINDING, MEASURED AND NOT FIXED HERE — THE CULTURE RULE IS UNREACHABLE ON THE QUAY: % (port, good) pairs are culture-refused and stocked, and % of them are on the port roster, so world.market serves the available flag as true on every row it shows, at every harbour. 0062 made the roster origin-based and a culture that refuses a good does not produce it, so the roster gate of 0061 now strictly shadows the culture gate of 0002/DESIGN B.4 for BUY and for the market screen. It remains live where 0061 left selling un-rostered: cmd.do_sell, cmd.haggle, and world.trade_routes''s destination filter. That is a DESIGN question for the owner, not a defect this file may decide.',
    (select count(*) from public.ports p cross join public.goods g), v_true, v_control,
    v_refused_stocked, v_refused_rostered;
end $$;
