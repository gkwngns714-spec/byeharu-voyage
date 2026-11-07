-- 0338 PARITY SCENE: run by proof-0338.mjs on the world BEFORE the file and AFTER it, rolled back each time. It names only what existed before 0338, and it reads everything the pirates must NOT change:
-- the ten realms, every harbour but the four pirate homes and the three new ones, the old fields of the nations, the old money. Every SCENE line must be equal, byte for byte, before and after.
-- (The pirates' own changes are proved by scripts/db/proofs/45_the_brethren.sql; this scene is the other half of "a slice that cannot hurt a live world".)
-- LOCAL PGlite WORLD ONLY (scripts/ops/harness/README.md): this scene writes and its runner rolls it back. The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite), so `db query --linked -f` can never commit it on production.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $$
declare
  c_skip constant text[] := array['POR', 'LGA', 'GOT', 'DJE'];
  c_ten  constant text[] := array['ENG', 'ESP', 'FRA', 'JOS', 'JPN', 'MNG', 'MUG', 'NLD', 'OTT', 'PRT'];
  v_prt  uuid := (select n.id from public.nations n where n.code = 'PRT');
  v_a    uuid;
  v_m    uuid;
  v_txt  text;
  v_uid  constant uuid := '00000000-0338-4000-8000-000000000001';
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'influence_enabled', 'economy_closed', 'regard_enabled');
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Casa Cena 0338', v_prt, 5000000, false) returning id into v_a;
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Merchant Cena 0338', v_prt, 5000000, true) returning id into v_m;
  update public.players set auth_uid = v_uid where id = v_a;
  -- a world with money in it, so "W unchanged" and "the book is equal" are measured on something: every purse but the three new ones, a few influence rows
  update public.port_treasury t set ducats = 1000000 + abs(hashtext(p.code)) % 5000000 from public.ports p where p.id = t.port_id and p.code not in ('LGA', 'GOT', 'DJE');
  insert into public.port_influence (port_id, nation_id, player_id, points, day_given) select p.id, v_prt, v_a, 12345 + length(p.code), 100 from public.ports p where p.code in ('SAL', 'LIS', 'ARK');

  -- the tax, the dock fee and the dues line at every other harbour, for a company and for a merchant (stance, regard and all)
  select md5(string_agg(p.code || '|' || world.tax_rate(p.id, v_a)::text || '|' || public.port_fee(p.id, v_a, 1000000)::text || '|' || (public.port_dues(p.id, v_a, 1000000))::text
                        || '|' || world.tax_rate(p.id, v_m)::text || '|' || public.port_fee(p.id, v_m, 1000000)::text || '|' || world.tax_rate(p.id)::text, ';' order by p.code))
    into v_txt from public.ports p where p.kind = 'HARBOUR' and p.code <> all (c_skip) and p.code not in ('LGA', 'GOT', 'DJE');
  raise notice 'SCENE: QUOTES %', v_txt;

  -- the crown of every other harbour, and the ten capitals
  raise notice 'SCENE: CAPITALS %', (select md5(string_agg(p.code || '>' || coalesce((select c.code from public.ports c where c.id = public.city_capital(p.id)), '-'), ';' order by p.code))
                                       from public.ports p where p.kind = 'HARBOUR' and p.code <> all (c_skip) and p.code not in ('LGA', 'GOT', 'DJE'));
  raise notice 'SCENE: REALM_CAPITALS %', (select string_agg(n.code || '>' || coalesce((select c.code from public.ports c where c.id = public.realm_capital(n.id)), '-'), ';' order by n.code) from public.nations n where n.code = any (c_ten));

  -- the curves of the ten: cargo ships wanted, navy size, realm purse
  raise notice 'SCENE: CONVOY %', (select string_agg(n.code || ':' || w.cash || ':' || w.ships, ';' order by n.code) from public.convoy_ships_wanted() w join public.nations n on n.id = w.nation_id);
  raise notice 'SCENE: NAVY_SIZES %', (select string_agg(n.code || ':' || public.realm_purse(n.id) || ':' || public.navy_size_for(public.realm_purse(n.id)), ';' order by n.code) from public.nations n where n.code = any (c_ten));

  -- what the client reads: every other port of the snapshot, and the old fields of the old nations
  raise notice 'SCENE: SNAPSHOT_PORTS %', (select md5(string_agg(e::text, ';' order by e ->> 'code')) from jsonb_array_elements(world.snapshot() -> 'ports') e
                                              where e ->> 'code' <> all (c_skip) and e ->> 'code' not in ('LGA', 'GOT', 'DJE'));
  raise notice 'SCENE: SNAPSHOT_NATIONS %', (select md5(string_agg((e ->> 'code') || '|' || (e ->> 'name') || '|' || (e ->> 'flag_char') || '|' || coalesce(e ->> 'capital', '-') || '|' || (e ->> 'great'), ';' order by e ->> 'code'))
                                                from jsonb_array_elements(world.snapshot() -> 'nations') e where e ->> 'code' <> 'PIR');
  raise notice 'SCENE: STANDINGS %', (select md5(string_agg(e::text, ';' order by e ->> 'nation')) from jsonb_array_elements(world.nation_standings() -> 'countries') e where e ->> 'nation' <> 'PIR');
  perform cmd.assume_identity(v_uid);
  raise notice 'SCENE: LEVELS_REGARD %', (select md5(string_agg(e::text, ';' order by e ->> 'code')) from jsonb_array_elements(world.levels() -> 'regard') e);

  -- the depth of every other harbour, the old relations, the old influence book, the flows, the money
  raise notice 'SCENE: DEPTH %', (select md5(string_agg(p.code || ':' || coalesce(t.depth_mult::text, '-') || ':' || coalesce(t.depth_day::text, '-'), ';' order by p.code))
                                    from public.ports p join public.port_treasury t on t.port_id = p.id where p.code <> all (c_skip) and p.code not in ('LGA', 'GOT', 'DJE'));
  raise notice 'SCENE: RELATIONS %', (select md5(string_agg(r.a::text || r.b::text || r.stance || r.why, ';' order by r.a, r.b)) from public.power_relations r
                                        where r.a in (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = any (c_ten))
                                          and r.b in (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = any (c_ten)));
  raise notice 'SCENE: INFLUENCE rows % points % given %', (select count(*) from public.port_influence), (select coalesce(sum(points), 0) from public.port_influence), (select coalesce(sum(day_given), 0) from public.port_influence);
  raise notice 'SCENE: FLOWS % %', (select count(*) from public.treasury_flows), (select count(*) from public.treasury_daybook);
  raise notice 'SCENE: W purses % companies % aboard %', (select coalesce(sum(public.treasury_balance(t.port_id)), 0) from public.port_treasury t),
    (select coalesce(sum(p.ducats), 0) from public.players p), public.funds_aboard();
  raise notice 'SCENE: OLD_STANCES %', (select md5(string_agg(a.code || b.code || public.power_stance(a.id, b.id), ';' order by a.code, b.code)) from public.nations a join public.nations b on b.code > a.code where a.code = any (c_ten) and b.code = any (c_ten));
end
$$;
