-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 204 - A WRECK CAN SELL  (migration 0497, dark: wreck_sells_enabled; docs/dev-log/2026-11-25-a-wreck-can-sell.md)
--
--   The owner's own company, 25 Nov 01:45 UTC: purse 0; her fleet UNABLE_TO_SAIL at Diego Garcia (no shipyard), hull 0, 899 black
--   coral aboard; her queue SAIL BAN, SAIL MAL, SAIL MAC, SELL black-coral ALL, all pending. This proof plays exactly that state
--   through the real doors (cmd.preview, cmd.issue, cmd.tow, the yard). Rolled back by proof.mjs.
--
-- @pass WS_DARK     dark, as prod is today: her Sell is dry-run "queued", taken with ok, and never runs; the tow is refused for coin (E_TOW_FUNDS): she is stuck
-- @pass WS_SELL     lit: the dry run is a real quote; ONE press runs the SELL already waiting in her queue past the three SAILs (coral out, coin in); the SAILs are neither run nor cancelled; she is still wrecked
-- @pass WS_TRUTH    lit: BUY, SAIL, HIRE and REPAIR for her are refused in plain words and nothing is queued; a second SELL the day's limit refuses is refused by the quay's own rule, not queued
-- @pass WS_STORE    lit: STORE lands her cargo into the warehouse where she lies and TAKE takes it up again
-- @pass WS_TOW      with the coin of that sale the tow takes her to the nearest yard (her queue cleared, the cargo still aboard), the yard quotes her repair, and the coin left covers it
-- @pass WS_OTHERS   lit: a docked fleet sells as before; a wreck at sea, an empty fleet and a merchant's wreck are not alongside
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a   constant uuid := '00000000-0497-4000-8000-0000000002a1';
  c_b   constant uuid := '00000000-0497-4000-8000-0000000002b1';
  v_dga uuid := (select p.id from public.ports p where p.code = 'DGA');
  v_a   uuid; v_f uuid; v_b uuid; v_fb uuid; v_nf uuid;
  v_r   jsonb; v_q jsonb; v_t jsonb; v_y record;
  v_c0  numeric; v_c1 numeric; v_p1 bigint; v_fee bigint; v_n bigint; v_orders text;
