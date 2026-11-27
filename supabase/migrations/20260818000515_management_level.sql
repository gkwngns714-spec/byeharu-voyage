-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights management_level_enabled or trade_benefits_enabled)
-- 0515 - THE MANAGEMENT LEVEL, AND WHAT TRADING'S LEVELS GIVE  (dark: the owner's switches management_level_enabled and
--   trade_benefits_enabled, false. Slice `management-level`, docs/design/owner-spec-red-2026-11-25.md R9, R10, section 2)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25: "NOPE, trading levels will give benefits when trading, such as +% increase in overall profits, bargaining
--   success rate, etc." and "There will be a new level, skill called management. This skill will enable to control fleets. You will be
--   able to control fleets from the start of the game, as long as you have fleet/".
--
-- MANAGEMENT IS A LEVEL IN THE EXISTING LEVEL TABLES (public.level_skills; 20 levels on the short curve; no second system). IT LOCKS
--   NOTHING: no job door, no plan and no tick asks it (asserted: no function but the readings below names it); a company of level 1
--   commands every fleet it has.
--   * Earned by running fleet jobs: a sail of 20 miles or more that makes a port, by a fleet whose standing job is not stopped, gives 5
--     (activity `job_sail`, once a voyage, key job:<voyage>, 300 a day; public.level_arrival, where a voyage's other levels are granted).
--   * What its levels give was NOT SAID; decided by default: every fleet's crew wage is 2 % less at levels 4, 8, 12, 16, 20 (perk
--     `fleet_wage`, 10 % in all; public.fleet_wage, the one reading of a wage, added to what Pursership takes off); and a waiting job is
--     asked again sooner, 6 % of the wait at 3, 7, 11, 15, 19 (perk `job_wait`, 30 % in all: 900 s becomes 630 s; NEVER under the 600 s of
--     0498's rule; public.job_wait_s, the one figure both of the job note's waits read).
-- TRADING'S NEW BENEFITS (added; every step Trading has today stays: one more fleet at 3 and 6 (fleet_room_levels), routes at 2 7 11 15
--   19, ships a fleet at 4 9 13 17, the yard's fee at 5 8 10 12 14 16 18 20 (0468), titles, captains' ceilings and promotions (0411); the
--   other levels' steps (0417, 0453) and the client's gate at Trading 5 (src/live/levelGate.ts) are not touched either):
--   * `trade_profit`, 1 point at 4, 8, 12, 16, 20 (5 in all): SHE KEEPS THAT MANY MORE POINTS OF EACH SALE'S PROFIT. It is a cut of ONE of
--     her costs, THE CITY'S TAX ON HER PROFIT (neither dock fees nor wages, and no coin is made): the rate the city asks her
--     (world.tax_rate, the one authority, through public.tax_home_half, where each of its answers passes) is that many points less, AND
--     NEVER LESS THAN HALF of what it was (trade_tax_keep 0.5): a city always keeps half its tax. Where the tax is nought (a pirate home)
--     nothing is given. Every reader of the rate moves with it: the door's TAX, the quotes of a run, Trade's board, the Town Hall's
--     "yours" and 0507's buy tax (a tenth of the same rate). The city gets exactly what she no longer pays less; the world's sum is the
--     same to the coin (asserted).
--   * `trade_bargain`, 1 point at 2, 6, 10, 14, 18 (5 in all): the first bargain's chance (public.bargain_p1, 0506; its ceiling stays).
--     A bargain is paid by the city's purse in the trade itself.
-- A STEP MAY WAIT FOR A SWITCH: public.level_perks.lit_by (as level_skills.lit_by, 0461 / 0506), read by the one reading (public.level_perk)
--   and the one list (public.level_benefits). Trading's steps are still under level_unlocks_enabled (0468) and level_perks_on (0417) too.
-- A merchant: no experience, no mark, so 0. DARK: every figure as before.
-- COST: dark, one switch read more a wage and a rate. Lit: a wage reads three keys more; a rate one key for a merchant (no mark: out),
--   four for a player. Arrival: one key more; a job's sail one level_book row and one level_xp update, at most 60 a company a day.
-- budget: no table, no cron, no index; one column on a 110-row table; lit, at most 60 level_book rows a company a day.
-- retention: none (no table is made; level_book's is 0411's).
-- THE HUNKS (11; each once, each reverses): level_perk x2, level_benefits x1, level_arrival x1, fleet_wage x1, bargain_p1 x1,
--   tax_home_half x3, fleet_job_note x2.
-- LOCKS: ALTER TABLE level_perks (one column), rows in three level tables, CREATE OR REPLACE x7, CREATE FUNCTION x4, three knobs. TIME: a
--   second. BUDGET: statement_timeout 60 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): QUICK, both switches false (every figure as before at once; experience kept). FULL: a migration reversing
--   the hunks (OLD texts below verbatim), deleting the rows, the column and the knobs.
-- SELF-ASSERT: hunks once and reversing; no other function moved; grants and settings unmoved; no knob of another file moved; the new
--   functions server only. THE PROBE (rolled back; its own company, city rate and cargo: nothing of prod's market, dice or companies is
--   asked a sign): dark identical before and after; lit, the wage, the wait, the rate (and its half), the sale's tax through the door with
--   the city's loss her gain to the coin, the bargain, the grant and its day's cap. Proof 219 plays the doors.
-- VERSION: 0515 (the lead deploys in number order; built on 0507 and 0502).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $m$
declare
  c_hunked constant text[] := array['public.level_perk(uuid,text)', 'public.level_benefits(text,integer)', 'public.level_arrival(uuid,uuid)',
    'public.fleet_wage(uuid,boolean,integer)', 'public.bargain_p1(uuid,uuid,uuid,uuid)', 'public.tax_home_half(uuid,uuid,numeric,numeric)',
    'public.fleet_job_note(uuid,jsonb)'];
  c_new    constant text[] := array['public.management_on()', 'public.trade_tax_cut(uuid,numeric)', 'public.job_wait_s(uuid)', 'public.job_sail_xp(uuid,uuid)'];
  c_knobs  constant text[] := array['management_level_enabled', 'trade_benefits_enabled', 'trade_tax_keep'];
  c_ua     constant uuid := '00000000-0515-4000-8000-0000000000a1';
  v_t0         timestamptz := clock_timestamp();
  x            record;
  v_def        text;
  v_pre        text;
  v_old        text;
  v_new        text;
  v_n          int;
  v_fn_before  text;
  v_meta       text;
  v_cfg_before text;
  v_b          jsonb;
  v_d          jsonb;
  v_l          jsonb;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = any (c_knobs)) or exists (select 1 from unnest(c_new) f where to_regprocedure(f) is not null)
     or exists (select 1 from public.level_skills s where s.code = 'management') then
    raise exception '0515 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked || array['public.level_grant(uuid,text,numeric,text)', 'world.tax_rate(uuid,uuid)', 'public.jobs_wait_on()', 'public.run_guard_on()']) f
              where to_regprocedure(f) is null) then
    raise exception '0515 refuses: 0498, 0502, 0505, 0506 or the levels (0411, 0417, 0468) are not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0515 (fn text primary key, def text) on commit drop;
  insert into pre_0515 select f, replace(pg_get_functiondef(f::regprocedure), E'\r', '') from unnest(c_hunked) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE SCENE (temp functions: their own company, city rate and cargo; the same figures dark before, dark after, and lit) ──
  execute $f$
