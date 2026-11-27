-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: no HQ can be opened while hq_cities_enabled is false, and every step is unset)
-- 0512 - HQ CITIES  (dark twice: 0509's hq_cities_enabled is false, and the owner has set no step of public.hq_steps)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25: "BY TOTAl level, gold, reputation etc." (answer 4); "The specific requirement will be set by me after reviewing all the contents that has been
--   made." (R2); "HQ can be assigned on any city. It can be assigned in any country anywhere." (slide 1). The HQ of a company (row 1), the list and the switching are 0509's.
-- WHAT:
--   public.hq_steps              slots 2 to 5 are set to NULL (0509's placeholders were never approved): an unset step refuses "HQ 2 is not set yet.". The owner fills them.
--   public.hq_perks              slide 2's perks as EMPTY data (PROPOSED: no rule reads it, no kind and no number is in it).
--   public.total_level           the sum of a company's counted levels, as the levels page counts them (public.level_skills_card).
--   public.hq_open_refusal       WHY SHE CANNOT OPEN AN HQ THERE NOW, in plain words, in order (one reader: the read and the door): not open yet; not a harbour; hers already;
--                                all five; the step not set; a fleet of hers in port there; the sea (public.sea_refusal, asked plainly of that fleet, while the seas bite);
--                                total level; gold; Reputation. Null: she can.
--   cmd.open_hq(port)            THE DOOR: the caller's own company. Gold by public.pay_city (kind HQ, into the NEW HQ's city), Reputation by public.reputation_credit
--                                (kind hq), one row of company_hqs, one event HQ_OPENED; all or nothing.
--   world.hq_open(port)          the read before the press: the next slot, whether it is set, each need with have / need, and the refusal.
--   public.hq_card (1 hunk)      lit, each HQ of the list carries the shed there {cap, used} (public.storage_cap, public.storage_used: goods stored in a city ARE that HQ's warehouse).
--   public.hq_at(player, port)   IS THIS CITY HOME FOR HER? Her home (public.home_port_of, 0509), or, lit, any HQ of hers. Read by tax_home_half, request_place, world.requests.
--   public.fleet_job_end (1)     lit, a bring-home job may name an HQ (`home`); none named: home, as it was.
-- WHAT "HOME" MEANS (the table with the reasons: docs/dev-log/2026-11-25-hq-cities.md): half tax and requests: any HQ; bring home: the HQ named, else slot 1; land party,
--   near round, the first charted point, a closed company's heir: slot 1; pass home and home waters (0396, 0513): her country's capital, NOT the HQ; dividends: no home at all.
-- NOTHING MOVES A LIVE COMPANY'S HOME: home_port_of is not touched; the switch stays false until the owner has seen before-0509's moves_home.
-- THE COIN: HQ is a moved flow (public.stats_flow_words), no profit of a city's (public.flow_is_profit: capital, as SHARE; no influence), a one-time line of the rate.
-- A NEW COMPANY IS OF EUROPE (no switch; the owner: "you will choose your home COUNTRY (EUROPE)"): cmd.found_house (2 hunks) refuses any other, E_NOT_EUROPE, by 0509's
--   one rule (public.nation_in_europe); world.snapshot (1 hunk) serves each country's `foundable` for the picker. Companies already of another country, and
--   cmd.change_country, are as they were. The skull is not of Europe: a new company no longer starts under it, and may change to it.
-- ROWS: hq_steps and kinds: seven rows of data. An open HQ: one row of company_hqs, one each of ledger, flow, event and Reputation. 0 a minute.
-- retention: none, bounded by one row a perk kind, data only a migration writes (public.hq_perks)
-- budget: no cron job, no autovacuum or fillfactor change. Tick: 0. world.player while dark: one knob read more.
-- LOCKS: ALTER TABLE hq_steps (5 rows); CREATE TABLE x1; CREATE FUNCTION x5; hunks x11 bodies. TIME: a second. BUDGET: statement_timeout 90 s, lock_timeout 5 s; fails above 45 s.
-- ROLLBACK (forward, owner only): QUICK, hq_cities_enabled false (it is). FULL: the hunks reversed, the functions and hq_perks dropped; an HQ opened stays a row.
-- SELF-ASSERT: each hunk once and reversing; no other function or knob moved; the door and the read for authenticated alone; every step past the first unset; the perks empty;
--   home_port_of, the tax and the job end answer as before; THE PROBE (rolled back; its own company, the switch, a step, levels 0 and a purse planted): dark and unset refuse in
--   words; set and met, HQ 2 opens once, its gold in its city's purse, its Reputation spent, home still slot 1.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['cmd.found_house(text,text)', 'world.snapshot()', 'public.hq_card(uuid)', 'public.tax_home_half(uuid,uuid,numeric,numeric)', 'cmd.request_place(uuid,uuid,numeric,bigint)', 'world.requests(uuid)', 'public.fleet_job_end(uuid,jsonb)', 'public.flow_is_profit(text)', 'public.company_rate_line(text)', 'public.client_rpc_entry_points()']::text[];
  c_new    constant text[] := array['public.total_level(uuid)', 'public.hq_at(uuid,uuid)', 'public.hq_open_refusal(uuid,uuid)', 'world.hq_open(text)', 'cmd.open_hq(text)']::text[];
  c_gone   constant text[] := array[]::text[];   -- dropped and made again with more to answer (the same arguments)
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_cfg_before text;
  v_lived     boolean := false;
  v_note      text := '';
  v_me   uuid;
  v_fl   uuid;
  v_lis  uuid;
  v_lon  uuid;
  v_r    jsonb;
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from unnest(c_new) u(q) where to_regprocedure(u.q) is not null and not (u.q = any (c_gone))) then
    raise exception '0512 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked || c_gone) u(q) where to_regprocedure(u.q) is null) then
    raise exception '0512 refuses: a function it cuts is not in this world: %', (select string_agg(u.q, ' ') from unnest(c_hunked || c_gone) u(q) where to_regprocedure(u.q) is null);
  end if;


  -- ── 1. THE PRE-IMAGES ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_gone) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE RULES ──
  alter table public.hq_steps alter column total_level drop not null;
  alter table public.hq_steps alter column ducats drop not null;
  alter table public.hq_steps alter column reputation drop not null;
  update public.hq_steps set total_level = null, ducats = null, reputation = null where slot > 1;
  comment on table public.hq_steps is '0509, 0512: what HQ slot n asks: total level, coin to the new city, Reputation. NULL: the owner has not set it, and the slot cannot be opened.';
  -- retention: none, bounded by one row a perk kind (hq_perks)
  create table public.hq_perks (code text primary key, note text not null default '');
  alter table public.hq_perks enable row level security;
  revoke all on public.hq_perks from public, anon, authenticated, service_role;
  comment on table public.hq_perks is '0512: the city perks of slide 2, PROPOSED: empty, and read by nothing, until the owner sets their kinds and numbers.';
  insert into public.reputation_kinds (code, sign, word, capped) values ('hq', -1, 'HQ opened', false);
  insert into public.stats_flow_words (kind, side, word, ord) select 'HQ', 'moved', 'HQs opened', coalesce(max(w.ord), 0) + 1 from public.stats_flow_words w;
  execute $f$
