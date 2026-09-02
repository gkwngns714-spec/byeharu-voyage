// Emits migration 0072 from data/hulls.json, for the reason scripts/build-fittings-0068.mjs states.
import fs from 'node:fs'

const hulls = JSON.parse(fs.readFileSync('data/hulls.json', 'utf8')).hulls
const goods = new Set(JSON.parse(fs.readFileSync('data/goods.json', 'utf8')).goods.map((g) => g.id))
const items = new Set(JSON.parse(fs.readFileSync('data/fittings.json', 'utf8')).fittings.map((f) => f.code))

const q = (s) => `'${String(s).replace(/'/g, "''")}'`

for (const h of hulls) {
  for (const g of h.goods) if (!goods.has(g.in)) throw new Error(`${h.class} wants good "${g.in}", which data/goods.json does not define`)
  for (const i of h.items) if (!items.has(i.in)) throw new Error(`${h.class} wants fitting "${i.in}", which data/fittings.json does not define`)
  if (h.goods.length < 2 || h.items.length < 1) throw new Error(`${h.class}: a hull is timber AND fittings (row 58)`)
}

const hullRows = hulls
  .map((h) => `  (${q(h.class)}, ${h.yard_tier}, ${h.ducats}, ${q(h.note)})`)
  .join(',\n')

const goodRows = hulls
  .flatMap((h) => h.goods.map((g) => `  (${q(h.class)}, ${q(g.in)}, ${g.qty})`))
  .join(',\n')

const itemRows = hulls
  .flatMap((h) => h.items.map((i) => `  (${q(h.class)}, ${q(i.in)}, ${i.qty})`))
  .join(',\n')