create function pg_temp.sale_0515(p_player uuid, p_fleet uuid, p_port uuid, p_good uuid, p_code text)
returns jsonb
language plpgsql
as $body$
-- one sale of 5 units that cost 1 a unit, through the door; rolled back; her gain, the city's (its purse's flows with her alone: another
-- company's trade in that city in the same second is not counted), the tax
declare
  v_p0 bigint := (select p.ducats from public.players p where p.id = p_player);
  v_c0 bigint := (select coalesce(sum(t.ducats), 0) from public.treasury_flows t where t.player_id = p_player and t.port_id = p_port);
  v_r  jsonb;
  v_o  jsonb;
begin
  perform public.fleet_load(p_fleet, p_code, 5, 1);
  v_r := cmd.do_sell(p_fleet, jsonb_build_object('good', p_good, 'qty', 5));
  v_o := jsonb_build_object('tax', v_r->'tax', 'total', v_r->'total', 'profit', v_r->'profit',
                            'her', (select p.ducats from public.players p where p.id = p_player) - v_p0, 'city', (select coalesce(sum(t.ducats), 0) from public.treasury_flows t where t.player_id = p_player and t.port_id = p_port) - v_c0);
  raise exception using errcode = 'ZY515', message = v_o::text;
exception when sqlstate 'ZY515' then
  return sqlerrm::jsonb;
end
$body$
  $f$;
  execute $f$
