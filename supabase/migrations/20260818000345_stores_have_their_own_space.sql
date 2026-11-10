-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0345 — STORES HAVE THEIR OWN SPACE: every ship carries her water and food in a stores space of her own, sized by her class and her roll, apart from the cargo hold. DARK
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Owner, 2026-10-26 (docs/OWNER_REQUESTS.md row 221): "separate cargo space so that provision is set differently by ship." Design: docs/SHIP_STORES_AND_VARIETY.md §1 (branch osn-ship-stores-variety,
-- written at head 0235), slice V2, checked against the live chain at head 0344. Row 222 (the roll, 0276) is live: every hull already carries roll_stores, read by nothing until this file.
-- TODAY (0007, 0150, 0225, 0231): one pool. public.fleet_free_hold = hold - cargo - water - food, and every top-up (public.stores_topup) fills "the room beside her cargo". A full hold means short stores.
--
-- WHAT THIS FILE ADDS (two knobs, five small readers, seventeen hunks over fifteen live bodies; no table, no column, no row written):
--   ship_stores_separate  false   THE switch (owner only). ship_stores_days  36   the days of stores her space holds for a FULL crew (class crew_max), the design's figure.
--   public.ship_stores_separate()          THE one reader of the switch.
--   public.ship_stores_space(ship)         HER STORES SPACE in tuns: floor(ceil(class crew_max x (water_per_crew_day + food_per_crew_day) x ship_stores_days) x her roll_stores (0276)). Barca 26 t, carlat 38 t,
--                                          nau 177 t at roll 1.000; a hull rolled after 0276 differs by her roll. The quartermaster's stretch is NOT applied (Provisioners already stretch the days).
--   public.ship_stores_room(ship, dark)    the room a top-up may fill: dark, the caller's own figure (byte for byte); lit, her stores space. Every stores_topup caller passes its old figure through it.
--   public.stores_in_hold(tons)            the tuns of stores that take cargo room: dark, all of them (byte for byte); lit, none.
--   public.ship_stores_card(ship)          what ship_view adds: dark '{}'; lit {"stores_cap": her space}.
-- THE HUNKS (sliced from the LIVE bodies of head 0344, each asserted to occur once and to reverse to its pre-image; ACL, volatility, definer and settings unmoved):
--   public.fleet_free_hold, public.fleet_load (the cargo room: hold - cargo, lit), cmd.do_provision (both passes), public.supply_needs (0225's `fits`, `tons`, `cost`), public.supply_reach (0231's cap),
--   public.npc_provision_for, public.fleet_stores (a crown's free top-up) — room and FULL read her stores space, lit; public.npc_casks_blocked (lit: selling cargo frees no stores room, so never
--   blocked for it); world.good_board (`units_fit` no longer subtracts the stores, lit); world.ship_view (+ `stores_cap`, lit); voyage.leg_refusal (lit: the words say the stores space, and the
--   figures carry `stores_space: true` so the desk words it "Supplies short"); world.npc_fleet_card, world.cargo_ship_card, world.navy_ship_card, world.pirate_ship_card (a stranger's card strips
--   `stores_cap` beside id, water_t and food_t).
-- DARK PARITY BY CONSTRUCTION: dark every new reader answers its argument (or '{}', or false), so every re-cut body computes what it did. Asserted below twice: the whole world's free hold, supply
-- reach, supply needs and ship views of every human fleet and 20 NPC fleets (by id), new against pg_temp copies of the pre-images IN ONE STATEMENT (one snapshot: a live trade during the deploy
-- cannot fail it; bounded, because the whole world's reads take about a minute on prod); a probe company's provision,
-- load, needs, refusal, crown top-up, uneven casks and ship view run before the hunks and again after them, dark, and answer the same jsonb.
-- NOT TOUCHED: voyage.ship_speed_at (stores still WEIGH: the fill stays (cargo + stores) / hold, so speed is byte-identical lit too, decided by default), voyage.settle (consumption), stores_topup
-- itself, store_ratio (unread lit; dropping it is a later slice).
-- DECIDED BY DEFAULT: no ship is backfilled. A hull that carries more stores than her space keeps them until she eats them. Lit, her top-up room is the tuns at which her short store matches her long
--   one in days (public.ship_stores_room): an uneven hull over her space (a cask lost, 0059) evens up and is never stuck; she never takes on past her long store's days.
--   One rule for every house (players, merchants, crown and pirate ships): lit, a crown's 90-day top-up fills her stores space, no more.
-- SELF-ASSERT (the catalog, the world read only, then a probe company of its own rolled-back rows): see sections 5 to 7. THE REAL PATHS ARE PROVED IN CI: proof 52, scripts/db/proofs/52_stores_have_their_own_space.sql.
-- BUDGET (docs/OPS_HEALTH.md section 4: the whole file within 45 s on prod): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Reads: the catalog; the free hold, reach and needs of every human fleet and 20 NPC fleets and the view of every ship in them, new and pre-image, in ONE statement (its ms printed in the receipt); the probe's own rows.
-- ROLLBACK (forward, owner only): lit, update public.world_config set value = 'false'::jsonb where key = 'ship_stores_separate'; every reader is the world before this file at once.
--   To remove: a new migration swapping this file's hunks back (each OLD text is here verbatim) and dropping the five readers and the two knobs.
-- VERSION: 0345 - prod head 0344 (read 2026-11-10).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0          timestamptz := clock_timestamp();
  v_h           record;
  v_def         text;
  v_pre         text;
  v_n           int;
  v_fn_before   text;
  v_meta_before text;
  v_cfg_before  text;
  v_rel_before  text;
  v_trig_before text;
  v_cron_before text;
  v_cron_after  text;
  v_entry       int;
  v_badf        int;
  v_bads        int;
  v_tw          timestamptz;
  v_world_ms    int;
  v_nsel        int;
  v_pre_probe   jsonb;
  v_dark        jsonb;
  v_lit         jsonb;
  v_space       numeric;
  c_keys      constant text[] := array['ship_stores_separate', 'ship_stores_days'];
  c_new_fns   constant text[] := array['public.ship_stores_separate()', 'public.ship_stores_space(uuid)', 'public.ship_stores_room(uuid,numeric)',
                                       'public.stores_in_hold(numeric)', 'public.ship_stores_card(uuid)'];
  c_hunked    constant text[] := array['public.fleet_free_hold(uuid)', 'public.fleet_load(uuid,text,numeric,numeric)', 'cmd.do_provision(uuid,jsonb)',
                                       'public.supply_needs(uuid,numeric[])', 'public.supply_reach(uuid)', 'public.npc_provision_for(uuid,numeric)',
                                       'public.npc_casks_blocked(uuid,uuid,numeric,numeric)', 'public.fleet_stores(uuid,numeric)',
                                       'world.good_board(uuid,uuid,uuid,numeric)', 'world.ship_view(uuid)', 'voyage.leg_refusal(uuid,uuid,numeric,jsonb)',
                                       'world.npc_fleet_card(uuid)', 'world.cargo_ship_card(uuid)', 'world.navy_ship_card(uuid)', 'world.pirate_ship_card(uuid)'];
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD: nothing of this file exists, and every body it cuts does ──
  if exists (select 1 from public.world_config c where c.key = any (c_keys))
     or exists (select 1 from unnest(c_new_fns) f where to_regprocedure(f) is not null) then
    raise exception '0345 refuses: something of it is already in this world';
  end if;
  if exists (select 1 from unnest(c_hunked) f where to_regprocedure(f) is null)
     or not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'ships' and column_name = 'roll_stores')
     or to_regprocedure('public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid)') is null then
    raise exception '0345 refuses: 0225 / 0231 / 0276 / 0331 (the bodies it cuts, the stores roll) are not all in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
    into v_meta_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c;
  select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname)) into v_rel_before
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p');
  select md5(string_agg(t.tgrelid::regclass::text || ':' || t.tgname || ':' || t.tgenabled::text, ',' order by t.tgrelid::regclass::text, t.tgname)) into v_trig_before
    from pg_trigger t where not t.tgisinternal;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_before;
  end if;
  v_entry := (select count(*) from public.client_rpc_entry_points());

  -- THE PRE-IMAGES KEPT AS pg_temp COPIES (0250's way): section 6 reads old and new in ONE statement, one snapshot, so a live trade between two reads cannot fail the deploy.
  -- The four readers it compares call nothing this file re-cuts, so each copy is the whole pre-image of its reading.
  declare
    d record;
    v_d text;
  begin
    for d in select * from (values ('public.fleet_free_hold(uuid)', 'public.fleet_free_hold', 'pg_temp.fleet_free_hold_old_0345'),
                                   ('public.supply_reach(uuid)', 'public.supply_reach', 'pg_temp.supply_reach_old_0345'),
                                   ('public.supply_needs(uuid,numeric[])', 'public.supply_needs', 'pg_temp.supply_needs_old_0345'),
                                   ('world.ship_view(uuid)', 'world.ship_view', 'pg_temp.ship_view_old_0345')) x(fn, name, old_name) loop
      v_d := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
      if (length(v_d) - length(replace(v_d, 'FUNCTION ' || d.name || '(', ''))) / length('FUNCTION ' || d.name || '(') <> 1 then
        raise exception '0345 refuses: %''s definition does not name itself once', d.fn;
      end if;
      execute replace(v_d, 'FUNCTION ' || d.name || '(', 'FUNCTION ' || d.old_name || '(');
    end loop;
  end;

  -- ── 2. THE PROBE (defined now, run before the hunks, after them dark, and lit; each run in a sub-block rolled back whole) ──
  -- A company of its own (never a real one), one barca with a FIXED id (so her 0276 roll is the same in every run), 20 hands, empty casks, docked at Lisbon. It provisions 20 days, loads a bulk-1
  -- good to the brim, reads its free hold, reach and needs (a short leg and a long one) before and after the load, provisions FULL, then reads the refusal for a long leg, the merchant
  -- reading, a crown's free top-up and her view. Every refused step answers its message: the probe answers what happened, never raises.
  execute $f$
create function pg_temp.probe_0345()
returns jsonb
language plpgsql
as $b$
declare
  v_nat  uuid := (select n.id from public.nations n where n.code = 'PRT');
  v_port uuid := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  v_good text := (select g.code from public.goods g where g.bulk = 1 order by g.code limit 1);
  v_pl   uuid;
  v_fl   uuid;
  v_sh   uuid := '00000000-0000-4000-8000-000000000345';
  v_out  jsonb := '{}'::jsonb;
  v_r    jsonb;
begin
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Stores 0345', v_nat, 100000000, false) returning id into v_pl;
  v_fl := public.form_fleet(v_pl, 'Stores 0345', v_port);
  perform public.commission_ship(v_pl, v_fl, 'barca', 'Stores 0345', true, false, v_sh);
  update public.ships set crew = 20, water_t = 0, food_t = 0 where id = v_sh;
  begin
    v_r := cmd.do_provision(v_fl, '{"mode": "DAYS", "days": 20}'::jsonb);
  exception when others then v_r := to_jsonb(sqlerrm);
  end;
  v_out := v_out || jsonb_build_object('prov20', v_r,
    'free0', public.fleet_free_hold(v_fl),
    'reach0', (select to_jsonb(r) from public.supply_reach(v_fl) r),
    'needs0', (select jsonb_agg(to_jsonb(x) order by x.nm) from public.supply_needs(v_fl, array[1000, 9000]::numeric[]) x));
  v_out := v_out || jsonb_build_object('loaded', public.fleet_load(v_fl, v_good, 100000, 1));   -- its own statement: the reads below see the load
  v_out := v_out || jsonb_build_object('free1', public.fleet_free_hold(v_fl),
    'reach1', (select to_jsonb(r) from public.supply_reach(v_fl) r),
    'needs1', (select jsonb_agg(to_jsonb(x) order by x.nm) from public.supply_needs(v_fl, array[1000, 9000]::numeric[]) x),
    'refusal', voyage.leg_refusal(v_fl, null, 9000, null),
    'npc60', (select to_jsonb(x) from public.npc_provision_for(v_fl, 60) x));
  begin
    v_r := cmd.do_provision(v_fl, '{"mode": "FULL"}'::jsonb);
  exception when others then v_r := to_jsonb(sqlerrm);
  end;
  v_out := v_out || jsonb_build_object('full', v_r,
    'after_full', (select jsonb_build_object('water_t', s.water_t, 'food_t', s.food_t) from public.ships s where s.id = v_sh));
  update public.ships set water_t = 0, food_t = 0 where id = v_sh;
  perform public.fleet_stores(v_fl, 90);
  v_out := v_out || jsonb_build_object('crown90', (select jsonb_build_object('water_t', s.water_t, 'food_t', s.food_t) from public.ships s where s.id = v_sh),
    'view', world.ship_view(v_sh), 'space', public.ship_stores_space(v_sh));
  -- an UNEVEN hull OVER her space (water for 0.9 of her space, food for 0.5: 140 %): PROVISION to her water's days, and the days her stores carry before and after
  update public.ships set water_t = round(public.ship_stores_space(v_sh) * 0.9, 3), food_t = round(public.ship_stores_space(v_sh) * 0.5, 3) where id = v_sh;
  v_out := v_out || jsonb_build_object('uneven0', (select jsonb_build_object('water_t', s.water_t, 'food_t', s.food_t) from public.ships s where s.id = v_sh),
    'uneven_reach0', (select to_jsonb(r) from public.supply_reach(v_fl) r));
  begin
    v_r := cmd.do_provision(v_fl, jsonb_build_object('mode', 'DAYS', 'days',
             (select floor(s.water_t / (s.crew * public.wc_num('water_per_crew_day'))) from public.ships s where s.id = v_sh)));
  exception when others then v_r := to_jsonb(sqlerrm);
  end;
  v_out := v_out || jsonb_build_object('uneven_prov', v_r,
    'uneven1', (select jsonb_build_object('water_t', s.water_t, 'food_t', s.food_t, 'crew', s.crew) from public.ships s where s.id = v_sh));
  v_out := v_out || jsonb_build_object('uneven_reach1', (select to_jsonb(r) from public.supply_reach(v_fl) r));
  return v_out;
end
$b$
  $f$;

  -- ── 3. THE KNOBS AND THE READERS ──
  insert into public.world_config (key, value, description) values
    ('ship_stores_separate', 'false'::jsonb,
     '0345: THE switch of the stores space (owner row 221). False: water and food share the cargo hold (0007, 0150). True: each ship carries them in her own stores space (public.ship_stores_space), apart from the hold; cargo takes none of it and it takes no cargo room. Read through public.ship_stores_separate alone. Owner only.'),
    ('ship_stores_days', to_jsonb(36),
     '0345: the days of stores a ship''s stores space holds for her FULL crew (class crew_max), before her 0276 roll: about 90 days at the crew she needs. Read through public.ship_stores_space alone.');

  execute $f$
create function public.ship_stores_separate()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0345: THE one reader of ship_stores_separate (owner row 221). Off: stores share the cargo hold. On: each ship has her own stores space. Server-only.
  select coalesce(public.wc('ship_stores_separate') = 'true'::jsonb, false)
$body$
  $f$;
  execute $f$
create function public.ship_stores_space(p_ship uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0345: HER STORES SPACE in tuns (owner row 221): the stores her class's full crew eats in ship_stores_days, rounded up to whole tuns, times her own stores roll (0276), floored.
  -- A fact of the hull, served dark too; only lit does anything read it as her room. Null for no such ship.
  select floor(ceil(c.crew_max * (public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day')) * public.wc_num('ship_stores_days')) * s.roll_stores)
    from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.id = p_ship
$body$
  $f$;
  execute $f$
create function public.ship_stores_room(p_ship uuid, p_dark numeric)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0345: THE ROOM A TOP-UP MAY FILL on this hull (public.stores_topup's p_room and p_full). Dark: p_dark, the caller's own figure, untouched. Lit: her stores space, whatever her cargo.
  -- A hull lit OVER her space (stores aboard from before the switch, or a crown's; a cask lost since, 0059, leaves the split uneven): the room is the tuns at which her short store matches her
  -- long one in days, so the short store may rise to the long one's days and never past them. Without it the top-up's free room is 0 for good, a leg longer than her short store is refused,
  -- and a docked merchant never sails again. She never takes on more than that, and as she eats she falls back to her space.
  select case when not public.ship_stores_separate() then p_dark
              when coalesce(s.water_t + s.food_t, 0) <= sp.space + 0.01 then sp.space
              else greatest(sp.space, s.water_t * (k.w + k.f) / k.w, s.food_t * (k.w + k.f) / k.f) end
    from (select public.ship_stores_space(p_ship) as space) sp
    left join public.ships s on s.id = p_ship
   cross join (select public.wc_num('water_per_crew_day') as w, public.wc_num('food_per_crew_day') as f) k
$body$
  $f$;
  execute $f$
create function public.stores_in_hold(p_tons numeric)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0345: THE TUNS OF STORES THAT TAKE CARGO ROOM. Dark: all of them (p_tons, untouched: water and food share the hold). Lit: none (they have their own space).
  select case when public.ship_stores_separate() then 0::numeric else p_tons end
$body$
  $f$;
  execute $f$
create function public.ship_stores_card(p_ship uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0345: what world.ship_view adds for the stores space. Dark: nothing ('{}'). Lit: stores_cap, her stores space in tuns (public.ship_stores_space).
  select case when public.ship_stores_separate() then jsonb_build_object('stores_cap', public.ship_stores_space(p_ship)) else '{}'::jsonb end
$body$
  $f$;
  revoke all on function public.ship_stores_separate() from public, anon, authenticated;
  revoke all on function public.ship_stores_space(uuid) from public, anon, authenticated;
  revoke all on function public.ship_stores_room(uuid, numeric) from public, anon, authenticated;
  revoke all on function public.stores_in_hold(numeric) from public, anon, authenticated;
  revoke all on function public.ship_stores_card(uuid) from public, anon, authenticated;
  comment on function public.ship_stores_separate() is '0345: THE one reader of the stores-space switch (world_config ship_stores_separate). Server-only.';
  comment on function public.ship_stores_space(uuid) is '0345: her stores space in tuns: floor(ceil(class crew_max x stores per crew day x ship_stores_days) x roll_stores). Server-only.';
  comment on function public.ship_stores_room(uuid, numeric) is '0345: the room a stores top-up may fill: dark the caller''s figure, lit her stores space. Server-only.';
  comment on function public.stores_in_hold(numeric) is '0345: the tuns of stores that take cargo room: dark all, lit none. Server-only.';
  comment on function public.ship_stores_card(uuid) is '0345: world.ship_view''s stores-space keys: dark {}, lit {stores_cap}. Server-only.';

  -- the probe BEFORE the hunks (the pre-image of every path it walks)
  begin
    v_pre_probe := pg_temp.probe_0345();
    raise exception 'rollback_0345';
  exception when raise_exception then
    if sqlerrm <> 'rollback_0345' then raise; end if;
  end;

  -- ── 4. THE HUNKS: sliced from the live bodies, each once ──
  create temp table hunks_0345 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0345 values
  -- the cargo room: hold - cargo, lit
  ('public.fleet_free_hold(uuid)', 1,
$h$                                  - public.ship_cargo_tuns(s.id) - s.water_t - s.food_t)), 0)
$h$,
$h$                                  - public.ship_cargo_tuns(s.id) - public.stores_in_hold(s.water_t + s.food_t))), 0)   -- 0345: lit, the stores keep their own space
$h$),
  ('public.fleet_load(uuid,text,numeric,numeric)', 1,
$h$                  hc.cap - public.ship_cargo_tuns(s.id)
                    - s.water_t - s.food_t as free
$h$,
$h$                  hc.cap - public.ship_cargo_tuns(s.id)
                    - public.stores_in_hold(s.water_t + s.food_t) as free   -- 0345: lit, the stores keep their own space
$h$),
  -- the top-ups: room and FULL read her stores space, lit
  ('cmd.do_provision(uuid,jsonb)', 1,
$h$    -- lay with short water and "the casks are already full".
    select t.water_t, t.food_t into v_tw, v_tf
      from public.stores_topup(r.crew, r.water_t, r.food_t, r.hold - r.cargo_t,
                               case when p_args->>'mode' = 'DAYS' then (p_args->>'days')::numeric end,
                               r.hold * r.store_ratio) t;
$h$,
$h$    -- lay with short water and "the casks are already full".
    -- 0345: lit, the room and FULL are her own stores space (public.ship_stores_room); dark, the figures above, untouched.
    select t.water_t, t.food_t into v_tw, v_tf
      from public.stores_topup(r.crew, r.water_t, r.food_t, public.ship_stores_room(r.id, r.hold - r.cargo_t),
                               case when p_args->>'mode' = 'DAYS' then (p_args->>'days')::numeric end,
                               public.ship_stores_room(r.id, r.hold * r.store_ratio)) t;
$h$),
  ('cmd.do_provision(uuid,jsonb)', 2,
$h$    select t.water_t, t.food_t into v_tw, v_tf   -- 0150: the same top-up as the pass above
      from public.stores_topup(r.crew, r.water_t, r.food_t, r.hold - r.cargo_t,
                               case when p_args->>'mode' = 'DAYS' then (p_args->>'days')::numeric end,
                               r.hold * r.store_ratio) t;
$h$,
$h$    select t.water_t, t.food_t into v_tw, v_tf   -- 0150: the same top-up as the pass above (0345: the same room)
      from public.stores_topup(r.crew, r.water_t, r.food_t, public.ship_stores_room(r.id, r.hold - r.cargo_t),
                               case when p_args->>'mode' = 'DAYS' then (p_args->>'days')::numeric end,
                               public.ship_stores_room(r.id, r.hold * r.store_ratio)) t;
$h$),
  ('public.supply_needs(uuid,numeric[])', 1,
$h$           'room', hc.cap - public.ship_cargo_tuns(s.id),
           'full', hc.cap * s.store_ratio)), '[]'::jsonb)
