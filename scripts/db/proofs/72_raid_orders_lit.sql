-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 72 — A FLEET FIGHTS, FLEES OR PAYS, LIT  (migration 0371 lights raid_orders_enabled; 0353 built it)
--
--   Proof 56 proves the rules of the three orders, through voyage.depart and the real settle, in a world it lights itself. This proof does NOT set the switch: it reads it as the
--   chain left it (0371) and goes the way a player goes, through the doors the client calls: cmd.raid_order, world.raid_read, a SAIL through cmd.issue (proof.sail, the client's
--   door, which proof 56 does not use), and a turn at sea through cmd.divert (which the 0353 dev-log lists as not proven). What her voyage then carries is read off the voyage row,
--   and the raid is asked what it would fight under (voyage.raid_opts) and fought through the real skin and engine (voyage.raid_report) on that voyage's own seed.
--
-- @pass LIT_BY_0371        the chain left raid_orders_enabled true, nobody holds an order, the flee knobs are 0.15 and 0.05, and 0371's news row is one row
-- @pass LIT_PICKER_READ    signed in, world.raid_read says on, order FIGHT for a fleet that never chose, her guns, her slip, the price of Pay and the raiders' word by danger
-- @pass LIT_SAIL_FREEZES   Flee set through cmd.raid_order, then a SAIL through the client's door: every segment of the voyage row carries FLEE, and the raid reads FLEE
-- @pass LIT_FLEE_FOUGHT    200 raid days of that voyage through the real engine under her frozen order: her guns never fire, some days she gets away (EVADED, fled), no day is paid
-- @pass LIT_TURN_REFREEZES Pay chosen at sea changes nothing behind her; a turn through cmd.divert writes a voyage frozen PAY
-- @pass LIT_FIGHT_IS_NO_ROW  FIGHT deletes her row, and a merchant's fleet never carries an order
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_auth constant uuid := '00000000-0371-4000-8000-0000000000aa';
  v_pl    uuid;
  v_fl    uuid;
  v_r     jsonb;
  v_voy   uuid;
  v_voy2  uuid;
  v_path  jsonb;
  v_h     jsonb;
  v_esc   numeric;
  v_f     jsonb;
  d       int;
  v_fled  int := 0;
  v_caught int := 0;
  v_slip  int := 0;
  v_fired int := 0;
  v_paid  int := 0;
  pos     record;
  v_seg   jsonb;
