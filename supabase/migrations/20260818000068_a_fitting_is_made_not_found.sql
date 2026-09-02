-- ===============================================================================================
-- 0068 - A FITTING IS MADE, NOT FOUND
-- ===============================================================================================
--
-- The owner, 2026-09-01, on the ship they want to design:
--
--     "each ship will have slots for items equipment, such as sail, anchor, and more. Make 12 item
--      (선수상 etc - in english) so that we can design our own ship."
--
-- and, on where those items come from:
--
--     "a workstation where you can create ship related items - sail etc."
--
-- -- THE GAME HAS NEVER HAD A THING YOU OWN N OF ------------------------------------------------
-- Ducats, cargo, crew and stores are all CONTINUOUS. `player_officers` owns a row and
-- `player_skills` owns a level; nothing owns a countable stack of a discrete thing. This is that
-- table, and the twelve fittings are what fills it.
--
-- -- WHERE THEY COME FROM, WHICH IS THE WHOLE POINT ---------------------------------------------
--
--     trade goods --> WORKSTATION --> fitting
--
-- Not a drop, not a reward, not a random find. You make a suit of sails out of six tuns of flax,
-- two of cordage and one of tar, standing at a city whose workstation is good enough to do it. That
-- answers "what stops items being farmed" with the only answer this game accepts: you farm them by
-- TRADING, which is the game. Nothing is granted (DESIGN 8's rule, applied one layer out).
--
-- -- EVERY FITTING BUYS ONE STAT AND SPENDS ANOTHER ---------------------------------------------
-- DESIGN 1.3. Without it "design your own ship" means "fit everything", and the best ship is the
-- one with the most slots. The buys/spends pair is carried on the row from the first day, even
-- though the stats it names are stage 2 - so the catalogue can never be authored as a shopping
-- list and then have the rule bolted on afterwards.
--
-- The figurehead spends nothing but ducats, deliberately: every catalogue needs one flourish a
-- player buys because they want to.
--
-- -- WHAT AN ITEM IS, EXACTLY -------------------------------------------------------------------
-- Owned by a PLAYER, standing at a PORT, counted. The location is not decoration: it is the
-- owner's own law from their other game - *items have VOLUME and a LOCATION; storage is PER-PORT;
-- reachable only while DOCKED there*. A fitting made at Bilbao is at Bilbao. The warehouse slice
-- gives that a cap and a screen; the law is here from the start because retrofitting a location
-- onto a global stash is the migration nobody wants to write.
--
-- -- WHAT THIS SLICE DELIBERATELY DOES NOT DO ---------------------------------------------------
-- No fitting is MOUNTED on a ship yet, no stat moves, and no hull is built from one. Slots by tier
-- and the ten ship stats are stage 2 (DESIGN 1.5), the building yard is its own slice, and DESIGN
-- 11 is explicit that a half-built system is worse than none. What lands here is whole: the
-- catalogue exists, cities can make them, a player owns them and can see them.
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
      raise exception '0068 slice: hunk % of % occurs % time(s) in %, expected exactly 1 - the deployed body is not what this migration was generated against.',
        (v_i + 1) / 2, (array_length(p_edits, 1)) / 2, v_n, p_fn;
    end if;
    v_def := replace(v_def, p_edits[v_i], p_edits[v_i + 1]);
    v_i := v_i + 2;
  end loop;
  if p_drop then execute format('drop function %s', p_fn::text); end if;
  execute v_def;
end $fn$;

create temporary table defs_before_0068 as
  select 'cmd.parse'::text as fn, pg_get_functiondef('cmd.parse(uuid, uuid, text)'::regprocedure) as def
  union all select 'cmd.verb_schema', pg_get_functiondef('cmd.verb_schema()'::regprocedure);

-- -- 1. THE TWELVE, AS A CATALOGUE ---------------------------------------------------------------
create table if not exists public.item_kinds (
  code    text primary key,
  name    text not null,
  slot    text not null,
  buys    text not null check (length(buys) > 2),
  spends  text not null check (length(spends) > 2),
  note    text not null check (length(note) > 12),
  volume  numeric(6,2) not null check (volume > 0),
  ws_tier int not null check (ws_tier between 1 and 5)
);

comment on table public.item_kinds is
  'The fittings a ship can carry, one row each. buys/spends are DESIGN 1.3 carried on the row: '
  'every fitting buys one stat and spends another, so the catalogue cannot be authored as a '
  'shopping list. ws_tier is the workstation a city needs to make it.';

insert into public.item_kinds (code, name, slot, buys, spends, note, volume, ws_tier) values
  ('suit-of-sails', 'Suit of Sails', 'rig', 'Speed', 'Handling', 'More canvas drives her harder and answers the helm worse.', 4, 1),
  ('bowsprit-and-jib', 'Bowsprit & Jib', 'rig', 'Handling, and a little Speed', 'Durability', 'Sail forward of the stem turns her quickly and is the first thing carried away.', 3, 2),
  ('rudder-and-helm', 'Rudder & Helm', 'steering', 'Handling', 'Hold', 'The gear takes room aft that cargo wanted.', 3, 2),
  ('anchor-and-cable', 'Anchor & Cable', 'ground-tackle', 'Weather-holding, and a faster turnaround in port', 'Hold', 'Ground tackle is dead weight until the night it is the only thing between her and a lee shore.', 4, 1),
  ('ballast', 'Ballast', 'hull', 'Handling, Armour', 'Speed', 'Weight low down makes her stiff and slow.', 2, 1),
  ('copper-sheathing', 'Copper Sheathing', 'hull', 'Armour, Durability', 'Speed', 'Worm and weed stop at copper; so does a little of her way through the water.', 5, 3),
  ('broadside-guns', 'Broadside Guns', 'weapon', 'Attack, Reach', 'Hold, Handling', 'A gun deck is cargo space that shoots back.', 6, 3),
  ('boarding-gear', 'Boarding Gear', 'weapon', 'Attack at close quarters', 'Reach', 'Grapnels and pikes pull her toward the fight she wants to have.', 3, 1),
  ('powder-magazine', 'Powder Magazine', 'weapon', 'Attack sustain, Accuracy', 'Hold, Durability', 'It can go up, and a ship that fires all day needs one anyway.', 4, 3),
  ('crows-nest', 'Crow''s Nest', 'lookout', 'Sighting', 'Handling', 'Weight aloft costs her a little of the helm and buys the horizon.', 2, 1),
  ('hold-fittings', 'Hold Fittings', 'hull', 'Hold', 'Speed, Handling', 'Shelving, dunnage and a tighter stow — more cargo, carried heavier.', 3, 2),
  ('figurehead', 'Figurehead', 'flourish', 'Crew morale, and fame', 'Nothing but ducats', 'The one fitting that costs no stat, deliberately: it is the flourish a player buys because they want to, and every catalogue needs one.', 2, 2)
on conflict (code) do update set name = excluded.name, slot = excluded.slot, buys = excluded.buys,
  spends = excluded.spends, note = excluded.note, volume = excluded.volume, ws_tier = excluded.ws_tier;

-- -- 2. WHAT EACH ONE IS MADE OF ------------------------------------------------------------------
create table if not exists public.item_recipes (
  item_code text not null references public.item_kinds(code) on delete cascade,
  good_id   uuid not null references public.goods(id),
  qty       numeric(8,2) not null check (qty > 0),
  primary key (item_code, good_id)
);

comment on table public.item_recipes is
  'What a fitting is made of: 2-5 trade goods, authored in data/fittings.json and guarded. A '
  'recipe that lived only inside a migration is exactly the drift world-guard exists to kill.';

create temporary table want_recipes_0068 (item_code text, good_code text, qty numeric);
insert into want_recipes_0068 (item_code, good_code, qty) values
  ('suit-of-sails', 'flax', 6),
  ('suit-of-sails', 'cordage', 2),
  ('suit-of-sails', 'tar', 1),
  ('bowsprit-and-jib', 'naval-timber', 3),
  ('bowsprit-and-jib', 'flax', 3),
  ('bowsprit-and-jib', 'cordage', 2),
  ('rudder-and-helm', 'live-oak', 4),
  ('rudder-and-helm', 'ships-nails', 2),
  ('rudder-and-helm', 'lignum-vitae', 1),
  ('anchor-and-cable', 'iron', 4),
  ('anchor-and-cable', 'hemp', 4),
  ('anchor-and-cable', 'tar', 1),
  ('ballast', 'lead', 5),
  ('ballast', 'timber', 2),
  ('copper-sheathing', 'copper-sheet', 6),
  ('copper-sheathing', 'ships-nails', 3),
  ('copper-sheathing', 'tar', 2),
  ('broadside-guns', 'bar-iron', 6),
  ('broadside-guns', 'timber', 2),
  ('broadside-guns', 'ships-nails', 2),
  ('boarding-gear', 'iron', 3),
  ('boarding-gear', 'hemp', 3),
  ('boarding-gear', 'timber', 1),
  ('powder-magazine', 'gunpowder', 4),
  ('powder-magazine', 'live-oak', 3),
  ('powder-magazine', 'copper-sheet', 1),
  ('crows-nest', 'naval-timber', 2),
  ('crows-nest', 'cordage', 2),
  ('crows-nest', 'canvas-duck', 1),
  ('hold-fittings', 'timber', 5),
  ('hold-fittings', 'ships-nails', 3),
  ('hold-fittings', 'oakum', 2),
  ('figurehead', 'cedar', 3),
  ('figurehead', 'tallow', 1),
  ('figurehead', 'lead', 1);

insert into public.item_recipes (item_code, good_id, qty)
select w.item_code, g.id, w.qty from want_recipes_0068 w join public.goods g on g.code = w.good_code
on conflict (item_code, good_id) do update set qty = excluded.qty;

-- -- 3. WHAT A PLAYER OWNS ------------------------------------------------------------------------
create table if not exists public.player_items (
  player_id uuid not null references public.players(id) on delete cascade,
  port_id   uuid not null references public.ports(id),
  item_code text not null references public.item_kinds(code),
  qty       int  not null check (qty >= 0),
  primary key (player_id, port_id, item_code)
);

comment on table public.player_items is
  'A countable stack of a discrete thing, which this game has never had - and it stands at a PORT, '
  'because items have a LOCATION (the owner''s own law): what you made at Bilbao is at Bilbao.';

alter table public.item_kinds   enable row level security;
alter table public.item_recipes enable row level security;
alter table public.player_items enable row level security;

drop policy if exists item_kinds_read on public.item_kinds;
create policy item_kinds_read on public.item_kinds for select to anon, authenticated using (true);
drop policy if exists item_recipes_read on public.item_recipes;
create policy item_recipes_read on public.item_recipes for select to anon, authenticated using (true);
-- YOURS ONLY. The catalogue is public; what you own is not.
drop policy if exists player_items_read on public.player_items;
create policy player_items_read on public.player_items for select to authenticated
  using (player_id = (select p.id from public.players p where p.auth_uid = auth.uid()));

-- -- 4. WHICH CITIES KEEP A WORKSTATION ------------------------------------------------------------
-- 0067 made a building a row and left this kind standing nowhere. A city works metal and timber
-- because it INDUSTRIALLY can, which the world already says in dev_industry (0-20) - so the
-- workstation tier is read off that rather than from a hand-written list of city names. The
-- thresholds are MEASURED against the world's own industry rather than picked: dev_industry runs
-- 4 to 19 across the 224 harbours, and 13 / 9 / 7 cut it into 12 cities that can make the tier-3
-- fittings, 35 more that can make the tier-2, and 24 that can make the plainest - 71 in all, under
-- a third of the world. An earlier 16 / 11 left only FIVE cities able to make copper sheathing,
-- broadside guns or a powder magazine, which is not scarcity, it is content a player never meets.
insert into public.port_buildings (port_id, kind, tier)
select p.id, 'workstation',
       case when p.dev_industry >= 13 then 3
            when p.dev_industry >= 9  then 2
            else 1 end
  from public.ports p
 where p.kind = 'HARBOUR' and p.dev_industry >= 7
on conflict (port_id, kind) do update set tier = excluded.tier;

-- -- 5. NAMING ONE, THE WAY A GOOD IS NAMED --------------------------------------------------------
-- cmd.resolve_good's twin, and deliberately its twin: a player types "sails" and means the suit of
-- sails, exactly as they type "pepper" and mean black pepper. Same folding, same ambiguity refusal,
-- same shape of sentence - because a second way of naming things is a second grammar.
create or replace function cmd.resolve_item(p_text text)
returns text
language plpgsql
stable
as $ri$
declare
  v_needle text := cmd.fold(p_text);
  v_hits   text[];
begin
  select array_agg(code order by code) into v_hits from public.item_kinds
   where cmd.fold(code) = v_needle or cmd.fold(name) = v_needle;
  if array_length(v_hits, 1) = 1 then return v_hits[1]; end if;

  select array_agg(code order by code) into v_hits from public.item_kinds
   where cmd.fold(code) like '%' || v_needle || '%' or cmd.fold(name) like '%' || v_needle || '%';
  if v_hits is null or array_length(v_hits, 1) = 0 then
    raise exception 'E_NO_SUCH_ITEM: nothing is called "%"', p_text using errcode = 'P0001';
  end if;
  if array_length(v_hits, 1) > 1 then
    raise exception 'E_AMBIGUOUS: "%" could be %', p_text,
      (select string_agg(k.name, ', ' order by k.name) from public.item_kinds k where k.code = any(v_hits))
      using errcode = 'P0001';
  end if;
  return v_hits[1];
end $ri$;

revoke all on function cmd.resolve_item(text) from public, anon, authenticated;

-- -- 6. MAKING ONE ----------------------------------------------------------------------------------
create or replace function cmd.do_make(p_fleet uuid, p_args jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $dm$
declare
  f       public.fleets%rowtype;
  k       public.item_kinds%rowtype;
  v_qty   int := greatest(1, coalesce((p_args->>'qty')::int, 1));
  v_tier  int;
  v_short text;
  v_spent jsonb := '[]'::jsonb;
  r       record;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.status <> 'DOCKED' then
    raise exception 'E_NOT_DOCKED: % is % and a fitting is made ashore', f.name, f.status using errcode = 'P0001';
  end if;

  select * into k from public.item_kinds where code = p_args->>'item';
  if k.code is null then
    raise exception 'E_NO_SUCH_ITEM: nothing is called "%"', coalesce(p_args->>'item', '') using errcode = 'P0001';
  end if;

  -- THE BUILDING DECIDES, NOT A LIST OF CITY NAMES (0067). A city makes what its workstation is
  -- good enough to make, which is where "some cities can craft" lives.
  select b.tier into v_tier from public.port_buildings b
   where b.port_id = f.port_id and b.kind = 'workstation';
  if v_tier is null then
    raise exception 'E_NO_WORKSTATION: this city keeps no workstation' using errcode = 'P0001';
  end if;
  if v_tier < k.ws_tier then
    raise exception 'E_WORKSTATION_TOO_SMALL: % needs a tier % workstation and this one is tier %',
      k.name, k.ws_tier, v_tier using errcode = 'P0001';
  end if;

  -- THE MATERIALS COME OUT OF HER HOLD, so a fitting is the far end of a voyage: the inputs are
  -- ship-supplies, and 0065 put every good in one to three cities.
  select string_agg(format('%s (%s of %s)', g.name,
                           trim(to_char(public.fleet_cargo_qty(p_fleet, g.code), 'FM999999.99')),
                           trim(to_char(ir.qty * v_qty, 'FM999999.99'))), ', ' order by g.name)
    into v_short
    from public.item_recipes ir join public.goods g on g.id = ir.good_id
   where ir.item_code = k.code and public.fleet_cargo_qty(p_fleet, g.code) < ir.qty * v_qty;
  if v_short is not null then
    raise exception 'E_NO_MATERIALS: % is short of %', f.name, v_short using errcode = 'P0001';
  end if;

  for r in select g.code, g.name, ir.qty * v_qty as need
             from public.item_recipes ir join public.goods g on g.id = ir.good_id
            where ir.item_code = k.code order by g.code loop
    -- The ONE cargo mover (0007). A second way of taking a good out of a hold is the defect.
    perform public.fleet_unload(p_fleet, r.code, r.need);
    v_spent := v_spent || jsonb_build_object('good', r.code, 'qty', r.need);
  end loop;

  insert into public.player_items (player_id, port_id, item_code, qty)
  values (f.player_id, f.port_id, k.code, v_qty)
  on conflict (player_id, port_id, item_code) do update set qty = public.player_items.qty + excluded.qty;

  perform public.emit_event(f.player_id, 'MADE', jsonb_build_object(
    'fleet', f.name, 'item', k.name, 'qty', v_qty, 'spent', v_spent));

  return jsonb_build_object('item', k.code, 'name', k.name, 'qty', v_qty, 'spent', v_spent);
end $dm$;

revoke all on function cmd.do_make(uuid, jsonb) from public, anon, authenticated;

-- -- 7. THE GRAMMAR GAINS ONE WORD ------------------------------------------------------------------
select pg_temp.recut('cmd.parse(uuid, uuid, text)'::regprocedure, false,
  $g0$  if v_verb not in ('SAIL','BUY','SELL','PROVISION','HIRE','REPAIR','CANCEL','CLEAR') then$g0$,
  $g1$  if v_verb not in ('SAIL','BUY','SELL','PROVISION','HIRE','REPAIR','MAKE','CANCEL','CLEAR') then$g1$,
  $g2$  elsif v_verb = 'HIRE' then$g2$,
  $g3$  elsif v_verb = 'MAKE' then
    -- MAKE <fitting> [count]. The count is optional and defaults to one, because "MAKE sails" is
    -- what a player types and needing "MAKE sails 1" would be the game asking for punctuation.
    if i > n then
      raise exception 'E_PARSE: MAKE needs something to make' using errcode = 'P0001';
    end if;
    v_args := jsonb_build_object('item', cmd.resolve_item(t[i]), 'qty', 1);
    i := i + 1;
    while i <= n loop
      v_num := cmd.parse_number(t[i]);
      if v_num is null or v_num <= 0 then
        raise exception 'E_PARSE: "%" is not a number to make', t[i] using errcode = 'P0001';
      end if;
      v_args := v_args || jsonb_build_object('qty', v_num::int);
      i := i + 1;
    end loop;

  elsif v_verb = 'HIRE' then$g3$);

select pg_temp.recut('cmd.verb_schema()'::regprocedure, false,
  $v0$    {"verb":"REPAIR","args":[$v0$,
  $v1$    {"verb":"MAKE","args":[
       {"name":"fleet","type":"fleet","required":false},
       {"name":"item","type":"item","required":true},
       {"name":"qty","type":"number","required":false}],
     "help":"Make a fitting for a ship out of trade goods in her hold.",
     "note":"Only at a city that keeps a workstation, and only one good enough for that fitting. What you make stays in that city."},
    {"verb":"REPAIR","args":[$v1$);

select pg_temp.recut('cmd.execute_order(uuid)'::regprocedure, false,
  $e0$               when 'REPAIR'    then cmd.do_repair(o.fleet_id, o.args)$e0$,
  $e1$               when 'REPAIR'    then cmd.do_repair(o.fleet_id, o.args)
               when 'MAKE'      then cmd.do_make(o.fleet_id, o.args)$e1$);

select pg_temp.recut('cmd.preview(uuid, text, jsonb)'::regprocedure, false,
  $p0$               when 'REPAIR'    then cmd.do_repair((v_parsed->>'fleet_id')::uuid, v_parsed->'args')$p0$,
  $p1$               when 'REPAIR'    then cmd.do_repair((v_parsed->>'fleet_id')::uuid, v_parsed->'args')
               when 'MAKE'      then cmd.do_make((v_parsed->>'fleet_id')::uuid, v_parsed->'args')$p1$);

-- -- 8. WHAT THE WORKSTATION SERVES -----------------------------------------------------------------
-- One read for the whole face: what this city can make, what each one costs, whether her hold
-- carries it, and what the player already owns HERE. Computed server-side because "can she make
-- this" is a rule, and a client that worked it out from a recipe and a manifest would be the
-- second implementation of it.
create or replace function world.workstation(p_port uuid, p_fleet uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $ws$
declare
  v_player uuid := (select id from public.players where auth_uid = auth.uid());
  v_tier   int;
begin
  select b.tier into v_tier from public.port_buildings b
   where b.port_id = p_port and b.kind = 'workstation';

  return jsonb_build_object(
    'port_id', p_port,
    'tier', v_tier,
    'items', (select coalesce(jsonb_agg(jsonb_build_object(
        'code', k.code, 'name', k.name, 'slot', k.slot, 'buys', k.buys, 'spends', k.spends,
        'note', k.note, 'volume', k.volume, 'ws_tier', k.ws_tier,
        'makeable', v_tier is not null and v_tier >= k.ws_tier,
        'owned_here', coalesce((select pi.qty from public.player_items pi
                                 where pi.player_id = v_player and pi.port_id = p_port
                                   and pi.item_code = k.code), 0),
        'recipe', (select coalesce(jsonb_agg(jsonb_build_object(
            'good', g.code, 'name', g.name, 'qty', ir.qty,
            'aboard', case when p_fleet is null then null
                           else public.fleet_cargo_qty(p_fleet, g.code) end)
            order by g.name), '[]'::jsonb)
          from public.item_recipes ir join public.goods g on g.id = ir.good_id
         where ir.item_code = k.code))
        order by k.ws_tier, k.name), '[]'::jsonb)
      from public.item_kinds k));
end $ws$;

grant execute on function world.workstation(uuid, uuid) to authenticated;

-- -- SELF-ASSERT ------------------------------------------------------------------------------------
do $$
declare
  v_kinds   int;
  v_recipes int;
  v_bad     int;
  v_ws      int;
  v_ws3     int;
  v_probe   uuid;
  v_player  uuid;
  v_fleet   uuid;
  v_port    uuid;
  v_res     jsonb;
  v_code    text;
  v_qty     numeric;
  v_before  text;
  v_grants  int;
  c_uid constant uuid := '00000000-0068-4000-8000-000000000001';
  r         record;
begin
  select count(*) into v_kinds from public.item_kinds;
  select count(*) into v_recipes from public.item_recipes;
  if v_kinds <> 12 then
    raise exception '0068 self-assert FAIL: % fitting(s), and the owner asked for 12', v_kinds;
  end if;

  -- (a) EVERY RECIPE IS 2-5 INPUTS (DESIGN 6.3), counted rather than trusted to the generator.
  select count(*) into v_bad from (
    select item_code, count(*) c from public.item_recipes group by item_code) x
   where x.c < 2 or x.c > 5;
  if v_bad <> 0 then
    raise exception '0068 self-assert FAIL: % recipe(s) are not 2-5 inputs', v_bad;
  end if;

  -- (b) NO RECIPE HAS A DEAD INGREDIENT. The owner's other game lost two hulls to recipes whose
  --     inputs had no live source, and this one had three goods buyable nowhere until 0062 caught
  --     it. Every input must be OFFERED somewhere a player can actually reach.
  select count(*) into v_bad
    from public.item_recipes ir
   where not exists (select 1 from public.port_goods pg
                      join public.ports p on p.id = pg.port_id
                     where pg.good_id = ir.good_id and public.port_offers(p.id, ir.good_id));
  if v_bad <> 0 then
    select string_agg(distinct g.name, ', ') into v_code
      from public.item_recipes ir join public.goods g on g.id = ir.good_id
     where not exists (select 1 from public.port_goods pg
                        join public.ports p on p.id = pg.port_id
                       where pg.good_id = ir.good_id and public.port_offers(p.id, ir.good_id));
    raise exception '0068 self-assert FAIL: % recipe input(s) are sold in NO city: %', v_bad, v_code;
  end if;

  -- (c) THE WORKSTATIONS LANDED, AND ARE NOT EVERYWHERE. A fitting you can make in every harbour
  --     is not made, it is bought; a tier 3 in every harbour would make the tier meaningless.
  select count(*) into v_ws  from public.port_buildings where kind = 'workstation';
  select count(*) into v_ws3 from public.port_buildings where kind = 'workstation' and tier >= 3;
  if v_ws = 0 then
    raise exception '0068 self-assert FAIL: not one city keeps a workstation';
  end if;
  if v_ws >= (select count(*) from public.ports where kind = 'HARBOUR') then
    raise exception '0068 self-assert FAIL: every harbour keeps a workstation, so the building means nothing';
  end if;
  if v_ws3 = 0 then
    raise exception '0068 self-assert FAIL: no city can make the tier-3 fittings, so three of them are unreachable';
  end if;

  -- (d) EVERY FITTING IS REACHABLE. A catalogue entry no city in the world can make is content
  --     that does not exist, and it would sit there looking real.
  select count(*) into v_bad from public.item_kinds k
   where not exists (select 1 from public.port_buildings b
                      where b.kind = 'workstation' and b.tier >= k.ws_tier);
  if v_bad <> 0 then
    raise exception '0068 self-assert FAIL: % fitting(s) can be made in no city', v_bad;
  end if;

  -- (e) IT ACTUALLY WORKS, END TO END, THROUGH THE ONE DOOR. Not "the function exists": a house is
  --     founded, put ashore at a city with a workstation, given the exact materials, and MAKES the
  --     thing by typing a line - and the goods leave her hold.
  v_player := public.new_house(c_uid, 'Casa Ferro', 'PRT');
  select id into v_fleet from public.fleets where player_id = v_player;
  perform cmd.assume_identity(c_uid);

  select b.port_id into v_port from public.port_buildings b where b.kind = 'workstation' and b.tier >= 1
   order by b.port_id limit 1;
  update public.fleets set port_id = v_port where id = v_fleet;

  -- The materials for one suit of sails, put aboard directly: what is under test is the MAKING,
  -- and buying them would drag the whole market into a proof about a workstation.
  for r in select g.code, ir.qty from public.item_recipes ir join public.goods g on g.id = ir.good_id
            where ir.item_code = 'suit-of-sails' loop
    perform public.fleet_load(v_fleet, r.code, r.qty);
  end loop;

  v_res := cmd.issue(v_fleet, 'MAKE sails', null, null);
  if not (v_res->>'ok')::boolean then
    raise exception '0068 self-assert FAIL: MAKE was refused: %', v_res->'refusal';
  end if;
  select qty into v_qty from public.player_items
   where player_id = v_player and port_id = v_port and item_code = 'suit-of-sails';
  if coalesce(v_qty, 0) <> 1 then
    raise exception '0068 self-assert FAIL: after MAKE she owns % suit(s) of sails here', coalesce(v_qty, 0);
  end if;
  -- AND THE MATERIALS ARE GONE. A make that yielded an item without spending the goods would be
  -- the farm loop this design exists to refuse, and every count above would still pass.
  if public.fleet_cargo_qty(v_fleet, 'flax') <> 0 then
    raise exception '0068 self-assert FAIL: the flax is still in her hold - MAKE minted a fitting out of nothing';
  end if;

  -- (f) AND IT REFUSES. Same line, same fleet, no materials left.
  v_res := cmd.issue(v_fleet, 'MAKE sails', null, null);
  if (v_res->>'ok')::boolean then
    raise exception '0068 self-assert FAIL: she made a second suit of sails out of an empty hold';
  end if;
  if v_res->'refusal'->>'code' <> 'E_NO_MATERIALS' then
    raise exception '0068 self-assert FAIL: an empty hold refused with % rather than E_NO_MATERIALS', v_res->'refusal'->>'code';
  end if;

  -- (f) left her HALTED, which is 0008 working: a failed order stops the fleet until it is
  -- released. Without this the next order would be QUEUED rather than run, and (g) would read a
  -- cheerful "ok" that means "written down", not "done".
  perform cmd.clear(v_fleet, true);

  -- (g) A CITY WITHOUT ONE REFUSES. The building is the gate, so a harbour with no workstation
  --     must say so - otherwise the gate is decoration.
  select p.id into v_port from public.ports p
   where p.kind = 'HARBOUR'
     and not exists (select 1 from public.port_buildings b where b.port_id = p.id and b.kind = 'workstation')
   order by p.code limit 1;
  update public.fleets set port_id = v_port where id = v_fleet;
  v_res := cmd.issue(v_fleet, 'MAKE sails', null, null);
  if (v_res->>'ok')::boolean or v_res->'refusal'->>'code' <> 'E_NO_WORKSTATION' then
    raise exception '0068 self-assert FAIL: a city with no workstation answered % rather than E_NO_WORKSTATION',
      coalesce(v_res->'refusal'->>'code', 'ok');
  end if;

  -- (h) THE GRAMMAR GREW BY EXACTLY ONE WORD, and the schema says so.
  select def into v_before from defs_before_0068 where fn = 'cmd.verb_schema';
  if position('MAKE' in v_before) <> 0 then
    raise exception '0068 self-assert FAIL: the pre-image already knew MAKE';
  end if;
  if jsonb_array_length(cmd.verb_schema()) <> 9 then
    raise exception '0068 self-assert FAIL: the grammar serves % verbs, expected 9', jsonb_array_length(cmd.verb_schema());
  end if;

  -- (i) POSTURE. The catalogue is public; what a player owns is theirs.
  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0068 self-assert FAIL: % client write grant(s)', v_grants;
  end if;

  raise notice '0068 self-assert ok: A FITTING IS MADE, NOT FOUND. 12 fittings with % recipe line(s), every one 2-5 inputs and every input SOLD SOMEWHERE (the dead-ingredient class that cost the owner two hulls in their other game); % cities keep a workstation and % of them are good enough for the tier-3 fittings, which is short of every harbour, so the building means something and no fitting is unreachable. It works END TO END through the one door: a house was founded, put ashore where a workstation stands, given six tuns of flax, two of cordage and one of tar, and typed MAKE sails - she owns the suit, and her hold is EMPTY, so nothing was minted out of nothing. The same line then refused E_NO_MATERIALS on an empty hold and E_NO_WORKSTATION at a city that keeps none. The grammar grew by exactly one word, from 8 verbs to 9; 0 client write grants.',
    v_recipes, v_ws, v_ws3;
end $$;
