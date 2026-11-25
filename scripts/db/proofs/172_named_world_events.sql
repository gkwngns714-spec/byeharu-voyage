-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 172 - NAMED WORLD EVENTS  (migration 0469; docs/design/playable-2026-11-22.md P2; docs/dev-log/2026-11-22-world-events.md)
--
--   Dark and lit, through the buff-calendar job's own call (public.tick_buff_calendar, which ends in public.tick_world_events), the want
--   reader (world.want_left) as the market (world.market) and a quote (world.quote) read it, the published cut (world.spread) and the
--   client's read (world.world_events), rolled back with proof.mjs's transaction. A closed economy and no drawn wants, so a want
--   served is the event's alone.
--
-- @pass WE_DARK      dark: the job's call names nothing, the read is {"on": false}, a famine row written by hand acts on nothing
-- @pass WE_NAME      lit: the job's call names one event at a harbour an hour ahead, with its world news; the read lists it (not live yet);
--                    a second call in the slot names none
-- @pass WE_FAMINE    lit: a running famine at the first harbour showing food, grain and cloth: the market's food row says wanted 2, a grain row too, a cloth row nothing; a sale's
--                    quote is about double
-- @pass WE_FESTIVAL  lit: a running festival at the next showing drink and food: a drink row wanted 1.75, a food row nothing
-- @pass WE_BLOCKADE  lit: a running blockade at Cadiz adds 0.20 to its cut, in world.spread and in world.market's port line
-- @pass WE_LIMITS    lit: at the most at once the job names none; an event ended more than a day ago is deleted, one ended an hour
--                    ago is kept
-- @pass WE_OFF       switched off: the want, the toll and the read are dark again at once
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  v_lis   uuid;   -- the famine's harbour: the first whose quay shows food (a stock to sell into), grain and cloth
  v_opo   uuid;   -- the festival's: the first other whose quay shows drink and food
  v_cad   uuid := (select p.id from public.ports p where p.code = 'CAD');
  v_food  uuid;
  v_grain uuid;
  v_cloth uuid;
  v_drink uuid;
  v_ofood uuid;
  v_qty   numeric;
  v_q0    numeric;
  v_q1    numeric;
  v_left  numeric;
  v_sp0   numeric;
  v_at    timestamptz := '2099-03-01 00:20:00+00';
  v_slot  bigint;
  v_r     jsonb;
  v_m     jsonb;
  v_ev    jsonb;
