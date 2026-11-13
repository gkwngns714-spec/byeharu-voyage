-- cost.sql — WHAT 0362 ADDS TO A CALL, measured: a LOCAL SCENE (it writes; proof-0362.mjs --cost runs it after the file and rolls it back). Not a prod check.
-- The OLD bodies are kept copies in pg_temp (<name>_old_0362), made by the runner from the live bodies with the migration's own hunks reversed, so old and new run in ONE
-- session, interleaved, each call in a subtransaction that is rolled back (the same market, the same hold, the same voyage every time). Means, in milliseconds (PGlite's clock ticks in whole milliseconds: a mean over many calls resolves below the tick).
-- LOCAL PGlite WORLD ONLY (scripts/ops/harness/README.md): it writes. The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite).
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;

create function pg_temp.med(p numeric[]) returns numeric language sql immutable as $b$
  -- the MEAN: PGlite's clock ticks in whole milliseconds, so a median is a whole number; a mean over many calls resolves below the tick
  select round(avg(x), 3) from unnest(p) x
$b$;

create function pg_temp.through_c(p_fleet uuid, p_sea uuid, p_days int) returns jsonb language sql stable as $b$
  select jsonb_agg(jsonb_build_object('a', jsonb_build_array(0, 0), 'b', jsonb_build_array(0, 0), 'nm', voyage.fleet_speed(p_fleet) * 24, 'sea_id', p_sea, 'hazard_mult', 1000))
    from generate_series(1, p_days)
$b$;

do $$
begin
  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_c;
  execute $f$
create function voyage.hazard_roll(p_voyage uuid, p_day integer)
returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
language plpgsql stable
as $b$
declare
  v_s text := coalesce(current_setting('byeharu.proof_sea', true), '');
begin
  return query select v_s <> '', nullif(v_s, ''), 0.5::numeric, 1::numeric;
end
$b$
  $f$;
end
$$;

do $c$
declare
  c_n     constant int := 400;   -- pairs of calls a trade scene
  v_lis   uuid;
  v_hum   uuid;
  v_fl    uuid;
  v_good  uuid;
  v_code  text;
  v_args  jsonb;
  v_sea   uuid;
  v_t     timestamptz;
  v_old   numeric[];
  v_new   numeric[];
  v_x     numeric[];
  v_ms    numeric;
  v_voy   uuid;
  v_pairs int;
  v_r     jsonb;
  i       int;
  k       int;
  v_is_old boolean;
  v_scene text;
  v_hour  timestamptz := '2099-06-07 08:00:00+00';
