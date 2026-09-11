-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0084 — A GOOD IS NATIVE WHERE IT GROWS  (one boolean on the quay's row, from 0062's own word)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW (docs/QUAY_LEDGER.md §3 A, §5) ──────────────────────────────────────────────────────
-- The ledger row of the redesigned quay carries a tag: `rare` from the served rarity, and
-- `native` — "this is grown here" — *"only once the payload carries it"*. §5 names the change:
-- *"add `native boolean` to `world.market` (server join; `demand` stays unserved, 0066:225-229)"*.
--
-- ── WHAT SAYS THE OPPOSITE, NAMED ───────────────────────────────────────────────────────────────
-- Nothing on `world.market()`'s row says whether the good is FROM here. The row says `offered`
-- (the roster fact, 0061) and `rarity` (how many ports produce it, 0032/0051), and the client has
-- `goods.origin_regions` on the snapshot and the port's region id — so a client that wanted the
-- tag would JOIN them itself, which is exactly the second author NO_SPAGHETTI §1 forbids: the day
-- 0062's word for "native" changes (an entrepot rule, a region merge) the client's tag would be
-- wrong and nothing would fail.
--
-- ── THE ONE WORD, AND WHERE IT ALREADY LIVES ────────────────────────────────────────────────────
-- 0062:70-72, verbatim: *"EVERY (port, good) offer is either NATIVE — the port's region is in
-- the good's origin_regions — or a NAMED ENTREPOT."* The columns are 0062's (`goods.origin_regions
-- text[]` of `regions.code`) and 0002's (`ports.region_id -> regions(id, code)`); the join is
-- 0062:1160-1165's own assert. This file serves that sentence as one boolean and decides nothing
-- new. NOT the roster: an offered good may be an entrepot's (native = false, offered = true), and a
-- good she is merely carrying here may be native (native = true, offered = false — she may sell it,
-- not buy it, 0061). The two flags are two facts.
--
-- ── SUPERSEDE ───────────────────────────────────────────────────────────────────────────────────
-- This file SUPERSEDES the deployed body of `world.market(uuid)` (0032:189 in full; last sliced
-- by 0080:179) by SLICING it: ONE hunk, the `offered` key gains a sibling `native`, asserted below
-- to be the pre-image with exactly that hunk swapped in. No signature moves, nothing is dropped,
-- and NO ACL statement is issued (0080 §3): the ACL is asserted byte-identical instead.
--
-- ── WHAT DOES NOT MOVE ──────────────────────────────────────────────────────────────────────────
--   * `demand` stays unserved (0066:225-229 — the owner's rule that the quay gives no hints).
--   * `offered`, `available`, `rarity`, prices, ranges, stock, the clock: every other key of the
--     row is byte-for-byte the same expression.
--   * The roster, the entrepot list, 0062's assert: this file reads them and writes none.
--
-- Depends on: 0002 (ports.region_id, regions.code), 0062 (goods.origin_regions), 0080 (the
-- deployed world.market body).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. The slice tool (its own copy, by necessity — tests/duplication.spec.ts:365-380) ─────────
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
      raise exception '0084 slice: hunk % of % occurs % time(s) in %, expected exactly 1 — the deployed body is not what this migration was generated against.',
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

-- ── 0b. THE PRE-IMAGE ──────────────────────────────────────────────────────────────────────────
create temporary table defs_before_0084 as
select pg_get_functiondef(p.oid) as def, coalesce(p.proacl::text, '') as acl
  from pg_proc p
 where p.oid = 'world.market(uuid)'::regprocedure;

-- ── 1. THE ONE HUNK ────────────────────────────────────────────────────────────────────────────
-- Aliases verified against the live body: `pg` is public.port_goods, `g` public.goods, `pr`
-- public.ports (joined for the culture flag since 0009).
select pg_temp.recut('world.market(uuid)'::regprocedure, false,
  $h$        'offered', public.port_offers(pg.port_id, pg.good_id))$h$,
  $h$        'offered', public.port_offers(pg.port_id, pg.good_id),
        -- 0084: NATIVE is 0062's own word - the port's region is among the good's origin_regions.
        'native', exists (select 1 from public.regions r where r.id = pr.region_id and r.code = any(g.origin_regions)))$h$);

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_port      uuid;
  v_port_code text;
  v_rows      int;
  v_native    int;
  v_mismatch  int;
  v_def       text;
  v_expect    text;
  v_acl       text;