create function pg_temp.scene_0515(p_uid uuid, p_lit boolean)
returns jsonb
language plpgsql
as $body$
declare
  v_lis uuid := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  v_pl  uuid;
  v_fl  uuid;
  v_g   uuid;
  v_gc  text;
  v_out jsonb;
  v_lv  int;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'level_unlocks_enabled', 'level_perks_on', 'level_skills_on');
  update public.world_config set value = 'false'::jsonb where key in ('influence_enabled', 'pirate_ports_free', 'tax_thirty_enabled', 'bargain_total_enabled');
  -- the city's rate, 10 %: its column 5 %, the knob 2 (inside this rolled-back block only)
  update public.world_config set value = to_jsonb(2) where key = 'profit_tax_scale';
  update public.world_config set value = to_jsonb(0.3) where key = 'tax_rate_max';
  insert into public.port_treasury (port_id) values (v_lis) on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 50000000 where port_id = v_lis;
  update public.ports set tax_rate = 0.05 where id = v_lis;
  v_pl := public.new_house(p_uid, 'Casa da Prova 0515', 'PRT');
  select f.id into v_fl from public.fleets f where f.player_id = v_pl;
  update public.players set ducats = 1000000 where id = v_pl;
  update public.fleets set call_fee = null where id = v_fl;
  -- a good of Lisbon's quay, its row written here: whatever the live market says
  select g.id, g.code into v_g, v_gc from public.port_goods pg join public.goods g on g.id = pg.good_id
   where pg.port_id = v_lis and public.port_offers(v_lis, g.id) and g.bulk > 0 and g.bulk <= 2
     and not public.culture_refuses((select h.culture from public.ports h where h.id = v_lis), g.culture_mask)
   order by g.base_value desc, g.code limit 1;
  update public.port_goods set stock_target = 100000, stock = 100000, affinity = 1, demand = 1, drift = 0, season_mod = 0, glut = 0, glut_at = now(), updated_at = now(),
                               want_period = null, haul = 1
   where port_id = v_lis and good_id = v_g;
  perform cmd.assume_identity(p_uid);
  insert into public.house_level_marks (player_id, track, level) values (v_pl, 'trading', 20) on conflict (player_id, track) do update set level = 20;
  if p_lit then
    update public.world_config set value = 'true'::jsonb where key in ('management_level_enabled', 'trade_benefits_enabled');
  end if;
  v_out := jsonb_build_object(
    'wage1', public.fleet_wage(v_fl, false), 'rate', world.tax_rate(v_lis, v_pl), 'city_rate', world.tax_rate(v_lis),
    'p1', public.bargain_p1(v_pl, v_lis, v_g, null), 'yard', public.level_perk(v_pl, 'yard_fee'), 'routes', public.standing_route_max_for(v_pl),
    'caps', public.earned_caps(v_pl), 'trading', public.level_benefits('trading', 10), 'card', public.level_skills_card(v_pl, '{}'::jsonb),
    'tax1000', public.profit_tax(v_lis, 1000, v_pl), 'sale', pg_temp.sale_0515(v_pl, v_fl, v_lis, v_g, v_gc));
  -- a waiting job's time, through the one note (the knob's own figure, whatever it is)
  update public.world_config set value = to_jsonb(900) where key = 'fleet_jobs_wait_s';
  insert into public.fleet_jobs (fleet_id, player_id, kind, params, since, seen_at) values (v_fl, v_pl, 'best', '{}', now(), now());
  perform public.fleet_job_note(v_fl, '{"wait": "low", "sentence": "prices low"}');
  v_out := v_out || jsonb_build_object('low', (select extract(epoch from j.next_at - now()) from public.fleet_jobs j where j.fleet_id = v_fl));
  perform public.fleet_job_note(v_fl, '{"wait": "purse", "sentence": "purse low"}');
  v_out := v_out || jsonb_build_object('purse', (select extract(epoch from j.next_at - now()) from public.fleet_jobs j where j.fleet_id = v_fl));
  if not p_lit then
    return v_out;
  end if;

  -- MANAGEMENT AT LEVELS 1, 4, 20
  foreach v_lv in array array[1, 4, 20] loop
    insert into public.level_xp (player_id, skill, xp) values (v_pl, 'management', public.level_begins('management', v_lv)::int)
    on conflict (player_id, skill) do update set xp = excluded.xp;
    perform public.fleet_job_note(v_fl, '{"wait": "low"}');
    v_out := v_out || jsonb_build_object('m' || v_lv, jsonb_build_object('wage', public.fleet_wage(v_fl, false),
      'wait', (select extract(epoch from j.next_at - now()) from public.fleet_jobs j where j.fleet_id = v_fl)));
  end loop;
  update public.world_config set value = to_jsonb(60) where key = 'fleet_jobs_wait_s';
  v_out := v_out || jsonb_build_object('floor', public.job_wait_s(v_fl));
  -- TRADING AT 3 AND 4, A SMALL RATE (never under half), NO TAX, NO MARK (a merchant has none)
  update public.house_level_marks set level = 3 where player_id = v_pl and track = 'trading';
  v_out := v_out || jsonb_build_object('t3', world.tax_rate(v_lis, v_pl));
  update public.house_level_marks set level = 4 where player_id = v_pl and track = 'trading';
  v_out := v_out || jsonb_build_object('t4', world.tax_rate(v_lis, v_pl));
  update public.house_level_marks set level = 20 where player_id = v_pl and track = 'trading';
  update public.world_config set value = to_jsonb(0.8) where key = 'profit_tax_scale';
  v_out := v_out || jsonb_build_object('small', world.tax_rate(v_lis, v_pl));
  update public.world_config set value = to_jsonb(0) where key = 'profit_tax_scale';
  v_out := v_out || jsonb_build_object('none', world.tax_rate(v_lis, v_pl));
  update public.world_config set value = to_jsonb(2) where key = 'profit_tax_scale';
  delete from public.house_level_marks where player_id = v_pl;
  v_out := v_out || jsonb_build_object('no_mark', world.tax_rate(v_lis, v_pl));
  -- dark again with the experience kept: the wage is the plain one
  update public.world_config set value = 'false'::jsonb where key in ('management_level_enabled', 'trade_benefits_enabled');
  v_out := v_out || jsonb_build_object('redark', public.fleet_wage(v_fl, false));
  update public.world_config set value = 'true'::jsonb where key = 'management_level_enabled';
  -- THE GRANT: one job's sail, once a voyage; a short hop and a stopped job give nothing; the day's cap
  delete from public.level_xp where player_id = v_pl and skill = 'management';
  insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
  select (u.v)::uuid, v_fl, v_pl, '[]'::jsonb, u.nm, '[]'::jsonb, now() - interval '1 hour', now(), 'ARRIVED', v_lis, v_lis
    from (values ('00000000-0515-4000-8000-0000000000b1', 30), ('00000000-0515-4000-8000-0000000000b2', 19), ('00000000-0515-4000-8000-0000000000b3', 30)) u(v, nm);
  v_out := v_out || jsonb_build_object('g', jsonb_build_array(
    public.job_sail_xp(v_pl, '00000000-0515-4000-8000-0000000000b1'), public.job_sail_xp(v_pl, '00000000-0515-4000-8000-0000000000b1'),
    public.job_sail_xp(v_pl, '00000000-0515-4000-8000-0000000000b2')));
  update public.fleet_jobs set paused_reason = 'E_X' where fleet_id = v_fl;
  v_out := v_out || jsonb_build_object('stopped', public.level_arrival(v_pl, '00000000-0515-4000-8000-0000000000b3'));
  update public.fleet_jobs set paused_reason = null where fleet_id = v_fl;
  v_out := v_out || jsonb_build_object('arrive', public.level_arrival(v_pl, '00000000-0515-4000-8000-0000000000b3'));
  for v_lv in 1 .. 65 loop
    perform public.level_grant(v_pl, 'job_sail', 1, 'probe:' || v_lv);
  end loop;
  return v_out || jsonb_build_object('xp', (select lx.xp from public.level_xp lx where lx.player_id = v_pl and lx.skill = 'management'));