begin
  select p.id into v_lis from public.ports p where p.code = 'LIS';
  v_hum := public.new_house('00000000-0362-4000-8000-0000000000c1', 'Casa Custo 0362', 'PRT', p_ducats => 300000);
  select f.id into v_fl from public.fleets f where f.player_id = v_hum;
  select g.id, g.code into v_good, v_code
    from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_lis and g.bulk <= 1 and pg.stock_target > 0 and pg.stock >= 20 and public.port_offers(v_lis, g.id)
     and not public.culture_refuses((select p.culture from public.ports p where p.id = v_lis), g.culture_mask)
   order by pg.stock_target desc, g.code limit 1;
  v_args := jsonb_build_object('good', v_good, 'qty', 10);

  -- ── A SALE and A BUY: under the knob (every trade but a handful a day), and a sale above it (told) ──
  foreach v_scene in array array['sale under the knob', 'buy under the knob', 'sale above the knob (told)'] loop
    update public.world_config set value = to_jsonb(case when v_scene like '%above%' then 1 else 250000 end) where key = 'news_big_trade';
    v_old := '{}'; v_new := '{}';
    for i in 1 .. c_n + 10 loop
      for k in 0 .. 1 loop
        v_is_old := (i + k) % 2 = 0;   -- the order alternates
        begin
          if v_scene like 'sale%' then
            perform public.fleet_load(v_fl, v_code, 10, 1);
            v_t := clock_timestamp();
            if v_is_old then perform pg_temp.do_sell_old_0362(v_fl, v_args); else perform cmd.do_sell(v_fl, v_args); end if;
          else
            v_t := clock_timestamp();
            if v_is_old then perform pg_temp.do_buy_old_0362(v_fl, v_args); else perform cmd.do_buy(v_fl, v_args); end if;
          end if;
          v_ms := extract(epoch from clock_timestamp() - v_t) * 1000;
          raise exception using errcode = 'ZX365', message = 'COST_ROLLBACK';
        exception when sqlstate 'ZX365' then
          null;
        end;
        if i > 10 then   -- the first ten pairs warm the plans
          if v_is_old then v_old := v_old || v_ms; else v_new := v_new || v_ms; end if;
        end if;
      end loop;
    end loop;
    raise notice 'COST %: old % ms, new % ms a call (means of % each, interleaved): + % ms', v_scene, pg_temp.med(v_old), pg_temp.med(v_new), c_n, pg_temp.med(v_new) - pg_temp.med(v_old);
  end loop;
  update public.world_config set value = to_jsonb(250000) where key = 'news_big_trade';
  -- the one thing a trade under the knob adds: the knob read and the comparison, alone
  v_t := clock_timestamp();
  for i in 1 .. 20000 loop
    if 1000 >= nullif(public.wc_num('news_big_trade'), 0) then null; end if;
  end loop;
  raise notice 'COST the threshold alone (one public.wc_num read and one comparison): % ms a call (20,000 calls)', round((extract(epoch from clock_timestamp() - v_t) * 1000 / 20000)::numeric, 4);

  -- ── THE SNAPSHOT: a run that folds no hour (three of four runs), and the run that folds one, with every recorded pair holding two hours ──
  select count(*) into v_pairs from public.price_record_pairs();
  perform public.tick_price_snapshot(v_hour + interval '5 minutes');   -- the marks stand at 2099; the hour before is folded
  v_old := '{}'; v_new := '{}';
  for i in 1 .. 8 loop
    for k in 0 .. 1 loop
      v_is_old := (i + k) % 2 = 0;
      begin
        v_t := clock_timestamp();
        if v_is_old then v_r := pg_temp.tick_price_snapshot_old_0362(v_hour + interval '20 minutes'); else v_r := public.tick_price_snapshot(v_hour + interval '20 minutes'); end if;
        v_ms := extract(epoch from clock_timestamp() - v_t) * 1000;
        if (v_r->>'hours')::int <> 0 then raise exception 'cost: the quiet run folded an hour'; end if;
        raise exception using errcode = 'ZX365', message = 'COST_ROLLBACK';
      exception when sqlstate 'ZX365' then
        null;
      end;
      if i > 2 then if v_is_old then v_old := v_old || v_ms; else v_new := v_new || v_ms; end if; end if;
    end loop;
  end loop;
  raise notice 'COST snapshot, no hour folded (% pairs): old % ms, new % ms a run (means of 6 each): + % ms', v_pairs, pg_temp.med(v_old), pg_temp.med(v_new), pg_temp.med(v_new) - pg_temp.med(v_old);
  -- every pair: the hour before at 100, the hour closing at 100, twelve of them at 130 (fine rows, so the real fold writes the hour rows)
  insert into public.price_history_hour (port_id, good_id, hour, ask_o, ask_h, ask_l, ask_c, bid_o, bid_h, bid_l, bid_c, n)
  select pr.port_id, pr.good_id, v_hour - interval '1 hour', 100, 100, 100, 100, 100, 100, 100, 100, 1 from public.price_record_pairs() pr
  on conflict (port_id, good_id, hour) do update set bid_c = 100;
  update public.price_history h set bid = case when z.rn <= 12 then 130 else 100 end
    from (select pr.port_id, pr.good_id, row_number() over (order by pr.port_id, pr.good_id) as rn from public.price_record_pairs() pr) z
   where h.port_id = z.port_id and h.good_id = z.good_id and h.at >= v_hour and h.at < v_hour + interval '1 hour';
  v_old := '{}'; v_new := '{}'; v_x := '{}';
  for i in 1 .. 6 loop
    for k in 0 .. 1 loop
      v_is_old := (i + k) % 2 = 0;
      begin
        v_t := clock_timestamp();
        if v_is_old then v_r := pg_temp.tick_price_snapshot_old_0362(v_hour + interval '65 minutes'); else v_r := public.tick_price_snapshot(v_hour + interval '65 minutes'); end if;
        v_ms := extract(epoch from clock_timestamp() - v_t) * 1000;
        if (v_r->>'hours')::int <> v_pairs then raise exception 'cost: the folding run folded % hour rows, not %', v_r->>'hours', v_pairs; end if;
        if not v_is_old and (select count(*) from public.world_news w where w.kind = 'PRICE_SPIKE') <> 5 then raise exception 'cost: the folding run did not tell five spikes'; end if;
        if not v_is_old then   -- the leaf alone, on the hour rows the fold just wrote (it tells nothing more: the five are quiet)
          v_t := clock_timestamp();
          perform public.news_price_spikes(v_hour + interval '1 hour', v_hour + interval '65 minutes');
          v_x := v_x || (extract(epoch from clock_timestamp() - v_t) * 1000)::numeric;
        end if;
        raise exception using errcode = 'ZX365', message = 'COST_ROLLBACK';
      exception when sqlstate 'ZX365' then
        null;
      end;
      if i > 1 then if v_is_old then v_old := v_old || v_ms; else v_new := v_new || v_ms; end if; end if;
    end loop;
  end loop;
  raise notice 'COST snapshot, the run that folds an hour (% pairs, 12 spikes, 5 told; once an hour): old % ms, new % ms a run (means of 5 each): + % ms; public.news_price_spikes alone % ms',
    v_pairs, pg_temp.med(v_old), pg_temp.med(v_new), pg_temp.med(v_new) - pg_temp.med(v_old), pg_temp.med(v_x);

  -- ── A PASSAGE OF 12 RAID DAYS through the real settle, a company with cargo (the fight lit, every raid anonymous) ──
  update public.world_config set value = 'true'::jsonb where key = 'combat_bite';
  update public.world_config set value = 'false'::jsonb where key in ('pirates_bite', 'navy_enabled', 'attack_enabled', 'npc_refits_enabled', 'raid_orders_enabled');
  v_sea := (select s.id from public.seas s order by s.piracy_index desc, s.code limit 1);
  update public.ships s set water_t = 100000, food_t = 100000, cargo = '{"baltic-amber": 10}'::jsonb, cargo_basis = '{"baltic-amber": 2000}'::jsonb where s.fleet_id = v_fl;
  v_old := '{}'; v_new := '{}';
  for i in 1 .. 10 loop
    for k in 0 .. 1 loop
      v_is_old := (i + k) % 2 = 0;
      begin
        v_voy := voyage.depart(v_fl, pg_temp.through_c(v_fl, v_sea, 12), v_lis, v_lis, '2026-03-04 05:06:07+00');
        update public.voyages set id = '00000000-0362-4000-8000-0000000000cc' where id = v_voy;
        perform set_config('byeharu.proof_sea', 'PIRATES', true);
        v_t := clock_timestamp();
        if v_is_old then perform pg_temp.settle_old_0362(v_fl, (select o.eta from public.voyages o where o.fleet_id = v_fl and o.status = 'SAILING'));
        else perform voyage.settle(v_fl, (select o.eta from public.voyages o where o.fleet_id = v_fl and o.status = 'SAILING')); end if;
        v_ms := extract(epoch from clock_timestamp() - v_t) * 1000;
        perform set_config('byeharu.proof_sea', '', true);
        if not v_is_old and i = 10 then
          raise notice 'COST the passage told % PIRATES row(s) over 12 raid days (% of them lost cargo)',
            (select count(*) from public.world_news w where w.kind = 'PIRATES'),
            (select count(*) from public.voyage_events e where e.voyage_id = '00000000-0362-4000-8000-0000000000cc' and e.payload ? 'cargo_lost');
        end if;
        raise exception using errcode = 'ZX365', message = 'COST_ROLLBACK';
      exception when sqlstate 'ZX365' then
        null;
      end;
      perform set_config('byeharu.proof_sea', '', true);
      if i > 2 then if v_is_old then v_old := v_old || v_ms; else v_new := v_new || v_ms; end if; end if;
    end loop;
  end loop;
  raise notice 'COST a passage of 12 raid days and its arrival, a company with cargo: old % ms, new % ms (means of 8 each): + % ms a passage, + % ms a raid day',
    pg_temp.med(v_old), pg_temp.med(v_new), pg_temp.med(v_new) - pg_temp.med(v_old), round((pg_temp.med(v_new) - pg_temp.med(v_old)) / 12, 3);
end
$c$;
