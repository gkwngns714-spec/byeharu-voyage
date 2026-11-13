-- npc-scene.sql — WHAT LIGHTING GEAR WEAR DOES TO THE MERCHANTS: a LOCAL SCENE (it writes; run.mjs rolls it back).
--   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/gear-wear/run.mjs --fixtures scripts/ops/harness/gear-wear/npc-scene.sql
-- The question (2026-11-13): do merchants repair, and does wear slowly cripple them? By the code they are EXEMPT: the one writer of wear
-- (public.wear_units_for) is called from voyage.settle's arrival arm inside the players-only block, so a merchant's fitting stays at wear 0, her
-- figures are counted whole and her repair door finds no fitting to mend. This scene shows it through the real jobs instead of reading it:
--   1. every NPC hull's world.ship_stats is digested dark, then again with gear_wear_bite lit: the two digests are equal (lighting moves no NPC figure);
--   2. with the switch lit, the sea's hazards ON (storms and pirates are what wear a fitting) and a sample of the roster started, the merchants sail
--      through the real arrivals beat and lap-start pass, as proof 12 drives them (each beat: every merchant at sea arrives now, every rested one is due);
--   3. printed: voyages arrived, miles, STORM and PIRATES days met, the wear a COMPANY's fittings would have taken from those same voyages by the
--      knobs, the wear the merchants' fittings really hold (0), their repairs and how many carried a fittings bill (0), and the digest once more
--      over the hulls that did not sail.
-- Each world rolls its own sea, so the counts move; the three zeroes do not depend on a roll (no path writes them). Nothing asserts an outcome of a roll.
-- LOCAL PGlite WORLD ONLY (scripts/ops/harness/README.md): it writes. The first statement refuses a real server.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;

do $v$
declare
  v_t0      timestamptz := clock_timestamp();
  v_dark    text;
  v_lit     text;
  v_round   int;
  v_done    int := 0;
  v_fleets  int;
  m         record;
  v_units   int;
  v_worn    int;
  v_maxwear numeric;
  v_rep     int;
  v_rep_g   int;
begin
  select count(*), count(*) filter (where u.wear > 0) into v_units, v_worn
    from public.fitted_units u join public.ships s on s.id = u.ship_id join public.players p on p.id = s.player_id and p.is_npc;
  raise notice 'NPC before: % fittings on NPC hulls, % of them worn', v_units, v_worn;

  -- 1. the figures of every NPC hull, dark and lit
  select md5(string_agg(s.id::text || world.ship_stats(s.id)::text, '|' order by s.id)) into v_dark
    from public.ships s join public.players p on p.id = s.player_id and p.is_npc;
  update public.world_config set value = 'true'::jsonb where key = 'gear_wear_bite';
  select md5(string_agg(s.id::text || world.ship_stats(s.id)::text, '|' order by s.id)) into v_lit
    from public.ships s join public.players p on p.id = s.player_id and p.is_npc;
  raise notice 'NPC figures: % NPC hulls digested dark % and lit %: %', (select count(*) from public.ships s join public.players p on p.id = s.player_id and p.is_npc),
    left(v_dark, 10), left(v_lit, 10), case when v_dark = v_lit then 'EQUAL (lighting moves no NPC figure)' else 'DIFFERENT' end;

  -- 2. the merchants sail, the sea's hazards on, the switches that send raiders lit
  update public.world_config set value = 'true'::jsonb where key in ('standing_routes_enabled', 'pirates_bite', 'combat_bite', 'npc_refits_enabled');
  update public.world_config set value = to_jsonb(0) where key = 'npc_laps_per_game_day';
  perform proof.pin_market('00000000-0158-4000-8000-0000000000dd'::uuid, 'scene-gear-wear-fixture', 'gw58u1:', 'gw58u2:');
  update public.world_config set value = to_jsonb(60) where key = 'npc_fleet_max';
  perform public.npc_traders_switch(true);
  select count(*) into v_fleets from public.standing_routes sr join public.players p on p.id = sr.player_id and p.is_npc where sr.fleet_id is not null;
  for v_round in 1 .. 40 loop
    update public.voyages v set departed_at = v.departed_at - (v.eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
      from public.fleets f join public.players p on p.id = f.player_id and p.is_npc
     where v.fleet_id = f.id and v.status = 'SAILING';
    update public.standing_routes sr set hold_until = now() - interval '1 second'
      from public.players p where p.id = sr.player_id and p.is_npc and sr.hold_until is not null;
    update public.fleets f set status = 'DOCKED', busy_until = null   -- the yard's hours are skipped, as the sea's are
      from public.players p where p.id = f.player_id and p.is_npc and f.status = 'REPAIRING';
    perform public.tick_arrivals(now());
    call public.tick_lap_starts(false);
    v_done := v_done + 1;
    exit when clock_timestamp() - v_t0 > interval '240 seconds';
  end loop;

  -- 3. what those voyages were, and what they wore
  select count(*) as voyages, coalesce(round(sum(v.total_nm)), 0) as nm,
         coalesce(sum((select count(*) from public.voyage_events ve where ve.voyage_id = v.id and ve.kind = 'STORM')), 0) as storms,
         coalesce(sum((select count(*) from public.voyage_events ve where ve.voyage_id = v.id and ve.kind = 'PIRATES')), 0) as pirates,
         count(distinct v.fleet_id) as sailed
    into m
    from public.voyages v join public.players p on p.id = v.player_id and p.is_npc
   where v.status = 'ARRIVED' and v.created_at >= now();
  select count(*) filter (where u.wear > 0), coalesce(max(u.wear), 0) into v_worn, v_maxwear
    from public.fitted_units u join public.ships s on s.id = u.ship_id join public.players p on p.id = s.player_id and p.is_npc;
  select count(*), count(*) filter (where e.payload ? 'gear') into v_rep, v_rep_g
    from public.events e join public.players p on p.id = e.player_id and p.is_npc
   where e.kind = 'REPAIRING' and e.created_at >= now();
  raise notice 'NPC sailed: % merchant fleets started, % beats, % voyages arrived by % fleets, % nm, % STORM days, % PIRATES days',
    v_fleets, v_done, m.voyages, m.sailed, m.nm, m.storms, m.pirates;
  raise notice 'NPC a company on those same voyages would have taken: canvas and rigging % wear points a fleet in all (miles), the low rack % (storms), the high rack % (pirates)',
    round(m.nm / 1000 * public.wc_num('gear_wear_per_1000nm') / greatest(m.sailed, 1), 2),
    round(m.storms * public.wc_num('gear_wear_per_storm') / greatest(m.sailed, 1), 2), round(m.pirates * public.wc_num('gear_wear_per_fight') / greatest(m.sailed, 1), 2);
  raise notice 'NPC after: % of the merchants'' fittings worn (the most worn at %); % merchant repairs, % of them with a fittings bill; wrecked or refitting hulls: %',
    v_worn, v_maxwear, v_rep, v_rep_g,
    (select count(*) from public.fleets f join public.players p on p.id = f.player_id and p.is_npc where f.status not in ('DOCKED', 'SAILING', 'ANCHORED'));
  raise notice 'NPC verdict: % (% ms)',
    case when v_worn = 0 and v_rep_g = 0 and v_dark = v_lit then 'EXEMPT: no merchant fitting wears, no merchant pays for fittings, lighting moves no NPC figure'
         else 'NOT EXEMPT: read the lines above' end,
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$v$;
