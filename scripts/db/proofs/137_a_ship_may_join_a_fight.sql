-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 137 - A SHIP MAY JOIN A FIGHT  (migration 0436; docs/design/tick-combat.md 8, 9.2; docs/dev-log/2026-11-15-battle-join.md; the owner,
--   2026-11-15, items 8-9 corrected: joining a battle is a CHOICE; no PvP, ever)
--
--   Lit as prod is, through the pirates' minute job (public.tick_pirates: the strike, then the NPC joins) and the battles' (public.tick_battles),
--   rolled back with proof.mjs's transaction. A hunting pirate raids a company's merchant; a player's ship, a navy ship, a second pirate and a
--   second merchant lie inside the circle. EVERY BUILT WORLD HAS ITS OWN DICE: nothing here assumes who wins the fight.
--
-- @pass BJ_REFUSE  in a raid a player's ship may not join the pirates (E_BAD_SIDE); at peace she may not join (E_AT_PEACE, "Wait n / 5 min")
-- @pass BJ_DOOR    a player's ship in the circle joins the side set upon at the next tick: JOINED, her hulls appended to sheet.a with `from`, the timeline re-run (k + 1) with her J event at that tick, held to the new end
-- @pass BJ_NPC     the NPC rule: the navy ship nearby joins the side set upon, the second pirate joins the pirates' side; a merchant in the circle is never pulled in
-- @pass BJ_CLOSE   the battle closes with every joiner freed; the navy's line counts the navy ship, not the pirate that joined
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

update public.world_config set value = case key when 'pirate_strike_from_port' then 'true'::jsonb else to_jsonb(720) end where key in ('pirate_strike_from_port', 'pirate_port_minutes');   -- 0445: this proof's pirate lies at her haunt and raids from it (0427's world, by 0445's two way-back knobs); the cruise and the raid under sail are proof 147's

create function pg_temp.lie_137(p_fleet uuid, p_lat numeric, p_lon numeric) returns void language sql as $f$
  update public.voyages v set status = 'ABORTED' where v.fleet_id = p_fleet and v.status = 'SAILING';
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = p_lat, lon = p_lon, busy_until = null, ready_at = null, version = f.version + 1 where f.id = p_fleet;
  update public.ships s set crew = (select b.crew_max from public.ship_base(s.id) b), durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = p_fleet;
$f$;

do $p$
declare
  t0      timestamptz := date_trunc('minute', now()) + interval '1 day';
  v_uid   uuid := '00000000-0436-4000-8000-0000000000a1';
  v_hub   uuid := (select p.id from public.ports p where p.code = 'TDC');
  v_lis   uuid := (select p.id from public.ports p where p.code = 'LIS');
  v_pf    uuid;
  v_pf2   uuid;
  v_m     uuid;
  v_m2    uuid;
  v_h     uuid;
  v_nv    uuid;
  v_np    uuid;
  v_lat   numeric;
  v_lon   numeric;
  v_slat  numeric;
  v_slon  numeric;
  v_sea   uuid;
  v_ord   int;
  v_ord2  int;
  v_r     jsonb;
  v_b     public.battles%rowtype;
  v_fake  uuid;
  v_k0    int;
  v_na    int;
  v_ex    int;
  v_tick  int;
  v_m2st  text;
  r       record;
