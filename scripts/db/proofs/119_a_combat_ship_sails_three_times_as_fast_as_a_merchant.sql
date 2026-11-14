-- ══════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 119 - A COMBAT SHIP SAILS THREE TIMES AS FAST AS A MERCHANT  (migration 0422; docs/dev-log/2026-11-15-combat-speed.md)
--
--   A navy ship (navy_ship_class, manned from the quay, as public.navy_commission makes one) and a pirate ship (pirate_ship_class, as
--   public.pirate_commission makes one), and a player's house, put to sea Lisbon to Setubal and back, against the median merchant of this world
--   (voyage.fleet_speed over public.npc_fleets) on the same course. Rolled back with proof.mjs's transaction.
--
-- @pass CS_KNOB         the one authority: fleet_speed_by_kind is {NAVY 4.5, PIRATE 4.5}, read by public.fleet_speed_mult alone; a merchant, a cargo ship and a player's fleet read 1; the door and the reader are not a player's to call
-- @pass CS_SAME_COURSE  on the same course a navy voyage and a pirate voyage each take at most a third of the median merchant's time
-- @pass CS_PLAYER       a player's speed and voyage do not change: her fleet sails at her own speed to the digit with the knob set and with it empty, and so does every player fleet of this world; the door refuses COMPANY
-- @pass CS_RETIME       a navy voyage at sea, moved through the door and back, stands on the same mile at the instant and arrives when she did
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════
do $p$
declare
  v_lis    uuid;
  v_set    uuid;
  v_c1     jsonb;
  v_c2     jsonb;
  v_segs   jsonb;
  v_nm     numeric;
  v_nat    uuid;
  v_pn     uuid;
  v_pp     uuid;
  v_fn     uuid;
  v_fp     uuid;
  v_ha     uuid;
  v_fa     uuid;
  v_vn     uuid;
  v_vp     uuid;
  v_va     uuid;
  v_dep    timestamptz := now();
  v_k      numeric := public.wc_num('time_compression');
  v_merch  numeric;
  v_nmerch int;
  v_tm     numeric;
  v_tn     numeric;
  v_tp     numeric;
  v_ta     numeric;
  v_knob   jsonb;
  v_bad    int;
  v_at     timestamptz;
  v_pos    numeric;
  v_eta    timestamptz;
  v_note   text;
