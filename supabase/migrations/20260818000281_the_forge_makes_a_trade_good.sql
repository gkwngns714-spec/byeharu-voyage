-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0281 — THE FORGE MAKES A TRADE GOOD
--        The City page's Forge building: a CRAFTED trade good (goods.tier 1-3) is made out of the
--        RAW goods (tier 0) stored in this city, using the recipe graph 0280 added
--        (public.goods_recipes). One verb, one read, two served fields.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHAT THIS FORGE IS, AND WHAT IT IS NOT (the owner's City page) ─────────────────────────────
-- The City page has six buildings; the Forge is "using raw materials + recipes, produce foods,
-- goods, weapons for trading." That is the GOODS economy: public.goods + public.goods_recipes
-- (0280). It is NOT the item/fitting system — public.item_kinds / public.item_recipes /
-- public.forge_jobs / cmd.do_make — which is the WORKSHOP's (0068) and, separately, the future
-- CORP home forge of docs/CORP_STORAGE_FORGE.md. Nothing here reads or writes those tables, and
-- no command word is added to the grammar. The read is named world.goods_forge ON PURPOSE, so
-- `world.forge` stays free for the corp item forge that design already names (see the dev-log).
--
-- ── WHAT IT COMPOSES, AND WHAT IT REFUSES TO RE-IMPLEMENT ──────────────────────────────────────
-- Storage is per (player, port, good) and is reachable only from a ship lying there (0070). This
-- file does NOT write a second storage rule: it NAMES the two halves 0070's verbs already spelled
-- out and re-cuts those verbs onto them, byte-identically in behaviour:
--   * public.storage_put(player, port, good, qty, basis) — the cap check (public.storage_cap /
--     public.storage_used), the E_SHED_FULL refusal and the basis-blended upsert cmd.do_store
--     performs (0081).
--   * public.storage_take(player, port, good, qty) — the removal cmd.do_take performs, returning
--     what actually left. (docs/CORP_STORAGE_FORGE.md §"taking from storage" names exactly this
--     extraction; it lands here early so the goods forge and the item forge share ONE removal.)
-- The forge itself is cmd.do_make's shape (0068: validate the product, test every material, spend
-- them, store the output) applied to goods instead of fittings, and cmd.invest's shape (0123) for
-- a port-scoped, fleet-gated client verb that answers with a refusal envelope.
--
-- ── NO MONEY MOVES ─────────────────────────────────────────────────────────────────────────────
-- A forge is not a sale. The purse is untouched and no ledger row is written. The only accounting
-- is 0081's cost basis: the tuns consumed carry their average paid cost into the product, through
-- public.blend_basis — the one weighted-average rule, never a second one.
--
-- ── SERVED ─────────────────────────────────────────────────────────────────────────────────────
--   * world.snapshot().goods[] and every world.market() row gain `tier` and `is_raw` (the fields
--     0280 put on public.goods). Nothing else in either payload moves.
--   * world.goods_forge(port) — the face's one read: whether a fleet of yours lies here, and every
--     crafted good with its recipe and how much of each ingredient is IN THIS CITY'S STORAGE, with
--     the server's own `can_forge` verdict beside it.
--   * cmd.forge_good(port, product, qty) — the one verb.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('lock_timeout', '5s', true);
  if to_regclass('public.goods_recipes') is null
     or not exists (select 1 from information_schema.columns
                     where table_schema = 'public' and table_name = 'goods' and column_name = 'tier') then
    raise exception '0281 refuses: 0280 is not applied (goods.tier / goods_recipes missing)';
  end if;
  if to_regprocedure('cmd.forge_good(uuid,uuid,int)') is not null
     or to_regprocedure('world.goods_forge(uuid)') is not null
     or to_regprocedure('public.storage_put(uuid,uuid,uuid,numeric,numeric)') is not null
     or to_regprocedure('public.storage_take(uuid,uuid,uuid,numeric)') is not null then
    raise exception '0281 refuses: a function this migration creates already exists';
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
      raise exception '0281 slice: hunk % of % occurs % time(s) in %, expected exactly 1 - the deployed body is not what this migration was generated against.',
        (v_i + 1) / 2, (array_length(p_edits, 1)) / 2, v_n, p_fn;
    end if;
    v_def := replace(v_def, p_edits[v_i], p_edits[v_i + 1]);
    v_i := v_i + 2;
  end loop;
  if p_drop then execute format('drop function %s', p_fn::text); end if;
  execute v_def;
end $fn$;