create function public.total_level(p_player uuid)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0512: TOTAL LEVEL: the sum of her counted levels, as the levels page counts them (public.level_skills_card: what a switch still hides is not in it). A merchant: null.
  select case when exists (select 1 from public.players p where p.id = p_player and not p.is_npc) then
           (select coalesce(sum((s->>'level')::int) filter (where (s->>'counted')::boolean), 0)::int
              from jsonb_array_elements(public.level_skills_card(p_player, public.player_progress(p_player))->'skills') s) end
$body$
  $f$;
  revoke all on function public.total_level(uuid) from public, anon, authenticated, service_role;
  comment on function public.total_level(uuid) is
    '0512: the sum of a company''s counted levels. Server only.';
  execute $f$
create function public.hq_at(p_player uuid, p_port uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0512: IS THIS CITY HOME FOR HER? Her home (public.home_port_of); lit (hq_cities_enabled), any of her HQs. Dark: home alone, as before 0512.
  select coalesce(public.home_port_of(p_player) = p_port, false)
         or (public.hq_cities_on() and exists (select 1 from public.company_hqs h where h.player_id = p_player and h.port_id = p_port))
$body$
  $f$;
  revoke all on function public.hq_at(uuid, uuid) from public, anon, authenticated, service_role;
  comment on function public.hq_at(uuid, uuid) is
    '0512: whether a city is home to a company: her home, or lit any of her HQs. Server only.';
  execute $f$
create function public.hq_open_refusal(p_player uuid, p_port uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0512: WHY SHE CANNOT OPEN AN HQ IN THIS CITY NOW (cmd.refusal's shape), the first reason in order; null: she can. The one reader, of world.hq_open and the door. Writes nothing.
declare
  v_slot int;
  s      public.hq_steps%rowtype;
  v_code text := (select p.code from public.ports p where p.id = p_port and p.kind = 'HARBOUR');
  v_name text := (select p.name from public.ports p where p.id = p_port);
  v_fl   uuid;
  v_bad  jsonb;
  v_have numeric;
begin
  if not public.hq_cities_on() then
    return cmd.refusal('E_NOT_IN_USE', 'Opening an HQ is not in use yet.');
  end if;
  if v_code is null then
    return cmd.refusal('E_NO_SUCH_PORT', 'An HQ is opened in a harbour.');
  end if;
  if exists (select 1 from public.company_hqs h where h.player_id = p_player and h.port_id = p_port) then
    return cmd.refusal('E_HQ_HERE', format('You have an HQ in %s already.', v_name));
  end if;
  v_slot := (select coalesce(max(h.slot), 0) + 1 from public.company_hqs h where h.player_id = p_player);
  select x.* into s from public.hq_steps x where x.slot = v_slot;
  if s.slot is null then
    return cmd.refusal('E_HQ_TOP', 'You have every HQ a company may have.');
  end if;
  if s.total_level is null or s.ducats is null or s.reputation is null then
    return cmd.refusal('E_HQ_NOT_SET', format('HQ %s is not set yet.', v_slot));
  end if;
  -- a fleet of hers in port there (0448's one reading of a fleet's state), the strongest hull first
  select f.id into v_fl from public.fleets f
   where f.player_id = p_player and f.port_id = p_port and (select c.state from public.fleet_census(f.id) c) = 'port'
   order by public.fleet_wave(f.id) desc nulls last, f.id limit 1;
  if v_fl is null then
    return cmd.refusal('E_NO_FLEET_HERE', format('Bring a fleet to %s first.', v_name));
  end if;
  if public.sea_conditions_on() then
    if to_regprocedure('public.fleet_sea_stats(uuid)') is null then   -- before 0525 the rule asks level and wave alone
      v_bad := public.sea_refusal(public.title_level(p_player), public.fleet_wave(v_fl), array_remove(array[public.harbour_zone(p_port)], null));
    else
      v_bad := public.sea_refusal(public.title_level(p_player), public.fleet_wave(v_fl), array_remove(array[public.harbour_zone(p_port)], null), public.fleet_sea_stats(v_fl));
    end if;
    if v_bad is not null then
      return v_bad;
    end if;
  end if;
  v_have := public.total_level(p_player);
  if v_have < s.total_level then
    return cmd.refusal('E_HQ_LEVEL', format('HQ %s asks total level %s and you have %s.', v_slot, s.total_level, v_have), cmd.figures(v_have, s.total_level, 'level'));
  end if;
  v_have := (select p.ducats from public.players p where p.id = p_player);
  if v_have < s.ducats then
    return cmd.refusal('E_INSUFFICIENT_FUNDS', format('HQ %s costs %s and you have %s.', v_slot, s.ducats, v_have), cmd.figures(v_have, s.ducats, 'ducats'));
  end if;
  v_have := coalesce((select b.balance from public.reputation_balance b where b.player_id = p_player), 0);
  if v_have < s.reputation then
    return cmd.refusal('E_NOT_ENOUGH_REPUTATION', format('HQ %s asks %s Reputation and you have %s.', v_slot, s.reputation, v_have), cmd.figures(v_have, s.reputation, 'reputation'));
  end if;
  if s.reputation > 0 and public.wc('reputation_on') is distinct from 'true'::jsonb then
    return cmd.refusal('E_NOT_IN_USE', 'Reputation is not in use yet.');
  end if;
  return null;
end
$body$
  $f$;
  revoke all on function public.hq_open_refusal(uuid, uuid) from public, anon, authenticated, service_role;
  comment on function public.hq_open_refusal(uuid, uuid) is
    '0512: why a company cannot open an HQ in a city now, in plain words; null: she can. Server only.';
  execute $f$
create function world.hq_open(p_port text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0512: THE READ BEFORE OPENING AN HQ: the next slot, whether the owner has set it, each need with what she has, the refusal (null: she may press). Dark: {on: false}.
declare
  v_p    uuid := public.current_player_id();
  v_port uuid := (select p.id from public.ports p where p.code = upper(btrim(coalesce(p_port, ''))));
  v_slot int;
  s      public.hq_steps%rowtype;
begin
  if v_p is null or not public.hq_cities_on() then
    return jsonb_build_object('on', false);
  end if;
  v_slot := (select coalesce(max(h.slot), 0) + 1 from public.company_hqs h where h.player_id = v_p);
  select x.* into s from public.hq_steps x where x.slot = v_slot;
  return jsonb_build_object('on', true, 'slot', s.slot, 'set', s.total_level is not null and s.ducats is not null and s.reputation is not null,
    'needs', jsonb_build_object('level', jsonb_build_object('have', public.total_level(v_p), 'need', s.total_level),
                                'ducats', jsonb_build_object('have', (select p.ducats from public.players p where p.id = v_p), 'need', s.ducats),
                                'reputation', jsonb_build_object('have', coalesce((select b.balance from public.reputation_balance b where b.player_id = v_p), 0), 'need', s.reputation)),
    'refusal', public.hq_open_refusal(v_p, v_port));
end
$body$
  $f$;
  revoke all on function world.hq_open(text) from public, anon, authenticated, service_role;
  comment on function world.hq_open(text) is
    '0512: what opening an HQ in a city asks of the callers company, and why not. Dark: {on: false}.';
  execute $f$
create function cmd.open_hq(p_port text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $body$
-- 0512: OPEN AN HQ in the city named, for the caller's own company (no player id). The company's row first, so two presses cannot open one slot twice. All or nothing.
declare
  v_player uuid := public.current_player_id();
  v_port   uuid := (select p.id from public.ports p where p.code = upper(btrim(coalesce(p_port, ''))));
  s        public.hq_steps%rowtype;
  v_bad    jsonb;
  v_ev     uuid;
  v_after  bigint;
  v_det    text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE', 'error_message', 'Found a company first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    perform 1 from public.players p where p.id = v_player for update;
    v_bad := public.hq_open_refusal(v_player, v_port);
    if v_bad is not null then
      perform cmd.refuse(v_bad);
    end if;
    select x.* into s from public.hq_steps x where x.slot = (select coalesce(max(h.slot), 0) + 1 from public.company_hqs h where h.player_id = v_player);
    v_ev := public.emit_event(v_player, 'HQ_OPENED', jsonb_build_object('port', upper(btrim(p_port)), 'slot', s.slot, 'ducats', s.ducats, 'reputation', s.reputation));
    v_after := (select p.ducats from public.players p where p.id = v_player);
    if s.ducats > 0 then
      v_after := public.pay_city(v_player, v_port, 'HQ', s.ducats, v_ev);
    end if;
    if s.reputation > 0 and public.reputation_credit(v_player, 'hq', -s.reputation, 'hq:' || s.slot, jsonb_build_object('port', upper(btrim(p_port)))) <> -s.reputation then
      perform cmd.refuse('E_NOT_ENOUGH_REPUTATION', 'The Reputation could not be spent.');
    end if;
    insert into public.company_hqs (player_id, slot, port_id) values (v_player, s.slot, v_port);
    return jsonb_build_object('ok', true, 'slot', s.slot, 'port', upper(btrim(p_port)), 'purse', v_after, 'hq', public.hq_card(v_player));
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end
$body$
  $f$;
  revoke all on function cmd.open_hq(text) from public, anon, authenticated, service_role;
  comment on function cmd.open_hq(text) is
    '0512: opens the caller''s next HQ in a city: gold to that city, Reputation spent. Dark: E_NOT_IN_USE.';

  grant execute on function world.hq_open(text) to authenticated;
  grant execute on function cmd.open_hq(text) to authenticated;

  -- ── 3. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0512 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0512 values
  ('public.hq_card(uuid)', 1,
$h$jsonb_build_object('slot', h.slot, 'port', p.code, 'since', h.opened_at) order by h.slot)$h$,
$h$jsonb_build_object('slot', h.slot, 'port', p.code, 'since', h.opened_at)
                               -- 0512: lit, her warehouse there: what is in her shed in that city
                               || case when public.hq_cities_on() then jsonb_build_object('warehouse', jsonb_build_object('cap', public.storage_cap(p.id), 'used', public.storage_used(p_player, p.id))) else '{}'::jsonb end order by h.slot)$h$),
  ('cmd.found_house(text,text)', 1,
$h$where public.nation_joinable(id)));   -- GP1$h$,
$h$where public.nation_joinable(id) and public.nation_in_europe(id)));   -- 0512: and of Europe; GP1$h$),
  ('cmd.found_house(text,text)', 2,
$h$where public.nation_joinable(id)));
  end if;

  -- 0503: THE NAME'S RULE$h$,
