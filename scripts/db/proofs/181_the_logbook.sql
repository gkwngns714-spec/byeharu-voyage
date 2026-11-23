-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 181 - THE LOGBOOK  (migration 0478; docs/design/roadmap-2026-11-23.md slice 9; docs/dev-log/2026-11-23-logbook.md)
--
--   The migration's self-assert walks one region finished at one arrival. This proof plays the logbook as production runs it: the
--   economy closed and the city purses lit (a sale is paid from a purse, a dock fee charged), a kind of goods finished by a sale, a
--   region finished before the switch was lit and settled at the next lit arrival, both cuts on one dock fee, a merchant, the page,
--   and the cost. Rolled back by proof.mjs. Its scenes take seconds and never straddle UTC midnight in a way that matters: nothing
--   here is daily (the logbook's Reputation is not day-capped, and no assertion reads a day's allowance).
--
-- @pass LB_DARK        dark: an arrival and a sale write no row and add nothing to their events; the fee and the read are as before
-- @pass LB_FOUND       lit: a first harbour is Discovered (logbook.found: its region n / of, its sea, its specialty, her harbours), the
--                      harbour she sailed from and her hulls written silently; a known harbour again tells nothing
-- @pass LB_SALE        a first sale of a good tells it (good, kind, n / of, goods); the same good again tells nothing and writes nothing
-- @pass LB_KIND_SET    the sale that finishes a goods kind writes its set row and pays logbook_set_rep once, on the SOLD event
-- @pass LB_LATER       a region finished while dark (her rows back-filled) is settled and paid at her next lit arrival, once
-- @pass LB_FEE         the one dock fee: a finished region's harbours cut by the region knob, every harbour by the kinds' cut, both
--                      multiplied; a company with no set and a merchant pay the fee as before
-- @pass LB_MERCHANT    a merchant's arrival and sale write nothing and tell nothing
-- @pass LB_READ        world.logbook(): the totals, the region and the kind done, what she has seen, the sets (42 today)
-- @pass LB_COST        a lit arrival at a known harbour, a known sale and a dock fee read, timed
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- she lies at p_from (her voyage, if any, ended), sails the probe course to p_to from p_at and arrives; answers the VOYAGE_REPORT payload
create function pg_temp.trip_181(p_fleet uuid, p_from text, p_to text) returns jsonb language plpgsql as $f$
declare
  v_a    uuid := (select p.id from public.ports p where p.code = p_from and p.kind = 'HARBOUR');
  v_b    uuid := (select p.id from public.ports p where p.code = p_to and p.kind = 'HARBOUR');
  v_segs jsonb;
  v_voy  uuid;
  v_eta  timestamptz;
begin
  select voyage.segments_from_course(jsonb_build_array(jsonb_build_array(x.roadstead_lat, x.roadstead_lon), jsonb_build_array(y.roadstead_lat, y.roadstead_lon)))
    into v_segs from public.sea_reaches x, public.sea_reaches y where x.port_id = v_a and y.port_id = v_b;
  update public.voyages v set status = 'ABORTED' where v.fleet_id = p_fleet and v.status = 'SAILING';
  update public.fleets f set status = 'DOCKED', port_id = v_a, lat = null, lon = null, busy_until = null, ready_at = null where f.id = p_fleet;
  v_voy := voyage.depart(p_fleet, v_segs, v_a, v_b, now() - interval '20 seconds');
  select v.eta into v_eta from public.voyages v where v.id = v_voy;
  perform voyage.settle(p_fleet, v_eta + interval '1 second');
  update public.fleets f set status = 'DOCKED', port_id = v_b, lat = null, lon = null, busy_until = null, ready_at = null where f.id = p_fleet;
  return (select e.payload from public.events e where e.kind = 'VOYAGE_REPORT' and e.payload ->> 'voyage_id' = v_voy::text);
end
$f$;

-- she sells p_qty of good p_good where she lies (the hold filled first); answers the SOLD payload
create function pg_temp.sell_181(p_fleet uuid, p_good uuid, p_qty int) returns jsonb language plpgsql as $f$
declare
  v_code text := (select g.code from public.goods g where g.id = p_good);
  v_pl   uuid := (select f.player_id from public.fleets f where f.id = p_fleet);
  v_was  uuid[];