$h$,
$h$           'room', public.ship_stores_room(s.id, hc.cap - public.ship_cargo_tuns(s.id)),   -- 0345: lit, her own stores space
           'full', public.ship_stores_room(s.id, hc.cap * s.store_ratio))), '[]'::jsonb)
$h$),
  ('public.supply_reach(uuid)', 1,
$h$                                                  hc.cap - public.ship_cargo_tuns(s.id),
                                                  1000000, hc.cap * s.store_ratio) t
$h$,
$h$                                                  public.ship_stores_room(s.id, hc.cap - public.ship_cargo_tuns(s.id)),   -- 0345: lit, her own stores space
                                                  1000000, public.ship_stores_room(s.id, hc.cap * s.store_ratio)) t
$h$),
  ('public.npc_provision_for(uuid,numeric)', 1,
$h$   cross join lateral public.stores_topup(s.crew, s.water_t, s.food_t, hc.cap,
                                          p_days, hc.cap * s.store_ratio) t
$h$,
$h$   cross join lateral public.stores_topup(s.crew, s.water_t, s.food_t, public.ship_stores_room(s.id, hc.cap),   -- 0345: lit, her own stores space
                                          p_days, public.ship_stores_room(s.id, hc.cap * s.store_ratio)) t
$h$),
  ('public.fleet_stores(uuid,numeric)', 1,
$h$            cross join lateral public.stores_topup(x.crew, x.water_t, x.food_t, hc.cap, p_days, hc.cap * x.store_ratio) t
$h$,
$h$            cross join lateral public.stores_topup(x.crew, x.water_t, x.food_t, public.ship_stores_room(x.id, hc.cap), p_days, public.ship_stores_room(x.id, hc.cap * x.store_ratio)) t   -- 0345
$h$),
  ('public.npc_casks_blocked(uuid,uuid,numeric,numeric)', 1,
$h$  v_d := public.sail_refused_days(p_fleet);
  if v_d = 0 then
$h$,
$h$  v_d := public.sail_refused_days(p_fleet);
  if v_d = 0 or public.ship_stores_separate() then   -- 0345: lit, her cargo takes no stores room, so selling it frees none
$h$),
  -- the board: a BUY's units no longer give up room to the stores, lit
  ('world.good_board(uuid,uuid,uuid,numeric)', 1,
$h$greatest(0, floor(((select t from free) - r.sn_tons) / g.bulk))$h$,
$h$greatest(0, floor(((select t from free) - public.stores_in_hold(r.sn_tons)) / g.bulk))$h$),
  -- the ship: her stores space, lit
  ('world.ship_view(uuid)', 1,
$h$  v_view := v_view || world.ship_set_card(p_ship);
$h$,
$h$  v_view := v_view || world.ship_set_card(p_ship);
  -- 0345 (owner row 221): … plus `stores_cap`, her stores space in tuns, only while ship_stores_separate is lit (public.ship_stores_card)
  v_view := v_view || public.ship_stores_card(p_ship);
$h$),
  -- a stranger's card strips her stores as it strips her casks (0124, 0333, 0339): stores_cap joins id, water_t and food_t (dark the key is absent, so nothing moves)
  ('world.npc_fleet_card(uuid)', 1, $h$ - array['id', 'water_t', 'food_t']$h$, $h$ - array['id', 'water_t', 'food_t', 'stores_cap']$h$),
  ('world.cargo_ship_card(uuid)', 1, $h$ - array['id', 'water_t', 'food_t']$h$, $h$ - array['id', 'water_t', 'food_t', 'stores_cap']$h$),
  ('world.navy_ship_card(uuid)', 1, $h$ - array['id', 'water_t', 'food_t']$h$, $h$ - array['id', 'water_t', 'food_t', 'stores_cap']$h$),
  ('world.pirate_ship_card(uuid)', 1, $h$ - array['id', 'water_t', 'food_t']$h$, $h$ - array['id', 'water_t', 'food_t', 'stores_cap']$h$),
  -- the leg judge: the words and a figure, lit
  ('voyage.leg_refusal(uuid,uuid,numeric,jsonb)', 1,
$h$           format('that leg is %s days at sea and asks %s days of supplies; beside the cargo the hold carries %s — sell some, or stop to resupply',
$h$,
$h$           format(case when public.ship_stores_separate()   -- 0345: lit, the stores keep their own space and cargo takes none of it
                       then 'that leg is %s days at sea and asks %s days of supplies; her stores space carries %s — stop to resupply'
                       else 'that leg is %s days at sea and asks %s days of supplies; beside the cargo the hold carries %s — sell some, or stop to resupply' end,
$h$),
  ('voyage.leg_refusal(uuid,uuid,numeric,jsonb)', 2,
$h$                              'carry_days', round(coalesce(v_reach.carry_days, 0), 1), 'cap_nm', round(v_reach.cap_nm)));
$h$,
$h$                              'carry_days', round(coalesce(v_reach.carry_days, 0), 1), 'cap_nm', round(v_reach.cap_nm))
             || case when public.ship_stores_separate() then '{"stores_space": true}'::jsonb else '{}'::jsonb end);   -- 0345: the desk words it "Supplies short"
