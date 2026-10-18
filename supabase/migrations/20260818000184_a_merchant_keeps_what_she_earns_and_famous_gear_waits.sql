-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0184 — A MERCHANT KEEPS WHAT SHE EARNS, AND FAMOUS GEAR WAITS  (0180's purse ceiling and hull
--        building are deleted; no workshop makes a famous piece, so no famous ship is laid down)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS (2026-10-18 ~13:25 UTC) ───────────────────────────────────────────────────
-- *"no need to hand in surplus... wtf. no they don't need to build ships."* And: *"yes famous gear can
-- be made, but later. there will be other items that needs to be gained in act of pirating, trading,
-- and all. i will set them later."* 0180's sinks (a) and (d) were chosen by default, not by him: he
-- rejected them, so they are DELETED here, not adapted (docs/OWNER_REQUESTS.md).
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) SINK (a) IS GONE: public.npc_give_above_ceiling and public.npc_purse_ceiling are dropped, and the
--     knob npc_purse_ceiling with them. public.npc_tend_houses no longer calls the pass and its receipt
--     no longer carries `ceiling` / `ceiling_given` — its body is its pre-0180 body again.
-- (2) SINK (d) IS GONE: public.npc_build_for is dropped. public.npc_tend_route no longer calls it and
--     its receipt no longer carries `built` (0181's `waiting` stays). public.npc_tend_sum adds up the
--     pre-0180 counts plus 0181's `waiting`.
--     KEPT from 0180: public.npc_leg_lines' "a BUY line is never born refused" (0181 reworded it; not
--     touched here). KEPT as books: every MERCHANT_SURPLUS ledger row, treasury flow and SURPLUS_GIVEN
--     event already written (append-only history; nothing here deletes a row of them), and every hull
--     0180 laid down stays its company's ship.
-- (3) FAMOUS GEAR IS MADE NOWHERE, FOR NOW. public.item_unmade — one row per item no workshop makes,
--     generated (scripts/build-gear.mjs FAMOUS_MADE = false writes each Famous piece `made: false`;
--     `--sql-0184` gives the VALUES below) and held by the world guard. public.item_not_made(item) is
--     THE one sentence ("Drake's Culverins is not made in any workshop yet"); public.made_only_in reads
--     it first, so cmd.do_make refuses E_NOT_MADE_HERE and world.workstation serves `makeable` false
--     with the sentence — neither body is touched. The recipes stay authored (data and item_recipes),
--     for the day the owner sets how a piece is won.
-- (4) A FAMOUS SHIP WAITS WITH HER GEAR. Each famous hull's one fitting is its famous piece
--     (hull_recipe_items, 0165), so with the piece made nowhere the hull cannot be laid down.
--     public.hull_unmade(class) is THE one sentence ("Golden Hind cannot be laid down yet: Drake's
--     Culverins is not made in any workshop yet"), read by cmd.do_build (E_NOT_BUILDABLE, before every
--     other rule of the yard) and world.building_yard (folded into `buildable`, served as `unmade` only
--     where it applies). It is derived from the parts, never a list of hulls. Measured on prod before
--     this file (2026-10-18, read-only): 0 famous ships, 0 famous pieces held or fitted, 0 companies with
--     Famous Ships I — so nobody loses anything; with skills_bite on, any company that learned Famous
--     Ships I could have made a piece and laid a famous hull down.
--
-- ── NOT THE OWNER'S — CONFIRM ───────────────────────────────────────────────────────────────────
-- * The two sentences' wording, and E_NOT_BUILDABLE (an existing code) for a hull whose part is made
--   nowhere.
--
-- ── LOCKS AND TIME ──────────────────────────────────────────────────────────────────────────────
-- CREATE TABLE ×1 (11 rows), CREATE FUNCTION ×2, DROP FUNCTION ×3, one world_config DELETE, CREATE OR
-- REPLACE FUNCTION ×6 by hunks. The probes run on one merchant fleet's own rows inside sub-transactions
-- rolled back whole (asserted). No LOCK TABLE, no set role, no set local, no begin. Timings are notices.
-- SUPERSEDES, by hunks sliced from the LIVE bodies (prod head 0183, LF-normalised, each asserted to
-- occur exactly once and to reverse to its pre-image, ACL unchanged): public.npc_tend_route (0181
-- line), public.npc_tend_houses (0180), public.npc_tend_sum (0181), public.made_only_in (0163),
-- world.building_yard (0165), cmd.do_build (0165). 0180's three functions are dropped.
-- ROLLBACK: a forward slice restores the six bodies (each hunk's OLD text is here verbatim), drops the
-- two functions and the table; 0180's file holds the three dropped functions verbatim.
-- VERSION: 0184 (provisional; renumbered to head + 1 at deploy). Applies on prod head 0183.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0184(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0184 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from (values ('public.npc_tend_route(timestamp with time zone,uuid,uuid,bigint)'),
               ('public.npc_tend_houses(timestamp with time zone)'),
               ('public.npc_tend_sum(jsonb,jsonb)'),
               ('public.made_only_in(text,uuid)'),
               ('world.building_yard(uuid)'),
               ('cmd.do_build(uuid,jsonb)')) f(fn);

do $$
begin
  if (select count(*) from defs_before_0184 where def is not null) <> 6 then
    raise exception '0184 self-assert FAIL: % of the 6 bodies found', (select count(*) from defs_before_0184 where def is not null);
  end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
       and p.proname in ('npc_purse_ceiling', 'npc_give_above_ceiling', 'npc_build_for')) <> 3 then
    raise exception '0184 self-assert FAIL: 0180''s three functions are not all there to drop';
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('item_not_made', 'hull_unmade'))
     or to_regclass('public.item_unmade') is not null then
    raise exception '0184 self-assert FAIL: a function or table this file creates exists already';
  end if;
