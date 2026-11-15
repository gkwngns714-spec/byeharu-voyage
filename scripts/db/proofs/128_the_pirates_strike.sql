-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 128 - THE PIRATES STRIKE  (migration 0427; docs/dev-log/2026-11-15-pirates-strike.md; the owner, 2026-11-15: "attack rate of pirates
--   with other merchants should be done also frequently. in stats i see no engagement")
--
--   Lit as prod is (the purses, the closed economy, the pirates, the refit rule, attacks), through the pirates' own minute job (public.tick_pirates)
--   and the battles' (public.tick_battles), rolled back with proof.mjs's transaction. A hunting pirate (a roster xebec of Tortuga lying at her haunt,
--   in her sea) and two ships at anchor beside her: a company's merchant, and a PLAYER'S ship ninety miles off. EVERY STRIKE MARKER FAILS BEFORE 0427:
--   nothing a pirate does reached public.battle_open (its one caller was the player's door), so the job opened no battle at all.
--
-- @pass PS_KNOBS    the knobs are 0427's: pirate_add_minutes 1, pirate_respawn_minutes 5, a strike every 5 minutes, 2 a run, kept 48 hours
-- @pass PS_STRIKE   the pirates' minute job opens ONE battle, kind RAID, the pirate the ATTACKER and the nearest merchant the DEFENDER, both held to its clock (battle_seconds; its rounds logged as an attack's are)
-- @pass PS_CLOSE    the battles' job closes it at its clock: RESOLVED or BROKEN_OFF with a raid line, both ships free again where they lay, and the world's money unmoved (moved, never made)
-- @pass PS_REST     a pirate who struck within pirate_strike_minutes rests; past it she strikes again, and never the merchant she fought within attack_ship_minutes: the next nearest, the player's ship
-- @pass PS_PLAYER   the player's ship set upon by a pirate gets her BATTLE_REPORT (raid true); a player's ship can still never be attacked by anyone but a pirate (E_HUMAN_TARGET), and no ship but a pirate's opens a RAID (E_BAD_TARGET)
-- @pass PS_STATS    the Stats count's window counts the two raids and how they ended; world.stats_fleets serves them as `battles` for the last 24 hours
-- @pass PS_KEEP     a closed RAID older than raid_keep_hours is deleted with its sides and rounds by the job; a player's ATTACK battle is never deleted
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

update public.world_config set value = case key when 'pirate_strike_from_port' then 'true'::jsonb else to_jsonb(720) end where key in ('pirate_strike_from_port', 'pirate_port_minutes');   -- 0445: this proof's pirate lies at her haunt and raids from it (0427's world, by 0445's two way-back knobs); the cruise and the raid under sail are proof 147's

update public.world_config set value = '[]'::jsonb where key = 'tick_fight_kinds';   -- 0435: this proof drives the round-by-round battle (the rollback's engine); a tick battle is proof 136's

create function pg_temp.w_128() returns numeric language sql as $f$
  select (select coalesce(sum(public.treasury_balance(t.port_id)), 0) from public.port_treasury t)::numeric
       + (select coalesce(sum(p.ducats), 0) from public.players p)::numeric + public.funds_aboard()::numeric
$f$;
create function pg_temp.lie_128(p_fleet uuid, p_lat numeric, p_lon numeric) returns void language sql as $f$
  update public.voyages v set status = 'ABORTED' where v.fleet_id = p_fleet and v.status = 'SAILING';
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = p_lat, lon = p_lon, busy_until = null, ready_at = null, version = f.version + 1 where f.id = p_fleet;
$f$;

do $p$
declare
  t0      timestamptz := date_trunc('minute', now()) + interval '1 day';
  v_hub   uuid := (select p.id from public.ports p where p.code = 'TDC');
  v_pf    uuid;
  v_m     uuid;
  v_h     uuid;
  v_hp    uuid;
  v_lat   numeric;
  v_lon   numeric;
  v_r     jsonb;
  v_b1    public.battles%rowtype;
  v_b2    public.battles%rowtype;
  v_w0    numeric;
  v_s     text;
  v_e     text;
  v_win   jsonb;
  v_sf    jsonb;
  v_old   uuid;
  r       record;
begin
  -- ── THE SCENE ──
  update public.world_config set value = 'true'::jsonb
   where key in ('city_treasury_enabled', 'economy_closed', 'pirates_bite', 'npc_refits_enabled', 'attack_enabled') and value is distinct from 'true'::jsonb;
  update public.world_config set value = 'false'::jsonb where key in ('navy_enabled', 'pirates_trade') and value is distinct from 'false'::jsonb;
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 5000000, reserve = 0;
  update public.port_treasury t set ducats = ceil(5000000 / public.wc_num('pirate_spend_day_pct'))::bigint where t.port_id = public.pirate_capital();
  if not public.pirates_on() or not public.attack_on() or not public.economy_closed() then
    raise exception 'PROOF 128 FAIL: the pirates, attacks or the closed economy could not be lit in this world';
  end if;

  -- ── PS_KNOBS ──
  if public.wc_int('pirate_add_minutes') <> 1 or public.wc_int('pirate_respawn_minutes') <> 5 or public.wc_int('pirate_strike_minutes') <> 5
     or public.wc_int('pirate_strikes_per_run') <> 2 or public.wc_int('raid_keep_hours') <> 48 then
    raise exception 'PROOF 128 FAIL: the knobs are not 0427''s';
  end if;
  raise notice 'PASS: PS_KNOBS — add every % min, respawn % min, strike every % min, % a run, kept % h', public.wc_int('pirate_add_minutes'),
    public.wc_int('pirate_respawn_minutes'), public.wc_int('pirate_strike_minutes'), public.wc_int('pirate_strikes_per_run'), public.wc_int('raid_keep_hours');

  -- the proof's pirate alone is at work: a lone roster xebec of Tortuga, manned, lying at her haunt (her hub) in her sea; the clock's add has just run
  update public.pirate_ships set laid_up_at = t0 where laid_up_at is null;
  update public.pirate_clock set added_at = t0 + interval '1 hour', paid_at = t0 + interval '1 hour';
  select q.ord into r from public.pirate_roster q where q.hub_port = v_hub and q.ord % 1000 = 4;
  v_pf := public.pirate_commission_fleet(r.ord, public.refit_yard(v_hub), t0);
  if v_pf is null then
    raise exception 'PROOF 128 FAIL: the roster xebec was not built';
  end if;
  update public.ships s set crew = (select b.crew_max from public.ship_base(s.id) b) where s.fleet_id = v_pf;
  select h.port_id, h.sea_id into r from public.pirate_haunt_of(v_hub, (select x.ord from public.pirate_ships x where x.fleet_id = v_pf)) h;
  if r.port_id is null then
    raise exception 'PROOF 128 FAIL: Tortuga has no haunt in this world';
  end if;
  update public.fleets f set port_id = r.port_id, status = 'DOCKED', ready_at = null where f.id = v_pf;
  update public.pirate_ships x set sea_id = r.sea_id, mission = 'CRUISE', haunt_port = r.port_id, haunt_since = t0 where x.fleet_id = v_pf;
  if not exists (select 1 from public.pirate_ships_cruising c where c.fleet_id = v_pf) then
    raise exception 'PROOF 128 FAIL: the scene''s pirate is not hunting';
  end if;
  select p.lat, p.lon into v_lat, v_lon from voyage.fleet_point(v_pf, t0) p;
  -- nobody else at sea or at anchor: the two ships below are the only merchants in reach
  update public.voyages v set status = 'ABORTED' where v.status = 'SAILING';
  update public.fleets f set status = 'DOCKED', port_id = coalesce(f.port_id, v_hub), lat = null, lon = null, busy_until = null where f.status in ('SAILING', 'ANCHORED');
  -- a company's merchant (not the pirates'), beside her
  select nf.fleet_id into v_m
    from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id join public.players pl on pl.id = f.player_id
   where pl.nation_id is distinct from public.pirate_nation() and exists (select 1 from public.ships s where s.fleet_id = nf.fleet_id and s.durability > 0)
   order by nf.fleet_id limit 1;
  perform pg_temp.lie_128(v_m, v_lat, v_lon);
  -- a player's ship, ninety miles north of her
  v_hp := public.new_house('00000000-0427-4000-8000-000000000001', 'Casa Raid 128', 'PRT', 'LIS', 'Raid 128', 'galion', 'Raid 128', null, false);
  select f.id into v_h from public.fleets f where f.player_id = v_hp;
  update public.ships s set crew = (select b.crew_max from public.ship_base(s.id) b), cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where s.fleet_id = v_h;
  perform pg_temp.lie_128(v_h, v_lat + 1.5, v_lon);
  if public.raid_target(v_pf, t0) is distinct from v_m then
    raise exception 'PROOF 128 FAIL: the nearest merchant in reach is not the company''s ship beside her (got %)', public.raid_target(v_pf, t0);
  end if;

  -- ── PS_STRIKE ── the pirates' own minute job
  v_w0 := pg_temp.w_128();
  v_r := public.tick_pirates(t0);
  select b.* into v_b1 from public.battles b join public.battle_sides s on s.battle_id = b.id and s.fleet_id = v_pf and s.side = 'ATTACKER' and s.how = 'OPENED';
  if (v_r #>> '{struck,STRUCK}')::int is distinct from 1 or (select count(*) from public.battles) <> 1 or v_b1.kind <> 'RAID'
     or not exists (select 1 from public.battle_sides s where s.battle_id = v_b1.id and s.fleet_id = v_m and s.side = 'DEFENDER' and s.how = 'OPENED')
     or (select f.busy_until from public.fleets f where f.id = v_pf) <> v_b1.resolves_at or (select f.busy_until from public.fleets f where f.id = v_m) <> v_b1.resolves_at
     or v_b1.resolves_at - v_b1.started_at <> make_interval(secs => public.wc_num('battle_seconds')::double precision)
     or v_b1.sheet is null then
    raise exception 'PROOF 128 FAIL: the job did not open one RAID of the pirate on the merchant: % / %', v_r, to_jsonb(v_b1) - 'sheet';
  end if;
  raise notice 'PASS: PS_STRIKE — tick_pirates %: one RAID, % s, pirate and merchant held', v_r -> 'struck', extract(epoch from v_b1.resolves_at - v_b1.started_at);

  -- ── PS_CLOSE ──
  perform public.tick_battles(v_b1.resolves_at);
  select * into v_b1 from public.battles b where b.id = v_b1.id;
  if v_b1.status not in ('RESOLVED', 'BROKEN_OFF') or not (v_b1.result ? 'raid') or (v_b1.result #>> '{raid,merchant_kind}') <> 'MERCHANT'
     or exists (select 1 from public.fleets f where f.id in (v_pf, v_m) and f.busy_until is not null)
     or (select f.status from public.fleets f where f.id = v_m) not in ('ANCHORED', 'UNABLE_TO_SAIL')
     or (select f.status from public.fleets f where f.id = v_pf) not in ('DOCKED', 'UNABLE_TO_SAIL')
     or pg_temp.w_128() <> v_w0 then
    raise exception 'PROOF 128 FAIL: the raid did not close as it should: % % (money moved by %)', v_b1.status, v_b1.result - 'rounds' - 'sheet', pg_temp.w_128() - v_w0;
  end if;
  raise notice 'PASS: PS_CLOSE — % %, taken %, money unmoved', v_b1.status, v_b1.result ->> 'outcome', v_b1.result #>> '{raid,taken}';

  -- ── PS_REST ── (the scene's pirate is mended and manned again, as at her haunt, so the second fight is a fight)
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b), crew = (select b.crew_max from public.ship_base(s.id) b) where s.fleet_id = v_pf;
  update public.fleets f set status = 'DOCKED' where f.id = v_pf;
  update public.world_config set value = to_jsonb(60) where key = 'pirate_strike_minutes';   -- longer than any battle: a fight that ends in a round brings its close in
  v_s := public.pirate_strike(v_pf, v_b1.resolves_at + interval '30 seconds');
  update public.world_config set value = to_jsonb(5) where key = 'pirate_strike_minutes';
  if v_s <> 'RESTING' then
    raise exception 'PROOF 128 FAIL: a pirate who struck within pirate_strike_minutes answered %', v_s;
  end if;
  v_r := public.tick_pirates(greatest(v_b1.resolves_at, v_b1.started_at + interval '5 minutes') + interval '1 minute');   -- past her rest, whenever the fight closed
  select b.* into v_b2 from public.battles b where b.id <> v_b1.id;
  if (v_r #>> '{struck,STRUCK}')::int is distinct from 1 or v_b2.kind <> 'RAID'
     or not exists (select 1 from public.battle_sides s where s.battle_id = v_b2.id and s.fleet_id = v_h and s.side = 'DEFENDER') then
    raise exception 'PROOF 128 FAIL: past her rest she did not strike the next merchant (the player''s ship): %', v_r;
  end if;
  raise notice 'PASS: PS_REST — RESTING inside the rest; then % on the player''s ship, the merchant she fought passed over', v_r -> 'struck';

  -- ── PS_PLAYER ──
  perform public.tick_battles(v_b2.resolves_at);
  select * into v_b2 from public.battles b where b.id = v_b2.id;
  if v_b2.status not in ('RESOLVED', 'BROKEN_OFF')
     or not exists (select 1 from public.events e where e.player_id = v_hp and e.kind = 'BATTLE_REPORT' and (e.payload ->> 'raid')::boolean and e.payload ->> 'battle_id' = v_b2.id::text)
     or pg_temp.w_128() <> v_w0 then
    raise exception 'PROOF 128 FAIL: the player''s ship got no raid report, or money was made: % %', v_b2.status, pg_temp.w_128() - v_w0;
  end if;
  begin
    perform public.battle_open('ATTACK', v_m, v_h, v_b2.resolves_at + interval '1 minute');
    v_e := 'opened';
  exception when others then v_e := sqlerrm;
  end;
  if v_e not like 'E_HUMAN_TARGET%' then
    raise exception 'PROOF 128 FAIL: an ATTACK on a player''s ship answered %', v_e;
  end if;
  begin
    perform public.battle_open('RAID', v_m, v_h, v_b2.resolves_at + interval '1 minute');
    v_e := 'opened';
  exception when others then v_e := sqlerrm;
  end;
  if v_e not like 'E_BAD_TARGET%' or (select count(*) from public.battles) <> 2 then
    raise exception 'PROOF 128 FAIL: a merchant opened a RAID: %', v_e;
  end if;
  raise notice 'PASS: PS_PLAYER — the player''s report (%), E_HUMAN_TARGET for an ATTACK, E_BAD_TARGET for a RAID by a merchant', v_b2.result ->> 'outcome';

  -- ── PS_STATS ──
  v_win := public.stats_fleets_count(t0 - interval '1 minute', v_b2.resolves_at + interval '5 minutes') -> 'win';
  if (v_win ->> 'raids')::int <> 2 or (v_win ->> 'raids_won')::int + (v_win ->> 'raids_held')::int <> 2 or (v_win ->> 'attacks')::int <> 0 then
    raise exception 'PROOF 128 FAIL: the count''s window reads %', v_win;
  end if;
  delete from public.stats_fleets;
  insert into public.stats_fleets (slot, at, figures)
  values (public.drift_slot_of(v_b2.resolves_at + interval '5 minutes'), v_b2.resolves_at + interval '5 minutes',
          public.stats_fleets_count(t0 - interval '1 minute', v_b2.resolves_at + interval '5 minutes'));
  v_sf := world.stats_fleets() -> 'battles';
  if (v_sf ->> 'raids_day')::int <> 2 or (v_sf ->> 'won_day')::int + (v_sf ->> 'held_day')::int <> 2 or not (v_sf ? 'navy_fights_day') then
    raise exception 'PROOF 128 FAIL: world.stats_fleets serves battles %', v_sf;
  end if;
  raise notice 'PASS: PS_STATS — the window %; served %', v_win - 'since', v_sf;

  -- ── PS_KEEP ──
  update public.battles b set started_at = b.started_at - interval '49 hours', resolves_at = b.resolves_at - interval '49 hours' where b.id = v_b1.id;
  insert into public.battles (kind, site, started_at, resolves_at, status) values ('ATTACK', '{"lat": 0, "lon": 0}'::jsonb, t0 - interval '60 hours', t0 - interval '59 hours', 'RESOLVED')
  returning id into v_old;
  v_r := public.pirate_strikes(v_b2.resolves_at + interval '2 minutes');
  if (v_r ->> 'kept_out')::int <> 1 or exists (select 1 from public.battles b where b.id = v_b1.id)
     or exists (select 1 from public.battle_sides s where s.battle_id = v_b1.id) or exists (select 1 from public.battle_rounds x where x.battle_id = v_b1.id)
     or not exists (select 1 from public.battles b where b.id = v_old) or not exists (select 1 from public.battles b where b.id = v_b2.id) then
    raise exception 'PROOF 128 FAIL: the retention: %', v_r;
  end if;
  raise notice 'PASS: PS_KEEP — % deleted (the old raid, its sides and rounds); the old ATTACK and the young raid kept', v_r ->> 'kept_out';
end
$p$;
