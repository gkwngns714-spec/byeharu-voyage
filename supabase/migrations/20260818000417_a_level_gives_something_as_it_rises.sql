-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0417 - A LEVEL GIVES SOMETHING AS IT RISES  (docs/LEVELS.md section 7; the second cut of the levels raised by doing)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
-- THE OWNER, 2026-11-14: "with exp table, exp info, with benefits when leveling up, what activity needs done etc."
-- 0411 gave the seven new levels one thing, Reputation. This file gives each of them a benefit of its own, at five of its twenty
-- levels, each small, each a rule the game already applies, each applied by the server and served to the page from the same rows.
--
-- WHAT THIS FILE MAKES
--   THE STEPS     public.level_perks (data): perk, level, amount. A company's benefit is the SUM of the amounts of the steps at or
--                 below her level. Thirty-five rows, seven levels, eight benefits:
--                   supplies      supplies_price      supplies cost 1 % less at each of levels 4, 8, 12, 16, 20       (5 % in all)
--                   weather       storm_wear          gear wears 5 % less on a storm day at each of the same levels  (25 % in all)
--                   shipbuilding  repair_price        ship repairs cost 2 % less at each                              (10 % in all)
--                   requests      request_reputation  a request fulfilled gives 10 % more Reputation at each          (50 % in all)
--                   craft         gear_wear           gear wears 3 % less from miles and fights at each               (15 % in all)
--                   routes        lap_reputation      a profitable lap gives 20 % more Reputation at 4, 12, 20        (60 % in all)
--                   routes        route_room          one more route at each of levels 8 and 16                       (2 in all)
--                   investment    share_regard        a stake in a city earns 10 % more regard at each                (50 % in all)
--   THE READER    public.level_perk(player, perk): THE ONE READING of what a benefit is worth to a company now. A merchant has no row
--                 in public.level_xp, so she leaves after two index probes with 0; a company at level 1 the same. level_perks_on false: 0.
--   THE CUTS      ten hunks over eight live bodies (pg_get_functiondef, LF), each once and reversing. Each multiplies ONE figure in the
--                 ONE function that already owns it, so what a screen quotes and what a door charges stay the same number:
--                   public.stores_cost            the one price of supplies (0142)                      x (1 - supplies_price %)
--                   public.fleet_repair_cost      the one price of a hull's repair (0279); gear is not cut  x (1 - repair_price %)
--                   public.wear_units_for         the one writer of wear (0158; a player's fleet only)   storm days x (1 - storm_wear %),
--                                                                                                       miles and fights x (1 - gear_wear %)
--                   public.reputation_request     a request's Reputation (0352)                         x (1 + request_reputation %)
--                   public.reputation_lap         a lap's Reputation (0356)                             x (1 + lap_reputation %)
--                   public.standing_route_max_for the one reading of how many routes she may keep (0154) + route_room
--                   public.invest_for             the regard a stake earns (0319, public.regard_gift)   x (1 + share_regard %)
--                   public.level_benefits         the page's list (0411) gains the steps, with the running total at each
--   THE KNOB      level_perks_on true. False: every benefit reads 0 at once and the page stops listing them (the rollback with no file).
--
-- THE OLD VALUES, so each can be put back: every figure these multiply is unchanged (provision_water_price, provision_food_price,
--   repair_rate_per_point, gear_wear_per_storm, gear_wear_per_1000nm, gear_wear_per_fight, rep_request_per_point / min / max, rep_lap,
--   standing_route_max, regard_per_100k). The benefit is the step rows alone: an amount set to another figure, or the knob to false.
-- WHAT IT DOES NOT TOUCH: no Academy skill's effect. The skills hold supplies' endurance, storm damage to the hull, the yard's labour,
--   the count of routes by Factorage, the tax: none of those figures is multiplied here, except the count of routes, where the level's
--   one or two routes ADD to Factorage's in the one function both are read in (public.standing_route_max_for).
-- NO PAY-TO-WIN, NO PvP: nothing here is bought; nothing takes from another company (the dividend was judged and left alone for that:
--   a city pays its shareholders pro rata, so a better share for one would be a worse one for another).
-- A MERCHANT GETS NONE: she has no experience row. Trading, Exploration and Combat are listed as they were: nothing new for them here.
-- NOT IN THIS FILE: Gunnery, Boarding, Raiding. 0409 (the pirates' homes) and 0412 (their trade) are not deployed, and both re-cut the
--   pirates' bodies beside the fight's end. They follow those.
-- COST: public.stores_cost and public.fleet_repair_cost are read for merchants (the planner; a repair): one more call of two index probes.
--   The self-assert measures OLD against NEW public.stores_cost for a merchant and prints it. The other six are players' doors or run
--   after a merchant has left. Nothing in a sale, a buy or a day at sea.
-- LOCKS: CREATE TABLE x1 (no foreign key to players); CREATE OR REPLACE x8 by hunks. BUDGET: statement_timeout 30 s, lock_timeout 5 s;
--   fails above 15 s.
-- ROLLBACK (forward, owner only): scripts/ops/harness/levels/rollback-0417.sql, a draft. At once, with no file: level_perks_on false.
-- SELF-ASSERT: the catalog; with no experience every cut body answers as its pre-image for a company and a merchant; then a probe
--   company at level 20 in each: every benefit to its figure. All of it rolled back. No table is counted or summed.
-- NEWS: this file posts its own UPDATE row once, outside the rolled-back probe (0347's law).
-- VERSION: 0417 (0411 is the levels; 0412 is the pirates' trade, another builder's).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_cut constant text[] := array[
    'public.stores_cost(uuid,numeric,numeric)', 'public.fleet_repair_cost(uuid,numeric,jsonb)', 'public.wear_units_for(uuid,uuid)',
    'public.reputation_request(uuid,bigint,uuid,jsonb)', 'public.reputation_lap(uuid,uuid,bigint,text,integer)',
    'public.standing_route_max_for(uuid)', 'public.invest_for(uuid,uuid,text,integer)', 'public.level_benefits(text,integer)'];
  c_new constant text[] := array['public.level_perk(uuid,text)'];
  c_uid constant uuid := '00000000-0417-4000-8000-000000000001';
  v_t0        timestamptz := clock_timestamp();
  v_t         timestamptz;
  t1          timestamptz;
  h           record;
  d           record;
  v_def       text;
  v_n         int;
  v_fn_before text;
  v_cfg_before text;
  v_lived     boolean := false;
  v_pl        uuid;
  v_npc       uuid;
  v_fl        uuid;
  v_nfl       uuid;
  v_sh        uuid;
  v_lis       uuid;
  v_voy       uuid;
  v_top       int;
  v_xp        int;
  v_a         numeric;
  v_b         numeric;
  v_c         numeric;
  v_storm     text;
  v_miles     text;
  v_r         jsonb;
  v_old_us    numeric := 0;
  v_new_us    numeric := 0;
  v_pairs     int := 0;
  v_note      text := '';
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regclass('public.level_perks') is not null or to_regprocedure('public.level_perk(uuid,text)') is not null
     or exists (select 1 from public.world_config c where c.key = 'level_perks_on') then
    raise exception '0417 refuses: it has been applied once';
  end if;
  if to_regclass('public.level_xp') is null or to_regclass('public.level_skills') is null
     or exists (select 1 from unnest(c_cut) f where to_regprocedure(f) is null)
     or to_regprocedure('public.level_from_points(numeric)') is null or to_regprocedure('public.level_points(integer)') is null
     or to_regprocedure('public.news_update(text,text,text)') is null or to_regprocedure('public.client_write_grants()') is null
     or (select count(*) from public.level_skills s where s.kept = 'book'
           and s.code in ('supplies', 'weather', 'shipbuilding', 'requests', 'craft', 'routes', 'investment')) <> 7 then
    raise exception '0417 refuses: the levels raised by doing (0411) or a function it cuts is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0417 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0417
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_cut) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid);
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE STEPS, THE KNOB, THE READER ──
  create table public.level_perks (
    perk   text not null check (perk ~ '^[a-z_]+$'),
    level  int  not null check (level between 2 and 20),
    skill  text not null references public.level_skills(code),
    unit   text not null check (unit in ('pct_less', 'pct_more', 'count')),
    amount numeric not null check (amount > 0),
    word   text not null,
    primary key (perk, level)
  );
  comment on table public.level_perks is
    '0417: what a level gives as it rises. One row a step: at `level` of `skill` the benefit `perk` grows by `amount` (unit pct_less / pct_more: per cent of the figure it acts on; count: a whole number). A company''s benefit is the sum of the steps at or below her level: public.level_perk, the one reading. word is the server''s English sentence. A perk belongs to one level (asserted).';
  alter table public.level_perks enable row level security;
  revoke all on table public.level_perks from public, anon, authenticated;
  insert into public.level_perks (perk, level, skill, unit, amount, word)
  select x.perk, l.level, x.skill, x.unit, x.amount, x.word
    from (values
      ('supplies_price',     'supplies',     'pct_less', 1,  array[4, 8, 12, 16, 20], 'Supplies cost less'),
      ('storm_wear',         'weather',      'pct_less', 5,  array[4, 8, 12, 16, 20], 'Gear wears less on a storm day'),
      ('repair_price',       'shipbuilding', 'pct_less', 2,  array[4, 8, 12, 16, 20], 'Ship repairs cost less'),
      ('request_reputation', 'requests',     'pct_more', 10, array[4, 8, 12, 16, 20], 'A request fulfilled gives more Reputation'),
      ('gear_wear',          'craft',        'pct_less', 3,  array[4, 8, 12, 16, 20], 'Gear wears less from miles and fights'),
      ('lap_reputation',     'routes',       'pct_more', 20, array[4, 12, 20],        'A profitable route lap gives more Reputation'),
      ('route_room',         'routes',       'count',    1,  array[8, 16],            'One more route'),
      ('share_regard',       'investment',   'pct_more', 10, array[4, 8, 12, 16, 20], 'Investing wins more favour with the country')
    ) x(perk, skill, unit, amount, levels, word)
    cross join lateral unnest(x.levels) l(level);

  insert into public.world_config (key, value, description) values
    ('level_perks_on', 'true'::jsonb,
     '0417: the benefits a level gives as it rises (public.level_perks) are applied and listed on the Levels page. false = public.level_perk answers 0 for everyone and the page lists none: supplies, repairs, wear, Reputation, regard and the count of routes are what they were before 0417. Experience and levels are not touched.');

  execute $f$
create function public.level_perk(p_player uuid, p_perk text)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0417: THE ONE READING of what a level's benefit is worth to a company now: the sum of the steps of p_perk (public.level_perks) at or
-- below her level in the level it belongs to. Nobody, a merchant (she has no row in public.level_xp) and a company with no experience
-- there: 0 after two index probes. level_perks_on false: 0. An unknown perk: 0.
declare
  v_skill text;
  v_xp    int;
begin
  if p_player is null then
    return 0;
  end if;
  select k.skill into v_skill from public.level_perks k where k.perk = p_perk limit 1;
  select x.xp into v_xp from public.level_xp x where x.player_id = p_player and x.skill = v_skill;
  if v_xp is null or v_xp <= 0 then
    return 0;
  end if;
  if public.wc('level_perks_on') is distinct from 'true'::jsonb then
    return 0;
  end if;
  return coalesce((select sum(k.amount) from public.level_perks k
                    where k.perk = p_perk and k.level <= public.level_from_points(v_xp)), 0);
end
$body$
  $f$;
  revoke all on function public.level_perk(uuid, text) from public, anon, authenticated;

  -- ── 3. THE HUNKS (each OLD text once in its live body) ──
  create temp table hunk_0417 (ord int primary key, fn text, old text, new text) on commit drop;
  insert into hunk_0417 values
  (1, c_cut[1],
$h$               * public.running_cost_mult(p_player)
               * public.wc_num('running_cost_level'))::bigint;   -- 0210: running costs keep pace with the goods
$h$,
$h$               * public.running_cost_mult(p_player)
               * (1 - public.level_perk(p_player, 'supplies_price') / 100)   -- 0417: her Supplies level (a merchant: 0)
               * public.wc_num('running_cost_level'))::bigint;   -- 0210: running costs keep pace with the goods
