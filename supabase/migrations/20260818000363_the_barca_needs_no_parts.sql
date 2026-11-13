-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0363 — THE BARCA NEEDS NO PARTS: the first hull a house builds is laid down from her four hull goods alone. Two recipe rows go and one note is reworded. No function, no knob, no switch, no job.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- WHY (docs/SECOND_SHIP.md, slice S2; owner rows 180, 305, 316; touches owner row 58). A second Barca asked a new company for seven goods from six foreign ports: timber, tar, cordage and
-- nails for the hull, and flax (nearest Riga, 2,101 nm, past a single leg of a new company), hemp (Naples) and iron for her two parts, a Suit of Sails and an Anchor & Cable. 0358 put all
-- seven on the yard's sheet. This file makes the errand four goods from four ports (Funchal, La Rochelle, Portsmouth, Bergen): the Barca's two public.hull_recipe_items rows go.
-- WHAT.
--   * public.hull_recipe_items: the two rows of class 'barca' are deleted (suit-of-sails 1, anchor-and-cable 1). Exactly those two, asserted before and counted after.
--   * public.hull_recipes: the Barca's note no longer says "Two fittings" (it is served by world.building_yard and printed on the sheet). data/hulls.json carries the same rows (the world guard).
--   Nothing else. cmd.do_build, world.building_yard and world.yard_sources read the recipe tables and are not edited: with no row, do_build asks for no part and takes none.
-- ROW 58 (the owner: "Building ships will require not only some of the trading goods, but some items"). Parts stay a rule of the yard: the Caravela latina (4 kinds of part), the Nau (5) and
--   the 11 famous ships keep every row (asserted), and every part is still made at a workshop (public.item_recipes untouched) and still FITTED to a ship's racks (cmd.do_fit untouched). Only
--   the hull a house builds FIRST asks for none, as 89 of the 103 hulls already do. This is the design's default and the owner may reverse it (the rollback below).
-- WHO ALREADY HOLDS SOMETHING LOSES NOTHING. This file writes to no player's row: not public.player_items, not public.player_storage, not a hold, not a purse. A Suit of Sails or an Anchor &
--   Cable a company keeps stays hers: it is not taken by a Barca's build any more, it still goes into a Caravela latina or a Nau, and it can still be fitted to a ship. Flax, hemp and iron
--   she bought stay in her hold or her storage, sell at any market as before, and still make the same parts. Hull goods in storage are counted by the build as they were.
-- ALTERS A RULE OF PLAY: what a Barca costs to build (the labour is unchanged: public.yard_labour). It gets its own measured window (docs/dev-log/2026-11-13-second-ship.md): before and
--   after, the first second ship of a new company by the real commands, in miles, real minutes and coin (scripts/db/proofs/65_a_second_ship_within_reach.sql).
-- MERCHANTS are not touched: they do not use the yard (public.commission_ship directly).
-- ROLLBACK (forward, a NEW migration, owner only; a draft is scripts/ops/harness/second-ship/rollback-0363.sql): insert the two rows again and put the note back. Both texts are in this
--   file, and the self-assert plays that rollback inside its probe: with the rows back, the yard refuses a Barca for her parts (E_NO_FITTINGS) as it did.
-- SELF-ASSERT: the pre-image is exactly what this file was written against; then, on a probe of this file's own rows, rolled back: a house with the four goods stored and no part builds a
--   Barca; a house that keeps both parts builds one and keeps both parts; the Caravela latina still refuses for her parts and counts the ones the house keeps; with the two rows put back
--   the Barca refuses for her parts again. The catalog: no function, knob, table or job moved; every other recipe row is as it was.
-- BUDGET: ONE DO block, statement_timeout 60 s, lock_timeout 5 s; it fails above 20 s. Each part's time is printed in a notice.
-- NEWS: this file posts its own UPDATE row, public.news_update('0363', 'Barca: no parts needed', '바르카: 부품 불필요') (0347's law, tests/news.lint.spec.ts).
-- VERSION: 0363 - stacked on 0358 (the yard plans the build). 0355 to 0362 are held by other open branches; none touches a recipe table (checked against origin/captain-skills,
--   origin/level-up, origin/live-rounds and origin/auto-route on 2026-11-13).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0          timestamptz := clock_timestamp();
  v_t           timestamptz;
  v_n           int;
  v_txt         text;
  v_fn_before   text;
  v_cfg_before  text;
  v_rel_before  text;
  v_job_before  text;
  v_items_rest  text;   -- every hull_recipe_items row that is not the Barca's
  v_items_all   text;   -- every hull_recipe_items row, the Barca's two with them (what the rollback must give back)
  v_goods_all   text;
  v_notes_rest  text;
  v_made_all    text;
  v_lived       boolean := false;
  v_lis         uuid;
  v_prt         uuid;
  v_a           uuid;   -- a house with no part
  v_b           uuid;   -- a house that keeps both parts
  v_fa          uuid;
  v_fb          uuid;
  v_labour      bigint;
  v_purse       bigint;
  v_r           jsonb;
  v_err         text;
  v_yard        jsonb;
  g             record;
  v_ms_catalog  numeric;
  v_ms_probe    numeric;
  c_class       constant text := 'barca';
  c_old_items   constant jsonb := '[{"item": "anchor-and-cable", "qty": 1}, {"item": "suit-of-sails", "qty": 1}]';
  c_old_note    constant text := 'A coaster. Two fittings and a stack of deal boards - the hull a house builds first.';
  c_new_note    constant text := 'A coaster. A stack of deal boards, tar, cordage and nails - the hull a house builds first.';
  c_uid_a       constant uuid := '00000000-0363-4000-8000-000000000001';
  c_uid_b       constant uuid := '00000000-0363-4000-8000-000000000002';
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from unnest(array['cmd.do_build(uuid,jsonb)', 'world.building_yard(uuid)', 'world.yard_sources(uuid,text)', 'public.yard_labour(uuid,text)', 'public.form_fleet(uuid,text,uuid)',
                                        'cmd.assume_identity(uuid)', 'public.news_update(text,text,text)']) f where to_regprocedure(f) is null)
     or to_regclass('public.hull_recipe_items') is null or to_regclass('public.hull_recipes') is null or to_regclass('public.player_items') is null or to_regclass('public.player_storage') is null then
    raise exception '0363 refuses: the yard (0072), its reads, or the news (0347) are not in this world';
  end if;
  if (select p.prosrc from pg_proc p where p.oid = 'world.yard_sources(uuid,text)'::regprocedure) not like '%0358: THE WHOLE LIST%' then
    raise exception '0363 refuses: 0358 (the yard plans the build) is not in this world; this file deploys after it';
  end if;
  if not exists (select 1 from public.hull_recipe_items hi where hi.class_code = c_class)
     and (select r.note from public.hull_recipes r where r.class_code = c_class) = c_new_note then
    raise exception '0363 refuses: it has been applied once';
  end if;
  -- THE PRE-IMAGE: exactly the two rows and the note this file was written against
  if (select coalesce(jsonb_agg(jsonb_build_object('item', hi.item_code, 'qty', hi.qty) order by hi.item_code), '[]'::jsonb) from public.hull_recipe_items hi where hi.class_code = c_class)
       is distinct from c_old_items
     or (select r.note from public.hull_recipes r where r.class_code = c_class) is distinct from c_old_note then
    raise exception '0363 refuses: the Barca''s recipe is not what this file was written against (her parts: %; her note: %)',
      (select jsonb_agg(jsonb_build_object('item', hi.item_code, 'qty', hi.qty) order by hi.item_code) from public.hull_recipe_items hi where hi.class_code = c_class),
      (select r.note from public.hull_recipes r where r.class_code = c_class);
  end if;

  -- ── 1. BEFORE: the catalog and the recipe tables (rule tables: no player writes to them) ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c;
  select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname)) into v_rel_before
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p');
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_job_before;
  end if;
  select md5(coalesce(string_agg(hi.class_code || ':' || hi.item_code || ':' || hi.qty::text, ',' order by hi.class_code, hi.item_code) filter (where hi.class_code <> c_class), '')),
         md5(coalesce(string_agg(hi.class_code || ':' || hi.item_code || ':' || hi.qty::text, ',' order by hi.class_code, hi.item_code), ''))
    into v_items_rest, v_items_all from public.hull_recipe_items hi;
  select md5(string_agg(hg.class_code || ':' || hg.good_id::text || ':' || hg.qty::text, ',' order by hg.class_code, hg.good_id)) into v_goods_all from public.hull_recipe_goods hg;
  select md5(string_agg(r.class_code || ':' || r.yard_tier::text || ':' || r.ducats::text || ':' || coalesce(r.note, ''), ',' order by r.class_code) filter (where r.class_code <> c_class)
             || '|' || (select r2.yard_tier::text || ':' || r2.ducats::text from public.hull_recipes r2 where r2.class_code = c_class))
    into v_notes_rest from public.hull_recipes r;
  select md5(string_agg(ir.item_code || ':' || ir.good_id::text || ':' || ir.qty::text, ',' order by ir.item_code, ir.good_id)) into v_made_all from public.item_recipes ir;

  -- ── 2. THE CHANGE: two rows go, one note is reworded ──
  delete from public.hull_recipe_items hi where hi.class_code = c_class;
  get diagnostics v_n = row_count;
  if v_n <> 2 then
    raise exception '0363 self-assert FAIL: % row(s) of the Barca''s parts were deleted, not 2', v_n;
  end if;
  update public.hull_recipes r set note = c_new_note where r.class_code = c_class and r.note = c_old_note;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception '0363 self-assert FAIL: % row(s) of the Barca''s note were reworded, not 1', v_n;
  end if;

  -- ── 3. THE SELF-ASSERT: the catalog and the other recipes ──
  v_t := clock_timestamp();
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> v_fn_before then
    raise exception '0363 self-assert FAIL: a function moved: this file edits none';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0363 self-assert FAIL: a world_config row moved: this file sets no knob';
  end if;
  if (select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname))
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p')) <> v_rel_before then
    raise exception '0363 self-assert FAIL: a table, view, sequence or index appeared or went: this file makes none';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_txt;
    if v_txt is distinct from v_job_before then
      raise exception '0363 self-assert FAIL: a cron job moved: this file schedules nothing';
    end if;
  end if;
  -- every other hull keeps her parts, every hull her goods, tier and labour; every part is made of what it was made of
  if (select md5(coalesce(string_agg(hi.class_code || ':' || hi.item_code || ':' || hi.qty::text, ',' order by hi.class_code, hi.item_code), '')) from public.hull_recipe_items hi) <> v_items_rest
     or (select md5(string_agg(hg.class_code || ':' || hg.good_id::text || ':' || hg.qty::text, ',' order by hg.class_code, hg.good_id)) from public.hull_recipe_goods hg) <> v_goods_all
     or (select md5(string_agg(r.class_code || ':' || r.yard_tier::text || ':' || r.ducats::text || ':' || coalesce(r.note, ''), ',' order by r.class_code) filter (where r.class_code <> c_class)
                    || '|' || (select r2.yard_tier::text || ':' || r2.ducats::text from public.hull_recipes r2 where r2.class_code = c_class)) from public.hull_recipes r) <> v_notes_rest
     or (select md5(string_agg(ir.item_code || ':' || ir.good_id::text || ':' || ir.qty::text, ',' order by ir.item_code, ir.good_id)) from public.item_recipes ir) <> v_made_all then
    raise exception '0363 self-assert FAIL: a recipe row other than the Barca''s two parts and her note moved';
  end if;
  if not exists (select 1 from public.hull_recipe_items hi where hi.class_code = 'carlat') or not exists (select 1 from public.hull_recipe_items hi where hi.class_code = 'nau')
     or (select count(*) from public.hull_recipe_goods hg where hg.class_code = c_class) <> 4 then
    raise exception '0363 self-assert FAIL: the Caravela latina or the Nau lost her parts, or the Barca does not take four hull goods';
  end if;
  v_ms_catalog := round(extract(epoch from clock_timestamp() - v_t) * 1000);

  -- ── 4. THE SELF-ASSERT: the doors, on a probe of this file's own rows, rolled back ──
  v_t := clock_timestamp();
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    select n.id into v_prt from public.nations n where n.code = 'PRT';
    if v_lis is null or v_prt is null or not exists (select 1 from public.port_buildings b where b.port_id = v_lis and b.kind = 'building_yard') then
      raise exception '0363 self-assert FAIL: Lisbon keeps no build yard to probe';
    end if;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values (c_uid_a, 'Casa Sem Pecas 0363', v_prt, 40000, false) returning id into v_a;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values (c_uid_b, 'Casa Com Pecas 0363', v_prt, 40000, false) returning id into v_b;
    v_fa := public.form_fleet(v_a, 'Sem Pecas', v_lis);
    perform public.commission_ship(v_a, v_fa, 'barca', 'Primeira A 0363', true, true);
    v_fb := public.form_fleet(v_b, 'Com Pecas', v_lis);
    perform public.commission_ship(v_b, v_fb, 'barca', 'Primeira B 0363', true, true);
    v_labour := public.yard_labour(v_a, c_class);

    -- (a) NO PART, NO GOODS: the yard still asks for her timber
    begin
      v_r := cmd.do_build(v_fa, jsonb_build_object('class', c_class, 'name', 'Segunda A 0363'));
      raise exception '0363 self-assert FAIL: with nothing stored the yard built a Barca: %', v_r;
    exception when sqlstate 'P0001' then
      get stacked diagnostics v_err = message_text;
      if v_err like '0363 self-assert FAIL%' then raise; end if;
      if v_err not like 'E_NO_TIMBER:%' then
        raise exception '0363 self-assert FAIL: with nothing stored the yard answered: %', v_err;
      end if;
    end;

    -- (b) THE FOUR GOODS STORED, NO PART: she is built. Both houses store the recipe's own counts.
    for g in select hg.good_id, hg.qty from public.hull_recipe_goods hg where hg.class_code = c_class loop
      insert into public.player_storage (player_id, port_id, good_id, qty) values (v_a, v_lis, g.good_id, g.qty), (v_b, v_lis, g.good_id, g.qty);
    end loop;
    perform cmd.assume_identity(c_uid_a);
    v_yard := (select h.value from jsonb_array_elements(world.building_yard(v_lis) -> 'hulls') h where h.value ->> 'class' = c_class);
    if v_yard is null or not (v_yard ->> 'buildable')::boolean or v_yard -> 'items' <> '[]'::jsonb or jsonb_array_length(v_yard -> 'goods') <> 4 or v_yard ->> 'note' <> c_new_note
       or exists (select 1 from jsonb_array_elements(v_yard -> 'goods') m where (m.value ->> 'have')::numeric < (m.value ->> 'qty')::numeric) then
      raise exception '0363 self-assert FAIL: the yard''s read does not serve a Barca of four goods, no part, all there: %', v_yard;
    end if;
    v_r := world.yard_sources(v_lis, c_class);
    if v_r -> 'items' <> '[]'::jsonb or jsonb_array_length(v_r -> 'goods') <> 4 then
      raise exception '0363 self-assert FAIL: the sheet''s read still lists a part for the Barca, or not her four goods: %', v_r;
    end if;
    v_r := cmd.do_build(v_fa, jsonb_build_object('class', c_class, 'name', 'Segunda A 0363'));
    if (select count(*) from public.ships s where s.fleet_id = v_fa) <> 2
       or exists (select 1 from public.player_storage ps where ps.player_id = v_a)
       or (select pl.ducats from public.players pl where pl.id = v_a) <> 40000 - v_labour or v_labour <= 0 then
      raise exception '0363 self-assert FAIL: the house with no part did not get her second ship for the four goods and the labour: %', v_r;
    end if;

    -- (c) A HOUSE THAT KEEPS BOTH PARTS builds one and KEEPS both parts: nothing she holds is taken
    insert into public.player_items (player_id, port_id, item_code, qty) values (v_b, v_lis, 'suit-of-sails', 1), (v_b, v_lis, 'anchor-and-cable', 1);
    v_r := cmd.do_build(v_fb, jsonb_build_object('class', c_class, 'name', 'Segunda B 0363'));
    if (select count(*) from public.ships s where s.fleet_id = v_fb) <> 2
       or (select coalesce(jsonb_agg(jsonb_build_object('item', pi.item_code, 'qty', pi.qty) order by pi.item_code), '[]'::jsonb) from public.player_items pi where pi.player_id = v_b) is distinct from c_old_items then
      raise exception '0363 self-assert FAIL: the house that keeps both parts lost one to a Barca''s build, or was not built her ship: %',
        (select jsonb_agg(jsonb_build_object('item', pi.item_code, 'qty', pi.qty)) from public.player_items pi where pi.player_id = v_b);
    end if;

    -- (d) PARTS STILL BITE ELSEWHERE: with a Caravela latina's goods stored, the yard refuses for her parts and counts the ones the house keeps
    for g in select hg.good_id, hg.qty from public.hull_recipe_goods hg where hg.class_code = 'carlat' loop
      insert into public.player_storage (player_id, port_id, good_id, qty) values (v_b, v_lis, g.good_id, g.qty);
    end loop;
    begin
      v_r := cmd.do_build(v_fb, jsonb_build_object('class', 'carlat', 'name', 'Latina B 0363'));
      raise exception '0363 self-assert FAIL: a Caravela latina was built without her parts: %', v_r;
    exception when sqlstate 'P0001' then
      get stacked diagnostics v_err = message_text;
      if v_err like '0363 self-assert FAIL%' then raise; end if;
      if v_err not like 'E_NO_FITTINGS:%' or v_err not like '%Suit of Sails (1 of 2)%' or v_err like '%Anchor & Cable%' then
        raise exception '0363 self-assert FAIL: the Caravela latina did not refuse for her parts, counting the ones kept: %', v_err;
      end if;
    end;

    -- (e) THE ROLLBACK, PLAYED: the two rows and the note put back are the pre-image, and the Barca refuses for her parts again
    insert into public.hull_recipe_items (class_code, item_code, qty) values (c_class, 'suit-of-sails', 1), (c_class, 'anchor-and-cable', 1);
    update public.hull_recipes r set note = c_old_note where r.class_code = c_class;
    if (select md5(coalesce(string_agg(hi.class_code || ':' || hi.item_code || ':' || hi.qty::text, ',' order by hi.class_code, hi.item_code), '')) from public.hull_recipe_items hi) <> v_items_all
       or (select r.note from public.hull_recipes r where r.class_code = c_class) <> c_old_note then
      raise exception '0363 self-assert FAIL: the two rows put back are not the pre-image';
    end if;
    for g in select hg.good_id, hg.qty from public.hull_recipe_goods hg where hg.class_code = c_class loop
      insert into public.player_storage (player_id, port_id, good_id, qty) values (v_a, v_lis, g.good_id, g.qty);
    end loop;
    select pl.ducats into v_purse from public.players pl where pl.id = v_a;
    begin
      v_r := cmd.do_build(v_fa, jsonb_build_object('class', c_class, 'name', 'Terceira A 0363'));
      raise exception '0363 self-assert FAIL: with the rows put back a Barca was built without her parts: %', v_r;
    exception when sqlstate 'P0001' then
      get stacked diagnostics v_err = message_text;
      if v_err like '0363 self-assert FAIL%' then raise; end if;
      if v_err not like 'E_NO_FITTINGS:%' or v_err not like '%Anchor & Cable (0 of 1)%' or v_err not like '%Suit of Sails (0 of 1)%' then
        raise exception '0363 self-assert FAIL: with the rows put back the Barca did not refuse for her two parts: %', v_err;
      end if;
    end;
    if (select pl.ducats from public.players pl where pl.id = v_a) <> v_purse or (select count(*) from public.player_storage ps where ps.player_id = v_a) <> 4 then
      raise exception '0363 self-assert FAIL: the refused build moved the probe''s purse or storage';
    end if;

    raise exception using errcode = 'ZX363', message = 'PROBE_ROLLBACK_0363';
  exception when sqlstate 'ZX363' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0363 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players pl where pl.auth_uid in (c_uid_a, c_uid_b)) then
    raise exception '0363 self-assert FAIL: a probe house outlived the probe';
  end if;
  -- the change outlived the probe's rollback; the rollback played inside it did not
  if exists (select 1 from public.hull_recipe_items hi where hi.class_code = c_class)
     or (select r.note from public.hull_recipes r where r.class_code = c_class) <> c_new_note
     or (select md5(coalesce(string_agg(hi.class_code || ':' || hi.item_code || ':' || hi.qty::text, ',' order by hi.class_code, hi.item_code), '')) from public.hull_recipe_items hi) <> v_items_rest then
    raise exception '0363 self-assert FAIL: the Barca''s recipe after the probe is not four goods, no part and the new note';
  end if;
  v_ms_probe := round(extract(epoch from clock_timestamp() - v_t) * 1000);

  -- THIS FILE'S OWN UPDATE ROW (0347's news law, tests/news.lint.spec.ts), counted by its own key; outside the rolled-back probe
  perform public.news_update('0363', 'Barca: no parts needed', '바르카: 부품 불필요');
  if (select count(*) from public.world_news w where w.key = 'update:0363') <> 1 then
    raise exception '0363 self-assert FAIL: this file''s UPDATE row is not one row';
  end if;
  if clock_timestamp() - v_t0 > interval '20 seconds' then
    raise exception '0363 self-assert FAIL: the file ran % s, over its 20 s budget', round(extract(epoch from clock_timestamp() - v_t0));
  end if;
  raise notice '0363 timings: catalog and recipes % ms; the doors (two probe houses, three builds, three refusals, the rollback played) % ms', v_ms_catalog, v_ms_probe;
  raise notice '0363 self-assert ok: THE BARCA NEEDS NO PARTS. Her two part rows are gone (exactly the two this file was written against) and her note is reworded; a probe house with her four goods stored and no part built one for the labour (%); a probe house that keeps a Suit of Sails and an Anchor & Cable built one and keeps both; the Caravela latina still refuses for her parts and counts the ones kept; with the two rows put back the Barca refuses for her parts again (the rollback, played and rolled back). No function, knob, table or job moved; every other recipe row is as it was; no player''s row is written; its UPDATE row is one row. % ms.',
    v_labour, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