begin
  -- one transaction: every event has the same created_at, so the new SOLD is the one not there before
  v_was := array(select e.id from public.events e where e.player_id = v_pl and e.kind = 'SOLD');
  update public.ships s set cargo = jsonb_build_object(v_code, p_qty), cargo_basis = jsonb_build_object(v_code, 1) where s.fleet_id = p_fleet;
  perform cmd.do_sell(p_fleet, jsonb_build_object('good', p_good, 'qty', p_qty));
  return (select e.payload from public.events e where e.player_id = v_pl and e.kind = 'SOLD' and e.id <> all (v_was));
end
$f$;

-- the dock fee's own figure for 100,000 of cargo before any logbook cut, unrounded (public.port_fee's expression, the purses lit)
create function pg_temp.port_fee_181_base(p_port uuid, p_player uuid) returns numeric language sql as $f$
  select greatest(0, (public.wc_num('port_fee_base') + public.wc_num('port_fee_pct') * 100000)
                     * public.country_factor(public.power_stance((select pl.nation_id from public.players pl where pl.id = p_player), public.port_nation(p_port)))
                     * public.regard_factor(p_player, p_port))
$f$;

do $p$
declare
  c_a     constant uuid := '00000000-0478-4000-8000-0000000000a1';
  c_b     constant uuid := '00000000-0478-4000-8000-0000000000b1';
  v_set   uuid := (select p.id from public.ports p where p.code = 'SET' and p.kind = 'HARBOUR');
  v_lis   uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_reg   uuid := (select p.region_id from public.ports p where p.code = 'SET' and p.kind = 'HARBOUR');
  v_rcode text := (select g.code from public.regions g join public.ports p on p.region_id = g.id where p.code = 'SET' and p.kind = 'HARBOUR');
  v_far   uuid;
  v_a     uuid;
  v_b     uuid;
  v_fa    uuid;
  v_fb    uuid;
  v_npc   uuid;
  v_g1    uuid;
  v_g2    uuid;
  v_kind  text;
  v_r     jsonb;
  v_s     jsonb;
  v_n     int;
  v_f     record;
  v_t     timestamptz;
  v_ms1   numeric;
  v_ms2   numeric;
  v_ms3   numeric;
  i       int;