begin
  -- ── CS_KNOB ──
  v_knob := (select value from public.world_config where key = 'fleet_speed_by_kind');
  if v_knob <> '{"NAVY": 4.5, "PIRATE": 4.5}'::jsonb
     or has_function_privilege('authenticated', 'public.fleet_speed_set(text,numeric,timestamp with time zone)', 'execute')
     or has_function_privilege('anon', 'public.fleet_speed_set(text,numeric,timestamp with time zone)', 'execute')
     or has_function_privilege('authenticated', 'public.fleet_speed_mult(uuid)', 'execute')
     or exists (select 1 from public.npc_fleets n where public.fleet_kind(n.fleet_id) = 'MERCHANT' and public.fleet_speed_mult(n.fleet_id) <> 1)
     or exists (select 1 from public.cargo_ships c where public.fleet_speed_mult(c.fleet_id) <> 1) then
    raise exception 'proof 119 CS_KNOB: the knob is % or a merchant, a cargo ship or a door is not as 0422 left it', v_knob;
  end if;
  raise notice 'PASS: CS_KNOB — fleet_speed_by_kind %; every merchant and cargo ship reads 1; the door and the reader are server-only', v_knob;

  -- ── THE SCENE ──
  select id into v_lis from public.ports where code = 'LIS';
  select id into v_set from public.ports where code = 'SET';
  select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon)),
         jsonb_build_array(jsonb_build_array(b.roadstead_lat, b.roadstead_lon), jsonb_build_array(a.roadstead_lat, a.roadstead_lon))
    into v_c1, v_c2 from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_set;
  v_segs := voyage.segments_from_course(v_c1) || voyage.segments_from_course(v_c2);
  select sum((e ->> 'nm')::numeric) into v_nm from jsonb_array_elements(v_segs) e;
  select g.nation_id into v_nat from public.great_powers g order by g.nation_id limit 1;

  -- the median merchant of this world, at the speed she would leave at now
  select percentile_cont(0.5) within group (order by s.kn), count(*) into v_merch, v_nmerch
    from (select voyage.fleet_speed(n.fleet_id) as kn from public.npc_fleets n
           where public.fleet_kind(n.fleet_id) = 'MERCHANT' and exists (select 1 from public.ships sh where sh.fleet_id = n.fleet_id)) s;
  if v_nmerch < 5 or v_merch is null or v_merch <= 0 then
    raise exception 'proof 119: this world has % merchant(s) with a ship to measure against', v_nmerch;
  end if;

  -- a navy ship and a pirate ship, made by the hands public.navy_commission and public.pirate_commission use, manned from the quay
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Proof 119 Navy', v_nat, 0, true) returning id into v_pn;
  v_fn := public.form_fleet(v_pn, 'Proof 119 navy ship', v_lis);
  perform public.commission_ship(v_pn, v_fn, public.wc_text('navy_ship_class'), 'Proof 119 navy ship', true, false);
  insert into public.navy_ships (fleet_id, player_id, nation_id, ord, station_port, last_port) values (v_fn, v_pn, v_nat, 2000000119, v_lis, v_lis);
  perform public.fleet_hands(v_fn, v_lis);
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Proof 119 Pirate', v_nat, 0, true) returning id into v_pp;
  v_fp := public.form_fleet(v_pp, 'Proof 119 pirate ship', v_lis);
  perform public.commission_ship(v_pp, v_fp, public.wc_text('pirate_ship_class'), 'Proof 119 pirate ship', true, false);
  insert into public.pirate_ships (fleet_id, player_id, ord, home_port, last_port) values (v_fp, v_pp, 2000000119, v_lis, v_lis);
  perform public.fleet_hands(v_fp, v_lis);
  v_ha := public.new_house('00000000-0000-4000-8000-000000000119'::uuid, 'Casa Prova', 'PRT');
  select f.id into v_fa from public.fleets f where f.player_id = v_ha limit 1;
  if public.fleet_kind(v_fn) <> 'NAVY' or public.fleet_kind(v_fp) <> 'PIRATE' or public.fleet_kind(v_fa) <> 'COMPANY' then
    raise exception 'proof 119: the scene''s kinds are %, %, %', public.fleet_kind(v_fn), public.fleet_kind(v_fp), public.fleet_kind(v_fa);
  end if;

  -- ── CS_SAME_COURSE ──
  v_vn := voyage.depart(v_fn, v_segs, v_lis, v_lis, v_dep);
  v_vp := voyage.depart(v_fp, v_segs, v_lis, v_lis, v_dep);
  v_va := voyage.depart(v_fa, v_segs, v_lis, v_lis, v_dep);
  v_tm := v_nm / v_merch * 3600 / v_k;
  select extract(epoch from v.eta - v.departed_at) into v_tn from public.voyages v where v.id = v_vn;
  select extract(epoch from v.eta - v.departed_at) into v_tp from public.voyages v where v.id = v_vp;
  select extract(epoch from v.eta - v.departed_at) into v_ta from public.voyages v where v.id = v_va;
  if v_tn > v_tm / 3 or v_tp > v_tm / 3 then
    raise exception 'proof 119 CS_SAME_COURSE: on % nm the median merchant (% kn, of %) takes % s; the navy ship % s (% kn), the pirate ship % s (% kn): not a third',
      round(v_nm), round(v_merch, 2), v_nmerch, round(v_tm, 1), round(v_tn, 1), voyage.fleet_speed(v_fn), round(v_tp, 1), voyage.fleet_speed(v_fp);
  end if;
  raise notice 'PASS: CS_SAME_COURSE — Lisbon-Setubal-Lisbon, % nm: the median of % merchants % kn, % s; the navy ship (%) % kn, % s (% of it); the pirate ship (%) % kn, % s (% of it)',
    round(v_nm), v_nmerch, round(v_merch, 2), round(v_tm, 1), public.wc_text('navy_ship_class'), voyage.fleet_speed(v_fn), round(v_tn, 1), round(v_tn / v_tm, 3),
    public.wc_text('pirate_ship_class'), voyage.fleet_speed(v_fp), round(v_tp, 1), round(v_tp / v_tm, 3);

  -- ── CS_PLAYER ──
  if abs(v_ta - v_nm / voyage.fleet_speed_alone_at(v_fa, null) * 3600 / v_k) > 0.01
     or voyage.fleet_speed(v_fa)::text <> voyage.fleet_speed_alone_at(v_fa, null)::text then
    raise exception 'proof 119 CS_PLAYER: the player''s voyage takes % s at % kn, not her own speed %', v_ta, voyage.fleet_speed(v_fa), voyage.fleet_speed_alone_at(v_fa, null);
  end if;
  create temp table pl_119 on commit drop as
    select f.id, voyage.fleet_speed(f.id)::text as kn from public.fleets f
     where public.fleet_kind(f.id) = 'COMPANY' and not exists (select 1 from public.armada_fleets af where af.fleet_id = f.id)
       and exists (select 1 from public.ships sh where sh.fleet_id = f.id);
  update public.world_config set value = '{}'::jsonb where key = 'fleet_speed_by_kind';
  select count(*) into v_bad from pl_119 p where voyage.fleet_speed(p.id)::text <> p.kn;
  update public.world_config set value = v_knob where key = 'fleet_speed_by_kind';
  if v_bad <> 0 then
    raise exception 'proof 119 CS_PLAYER: % player fleet(s) sail at another speed with the knob set', v_bad;
  end if;
  begin
    perform public.fleet_speed_set('COMPANY', 2, now());
    raise exception 'proof 119 CS_PLAYER: the door moved a player''s speed';
  exception when sqlstate 'P0001' then
    if sqlerrm not like 'E_BAD_SPEED%' then raise; end if;
  end;
  raise notice 'PASS: CS_PLAYER — the player''s voyage % s at her own % kn; % player fleet(s) sail at the same speed to the digit with the knob set and empty; the door refuses COMPANY',
    round(v_ta, 1), voyage.fleet_speed(v_fa), (select count(*) from pl_119);

  -- ── CS_RETIME: the navy voyage, a quarter of the way along her passage, moved back to 1 and forward again at the same instant ──
  select v.eta into v_eta from public.voyages v where v.id = v_vn;
  v_at  := v_dep + (v_eta - v_dep) / 4;
  v_pos := voyage.progress_nm(v_vn, v_at);
  perform public.fleet_speed_set('NAVY', 1, v_at);
  if abs(voyage.progress_nm(v_vn, v_at) - v_pos) > 0.01 or (select v.eta from public.voyages v where v.id = v_vn) <= v_eta then
    raise exception 'proof 119 CS_RETIME: moved to 1 the navy voyage jumped (% nm, was %) or did not slow', voyage.progress_nm(v_vn, v_at), v_pos;
  end if;
  v_note := round(extract(epoch from (select v.eta from public.voyages v where v.id = v_vn) - v_at), 1)::text;
  perform public.fleet_speed_set('NAVY', 4.5, v_at);
  if abs(voyage.progress_nm(v_vn, v_at) - v_pos) > 0.01 or abs(extract(epoch from (select v.eta from public.voyages v where v.id = v_vn) - v_eta)) > 0.05 then
    raise exception 'proof 119 CS_RETIME: moved back to 4.5 the navy voyage is not as she was (% nm, was %; eta %, was %)', voyage.progress_nm(v_vn, v_at), v_pos,
      (select v.eta from public.voyages v where v.id = v_vn), v_eta;
  end if;
  raise notice 'PASS: CS_RETIME — at % nm a quarter of the way: % s left at 1, % s at 4.5 again; the same mile at the instant both times', round(v_pos, 2), v_note,
    round(extract(epoch from v_eta - v_at), 1);
end $p$;