const SQL = `-- ===============================================================================================
-- 0072 - A HULL IS BUILT, NOT BOUGHT
-- ===============================================================================================
--
-- The owner, 2026-09-01:
--
--     "i want another building - a 건조소 in korean, where you can create ships. Building ships will
--      require not only some of the trading goods, but some items will be earned when a successful
--      trade is made."
--
-- -- THE CHAIN CLOSES HERE ----------------------------------------------------------------------
--
--     trade goods --> WORKSTATION --> fittings --> BUILDING YARD --> hull
--
-- 0068 built the middle of that sentence and said so: fittings could be MADE and not yet spent.
-- This is what spends them. A hull is timber AND fittings AND the yard's labour - the owner's
-- "not only some of the trading goods, but some items", which is one requirement and not two.
--
-- -- WHERE THE MATERIALS COME FROM, AND WHY IT MATTERS ------------------------------------------
-- OUT OF THE WAREHOUSE IN THE YARD'S OWN CITY (0070), never out of a hold. A nau wants 255 units
-- of timber and iron - 357 tuns of it - and no ship afloat in this game carries that. So you ferry
-- it in over several voyages and leave it ashore, which is the first thing in this game that makes
-- a warehouse worth having and the reason storage was built before this.
--
-- The fittings come from the same city for the same reason: 0068 made an item OWNED, COUNTED and
-- STANDING AT A PORT. A suit of sails made at Bilbao is at Bilbao. Building a hull somewhere else
-- means carrying it there.
--
-- -- WHY THE DUCATS ARE SMALL --------------------------------------------------------------------
-- ship_classes.build_cost is what a hull costs if you simply BUY one - 12,000 d. for a barca,
-- 120,000 for a nau. Here you bring the materials and pay for the WORK, which is roughly a
-- quarter. Charging both would mean the materials cost you nothing and the yard is a shop.
--
-- -- THE TIER DECIDES WHAT CAN BE LAID DOWN ------------------------------------------------------
-- Every one of the 35 harbours that keeps a building yard is size 5 (they are chosen by
-- ports.yard_tier, the authored shipbuilding column), so SIZE cannot tell them apart - a rule keyed
-- on it would give all 35 the same tier and the tier would mean nothing. dev_industry does vary,
-- and it is the same axis the workstation reads: a city lays down a nau because it can work that
-- much timber and iron, not because a list names it.
--
-- The thresholds are MEASURED against those 35 rather than picked. Their industry runs 10 to 19,
-- and 15 / 12 cuts them 7 / 18 / 10 - seven yards in the world good enough for a nau, ten that lay
-- down nothing bigger than a coaster. The workstation's own 13 / 9 was tried first and gave ZERO
-- tier-1 yards, which the self-assert below refused: a tier every city passes is decoration.
--
-- -- WHAT THIS SLICE DOES NOT DO -----------------------------------------------------------------
-- No fitting is MOUNTED on the hull it helped build - the ten ship stats and the slots-by-tier
-- table are their own slice (DESIGN 1.5), and a fitting spent here is spent as a MATERIAL. The
-- hull arrives with her class's own numbers, exactly as a founding ship does.
-- ===============================================================================================

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
      raise exception '0072 slice: hunk % of % occurs % time(s) in %, expected exactly 1 - the deployed body is not what this migration was generated against.',
        (v_i + 1) / 2, (array_length(p_edits, 1)) / 2, v_n, p_fn;
    end if;
    v_def := replace(v_def, p_edits[v_i], p_edits[v_i + 1]);
    v_i := v_i + 2;
  end loop;
  if p_drop then execute format('drop function %s', p_fn::text); end if;
  execute v_def;
end $fn$;

create temporary table defs_before_0072 as
  select 'cmd.verb_schema'::text as fn, pg_get_functiondef('cmd.verb_schema()'::regprocedure) as def;

-- -- 1. WHAT A HULL IS MADE OF -------------------------------------------------------------------
create table if not exists public.hull_recipes (
  class_code text primary key references public.ship_classes(code),
  yard_tier  int  not null check (yard_tier between 1 and 5),
  ducats     bigint not null check (ducats >= 0),
  note       text not null check (length(note) > 12)
);

create table if not exists public.hull_recipe_goods (
  class_code text not null references public.hull_recipes(class_code) on delete cascade,
  good_id    uuid not null references public.goods(id),
  qty        numeric(10,2) not null check (qty > 0),
  primary key (class_code, good_id)
);

create table if not exists public.hull_recipe_items (
  class_code text not null references public.hull_recipes(class_code) on delete cascade,
  item_code  text not null references public.item_kinds(code),
  qty        int  not null check (qty > 0),
  primary key (class_code, item_code)
);

comment on table public.hull_recipes is
  'What a hull is laid down from: timber out of the city''s warehouse, fittings out of the same '
  'city''s store, and the yard''s labour in ducats. Authored in data/hulls.json and guarded.';

insert into public.hull_recipes (class_code, yard_tier, ducats, note) values
${hullRows}
on conflict (class_code) do update set yard_tier = excluded.yard_tier, ducats = excluded.ducats, note = excluded.note;

create temporary table want_hull_goods_0072 (class_code text, good_code text, qty numeric);
insert into want_hull_goods_0072 (class_code, good_code, qty) values
${goodRows};

insert into public.hull_recipe_goods (class_code, good_id, qty)
select w.class_code, g.id, w.qty from want_hull_goods_0072 w join public.goods g on g.code = w.good_code
on conflict (class_code, good_id) do update set qty = excluded.qty;

insert into public.hull_recipe_items (class_code, item_code, qty) values
${itemRows}
on conflict (class_code, item_code) do update set qty = excluded.qty;

alter table public.hull_recipes      enable row level security;
alter table public.hull_recipe_goods enable row level security;
alter table public.hull_recipe_items enable row level security;
drop policy if exists hull_recipes_read on public.hull_recipes;
create policy hull_recipes_read on public.hull_recipes for select to anon, authenticated using (true);
drop policy if exists hull_recipe_goods_read on public.hull_recipe_goods;
create policy hull_recipe_goods_read on public.hull_recipe_goods for select to anon, authenticated using (true);
drop policy if exists hull_recipe_items_read on public.hull_recipe_items;
create policy hull_recipe_items_read on public.hull_recipe_items for select to anon, authenticated using (true);

-- -- 2. WHICH CITIES LAY DOWN A HULL --------------------------------------------------------------
-- ports.yard_tier is the AUTHORED shipbuilding column (data/ports.json) and 0067 already reads it
-- for the repair yard. A building yard stands where a city genuinely builds - yard_tier 3 - and how
-- BIG a hull it can lay down comes from dev_industry, because all 35 of those harbours are size 5
-- and size therefore cannot tell them apart.
insert into public.port_buildings (port_id, kind, tier)
select p.id, 'building_yard',
       case when p.dev_industry >= 15 then 3
            when p.dev_industry >= 12 then 2
            else 1 end
  from public.ports p
 where p.kind = 'HARBOUR' and p.yard_tier >= 3
on conflict (port_id, kind) do update set tier = excluded.tier;

-- -- 3. LAYING ONE DOWN ---------------------------------------------------------------------------
create or replace function cmd.do_build(p_fleet uuid, p_args jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $db$
declare
  f        public.fleets%rowtype;
  c        public.ship_classes%rowtype;
  h        public.hull_recipes%rowtype;
  v_tier   int;
  v_name   text := btrim(coalesce(p_args->>'name', ''));
  v_short  text;
  v_purse  bigint;
  v_ship   uuid;
  r        record;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.status <> 'DOCKED' then
    raise exception 'E_NOT_DOCKED: % is % and a hull is laid down ashore', f.name, f.status using errcode = 'P0001';
  end if;

  select * into c from public.ship_classes where code = p_args->>'class';
  if c.code is null then
    raise exception 'E_NO_SUCH_CLASS: no ship is called "%"', coalesce(p_args->>'class', '') using errcode = 'P0001';
  end if;
  select * into h from public.hull_recipes where class_code = c.code;
  if h.class_code is null then
    raise exception 'E_NOT_BUILDABLE: % is not a hull any yard lays down', c.name using errcode = 'P0001';
  end if;

  select b.tier into v_tier from public.port_buildings b
   where b.port_id = f.port_id and b.kind = 'building_yard';
  if v_tier is null then
    raise exception 'E_NO_BUILDING_YARD: this city lays down no hulls' using errcode = 'P0001';
  end if;
  if v_tier < h.yard_tier then
    raise exception 'E_YARD_TOO_SMALL: a % wants a tier % yard and this one is tier %',
      c.name, h.yard_tier, v_tier using errcode = 'P0001';
  end if;

  -- A NAME IS THE PLAYER'S, and the same rule the founding ship is held to (0004).
  if length(v_name) < 3 or length(v_name) > 24 then
    raise exception 'E_PARSE: a ship is named in 3 to 24 letters' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.ships s where s.player_id = f.player_id and lower(s.name) = lower(v_name)) then
    raise exception 'E_NAME_TAKEN: you already keep a ship called %', v_name using errcode = 'P0001';
  end if;

  -- THE TIMBER, out of THIS city's shed. Named in full when short, because "you are short of
  -- materials" is the sentence that sends a player to count crates by hand.
  select string_agg(format('%s (%s of %s)', g.name,
                           trim(to_char(coalesce(ps.qty, 0), 'FM999999.99')),
                           trim(to_char(hg.qty, 'FM999999.99'))), ', ' order by g.name)
    into v_short
    from public.hull_recipe_goods hg
    join public.goods g on g.id = hg.good_id
    left join public.player_storage ps
      on ps.player_id = f.player_id and ps.port_id = f.port_id and ps.good_id = hg.good_id
   where hg.class_code = c.code and coalesce(ps.qty, 0) < hg.qty;
  if v_short is not null then
    raise exception 'E_NO_TIMBER: the shed here is short of %', v_short using errcode = 'P0001';
  end if;

  -- AND THE FITTINGS, standing in the same city (0068).
  select string_agg(format('%s (%s of %s)', k.name,
                           coalesce(pi.qty, 0), hi.qty), ', ' order by k.name)
    into v_short
    from public.hull_recipe_items hi
    join public.item_kinds k on k.code = hi.item_code
    left join public.player_items pi
      on pi.player_id = f.player_id and pi.port_id = f.port_id and pi.item_code = hi.item_code
   where hi.class_code = c.code and coalesce(pi.qty, 0) < hi.qty;
  if v_short is not null then
    raise exception 'E_NO_FITTINGS: you keep no % in this city', v_short using errcode = 'P0001';
  end if;

  select ducats into v_purse from public.players where id = f.player_id;
  if v_purse < h.ducats then
    raise exception 'E_NO_FUNDS: the yard asks % d. for the work and you hold %', h.ducats, v_purse
      using errcode = 'P0001';
  end if;

  -- SPEND. The shed and the store first, so a purse check that passed cannot leave a hull half paid
  -- for: any refusal after this point rolls the whole order back (0007's one-transaction rule).
  for r in select hg.good_id, hg.qty from public.hull_recipe_goods hg where hg.class_code = c.code loop
    update public.player_storage set qty = qty - r.qty
     where player_id = f.player_id and port_id = f.port_id and good_id = r.good_id;
  end loop;
  delete from public.player_storage where player_id = f.player_id and port_id = f.port_id and qty <= 0;

  for r in select hi.item_code, hi.qty from public.hull_recipe_items hi where hi.class_code = c.code loop
    update public.player_items set qty = qty - r.qty
     where player_id = f.player_id and port_id = f.port_id and item_code = r.item_code;
  end loop;
  delete from public.player_items where player_id = f.player_id and port_id = f.port_id and qty <= 0;

  -- The ONE money mover, and the ONE record (0004). There is no debit function in this game: a payment is
  -- a credit of a NEGATIVE amount, so the ledger has one direction and one function, and every
  -- movement in the book is the same shape.
  perform public.credit(f.player_id, 'BUILD', -h.ducats,
    public.emit_event(f.player_id, 'HULL_LAID_DOWN', jsonb_build_object(
      'fleet', f.name, 'ship', v_name, 'class', c.name, 'ducats', h.ducats)));

  -- SHE JOINS THE FLEET LYING HERE. The ship_max trigger (0021) is what refuses a ninth hull, and
  -- it is not re-implemented here: one cap, one place.
  insert into public.ships (player_id, fleet_id, class_id, name, durability, crew,
                            water_t, food_t, store_ratio, is_flagship)
  values (f.player_id, p_fleet, c.id, v_name, c.durability, 0,
          0, 0, public.wc_num('store_ratio_default'), false)
  returning id into v_ship;

  return jsonb_build_object('ship', v_ship, 'name', v_name, 'class', c.code,
                            'fleet', f.name, 'ducats', h.ducats);
end $db$;

revoke all on function cmd.do_build(uuid, jsonb) from public, anon, authenticated;

-- -- 4. ONE MORE WORD ------------------------------------------------------------------------------
-- BUILD <class> <name...>. The name runs to the end of the line and may hold spaces, which is why
-- it is not folded into the BUY/STORE shape: those take a quantity, and a quantity is one token.
select pg_temp.recut('cmd.parse(uuid, uuid, text)'::regprocedure, false,
  $g0$  if v_verb not in ('SAIL','BUY','SELL','PROVISION','HIRE','REPAIR','MAKE','STORE','TAKE','CANCEL','CLEAR') then$g0$,
  $g1$  if v_verb not in ('SAIL','BUY','SELL','PROVISION','HIRE','REPAIR','MAKE','STORE','TAKE','BUILD','CANCEL','CLEAR') then$g1$,
  $g2$  elsif v_verb = 'MAKE' then$g2$,
  $g3$  elsif v_verb = 'BUILD' then
    if i > n then
      raise exception 'E_PARSE: BUILD needs a kind of ship' using errcode = 'P0001';
    end if;
    v_args := jsonb_build_object('class', cmd.resolve_class(t[i]));
    i := i + 1;
    if i > n then
      raise exception 'E_PARSE: BUILD needs a name for her' using errcode = 'P0001';
    end if;
    v_args := v_args || jsonb_build_object('name', btrim(array_to_string(t[i:n], ' ')));
    i := n + 1;

  elsif v_verb = 'MAKE' then$g3$);

create or replace function cmd.resolve_class(p_text text)
returns text
language plpgsql
stable
as $rc$
declare
  v_needle text := cmd.fold(p_text);
  v_hits   text[];
begin
  select array_agg(code order by code) into v_hits from public.ship_classes
   where cmd.fold(code) = v_needle or cmd.fold(name) = v_needle;
  if array_length(v_hits, 1) = 1 then return v_hits[1]; end if;

  select array_agg(code order by code) into v_hits from public.ship_classes
   where cmd.fold(code) like '%' || v_needle || '%' or cmd.fold(name) like '%' || v_needle || '%';
  if v_hits is null or array_length(v_hits, 1) = 0 then
    raise exception 'E_NO_SUCH_CLASS: no ship is called "%"', p_text using errcode = 'P0001';
  end if;
  if array_length(v_hits, 1) > 1 then
    raise exception 'E_AMBIGUOUS: "%" could be %', p_text,
      (select string_agg(sc.name, ', ' order by sc.name) from public.ship_classes sc where sc.code = any(v_hits))
      using errcode = 'P0001';
  end if;
  return v_hits[1];
end $rc$;

revoke all on function cmd.resolve_class(text) from public, anon, authenticated;

select pg_temp.recut('cmd.verb_schema()'::regprocedure, false,
  $v0$    {"verb":"REPAIR","args":[$v0$,
  $v1$    {"verb":"BUILD","args":[
       {"name":"fleet","type":"fleet","required":false},
       {"name":"class","type":"ship_class","required":true},
       {"name":"name","type":"text","required":true}],
     "help":"Lay down a new hull, out of what you keep in this city.",
     "note":"Only at a city with a building yard good enough for her. The timber comes out of the warehouse here and the fittings out of your store here - not out of a hold."},
    {"verb":"REPAIR","args":[$v1$);

select pg_temp.recut('cmd.execute_order(uuid)'::regprocedure, false,
  $e0$               when 'TAKE'      then cmd.do_take(o.fleet_id, o.args)$e0$,
  $e1$               when 'TAKE'      then cmd.do_take(o.fleet_id, o.args)
               when 'BUILD'     then cmd.do_build(o.fleet_id, o.args)$e1$);

select pg_temp.recut('cmd.preview(uuid, text, jsonb)'::regprocedure, false,
  $p0$               when 'TAKE'      then cmd.do_take((v_parsed->>'fleet_id')::uuid, v_parsed->'args')$p0$,
  $p1$               when 'TAKE'      then cmd.do_take((v_parsed->>'fleet_id')::uuid, v_parsed->'args')
               when 'BUILD'     then cmd.do_build((v_parsed->>'fleet_id')::uuid, v_parsed->'args')$p1$);

-- -- 5. WHAT THE YARD SERVES -----------------------------------------------------------------------
create or replace function world.building_yard(p_port uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $by$
declare
  v_player uuid := (select id from public.players where auth_uid = auth.uid());
  v_tier   int;
begin
  select b.tier into v_tier from public.port_buildings b
   where b.port_id = p_port and b.kind = 'building_yard';

  return jsonb_build_object(
    'port_id', p_port,
    'tier', v_tier,
    'hulls', (select coalesce(jsonb_agg(jsonb_build_object(
        'class', c.code, 'name', c.name, 'tier', c.tier, 'note', h.note,
        'yard_tier', h.yard_tier, 'ducats', h.ducats,
        'hold', c.hold, 'speed_kn', c.speed_kn, 'crew_required', c.crew_required,
        'durability', c.durability, 'draft', c.draft,
        'buildable', v_tier is not null and v_tier >= h.yard_tier,
        -- WHAT IS ASHORE AGAINST WHAT SHE WANTS, both halves, so the screen states a shortfall
        -- rather than working one out. The rule is cmd.do_build's and this is a reading of it.
        --
        -- ONE SHAPE for timber and fittings alike - code, name, qty, have - because the screen
        -- draws them as one list of materials and a second shape would be a second renderer.
        'goods', (select coalesce(jsonb_agg(jsonb_build_object(
            'code', g.code, 'name', g.name, 'qty', hg.qty,
            'have', coalesce((select ps.qty from public.player_storage ps
                                 where ps.player_id = v_player and ps.port_id = p_port
                                   and ps.good_id = hg.good_id), 0))
            order by g.name), '[]'::jsonb)
          from public.hull_recipe_goods hg join public.goods g on g.id = hg.good_id
         where hg.class_code = h.class_code),
        'items', (select coalesce(jsonb_agg(jsonb_build_object(
            'code', k.code, 'name', k.name, 'qty', hi.qty,
            'have', coalesce((select pi.qty from public.player_items pi
                               where pi.player_id = v_player and pi.port_id = p_port
                                 and pi.item_code = hi.item_code), 0))
            order by k.name), '[]'::jsonb)
          from public.hull_recipe_items hi join public.item_kinds k on k.code = hi.item_code
         where hi.class_code = h.class_code))
        order by h.yard_tier, c.name), '[]'::jsonb)
      from public.hull_recipes h join public.ship_classes c on c.code = h.class_code));
end $by$;

grant execute on function world.building_yard(uuid) to authenticated;

-- -- SELF-ASSERT ------------------------------------------------------------------------------------
do $$
declare
  v_player uuid;
  v_fleet  uuid;
  v_port   uuid;
  v_res    jsonb;
  v_yards  int;
  v_y1     int;
  v_y3     int;
  v_bad    int;
  v_ships  int;
  v_before text;
  v_purse  bigint;
  v_grants int;
  c_uid constant uuid := '00000000-0072-4000-8000-000000000001';
  r        record;
begin
  -- (a) THE THREE HULLS ARE AUTHORED, AND EACH IS TIMBER AND FITTINGS BOTH. Row 58 says "not only
  --     some of the trading goods, but some items" - one requirement, and a hull that wanted only
  --     goods would quietly make 0068's fittings optional again.
  if (select count(*) from public.hull_recipes) <> 3 then
    raise exception '0072 self-assert FAIL: % hull recipe(s), expected 3', (select count(*) from public.hull_recipes);
  end if;
  select count(*) into v_bad from public.hull_recipes h
   where not exists (select 1 from public.hull_recipe_goods g where g.class_code = h.class_code)
      or not exists (select 1 from public.hull_recipe_items i where i.class_code = h.class_code);
  if v_bad <> 0 then
    raise exception '0072 self-assert FAIL: % hull(s) are not timber AND fittings', v_bad;
  end if;

  -- (b) NO DEAD INGREDIENT, the class that cost the owner two hulls in their other game. Every
  --     good must be SOLD somewhere and every fitting must be MAKEABLE somewhere.
  select count(*) into v_bad from public.hull_recipe_goods hg
   where not exists (select 1 from public.port_goods pg join public.ports p on p.id = pg.port_id
                      where pg.good_id = hg.good_id and public.port_offers(p.id, hg.good_id));
  if v_bad <> 0 then
    raise exception '0072 self-assert FAIL: % hull material(s) are sold in NO city', v_bad;
  end if;
  select count(*) into v_bad from public.hull_recipe_items hi
    join public.item_kinds k on k.code = hi.item_code
   where not exists (select 1 from public.port_buildings b
                      where b.kind = 'workstation' and b.tier >= k.ws_tier);
  if v_bad <> 0 then
    raise exception '0072 self-assert FAIL: % hull fitting(s) can be made in no city', v_bad;
  end if;

  -- (c) THE YARDS LANDED AND THEIR TIERS DIFFER, or the tier is decoration and every hull is
  --     reachable at every yard.
  select count(*) into v_yards from public.port_buildings where kind = 'building_yard';
  select count(*) into v_y1 from public.port_buildings where kind = 'building_yard' and tier = 1;
  select count(*) into v_y3 from public.port_buildings where kind = 'building_yard' and tier >= 3;
  if v_yards = 0 then
    raise exception '0072 self-assert FAIL: not one city lays down a hull';
  end if;
  if v_y3 = 0 then
    raise exception '0072 self-assert FAIL: no yard is good enough for a nau, so one hull is unreachable';
  end if;
  if v_y1 = 0 then
    raise exception '0072 self-assert FAIL: every yard is a great one - the tier says nothing';
  end if;

  -- (d) A HULL FITS IN THE SHED IT IS BUILT FROM. The materials come out of a warehouse, and a
  --     recipe that wants more tuns than the biggest shed in the world holds is a recipe nobody
  --     can ever fill - content that looks real and is not.
  select count(*) into v_bad from (
    select h.class_code, sum(hg.qty * g.bulk) tuns
      from public.hull_recipes h
      join public.hull_recipe_goods hg on hg.class_code = h.class_code
      join public.goods g on g.id = hg.good_id
     group by h.class_code) x
   where x.tuns > (select max(public.storage_cap(b.port_id)) from public.port_buildings b
                    where b.kind = 'building_yard');
  if v_bad <> 0 then
    raise exception '0072 self-assert FAIL: % hull(s) want more timber than any yard city can store', v_bad;
  end if;

  -- (e) IT WORKS, END TO END, THROUGH THE ONE DOOR - and the materials really leave.
  v_player := public.new_house(c_uid, 'Casa Estaleiro', 'PRT');
  select id into v_fleet from public.fleets where player_id = v_player;
  perform cmd.assume_identity(c_uid);

  select b.port_id into v_port from public.port_buildings b
   where b.kind = 'building_yard' and b.tier >= 1 order by b.port_id limit 1;
  update public.fleets set port_id = v_port where id = v_fleet;

  -- Put the barca's materials ashore directly: what is under test is the BUILDING, and buying and
  -- ferrying them would drag the whole market and the mover into a proof about a yard.
  insert into public.player_storage (player_id, port_id, good_id, qty)
  select v_player, v_port, hg.good_id, hg.qty from public.hull_recipe_goods hg where hg.class_code = 'barca'
  on conflict (player_id, port_id, good_id) do update set qty = excluded.qty;
  insert into public.player_items (player_id, port_id, item_code, qty)
  select v_player, v_port, hi.item_code, hi.qty from public.hull_recipe_items hi where hi.class_code = 'barca'
  on conflict (player_id, port_id, item_code) do update set qty = excluded.qty;
  -- FUND THE PROBE THROUGH THE LEDGER, not by setting the column. public.players.ducats must equal
  -- the sum of its own ledger movements (0004's honest-ledger invariant, and proof 02 checks it) -
  -- an UPDATE here passed every assert in this block and then failed reconciliation two files
  -- later, which is the trigger doing exactly its job.
  perform public.credit(v_player, 'PROBE_YARD', 42000,
    public.emit_event(v_player, 'PROBE', jsonb_build_object('why', '0072 self-assert')));

  select count(*) into v_ships from public.ships where player_id = v_player;
  v_res := cmd.issue(v_fleet, 'BUILD barca Andorinha', null, null);
  if not (v_res->>'ok')::boolean then
    raise exception '0072 self-assert FAIL: BUILD was refused: %', v_res->'order';
  end if;
  if (select count(*) from public.ships where player_id = v_player) <> v_ships + 1 then
    raise exception '0072 self-assert FAIL: the yard took the timber and launched nothing';
  end if;
  if not exists (select 1 from public.ships where player_id = v_player and name = 'Andorinha') then
    raise exception '0072 self-assert FAIL: she was not given the name she was ordered under';
  end if;
  -- AND THE MATERIALS ARE GONE. A hull built out of nothing is the farm loop every one of these
  -- files is written to refuse, and every count above would still pass.
  if exists (select 1 from public.player_storage where player_id = v_player and port_id = v_port and qty > 0) then
    raise exception '0072 self-assert FAIL: the timber is still in the shed - the hull was built out of nothing';
  end if;
  if exists (select 1 from public.player_items where player_id = v_player and port_id = v_port and qty > 0) then
    raise exception '0072 self-assert FAIL: the fittings are still in store';
  end if;
  select ducats into v_purse from public.players where id = v_player;
  if v_purse <> 50000 - (select ducats from public.hull_recipes where class_code = 'barca') then
    raise exception '0072 self-assert FAIL: the yard was paid % rather than its price', 50000 - v_purse;
  end if;

  -- (f) AND IT REFUSES: the same line, with an empty shed.
  perform cmd.clear(v_fleet, true);
  v_res := cmd.issue(v_fleet, 'BUILD barca Segunda', null, null);
  if (v_res->>'ok')::boolean then
    raise exception '0072 self-assert FAIL: a second hull came out of an empty shed';
  end if;
  if v_res->'refusal'->>'code' <> 'E_NO_TIMBER' then
    raise exception '0072 self-assert FAIL: an empty shed refused with % rather than E_NO_TIMBER',
      v_res->'refusal'->>'code';
  end if;

  -- (g) A CITY WITHOUT A YARD REFUSES.
  select p.id into v_port from public.ports p
   where p.kind = 'HARBOUR'
     and not exists (select 1 from public.port_buildings b where b.port_id = p.id and b.kind = 'building_yard')
   order by p.code limit 1;
  update public.fleets set port_id = v_port where id = v_fleet;
  perform cmd.clear(v_fleet, true);
  v_res := cmd.issue(v_fleet, 'BUILD barca Terceira', null, null);
  if (v_res->>'ok')::boolean or v_res->'refusal'->>'code' <> 'E_NO_BUILDING_YARD' then
    raise exception '0072 self-assert FAIL: a city with no yard answered % rather than E_NO_BUILDING_YARD',
      coalesce(v_res->'refusal'->>'code', 'ok');
  end if;

  -- (h) THE GRAMMAR GREW BY EXACTLY ONE WORD.
  select def into v_before from defs_before_0072 where fn = 'cmd.verb_schema';
  if position('BUILD' in v_before) <> 0 then
    raise exception '0072 self-assert FAIL: the pre-image already knew BUILD';
  end if;
  if jsonb_array_length(cmd.verb_schema()) <> 12 then
    raise exception '0072 self-assert FAIL: the grammar serves % verbs, expected 12', jsonb_array_length(cmd.verb_schema());
  end if;

  -- (i) POSTURE.
  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0072 self-assert FAIL: % client write grant(s)', v_grants;
  end if;

  raise notice '0072 self-assert ok: A HULL IS BUILT, NOT BOUGHT. The chain the owner asked for closes - trade goods to a workstation to fittings to a YARD to a hull - and every one of the 3 hulls is timber AND fittings both, which is what row 58 asked for as one requirement rather than two. No dead ingredient: every material is sold somewhere and every fitting can be made somewhere. % cities lay down hulls, % of them well enough for a nau and % only for a coaster, so the tier decides what can be laid down rather than decorating a row. Every recipe FITS IN A SHED: the materials come out of the warehouse in the yard''s own city, which is what makes storage worth having and why it was built first. It works END TO END through the one door: a house with the timber ashore and the fittings in store typed BUILD barca Andorinha, she was launched under that name, the yard was paid its labour - and the shed and the store are EMPTY, so nothing was built out of nothing. The same line then refused E_NO_TIMBER on an empty shed and E_NO_BUILDING_YARD at a city that lays down none. The grammar grew by exactly one word, from 11 verbs to 12; 0 client write grants.',
    v_yards, v_y3, v_y1;
end $$;
`

fs.writeFileSync('supabase/migrations/20260818000072_a_hull_is_built_not_bought.sql', SQL)
console.log('wrote 0072:', hulls.length, 'hulls,',
  hulls.reduce((n, h) => n + h.goods.length, 0), 'material lines,',
  hulls.reduce((n, h) => n + h.items.length, 0), 'fitting lines')
