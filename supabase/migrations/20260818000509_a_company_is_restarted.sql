-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: one row, public.news_update('0509', ...): HQ shows the company's own HQ city.
-- 0509 - A COMPANY IS RESTARTED, AND EVERY COMPANY HAS AN HQ  (dark: restart_enabled, hq_cities_enabled; HQ row 1 needs no switch)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25 (docs/design/owner-spec-red-2026-11-25.md R1, R2): "Right now my account does not have a designated HQ. I need
--   a way to restart the game." / "The specific requirement will be set by me after reviewing all the contents that has been made."
--   The design, with every rule: docs/dev-log/2026-11-25-restart-company.md.
--
-- WHAT:
--   public.company_hqs           THE ONE LIST of a company's HQ cities, slot 1 to 5. Slot 1 is written here for every company of a player:
--                                her country's capital; her founding port where she has no country or it has no harbour for a capital.
--                                public.new_house (1 hunk) writes it for every company founded from now on (the port she is founded in,
--                                which at cmd.found_house is her country's capital).
--   public.hq_steps              THE LADDER AS DATA (total level, coin, Reputation a slot). The plan's placeholders, NOT approved (R2).
--                                No door opens a slot: cmd.open_hq is not in this file. hq_cities_enabled false.
--   public.hq_card(player)       {at, list, next}: served in world.player (1 hunk) as `hq`. `next` is null while dark.
--   public.home_port_of          (2 hunks) lit (hq_cities_enabled) her home is HQ slot 1; dark it is what it was: the founding event's
--                                port. So no home, shed, request or land party moves with this file.
--   public.nation_in_europe      a country whose capital harbour lies in one of the eight European regions (public.regions).
--   public.players.retired_at    null: a company. Else she was closed then: no account, no country, a placeholder name.
--   public.company_retirements   one row a closed company: the account, her name and country as they were, and the receipt.
--   public.company_heir          the city her coin goes to: her country's capital, else her founding port.
--   public.restart_refusal       WHY A COMPANY CANNOT BE RESTARTED NOW, in plain words (one reader, read by the card and by the core).
--   public.company_retire        THE ONE WAY A COMPANY CLOSES. The rules a holding are in its body, in order. Never deletes a row of
--                                players, events, ledger, level_book, reputation_book, capital_gifts or treasury_flows.
--   cmd.restart_company(confirm, name, nation)   THE DOOR: the caller's own company, her name typed, closed, and a new one founded by
--                                cmd.found_house in the same transaction. Any refusal undoes all of it. Dark: E_NOT_IN_USE.
--   A CLOSED COMPANY APPEARS NOWHERE (1 hunk each): public.settle_standings, world.stats_me, world.town_hall, world.city_history,
--                                public.town_hall_gifts. Every other board already asks for an account or a country, which she has not.
--   THE COIN: public.flow_is_profit and public.ledger_is_earning (1 hunk each) know COMPANY_CLOSED: not a city's profit (it would be paid
--                                out as dividends), not a company's earning or loss. public.stats_flow_words: one row, moved.
-- THE CLOSED ECONOMY: her escrows and set-aside dividends come home to her purse, her debts to cities are paid out of it, and what is
--   left is paid to her country's capital (ledger COMPANY_CLOSED out, treasury flow COMPANY_CLOSED in, one event). Coin is moved, never
--   made or lost. The new company's starting money is cmd.found_house's own (public.founding_credit: the capital pays, closed).
-- NO COMPANY IS RESTARTED BY THIS FILE, AND NONE CAN BE WHILE restart_enabled IS false. The probe closes its own company alone.
-- ROWS: one row a company of a player (company_hqs), five (hq_steps), one a restart (at most one an account a day). 0 a minute.
-- budget: no cron job, no autovacuum or fillfactor change.
-- LOCKS: ALTER TABLE public.players ADD COLUMN (nullable, no rewrite); CREATE TABLE x3; CREATE FUNCTION x9; CREATE OR REPLACE x11 by hunks.
-- TIME: a second or two. BUDGET: statement_timeout 60 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): restart_enabled false closes the door at once. A migration reversing the hunks (OLD texts verbatim).
-- SELF-ASSERT: each hunk once and reversing; no other function moved; grants, volatility, definer, search path, owner of the hunked
--   unmoved; the door for `authenticated` alone, the rest for no client and not service_role; the tables for no client; two knobs, both
--   false; home_port_of answers as before for every company. THE PROBE (rolled back by a raised sentinel) founds its own companies and
--   reads no live company, market or dice, and no figure of the founding purse: every sum is over the probe's own rows.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['public.new_house(uuid,text,text,text,text,text,text,bigint,boolean)', 'world.player()',
                                    'public.home_port_of(uuid)', 'public.settle_standings(timestamp with time zone)', 'world.stats_me()',
                                    'world.town_hall(uuid)', 'world.city_history(uuid,integer)', 'public.town_hall_gifts(uuid)',
                                    'public.flow_is_profit(text)', 'public.ledger_is_earning(text)', 'public.client_rpc_entry_points()'];
  c_new    constant text[] := array['public.restart_on()', 'public.hq_cities_on()', 'public.nation_in_europe(uuid)', 'public.hq_card(uuid)',
                                    'public.company_heir(uuid)', 'public.restart_refusal(uuid,timestamp with time zone)',
                                    'public.restart_card(uuid)', 'public.company_retire(uuid,timestamp with time zone)',
                                    'cmd.restart_company(text,text,text)'];
  c_door   constant text := 'cmd.restart_company(text,text,text)';
  c_a      constant uuid := '00000000-0509-4000-8000-000000000001';
  c_b      constant uuid := '00000000-0509-4000-8000-000000000002';
  v_t0     timestamptz := clock_timestamp();
  v_h record; x record; v_q text; v_def text; v_pre text; v_n int;
  v_fn_before text; v_meta text; v_cfg_before text; v_home_before text;
  v_hqs int; v_by_founding int; v_none int;
  v_lived boolean := false;
  v_a uuid; v_b uuid; v_a2 uuid; v_r jsonb; v_names text[]; v_cap uuid; v_cap2 uuid;
  v_before bigint; v_after bigint; v_purse bigint; v_good uuid; v_fleet uuid; v_events int; v_ledger int; v_note text := '';
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regclass('public.company_hqs') is not null or to_regprocedure(c_door) is not null then
    raise exception '0509 refuses: it has been applied once';
  end if;
  foreach v_q in array c_hunked || array['public.company_name_refusal(text,uuid)', 'cmd.found_house(text,text)', 'public.nation_joinable(uuid)',
      'public.courier_settle(uuid,text,text,timestamp with time zone)', 'public.armada_disband_for(uuid,uuid)', 'public.port_fee_collect(uuid,uuid,bigint)',
      'public.credit(uuid,text,bigint,uuid)', 'public.treasury_post(uuid,text,bigint,uuid,uuid,boolean)', 'public.emit_event(uuid,text,jsonb)',
      'public.real_day(timestamp with time zone)', 'cmd.refuse(text,text,jsonb)', 'cmd.refused_envelope(text,text)'] loop
    if to_regprocedure(v_q) is null then
      raise exception '0509 refuses: % is not in this world', v_q;
    end if;
  end loop;

  -- ── 1. THE PRE-IMAGES ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;
  select md5(coalesce(string_agg(p.id::text || ':' || coalesce(public.home_port_of(p.id)::text, ''), ',' order by p.id), ''))
    into v_home_before from public.players p where not p.is_npc;

  -- ── 2. THE COLUMN, THE TABLES, THE KNOBS ──
  alter table public.players add column retired_at timestamptz;
  comment on column public.players.retired_at is
    '0509: null: a company. Else the instant she was closed by public.company_retire: no account, no country, a placeholder name; her books stay.';
  -- retention: none, bounded by five rows a company (company_hqs)
  create table public.company_hqs (
    player_id uuid not null references public.players(id) on delete cascade,
    slot      smallint not null check (slot between 1 and 5),
    port_id   uuid not null references public.ports(id),
    opened_at timestamptz not null default now(),
    primary key (player_id, slot),
    unique (player_id, port_id)
  );
  -- retention: none, bounded by five rows of data (hq_steps)
  create table public.hq_steps (
    slot        smallint primary key check (slot between 1 and 5),
    total_level integer not null check (total_level >= 0),
    ducats      bigint not null check (ducats >= 0),
    reputation  integer not null check (reputation >= 0)
  );
  -- retention: none, bounded by one row a restart, at most one an account a real day (company_retirements)
  create table public.company_retirements (
    player_id    uuid primary key references public.players(id) on delete cascade,
    auth_uid     uuid,
    company_name text not null,
    nation_code  text,
    retired_at   timestamptz not null,
    receipt      jsonb not null
  );
  create index company_retirements_account on public.company_retirements (auth_uid, retired_at);
  foreach v_q in array array['company_hqs', 'hq_steps', 'company_retirements'] loop
    execute format('alter table public.%I enable row level security', v_q);
    execute format('revoke all on table public.%I from public, anon, authenticated, service_role', v_q);
  end loop;
  comment on table public.company_hqs is '0509: THE ONE LIST of a company''s HQ cities. Slot 1 is her first (her country''s capital). Server only; served by public.hq_card.';
  comment on table public.hq_steps is '0509: what HQ slot n asks: total level, coin to the new city, Reputation. PLACEHOLDERS (owner R2: the owner sets them); no door reads them to open anything.';
  comment on table public.company_retirements is '0509: one row a company closed by public.company_retire: the account it was bound to, its name and country as they were, the receipt. Server only.';
  insert into public.hq_steps (slot, total_level, ducats, reputation) values
    (1, 0, 0, 0), (2, 30, 50000, 300), (3, 65, 250000, 1200), (4, 120, 1500000, 5000), (5, 160, 4000000, 10000);
  insert into public.world_config (key, value, description) values
    ('restart_enabled', 'false'::jsonb,
     '0509: THE SWITCH (the owner''s). true: a player may close their company and found again (cmd.restart_company), once a real day. false: the door answers E_NOT_IN_USE and world.player serves no restart card. No company is ever closed but by its own player''s press.'),
    ('hq_cities_enabled', 'false'::jsonb,
     '0509: THE SWITCH (the owner''s; the ladder public.hq_steps is the owner''s to set first). true: a company''s home (public.home_port_of) is her HQ slot 1, and world.player serves what the next HQ asks. false: home is the founding port as before 0509. HQ''s city and the list need no switch.');

  -- ── 3. ROW 1 FOR EVERY COMPANY (read before the hunks: home_port_of is still 0288's) ──
  insert into public.company_hqs (player_id, slot, port_id, opened_at)
  select p.id, 1, coalesce(cap.id, public.home_port_of(p.id)), p.created_at
    from public.players p
    left join public.nations n on n.id = p.nation_id
    left join public.ports cap on cap.code = n.capital_port_code and cap.kind = 'HARBOUR'
   where not p.is_npc and coalesce(cap.id, public.home_port_of(p.id)) is not null;
  get diagnostics v_hqs = row_count;

  -- ── 4. THE READERS, THE RULE, THE CORE, THE DOOR ──
  execute $f$
create function public.restart_on()
returns boolean language sql stable security definer set search_path = public, pg_temp
as $body$ select coalesce(public.wc('restart_enabled') = 'true'::jsonb, false) /* 0509: the one reader of the switch */ $body$
  $f$;
  execute $f$
create function public.hq_cities_on()
returns boolean language sql stable security definer set search_path = public, pg_temp
as $body$ select coalesce(public.wc('hq_cities_enabled') = 'true'::jsonb, false) /* 0509: the one reader of the switch */ $body$
  $f$;
  execute $f$
create function public.nation_in_europe(p_nation uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0509 (the owner: "Then you will choose your home COUNTRY (EUROPE)"): a country whose capital is a harbour of one of the European
  -- regions. Of the ten powers: Portugal, Spain, England, the Netherlands, France, and the Ottomans (Istanbul). Read by the restart alone:
  -- founding is not asked (slice europe-start).
  select exists (select 1 from public.nations n join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR'
                                               join public.regions r on r.id = p.region_id
                  where n.id = p_nation and r.code in ('IBE', 'FRA', 'BRI', 'BAL', 'SCA', 'WES', 'ADR', 'AEG'))
$body$
  $f$;
  execute $f$
create function public.hq_card(p_player uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0509: A COMPANY'S HQ CITIES as world.player serves them: `at` her first HQ's harbour code (null: none on record), `list` every one in
  -- slot order, `next` what the next slot asks (null while hq_cities_enabled is false, or with all five). Switching is the screen's: it
  -- shows one city of this list at a time, and no fleet's place enters it.
  select jsonb_build_object(
           'at', (select p.code from public.company_hqs h join public.ports p on p.id = h.port_id where h.player_id = p_player and h.slot = 1),
           'list', coalesce((select jsonb_agg(jsonb_build_object('slot', h.slot, 'port', p.code, 'since', h.opened_at) order by h.slot)
                               from public.company_hqs h join public.ports p on p.id = h.port_id where h.player_id = p_player), '[]'::jsonb),
           'next', case when public.hq_cities_on() then
                     (select jsonb_build_object('slot', s.slot, 'total_level', s.total_level, 'ducats', s.ducats, 'reputation', s.reputation)
                        from public.hq_steps s
                       where s.slot = (select coalesce(max(h.slot), 0) + 1 from public.company_hqs h where h.player_id = p_player)) end)
$body$
  $f$;
  execute $f$
create function public.company_heir(p_player uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0509: THE CITY A CLOSED COMPANY'S COIN GOES TO: her country's capital; without one, her founding port.
  select coalesce((select cap.id from public.players p join public.nations n on n.id = p.nation_id
                                 join public.ports cap on cap.code = n.capital_port_code and cap.kind = 'HARBOUR' where p.id = p_player),
                  public.home_port_of(p_player))
$body$
  $f$;
  execute $f$
create function public.restart_refusal(p_player uuid, p_now timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0509: WHY THIS COMPANY CANNOT BE RESTARTED NOW, in plain words; null: she can. The one reader, of the card (public.restart_card) and of
-- the core (public.company_retire). Writes nothing.
--   E_RESTART_TODAY   this account restarted on this real day (UTC)
--   E_IN_BATTLE       a fleet of hers is in a battle that is not over
--   E_CONTRACT_OUT    another company carries a contract she posted: its reward and the carrier's collateral are held, and only the
--                     delivery or the deadline settles them
--   E_NO_HARBOUR      no city can take her coin (no country's capital and no founding port on record)
declare
  v_f text;
begin
  if exists (select 1 from public.company_retirements r
              where r.auth_uid = (select p.auth_uid from public.players p where p.id = p_player)
                and public.real_day(r.retired_at) = public.real_day(p_now)) then
    return jsonb_build_object('code', 'E_RESTART_TODAY', 'sentence', 'You restarted today. You can restart again after 00:00 UTC.');
  end if;
  select f.name into v_f from public.fleets f
   where f.player_id = p_player
     and ((select c.state from public.fleet_census(f.id) c) = 'battle'   -- the one reading of a fleet's state; and a wreck still on a side
          or exists (select 1 from public.battle_sides s join public.battles b on b.id = s.battle_id and b.status = 'FIGHTING' where s.fleet_id = f.id))
   order by f.created_at limit 1;
  if v_f is not null then
    return jsonb_build_object('code', 'E_IN_BATTLE', 'sentence', format('%s is in battle. Restart when the battle is over.', v_f));
  end if;
  if exists (select 1 from public.courier_contracts c where c.poster_id = p_player and c.status = 'taken') then
    return jsonb_build_object('code', 'E_CONTRACT_OUT', 'sentence', 'Another company is carrying a contract you posted. Restart when it is delivered or its time runs out.');
  end if;
  if public.company_heir(p_player) is null then
    return jsonb_build_object('code', 'E_NO_HARBOUR', 'sentence', 'Your company has no capital to close in.');
  end if;
  return null;
end
$body$
  $f$;
  execute $f$
create function public.restart_card(p_player uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0509: what the Restart press shows (world.player's `restart`): null while dark. `refusal` null: she may press now. `nations`: the
  -- countries a restarted company may sail for (European, and open to companies).
  select case when public.restart_on() then jsonb_build_object(
           'refusal', public.restart_refusal(p_player, now()),
           'nations', coalesce((select jsonb_agg(n.code order by n.name) from public.nations n
                                 where public.nation_joinable(n.id) and public.nation_in_europe(n.id)), '[]'::jsonb)) end
$body$
  $f$;
  execute $f$
create function public.company_retire(p_player uuid, p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
set lock_timeout = '3s'
as $body$
-- 0509: THE ONE WAY A COMPANY CLOSES (the rules a holding: docs/dev-log/2026-11-25-restart-company.md). The house's row first, then her
-- fleets without waiting (E_BUSY when the beat holds one). Nothing of players, events, ledger, level_book, reputation_book, capital_gifts,
-- treasury_flows or another company is deleted. Coin: escrows and set-aside dividends come home, debts to cities are paid, the rest goes to
-- her country's capital (public.company_heir). Called by cmd.restart_company alone; server only.
declare
  p        public.players%rowtype;
  v_fleets uuid[];
  v_ships  uuid[];
  v_voy    uuid[];
  v_bad    jsonb;
  r        record;
  v_heir   uuid;
  v_code   text;
  v_nation text;
  v_div    bigint;
  v_ref    bigint := 0;
  v_debts  bigint;
  v_purse  bigint;
  v_ev     uuid;
  v_name   text;
  v_out    jsonb;
  v_cancel int := 0;
  v_fail   int := 0;
begin
  select x.* into p from public.players x where x.id = p_player and not x.is_npc and x.retired_at is null for update;
  if p.id is null then
    perform cmd.refuse('E_NO_HOUSE', 'Found a company first.');
  end if;
  v_fleets := array(select f.id from public.fleets f where f.player_id = p.id order by f.id for update skip locked);
  if cardinality(v_fleets) <> (select count(*) from public.fleets f where f.player_id = p.id) then
    perform cmd.refuse('E_BUSY', 'One of your fleets is busy this moment. Try again.');
  end if;
  v_bad := public.restart_refusal(p.id, p_now);
  if v_bad is not null then
    perform cmd.refuse(v_bad->>'code', v_bad->>'sentence');
  end if;
  v_heir := public.company_heir(p.id);
  v_code := (select q.code from public.ports q where q.id = v_heir);
  v_nation := (select n.code from public.nations n where n.id = p.nation_id);
  v_ships := array(select s.id from public.ships s where s.player_id = p.id);
  v_voy := array(select v.id from public.voyages v where v.fleet_id = any(v_fleets) and v.status = 'SAILING')
        || array(select v.id from public.voyages v where v.fleet_id = any(v_fleets) and v.status <> 'SAILING');   -- each half by its partial index

  -- ── 1. HELD COIN COMES HOME ──
  -- contracts: hers nobody took are taken down (the reward and goods back); the ones she carries fail by the ordinary rule (what is aboard
  -- goes back to the poster, her collateral is the poster's)
  for r in select c.id from public.courier_contracts c where c.poster_id = p.id and c.status = 'open' order by c.id loop
    perform public.courier_settle(r.id, 'cancel', 'company closed', p_now);
    v_cancel := v_cancel + 1;
  end loop;
  for r in select c.id from public.courier_contracts c where c.carrier_id = p.id and c.status = 'taken' order by c.id loop
    perform public.courier_settle(r.id, 'fail', 'company closed', p_now);
    v_fail := v_fail + 1;
  end loop;
  -- market requests: closed, the coin held for them back (cmd.request_cancel's rule)
  for r in select m.id, m.escrow from public.market_requests m where m.player_id = p.id and m.status = 'open' order by m.id for update loop
    update public.market_requests set status = 'cancelled', qty = 0, escrow = 0 where id = r.id;
    if r.escrow > 0 then
      perform public.credit(p.id, 'REQUEST_REFUND', r.escrow);
      v_ref := v_ref + r.escrow;
    end if;
  end loop;
  -- dividends the cities set aside for her are paid; her shares end (the works they built stay built, and pay her nothing more)
  select coalesce(sum(s.accrued), 0) into v_div from (select c.accrued from public.city_shares c where c.player_id = p.id for update) s;
  update public.city_shares set accrued = 0, drip_left = 0, drip_hour = 0 where player_id = p.id;
  if v_div > 0 then
    perform public.credit(p.id, 'DIVIDEND', v_div, null);
  end if;
  delete from public.city_shares where player_id = p.id;

  -- ── 2. DEBTS, THEN THE PURSE ── (what the purse cannot pay of a debt is written off: a debt is no coin)
  v_debts := public.port_fee_collect(p.id, null, 9000000000000000);
  delete from public.port_fee_debts where player_id = p.id;
  v_purse := (select x.ducats from public.players x where x.id = p.id);
  v_ev := public.emit_event(p.id, 'COMPANY_CLOSED', jsonb_build_object('company', p.company_name, 'nation', v_nation, 'port', v_code, 'ducats', v_purse));
  if v_purse > 0 then
    perform public.credit(p.id, 'COMPANY_CLOSED', -v_purse, v_ev);
    perform public.treasury_post(v_heir, 'COMPANY_CLOSED', v_purse, p.id, v_ev, true);
  end if;

  -- ── 3. OFFICES, VOTES AND BOARDS ── (a mayor's seat is empty until the next count)
  delete from public.port_mayor where player_id = p.id;
  delete from public.port_influence where player_id = p.id;
  delete from public.house_regard where player_id = p.id;
  delete from public.wanted where player_id = p.id;
  delete from public.nation_race_book where player_id = p.id;
  delete from public.houses_week where player_id = p.id;
  delete from public.standings where player_id = p.id;

  -- ── 4. WORK: jobs, routes, queues, land, the yard, captains, sheds ──
  for r in select a.id from public.armadas a where a.player_id = p.id order by a.id loop
    perform public.armada_disband_for(p.id, r.id);
  end loop;
  delete from public.fleet_jobs where player_id = p.id;
  delete from public.standing_routes where player_id = p.id;
  delete from public.early_sightings where player_id = p.id;
  delete from public.skill_queue where player_id = p.id;
  delete from public.land_parties where player_id = p.id;
  delete from public.hull_orders where player_id = p.id;
  delete from public.player_officers where player_id = p.id;
  delete from public.player_storage where player_id = p.id;
  delete from public.player_items where player_id = p.id;
  delete from public.provision_presets where player_id = p.id;

  -- ── 5. FLEETS AND SHIPS, with the cargo, stores, crew and insurance of the voyage under way (goods are no coin and go with the hull) ──
  -- a city's request she once fulfilled keeps its figures and her id, and no longer names the fleet (its check asks all three or none)
  update public.trade_contracts set status = 'spent', fulfilled_fleet = null where fulfilled_by = p.id and status = 'fulfilled';
  update public.trade_contracts set fulfilled_fleet = null where fulfilled_fleet = any(v_fleets);
  delete from public.fitted_units where ship_id = any(v_ships);
  delete from public.ship_xp where ship_id = any(v_ships);
  delete from public.voyage_hostile where voyage_id = any(v_voy);
  delete from public.fleet_book where fleet_id = any(v_fleets);
  delete from public.fleet_lines where fleet_id = any(v_fleets);
  delete from public.ships where player_id = p.id;
  delete from public.voyages where id = any(v_voy);
  delete from public.fleets where player_id = p.id;
  delete from public.company_hqs where player_id = p.id;

  -- ── 6. THE ROW: no account, no country, her name free ──
  loop
    v_name := 'Closed company ' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
    exit when not exists (select 1 from public.players x where lower(x.company_name) = lower(v_name));
  end loop;
  update public.players set auth_uid = null, nation_id = null, company_name = v_name, retired_at = p_now where id = p.id;
  v_out := jsonb_build_object('ducats', v_purse, 'port', v_code, 'debts_paid', v_debts, 'dividends', v_div, 'requests', v_ref,
                              'contracts_cancelled', v_cancel, 'contracts_failed', v_fail,
                              'fleets', cardinality(v_fleets), 'ships', cardinality(v_ships));
  insert into public.company_retirements (player_id, auth_uid, company_name, nation_code, retired_at, receipt)
  values (p.id, p.auth_uid, p.company_name, v_nation, p_now, v_out);
  return v_out;
end
$body$
  $f$;
  execute $f$
create function cmd.restart_company(p_confirm text, p_company_name text, p_nation_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0509: RESTART. The caller's own company (no player id): her name typed, closed by public.company_retire, and a new one founded for the
-- same account by cmd.found_house, all in one transaction: any refusal leaves the old company as it was. The new name is judged by THE one
-- rule (0503); the country is one of Europe's that takes companies. Dark: E_NOT_IN_USE.
declare
  v_player uuid := public.current_player_id();
  v_name   text;
  v_nation uuid;
  v_bad    jsonb;
  v_closed jsonb;
  v_new    jsonb;
  v_det    text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE', 'error_message', 'Found a company first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    if not public.restart_on() then
      perform cmd.refuse('E_NOT_IN_USE', 'Restart is not open yet.');
    end if;
    v_name := (select x.company_name from public.players x where x.id = v_player);
    if btrim(coalesce(p_confirm, '')) <> btrim(v_name) then
      perform cmd.refuse('E_CONFIRM', format('Type your company''s name, %s, to restart.', v_name));
    end if;
    select n.id into v_nation from public.nations n where n.code = upper(btrim(coalesce(p_nation_code, '')));
    if v_nation is null or not public.nation_joinable(v_nation) or not public.nation_in_europe(v_nation) then
      perform cmd.refuse('E_NOT_EUROPE', 'Choose a country of Europe.');
    end if;
    v_bad := public.company_name_refusal(btrim(coalesce(p_company_name, '')), v_player);   -- her own old name is hers to take again
    if v_bad is not null then
      perform cmd.refuse(v_bad->>'code', v_bad->>'sentence');
    end if;
    v_closed := public.company_retire(v_player, now());
    v_new := cmd.found_house(p_company_name, p_nation_code);
    if not coalesce((v_new->>'ok')::boolean, false) then
      perform cmd.refuse(v_new->>'error_code', v_new->>'error_message');
    end if;
    return v_new || jsonb_build_object('closed', v_closed);
  exception
    when lock_not_available or deadlock_detected then
      return jsonb_build_object('ok', false, 'error_code', 'E_BUSY', 'error_message', 'Your company is busy this moment. Try again.', 'fixes', '[]'::jsonb);
    when others then
      if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
      get stacked diagnostics v_det = pg_exception_detail;
      return cmd.refused_envelope(sqlerrm, v_det);
  end;
end
$body$
  $f$;
  foreach v_q in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_q::regprocedure);
  end loop;
  execute format('grant execute on function %s to authenticated', c_door::regprocedure);

  -- ── 5. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0509 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0509 values
  (c_hunked[1], 1,
$h$  perform public.founding_credit(v_player, 'FOUNDING', v_start,$h$,
$h$  -- 0509: a player's company has her first HQ from her first moment: the port she is founded in (her country's capital, at cmd.found_house)
  if not coalesce(p_is_npc, false) then
    insert into public.company_hqs (player_id, slot, port_id) values (v_player, 1, v_port);
  end if;

  perform public.founding_credit(v_player, 'FOUNDING', v_start,$h$),
  ('world.player()', 1,
$h$      'rename_free',   public.company_rename_free(v_row.renames),
$h$,
$h$      'rename_free',   public.company_rename_free(v_row.renames),
      -- 0509: her HQ cities (the first is slot 1; no fleet's place enters it), and the Restart press (null while dark)
      'hq',            public.hq_card(v_id),
      'restart',       public.restart_card(v_id),
$h$),
  ('public.home_port_of(uuid)', 1,
$h$  select p.id
    from public.events e
$h$,
$h$  -- 0509: lit (hq_cities_enabled) her home is her HQ slot 1; dark, the founding port, as it was
  select coalesce((select h.port_id from public.company_hqs h where h.player_id = p_player and h.slot = 1 and public.hq_cities_on()), (
  select p.id
    from public.events e
$h$),
  ('public.home_port_of(uuid)', 2,
$h$   order by e.created_at asc
   limit 1
$h$,
$h$   order by e.created_at asc
   limit 1))
$h$),
  (c_hunked[4], 1,
$h$       where not p.is_npc   -- 0097$h$,
$h$       where not p.is_npc and p.retired_at is null   -- 0509: a closed company ranks nowhere   -- 0097$h$),
  ('world.stats_me()', 1,
$h$left join public.nations n on n.id = p.nation_id where not p.is_npc)$h$,
$h$left join public.nations n on n.id = p.nation_id where not p.is_npc and p.retired_at is null)   /* 0509 */$h$),
  ('world.town_hall(uuid)', 1,
$h$                            join public.players pl on pl.id = b.player_id
$h$,
$h$                            join public.players pl on pl.id = b.player_id and pl.retired_at is null   -- 0509
$h$),
  (c_hunked[7], 1,
$h$                             join public.players pl on pl.id = b.player_id
$h$,
$h$                             join public.players pl on pl.id = b.player_id and pl.retired_at is null   -- 0509
$h$),
  ('public.town_hall_gifts(uuid)', 1,
$h$                    join public.players pl on pl.id = c.player_id
$h$,
$h$                    join public.players pl on pl.id = c.player_id and pl.retired_at is null   -- 0509
$h$),
  ('public.flow_is_profit(text)', 1,
$h$'CONVOY_RETURN', 'SHARE')$h$,
$h$'CONVOY_RETURN', 'SHARE', 'COMPANY_CLOSED')   /* 0509: a closed company's coin is no profit of the city's */$h$),
  ('public.ledger_is_earning(text)', 1,
$h$p_kind not in ('FOUNDING', 'NPC_REFOUND', 'NPC_CARRIED')$h$,
$h$p_kind not in ('FOUNDING', 'NPC_REFOUND', 'NPC_CARRIED', 'COMPANY_CLOSED')   /* 0509 */$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('cmd',         'rename_company',        'text'),
$h$,
$h$      ('cmd',         'rename_company',        'text'),
      -- 0509: close the caller's company and found again (her name typed; dark until restart_enabled)
      ('cmd',         'restart_company',       'text, text, text'),
$h$);

  for v_h in select h.fn from hunks_0509 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0509 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0509 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0509 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0509 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0509 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;
  if (select count(distinct h.fn) from hunks_0509 h) <> cardinality(c_hunked) then
    raise exception '0509 self-assert FAIL: a listed body has no hunk';
  end if;

  -- the one word of the new kind (moved: from a purse to a city)
  insert into public.stats_flow_words (kind, side, word, ord)
  select 'COMPANY_CLOSED', 'moved', 'Companies closed', coalesce(max(w.ord), 0) + 1 from public.stats_flow_words w;

  -- ── 6. SELF-ASSERT: the catalog, the grants, the knobs, the rows ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0509 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0509 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('anon', u.q::regprocedure, 'execute') or has_function_privilege('service_role', u.q::regprocedure, 'execute')
                 or has_function_privilege('authenticated', u.q::regprocedure, 'execute') <> (u.q = c_door))
     or (select count(*) from public.client_write_grants()) <> 0
     or exists (select 1 from unnest(array['public.company_hqs', 'public.hq_steps', 'public.company_retirements']) t(n), unnest(array['anon', 'authenticated', 'service_role']) g(r)
                 where has_table_privilege(g.r, t.n, 'select,insert,update,delete')) then
    raise exception '0509 self-assert FAIL: the grants are not the contract';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e where e.schema_name = 'cmd' and e.function_name = 'restart_company' and e.fn is not null) <> 1 then
    raise exception '0509 self-assert FAIL: the door is not in the client registry';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key)) from public.world_config c
       where c.key not in ('restart_enabled', 'hq_cities_enabled')) <> v_cfg_before or public.restart_on() or public.hq_cities_on() then
    raise exception '0509 self-assert FAIL: a knob moved, or a switch is not dark';
  end if;
  if (select md5(coalesce(string_agg(p.id::text || ':' || coalesce(public.home_port_of(p.id)::text, ''), ',' order by p.id), '')) from public.players p where not p.is_npc) <> v_home_before then
    raise exception '0509 self-assert FAIL: a home moved while dark';
  end if;
  if exists (select 1 from public.players p left join public.nations n on n.id = p.nation_id
                                            left join public.ports cap on cap.code = n.capital_port_code and cap.kind = 'HARBOUR'
                                            left join public.company_hqs h on h.player_id = p.id and h.slot = 1
              where not p.is_npc and h.port_id is distinct from coalesce(cap.id, public.home_port_of(p.id)))
     or exists (select 1 from public.company_hqs h join public.players p on p.id = h.player_id where p.is_npc) then
    raise exception '0509 self-assert FAIL: HQ row 1 is not the capital (or the founding port) for every company';
  end if;
  select count(*) filter (where cap.id is null and h.port_id is not null), count(*) filter (where h.port_id is null) into v_by_founding, v_none
    from public.players p left join public.nations n on n.id = p.nation_id
    left join public.ports cap on cap.code = n.capital_port_code and cap.kind = 'HARBOUR'
    left join public.company_hqs h on h.player_id = p.id and h.slot = 1
   where not p.is_npc;

  -- ── 7. THE PROBE, rolled back by a raised sentinel (its own companies' rows alone) ──
  begin
    select array_agg(c.nm order by c.i) into v_names
      from (select i, 'Casa Nova 0509 ' || i as nm from generate_series(1, 5000) i
             where not exists (select 1 from public.players p where p.company_name like '% 0509 ' || i) order by i limit 3) c;
    v_cap := (select p.id from public.ports p join public.nations n on n.capital_port_code = p.code where n.code = 'PRT');
    v_cap2 := (select p.id from public.ports p join public.nations n on n.capital_port_code = p.code where n.code = 'ESP');
    v_a := public.new_house(c_a, v_names[1], 'PRT', (select p.code from public.ports p where p.id = v_cap));
    v_b := public.new_house(c_b, v_names[3], 'ESP', (select p.code from public.ports p where p.id = v_cap2));
    if (select h.port_id from public.company_hqs h where h.player_id = v_a and h.slot = 1) is distinct from v_cap then
      raise exception '0509 self-assert FAIL: a founded company''s first HQ is not her capital';
    end if;
    perform cmd.assume_identity(c_a);
    -- DARK: no card, no door
    v_r := world.player()->'player';
    if v_r->'restart' <> 'null'::jsonb or v_r->'hq'->>'at' is distinct from (select p.code from public.ports p where p.id = v_cap) or v_r->'hq'->'next' <> 'null'::jsonb
       or cmd.restart_company(v_names[1], v_names[2], 'PRT')->>'error_code' is distinct from 'E_NOT_IN_USE' then
      raise exception '0509 self-assert FAIL: dark, the door or the card is not shut, or HQ is not served: %', v_r;
    end if;
    update public.world_config set value = 'true'::jsonb where key = 'restart_enabled';
    -- her coin in four places: the purse (whatever the founding gave and a little more), a request's escrow, a city's set-aside, a debt
    v_good := (select g.id from public.goods g order by g.code limit 1);
    select f.id into v_fleet from public.fleets f where f.player_id = v_a;
    perform public.credit(v_a, 'PREMIUM', 1000);
    perform public.credit(v_a, 'REQUEST_ESCROW', -300);
    insert into public.market_requests (player_id, port_id, good_id, qty, unit_price, escrow) values (v_a, v_cap, v_good, 3, 100, 300);
    insert into public.city_shares (port_id, kind, player_id, shares, paid, accrued, accrued_day) values (v_cap, 'docks', v_a, 1, 10, 77, world.game_day());
    insert into public.port_influence (port_id, nation_id, player_id, points) select v_cap, n.id, v_a, 5 from public.nations n where n.code = 'PRT';
    insert into public.port_fee_debts (player_id, port_id, ducats, kind) values (v_a, v_cap, 40, 'PORT_FEE');
    v_purse := (select p.ducats from public.players p where p.id = v_a);
    select count(*) into v_events from public.events e where e.player_id = v_a;
    select count(*) into v_ledger from public.ledger l where l.player_id = v_a;
    v_before := v_purse + 300 + 77 + coalesce((select sum(f.ducats) from public.treasury_flows f where f.player_id = v_a), 0);

    -- REFUSED, and nothing moves: a wrong name typed, a country outside Europe, a taken name, a bad name, a fleet in battle
    for x in select * from (values ('not her name', v_names[2], 'PRT', 'E_CONFIRM'), (v_names[1], v_names[2], 'JPN', 'E_NOT_EUROPE'),
                                   (v_names[1], v_names[2], 'XXX', 'E_NOT_EUROPE'), (v_names[1], upper(v_names[3]), 'PRT', 'E_NAME_TAKEN'),
                                   (v_names[1], 'A*B', 'PRT', 'E_BAD_NAME')) t(confirm, nm, nation, code) loop
      v_r := cmd.restart_company(x.confirm, x.nm, x.nation);
      if (v_r->>'ok')::boolean or v_r->>'error_code' is distinct from x.code then
        raise exception '0509 self-assert FAIL: restart(%, %, %) was not refused as %: %', x.confirm, x.nm, x.nation, x.code, v_r;
      end if;
    end loop;
    update public.fleets set status = 'IN_BATTLE' where id = v_fleet;
    v_r := cmd.restart_company(v_names[1], v_names[2], 'PRT');
    if v_r->>'error_code' is distinct from 'E_IN_BATTLE' then
      raise exception '0509 self-assert FAIL: a company in battle was not refused: %', v_r;
    end if;
    update public.fleets set status = 'DOCKED' where id = v_fleet;
    if (select p.ducats from public.players p where p.id = v_a) <> v_purse or public.current_player_id() <> v_a then
      raise exception '0509 self-assert FAIL: a refused restart moved something';
    end if;

    -- RESTARTED
    v_r := cmd.restart_company(v_names[1], v_names[2], 'ESP');
    if not coalesce((v_r->>'ok')::boolean, false) then
      raise exception '0509 self-assert FAIL: the restart was refused: %', v_r;
    end if;
    v_a2 := public.current_player_id();
    if v_a2 is null or v_a2 = v_a or (v_r->>'player_id')::uuid <> v_a2 or (select p.company_name from public.players p where p.id = v_a2) <> v_names[2]
       or (select h.port_id from public.company_hqs h where h.player_id = v_a2 and h.slot = 1) is distinct from v_cap2 then
      raise exception '0509 self-assert FAIL: the account is not bound to a new company with her HQ in her capital';
    end if;
    if not exists (select 1 from public.players p where p.id = v_a and p.ducats = 0 and p.auth_uid is null and p.nation_id is null
                      and p.retired_at is not null and p.company_name like 'Closed company %') then
      raise exception '0509 self-assert FAIL: the old row is not closed: %', (select to_jsonb(p) from public.players p where p.id = v_a);
    end if;
    v_after := coalesce((select sum(f.ducats) from public.treasury_flows f where f.player_id = v_a), 0);
    if v_after <> v_before then
      raise exception '0509 self-assert FAIL: her coin is not in the cities: % before, % after', v_before, v_after;
    end if;
    if (select count(*) from public.events e where e.player_id = v_a) <= v_events or (select count(*) from public.ledger l where l.player_id = v_a) <= v_ledger
       or (select sum(l.ducats_delta) from public.ledger l where l.player_id = v_a) <> 0 then
      raise exception '0509 self-assert FAIL: her books were cut, or do not close at 0';
    end if;
    if exists (select 1 from public.fleets f where f.player_id = v_a) or exists (select 1 from public.ships s where s.player_id = v_a)
       or exists (select 1 from public.city_shares s where s.player_id = v_a) or exists (select 1 from public.port_influence i where i.player_id = v_a)
       or exists (select 1 from public.port_fee_debts d where d.player_id = v_a) or exists (select 1 from public.company_hqs h where h.player_id = v_a)
       or exists (select 1 from public.market_requests m where m.player_id = v_a and (m.status = 'open' or m.escrow <> 0)) then
      raise exception '0509 self-assert FAIL: a closed company still holds something';
    end if;
    -- her name is free again; a second restart the same day is refused
    if public.company_name_refusal(v_names[1], null) is not null then
      raise exception '0509 self-assert FAIL: the closed company''s name is not free';
    end if;
    v_r := cmd.restart_company(v_names[2], v_names[1], 'PRT');
    if v_r->>'error_code' is distinct from 'E_RESTART_TODAY' then
      raise exception '0509 self-assert FAIL: a second restart the same day was not refused: %', v_r;
    end if;
    -- the other company is untouched
    if (select p.retired_at from public.players p where p.id = v_b) is not null or not exists (select 1 from public.fleets f where f.player_id = v_b) then
      raise exception '0509 self-assert FAIL: another company was touched';
    end if;
    v_note := 'dark shut; six refusals moved nothing; one restart: the account on a new company with HQ in its capital, the old row closed, its purse, escrow, set-aside and debt in cities'' books to the coin, its ledger summing to 0, its name free; the second the same day refused';
    raise exception using errcode = 'ZX509', message = 'PROBE_ROLLBACK_0509';
  exception when sqlstate 'ZX509' then
    v_lived := true;
  end;
  if not v_lived or exists (select 1 from public.players p where p.auth_uid in (c_a, c_b) or p.retired_at is not null)
     or exists (select 1 from public.company_retirements) or public.restart_on() then
    raise exception '0509 self-assert FAIL: the probe did not run to its end, or left something behind';
  end if;

  -- ── 8. THE NEWS ──
  perform public.news_update('0509', 'HQ shows your HQ city. Press its name to see your HQ cities', 'HQ shows your HQ city. Press its name to see your HQ cities');

  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0509 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0509 self-assert ok: A COMPANY IS RESTARTED (dark), AND EVERY COMPANY HAS AN HQ. % HQ rows (% by the founding port, % companies with neither); twelve hunks once and reversing; nine new functions (one door); two knobs, both false. Probe (rolled back): %. % ms.',
    v_hqs, v_by_founding, v_none, v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