$h$);

  for v_h in select h.fn from hunks_0345 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    declare
      x record;
    begin
      for x in select * from hunks_0345 h where h.fn = v_h.fn order by h.ord loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0345 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
      for x in select * from hunks_0345 h where h.fn = v_h.fn order by h.ord desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0345 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0345 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;

  -- ── 5. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked || c_new_fns) x))) <> v_fn_before then
    raise exception '0345 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_new_fns) x))) <> v_meta_before then
    raise exception '0345 self-assert FAIL: an ACL, a volatility, a definer flag or a setting moved (the re-cut bodies included)';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> all (c_keys)) <> v_cfg_before then
    raise exception '0345 self-assert FAIL: a world_config row moved';
  end if;
  if (select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname))
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p')) <> v_rel_before
     or (select md5(string_agg(t.tgrelid::regclass::text || ':' || t.tgname || ':' || t.tgenabled::text, ',' order by t.tgrelid::regclass::text, t.tgname)) from pg_trigger t where not t.tgisinternal) <> v_trig_before then
    raise exception '0345 self-assert FAIL: a table, view, index or trigger appeared or went: this file makes none';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_after;
    if v_cron_after is distinct from v_cron_before then
      raise exception '0345 self-assert FAIL: a cron job moved';
    end if;
  end if;
  if (select string_agg(p.provolatile::text || case when p.prosecdef then 'd' else '-' end, '' order by p.oid::regprocedure::text)
        from pg_proc p where p.oid = any (array(select x::regprocedure::oid from unnest(c_new_fns) x))) <> 'sdsdsdsdsd' then
    raise exception '0345 self-assert FAIL: the new readers are not STABLE SECURITY DEFINER';
  end if;
  if exists (select 1 from unnest(c_new_fns) f where has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')) then
    raise exception '0345 self-assert FAIL: a client can reach a reader of the stores space';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> v_entry
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0345 self-assert FAIL: the registry or a wall moved (no new door; the posture must read zero)';
  end if;
  if public.ship_stores_separate() or public.wc('ship_stores_separate') <> 'false'::jsonb or public.wc_num('ship_stores_days') <> 36 then
    raise exception '0345 self-assert FAIL: the switch must ship false (dark) and the days at 36';
  end if;
  -- no live body but stores_topup itself and the four new readers' callers re-cut here hands stores_topup a room that skips ship_stores_room
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
                and p.oid <> 'public.stores_topup(numeric,numeric,numeric,numeric,numeric,numeric)'::regprocedure
                and p.prosrc like '%stores_topup(%' and p.prosrc not like '%ship_stores_room(%'
                and p.oid <> 'public.npc_casks_blocked(uuid,uuid,numeric,numeric)'::regprocedure) then
    raise exception '0345 self-assert FAIL: a caller of stores_topup was not re-cut onto ship_stores_room';
  end if;

  -- ── 6. DARK PARITY ON THE LIVE WORLD (read only, ONE statement, one snapshot): a BOUNDED set, new against the pg_temp pre-image ──
  -- Every human company's fleet (19 on prod) and the first 20 merchant / crown / pirate fleets by id, and every ship of those fleets. Not the whole world: on prod the whole world's reads take
  -- about 24 s (fleets) and 39 s (ship views) each, which no 45 s file can afford (measured read only 2026-11-10). The probe below walks every re-cut path on its own rows.
  v_tw := clock_timestamp();
  with sel as (
    select f.id from public.fleets f join public.players p on p.id = f.player_id where not p.is_npc
    union
    select x.id from (select f.id from public.fleets f join public.players p on p.id = f.player_id where p.is_npc order by f.id limit 20) x
  )
  select (select count(*) from sel f
           where public.fleet_free_hold(f.id) is distinct from pg_temp.fleet_free_hold_old_0345(f.id)
              or (select r::text from public.supply_reach(f.id) r) is distinct from (select r::text from pg_temp.supply_reach_old_0345(f.id) r)
              or (select string_agg(x::text, ';' order by x.nm) from public.supply_needs(f.id, array[500, 2000]::numeric[]) x)
                   is distinct from (select string_agg(x::text, ';' order by x.nm) from pg_temp.supply_needs_old_0345(f.id, array[500, 2000]::numeric[]) x)),
         (select count(*) from (select s.id from public.ships s join sel on sel.id = s.fleet_id offset 0) s where world.ship_view(s.id) is distinct from pg_temp.ship_view_old_0345(s.id)),
         (select count(*) from sel)
    into v_badf, v_bads, v_nsel;
  v_world_ms := round(extract(epoch from clock_timestamp() - v_tw) * 1000);
  if v_badf <> 0 or v_bads <> 0 then
    raise exception '0345 self-assert FAIL: dark, % fleet(s) and % ship(s) read differently after the hunks', v_badf, v_bads;
  end if;

  -- ── 7. THE PROBE AFTER THE HUNKS: dark = the pre-image; lit = the stores space ──
  begin
    v_dark := pg_temp.probe_0345();
    raise exception 'rollback_0345';
  exception when raise_exception then
    if sqlerrm <> 'rollback_0345' then raise; end if;
  end;
  if v_dark is distinct from v_pre_probe then
    raise exception '0345 self-assert FAIL: dark, the probe reads differently after the hunks: before % after %', v_pre_probe, v_dark;
  end if;
  if v_dark->'view' ? 'stores_cap' or (v_dark->'refusal'->'figures') ? 'stores_space' then
    raise exception '0345 self-assert FAIL: dark, a lit-only key is served';
  end if;
  begin
    update public.world_config set value = 'true'::jsonb where key = 'ship_stores_separate';
    v_lit := pg_temp.probe_0345();
    raise exception 'rollback_0345';
  exception when raise_exception then
    if sqlerrm <> 'rollback_0345' then raise; end if;
  end;
  if public.ship_stores_separate() then
    raise exception '0345 self-assert FAIL: the lit probe did not roll back';
  end if;
  v_space := (v_lit->>'space')::numeric;
  if v_space is null or v_space <> (v_dark->>'space')::numeric or v_space < 1 then
    raise exception '0345 self-assert FAIL: her stores space is not a fact of the hull (lit %, dark %)', v_lit->>'space', v_dark->>'space';
  end if;
  if (v_lit->'view'->>'stores_cap')::numeric is distinct from v_space then
    raise exception '0345 self-assert FAIL: lit, ship_view does not serve stores_cap = her space';
  end if;
  -- the cargo room: lit, a hold loaded to the brim holds no stores, so it loads more than dark by the stores she holds, and nothing is left
  if (v_lit->>'loaded')::numeric <= (v_dark->>'loaded')::numeric or (v_lit->>'free1')::numeric <> 0
     or (v_lit->>'free0')::numeric <= (v_dark->>'free0')::numeric then
    raise exception '0345 self-assert FAIL: lit, the stores still take cargo room (loaded % vs %, free %)', v_lit->>'loaded', v_dark->>'loaded', v_lit->>'free1';
  end if;
  -- the stores: lit, loading cargo moves no reach and no need (fits stays), and every top-up stays inside her space
  if v_lit->'reach0'->'carry_days' <> v_lit->'reach1'->'carry_days' or v_dark->'reach0'->'carry_days' = v_dark->'reach1'->'carry_days'
     or not (v_lit->'needs1'->0->>'fits')::boolean or not (v_lit->'needs1'->1->>'fits')::boolean or (v_dark->'needs1'->1->>'fits')::boolean then
    raise exception '0345 self-assert FAIL: lit, the days her stores carry moved when cargo was loaded, or the long leg does not fit lit and not dark: lit % / %, dark % / %',
      v_lit->'reach1', v_lit->'needs1', v_dark->'reach1', v_dark->'needs1';
  end if;
  if (v_lit->'after_full'->>'water_t')::numeric + (v_lit->'after_full'->>'food_t')::numeric > v_space + 0.01
     or (v_lit->'after_full'->>'water_t')::numeric + (v_lit->'after_full'->>'food_t')::numeric < v_space - 0.01
     or (v_lit->'crown90'->>'water_t')::numeric + (v_lit->'crown90'->>'food_t')::numeric > v_space + 0.01 then
    raise exception '0345 self-assert FAIL: lit, FULL does not fill her stores space exactly, or a crown top-up passes it (% / %, space %)', v_lit->'after_full', v_lit->'crown90', v_space;
  end if;
  -- an uneven hull over her space: lit, her short store rises to her long one's days and never past them; her water is untouched; the leg judge reads her long store's days
  if (v_lit->'uneven0'->>'water_t')::numeric + (v_lit->'uneven0'->>'food_t')::numeric <= v_space
     or (v_lit->'uneven1'->>'water_t')::numeric <> (v_lit->'uneven0'->>'water_t')::numeric
     or (v_lit->'uneven1'->>'food_t')::numeric <= (v_lit->'uneven0'->>'food_t')::numeric
     or (v_lit->'uneven1'->>'food_t')::numeric / ((v_lit->'uneven1'->>'crew')::numeric * public.wc_num('food_per_crew_day'))
        < floor((v_lit->'uneven0'->>'water_t')::numeric / ((v_lit->'uneven1'->>'crew')::numeric * public.wc_num('water_per_crew_day'))) - 0.01
     or (v_lit->'uneven1'->>'food_t')::numeric / ((v_lit->'uneven1'->>'crew')::numeric * public.wc_num('food_per_crew_day'))
        > (v_lit->'uneven0'->>'water_t')::numeric / ((v_lit->'uneven1'->>'crew')::numeric * public.wc_num('water_per_crew_day')) + 0.01
     or (v_lit->'uneven_reach0'->>'carry_days')::numeric   -- the leg judge already reads her evened days (not her short store's), so a leg within them is never refused
        < (v_lit->'uneven0'->>'water_t')::numeric / ((v_lit->'uneven1'->>'crew')::numeric * public.wc_num('water_per_crew_day')) - 0.01 then
    raise exception '0345 self-assert FAIL: lit, an uneven hull over her space is not evened up to her long store and no further: % -> % (%), reach % -> %',
      v_lit->'uneven0', v_lit->'uneven1', v_lit->'uneven_prov', v_lit->'uneven_reach0', v_lit->'uneven_reach1';
  end if;
  -- dark, the same full hold leaves FULL nothing to take on (the pre-image's own answer)
  if jsonb_typeof(v_dark->'full') <> 'string' or v_dark->>'full' not like '%E_HOLD_FULL%' then
    raise exception '0345 self-assert FAIL: dark, FULL on a brimming hold is not refused as before: %', v_dark->'full';
  end if;

  raise notice '0345 self-assert ok: STORES HAVE THEIR OWN SPACE, dark behind ship_stores_separate. % hunks over % bodies, each once and reversing, grants unmoved; % readers made, server-only; % knobs; no other function, knob, table, trigger or job moved. Dark parity: % fleets (every human one, 20 NPC) and their ships read the same new and pre-image in one statement, and the probe''s every path reads the same before and after. Lit probe barca: space % t, loaded % vs % dark, free hold 0, reach and needs unmoved by cargo, FULL to the space, an uneven hull over her space evened up to her long store. Printed, never asserted: world compare % ms, whole file % ms.',
    (select count(*) from hunks_0345), (select count(distinct h.fn) from hunks_0345 h), cardinality(c_new_fns), cardinality(c_keys), v_nsel,
    v_space, v_lit->>'loaded', v_dark->>'loaded', v_world_ms, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0345;
  drop function pg_temp.probe_0345();
  drop function pg_temp.fleet_free_hold_old_0345(uuid);
  drop function pg_temp.supply_reach_old_0345(uuid);
  drop function pg_temp.supply_needs_old_0345(uuid, numeric[]);
  drop function pg_temp.ship_view_old_0345(uuid);
end
$m$;