end $$;

-- ── 2. (1) + (2) THE HUNKS THAT TAKE 0180's SINKS OUT, AND (3) + (4) THE ONES THAT READ "MADE NOWHERE"
create temporary table hunks_0184 (fn text not null, n int not null, old text not null, new text not null,
                                   primary key (fn, n)) on commit drop;
insert into hunks_0184 values
('public.npc_tend_route(timestamp with time zone,uuid,uuid,bigint)', 1,
$h$  v_notes   jsonb := '[]'::jsonb;
  v_built   int := 0;   -- 0180 (d): hulls she laid down this hour
  v_waiting int := 0;   -- 0181: laid up in port, nothing on her loops paying
$h$,
$h$  v_notes   jsonb := '[]'::jsonb;
  v_waiting int := 0;   -- 0181: laid up in port, nothing on her loops paying
$h$),
('public.npc_tend_route(timestamp with time zone,uuid,uuid,bigint)', 2,
$h$      -- 0180 (d): SHE SPENDS HER SURPLUS ON HER FLEET — lying docked at a build yard while her house
      -- stands above her purse ceiling, one hull (public.npc_build_for: the players' doors, paid into
      -- this city). Budgeted like the dear work above.
      if f.status = 'DOCKED' and not public.npc_upkeep_spent() then
        v_res := public.npc_build_for(r.fleet_id, p_now);
        if v_res is not null then
          v_built := v_built + coalesce((v_res->>'built')::int, 0);
          v_notes := v_notes || (jsonb_build_object('route', sr.name) || v_res);
        end if;
      end if;

      -- THE HALT LAW'S RELEASE, counted: clears with no lap closed between share her lap number.
$h$,
$h$      -- THE HALT LAW'S RELEASE, counted: clears with no lap closed between share her lap number.
$h$),
('public.npc_tend_route(timestamp with time zone,uuid,uuid,bigint)', 3,
$h$                            'built', v_built,   -- 0180 (d)
                            'waiting', v_waiting,   -- 0181
$h$,
$h$                            'waiting', v_waiting,   -- 0181
$h$),
('public.npc_tend_houses(timestamp with time zone)', 1,
$h$  v_inv      jsonb := '{}'::jsonb;
  v_ceil     jsonb := '{}'::jsonb;   -- 0180 (a): the purse ceiling's pass
$h$,
$h$  v_inv      jsonb := '{}'::jsonb;
$h$),
('public.npc_tend_houses(timestamp with time zone)', 2,
$h$    v_notes := v_notes || coalesce(v_inv->'notes', '[]'::jsonb);
  end if;

  -- 0180 (a): ABOVE HER PURSE CEILING, the rest goes to the cities of her loop (public.npc_give_above_ceiling).
  if v_on then
    v_ceil := public.npc_give_above_ceiling(p_now);
    v_deferred := v_deferred + coalesce((v_ceil->>'deferred')::int, 0);
    v_failed := v_failed + coalesce((v_ceil->>'failed')::int, 0);
    v_notes := v_notes || coalesce(v_ceil->'notes', '[]'::jsonb);
  end if;
$h$,
$h$    v_notes := v_notes || coalesce(v_inv->'notes', '[]'::jsonb);
  end if;
$h$),
('public.npc_tend_houses(timestamp with time zone)', 3,
$h$                            'donated', coalesce((v_inv->>'donated')::int, 0),   -- 0145
                            'ceiling', coalesce((v_ceil->>'ceiling')::int, 0),   -- 0180 (a)
                            'ceiling_given', coalesce((v_ceil->>'given')::bigint, 0) + coalesce((v_ceil->>'shares')::bigint, 0),
$h$,
$h$                            'donated', coalesce((v_inv->>'donated')::int, 0),   -- 0145
$h$),
('public.npc_tend_sum(jsonb,jsonb)', 1,
$h$                             'built', 'ceiling', 'ceiling_given', 'waiting'] loop   -- 0145: donated; 0180: built, ceiling, ceiling_given; 0181: waiting
$h$,
$h$                             'waiting'] loop   -- 0145: donated; 0181: waiting (0184: 0180's built, ceiling, ceiling_given gone)
$h$),
('public.made_only_in(text,uuid)', 1,
$h$  return coalesce(
$h$,
$h$  return coalesce(
         -- 0184: an item NO workshop makes (public.item_unmade: the Famous pieces, until the owner sets how
         -- they are won) — first, so it is never "made only in" some city
         public.item_not_made(p_item),
$h$),
('world.building_yard(uuid)', 1,
$h$                     and yw.held is null,                                                -- 0165: and, a famous ship, not one it keeps
$h$,
$h$                     and yw.held is null                                                 -- 0165: and, a famous ship, not one it keeps
                     and yw.unmade is null,                                              -- 0184: and every part of her made somewhere
$h$),
('world.building_yard(uuid)', 2,
$h$        || case when yw.held is null then '{}'::jsonb else jsonb_build_object('famous_held', yw.held) end
$h$,
$h$        || case when yw.held is null then '{}'::jsonb else jsonb_build_object('famous_held', yw.held) end
        -- 0184: a hull whose part no workshop makes says so (public.hull_unmade, cmd.do_build's sentence), only then
        || case when yw.unmade is null then '{}'::jsonb else jsonb_build_object('unmade', yw.unmade) end
$h$),
('world.building_yard(uuid)', 3,
$h$                                 public.famous_held(v_player, c.code) as held) yw));                     -- 0165
$h$,
$h$                                 public.famous_held(v_player, c.code) as held,                           -- 0165
                                 public.hull_unmade(c.code) as unmade) yw));                             -- 0184