begin
  -- ── THE SCENE (as proof 133's) ──
  update public.world_config set value = 'true'::jsonb
   where key in ('city_treasury_enabled', 'economy_closed', 'pirates_bite', 'npc_refits_enabled', 'attack_enabled') and value is distinct from 'true'::jsonb;
  update public.world_config set value = 'false'::jsonb where key in ('navy_enabled', 'pirates_trade', 'convoys_enabled') and value is distinct from 'false'::jsonb;
  update public.world_config set value = '["RAID", "ATTACK"]'::jsonb where key = 'tick_fight_kinds';
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 5000000, reserve = 0;
  update public.port_treasury t set ducats = 900000000 where t.port_id = public.pirate_capital();
  update public.pirate_ships set laid_up_at = t0 where laid_up_at is null;
  update public.world_config set value = to_jsonb(0) where key = 'pirate_wakes_per_run';
  update public.pirate_clock set added_at = t0 + interval '1 hour', paid_at = t0 + interval '1 hour';
  select q.ord into v_ord from public.pirate_roster q where q.hub_port = v_hub and q.ord % 1000 = 6;
  v_pf := public.pirate_commission_fleet(v_ord, public.refit_yard(v_hub), t0);
  update public.ships s set crew = (select b.crew_max from public.ship_base(s.id) b) where s.fleet_id = v_pf;
  select h.port_id, h.sea_id into r from public.pirate_haunt_of(v_hub, (select x.ord from public.pirate_ships x where x.fleet_id = v_pf)) h;
  v_sea := r.sea_id;
  update public.fleets f set port_id = r.port_id, status = 'DOCKED', ready_at = null where f.id = v_pf;
  update public.pirate_ships x set sea_id = r.sea_id, mission = 'CRUISE', haunt_port = r.port_id, haunt_since = t0 where x.fleet_id = v_pf;
  select p.lat, p.lon into v_lat, v_lon from voyage.fleet_point(v_pf, t0) p;
  update public.voyages v set status = 'ABORTED' where v.status = 'SAILING';
  update public.fleets f set status = 'DOCKED', port_id = coalesce(f.port_id, v_hub), lat = null, lon = null, busy_until = null where f.status in ('SAILING', 'ANCHORED');
  -- the site: sixty miles north of the pirate; everybody else inside its 30-mile circle, the merchant set upon nearest
  v_slat := v_lat + 1;
  v_slon := v_lon;
  select nf.fleet_id into v_m from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id join public.players pl on pl.id = f.player_id
   where pl.nation_id is distinct from public.pirate_nation() and exists (select 1 from public.ships s where s.fleet_id = nf.fleet_id and s.durability > 0)
   order by nf.fleet_id limit 1;
  select nf.fleet_id into v_m2 from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id join public.players pl on pl.id = f.player_id
   where pl.nation_id is distinct from public.pirate_nation() and exists (select 1 from public.ships s where s.fleet_id = nf.fleet_id and s.durability > 0)
     and f.player_id <> (select x.player_id from public.fleets x where x.id = v_m)
   order by nf.fleet_id limit 1;
  perform pg_temp.lie_137(v_m, v_slat, v_slon);
  perform pg_temp.lie_137(v_m2, v_slat + 0.2, v_slon);   -- 12 miles further from the pirate, inside the circle
  v_np := public.new_house(v_uid, 'Casa Junta 137', 'PRT', 'LIS', 'Junta 137', 'galion', 'Junta 137', null, false);
  select f.id into v_h from public.fleets f where f.player_id = v_np;
  update public.ships s set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where s.fleet_id = v_h;
  perform pg_temp.lie_137(v_h, v_slat + 0.3, v_slon);   -- 18 miles off the site

  -- the raid. Every world rolls its own dice; one where the merchant sees the pirate first may slip away at tick 0, and then no ship could join
  -- (E_BATTLE_OVER, rightly). The slip is not what this proof is about: it is off here, so the fight is still being fought at the next tick.
  update public.world_config set value = to_jsonb(0) where key = 'fight_evade_per_sighting';
  v_r := public.tick_pirates(t0);
  select b.* into v_b from public.battles b join public.battle_sides s on s.battle_id = b.id and s.fleet_id = v_m and s.side = 'DEFENDER';
  if v_b.id is null or v_b.kind <> 'RAID' or v_b.ticks is null then
    raise exception 'PROOF 137 FAIL: the job did not open a tick raid on the merchant: %', v_r;
  end if;
  -- the battle on the wall clock (the door reads clock_timestamp()), every side held to it
  update public.battles b set resolves_at = clock_timestamp() + (b.resolves_at - b.started_at),
                              next_round_at = clock_timestamp() + (coalesce(b.next_round_at, b.resolves_at) - b.started_at), started_at = clock_timestamp()
   where b.id = v_b.id;
  select * into v_b from public.battles b where b.id = v_b.id;
  update public.fleets f set busy_until = v_b.resolves_at where f.id in (v_pf, v_m);

  -- ── BJ_REFUSE ──
  perform cmd.assume_identity(v_uid);
  v_r := cmd.battle_join(v_b.id, v_h, 'ATTACKER');
  if v_r ->> 'error_code' is distinct from 'E_BAD_SIDE' then
    raise exception 'PROOF 137 FAIL: a player''s ship could join the pirates: %', v_r;
  end if;
  v_m2st := v_r ->> 'error_code';
  insert into public.battles (kind, site, started_at, resolves_at, status) values ('ATTACK', v_b.site, clock_timestamp() - interval '2 minutes', clock_timestamp() - interval '1 minute', 'RESOLVED')
  returning id into v_fake;
  insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at) values (v_fake, v_h, 'DEFENDER', clock_timestamp() - interval '2 minutes', clock_timestamp() - interval '2 minutes');
  v_r := cmd.battle_join(v_b.id, v_h, 'DEFENDER');
  if v_r ->> 'error_code' is distinct from 'E_AT_PEACE' or v_r ->> 'error_message' not like '%Wait % / 5 min' then
    raise exception 'PROOF 137 FAIL: a ship at peace could join: %', v_r;
  end if;
  raise notice 'PASS: BJ_REFUSE — the pirates'' side: %; at peace: "%"', v_m2st, v_r ->> 'error_message';
  delete from public.battles b where b.id = v_fake;

  -- ── BJ_DOOR ──
  v_k0 := coalesce((v_b.ticks ->> 'k')::int, 0);
  v_na := jsonb_array_length(v_b.sheet -> 'a');
  v_r := cmd.battle_join(v_b.id, v_h, 'DEFENDER');
  if not coalesce((v_r ->> 'ok')::boolean, false) or v_r ->> 'side' <> 'DEFENDER' then
    raise exception 'PROOF 137 FAIL: the player''s ship in the circle could not join the side set upon: %', v_r;
  end if;
  v_tick := (v_r ->> 'from_tick')::int;
  select * into v_b from public.battles b where b.id = v_b.id;
  if not exists (select 1 from public.battle_sides s where s.battle_id = v_b.id and s.fleet_id = v_h and s.side = 'DEFENDER' and s.how = 'JOINED')
     or jsonb_array_length(v_b.sheet -> 'a') <= v_na
     or exists (select 1 from jsonb_array_elements(v_b.sheet -> 'a') with ordinality e(h, o)
                 where o > v_na and ((e.h ->> 'from')::int is distinct from v_tick or e.h ->> 'fleet' is distinct from v_h::text))
     or (v_b.ticks ->> 'k')::int <> v_k0 + 1 then
    raise exception 'PROOF 137 FAIL: her hulls are not on sheet.a from tick %, or the timeline was not re-run (k % -> %)', v_tick, v_k0, v_b.ticks ->> 'k';
  end if;
  if not exists (select 1 from jsonb_array_elements(v_b.ticks -> 'e') e
                  where e ->> 2 = 'J' and (e ->> 0)::int = v_tick and (e ->> 1)::int = 0 and (e ->> 3)::int = v_na) then
    raise exception 'PROOF 137 FAIL: no J event for her at tick % (index %)', v_tick, v_na;
  end if;
  if (select f.busy_until from public.fleets f where f.id = v_h) is distinct from v_b.resolves_at or (select f.status from public.fleets f where f.id = v_h) <> 'IN_BATTLE' then
    raise exception 'PROOF 137 FAIL: the ship that joined is not held to the new end';
  end if;
  raise notice 'PASS: BJ_DOOR — joined DEFENDER from tick % (sheet.a % -> %), re-run k %, J event, held to %', v_tick, v_na, jsonb_array_length(v_b.sheet -> 'a'), v_b.ticks ->> 'k', v_b.resolves_at;

  -- ── BJ_NPC ──
  update public.world_config set value = 'true'::jsonb where key = 'navy_enabled';   -- lit after the open: the raid called nobody
  -- a navy ship (a crown's house of her own, as public.navy_commission makes), at anchor inside the circle
  v_np := public.new_house(null, 'Navio 137', 'PRT', 'LIS', 'Navio 137', 'galion', 'Navio 137', null, true);
  select f.id into v_nv from public.fleets f where f.player_id = v_np;
  insert into public.navy_ships (fleet_id, player_id, nation_id, ord, station_port, last_port, mission)
  select v_nv, f.player_id, g.nation_id, coalesce((select max(n.ord) from public.navy_ships n where n.nation_id = g.nation_id), 0) + 1, v_lis, v_lis, 'PATROL'
    from public.fleets f cross join lateral (select gp.nation_id from public.great_powers gp order by gp.nation_id limit 1) g where f.id = v_nv;
  perform pg_temp.lie_137(v_nv, v_slat - 0.1, v_slon);
  -- a second pirate, cruising at anchor inside the circle
  select q.ord into v_ord2 from public.pirate_roster q
   where q.hub_port = v_hub and q.ord <> v_ord and not exists (select 1 from public.pirate_ships x where x.ord = q.ord) order by q.ord limit 1;
  v_pf2 := public.pirate_commission_fleet(v_ord2, public.refit_yard(v_hub), t0);
  update public.pirate_ships x set sea_id = v_sea, mission = 'CRUISE', laid_up_at = null where x.fleet_id = v_pf2;
  perform pg_temp.lie_137(v_pf2, v_slat - 0.2, v_slon);
  update public.world_config set value = to_jsonb(1) where key in ('battle_join_navy_chance', 'battle_join_pirate_chance');
  update public.world_config set value = to_jsonb(2) where key = 'battle_join_per_battle';
  v_m2st := (select f.status from public.fleets f where f.id = v_m2);
  v_r := public.battle_npc_joins(clock_timestamp());
  if not exists (select 1 from public.battle_sides s where s.battle_id = v_b.id and s.fleet_id = v_nv and s.side = 'DEFENDER' and s.how = 'JOINED')
     or not exists (select 1 from public.battle_sides s where s.battle_id = v_b.id and s.fleet_id = v_pf2 and s.side = 'ATTACKER' and s.how = 'JOINED')
     or (select n.battle_id from public.navy_ships n where n.fleet_id = v_nv) is distinct from v_b.id then
    raise exception 'PROOF 137 FAIL: the NPC rule did not bring the navy ship to the side set upon and the pirate to hers: %', v_r;
  end if;
  if exists (select 1 from public.battle_sides s where s.fleet_id = v_m2)
     or (select f.busy_until from public.fleets f where f.id = v_m2) is not null or (select f.status from public.fleets f where f.id = v_m2) <> v_m2st then
    raise exception 'PROOF 137 FAIL: a merchant in the circle was pulled in or stopped';
  end if;
  raise notice 'PASS: BJ_NPC — %; the merchant in the circle untouched (%)', v_r, v_m2st;

  -- ── BJ_CLOSE ──
  select * into v_b from public.battles b where b.id = v_b.id;
  perform public.tick_battles(v_b.resolves_at + interval '1 second');
  select * into v_b from public.battles b where b.id = v_b.id;
  if v_b.status = 'FIGHTING' then
    raise exception 'PROOF 137 FAIL: the raid did not close at its end';
  end if;
  if exists (select 1 from public.fleets f where f.id in (v_h, v_nv, v_pf2) and f.busy_until is not null)
     or (select n.battle_id from public.navy_ships n where n.fleet_id = v_nv) is not null then
    raise exception 'PROOF 137 FAIL: a ship that joined was not freed';
  end if;
  if (v_b.result #>> '{navy,came}')::int is distinct from 1 then
    raise exception 'PROOF 137 FAIL: the navy line counts % ships, not the one navy ship: %', v_b.result #>> '{navy,came}', v_b.result -> 'navy';
  end if;
  raise notice 'PASS: BJ_CLOSE — % (%); every joiner freed; navy came %', v_b.status, v_b.result ->> 'outcome', v_b.result #>> '{navy,came}';
end
$p$;
