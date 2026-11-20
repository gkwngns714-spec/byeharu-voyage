-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 166 - EVERY HOUSE IS CUT  (migration 0463; docs/dev-log/2026-11-20-hot-set.md)
--   public.tick_compact called a computer house due only by her oldest LEDGER row, so a house with no ledger (a navy or pirate
--   fleet) was never due and only the first ~75 ids of the hour's sweep were ever cut: 70 % of prod's voyages were older than
--   the 3-hour cut. 0463 makes her oldest ended voyage count. Everything rolls back (proof.mjs).
--
-- @pass CUT_LEDGERLESS_GOES   a house with a new ledger row and ended voyages from 2 days to 4 hours back loses every one past the cut, run by run, walked 6 hours a visit
-- @pass CUT_RECENT_STAYS      her voyages inside the cut, her SAILING voyage and her events of a kept kind stay; the voyage_events of a gone voyage go with it
-- @pass CUT_PLAYER_UNTOUCHED  a player's old ended voyages are not touched
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  v_a    uuid;
  v_h    uuid;
  v_fa   uuid;
  v_fh   uuid;
  v_p1   uuid := (select p.id from public.ports p where p.kind = 'HARBOUR' order by p.code limit 1);
  v_p2   uuid := (select p.id from public.ports p where p.kind = 'HARBOUR' order by p.code offset 1 limit 1);
  v_now  timestamptz := now();
  v_n    int;
  v_runs int := 0;
  v_kind text := (select code from public.voyage_event_kinds order by code limit 1);
begin
  if not public.npc_traders_on() then
    update public.world_config set value = 'true'::jsonb
     where key in ('npc_traders_enabled', 'standing_routes_enabled') and value is distinct from 'true'::jsonb;
  end if;
  if not public.npc_traders_on() then raise exception 'PROOF 166 FAIL: cannot light the merchants'; end if;
  v_a := public.new_house(null, 'Casa Cortada A 0463', 'PRT', 'LIS', p_ducats => 1000, p_is_npc => true);
  v_h := public.new_house(null, 'Companhia Humana 0463', 'PRT', 'LIS', p_ducats => 1000, p_is_npc => false);
  v_fa := (select f.id from public.fleets f where f.player_id = v_a limit 1);
  v_fh := (select f.id from public.fleets f where f.player_id = v_h limit 1);
  -- the NPC house: ended voyages 48 h ... 4 h back (all past the 3 h cut but the last two), one ended 1 h back, one still sailing is not possible on a docked fleet: skip
  insert into public.voyages (fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id, created_at)
  select v_fa, v_a, '[]', 100, '{}', v_now - make_interval(hours => h + 1), v_now - make_interval(hours => h), 'ARRIVED', v_p1, v_p2, v_now - make_interval(hours => h + 1)
    from unnest(array[48, 40, 30, 20, 10, 5, 1]) h;
  insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at)
  select v.id, 1, v_kind, '{}', v.eta from public.voyages v where v.fleet_id in (v_fa, v_fh);
  insert into public.voyages (fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id, created_at)
  select v_fh, v_h, '[]', 100, '{}', v_now - interval '3 days', v_now - interval '2 days', 'ARRIVED', v_p1, v_p2, v_now - interval '3 days';
  -- her ledger has one row, of now: before 0463 she was never due
  if (select count(*) from public.ledger l where l.player_id = v_a and l.created_at < v_now - interval '1 hour') <> 0 then
    raise exception 'PROOF 166 FAIL: the probe house has an old ledger row';
  end if;
  loop
    exit when v_runs >= 12;
    call public.tick_compact(false, false);
    v_runs := v_runs + 1;
    exit when (select count(*) from public.voyages v where v.fleet_id = v_fa and v.eta < v_now - interval '3 hours') = 0;
  end loop;
  select count(*) into v_n from public.voyages v where v.fleet_id = v_fa and v.eta < v_now - interval '3 hours';
  if v_n <> 0 then
    raise exception 'PROOF 166 FAIL: % old ended voyage(s) of a house with a new ledger are left after % runs', v_n, v_runs;
  end if;
  raise notice 'PASS: CUT_LEDGERLESS_GOES — six voyages past the cut gone in % compactor run(s)', v_runs;

  select count(*) into v_n from public.voyages v where v.fleet_id = v_fa;
  if v_n <> 1 or exists (select 1 from public.voyage_events e join public.voyages v on v.id = e.voyage_id where v.fleet_id = v_fa and v.eta < v_now - interval '3 hours')
     or (select count(*) from public.voyage_events e join public.voyages v on v.id = e.voyage_id where v.fleet_id = v_fa) <> 1 then
    raise exception 'PROOF 166 FAIL: the house should keep exactly her voyage of 1 h ago and its one voyage_event (voyages %)', v_n;
  end if;
  raise notice 'PASS: CUT_RECENT_STAYS — the voyage inside the cut and its voyage_event stay, the others'' voyage_events went';

  if (select count(*) from public.voyages v where v.fleet_id = v_fh) <> 1 then
    raise exception 'PROOF 166 FAIL: a player''s voyage was touched';
  end if;
  raise notice 'PASS: CUT_PLAYER_UNTOUCHED — a player''s old ended voyage stands';
end $p$;
