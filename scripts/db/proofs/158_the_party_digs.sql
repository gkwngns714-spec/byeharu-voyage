-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 158 - THE PARTY DIGS  (migration 0455; docs/design/land-2026-11.md 4.4, 5.4, 6.2, 6.5, 8 L1; docs/dev-log/2026-11-18-land-l1.md)
--   The owner, 2026-11-16: "sending expeditions to land site (mountains), for minerals like rs3" ... "it should be connected" ... "max 100".
--
--   Dark as shipped first; then lit inside this proof's own transaction (proof.mjs rolls it back). Companies of the game's own making
--   (public.new_house) at Lisbon. Every instant is passed to the cores (public.land_*_for, public.land_progress), so the sum is read at fixed
--   times and nothing waits on the clock. The dice are pinned (world_secret), as production's are not the chain's.
--
-- @pass LAND_DARK    land_enabled false: the four doors refuse E_NOT_IN_USE, world.land says {enabled: false} and nothing else, the Levels card serves no land skill, the snapshot says false, no party row is made
-- @pass LAND_CURVE   the long curve is 100 x (1.1 ^ (L - 1) - 1) rounded down, 1 to 100 (10 at 2, 135 at 10, 10,571 at 50, 1,252,682 at 100); nothing above 100; every sea skill's level for every experience 0 to 9,100 is level_from_points'
-- @pass LAND_HOME    iron from Lisbon: no passage, a 300-s trip; the sum at 0, 14, 16, 61, 299 and 300 s; a Collect books trips x packs at a cost of 0 and the experience; a second at the same instant books nothing; experience is booked at most once in ten minutes and none is lost
-- @pass LAND_FAR     Sea Coal from Lisbon by Plymouth, 760.2 miles, 950 s a way; a 2,170-s trip read at 949, 966, 1,006, 2,169 and 2,170 s; on the British Isles' list while out, never on Iberia's; the haul in Lisbon's Storage, none at Plymouth
-- @pass LAND_CAP     a 300-s trip: 13 hours away give what 12 give; a trip longer than 12 hours comes home whole once, the next stops at the twelfth hour after the press, and goes on from there at the next press
-- @pass LAND_PICK    the plain pick costs 300 to the purse (ledger LAND, nothing minted), the next Send is 3 % faster, a second is refused E_LAND_HAVE, a short purse E_INSUFFICIENT_FUNDS
-- @pass LAND_SHED    a full Storage keeps the rest waiting with the party and loses none; the party is not sent again (E_SHED_FULL); with room, a Collect books what waited
-- @pass LAND_GIFT    a land skill's level-up pays Reputation at every fifth level only, what the matching sea level pays (level 5: 10; level 4: 0); each level a LEVEL_UP
-- @pass LAND_REFUSE  out already E_LAND_OUT; a level short E_NEEDS_SKILL with have / need; no such job E_NO_SUCH_JOB; a merchant E_NOT_IN_USE; a second company's party on the land makes company (crowd 2 %)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  t0      timestamptz := date_trunc('minute', now()) - interval '10 days';
  v_lis   uuid := (select p.id from public.ports p where p.code = 'LIS');
  v_ply   uuid := (select p.id from public.ports p where p.code = 'PLY');
  v_iron  uuid := (select g.id from public.goods g where g.code = 'iron');
  v_coal  uuid := (select g.id from public.goods g where g.code = 'coal');
  v_sand  uuid := (select g.id from public.goods g where g.code = 'sand');
  v_pl    uuid;
  v_pl2   uuid;
  v_npc   uuid;
  v_party uuid;
  v_r     jsonb;
  v_s     jsonb;
  v_t     timestamptz;
  v_n     numeric;
  v_purse bigint;
  v_note  text;