-- ── 0. THE PRE-IMAGE ────────────────────────────────────────────────────────────────────────────
create temp table defs_pre_0281 on commit drop as
select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce(p.proacl::text, '') as acl
  from (values ('world.snapshot()'),
               ('world.market(uuid)'),
               ('cmd.do_store(uuid,jsonb)'),
               ('cmd.do_take(uuid,jsonb)'),
               ('public.client_rpc_entry_points()')) f(fn)
  join pg_proc p on p.oid = f.fn::regprocedure;

create temp table pre_0281 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       world.snapshot() as snap;

-- ── 1. THE TWO STORAGE HALVES, NAMED ONCE ──────────────────────────────────────────────────────
-- PUT: the cap, the refusal and the blended upsert cmd.do_store spelled out (0070 §3-4, 0081 §1).
create or replace function public.storage_put(p_player uuid, p_port uuid, p_good uuid,
                                              p_qty numeric, p_basis numeric default null)
returns numeric
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $sp$
declare
  g      public.goods%rowtype;
  v_room numeric;
begin
  if coalesce(p_qty, 0) <= 0 then
    raise exception 'E_NO_QTY: nothing is put ashore' using errcode = 'P0001';
  end if;
  select * into g from public.goods where id = p_good;
  if g.id is null then
    raise exception 'E_NO_SUCH_GOOD: nothing is called that' using errcode = 'P0001';
  end if;
  v_room := public.storage_cap(p_port) - public.storage_used(p_player, p_port);
  if p_qty * g.bulk > v_room then
    raise exception 'E_SHED_FULL: the shed here holds % more tun(s) and % of % wants %',
      trim(to_char(greatest(v_room, 0), 'FM999999.9')), trim(to_char(p_qty, 'FM999999')),
      g.name, trim(to_char(p_qty * g.bulk, 'FM999999.9')) using errcode = 'P0001';
  end if;
  insert into public.player_storage (player_id, port_id, good_id, qty, basis)
  values (p_player, p_port, p_good, p_qty, p_basis)
  on conflict (player_id, port_id, good_id) do update
    set qty   = public.player_storage.qty + excluded.qty,
        basis = public.blend_basis(public.player_storage.qty, public.player_storage.basis,
                                   excluded.qty, excluded.basis);
  return p_qty;
end $sp$;

-- TAKE: the removal cmd.do_take performs, returning what actually left (never more than is there).
create or replace function public.storage_take(p_player uuid, p_port uuid, p_good uuid, p_qty numeric)
returns numeric
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $st$
declare
  v_have numeric;
  v_take numeric;
begin
  select ps.qty into v_have from public.player_storage ps
   where ps.player_id = p_player and ps.port_id = p_port and ps.good_id = p_good;
  v_take := least(greatest(coalesce(p_qty, 0), 0), coalesce(v_have, 0));
  if v_take <= 0 then return 0; end if;
  update public.player_storage set qty = qty - v_take
   where player_id = p_player and port_id = p_port and good_id = p_good;
  delete from public.player_storage
   where player_id = p_player and port_id = p_port and good_id = p_good and qty <= 0;
  return v_take;
end $st$;

revoke all on function public.storage_put(uuid, uuid, uuid, numeric, numeric) from public, anon, authenticated;
revoke all on function public.storage_take(uuid, uuid, uuid, numeric) from public, anon, authenticated;

comment on function public.storage_put(uuid, uuid, uuid, numeric, numeric) is
  '0281 — the ONE way goods go ashore: the shed''s cap, its E_SHED_FULL refusal and the basis-'
  'blended upsert. cmd.do_store calls it (0070 §4, 0081 §1); the Forge calls it. A second writer '
  'of public.player_storage is the defect this exists to prevent.';
comment on function public.storage_take(uuid, uuid, uuid, numeric) is
  '0281 — the ONE way goods leave a city''s storage without a hold: it removes up to the quantity '
  'and returns what left. cmd.do_take calls it for the tuns that fitted (0070 §4); the Forge calls '
  'it for its ingredients. Named by docs/CORP_STORAGE_FORGE.md so the item forge shares it.';

