-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 146 - A SHIP SAILS ON WHEN HER FIGHT ENDS, ON THE MAP TOO  (migration 0444; docs/dev-log/2026-11-16-battle-fix2.md; the owner,
--   2026-11-15: "ships inside the circle still move")
--
--   A crown's cargo ship sails (the real public.cargo_ship_step). She is held as a battle's open holds her (the real voyage.hold, for
--   battle_seconds), and her hold is cut as a battle's close cuts it (the real voyage.hold_cut, to a fight of 40 s). The battle's own row is
--   written by hand, closed: who wins a fight is not what this proof is about. Rolled back with proof.mjs's transaction.
--   FAILS BEFORE 0444 at RS_CUT: once her battle had closed (busy_until null) no delta of the roster served her, so the map kept the
--   ten-minute hold and the eta ten minutes late.
--
-- @pass RS_QUIET  a ship under sail that nothing has happened to is not served by a delta of the roster asked from after her departure
-- @pass RS_HELD   held, she is served by that delta with her hold of battle_seconds and her eta later by as much (0323, unmoved)
-- @pass RS_CUT    her battle closed and her hold cut to the fight's 40 s, the same delta serves her: the hold ends at the fight's end and her eta is the one before the fight plus 40 s
-- @pass RS_AGE    a battle that closed 10 minutes before the delta's instant serves nobody; a full read serves the same fleets with or without a battle
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  t0      timestamptz := now();
  v_since timestamptz := now() + interval '1 second';
  v_secs  numeric;
  v_f     uuid;
  v_v     uuid;
  v_b     uuid;
  v_eta0  timestamptz;
  v_eta   timestamptz;
  v_row   jsonb;
  v_full0 text;