begin
  if v_dga is null or public.port_has_shipyard(v_dga)
     or not exists (select 1 from public.port_goods pg join public.goods g on g.id = pg.good_id where pg.port_id = v_dga and g.code = 'black-coral') then
    raise exception 'WS_DARK: Diego Garcia is not the yardless harbour with a black-coral row in this world: the scene proves nothing';
  end if;
  v_a := public.new_house(c_a, 'Casa de Diego 204', 'PRT');
  select f.id into v_f from public.fleets f where f.player_id = v_a;
  perform cmd.assume_identity(c_a);
  -- her state, to the row
  update public.fleets set port_id = v_dga, status = 'DOCKED', ready_at = null where id = v_f;
  perform public.fleet_load(v_f, 'black-coral', 899, 10);
  insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args, status)
  select v_f, v_a, x.i, x.t, split_part(x.t, ' ', 1),
         case when x.t like 'SAIL%' then jsonb_build_object('dest', (select p.id from public.ports p where p.code = split_part(x.t, ' ', 2)))
              else jsonb_build_object('good', (select g.id from public.goods g where g.code = 'black-coral'), 'qty_mode', 'ALL') end, 'pending'
    from (values (1, 'SAIL BAN'), (2, 'SAIL MAL'), (3, 'SAIL MAC'), (4, 'SELL black-coral ALL')) x(i, t);
  update public.ships set durability = 0 where fleet_id = v_f;
  update public.fleets set status = 'UNABLE_TO_SAIL' where id = v_f;
  update public.players set ducats = 0 where id = v_a;
  v_c0 := public.fleet_cargo_qty(v_f, 'black-coral');
  select * into v_y from public.yards_from(v_dga) y order by y.nm, y.code limit 1;
  v_fee := round(v_y.nm * public.wc_num('tow_fee_per_nm') * public.running_cost_mult(v_a))::bigint;

  -- WS_DARK
  begin
    v_q := cmd.preview(v_f, 'SELL black-coral ALL');
    v_r := cmd.issue(v_f, 'SELL black-coral ALL', null, null);
    v_t := cmd.tow(v_f, null);
    if v_q->>'queued' is distinct from 'true' or (v_r->>'ok')::boolean is not true or v_r #>> '{order,status}' is distinct from 'pending'
       or public.fleet_cargo_qty(v_f, 'black-coral') <> v_c0 or (select ducats from public.players where id = v_a) <> 0
       or v_t->>'error_code' is distinct from 'E_TOW_FUNDS' or public.fleet_alongside(v_f) then
      raise exception 'WS_DARK: dark, she is not stuck as prod is: % / % / %', v_q, left(v_r::text, 300), v_t;
    end if;
    raise notice 'PASS: WS_DARK — dry run {queued: true}; the press answers ok and the order stays %; cargo %, purse 0; the tow to % (% nm): % "%"',
      v_r #>> '{order,status}', v_c0, v_y.name, round(v_y.nm), v_t->>'error_code', v_t->>'error_message';
    raise exception using errcode = 'ZW204', message = 'dark part rolled back';
  exception when sqlstate 'ZW204' then null;
  end;

  update public.world_config set value = 'true'::jsonb where key = 'wreck_sells_enabled';

  -- WS_SELL: the dry run, then ONE press (she presses Sell for one coral: her queue's own SELL ALL runs first)
  v_q := cmd.preview(v_f, 'SELL black-coral ALL');
  if (v_q->>'ok')::boolean is not true or v_q ? 'queued' or (v_q #>> '{estimate,qty}')::numeric < 1 or (v_q #>> '{estimate,net}')::numeric <= 0 then
    raise exception 'WS_SELL: lit, the dry run of her SELL is not a real quote: %', v_q;
  end if;
  v_r := cmd.issue(v_f, 'SELL black-coral 1', null, null);
  v_c1 := public.fleet_cargo_qty(v_f, 'black-coral');
  v_p1 := (select ducats from public.players where id = v_a);
  select string_agg(o.raw_text || ':' || o.status, ', ' order by o.seq) into v_orders from public.orders o where o.fleet_id = v_f;
  if v_c1 >= v_c0 or v_p1 <= 0
     or (select o.status from public.orders o where o.fleet_id = v_f and o.seq = 4) <> 'done'
     or (select count(*) from public.orders o where o.fleet_id = v_f and o.verb = 'SAIL' and o.status = 'pending') <> 3
     or exists (select 1 from public.voyages v where v.fleet_id = v_f and v.status = 'SAILING')
     or (select f.status from public.fleets f where f.id = v_f) <> 'UNABLE_TO_SAIL' or public.fleet_state(v_f) <> 'wrecked'
     or (select f.port_id from public.fleets f where f.id = v_f) is distinct from v_dga then
    raise exception 'WS_SELL: lit, her waiting SELL did not run past her SAILs: % (cargo % -> %, purse %)', v_orders, v_c0, v_c1, v_p1;
  end if;
  raise notice 'PASS: WS_SELL — the dry run quotes % coral for % coin; one press: % coral sold for % coin (%), she still % at Diego Garcia',
    v_q #>> '{estimate,qty}', v_q #>> '{estimate,net}', v_c0 - v_c1, v_p1, v_orders, public.fleet_state(v_f);

  -- WS_TRUTH
  v_n := (select count(*) from public.orders o where o.fleet_id = v_f);
  if cmd.issue(v_f, 'BUY black-coral 1', null, null)->>'error_code' is distinct from 'E_NOT_DOCKED'
     or cmd.issue(v_f, 'SAIL BAN', null, null)->>'error_code' is distinct from 'E_NOT_DOCKED'
     or cmd.issue(v_f, 'HIRE 1', null, null)->>'error_code' is distinct from 'E_NOT_DOCKED'
     or cmd.issue(v_f, 'REPAIR', null, null)->>'error_code' is distinct from 'E_NOT_DOCKED'
     or cmd.preview(v_f, 'SAIL BAN')->>'error_code' is distinct from 'E_NOT_DOCKED' or cmd.preview(v_f, 'SAIL BAN') ? 'queued'
     or (select count(*) from public.orders o where o.fleet_id = v_f) <> v_n then
    raise exception 'WS_TRUTH: lit, an order she cannot run was not refused outright: % / %', cmd.preview(v_f, 'SAIL BAN'), cmd.issue(v_f, 'BUY black-coral 1', null, null);
  end if;
  -- the order her press added ran too, or was refused by the quay (its day's limit, nothing left): never left waiting
  if (v_r #>> '{order,status}') not in ('done', 'failed') then
    raise exception 'WS_TRUTH: her own SELL was left waiting: %', left(v_r::text, 300);
  end if;
  raise notice 'PASS: WS_TRUTH — BUY, SAIL, HIRE, REPAIR: "%", nothing queued; her own SELL: % %',
    cmd.preview(v_f, 'SAIL BAN')->>'error_message', v_r #>> '{order,status}', coalesce(v_r->>'error_message', '');

  -- WS_STORE
  update public.orders set status = 'cancelled' where fleet_id = v_f and status = 'failed';
  v_c0 := public.fleet_cargo_qty(v_f, 'black-coral');
  if v_c0 >= 2 then
    v_r := cmd.issue(v_f, 'STORE black-coral 2', null, null);
    v_q := cmd.issue(v_f, 'TAKE black-coral 2', null, null);
    if v_r #>> '{order,status}' is distinct from 'done' or v_q #>> '{order,status}' is distinct from 'done' or public.fleet_cargo_qty(v_f, 'black-coral') <> v_c0 then
      raise exception 'WS_STORE: lit, STORE or TAKE did not run for her: % / %', left(v_r::text, 300), left(v_q::text, 300);
    end if;
    raise notice 'PASS: WS_STORE — STORE 2 % and TAKE 2 % at Diego Garcia''s warehouse; % coral aboard as before', v_r #>> '{order,status}', v_q #>> '{order,status}', v_c0;
  else
    raise notice 'PASS: WS_STORE — every coral was sold: nothing left to land (STORE and TAKE are held by the migration''s own probe)';
  end if;

  -- WS_TOW: the coin of the sale against the tow and the repair
  v_p1 := (select ducats from public.players where id = v_a);
  v_t := cmd.tow(v_f, null);
  if v_p1 >= v_fee then
    v_q := cmd.preview(v_f, 'REPAIR');
    if (v_t->>'ok')::boolean is not true or v_t->>'to' is distinct from v_y.code or (v_t->>'fee')::bigint <> v_fee
       or (select f.status from public.fleets f where f.id = v_f) <> 'DOCKED'
       or exists (select 1 from public.orders o where o.fleet_id = v_f and o.status in ('pending', 'active'))
       or public.fleet_cargo_qty(v_f, 'black-coral') <> v_c0
       or (v_q->>'ok')::boolean is not true or (v_q #>> '{estimate,cost}')::bigint > (select ducats from public.players where id = v_a) then
      raise exception 'WS_TOW: the sale''s coin did not carry her to a yard and a repair: % / %', left(v_t::text, 400), left(v_q::text, 300);
    end if;
    raise notice 'PASS: WS_TOW — purse % covers the tow to % (% nm, fee %); she lies DOCKED there, her SAILs cleared, % coral still aboard; the repair costs % of the % left',
      v_p1, v_y.name, round(v_y.nm), v_fee, v_c0, v_q #>> '{estimate,cost}', (select ducats from public.players where id = v_a);
  else
    raise exception 'WS_TOW: one day''s sale at Diego Garcia (% coin) does not cover the tow to % (%): she would have to sell on a second day', v_p1, v_y.name, v_fee;
  end if;

  -- WS_OTHERS
  v_b := public.new_house(c_b, 'Casa Dois 204', 'PRT');
  select f.id into v_fb from public.fleets f where f.player_id = v_b;
  perform cmd.assume_identity(c_b);
  update public.fleets set port_id = v_dga, status = 'DOCKED', ready_at = null where id = v_fb;
  perform public.fleet_load(v_fb, 'black-coral', 3, 10);
  v_r := cmd.issue(v_fb, 'SELL black-coral 1', null, null);
  select nf.fleet_id into v_nf from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id
   where f.port_id is not null and exists (select 1 from public.ships s where s.fleet_id = f.id) order by nf.fleet_id limit 1;
  update public.fleets set status = 'UNABLE_TO_SAIL' where id = v_nf;
  if not public.fleet_alongside(v_fb) or (v_r #>> '{order,status}') not in ('done', 'failed') or v_r #>> '{order,status}' = 'pending' then
    raise exception 'WS_OTHERS: a docked fleet''s SELL is not what it was: %', left(v_r::text, 300);
  end if;
  update public.fleets set status = 'UNABLE_TO_SAIL', port_id = null, lat = -7, lon = 72 where id = v_fb;
  if public.fleet_alongside(v_fb) or cmd.issue(v_fb, 'SELL black-coral 1', null, null)->>'error_code' is distinct from 'E_NOT_DOCKED'
     or (v_nf is not null and (public.fleet_alongside(v_nf) or public.wreck_order_refusal(v_nf, 'SAIL') is not null))
     or exists (select 1 from public.fleets f where f.status = 'UNABLE_TO_SAIL' and not exists (select 1 from public.ships s where s.fleet_id = f.id) and public.fleet_alongside(f.id)) then
    raise exception 'WS_OTHERS: a wreck at sea, a merchant''s wreck or an empty fleet is treated as alongside';
  end if;
  raise notice 'PASS: WS_OTHERS — a docked fleet''s SELL: %; a wreck at sea: E_NOT_DOCKED, not alongside; a merchant''s wreck: not alongside, told nothing; no empty fleet is alongside', v_r #>> '{order,status}';
end
$p$;