-- ── 2. THE EXISTING VERBS CALL THE ONE RULE ────────────────────────────────────────────────────
select pg_temp.recut('cmd.do_store(uuid,jsonb)'::regprocedure, false,
  $s0$  v_room := public.storage_cap(f.port_id) - public.storage_used(f.player_id, f.port_id);
  if v_qty * g.bulk > v_room then
    raise exception 'E_SHED_FULL: the shed here holds % more tun(s) and % of % wants %',
      trim(to_char(greatest(v_room, 0), 'FM999999.9')), trim(to_char(v_qty, 'FM999999')),
      g.name, trim(to_char(v_qty * g.bulk, 'FM999999.9')) using errcode = 'P0001';
  end if;$s0$,
  $s1$  -- 0281: how much room is left and what the shed refuses is ONE rule (public.storage_put).
  -- The unload below still happens first, and a raise from the put rolls the whole order back.$s1$,
  $s2$  insert into public.player_storage (player_id, port_id, good_id, qty, basis)
  values (f.player_id, f.port_id, g.id, v_qty, v_basis)
  on conflict (player_id, port_id, good_id) do update
    set qty   = public.player_storage.qty + excluded.qty,
        basis = public.blend_basis(public.player_storage.qty, public.player_storage.basis,
                                   excluded.qty, excluded.basis);$s2$,
  $s3$  perform public.storage_put(f.player_id, f.port_id, g.id, v_qty, v_basis);$s3$);

select pg_temp.recut('cmd.do_take(uuid,jsonb)'::regprocedure, false,
  $t0$  update public.player_storage set qty = qty - v_took
   where player_id = f.player_id and port_id = f.port_id and good_id = g.id;
  delete from public.player_storage
   where player_id = f.player_id and port_id = f.port_id and good_id = g.id and qty <= 0;$t0$,
  $t1$  -- 0281: the removal is ONE rule (public.storage_take), shared with the Forge.
  perform public.storage_take(f.player_id, f.port_id, g.id, v_took);$t1$);

-- ── 3. TIER AND IS_RAW CROSS THE WIRE ──────────────────────────────────────────────────────────
-- On snapshot.goods[] and on every market row, beside 0032's rarity, from the columns 0280 added.
-- The field, not the rule: a client prints what the catalogue says and derives nothing.
select pg_temp.recut('world.snapshot()'::regprocedure, false,
  $g0$        'rarity', public.good_rarity(g.id),
        'culture_mask', g.culture_mask) order by g.code), '[]'::jsonb) from public.goods g),$g0$,
  $g1$        'rarity', public.good_rarity(g.id),
        -- 0281: 0280's tier, served so the Forge and the market can tell a raw good from a made one.
        'tier', g.tier, 'is_raw', g.is_raw,
        'culture_mask', g.culture_mask) order by g.code), '[]'::jsonb) from public.goods g),$g1$);

select pg_temp.recut('world.market(uuid)'::regprocedure, false,
  $m0$        'rarity', public.good_rarity(g.id),
        'buy',  q.ask, 'sell', q.bid, 'mid', q.mid,$m0$,
  $m1$        'rarity', public.good_rarity(g.id),
        -- 0281: the same two fields as snapshot.goods[], from the same columns.
        'tier', g.tier, 'is_raw', g.is_raw,
        'buy',  q.ask, 'sell', q.bid, 'mid', q.mid,$m1$);