end
$body$
  $f$;

  begin
    raise exception using errcode = 'ZX515', message = pg_temp.scene_0515(c_ua, false)::text;
  exception when sqlstate 'ZX515' then v_b := sqlerrm::jsonb;
  end;

  -- ── 3. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('management_level_enabled', 'false'::jsonb,
     '0515: THE SWITCH (the owner''s). true: the Management level is shown, earned by the sails of standing jobs, and its steps count (lower crew wages, a shorter wait of a waiting job). It locks nothing.'),
    ('trade_benefits_enabled', 'false'::jsonb,
     '0515: THE SWITCH (the owner''s). true: Trading''s new steps count: a city asks her less tax on a profit (trade_profit points, never under trade_tax_keep of it) and her first bargain is likelier (trade_bargain). Under level_unlocks_enabled.'),
    ('trade_tax_keep', to_jsonb(0.5), '0515: lit, the least share of its tax rate a city keeps from a company, whatever her Trading level.');

  -- ── 4. THE ROWS ──
  alter table public.level_perks add column lit_by text;
  comment on column public.level_perks.lit_by is
    '0515: the world_config switch this step waits for (null: none). public.level_perk and public.level_benefits read it; every step of one perk names the same.';
  insert into public.level_skills (code, ord, word, kept, day_cap, side, curve, gift_every, lit_by)
  values ('management', (select max(s.ord) + 1 from public.level_skills s), 'Management', 'book', 300, 'sea', 'short', 1, 'management_level_enabled');
  insert into public.level_activities (code, skill, ord, word, unit, xp, per, once, voyage_nm) values
    ('job_sail', 'management', 1, 'A sail made by a fleet''s job', 'each', 5, 1, true, 20);
  insert into public.level_perks (perk, level, skill, unit, amount, word, lit_by)
  select p.perk, l, p.skill, p.unit, p.amount, p.word, p.lit
    from (values ('fleet_wage', array[4, 8, 12, 16, 20], 'management', 'pct_less', 2, 'Every fleet''s crew wages are less', 'management_level_enabled'),
                 ('job_wait', array[3, 7, 11, 15, 19], 'management', 'pct_less', 6, 'A waiting job asks again sooner', 'management_level_enabled'),
                 ('trade_profit', array[4, 8, 12, 16, 20], 'trading', 'pct_more', 1, 'You keep more of each profit: the city taxes it less', 'trade_benefits_enabled'),
                 ('trade_bargain', array[2, 6, 10, 14, 18], 'trading', 'pct_more', 1, 'A better chance on the first bargain', 'trade_benefits_enabled'))
         p(perk, levels, skill, unit, amount, word, lit)
   cross join lateral unnest(p.levels) l;

  -- ── 5. THE RULES ──
  execute $f$
