-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0358 — THE YARD PLANS THE BUILD: world.yard_sources names every good a hull takes, its parts' goods too, with the count, the weight and the seller's price now. No table, no knob, no switch, no job.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- WHY (docs/SECOND_SHIP.md, slice S1; owner rows 180, 305, 316). world.yard_sources (0349, never re-cut) names where the four hull goods of a Barca are sold and where her two parts are
-- made. It does not say what the parts are made of: a Suit of Sails takes flax, cordage and tar; an Anchor & Cable takes hemp, iron and tar. So the errand is seven goods, three of them
-- named nowhere on the sheet, and the sheet has no price and no weight to add up. A new company cannot tell whether it can pay for a second ship or carry her materials.
-- WHAT. world.yard_sources RE-CUT (3 hunks on its live body). Every key it served is served as it was (asserted against a copy of the body before this file); these are added:
--   * goods[]: qty (the recipe's count), bulk (the good's weight a unit, public.goods.bulk), ask (what the named seller asks for one now).
--   * items[]: inputs: [{code, good, qty, bulk, port, name, miles, ask}], one row per public.item_recipes row of the part. code and good are the good's code and name; qty is the
--     recipe's count times the number of that part the hull takes; port, name and miles are the nearest seller of the good, found as a hull good's seller is found (0349: the roster's
--     one reading, public.port_offered_goods, and not public.culture_refuses; fewest sailed miles of public.sea_reaches, then the name); ask is that seller's.
--   * ask is world.price(port, good).ask, the one price authority (STABLE; what world.quote starts from), asked once a good. It is the price of one unit before the walk up the shelves a
--     real buy makes (world.quote), so a sum of qty x ask is an estimate, a little under what the buys cost. null where no harbour sells the good, or the seller has no market row.
--   The `sold` list now holds the goods of the hull AND of her parts (one row a good: a good in both is found once), and keeps the seller's port id for the price.
-- NOT TOUCHED: every other function (asserted byte for byte), every table, knob, switch and job; the reader's volatility (STABLE), definer, search_path, owner and ACL (authenticated only).
-- ALTERS NO RULE OF PLAY: a read gains keys. cmd.do_build, cmd.do_make, cmd.do_store and cmd.do_buy are not edited.
-- THE COST. One world.price a good of the hull and her parts (a Barca: seven), and the roster asked for those goods instead of the hull's own (a Barca: seven instead of four). 89 of the
-- 103 hulls have no part and ask only the price of their hull goods. Measured in docs/dev-log/2026-11-12-yard-plan.md; printed by this file's notices.
-- ROLLBACK (forward, a NEW migration, owner only): reverse the 3 hunks (each OLD text is here verbatim). The client reads the new keys as optional.
-- SELF-ASSERT: the catalog, then old against new on a pg_temp copy of the body before this file, rolled back. TIME-BOUNDED: the old-against-new walk over hulls and yards stops at
--   c_walk_budget of wall clock once its MINIMUM is done (every hull with a part, at Lisbon's yard); the proof (scripts/db/proofs/61_the_yard_plans_the_build.sql) walks every hull at every yard.
-- BUDGET: ONE DO block, statement_timeout 60 s, lock_timeout 5 s; it fails above 45 s. Each part's time is printed in a notice.
-- NEWS: this file posts its own UPDATE row, public.news_update('0358', 'Build: the whole list', '건조: 전체 목록') (0347's law, tests/news.lint.spec.ts).
-- VERSION: 0358 - prod head 0353 (2026-11-12); 0354 to 0357 are ahead of it in the deploy order and none touches the yard.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0          timestamptz := clock_timestamp();
  v_t           timestamptz;
  v_def         text;
  v_pre         text;
  v_meta        text;
  v_n           int;
  v_fn_before   text;
  v_cfg_before  text;
  v_rel_before  text;
  v_job_before  text;
  h             record;
  y             record;
  v_lived       boolean := false;
  v_lis         uuid;
  v_old         jsonb;
  v_new         jsonb;
  v_bad         text;
  v_pairs       int := 0;
  v_min_pairs   int := 0;
  v_all_pairs   int;
  v_asks        int := 0;
  v_inputs      int := 0;
  v_ms_old      numeric := 0;
  v_ms_new      numeric := 0;
  v_ms_hunks    numeric;
  v_ms_catalog  numeric;
  v_ms_walk     numeric;
  v_ms_min      numeric := 0;
  v_ms_control  numeric;
  v_flax        jsonb;
  c_walk_budget constant interval := interval '3 seconds';
  c_fn          constant text := 'world.yard_sources(uuid,text)';
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from unnest(array[c_fn, 'world.price(uuid,uuid)', 'public.port_offered_goods(uuid)', 'public.made_only_in(text,uuid)']) f where to_regprocedure(f) is null)
     or to_regclass('public.item_recipes') is null or to_regclass('public.hull_recipe_items') is null or to_regclass('public.port_goods') is null then
    raise exception '0358 refuses: 0349 (the reader), the price authority (world.price) or a recipe table is not in this world';
  end if;
  if to_regprocedure('public.news_update(text,text,text)') is null then
    raise exception '0358 refuses: 0347 (the world keeps its news) is not in this world';
  end if;
  if (select p.prosrc from pg_proc p where p.oid = c_fn::regprocedure) like '%0358%' then
    raise exception '0358 refuses: it has been applied once';
  end if;
  -- everything the reader will call must be a read: it is STABLE and is called inside read-only checks
  if exists (select 1 from unnest(array['world.price(uuid,uuid)', 'public.port_offered_goods(uuid)', 'public.made_only_in(text,uuid)']) f
              join pg_proc p on p.oid = f::regprocedure where p.provolatile not in ('s', 'i'))
     or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where ((n.nspname = 'public' and p.proname = 'culture_refuses') or (n.nspname = 'world' and p.proname in ('mid_price', 'price_terms', 'price_sides')))
                   and p.provolatile not in ('s', 'i')) then
    raise exception '0358 refuses: a function the reader calls is volatile';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  v_pre := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text into v_meta
    from pg_proc p where p.oid = c_fn::regprocedure;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_fn::regprocedure;
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c;
  select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname)) into v_rel_before
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p');
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_job_before;
  end if;

  -- ── 2. THE HUNKS: the goods of her parts are sourced too, with the seller's port and price; a good's row gains qty, bulk, ask; a part's row gains its inputs (each hunk once, and reversing) ──
  v_t := clock_timestamp();
  create temp table hunks_0358 (n int primary key, old text, new text) on commit drop;
  insert into hunks_0358 values
