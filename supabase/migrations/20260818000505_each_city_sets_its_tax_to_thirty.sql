-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights tax_thirty_enabled)
-- 0505 - EACH CITY SETS ITS TAX, 0 TO 30 %, AND HOME PAYS HALF  (dark: the owner's switch tax_thirty_enabled, false. Slice T1
--   `tax-to-thirty`, docs/design/owner-spec-plan-2026-11-25.md section 6, rows 54 and 55)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25 (docs/design/owner-spec-2026-11-25.md, "Addition"): "Each city will have its own tax, with 0%~30%. Your own
--   country or the city that has your HQ will provide less tax."
--
-- TODAY (read in the live bodies). world.tax_rate(city, company) is THE one authority of the profit tax's rate: the city's column x
--   profit_tax_scale, never above tax_rate_max (0.20); while the race is on, the MAYOR's rate replaces it (cmd.set_tax: 0 to
--   tax_rate_max, once a real day); then the company's standing with the city's holder (her own country: half open, a quarter closed).
--   The city that is her HOME (public.home_port_of, 0288) gets nothing for it.
--
-- LIT (tax_thirty_enabled true):
--   * THE MAYOR'S DIAL goes to 30 %: cmd.set_tax (one hunk) takes 0 to public.tax_cap() = tax_rate_cap (0.30, this file's knob).
--   * HOME PAYS HALF: at the city that is her home a company pays no more than (1 - home_tax_cut) = half of the city's rate; the
--     BETTER of that and what her country's standing gives her today, never both on top of each other (world.tax_rate, four hunks:
--     each of its four answers that knows the city's rate goes through public.tax_home_half).
--   * OWN COUNTRY: as today (untouched).
-- NO RATE MOVES, AT DEPLOY OR AT THE LIGHT. The owner's knobs tax_rate_max and profit_tax_scale are NOT changed and a city's own
--   column still stops at tax_rate_max, so no city's rate rises by itself: only a mayor's own press can take a city above 20 %, and
--   only her home half can lower what a company pays. The self-assert reads world.tax_rate for every harbour before, after (dark)
--   and lit: equal, and for a company away from home: equal.
-- DARK (as deployed): byte-identical answers. public.tax_cap() is tax_rate_max; public.tax_home_half hands back the rate it was given.
-- THE HUNKS (5; each once in the live body, each reverses): world.tax_rate x4, cmd.set_tax x1.
-- NEW: public.tax_thirty_on(), public.tax_cap(), public.tax_home_half(city, company, rate, the city's rate). All server only
--   (public, anon, authenticated, service_role revoked) and STABLE. Knobs: tax_thirty_enabled false, tax_rate_cap 0.30,
--   home_tax_cut 0.5. NOT CHANGED: tax_rate_max, profit_tax_scale, influence_citizen_tax_cut, country_tax_factor, every other knob;
--   public.profit_tax, public.profit_tax_at; ports.tax_rate; port_mayor's rows; any table.
-- ROWS: none, dark or lit (no table, no row is written by this file; a mayor's press updates her one row as today).
-- budget: none (no table, no cron job, no index, no autovacuum setting is made). -- retention: none (no table is made).
-- COST: dark, one switch read more in a world.tax_rate that names a company, and one in cmd.set_tax. Lit, one public.home_port_of more
--   (her first FOUNDED event, by events' player index) in a world.tax_rate that names a company.
-- LOCKS: CREATE OR REPLACE x2 by hunks, CREATE FUNCTION x3, three knobs. TIME: under a second. BUDGET: statement_timeout 45 s,
--   lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): QUICK, tax_thirty_enabled false: a mayor's rate above tax_rate_max stays in her row and is served as
--   it is (world.tax_rate never capped a mayor's rate), so the lead reads port_mayor before darkening (after-0505.sql, `over_max`).
--   FULL: scripts/ops/harness/tax-to-thirty/rollback-0505.sql (a draft).
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path and
--   owner unmoved; no other knob moved; the three new functions server only and STABLE. EVERY HARBOUR: world.tax_rate equal before,
--   after and lit. THE PROBE (rolled back by a raised sentinel; no role is changed; INDEPENDENT OF PROD'S MARKET, DICE AND COMPANIES:
--   its city is a SEA_PLACE that no country holds and no mayor has, so the allegiance row, the mayor row, the two companies and the
--   founding event it writes are its own; no price, no stock and no roll is read): one matrix of the rate (the city held by her
--   country, by another, by none; the economy open and closed; a mayor's rate set and not; the race off; the purses dark) read
--   before the hunks, after them dark (equal, cell for cell) and lit: the company away from home and the city's own rate are equal
--   in every cell; the company at home pays least(what she paid, half the city's rate): less where she paid more than half, the
--   same where her country already gave her as much (never both). The dial: dark 25 % is refused (E_TAX_BAND) as before; lit 25 %
--   and 30 % are taken and served, 31 % refused.
--   Proof 207 plays it through public.profit_tax and cmd.set_tax on a founded company.
-- VERSION: 0505 (0499 to 0504 are other slices' numbers; the lead deploys in number order).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $m$
declare
  c_hunked constant text[] := array['world.tax_rate(uuid,uuid)', 'cmd.set_tax(uuid,numeric)'];
  c_new    constant text[] := array['public.tax_thirty_on()', 'public.tax_cap()', 'public.tax_home_half(uuid,uuid,numeric,numeric)'];
  c_knobs  constant text[] := array['tax_thirty_enabled', 'tax_rate_cap', 'home_tax_cut'];
  c_ua     constant uuid := '00000000-0505-4000-8000-0000000000a1';
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
  v_all0       text;
  v_b          jsonb;
  v_d          jsonb;
  v_l          jsonb;
  v_less       int := 0;
  v_same       int := 0;
  k            record;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = any (c_knobs))
     or exists (select 1 from unnest(c_new) f where to_regprocedure(f) is not null) then
    raise exception '0505 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked || array['public.home_port_of(uuid)', 'public.profit_tax(uuid,numeric,uuid)', 'cmd.assume_identity(uuid)']) f
              where to_regprocedure(f) is null)
     or not exists (select 1 from public.world_config c where c.key = 'tax_rate_max') or to_regclass('public.port_mayor') is null then
    raise exception '0505 refuses: the profit tax (0122), the mayor (0147) or the home (0288) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0505 (fn text primary key, def text) on commit drop;
  insert into pre_0505 select f, replace(pg_get_functiondef(f::regprocedure), E'\r', '') from unnest(c_hunked) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;
  -- every harbour's rate as it is served now (no company): what must not move
  select md5(string_agg(h.code || ':' || world.tax_rate(h.id)::text, ',' order by h.code)) into v_all0 from public.ports h where h.kind = 'HARBOUR';

  -- ── 2. THE SCENE (a temp function; every row it writes is its own: a SEA_PLACE no country holds and no mayor has) ──
  --    Answers {m: {cell: [the city's rate, the company at HOME there, a company of the same country away from home]},
  --             set25, set30, set31, served: the rate served after a 25 % press}.
  execute $f$
create function pg_temp.scene_0505(p_uid uuid, p_lit boolean)
returns jsonb
language plpgsql
as $body$
declare
  v_port uuid;
  v_code text;
  v_n1   uuid;
  v_n2   uuid;
  v_a    uuid;
  v_b    uuid;
  v_m    jsonb := '{}'::jsonb;
  v_s25  jsonb;
  v_s30  jsonb;
  v_s31  jsonb;
  v_srv  numeric;
  c      record;
begin
  select q.id, q.code into v_port, v_code from public.ports q
   where q.kind = 'SEA_PLACE'
     and not exists (select 1 from public.port_allegiance a where a.port_id = q.id)
     and not exists (select 1 from public.port_mayor pm where pm.port_id = q.id)
   order by q.code limit 1;
  select g.nation_id into v_n1 from public.great_powers g where not g.pirate order by g.nation_id limit 1;
  select g.nation_id into v_n2 from public.great_powers g where not g.pirate and g.nation_id <> v_n1 order by g.nation_id limit 1;
  if v_port is null or v_n2 is null then
    raise exception '0505 self-assert FAIL: no sea place without a holder and a mayor, or no two countries, to stand the scene on';
  end if;
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values (p_uid, 'Probe 0505 a', v_n1, 0, false) returning id into v_a;
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Probe 0505 b', v_n1, 0, false) returning id into v_b;
  perform public.emit_event(v_a, 'FOUNDED', jsonb_build_object('port', v_code));   -- a's home is the scene's city; b has none
  if public.home_port_of(v_a) is distinct from v_port or public.home_port_of(v_b) is not null then
    raise exception '0505 self-assert FAIL: the probe''s home is not the scene''s city';
  end if;
  insert into public.port_allegiance (port_id, nation_id, home) values (v_port, null, false);
  insert into public.port_mayor (port_id, player_id) values (v_port, v_a);
  update public.world_config set value = 'false'::jsonb where key = 'pirate_ports_free';
  if p_lit then
    update public.world_config set value = 'true'::jsonb where key = 'tax_thirty_enabled';
  end if;

  for c in
    select t.on_ as treasury, i.on_ as race, e.on_ as closed, h.who as holder, r.rate as mayor
      from (values (true), (false)) t(on_), (values (true), (false)) i(on_), (values (false), (true)) e(on_),
           (values ('own'), ('other'), ('none')) h(who), (values (null::numeric), (0.30), (0.10)) r(rate)
     where (t.on_ and i.on_) or (h.who = 'other' and r.rate is null and not e.on_)   -- the whole matrix lit; one cell each with the race off, the purses dark
  loop
    update public.world_config set value = to_jsonb(c.treasury) where key = 'city_treasury_enabled';
    update public.world_config set value = to_jsonb(c.race) where key = 'influence_enabled';
    update public.world_config set value = to_jsonb(c.closed) where key = 'economy_closed';
    update public.port_allegiance set nation_id = case c.holder when 'own' then v_n1 when 'other' then v_n2 end where port_id = v_port;
    update public.port_mayor set tax_rate = c.mayor where port_id = v_port;
    v_m := v_m || jsonb_build_object(
      format('%s/%s/%s/%s/%s', case when c.treasury then 'lit' else 'dark' end, case when c.race then 'race' else 'norace' end,
             case when c.closed then 'closed' else 'open' end, c.holder, coalesce(c.mayor::text, '-')),
      jsonb_build_array(world.tax_rate(v_port), world.tax_rate(v_port, v_a), world.tax_rate(v_port, v_b)));
  end loop;

  -- THE DIAL, pressed by the mayor herself through the door
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'influence_enabled');
  update public.world_config set value = 'false'::jsonb where key = 'economy_closed';
  update public.port_allegiance set nation_id = null where port_id = v_port;
  update public.port_mayor set tax_rate = null, tax_set_at = null where port_id = v_port;
  perform cmd.assume_identity(p_uid);
  v_s25 := cmd.set_tax(v_port, 0.25);
  v_srv := world.tax_rate(v_port);
  update public.port_mayor set tax_set_at = null where port_id = v_port;
  v_s31 := cmd.set_tax(v_port, 0.31);
  v_s30 := cmd.set_tax(v_port, 0.30);
  return jsonb_build_object('m', v_m, 'set25', jsonb_build_array(v_s25->'ok', v_s25->'error_code'), 'set30', jsonb_build_array(v_s30->'ok', v_s30->'error_code'),
                            'set31', jsonb_build_array(v_s31->'ok', v_s31->'error_code'), 'served', v_srv,
                            'all', (select md5(string_agg(h.code || ':' || world.tax_rate(h.id)::text, ',' order by h.code)) from public.ports h where h.kind = 'HARBOUR'));
end
$body$
  $f$;

  begin
    raise exception using errcode = 'ZX505', message = pg_temp.scene_0505(c_ua, false)::text;
  exception when sqlstate 'ZX505' then v_b := sqlerrm::jsonb;
  end;
  if v_b->'set25' <> '[false, "E_TAX_BAND"]'::jsonb or v_b->'set30' <> '[false, "E_TAX_BAND"]'::jsonb
     or (select count(*) from jsonb_object_keys(v_b->'m')) <> 21 then
    raise exception '0505 self-assert FAIL: before the hunks the dial took more than 20 %%, or the matrix is not whole: %', left(v_b::text, 600);
  end if;

  -- ── 3. THE KNOBS (this file's own; the owner's switch dark) ──
  insert into public.world_config (key, value, description) values
    ('tax_thirty_enabled', 'false'::jsonb,
     '0505: THE SWITCH (the owner''s). true: a mayor may set her city''s profit tax from 0 to tax_rate_cap (30 %) (cmd.set_tax, public.tax_cap), and a company pays at most (1 - home_tax_cut) of the city''s rate in the city that is her home (public.home_port_of; world.tax_rate, public.tax_home_half): the better of that and what her country''s standing gives her, never both. false: the dial stops at tax_rate_max and home gives nothing, as before. No city''s own rate moves either way.'),
    ('tax_rate_cap', to_jsonb(0.30),
     '0505: the most a mayor may set as her city''s profit tax while tax_thirty_enabled is lit (the owner: 0 to 30 %). A city''s own column rate still stops at tax_rate_max.'),
    ('home_tax_cut', to_jsonb(0.5),
     '0505: the share of a city''s profit tax a company is spared in the city that is her home, while tax_thirty_enabled is lit. Not added to her country''s cut: she pays the lower of the two.');

  -- ── 4. THE RULES ──
  execute $f$
create function public.tax_thirty_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0505: THE SWITCH, read once: world_config tax_thirty_enabled.
  select public.wc('tax_thirty_enabled') = 'true'::jsonb
$body$
  $f$;

  execute $f$
create function public.tax_cap()
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0505: THE MOST A MAYOR MAY SET (cmd.set_tax's upper bound): tax_rate_cap (30 %) while tax_thirty_enabled is lit, else tax_rate_max, as before.
  select case when public.tax_thirty_on() then public.wc_num('tax_rate_cap') else public.wc_num('tax_rate_max') end
$body$
  $f$;

  execute $f$
create function public.tax_home_half(p_port uuid, p_player uuid, p_rate numeric, p_city numeric)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0505: HOME PAYS HALF. world.tax_rate hands every answer that knows the city's rate through here: p_rate is what the company pays by
-- today's rule (her country's standing included), p_city the city's own rate (its column's, or its mayor's). Lit, in the city that is
-- her home (public.home_port_of, 0288), she pays the LOWER of p_rate and (1 - home_tax_cut) x p_city: the better of the two cuts, never
-- one on top of the other. Dark, with no company, or away from home: p_rate, untouched.
begin
  if p_player is null or not public.tax_thirty_on() then
    return p_rate;
  end if;
  if public.home_port_of(p_player) is distinct from p_port then
    return p_rate;
  end if;
  return least(p_rate, p_city * (1 - public.wc_num('home_tax_cut')));
end
$body$
  $f$;

  foreach v_def in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_def::regprocedure);
  end loop;

  -- ── 5. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0505 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0505 values
  ('world.tax_rate(uuid,uuid)', 1,
$h$  if not public.influence_on() then
    return v_base;
  end if;
$h$,
$h$  if not public.influence_on() then
    return public.tax_home_half(p_port, p_player, v_base, v_base);   -- 0505 (dark: tax_thirty_enabled): lit, her home city asks half
  end if;
$h$),
  ('world.tax_rate(uuid,uuid)', 2,
$h$    return least(v_base * public.country_factor(v_stance) * public.regard_factor(p_player, p_port), greatest(v_base, public.wc_num('tariff_rate_max')));
$h$,
$h$    return public.tax_home_half(p_port, p_player,   -- 0505 (dark: tax_thirty_enabled): lit, at her home the lower of this and half the city's rate
             least(v_base * public.country_factor(v_stance) * public.regard_factor(p_player, p_port), greatest(v_base, public.wc_num('tariff_rate_max'))), v_base);
$h$),
  ('world.tax_rate(uuid,uuid)', 3,
$h$    return v_base * (1 - public.wc_num('influence_citizen_tax_cut'));
$h$,
$h$    return public.tax_home_half(p_port, p_player, v_base * (1 - public.wc_num('influence_citizen_tax_cut')), v_base);   -- 0505: never both cuts
$h$),
  ('world.tax_rate(uuid,uuid)', 4,
$h$  return least(v_base * public.stance_mult(v_stance), greatest(v_base, public.wc_num('tariff_rate_max')));
$h$,
$h$  return public.tax_home_half(p_port, p_player,   -- 0505 (dark: tax_thirty_enabled)
           least(v_base * public.stance_mult(v_stance), greatest(v_base, public.wc_num('tariff_rate_max'))), v_base);
$h$),
  ('cmd.set_tax(uuid,numeric)', 1,
$h$    if p_rate is null or p_rate < 0 or p_rate > public.wc_num('tax_rate_max') then
      perform cmd.refuse('E_TAX_BAND', format('the tax is between 0%% and %s%% of the profit',
                                              round(public.wc_num('tax_rate_max') * 100)));
$h$,
$h$    -- 0505 (dark: tax_thirty_enabled): the upper bound is public.tax_cap(): the old 20 % cap as before, 30 % when lit
    if p_rate is null or p_rate < 0 or p_rate > public.tax_cap() then
      perform cmd.refuse('E_TAX_BAND', format('the tax is between 0%% and %s%% of the profit',
                                              round(public.tax_cap() * 100)));
$h$);

  for x in select distinct h.fn from hunks_0505 h loop
    v_pre := (select p.def from pre_0505 p where p.fn = x.fn);
    v_def := v_pre;
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0505 h where h.fn = x.fn order by h.ord loop
      if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
        raise exception '0505 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', v_n, x.fn,
          (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
      end if;
      v_def := replace(v_def, v_old, v_new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(x.fn::regprocedure), E'\r', '');
    for v_old, v_new, v_n in select h.old, h.new, h.ord from hunks_0505 h where h.fn = x.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new) <> 1 then
        raise exception '0505 self-assert FAIL: hunk % of % is not in the new body once', v_n, x.fn;
      end if;
      v_def := replace(v_def, v_new, v_old);
    end loop;
    if v_def <> v_pre then
      raise exception '0505 self-assert FAIL: % does not reverse to its pre-image', x.fn;
    end if;
  end loop;
  if (select count(*) from hunks_0505) <> 5 then
    raise exception '0505 self-assert FAIL: the hunks are not the 5 of the two re-cut bodies';
  end if;
  if position('wc_num(''tax_rate_max'')' in pg_get_functiondef('cmd.set_tax(uuid,numeric)'::regprocedure)) > 0 then
    raise exception '0505 self-assert FAIL: cmd.set_tax still reads the old cap itself';
  end if;

  -- ── 6. THE SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0505 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0505 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before
     or public.tax_thirty_on() or public.tax_cap() <> public.wc_num('tax_rate_max') then
    raise exception '0505 self-assert FAIL: a knob of another file moved, or the switch is not false';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('anon', u.q::regprocedure, 'execute') or has_function_privilege('authenticated', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute') or has_function_privilege('public', u.q::regprocedure, 'execute')
                 or (select p.provolatile from pg_proc p where p.oid = u.q::regprocedure) <> 's') then
    raise exception '0505 self-assert FAIL: a new function is reachable by a client or service_role, or is not STABLE';
  end if;
  if (select md5(string_agg(h.code || ':' || world.tax_rate(h.id)::text, ',' order by h.code)) from public.ports h where h.kind = 'HARBOUR') <> v_all0 then
    raise exception '0505 self-assert FAIL: a harbour''s rate moved at deploy';
  end if;

  -- ── 7. DARK IDENTITY, then LIT ──
  begin
    raise exception using errcode = 'ZX505', message = pg_temp.scene_0505(c_ua, false)::text;
  exception when sqlstate 'ZX505' then v_d := sqlerrm::jsonb;
  end;
  if v_d is distinct from v_b then
    raise exception '0505 self-assert FAIL: DARK IS NOT IDENTICAL. Before: % After: %', left(v_b::text, 900), left(v_d::text, 900);
  end if;
  begin
    raise exception using errcode = 'ZX505', message = pg_temp.scene_0505(c_ua, true)::text;
  exception when sqlstate 'ZX505' then v_l := sqlerrm::jsonb;
  end;
  drop function pg_temp.scene_0505(uuid, boolean);

  -- no harbour's rate moves at the light either
  -- (read inside the scene, with the purses and the race lit there: the same reading before the hunks and lit)
  if v_l->>'all' is null or v_l->>'all' is distinct from v_b->>'all' then
    raise exception '0505 self-assert FAIL: a harbour''s rate moved when the switch was lit';
  end if;
  for k in select e.key as cell, e.value as was, v_l->'m'->e.key as now from jsonb_each(v_b->'m') e loop
    -- the city's own rate, and a company away from home: nothing moves, in any cell
    if k.now->0 is distinct from k.was->0 or k.now->2 is distinct from k.was->2 then
      raise exception '0505 self-assert FAIL: lit, the city''s rate or a company away from home moved in %: % -> %', k.cell, k.was, k.now;
    end if;
    -- the company at home: the lower of what she paid and half the city's rate (the purses dark: the old turnover column, untouched)
    if (k.now->>1)::numeric <> (case when k.cell like 'dark/%' then (k.was->>1)::numeric
                                     else least((k.was->>1)::numeric, (k.was->>0)::numeric * 0.5) end) then
      raise exception '0505 self-assert FAIL: lit, home did not pay the lower of today''s rate and half in %: % -> %', k.cell, k.was, k.now;
    end if;
    if (k.now->>1)::numeric < (k.was->>1)::numeric then v_less := v_less + 1; else v_same := v_same + 1; end if;
  end loop;
  -- both things happened: home lowered a rate somewhere, and somewhere her country had already given as much (never both)
  if v_less < 4 or v_same < 4
     or (v_l #>> '{m,lit/race/open/none/0.30,1}')::numeric <> 0.15 or (v_l #>> '{m,lit/race/open/none/0.30,0}')::numeric <> 0.30
     or (v_l #>> '{m,lit/race/open/own/0.30,1}')::numeric <> 0.15 or (v_b #>> '{m,lit/race/open/own/0.30,1}')::numeric <> 0.15
     or (v_l #>> '{m,lit/norace/open/other/-,1}')::numeric <> (v_b #>> '{m,lit/norace/open/other/-,0}')::numeric * 0.5 then
    raise exception '0505 self-assert FAIL: the home half is not the better of the two cuts (% lowered, % unchanged): %', v_less, v_same, left((v_l->'m')::text, 900);
  end if;
  -- THE DIAL: lit, 25 % and 30 % are taken and served; 31 % is refused
  if v_l->'set25' <> '[true, null]'::jsonb or v_l->'set30' <> '[true, null]'::jsonb or v_l->'set31' <> '[false, "E_TAX_BAND"]'::jsonb
     or (v_l->>'served')::numeric <> 0.25 then
    raise exception '0505 self-assert FAIL: lit, the mayor''s dial is not 0 to 30 %%: %', v_l - 'm';
  end if;

  -- ── 8. NOTHING OF THE PROBE SURVIVES; the switch is dark ──
  if exists (select 1 from public.players p where p.company_name like 'Probe 0505 %')
     or exists (select 1 from public.port_mayor pm join public.ports q on q.id = pm.port_id where q.kind = 'SEA_PLACE')
     or exists (select 1 from public.port_allegiance a join public.ports q on q.id = a.port_id where q.kind = 'SEA_PLACE')
     or public.tax_thirty_on()
     or (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
           from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before then
    raise exception '0505 self-assert FAIL: the probe left rows behind, or a knob moved';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0505 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0505 self-assert ok: EACH CITY SETS ITS TAX, 0 TO 30 %%, AND HOME PAYS HALF (dark). 5 hunks once and reversing (world.tax_rate x4, cmd.set_tax x1); no other function moved; grants and settings unmoved; three new functions STABLE and server only; knobs tax_thirty_enabled false, tax_rate_cap 0.30, home_tax_cut 0.5; no other knob moved. NO RATE MOVES: every harbour''s rate equal before, after and lit. DARK IDENTICAL: 21 cells of the rate and the dial, equal. LIT: the city''s rate and a company away from home equal in all 21 cells; the company at home pays the lower of today''s rate and half the city''s (% cells lowered, % unchanged: never both cuts); a mayor''s 30 %% -> 15 %% at home; the dial takes 25 %% and 30 %%, refuses 31 %%. % ms.',
    v_less, v_same, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0505;
  drop table pre_0505;
end $m$;