create function public.management_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0515: THE SWITCH, read once: world_config management_level_enabled.
  select public.wc('management_level_enabled') = 'true'::jsonb
$body$
  $f$;
  execute $f$
create function public.trade_tax_cut(p_player uuid, p_rate numeric)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0515: WHAT A CITY'S RATE IS FOR HER TRADING LEVEL (public.tax_home_half hands every answer of world.tax_rate through here): `trade_profit`
-- points less, never under trade_tax_keep of it. So she keeps that many points more of each profit, and the city's tax is exactly that
-- much less: a cut of her cost, no coin made. Dark, nobody, a merchant or a company with no Trading mark: the rate, untouched (one key).
declare
  v_pts numeric;
begin
  if p_player is null or p_rate is null or p_rate <= 0 or public.wc('trade_benefits_enabled') is distinct from 'true'::jsonb
     or not exists (select 1 from public.house_level_marks m where m.player_id = p_player and m.track = 'trading') then
    return p_rate;
  end if;
  v_pts := public.level_perk(p_player, 'trade_profit');
  if v_pts = 0 then
    return p_rate;
  end if;
  return greatest(p_rate - v_pts / 100.0, p_rate * least(1, greatest(0, public.wc_num('trade_tax_keep'))));
end
$body$
  $f$;
  execute $f$
