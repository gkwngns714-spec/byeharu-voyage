-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 237 - LAND RAIDS (THE FIGHT) AND CAPTAIN UPGRADES  (migrations 0532, 0533; dark: land_raids_enabled, honor_enabled; docs/dev-log/2026-11-25-captain-works.md)
--
-- @pass LR_FOES   every foe of the data, met by a captain of its level with 48 hands, is fought 16 times to an end; the crew cap follows the COMBAT level
-- @pass LR_CARD   the card of each: hands a round, what it brings; never a result, a chance or the seed
-- @pass LR_ROUNDS 1,000 rounds: the hands lost a round are the card's mean; rounds 1 to 1,000 read once and read again are the same rounds
-- @pass LR_COST   the 16 fights of a Send, in ms (printed; fails only over 2 s)
-- @pass CU_RAID   Drill and Surgeon's hand: the same Send costs fewer hands a round; the sea's figures of a fleet she sits in do not move by a digit
-- @pass CU_DIG    Pathfinder shortens the turn of the party she leads, frozen at Send; a rank bought while it is out is refused
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  v_me uuid; v_po uuid; v_code text; v_fl uuid; v_sh uuid; v_pa uuid; v_t jsonb; v_t2 jsonb; v_c jsonb; v_c2 jsonb; v_seed uuid := '00000000-0532-4000-8000-000000000237'; v_at timestamptz; v_ms numeric; v_n int := 0;
  v_mean numeric; v_s1 text; v_s2 text; v_sea0 text; v_sea1 text; v_act text; v_a0 int; v_a1 int; f record; v_txt text := '';
