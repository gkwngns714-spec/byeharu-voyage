-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 167 - PIRATES RAID COMPANIES TOO  (migration 0464; docs/design/content-plan-2026-11.md 5.3 item 1; docs/dev-log/2026-11-22-raid-companies.md;
--   the owner, 2026-11-22: "make this game a proper game")
--
--   Lit and dark, through public.raid_target and the pirates' minute job (public.tick_pirates), rolled back with proof.mjs's transaction.
--   0427/0432's scene (proof 133's): a hunting pirate at her haunt; the world's merchant 60 miles north of her; a new company's ship
--   (an Apprentice) 15 miles north. Nothing else at sea or at anchor.
--
-- @pass RC_KNOBS    the three knobs are 0464's: raid_companies_enabled false (dark), raid_company_title_min 3 (Master), raid_company_weight 1
-- @pass RC_DARK     dark, 0432's rule to the row: the world's merchant 60 miles off is chosen before the company 15 miles off
-- @pass RC_PEACE    lit, a company under Master is passed over (the beginner's peace): the merchant is chosen; with no merchant, nobody
-- @pass RC_NEAREST  lit, a company at or over the title: the nearest wins, whoever owns her: the company 15 miles off before the merchant at 60
-- @pass RC_WEIGHT   lit, raid_company_weight weighs her miles: 3 (45 < 60) she is still chosen; 5 (75 > 60) the merchant is
-- @pass RC_STRIKE   lit, the pirates' job opens the RAID on the company's ship, and not on the merchant
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

update public.world_config set value = case key when 'pirate_strike_from_port' then 'true'::jsonb else to_jsonb(720) end where key in ('pirate_strike_from_port', 'pirate_port_minutes');   -- 0445: the pirate lies at her haunt and raids from it (proof 133's scene)

update public.world_config set value = '[]'::jsonb where key = 'tick_fight_kinds';   -- 0435: the round-by-round battle; nothing here fights it out

create function pg_temp.lie_167(p_fleet uuid, p_lat numeric, p_lon numeric) returns void language sql as $f$
  update public.voyages v set status = 'ABORTED' where v.fleet_id = p_fleet and v.status = 'SAILING';
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = p_lat, lon = p_lon, busy_until = null, ready_at = null, version = f.version + 1 where f.id = p_fleet;
$f$;

do $p$
declare
  t0      timestamptz := date_trunc('minute', now()) + interval '1 day';
  v_uid   uuid := '00000000-0464-4000-8000-000000000001';
  v_hub   uuid := (select p.id from public.ports p where p.code = 'TDC');
  v_pf    uuid;
  v_m     uuid;
  v_h     uuid;
  v_hp    uuid;
  v_lat   numeric;
  v_lon   numeric;
  v_r     jsonb;
  v_b     public.battles%rowtype;
  v_t     uuid;
  r       record;
begin
  -- ── THE SCENE (proof 133's) ──
  update public.world_config set value = 'true'::jsonb
   where key in ('city_treasury_enabled', 'economy_closed', 'pirates_bite', 'npc_refits_enabled', 'attack_enabled') and value is distinct from 'true'::jsonb;
  update public.world_config set value = 'false'::jsonb where key in ('navy_enabled', 'pirates_trade', 'convoys_enabled') and value is distinct from 'false'::jsonb;
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 5000000, reserve = 0;
  update public.port_treasury t set ducats = 900000000 where t.port_id = public.pirate_capital();
  update public.pirate_ships set laid_up_at = t0 where laid_up_at is null;
  update public.world_config set value = to_jsonb(0) where key = 'pirate_wakes_per_run';   -- the proof's pirate alone is at work
  update public.pirate_clock set added_at = t0 + interval '1 hour', paid_at = t0 + interval '1 hour';
  select q.ord into r from public.pirate_roster q where q.hub_port = v_hub and q.ord % 1000 = 6;
  v_pf := public.pirate_commission_fleet(r.ord, public.refit_yard(v_hub), t0);
  update public.ships s set crew = (select b.crew_max from public.ship_base(s.id) b) where s.fleet_id = v_pf;
  select h.port_id, h.sea_id into r from public.pirate_haunt_of(v_hub, (select x.ord from public.pirate_ships x where x.fleet_id = v_pf)) h;
  update public.fleets f set port_id = r.port_id, status = 'DOCKED', ready_at = null where f.id = v_pf;
  update public.pirate_ships x set sea_id = r.sea_id, mission = 'CRUISE', haunt_port = r.port_id, haunt_since = t0 where x.fleet_id = v_pf;
  select p.lat, p.lon into v_lat, v_lon from voyage.fleet_point(v_pf, t0) p;
  update public.voyages v set status = 'ABORTED' where v.status = 'SAILING';
  update public.fleets f set status = 'DOCKED', port_id = coalesce(f.port_id, v_hub), lat = null, lon = null, busy_until = null where f.status in ('SAILING', 'ANCHORED');
  select nf.fleet_id into v_m
    from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id join public.players pl on pl.id = f.player_id
   where pl.nation_id is distinct from public.pirate_nation() and exists (select 1 from public.ships s where s.fleet_id = nf.fleet_id and s.durability > 0)
   order by nf.fleet_id limit 1;
  perform pg_temp.lie_167(v_m, v_lat + 1, v_lon);      -- sixty miles north
  v_hp := public.new_house(v_uid, 'Casa Presa 167', 'PRT', 'LIS', 'Presa 167', 'galion', 'Presa 167', null, false);
  select f.id into v_h from public.fleets f where f.player_id = v_hp;
  update public.ships s set crew = (select b.crew_max from public.ship_base(s.id) b), cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where s.fleet_id = v_h;
  perform pg_temp.lie_167(v_h, v_lat + 0.25, v_lon);   -- fifteen miles north

  -- ── RC_KNOBS ──
  if public.wc('raid_companies_enabled') is distinct from 'false'::jsonb or public.wc_int('raid_company_title_min') is distinct from 3
     or public.wc_num('raid_company_weight') is distinct from 1 then
    raise exception 'PROOF 167 FAIL: the knobs are not 0464''s: % / % / %', public.wc('raid_companies_enabled'), public.wc_int('raid_company_title_min'), public.wc_num('raid_company_weight');
  end if;
  if public.title_level(v_hp) is distinct from 1 or (select t.name from public.title_names t where t.level = 3) <> 'Master' then
    raise exception 'PROOF 167 FAIL: the new company is not an Apprentice (title %), or title 3 is not Master', public.title_level(v_hp);
  end if;
  raise notice 'PASS: RC_KNOBS — raid_companies_enabled false, raid_company_title_min 3 (Master), raid_company_weight 1; the company is an Apprentice';

  -- ── RC_DARK ──
  v_t := public.raid_target(v_pf, t0);
  if v_t is distinct from v_m then
    raise exception 'PROOF 167 FAIL: dark, the pirate chose % before the world''s merchant %', v_t, v_m;
  end if;
  raise notice 'PASS: RC_DARK — dark: the merchant 60 miles off before the company 15 miles off (0432''s order)';

  -- ── RC_PEACE ──
  update public.world_config set value = 'true'::jsonb where key = 'raid_companies_enabled';
  v_t := public.raid_target(v_pf, t0);
  if v_t is distinct from v_m then
    raise exception 'PROOF 167 FAIL: lit, with the Apprentice company passed over the pirate chose %, not the merchant %', v_t, v_m;
  end if;
  update public.fleets f set status = 'DOCKED', port_id = v_hub, lat = null, lon = null where f.id = v_m;   -- no merchant: nobody at all
  v_t := public.raid_target(v_pf, t0);
  if v_t is not null then
    raise exception 'PROOF 167 FAIL: lit, with only an Apprentice company in reach the pirate chose %', v_t;
  end if;
  perform pg_temp.lie_167(v_m, v_lat + 1, v_lon);
  raise notice 'PASS: RC_PEACE — lit: the Apprentice company passed over, the merchant chosen; alone in reach, nobody';

  -- ── RC_NEAREST ──
  update public.world_config set value = to_jsonb(1) where key = 'raid_company_title_min';   -- every company stands at or over the title
  v_t := public.raid_target(v_pf, t0);
  if v_t is distinct from v_h then
    raise exception 'PROOF 167 FAIL: lit, nearest wins: the pirate chose %, not the company 15 miles off %', v_t, v_h;
  end if;
  raise notice 'PASS: RC_NEAREST — lit: the company 15 miles off before the merchant at 60';

  -- ── RC_WEIGHT ──
  update public.world_config set value = to_jsonb(3) where key = 'raid_company_weight';
  if public.raid_target(v_pf, t0) is distinct from v_h then
    raise exception 'PROOF 167 FAIL: weight 3 (45 miles against 60), the pirate chose %', public.raid_target(v_pf, t0);
  end if;
  update public.world_config set value = to_jsonb(5) where key = 'raid_company_weight';
  if public.raid_target(v_pf, t0) is distinct from v_m then
    raise exception 'PROOF 167 FAIL: weight 5 (75 miles against 60), the pirate chose %', public.raid_target(v_pf, t0);
  end if;
  update public.world_config set value = to_jsonb(1) where key = 'raid_company_weight';
  raise notice 'PASS: RC_WEIGHT — weight 3: the company; weight 5: the merchant';

  -- ── RC_STRIKE ──
  v_r := public.tick_pirates(t0);
  select b.* into v_b from public.battles b join public.battle_sides s on s.battle_id = b.id and s.fleet_id = v_h and s.side = 'DEFENDER';
  if v_b.id is null or v_b.kind <> 'RAID'
     or not exists (select 1 from public.battle_sides s where s.battle_id = v_b.id and s.fleet_id = v_pf and s.side = 'ATTACKER') then
    raise exception 'PROOF 167 FAIL: lit, the job did not raid the company''s ship: %', v_r;
  end if;
  if exists (select 1 from public.battle_sides s where s.fleet_id = v_m) then
    raise exception 'PROOF 167 FAIL: the merchant was raided as well';
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'raid_companies_enabled';
  update public.world_config set value = to_jsonb(3) where key = 'raid_company_title_min';
  raise notice 'PASS: RC_STRIKE — lit, tick_pirates opened RAID % on the company''s ship (%); the merchant untouched', v_b.id, v_r;
end
$p$;
