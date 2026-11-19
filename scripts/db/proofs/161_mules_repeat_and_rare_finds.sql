-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 161 - MULES, REPEAT AND RARE FINDS  (migration 0458; docs/design/land-2026-11.md 6.1, 6.2, 6.5, 4.1; docs/dev-log/2026-11-19-land-l1c.md)
--   The three things land slice L1 cut, each whole, and each inside the market guard of 0457. Lit inside this proof's own transaction
--   (proof.mjs rolls it back). Every instant is passed to the cores, so the sum is read at fixed times. The dice are pinned
--   (world_secret), and the party that finds has a fixed id and a fixed Send instant, so its dice are fixed too.
--
-- @pass L1C_DARK     land_enabled false: cmd.land_pack and cmd.land_repeat refuse E_NOT_IN_USE and no party is made
-- @pass L1C_MULES    four mules for 3,000, 8,000, 20,000 and 50,000 to the home city (ledger LAND): 10, 15, 20, 30 packs from the next Send, never the job out; a fifth E_TOP_GRADE; a short purse E_INSUFFICIENT_FUNDS
-- @pass L1C_GUARD    with the top mule, Mining 100, the best tool and the crowd's full chance, every job-region and every find-region is at most a hundredth of its middling target; the check bites a find made too common
-- @pass L1C_REPEAT   Repeat off: one trip and home, the job ends at the next press; turned off while out: the trip under way is the last; turned on while out: on again by itself to the 12-hour cap; the door says on and off
-- @pass L1C_FINDS    a find only on a land where it lies; booked in twelve presses or in one, the same finds, and exactly the dice's; at a cost of 0
-- @pass L1C_SHED     a find that does not fit waits with the party, the next Send is refused E_SHED_FULL, and with room a press books it
-- @pass L1C_READ     world.land serves the mules, the next mule and its price, Repeat, finds waiting and each job's finds
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

create function pg_temp.guard_161(p_player uuid)
returns table (kind text, code text, find text, region text, per_hour numeric, target numeric, share numeric)
language sql
as $f$
  with j as (
    select a.code, a.good_id, public.land_terms(p_player, a.code) as t,
           (select min(s.march_seconds) from public.land_sites s where s.ground = a.ground) as m
      from public.land_actions a where a.kind = 'gather'),
  pace as (
    select j.code, j.good_id, (j.t ->> 'p')::numeric * 3600 / (2 * j.m + (j.t ->> 'p')::numeric * (j.t ->> 'a')::int) as turns_h from j),
  mid as (
    select g.id as good_id, rg.code as region, percentile_disc(0.5) within group (order by coalesce(pg.base_target, pg.stock_target) * least(1, coalesce((select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'depth_m0'), 1))) as target
      from public.goods g
      cross join unnest(g.origin_regions) o(rc)
      join public.regions rg on rg.code = o.rc
      join public.ports p on p.region_id = rg.id and p.kind = 'HARBOUR'
      join public.port_goods pg on pg.port_id = p.id and pg.good_id = g.id
     where g.id in (select a.good_id from public.land_actions a)
     group by g.id, rg.code),
  x as (
    select 'job' as kind, pace.code, null::text as find, mid.region, pace.turns_h * (1 + public.wc_num('land_crowd_max') / 100) as per_hour, mid.target
      from pace join mid on mid.good_id = pace.good_id
    union all
    select 'find', pace.code, g.code, mid.region, pace.turns_h / d.one_in, mid.target
      from public.land_drops d join pace on pace.code = d.action join public.goods g on g.id = d.good_id join mid on mid.good_id = d.good_id)
  select x.kind, x.code, x.find, x.region, x.per_hour, x.target, x.per_hour / (x.target / 100.0) from x
$f$;

