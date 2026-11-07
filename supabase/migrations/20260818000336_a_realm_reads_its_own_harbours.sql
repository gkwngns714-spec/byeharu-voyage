-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0336 — A REALM READS ITS OWN HARBOURS: public.cargo_origins asks whose a harbour is BEFORE it asks what the harbour can give. NO BEHAVIOUR CHANGE
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- A pure performance fix, found while W7 (`convoy_rich_enabled`, 0324) waits to be lit. Measured on prod, read only, 2026-11-07, head 0335, for ESP, the biggest realm. The plan of the lit arm of public.cargo_origins:
--   Seq Scan on ports h   Filter: ((kind = 'HARBOUR') AND (crown_call_room(id) > 0) AND (port_nation(id) = (InitPlan 1).col1))   Rows Removed by Filter: 233   actual time=7.0..325 ms
-- The planner asks public.crown_call_room of EVERY harbour in the world and only then whose it is, so one call costs 343 to 1,022 ms where the realm's own harbours would cost a fraction. Lit, the read runs once for every idle cargo ship
-- in public.cargo_rebase_to (about 64 ships in the first five minutes) and ten times a minute in public.tick_cargo_ships, through public.cargo_homes: 2.4 to 9.7 s a minute for the ten great powers, and 22 to 65 s in the first lit
-- minutes, for a job that must fit its minute (the fail line is 55 s).
--
-- THE FIX, ONE HUNK. The realm test moves into a select of its own with `offset 0`, which keeps the planner from folding it into its parent, so it runs FIRST and public.crown_call_room is asked of the realm's harbours only.
-- The same harbours, the same room test, the same course test, the same order, the same limit and the same fallback to the capital: the answer is the same array. Measured on prod, ESP, three runs each: before 343 / 411 / 1,022 ms,
-- after 75 / 84 / 152 ms, and the two arrays equal.
--
-- DARK. `convoy_rich_enabled` is false, so only the off arm (the capital) runs, and this file does not touch it. No table, knob, switch, job or other function moves. The fallback `coalesce(.., array[realm_capital])` and the off arm are
-- byte for byte what they were: the hunk is the FROM and the WHERE of the one select, nothing else.
--
-- THE RE-CUT (one hunk of the live body, read on prod at head 0335; it occurs once and reverses to its pre-image; this supersedes the same lines of 0324's public.cargo_origins).
-- NOT TOUCHED: public.crown_call_room, public.port_nation, public.cargo_homes, public.cargo_rebase_to, public.tick_cargo_ships, every switch and knob. THE SAME PATTERN (a `cross join lateral (select public.crown_call_room(h.id)..`
-- with the realm test in the same WHERE) stands in public.crown_call and public.crown_donors: named in the dev-log, not changed here, because each is its own slice with its own proof.
--
-- WHAT NO RESULT CAN SEE. The fence changes the plan and not one row, so "remove the fence" cannot make any answer differ. Two things pin it: the self-assert reads the live body and requires the fence in it, and the cost evidence
-- of the dev-log (docs/dev-log/2026-11-07-origins-fence.md). Proof 43 also counts the calls public.crown_call_room receives and requires none for a harbour outside the realm.
--
-- SELF-ASSERT: the hunk once and reversing; no other function, knob or ACL moved; the fence stands in the body; then a probe realm of its own rolled-back harbours (a richer harbour of another realm and a sea place beside it) with
-- the switch set inside the transaction: the new read answers what the OLD body answers, and the OLD body is the live pre-image itself, renamed into pg_temp, never retyped. Scenes: off; lit with a limit above the roster; lit
-- with a limit that cuts a tie; lit with no room anywhere. Planted rows only, rolled back, and the check that none is left. THE LIVE PATHS ARE PROVED IN CI: proof 43, scripts/db/proofs/43_a_realm_reads_its_own.sql. Mutation
-- controls: scripts/ops/harness/origins-fence/mutations-0336.mjs (local).
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Self-assert fails above 45 s. The OLD reference is read four times lit; each costs what the problem costs (about 0.3 to 1 s on prod).
-- ROLLBACK (forward, a NEW migration, owner only): swap this file's hunk (new for old). No data, knob or switch moved, so there is nothing else to undo.
-- VERSION: 0336 - prod head 0335 (read 2026-11-07).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0          timestamptz := clock_timestamp();
  v_def         text;
  v_pre         text;
  v_old         text;
  v_n           int;
  v_fn_before   text;
  v_cfg_before  text;
  v_meta_before text;
  v_nat         uuid;
  v_nat2        uuid;
  v_all         jsonb;
  v_res         jsonb := '{}'::jsonb;
  v_x           jsonb;
  s             record;
  hk            record;
  c_fn   constant text := 'public.cargo_origins(uuid)';
  c_head constant text := 'CREATE OR REPLACE FUNCTION public.cargo_origins(p_nation uuid)';
  -- A donor's room is 10 % of what stands above 50,000 (reserve 0): ducats = 50,000 + 10 x room. QYB sits at room 1, QYG 9 d. over the floor and so at room 0, QYF is the richest of the realm.
  c_base constant jsonb := '{"QYA": 5050000, "QYB": 50010, "QYC": 9050000, "QYD": 9050000, "QYE": 3050000, "QYF": 20050000, "QYG": 50009, "QYS": 25050000, "QYZ": 50050000}'::jsonb;
  c_zero constant jsonb := '{"QYA": 0, "QYB": 0, "QYC": 0, "QYD": 0, "QYE": 0, "QYF": 0, "QYG": 0, "QYS": 0, "QYZ": 0}'::jsonb;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure(c_fn) is null then
    raise exception '0336 refuses: public.cargo_origins is not in this world (0324 is not)';
  end if;
  v_pre := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  if position('offset 0) h' in v_pre) > 0 then
    raise exception '0336 refuses: the realm is already fenced in this world';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_fn::regprocedure::oid;
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  select md5(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''))
    into v_meta_before
    from pg_proc p where p.oid = c_fn::regprocedure::oid;

  -- ── 1. THE RE-CUT: one hunk of the live body ──
  create temp table hunks_0336 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0336 values
  ('public.cargo_origins(uuid)', 1,
$h$                                       from public.ports h
                                      cross join lateral (select public.crown_call_room(h.id) as room) x
                                      where h.kind = 'HARBOUR' and public.port_nation(h.id) = p_nation and x.room > 0
                                        and exists (select 1 from public.npc_courses c where c.from_port = h.id or c.to_port = h.id)
$h$,
$h$                                       from (select p.id, p.code from public.ports p
                                              -- 0336: the realm is chosen FIRST. offset 0 keeps the planner from folding this select into its parent, which asked public.crown_call_room of every harbour in the world before it asked whose the harbour was.
                                              where p.kind = 'HARBOUR' and public.port_nation(p.id) = p_nation offset 0) h
                                      cross join lateral (select public.crown_call_room(h.id) as room) x
                                      where x.room > 0
                                        and exists (select 1 from public.npc_courses c where c.from_port = h.id or c.to_port = h.id)
$h$);

  v_def := v_pre;
  for hk in select * from hunks_0336 h where h.fn = c_fn order by h.ord loop
    v_n := (length(v_def) - length(replace(v_def, hk.old, ''))) / length(hk.old);
    if v_n <> 1 then
      raise exception '0336 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', hk.ord, hk.fn, v_n;
    end if;
    v_def := replace(v_def, hk.old, hk.new);
  end loop;
  execute v_def;
  v_def := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  for hk in select * from hunks_0336 h where h.fn = c_fn order by h.ord desc loop
    v_n := (length(v_def) - length(replace(v_def, hk.new, ''))) / length(hk.new);
    if v_n <> 1 then
      raise exception '0336 self-assert FAIL: hunk % of % is not in the new body once', hk.ord, hk.fn;
    end if;
    v_def := replace(v_def, hk.new, hk.old);
  end loop;
  if v_def <> v_pre then
    raise exception '0336 self-assert FAIL: % does not reverse to its pre-image', c_fn;
  end if;

  -- ── 2. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_fn::regprocedure::oid) <> v_fn_before then
    raise exception '0336 self-assert FAIL: another function moved';
  end if;
  if (select md5(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''))
        from pg_proc p where p.oid = c_fn::regprocedure::oid) <> v_meta_before then
    raise exception '0336 self-assert FAIL: the ACL, volatility, definer or config of public.cargo_origins moved';
  end if;
  if (select p.provolatile from pg_proc p where p.oid = c_fn::regprocedure::oid) <> 's' then
    raise exception '0336 self-assert FAIL: public.cargo_origins is not stable';
  end if;
  if position('offset 0) h' in replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '')) = 0 then
    raise exception '0336 self-assert FAIL: the realm test does not stand ahead of public.crown_call_room';
  end if;

  -- ── 3. THE SELF-ASSERT: a probe realm, every row rolled back. The OLD body is the live pre-image, renamed: the reference is never retyped. ──
  v_old := replace(v_pre, c_head, 'CREATE OR REPLACE FUNCTION pg_temp.cargo_origins_pre_0336(p_nation uuid)');
  if v_old = v_pre or (length(v_pre) - length(replace(v_pre, c_head, ''))) <> length(c_head) then
    raise exception '0336 self-assert FAIL: the pre-image does not open as this file read it';
  end if;
  execute v_old;
  execute $f$