$h$),
('cmd.do_build(uuid,jsonb)', 1,
$h$    raise exception 'E_NOT_BUILDABLE: % is not a hull any yard lays down', c.name using errcode = 'P0001';
  end if;
$h$,
$h$    raise exception 'E_NOT_BUILDABLE: % is not a hull any yard lays down', c.name using errcode = 'P0001';
  end if;
  -- 0184: A HULL WHOSE PART NO WORKSHOP MAKES IS NOT LAID DOWN — public.hull_unmade, the one sentence (the
  -- build yard serves the same one): a famous ship waits with her famous gear.
  if public.hull_unmade(c.code) is not null then
    perform cmd.refuse('E_NOT_BUILDABLE', public.hull_unmade(c.code));
  end if;
$h$);

-- ── 3. (3) THE ITEMS MADE NOWHERE, AND THE TWO SENTENCES (before the bodies that read them) ─────
create table public.item_unmade (
  item_code text primary key references public.item_kinds (code)
);
comment on table public.item_unmade is
  '0184: an item NO workshop makes — one row per item (the Famous pieces, until the owner sets how they are '
  'won). Read only by public.item_not_made. Generated (scripts/build-gear.mjs `made: false`, --sql-0184), held '
  'by the world guard. Server-only.';
alter table public.item_unmade enable row level security;
revoke all on table public.item_unmade from public, anon, authenticated;