do $p$
declare
  t0      constant timestamptz := '2026-02-02 00:00:00+00';
  c_bp    constant uuid := '00000000-0458-4000-8000-0000000161b1';
  v_lis   uuid := (select p.id from public.ports p where p.code = 'LIS');
  v_bal   uuid := (select p.id from public.ports p join public.regions r on r.id = p.region_id where r.code = 'BAL' and p.kind = 'HARBOUR' order by p.code limit 1);
  v_sand  uuid := (select g.id from public.goods g where g.code = 'sand');
  v_amber uuid := (select g.id from public.goods g where g.code = 'amber');
  v_pl    uuid;
  v_pl2   uuid;
  v_party uuid;
  v_r     jsonb;
  v_s     jsonb;
  v_q     record;
  v_n     int;
  v_x     numeric;
  v_trip  numeric;
  v_purse bigint;
  v_note  text;
  v_split jsonb;
  v_one   jsonb;
  v_dice  jsonb;
begin
  update public.world_config set value = to_jsonb('0458-fixed-dice-of-proof-161-mules-repeat-and-rare-finds-000000000000000'::text) where key = 'world_secret';
  v_pl := public.new_house('00000000-0458-4000-8000-0000000161c1', 'Casa Mula 161', 'PRT', 'LIS', 'Mula 161', 'carlat', 'Mula 161', null, false);
  v_pl2 := public.new_house('00000000-0458-4000-8000-0000000161c2', 'Casa Ambar 161', 'PRT', 'LIS', 'Ambar 161', 'carlat', 'Ambar 161', null, false);
  if public.home_port_of(v_pl) <> v_lis or v_bal is null then
    raise exception 'proof 161: the probe company is not of Lisbon, or the Baltic has no harbour';
  end if;
  perform cmd.assume_identity('00000000-0458-4000-8000-0000000161c1');

  -- ── DARK ──
  update public.world_config set value = 'false'::jsonb where key = 'land_enabled';
  v_r := jsonb_build_array(cmd.land_pack() ->> 'error_code', cmd.land_repeat(true) ->> 'error_code');
  if v_r <> '["E_NOT_IN_USE", "E_NOT_IN_USE"]'::jsonb or exists (select 1 from public.land_parties lp where lp.player_id = v_pl) then
    raise exception 'proof 161 L1C_DARK: a new door opened dark: %', v_r;
  end if;
  raise notice 'PASS: L1C_DARK - cmd.land_pack and cmd.land_repeat refuse E_NOT_IN_USE, no party made';
  update public.world_config set value = 'true'::jsonb where key = 'land_enabled';

  -- ── MULES ──
  update public.players set ducats = 81500 where id = v_pl;
  v_r := cmd.land_pack();
  select lp.id into v_party from public.land_parties lp where lp.player_id = v_pl;
  if (v_r ->> 'packs')::int <> 10 or (v_r ->> 'price')::int <> 3000 or (public.land_terms(v_pl, 'iron') ->> 'p')::int <> 10 then
    raise exception 'proof 161 L1C_MULES: the first mule is not 10 packs for 3,000: %', v_r;
  end if;
  -- a job out keeps the packs it was sent with
  perform public.land_send_for(v_pl, 'iron', now() - interval '1 minute');
  v_r := v_r || jsonb_build_object('b', cmd.land_pack() ->> 'packs');
  if (select (lp.terms ->> 'p')::int from public.land_parties lp where lp.id = v_party) <> 10 or (public.land_terms(v_pl, 'iron') ->> 'p')::int <> 15 then
    raise exception 'proof 161 L1C_MULES: a mule bought while out changed the job out, or not the next Send';
  end if;
  perform public.land_home_for(v_pl, now());
  perform public.land_collect_for(v_pl, now() + interval '1 hour');
  v_r := v_r || jsonb_build_object('c', cmd.land_pack() ->> 'packs', 'd', cmd.land_pack() ->> 'packs', 'e', cmd.land_pack() ->> 'error_code');
  if v_r ->> 'c' <> '20' or v_r ->> 'd' <> '30' or v_r ->> 'e' <> 'E_TOP_GRADE'
     or (select p.ducats from public.players p where p.id = v_pl) <> 500
     or (select count(*) from public.ledger l where l.player_id = v_pl and l.kind = 'LAND') <> 4
     or (select -sum(l.ducats_delta) from public.ledger l where l.player_id = v_pl and l.kind = 'LAND') <> 81000
     or (public.land_terms(v_pl, 'iron') ->> 'p')::int <> 30 then
    raise exception 'proof 161 L1C_MULES: the mules are not 10/15/20/30 for 81,000 in four LAND rows, or a fifth was sold: %', v_r;
  end if;
  update public.land_parties set mules = 1 where id = v_party;
  if cmd.land_pack() ->> 'error_code' <> 'E_INSUFFICIENT_FUNDS' or (select lp.mules from public.land_parties lp where lp.id = v_party) <> 1 then
    raise exception 'proof 161 L1C_MULES: a short purse bought a mule';
  end if;
  update public.land_parties set mules = 0 where id = v_party;
  raise notice 'PASS: L1C_MULES - 10, 15, 20, 30 packs for 81,000 in four LAND rows; a job out kept its 10; a fifth E_TOP_GRADE; a short purse E_INSUFFICIENT_FUNDS';

  -- ── THE GUARD with the top mule and the finds ──
  insert into public.level_xp (player_id, skill, xp, seq) values (v_pl2, 'mining', public.level_begins('mining', 100)::int, 0)
    on conflict (player_id, skill) do update set xp = excluded.xp;
  insert into public.land_parties (id, player_id, port_id, tools, mules, xp_booked_at)
  values (c_bp, v_pl2, v_bal, (select array_agg(t.code) from public.land_tools t), jsonb_array_length(public.wc('land_packs')), t0 + interval '1000 days');
  select g.* into v_q from pg_temp.guard_161(v_pl2) g order by g.share desc, g.code, g.region limit 1;
  select count(*) into v_n from pg_temp.guard_161(v_pl2) g;
  if v_q.share > 1 or (public.land_terms(v_pl2, 'iron') ->> 'p')::int <> 30 or (public.land_terms(v_pl2, 'iron') ->> 'have')::int <> 100 then
    raise exception 'proof 161 L1C_GUARD: % % % at % is % of the hundredth', v_q.kind, v_q.code, v_q.find, v_q.region, round(v_q.share, 3);
  end if;
  v_note := format('%s job- and find-regions, the tightest %s %s at %s (%s)', v_n, v_q.code, coalesce(v_q.find, ''), v_q.region, round(v_q.share, 4));
  select g.* into v_q from pg_temp.guard_161(v_pl2) g where g.kind = 'find' order by g.share desc limit 1;
  v_note := v_note || format(', the most finds %s from %s at %s (%s)', v_q.find, v_q.code, v_q.region, round(v_q.share, 4));
  update public.land_drops d set one_in = 1 from public.goods g where g.id = d.good_id and g.code = 'rubies' and d.action = 'tin';
  select g.* into v_q from pg_temp.guard_161(v_pl2) g where g.kind = 'find' and g.code = 'tin' and g.find = 'rubies' order by g.share desc limit 1;
  if v_q.share <= 1 then
    raise exception 'proof 161 L1C_GUARD: a ruby on every turn of tin passed the guard (%)', round(v_q.share, 2);
  end if;
  update public.land_drops d set one_in = 100 from public.goods g where g.id = d.good_id and g.code = 'rubies' and d.action = 'tin';
  raise notice 'PASS: L1C_GUARD - %; a ruby every turn of tin is % x and fails', v_note, round(v_q.share, 1);

  -- ── REPEAT ──
  update public.players set ducats = 10000 where id = v_pl;
  v_n := coalesce((select ps.qty from public.player_storage ps join public.goods g on g.id = ps.good_id where ps.player_id = v_pl and ps.port_id = v_lis and g.code = 'iron'), 0);
  v_r := jsonb_build_array(cmd.land_repeat(false) ->> 'repeat');
  v_r := v_r || jsonb_build_array((select lp.repeat_on from public.land_parties lp where lp.id = v_party));
  perform public.land_send_for(v_pl, 'iron', t0 + interval '1 day');
  v_trip := (select (lp.terms ->> 'trip')::numeric from public.land_parties lp where lp.id = v_party);
  if v_r <> '["false", false]'::jsonb or (public.land_progress(v_party, t0 + interval '1 day' + make_interval(secs => 3 * v_trip)) ->> 'turns')::int <> 6
     or (public.land_progress(v_party, t0 + interval '1 day' + make_interval(secs => v_trip)) ->> 'phase') <> 'home' then
    raise exception 'proof 161 L1C_REPEAT: Repeat off is not one trip: %', v_r;
  end if;
  v_r := public.land_collect_for(v_pl, t0 + interval '1 day' + make_interval(secs => 3 * v_trip));
  if (v_r ->> 'units')::int <> 6 or (select lp.action from public.land_parties lp where lp.id = v_party) is not null then
    raise exception 'proof 161 L1C_REPEAT: the one trip did not end the job: %', v_r;
  end if;
  -- sent with Repeat off, turned on before the trip is home: on by itself to the cap (12 h: 11 whole 3,900-s trips)
  perform public.land_send_for(v_pl, 'iron', t0 + interval '2 days');
  perform public.land_repeat_for(v_pl, true, t0 + interval '2 days' + interval '10 minutes');
  v_r := public.land_progress(v_party, t0 + interval '2 days' + interval '13 hours');
  if (v_r ->> 'turns')::int <> floor((12 * 3600 + 600) / v_trip) * 6 or v_r ? 'done' then
    raise exception 'proof 161 L1C_REPEAT: turned on while out, it did not go on to the cap: %', v_r;
  end if;
  -- turned off while out at its fourth trip: that is the last
  perform public.land_repeat_for(v_pl, false, t0 + interval '2 days' + make_interval(secs => 3.5 * v_trip));
  v_r := public.land_collect_for(v_pl, t0 + interval '2 days' + make_interval(secs => 20 * v_trip));
  if (select lp.action from public.land_parties lp where lp.id = v_party) is not null
     or (select ps.qty from public.player_storage ps join public.goods g on g.id = ps.good_id where ps.player_id = v_pl and ps.port_id = v_lis and g.code = 'iron') <> v_n + 6 + 24 then
    raise exception 'proof 161 L1C_REPEAT: turned off while out, the trip under way was not the last: %', v_r;
  end if;
  -- a party called home stays called home whatever Repeat says
  perform public.land_send_for(v_pl, 'iron', t0 + interval '3 days');
  perform public.land_home_for(v_pl, t0 + interval '3 days' + interval '20 minutes');
  perform public.land_repeat_for(v_pl, true, t0 + interval '3 days' + interval '21 minutes');
  if not (select lp.terms ? 'home_at' from public.land_parties lp where lp.id = v_party) or cmd.land_repeat(null) ->> 'error_code' <> 'E_BAD_ORDER' then
    raise exception 'proof 161 L1C_REPEAT: Repeat undid Call home, or a null was taken';
  end if;
  perform public.land_collect_for(v_pl, t0 + interval '4 days');
  raise notice 'PASS: L1C_REPEAT - off: one % s trip; on while out: % turns to the cap; off at the fourth trip: 4 trips; Call home kept; null E_BAD_ORDER', v_trip, floor((12 * 3600 + 600) / v_trip) * 6;

  -- ── RARE FINDS ──
  if jsonb_array_length(public.land_terms(v_pl, 'lead') -> 'finds') <> 0
     or public.land_terms(v_pl2, 'lead') -> 'finds' <> '[{"code": "amber", "one_in": 100}, {"code": "baltic-amber", "one_in": 100}]'::jsonb then
    raise exception 'proof 161 L1C_FINDS: the finds are not the land''s: % / %', public.land_terms(v_pl, 'lead') -> 'finds', public.land_terms(v_pl2, 'lead') -> 'finds';
  end if;
  perform public.land_send_for(v_pl2, 'lead', t0);
  -- the dice, read on their own
  select jsonb_build_object('amber', count(*) filter (where z.r < 0.01), 'baltic-amber', count(*) filter (where z.r >= 0.01 and z.r < 0.02)) into v_dice
    from generate_series(1, (public.land_progress(c_bp, t0 + interval '12 hours') ->> 'turns')::int) n
    cross join lateral (select voyage.rng(c_bp, n, 'find:' || (select lp.terms ->> 'sent' from public.land_parties lp where lp.id = c_bp)) as r) z;
  -- twelve presses, an hour apart, inside a block that is rolled back
  begin
    v_split := '{}'::jsonb;
    for v_n in 1 .. 12 loop
      v_r := public.land_collect_for(v_pl2, t0 + make_interval(hours => v_n));
      v_split := jsonb_build_object('amber', coalesce((v_split ->> 'amber')::int, 0) + coalesce((v_r -> 'found' ->> 'amber')::int, 0),
                                    'baltic-amber', coalesce((v_split ->> 'baltic-amber')::int, 0) + coalesce((v_r -> 'found' ->> 'baltic-amber')::int, 0));
    end loop;
    raise exception using errcode = 'ZX161', message = v_split::text;
  exception when sqlstate 'ZX161' then
    v_split := sqlerrm::jsonb;
  end;
  -- one press at twelve hours: the same
  v_r := public.land_collect_for(v_pl2, t0 + interval '12 hours');
  v_one := jsonb_build_object('amber', coalesce((v_r -> 'found' ->> 'amber')::int, 0), 'baltic-amber', coalesce((v_r -> 'found' ->> 'baltic-amber')::int, 0));
  if v_one <> v_dice or v_split <> v_dice or (v_dice ->> 'amber')::int + (v_dice ->> 'baltic-amber')::int = 0
     or coalesce((select ps.qty from public.player_storage ps where ps.player_id = v_pl2 and ps.port_id = v_bal and ps.good_id = v_amber), 0) <> (v_dice ->> 'amber')::int
     or coalesce((select ps.basis from public.player_storage ps where ps.player_id = v_pl2 and ps.port_id = v_bal and ps.good_id = v_amber), 0) <> 0 then
    raise exception 'proof 161 L1C_FINDS: the dice % / twelve presses % / one press %', v_dice, v_split, v_one;
  end if;
  raise notice 'PASS: L1C_FINDS - none from Lisbon''s lead (British Isles), amber and baltic amber from the Baltic''s; 12 h: % by the dice = twelve presses = one press, at a cost of 0', v_dice;
  perform public.land_home_for(v_pl2, t0 + interval '12 hours');
  perform public.land_collect_for(v_pl2, t0 + interval '20 hours');

  -- ── A FULL STORAGE ──
  -- every turn finds amber (inside this proof); the shed is filled to under 0.2 of a tun: neither lead (0.8) nor amber (0.3) fits
  update public.land_drops d set one_in = 1 from public.goods g where g.id = d.good_id and g.code = 'amber' and d.action = 'lead';
  v_x := floor((public.storage_cap(v_bal) - public.storage_used(v_pl2, v_bal)) / 0.8);
  perform public.storage_put(v_pl2, v_bal, v_sand, v_x, null);
  if public.storage_cap(v_bal) - public.storage_used(v_pl2, v_bal) >= 0.2 then
    perform public.storage_put(v_pl2, v_bal, (select g.id from public.goods g where g.code = 'baltic-amber'), floor((public.storage_cap(v_bal) - public.storage_used(v_pl2, v_bal)) / 0.2), null);
  end if;
  v_n := coalesce((select ps.qty from public.player_storage ps where ps.player_id = v_pl2 and ps.port_id = v_bal and ps.good_id = v_amber), 0);
  perform public.land_send_for(v_pl2, 'lead', t0 + interval '1 day');
  v_trip := (select (lp.terms ->> 'trip')::numeric from public.land_parties lp where lp.id = c_bp);
  v_r := public.land_collect_for(v_pl2, t0 + interval '1 day' + make_interval(secs => v_trip));
  begin
    perform public.land_send_for(v_pl2, 'lead', t0 + interval '1 day' + make_interval(secs => v_trip + 1));
    v_note := 'sent';
  exception when others then
    v_note := split_part(sqlerrm, ':', 1);
  end;
  if (v_r -> 'found' ->> 'amber')::int <> 30 or (v_r -> 'found_waiting' ->> 'amber')::int < 1
     or (select lp.action from public.land_parties lp where lp.id = c_bp) is not null or v_note <> 'E_SHED_FULL'
     or coalesce((select ps.qty from public.player_storage ps where ps.player_id = v_pl2 and ps.port_id = v_bal and ps.good_id = v_amber), 0)
        + (v_r -> 'found_waiting' ->> 'amber')::int <> v_n + 30 then
    raise exception 'proof 161 L1C_SHED: a full shed lost a find or the party went out again (%): %', v_note, v_r;
  end if;
  -- the lead that waited goes first, as before; then room for everything: all booked
  perform public.storage_take(v_pl2, v_bal, v_sand, v_x);
  v_s := public.land_collect_for(v_pl2, t0 + interval '2 days');
  if (select lp.found_waiting from public.land_parties lp where lp.id = c_bp) <> '{}'::jsonb or (select lp.waiting from public.land_parties lp where lp.id = c_bp) <> 0
     or (select ps.qty from public.player_storage ps where ps.player_id = v_pl2 and ps.port_id = v_bal and ps.good_id = v_amber) <> v_n + 30 then
    raise exception 'proof 161 L1C_SHED: with room, the waiting find was not booked: %', v_s;
  end if;
  raise notice 'PASS: L1C_SHED - % amber waited with the party, the Send refused E_SHED_FULL; with room all 30 booked', v_r -> 'found_waiting' ->> 'amber';
  update public.land_drops d set one_in = 100 from public.goods g where g.id = d.good_id and g.code = 'amber' and d.action = 'lead';

  -- ── THE READ ──
  update public.land_parties set mules = 2 where id = c_bp;
  update public.land_parties set found_waiting = '{"jade": 2}'::jsonb where id = c_bp;
  perform cmd.assume_identity('00000000-0458-4000-8000-0000000161c2');
  v_r := world.land('mining');
  if (v_r -> 'party' ->> 'mules')::int <> 2 or (v_r -> 'party' ->> 'repeat')::boolean is not true
     or v_r -> 'party' -> 'found_waiting' <> '{"jade": 2}'::jsonb
     or (v_r -> 'packs' ->> 'now')::int <> 15 or v_r -> 'packs' -> 'next' <> '{"packs": 20, "price": 20000}'::jsonb
     or (select j -> 'finds' from jsonb_array_elements(v_r -> 'jobs') j where j ->> 'code' = 'lead') <> '[{"code": "amber", "one_in": 100}, {"code": "baltic-amber", "one_in": 100}]'::jsonb
     or (select jsonb_array_length(j -> 'finds') from jsonb_array_elements(v_r -> 'jobs') j where j ->> 'code' = 'coal') <> 0 then
    raise exception 'proof 161 L1C_READ: the read is not the party''s mules, Repeat, finds and the next mule: % %', v_r -> 'party', v_r -> 'packs';
  end if;
  raise notice 'PASS: L1C_READ - mules 2, packs 15, next 20 for 20,000, Repeat on, finds waiting, lead''s two finds from the Baltic, coal none';
end
$p$;
