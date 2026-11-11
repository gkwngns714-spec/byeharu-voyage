-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0349 — A YARD SAYS WHERE TO GET IT: each material of a hull, and the nearest city that sells (or makes) it
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Owner rows 180 and 305 (build ships). The remaster's playtest, 2026-11-11: Port > Build lists 50+ hulls, the cheapest (Barca)
-- needs six materials, and nothing says where Timber (or any of them) is sold, so no player can plan a second ship.
--
-- ONE NEW READER, nothing else moves:
--   world.yard_sources(p_port uuid, p_class text) -> jsonb, STABLE, SECURITY DEFINER, read-only, no volatile call.
--     { port_id, class,
--       goods: [{code, port, name, miles}]   one row per hull_recipe_goods row of the class: the NEAREST harbour where
--                                            cmd.do_buy would sell the good — the two gates it applies, called, not copied:
--                                            public.port_offered_goods (the roster's one reading, 0136) and
--                                            not public.culture_refuses(port culture, good mask);
--       items: [{code, port, name, miles}] } one row per hull_recipe_items row: the NEAREST harbour whose workstation is
--                                            good enough (tier >= item_kinds.ws_tier) and where public.made_only_in is null —
--                                            the two gates cmd.do_make applies (the company's skill gate is the company's,
--                                            not the city's, and the workshop page says it).
--     `miles` is the sailed distance from p_port in public.sea_reaches (the table world.reach serves), rounded; 0 for p_port
--     itself; null where the table has no figure. Nearest = fewest miles (nulls last), then the name. port/name/miles are
--     null where no harbour qualifies (0072's self-assert keeps every hull material sold, and every fitting made, somewhere).
--   Grants like its sibling readers (0305): revoke from public/anon/authenticated, then execute to authenticated.
--   No table, column, knob, cron job or other function is touched (asserted).
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Work: one function, one
--   ACL, catalog reads, one probe call per hull class at one yard. Self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): drop function world.yard_sources(uuid, text); the yard sheet then shows the
--   materials without a seller line.
-- VERSION: 0349 - prod head 0346 (2026-11-11); 0347 and 0348 are ahead of it in the deploy order.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_fn_before  text;
  v_fn_after   text;
  v_cfg_before text;
  v_t0   timestamptz := clock_timestamp();
  v_port uuid;
  v_r    jsonb;
  v_bad  int;
  v_n    int := 0;
  v_ms   numeric;
  h      record;
  x      jsonb;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.port_offered_goods(uuid)') is null or to_regprocedure('public.made_only_in(text, uuid)') is null
     or not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'culture_refuses')
     or to_regclass('public.sea_reaches') is null or to_regclass('public.hull_recipe_goods') is null then
    raise exception '0349 refuses: a function or table it reads is not in this world';
  end if;
  if to_regprocedure('world.yard_sources(uuid, text)') is not null then
    raise exception '0349 refuses: it has been applied once';
  end if;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c;

  -- ── 1. THE READER ──
  execute $f$
create function world.yard_sources(p_port uuid, p_class text)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0349: where each material of a hull is had nearest to this yard. The gates are cmd.do_buy's and cmd.do_make's, called.
  with dist as materialized (
    select p.id, p.code, p.name, p.culture,
           case when p.id = p_port then 0::numeric else (sr.reaches ->> p.code)::numeric end as miles
      from public.ports p
      left join public.sea_reaches sr on sr.port_id = p_port
     where p.kind = 'HARBOUR'),
  sold as materialized (
    select distinct on (g.id) g.id as good_id, d.code, d.name, d.miles
      from public.hull_recipe_goods hg
      join public.goods g on g.id = hg.good_id
      cross join dist d
      join lateral public.port_offered_goods(d.id) o on o.good_id = g.id
     where hg.class_code = p_class
       and not public.culture_refuses(d.culture, g.culture_mask)
     order by g.id, d.miles nulls last, d.name),
  can as materialized (
    select k.code as item, d.id, d.code, d.name, d.miles
      from public.hull_recipe_items hi
      join public.item_kinds k on k.code = hi.item_code
      join public.port_buildings b on b.kind = 'workstation' and b.tier >= k.ws_tier
      join dist d on d.id = b.port_id
     where hi.class_code = p_class),
  made as materialized (
    select distinct on (c.item) c.item, c.code, c.name, c.miles
      from can c
     where public.made_only_in(c.item, c.id) is null
     order by c.item, c.miles nulls last, c.name)
  select jsonb_build_object(
    'port_id', p_port,
    'class', p_class,
    'goods', coalesce((
      select jsonb_agg(jsonb_build_object('code', g.code, 'port', s.code, 'name', s.name, 'miles', round(s.miles)) order by g.code)
        from public.hull_recipe_goods hg join public.goods g on g.id = hg.good_id
        left join sold s on s.good_id = g.id
       where hg.class_code = p_class), '[]'::jsonb),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object('code', k.code, 'port', m.code, 'name', m.name, 'miles', round(m.miles)) order by k.code)
        from public.hull_recipe_items hi join public.item_kinds k on k.code = hi.item_code
        left join made m on m.item = k.code
       where hi.class_code = p_class), '[]'::jsonb))
