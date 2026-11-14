-- 0410 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number, add "-- news: none" and
-- deploy it as any migration (owner only). It reverses 0410's six hunks: public.npc_leg_lines no longer sizes a parcel by the sink city's purse,
-- public.port_call no longer writes the dock fee into the open lap and cmd.standing_route_close_lap no longer takes a lap's fees from its net.
-- The column standing_route_laps.fees and the table public.lap_costs STAY (nothing reads them then; proof 105 must be withdrawn with the same PR).
-- Each hunk's NEW text must occur once in the live body (else it refuses: a later file re-cut the same lines and this draft is stale).
-- To reverse the planner alone (the part that changes which parcels merchants carry), keep rows 1 to 4 and drop rows 5 and 6.
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  h      record;
  v_def  text;
  v_n    int;
begin
  perform set_config('statement_timeout', '20s', true);
  perform set_config('lock_timeout', '5s', true);
  create temp table back_0410 (ord int primary key, fn text, new text, old text) on commit drop;
  insert into back_0410 values
  (1, 'public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)',
$h$  v_cost    numeric := 0;   -- 0406: what the kept parcels cost her here (the buy quotes' totals)
  v_room    numeric;        -- 0410: what the sink's purse can still pay for this leg's parcels (null while the purses are dark)
  v_haul    numeric;        -- 0410: the haul the purse's part of a sale is cut by (the door's: 1 while the economy is closed)
  v_due     numeric;        -- 0410: what the sink's purse pays of this parcel's sale
  v_shrunk  int;            -- 0410: the times this parcel was shrunk to fit
$h$,
$h$  v_cost    numeric := 0;   -- 0406: what the kept parcels cost her here (the buy quotes' totals)
$h$),
  (2, 'public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)',
$h$  select * into k_to   from world.quote_terms(p_to, null, null);
  -- 0410: THE SINK'S PURSE, read once a leg: THE live balance the sale door reads (public.treasury_balance, cmd.do_sell 0122). The door sells
  -- a city only what its purse can pay and refuses E_CITY_BROKE past it; a parcel sized past it was bought, refused there and let go at a loss.
  if public.city_treasury_on() then
    v_room := greatest(public.treasury_balance(p_to), 0);
  end if;
$h$,
$h$  select * into k_to   from world.quote_terms(p_to, null, null);
$h$),
  (3, 'public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)',
$h$      continue when v_q < 1;
      -- 0410: AND NO MORE THAN THE SINK'S PURSE CAN PAY FOR, by the door's own measure: the purse pays round(total / haul) of a sale (0174),
      -- the whole total while the economy is closed (0233). q_size is the sale of at least v_q units, so a parcel it shows to fit spends no
      -- quote; one that does not is shrunk by what it is over (the price rises as the lot shrinks, so again, six times at most) and is
      -- not kept when it still does not fit. What the purse has left falls by every parcel kept on this leg (below).
      if v_room is not null then
        continue when v_room < 1;
        v_haul   := case when public.economy_closed() then 1 else public.cargo_haul(p_to, v_good) end;
        v_due    := round(q_size.total / v_haul);
        v_shrunk := 0;
        while v_due > v_room and v_q >= 1 and v_shrunk < 6 loop
          select * into q_sell from world.quote_priced(p_to, v_good, v_q, 'sell', null, null,
                                                       k_to.q_spread, k_to.q_nohag, k_to.q_tax, k_to.q_bidf);
          v_due := round(q_sell.total / v_haul);
          exit when v_due <= v_room;
          v_q := least(v_q - 1, floor(v_q * v_room / v_due));
          v_shrunk := v_shrunk + 1;
        end loop;
        continue when v_q < 1 or v_due > v_room;
      end if;
      select * into q_buy from world.quote_priced(p_from, v_good, v_q, 'buy', null, null,
$h$,
$h$      continue when v_q < 1;
      select * into q_buy from world.quote_priced(p_from, v_good, v_q, 'buy', null, null,
$h$),
  (4, 'public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)',
$h$      v_cost   := v_cost + q_buy.total;     -- 0406
      if v_room is not null then   -- 0410: the purse pays this parcel first
        v_room := v_room - round(q_sell.total / v_haul);
      end if;
$h$,
$h$      v_cost   := v_cost + q_buy.total;     -- 0406
$h$),
  (5, 'public.port_call(uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,uuid)',
$h$  if v_fee > 0 then
    -- 0410: THE LAP'S BOOK KEEPS THE FEE (standing_route_laps.fees; written here and nowhere else): the open lap of this fleet's route, when
    -- she sails one. The fee charged, paid or owed. A lap closes after its last arrival's call, so every call of the lap is in it.
    update public.standing_route_laps x set fees = x.fees + v_fee
     where x.id = (select sr.lap_id from public.standing_routes sr where sr.fleet_id = p_fleet and sr.lap_id is not null);
    select pl.ducats into v_purse from public.players pl where pl.id = p_player for update;
$h$,
$h$  if v_fee > 0 then
    select pl.ducats into v_purse from public.players pl where pl.id = p_player for update;
$h$),
  (6, 'cmd.standing_route_close_lap(uuid,timestamp with time zone)',
$h$         net = v_sold - v_bought - v_supp - v_rep - v_wages + v_out - v_in - v_taxes - v_insure
               - l.fees,   -- 0410: the dock fees of the lap's calls (public.port_call wrote them; public.lap_costs is the list)
$h$,
$h$         net = v_sold - v_bought - v_supp - v_rep - v_wages + v_out - v_in - v_taxes - v_insure,
$h$);
  for h in select * from back_0410 order by ord desc loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new);
    if v_n <> 1 then
      raise exception 'rollback 0410 refuses: hunk % of % occurs % time(s) in the live body, not once', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.new, h.old);
  end loop;
  if exists (select 1 from back_0410 b where position('0410' in pg_get_functiondef(b.fn::regprocedure)) > 0) then
    raise exception 'rollback 0410 FAIL: something of 0410 is left in the three bodies';
  end if;
  raise notice 'rollback 0410 ok: the six hunks reversed; the leg planner sizes a parcel as 0406 left it and a lap''s net is before dock fees again';
end $r$;