begin
  update public.world_config set value = to_jsonb('0455-fixed-dice-of-proof-158-the-party-digs-00000000000000000000000000'::text) where key = 'world_secret';
  update public.world_config set value = 'true'::jsonb where key in ('level_skills_on', 'reputation_on');
  -- 0457 re-timed the jobs by the market guard (proof 160 proves those rows). This proof proves the sum's mechanics on the design's
  -- hand-worked figures, pinned here inside its own rolled-back transaction: Iron 45 s and 4 experience, Sea Coal 40 s and 3.
  update public.land_actions set seconds = 45, xp = 4 where code = 'iron';
  update public.land_actions set seconds = 40, xp = 3 where code = 'coal';
  v_pl := public.new_house('00000000-0455-4000-8000-0000000158c1', 'Casa Mina 158', 'PRT', 'LIS', 'Mina 158', 'carlat', 'Mina 158', null, false);
  v_pl2 := public.new_house('00000000-0455-4000-8000-0000000158c2', 'Casa Vizinha 158', 'PRT', 'LIS', 'Vizinha 158', 'carlat', 'Vizinha 158', null, false);
  select p.id into v_npc from public.players p where p.is_npc order by p.id limit 1;
  if public.home_port_of(v_pl) <> v_lis or v_npc is null then
    raise exception 'proof 158: the probe companies are not of Lisbon, or no merchant';
  end if;
  perform cmd.assume_identity('00000000-0455-4000-8000-0000000158c1');

  -- ── DARK ──
  update public.world_config set value = 'false'::jsonb where key = 'land_enabled';
  v_r := jsonb_build_array(cmd.land_send('iron') ->> 'error_code', cmd.land_collect() ->> 'error_code', cmd.land_home() ->> 'error_code',
                           cmd.land_tool('plain-pick') ->> 'error_code');
  if v_r <> '["E_NOT_IN_USE", "E_NOT_IN_USE", "E_NOT_IN_USE", "E_NOT_IN_USE"]'::jsonb or world.land('mining') <> '{"enabled": false}'::jsonb
     or exists (select 1 from public.land_parties lp where lp.player_id = v_pl)
     or exists (select 1 from jsonb_array_elements(world.levels() -> 'level_skills' -> 'skills') s where s ->> 'code' = 'mining')
     or (world.snapshot() -> 'config' ->> 'land_enabled')::boolean is distinct from false then
    raise exception 'proof 158 LAND_DARK: a door opened or the land was served: %', v_r;
  end if;
  raise notice 'PASS: LAND_DARK - four doors E_NOT_IN_USE, the read {enabled: false}, no Mining tile, the snapshot false, no party';
  update public.world_config set value = 'true'::jsonb where key = 'land_enabled';

  -- ── THE CURVE ──
  if (select count(*) from public.level_curves c where c.curve = 'long' and c.xp = floor(100 * (power(1.1::numeric, c.level - 1) - 1))) <> 100
     or public.level_begins('mining', 2) <> 10 or public.level_begins('mining', 10) <> 135 or public.level_begins('mining', 50) <> 10571
     or public.level_begins('mining', 100) <> 1252682 or public.level_begins('mining', 101) is not null or public.level_top('mining') <> 100
     or public.level_of('mining', 1252682 + 10000000) <> 100 or public.level_of('mining', 134) <> 9 or public.level_of('mining', 135) <> 10
     or exists (select 1 from public.level_skills s cross join generate_series(0, 9100, 7) x
                 where s.side = 'sea' and public.level_of(s.code, x) <> public.level_from_points(x))
     or (select (s ->> 'top')::int from jsonb_array_elements(world.levels() -> 'level_skills' -> 'skills') s where s ->> 'code' = 'mining') <> 100
     or (select (s ->> 'top')::int from jsonb_array_elements(world.levels() -> 'level_skills' -> 'skills') s where s ->> 'code' = 'trading') <> 20 then
    raise exception 'proof 158 LAND_CURVE: the long curve or the sea''s levels are not as written';
  end if;
  raise notice 'PASS: LAND_CURVE - 100 rows, 10 / 135 / 10,571 / 1,252,682 at 2 / 10 / 50 / 100, none above; every sea level as before';

  -- ── THE FAR SITE (at Mining 1) ──
  v_r := public.land_passage(v_lis, v_coal);
  v_t := t0;
  perform public.land_send_for(v_pl, 'coal', v_t);
  select lp.id into v_party from public.land_parties lp where lp.player_id = v_pl;
  if v_r ->> 'via' <> 'PLY' or v_r ->> 'region' <> 'BRI' or (v_r ->> 'nm')::numeric <> 760.2 or (v_r ->> 'seconds')::int <> 950
     or (select (lp.terms ->> 'trip')::int from public.land_parties lp where lp.id = v_party) <> 2170
     or (public.land_progress(v_party, v_t + interval '949 seconds') ->> 'phase') <> 'out'
     or (public.land_progress(v_party, v_t + interval '966 seconds') ->> 'phase') <> 'digging'
     or (public.land_progress(v_party, v_t + interval '966 seconds') ->> 'in_packs')::int <> 0
     or (public.land_progress(v_party, v_t + interval '1006 seconds') ->> 'in_packs')::int <> 1
     or (public.land_progress(v_party, v_t + interval '2169 seconds') ->> 'turns')::int <> 0
     or (public.land_progress(v_party, v_t + interval '2170 seconds') ->> 'turns')::int <> 6
     or not exists (select 1 from public.land_parties lp join public.regions r on r.id = lp.region_id where lp.id = v_party and r.code = 'BRI') then
    raise exception 'proof 158 LAND_FAR: the coal trip is not by Plymouth in 2,170 s, or the sum is not the design''s: %', v_r;
  end if;
  v_r := public.land_collect_for(v_pl, v_t + interval '2170 seconds');
  if (v_r ->> 'units')::int <> 6
     or (select ps.qty from public.player_storage ps where ps.player_id = v_pl and ps.port_id = v_lis and ps.good_id = v_coal) <> 6
     or exists (select 1 from public.player_storage ps where ps.player_id = v_pl and ps.port_id = v_ply) then
    raise exception 'proof 158 LAND_FAR: the far haul is not in Lisbon''s Storage alone: %', v_r;
  end if;
  perform public.land_home_for(v_pl, v_t + interval '2171 seconds');
  perform public.land_collect_for(v_pl, v_t + interval '1 hour');
  raise notice 'PASS: LAND_FAR - Sea Coal by Plymouth, 760.2 miles, 950 s a way, 2,170 s a trip; out at 949 s, digging at 966 s, 1 in the packs at 1,006 s, 6 home at 2,170 s in Lisbon';

  -- ── THE HOME SITE ──
  v_t := t0 + interval '1 day';
  perform public.land_send_for(v_pl, 'iron', v_t);
  v_s := (select lp.terms from public.land_parties lp where lp.id = v_party);
  v_n := (select x.xp from public.level_xp x where x.player_id = v_pl and x.skill = 'mining');
  if (v_s ->> 's')::int <> 0 or (v_s ->> 'trip')::int <> 300
     or (public.land_progress(v_party, v_t) ->> 'phase') <> 'march'
     or (public.land_progress(v_party, v_t + interval '14 seconds') ->> 'phase') <> 'march'
     or (public.land_progress(v_party, v_t + interval '16 seconds') ->> 'in_packs')::int <> 0
     or (public.land_progress(v_party, v_t + interval '61 seconds') ->> 'in_packs')::int <> 1
     or (public.land_progress(v_party, v_t + interval '299 seconds') ->> 'turns')::int <> 0
     or (public.land_progress(v_party, v_t + interval '300 seconds') ->> 'turns')::int <> 6 then
    raise exception 'proof 158 LAND_HOME: the iron trip''s sum is not the design''s: %', v_s;
  end if;
  -- 5 minutes after the coal's booking (one hour after it): the 10-minute rule is passed; three trips home at 900 s
  v_r := public.land_collect_for(v_pl, v_t + interval '900 seconds');
  v_s := public.land_collect_for(v_pl, v_t + interval '900 seconds');
  if (v_r ->> 'units')::int <> 18 or (v_r ->> 'xp')::int <> 72 or (v_s ->> 'units')::int <> 0 or (v_s ->> 'xp')::int <> 0
     or (select ps.basis from public.player_storage ps where ps.player_id = v_pl and ps.port_id = v_lis and ps.good_id = v_iron) <> 0
     or (select x.xp from public.level_xp x where x.player_id = v_pl and x.skill = 'mining') <> v_n + 72 then
    raise exception 'proof 158 LAND_HOME: a Collect did not book 3 trips once: % then %', v_r, v_s;
  end if;
  -- 5 minutes later: two trips more come home, their experience waits on the party (under ten minutes since the last booking) ...
  v_r := public.land_collect_for(v_pl, v_t + interval '1200 seconds');
  if (v_r ->> 'units')::int <> 6 or (v_r ->> 'xp')::int <> 0 or (select lp.xp_due from public.land_parties lp where lp.id = v_party) <> 24
     or (select x.xp from public.level_xp x where x.player_id = v_pl and x.skill = 'mining') <> v_n + 72 then
    raise exception 'proof 158 LAND_HOME: experience was booked within ten minutes, or lost: %', v_r;
  end if;
  -- ... and is booked whole at the first press ten minutes on
  v_r := public.land_collect_for(v_pl, v_t + interval '1500 seconds');
  if (v_r ->> 'xp')::int <> 24 + 6 * 4 or (select x.xp from public.level_xp x where x.player_id = v_pl and x.skill = 'mining') <> v_n + 72 + 48
     or (select ps.qty from public.player_storage ps where ps.player_id = v_pl and ps.port_id = v_lis and ps.good_id = v_iron) <> 30 then
    raise exception 'proof 158 LAND_HOME: the waiting experience was not booked whole: %', v_r;
  end if;
  perform public.storage_take(v_pl, v_lis, v_iron, 100000);   -- room for what follows (Lisbon's shed is 750 tuns)
  raise notice 'PASS: LAND_HOME - iron 300 s a trip, the sum at 0 / 14 / 16 / 61 / 299 / 300 s; 18 iron and 72 experience once; 24 waited under ten minutes and was booked with the next 24';

  -- ── THE CAP ──
  -- a 300-s trip: away 13 hours give what 12 give (the press at 1,500 s is the last)
  if (public.land_progress(v_party, v_t + interval '1500 seconds' + interval '13 hours') ->> 'turns')::int
     <> (public.land_progress(v_party, v_t + interval '1500 seconds' + interval '12 hours') ->> 'turns')::int
     or (public.land_progress(v_party, v_t + interval '1500 seconds' + interval '12 hours') ->> 'turns')::int <> 6 * floor((1500 + 43200) / 300)
     or not (public.land_progress(v_party, v_t + interval '1500 seconds' + interval '13 hours') ->> 'stopped')::boolean then
    raise exception 'proof 158 LAND_CAP: 13 hours away gave more than 12';
  end if;
  perform public.land_home_for(v_pl, v_t + interval '1 day');
  perform public.land_collect_for(v_pl, v_t + interval '1 day 1 hour');
  -- a trip over 12 hours (the one dial at 0.5 %: every gather job 200 times as long): it comes home whole once with no press
  update public.world_config set value = '0.5'::jsonb where key = 'land_yield_pct';
  v_t := t0 + interval '3 days';
  perform public.land_send_for(v_pl, 'iron', v_t);
  v_s := (select lp.terms from public.land_parties lp where lp.id = v_party);
  v_n := (v_s ->> 'trip')::numeric;
  if v_n <= 12 * 3600 or (public.land_progress(v_party, v_t + make_interval(secs => v_n)) ->> 'turns')::int <> 6
     or (public.land_progress(v_party, v_t + make_interval(secs => v_n) + interval '20 hours') ->> 'turns')::int <> 6 then
    raise exception 'proof 158 LAND_CAP: a trip over 12 hours (% s) did not come home once, whole', v_n;
  end if;
  -- pressed when it is home: the next trip runs 12 hours from the press and stops there, short of home; at a press 30 h on it goes on from there
  perform public.land_collect_for(v_pl, v_t + make_interval(secs => v_n));
  v_r := public.land_progress(v_party, v_t + make_interval(secs => v_n) + interval '30 hours');
  if (v_r ->> 'stopped')::boolean is not true or (v_r ->> 'stop_at')::timestamptz <> v_t + make_interval(secs => v_n) + interval '12 hours'
     or (v_r ->> 'turns')::int <> 6 then
    raise exception 'proof 158 LAND_CAP: the second long trip did not stop at the twelfth hour after the press: %', v_r;
  end if;
  perform public.land_collect_for(v_pl, v_t + make_interval(secs => v_n) + interval '30 hours');
  -- after that press the clock runs again from where it stopped: the trip ends v_n - 12 h later
  v_r := public.land_progress(v_party, v_t + make_interval(secs => v_n) + interval '30 hours' + make_interval(secs => v_n - 12 * 3600));
  if (v_r ->> 'turns')::int <> 12 then
    raise exception 'proof 158 LAND_CAP: the stopped trip did not go on from where it stopped: %', v_r;
  end if;
  perform public.land_home_for(v_pl, now() - interval '1 day');
  perform public.land_collect_for(v_pl, now());
  update public.world_config set value = '100'::jsonb where key = 'land_yield_pct';
  raise notice 'PASS: LAND_CAP - 13 h away = 12 h on a 300-s trip; a % s trip home whole once, the next stopped at the 12th hour after the press and went on after the next', v_n;

  -- ── THE PICK ──
  update public.players set ducats = 1000 where id = v_pl;
  v_s := public.land_terms(v_pl, 'iron');
  v_r := cmd.land_tool('plain-pick');
  if (v_r ->> 'ok')::boolean is not true or (select p.ducats from public.players p where p.id = v_pl) <> 700
     or (select count(*) from public.ledger l where l.player_id = v_pl and l.kind = 'LAND' and l.ducats_delta = -300) <> 1
     or (public.land_terms(v_pl, 'iron') ->> 'tool')::numeric <> 3
     or (public.land_terms(v_pl, 'iron') ->> 'a')::int <> round(45 * (1 - public.wc_num('land_level_speed_pct') / 100 * ((v_s ->> 'have')::int - 1)) * 0.97)
     or cmd.land_tool('plain-pick') ->> 'error_code' <> 'E_LAND_HAVE' or cmd.land_tool('gold-pick') ->> 'error_code' <> 'E_NO_SUCH_ITEM' then
    raise exception 'proof 158 LAND_PICK: the pick did not cost 300, speed the next Send by 3 %%, or refuse a second: %', v_r;
  end if;
  v_n := (public.land_terms(v_pl, 'iron') ->> 'a')::numeric;
  update public.land_parties set tools = '{}' where id = v_party;
  update public.players set ducats = 100 where id = v_pl;
  if cmd.land_tool('plain-pick') ->> 'error_code' <> 'E_INSUFFICIENT_FUNDS' or (select p.ducats from public.players p where p.id = v_pl) <> 100 then
    raise exception 'proof 158 LAND_PICK: a short purse bought a pick';
  end if;
  raise notice 'PASS: LAND_PICK - 300 from the purse (ledger LAND), iron % s a turn -> %, a second E_LAND_HAVE, a short purse E_INSUFFICIENT_FUNDS', v_s ->> 'a', v_n;

  -- ── A FULL STORAGE ──
  -- fill Lisbon's shed to within 2 tuns: 2 iron fit (0.8 a unit), the rest of a trip waits
  v_n := public.storage_cap(v_lis) - public.storage_used(v_pl, v_lis) - 2;
  perform public.storage_put(v_pl, v_lis, v_sand, floor(v_n / 0.8), null);
  v_n := coalesce((select ps.qty from public.player_storage ps where ps.player_id = v_pl and ps.port_id = v_lis and ps.good_id = v_iron), 0);
  v_t := t0 + interval '6 days';
  perform public.land_send_for(v_pl, 'iron', v_t);
  v_r := public.land_collect_for(v_pl, v_t + interval '300 seconds');
  v_s := (select to_jsonb(lp) from public.land_parties lp where lp.id = v_party);
  begin
    perform public.land_send_for(v_pl, 'iron', v_t + interval '301 seconds');
    v_note := 'sent';
  exception when others then
    v_note := split_part(sqlerrm, ':', 1);
  end;
  if (v_r ->> 'units')::int + (v_r ->> 'waiting')::int <> 6 or (v_r ->> 'waiting')::int < 1 or (v_s ->> 'action') is not null
     or coalesce((select ps.qty from public.player_storage ps where ps.player_id = v_pl and ps.port_id = v_lis and ps.good_id = v_iron), 0) <> v_n + (v_r ->> 'units')::int
     or v_note <> 'E_SHED_FULL' then
    raise exception 'proof 158 LAND_SHED: a full shed lost goods or the party went out again (%): % %', v_note, v_r, v_s;
  end if;
  perform public.storage_take(v_pl, v_lis, v_sand, 100);
  v_s := public.land_collect_for(v_pl, v_t + interval '400 seconds');
  if (v_s ->> 'waiting')::int <> 0 or (select lp.waiting from public.land_parties lp where lp.id = v_party) <> 0
     or (select ps.qty from public.player_storage ps where ps.player_id = v_pl and ps.port_id = v_lis and ps.good_id = v_iron) <> v_n + 6 then
    raise exception 'proof 158 LAND_SHED: with room, what waited was not booked: %', v_s;
  end if;
  raise notice 'PASS: LAND_SHED - % fitted, % waited with the party, the Send refused E_SHED_FULL; with room, all 6 booked', v_r ->> 'units', v_r ->> 'waiting';
end
$p$;

do $p$
declare
  v_pl   uuid := (select p.id from public.players p where p.company_name = 'Casa Mina 158');
  v_pl2  uuid := (select p.id from public.players p where p.company_name = 'Casa Vizinha 158');
  v_npc  uuid := (select p.id from public.players p where p.is_npc order by p.id limit 1);
  v_r    jsonb;
  v_note text;
begin
  -- ── THE GIFT: a fresh skill's levels 2 to 5 paid by the one writer ──
  update public.world_config set value = 'true'::jsonb where key = 'land_enabled';
  perform public.level_grant(v_pl2, 'dig', 46, 'proof158:gift');
  if (select count(*) from public.events e where e.player_id = v_pl2 and e.kind = 'LEVEL_UP' and e.payload ->> 'track' = 'mining') <> 4
     or (select (e.payload ->> 'reputation')::int from public.events e where e.player_id = v_pl2 and e.kind = 'LEVEL_UP' and e.payload ->> 'track' = 'mining' and (e.payload ->> 'level')::int = 4) <> 0
     or (select (e.payload ->> 'reputation')::int from public.events e where e.player_id = v_pl2 and e.kind = 'LEVEL_UP' and e.payload ->> 'track' = 'mining' and (e.payload ->> 'level')::int = 5)
        <> public.wc_int('rep_level_per_level') * 1 then
    raise exception 'proof 158 LAND_GIFT: levels 2 to 5 did not pay at the fifth alone';
  end if;
  raise notice 'PASS: LAND_GIFT - Mining 1 -> 5: four LEVEL_UPs, Reputation 0 at 2, 3, 4 and % at 5', public.wc_int('rep_level_per_level');

  -- ── THE REFUSALS, through the doors, and company at a site ──
  perform cmd.assume_identity('00000000-0455-4000-8000-0000000158c2');
  perform public.land_send_for(v_pl2, 'iron', now() - interval '1 minute');
  v_r := jsonb_build_array(cmd.land_send('clay') ->> 'error_code');
  perform public.land_send_for(v_pl, 'iron', now() - interval '1 minute');
  v_r := v_r || jsonb_build_array((select (lp.terms ->> 'crowd')::numeric from public.land_parties lp where lp.player_id = v_pl));
  perform public.land_home_for(v_pl2, now());
  perform public.land_collect_for(v_pl2, now() + interval '1 hour');
  v_r := v_r || jsonb_build_array(cmd.land_send('platinum') -> 'figures', cmd.land_send('no-such') ->> 'error_code');
  begin
    perform public.land_send_for(v_npc, 'iron', now());
    v_note := 'sent';
  exception when others then
    v_note := split_part(sqlerrm, ':', 1);
  end;
  if v_r <> jsonb_build_array('E_LAND_OUT', 2, jsonb_build_object('have', public.level_of('mining', 46), 'need', 96, 'unit', 'level'), 'E_NO_SUCH_JOB')
     or v_note <> 'E_NOT_IN_USE' then
    raise exception 'proof 158 LAND_REFUSE: the refusals are not out, crowd, level and job, merchant: % %', v_r, v_note;
  end if;
  raise notice 'PASS: LAND_REFUSE - E_LAND_OUT; company 2 %%; E_NEEDS_SKILL %; E_NO_SUCH_JOB; a merchant E_NOT_IN_USE', v_r -> 2;
end
$p$;