begin
  -- ── THE SCENE (as tests/fightWorld.fixture.ts makes a cargo ship sail) ──
  update public.world_config set value = 'true'::jsonb
   where key in ('attack_enabled', 'convoys_enabled', 'city_treasury_enabled', 'npc_traders_enabled', 'standing_routes_enabled') and value is distinct from 'true'::jsonb;
  v_secs := public.wc_num('battle_seconds');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 50000000, reserve = 0;
  perform public.tick_cargo_ships(t0, n.id) from public.nations n where n.code = 'ESP';
  perform public.tick_cargo_ships(t0, n.id) from public.nations n where n.code = 'ESP';
  perform public.tick_cargo_ships(t0, n.id) from public.nations n where n.code = 'ESP';
  select c.fleet_id into v_f
    from public.cargo_ships c join public.nations n on n.id = c.nation_id join public.fleets f on f.id = c.fleet_id
   where n.code = 'ESP' and f.status = 'DOCKED' and f.busy_until is null
     and not exists (select 1 from public.battle_sides bs where bs.fleet_id = c.fleet_id)
   order by c.ord limit 1;
  if v_f is null then
    raise exception 'PROOF 146 FAIL: no cargo ship of Spain lies in port in this world: the scene cannot be made';
  end if;
  update public.fleets set ready_at = null where id = v_f;
  perform public.convoy_book('LOADED', c.fleet_id, c.player_id, c.home_port_id, 100000) from public.cargo_ships c where c.fleet_id = v_f;
  perform public.cargo_ship_step(v_f, t0);
  -- slowed a hundredfold, so her arrival is far from every instant below
  update public.voyages vo set speed_profile = (select jsonb_agg(to_jsonb(e::text::numeric / 100) order by o) from jsonb_array_elements(vo.speed_profile) with ordinality t(e, o))
   where vo.fleet_id = v_f and vo.status = 'SAILING';
  perform voyage.recompute_eta(vo.id) from public.voyages vo where vo.fleet_id = v_f and vo.status = 'SAILING';
  select vo.id, vo.eta into v_v, v_eta0 from public.voyages vo where vo.fleet_id = v_f and vo.status = 'SAILING';
  if v_v is null or v_eta0 <= t0 + make_interval(secs => (v_secs + 120)::double precision) then
    raise exception 'PROOF 146 FAIL: the cargo ship is not under sail for long enough: voyage %, eta %', v_v, v_eta0;
  end if;
  select md5(string_agg(e ->> 'id', ',' order by e ->> 'id')) into v_full0 from jsonb_array_elements(world.sea_roster(null) -> 'fleets') e;
  if v_full0 is null then
    raise exception 'PROOF 146 FAIL: a full read of the roster serves nobody';
  end if;

  -- ── RS_QUIET ──
  if exists (select 1 from jsonb_array_elements(world.sea_roster(v_since) -> 'fleets') e where (e ->> 'id')::uuid = v_f) then
    raise exception 'PROOF 146 FAIL: a ship nothing happened to is served by a delta from after her departure: the control proves nothing';
  end if;

  raise notice 'PASS: RS_QUIET — under sail and untouched, she is in no delta of the roster asked from after her departure';

  -- ── RS_HELD: as public.battle_open holds her ──
  perform voyage.settle(v_f, t0);
  perform voyage.hold(v_f, t0 + make_interval(secs => v_secs::double precision), t0);
  select e into v_row from jsonb_array_elements(world.sea_roster(v_since) -> 'fleets') e where (e ->> 'id')::uuid = v_f;
  select vo.eta into v_eta from public.voyages vo where vo.id = v_v;
  if v_row is null or jsonb_array_length(coalesce(v_row #> '{voyage,holds}', '[]'::jsonb)) <> 1
     or (v_row #>> '{voyage,holds,0,until}')::timestamptz <> t0 + make_interval(secs => v_secs::double precision)
     or abs(extract(epoch from v_eta - v_eta0) - v_secs) > 1 then
    raise exception 'PROOF 146 FAIL: a held ship is not served with her hold of % s and her eta later by as much: row %, eta % -> %', v_secs, v_row -> 'voyage' -> 'holds', v_eta0, v_eta;
  end if;

  raise notice 'PASS: RS_HELD — held, the delta serves her with one hold of % s and her eta later by as much', v_secs;

  -- ── RS_CUT: as public.battle_resolve closes a fight of 40 s ──
  insert into public.battles (kind, site, started_at, resolves_at, status)
  values ('PROBE', '{"lat": 0, "lon": 0}'::jsonb, t0, t0 + interval '40 seconds', 'RESOLVED') returning id into v_b;
  insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at) values (v_b, v_f, 'DEFENDER', t0, t0);
  update public.fleets f set busy_until = null, version = f.version + 1 where f.id = v_f;
  perform voyage.hold_cut(v_f, t0, t0 + interval '40 seconds');
  select e into v_row from jsonb_array_elements(world.sea_roster(v_since) -> 'fleets') e where (e ->> 'id')::uuid = v_f;
  if v_row is null then
    raise exception 'PROOF 146 FAIL: a ship whose battle has just closed is not served by a delta: the map keeps her ten-minute hold';
  end if;
  if jsonb_array_length(coalesce(v_row #> '{voyage,holds}', '[]'::jsonb)) <> 1
     or (v_row #>> '{voyage,holds,0,from}')::timestamptz <> t0
     or (v_row #>> '{voyage,holds,0,until}')::timestamptz <> t0 + interval '40 seconds'
     or abs(extract(epoch from (v_row #>> '{voyage,eta}')::timestamptz - v_eta0) - 40) > 1 then
    raise exception 'PROOF 146 FAIL: the served row is not the cut hold and the eta of before the fight plus 40 s: holds %, eta % (before the fight %)',
      v_row #> '{voyage,holds}', v_row #>> '{voyage,eta}', v_eta0;
  end if;
  if (select count(*) from jsonb_array_elements(world.sea_roster(v_since) -> 'fleets') e where (e ->> 'id')::uuid = v_f) <> 1 then
    raise exception 'PROOF 146 FAIL: she is served more than once';
  end if;

  raise notice 'PASS: RS_CUT — her battle closed and her hold cut to 40 s, the delta serves her once: hold % to %, eta % (before the fight %)',
    v_row #>> '{voyage,holds,0,from}', v_row #>> '{voyage,holds,0,until}', v_row #>> '{voyage,eta}', v_eta0;

  -- ── RS_AGE ──
  update public.battles set started_at = v_since - interval '11 minutes', resolves_at = v_since - interval '10 minutes' where id = v_b;
  if exists (select 1 from jsonb_array_elements(world.sea_roster(v_since) -> 'fleets') e where (e ->> 'id')::uuid = v_f) then
    raise exception 'PROOF 146 FAIL: a battle that closed 10 minutes before the delta still serves its fleet';
  end if;
  if (select md5(string_agg(e ->> 'id', ',' order by e ->> 'id')) from jsonb_array_elements(world.sea_roster(null) -> 'fleets') e) is distinct from v_full0 then
    raise exception 'PROOF 146 FAIL: a full read of the roster serves other fleets than before';
  end if;

  raise notice 'PASS: RS_AGE — a battle closed 10 minutes before the delta serves nobody, and a full read serves the same fleets as before';
end $p$;