begin
  -- THE MARKET IS PINNED (proof.pin_market, scripts/db/market-fixture.mjs: the one authority, this proof's own key), its drift slot
  -- parked a day ahead. The famine's sale is held against the plain sale quoted BEFORE the event, and world.market, read between the
  -- two, winds the drift of a harbour whose slot is behind the clock: a random() step (0010) on the very price compared. Unpinned, the
  -- same sale read x1.89 to x2.08 of the plain one over eighteen runs, with 0498 and without (PR #865's red, 2026-11-25: 16.50 ->
  -- 36.56, x2.22, past the 10 % allowed); pinned it is x2.00 every run. Every assertion is as it was.
  if (proof.pin_market('00000000-0469-4000-8000-000000000172'::uuid, 'proof-172') ->> 'nonzero')::int < 14000 then
    raise exception 'PROOF 172 FAIL: the market was not pinned';
  end if;
  select p.id into v_lis from public.ports p
   where p.kind = 'HARBOUR' and p.code <> 'CAD'
     and exists (select 1 from public.port_goods pg join public.goods g on g.id = pg.good_id
                  where pg.port_id = p.id and g.category = 'food' and pg.stock_target >= 40 and pg.stock > 0 and public.quay_shows(pg.port_id, pg.good_id))
     and exists (select 1 from public.port_goods pg join public.goods g on g.id = pg.good_id
                  where pg.port_id = p.id and g.category = 'grain' and public.quay_shows(pg.port_id, pg.good_id))
     and exists (select 1 from public.port_goods pg join public.goods g on g.id = pg.good_id
                  where pg.port_id = p.id and g.category = 'cloth' and public.quay_shows(pg.port_id, pg.good_id))
   order by p.code limit 1;
  select p.id into v_opo from public.ports p
   where p.kind = 'HARBOUR' and p.id is distinct from v_lis and p.code <> 'CAD'
     and exists (select 1 from public.port_goods pg join public.goods g on g.id = pg.good_id
                  where pg.port_id = p.id and g.category = 'drink' and public.quay_shows(pg.port_id, pg.good_id))
     and exists (select 1 from public.port_goods pg join public.goods g on g.id = pg.good_id
                  where pg.port_id = p.id and g.category = 'food' and public.quay_shows(pg.port_id, pg.good_id))
   order by p.code limit 1;
  if v_lis is null or v_opo is null or v_cad is null then
    raise exception 'PROOF 172 FAIL: no harbour shows food, grain and cloth, or none other drink and food, or Cadiz is missing';
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'city_wants';
  update public.world_config set value = 'true'::jsonb where key = 'economy_closed';
  delete from public.active_buffs ab where ab.source like 'event:%';
  delete from public.city_want_fills where port_id in (v_lis, v_opo);

  select pg.good_id into v_food from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_lis and g.category = 'food' and pg.stock_target >= 40 and pg.stock > 0 and public.quay_shows(pg.port_id, pg.good_id) order by g.code limit 1;
  select pg.good_id into v_grain from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_lis and g.category = 'grain' and public.quay_shows(pg.port_id, pg.good_id) order by g.code limit 1;
  select pg.good_id into v_cloth from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_lis and g.category = 'cloth' and public.quay_shows(pg.port_id, pg.good_id) order by g.code limit 1;
  select pg.good_id into v_drink from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_opo and g.category = 'drink' and public.quay_shows(pg.port_id, pg.good_id) order by g.code limit 1;
  select pg.good_id into v_ofood from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_opo and g.category = 'food' and public.quay_shows(pg.port_id, pg.good_id) order by g.code limit 1;
  if v_food is null or v_grain is null or v_cloth is null or v_drink is null or v_ofood is null then
    raise exception 'PROOF 172 FAIL: the scene''s goods are not on the quays (food %, grain %, cloth %, drink %, festival food %)', v_food, v_grain, v_cloth, v_drink, v_ofood;
  end if;
  v_qty := least(10, floor(0.25 * (select pg.stock_target from public.port_goods pg where pg.port_id = v_lis and pg.good_id = v_food)));
  update public.port_goods set want_period = coalesce(want_period, public.want_period(now())) where port_id = v_lis and good_id = v_food;
  select q.avg_price into v_q0 from world.quote(v_lis, v_food, v_qty, 'sell', null, null) q;
  v_sp0 := world.spread(v_cad);

  -- ── DARK ──
  if public.wc('world_events_enabled') <> 'false'::jsonb then
    raise exception 'PROOF 172 FAIL: the switch is not dark in the shipped world';
  end if;
  update public.world_config set value = '1'::jsonb where key = 'world_event_chance';
  perform public.tick_buff_calendar(v_at);
  if exists (select 1 from public.active_buffs ab where ab.source like 'event:%') or world.world_events() <> '{"on": false}'::jsonb then
    raise exception 'PROOF 172 FAIL: dark, the job named an event or the read served one';
  end if;
  insert into public.active_buffs (kind_code, subject_id, season, starts_at, ends_at, source)
    values ('FAMINE', v_lis, null, now() - interval '1 minute', now() + interval '2 hours', 'event:proof-172-a');
  if exists (select 1 from world.want_left(v_lis, v_food)) then
    raise exception 'PROOF 172 FAIL: dark, a famine row acted';
  end if;
  delete from public.active_buffs ab where ab.source = 'event:proof-172-a';
  raise notice 'PASS: WE_DARK — the job''s call named nothing, {"on": false}, a famine row written by hand moved no want';

  -- ── LIT: THE JOB NAMES ONE ──
  update public.world_config set value = 'true'::jsonb where key = 'world_events_enabled';
  v_slot := floor(extract(epoch from v_at) / public.wc_num('world_event_slot_seconds'))::bigint;
  perform public.tick_buff_calendar(v_at);
  select to_jsonb(ab) into v_ev from public.active_buffs ab where ab.source = 'event:' || v_slot;
  if v_ev is null
     or (v_ev ->> 'starts_at')::timestamptz <> v_at + make_interval(secs => public.wc_num('world_event_lead_seconds'))
     or (v_ev ->> 'ends_at')::timestamptz <> (v_ev ->> 'starts_at')::timestamptz + make_interval(secs => (select k.duration_seconds from public.buff_kinds k where k.code = v_ev ->> 'kind_code'))
     or not exists (select 1 from public.ports p where p.id = (v_ev ->> 'subject_id')::uuid and p.kind = 'HARBOUR')
     or (v_ev ->> 'kind_code') not in ('FAMINE', 'FESTIVAL', 'BLOCKADE') then
    raise exception 'PROOF 172 FAIL: lit, the job did not name one event at a harbour an hour ahead: %', v_ev;
  end if;
  if not exists (select 1 from public.world_news w
                  where w.key = 'world-event:' || (v_ev ->> 'id') and w.kind = 'EVENT_' || (v_ev ->> 'kind_code') and w.scope = 'world' and w.importance = 3
                    and w.port_id = (v_ev ->> 'subject_id')::uuid and w.detail -> 'words' -> 'city' ->> 'kind' = 'port') then
    raise exception 'PROOF 172 FAIL: lit, the event has no world news';
  end if;
  perform public.tick_buff_calendar(v_at + interval '5 minutes');
  if (select count(*) from public.active_buffs ab where ab.source like 'event:%') <> 1 then
    raise exception 'PROOF 172 FAIL: lit, a second call in the slot named another event';
  end if;
  raise notice 'PASS: WE_NAME — % named at % an hour ahead, its news posted, a second call in the slot named none',
    v_ev ->> 'kind_code', (select p.code from public.ports p where p.id = (v_ev ->> 'subject_id')::uuid);
  -- the read speaks of now; the named one starts in 2099, so it is listed, not live
  v_r := world.world_events();
  if (v_r ->> 'on')::boolean is not true
     or not exists (select 1 from jsonb_array_elements(v_r -> 'events') e where e ->> 'id' = v_ev ->> 'id' and not (e ->> 'live')::boolean) then
    raise exception 'PROOF 172 FAIL: lit, the read does not list the named event as announced: %', v_r;
  end if;

  -- ── LIT: A FAMINE AT LISBON ──
  insert into public.active_buffs (kind_code, subject_id, season, starts_at, ends_at, source)
    values ('FAMINE', v_lis, null, now() - interval '1 minute', now() + interval '2 hours', 'event:proof-172-f');
  update public.port_goods set want_period = coalesce(want_period, public.want_period(now())) where port_id = v_lis and good_id in (v_grain, v_cloth);
  v_m := world.market(v_lis);
  if (select (e ->> 'wanted')::numeric from jsonb_array_elements(v_m -> 'goods') e where (e ->> 'good_id')::uuid = v_food) is distinct from 2
     or (select (e ->> 'wanted')::numeric from jsonb_array_elements(v_m -> 'goods') e where (e ->> 'good_id')::uuid = v_grain) is distinct from 2
     or (select e ? 'wanted' from jsonb_array_elements(v_m -> 'goods') e where (e ->> 'good_id')::uuid = v_cloth) then
    raise exception 'PROOF 172 FAIL: lit, the market''s rows do not say the famine (food x2, grain x2, cloth nothing)';
  end if;
  select q.avg_price into v_q1 from world.quote(v_lis, v_food, v_qty, 'sell', null, null) q;
  -- only the units LEFT at the famine's cap (its 25 % less what was sold there this period) are paid x2, the rest at the plain price
  -- (0255's walk). A world whose merchants sold food at Lisbon this period leaves fewer than v_qty (main's red, 2026-11-22: 16.50 → 29.16,
  -- x1.77): the expected multiple is the served one, (2·min(left, qty) + rest) / qty, within 10 %.
  select least(v_qty, greatest(0, w.left_units)) into v_left from world.want_left(v_lis, v_food) w;
  v_left := coalesce(v_left, 0);
  if v_q0 is null or v_q1 is null or v_left <= 0
     or v_q1 < v_q0 * (2 * v_left + (v_qty - v_left)) / v_qty * 0.9 or v_q1 > v_q0 * (2 * v_left + (v_qty - v_left)) / v_qty * 1.1 then
    raise exception 'PROOF 172 FAIL: lit, a sale of % at the famine (% of them left at x2) is not paid as served (dark %, lit %)', v_qty, v_left, v_q0, v_q1;
  end if;
  raise notice 'PASS: WE_FAMINE — % food and grain rows wanted x2, cloth nothing; a sale of % quoted % a unit (was %)', (select p.code from public.ports p where p.id = v_lis), v_qty, round(v_q1, 2), round(v_q0, 2);

  -- ── LIT: A FESTIVAL AT PORTO ──
  insert into public.active_buffs (kind_code, subject_id, season, starts_at, ends_at, source)
    values ('FESTIVAL', v_opo, null, now() - interval '1 minute', now() + interval '2 hours', 'event:proof-172-v');
  if (select w.mult from world.want_left(v_opo, v_drink) w) is distinct from 1.75 or exists (select 1 from world.want_left(v_opo, v_ofood)) then
    raise exception 'PROOF 172 FAIL: lit, the festival''s want is not drink x1.75 alone';
  end if;
  raise notice 'PASS: WE_FESTIVAL — %''s drink wanted x1.75, its food nothing', (select p.code from public.ports p where p.id = v_opo);

  -- ── LIT: A BLOCKADE OF CADIZ ──
  insert into public.active_buffs (kind_code, subject_id, season, starts_at, ends_at, source)
    values ('BLOCKADE', v_cad, null, now() - interval '1 minute', now() + interval '2 hours', 'event:proof-172-b');
  v_m := world.market(v_cad);
  if abs(world.spread(v_cad) - (v_sp0 + 0.20)) > 0.000001 or abs((v_m -> 'port' ->> 'spread')::numeric - world.spread(v_cad)) > 0.000001 then
    raise exception 'PROOF 172 FAIL: lit, the blockade did not add 0.20 to Cadiz''s cut (was %, now %, market %)', v_sp0, world.spread(v_cad), v_m -> 'port' ->> 'spread';
  end if;
  raise notice 'PASS: WE_BLOCKADE — Cadiz''s cut % -> %, the market''s port line the same', round(v_sp0, 4), round(world.spread(v_cad), 4);

  -- ── LIT: THE LIMITS ──
  -- in 2099 the named one is the only event running or announced; at one most at once the next slot names none
  update public.world_config set value = '1'::jsonb where key = 'world_event_max';
  if (public.tick_world_events(v_at + interval '1 hour') ->> 'named')::boolean then
    raise exception 'PROOF 172 FAIL: lit, the job named an event past world_event_max';
  end if;
  insert into public.active_buffs (kind_code, subject_id, season, starts_at, ends_at, source) values
    ('FESTIVAL', v_cad, null, v_at - interval '40 hours', v_at - interval '30 hours', 'event:proof-172-old'),
    ('FESTIVAL', v_opo, null, v_at - interval '3 hours', v_at - interval '1 hour', 'event:proof-172-new');
  -- room for one more, in a slot nobody holds: its run deletes the old and keeps the new
  update public.world_config set value = '9'::jsonb where key = 'world_event_max';
  perform public.tick_world_events(v_at + interval '2 hours');
  if exists (select 1 from public.active_buffs ab where ab.source = 'event:proof-172-old')
     or not exists (select 1 from public.active_buffs ab where ab.source = 'event:proof-172-new') then
    raise exception 'PROOF 172 FAIL: lit, the keep is wrong (a day-old event kept, or an hour-old one deleted)';
  end if;
  raise notice 'PASS: WE_LIMITS — none named past the most at once; an event ended 30 h ago deleted, one ended 1 h ago kept';

  -- ── SWITCHED OFF ──
  update public.world_config set value = 'false'::jsonb where key = 'world_events_enabled';
  if exists (select 1 from world.want_left(v_lis, v_food)) or exists (select 1 from world.want_left(v_opo, v_drink))
     or world.spread(v_cad) <> v_sp0 or world.world_events() <> '{"on": false}'::jsonb then
    raise exception 'PROOF 172 FAIL: switched off, an event still acts or is served';
  end if;
  raise notice 'PASS: WE_OFF — the want, the toll and the read dark again at once, the rows still there';
end $p$;