create function pg_temp.scene_0336(p_nat uuid, p_lit boolean, p_ports int, p_purses jsonb)
returns jsonb
language plpgsql
as $b$
begin
  update public.world_config set value = to_jsonb(p_lit) where key = 'convoy_rich_enabled';
  update public.world_config set value = to_jsonb(p_ports) where key = 'convoy_rich_ports';
  update public.port_treasury t set ducats = (p_purses ->> p.code)::bigint from public.ports p where p.id = t.port_id and p_purses ? p.code;
  return jsonb_build_object(
    'lit', public.rich_cities_on(),
    'rooms', (select jsonb_object_agg(p.code, public.crown_call_room(p.id)) from public.ports p where p.code like 'QY_'),
    'new', (select to_jsonb(array_agg(p.code order by o.n)) from unnest(public.cargo_origins(p_nat)) with ordinality o(id, n) join public.ports p on p.id = o.id),
    'old', (select to_jsonb(array_agg(p.code order by o.n)) from unnest(pg_temp.cargo_origins_pre_0336(p_nat)) with ordinality o(id, n) join public.ports p on p.id = o.id));
end
$b$
  $f$;

  begin
    update public.world_config set value = to_jsonb(0.10) where key = 'crown_call_share' and value is distinct from to_jsonb(0.10);
    update public.world_config set value = to_jsonb(20) where key = 'crown_call_cover' and value is distinct from to_jsonb(20);
    update public.world_config set value = to_jsonb(50000) where key = 'treasury_reserve_floor' and value is distinct from to_jsonb(50000);
    update public.world_config set value = 'true'::jsonb where key = 'convoys_enabled' and value is distinct from 'true'::jsonb;   -- the switch under test is the other one, set by each scene
    insert into public.nations (code, name, flag_char, capital_port_code) values ('QX6', 'Probe 0336', 'Z', 'QYA'), ('QX7', 'Probe 0336 B', 'Y', 'QYZ');
    insert into public.great_powers (nation_id) select n.id from public.nations n where n.code in ('QX6', 'QX7');
    select n.id into v_nat from public.nations n where n.code = 'QX6';
    select n.id into v_nat2 from public.nations n where n.code = 'QX7';
    insert into public.ports (code, name, country, lat, lon, sea_id, region_id, culture, size_tier, max_draft, kind, approach)
    select x.code, 'Probe ' || x.code, t.country, t.lat, t.lon, t.sea_id, t.region_id, t.culture, t.size_tier, t.max_draft, x.kind, x.approach
      from (values ('QYA', 'HARBOUR', null), ('QYB', 'HARBOUR', null), ('QYC', 'HARBOUR', null), ('QYD', 'HARBOUR', null), ('QYE', 'HARBOUR', null), ('QYF', 'HARBOUR', null), ('QYG', 'HARBOUR', null),
                   ('QYZ', 'HARBOUR', null), ('QYS', 'SEA_PLACE', 'a probe')) x(code, kind, approach)
     cross join (select * from public.ports where kind = 'HARBOUR' order by code limit 1) t;
    -- QYA..QYG, and the sea place QYS, fly the probe flag; QYZ, the richest of all, flies the other
    insert into public.port_allegiance (port_id, nation_id) select p.id, case when p.code = 'QYZ' then v_nat2 else v_nat end from public.ports p where p.code like 'QY_';
    insert into public.port_treasury (port_id, ducats, reserve) select p.id, 0, 0 from public.ports p where p.code like 'QY_';
    -- Courses: QYB is only a start, QYE only an end, QYC both, QYD an end, QYA an end. QYF has none. QYZ is another realm's, QYS a sea place's.
    insert into public.npc_courses (from_port, to_port, course, nm)
    select a.id, b.id, '[[0, 0], [1, 1]]'::jsonb, 1
      from (values ('QYB', 'QYE'), ('QYC', 'QYD'), ('QYG', 'QYA'), ('QYZ', 'QYC'), ('QYS', 'QYG')) v(f, t)
      join public.ports a on a.code = v.f join public.ports b on b.code = v.t;

    for s in select * from (values
      ('dark', false, 9, c_base),   -- switch off: the capital, whatever the purses say
      ('all',  true,  9, c_base),   -- a limit above the roster: room > 0, a course, this realm, a harbour; a tie by code
      ('cut3', true,  3, c_base),   -- the limit cuts after the capital
      ('cut1', true,  1, c_base),   -- the limit cuts a tie: the lower code
      ('none', true,  3, c_zero)    -- no room anywhere: the capital
    ) v(name, lit, ports, purses) loop
      begin
        raise exception using errcode = 'ZX336', message = pg_temp.scene_0336(v_nat, s.lit, s.ports, s.purses)::text;
      exception when sqlstate 'ZX336' then v_res := v_res || jsonb_build_object(s.name, sqlerrm::jsonb); end;
    end loop;
    raise exception using errcode = 'ZX336', message = v_res::text;
  exception when sqlstate 'ZX336' then
    v_all := sqlerrm::jsonb;
  end;
  drop function pg_temp.scene_0336(uuid, boolean, int, jsonb);
  drop function pg_temp.cargo_origins_pre_0336(uuid);

  if (v_all -> 'all' -> 'rooms') is distinct from '{"QYA": 500000, "QYB": 1, "QYC": 900000, "QYD": 900000, "QYE": 300000, "QYF": 2000000, "QYG": 0, "QYS": 2500000, "QYZ": 5000000}'::jsonb
     or (v_all -> 'none' -> 'rooms') is distinct from '{"QYA": 0, "QYB": 0, "QYC": 0, "QYD": 0, "QYE": 0, "QYF": 0, "QYG": 0, "QYS": 0, "QYZ": 0}'::jsonb then
    raise exception '0336 self-assert FAIL: the probe purses are not the rooms the scenes were built on: %', v_all;
  end if;
  for s in select * from (values
    ('dark', false, '["QYA"]'::jsonb),
    ('all',  true,  '["QYC", "QYD", "QYA", "QYE", "QYB"]'::jsonb),
    ('cut3', true,  '["QYC", "QYD", "QYA"]'::jsonb),
    ('cut1', true,  '["QYC"]'::jsonb),
    ('none', true,  '["QYA"]'::jsonb)
  ) v(name, lit, want) loop
    v_x := v_all -> s.name;
    if v_x is null or (v_x ->> 'lit')::boolean is distinct from s.lit then
      raise exception '0336 self-assert FAIL: scene % did not run with the switch it names: %', s.name, v_x;
    end if;
    if v_x -> 'old' is distinct from s.want then
      raise exception '0336 self-assert FAIL: scene %: the OLD body does not answer what the scene was built to ask, so the scene proves nothing: %', s.name, v_x;
    end if;
    if v_x -> 'new' is distinct from v_x -> 'old' then
      raise exception '0336 self-assert FAIL: scene %: the new read answers differently from the OLD body: %', s.name, v_x;
    end if;
  end loop;

  -- nothing of the probe survives, and nothing else moved
  if exists (select 1 from public.ports p where p.code like 'QY_') or exists (select 1 from public.nations n where n.code in ('QX6', 'QX7'))
     or exists (select 1 from public.npc_courses c join public.ports p on p.id in (c.from_port, c.to_port) where p.code like 'QY_') then
    raise exception '0336 self-assert FAIL: the probe left rows behind';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0336 self-assert FAIL: a world_config row moved';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0336 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0336 self-assert ok: A REALM READS ITS OWN HARBOURS, dark behind convoy_rich_enabled. % hunk once and reversing; no other function, knob or ACL moved; the fence stands. Probe realm, % scenes, the new read equal to the OLD body in each: off, a limit above the roster, a limit that cuts a tie, no room anywhere. % ms.',
    (select count(*) from hunks_0336), (select count(*) from jsonb_object_keys(v_all)), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0336;
end
$m$;