(1,
$h$  sold as materialized (
    select distinct on (g.id) g.id as good_id, d.code, d.name, d.miles
      from public.hull_recipe_goods hg
      join public.goods g on g.id = hg.good_id
      cross join dist d
      join lateral public.port_offered_goods(d.id) o on o.good_id = g.id
     where hg.class_code = p_class
       and not public.culture_refuses(d.culture, g.culture_mask)
     order by g.id, d.miles nulls last, d.name),
$h$,
$h$  -- 0358: THE WHOLE LIST. `need` is every good the hull takes: her own (hull_recipe_goods) and the goods her parts are made of (hull_recipe_items x item_recipes), one row a good.
  -- `near` is 0349's nearest seller, for each of them, keeping the seller's port id. `sold` adds what that seller asks for one now: world.price, the one price authority, once a good
  -- (null where the seller has no market row). Added keys only: goods[] gain qty, bulk, ask; items[] gain inputs [{code, good, qty, bulk, port, name, miles, ask}].
  need as materialized (
    select hg.good_id from public.hull_recipe_goods hg where hg.class_code = p_class
    union
    select ir.good_id from public.hull_recipe_items hi join public.item_recipes ir on ir.item_code = hi.item_code where hi.class_code = p_class),
  near as materialized (
    select distinct on (g.id) g.id as good_id, d.id as port_id, d.code, d.name, d.miles
      from need hg
      join public.goods g on g.id = hg.good_id
      cross join dist d
      join lateral public.port_offered_goods(d.id) o on o.good_id = g.id
     where not public.culture_refuses(d.culture, g.culture_mask)
     order by g.id, d.miles nulls last, d.name),
  sold as materialized (
    select n.good_id, n.port_id, n.code, n.name, n.miles,
           (select pr.ask from public.port_goods pg cross join lateral world.price(pg.port_id, pg.good_id) pr
             where pg.port_id = n.port_id and pg.good_id = n.good_id) as ask
      from near n),
$h$),
(2,
$h$      select jsonb_agg(jsonb_build_object('code', g.code, 'port', s.code, 'name', s.name, 'miles', round(s.miles)) order by g.code)
$h$,
$h$      select jsonb_agg(jsonb_build_object('code', g.code, 'port', s.code, 'name', s.name, 'miles', round(s.miles),
                                          'qty', hg.qty, 'bulk', g.bulk, 'ask', s.ask) order by g.code)
$h$),
(3,
$h$      select jsonb_agg(jsonb_build_object('code', k.code, 'port', m.code, 'name', m.name, 'miles', round(m.miles)) order by k.code)
$h$,
$h$      select jsonb_agg(jsonb_build_object('code', k.code, 'port', m.code, 'name', m.name, 'miles', round(m.miles),
                                          'inputs', coalesce((
                                            select jsonb_agg(jsonb_build_object('code', g.code, 'good', g.name, 'qty', ir.qty * hi.qty, 'bulk', g.bulk,
                                                                                'port', s.code, 'name', s.name, 'miles', round(s.miles), 'ask', s.ask) order by g.code)
                                              from public.item_recipes ir join public.goods g on g.id = ir.good_id
                                              left join sold s on s.good_id = g.id
                                             where ir.item_code = k.code), '[]'::jsonb)) order by k.code)
$h$);

  v_def := v_pre;
  for h in select * from hunks_0358 order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0358 self-assert FAIL: hunk % occurs % time(s), not once: the deployed body is not what this file was written against', h.n, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
  v_def := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  for h in select * from hunks_0358 order by n desc loop
    if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
      raise exception '0358 self-assert FAIL: new hunk % is not in the live body once', h.n;
    end if;
    v_def := replace(v_def, h.new, h.old);
  end loop;
  if v_def <> v_pre then
    raise exception '0358 self-assert FAIL: the reader does not reverse to its pre-image';
  end if;
  if (select count(*) from hunks_0358) <> 3 then
    raise exception '0358 self-assert FAIL: the hunks are not the 3 of the re-cut body';
  end if;
  v_ms_hunks := round(extract(epoch from clock_timestamp() - v_t) * 1000);

  -- ── 3. THE SELF-ASSERT: the catalog ──
  v_t := clock_timestamp();
  if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
        from pg_proc p where p.oid = c_fn::regprocedure) <> v_meta then
    raise exception '0358 self-assert FAIL: the reader changed its ACL, volatility, definer, config or owner';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = c_fn::regprocedure and p.provolatile = 's' and p.prosecdef)
     or not has_function_privilege('authenticated', c_fn, 'execute') or has_function_privilege('anon', c_fn, 'execute') then
    raise exception '0358 self-assert FAIL: the reader is not STABLE SECURITY DEFINER, executable by authenticated alone';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_fn::regprocedure) <> v_fn_before then
    raise exception '0358 self-assert FAIL: a function other than world.yard_sources moved';
  end if;
  -- ONE price authority, asked in one place; no price rule of its own
  v_def := (select p.prosrc from pg_proc p where p.oid = c_fn::regprocedure);
  if (length(v_def) - length(replace(v_def, 'world.price(', ''))) / length('world.price(') <> 1
     or v_def like '%mid_price%' or v_def like '%price_sides%' or v_def like '%world.quote%' or v_def like '%wc_num(%' then
    raise exception '0358 self-assert FAIL: the reader does not ask world.price in exactly one place, or carries a price rule of its own';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0358 self-assert FAIL: a world_config row moved: this file sets no knob';
  end if;
  if (select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname))
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p')) <> v_rel_before then
    raise exception '0358 self-assert FAIL: a table, view, sequence or index appeared or went: this file makes none';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_def;
    if v_def is distinct from v_job_before then
      raise exception '0358 self-assert FAIL: a cron job moved: this file schedules nothing';
    end if;
  end if;
  v_ms_catalog := round(extract(epoch from clock_timestamp() - v_t) * 1000);

  -- ── 4. THE SELF-ASSERT: old against new. A pg_temp copy of the body BEFORE this file answers beside the live one; the copy is rolled back. Reads only: no row is written. ──
  select id into v_lis from public.ports where code = 'LIS';
  if v_lis is null or not exists (select 1 from public.port_buildings b where b.port_id = v_lis and b.kind = 'building_yard') then
    raise exception '0358 self-assert FAIL: Lisbon keeps no build yard to probe';
  end if;
  begin
    execute replace(v_pre, 'FUNCTION world.yard_sources(', 'FUNCTION pg_temp.yard_sources_old_0358(');
    select count(*) into v_all_pairs from public.hull_recipes r cross join public.port_buildings b where b.kind = 'building_yard';

    -- (w) THE WALK, bounded by the clock: Lisbon's yard first and the hulls with a part first, then every other yard by its code. THE MINIMUM, done whatever the clock says: every
    -- hull with a part, at Lisbon. Past the minimum the walk stops at c_walk_budget. On each pair: the new answer less the new keys IS the old answer; a part's inputs are one row per
    -- item_recipes row, with the recipe's count times the part's; a good's qty and bulk are the recipe's and the good's. On the minimum also: every ask is world.price's.
    v_t := clock_timestamp();
    for y in
      select b.port_id, r.class_code, (b.port_id = v_lis and x.parts) as must
        from public.port_buildings b
        join public.ports p on p.id = b.port_id
       cross join public.hull_recipes r
       cross join lateral (select exists (select 1 from public.hull_recipe_items hi where hi.class_code = r.class_code) as parts) x
       where b.kind = 'building_yard'
       order by (b.port_id = v_lis) desc, x.parts desc, p.code, r.class_code
    loop
      exit when not y.must and clock_timestamp() - v_t > c_walk_budget;
      with t0 as materialized (select clock_timestamp() as c),
           o  as materialized (select pg_temp.yard_sources_old_0358(y.port_id, y.class_code) as b from t0),
           t1 as materialized (select clock_timestamp() as c, o.b from o),
           n  as materialized (select world.yard_sources(y.port_id, y.class_code) as b, t1.c, t1.b as ob from t1),
           t2 as materialized (select clock_timestamp() as c2, n.c as c1, n.b, n.ob from n)
      select t2.ob, t2.b, v_ms_old + extract(epoch from t2.c1 - t0.c) * 1000, v_ms_new + extract(epoch from t2.c2 - t2.c1) * 1000
        into v_old, v_new, v_ms_old, v_ms_new from t2, t0;
      v_pairs := v_pairs + 1;
      if y.must then v_min_pairs := v_min_pairs + 1; end if;
      if jsonb_build_object(
           'port_id', v_new -> 'port_id', 'class', v_new -> 'class',
           'goods', coalesce((select jsonb_agg(e.value - 'qty' - 'bulk' - 'ask' order by e.ord) from jsonb_array_elements(v_new -> 'goods') with ordinality e(value, ord)), '[]'::jsonb),
           'items', coalesce((select jsonb_agg(e.value - 'inputs' order by e.ord) from jsonb_array_elements(v_new -> 'items') with ordinality e(value, ord)), '[]'::jsonb))
         is distinct from v_old
         or (select count(*) from jsonb_object_keys(v_new)) <> 4 then
        raise exception '0358 self-assert FAIL: % at yard %: the new answer less its new keys is not the old answer. OLD % NEW %', y.class_code, y.port_id, v_old, v_new;
      end if;
      -- a good's row: the recipe's count, the good's weight
      select string_agg(e.value ->> 'code', ', ') into v_bad
        from jsonb_array_elements(v_new -> 'goods') e
        join public.goods g on g.code = e.value ->> 'code'
        left join public.hull_recipe_goods hg on hg.class_code = y.class_code and hg.good_id = g.id
       where (e.value ->> 'qty')::numeric is distinct from hg.qty or (e.value ->> 'bulk')::numeric is distinct from g.bulk
          or ((e.value ->> 'port') is null) <> ((e.value ->> 'ask') is null);
      if v_bad is not null then
        raise exception '0358 self-assert FAIL: % at yard %: the row of % does not carry the recipe''s count, the good''s weight, or an ask where (and only where) a seller is named', y.class_code, y.port_id, v_bad;
      end if;
      -- a part's inputs: one row per item_recipes row, the count times the part's, the seller the hull goods' rule names
      select string_agg(i.value ->> 'code', ', ') into v_bad
        from jsonb_array_elements(v_new -> 'items') i
        join public.hull_recipe_items hi on hi.class_code = y.class_code and hi.item_code = i.value ->> 'code'
       where jsonb_typeof(i.value -> 'inputs') is distinct from 'array'
          or jsonb_array_length(i.value -> 'inputs') <> (select count(*) from public.item_recipes ir where ir.item_code = hi.item_code)
          or exists (select 1 from jsonb_array_elements(i.value -> 'inputs') u
                       left join public.goods g on g.code = u.value ->> 'code'
                       left join public.item_recipes ir on ir.item_code = hi.item_code and ir.good_id = g.id
                      where ir.good_id is null or (u.value ->> 'qty')::numeric is distinct from ir.qty * hi.qty
                         or (u.value ->> 'bulk')::numeric is distinct from g.bulk or u.value ->> 'good' is distinct from g.name
                         or (select count(*) from jsonb_object_keys(u.value)) <> 8
                         or ((u.value ->> 'port') is null) <> ((u.value ->> 'ask') is null));
      if v_bad is not null then
        raise exception '0358 self-assert FAIL: % at yard %: the inputs of % are not one row per recipe row with its count, weight and name: %', y.class_code, y.port_id, v_bad, v_new -> 'items';
      end if;
      select count(*) into v_n from jsonb_array_elements(v_new -> 'items') i cross join jsonb_array_elements(i.value -> 'inputs') u;
      v_inputs := v_inputs + v_n;
      if y.must then
        -- every ask is the price authority's, for the seller the row names; and an input's seller is the one a hull good of the same code is given
        select count(*), string_agg(q.code || '@' || coalesce(q.port, '-'), ', ') filter (where q.ask is distinct from q.want) into v_n, v_bad
          from (select u.value ->> 'code' as code, u.value ->> 'port' as port, (u.value ->> 'ask')::numeric as ask,
                       (select pr.ask from public.ports p join public.goods g on g.code = u.value ->> 'code' cross join lateral world.price(p.id, g.id) pr where p.code = u.value ->> 'port') as want
                  from (select e.value from jsonb_array_elements(v_new -> 'goods') e
                        union all
                        select u2.value from jsonb_array_elements(v_new -> 'items') i cross join jsonb_array_elements(i.value -> 'inputs') u2) u
                 where u.value ->> 'port' is not null) q;
        if v_bad is not null then
          raise exception '0358 self-assert FAIL: % at Lisbon: the ask of % is not world.price''s', y.class_code, v_bad;
        end if;
        v_asks := v_asks + v_n;
        v_ms_min := round(extract(epoch from clock_timestamp() - v_t) * 1000);
        if exists (select 1 from jsonb_array_elements(v_new -> 'goods') e
                     join (select u.value from jsonb_array_elements(v_new -> 'items') i cross join jsonb_array_elements(i.value -> 'inputs') u) x on x.value ->> 'code' = e.value ->> 'code'
                    where (x.value ->> 'port', x.value ->> 'name', x.value ->> 'miles', x.value ->> 'ask') is distinct from (e.value ->> 'port', e.value ->> 'name', e.value ->> 'miles', e.value ->> 'ask')) then
          raise exception '0358 self-assert FAIL: % at Lisbon: a good that is both a hull good and a part''s input is given two sellers', y.class_code;
        end if;
      end if;
    end loop;
    v_ms_walk := round(extract(epoch from clock_timestamp() - v_t) * 1000);
    if v_min_pairs < 1 or v_min_pairs <> (select count(distinct hi.class_code) from public.hull_recipe_items hi join public.hull_recipes r on r.class_code = hi.class_code) or v_asks < 1 or v_inputs < 1 then
      raise exception '0358 self-assert FAIL: the walk did not do its minimum (every hull with a part, at Lisbon): % pair(s), % ask(s), % input row(s)', v_min_pairs, v_asks, v_inputs;
    end if;

    -- (c) THE POSITIVE CONTROL, at Lisbon: the Barca's sails name flax, sold nearest at Riga; an unknown class still serves empty lists
    v_t := clock_timestamp();
    v_new := world.yard_sources(v_lis, 'barca');
    select u.value into v_flax
      from jsonb_array_elements(v_new -> 'items') i cross join jsonb_array_elements(i.value -> 'inputs') u
     where i.value ->> 'code' = 'suit-of-sails' and u.value ->> 'code' = 'flax';
    if v_flax is null or v_flax ->> 'port' is distinct from 'RIG' or (v_flax ->> 'miles')::numeric <= 0 or (v_flax ->> 'ask')::numeric <= 0 or (v_flax ->> 'qty')::numeric <= 0 then
      raise exception '0358 self-assert FAIL: at Lisbon the Barca''s Suit of Sails does not name flax at Riga: % (her parts: %)', v_flax, v_new -> 'items';
    end if;
    if exists (select 1 from jsonb_array_elements(v_new -> 'goods') e where e.value ->> 'code' in ('flax', 'hemp', 'iron')) or jsonb_array_length(v_new -> 'goods') <> 4 then
      raise exception '0358 self-assert FAIL: a part''s good is listed among the Barca''s hull goods: %', v_new -> 'goods';
    end if;
    v_old := world.yard_sources(v_lis, '0358-no-such-class');
    if v_old -> 'goods' <> '[]'::jsonb or v_old -> 'items' <> '[]'::jsonb then
      raise exception '0358 self-assert FAIL: an unknown class served %', v_old;
    end if;
    v_ms_control := round(extract(epoch from clock_timestamp() - v_t) * 1000);

    raise exception using errcode = 'ZX358', message = 'PROBE_ROLLBACK_0358';
  exception when sqlstate 'ZX358' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0358 self-assert FAIL: the probe did not run to its end';
  end if;
  if to_regprocedure('pg_temp.yard_sources_old_0358(uuid,text)') is not null then
    raise exception '0358 self-assert FAIL: the copy of the pre-image outlived the probe';
  end if;
  if (select p.prosrc from pg_proc p where p.oid = c_fn::regprocedure) not like '%0358: THE WHOLE LIST%' then
    raise exception '0358 self-assert FAIL: the re-cut body did not outlive the probe''s rollback';
  end if;

  -- THIS FILE'S OWN UPDATE ROW (0347's news law, tests/news.lint.spec.ts), counted by its own key; outside the rolled-back probe
  perform public.news_update('0358', 'Build: the whole list', '건조: 전체 목록');
  if (select count(*) from public.world_news w where w.key = 'update:0358') <> 1 then
    raise exception '0358 self-assert FAIL: this file''s UPDATE row is not one row';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0358 self-assert FAIL: the file ran % s, over its 45 s budget', round(extract(epoch from clock_timestamp() - v_t0));
  end if;
  raise notice '0358 timings: hunks % ms; catalog % ms; walk % ms (% of % hull x yard pair(s): the old body % ms, the new % ms; the minimum % pair(s) in % ms, every hull with a part at Lisbon; stops at % past it); control % ms',
    v_ms_hunks, v_ms_catalog, v_ms_walk, v_pairs, v_all_pairs, round(v_ms_old), round(v_ms_new), v_min_pairs, v_ms_min, c_walk_budget, v_ms_control;
  raise notice '0358 control: at Lisbon the Barca''s Suit of Sails names %', v_flax;
  raise notice '0358 self-assert ok: THE YARD PLANS THE BUILD. world.yard_sources serves every key it served, unchanged (% hull x yard pair(s) against a copy of the body before this file), and adds qty, bulk and ask to a good''s row and inputs to a part''s row: % input row(s), one per item_recipes row; % ask(s) are world.price''s. It is still STABLE, definer-owned, executable by authenticated alone; its 3 hunks each occurred once and reverse to the pre-image; no other function, knob, table or job moved; its UPDATE row is one row. % ms.',
    v_pairs, v_inputs, v_asks, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