$h$),
  (2, c_cut[2],
$h$               * public.running_cost_mult(f.player_id)
               * public.wc_num('running_cost_level'))::bigint
$h$,
$h$               * public.running_cost_mult(f.player_id)
               * (1 - public.level_perk(f.player_id, 'repair_price') / 100)   -- 0417: her Shipbuilding level, on the hull's price (a merchant: 0)
               * public.wc_num('running_cost_level'))::bigint
$h$),
  (3, c_cut[3],
$h$  v_n      int;
begin
$h$,
$h$  v_n      int;
  v_storm_x numeric := 1;   -- 0417: what her Weather level leaves of a storm day's wear
  v_gear_x  numeric := 1;   -- 0417: what her Craft level leaves of the wear of miles and fights
begin
$h$),
  (4, c_cut[3],
$h$    from public.voyage_events ve where ve.voyage_id = p_voyage;
$h$,
$h$    from public.voyage_events ve where ve.voyage_id = p_voyage;
  -- 0417: her company's levels, read once a passage (public.level_perk). This function runs for a player's fleet only.
  select 1 - public.level_perk(f.player_id, 'storm_wear') / 100, 1 - public.level_perk(f.player_id, 'gear_wear') / 100
    into v_storm_x, v_gear_x from public.fleets f where f.id = p_fleet;
$h$),
  (5, c_cut[3],
$h$                   when 'MILES'   then v_nm / 1000 * public.wc_num('gear_wear_per_1000nm')
                   when 'PIRATES' then v_fights * public.wc_num('gear_wear_per_fight')
                   when 'STORM'   then v_storms * public.wc_num('gear_wear_per_storm')
$h$,
$h$                   when 'MILES'   then v_nm / 1000 * public.wc_num('gear_wear_per_1000nm') * v_gear_x
                   when 'PIRATES' then v_fights * public.wc_num('gear_wear_per_fight') * v_gear_x
                   when 'STORM'   then v_storms * public.wc_num('gear_wear_per_storm') * v_storm_x
$h$),
  (6, c_cut[4],
$h$    least(greatest(floor(p_premium / v_per), public.wc_int('rep_request_min')), public.wc_int('rep_request_max'))::int,
$h$,
$h$    -- 0417: and her Requests level's share more (public.level_perk)
    floor(least(greatest(floor(p_premium / v_per), public.wc_int('rep_request_min')), public.wc_int('rep_request_max'))
          * (1 + public.level_perk(p_player, 'request_reputation') / 100))::int,
$h$),
  (7, c_cut[5],
$h$  return public.reputation_credit(p_player, 'lap', public.wc_int('rep_lap'), 'lap:' || p_lap,
$h$,
$h$  -- 0417: and her Routes level's share more (public.level_perk)
  return public.reputation_credit(p_player, 'lap', floor(public.wc_int('rep_lap') * (1 + public.level_perk(p_player, 'lap_reputation') / 100))::int, 'lap:' || p_lap,
$h$),
  (8, c_cut[6],
$h$  if p_player is null or not public.skills_bite_on() then
    return v_max;
  end if;
$h$,
$h$  if p_player is null then
    return v_max;
  end if;
  v_max := v_max + public.level_perk(p_player, 'route_room')::int;   -- 0417: and the routes her Routes level gives
  if not public.skills_bite_on() then
    return v_max;
  end if;
$h$),
  (9, c_cut[7],
$h$  perform public.regard_gift(p_player, p_port, v_cost, 'SHARE');   -- 0319: dark, nothing
$h$,
$h$  -- 0417: her Investment level makes the stake count for more regard (public.level_perk; a merchant: 0, and public.regard_add turns her away)
  perform public.regard_gift(p_player, p_port, round(v_cost * (1 + public.level_perk(p_player, 'share_regard') / 100))::bigint, 'SHARE');   -- 0319: dark, nothing
$h$),
  (10, c_cut[8],
$h$       where p_skill in ('trading', 'exploration') and t.level between 2 and public.wc_int('title_max')
    ) b
$h$,
$h$       where p_skill in ('trading', 'exploration') and t.level between 2 and public.wc_int('title_max')
      union all
      -- 0417: perk: a step of public.level_perks at this level: its amount, and `total`, what the benefit is worth from this level on
      select k.level, 5, jsonb_build_object('level', k.level, 'kind', 'perk', 'perk', k.perk, 'unit', k.unit, 'word', k.word, 'amount', k.amount,
               'total', (select sum(k2.amount) from public.level_perks k2 where k2.perk = k.perk and k2.level <= k.level))
        from public.level_perks k
       where k.skill = p_skill and public.wc('level_perks_on') = 'true'::jsonb
    ) b
$h$);
  for h in select * from hunk_0417 order by ord loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0417 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.old, h.new);
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
      raise exception '0417 self-assert FAIL: hunk % of % is not in the new body once', h.ord, h.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = h.fn::regprocedure) <> (select p.meta from pre_0417 p where p.fn = h.fn) then
      raise exception '0417 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', h.fn;
    end if;
  end loop;

  -- ── 4. THE SELF-ASSERT: the catalog ──
  for d in select p.fn, p.def from pre_0417 p loop
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select x.old, x.new from hunk_0417 x where x.fn = d.fn order by x.ord desc loop
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> d.def then
      raise exception '0417 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and not exists (select 1 from unnest(c_cut || c_new) f where f::regprocedure = p.oid)) <> v_fn_before then
    raise exception '0417 self-assert FAIL: a function this file does not name moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> 'level_perks_on') <> v_cfg_before
     or public.wc('level_perks_on') is distinct from 'true'::jsonb then
    raise exception '0417 self-assert FAIL: an existing world_config row moved, or this file''s knob is not true';
  end if;
  if has_function_privilege('anon', 'public.level_perk(uuid,text)', 'execute') or has_function_privilege('authenticated', 'public.level_perk(uuid,text)', 'execute')
     or has_table_privilege('anon', 'public.level_perks', 'select,insert,update,delete') or has_table_privilege('authenticated', 'public.level_perks', 'select,insert,update,delete')
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.level_perks'::regclass)
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0417 self-assert FAIL: a client can call the reader or reach the steps';
  end if;
  -- THE DATA: a perk belongs to one level and one unit; every level raised by doing has a step; no step for a level counted from the record
  if exists (select 1 from public.level_perks k group by k.perk having count(distinct k.skill) > 1 or count(distinct k.unit) > 1)
     or exists (select 1 from public.level_skills s where s.kept = 'book' and not exists (select 1 from public.level_perks k where k.skill = s.code))
     or exists (select 1 from public.level_perks k join public.level_skills s on s.code = k.skill where s.kept <> 'book')
     or exists (select 1 from public.level_perks k where k.level > public.level_from_points(1000000000000)) then
    raise exception '0417 self-assert FAIL: the steps'' data is not whole';
  end if;
  -- THE HOT PATHS: a sale, a buy and voyage.settle name nothing of this file
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where ((n.nspname = 'cmd' and (p.proname like 'do\_sell%' or p.proname = 'do_buy')) or (n.nspname = 'voyage' and p.proname = 'settle'))
                and p.prosrc like '%level\_perk%') then
    raise exception '0417 self-assert FAIL: a sale, a buy or voyage.settle names the level benefits';
  end if;

  -- ── 5. THE SELF-ASSERT: probe houses of this file's own rows, rolled back ──
  v_t := clock_timestamp();
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid, 'Casa dos Passos 0417', (select n.id from public.nations n where n.code = 'PRT'), 0, false) returning id into v_pl;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (null, 'Casa Mercante 0417', (select n.id from public.nations n where n.code = 'PRT'), 0, true) returning id into v_npc;
    update public.world_config set value = 'true'::jsonb where key in ('reputation_on', 'level_skills_on') and value is distinct from 'true'::jsonb;
    v_fl := public.form_fleet(v_pl, 'Passos', v_lis);
    v_nfl := public.form_fleet(v_npc, 'Mercante', v_lis);
    v_top := public.level_from_points(1000000000000);
    v_xp := public.level_points(v_top)::int;
    for d in select p.fn, p.def from pre_0417 p where p.fn in (c_cut[1], c_cut[2], c_cut[6]) loop
      execute replace(replace(replace(d.def, 'FUNCTION public.stores_cost(', 'FUNCTION pg_temp.stores_cost_old_0417('),
                              'FUNCTION public.fleet_repair_cost(', 'FUNCTION pg_temp.fleet_repair_cost_old_0417('),
                      'FUNCTION public.standing_route_max_for(', 'FUNCTION pg_temp.route_max_old_0417(');
    end loop;

    -- (a) WITH NO EXPERIENCE NOTHING MOVED: a new company and a merchant read every cut figure as the pre-image does
    if public.level_perk(v_pl, 'supplies_price') <> 0 or public.level_perk(v_npc, 'supplies_price') <> 0 or public.level_perk(null, 'supplies_price') <> 0
       or public.level_perk(v_pl, 'no_such_perk') <> 0
       or exists (select 1 from unnest(array[v_pl, v_npc]) p(id)
                   where public.stores_cost(p.id, 37.5, 12.25) <> pg_temp.stores_cost_old_0417(p.id, 37.5, 12.25)
                      or public.standing_route_max_for(p.id) <> pg_temp.route_max_old_0417(p.id))
       or public.fleet_repair_cost(v_fl, 1234.5, null) <> pg_temp.fleet_repair_cost_old_0417(v_fl, 1234.5, null)
       or public.fleet_repair_cost(v_nfl, 1234.5, null) <> pg_temp.fleet_repair_cost_old_0417(v_nfl, 1234.5, null) then
      raise exception '0417 self-assert FAIL: with no experience a cut figure is not its pre-image''s';
    end if;

    -- (b) A MERCHANT WITH A ROW SHE CANNOT HAVE still pays the pre-image's price only if she has none: she has none, by 0411's one writer.
    --     A COMPANY AT THE TOP LEVEL OF EVERY LEVEL: each benefit to its figure, from the steps' own rows.
    insert into public.level_xp (player_id, skill, xp, seq)
    select v_pl, s.code, v_xp, 0 from public.level_skills s where s.kept = 'book';
    select sum(k.amount) into v_a from public.level_perks k where k.perk = 'supplies_price';
    select sum(k.amount) into v_b from public.level_perks k where k.perk = 'repair_price';
    select sum(k.amount) into v_c from public.level_perks k where k.perk = 'route_room';
    if public.level_perk(v_pl, 'supplies_price') <> v_a or public.level_perk(v_pl, 'route_room') <> v_c
       or abs(public.stores_cost(v_pl, 4000, 1000) - pg_temp.stores_cost_old_0417(v_pl, 4000, 1000) * (1 - v_a / 100)) > 1
       or public.stores_cost(v_pl, 4000, 1000) >= pg_temp.stores_cost_old_0417(v_pl, 4000, 1000)
       or abs(public.fleet_repair_cost(v_fl, 10000, null) - pg_temp.fleet_repair_cost_old_0417(v_fl, 10000, null) * (1 - v_b / 100)) > 1
       or public.fleet_repair_cost(v_fl, 10000, null) >= pg_temp.fleet_repair_cost_old_0417(v_fl, 10000, null)
       or public.fleet_repair_cost(v_fl, 10000, jsonb_build_object('cost', 777)) - public.fleet_repair_cost(v_fl, 10000, null) <> 777
       or public.standing_route_max_for(v_pl) <> pg_temp.route_max_old_0417(v_pl) + v_c
       or public.stores_cost(v_npc, 4000, 1000) <> pg_temp.stores_cost_old_0417(v_npc, 4000, 1000) then
      raise exception '0417 self-assert FAIL: at the top level supplies (% of %), repairs (% of %) or routes (% of %) are not the steps'' sum',
        public.stores_cost(v_pl, 4000, 1000), pg_temp.stores_cost_old_0417(v_pl, 4000, 1000),
        public.fleet_repair_cost(v_fl, 10000, null), pg_temp.fleet_repair_cost_old_0417(v_fl, 10000, null),
        public.standing_route_max_for(v_pl), pg_temp.route_max_old_0417(v_pl);
    end if;
    -- one step below a step's level she has not got it: the benefit is by level, not by experience
    update public.level_xp set xp = public.level_points(4)::int - 1 where player_id = v_pl and skill = 'supplies';
    if public.level_perk(v_pl, 'supplies_price') <> 0 then
      raise exception '0417 self-assert FAIL: a company at level 3 has level 4''s step';
    end if;
    update public.level_xp set xp = public.level_points(4)::int where player_id = v_pl and skill = 'supplies';
    if public.level_perk(v_pl, 'supplies_price') <> (select k.amount from public.level_perks k where k.perk = 'supplies_price' and k.level = 4) then
      raise exception '0417 self-assert FAIL: a company at level 4 has not exactly level 4''s step';
    end if;

    -- (c) REPUTATION: a request and a lap give their share more, from the knobs and the steps
    select sum(k.amount) into v_a from public.level_perks k where k.perk = 'request_reputation';
    select sum(k.amount) into v_b from public.level_perks k where k.perk = 'lap_reputation';
    v_n := public.reputation_request(v_pl, (public.wc_num('rep_request_per_point') * 20)::bigint, gen_random_uuid(), '{}');
    if v_n <> floor(least(greatest(20, public.wc_int('rep_request_min')), public.wc_int('rep_request_max')) * (1 + v_a / 100)) then
      raise exception '0417 self-assert FAIL: a request of 20 points gave % Reputation at the top Requests level', v_n;
    end if;
    v_n := public.reputation_lap(v_pl, gen_random_uuid(), 500, 'Rota', 1);
    if v_n <> floor(public.wc_int('rep_lap') * (1 + v_b / 100)) or public.reputation_lap(v_pl, gen_random_uuid(), 0, 'Rota', 2) <> 0
       or public.reputation_lap(v_npc, gen_random_uuid(), 500, 'Rota', 1) <> 0 then
      raise exception '0417 self-assert FAIL: a lap at a gain gave % Reputation at the top Routes level (or a lap with no gain, or a merchant''s, gave some)', v_n;
    end if;

    -- (d) WEAR: two storm days and 2,000 miles, on a storm piece and a miles piece
    select min(iu.item_code) into v_storm from public.item_use iu where iu.trigger = 'STORM';
    select min(iu.item_code) into v_miles from public.item_use iu where iu.trigger = 'MILES';
    if v_storm is not null and v_miles is not null then
      v_sh := public.commission_ship(v_pl, v_fl, 'barca', 'Passos', true, true);
      insert into public.fitted_units (ship_id, item_code) values (v_sh, v_storm), (v_sh, v_miles);
      v_voy := gen_random_uuid();
      insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
      values (v_voy, v_fl, v_pl, '[]', 2000, '{}', now() - interval '10 minutes', now() - interval '1 minute', 'ARRIVED', v_lis, v_lis);
      insert into public.voyage_events (voyage_id, day_index, kind, payload) values (v_voy, 1, 'STORM', '{}'), (v_voy, 2, 'STORM', '{}');
      select sum(k.amount) into v_a from public.level_perks k where k.perk = 'storm_wear';
      select sum(k.amount) into v_b from public.level_perks k where k.perk = 'gear_wear';
      perform public.wear_units_for(v_fl, v_voy);
      if (select u.wear from public.fitted_units u where u.ship_id = v_sh and u.item_code = v_storm)
           <> round(2 * public.wc_num('gear_wear_per_storm') * (1 - v_a / 100) * (select case when cardinality(u.perks) = 0 then 1 else public.perk_wear_mult(u.perks) end from public.fitted_units u where u.ship_id = v_sh and u.item_code = v_storm), 2)
         or (select u.wear from public.fitted_units u where u.ship_id = v_sh and u.item_code = v_miles)
           <> round(2 * public.wc_num('gear_wear_per_1000nm') * (1 - v_b / 100) * (select case when cardinality(u.perks) = 0 then 1 else public.perk_wear_mult(u.perks) end from public.fitted_units u where u.ship_id = v_sh and u.item_code = v_miles), 2) then
        raise exception '0417 self-assert FAIL: two storm days and 2,000 miles wore her % at the top Weather and Craft levels',
          (select jsonb_agg(jsonb_build_array(u.item_code, u.wear)) from public.fitted_units u where u.ship_id = v_sh);
      end if;
      -- and with the knob off the same passage wears what it always did
      update public.world_config set value = 'false'::jsonb where key = 'level_perks_on';
      update public.fitted_units set wear = 0 where ship_id = v_sh;
      perform public.wear_units_for(v_fl, v_voy);
      if (select u.wear from public.fitted_units u where u.ship_id = v_sh and u.item_code = v_storm)
           <> round(2 * public.wc_num('gear_wear_per_storm') * (select case when cardinality(u.perks) = 0 then 1 else public.perk_wear_mult(u.perks) end from public.fitted_units u where u.ship_id = v_sh and u.item_code = v_storm), 2) then
        raise exception '0417 self-assert FAIL: with level_perks_on false a storm day did not wear what it did before';
      end if;
      update public.world_config set value = 'true'::jsonb where key = 'level_perks_on';
      v_note := 'wear proved on ' || v_storm || ' and ' || v_miles;
    else
      v_note := 'this world has no storm piece or no miles piece: wear was NOT RUN HERE (CI''s proof 113 holds it)';
    end if;

    -- (e) THE KNOB: off, every benefit is 0 and every figure its pre-image's; the page lists no step
    update public.level_xp set xp = v_xp where player_id = v_pl and skill = 'supplies';
    update public.world_config set value = 'false'::jsonb where key = 'level_perks_on';
    if public.level_perk(v_pl, 'supplies_price') <> 0 or public.stores_cost(v_pl, 4000, 1000) <> pg_temp.stores_cost_old_0417(v_pl, 4000, 1000)
       or public.standing_route_max_for(v_pl) <> pg_temp.route_max_old_0417(v_pl)
       or exists (select 1 from jsonb_array_elements(public.level_benefits('supplies', 10)) b where b ->> 'kind' = 'perk') then
      raise exception '0417 self-assert FAIL: with level_perks_on false a benefit is still applied or listed';
    end if;
    update public.world_config set value = 'true'::jsonb where key = 'level_perks_on';

    -- (f) THE PAGE: each level raised by doing lists its steps with the running total; the three old levels list none
    perform cmd.assume_identity(c_uid);
    v_r := world.levels() -> 'level_skills' -> 'skills';
    if exists (select 1 from jsonb_array_elements(v_r) e
                where (select count(*) from jsonb_array_elements(e -> 'benefits') b where b ->> 'kind' = 'perk')
                      <> (select count(*) from public.level_perks k where k.skill = e ->> 'code'))
       or exists (select 1 from jsonb_array_elements(v_r) e cross join jsonb_array_elements(e -> 'benefits') b
                   where b ->> 'kind' = 'perk'
                     and (b ->> 'total')::numeric <> (select sum(k.amount) from public.level_perks k where k.perk = b ->> 'perk' and k.level <= (b ->> 'level')::int))
       or (select count(*) from jsonb_array_elements(v_r) e cross join jsonb_array_elements(e -> 'benefits') b where b ->> 'kind' = 'perk') <> (select count(*) from public.level_perks) then
      raise exception '0417 self-assert FAIL: the page does not list the steps as the table holds them';
    end if;

    -- (g) WHAT IT COSTS A MERCHANT (a measurement, printed, never a gate): public.stores_cost, OLD and NEW interleaved, 1.5 s
    begin
      t1 := clock_timestamp();
      for i in 1 .. 4000 loop
        exit when clock_timestamp() - t1 > interval '1.5 seconds';
        if i % 2 = 0 then
          v_t := clock_timestamp(); perform pg_temp.stores_cost_old_0417(v_npc, 40, 10); v_old_us := v_old_us + extract(epoch from clock_timestamp() - v_t) * 1000000;
          v_t := clock_timestamp(); perform public.stores_cost(v_npc, 40, 10); v_new_us := v_new_us + extract(epoch from clock_timestamp() - v_t) * 1000000;
        else
          v_t := clock_timestamp(); perform public.stores_cost(v_npc, 40, 10); v_new_us := v_new_us + extract(epoch from clock_timestamp() - v_t) * 1000000;
          v_t := clock_timestamp(); perform pg_temp.stores_cost_old_0417(v_npc, 40, 10); v_old_us := v_old_us + extract(epoch from clock_timestamp() - v_t) * 1000000;
        end if;
        v_pairs := i;
      end loop;
    exception when others then
      v_note := v_note || ' (the measurement stopped: ' || left(sqlerrm, 80) || ')';
    end;
    raise exception using errcode = 'ZX417', message = 'PROBE_ROLLBACK_0417';
  exception when sqlstate 'ZX417' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0417 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like 'Casa % 0417' or p.auth_uid = c_uid)
     or public.wc('level_perks_on') is distinct from 'true'::jsonb
     or to_regprocedure('pg_temp.stores_cost_old_0417(uuid,numeric,numeric)') is not null
     or public.current_player_id() is not null then
    raise exception '0417 self-assert FAIL: the probe left something behind';
  end if;

  -- THIS FILE'S OWN UPDATE ROW (0347's news law), counted by its own key
  perform public.news_update('0417', 'Levels now give benefits', '레벨이 오르면 혜택이 생깁니다');
  if (select count(*) from public.world_news w where w.key = 'update:0417') <> 1 then
    raise exception '0417 self-assert FAIL: this file''s UPDATE row is not one row';
  end if;
  if clock_timestamp() - v_t0 > interval '15 seconds' then
    raise exception '0417 self-assert FAIL: the file took % (budget 15 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0417 cost: public.stores_cost for a merchant (the planner''s read), OLD and NEW interleaved, % pair(s): OLD % microseconds, NEW % microseconds a call. public.fleet_repair_cost gains the same one call. A sale, a buy and voyage.settle are not cut.',
    v_pairs, case when v_pairs > 0 then round(v_old_us / v_pairs, 1) end, case when v_pairs > 0 then round(v_new_us / v_pairs, 1) end;
  raise notice '0417 self-assert ok: A LEVEL GIVES SOMETHING AS IT RISES. One table no client reaches (% steps, eight benefits, seven levels), one knob (level_perks_on true), one reader no client calls; ten hunks over eight bodies, each once and reversing, grants, volatility, definer and search path unmoved; no other function and no existing knob moved; a sale, a buy and voyage.settle name nothing of it. Probe (rolled back): with no experience a company and a merchant read supplies, repairs and routes as the pre-images do; at the top level supplies and a hull''s repair cost their steps'' sum less (gear''s price unmoved), she keeps her steps'' routes more, a request and a profitable lap give their share more Reputation, and a merchant none; a step is had at its level and not one point before; %; with the knob off every figure is its pre-image''s and the page lists no step; the page lists every step with its running total. In all % ms.',
    (select count(*) from public.level_perks), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