begin
  -- production's switches: the economy closed, the purses lit and well above their reserves, Reputation on
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 5000000, reserve = 0;
  update public.world_config set value = 'true'::jsonb
   where key in ('economy_closed', 'city_treasury_enabled', 'reputation_on') and value is distinct from 'true'::jsonb;
  select p.id into v_far from public.ports p where p.kind = 'HARBOUR' and p.region_id is distinct from v_reg order by p.code limit 1;
  -- two goods Setubal trades, of one kind (the kind the second finishes)
  select g.id, g.category into v_g1, v_kind
    from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_set and not public.culture_refuses((select p.culture from public.ports p where p.id = v_set), g.culture_mask)
     and exists (select 1 from public.port_goods pg2 join public.goods g2 on g2.id = pg2.good_id
                  where pg2.port_id = v_set and g2.category = g.category and g2.id <> g.id
                    and not public.culture_refuses((select p.culture from public.ports p where p.id = v_set), g2.culture_mask))
   order by g.category, g.code limit 1;
  select g.id into v_g2
    from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_set and g.category = v_kind and g.id <> v_g1
     and not public.culture_refuses((select p.culture from public.ports p where p.id = v_set), g.culture_mask)
   order by g.code limit 1;
  v_a := public.new_house(c_a, 'Casa do Diario A 181', 'PRT');
  v_b := public.new_house(c_b, 'Casa do Diario B 181', 'PRT');
  select f.id into v_fa from public.fleets f where f.player_id = v_a;
  select f.id into v_fb from public.fleets f where f.player_id = v_b;
  select f.player_id into v_npc from public.fleets f join public.players p on p.id = f.player_id where p.is_npc order by f.id limit 1;

  -- ── LB_DARK ──
  update public.world_config set value = 'false'::jsonb where key = 'logbook_enabled';
  v_r := pg_temp.trip_181(v_fa, 'LIS', 'SET');
  v_s := pg_temp.sell_181(v_fa, v_g1, 10);
  perform cmd.assume_identity(c_a);
  if v_r ? 'logbook' or v_s ? 'logbook' or v_r is null or v_s is null
     or exists (select 1 from public.logbook l where l.player_id in (v_a, v_b))
     or world.logbook() is distinct from '{"on": false}'::jsonb
     or public.logbook_fee_factor(v_a, v_set) <> 1 then
    raise exception 'PROOF 181 FAILED: dark, the logbook moved: % % %', v_r -> 'logbook', v_s -> 'logbook', world.logbook();
  end if;
  raise notice 'PASS: LB_DARK — an arrival at SET and a sale of % wrote no row and told nothing; the read {"on": false}; the fee factor 1',
    (select g.code from public.goods g where g.id = v_g1);

  -- ── LB_FOUND ──
  update public.world_config set value = 'true'::jsonb where key = 'logbook_enabled';
  v_r := pg_temp.trip_181(v_fa, 'LIS', 'SET');
  if v_r #>> '{logbook,found,port}' is distinct from 'SET' or v_r #>> '{logbook,found,region}' is distinct from v_rcode
     or (v_r #>> '{logbook,found,n}')::int <> 2 or (v_r #>> '{logbook,found,harbours}')::int <> 2
     or (v_r #>> '{logbook,found,of}')::int <> (select count(*) from public.ports p where p.region_id = v_reg and p.kind = 'HARBOUR')
     or (v_r #>> '{logbook,found,sea_new}')::boolean is not false   -- Lisbon, written first, lies in the same sea
     or jsonb_array_length(v_r #> '{logbook,found,specialty}') not between 1 and 3
     or exists (select 1 from jsonb_array_elements_text(v_r #> '{logbook,found,specialty}') c
                 where not exists (select 1 from public.port_specialties ps join public.goods g on g.id = ps.good_id where ps.port_id = v_set and g.code = c))
     or not exists (select 1 from public.logbook l where l.player_id = v_a and l.kind = 'harbour' and l.code = 'LIS')
     or not exists (select 1 from public.logbook l where l.player_id = v_a and l.kind = 'hull') then
    raise exception 'PROOF 181 FAILED: the first harbour was not Discovered as written: %', v_r -> 'logbook';
  end if;
  v_s := pg_temp.trip_181(v_fa, 'LIS', 'SET');
  if v_s ? 'logbook' then
    raise exception 'PROOF 181 FAILED: a known harbour told again: %', v_s -> 'logbook';
  end if;
  raise notice 'PASS: LB_FOUND — SET Discovered (% %/% , sea % , specialty %), Lisbon and her hull written silently; the second call told nothing',
    v_rcode, v_r #>> '{logbook,found,n}', v_r #>> '{logbook,found,of}', v_r #>> '{logbook,found,sea}', v_r #> '{logbook,found,specialty}';

  -- ── LB_SALE ──
  v_s := pg_temp.sell_181(v_fa, v_g1, 10);
  if v_s #>> '{logbook,good}' is distinct from (select g.code from public.goods g where g.id = v_g1) or v_s #>> '{logbook,kind}' is distinct from v_kind
     or (v_s #>> '{logbook,n}')::int <> 1 or (v_s #>> '{logbook,goods}')::int <> 1
     or (v_s #>> '{logbook,of}')::int <> (select count(*) from public.goods g where g.category = v_kind) then
    raise exception 'PROOF 181 FAILED: the first sale was not told: %', v_s;
  end if;
  v_n := (select count(*) from public.logbook l where l.player_id = v_a);
  v_s := pg_temp.sell_181(v_fa, v_g1, 10);
  if v_s ? 'logbook' or (select count(*) from public.logbook l where l.player_id = v_a) <> v_n then
    raise exception 'PROOF 181 FAILED: a good sold before told or wrote again: %', v_s -> 'logbook';
  end if;
  raise notice 'PASS: LB_SALE — the first sale said "New: % · % 1 / %"; the second said nothing and wrote no row',
    (select g.code from public.goods g where g.id = v_g1), v_kind, (select count(*) from public.goods g where g.category = v_kind);

  -- ── LB_KIND_SET ── every other good of the kind seeded; the sale of the last finishes it
  insert into public.logbook (player_id, kind, code)
  select v_a, 'good', g.code from public.goods g where g.category = v_kind and g.id <> v_g2 on conflict do nothing;
  v_s := pg_temp.sell_181(v_fa, v_g2, 10);
  if v_s #> '{logbook,sets}' is distinct from jsonb_build_array(jsonb_build_object('set', 'kind', 'code', v_kind, 'name', v_kind, 'rep', 100))
     or (v_s #>> '{logbook,n}')::int <> (v_s #>> '{logbook,of}')::int
     or (select count(*) from public.logbook l where l.player_id = v_a and l.kind = 'kind') <> 1
     or (select count(*) from public.reputation_book b where b.player_id = v_a and b.kind = 'logbook' and b.key = 'logbook:kind:' || v_kind) <> 1 then
    raise exception 'PROOF 181 FAILED: the kind was not finished and paid once on the sale: %', v_s -> 'logbook';
  end if;
  raise notice 'PASS: LB_KIND_SET — the sale of the last % finished the kind: its set row, +% Reputation, once', v_kind, v_s #>> '{logbook,sets,0,rep}';

  -- ── LB_LATER ── B's region filled while dark (as the back-fill fills it); lit, her next arrival anywhere settles and pays it once
  update public.world_config set value = 'false'::jsonb where key = 'logbook_enabled';
  insert into public.logbook (player_id, kind, code)
  select v_b, 'harbour', p.code from public.ports p where p.region_id = v_reg and p.kind = 'HARBOUR';
  update public.world_config set value = 'true'::jsonb where key = 'logbook_enabled';
  v_r := pg_temp.trip_181(v_fb, 'LIS', 'SET');
  if v_r ? 'logbook' is not true or v_r #> '{logbook,found}' is not null
     or v_r #> '{logbook,sets}' is distinct from jsonb_build_array(jsonb_build_object('set', 'region', 'code', v_rcode, 'name', (select g.name from public.regions g where g.id = v_reg), 'rep', 100))
     or (select count(*) from public.reputation_book b where b.player_id = v_b and b.kind = 'logbook') <> 1 then
    raise exception 'PROOF 181 FAILED: a region finished while dark was not settled at the next lit arrival: %', v_r -> 'logbook';
  end if;
  v_r := pg_temp.trip_181(v_fb, 'LIS', 'SET');
  if v_r ? 'logbook' or (select count(*) from public.reputation_book b where b.player_id = v_b and b.kind = 'logbook') <> 1 then
    raise exception 'PROOF 181 FAILED: the region was paid twice: %', v_r -> 'logbook';
  end if;
  raise notice 'PASS: LB_LATER — % filled while dark: settled and paid +100 at the first lit arrival (no Discovered: SET was known), never again', v_rcode;

  -- ── LB_FEE ── A: one kind (2 %); B: the region (25 %) — and then both on B; a fresh company and a merchant as before
  insert into public.logbook (player_id, kind, code) values (v_b, 'kind', v_kind);
  for v_f in
    select p.id, p.code,
           pg_temp.port_fee_181_base(p.id, v_a) as a_base, public.port_fee(p.id, v_a, 100000) as a_fee,
           pg_temp.port_fee_181_base(p.id, v_b) as b_base, public.port_fee(p.id, v_b, 100000) as b_fee,
           public.logbook_fee_factor(v_a, p.id) as a_f, public.logbook_fee_factor(v_b, p.id) as b_f,
           public.logbook_fee_factor(v_npc, p.id) as n_f
      from public.ports p where p.id in (v_set, v_far)
  loop
    if v_f.a_f <> 0.98 or v_f.n_f <> 1
       or v_f.b_f <> (case when v_f.id = v_set then 0.75 * 0.98 else 0.98 end)
       or abs(v_f.a_fee - v_f.a_base * 0.98) > 1 or abs(v_f.b_fee - v_f.b_base * v_f.b_f) > 1 or v_f.a_base <= 0 then
      raise exception 'PROOF 181 FAILED: the dock fee at % is not cut by her sets: %', v_f.code, to_jsonb(v_f);
    end if;
  end loop;
  raise notice 'PASS: LB_FEE — the one dock fee: one finished kind 0.98 everywhere; the region and the kind 0.735 at SET, 0.98 at %; a merchant 1',
    (select p.code from public.ports p where p.id = v_far);

  -- ── LB_MERCHANT ──
  if public.logbook_arrival(v_npc, v_lis, v_set, now()) <> '{}'::jsonb or public.logbook_sale(v_npc, v_g1) <> '{}'::jsonb
     or exists (select 1 from public.logbook l where l.player_id = v_npc)
     or exists (select 1 from public.logbook l join public.players p on p.id = l.player_id where p.is_npc) then
    raise exception 'PROOF 181 FAILED: a merchant was written';
  end if;
  raise notice 'PASS: LB_MERCHANT — a merchant''s arrival and sale answered {} and wrote nothing';

  -- ── LB_READ ──
  v_r := world.logbook();
  if (v_r ->> 'company')::boolean is not true
     or (v_r #>> '{totals,harbours,n}')::int <> (select count(*) from public.logbook l where l.player_id = v_a and l.kind = 'harbour')
     or (v_r #>> '{totals,goods,n}')::int <> (select count(*) from public.goods g where g.category = v_kind)
     or (v_r #>> '{totals,seas,of}')::int <> (select count(distinct p.sea_id) from public.ports p where p.kind = 'HARBOUR')
     or (v_r #>> '{totals,harbours,of}')::int <> (select count(*) from public.ports p where p.kind = 'HARBOUR')
     or (v_r #>> '{sets,done}')::int <> 1
     or (v_r #>> '{sets,of}')::int <> jsonb_array_length(v_r -> 'regions') + jsonb_array_length(v_r -> 'kinds')
     or not exists (select 1 from jsonb_array_elements(v_r -> 'kinds') k where k ->> 'code' = v_kind and (k ->> 'done')::boolean)
     or exists (select 1 from jsonb_array_elements(v_r -> 'regions') g where (g ->> 'done')::boolean)
     or jsonb_array_length(v_r -> 'regions') <> (select count(distinct p.region_id) from public.ports p where p.kind = 'HARBOUR')
     or jsonb_array_length(v_r -> 'kinds') <> (select count(distinct g.category) from public.goods g where g.category is not null)
     or (select sum(jsonb_array_length(g -> 'harbours')) from jsonb_array_elements(v_r -> 'regions') g) <> (v_r #>> '{totals,harbours,of}')::int
     or (select sum(jsonb_array_length(k -> 'goods')) from jsonb_array_elements(v_r -> 'kinds') k) <> (v_r #>> '{totals,goods,of}')::int
     or jsonb_array_length(v_r -> 'captains') <> (v_r #>> '{totals,captains,of}')::int
     or jsonb_array_length(v_r #> '{seen,hulls}') < 1 or (v_r #>> '{reward,rep}')::int <> 100 then
    raise exception 'PROOF 181 FAILED: the read does not count her logbook: %', left(v_r::text, 800);
  end if;
  raise notice 'PASS: LB_READ — harbours %/%, goods %/%, seas %/%, hulls %/%, captains %/%; sets %/% (the kind done)',
    v_r #>> '{totals,harbours,n}', v_r #>> '{totals,harbours,of}', v_r #>> '{totals,goods,n}', v_r #>> '{totals,goods,of}',
    v_r #>> '{totals,seas,n}', v_r #>> '{totals,seas,of}', v_r #>> '{totals,hulls,n}', v_r #>> '{totals,hulls,of}',
    v_r #>> '{totals,captains,n}', v_r #>> '{totals,captains,of}', v_r #>> '{sets,done}', v_r #>> '{sets,of}';

  -- ── LB_COST ──
  v_t := clock_timestamp();
  for i in 1 .. 20 loop
    perform public.logbook_arrival(v_a, v_lis, v_set, now());
  end loop;
  v_ms1 := extract(epoch from clock_timestamp() - v_t) * 1000 / 20;
  v_t := clock_timestamp();
  for i in 1 .. 50 loop
    perform public.logbook_sale(v_a, v_g1);
  end loop;
  v_ms2 := extract(epoch from clock_timestamp() - v_t) * 1000 / 50;
  v_t := clock_timestamp();
  for i in 1 .. 200 loop
    perform public.logbook_fee_factor(v_b, v_set), public.logbook_fee_factor(v_npc, v_set);
  end loop;
  v_ms3 := extract(epoch from clock_timestamp() - v_t) * 1000 / 200;
  if v_ms1 > 100 or v_ms2 > 10 or v_ms3 > 10 then
    raise exception 'PROOF 181 FAILED: too slow: arrival % ms, sale % ms, fee % ms', round(v_ms1, 3), round(v_ms2, 3), round(v_ms3, 3);
  end if;
  raise notice 'PASS: LB_COST — a lit arrival at a known harbour % ms (the sets'' check included), a known sale % ms, two fee factors % ms',
    round(v_ms1, 3), round(v_ms2, 3), round(v_ms3, 3);
end
$p$;