-- ── 4. THE FORGE'S ONE READ ────────────────────────────────────────────────────────────────────
-- What this city's Forge offers, and — because only the server may decide it — whether you can
-- make each one from what is IN THIS CITY'S STORAGE. No fleet argument: the ingredients come out
-- of the shed, not a hold (0072's reason). `docked` is the same test cmd.forge_good applies.
create or replace function world.goods_forge(p_port uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $wf$
declare
  v_player uuid := public.current_player_id();
begin
  return jsonb_build_object(
    'port_id', p_port,
    'docked', exists (select 1 from public.fleets f
                       where f.player_id = v_player and f.port_id = p_port and f.status = 'DOCKED'),
    'recipes', (
      select coalesce(jsonb_agg(jsonb_build_object(
          'product_id', g.id, 'product', g.code, 'name', g.name, 'tier', g.tier, 'bulk', g.bulk,
          -- THE SERVER'S VERDICT, for one: every ingredient is ashore here in the recipe's quantity.
          'can_forge', not exists (
            select 1 from public.goods_recipes gr
              left join public.player_storage ps
                     on ps.player_id = v_player and ps.port_id = p_port and ps.good_id = gr.ingredient_id
             where gr.product_id = g.id and coalesce(ps.qty, 0) < gr.qty),
          'ingredients', (
            select coalesce(jsonb_agg(jsonb_build_object(
                'good', i.code, 'name', i.name, 'tier', i.tier,
                'qty', gr.qty, 'have', coalesce(ps.qty, 0))
              order by i.name), '[]'::jsonb)
              from public.goods_recipes gr
              join public.goods i on i.id = gr.ingredient_id
              left join public.player_storage ps
                     on ps.player_id = v_player and ps.port_id = p_port and ps.good_id = gr.ingredient_id
             where gr.product_id = g.id))
        order by g.tier, g.name), '[]'::jsonb)
      from public.goods g
     where g.tier >= 1
       and exists (select 1 from public.goods_recipes gr where gr.product_id = g.id)));
end $wf$;

revoke all on function world.goods_forge(uuid) from public, anon;
grant execute on function world.goods_forge(uuid) to authenticated;

comment on function world.goods_forge(uuid) is
  '0281 — the City page''s Forge read: every crafted good (tier >= 1 with a goods_recipes row), its '
  'ingredients, how many of each are ashore HERE, and whether that is enough. Named goods_forge, '
  'not forge, so docs/CORP_STORAGE_FORGE.md''s world.forge (the ITEM forge) is not taken.';

-- ── 5. THE FORGE'S ONE VERB ────────────────────────────────────────────────────────────────────
create or replace function cmd.forge_good(p_port uuid, p_product uuid, p_qty int)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $fg$
-- 0281: the caller's house forges v_qty of a crafted TRADE good out of the raw goods stored in
-- this city (public.goods_recipes). Fleet-gated like cmd.invest: storage is only reachable from a
-- ship lying here (0070). No money moves; the ingredients' cost basis carries into the product.
declare
  v_player uuid := public.current_player_id();
  v_qty    int := greatest(1, coalesce(p_qty, 1));
  v_product public.goods%rowtype;
  v_short  text;
  v_spent  jsonb := '[]'::jsonb;
  v_tuns   numeric := 0;
  v_basis  numeric;
  v_det    text;
  r        record;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE',
                              'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    if not exists (select 1 from public.fleets f
                    where f.player_id = v_player and f.status = 'DOCKED' and f.port_id = p_port) then
      perform cmd.refuse('E_NOT_DOCKED', 'dock a fleet here to forge');
    end if;

    select * into v_product from public.goods where id = p_product;
    if v_product.id is null then
      perform cmd.refuse('E_NO_SUCH_GOOD', 'nothing is called that');
    end if;

    -- ONLY A CRAFTED GOOD IS FORGED. Tier 0 is what a city PRODUCES; a good with no recipe in
    -- 0280's table is not forgeable at all. The item system (item_kinds/item_recipes) is not read.
    if v_product.tier < 1
       or not exists (select 1 from public.goods_recipes gr where gr.product_id = p_product) then
      perform cmd.refuse('E_NOT_FORGEABLE', format('%s is not made in a forge', v_product.name));
    end if;

    -- EVERYTHING, BEFORE ANYTHING LEAVES. Same rule as cmd.do_make: test all the materials first,
    -- name what is short, then spend.
    select string_agg(format('%s (%s of %s)', g.name,
             trim(to_char(coalesce(ps.qty, 0), 'FM999999.99')),
             trim(to_char(gr.qty * v_qty, 'FM999999.99'))), ', ' order by g.name)
      into v_short
      from public.goods_recipes gr
      join public.goods g on g.id = gr.ingredient_id
      left join public.player_storage ps
             on ps.player_id = v_player and ps.port_id = p_port and ps.good_id = gr.ingredient_id
     where gr.product_id = p_product
       and coalesce(ps.qty, 0) < gr.qty * v_qty;
    if v_short is not null then
      perform cmd.refuse('E_NO_MATERIALS', format('the forge is short of %s', v_short));
    end if;

    for r in select gr.ingredient_id, g.code, g.name, gr.qty * v_qty as need, ps.basis
               from public.goods_recipes gr
               join public.goods g on g.id = gr.ingredient_id
               left join public.player_storage ps
                      on ps.player_id = v_player and ps.port_id = p_port and ps.good_id = gr.ingredient_id
              where gr.product_id = p_product
              order by g.code loop
      -- 0081's ONE weighted average: what the consumed tuns cost per tun, carried into the product.
      v_basis := public.blend_basis(v_tuns, v_basis, r.need, r.basis);
      v_tuns  := v_tuns + r.need;
      perform public.storage_take(v_player, p_port, r.ingredient_id, r.need);
      v_spent := v_spent || jsonb_build_object('good', r.code, 'qty', r.need);
    end loop;

    -- THE PRODUCT LANDS IN THE SAME SHED, through the same cap rule. A full shed refuses here and
    -- the raise rolls every take above back with it (this block is one subtransaction).
    perform public.storage_put(v_player, p_port, p_product, v_qty, v_basis);

    perform public.emit_event(v_player, 'FORGED', jsonb_build_object(
      'product', v_product.name, 'qty', v_qty, 'spent', v_spent));

    return jsonb_build_object('ok', true,
      'product', v_product.code, 'name', v_product.name, 'qty', v_qty, 'spent', v_spent,
      'stored_here', (select ps.qty from public.player_storage ps
                       where ps.player_id = v_player and ps.port_id = p_port and ps.good_id = p_product));
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end $fg$;

revoke all on function cmd.forge_good(uuid, uuid, int) from public, anon;
grant execute on function cmd.forge_good(uuid, uuid, int) to authenticated;

comment on function cmd.forge_good(uuid, uuid, int) is
  '0281 — the goods Forge''s one verb: consume a crafted good''s goods_recipes ingredients from '
  'this city''s storage and store the product there. No money moves, no item is touched. Refuses '
  'E_NOT_DOCKED / E_NO_SUCH_GOOD / E_NOT_FORGEABLE / E_NO_MATERIALS / E_SHED_FULL.';

-- ── 6. THE CLIENT MAY CALL BOTH ────────────────────────────────────────────────────────────────
select pg_temp.recut('public.client_rpc_entry_points()'::regprocedure, false,
  $e0$      ('world',       'city_history',          'uuid, int')$e0$,
  $e1$      ('world',       'city_history',          'uuid, int'),
      -- 0281 (the City page's Forge): the goods-crafting read and verb. Distinct from the item
      -- forge docs/CORP_STORAGE_FORGE.md plans (world.forge / cmd.forge).
      ('world',       'goods_forge',           'uuid'),
      ('cmd',         'forge_good',            'uuid, uuid, int')$e1$);

-- ── 7. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_ep         int;
  v_bad        int;
  v_cur        text;
  v_rev        text;
  v_def        record;
  v_acl        text;
  v_h          record;
  v_snap       jsonb;
  v_player     uuid;
  v_fleet      uuid;
  v_port       uuid;
  v_other      uuid;
  v_product    uuid;
  v_product_c  text;
  v_raw        uuid;
  v_need       numeric;
  v_have       numeric;
  v_res        jsonb;
  v_purse      numeric;
  v_basis      numeric;
  v_can        boolean;
  c_uid constant uuid := '00000000-0281-4000-8000-000000000001';
  c_date constant text := '0281';
begin
  create temp table hunks_0281 (fn text, old_text text, new_text text);

  insert into hunks_0281 values
  ('cmd.do_store(uuid,jsonb)',
   $s0$  v_room := public.storage_cap(f.port_id) - public.storage_used(f.player_id, f.port_id);
  if v_qty * g.bulk > v_room then
    raise exception 'E_SHED_FULL: the shed here holds % more tun(s) and % of % wants %',
      trim(to_char(greatest(v_room, 0), 'FM999999.9')), trim(to_char(v_qty, 'FM999999')),
      g.name, trim(to_char(v_qty * g.bulk, 'FM999999.9')) using errcode = 'P0001';
  end if;$s0$,
   $s1$  -- 0281: how much room is left and what the shed refuses is ONE rule (public.storage_put).
  -- The unload below still happens first, and a raise from the put rolls the whole order back.$s1$),
  ('cmd.do_store(uuid,jsonb)',
   $s2$  insert into public.player_storage (player_id, port_id, good_id, qty, basis)
  values (f.player_id, f.port_id, g.id, v_qty, v_basis)
  on conflict (player_id, port_id, good_id) do update
    set qty   = public.player_storage.qty + excluded.qty,
        basis = public.blend_basis(public.player_storage.qty, public.player_storage.basis,
                                   excluded.qty, excluded.basis);$s2$,
   $s3$  perform public.storage_put(f.player_id, f.port_id, g.id, v_qty, v_basis);$s3$),
  ('cmd.do_take(uuid,jsonb)',
   $t0$  update public.player_storage set qty = qty - v_took
   where player_id = f.player_id and port_id = f.port_id and good_id = g.id;
  delete from public.player_storage
   where player_id = f.player_id and port_id = f.port_id and good_id = g.id and qty <= 0;$t0$,
   $t1$  -- 0281: the removal is ONE rule (public.storage_take), shared with the Forge.
  perform public.storage_take(f.player_id, f.port_id, g.id, v_took);$t1$),
  ('world.snapshot()',
   $g0$        'rarity', public.good_rarity(g.id),
        'culture_mask', g.culture_mask) order by g.code), '[]'::jsonb) from public.goods g),$g0$,
   $g1$        'rarity', public.good_rarity(g.id),
        -- 0281: 0280's tier, served so the Forge and the market can tell a raw good from a made one.
        'tier', g.tier, 'is_raw', g.is_raw,
        'culture_mask', g.culture_mask) order by g.code), '[]'::jsonb) from public.goods g),$g1$),
  ('world.market(uuid)',
   $m0$        'rarity', public.good_rarity(g.id),
        'buy',  q.ask, 'sell', q.bid, 'mid', q.mid,$m0$,
   $m1$        'rarity', public.good_rarity(g.id),
        -- 0281: the same two fields as snapshot.goods[], from the same columns.
        'tier', g.tier, 'is_raw', g.is_raw,
        'buy',  q.ask, 'sell', q.bid, 'mid', q.mid,$m1$),
  ('public.client_rpc_entry_points()',
   $e0$      ('world',       'city_history',          'uuid, int')$e0$,
   $e1$      ('world',       'city_history',          'uuid, int'),
      -- 0281 (the City page's Forge): the goods-crafting read and verb. Distinct from the item
      -- forge docs/CORP_STORAGE_FORGE.md plans (world.forge / cmd.forge).
      ('world',       'goods_forge',           'uuid'),
      ('cmd',         'forge_good',            'uuid, uuid, int')$e1$);

  -- (a) EVERY HUNK IS THE ONLY ONE, AND THE WHOLE SET REVERSES TO THE PRE-IMAGE.
  for v_def in select * from defs_pre_0281 loop
    v_cur := replace(pg_get_functiondef(v_def.fn::regprocedure), E'\r', '');
    v_rev := v_cur;
    for v_h in select * from hunks_0281 where fn = v_def.fn loop
      if (length(v_cur) - length(replace(v_cur, v_h.new_text, ''))) / length(v_h.new_text) <> 1 then
        raise exception '0281 self-assert FAIL: a new hunk of % is not present exactly once', v_def.fn;
      end if;
      v_rev := replace(v_rev, v_h.new_text, v_h.old_text);
    end loop;
    if v_rev <> v_def.def then
      raise exception '0281 self-assert FAIL: % does not reverse to its pre-image', v_def.fn;
    end if;
    select coalesce(p.proacl::text, '') into v_acl from pg_proc p where p.oid = v_def.fn::regprocedure;
    if v_acl <> v_def.acl then
      raise exception '0281 self-assert FAIL: the ACL of % moved', v_def.fn;
    end if;
  end loop;

  -- (b) THE SERVED FIELDS ARE THE CATALOGUE'S, ON EVERY GOOD AND EVERY MARKET ROW.
  select count(*) into v_bad
    from jsonb_array_elements(world.snapshot()->'goods') e
    join public.goods g on g.id = (e->>'id')::uuid
   where (e->>'tier')::int is distinct from g.tier
      or (e->>'is_raw')::boolean is distinct from g.is_raw;
  if v_bad <> 0 then
    raise exception '0281 self-assert FAIL: % snapshot good(s) do not carry their own tier/is_raw', v_bad;
  end if;
  select count(*) into v_bad
    from jsonb_array_elements(
           world.market((select id from public.ports where kind = 'HARBOUR' order by code limit 1))->'goods') e
    join public.goods g on g.id = (e->>'good_id')::uuid
   where (e->>'tier')::int is distinct from g.tier
      or (e->>'is_raw')::boolean is distinct from g.is_raw;
  if v_bad <> 0 then
    raise exception '0281 self-assert FAIL: % market row(s) do not carry their own tier/is_raw', v_bad;
  end if;

  -- (c) THE READ AND ITS SHAPE.
  v_ep := (select count(*) from public.client_rpc_entry_points());
  if v_ep <> (select entry_points from pre_0281) + 2 then
    raise exception '0281 self-assert FAIL: the registry is % rows, expected the pre-image + 2', v_ep;
  end if;
  if to_regprocedure('world.goods_forge(uuid)') is null
     or to_regprocedure('cmd.forge_good(uuid,uuid,int)') is null
     or not exists (select 1 from public.client_rpc_entry_points() e
                     where e.schema_name = 'world' and e.function_name = 'goods_forge' and e.fn is not null)
     or not exists (select 1 from public.client_rpc_entry_points() e
                     where e.schema_name = 'cmd' and e.function_name = 'forge_good' and e.fn is not null) then
    raise exception '0281 self-assert FAIL: a registered name does not resolve to a function';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0281 self-assert FAIL: a client wall moved';
  end if;
  if has_function_privilege('anon', 'cmd.forge_good(uuid,uuid,int)', 'execute')
     or has_function_privilege('anon', 'world.goods_forge(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.storage_put(uuid,uuid,uuid,numeric,numeric)', 'execute')
     or has_function_privilege('authenticated', 'public.storage_take(uuid,uuid,uuid,numeric)', 'execute')
     or has_function_privilege('authenticated', 'cmd.forge_good(uuid,uuid,int)', 'execute') = false then
    raise exception '0281 self-assert FAIL: the posture of the new functions is wrong';
  end if;
  -- c2: an unauthenticated read answers, and it has a recipe for every crafted good.
  if jsonb_array_length(world.goods_forge((select id from public.ports where kind = 'HARBOUR' order by code limit 1))->'recipes')
     <> (select count(*) from public.goods where tier >= 1) then
    raise exception '0281 self-assert FAIL: the read does not list every crafted good';
  end if;

  -- (d) IT WORKS, END TO END, THROUGH THE ONE DOOR — and the probe leaves nothing behind.
  begin
    v_player := public.new_house(c_uid, 'Casa Forja', 'PRT');
    select id, port_id into v_fleet, v_port from public.fleets where player_id = v_player;
    perform cmd.assume_identity(c_uid);

    -- A recipe chosen by the DATA: lowest tier, fewest ingredients, first code.
    select gr.product_id into v_product
      from public.goods_recipes gr
      join public.goods p on p.id = gr.product_id
     group by gr.product_id, p.tier, p.code
     order by p.tier, count(*), p.code
     limit 1;
    select code into v_product_c from public.goods where id = v_product;

    -- Seed every ingredient with two extra, at a known cost, through the one put rule.
    perform public.storage_put(v_player, v_port, gr.ingredient_id, gr.qty + 2, 3.50)
      from public.goods_recipes gr where gr.product_id = v_product;

    v_purse := (select coalesce(sum(ducats_delta), 0) from public.ledger where player_id = v_player);
    v_res := cmd.forge_good(v_port, v_product, 1);
    if coalesce((v_res->>'ok')::boolean, false) is not true then
      raise exception '0281 self-assert FAIL: the forge refused its own probe: %', v_res;
    end if;

    select ps.qty into v_have from public.player_storage ps
     where ps.player_id = v_player and ps.port_id = v_port and ps.good_id = v_product;
    if v_have is distinct from 1 then
      raise exception '0281 self-assert FAIL: the product is % in the shed, expected 1', coalesce(v_have, 0);
    end if;
    select ps.basis into v_basis from public.player_storage ps
     where ps.player_id = v_player and ps.port_id = v_port and ps.good_id = v_product;
    if v_basis is distinct from 3.50 then
      raise exception '0281 self-assert FAIL: the product''s cost basis is % rather than the ingredients'' 3.50', v_basis;
    end if;
    select count(*) into v_bad
      from public.goods_recipes gr
      left join public.player_storage ps
             on ps.player_id = v_player and ps.port_id = v_port and ps.good_id = gr.ingredient_id
     where gr.product_id = v_product and coalesce(ps.qty, 0) <> 2;
    if v_bad <> 0 then
      raise exception '0281 self-assert FAIL: % ingredient(s) are not exactly the two spare tuns after one forge', v_bad;
    end if;
    if (select coalesce(sum(ducats_delta), 0) from public.ledger where player_id = v_player) <> v_purse then
      raise exception '0281 self-assert FAIL: the forge moved money';
    end if;
    if not exists (select 1 from public.events e
                    where e.player_id = v_player and e.kind = 'FORGED') then
      raise exception '0281 self-assert FAIL: no FORGED event was written';
    end if;

    -- (e) SHORT REFUSES, and moves nothing.
    v_res := cmd.forge_good(v_port, v_product, 5);
    if (v_res->>'ok')::boolean
       or v_res->>'error_code' <> 'E_NO_MATERIALS' then
      raise exception '0281 self-assert FAIL: a short forge answered % rather than E_NO_MATERIALS', v_res;
    end if;
    if (select ps.qty from public.player_storage ps
         where ps.player_id = v_player and ps.port_id = v_port and ps.good_id = v_product) is distinct from 1 then
      raise exception '0281 self-assert FAIL: a refused forge moved the product';
    end if;

    -- (f) A RAW PRODUCT IS NOT FORGEABLE.
    select g.id into v_raw from public.goods g
     where g.tier = 0 and exists (select 1 from public.goods_recipes gr where gr.ingredient_id = g.id)
     order by g.code limit 1;
    v_res := cmd.forge_good(v_port, v_raw, 1);
    if (v_res->>'ok')::boolean or v_res->>'error_code' <> 'E_NOT_FORGEABLE' then
      raise exception '0281 self-assert FAIL: a raw good answered % rather than E_NOT_FORGEABLE', v_res;
    end if;

    -- (g) STORAGE IS ONLY REACHABLE FROM A SHIP LYING HERE (0070's law).
    select p.id into v_other from public.ports p
     where p.kind = 'HARBOUR' and p.id <> v_port order by p.code limit 1;
    update public.fleets set port_id = v_other where id = v_fleet;
    v_res := cmd.forge_good(v_port, v_product, 1);
    if (v_res->>'ok')::boolean or v_res->>'error_code' <> 'E_NOT_DOCKED' then
      raise exception '0281 self-assert FAIL: a forge with no fleet here answered % rather than E_NOT_DOCKED', v_res;
    end if;
    update public.fleets set port_id = v_port where id = v_fleet;

    -- (h) THE SHED'S CAP IS STILL THE PUT RULE'S (do_store's own E_SHED_FULL).
    begin
      perform public.storage_put(v_player, v_port, v_product, 1000000, null);
      raise exception '0281 self-assert FAIL: the shed took a million tuns';
    exception when sqlstate 'P0001' then
      if sqlerrm not like 'E_SHED_FULL:%' then raise; end if;
    end;

    -- (i) TAKE REMOVES EXACTLY WHAT IS THERE, NEVER MORE.
    if public.storage_take(v_player, v_port, v_product, 99) <> 1
       or public.storage_take(v_player, v_port, v_product, 1) <> 0 then
      raise exception '0281 self-assert FAIL: storage_take did not remove exactly the one tun';
    end if;

    -- (j) THE READ AGREES: with the materials back and the fleet here, can_forge is true.
    perform public.storage_put(v_player, v_port, gr.ingredient_id, gr.qty, null)
      from public.goods_recipes gr where gr.product_id = v_product;
    select (r->>'can_forge')::boolean into v_can
      from jsonb_array_elements(world.goods_forge(v_port)->'recipes') r
     where r->>'product' = v_product_c;
    if v_can is distinct from true then
      raise exception '0281 self-assert FAIL: the read says a stocked recipe cannot be forged';
    end if;

    raise exception using errcode = 'ZX281', message = 'probe ok';
  exception when sqlstate 'ZX281' then
    null;
  end;

  -- (k) THE REVERSE RESTORES THE PRE-IMAGE, PAYLOAD AND REGISTRY INCLUDED.
  begin
    drop function world.goods_forge(uuid);
    drop function cmd.forge_good(uuid, uuid, int);
    drop function public.storage_take(uuid, uuid, uuid, numeric);
    drop function public.storage_put(uuid, uuid, uuid, numeric, numeric);
    for v_def in select * from defs_pre_0281 loop
      execute v_def.def;
    end loop;
    v_snap := world.snapshot();
    if v_snap::text <> (select snap::text from pre_0281) then
      raise exception '0281 self-assert FAIL: the reverse does not restore the snapshot payload';
    end if;
    if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from pre_0281) then
      raise exception '0281 self-assert FAIL: the reverse does not restore the registry';
    end if;
    raise exception using errcode = 'ZX282', message = 'reverse ok';
  exception when sqlstate 'ZX282' then
    null;
  end;

  raise notice '0281 self-assert ok: the Forge crafts TRADE goods. public.storage_put / public.storage_take name the two storage halves cmd.do_store and cmd.do_take already performed (each re-cut by its hunks, reversed to its pre-image, ACL unmoved); world.snapshot().goods[] and every world.market() row carry tier / is_raw from the catalogue; world.goods_forge lists every crafted good with its recipe and what is ashore, and is registered beside cmd.forge_good (registry % -> %). PROVEN through the one door, rolled back: the recipe''s ingredients leave the shed by exactly its quantities, the product lands with the ingredients'' 3.50 basis, no ducat moves, one FORGED event; a short batch refuses E_NO_MATERIALS without moving anything, a raw good E_NOT_FORGEABLE, a forge with no fleet here E_NOT_DOCKED; the shed''s cap still refuses E_SHED_FULL and storage_take never removes more than is there. The reverse restores the snapshot payload byte for byte and the registry count',
    (select entry_points from pre_0281), (select count(*) from public.client_rpc_entry_points());
end $$;
