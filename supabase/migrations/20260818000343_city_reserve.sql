-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0343 — THE DEFAULT CITY RESERVE: a city's floor is sized by the city, a capital's first; it is an aid target and nothing else. DARK
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Owner, 2026-11-05 (docs/OWNER_REQUESTS.md row 281): "i think the cities should have gold reserve as default - bank"; "hold 484 for now, city reserve size - capital comes first".
-- 2026-11-06 (row 306): "use your recommended defaults for the rest". 2026-11-08: "continue all without asking". The bank itself (#484) stays on hold: nothing of it is here.
--
-- WHAT THE FLOOR IS TODAY (0306): one flat knob, treasury_reserve_floor, 50,000 d. for every harbour alike. It is read in exactly two places: public.city_aid_target (the level the crown's aid tops a
-- city up to: the roster of public.crown_aid, a cargo ship's delivery in public.cargo_ship_step, a donor's room in public.crown_call_room, the hall's public.funds_on_way) and public.tick_contract_wind
-- (a harbour under the floor posts no request). MEASURED ON PROD, read-only, 2026-11-07 18:11 UTC, head 0341 (docs/dev-log/2026-11-08-city-reserve.md): 249 harbours, 10 working capitals, 227 crown
-- cities, 12 with no crown. The flat floor IS the aid target at nearly every harbour (the rolled reserve is 3 game days of payouts and a game day is a minute: medians 4,800 / 12,500 / 40,900 d. by tier).
-- 73 of 227 cities held under 50,000 d., 170 of 227 were under it at some point of the day, 39 % of all city slots of the day were under it, and 2.5 % sat exactly at it (just topped up, draining again).
-- A city's sale payouts a day scale with its size: medians 2.1 M (tier 2, 119 cities), 6.2 M (tier 3, 81), 19.6 M (tier 5, 27); 50,000 d. is 34 minutes of a tier-2 city's payouts and 4 minutes of a tier-5's.
--
-- WHAT THIS FILE DOES (decided by default, each in the dev-log with its consequence):
--   1. public.city_default_reserve(port): THE default reserve a harbour keeps by its size: ports.size_tier x city_reserve_per_tier (100,000 d.: tier 2 = 200,000, tier 3 = 300,000, tier 5 = 500,000),
--      a capital's times city_reserve_capital_mult (5: the owner's "capital comes first", so 1.0 M / 1.5 M / 2.5 M). size_tier is the one size the world keeps for a harbour (stock and production
--      derive from it); the rolled reserve is NOT in it (the owner: "not by recent payouts"). A harbour of no crown (a free city, a pirate home, a city the pirates hold) is sized as a city of its tier:
--      nobody fills it (public.city_capital is null, so public.crown_aid's roster, a cargo ship and a donor's call never reach it: no crown money can move into the pirates through a reserve).
--   2. public.city_floor(port): THE level under which a harbour is short whatever its rolled reserve. Dark: the flat knob of 0306, every harbour alike, so the world reads byte for byte as before.
--      Lit: public.city_default_reserve. It REPLACES the flat floor exactly where that floor is read, and nowhere else.
--   3. public.city_reserve_on(): THE one reader of the switch city_reserve_enabled (false; the owner lights it).
--   4. THE RE-CUTS (hunks sliced from the LIVE bodies read in the cached head world at 0341, each asserted to occur exactly once and to reverse to its pre-image, ACL and settings unchanged;
--      this file supersedes those lines of 0306's public.city_aid_target and of 0318's public.tick_contract_wind):
--        public.city_aid_target (2 hunks): greatest(rolled reserve, public.city_floor) instead of greatest(rolled reserve, the knob); the comment that names the floor.
--        public.tick_contract_wind (3 hunks): the gate reads public.city_floor(p.id) instead of the knob read once into v_floor; v_floor goes; the comment that names the floor.
-- WHAT IT IS NOT: never a price or a bid (public.city_bid_factor and world.price_terms read port_treasury.reserve, untouched: 0306 measured 121 harbours bidding 29 % less if the floor lowered what a city
-- pays for goods), never a spending lock (public.city_surplus, the one figure every spender reads, untouched: a city may spend under its default reserve and the crown fills it again), never a new
-- mover of gold (the aid stays CROWN_AID, CROWN_CALL and the cargo ships' CONVOY_LOAD / CONVOY_DELIVER; W is unchanged to the ducat by this file: it writes no purse). No bank. No other slice.
-- A CAPITAL THAT CANNOT AFFORD ITS CITIES lays nothing off, no error: the pay term greatest(0, public.city_surplus(capital)) stands (0306: a capital is judged by its own reserve), a donor's room is
-- 0 when the realm has none, a ship loads nothing. "Capital comes first" is its size (the multiple) and its place in the roster: lit, with rich cities sending the ships (0324, live since 2026-11-07),
-- the capital is a stop with the realm's largest target; the stops are filled in the ship's circuit order (a nearest-neighbour tour: no stop order can carry a priority, said in the dev-log).
-- LIT, AT TODAY'S PURSES (measured): 133 cities and 7 capitals would be under their default reserve (74 cities and 2 capitals are under the flat floor), a gap of 25.2 M + 11.5 M d., against a
-- realm donor room of 1.5 M (LON) to 447 M (LIS) a run; moved by the cargo ships over hours, nothing minted. And a city under its reserve posts no request until the ships fill it.
--
-- SELF-ASSERT (the catalog, stable reads and arithmetic; a probe realm of its own rolled-back harbours, a pirate-held probe city and a crownless one; no real city is written, no real game step runs,
-- docs/OPS_HEALTH.md section 4): the hunks once and reversing; no other function, ACL, knob, trigger or job moved; the switch false; the new functions STABLE, definer, server-only; DARK PARITY on the
-- live world: public.city_floor is the knob and public.city_aid_target is 0306's formula at every harbour; on the probe: the sizes by tier, the capital's multiple, the crownless and the pirate-held
-- city sized as cities, a city that grows or shrinks, the knobs at 0 and 1, the floor dark 50,000 and lit the size, the target greatest(rolled, floor), bid / surplus / reserve the same at both
-- states; then public.crown_aid narrowed to the probe realm (the instant path, with both ship switches set false inside the rolled-back probe): dark it is 0306's arithmetic to the ducat, lit each
-- city is topped up to its default reserve, a second pass gives nothing, a broke capital gives nothing with no error, a poorer capital stops exactly at its rolled reserve, the pirate-held city and
-- the crownless city are never aided, the sum of every probe purse is unchanged in every pass. THE REAL PATHS (public.city_day over the world, the cargo ships lit, the wind's gate, prices) ARE
-- PROVED IN CI: proof 50, scripts/db/proofs/50_city_reserve.sql. Mutation controls: scripts/ops/harness/city-reserve/proof-0343.mjs (local).
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 60 s, lock_timeout 5 s first. Work: three rows, three functions, two re-cuts, catalog reads, five probe passes (each a
--   249-harbour roster read). Self-assert fails above 45 s. No unindexed read of a big table: port_treasury (249 rows) and the catalog only.
-- ROLLBACK (forward, a NEW migration, owner only): dark there is nothing to switch off. Lit: update public.world_config set value = 'false'::jsonb where key = 'city_reserve_enabled';
--   the next hourly public.tick_city and the next wind minute are 0306's rule. Gold already moved stays where it went: it was moved, not made. To remove: swap this file's hunks and drop the three.
-- VERSION: 0343 - prod head 0341 (read 2026-11-07 18:11 UTC); 0342 (the navy off pirate ports) is before it and touches none of these bodies.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0   timestamptz := clock_timestamp();
  v_h    record;
  v_def  text;
  v_pre  text;
  v_n    int;
  v_fn_before   text;
  v_meta_before text;
  v_cfg_before  text;
  v_trig_before text;
  v_cron_before text;
  v_cron_after  text;
  v_bad  int;
  v_mark bigint;
  v_nat  uuid;
  v_pir  uuid;
  v_cap  uuid;
  v_b uuid; v_c uuid; v_d uuid; v_e uuid; v_p uuid; v_x uuid;
  v_all  jsonb;
  v_dark jsonb;
  v_full jsonb;
  v_poor jsonb;
  v_none jsonb;
  v_r    jsonb;
  c_keys constant text[] := array['city_reserve_enabled', 'city_reserve_per_tier', 'city_reserve_capital_mult'];
  c_new_fns constant text[] := array['public.city_reserve_on()', 'public.city_default_reserve(uuid)', 'public.city_floor(uuid)'];
  c_hunked constant text[] := array['public.city_aid_target(uuid)', 'public.tick_contract_wind(boolean,uuid)'];
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD: nothing of this file exists, and the premises it was cut against hold ──
  if exists (select 1 from public.world_config c where c.key = any (c_keys))
     or to_regprocedure('public.city_reserve_on()') is not null or to_regprocedure('public.city_default_reserve(uuid)') is not null or to_regprocedure('public.city_floor(uuid)') is not null then
    raise exception '0343 refuses: something of it is already in this world';
  end if;
  if to_regprocedure('public.city_aid_target(uuid)') is null or to_regprocedure('public.crown_aid(uuid)') is null or to_regprocedure('public.tick_contract_wind(boolean,uuid)') is null
     or to_regprocedure('public.city_capital(uuid)') is null or to_regprocedure('public.pirate_power(uuid)') is null or to_regprocedure('public.pirate_nation()') is null
     or not exists (select 1 from public.world_config c where c.key = 'treasury_reserve_floor') then
    raise exception '0343 refuses: 0306 / 0315 / 0318 / 0338 / 0339 (the floor, the wind, the pirates'' crownless cities) are not all in this world';
  end if;
  v_pir := public.pirate_nation();
  if v_pir is null then
    raise exception '0343 refuses: the Brethren (0338) are not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
    into v_meta_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c;
  select md5(string_agg(t.tgrelid::regclass::text || ':' || t.tgname || ':' || t.tgenabled::text, ',' order by t.tgrelid::regclass::text, t.tgname)) into v_trig_before
    from pg_trigger t where not t.tgisinternal;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_before;
  end if;

  -- ── 2. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('city_reserve_enabled', 'false'::jsonb,
     '0343: THE switch of the default city reserve (owner row 281). False: a harbour''s floor is the flat treasury_reserve_floor of 0306. True: its default reserve by size (public.city_default_reserve). Read through public.city_reserve_on alone. Owner only.'),
    ('city_reserve_per_tier', to_jsonb(100000),
     '0343: ducats of default reserve a harbour keeps per size tier (ports.size_tier 1-5): tier 2 = 200,000, tier 3 = 300,000, tier 5 = 500,000. Measured 2026-11-07: about 2 hours of a tier-2 city''s sale payouts. An aid target only: never a bid, never a spending lock. Read through public.city_default_reserve alone.'),
    ('city_reserve_capital_mult', to_jsonb(5),
     '0343: a capital''s default reserve is this multiple of a city''s of its tier (owner 2026-11-05: "capital comes first"). Read through public.city_default_reserve alone.');

  -- ── 3. THE THREE READERS ──
  execute $f$
create function public.city_reserve_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0343: THE one reader of city_reserve_enabled (owner row 281). Off: the flat floor of 0306. On: the default reserve by size. Server-only.
  select coalesce(public.wc('city_reserve_enabled') = 'true'::jsonb, false)
$body$
  $f$;
  revoke all on function public.city_reserve_on() from public, anon, authenticated;
  comment on function public.city_reserve_on() is '0343: THE one reader of the default-city-reserve switch (world_config city_reserve_enabled). Server-only.';

  execute $f$
create function public.city_default_reserve(p_port uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0343: THE default reserve a harbour keeps by its size (owner row 281: "cities should have gold reserve as default", "capital comes first"): ports.size_tier x city_reserve_per_tier,
  -- a capital's times city_reserve_capital_mult. Not by recent payouts (the owner's word): the rolled reserve is not in it. A harbour of no crown (a free city, a pirate home, a city the pirates
  -- hold) is sized as a city of its tier; nobody fills it (public.city_capital is null there, so no aid, no ship, no call reaches it). An AID TARGET and nothing else: public.city_bid_factor and
  -- public.city_surplus do not read it. Null for a port that is no harbour.
  select round(p.size_tier * public.wc_num('city_reserve_per_tier')
               * case when public.city_capital(p.id) = p.id then public.wc_num('city_reserve_capital_mult') else 1 end)::bigint
    from public.ports p where p.id = p_port and p.kind = 'HARBOUR'
$body$
  $f$;
  revoke all on function public.city_default_reserve(uuid) from public, anon, authenticated;
  comment on function public.city_default_reserve(uuid) is '0343: THE default reserve a harbour keeps by its size: size_tier x city_reserve_per_tier, a capital''s x city_reserve_capital_mult. An aid target only. Server-only.';

  execute $f$
create function public.city_floor(p_port uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0343: THE level under which a harbour is short whatever its rolled reserve. Read by public.city_aid_target (the crown's aid: the roster, a cargo ship's delivery, a donor's room, the hall's
  -- funds on the way) and by public.tick_contract_wind (a short harbour posts no request), and by nothing else. Dark (city_reserve_enabled false): the flat knob treasury_reserve_floor of 0306,
  -- every harbour alike. Lit: its default reserve by size (public.city_default_reserve).
  select case when public.city_reserve_on() then coalesce(public.city_default_reserve(p_port), 0)
              else round(public.wc_num('treasury_reserve_floor'))::bigint end
$body$
  $f$;
  revoke all on function public.city_floor(uuid) from public, anon, authenticated;
  comment on function public.city_floor(uuid) is '0343: THE floor under which a harbour is short: 0306''s flat knob dark, its default reserve by size lit. Read by city_aid_target and tick_contract_wind alone. Server-only.';

  -- ── 4. THE HUNKS: sliced from the live bodies, each once ──
  create temp table hunks_0343 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0343 values
  -- city_aid_target: the one level the crown tops a city up to
  ('public.city_aid_target(uuid)', 1,
$h$  -- 0306: THE level the crown tops a city up to: its rolled reserve, never under treasury_reserve_floor. A city under it is short (a broke city
$h$,
$h$  -- 0306: THE level the crown tops a city up to: its rolled reserve, never under its floor (public.city_floor: 0343, the flat knob dark, its default reserve by size lit). A city under it is short (a broke city
$h$),
  ('public.city_aid_target(uuid)', 2,
$h$                  round(public.wc_num('treasury_reserve_floor')))::bigint
$h$,
$h$                  public.city_floor(p_port))::bigint   -- 0343: the one floor
$h$),
  -- tick_contract_wind: a short harbour posts no request
  ('public.tick_contract_wind(boolean,uuid)', 1,
$h$-- A city under treasury_reserve_floor is left alone: it is already short (0306), and its purse is what pays for cargo. Its own read may still post.
$h$,
$h$-- A city under its floor (public.city_floor: 0306's flat knob dark, 0343's default reserve by size lit) is left alone: it is already short, and its purse is what pays for cargo. Its own read may still post.
$h$),
  ('public.tick_contract_wind(boolean,uuid)', 2,
$h$  v_floor  bigint := public.wc_int('treasury_reserve_floor');
  v_posts  int := public.wc_int('contract_wind_posts');   -- 0318
$h$,
$h$  v_posts  int := public.wc_int('contract_wind_posts');   -- 0318
$h$),
  ('public.tick_contract_wind(boolean,uuid)', 3,
$h$       and public.treasury_balance(p.id) >= v_floor
$h$,
$h$       and public.treasury_balance(p.id) >= public.city_floor(p.id)   -- 0343: its own floor: the flat knob dark, its default reserve by size lit
$h$);

  for v_h in select h.fn from hunks_0343 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    declare
      x record;
    begin
      for x in select * from hunks_0343 h where h.fn = v_h.fn order by h.ord loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0343 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
      for x in select * from hunks_0343 h where h.fn = v_h.fn order by h.ord desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0343 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0343 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;

  -- ── 5. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked || c_new_fns) x))) <> v_fn_before then
    raise exception '0343 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_new_fns) x))) <> v_meta_before then
    raise exception '0343 self-assert FAIL: an ACL, a volatility, a definer flag or a setting moved (the re-cut bodies included)';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> all (c_keys)) <> v_cfg_before then
    raise exception '0343 self-assert FAIL: a world_config row moved';
  end if;
  if (select md5(string_agg(t.tgrelid::regclass::text || ':' || t.tgname || ':' || t.tgenabled::text, ',' order by t.tgrelid::regclass::text, t.tgname))
        from pg_trigger t where not t.tgisinternal) <> v_trig_before then
    raise exception '0343 self-assert FAIL: a trigger moved';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_after;
    if v_cron_after is distinct from v_cron_before then
      raise exception '0343 self-assert FAIL: a cron job moved';
    end if;
  end if;
  if (select string_agg(p.provolatile::text || case when p.prosecdef then 'd' else '-' end, '' order by p.oid::regprocedure::text) from pg_proc p where p.oid = any (array(select x::regprocedure::oid from unnest(c_new_fns) x))) <> 'sdsdsd' then
    raise exception '0343 self-assert FAIL: the new functions are not STABLE SECURITY DEFINER';
  end if;
  if exists (select 1 from unnest(c_new_fns) f where has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')) then
    raise exception '0343 self-assert FAIL: a client can reach a reader of the reserve';
  end if;
  if public.city_reserve_on() or public.wc('city_reserve_enabled') <> 'false'::jsonb then
    raise exception '0343 self-assert FAIL: the switch must ship false (dark)';
  end if;
  if public.wc_num('city_reserve_per_tier') <> 100000 or public.wc_num('city_reserve_capital_mult') <> 5 then
    raise exception '0343 self-assert FAIL: the knobs are not at their defaults';
  end if;
  v_def := replace(pg_get_functiondef('public.tick_contract_wind(boolean,uuid)'::regprocedure), E'\r', '');
  if v_def like '%v_floor%' or v_def not like '%>= public.city_floor(p.id)%' then
    raise exception '0343 self-assert FAIL: the wind still reads the flat knob, or not its own floor';
  end if;

  -- ── 6. DARK PARITY ON THE LIVE WORLD (read-only): the floor is the knob and the target is 0306's formula at every harbour ──
  select count(*) into v_bad
    from public.ports p left join public.port_treasury t on t.port_id = p.id
   where p.kind = 'HARBOUR'
     and (public.city_floor(p.id) <> round(public.wc_num('treasury_reserve_floor'))::bigint
          or public.city_aid_target(p.id) <> greatest(coalesce(t.reserve, 0), round(public.wc_num('treasury_reserve_floor')))::bigint);
  if v_bad <> 0 then
    raise exception '0343 self-assert FAIL: dark, % harbour(s) read a floor or a target that is not 0306''s', v_bad;
  end if;

  -- ── 7. THE SELF-ASSERT: a probe realm, every row rolled back ──
  -- One pass of the instant aid over the probe realm: what each harbour's own flows came to, the capital after, the sum of every probe purse (the realm, the pirate-held city, the crownless one), a second pass.
  execute $f$
create function pg_temp.pass_0343(p_nation uuid, p_cap uuid, p_mark bigint)
returns jsonb
language plpgsql
as $b$
declare
  v_sum0 bigint;
  v_r    jsonb;
  v_again jsonb;
begin
  select sum(public.treasury_balance(p.id)) into v_sum0 from public.ports p where p.code like 'QX_';
  v_r := public.crown_aid(p_cap);
  v_again := public.crown_aid(p_cap);
  return v_r || jsonb_build_object(
    'again', v_again,
    'by', coalesce((select jsonb_object_agg(x.code, x.d)
                      from (select p.code, sum(f.ducats) as d from public.treasury_flows f join public.ports p on p.id = f.port_id
                             where f.id > p_mark and f.created_at = now() and f.kind = 'CROWN_AID' and p.code like 'QX_'
                             group by p.code) x), '{}'::jsonb),
    'sum_moved', (select sum(public.treasury_balance(p.id)) from public.ports p where p.code like 'QX_') - v_sum0,
    'cap_after', public.treasury_balance(p_cap),
    'cap_reserve', (select t.reserve from public.port_treasury t where t.port_id = p_cap));
end
$b$
  $f$;

  v_mark := coalesce((select max(f.id) from public.treasury_flows f), 0);
  begin
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed') and value is distinct from 'true'::jsonb;
    -- the instant path for the probe realm alone: both ship switches off inside this rolled-back probe (the real ship path is proof 50's, in CI)
    update public.world_config set value = 'false'::jsonb where key in ('convoys_enabled', 'convoy_rich_enabled') and value is distinct from 'false'::jsonb;
    insert into public.nations (code, name, flag_char, capital_port_code) values ('QX7', 'Probe 0343', 'Z', 'QXA') returning id into v_nat;
    insert into public.great_powers (nation_id) values (v_nat);
    insert into public.ports (code, name, country, lat, lon, sea_id, region_id, culture, size_tier, max_draft, kind)
    select x.code, 'Probe ' || x.code, t.country, t.lat, t.lon, t.sea_id, t.region_id, t.culture, x.tier, t.max_draft, 'HARBOUR'
      from (values ('QXA', 5), ('QXB', 2), ('QXC', 3), ('QXD', 5), ('QXE', 2), ('QXP', 3), ('QXN', 2)) x(code, tier)
     cross join (select * from public.ports where kind = 'HARBOUR' order by code limit 1) t;
    v_cap := (select p.id from public.ports p where p.code = 'QXA');   -- the capital, tier 5
    v_b   := (select p.id from public.ports p where p.code = 'QXB');   -- broke, zero outflow, reserve 0, tier 2
    v_c   := (select p.id from public.ports p where p.code = 'QXC');   -- under a small reserve, tier 3
    v_d   := (select p.id from public.ports p where p.code = 'QXD');   -- under a reserve above the flat floor, under its default reserve, tier 5
    v_e   := (select p.id from public.ports p where p.code = 'QXE');   -- a rolled reserve above its default reserve: the rolled reserve wins, tier 2
    v_p   := (select p.id from public.ports p where p.code = 'QXP');   -- held by the pirates: no crown, tier 3
    v_x   := (select p.id from public.ports p where p.code = 'QXN');   -- held by nobody: no crown, tier 2
    insert into public.port_allegiance (port_id, nation_id) select p.id, v_nat from public.ports p where p.code in ('QXA', 'QXB', 'QXC', 'QXD', 'QXE');
    insert into public.port_allegiance (port_id, nation_id) values (v_p, v_pir);
    insert into public.port_treasury (port_id, ducats, reserve, earned_day) values
      (v_cap, 10000000, 7777, world.game_day()), (v_b, 1000, 0, world.game_day()), (v_c, 100, 900, world.game_day()),
      (v_d, 30000, 80000, world.game_day()), (v_e, 1000000, 777777, world.game_day()), (v_p, 100, 0, world.game_day()), (v_x, 100, 0, world.game_day());

    -- dark: sizes, floors, targets, and what the floor must never move (bid, surplus, reserve)
    select jsonb_object_agg(p.code, jsonb_build_array(public.city_default_reserve(p.id), public.city_floor(p.id), public.city_aid_target(p.id))) into v_r from public.ports p where p.code like 'QX_';
    v_all := jsonb_build_object('dark', v_r, 'capital_of_p', public.city_capital(v_p), 'capital_of_x', public.city_capital(v_x), 'capital_of_b', public.city_capital(v_b) = v_cap);
    select jsonb_object_agg(p.code, jsonb_build_array(public.city_bid_factor(p.id), public.city_surplus(p.id), public.treasury_reserve(p.id))) into v_r from public.ports p where p.code like 'QX_';
    v_all := v_all || jsonb_build_object('fixed0', v_r);
    begin   -- dark: today's rule, 0306's arithmetic
      raise exception using errcode = 'ZX343', message = pg_temp.pass_0343(v_nat, v_cap, v_mark)::text;
    exception when sqlstate 'ZX343' then v_dark := sqlerrm::jsonb; end;

    -- lit
    update public.world_config set value = 'true'::jsonb where key = 'city_reserve_enabled';
    select jsonb_object_agg(p.code, jsonb_build_array(public.city_default_reserve(p.id), public.city_floor(p.id), public.city_aid_target(p.id))) into v_r from public.ports p where p.code like 'QX_';
    v_all := v_all || jsonb_build_object('lit', v_r);
    select jsonb_object_agg(p.code, jsonb_build_array(public.city_bid_factor(p.id), public.city_surplus(p.id), public.treasury_reserve(p.id))) into v_r from public.ports p where p.code like 'QX_';
    v_all := v_all || jsonb_build_object('fixed1', v_r);
    -- a city that grows, and one that shrinks
    update public.ports set size_tier = 5 where id = v_b;
    v_all := v_all || jsonb_build_object('grown', public.city_default_reserve(v_b));
    update public.ports set size_tier = 1 where id = v_b;
    v_all := v_all || jsonb_build_object('shrunk', public.city_default_reserve(v_b));
    update public.ports set size_tier = 2 where id = v_b;
    -- the knobs: per tier 0 is a floor of 0 (the target is the rolled reserve alone); a multiple of 1 makes the capital a city
    update public.world_config set value = to_jsonb(0) where key = 'city_reserve_per_tier';
    v_all := v_all || jsonb_build_object('per0', jsonb_build_array(public.city_default_reserve(v_cap), public.city_floor(v_b), public.city_aid_target(v_b), public.city_aid_target(v_e)));
    update public.world_config set value = to_jsonb(100000) where key = 'city_reserve_per_tier';
    update public.world_config set value = to_jsonb(1) where key = 'city_reserve_capital_mult';
    v_all := v_all || jsonb_build_object('mult1', public.city_default_reserve(v_cap));
    update public.world_config set value = to_jsonb(5) where key = 'city_reserve_capital_mult';

    begin   -- lit, a rich capital: every city of the realm up to its default reserve; the pirate-held and the crownless city untouched
      raise exception using errcode = 'ZX343', message = pg_temp.pass_0343(v_nat, v_cap, v_mark)::text;
    exception when sqlstate 'ZX343' then v_full := sqlerrm::jsonb; end;
    begin   -- lit, a capital with 300,000 above its rolled reserve: it stops exactly at that reserve (0306's rule stands: its own default reserve is an aid target, not a lock)
      update public.port_treasury set ducats = 7777 + 300000 where port_id = v_cap;
      raise exception using errcode = 'ZX343', message = pg_temp.pass_0343(v_nat, v_cap, v_mark)::text;
    exception when sqlstate 'ZX343' then v_poor := sqlerrm::jsonb; end;
    begin   -- lit, a broke capital: it lays nothing off, no error
      update public.port_treasury set ducats = 1000 where port_id = v_cap;
      raise exception using errcode = 'ZX343', message = pg_temp.pass_0343(v_nat, v_cap, v_mark)::text;
    exception when sqlstate 'ZX343' then v_none := sqlerrm::jsonb; end;

    raise exception using errcode = 'ZX343', message = v_all::text;
  exception when sqlstate 'ZX343' then
    v_all := sqlerrm::jsonb;
  end;
  drop function pg_temp.pass_0343(uuid, uuid, bigint);

  -- the probe's crowns: the realm's city has the probe capital, the pirate-held and the crownless have none
  if (v_all ->> 'capital_of_p') is not null or (v_all ->> 'capital_of_x') is not null or not (v_all ->> 'capital_of_b')::boolean then
    raise exception '0343 self-assert FAIL: the probe''s crowns are not as planned: %', v_all;
  end if;
  -- dark: every size is already the formula; every floor is 50,000; every target is greatest(rolled, 50,000)
  if v_all -> 'dark' <> '{"QXA": [2500000, 50000, 50000], "QXB": [200000, 50000, 50000], "QXC": [300000, 50000, 50000], "QXD": [500000, 50000, 80000], "QXE": [200000, 50000, 777777], "QXP": [300000, 50000, 50000], "QXN": [200000, 50000, 50000]}'::jsonb then
    raise exception '0343 self-assert FAIL: dark, the sizes, floors or targets are not as planned: %', v_all -> 'dark';
  end if;
  -- lit: the floor is the size (tier x 100,000; the capital x 5; the pirate-held and the crownless sized as cities); the target is greatest(rolled, floor)
  if v_all -> 'lit' <> '{"QXA": [2500000, 2500000, 2500000], "QXB": [200000, 200000, 200000], "QXC": [300000, 300000, 300000], "QXD": [500000, 500000, 500000], "QXE": [200000, 200000, 777777], "QXP": [300000, 300000, 300000], "QXN": [200000, 200000, 200000]}'::jsonb then
    raise exception '0343 self-assert FAIL: lit, the sizes, floors or targets are not as planned: %', v_all -> 'lit';
  end if;
  if (v_all ->> 'grown')::bigint <> 500000 or (v_all ->> 'shrunk')::bigint <> 100000 then
    raise exception '0343 self-assert FAIL: a city that grows or shrinks does not read its new size: % %', v_all ->> 'grown', v_all ->> 'shrunk';
  end if;
  if v_all -> 'per0' <> '[0, 0, 0, 777777]'::jsonb or (v_all ->> 'mult1')::bigint <> 500000 then
    raise exception '0343 self-assert FAIL: the knobs do not move the size as planned: % %', v_all -> 'per0', v_all ->> 'mult1';
  end if;
  -- never a price, never a spending lock: bid, surplus and reserve the same at both states, and a broke city's bid is 1 with no reserve
  if (v_all -> 'fixed0') is distinct from (v_all -> 'fixed1') or (v_all #>> '{fixed1,QXB,0}')::numeric <> 1 or (v_all #>> '{fixed1,QXB,2}')::bigint <> 0 then
    raise exception '0343 self-assert FAIL: the reserve moved a bid, a surplus or a rolled reserve: %', v_all;
  end if;
  -- nothing minted in any pass
  if (v_dark ->> 'sum_moved')::bigint <> 0 or (v_full ->> 'sum_moved')::bigint <> 0 or (v_poor ->> 'sum_moved')::bigint <> 0 or (v_none ->> 'sum_moved')::bigint <> 0 then
    raise exception '0343 self-assert FAIL: the sum of the probe purses moved: % % % %', v_dark, v_full, v_poor, v_none;
  end if;
  -- dark is 0306 to the ducat (its own self-assert's figures: 49,000 + 49,900 + 50,000)
  if v_dark -> 'by' <> '{"QXA": -148900, "QXB": 49000, "QXC": 49900, "QXD": 50000}'::jsonb or (v_dark ->> 'aided')::int <> 3 or (v_dark ->> 'aid')::bigint <> 148900 then
    raise exception '0343 self-assert FAIL: dark is not 0306''s rule to the ducat: %', v_dark;
  end if;
  -- lit: each city up to its default reserve (199,000 + 299,900 + 470,000), the city whose rolled reserve is higher untouched (it holds above it), the pirate-held and the crownless never aided
  if v_full -> 'by' <> '{"QXA": -968900, "QXB": 199000, "QXC": 299900, "QXD": 470000}'::jsonb or (v_full ->> 'aided')::int <> 3 or (v_full ->> 'aid')::bigint <> 968900 then
    raise exception '0343 self-assert FAIL: lit, the cities were not topped up to their default reserve, or a city of no crown was: %', v_full;
  end if;
  if (v_dark -> 'again' ->> 'aided')::int <> 0 or (v_full -> 'again' ->> 'aided')::int <> 0 then
    raise exception '0343 self-assert FAIL: a second pass gave more: % %', v_dark, v_full;
  end if;
  if v_poor -> 'by' <> '{"QXA": -300000, "QXB": 199000, "QXC": 101000}'::jsonb or (v_poor ->> 'cap_after')::bigint <> (v_poor ->> 'cap_reserve')::bigint then
    raise exception '0343 self-assert FAIL: a capital did not stop exactly at its rolled reserve: %', v_poor;
  end if;
  if v_none -> 'by' <> '{}'::jsonb or (v_none ->> 'aided')::int <> 0 or (v_none ->> 'cap_after')::bigint <> 1000 then
    raise exception '0343 self-assert FAIL: a broke capital gave, or was aided: %', v_none;
  end if;

  -- nothing of the probe survives; the switch and the knobs stand at their defaults
  if exists (select 1 from public.ports p where p.code like 'QX_') or exists (select 1 from public.nations n where n.code = 'QX7')
     or exists (select 1 from public.treasury_flows f where f.id > v_mark and f.created_at = now()) then
    raise exception '0343 self-assert FAIL: the probe left rows behind';
  end if;
  if public.city_reserve_on() or public.wc_num('city_reserve_per_tier') <> 100000 or public.wc_num('city_reserve_capital_mult') <> 5 then
    raise exception '0343 self-assert FAIL: the switch or a knob is not at its default after the probe';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> all (c_keys)) <> v_cfg_before then
    raise exception '0343 self-assert FAIL: a world_config row moved during the probe';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0343 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0343 self-assert ok: THE DEFAULT CITY RESERVE, dark behind city_reserve_enabled. % hunks over % bodies, each once and reversing, grants unmoved; % readers made, server-only; % knobs; no other function, knob, trigger or job moved. Dark parity on the live world at every harbour. Probe realm: dark = 0306 (% d.), lit each city to its size (% d.), a capital stopped at its rolled reserve, a broke one gave nothing, the pirate-held and crownless cities never aided, purses summed moved 0. The real paths: proof 50, in CI. Printed, never asserted: % ms.',
    (select count(*) from hunks_0343), (select count(distinct h.fn) from hunks_0343 h), cardinality(c_new_fns), cardinality(c_keys),
    v_dark ->> 'aid', v_full ->> 'aid', round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0343;
end
$m$;
