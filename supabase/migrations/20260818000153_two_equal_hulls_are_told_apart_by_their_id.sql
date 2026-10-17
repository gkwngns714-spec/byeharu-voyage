-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0153 — TWO EQUAL HULLS ARE TOLD APART BY THEIR ID  (never by where their rows lie on disk)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- Found by the correction to 0137's proof (PR #169, docs/dev-log/2026-10-18-0137-proof-pins-the-
-- hull-order.md): public.fleet_load walks a fleet's hulls `order by cap desc` and public.fleet_unload
-- `order by have desc`, and neither says what happens when two hulls tie. public.ships has no index
-- on fleet_id, so the tie is broken by the heap's physical order — and that order moves every time a
-- row is updated (a rolled-back run's dead tuples are enough). Which of two identical hulls takes a
-- parcel decides the fleet's laden speed, so the same order, on the same world, could sail at
-- 6.1547 kn or 6.3263 kn (measured on the growth-path world, 1 merchant of 837). The owner's default
-- (yes): break the tie by the ship's id.
--
-- ── WHAT SAYS THE OPPOSITE, NAMED ───────────────────────────────────────────────────────────────
-- public.fleet_load (last cut by 0081):   `where s.fleet_id = p_fleet order by cap desc loop`
-- public.fleet_unload (last cut by 0081): `from public.ships s where s.fleet_id = p_fleet order by have desc loop`
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- Adds `, s.id` to exactly those two ORDER BYs, sliced from the LIVE bodies (each hunk asserted to
-- occur exactly once). Largest hull first, fullest hull first, as before; between equals, the lower
-- id. Nothing else in either body moves: language, volatility, SECURITY DEFINER, search_path and
-- ACL are asserted unchanged, and each body reverses to its pre-image hunk by hunk.
--
-- ── WHAT IT DELIBERATELY DOES NOT ───────────────────────────────────────────────────────────────
-- No data is rewritten: a parcel already split across two hulls stays where it is. No other hull
-- order in the game is touched. 0137's proof pin (pg_temp, inside its rolled-back runs) is left as
-- it is: on a fresh chain it runs before this file, against the bodies it was written for.
--
-- ── SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────────
-- (a) parity by reverse substitution; ACL, language, volatility, definer and config unmoved.
-- (b) on a probe house of its OWN (founded inside a block that is rolled back; the live world is
--     never searched for a subject) with two hulls of one class: a load of one tun and an unload of
--     one tun each go to the lower id, in separate subtransactions, with first the one hull's row
--     and then the other's moved to the end of the heap. The old bodies' answers to the same runs
--     are reported (notice only: how the old sort breaks a tie is not something to assert).
-- (c) with the hulls made UNEQUAL (one re-classed to the nearest different hold) and unequal holds
--     to unload, in both directions and both heap orders, the new bodies write exactly what the
--     old bodies write (cargo and cost basis of every hull, and the returned quantity) — and the
--     loads really split across both hulls, so the compare is not vacuous.
-- Timings are notices only.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0153 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce(p.proacl::text, '') as acl,
       p.provolatile, p.prolang, p.prosecdef, coalesce(p.proconfig::text, '') as config
  from unnest(array['public.fleet_load(uuid, text, numeric, numeric)',
                    'public.fleet_unload(uuid, text, numeric)']) f(fn)
  join pg_proc p on p.oid = f.fn::regprocedure;

-- ── 2. THE HUNKS (old → new), sliced from the live bodies ──────────────────────────────────────
create temp table hunks_0153 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0153 values
('public.fleet_load(uuid, text, numeric, numeric)', 1,
$h$            where s.fleet_id = p_fleet order by cap desc loop
$h$,
$h$            where s.fleet_id = p_fleet order by cap desc, s.id loop   -- 0153: equal hulls by id
$h$),
('public.fleet_unload(uuid, text, numeric)', 1,
$h$             from public.ships s where s.fleet_id = p_fleet order by have desc loop
$h$,
$h$             from public.ships s where s.fleet_id = p_fleet order by have desc, s.id loop   -- 0153: equal hulls by id
$h$);

-- ── 3. THE RE-CUTS ─────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.recut_0153(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0153 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0153 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0153(fn) from defs_before_0153 order by fn;

-- ── 4. THE PROBE RUN (pg_temp, gone at commit) ─────────────────────────────────────────────────
-- One load or unload on the probe fleet, inside a subtransaction that is always undone. p_old runs
-- it against the pre-images (re-created inside the same subtransaction, so undone with it). p_set
-- fills the hulls ({ship_id: tuns}, every other hull emptied); p_reclass/p_class re-classes one hull;
-- p_move is updated last, so its row is moved to the end of the heap before the call.
create or replace function pg_temp.run_0153(p_old boolean, p_op text, p_fleet uuid, p_code text, p_qty numeric,
                                            p_set jsonb, p_reclass uuid, p_class uuid, p_move uuid)
returns jsonb
language plpgsql
as $$
declare
  v_def text;
  v_ret numeric;
  v_out jsonb;
  v_t0  timestamptz;
begin
  begin
    if p_old then
      for v_def in select def from defs_before_0153 order by fn loop
        execute v_def;
      end loop;
    end if;
    if p_reclass is not null then
      update public.ships set class_id = p_class where id = p_reclass;
    end if;
    update public.ships s
       set cargo = case when p_set ? s.id::text then jsonb_build_object(p_code, (p_set->>s.id::text)::numeric)
                        else '{}'::jsonb end,
           cargo_basis = case when p_set ? s.id::text then jsonb_build_object(p_code, 10) else '{}'::jsonb end
     where s.fleet_id = p_fleet;
    update public.ships set name = name where id = p_move;   -- its row now lies last on the heap
    v_t0 := clock_timestamp();
    if p_op = 'load' then
      v_ret := public.fleet_load(p_fleet, p_code, p_qty, 12);
    else
      v_ret := public.fleet_unload(p_fleet, p_code, p_qty);
    end if;
    v_out := jsonb_build_object(
      'ret', v_ret,
      'ms', extract(epoch from clock_timestamp() - v_t0) * 1000,
      'holds', (select jsonb_object_agg(s.id::text, jsonb_build_object('cargo', s.cargo, 'basis', s.cargo_basis))
                  from public.ships s where s.fleet_id = p_fleet),
      'caps', (select jsonb_object_agg(s.id::text, public.ship_hold_capacity(s.id))
                 from public.ships s where s.fleet_id = p_fleet));
    raise exception '__0153_UNDO__';
  exception when others then
    if sqlerrm <> '__0153_UNDO__' then raise; end if;
  end;
  return v_out;
end $$;

-- ── 5. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid      constant uuid := '00000000-0153-4000-8000-000000000001';
  v_players0 int := (select count(*) from public.players);
  v_fn       text;
  v_def      text;
  v_back     text;
  h          record;
  v_n        int;
  v_r        jsonb;
  v_player   uuid;
  v_fleet    uuid;
  v_flag     record;
  v_low      uuid;
  v_high     uuid;
  v_cap      numeric;
  v_code     text;
  v_bulk     numeric;
  v_other    uuid;
  v_other_hold numeric;
  v_hold     numeric;
  v_qty      numeric;
  v_move     uuid;
  v_new      jsonb;
  v_old      jsonb;
  v_case     record;
  v_ms       numeric := 0;
  v_k        int := 0;
  v_old_high int := 0;
  v_cases    int := 0;
  v_done     boolean := false;
begin
  -- (a) PARITY BY REVERSE SUBSTITUTION; ACL, language, volatility, definer, config unmoved.
  for v_fn in select fn from defs_before_0153 loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0153 where fn = v_fn order by n desc loop
      v_n := (length(v_back) - length(replace(v_back, h.new, ''))) / length(h.new);
      if v_n <> 1 then
        raise exception '0153 self-assert FAIL: hunk % of % is in the new body % time(s), not once', h.n, v_fn, v_n;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back <> (select def from defs_before_0153 where fn = v_fn) or v_def = v_back then
      raise exception '0153 self-assert FAIL: % is not its pre-image plus only 0153''s hunk', v_fn;
    end if;
    if exists (select 1 from pg_proc p join defs_before_0153 d on d.fn = v_fn
                where p.oid = v_fn::regprocedure
                  and (coalesce(p.proacl::text, '') is distinct from d.acl
                       or p.provolatile is distinct from d.provolatile
                       or p.prolang is distinct from d.prolang
                       or p.prosecdef is distinct from d.prosecdef
                       or coalesce(p.proconfig::text, '') is distinct from d.config)) then
      raise exception '0153 self-assert FAIL: the re-cut of % moved its ACL, language, volatility, definer or config', v_fn;
    end if;
  end loop;

  -- (b) and (c), on a probe house of the probe's own; everything below is rolled back.
  begin
    perform cmd.assume_identity(c_uid);
    v_r := cmd.found_house('Casa das Gemeas 0153', 'prt');
    if not coalesce((v_r->>'ok')::boolean, false) then
      raise exception '0153 self-assert FAIL: the probe house was not founded: %', v_r;
    end if;
    v_player := (v_r->>'player_id')::uuid;
    select f.id into v_fleet from public.fleets f where f.player_id = v_player order by f.id limit 1;
    if (select count(*) from public.ships where fleet_id = v_fleet) <> 1 then
      raise exception '0153 self-assert FAIL: the probe house''s first fleet has % hull(s), not the one this probe twins',
        (select count(*) from public.ships where fleet_id = v_fleet);
    end if;
    select * into v_flag from public.ships where fleet_id = v_fleet;
    -- THE TWIN: a second hull of the flagship's own class, crewed and sound as she is.
    insert into public.ships (player_id, fleet_id, class_id, name, durability, crew, water_t, food_t, store_ratio, is_flagship)
    values (v_player, v_fleet, v_flag.class_id, 'Gemea 0153', v_flag.durability, v_flag.crew, 0, 0, v_flag.store_ratio, false);
    update public.ships set water_t = 0, food_t = 0, cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where fleet_id = v_fleet;
    select id into v_low  from public.ships where fleet_id = v_fleet order by id limit 1;
    select id into v_high from public.ships where fleet_id = v_fleet order by id desc limit 1;
    v_cap := public.ship_hold_capacity(v_low);
    if v_low = v_high or v_cap is distinct from public.ship_hold_capacity(v_high) or v_cap <= 0 then
      raise exception '0153 self-assert FAIL: the two probe hulls do not hold the same (% and %) — no tie to break',
        public.ship_hold_capacity(v_low), public.ship_hold_capacity(v_high);
    end if;
    -- the subject good: the least bulky (then by code), so whole tuns fit with room to spare
    select g.code, g.bulk into v_code, v_bulk from public.goods g where g.bulk > 0 order by g.bulk, g.code limit 1;
    if v_code is null or floor(v_cap / v_bulk) < 3 then
      raise exception '0153 self-assert FAIL: no good fits three tuns in a % hold (subject %, bulk %)', v_cap, v_code, v_bulk;
    end if;

    -- (b) EQUAL HULLS: the lower id, whichever row lies last on the heap.
    foreach v_move in array array[v_low, v_high] loop
      -- a load of one tun goes into the lower id
      v_new := pg_temp.run_0153(false, 'load', v_fleet, v_code, 1, '{}'::jsonb, null, null, v_move);
      if (v_new->>'ret')::numeric <> 1
         or (v_new->'holds'->v_low::text->'cargo'->>v_code)::numeric is distinct from 1
         or (v_new->'holds'->v_high::text->'cargo') <> '{}'::jsonb then
        raise exception '0153 self-assert FAIL: with % moved last, one tun went %, not into the lower id %',
          v_move, v_new->'holds', v_low;
      end if;
      v_ms := v_ms + (v_new->>'ms')::numeric; v_k := v_k + 1;
      v_old := pg_temp.run_0153(true, 'load', v_fleet, v_code, 1, '{}'::jsonb, null, null, v_move);
      if (v_old->'holds'->v_high::text->'cargo'->>v_code)::numeric = 1 then v_old_high := v_old_high + 1; end if;
      -- an unload of one tun from two hulls holding two each comes out of the lower id
      v_new := pg_temp.run_0153(false, 'unload', v_fleet, v_code, 1,
                                jsonb_build_object(v_low::text, 2, v_high::text, 2), null, null, v_move);
      if (v_new->>'ret')::numeric <> 1
         or (v_new->'holds'->v_low::text->'cargo'->>v_code)::numeric is distinct from 1
         or (v_new->'holds'->v_high::text->'cargo'->>v_code)::numeric is distinct from 2 then
        raise exception '0153 self-assert FAIL: with % moved last, one tun of two-and-two came out as %, not out of the lower id %',
          v_move, v_new->'holds', v_low;
      end if;
      v_ms := v_ms + (v_new->>'ms')::numeric; v_k := v_k + 1;
      v_old := pg_temp.run_0153(true, 'unload', v_fleet, v_code, 1,
                                jsonb_build_object(v_low::text, 2, v_high::text, 2), null, null, v_move);
      if (v_old->'holds'->v_high::text->'cargo'->>v_code)::numeric = 1 then v_old_high := v_old_high + 1; end if;
    end loop;

    -- (c) UNEQUAL HULLS: the new bodies write what the old ones write.
    -- the nearest different hold among the classes (then by code)
    select c.id, c.hold into v_other, v_other_hold
      from public.ship_classes c, public.ship_classes f0
     where f0.id = v_flag.class_id and c.hold <> f0.hold
     order by abs(c.hold - f0.hold), c.code limit 1;
    if v_other is null then
      raise exception '0153 self-assert FAIL: no ship class holds other than the flagship''s — no unequal case';
    end if;
    for v_case in select * from (values
        -- re-class the lower id, then the higher, and load past the larger hull's room
        ('load',   v_low,  '{}'::jsonb),
        ('load',   v_high, '{}'::jsonb),
        -- unequal holds to unload, both ways round, more than either hull holds
        ('unload', null::uuid, jsonb_build_object(v_low::text, 3, v_high::text, 5)),
        ('unload', null::uuid, jsonb_build_object(v_low::text, 5, v_high::text, 3))) c(op, reclass, setv) loop
      foreach v_move in array array[v_low, v_high] loop
        if v_case.op = 'load' then
          -- the larger of the two holds once re-classed (the probe reads the caps the run reports)
          v_r := pg_temp.run_0153(false, 'load', v_fleet, v_code, 0, '{}'::jsonb, v_case.reclass, v_other, v_move);
          select max(value::text::numeric), min(value::text::numeric) into v_hold, v_cap from jsonb_each(v_r->'caps');
          if v_hold = v_cap then
            raise exception '0153 self-assert FAIL: re-classed, the two hulls still hold the same (%) — no unequal case', v_hold;
          end if;
          v_qty := floor(v_hold / v_bulk) + 1;
        else
          v_qty := 6;
        end if;
        v_new := pg_temp.run_0153(false, v_case.op, v_fleet, v_code, v_qty, v_case.setv, v_case.reclass, v_other, v_move);
        v_old := pg_temp.run_0153(true,  v_case.op, v_fleet, v_code, v_qty, v_case.setv, v_case.reclass, v_other, v_move);
        if (v_new - 'ms') is distinct from (v_old - 'ms') then
          raise exception '0153 self-assert FAIL: on unequal hulls (% % tuns, re-classed %, % moved last) the new body wrote % and the old %',
            v_case.op, v_qty, v_case.reclass, v_move, v_new - 'ms', v_old - 'ms';
        end if;
        -- not vacuous: something moved, and a load really split across both hulls
        if (v_new->>'ret')::numeric <> v_qty
           or (v_case.op = 'load' and (select count(*) from jsonb_each(v_new->'holds') e
                                        where (e.value->'cargo'->>v_code)::numeric > 0) <> 2) then
          raise exception '0153 self-assert FAIL: the unequal case (% % tuns) moved % and left %, so the compare proves nothing',
            v_case.op, v_qty, v_new->>'ret', v_new->'holds';
        end if;
        v_ms := v_ms + (v_new->>'ms')::numeric; v_k := v_k + 1;
        v_cases := v_cases + 1;
      end loop;
    end loop;
    v_done := true;
    raise exception '__0153_PROBE_UNDO__';
  exception when others then
    if sqlerrm <> '__0153_PROBE_UNDO__' then raise; end if;
  end;

  if not v_done or v_cases <> 8 then
    raise exception '0153 self-assert FAIL: the probe did not run to its end (% unequal case(s))', v_cases;
  end if;
  if (select count(*) from public.players) <> v_players0
     or exists (select 1 from public.ships where name = 'Gemea 0153') then
    raise exception '0153 self-assert FAIL: the probe world was not rolled back';
  end if;

  raise notice '0153 loads and unloads timed: % call(s), mean % ms', v_k, round(v_ms / greatest(v_k, 1), 3);
  raise notice '0153 the old bodies, on the same 4 equal-hull runs, put the tun in (or took it from) the higher id % time(s)', v_old_high;
  raise notice '0153 self-assert ok: TWO EQUAL HULLS ARE TOLD APART BY THEIR ID. fleet_load and fleet_unload reverse to their pre-images hunk by hunk, ACL, language, volatility, definer and config unmoved; on a probe house of two equal hulls a load and an unload of one tun went to the lower id with either row last on the heap (4 runs in 4 subtransactions); on unequal hulls the new bodies wrote what the old wrote in % case(s), every load split across both hulls. Rolled back.',
    v_cases;
end $$;
