-- 0429 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number, add "-- news: none"
-- and deploy it as any migration (owner only).
-- QUICK WAY BACK, no file: pirate_cargo_ships 0 (no new pirate cargo ship and none loaded; those out deliver or bring their gold home),
-- pirate_wakes_per_run 0, pirate_hoard_floor 2000000000 (every payment of the hoard is back under the day's room), pirate_spend_day_pct 0.006.
-- This draft also reverses the nine hunks (each checked once) and drops the two functions. The allotment is NOT taken back: it was moved gold,
-- the cities hold and spend it. The pirate cargo ships stay as rows (their book is the ledger's); with pirate_cargo_ships 0 they lie at Port Royal.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  v_h   record;
  x     record;
  v_def text;
begin
  create temp table hunks_r0429 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_r0429 values
  ('public.pirate_pay(text,bigint,timestamp with time zone,uuid,uuid)', 1,
$h$  if public.pirate_spend_room(p_now) < p_amount or public.city_surplus(v_cap) < p_amount then
    return 0;
  end if;$h$,
$h$  -- 0429 (the owner, 2026-11-15: "pirates should never be laid up"): an hour's pay, a wreck's refit and a 0339 hull are paid while the hoard stays at or
  -- above pirate_hoard_floor after the payment, whatever the day's room says; the room bounds every other kind. Every payment is still written to the day.
  if (case when p_kind in ('NAVY_PAY', 'REFIT', 'BUILD_NAVY') then public.pirate_hoard() - p_amount < public.wc_num('pirate_hoard_floor')::bigint
           else public.pirate_spend_room(p_now) < p_amount end)
     or public.city_surplus(v_cap) < p_amount then
    return 0;
  end if;$h$),
  ('public.pirate_add(timestamp with time zone)', 1,
$h$    if public.pirate_spend_room(p_now) < v_slice or public.city_surplus(v_cap) < v_slice then$h$,
$h$    if public.pirate_hoard() - v_slice < public.wc_num('pirate_hoard_floor')::bigint or public.city_surplus(v_cap) < v_slice then   -- 0429: a wake waits on the hoard's floor, not the day's room$h$),
  ('public.tick_pirates(timestamp with time zone)', 1,
$h$         || case when v_lit and current_setting('byeharu.pirate_traded', true) is distinct from 'on' then jsonb_build_object('struck', public.pirate_strikes(p_now)) else '{}'::jsonb end;$h$,
$h$         || case when v_lit and current_setting('byeharu.pirate_traded', true) is distinct from 'on' then jsonb_build_object('struck', public.pirate_strikes(p_now)) else '{}'::jsonb end
         -- 0429: the wake and the pirate cargo ships (public.pirate_purse_step, which never raises), as the strikes
         || case when v_lit and current_setting('byeharu.pirate_traded', true) is distinct from 'on' then jsonb_build_object('purses', public.pirate_purse_step(p_now)) else '{}'::jsonb end;$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 1,
$h$      perform public.cargo_hull(p_fleet);   -- 0328: idle at home, no load: the one moment her hull may change
      return public.cargo_rebase(p_fleet, f.port_id, f.ready_at, p_now);$h$,
$h$      perform public.cargo_hull(p_fleet);   -- 0328: idle at home, no load: the one moment her hull may change
      if public.pirate_power(c.nation_id) then
        return 'IDLE';   -- 0429: a pirate cargo ship's home is Port Royal, always: she never takes a new one
      end if;
      return public.cargo_rebase(p_fleet, f.port_id, f.ready_at, p_now);$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 2,
$h$      v_give := least(public.city_aid_target(f.port_id) - public.treasury_balance(f.port_id), v_left);$h$,
$h$      v_give := least(case when public.pirate_power(c.nation_id) then public.wc_num('pirate_city_purse')::bigint   -- 0429: a pirate city is topped up to pirate_city_purse
                           else public.city_aid_target(f.port_id) end - public.treasury_balance(f.port_id), v_left);$h$),
  ('public.cargo_circuit_plan(uuid,uuid,uuid)', 1,
$h$          union select p.id from public.ports p where p.kind = 'HARBOUR' and (p.id = p_to or (p_to is null and public.city_capital(p.id) = v_cap))) x;$h$,
$h$          union select p.id from public.ports p where p.kind = 'HARBOUR' and (p.id = p_to or (p_to is null and (public.city_capital(p.id) = v_cap
                                                                                                           -- 0429: the pirates keep no capital that aids (public.city_capital): their stops are their harbours
                                                                                                           or (public.pirate_power(p_nation) and public.port_nation(p.id) = p_nation))))) x;$h$),
  ('public.cargo_circuit_plan(uuid,uuid,uuid)', 2,
$h$                   where p.kind = 'HARBOUR' and p.id <> v_start and (p.id = p_to or (p_to is null and public.city_capital(p.id) = v_cap)) order by p.code);$h$,
$h$                   where p.kind = 'HARBOUR' and p.id <> v_start and (p.id = p_to or (p_to is null and (public.city_capital(p.id) = v_cap
                                                                                         or (public.pirate_power(p_nation) and public.port_nation(p.id) = p_nation)))) order by p.code);   -- 0429$h$),
  ('voyage.freeze_raiders(jsonb,uuid)', 1,
$h$  select case when not public.pirates_on() or exists (select 1 from public.pirate_ships n where n.fleet_id = p_fleet) then p_segments$h$,
$h$  select case when not public.pirates_on() or exists (select 1 from public.pirate_ships n where n.fleet_id = p_fleet)
                   or coalesce(public.crown_nation(p_fleet) = public.pirate_nation(), false) then p_segments   -- 0429: nor a ship of the pirates' own country (their cargo ships)$h$),
  ('voyage.hazard_roll(uuid,integer)', 1,
$h$      v_sea, r_kind using errcode = 'P0001';
  end if;
$h$,
$h$      v_sea, r_kind using errcode = 'P0001';
  end if;

  -- 0429: a cargo ship of the pirates' own country is never raided by pirates: her PIRATES day passes her by (read only on such a day)
  if kind = 'PIRATES' and exists (select 1 from public.voyages v join public.cargo_ships c on c.fleet_id = v.fleet_id
                                   where v.id = p_voyage and public.pirate_power(c.nation_id)) then
    occurred := false;
    kind := null;
  end if;
$h$);

  for v_h in select h.fn from hunks_r0429 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), chr(13), '');
    for x in select * from hunks_r0429 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception 'rollback-0429 refuses: hunk % of % is not in the live body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    execute v_def;
  end loop;
  drop function public.pirate_purse_step(timestamptz);
  drop function public.pirate_purses_allot(timestamptz);
  update public.world_config set value = to_jsonb(0) where key in ('pirate_cargo_ships', 'pirate_wakes_per_run');
  update public.world_config set value = to_jsonb(2000000000) where key = 'pirate_hoard_floor';
  update public.world_config set value = to_jsonb(0.006) where key = 'pirate_spend_day_pct' and value = to_jsonb(0.01);
  raise notice 'rollback-0429 ok: the nine hunks reversed, the two functions dropped; no cargo ship, no wake, the floor out of reach, the room %',
    public.wc_num('pirate_spend_day_pct');
  drop table hunks_r0429;
end $r$;