$body$
  $f$;
  revoke all on function world.yard_sources(uuid, text) from public, anon, authenticated;
  grant execute on function world.yard_sources(uuid, text) to authenticated;

  -- ── 2. SELF-ASSERT ──
  if not exists (select 1 from pg_proc p where p.oid = 'world.yard_sources(uuid, text)'::regprocedure and p.provolatile = 's' and p.prosecdef) then
    raise exception '0349 self-assert FAIL: the reader is not STABLE SECURITY DEFINER';
  end if;
  if not has_function_privilege('authenticated', 'world.yard_sources(uuid, text)', 'execute')
     or has_function_privilege('anon', 'world.yard_sources(uuid, text)', 'execute') then
    raise exception '0349 self-assert FAIL: the reader is not granted to authenticated alone';
  end if;

  -- (a) at Lisbon's yard, every hull class: one row per recipe line, and every named source passes the very gates the verbs apply
  select id into v_port from public.ports where code = 'LIS';
  for h in select r.class_code from public.hull_recipes r order by r.class_code loop
    v_r := world.yard_sources(v_port, h.class_code);
    v_n := v_n + 1;
    if jsonb_array_length(v_r -> 'goods') <> (select count(*) from public.hull_recipe_goods g where g.class_code = h.class_code)
       or jsonb_array_length(v_r -> 'items') <> (select count(*) from public.hull_recipe_items i where i.class_code = h.class_code) then
      raise exception '0349 self-assert FAIL: % served % / % rows against its recipe', h.class_code, v_r -> 'goods', v_r -> 'items';
    end if;
    for x in select value from jsonb_array_elements(v_r -> 'goods') loop
      if x ->> 'port' is null then
        raise exception '0349 self-assert FAIL: % names no seller of %', h.class_code, x ->> 'code';
      end if;
      select count(*) into v_bad from public.ports p join public.goods g on g.code = x ->> 'code'
       where p.code = x ->> 'port' and public.port_offers(p.id, g.id) and not public.culture_refuses(p.culture, g.culture_mask);
      if v_bad <> 1 then
        raise exception '0349 self-assert FAIL: % names % as a seller of %, and it does not sell it', h.class_code, x ->> 'port', x ->> 'code';
      end if;
      -- nearest: no harbour that sells it lies closer
      if exists (select 1 from public.ports p join public.goods g on g.code = x ->> 'code'
                   left join public.sea_reaches sr on sr.port_id = v_port
                  where p.kind = 'HARBOUR' and public.port_offers(p.id, g.id) and not public.culture_refuses(p.culture, g.culture_mask)
                    and round(case when p.id = v_port then 0 else (sr.reaches ->> p.code)::numeric end) < (x ->> 'miles')::numeric) then
        raise exception '0349 self-assert FAIL: % names % for %, and a nearer harbour sells it', h.class_code, x ->> 'port', x ->> 'code';
      end if;
    end loop;
    for x in select value from jsonb_array_elements(v_r -> 'items') loop
      -- no maker only for a hull no yard lays down while a part of it waits (public.hull_unmade, 0184: the famous gear)
      if x ->> 'port' is null then
        if public.hull_unmade(h.class_code) is null then
          raise exception '0349 self-assert FAIL: % names no maker of %', h.class_code, x ->> 'code';
        end if;
        continue;
      end if;
      select count(*) into v_bad from public.ports p join public.item_kinds k on k.code = x ->> 'code'
        join public.port_buildings b on b.port_id = p.id and b.kind = 'workstation' and b.tier >= k.ws_tier
       where p.code = x ->> 'port' and public.made_only_in(k.code, p.id) is null;
      if v_bad <> 1 then
        raise exception '0349 self-assert FAIL: % names % as a maker of %, and it cannot make it', h.class_code, x ->> 'port', x ->> 'code';
      end if;
    end loop;
  end loop;
  if v_n = 0 then
    raise exception '0349 self-assert FAIL: no hull recipe to probe';
  end if;
  -- (b) a good sold at the yard itself is served there, at 0 miles
  if exists (select 1 from public.hull_recipe_goods hg join public.goods g on g.id = hg.good_id
              where public.port_offers(v_port, g.id) and not public.culture_refuses((select culture from public.ports where id = v_port), g.culture_mask)
                and exists (select 1 from jsonb_array_elements(world.yard_sources(v_port, hg.class_code) -> 'goods') e
                             where e.value ->> 'code' = g.code and (e.value ->> 'port' <> 'LIS' or (e.value ->> 'miles')::numeric <> 0))) then
    raise exception '0349 self-assert FAIL: a good Lisbon sells is not served at Lisbon, 0 miles';
  end if;
  -- (c) an unknown class serves empty lists
  v_r := world.yard_sources(v_port, '0349-no-such-class');
  if v_r -> 'goods' <> '[]'::jsonb or v_r -> 'items' <> '[]'::jsonb then
    raise exception '0349 self-assert FAIL: an unknown class served %', v_r;
  end if;
  -- nothing else moved
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_after
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> 'world.yard_sources(uuid, text)'::regprocedure;
  if v_fn_after <> v_fn_before then
    raise exception '0349 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0349 self-assert FAIL: a world_config row moved';
  end if;
  v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0349 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0349 self-assert ok: world.yard_sources is STABLE, definer-owned, executable by authenticated alone; at Lisbon, % hull class(es) each serve one row per recipe line, every seller passes do_buy''s roster and culture gates and none nearer does, every maker passes do_make''s workstation and made-only-in gates; a good sold at the yard is served there at 0 miles; an unknown class serves empty lists; nothing else moved. Printed, never asserted: % ms.', v_n, v_ms;
end
$m$;