begin
  -- The busiest quay AMONG those whose market read lists at least one row that is NOT native
  -- (an entrepot's offer, or a good she is carrying in): deterministic (count desc, then code),
  -- and chosen so that both branches of the boolean are real on it BY SELECTION — a roster edit
  -- that made the single busiest harbour all-native would otherwise turn this red on a fresh
  -- apply while the flag was still right. If no such quay exists at all, the world has no
  -- entrepot and (b)'s second check says so.
  select pg.port_id into v_port
    from public.port_goods pg
    join public.ports p on p.id = pg.port_id
    join public.regions rg on rg.id = p.region_id
    join public.goods g on g.id = pg.good_id
   where p.kind = 'HARBOUR' and public.quay_shows(pg.port_id, pg.good_id)
   group by pg.port_id
  having count(*) filter (where not (rg.code = any(g.origin_regions))) >= 1
   order by count(*) desc, min(p.code)
   limit 1;
  if v_port is null then
    raise exception '0084 self-assert FAIL: no harbour''s quay lists a non-native row, so the false branch of native could not be examined anywhere';
  end if;
  select code into v_port_code from public.ports where id = v_port;

  -- (a) BOTH BRANCHES ARE REAL on that quay.
  select count(*), count(*) filter (where (r->>'native')::boolean)
    into v_rows, v_native
    from jsonb_array_elements(world.market(v_port)->'goods') r;
  if v_rows = 0 then
    raise exception '0084 self-assert FAIL: world.market(%) served no rows; nothing was examined', v_port_code;
  end if;
  if v_native <= 0 or v_native >= v_rows then
    raise exception '0084 self-assert FAIL: at % native reads true on % of % rows — one branch of the boolean is dead on the busiest quay', v_port_code, v_native, v_rows;
  end if;
  if exists (select 1 from jsonb_array_elements(world.market(v_port)->'goods') r
              where jsonb_typeof(r->'native') is distinct from 'boolean') then
    raise exception '0084 self-assert FAIL: a served row carries native as something other than a boolean';
  end if;

  -- (b) THE SERVED FLAG EQUALS 0062's JOIN, recomputed here without going through the body.
  select count(*) into v_mismatch
    from jsonb_array_elements(world.market(v_port)->'goods') r
    join public.goods g on g.id = (r->>'good_id')::uuid
    join public.ports p on p.id = v_port
    join public.regions rg on rg.id = p.region_id
   where (r->>'native')::boolean is distinct from (rg.code = any(g.origin_regions));
  if v_mismatch <> 0 then
    raise exception '0084 self-assert FAIL: % served row(s) at % disagree with 0062''s join (port region in goods.origin_regions)', v_mismatch, v_port_code;
  end if;
  --     ... and the two flags are two facts: somewhere in the world a row is offered and not
  --     native (an entrepot), or 0062's second arm is dead and this flag would equal `offered`.
  if not exists (
      select 1 from public.port_specialties s
        join public.ports p on p.id = s.port_id
        join public.regions rg on rg.id = p.region_id
        join public.goods g on g.id = s.good_id
       where not (rg.code = any(g.origin_regions))) then
    raise exception '0084 self-assert FAIL: every offer in the world is native, so native would be offered under another name';
  end if;

  -- (c) PARITY: the pre-image with exactly the one hunk swapped in, and the ACL unmoved.
  select def, acl into v_expect, v_acl from defs_before_0084;
  v_expect := replace(v_expect,
    E'        \'offered\', public.port_offers(pg.port_id, pg.good_id))',
    E'        \'offered\', public.port_offers(pg.port_id, pg.good_id),\n'
    || E'        -- 0084: NATIVE is 0062\'s own word - the port\'s region is among the good\'s origin_regions.\n'
    || E'        \'native\', exists (select 1 from public.regions r where r.id = pr.region_id and r.code = any(g.origin_regions)))');
  select pg_get_functiondef('world.market(uuid)'::regprocedure) into v_def;
  if v_def <> v_expect then
    raise exception '0084 self-assert FAIL: world.market is not its pre-image with only the declared hunk swapped in (% chars before, % after, % expected)',
      (select length(def) from defs_before_0084), length(v_def), length(v_expect);
  end if;
  if v_def = (select def from defs_before_0084) then
    raise exception '0084 self-assert FAIL: world.market is byte-identical to its pre-image — the slice did nothing';
  end if;
  if coalesce((select p.proacl::text from pg_proc p where p.oid = 'world.market(uuid)'::regprocedure), '') is distinct from v_acl then
    raise exception '0084 self-assert FAIL: the ACL of world.market moved — was [%], is now [%]', v_acl,
      coalesce((select p.proacl::text from pg_proc p where p.oid = 'world.market(uuid)'::regprocedure), '');
  end if;
  if not has_function_privilege('authenticated', 'world.market(uuid)', 'execute')
     or has_function_privilege('anon', 'world.market(uuid)', 'execute') then
    raise exception '0084 self-assert FAIL: world.market is not open to authenticated and closed to anon';
  end if;
  --     `demand` is still not served (0066:225-229).
  if exists (select 1 from jsonb_array_elements(world.market(v_port)->'goods') r where r ? 'demand') then
    raise exception '0084 self-assert FAIL: world.market serves demand, which 0066 forbids';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0 then
    raise exception '0084 self-assert FAIL: the grant lockdown does not read zero on both halves';
  end if;

  raise notice '0084 self-assert ok: A GOOD IS NATIVE WHERE IT GROWS. world.market rows carry `native` = 0062''s own word (the port''s region is among the good''s origin_regions): on the busiest quay that lists a non-native row, %, % of % served rows are native and % are not, every one equal to 0062''s join recomputed independently, and the world still holds offers that are not native so the flag is not `offered` renamed; world.market is its pre-image with exactly one hunk swapped in, its ACL unmoved (authenticated yes, anon no), `demand` still unserved; 0 client write grants, 0 client-executable writers.',
    v_port_code, v_native, v_rows, v_rows - v_native;
end $$;