begin
  v_me := public.new_house('00000000-0533-4000-8000-0000000002a1', 'Casa do Covil 237', 'PRT');
  select x.id into v_fl from public.fleets x where x.player_id = v_me;
  select s.id into v_sh from public.ships s where s.fleet_id = v_fl and s.is_flagship;
  select o.code into v_code from public.officers o join public.captain_job j on j.officer_id = o.id where j.job = 'NAVIGATOR' order by o.code limit 1;
  update public.players set ducats = 500000 where id = v_me;
  perform cmd.assume_identity('00000000-0533-4000-8000-0000000002a1');
  perform public.sign_officer(v_me, v_code, null);
  select po.id into v_po from public.player_officers po where po.player_id = v_me;
  update public.world_config set value = 'true'::jsonb where key in ('land_enabled', 'captain_works_enabled', 'land_raids_enabled');
  update public.world_config set value = 'false'::jsonb where key = 'levels_bite';

  -- LR_FOES, LR_CARD
  if public.land_raid_crew_cap(v_me) <> 10 then raise exception 'LR_FOES: the first crew is not 10'; end if;
  update public.world_config set value = '[48, 2]'::jsonb where key = 'land_crew_cap';
  if public.land_raid_crew_cap(v_me) <> 48 then raise exception 'LR_FOES: the cap is not the data''s'; end if;
  for f in select * from public.land_foes x order by x.ord loop
    insert into public.captain_work_xp (player_officer_id, work, xp) select v_po, 'arms', c.xp from public.level_curves c where c.curve = 'long' and c.level = f.level
    on conflict (player_officer_id, work) do update set xp = excluded.xp;
    v_t := public.land_raid_terms(v_me, f.code, 48, v_po, v_seed);
    if v_t ? 'short' or jsonb_array_length(v_t->'fights') <> 16 then raise exception 'LR_FOES: %: %', f.code, v_t; end if;
    v_c := public.land_raid_card(v_t);
    if v_c ? 'fights' or v_c ? 'seed' or v_c::text ~* '(chance|odds|win)' then raise exception 'LR_CARD: %', v_c; end if;
    v_txt := v_txt || format('%s(%s): %s of 16, %s hands a round; ', f.word, f.level, (select count(*) from jsonb_array_elements(v_t->'fights') w where (w->>0)::int = 1), v_c #>> '{cost,hands}');
    v_n := v_n + 1;
  end loop;
  raise notice 'PASS: LR_FOES — % foes, 16 fights each (of 48 hands): %', v_n, v_txt;
  raise notice 'PASS: LR_CARD — %', v_c;

  -- LR_COST
  v_at := clock_timestamp();
  v_t := public.land_raid_terms(v_me, 'robbers', 48, v_po, v_seed);
  v_ms := round(extract(epoch from clock_timestamp() - v_at)::numeric * 1000);
  if v_ms > 2000 then raise exception 'LR_COST: % ms', v_ms; end if;
  raise notice 'PASS: LR_COST — a Send''s 16 fights: % ms', v_ms;

  -- LR_ROUNDS
  v_mean := (public.land_raid_card(v_t) #>> '{cost,hands}')::numeric;
  select avg(r.hands), md5(string_agg(r::text, ',' order by n)) into v_ms, v_s1 from generate_series(1, 1000) n cross join lateral public.land_raid_round(v_t, v_seed, n) r;
  select md5(string_agg(r::text, ',' order by n)) into v_s2 from generate_series(1, 1000) n cross join lateral public.land_raid_round(v_t, v_seed, n) r;
  -- 16 equally likely fights and a fair fraction: within a tenth of the mean, and a twentieth of a hand
  if v_s1 is distinct from v_s2 or abs(v_ms - v_mean) > v_mean * 0.1 + 0.05 then raise exception 'LR_ROUNDS: % hands a round against a card of %', v_ms, v_mean; end if;
  raise notice 'PASS: LR_ROUNDS — % hands a round over 1,000, the card says %', round(v_ms, 3), v_mean;

  -- CU_RAID
  perform public.captain_seat_put(v_po, v_sh, 1);
  select string_agg(e.code || '=' || public.crew_pct(v_fl, v_sh, e.code, null), ',' order by e.code) into v_sea0 from public.crew_effects e where e.scope = 'fleet' and e.code <> 'category_spread';
  v_c := public.land_raid_card(v_t);
  update public.world_config set value = 'true'::jsonb where key = 'honor_enabled';
  perform public.honor_credit(v_me, 'land', 5000, 'proof-237');
  for v_n in 1 .. 5 loop
    perform cmd.captain_upgrade(v_code, 'drill');
    perform cmd.captain_upgrade(v_code, 'surgeon');
    perform cmd.captain_upgrade(v_code, 'pathfinder');
  end loop;
  v_t2 := public.land_raid_terms(v_me, 'robbers', 48, v_po, v_seed);
  v_c2 := public.land_raid_card(v_t2);
  select string_agg(e.code || '=' || public.crew_pct(v_fl, v_sh, e.code, null), ',' order by e.code) into v_sea1 from public.crew_effects e where e.scope = 'fleet' and e.code <> 'category_spread';
  if (v_c2 #>> '{cost,hands}')::numeric >= (v_c #>> '{cost,hands}')::numeric or v_sea1 is distinct from v_sea0 then raise exception 'CU_RAID: % against %, the sea % / %', v_c2, v_c, v_sea1, v_sea0; end if;
  raise notice 'PASS: CU_RAID — % hands a round, % with five ranks of Drill and Surgeon''s hand; the sea unmoved', v_c #>> '{cost,hands}', v_c2 #>> '{cost,hands}';

  -- CU_DIG
  select a.code into v_act from public.land_actions a where a.skill = 'mining' and a.level = 1 and jsonb_typeof(public.land_terms(v_me, a.code)->'short') = 'null' order by (public.land_terms(v_me, a.code)->>'trip')::numeric, a.code limit 1;
  v_a0 := (public.land_terms(v_me, v_act)->>'a')::int;
  perform cmd.captain_land(v_code, 1);
  perform public.land_send_for(v_me, v_act, now());
  v_pa := public.land_party(v_me);
  v_a1 := (select (lp.terms->>'a')::int from public.land_parties lp where lp.id = v_pa);
  if v_a1 <> greatest(1, round(v_a0 * 0.85))::int or cmd.captain_upgrade(v_code, 'quartermaster')->>'error_code' is distinct from 'E_LAND_OUT' then
    raise exception 'CU_DIG: % then %', v_a0, v_a1;
  end if;
  raise notice 'PASS: CU_DIG — a turn of % s, % s with Pathfinder 5; out, a rank is refused', v_a0, v_a1;
end $p$;
