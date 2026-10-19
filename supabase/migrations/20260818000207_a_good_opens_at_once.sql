-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0207 — A GOOD OPENS AT ONCE  (world.good_board asks the pathfinder once, and the pathfinder reads each
--        harbour's miles once and asks the region door once a region)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- The owner, 2026-10-19: "when pressing a different trade goods, it takes too long to load, any way to fix
-- this?" — COMMAND → Markets: a press opens the good's chart and ticket, and both wait on world.good_board.
--
-- MEASURED ON PROD (read-only, a docked fleet of a company that is not the owner's; docs/dev-log/
-- 2026-10-19-good-switch-fast.md): world.good_board 4.3–6.1 s a good (6 goods); world.price_outlook 8 ms,
-- world.price_why 8–12 ms, world.price_history 64–90 ms. Inside the board, voyage.reach_passage (0188) costs
-- 1.2–1.3 s and is asked THREE times: BUY AT's passages, SELL AT's (the same question again), and from the buy
-- city (the same question a third time when she is docked where she would buy). Inside reach_passage:
--   the miles matrix  ~0.8 s  — `(sr.reaches->>code)` in a cross join de-toasts a harbour's whole miles
--                               document once per CELL: 238 × 238 reads of a 238-key document;
--   the region door   ~0.4 s  — public.passage_gate once per harbour (238), each re-deriving her exploration
--                               from her record (public.exploration_reach reads her VOYAGE_REPORTs);
--   the search itself ~0.06 s.
--
-- THE CHANGE (no rule moves; every figure is the same function's):
--   (1) voyage.reach_passage reads each harbour's miles document into memory ONCE, not once a cell, and asks
--       public.passage_gate once per REGION, of that region's first harbour. With no leg length named, the gate's
--       answer for a harbour is its region's min_exploration_level against her exploration — the same for every
--       harbour of the region (0107/0112: the harbour is read only for its region). Still the one gate.
--   (2) world.good_board asks voyage.reach_passage(v_player, v_origin) ONCE, keeps the rows in a jsonb, and
--       reads them for BUY AT, SELL AT, and for the buy city when it is where she sails from.
--
-- ── LOCKS AND TIME ──────────────────────────────────────────────────────────────────────────────
-- CREATE OR REPLACE FUNCTION ×2 by hunks; the probe company is made inside a sub-transaction rolled back
-- whole. No LOCK TABLE, no set role, no begin. Timings are notices only.
-- SUPERSEDES, by hunks sliced from the LIVE bodies (prod head 0204, LF-normalised, each asserted to occur
-- exactly once and to reverse to its pre-image, ACL unchanged): voyage.reach_passage(uuid,uuid),
-- world.good_board(uuid,uuid,uuid,numeric).
-- SELF-ASSERT: on its own probe company only — every (origin) passage list and every board it reads equals
-- the pre-image's, byte for byte.
-- ROLLBACK: a forward slice restores the two bodies (each hunk's OLD text is here verbatim).
-- VERSION: 0207 (renumbers to the prod head + 1 at push; 0205 and 0206 are on other branches).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0207(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0207 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from (values ('voyage.reach_passage(uuid,uuid)'),
               ('world.good_board(uuid,uuid,uuid,numeric)')) f(fn);

-- the hunks: (fn, ord, old, new) — each OLD occurs exactly once in its live body
create temp table hunks_0207 (fn text, ord int, old text, new text) on commit drop;

insert into hunks_0207 values
('voyage.reach_passage(uuid,uuid)', 1,
$h$  select array_agg(p.id order by p.code), array_agg(p.code order by p.code),
         array_agg(p.id = p_from or public.passage_gate(p_player, null, p.id) is null order by p.code)
    into v_ids, v_codes, v_open
    from public.ports p
   where p.kind = 'HARBOUR' or p.id = p_from;$h$,
$h$  -- 0207: THE REGION DOOR ASKED ONCE A REGION, not once a harbour. With no leg length named, passage_gate's
  -- answer for a harbour is its region's door against her exploration (0107, 0112), the same for every harbour
  -- of that region; each ask re-derived her exploration from her record (~1.7 ms × 238 on prod). The gate is
  -- still the one asked, of each region's first harbour.
  with door as materialized (
    select h.region_id, public.passage_gate(p_player, null, h.id) is null as open
      from (select distinct on (p.region_id) p.region_id, p.id
              from public.ports p where p.kind = 'HARBOUR' order by p.region_id, p.code) h
  )
  select array_agg(p.id order by p.code), array_agg(p.code order by p.code),
         array_agg(p.id = p_from
                   or coalesce((select d.open from door d where d.region_id is not distinct from p.region_id), true)
                   order by p.code)
    into v_ids, v_codes, v_open
    from public.ports p
   where p.kind = 'HARBOUR' or p.id = p_from;$h$),
('voyage.reach_passage(uuid,uuid)', 2,
$h$  select array_agg((sr.reaches->>b.c)::float8 order by a.i, b.i) into d
    from unnest(v_ids) with ordinality a(id, i)
    join public.sea_reaches sr on sr.port_id = a.id
   cross join unnest(v_codes) with ordinality b(c, i);$h$,
$h$  -- 0207: each harbour's miles document is read ONCE: `sr.reaches->>code` in the cross join de-toasted the
  -- whole stored document again for every cell (~0.8 s of 1.2 s on prod, 238 harbours). `m.doc` is the
  -- document read into memory once a harbour (offset 0 keeps it one evaluation); its cells are looked up there.
  select array_agg(c.nm order by a.i, c.j) into d
    from unnest(v_ids) with ordinality a(id, i)
    join public.sea_reaches sr on sr.port_id = a.id
   cross join lateral (select sr.reaches || '{}'::jsonb as doc offset 0) m
   cross join lateral (select b.j, (m.doc->>b.c)::float8 as nm from unnest(v_codes) with ordinality b(c, j)) c;$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 1,
$h$  v_margin  numeric;                -- 0188: endurance_margin, as voyage.sail_refusal applies it
$h$,
$h$  v_margin  numeric;                -- 0188: endurance_margin, as voyage.sail_refusal applies it
  v_passages jsonb;                 -- 0207: voyage.reach_passage(v_player, v_origin), asked once
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 2,
$h$  -- BUY AT: every city that sells it
  with reach as materialized (
    -- 0188: THE PASSAGE HER CAPTAIN CAN SAIL — every leg within her navigation's reach, through harbours
    select r.port_id, r.nm, r.direct_nm, v_lead_stops || r.stops as stops,
           greatest(r.max_leg_nm, case when cardinality(v_lead_stops) > 0 then v_lead_nm else 0 end) as max_leg
      from voyage.reach_passage(v_player, v_origin) r
$h$,
$h$  -- 0207: THE PASSAGES FROM WHERE SHE SAILS, ASKED ONCE. voyage.reach_passage was asked three times a board —
  -- BUY AT, SELL AT, and from the buy city when that is where she is — at ~1.2 s each on prod.
  select coalesce(jsonb_agg(jsonb_build_object('port_id', r.port_id, 'nm', r.nm, 'direct_nm', r.direct_nm,
                                               'stops', r.stops, 'max_leg_nm', r.max_leg_nm)), '[]'::jsonb)
    into v_passages
    from voyage.reach_passage(v_player, v_origin) r;

  -- BUY AT: every city that sells it
  with reach as materialized (
    -- 0188: THE PASSAGE HER CAPTAIN CAN SAIL — every leg within her navigation's reach, through harbours
    select r.port_id, r.nm, r.direct_nm, v_lead_stops || r.stops as stops,
           greatest(r.max_leg_nm, case when cardinality(v_lead_stops) > 0 then v_lead_nm else 0 end) as max_leg
      from jsonb_to_recordset(v_passages) r(port_id uuid, nm numeric, direct_nm numeric, stops text[], max_leg_nm numeric)   -- 0207
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 3,
$h$    -- 0188: the passage she can sail (voyage.reach_passage), as BUY AT reads it
    select r.port_id, r.nm, r.direct_nm, v_lead_stops || r.stops as stops,
           greatest(r.max_leg_nm, case when cardinality(v_lead_stops) > 0 then v_lead_nm else 0 end) as max_leg
      from voyage.reach_passage(v_player, v_origin) r
$h$,
$h$    -- 0188: the passage she can sail (voyage.reach_passage), as BUY AT reads it — 0207: the rows asked once, above
    select r.port_id, r.nm, r.direct_nm, v_lead_stops || r.stops as stops,
           greatest(r.max_leg_nm, case when cardinality(v_lead_stops) > 0 then v_lead_nm else 0 end) as max_leg
      from jsonb_to_recordset(v_passages) r(port_id uuid, nm numeric, direct_nm numeric, stops text[], max_leg_nm numeric)
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 4,
$h$      from src cross join lateral voyage.reach_passage(v_player, src.id) r
    union all select id, 0, 0, '{}'::text[], 0 from src
$h$,
$h$      from (select id from src where id is distinct from v_origin) s
     cross join lateral voyage.reach_passage(v_player, s.id) r
    union all   -- 0207: bought where she sails from — those are the passages asked once, above
    select x.port_id, x.nm, x.direct_nm, x.stops, x.max_leg_nm
      from src cross join jsonb_to_recordset(v_passages) x(port_id uuid, nm numeric, direct_nm numeric, stops text[], max_leg_nm numeric)
     where src.id = v_origin
    union all select id, 0, 0, '{}'::text[], 0 from src
$h$);

do $$
declare
  d     record;
  k     record;
  v_new text;
  v_rev text;
begin
  if (select count(*) from defs_before_0207 where def is not null) <> 2 then
    raise exception '0207 self-assert FAIL: % of the 2 bodies found', (select count(*) from defs_before_0207 where def is not null);
  end if;
  for k in select h.*, b.def from hunks_0207 h join defs_before_0207 b using (fn) loop
    if pg_temp.occurs_0207(k.def, k.old) <> 1 then
      raise exception '0207 self-assert FAIL: % hunk % occurs % times in the live body, not once', k.fn, k.ord, pg_temp.occurs_0207(k.def, k.old);
    end if;
  end loop;
  -- the pre-images under pg_temp names, for the equivalence check; the old board asks the old pathfinder
  execute replace((select def from defs_before_0207 where fn = 'voyage.reach_passage(uuid,uuid)'),
                  'CREATE OR REPLACE FUNCTION voyage.reach_passage(', 'CREATE OR REPLACE FUNCTION pg_temp.reach_passage_old_0207(');
  execute replace(replace((select def from defs_before_0207 where fn = 'world.good_board(uuid,uuid,uuid,numeric)'),
                          'CREATE OR REPLACE FUNCTION world.good_board(', 'CREATE OR REPLACE FUNCTION pg_temp.good_board_old_0207('),
                  'voyage.reach_passage(', 'pg_temp.reach_passage_old_0207(');
  -- the new bodies: every hunk applied; each new text occurs once in the result and the result reverses
  for d in select * from defs_before_0207 loop
    v_new := d.def;
    for k in select * from hunks_0207 where fn = d.fn order by ord loop
      v_new := replace(v_new, k.old, k.new);
    end loop;
    v_rev := v_new;
    for k in select * from hunks_0207 where fn = d.fn order by ord desc loop
      if pg_temp.occurs_0207(v_rev, k.new) <> 1 then
        raise exception '0207 self-assert FAIL: % new hunk % does not occur exactly once', d.fn, k.ord;
      end if;
      v_rev := replace(v_rev, k.new, k.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0207 self-assert FAIL: the hunks of % do not reverse to the pre-image', d.fn;
    end if;
    execute v_new;
  end loop;
end $$;

-- ── 2. SELF-ASSERT: the probe company's passages and boards are the pre-image's ──────────────────
do $$
declare
  c_uid   constant uuid := '00000000-0207-4000-8000-000000000001';
  c_nil   constant uuid := '00000000-0000-0000-0000-000000000000';
  v_out   text;
  v_player uuid;
  v_fleet uuid;
  v_home  uuid;
  o       record;
  g       record;
  v_n     int := 0;
  v_bad   int := 0;
  v_t0    timestamptz;
  v_old_ms numeric := 0;
  v_new_ms numeric := 0;
  v_rp_old numeric := 0;
  v_rp_new numeric := 0;
  j_old   jsonb;
  j_new   jsonb;
begin
  begin
    v_player := public.new_house(c_uid, 'Casa 0207', 'PRT');
    select f.id, f.port_id into v_fleet, v_home from public.fleets f where f.player_id = v_player order by f.created_at limit 1;
    if v_fleet is null or v_home is null or public.passage_reach_nm(v_player) is null then
      raise exception '0207 self-assert FAIL: the probe company has no docked fleet, or no reach to search under';
    end if;

    -- THE PASSAGES: from her home and from three other harbours, old against new, as a list
    for o in select p.id from public.ports p where p.id = v_home
             union all (select p.id from public.ports p where p.kind = 'HARBOUR' and p.id <> v_home order by md5(p.code) limit 3) loop
      v_t0 := clock_timestamp();
      select coalesce(jsonb_agg(to_jsonb(r) order by r.port_id), '[]') into j_old from pg_temp.reach_passage_old_0207(v_player, o.id) r;
      v_rp_old := v_rp_old + extract(epoch from clock_timestamp() - v_t0) * 1000;
      v_t0 := clock_timestamp();
      select coalesce(jsonb_agg(to_jsonb(r) order by r.port_id), '[]') into j_new from voyage.reach_passage(v_player, o.id) r;
      v_rp_new := v_rp_new + extract(epoch from clock_timestamp() - v_t0) * 1000;
      if j_old is distinct from j_new or jsonb_array_length(j_new) = 0 then
        raise exception '0207 self-assert FAIL: voyage.reach_passage from % is not its pre-image (% rows, was %)',
          (select code from public.ports where id = o.id), jsonb_array_length(j_new), jsonb_array_length(j_old);
      end if;
    end loop;
    if not exists (select 1 from voyage.reach_passage(v_player, v_home) r where r.nm is null)
       or not exists (select 1 from voyage.reach_passage(v_player, v_home) r where cardinality(r.stops) > 0) then
      raise exception '0207 self-assert FAIL: the probe''s passages exercise neither a shut harbour nor a passage with a stop';
    end if;

    -- THE BOARDS: a good her home sells (bought here, and bought here by name), and three it does not
    perform cmd.assume_identity(c_uid);
    for g in (select gd.id, null::uuid as frm from public.goods gd where public.port_offers(v_home, gd.id) order by gd.code limit 1)
             union all (select gd.id, v_home from public.goods gd where public.port_offers(v_home, gd.id) order by gd.code limit 1)
             union all (select gd.id, null from public.goods gd where not public.port_offers(v_home, gd.id)
                           and exists (select 1 from public.port_goods pg where pg.good_id = gd.id)
                         order by md5(gd.code) limit 3) loop
      v_t0 := clock_timestamp();
      j_old := pg_temp.good_board_old_0207(g.id, v_fleet, g.frm, null);
      v_old_ms := v_old_ms + extract(epoch from clock_timestamp() - v_t0) * 1000;
      v_t0 := clock_timestamp();
      j_new := world.good_board(g.id, v_fleet, g.frm, null);
      v_new_ms := v_new_ms + extract(epoch from clock_timestamp() - v_t0) * 1000;
      v_n := v_n + 1;
      if j_old is distinct from j_new then
        v_bad := v_bad + 1;
      end if;
    end loop;
    if v_n <> 5 or v_bad <> 0 then
      raise exception '0207 self-assert FAIL: % of % probe boards differ from the pre-image', v_bad, v_n;
    end if;
    perform cmd.assume_identity(c_nil);

    v_out := format('passages from 4 harbours %s ms (was %s); %s boards %s ms (was %s)',
                    round(v_rp_new), round(v_rp_old), v_n, round(v_new_ms), round(v_old_ms));
    raise exception using errcode = 'ZX207', message = v_out;
  exception when sqlstate 'ZX207' then
    v_out := sqlerrm;
  end;
  perform cmd.assume_identity(c_nil);
  if exists (select 1 from public.players where auth_uid = c_uid) then
    raise exception '0207 self-assert FAIL: the probe company survived its rollback';
  end if;
  if exists (select 1 from defs_before_0207 d
              where coalesce((select p.proacl::text from pg_proc p where p.oid = d.fn::regprocedure), '') <> d.acl
                 or (select p.provolatile from pg_proc p where p.oid = d.fn::regprocedure) <> 's') then
    raise exception '0207 self-assert FAIL: an ACL moved, or a body is no longer STABLE';
  end if;
  raise notice '0207 self-assert ok: A GOOD OPENS AT ONCE. voyage.reach_passage reads each harbour''s miles once and asks the region door once a region (2 hunks); world.good_board asks it once (4 hunks); all reverse. Probe company: %.', v_out;
end $$;