insert into public.item_unmade (item_code) values
  ('madre-de-deus-holds'),
  ('san-martin-tercio'),
  ('batavia-double-planking'),
  ('drakes-culverins'),
  ('couronne-battery'),
  ('duodo-bow-guns'),
  ('turgut-reis-swivels'),
  ('rahimi-pilgrim-holds'),
  ('zheng-he-bulkheads'),
  ('date-masamune-charts'),
  ('dragon-head-cannon');

create function public.item_not_made(p_item text)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0184: THE ONE SENTENCE OF "MADE NOWHERE" — null where some workshop makes the item, else "Drake's
  -- Culverins is not made in any workshop yet" (public.item_unmade). Read by public.made_only_in (so
  -- cmd.do_make and world.workstation) and public.hull_unmade.
  select format('%s is not made in any workshop yet', k.name)
    from public.item_unmade u join public.item_kinds k on k.code = u.item_code
   where u.item_code = p_item
$$;
comment on function public.item_not_made(text) is
  '0184: the one sentence of an item no workshop makes, or null. Server-only.';
revoke all on function public.item_not_made(text) from public, anon, authenticated;

create function public.hull_unmade(p_class text)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0184: THE ONE SENTENCE OF A HULL THAT CANNOT BE LAID DOWN BECAUSE A PART OF HER IS MADE NOWHERE —
  -- null when every fitting of her recipe (hull_recipe_items) is made somewhere; else "Golden Hind cannot
  -- be laid down yet: Drake's Culverins is not made in any workshop yet". Derived from her parts
  -- (public.item_not_made), never a list of hulls. Read by cmd.do_build and world.building_yard.
  select format('%s cannot be laid down yet: %s', c.name,
                string_agg(public.item_not_made(hi.item_code), '; ' order by hi.item_code))
    from public.hull_recipe_items hi join public.ship_classes c on c.code = hi.class_code
   where hi.class_code = p_class and public.item_not_made(hi.item_code) is not null
   group by c.name
$$;
comment on function public.hull_unmade(text) is
  '0184: the one sentence of a hull a part of which no workshop makes, or null. Server-only.';
revoke all on function public.hull_unmade(text) from public, anon, authenticated;

-- ── 4. THE BODIES (each hunk once; each body reverses to its pre-image; ACL unchanged) ───────────
do $$
declare
  d     record;
  h     record;
  v_def text;
  v_rev text;
begin
  for d in select * from defs_before_0184 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0184 where fn = d.fn order by n loop
      if pg_temp.occurs_0184(v_def, h.old) <> 1 then
        raise exception '0184 self-assert FAIL: hunk % of % occurs % time(s), not once — the deployed body is not what this file was written against',
          h.n, d.fn, pg_temp.occurs_0184(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    if v_def = d.def then
      raise exception '0184 self-assert FAIL: no hunk for %', d.fn;
    end if;
    execute v_def;
    v_rev := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0184 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0184(v_rev, h.new) <> 1 then
        raise exception '0184 self-assert FAIL: hunk % of % is not in the new body once', h.n, d.fn;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0184 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = d.fn::regprocedure), '') <> d.acl then
      raise exception '0184 self-assert FAIL: the ACL of % moved', d.fn;
    end if;
  end loop;