$h$where public.nation_joinable(id) and public.nation_in_europe(id)));
  end if;

  -- 0512: A NEW COMPANY'S COUNTRY IS ONE OF EUROPE (public.nation_in_europe, 0509's one rule, as Restart asks it). A company of another country is not asked.
  if not public.nation_in_europe((select id from public.nations where code = v_nation)) then
    return jsonb_build_object(
      'ok', false, 'error_code', 'E_NOT_EUROPE', 'error_message', 'Choose a country of Europe.',
      'fixes', (select jsonb_agg(format('(sail under %s — %s)', code, name) order by code)
                  from public.nations where public.nation_joinable(id) and public.nation_in_europe(id)));
  end if;

  -- 0503: THE NAME'S RULE$h$),
  ('world.snapshot()', 1,
$h$        'joinable', public.nation_joinable(n.id),$h$,
$h$        'foundable', public.nation_joinable(n.id) and public.nation_in_europe(n.id),   -- 0512: a new company may choose it (cmd.found_house)
        'joinable', public.nation_joinable(n.id),$h$),
  ('public.tax_home_half(uuid,uuid,numeric,numeric)', 1,
$h$  if public.home_port_of(p_player) is distinct from p_port then
$h$,
$h$  if not public.hq_at(p_player, p_port) then   -- 0512: home, or lit any HQ of hers
$h$),
  ('cmd.request_place(uuid,uuid,numeric,bigint)', 1,
$h$    if public.home_port_of(v_player) is distinct from p_port then
$h$,
$h$    if not public.hq_at(v_player, p_port) then   -- 0512: home, or lit any HQ of hers
$h$),
  ('world.requests(uuid)', 1,
$h$coalesce(public.home_port_of(v_player) = p_port, false)$h$,
$h$public.hq_at(v_player, p_port)   /* 0512 */$h$),
  ('public.fleet_job_end(uuid,jsonb)', 1,
$h$    v_home := public.home_port_of(p_player);
$h$,
$h$    -- 0512: lit, the HQ the order names (`home`, a harbour code of her list); none named: home, as it was
    if public.hq_cities_on() and p_params ? 'home' then
      v_home := (select h.port_id from public.company_hqs h join public.ports p on p.id = h.port_id where h.player_id = p_player and p.code = p_params->>'home');
    else
    v_home := public.home_port_of(p_player);
    end if;
$h$),
  ('public.flow_is_profit(text)', 1,
$h$'SHARE', 'COMPANY_CLOSED')$h$,
$h$'SHARE', 'HQ', 'COMPANY_CLOSED')$h$),
  ('public.company_rate_line(text)', 1,
$h$('SLOT', 'room', true),$h$,
$h$('SLOT', 'room', true), ('HQ', 'room', true),$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('cmd',         'restart_company',       'text, text, text'),
$h$,
$h$      ('cmd',         'restart_company',       'text, text, text'),
      -- 0512: an HQ is opened (dark: E_NOT_IN_USE), and the read before it ({on: false})
      ('cmd',         'open_hq',               'text'),
      ('world',       'hq_open',               'text'),
$h$);

  for v_h in select h.fn from hunks_0512 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0512 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0512 refuses: hunk % of % is found % times in the live body, not once', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0512 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0512 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0512 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 4. SELF-ASSERT: the catalog, the grants, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0512 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0512 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where (has_function_privilege('authenticated', u.q::regprocedure, 'execute') <> (u.q = any (array['world.hq_open(text)', 'cmd.open_hq(text)'])))
                 or has_function_privilege('anon', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute'))
     or (select count(*) from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_new) u(q))) and p.prosecdef
                                          and p.provolatile = case when p.proname = 'open_hq' then 'v' else 's' end) <> cardinality(c_new)
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0512 self-assert FAIL: a new function is reachable by a client or service_role, or is not of its declared kind';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c
       where c.key <> all (array[]::text[])) <> v_cfg_before then
    raise exception '0512 self-assert FAIL: a knob this file does not add moved';
  end if;

  -- ── 5. EVERY STEP UNSET, THE PERKS EMPTY ──
  if exists (select 1 from public.hq_steps s where s.slot > 1 and (s.total_level is not null or s.ducats is not null or s.reputation is not null))
     or (select count(*) from public.hq_steps) <> 5 or exists (select 1 from public.hq_perks) then
    raise exception '0512 self-assert FAIL: a step is set, or a perk is there';
  end if;
  if (select md5(coalesce(string_agg(p.id::text || ':' || coalesce(public.home_port_of(p.id)::text, '') || ':' || coalesce(public.hq_at(p.id, public.home_port_of(p.id))::text, ''), ',' order by p.id), ''))
        from public.players p where not p.is_npc)
     is distinct from (select md5(coalesce(string_agg(p.id::text || ':' || coalesce(public.home_port_of(p.id)::text, '') || ':' || (public.home_port_of(p.id) is not null)::text, ',' order by p.id), ''))
        from public.players p where not p.is_npc) then
    raise exception '0512 self-assert FAIL: dark, home is not home';
  end if;

  -- ── 6. THE PROBE (its own company; rolled back) ──
  begin
    v_me := public.new_house('00000000-0512-4000-8000-000000000001', 'Casa das Sedes 0512', 'PRT');
    select f.id, f.port_id into v_fl, v_lis from public.fleets f where f.player_id = v_me;
    perform cmd.assume_identity('00000000-0512-4000-8000-000000000001');
    v_lon := (select p.id from public.ports p where p.code = 'LON');
    update public.world_config set value = 'false'::jsonb where key = 'hq_cities_enabled';   -- the probe's own dark (it may be lit by now; rolled back)
    v_r := cmd.open_hq('LON');
    if v_r->>'error_code' is distinct from 'E_NOT_IN_USE' then raise exception '0512 self-assert FAIL: dark: %', v_r; end if;
    update public.world_config set value = 'true'::jsonb where key = 'hq_cities_enabled';
    update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite';
    update public.world_config set value = 'true'::jsonb where key = 'reputation_on';
    v_r := cmd.open_hq('LON');
    if v_r->>'error_code' is distinct from 'E_HQ_NOT_SET' or v_r->>'error_message' is distinct from 'HQ 2 is not set yet.' then raise exception '0512 self-assert FAIL: unset: %', v_r; end if;
    update public.hq_steps set total_level = 1, ducats = 1000, reputation = 0 where slot = 2;
    v_r := cmd.open_hq('LON');
    if v_r->>'error_code' is distinct from 'E_NO_FLEET_HERE' then raise exception '0512 self-assert FAIL: no fleet there: %', v_r; end if;
    update public.fleets set port_id = v_lon where id = v_fl;
    update public.players set ducats = 5000 where id = v_me;
    v_r := cmd.open_hq('LON');
    if (v_r->>'ok')::boolean is not true or (select ducats from public.players where id = v_me) <> 4000
       or (public.city_treasury_on() and not exists (select 1 from public.treasury_flows t where t.port_id = v_lon and t.player_id = v_me and t.kind = 'HQ' and t.ducats = 1000))
       or public.home_port_of(v_me) <> v_lis or not public.hq_at(v_me, v_lon) or cmd.open_hq('LON')->>'error_code' <> 'E_HQ_HERE' then
      raise exception '0512 self-assert FAIL: HQ 2: %', v_r;
    end if;
    v_note := 'dark, unset and no fleet there refuse in words; HQ 2 in London opened once, 1,000 in London''s purse, home still Lisbon';
    raise exception using errcode = 'ZX512', message = 'PROBE_ROLLBACK_0512';
  exception when sqlstate 'ZX512' then
    v_lived := true;
  end;
  if not v_lived or exists (select 1 from public.players p where p.company_name = 'Casa das Sedes 0512')
     or (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0512 self-assert FAIL: the probe did not run to its end, or left something behind';
  end if;

  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0512 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0512 self-assert ok: HQ CITIES (dark: the switch as found, every step past the first unset, the perks empty). Every hunk once and reversing; no other function or knob moved. Probe (rolled back): %. % ms.', v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
