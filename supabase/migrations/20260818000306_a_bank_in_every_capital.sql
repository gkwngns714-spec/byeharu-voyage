-- ═════════════════════════════════════════════════════════════════════════════════════════
-- 0306 — A BANK IN EVERY CAPITAL   (slice B1 of docs/BANK.md: the books, the knobs and one reader, all DARK; nothing moves money)
-- ═════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE ORDER (owner, 2026-11-05) ──────────────────────────────────────────────────────────────
--   "an institution like a bank, where cities can hold cash and be given a mortgage" — one bank per nation, in the capital city only.
--   Design and every default: docs/BANK.md (decided by default; the owner reverses afterwards). Dev-log: docs/dev-log/2026-11-05-bank-b1.md.
--
-- ── WHAT THIS FILE ADDS (B1 only; deposit, withdraw, lending and the client are B2..B4) ──────────
--   public.banks          one row per nation (23): nation_id pk, port_id = that nation's CAPITAL (unique), units 0, vault 0.
--                         A trigger refuses any port that is not nations.capital_port_code's port (insert, and an update of either key).
--   public.bank_accounts  (nation_id, player_id) -> units. Empty. A player reads only their own rows.
--   public.bank_loans     the mortgages. Empty. One OPEN loan per city (partial unique index). Read by any signed-in player.
--   public.bank_flows     the bank's book, APPEND-ONLY (public.forbid_mutation, as capital_gifts and events). Empty. Server-only.
--   public.bank_unit_price(nation) -> numeric   (vault + the OPEN loans' outstanding) / units; 1.0 when units = 0. STABLE, server-only.
--   12 world_config knobs (docs/BANK.md §6): bank_enabled FALSE and the rest at their defaults, bank_seed_per_nation 0, bank_npc_deposit false.
--
-- ── WHAT DOES NOT MOVE ─────────────────────────────────────────────────────────────────────────
--   No function, cron job, existing knob, treasury or purse is touched: nothing reads these tables or knobs yet, so the game is byte for byte
--   today's (the self-assert compares every existing function body and every existing world_config row before and after).
--
-- ── SELF-ASSERT (on probe rows rolled back; counts only this file's own rows) ────────────────────
--   23 banks, each port_id = its nation's capital; units and vault all 0; a bank at a non-capital port refused (insert, and moving a bank off
--   its capital); bank_flows UPDATE and DELETE refused (a probe row, rolled back); bank_unit_price = 1.0 at units 0 and (vault + loans) / units
--   on a rolled-back probe; bank_enabled false and the knob defaults; the new tables and the reader are not reachable by a client beyond the
--   RLS written; no existing function or knob moved.
-- ═════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_new_fns  constant text[] := array['public.bank_unit_price(uuid)', 'public.tg_banks_capital_only()'];
  v_fn_before  text;
  v_cfg_before text;
  v_n          int;
  v_nation     uuid;
  v_other_port uuid;
  v_price      numeric;
  r            record;
  v_t0         timestamptz := clock_timestamp();
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD: not applied; the pieces it stands on are in this world ──
  if to_regclass('public.nations') is null or to_regclass('public.ports') is null or to_regclass('public.players') is null
     or to_regclass('public.world_config') is null or to_regprocedure('public.forbid_mutation()') is null
     or to_regprocedure('public.current_player_id()') is null or to_regprocedure('public.wc(text)') is null then
    raise exception '0306 refuses: the nations, ports, players, knobs or the append-only guard are not in this world';
  end if;
  if to_regclass('public.banks') is not null or to_regclass('public.bank_flows') is not null
     or exists (select 1 from public.world_config where key like 'bank\_%') then
    raise exception '0306 refuses: it has been applied once';
  end if;
  if (select count(*) from public.nations) <> 23
     or exists (select 1 from public.nations n where n.capital_port_code is null
                or not exists (select 1 from public.ports p where p.code = n.capital_port_code)) then
    raise exception '0306 refuses: the 23 nations do not all name a capital port that exists';
  end if;

  -- what must not move (read once, compared after)
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 1. THE TABLES ──
  create table public.banks (
    nation_id  uuid primary key references public.nations(id),
    port_id    uuid not null unique references public.ports(id),
    units      numeric(30, 10) not null default 0 check (units >= 0),
    vault      bigint not null default 0 check (vault >= 0),
    created_at timestamptz not null default now()
  );
  comment on table public.banks is
    '0306 (docs/BANK.md §2): one national bank per nation, seated in its capital city only (port_id = the port of nations.capital_port_code; a trigger refuses any other). A pool: depositors hold units (bank_accounts), the vault holds cash, loans out (bank_loans) are an asset. Dark: bank_enabled is false and nothing writes here until B2/B3.';

  create table public.bank_accounts (
    nation_id uuid not null references public.banks(nation_id),
    player_id uuid not null references public.players(id) on delete cascade,
    units     numeric(30, 10) not null default 0 check (units >= 0),
    primary key (nation_id, player_id)
  );
  comment on table public.bank_accounts is
    '0306 (docs/BANK.md §2): a depositor''s units in a nation''s bank pool. RLS: a player reads only their own rows. Written by B2''s deposit and withdraw alone.';

  create table public.bank_loans (
    id            bigint generated always as identity primary key,
    nation_id     uuid   not null references public.banks(nation_id),
    port_id       uuid   not null references public.ports(id),
    principal     bigint not null check (principal > 0),
    outstanding   bigint not null check (outstanding >= 0),
    rate_per_day  numeric not null check (rate_per_day >= 0),
    term_days     int    not null check (term_days > 0),
    opened_at     timestamptz not null default now(),
    due_at        timestamptz not null,
    arrears_days  int    not null default 0 check (arrears_days >= 0),
    state         text   not null default 'OPEN' check (state in ('OPEN', 'PAID', 'WRITTEN_OFF'))
  );
  create unique index bank_loans_one_open_per_city on public.bank_loans (port_id) where state = 'OPEN';
  create index bank_loans_nation_state on public.bank_loans (nation_id, state);
  comment on table public.bank_loans is
    '0306 (docs/BANK.md §2, §4): a mortgage to a city of the bank''s own nation. One OPEN loan per city. Written by B3''s daily job alone. Read by any signed-in player.';

  create table public.bank_flows (
    id        bigint generated always as identity primary key,
    nation_id uuid   not null references public.banks(nation_id),
    kind      text   not null check (kind in ('DEPOSIT', 'WITHDRAW', 'LOAN', 'REPAY', 'INTEREST', 'WRITE_OFF', 'SEED')),
    amount    bigint not null,
    player_id uuid,
    port_id   uuid,
    loan_id   bigint,
    at        timestamptz not null default now()
  );
  create index bank_flows_nation_at on public.bank_flows (nation_id, at);
  comment on table public.bank_flows is
    '0306 (docs/BANK.md §2): the bank''s book, one row per movement (DEPOSIT, WITHDRAW, LOAN, REPAY, INTEREST, WRITE_OFF, SEED); the vault is the sum of its flows (B2 reconciles). APPEND-ONLY (public.forbid_mutation, as capital_gifts). No foreign key on player_id / port_id / loan_id: a flow outlives them (as treasury_flows). Server-only.';
  create trigger bank_flows_append_only
    before update or delete on public.bank_flows
    for each row execute function public.forbid_mutation();

  -- RLS. Supabase's default privileges grant ALL on a new table to the client roles: revoked, then only what is written.
  alter table public.banks         enable row level security;
  alter table public.bank_accounts enable row level security;
  alter table public.bank_loans    enable row level security;
  alter table public.bank_flows    enable row level security;
  revoke all on table public.banks, public.bank_accounts, public.bank_loans, public.bank_flows from public, anon, authenticated;
  revoke all on sequence public.bank_loans_id_seq, public.bank_flows_id_seq from public, anon, authenticated;
  grant select on table public.banks, public.bank_loans to authenticated;
  create policy banks_read on public.banks for select to authenticated using (true);
  create policy bank_loans_read on public.bank_loans for select to authenticated using (true);
  grant select on table public.bank_accounts to authenticated;
  create policy bank_accounts_read_own on public.bank_accounts for select to authenticated using (player_id = public.current_player_id());
  -- bank_flows: RLS on, no grant, no policy: the server's alone (as treasury_flows).

  -- ── 2. THE CAPITAL-ONLY RULE ──
  create function public.tg_banks_capital_only()
  returns trigger
  language plpgsql
  set search_path = public, pg_temp
  as $f$
  begin
    if not exists (select 1 from public.nations n join public.ports p on p.code = n.capital_port_code
                    where n.id = new.nation_id and p.id = new.port_id) then
      raise exception 'a bank sits in its nation''s capital city only: port % is not the capital of nation %', new.port_id, new.nation_id
        using errcode = 'check_violation';
    end if;
    return new;
  end $f$;
  comment on function public.tg_banks_capital_only() is
    '0306: refuses any banks row whose port_id is not the port of its nation''s capital_port_code (docs/BANK.md §0 line 1).';
  create trigger banks_capital_only
    before insert or update of nation_id, port_id on public.banks
    for each row execute function public.tg_banks_capital_only();

  -- ── 3. THE 23 BANKS (empty vaults, no units) ──
  insert into public.banks (nation_id, port_id)
  select n.id, p.id from public.nations n join public.ports p on p.code = n.capital_port_code;
  get diagnostics v_n = row_count;
  if v_n <> 23 then
    raise exception '0306 FAIL: % banks seeded, the 23 nations name 23', v_n;
  end if;

  -- ── 4. THE KNOBS (docs/BANK.md §6; inert while bank_enabled is false) ──
  insert into public.world_config (key, value, description) values
    ('bank_enabled', 'false'::jsonb,
     '0306: the national banks'' switch (docs/BANK.md). False = no deposit, no loan, no daily bank job: the game is exactly as before. OWNER ONLY.'),
    ('bank_min_ducats', to_jsonb(1000),
     '0306: the smallest deposit (as invest_min_ducats).'),
    ('bank_rate_per_day', to_jsonb(0.003),
     '0306: simple interest a day on a loan''s outstanding (0.30 %).'),
    ('bank_term_days', to_jsonb(30),
     '0306: a loan''s length in days.'),
    ('bank_reserve_pct', to_jsonb(0.2),
     '0306: the vault never lends below this share of (vault + loans out).'),
    ('bank_low_water_days', to_jsonb(3),
     '0306: a city qualifies for a loan when its purse is under this many days of its average daily payout.'),
    ('bank_target_days', to_jsonb(7),
     '0306: a loan tops the purse up toward this many days of the city''s average daily payout.'),
    ('bank_cap_tax_days', to_jsonb(20),
     '0306: the largest loan is this many days of the city''s POPULATION_TAX.'),
    ('bank_default_days', to_jsonb(10),
     '0306: days in arrears before a loan is written off.'),
    ('bank_cooldown_days', to_jsonb(30),
     '0306: days a city waits after a loan closes or is written off.'),
    ('bank_seed_per_nation', to_jsonb(0),
     '0306: a one-time vault seed per capital (docs/BANK.md §7, option B). 0 = banks open empty. OWNER ONLY.'),
    ('bank_npc_deposit', 'false'::jsonb,
     '0306: merchants may deposit in the bank (slice B6, later). False = their surplus rule is untouched.');

  -- ── 5. THE READER ──
  create function public.bank_unit_price(p_nation uuid)
  returns numeric
  language sql
  stable
  security definer
  set search_path = public, pg_temp
  as $f$
    select case when b.units = 0 then 1.0::numeric
                else (b.vault + coalesce((select sum(l.outstanding) from public.bank_loans l where l.nation_id = b.nation_id and l.state = 'OPEN'), 0))::numeric / b.units
           end
      from public.banks b where b.nation_id = p_nation
  $f$;
  comment on function public.bank_unit_price(uuid) is
    '0306 (docs/BANK.md §2): the ONE unit-price reader. (vault + the OPEN loans'' outstanding) / units; 1.0 while units = 0; null for a nation with no bank. A deposit buys amount / price units; a withdrawal sells units at it. STABLE, server-only.';
  revoke all on function public.bank_unit_price(uuid) from public, anon, authenticated;
  revoke all on function public.tg_banks_capital_only() from public, anon, authenticated;

  -- ── 6. SELF-ASSERT ──
  -- (a) 23 banks, each at its nation's capital; empty; dark
  select count(*) into v_n from public.banks b
    join public.nations n on n.id = b.nation_id join public.ports p on p.id = b.port_id and p.code = n.capital_port_code;
  if v_n <> 23 or (select count(*) from public.banks) <> 23 then
    raise exception '0306 self-assert FAIL: % of 23 banks sit at their nation''s capital', v_n;
  end if;
  if exists (select 1 from public.banks where units <> 0 or vault <> 0)
     or exists (select 1 from public.bank_accounts) or exists (select 1 from public.bank_loans) or exists (select 1 from public.bank_flows) then
    raise exception '0306 self-assert FAIL: a bank, account, loan or flow is not empty';
  end if;
  if public.wc('bank_enabled') <> 'false'::jsonb or public.wc('bank_npc_deposit') <> 'false'::jsonb or public.wc('bank_seed_per_nation') <> to_jsonb(0)
     or public.wc('bank_min_ducats') <> to_jsonb(1000) or public.wc('bank_rate_per_day') <> to_jsonb(0.003) or public.wc('bank_term_days') <> to_jsonb(30)
     or public.wc('bank_reserve_pct') <> to_jsonb(0.2) or public.wc('bank_low_water_days') <> to_jsonb(3) or public.wc('bank_target_days') <> to_jsonb(7)
     or public.wc('bank_cap_tax_days') <> to_jsonb(20) or public.wc('bank_default_days') <> to_jsonb(10) or public.wc('bank_cooldown_days') <> to_jsonb(30)
     or (select count(*) from public.world_config where key like 'bank\_%') <> 12 then
    raise exception '0306 self-assert FAIL: the bank knobs are not the 12 written (bank_enabled false)';
  end if;

  -- (b) a bank at a non-capital port is refused: a new nation, then a bank off its capital; and a bank moved off its capital (rolled back)
  select p.id into v_other_port from public.ports p
   where not exists (select 1 from public.nations n where n.capital_port_code = p.code) order by p.code limit 1;
  begin
    insert into public.nations (code, name, flag_char, capital_port_code) values ('ZZ0306', 'Probe 0306', 'Z', (select capital_port_code from public.nations order by code limit 1))
      returning id into v_nation;
    insert into public.banks (nation_id, port_id) values (v_nation, v_other_port);
    raise exception '0306 self-assert FAIL: a bank at a non-capital port was accepted';
  exception when check_violation then null;
  end;
  begin
    update public.banks set port_id = v_other_port where nation_id = (select id from public.nations order by code limit 1);
    raise exception '0306 self-assert FAIL: a bank was moved off its capital';
  exception when check_violation then null;
  end;
  begin
    delete from public.banks where nation_id = (select id from public.nations order by code limit 1);
    insert into public.banks (nation_id, port_id) values ((select id from public.nations order by code limit 1), v_other_port);
    raise exception '0306 self-assert FAIL: a re-seated bank at a non-capital port was accepted';
  exception when check_violation then null;
  end;

  -- (c) bank_flows is append-only; the unit price on a probe (all rolled back)
  begin
    select n.id into v_nation from public.nations n order by n.code limit 1;
    insert into public.bank_flows (nation_id, kind, amount) values (v_nation, 'SEED', 1);
    begin
      update public.bank_flows set amount = 2 where nation_id = v_nation;
      raise exception '0306 self-assert FAIL: a bank flow was updated';
    exception when insufficient_privilege then null;
    end;
    begin
      delete from public.bank_flows where nation_id = v_nation;
      raise exception '0306 self-assert FAIL: a bank flow was deleted';
    exception when insufficient_privilege then null;
    end;
    if public.bank_unit_price(v_nation) <> 1.0 then
      raise exception '0306 self-assert FAIL: bank_unit_price is not 1.0 while units = 0';
    end if;
    update public.banks set units = 100, vault = 150 where nation_id = v_nation;
    insert into public.bank_loans (nation_id, port_id, principal, outstanding, rate_per_day, term_days, due_at)
      values (v_nation, v_other_port, 60, 50, 0.003, 30, now() + interval '30 days');
    if public.bank_unit_price(v_nation) <> 2.0 then
      raise exception '0306 self-assert FAIL: bank_unit_price is % , not (150 + 50) / 100', public.bank_unit_price(v_nation);
    end if;
    raise exception 'PROBE_0306_ROLLBACK';
  exception when others then
    if sqlerrm <> 'PROBE_0306_ROLLBACK' then raise; end if;
  end;
  if exists (select 1 from public.bank_flows) or exists (select 1 from public.bank_loans) or exists (select 1 from public.nations where code = 'ZZ0306')
     or exists (select 1 from public.banks where units <> 0 or vault <> 0) or (select count(*) from public.banks) <> 23 then
    raise exception '0306 self-assert FAIL: a probe row survived its rollback';
  end if;
  select public.bank_unit_price(n.id) into v_price from public.nations n order by n.code limit 1;
  if v_price <> 1.0 or public.bank_unit_price('00000000-0000-0000-0000-000000000000') is not null then
    raise exception '0306 self-assert FAIL: the dark unit price is not 1.0 (null for no bank)';
  end if;

  -- (d) reach: the reader and the trigger function are server-only; flows are the server's; accounts, loans and banks are read-only to a client
  for r in select f from unnest(c_new_fns) f loop
    if to_regprocedure(r.f) is null
       or has_function_privilege('anon', to_regprocedure(r.f), 'execute') or has_function_privilege('authenticated', to_regprocedure(r.f), 'execute') then
      raise exception '0306 self-assert FAIL: % is not server-only', r.f;
    end if;
  end loop;
  if (select p.provolatile from pg_proc p where p.oid = 'public.bank_unit_price(uuid)'::regprocedure) <> 's'
     or not (select p.prosecdef from pg_proc p where p.oid = 'public.bank_unit_price(uuid)'::regprocedure) then
    raise exception '0306 self-assert FAIL: bank_unit_price is not STABLE and security definer';
  end if;
  if has_table_privilege('anon', 'public.banks', 'select') or has_table_privilege('anon', 'public.bank_loans', 'select')
     or has_table_privilege('anon', 'public.bank_accounts', 'select')
     or has_table_privilege('authenticated', 'public.bank_flows', 'select') or has_table_privilege('authenticated', 'public.bank_flows', 'insert')
     or has_table_privilege('authenticated', 'public.banks', 'insert') or has_table_privilege('authenticated', 'public.banks', 'update')
     or has_table_privilege('authenticated', 'public.bank_accounts', 'insert') or has_table_privilege('authenticated', 'public.bank_accounts', 'update')
     or has_table_privilege('authenticated', 'public.bank_loans', 'insert') or has_table_privilege('authenticated', 'public.bank_loans', 'update')
     or not has_table_privilege('authenticated', 'public.bank_accounts', 'select') then
    raise exception '0306 self-assert FAIL: a bank table is reachable by a client beyond its read rule';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0 or (select count(*) from public.client_executable_writers()) <> 0 then
    raise exception '0306 self-assert FAIL: a client role holds a write grant or a writer function';
  end if;

  -- (e) nothing else moved: every existing function, every existing knob
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select to_regprocedure(x)::oid from unnest(c_new_fns) x))) <> v_fn_before then
    raise exception '0306 self-assert FAIL: an existing function changed';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key not like 'bank\_%') <> v_cfg_before then
    raise exception '0306 self-assert FAIL: an existing world_config row moved';
  end if;

  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0306 self-assert FAIL: the self-assert took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0306 self-assert ok: 23 banks, each at its nation''s capital, empty (units 0, vault 0); a bank off its capital refused (insert, move, re-seat); bank_flows UPDATE and DELETE refused; bank_unit_price 1.0 at units 0 and (150 + 50) / 100 = 2.0 on a rolled-back probe; 12 knobs, bank_enabled false; client reach as written; no existing function or knob moved (% ms)',
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