end $$;

-- ── 5. (1) + (2) 0180's FUNCTIONS AND KNOB, DELETED ─────────────────────────────────────────────
drop function public.npc_build_for(uuid, timestamptz);
drop function public.npc_give_above_ceiling(timestamptz, uuid);
drop function public.npc_purse_ceiling(uuid);
delete from public.world_config where key = 'npc_purse_ceiling';

-- ── 6. THE PROBES (own state, every one rolled back whole) ─────────────────────────────────────
create temp table probe_0184 (k text primary key, j jsonb) on commit drop;

-- one merchant fleet (roster order) laid at a harbour with a tier ≥ 3 workshop and a yard: a famous piece is
-- refused at the workshop's door, a G1 there passes every gate to the materials (positive control); a famous
-- hull is refused at the yard's door with the yard's own sentence, a plain hull passes it to the shed.
do $$
declare
  v_f     uuid;
  v_port  uuid;
  v_ws    jsonb;
  v_yard  jsonb;
  v_g1    text;
  v_plain text;
  v_out   jsonb := '{}'::jsonb;
  v_t0    timestamptz := clock_timestamp();
  e       text;
begin
  begin
    select nf.fleet_id into v_f from public.npc_fleets nf order by nf.roster_ord limit 1;
    select b.port_id into v_port from public.port_buildings b
      join public.port_buildings y on y.port_id = b.port_id and y.kind = 'building_yard'
      join public.ports p on p.id = b.port_id
     where b.kind = 'workstation' and b.tier >= 3 order by p.code limit 1;
    if v_f is null or v_port is null then
      raise exception '0184 self-assert FAIL: no merchant fleet (%) or no harbour with a tier-3 workshop and a yard (%)', v_f, v_port;
    end if;
    -- THE PRECONDITION: her fleet lies docked here (a passage she is on is set aside)
    update public.voyages set status = 'ABORTED' where fleet_id = v_f and status = 'SAILING';
    update public.fleets set status = 'DOCKED', port_id = v_port, lat = null, lon = null where id = v_f;
    -- a G1 fitting with a recipe, no skill, no city, at a tier this workshop makes (the control)
    select k.code into v_g1 from public.item_kinds k join public.item_profile ip on ip.item_code = k.code
     where k.kind = 'fitting' and ip.grade = 1 and k.ws_tier <= 3
       and public.made_only_in(k.code, v_port) is null
       and public.requirements_met((select f.player_id from public.fleets f where f.id = v_f), 'item', k.code)
       and exists (select 1 from public.item_recipes ir where ir.item_code = k.code)
     order by k.code limit 1;
    -- a hull with no part made nowhere (the control)
    select h.class_code into v_plain from public.hull_recipes h where public.hull_unmade(h.class_code) is null order by h.class_code limit 1;
    v_out := v_out || jsonb_build_object('g1', v_g1, 'plain', v_plain);

    begin
      perform cmd.do_make(v_f, jsonb_build_object('item', 'drakes-culverins'));
      v_out := v_out || jsonb_build_object('make_famous', 'MADE');
    exception when others then
      v_out := v_out || jsonb_build_object('make_famous', sqlerrm);
    end;
    begin
      perform cmd.do_make(v_f, jsonb_build_object('item', v_g1));
      v_out := v_out || jsonb_build_object('make_g1', 'MADE');
    exception when others then
      v_out := v_out || jsonb_build_object('make_g1', split_part(sqlerrm, ':', 1));
    end;
    begin
      perform cmd.do_build(v_f, jsonb_build_object('class', 'goldenhind', 'name', 'Probe 0184'));
      v_out := v_out || jsonb_build_object('build_famous', 'BUILT');
    exception when others then
      v_out := v_out || jsonb_build_object('build_famous', sqlerrm);
    end;
    begin
      perform cmd.do_build(v_f, jsonb_build_object('class', v_plain, 'name', 'Probe 0184'));
      v_out := v_out || jsonb_build_object('build_plain', 'BUILT');
    exception when others then
      v_out := v_out || jsonb_build_object('build_plain', split_part(sqlerrm, ':', 1));
    end;

    -- the screens: the workshop and the yard of this harbour
    v_ws := world.workstation(v_port, v_f);
    v_yard := world.building_yard(v_port);
    v_out := v_out || jsonb_build_object(
      'ws_unmade', (select count(*) from jsonb_array_elements(v_ws->'items') x
                     where x->>'code' in (select item_code from public.item_unmade)
                       and not (x->>'makeable')::boolean and x->>'made_only_in' = public.item_not_made(x->>'code')),
      'ws_unmade_listed', (select count(*) from jsonb_array_elements(v_ws->'items') x where x->>'code' in (select item_code from public.item_unmade)),
      'ws_g1_makeable', (select (x->>'makeable')::boolean from jsonb_array_elements(v_ws->'items') x where x->>'code' = v_g1),
      'yard_unmade', (select count(*) from jsonb_array_elements(v_yard->'hulls') x
                       where x ? 'unmade' and not (x->>'buildable')::boolean and x->>'unmade' = public.hull_unmade(x->>'class')),
      'yard_famous', (select count(*) from jsonb_array_elements(v_yard->'hulls') x
                       where x->>'class' in (select cp.class_code from public.class_profile cp where cp.tech = 'F')),
      'yard_famous_unmade', (select count(*) from jsonb_array_elements(v_yard->'hulls') x
                              where x ? 'unmade' and x->>'class' in (select cp.class_code from public.class_profile cp where cp.tech = 'F')),
      'yard_other_unmade', (select count(*) from jsonb_array_elements(v_yard->'hulls') x
                             where x ? 'unmade' and x->>'class' not in (select cp.class_code from public.class_profile cp where cp.tech = 'F')),
      'hulls_unmade', (select count(*) from public.hull_recipes h where public.hull_unmade(h.class_code) is not null),
      'famous_hulls', (select count(*) from public.class_profile cp where cp.tech = 'F'),
      'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
    raise exception 'PROBE_ROLLBACK_0184:%', v_out::text;
  exception when others then
    if sqlerrm not like 'PROBE_ROLLBACK_0184:%' then raise; end if;
    insert into probe_0184 values ('made', substr(sqlerrm, length('PROBE_ROLLBACK_0184:') + 1)::jsonb);
  end;
end $$;

-- ── 7. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  m jsonb := (select j from probe_0184 where k = 'made');
  s jsonb := public.npc_tend_sum(jsonb_build_object('waiting', 2, 'invested', 1), jsonb_build_object('waiting', 1, 'built', 4, 'ceiling', 5));
begin
  -- (1) + (2): the three functions, the knob and every caller gone
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname in ('npc_purse_ceiling', 'npc_give_above_ceiling', 'npc_build_for')) then
    raise exception '0184 self-assert FAIL: one of 0180''s three functions survived';
  end if;
  if exists (select 1 from public.world_config where key = 'npc_purse_ceiling') then
    raise exception '0184 self-assert FAIL: the knob npc_purse_ceiling survived';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'cmd', 'voyage', 'world')
                and p.prosrc ~ '(npc_purse_ceiling|npc_give_above_ceiling|npc_build_for)') then
    raise exception '0184 self-assert FAIL: a live body still reads 0180''s sinks: %',
      (select string_agg(n.nspname || '.' || p.proname, ', ') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname in ('public', 'cmd', 'voyage', 'world')
          and p.prosrc ~ '(npc_purse_ceiling|npc_give_above_ceiling|npc_build_for)');
  end if;
  if s ? 'built' or s ? 'ceiling' or s ? 'ceiling_given' or (s->>'waiting')::int <> 3 or (s->>'invested')::int <> 1 then
    raise exception '0184 self-assert FAIL: npc_tend_sum still adds 0180''s counts or lost its own: %', s;
  end if;
  -- (3): the rows are the generator's 11, every one a fitting
  if (select count(*) from public.item_unmade) <> 11
     or exists (select 1 from public.item_unmade u join public.item_kinds k on k.code = u.item_code where k.kind <> 'fitting')
     or exists (select 1 from public.item_unmade u where not exists (select 1 from public.hull_recipe_items hi where hi.item_code = u.item_code)) then
    raise exception '0184 self-assert FAIL: public.item_unmade is not the 11 famous pieces, each a famous hull''s part';
  end if;
  if m->>'make_famous' <> 'E_NOT_MADE_HERE: ' || public.item_not_made('drakes-culverins') then
    raise exception '0184 self-assert FAIL: the workshop door answered a famous piece with "%"', m->>'make_famous';
  end if;
  if m->>'g1' is null or m->>'make_g1' <> 'E_NO_MATERIALS' then
    raise exception '0184 self-assert FAIL: the positive control (G1 %) met "%" at the workshop door, not E_NO_MATERIALS', m->>'g1', m->>'make_g1';
  end if;
  if (m->>'ws_unmade')::int <> 11 or (m->>'ws_unmade_listed')::int <> 11 or not (m->>'ws_g1_makeable')::boolean then
    raise exception '0184 self-assert FAIL: the workshop served % of the 11 famous pieces closed with the sentence (% listed); the G1 makeable %',
      m->>'ws_unmade', m->>'ws_unmade_listed', m->>'ws_g1_makeable';
  end if;
  -- (4)
  if m->>'build_famous' <> 'E_NOT_BUILDABLE: ' || public.hull_unmade('goldenhind') then
    raise exception '0184 self-assert FAIL: the yard door answered a Golden Hind with "%"', m->>'build_famous';
  end if;
  if m->>'plain' is null or m->>'build_plain' in ('E_NOT_BUILDABLE', 'BUILT') then
    raise exception '0184 self-assert FAIL: the positive control (%) met "%" at the yard door', m->>'plain', m->>'build_plain';
  end if;
  if (m->>'hulls_unmade')::int <> (m->>'famous_hulls')::int or (m->>'famous_hulls')::int <> 11
     or (m->>'yard_famous_unmade')::int <> (m->>'yard_famous')::int or (m->>'yard_other_unmade')::int <> 0
     or (m->>'yard_unmade')::int <> (m->>'yard_famous')::int or (m->>'yard_famous')::int < 1 then
    raise exception '0184 self-assert FAIL: % hulls cannot be laid down (want the % famous); the yard served % of its % famous closed with the sentence, % others closed',
      m->>'hulls_unmade', m->>'famous_hulls', m->>'yard_unmade', m->>'yard_famous', m->>'yard_other_unmade';
  end if;

  raise notice '0184 self-assert ok: A MERCHANT KEEPS WHAT SHE EARNS, AND FAMOUS GEAR WAITS. (1)+(2) npc_give_above_ceiling, npc_purse_ceiling and npc_build_for dropped with the knob; no live body reads them; npc_tend_houses / npc_tend_route / npc_tend_sum carry no built, ceiling or ceiling_given (0181''s waiting kept); the MERCHANT_SURPLUS books untouched. (3) 11 famous pieces made nowhere: the workshop door refuses "%" (a G1 %, the control, reaches E_NO_MATERIALS), the workshop serves all 11 closed with the sentence. (4) % of % hulls cannot be laid down — exactly the famous ones, derived from their parts: the yard door refuses "%" (%, the control, passes to %), the yard serves % of its % famous closed and no other. Bodies reverse, ACLs unchanged (% ms).',
    public.item_not_made('drakes-culverins'), m->>'g1', m->>'hulls_unmade', (select count(*) from public.hull_recipes),
    public.hull_unmade('goldenhind'), m->>'plain', m->>'build_plain', m->>'yard_unmade', m->>'yard_famous', m->>'ms';
end $$;