begin
  -- AS THE CHAIN LEFT IT
  if not public.raid_orders_on() or (select c.value from public.world_config c where c.key = 'raid_orders_enabled') is distinct from 'true'::jsonb
     or exists (select 1 from public.fleet_raid_orders)
     or public.wc_num('fight_flee_base') <> 0.15 or public.wc_num('fight_flee_floor') <> 0.05
     or (select count(*) from public.world_news w where w.key = 'update:0371') <> 1 then
    raise exception 'PROOF 72 FAIL: the chain did not leave raid_orders_enabled true, no order held, the flee knobs at 0.15 / 0.05 and one news row of 0371';
  end if;
  raise notice 'PASS: LIT_BY_0371 — raid_orders_enabled true, no order held, flee knobs 0.15 / 0.05, one news row "update:0371"';

  -- the fight in rounds is on for this transaction (prod: combat_bite true); no storm takes the voyage
  update public.world_config set value = 'true'::jsonb where key = 'combat_bite';
  update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
  v_pl := public.new_house(c_auth, 'Casa da Prova 72', 'PRT');
  select f.id into v_fl from public.fleets f where f.player_id = v_pl;
  update public.players set ducats = 1000000 where id = v_pl;
  perform cmd.assume_identity(c_auth);

  -- ── THE PICKER'S READ ──
  v_r := world.raid_read(v_fl);
  if (v_r ->> 'on')::boolean is not true or v_r ->> 'order' is distinct from 'FIGHT' or jsonb_typeof(v_r -> 'guns') <> 'boolean'
     or coalesce(v_r ->> 'slip', '') not in ('poor', 'fair', 'good') or jsonb_typeof(v_r -> 'pay') <> 'number' or coalesce(jsonb_array_length(v_r -> 'foes'), 0) < 1
     or exists (select 1 from jsonb_array_elements(v_r -> 'foes') e where coalesce(e ->> 'word', '') not in ('weaker', 'even', 'stronger', 'far_stronger')) then
    raise exception 'PROOF 72 FAIL: lit, the picker''s read for a fleet that never chose: %', v_r;
  end if;
  raise notice 'PASS: LIT_PICKER_READ — on, order FIGHT, guns %, slip %, pay %, % danger level(s) with the raiders'' word', v_r ->> 'guns', v_r ->> 'slip', v_r ->> 'pay', jsonb_array_length(v_r -> 'foes');

  -- ── FLEE, THEN A SAIL THROUGH THE CLIENT'S DOOR ──
  v_r := cmd.raid_order(v_fl, 'FLEE');
  if v_r is distinct from '{"ok": true, "order": "FLEE"}'::jsonb or world.raid_read(v_fl) ->> 'order' is distinct from 'FLEE' then
    raise exception 'PROOF 72 FAIL: the door did not keep Flee: %', v_r;
  end if;
  v_r := proof.sail(v_fl, 'CAD');
  if coalesce((v_r ->> 'ok')::boolean, false) is not true then
    raise exception 'PROOF 72 FAIL: she could not SAIL LIS -> CAD: %', v_r;
  end if;
  select v.id, v.path into v_voy, v_path from public.voyages v where v.fleet_id = v_fl and v.status = 'SAILING';
  if v_voy is null or jsonb_array_length(v_path) < 1 or exists (select 1 from jsonb_array_elements(v_path) e where e ->> 'order' is distinct from 'FLEE')
     or voyage.raid_opts(v_voy, 1, v_fl) ->> 'order' is distinct from 'FLEE' then
    raise exception 'PROOF 72 FAIL: the SAIL did not freeze Flee on every segment, or the raid does not read it: path %, opts %', v_path, voyage.raid_opts(v_voy, 1, v_fl);
  end if;
  raise notice 'PASS: LIT_SAIL_FREEZES — a SAIL through cmd.issue wrote a voyage of % segment(s), each frozen FLEE; the raid reads %', jsonb_array_length(v_path), voyage.raid_opts(v_voy, 1, v_fl);

  -- ── THE RAID, UNDER HER FROZEN ORDER: 200 days of this voyage's own seed, one xebec (12.7), through the real skin and engine ──
  v_h := voyage.fleet_hulls(v_fl);
  v_esc := voyage.escort_score(v_fl);
  for d in 1 .. 200 loop
    v_f := voyage.raid_report(v_voy, d, 12.7, v_esc, v_h, voyage.raid_opts(v_voy, d, v_fl));
    if coalesce((v_f ->> 'fled')::boolean, false) then
      v_fled := v_fled + 1;
      if v_f ->> 'outcome' is distinct from 'EVADED' then
        raise exception 'PROOF 72 FAIL: day % she fled and the outcome is %', d, v_f ->> 'outcome';
      end if;
    elsif v_f -> 'log' ->> 'end' = 'SLIP' then
      v_slip := v_slip + 1;
    else
      v_caught := v_caught + 1;
    end if;
    v_paid := v_paid + case when coalesce((v_f ->> 'paid')::boolean, false) then 1 else 0 end;
    v_fired := v_fired + case when exists (select 1 from jsonb_each_text(coalesce(v_f -> 'raider_hull_lost', '{}'::jsonb)) x where x.value::numeric > 0) then 1 else 0 end;
    if v_f -> 'log' ->> 'order' is distinct from 'FLEE' then
      raise exception 'PROOF 72 FAIL: day % was not fought under Flee: %', d, v_f -> 'log';
    end if;
  end loop;
  if v_fled < 1 or v_caught < 1 or v_paid <> 0 or v_fired <> 0 then
    raise exception 'PROOF 72 FAIL: 200 Flee days: fled %, caught %, slipped at first sight %, paid %, days her guns hit %', v_fled, v_caught, v_slip, v_paid, v_fired;
  end if;
  raise notice 'PASS: LIT_FLEE_FOUGHT — 200 raid days of one xebec under her frozen Flee: away on % (EVADED, fled), caught on %, slipped at first sight on %; no day paid, her guns hit on none', v_fled, v_caught, v_slip;

  -- ── PAY CHOSEN AT SEA, THEN A TURN ──
  v_r := cmd.raid_order(v_fl, 'PAY');
  if v_r ->> 'order' is distinct from 'PAY' or (select v.path from public.voyages v where v.id = v_voy)::text is distinct from v_path::text
     or voyage.raid_opts(v_voy, 1, v_fl) ->> 'order' is distinct from 'FLEE' then
    raise exception 'PROOF 72 FAIL: an order changed at sea moved the water behind her';
  end if;
  -- she turns where she lies, on to a point further along the water she is on (the turn of proof 38)
  select * into pos from voyage.position(v_voy, now());
  v_seg := v_path -> pos.seg_index;
  v_r := cmd.divert(v_fl, null, jsonb_build_object('lat', v_seg -> 'b' -> 0, 'lon', v_seg -> 'b' -> 1),
                    jsonb_build_array(jsonb_build_array(pos.lat, pos.lon), v_seg -> 'b'));
  if coalesce((v_r ->> 'ok')::boolean, false) is not true then
    raise exception 'PROOF 72 FAIL: the turn was refused: %', v_r;
  end if;
  select v.id into v_voy2 from public.voyages v where v.fleet_id = v_fl and v.status = 'SAILING';
  if v_voy2 is null or v_voy2 = v_voy
     or exists (select 1 from jsonb_array_elements((select v.path from public.voyages v where v.id = v_voy2)) e where e ->> 'order' is distinct from 'PAY') then
    raise exception 'PROOF 72 FAIL: the turn did not write a voyage frozen Pay: %', (select v.path from public.voyages v where v.id = v_voy2);
  end if;
  raise notice 'PASS: LIT_TURN_REFREEZES — Pay chosen at sea left the voyage as it was (the raid still read FLEE); the turn through cmd.divert wrote a new voyage, every segment frozen PAY';

  -- ── FIGHT IS NO ROW; A MERCHANT NEVER CARRIES AN ORDER ──
  v_r := cmd.raid_order(v_fl, 'FIGHT');
  if v_r is distinct from '{"ok": true, "order": "FIGHT"}'::jsonb or exists (select 1 from public.fleet_raid_orders o where o.fleet_id = v_fl)
     or exists (select 1 from public.fleet_raid_orders o join public.fleets f on f.id = o.fleet_id join public.players p on p.id = f.player_id where p.is_npc)
     or exists (select 1 from public.voyages v join public.players p on p.id = v.player_id cross join lateral jsonb_array_elements(v.path) e
                 where p.is_npc and v.status = 'SAILING' and e ? 'order') then
    raise exception 'PROOF 72 FAIL: Fight left a row, or a merchant carries an order: %', v_r;
  end if;
  raise notice 'PASS: LIT_FIGHT_IS_NO_ROW — FIGHT deleted her row; no merchant holds an order and no merchant voyage under way carries one';
end
$$;
