-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 64 — THE NEWS TELLS OF BIG TRADES, PRICE SPIKES, PIRATES AND GIFTS  (migration 0362; slices N4, N5 and the gift of N6 of docs/NEWS_AND_MARKERS.md; owner row 216)
--
--   The migration's self-assert proves the leaves on probe rows. This proof plays the real commands: real sales and buys through cmd.do_sell and cmd.do_buy, the real
--   public.tick_price_snapshot over planted fine prices, real raid days through voyage.settle (the sea stubbed on one setting, as proofs 37, 38, 46 and 56 stub it), a real gift
--   through public.capital_gift_pass. OLD AGAINST NEW is not taken on trust: the migration's own 7 hunks are held below (written by
--   scripts/ops/harness/news-kinds/gen-checks.mjs --proof), the old bodies are rebuilt from the live ones by them, and each scene is played under the old bodies and under the new,
--   each in a subtransaction that is rolled back: every answer, every event, every ledger row, every purse and hold is compared as text. The news is the only thing that differs.
--   Everything rolls back with proof.mjs's transaction; the knobs and switches set here go back with it.
--
-- @pass NEWS_TRADE_PARITY    a real sale and a real buy, under the knob and at it, a merchant's and a player's: the old bodies against the new, the answer, the events, the ledger, the purse, the market row, the hold and the day's allowance equal as text
-- @pass NEWS_BIG_TRADE       a real sale under news_big_trade writes no row; at it, one BIG_SALE row naming the company, the count, the good, the city and the total; a real buy the same (BIG_BUY); with the knob at 0 nothing; a refused sale writes nothing
-- @pass NEWS_MERCHANT_CAP    seven real merchant sales of seven goods above the knob in one hour tell exactly news_merchant_hour (2); a player's sale after them is still told
-- @pass NEWS_SPIKE           the real snapshot folds two planted hours: +30 % and -30 % are told with before and after, +5 % is not; the same answer and the same hour rows as the old body; a later run in the same hour tells nothing more
-- @pass NEWS_PIRATES         real raid days through voyage.settle: a company's day that lost cargo is told with what the cargo cost, a day that lost nothing is not; a merchant's small loss is not told, her large one is; days, report, purse and hulls are the old bodies'
-- @pass NEWS_GIFT            a real gift to a broke company through public.capital_gift_pass is one CAPITAL_GIFT row at her capital with the sum; the pass's answer, her events and her ledger are the old body's
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- HUNKS BEGIN (written by scripts/ops/harness/news-kinds/gen-checks.mjs --proof from the migration; do not edit by hand)
create temp table hunks_64 (fn text, n int, old text, new text) on commit drop;
insert into hunks_64 (fn, n, old, new) values
  ('cmd.do_sell(uuid,jsonb)', 1, $h$  perform public.stats_live_add(jsonb_build_object('trades', 1, 'units', q.units, 'sold', round(q.total)::bigint));
$h$, $h$  perform public.stats_live_add(jsonb_build_object('trades', 1, 'units', q.units, 'sold', round(q.total)::bigint));
  -- 0362 (N4, docs/NEWS_AND_MARKERS.md 2.2): a big sale is news. The threshold first (one knob read, one comparison; 0 is off); public.news_big_trade only above it.
  if q.total >= nullif(public.wc_num('news_big_trade'), 0) then
    perform public.news_big_trade('BIG_SALE', f.player_id, f.port_id, g.id, q.units, q.total);
  end if;
$h$),
  ('cmd.do_buy(uuid,jsonb)', 1, $h$  perform public.stats_live_add(jsonb_build_object('trades', 1, 'units', q.units, 'bought', round(q.total)::bigint));
$h$, $h$  perform public.stats_live_add(jsonb_build_object('trades', 1, 'units', q.units, 'bought', round(q.total)::bigint));
  -- 0362 (N4, docs/NEWS_AND_MARKERS.md 2.2): a big buy is news. The threshold first (one knob read, one comparison; 0 is off); public.news_big_trade only above it.
  if q.total >= nullif(public.wc_num('news_big_trade'), 0) then
    perform public.news_big_trade('BIG_BUY', f.player_id, f.port_id, g.id, q.units, q.total);
  end if;
$h$),
  ('public.tick_price_snapshot(timestamp with time zone)', 1, $h$    get diagnostics v_hours = row_count;
    update public.price_rollup set hour_done = v_hour_now where one;
$h$, $h$    get diagnostics v_hours = row_count;
    update public.price_rollup set hour_done = v_hour_now where one;
    -- 0362 (N4): the hour that just closed against the hour before it: the largest moves are news (public.news_price_spikes). Only in the run that folded an hour.
    if v_hours > 0 then
      perform public.news_price_spikes(v_hour_now, p_now);
    end if;
$h$),
  ('voyage.settle(uuid,timestamp with time zone)', 1, $h$  v_booked  bigint;    -- 0339: the gold she took from a cargo ship (public.pirate_loot_book)
$h$, $h$  v_booked  bigint;    -- 0339: the gold she took from a cargo ship (public.pirate_loot_book)
  v_cost0   bigint;    -- 0362: her cargo at what it cost, read before the raiders take their share (the news of the day says what they took)
$h$),
  ('voyage.settle(uuid,timestamp with time zone)', 2, $h$        v_taken := voyage.raid_takes(v.id, d, p_fleet, v_outcome);
$h$, $h$        v_cost0 := public.fleet_stock_at_cost(p_fleet);   -- 0362: before they take it (public.fleet_unload drops a good's cost with its last tun)
        v_taken := voyage.raid_takes(v.id, d, p_fleet, v_outcome);
$h$),
  ('voyage.settle(uuid,timestamp with time zone)', 3, $h$      v_payload := v_payload || jsonb_build_object('outcome', v_outcome, 'prose', v_prose,
$h$, $h$      -- 0362 (N5, docs/NEWS_AND_MARKERS.md 2.2): pirates are news, when the day cost her something: the cargo taken at what it cost, the ransom paid, a cargo ship's gold
      -- (public.news_pirates: a player's company always, a ship of the world at news_pirate_loss and up). The day's payload below is what it was.
      if v_outcome in ('PLUNDERED', 'STRIPPED') or (v_outcome = 'RANSOM' and v_ransom > 0) then
        perform public.news_pirates(v.id, d, f.player_id, v_outcome,
                  v_ransom + v_booked + case when v_outcome = 'RANSOM' then 0 else v_cost0 - public.fleet_stock_at_cost(p_fleet) end);
      end if;
      v_payload := v_payload || jsonb_build_object('outcome', v_outcome, 'prose', v_prose,
$h$),
  ('public.capital_gift_one(timestamp with time zone,uuid)', 1, $h$    end;
  return jsonb_build_object('gifted', v_n, 'gift_ducats', v_d, 'gift_waiting', v_wait, 'failed', v_fail, 'notes', v_notes);
$h$, $h$    end;
  -- 0362 (N6, docs/NEWS_AND_MARKERS.md 2.2): a gift that was made is news (public.news_gift). After the gift's own sub-block, so the news never makes a gift a failed one.
  if v_n > 0 then
    perform public.news_gift(r.cap_id, r.player_id, r.capital, p_now);
  end if;
  return jsonb_build_object('gifted', v_n, 'gift_ducats', v_d, 'gift_waiting', v_wait, 'failed', v_fail, 'notes', v_notes);
$h$);
-- HUNKS END

-- THE BODIES AS THEY ARE NOW, by digest: what a rolled-back rebuild must differ from. Never a fixed digest: a later migration may re-cut any of these.
create temp table live_64 on commit drop as
select f.fn, md5(replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '')) as md5
  from (select distinct h.fn from hunks_64 h) f;

-- THE OLD BODIES, rebuilt from the live ones, whatever a later migration has made of them: each hunk's NEW text occurs exactly once in the live body and is reversed; each OLD text
-- then occurs exactly once; putting the NEW texts back gives the live body again, to the character. Called only inside a subtransaction that is rolled back.
create function pg_temp.to_old_64() returns void language plpgsql as $b$
declare
  f      record;
  h      record;
  v_live text;
  v_def  text;
  v_back text;
begin
  for f in select distinct x.fn from hunks_64 x order by x.fn loop
    v_live := replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '');
    v_def := v_live;
    for h in select * from hunks_64 x where x.fn = f.fn order by x.n desc loop
      if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
        raise exception 'PROOF 64 FAIL: hunk % of % is not in the live body exactly once: a later migration re-cut the very text 0362 added, and must amend this proof''s copy of the hunk', h.n, f.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    v_back := v_def;
    for h in select * from hunks_64 x where x.fn = f.fn order by x.n loop
      if (length(v_back) - length(replace(v_back, h.old, ''))) / length(h.old) <> 1 then
        raise exception 'PROOF 64 FAIL: hunk % of %: its OLD text is not in the rebuilt body exactly once', h.n, f.fn;
      end if;
      v_back := replace(v_back, h.old, h.new);
    end loop;
    if v_back is distinct from v_live or v_def = v_live then
      raise exception 'PROOF 64 FAIL: the rebuilt % does not come back to the live body when 0362''s hunks are put back (or nothing was reversed)', f.fn;
    end if;
    execute v_def;
  end loop;
  if exists (select 1 from live_64 l where md5(replace(pg_get_functiondef(l.fn::regprocedure), E'\r', '')) = l.md5)
     or exists (select 1 from live_64 l where pg_get_functiondef(l.fn::regprocedure) ~ 'news_(big_trade|price_spikes|pirates|gift)') then
    raise exception 'PROOF 64 FAIL: the old bodies were not rebuilt, or one still names a leaf of 0362';
  end if;
end
$b$;

-- the news written above a mark, as the scenes report it
create function pg_temp.news_64(p_mark bigint) returns jsonb language sql stable as $b$
  select coalesce(jsonb_agg(jsonb_build_object('kind', w.kind, 'importance', w.importance, 'scope', w.scope, 'port', w.port_id, 'good', w.good_id, 'company', w.company_id,
                                               'key', w.key, 'detail', w.detail) order by w.id), '[]'::jsonb)
    from public.world_news w where w.id > p_mark
$b$;

-- everything a company's command leaves behind, less the ids and clocks of rows made in the scene
create function pg_temp.left_64(p_player uuid, p_fleet uuid, p_ev uuid[], p_led uuid[]) returns jsonb language sql stable as $b$
  select jsonb_build_object(
    'events', (select coalesce(jsonb_agg(jsonb_build_object('kind', e.kind, 'payload', e.payload) order by e.kind, e.payload::text), '[]'::jsonb)
                 from public.events e where e.player_id = p_player and e.id <> all (p_ev)),
    'ledger', (select coalesce(jsonb_agg(jsonb_build_array(l.kind, l.ducats_delta, l.balance_after) order by l.balance_after desc, l.kind), '[]'::jsonb)
                 from public.ledger l where l.player_id = p_player and l.id <> all (p_led)),
    'purse', (select p.ducats from public.players p where p.id = p_player),
    'ships', (select jsonb_agg(jsonb_build_array(s.name, s.durability, s.crew, s.cargo, s.cargo_basis) order by s.name) from public.ships s where s.fleet_id = p_fleet),
    'day', (select coalesce(jsonb_agg(jsonb_build_array(td.good_id, td.qty) order by td.good_id), '[]'::jsonb) from public.trade_daily td where td.player_id = p_player))
$b$;

-- ONE REAL TRADE, in a subtransaction that is rolled back: under the old bodies or the new. p_side 'sell' loads p_qty at 1 d. a tun first. Answers {out, news}.
create function pg_temp.trade_64(p_fleet uuid, p_side text, p_good uuid, p_qty numeric, p_knob numeric, p_old boolean) returns jsonb language plpgsql as $b$
declare
  v_pl   uuid := (select f.player_id from public.fleets f where f.id = p_fleet);
  v_port uuid := (select f.port_id from public.fleets f where f.id = p_fleet);
  v_ev   uuid[] := array(select e.id from public.events e where e.player_id = v_pl);
  v_led  uuid[] := array(select l.id from public.ledger l where l.player_id = v_pl);
  v_mark bigint := coalesce((select max(w.id) from public.world_news w), 0);
  v_r    jsonb;
  v_out  jsonb;
begin
  begin
    if p_old then
      perform pg_temp.to_old_64();
    end if;
    update public.world_config set value = to_jsonb(p_knob) where key = 'news_big_trade';
    if p_side = 'sell' then
      perform public.fleet_load(p_fleet, (select g.code from public.goods g where g.id = p_good), p_qty, 1);
      v_r := cmd.do_sell(p_fleet, jsonb_build_object('good', p_good, 'qty', p_qty));
    else
      v_r := cmd.do_buy(p_fleet, jsonb_build_object('good', p_good, 'qty', p_qty));
    end if;
    v_out := jsonb_build_object(
      'out', jsonb_build_object('answer', v_r, 'left', pg_temp.left_64(v_pl, p_fleet, v_ev, v_led),
                                'market', (select jsonb_build_array(pg.stock, pg.glut) from public.port_goods pg where pg.port_id = v_port and pg.good_id = p_good)),
      'news', pg_temp.news_64(v_mark));
    raise exception using errcode = 'ZX364', message = 'SCENE_ROLLBACK_64';
  exception when sqlstate 'ZX364' then
    null;
  end;
  return v_out;
end
$b$;

-- a path of p_days voyage-days, every day in sea p_sea (proof 46's and 56's: a day is her speed x 24 to the digit)
create function pg_temp.through_64(p_fleet uuid, p_sea uuid, p_days int) returns jsonb language sql stable as $b$
  select jsonb_agg(jsonb_build_object('a', jsonb_build_array(0, 0), 'b', jsonb_build_array(0, 0), 'nm', voyage.fleet_speed(p_fleet) * 24, 'sea_id', p_sea, 'hazard_mult', 1000))
    from generate_series(1, p_days)
$b$;

-- ── the sea on one setting (proof 37's, 38's, 46's and 56's stub): '' quiet, 'PIRATES' a raid of magnitude 0.5 ──
do $$
begin
  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_64;
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

-- A WHOLE PASSAGE OF RAID DAYS, in a subtransaction that is rolled back: under the old bodies or the new. The voyage id is pinned (the fight's seed). p_basis is what each of her
-- ten tuns of amber cost. Answers {out: every day, event, ledger row, her purse and hulls; news}.
create function pg_temp.passage_64(p_fleet uuid, p_sea uuid, p_days int, p_at timestamptz, p_basis numeric, p_old boolean) returns jsonb language plpgsql as $b$
declare
  c_voy  constant uuid := '00000000-0364-4000-8000-0000000000aa';
  v_pl   uuid := (select f.player_id from public.fleets f where f.id = p_fleet);
  v_port uuid := (select f.port_id from public.fleets f where f.id = p_fleet);
  v_ev   uuid[] := array(select e.id from public.events e where e.player_id = v_pl);
  v_led  uuid[] := array(select l.id from public.ledger l where l.player_id = v_pl);
  v_mark bigint := coalesce((select max(w.id) from public.world_news w), 0);
  v_voy  uuid;
  v_out  jsonb;
begin
  begin
    if p_old then
      perform pg_temp.to_old_64();
    end if;
    update public.ships s set durability = (select b.durability from public.ship_base(s.id) b), crew = (select c.crew_required from public.ship_classes c where c.id = s.class_id),
                              water_t = 100000, food_t = 100000,
                              cargo = '{"baltic-amber": 10}'::jsonb, cargo_basis = jsonb_build_object('baltic-amber', p_basis)
     where s.fleet_id = p_fleet;
    v_voy := voyage.depart(p_fleet, pg_temp.through_64(p_fleet, p_sea, p_days), v_port, v_port, p_at);
    update public.voyages set id = c_voy where id = v_voy;
    perform set_config('byeharu.proof_sea', 'PIRATES', true);
    perform voyage.settle(p_fleet, (select o.eta from public.voyages o where o.id = c_voy));
    perform set_config('byeharu.proof_sea', '', true);
    if (select o.status from public.voyages o where o.id = c_voy) <> 'ARRIVED' then
      raise exception 'PROOF 64 FAIL: the passage did not arrive';
    end if;
    v_out := jsonb_build_object(
      'out', jsonb_build_object(
        'days', (select jsonb_agg(jsonb_build_object('d', e.day_index, 'kind', e.kind, 'payload', e.payload, 'at', e.resolved_at) order by e.day_index)
                   from public.voyage_events e where e.voyage_id = c_voy),
        'left', pg_temp.left_64(v_pl, p_fleet, v_ev, v_led)),
      'news', pg_temp.news_64(v_mark));
    raise exception using errcode = 'ZX364', message = 'SCENE_ROLLBACK_64';
  exception when sqlstate 'ZX364' then
    null;
  end;
  perform set_config('byeharu.proof_sea', '', true);
  return v_out;
end
$b$;

-- THE REAL SNAPSHOT over two planted hours of 2099, in a subtransaction that is rolled back. Three recorded pairs: 100 then 130, 100 then 70, 100 then 105.
create function pg_temp.snapshot_64(p_old boolean) returns jsonb language plpgsql as $b$
declare
  c_t0   constant timestamptz := '2099-06-07 08:00:00+00';
  v_mark bigint := coalesce((select max(w.id) from public.world_news w), 0);
  v_a    jsonb;
  v_b    jsonb;
  v_n1   jsonb;
  v_out  jsonb;
  v_s1   bigint;
  v_t2   timestamptz;
begin
  begin
    if p_old then
      perform pg_temp.to_old_64();
    end if;
    update public.price_rollup set hour_done = c_t0, day_done = (c_t0 at time zone 'UTC')::date where one;
    -- The two samples a pair keeps, one in each planted hour and each in its OWN drift slot, as the real writer keeps them (one sample a slot, the
    -- first): the second at 09:10, or at the start of the slot after the first's when a slot is longer than the hour between them (0413: the
    -- chain's slot is 4,500 s, so 08:10 and 09:10 can be one slot). Both instants and both slots come from the one authority, public.clock_count
    -- and public.clock_start; the hour fold reads only the hours, so the scene is the same scene.
    v_s1 := public.drift_slot_of(c_t0 + interval '10 minutes');
    v_t2 := greatest(c_t0 + interval '70 minutes', public.clock_start('drift_slot', v_s1 + 1));
    if v_t2 >= c_t0 + interval '2 hours' or public.drift_slot_of(v_t2) = v_s1 then
      raise exception 'PROOF 64 SETUP: no second drift slot inside the second planted hour (first slot %, second sample at %)', v_s1, v_t2;
    end if;
    insert into public.price_history (port_id, good_id, slot, at, mid, stock, ask, bid)
    select x.port_id, x.good_id, v_s1, c_t0 + interval '10 minutes', 100, 10, 110, 100 from pairs_64 x
    union all
    select x.port_id, x.good_id, public.drift_slot_of(v_t2), v_t2, x.then, 10, x.then * 1.1, x.then from pairs_64 x;
    v_a := public.tick_price_snapshot(c_t0 + interval '125 minutes');
    v_n1 := pg_temp.news_64(v_mark);
    v_b := public.tick_price_snapshot(c_t0 + interval '140 minutes');   -- the same hour, a later slot: no hour is folded, nothing more is told
    v_out := jsonb_build_object(
      'out', jsonb_build_object('first', v_a, 'second', v_b,
                                'hours', (select jsonb_agg(to_jsonb(h) order by h.port_id, h.good_id, h.hour) from public.price_history_hour h join pairs_64 x on x.port_id = h.port_id and x.good_id = h.good_id
                                           where h.hour >= c_t0),
                                'mark', (select to_jsonb(m) from public.price_rollup m where m.one)),
      'news', v_n1, 'news_after', pg_temp.news_64(v_mark));
    raise exception using errcode = 'ZX364', message = 'SCENE_ROLLBACK_64';
  exception when sqlstate 'ZX364' then
    null;
  end;
  return v_out;
end
$b$;

-- A REAL GIFT to a broke company, in a subtransaction that is rolled back.
create function pg_temp.gift_64(p_player uuid, p_at timestamptz, p_old boolean) returns jsonb language plpgsql as $b$
declare
  v_ev   uuid[] := array(select e.id from public.events e where e.player_id = p_player);
  v_led  uuid[] := array(select l.id from public.ledger l where l.player_id = p_player);
  v_mark bigint := coalesce((select max(w.id) from public.world_news w), 0);
  v_r    jsonb;
  v_out  jsonb;
begin
  begin
    if p_old then
      perform pg_temp.to_old_64();
    end if;
    v_r := public.capital_gift_pass(p_at, p_player);
    v_out := jsonb_build_object(
      'out', jsonb_build_object('answer', v_r, 'left', pg_temp.left_64(p_player, null, v_ev, v_led),
                                'gifts', (select jsonb_agg(jsonb_build_array(g.port_id, g.ducats, g.created_at) order by g.id) from public.capital_gifts g where g.player_id = p_player)),
      'news', pg_temp.news_64(v_mark));
    raise exception using errcode = 'ZX364', message = 'SCENE_ROLLBACK_64';
  exception when sqlstate 'ZX364' then
    null;
  end;
  return v_out;
end
$b$;

create temp table pairs_64 (i int, port_id uuid, good_id uuid, "then" numeric) on commit drop;

do $p$
declare
  c_uid   constant uuid := '00000000-0364-4000-8000-000000000001';
  v_lis   uuid;
  v_hum   uuid;
  v_hfl   uuid;
  v_npc   uuid;
  v_nfl   uuid;
  v_goods uuid[];
  v_good  uuid;
  v_a     jsonb;
  v_b     jsonb;
  v_t     numeric;
  v_n     int;
  v_m     int;
  v_i     int;
  v_w     jsonb;
  v_sea   uuid;
  v_at    timestamptz := '2026-03-04 05:06:07+00';
  v_cap   uuid;
  v_row   record;
  v_lost  int := 0;
  v_quiet int := 0;
  v_bytes bigint := 0;
  v_mark  bigint;
begin
  select p.id into v_lis from public.ports p where p.code = 'LIS';
  if (select md5(string_agg(c.key || c.value::text, ',' order by c.key)) from public.world_config c where c.key like 'news\_%')
       is distinct from md5('news_big_trade250000,news_merchant_hour2,news_pirate_loss50000,news_spike_pct20,news_spike_quiet_hours6,news_spike_top5') then
    raise exception 'PROOF 64 FAIL: the six knobs are not as 0362 wrote them';
  end if;

  -- THE COMPANIES: a player's house and a merchant, each a barca at Lisbon
  v_hum := public.new_house(c_uid, 'Casa Noticia 64', 'PRT', p_ducats => 200000);
  select f.id into v_hfl from public.fleets f where f.player_id = v_hum;
  v_npc := public.new_house(null, 'Casa Mercante 64', 'PRT', p_ducats => 200000, p_is_npc => true);
  select f.id into v_nfl from public.fleets f where f.player_id = v_npc;
  -- seven goods Lisbon trades and sells, small enough for a barca
  select array_agg(x.id) into v_goods
    from (select g.id from public.port_goods pg join public.goods g on g.id = pg.good_id
           where pg.port_id = v_lis and g.bulk <= 1 and pg.stock_target > 0 and pg.stock >= 20 and public.port_offers(v_lis, g.id)
             and not public.culture_refuses((select p.culture from public.ports p where p.id = v_lis), g.culture_mask)
           order by pg.stock_target desc, g.code limit 7) x;
  if coalesce(cardinality(v_goods), 0) <> 7 then
    raise exception 'PROOF 64 FAIL: Lisbon does not offer seven small goods';
  end if;
  v_good := v_goods[1];

  -- ── NEWS_TRADE_PARITY and NEWS_BIG_TRADE ──
  -- what the sale and the buy come to (the knob far above them), then each again with the knob AT its total and one ducat over it
  v_a := pg_temp.trade_64(v_hfl, 'sell', v_good, 10, 1e12, false);
  v_t := (v_a->'out'->'answer'->>'total')::numeric;
  if v_t is null or v_t <= 0 or jsonb_array_length(v_a->'news') <> 0 then
    raise exception 'PROOF 64 FAIL: a sale far under the knob was told, or sold nothing: %', v_a;
  end if;
  v_n := 0;
  for v_row in select s.side, k.knob, c.fleet
                 from (values ('sell'), ('buy')) s(side)
                 cross join (values (0), (1), (2)) k(knob)
                 cross join (values (v_hfl), (v_nfl)) c(fleet) loop
    -- knob 0: far above; 1: at the trade's total; 2: one ducat over it
    v_t := (pg_temp.trade_64(v_row.fleet, v_row.side, v_good, 10, 1e12, false)->'out'->'answer'->>'total')::numeric;
    v_a := pg_temp.trade_64(v_row.fleet, v_row.side, v_good, 10, case v_row.knob when 0 then 1e12 when 1 then v_t else v_t + 1 end, false);
    v_b := pg_temp.trade_64(v_row.fleet, v_row.side, v_good, 10, case v_row.knob when 0 then 1e12 when 1 then v_t else v_t + 1 end, true);
    if v_a->'out' is null or (v_a->'out')::text is distinct from (v_b->'out')::text then
      raise exception 'PROOF 64 FAIL: a % (knob case %) is not the old body''s: % against %', v_row.side, v_row.knob, v_a->'out', v_b->'out';
    end if;
    if jsonb_array_length(v_b->'news') <> 0 or jsonb_array_length(v_a->'news') <> (case when v_row.knob = 1 then 1 else 0 end) then
      raise exception 'PROOF 64 FAIL: a % of % with the knob case % told % row(s) (the old body %)', v_row.side, v_t, v_row.knob, jsonb_array_length(v_a->'news'), jsonb_array_length(v_b->'news');
    end if;
    if v_row.knob = 1 then
      v_w := v_a->'news'->0;
      if v_w->>'kind' <> (case v_row.side when 'sell' then 'BIG_SALE' else 'BIG_BUY' end) or (v_w->>'importance')::int <> 2 or v_w->>'scope' <> 'port'
         or (v_w->>'port')::uuid <> v_lis or (v_w->>'good')::uuid <> v_good
         or (v_w->>'company')::uuid <> (select f.player_id from public.fleets f where f.id = v_row.fleet)
         or v_w->'detail'->'words'->>'company' <> (case when v_row.fleet = v_hfl then 'Casa Noticia 64' else 'Casa Mercante 64' end)
         or v_w->'detail'->'words'->>'n' <> public.news_num(v_t) or v_w->'detail'->'words'->>'qty' <> '10'
         or v_w->'detail'->'words'->'good'->>'key' <> (select g.code from public.goods g where g.id = v_good)
         or v_w->'detail'->'words'->'city'->>'name' <> (select p.name from public.ports p where p.id = v_lis)
         or (v_w->'detail'->>'npc')::boolean is distinct from (v_row.fleet = v_nfl) then
        raise exception 'PROOF 64 FAIL: the news of a big % is not its company, count, good, city and total: %', v_row.side, v_w;
      end if;
    end if;
    v_n := v_n + 1;
    v_bytes := v_bytes + length((v_a->'out')::text);
  end loop;
  raise notice 'PASS: NEWS_TRADE_PARITY — % real trades (a sale and a buy, a player''s and a merchant''s, the knob far above, at the total and a ducat over it), the old bodies (rebuilt from the live ones by the hunks) against the new: answer, events, ledger, purse, market row, hold and allowance equal as text (% bytes)', v_n, v_bytes;

  -- the knob at 0 is off; a refused sale writes nothing
  v_a := pg_temp.trade_64(v_hfl, 'sell', v_good, 10, 0, false);
  v_mark := coalesce((select max(w.id) from public.world_news w), 0);
  update public.world_config set value = to_jsonb(1) where key = 'news_big_trade';
  begin
    perform cmd.do_sell(v_hfl, jsonb_build_object('good', v_goods[2], 'qty', 10));   -- she carries none
    raise exception 'PROOF 64 FAIL: a sale of cargo she does not carry went through';
  exception when sqlstate 'P0001' then
    if sqlerrm not like 'E_NO_CARGO%' then raise; end if;
  end;
  if jsonb_array_length(v_a->'news') <> 0 or v_a->'out'->'answer'->>'total' is null or exists (select 1 from public.world_news w where w.id > v_mark) then
    raise exception 'PROOF 64 FAIL: with the knob at 0 a sale was told, or a refused sale was';
  end if;
  raise notice 'PASS: NEWS_BIG_TRADE — a real sale and a real buy tell nothing under news_big_trade and one row at it (BIG_SALE, BIG_BUY: company, count, good, city, total); at 0 nothing; a refused sale nothing';

  -- ── NEWS_MERCHANT_CAP: every trade is big (the knob at 1); seven goods, one merchant, one hour ──
  begin
    v_mark := coalesce((select max(w.id) from public.world_news w), 0);
    for v_i in 1 .. 7 loop
      perform public.fleet_load(v_nfl, (select g.code from public.goods g where g.id = v_goods[v_i]), 5, 1);
      perform cmd.do_sell(v_nfl, jsonb_build_object('good', v_goods[v_i], 'qty', 5));
    end loop;
    v_n := (select count(*) from public.world_news w where w.id > v_mark and w.kind = 'BIG_SALE' and w.company_id = v_npc);
    perform public.fleet_load(v_hfl, (select g.code from public.goods g where g.id = v_good), 5, 1);
    perform cmd.do_sell(v_hfl, jsonb_build_object('good', v_good, 'qty', 5));
    perform public.fleet_load(v_hfl, (select g.code from public.goods g where g.id = v_good), 5, 1);
    perform cmd.do_sell(v_hfl, jsonb_build_object('good', v_good, 'qty', 5));   -- the same good, city and hour again: no second row
    v_m := (select count(*) from public.world_news w where w.id > v_mark and w.kind = 'BIG_SALE' and w.company_id = v_hum);
    if v_n <> public.wc_int('news_merchant_hour') or v_n <> 2 or v_m <> 1 or (select count(*) from public.world_news w where w.id > v_mark) <> 3 then
      raise exception 'PROOF 64 FAIL: seven merchant sales told % (the cap is %), and a player''s two sales of one good told %', v_n, public.wc_int('news_merchant_hour'), v_m;
    end if;
    raise exception using errcode = 'ZX364', message = 'SCENE_ROLLBACK_64';
  exception when sqlstate 'ZX364' then
    null;
  end;
  update public.world_config set value = to_jsonb(250000) where key = 'news_big_trade';
  raise notice 'PASS: NEWS_MERCHANT_CAP — seven real merchant sales of seven goods above the knob told % (news_merchant_hour); a player''s sale after them was told, and her second of the same good in the hour was not a second row', v_n;

  -- ── NEWS_SPIKE ──
  insert into pairs_64 (i, port_id, good_id, "then")
  select row_number() over (order by pr.port_id, pr.good_id)::int, pr.port_id, pr.good_id, 0
    from (select * from public.price_record_pairs() order by port_id, good_id limit 3) pr;
  update pairs_64 set "then" = case i when 1 then 130 when 2 then 70 else 105 end;
  v_a := pg_temp.snapshot_64(false);
  v_b := pg_temp.snapshot_64(true);
  if v_a->'out' is null or (v_a->'out')::text is distinct from (v_b->'out')::text or (v_a->'out'->'first'->>'hours')::int <> 6 or (v_a->'out'->'second'->>'hours')::int <> 0
     or jsonb_array_length(v_a->'out'->'hours') < 6 then
    raise exception 'PROOF 64 FAIL: the snapshot''s answer, hour rows or mark are not the old body''s, or it did not fold the two planted hours: % against %', v_a->'out', v_b->'out';
  end if;
  if jsonb_array_length(v_b->'news') <> 0 or jsonb_array_length(v_a->'news') <> 2 or (v_a->'news')::text is distinct from (v_a->'news_after')::text
     or (select count(*) from jsonb_array_elements(v_a->'news') e join pairs_64 x on x.port_id = (e->>'port')::uuid and x.good_id = (e->>'good')::uuid
          where e->>'kind' = 'PRICE_SPIKE' and (e->>'importance')::int = 2 and e->>'scope' = 'port'
            and ((x.i = 1 and e->'detail'->'words'->>'p' = '+30%' and (e->'detail'->>'before')::numeric = 100 and (e->'detail'->>'after')::numeric = 130)
              or (x.i = 2 and e->'detail'->'words'->>'p' = '-30%' and (e->'detail'->>'before')::numeric = 100 and (e->'detail'->>'after')::numeric = 70))
            and e->'detail'->'words'->'good'->>'kind' = 'good' and e->'detail'->'words'->'city'->>'kind' = 'port') <> 2 then
    raise exception 'PROOF 64 FAIL: the spikes told are not +30 %% and -30 %% with their before and after, once: % (after the later run %; the old body %)', v_a->'news', v_a->'news_after', v_b->'news';
  end if;
  raise notice 'PASS: NEWS_SPIKE — the real snapshot folded 6 planted hour rows: +30 %% and -30 %% told with 100 → 130 and 100 → 70, +5 %% not; answer, hour rows and mark equal to the old body''s; the later run in the same hour told nothing more';

  -- ── NEWS_PIRATES: the fight lit (as the chain leaves it), the pirates' ships dark (every raid anonymous), the purses dark ──
  update public.world_config set value = 'true'::jsonb where key = 'combat_bite';
  update public.world_config set value = 'false'::jsonb where key in ('pirates_bite', 'navy_enabled', 'attack_enabled', 'npc_refits_enabled', 'raid_orders_enabled');
  v_sea := (select s.id from public.seas s order by s.piracy_index desc, s.code limit 1);
  -- a company, 12 raid days, ten tuns of amber at 2,000 d.
  v_a := pg_temp.passage_64(v_hfl, v_sea, 12, v_at, 2000, false);
  v_b := pg_temp.passage_64(v_hfl, v_sea, 12, v_at, 2000, true);
  if v_a->'out' is null or (v_a->'out')::text is distinct from (v_b->'out')::text or jsonb_array_length(v_b->'news') <> 0 then
    raise exception 'PROOF 64 FAIL: a company''s raid passage is not the old bodies'', or the old bodies told news';
  end if;
  v_bytes := length((v_a->'out')::text);
  for v_row in select (e->>'d')::int as d, e->'payload' as p from jsonb_array_elements(v_a->'out'->'days') e where e->>'kind' = 'PIRATES' loop
    v_t := coalesce((select sum(x.value::numeric) from jsonb_each_text(coalesce(v_row.p->'cargo_lost', '{}'::jsonb)) x), 0) * 2000
           + coalesce((v_row.p->>'ransom_paid')::numeric, (v_row.p->'pirate'->>'ransom')::numeric, 0);
    select e into v_w from jsonb_array_elements(v_a->'news') e where e->>'key' = 'pirates:00000000-0364-4000-8000-0000000000aa:' || v_row.d;
    if v_t > 0 then
      v_lost := v_lost + 1;
      if v_w is null or v_w->>'kind' <> 'PIRATES' or v_w->>'scope' <> 'company' or (v_w->>'company')::uuid <> v_hum or (v_w->'detail'->>'loss')::numeric <> v_t
         or v_w->'detail'->'words'->>'n' <> public.news_num(v_t) or v_w->'detail'->'words'->>'company' <> 'Casa Noticia 64' or v_w->'detail'->>'outcome' <> v_row.p->>'outcome' then
        raise exception 'PROOF 64 FAIL: day % cost her % and its news is %', v_row.d, v_t, v_w;
      end if;
    else
      v_quiet := v_quiet + 1;
      if v_w is not null then
        raise exception 'PROOF 64 FAIL: day % cost her nothing and was told: %', v_row.d, v_w;
      end if;
    end if;
  end loop;
  if v_lost < 1 or v_quiet < 1 or jsonb_array_length(v_a->'news') <> v_lost then
    raise exception 'PROOF 64 FAIL: of 12 raid days % cost her cargo and % did not (both are needed), and % rows were told', v_lost, v_quiet, jsonb_array_length(v_a->'news');
  end if;
  -- a merchant: the same days at 2,000 d. a tun are under news_pirate_loss (nothing told); at 60,000 d. a tun her first loss is over it (told)
  v_n := v_lost;
  v_a := pg_temp.passage_64(v_nfl, v_sea, 12, v_at, 2000, false);
  v_b := pg_temp.passage_64(v_nfl, v_sea, 12, v_at, 2000, true);
  if v_a->'out' is null or (v_a->'out')::text is distinct from (v_b->'out')::text or jsonb_array_length(v_a->'news') <> 0
     or not exists (select 1 from jsonb_array_elements(v_a->'out'->'days') e where e->'payload' ? 'cargo_lost') then
    raise exception 'PROOF 64 FAIL: a merchant''s small losses were told, she lost nothing, or her passage is not the old bodies'': %', v_a->'news';
  end if;
  v_bytes := v_bytes + length((v_a->'out')::text);
  v_a := pg_temp.passage_64(v_nfl, v_sea, 12, v_at, 60000, false);
  v_b := pg_temp.passage_64(v_nfl, v_sea, 12, v_at, 60000, true);
  v_m := (select count(*) from jsonb_array_elements(v_a->'out'->'days') e
           where coalesce((select sum(x.value::numeric) from jsonb_each_text(coalesce(e->'payload'->'cargo_lost', '{}'::jsonb)) x), 0) * 60000 >= public.wc_num('news_pirate_loss'));
  if (v_a->'out')::text is distinct from (v_b->'out')::text or v_m < 1 or jsonb_array_length(v_a->'news') <> least(v_m, public.wc_int('news_merchant_hour'))
     or exists (select 1 from jsonb_array_elements(v_a->'news') e where e->>'kind' <> 'PIRATES' or not (e->'detail'->>'npc')::boolean
                  or (e->'detail'->>'loss')::numeric < public.wc_num('news_pirate_loss')) then
    raise exception 'PROOF 64 FAIL: a merchant''s % losses of 50,000 and up told % row(s): %', v_m, jsonb_array_length(v_a->'news'), v_a->'news';
  end if;
  raise notice 'PASS: NEWS_PIRATES — 12 real raid days of a company: % cost her cargo and each is told with what it cost, % cost nothing and are not; a merchant''s losses under news_pirate_loss are not told, her % of 50,000 and up are (% rows, the hour''s cap); days, report, purse and hulls equal to the old bodies'' (% bytes)',
    v_n, v_quiet, v_m, jsonb_array_length(v_a->'news'), v_bytes + length((v_a->'out')::text);

  -- ── NEWS_GIFT: the economy closed and the purses lit (here only), every harbour rich; a company with nothing ──
  update public.world_config set value = 'true'::jsonb where key in ('economy_closed', 'city_treasury_enabled');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 50000000, reserve = 0;
  update public.players set ducats = 0 where id = v_hum;
  update public.ships s set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where s.fleet_id = v_hfl;
  select g.cap_id into v_cap from public.capital_gift_roster(v_at, v_hum) g;
  if v_cap is null then
    raise exception 'PROOF 64 FAIL: a company with nothing is not on the gift roster, or her country has no capital';
  end if;
  v_a := pg_temp.gift_64(v_hum, v_at, false);
  v_b := pg_temp.gift_64(v_hum, v_at, true);
  v_w := v_a->'news'->0;
  if v_a->'out' is null or (v_a->'out')::text is distinct from (v_b->'out')::text or (v_a->'out'->'answer'->>'gifted')::int <> 1
     or jsonb_array_length(v_b->'news') <> 0 or jsonb_array_length(v_a->'news') <> 1
     or v_w->>'kind' <> 'CAPITAL_GIFT' or v_w->>'scope' <> 'company' or (v_w->>'port')::uuid <> v_cap or (v_w->>'company')::uuid <> v_hum
     or v_w->'detail'->'words'->>'n' <> public.news_num((v_a->'out'->'answer'->>'gift_ducats')::numeric)
     or v_w->'detail'->'words'->'capital'->>'name' <> (select p.name from public.ports p where p.id = v_cap) or v_w->'detail'->'words'->>'company' <> 'Casa Noticia 64' then
    raise exception 'PROOF 64 FAIL: a real gift is not the old body''s, or its news is not one CAPITAL_GIFT row at her capital: % / % against %', v_a->'news', v_a->'out', v_b->'out';
  end if;
  raise notice 'PASS: NEWS_GIFT — a real gift of % d. through public.capital_gift_pass: one CAPITAL_GIFT row at her capital naming it and her; the answer, her events, her ledger and the gift row equal to the old body''s',
    v_a->'out'->'answer'->>'gift_ducats';
end
$p$;