create function public.job_wait_s(p_fleet uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0515: HOW LONG A WAITING JOB WAITS before it is asked again (public.fleet_job_note's waits of 0498 and 0502): fleet_jobs_wait_s, less her
  -- company's Management (perk job_wait, per cent), never under 600 s.
  select greatest(600, coalesce(public.wc_num('fleet_jobs_wait_s'), 900)
                       * (1 - case when public.management_on()
                                   then least(90, public.level_perk((select f.player_id from public.fleets f where f.id = p_fleet), 'job_wait')) else 0 end / 100.0))
$body$
  $f$;
  execute $f$
create function public.job_sail_xp(p_player uuid, p_voyage uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0515: A SAIL MADE BY A FLEET'S JOB is experience in Management (public.level_arrival calls this for a voyage that has ended): a port
-- made, at least the activity's miles, her fleet's standing job not stopped. Once a voyage (key job:<voyage>). Dark: nothing.
begin
  if not public.management_on() then
    return 0;
  end if;
  if not exists (select 1 from public.voyages v join public.fleet_jobs j on j.fleet_id = v.fleet_id and j.player_id = v.player_id and j.paused_reason is null
                  where v.id = p_voyage and v.player_id = p_player and v.dest_port_id is not null
                    and v.total_nm >= coalesce((select t.voyage_nm from public.level_activity_terms() t where t.code = 'job_sail'), 0)) then
    return 0;
  end if;
  return public.level_grant(p_player, 'job_sail', 1, 'job:' || p_voyage);
end
$body$
  $f$;
  foreach v_def in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_def::regprocedure);
  end loop;

  -- ── 6. THE HUNKS ──
  create temp table hunks_0515 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0515 values
  ('public.level_perk(uuid,text)', 1,
$h$  v_xp    int;
begin
$h$,
$h$  v_xp    int;
  v_lit   text;   -- 0515: the switch the step waits for (public.level_perks.lit_by)
begin
$h$),
  ('public.level_perk(uuid,text)', 2,
$h$  select k.skill into v_skill from public.level_perks k where k.perk = p_perk limit 1;
$h$,
$h$  select k.skill, k.lit_by into v_skill, v_lit from public.level_perks k where k.perk = p_perk limit 1;
  if v_lit is not null and public.wc(v_lit) is distinct from 'true'::jsonb then   -- 0515: a step whose switch is dark is worth nothing
    return 0;
  end if;
$h$),
  ('public.level_benefits(text,integer)', 1,
$h$              or not exists (select 1 from public.level_skills s where s.code = p_skill and s.kept = 'record'))
$h$,
$h$              or not exists (select 1 from public.level_skills s where s.code = p_skill and s.kept = 'record'))
         and (k.lit_by is null or public.wc(k.lit_by) = 'true'::jsonb)   -- 0515: a step whose switch is dark is not listed
$h$),
  ('public.level_arrival(uuid,uuid)', 1,
$h$  return v_n;
$h$,
$h$  v_n := v_n + public.job_sail_xp(p_player, p_voyage);   -- 0515 (dark: management_level_enabled): a sail made by a fleet's job
  return v_n;
$h$),
  ('public.fleet_wage(uuid,boolean,integer)', 1,
$h$    v_pct := world.skill_pct(v_player, null, 'crew_wage');
  end if;
$h$,
$h$    v_pct := world.skill_pct(v_player, null, 'crew_wage');
  end if;
  if public.management_on() then   -- 0515: and less her Management level's share, for every fleet she has
    v_pct := v_pct + public.level_perk(v_player, 'fleet_wage');
  end if;
$h$),
  ('public.bargain_p1(uuid,uuid,uuid,uuid)', 1,
$h$           + public.level_perk(p_player, 'bargain_chance') / 100.0
$h$,
$h$           + public.level_perk(p_player, 'bargain_chance') / 100.0
           + public.level_perk(p_player, 'trade_bargain') / 100.0   -- 0515 (dark: trade_benefits_enabled): her Trading level's points
$h$),
  ('public.tax_home_half(uuid,uuid,numeric,numeric)', 1,
$h$  if p_player is null or not public.tax_thirty_on() then
    return p_rate;
$h$,
$h$  -- 0515 (dark: trade_benefits_enabled): each answer less her Trading level's points (public.trade_tax_cut)
  if p_player is null or not public.tax_thirty_on() then
    return public.trade_tax_cut(p_player, p_rate);
$h$),
  ('public.tax_home_half(uuid,uuid,numeric,numeric)', 2,
$h$  if not public.hq_at(p_player, p_port) then   -- 0512: home, or lit any HQ of hers
    return p_rate;
$h$,
$h$  if not public.hq_at(p_player, p_port) then   -- 0512: home, or lit any HQ of hers
    return public.trade_tax_cut(p_player, p_rate);
$h$),
  ('public.tax_home_half(uuid,uuid,numeric,numeric)', 3,
$h$  return least(p_rate, p_city * (1 - public.wc_num('home_tax_cut')));
$h$,
$h$  return public.trade_tax_cut(p_player, least(p_rate, p_city * (1 - public.wc_num('home_tax_cut'))));
$h$),
  ('public.fleet_job_note(uuid,jsonb)', 1,
$h$       set next_at = now() + make_interval(secs => greatest(600, coalesce(public.wc_num('fleet_jobs_wait_s'), 900))),
           last = jsonb_build_object('at', now(), 'wait', p_plan->>'wait', 'sentence', p_plan->>'sentence', 'purse', p_plan->'purse', 'need', p_plan->'need',
$h$,
$h$       set next_at = now() + make_interval(secs => public.job_wait_s(p_fleet)),   -- 0515: the one wait
           last = jsonb_build_object('at', now(), 'wait', p_plan->>'wait', 'sentence', p_plan->>'sentence', 'purse', p_plan->'purse', 'need', p_plan->'need',
$h$),
  ('public.fleet_job_note(uuid,jsonb)', 2,
$h$       set next_at = now() + make_interval(secs => greatest(600, coalesce(public.wc_num('fleet_jobs_wait_s'), 900))),
           last = jsonb_build_object('at', now(), 'wait', 'low',
$h$,
$h$       set next_at = now() + make_interval(secs => public.job_wait_s(p_fleet)),   -- 0515: the one wait
           last = jsonb_build_object('at', now(), 'wait', 'low',
$h$);
  update hunks_0515 set old = rtrim(old, E'\n'), new = rtrim(new, E'\n') where fn = 'public.fleet_job_note(uuid,jsonb)';

  for x in select distinct h.fn from hunks_0515 h loop
    v_pre := (select p.def from pre_0515 p where p.fn = x.fn);
    v_def := v_pre;
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0515 h where h.fn = x.fn order by h.ord loop
      if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
        raise exception '0515 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', v_n, x.fn,
          (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
      end if;
      v_def := replace(v_def, v_old, v_new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '');
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0515 h where h.fn = x.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 then
        raise exception '0515 self-assert FAIL: hunk % of % is not in the new body once', v_n, x.fn;
      end if;
      v_def := replace(v_def, v_new, v_old);
    end loop;
    if v_def <> v_pre then
      raise exception '0515 self-assert FAIL: % does not reverse to its pre-image', x.fn;
    end if;
  end loop;

  -- ── 7. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0515 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0515 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before or public.management_on() or public.wc('trade_benefits_enabled') <> 'false'::jsonb then
    raise exception '0515 self-assert FAIL: a knob of another file moved, or a switch is not false';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('anon', u.q::regprocedure, 'execute') or has_function_privilege('authenticated', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute') or has_function_privilege('public', u.q::regprocedure, 'execute'))
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0515 self-assert FAIL: a new function is reachable by a client or service_role';
  end if;
  -- IT LOCKS NOTHING: the job doors, the plan, the tick and the order door ask neither the level nor its switch
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and (position('management_on()' in p.prosrc) > 0 or position('''management''' in p.prosrc) > 0)
                and p.oid <> all (array['public.fleet_wage(uuid,boolean,integer)'::regprocedure::oid, 'public.job_wait_s(uuid)'::regprocedure::oid, 'public.job_sail_xp(uuid,uuid)'::regprocedure::oid])) then
    raise exception '0515 self-assert FAIL: a function other than the wage, the wait and the grant asks the Management level';
  end if;
  if exists (select 1 from public.level_perks k group by k.perk having count(distinct k.skill) <> 1 or count(distinct coalesce(k.lit_by, '')) <> 1) then
    raise exception '0515 self-assert FAIL: a perk belongs to two levels, or to two switches';
  end if;

  -- ── 8. DARK IDENTITY, then LIT ──
  begin
    raise exception using errcode = 'ZX515', message = pg_temp.scene_0515(c_ua, false)::text;
  exception when sqlstate 'ZX515' then v_d := sqlerrm::jsonb;
  end;
  if v_d is distinct from v_b then
    raise exception '0515 self-assert FAIL: DARK IS NOT IDENTICAL: %',
      (select string_agg(e.key || ': ' || left(e.value::text, 300) || ' -> ' || left((v_d->e.key)::text, 300), ' | ') from jsonb_each(v_b) e where v_d->e.key is distinct from e.value);
  end if;
  begin
    raise exception using errcode = 'ZX515', message = pg_temp.scene_0515(c_ua, true)::text;
  exception when sqlstate 'ZX515' then v_l := sqlerrm::jsonb;
  end;
  drop function pg_temp.scene_0515(uuid, boolean);
  drop function pg_temp.sale_0515(uuid, uuid, uuid, uuid, text);

  -- the rate: 10 % is 5 % at Trading 20 (five points, not under its half), 10 % at 3, 9 % at 4; 4 % is 2 % (the half); none stays none; no mark: the city's
  if (v_b->>'rate')::numeric <> 0.10 or (v_l->>'city_rate')::numeric <> 0.10 or (v_l->>'rate')::numeric <> 0.05 or (v_l->>'t3')::numeric <> 0.10 or (v_l->>'t4')::numeric <> 0.09
     or (v_l->>'small')::numeric <> 0.02 or (v_l->>'none')::numeric <> 0 or (v_l->>'no_mark')::numeric <> 0.10 or (v_b->>'tax1000')::int <> 100 or (v_l->>'tax1000')::int <> 50 then
    raise exception '0515 self-assert FAIL: the rate by Trading level: %', v_l - 'card' - 'trading';
  end if;
  -- THE SALE THROUGH THE DOOR, AND THE WORLD'S SUM: the same total; the tax half; her gain is the city's loss, dark and lit, to the coin
  if v_l #> '{sale,total}' is distinct from v_b #> '{sale,total}' or (v_b #>> '{sale,tax}')::numeric <= 0
     or (v_l #>> '{sale,tax}')::numeric <> round((v_l #>> '{sale,profit}')::numeric * 0.05) or (v_b #>> '{sale,tax}')::numeric <> round((v_b #>> '{sale,profit}')::numeric * 0.10)
     or (v_l #>> '{sale,her}')::numeric - (v_b #>> '{sale,her}')::numeric <> (v_b #>> '{sale,tax}')::numeric - (v_l #>> '{sale,tax}')::numeric
     or (v_b #>> '{sale,her}')::numeric + (v_b #>> '{sale,city}')::numeric <> 0 or (v_l #>> '{sale,her}')::numeric + (v_l #>> '{sale,city}')::numeric <> 0 then
    raise exception '0515 self-assert FAIL: the sale: dark % lit % (her coin and the city''s must sum to nought)', v_b->'sale', v_l->'sale';
  end if;
  -- the bargain's five points; nothing of 0417, 0453 or 0468 moved
  if round((v_l->>'p1')::numeric - (v_b->>'p1')::numeric, 6) <> least(0.05, public.wc_num('bargain_p1_max') - (v_b->>'p1')::numeric)
     or v_l->'yard' is distinct from v_b->'yard' or v_l->'routes' is distinct from v_b->'routes' or v_l->'caps' is distinct from v_b->'caps'
     or jsonb_array_length(v_l->'trading') - jsonb_array_length(v_b->'trading') <> 10 or not (v_l->'trading') @> (v_b->'trading') then
    raise exception '0515 self-assert FAIL: the bargain, or what Trading gives today: p1 % -> %, % / %', v_b->'p1', v_l->'p1', v_b->'routes', v_l->'routes';
  end if;
  -- MANAGEMENT: level 1 nothing; level 4 a 2 % and one 6 % of the wait; level 20 10 % and 30 %; never under 600 s
  if v_l #> '{m1,wage}' is distinct from v_b->'wage1' or (v_l #>> '{m1,wait}')::numeric <> 900 or (v_b->>'low')::numeric <> 900 or (v_b->>'purse')::numeric <> 900
     or (v_l #>> '{m4,wage}')::numeric <> round((v_b->>'wage1')::numeric * 0.98, 4) or (v_l #>> '{m4,wait}')::numeric <> 846
     or (v_l #>> '{m20,wage}')::numeric <> round((v_b->>'wage1')::numeric * 0.90, 4) or (v_l #>> '{m20,wait}')::numeric <> 630
     or (v_l->>'floor')::numeric <> 600 or v_l->'redark' is distinct from v_b->'wage1' or (v_b->>'wage1')::numeric <= 0 then
    raise exception '0515 self-assert FAIL: Management''s steps: plain wage %, %', v_b->'wage1', v_l - 'card' - 'trading' - 'sale';
  end if;
  -- the grant: 5 once; a short hop, the same voyage again, a stopped job: none; the arrival itself 5; the day's cap 300
  if v_l->'g' is distinct from '[5, 0, 0]'::jsonb or (v_l->>'arrive')::int <> 5 or (v_l->>'stopped')::int <> 0 or (v_l->>'xp')::int <> 300 then
    raise exception '0515 self-assert FAIL: the grant: % arrival % stopped % xp %', v_l->'g', v_l->'arrive', v_l->'stopped', v_l->'xp';
  end if;
  if position('"management"' in (v_d->'card')::text) > 0 or position('"management"' in (v_l->'card')::text) = 0 then
    raise exception '0515 self-assert FAIL: the level is shown dark, or not shown lit';
  end if;

  -- ── 9. NOTHING OF THE PROBE SURVIVES ──
  if exists (select 1 from public.players p where p.company_name = 'Casa da Prova 0515') or public.management_on()
     or (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
           from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before then
    raise exception '0515 self-assert FAIL: the probe left rows behind, or a knob moved';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0515 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0515 self-assert ok: MANAGEMENT, AND TRADING''S BENEFITS (dark). Eleven hunks once and reversing in seven bodies; no other function moved; four new functions server only. Probe (rolled back): a 10 %% tax is 5 %% at Trading 20; a sale of % paid the city % of tax instead of %, her coin and the city''s summing to nought both ways; a wage % is % at Management 20, a wait 900 s is 630 s; a job''s sail 5, 300 a day. % ms.',
    v_b #> '{sale,total}', v_l #> '{sale,tax}', v_b #> '{sale,tax}', v_b->'wage1', v_l #> '{m20,wage}', round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0515;
  drop table pre_0515;
end $m$;
