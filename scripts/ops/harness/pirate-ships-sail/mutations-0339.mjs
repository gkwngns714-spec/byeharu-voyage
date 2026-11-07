// The deliberate breakages of migration 0339: [label, mutate(file), the error it must fail with]. Each must be caught by the file's own self-assert or by proof 46 right after it, for the stated reason.
export const mutations = (swap) => [
  ['the switch ignores the purses', (s) => swap(s, `  select coalesce(public.wc('pirates_bite') = 'true'::jsonb, false) and public.city_treasury_on()`, `  select coalesce(public.wc('pirates_bite') = 'true'::jsonb, false)`), /PROOF 46 FAIL: with no purses/],
  ['the size has no cap', (s) => swap(s, `  select least(public.wc_int('pirate_max'), public.wc_int('pirate_min') + floor(greatest(coalesce(p_hoard, 0), 0)::numeric / public.wc_num('pirate_hoard_unit'))::integer)`, `  select public.wc_int('pirate_min') + floor(greatest(coalesce(p_hoard, 0), 0)::numeric / public.wc_num('pirate_hoard_unit'))::integer`), /0339 self-assert FAIL: the size formula/],
  ['the size is a root', (s) => swap(s, `floor(greatest(coalesce(p_hoard, 0), 0)::numeric / public.wc_num('pirate_hoard_unit'))::integer)`, `floor(sqrt(greatest(coalesce(p_hoard, 0), 0)::numeric / public.wc_num('pirate_hoard_unit')))::integer)`), /0339 self-assert FAIL: the size formula/],
  ['the room ignores the day\'s spend', (s) => swap(s, `                     - coalesce((select d.spent from public.pirate_spend_day d where d.day = (p_now at time zone 'UTC')::date), 0))::bigint`, `                     - 0)::bigint`), /PROOF 46 FAIL: (a payee inside the room|the room was overdrawn|she is not one crewless)/],
  ['the payer ignores the room', (s) => swap(s, `  if public.pirate_spend_room(p_now) < p_amount or public.city_surplus(v_cap) < p_amount then`, `  if public.city_surplus(v_cap) < p_amount then`), /PROOF 46 FAIL: a payee was paid above the room/],
  ['the payer ignores the purse', (s) => swap(swap(s, `  if public.pirate_spend_room(p_now) < p_amount or public.city_surplus(v_cap) < p_amount then`, `  if public.pirate_spend_room(p_now) < p_amount then`), `  if public.city_surplus(v_cap) < p_amount then
    return 0;
  end if;
  if p_player is not null then`, `  if p_player is not null then`), /PROOF 46 FAIL: the capital paid below its reserve/],
  ['the build is minted', (s) => swap(s, `    perform public.treasury_post(v_cap, p_kind, -p_amount, null, null);\n`, ``), /PROOF 46 FAIL: the build is not one class/],
  ['the build vanishes', (s) => swap(s, `    perform public.treasury_post(p_port, p_kind, p_amount, null, null);\n`, ``), /PROOF 46 FAIL: the build is not one class/],
  ['a hull comes with a free crew', (s) => swap(s, `perform public.commission_ship(v_player, v_fleet, v_class, format('Pirate ship %s', p_ord), true, false);`, `perform public.commission_ship(v_player, v_fleet, v_class, format('Pirate ship %s', p_ord), true, true);`), /PROOF 46 FAIL: she is not one crewless hull/],
  ['two ships in a day', (s) => swap(s, `  if v_cap is null or (select c.added_at from public.pirate_clock c) > p_now - make_interval(hours => public.wc_int('navy_build_hours')) then
    return null;
  end if;
`, `  if v_cap is null then
    return null;
  end if;
`), /PROOF 46 FAIL: two ships in a day/],
  ['she answers no kind', (s) => swap(s, `              when exists (select 1 from public.pirate_ships n where n.fleet_id = f.id) then 'PIRATE'   -- 0339: after the navy test, so every other read is what it was\n`, ``), /PROOF 46 FAIL: the kind, the origin/],
  ['she has no origin', (s) => swap(s, `                  (select n.home_port from public.pirate_ships n where n.fleet_id = p_fleet))   -- 0339: a pirate ship's home\n`, `                  null)\n`), /PROOF 46 FAIL: the kind, the origin/],
  ['she is no crown house', (s) => swap(s, `      or exists (select 1 from public.pirate_ships x where x.player_id = p_player)   -- 0339: a pirate ship's house too: no dock fee, no wage, no merchant in the count\n`, ``), /PROOF 46 FAIL: the kind, the origin/],
  ['she is not on the sea', (s) => swap(s, `          select z.player_id, public.pirate_nation(), 'PIRATE' from public.pirate_ships_at_work z) c`, `          select z.player_id, public.pirate_nation(), 'PIRATE' from public.pirate_ships_at_work z where false) c`), /PROOF 46 FAIL: the kind, the origin/],
  ['the sea shows a laid-up ship', (s) => swap(s, `          select z.player_id, public.pirate_nation(), 'PIRATE' from public.pirate_ships_at_work z) c`, `          select z.player_id, public.pirate_nation(), 'PIRATE' from public.pirate_ships z) c`), /PROOF 46 FAIL: unpaid at home she was not laid up and off the sea/],
  ['her own voyage names her', (s) => swap(s, `  select case when not public.pirates_on() or exists (select 1 from public.pirate_ships n where n.fleet_id = p_fleet) then p_segments`, `  select case when not public.pirates_on() then p_segments`), /PROOF 46 FAIL: her own voyage names a raider/],
  ['the freeze ignores the switch', (s) => swap(s, `  select case when not public.pirates_on() or exists (select 1 from public.pirate_ships n where n.fleet_id = p_fleet) then p_segments`, `  select case when exists (select 1 from public.pirate_ships n where n.fleet_id = p_fleet) then p_segments`), /PROOF 46 FAIL: off, a departure named her/],
  ['a named raider fights at the anonymous figure', (s) => swap(s, `                       else voyage.pirate_strength(v_pirate) end;   -- 0339: a named raider fights with her own hulls`, `                       else voyage.leg_danger(v_leg) * 40 * (0.5 + h.magnitude) end;`), /PROOF 46 FAIL: the raid is not hers/],
  ['the stow has no cap', (s) => swap(s, `    v_in := greatest(0, least(r.qty, 2 * v_t - v_s));`, `    v_in := r.qty;`), /PROOF 46 FAIL: the stow is not capped/],
  ['the ransom pays above the purse', (s) => swap(s, `  v_take := least(public.ransom_take(p_basis), greatest(coalesce(v_purse, 0), 0));`, `  v_take := public.ransom_take(p_basis);`), /(PROOF 46 FAIL|E_INSUFFICIENT_FUNDS)/],
  ['the ransom ignores the cap', (s) => swap(s, `  if n.fleet_id is null or p_company is null or not public.city_treasury_on() or public.pirate_hoard() >= public.wc_num('pirate_hoard_cap') then`, `  if n.fleet_id is null or p_company is null or not public.city_treasury_on() then`), /PROOF 46 FAIL: a hoard at the cap took gold/],
  ['the loot is minted', (s) => swap(s, `  perform public.convoy_book('LOOTED', p_victim, c.player_id, (select l.port_id from public.convoy_cargo l where l.id = v_load), v_take, v_load);\n`, ``), /PROOF 46 FAIL: the cargo ship's gold did not land/],
  ['the loot never lands', (s) => swap(s, `  perform public.treasury_post(n.home_port, 'LOOT', v_take, null, p_event, true);\n`, ``), /PROOF 46 FAIL: the cargo ship's gold did not land/],
  ['the pressure outlives her', (s) => swap(s, `  delete from public.sea_pressure sp where not v_lit or not exists (select 1 from public.pirate_ships_at_work x where x.sea_id = sp.sea_id);`, `  delete from public.sea_pressure sp where false;`), /PROOF 46 FAIL: off, a departure named her, the pressure stood/],
  ['the regen holds dark', (s) => swap(s, `  v_pir    boolean := public.pirates_on();   -- 0339: with the pirates lit, a pirate home's stock is plunder, not production (docs/WORLD_POWERS.md 7.6)`, `  v_pir    boolean := true;`), /PROOF 46 FAIL: off, Port Royal's stock did not regenerate/],
  ['the regen never holds', (s) => swap(s, `         stock = case when pg.last_regen_day < v_day and not f.held then public.depth_stock(`, `         stock = case when pg.last_regen_day < v_day then public.depth_stock(`), /PROOF 46 FAIL: lit, Port Royal's stock moved/],
  ['paid twice an hour', (s) => swap(s, `  if (select c.paid_at from public.pirate_clock c) > p_now - interval '1 hour' then
    return 0;
  end if;
`, ``), /PROOF 46 FAIL: paid twice in an hour/],
  ['unpaid she is never marked', (s) => swap(s, `    update public.pirate_ships n set unpaid_since = case when v_paid > 0 then null else coalesce(n.unpaid_since, p_now) end where n.fleet_id = r.fleet_id;`, `    update public.pirate_ships n set unpaid_since = null where n.fleet_id = r.fleet_id;`), /PROOF 46 FAIL: a hoard at 0 paid .*or she was not marked unpaid/],
  ['the card serves anyone', (s) => swap(s, `  if n.fleet_id is null then
    raise exception 'E_NOT_FOUND: there is no such pirate ship' using errcode = 'P0001';
  end if;
`, ``), /PROOF 46 FAIL: the card served a company/],
  ['the pirates write a wanted list', (s) => swap(s, `  if not public.pirate_power(c.nation_id) and (v_out in ('PLUNDERED', 'RANSOM') or not public.navy_arrived(p_battle, c.nation_id, v_d)) then   -- 0339: the pirates keep no wanted list: they have no navy to answer`, `  if v_out in ('PLUNDERED', 'RANSOM') or not public.navy_arrived(p_battle, c.nation_id, v_d) then`), /PROOF 46 FAIL: the battle did not resolve, or the pirates wrote a WANTED row/],
  ['the job builds dark', (s) => swap(s, `  if v_lit then
    begin
      v_add := public.pirate_add(p_now);`, `  if true then
    begin
      v_add := public.pirate_add(p_now);`), /PROOF 46 FAIL: (off, the job wrote something|with no purses)/],
  ['the switch ships on', (s) => swap(s, `    ('pirates_bite', 'false'::jsonb,`, `    ('pirates_bite', 'true'::jsonb,`), /0339 self-assert FAIL: the switch is not off/],
  ['a reader is volatile', (s) => swap(s, `create function public.pirate_ship_in_sea(p_sea uuid)
returns uuid
language sql
stable`, `create function public.pirate_ship_in_sea(p_sea uuid)
returns uuid
language sql
volatile`), /0339 self-assert FAIL: a read is not stable/],
  ['the card is open to anon', (s) => swap(s, `  grant execute on function world.pirate_ship_card(uuid) to authenticated;\n`, `  grant execute on function world.pirate_ship_card(uuid) to authenticated, anon;\n`), /0339 self-assert FAIL: the card is not exactly authenticated-only/],
  // a hunk whose old text is in the live body twice (the `when exists (select 1 from public.` lines of fleet_kind at that indent): the apply loop must refuse it
  ['a hunk occurs twice', (s) => swap(s, `  ('public.fleet_kind(uuid)', 1,
$h$              when exists (select 1 from public.navy_ships n where n.fleet_id = f.id) then 'NAVY'
$h$,`, `  ('public.fleet_kind(uuid)', 1,
$h$              when exists (select 1 from public.$h$,`), /0339 self-assert FAIL: hunk 1 of public.fleet_kind\(uuid\) occurs 2 time/],
  ['a hunk occurs nowhere', (s) => swap(s, `$h$              when exists (select 1 from public.navy_ships n where n.fleet_id = f.id) then 'NAVY'
$h$,
$h$              when exists (select 1 from public.navy_ships n where n.fleet_id = f.id) then 'NAVY'
              when exists (select 1 from public.pirate_ships n where n.fleet_id = f.id) then 'PIRATE'`, `$h$              when exists (select 1 from public.navy_ships n where n.fleet_id = f.id) then 'NAVY ship'
$h$,
$h$              when exists (select 1 from public.navy_ships n where n.fleet_id = f.id) then 'NAVY'
              when exists (select 1 from public.pirate_ships n where n.fleet_id = f.id) then 'PIRATE'`), /0339 self-assert FAIL: hunk 1 of public.fleet_kind\(uuid\) occurs 0 time/],
]
