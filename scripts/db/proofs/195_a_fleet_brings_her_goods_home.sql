-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 195 - A FLEET BRINGS HER GOODS HOME  (migration 0492; docs/design/hq-corp-2026-11-24.md slice 0492 `assign-bring-home`;
--             docs/dev-log/2026-11-24-assign-bring-home.md)
--
--   The migration's self-assert plays one bring-home run up to her departure. This proof plays the job as a company lives it, through
--   the real tick and her real arrivals: a bring-home job of two runs from Lisbon (her home): out to the buy harbour, the BUY, home, the
--   STORE into the Lisbon warehouse at the price she paid, out again, the second load home, the count spent and the job cleared; then a
--   full warehouse stops a job before it buys; then a warehouse that fills while she sails refuses her STORE and the cargo stays aboard.
--   Rolled back by proof.mjs. A voyage is brought home by moving its clock back (proof 184's way); the read that follows settles her.
--
-- @pass AH_SET      lit: a bring-home job of two runs is set: sell = her home harbour, left = 2; her report shows it
-- @pass AH_LAP      out, BUY ALL / SAIL home / STORE ALL, home: the Lisbon warehouse gains every unit she bought, at the price she paid
-- @pass AH_COUNT    the second loaded run counts left to 0; after its delivery the next turn clears the job (receipt: done)
-- @pass AH_FULL     a full home warehouse stops a bring-home job at the buy harbour (E_SHED_FULL, "stopped" in her report), nothing bought
-- @pass AH_KEEP     a warehouse that fills while she sails: her STORE is refused (E_SHED_FULL), the cargo stays aboard, the job stops on it
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a     constant uuid := '00000000-0492-4000-8000-0000000001a1';
  v_lis   uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_a     uuid;
  v_fa    uuid;
  v_x     uuid;
  v_xc    text;
  g       record;
  v_r     jsonb;
  v_rep   jsonb;
  v_j     record;
  v_texts text;
  v_q0    numeric;
  v_q1    numeric;
  v_bq    numeric;
  v_bt    numeric;
  v_orders bigint;
  v_room  numeric;
  k       int;
  n       int;
begin
  -- THE SEA IS CALMED for this transaction (hazard_p_max 0, as proofs 04, 11, 157 and 184): a voyage's days are rolled on its own id, new
  -- every run, and a storm, a calm or a raid on a leg moves her days, her stores, her hold or her crew (about one sea-day in 70 meets
  -- something; with a raid on every day this proof went red, 2026-11-25). What is proved here is not the weather.
  update public.world_config set value = to_jsonb(0) where key = 'hazard_p_max';
  if public.wc_num('hazard_p_max') <> 0 then
    raise exception 'PROOF 195: the sea was not calmed (hazard_p_max %)', public.wc_num('hazard_p_max');
  end if;
  v_a := public.new_house(c_a, 'Casa do Armazem 195', 'PRT');
  select f.id into v_fa from public.fleets f where f.player_id = v_a;
  update public.players p set ducats = 2000000 where p.id = v_a;
  update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'assign_home_enabled');
  perform cmd.assume_identity(c_a);
  -- the buy harbour: Lisbon's nearest merchant lane both ways; the good: the one it offers most
  select k2.to_port, k2.code into v_x, v_xc from public.npc_known_legs(v_lis) k2 join public.ports p on p.id = k2.to_port
   where p.kind = 'HARBOUR' and public.fleet_job_course(v_fa, k2.to_port, v_lis) is not null order by k2.nm, k2.code limit 1;
  select gg.id, gg.code, gg.bulk into g from public.port_goods pg join public.goods gg on gg.id = pg.good_id
   where pg.port_id = v_x and public.port_offers(v_x, gg.id) and pg.stock > 0 and gg.bulk > 0
     and not public.culture_refuses((select p.culture from public.ports p where p.id = v_x), gg.culture_mask)
   order by pg.stock_target desc, gg.code limit 1;

  -- AH_SET
  v_r := cmd.set_fleet_job(v_fa, 'fixed', jsonb_build_object('good', g.code, 'buy', v_xc, 'end', 'store', 'times', 2));
  v_rep := world.away_report();
  if (v_r->>'ok')::boolean is not true or v_r #>> '{params,sell}' <> 'LIS' or v_r #>> '{params,left}' <> '2' or v_r #>> '{params,end}' <> 'store'
     or v_rep #> '{jobs,0,params}' is distinct from v_r->'params' then
    raise exception 'AH_SET: the bring-home job was not set to Lisbon with two runs: % / %', v_r, left(v_rep::text, 400);
  end if;
  raise notice 'PASS: AH_SET — % bought at %, brought home to LIS, 2 runs: %', g.code, v_xc, v_r->'params';

  -- AH_LAP + AH_COUNT: four turns (out, the loaded run, out, the loaded run), each sailed to its end; then the clearing turn
  v_q0 := coalesce((select ps.qty from public.player_storage ps where ps.player_id = v_a and ps.port_id = v_lis and ps.good_id = g.id), 0);
  for k in 1 .. 4 loop
    call public.tick_fleet_jobs(false);
    select * into v_j from public.fleet_jobs j where j.fleet_id = v_fa;
    select string_agg(o.raw_text, ' / ' order by o.seq) into v_texts from public.orders o where o.fleet_id = v_fa and o.plan_id = v_j.last_plan;
    if v_j.runs <> k or v_texts is distinct from (case when k in (1, 3) then format('SAIL %s', v_xc)
                                                       else format('BUY %s ALL / SAIL LIS / STORE %s ALL', g.code, g.code) end)
       or (v_j.params->>'left')::int <> (case when k < 2 then 2 when k < 4 then 1 else 0 end) then
      raise exception 'AH_LAP: turn % sent % (job %)', k, v_texts, to_jsonb(v_j);
    end if;
    if k in (2, 4) then
      select (e.payload->>'qty')::numeric, (e.payload->>'total')::numeric into v_bq, v_bt
        from public.events e where e.player_id = v_a and e.kind = 'BOUGHT' order by e.created_at desc, e.id desc limit 1;
    end if;
    for n in 1 .. 12 loop
      exit when (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING';
      update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
       where fleet_id = v_fa and status = 'SAILING';
      perform world.fleets();
    end loop;
    if exists (select 1 from public.orders o where o.fleet_id = v_fa and o.status in ('pending', 'active', 'failed'))
       or (select p.code from public.fleets f join public.ports p on p.id = f.port_id where f.id = v_fa) is distinct from (case when k in (1, 3) then v_xc else 'LIS' end) then
      raise exception 'AH_LAP: after turn % she lies at % with %', k, (select p.code from public.fleets f join public.ports p on p.id = f.port_id where f.id = v_fa),
        (select jsonb_agg(jsonb_build_object('t', o.raw_text, 's', o.status, 'e', o.error_code) order by o.seq) from public.orders o where o.fleet_id = v_fa);
    end if;
    if k = 2 then
      v_q1 := (select ps.qty from public.player_storage ps where ps.player_id = v_a and ps.port_id = v_lis and ps.good_id = g.id);
      if v_q1 is distinct from v_q0 + v_bq or public.fleet_cargo_qty(v_fa, g.code) <> 0
         or round((select ps.basis from public.player_storage ps where ps.player_id = v_a and ps.port_id = v_lis and ps.good_id = g.id), 4)
            is distinct from round(v_bt / v_bq, 4) then
        raise exception 'AH_LAP: the warehouse holds % (was %, bought %), basis % against % paid each', v_q1, v_q0, v_bq,
          (select ps.basis from public.player_storage ps where ps.player_id = v_a and ps.port_id = v_lis and ps.good_id = g.id), v_bt / v_bq;
      end if;
      raise notice 'PASS: AH_LAP — out to %, BUY % ALL (% units for % = % each) / SAIL LIS / STORE: the Lisbon warehouse % -> %, at % each',
        v_xc, g.code, v_bq, v_bt, round(v_bt / v_bq, 2), v_q0, v_q1,
        round((select ps.basis from public.player_storage ps where ps.player_id = v_a and ps.port_id = v_lis and ps.good_id = g.id), 2);
    end if;
  end loop;
  call public.tick_fleet_jobs(false);
  if exists (select 1 from public.fleet_jobs j where j.fleet_id = v_fa)
     or (select r.receipt #>> '{steps,0,wait}' from public.fleet_job_runs r order by r.at desc limit 1) is distinct from 'done'
     or (select ps.qty from public.player_storage ps where ps.player_id = v_a and ps.port_id = v_lis and ps.good_id = g.id) <= v_q1 then
    raise exception 'AH_COUNT: two runs done, the job was not cleared: %', (select r.receipt from public.fleet_job_runs r order by r.at desc limit 1);
  end if;
  raise notice 'PASS: AH_COUNT — the second load stored (warehouse %), left 0, the next turn cleared the job (receipt: done)',
    (select ps.qty from public.player_storage ps where ps.player_id = v_a and ps.port_id = v_lis and ps.good_id = g.id);

  -- AH_FULL: at the buy harbour, the Lisbon warehouse filled to the last unit of the good: the job stops before it buys
  update public.fleets set port_id = v_x where id = v_fa;
  v_room := floor((public.storage_cap(v_lis) - public.storage_used(v_a, v_lis)) / g.bulk);
  if v_room >= 1 then
    perform public.storage_put(v_a, v_lis, g.id, v_room, 1);
  end if;
  v_r := cmd.set_fleet_job(v_fa, 'fixed', jsonb_build_object('good', g.code, 'buy', v_xc, 'end', 'store'));
  v_orders := (select count(*) from public.orders o where o.fleet_id = v_fa);
  call public.tick_fleet_jobs(false);
  v_rep := world.away_report();
  if (v_r->>'ok')::boolean is not true or v_rep #>> '{jobs,0,state}' <> 'stopped' or v_rep #>> '{jobs,0,paused}' <> 'E_SHED_FULL'
     or v_rep #>> '{jobs,0,last,sentence}' <> 'the warehouse at LIS is full'
     or (select count(*) from public.orders o where o.fleet_id = v_fa) <> v_orders or public.fleet_cargo_qty(v_fa, g.code) <> 0 then
    raise exception 'AH_FULL: a full warehouse did not stop the job before the buy: % / %', v_r, left(v_rep::text, 400);
  end if;
  raise notice 'PASS: AH_FULL — the Lisbon warehouse full (% of % t): stopped E_SHED_FULL "%", nothing bought',
    public.storage_used(v_a, v_lis), public.storage_cap(v_lis), v_rep #>> '{jobs,0,last,sentence}';

  -- AH_KEEP: room again (the good taken out), she buys and sails; while she sails the warehouse fills; her STORE is refused, nothing lost
  perform public.storage_take(v_a, v_lis, g.id, (select ps.qty from public.player_storage ps where ps.player_id = v_a and ps.port_id = v_lis and ps.good_id = g.id));
  v_r := cmd.set_fleet_job(v_fa, 'fixed', jsonb_build_object('good', g.code, 'buy', v_xc, 'end', 'store'));
  call public.tick_fleet_jobs(false);
  v_bq := public.fleet_cargo_qty(v_fa, g.code);
  v_room := floor((public.storage_cap(v_lis) - public.storage_used(v_a, v_lis)) / g.bulk);
  perform public.storage_put(v_a, v_lis, g.id, v_room, 1);
  for n in 1 .. 12 loop
    exit when (select f.status from public.fleets f where f.id = v_fa) <> 'SAILING';
    update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
     where fleet_id = v_fa and status = 'SAILING';
    perform world.fleets();
  end loop;
  call public.tick_fleet_jobs(false);
  v_rep := world.away_report();
  if v_bq < 1 or public.fleet_cargo_qty(v_fa, g.code) <> v_bq
     or (select p.code from public.fleets f join public.ports p on p.id = f.port_id where f.id = v_fa) is distinct from 'LIS'
     or v_rep #>> '{jobs,0,paused}' is distinct from 'E_SHED_FULL' or v_rep #>> '{jobs,0,state}' <> 'stopped' then
    raise exception 'AH_KEEP: a STORE into a full warehouse did not keep the cargo aboard and stop the job: aboard % of %, %', public.fleet_cargo_qty(v_fa, g.code), v_bq,
      left(v_rep::text, 400);
  end if;
  raise notice 'PASS: AH_KEEP — the warehouse filled while she sailed: STORE refused (E_SHED_FULL: %), % units still aboard, the job stopped',
    v_rep #>> '{jobs,0,last,sentence}', v_bq;
end
$p$;
