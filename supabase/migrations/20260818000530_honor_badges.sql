-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights it)
-- 0530 - HONOR BADGES  (dark: honor_enabled, false)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25 (R4): "The land site expedition in addition should give another currency called HONOR BADGE - where you can use to
--   upgrade CAPTAINS." Section 2: from LAND expeditions only, spent only on captains; not Reputation and not coin.
--   docs/design/captains-land-2026-11-25.md section 7; docs/dev-log/2026-11-25-captain-works.md.
--
-- WHAT (lit; dark nothing is booked):
--   public.honor_kinds        DATA: one earn kind (land) and one spend kind (captain_upgrade), and the table itself holds no other.
--   public.honor_balance      a company's badges. public.honor_book: the book, append-only (public.forbid_mutation) and a chain, as 0352's.
--   public.honor_credit       THE ONE WRITER: signs checked against the kind, a once-ever key, never below nothing (E_NOT_ENOUGH_HONOR). A merchant: nothing.
--   the reconcile             at commit the balance is the book's newest row, as 0352's reputation_reconciles.
--   world.captains (1 hunk)   lit, `honor`: her badges; dark no key.
-- NO EARNER AND NO SPENDER YET: the land expedition (0534) earns, the captain upgrades (0533) spend.
-- ROWS: 2 data rows, 1 config row; 0 a minute (0534: one a party home, about 240 a day at 60 companies).
-- budget: no cron job, no autovacuum or fillfactor change; three tables.
-- LOCKS: CREATE TABLE x3 (foreign keys on players: SHARE ROW EXCLUSIVE for an instant, under lock_timeout 5 s).
-- RESTART (0509): nothing to add. Like Reputation's, a closed company's balance and book stay its old row's record, unreachable.
-- ROLLBACK (forward, owner only): honor_enabled false.
-- SELF-ASSERT: the hunk once and reversing; no other function or knob moved; no body but the honor functions and world.captains names the
--   tables, so nothing else earns or spends; then a probe company, rolled back: dark nothing; signs, the key, the floor, the chain and the
--   append-only book; the reconcile refuses a balance that is not the book's.
-- VERSION: 0530.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $m$
declare
  c_hunked constant text[] := array['world.captains()']::text[];
  c_new    constant text[] := array['public.honor_on()', 'public.honor_book_chains()', 'public.honor_reconciles()', 'public.honor_credit(uuid,text,integer,text,jsonb)']::text[];
  c_doors  constant text[] := array[]::text[];
  c_knobs  constant text[] := array['honor_enabled']::text[];
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_q         text;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_cfg_before text;
  v_lived     boolean := false;
  v_note      text := '';
  v_me uuid; v_np uuid; v_bad int := 0;
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = any (c_knobs)) or exists (select 1 from unnest(c_new) u(q) where to_regprocedure(u.q) is not null) then
    raise exception '0530 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked) u(q) where to_regprocedure(u.q) is null) or to_regprocedure('public.captain_places_on()') is null then
    raise exception '0530 refuses: a body it cuts or a reading it asks is not in this world';
  end if;

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

  -- ── 2. THE TABLES ──

  -- retention: none, bounded by the two kinds the table's own check allows
  create table public.honor_kinds (
    code text primary key check (code in ('land', 'captain_upgrade')),
    sign smallint not null check (sign = case code when 'land' then 1 else -1 end),
    word text not null);
  alter table public.honor_kinds enable row level security;
  revoke all on table public.honor_kinds from public, anon, authenticated, service_role;
  insert into public.honor_kinds (code, sign, word) values ('land', 1, 'Land expedition'), ('captain_upgrade', -1, 'Captain upgrade');
  -- retention: none, bounded by one row a company
  create table public.honor_balance (
    player_id uuid primary key references public.players(id) on delete cascade,
    balance   int not null default 0 check (balance >= 0),
    seq       int not null default 0 check (seq >= 0));
  alter table public.honor_balance enable row level security;
  revoke all on table public.honor_balance from public, anon, authenticated, service_role;
  comment on table public.honor_balance is '0530: a company''s HONOR BADGES: the newest book row''s balance_after (seq names it). Writer: public.honor_credit. Server only.';
  -- retention: append-only as reputation_book (the record of a currency); about one row a party home
  create table public.honor_book (
    player_id     uuid not null references public.players(id) on delete cascade,
    seq           int  not null check (seq >= 1),
    kind          text not null references public.honor_kinds(code),
    delta         int  not null check (delta <> 0),
    balance_after int  not null check (balance_after >= 0),
    key           text,
    note          jsonb not null default '{}'::jsonb,
    created_at    timestamptz not null default now(),
    primary key (player_id, seq));
  create unique index honor_book_once on public.honor_book (player_id, key) where key is not null;
  alter table public.honor_book enable row level security;
  revoke all on table public.honor_book from public, anon, authenticated, service_role;
  comment on table public.honor_book is '0530: the honor book, APPEND-ONLY (public.forbid_mutation) and a CHAIN (public.honor_book_chains). key: once ever. Writer: public.honor_credit. Server only.';

  -- ── 3. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('honor_enabled', 'false'::jsonb, '0530: THE SWITCH (the owner''s). true: honor badges are booked (earned by land expeditions alone, spent on captains alone). false: nothing is booked.');

  -- ── 4. THE RULES ──

  execute $f$
create function public.honor_on()
returns boolean language sql stable security definer set search_path = public, pg_temp
as $body$
  -- 0530: THE SWITCH, read once: world_config honor_enabled.
  select public.wc('honor_enabled') = 'true'::jsonb
$body$
  $f$;

  execute $f$
create function public.honor_book_chains()
returns trigger language plpgsql
as $body$
-- 0530: a book row follows the row before it and its kind's sign. Two primary-key probes; no sum.
begin
  if (select k.sign from public.honor_kinds k where k.code = new.kind) <> sign(new.delta) then
    raise exception 'honor_book: % books %', new.kind, new.delta using errcode = '23514';
  end if;
  if new.seq = 1 then
    if new.balance_after <> new.delta then
      raise exception 'honor_book: row 1 of % opens at %, not at its own delta %', new.player_id, new.balance_after, new.delta using errcode = '23514';
    end if;
  elsif not exists (select 1 from public.honor_book b where b.player_id = new.player_id and b.seq = new.seq - 1 and b.balance_after + new.delta = new.balance_after) then
    raise exception 'honor_book: row % of % does not follow row %', new.seq, new.player_id, new.seq - 1 using errcode = '23514';
  end if;
  return new;
end
$body$
  $f$;

  execute $f$
create function public.honor_reconciles()
returns trigger language plpgsql security definer set search_path = public, pg_temp
as $body$
-- 0530: at the end of the transaction the balance is the newest book row's, and no row stands past it (as public.reputation_reconciles).
declare
  b public.honor_balance%rowtype;
begin
  select * into b from public.honor_balance x where x.player_id = new.player_id;
  if not found
     or (b.seq = 0 and b.balance <> 0)
     or (b.seq > 0 and not exists (select 1 from public.honor_book k where k.player_id = b.player_id and k.seq = b.seq and k.balance_after = b.balance))
     or exists (select 1 from public.honor_book k where k.player_id = new.player_id and k.seq = coalesce(b.seq, 0) + 1) then
    raise exception 'honor: the balance of % is not its newest book row''s', new.player_id using errcode = '23514';
  end if;
  return null;
end
$body$
  $f$;

  execute $f$
create function public.honor_credit(p_player uuid, p_kind text, p_amount int, p_key text default null, p_note jsonb default '{}'::jsonb)
returns int language plpgsql security definer set search_path = public, pg_temp
as $body$
-- 0530: THE ONE WRITER of HONOR BADGES. Earns are positive, spends negative: the sign is the kind's. Returns what was booked: 0 while dark, for
-- a merchant, for nothing, or for a key already booked. A spend past her badges is refused (E_NOT_ENOUGH_HONOR, have / need).
declare
  k public.honor_kinds%rowtype;
  b public.honor_balance%rowtype;
begin
  if not public.honor_on() or p_player is null or coalesce(p_amount, 0) = 0
     or coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then
    return 0;
  end if;
  select * into k from public.honor_kinds x where x.code = p_kind;
  if k.code is null or sign(p_amount) <> k.sign then
    raise exception 'honor_credit: % does not book %', coalesce(p_kind, 'no kind'), p_amount using errcode = '22023';
  end if;
  insert into public.honor_balance (player_id) values (p_player) on conflict (player_id) do nothing;
  select * into b from public.honor_balance x where x.player_id = p_player for update;
  -- under the lock: two calls with one key book once
  if p_key is not null and exists (select 1 from public.honor_book x where x.player_id = p_player and x.key = p_key) then
    return 0;
  end if;
  if b.balance + p_amount < 0 then
    perform cmd.refuse('E_NOT_ENOUGH_HONOR', format('Needs %s badges: you have %s', -p_amount, b.balance), cmd.figures(b.balance, -p_amount, 'badges'));
  end if;
  insert into public.honor_book (player_id, seq, kind, delta, balance_after, key, note)
  values (p_player, b.seq + 1, p_kind, p_amount, b.balance + p_amount, p_key, coalesce(p_note, '{}'::jsonb));
  update public.honor_balance set balance = b.balance + p_amount, seq = b.seq + 1 where player_id = p_player;
  return p_amount;
end
$body$
  $f$;

  foreach v_q in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_q::regprocedure);
  end loop;
  foreach v_q in array c_doors loop
    execute format('grant execute on function %s to authenticated', v_q::regprocedure);
  end loop;

  -- ── 5. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0530 (fn text, ord int, old text, new text) on commit drop;

  insert into hunks_0530 values ('world.captains()', 1,
$h$  return case when public.captain_places_on() then$h$,
$h$  return case when public.honor_on() then jsonb_build_object('honor', coalesce((select hb.balance from public.honor_balance hb where hb.player_id = v_player), 0)) else '{}'::jsonb end   -- 0530
      || case when public.captain_places_on() then$h$);


  for v_h in select h.fn from hunks_0530 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0530 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0530 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0530 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0530 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0530 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 6. SELF-ASSERT: the catalog, the grants, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0530 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) is distinct from v_meta then
    raise exception '0530 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('anon', u.q::regprocedure, 'execute') or has_function_privilege('service_role', u.q::regprocedure, 'execute')
                 or has_function_privilege('authenticated', u.q::regprocedure, 'execute') <> (u.q = any (c_doors)))
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0530 self-assert FAIL: a new function is reachable by a client that should not reach it, or a client may write';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before then
    raise exception '0530 self-assert FAIL: a knob of another file moved';
  end if;
  create trigger honor_book_chains before insert on public.honor_book for each row execute function public.honor_book_chains();
  create trigger honor_book_append_only before update or delete on public.honor_book for each row execute function public.forbid_mutation();
  create constraint trigger honor_book_reconciles after insert on public.honor_book deferrable initially deferred for each row execute function public.honor_reconciles();
  create constraint trigger honor_balance_reconciles after insert or update on public.honor_balance deferrable initially deferred for each row execute function public.honor_reconciles();
  -- nothing else earns or spends: only these bodies name the tables
  if (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.prosrc ~ 'honor_(book|balance|kinds|credit)')
     is distinct from 'honor_book_chains(),honor_credit(uuid,text,integer,text,jsonb),honor_reconciles(),world.captains()' then
    raise exception '0530 self-assert FAIL: another body names the badges: %', (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.prosrc ~ 'honor_(book|balance|kinds|credit)');
  end if;

  -- ── 7. THE PROBE, rolled back by a raised sentinel (its own companies' rows) ──
  begin

    v_me := public.new_house('00000000-0530-4000-8000-000000000001', 'Casa da Honra 0530', 'PRT');
    perform cmd.assume_identity('00000000-0530-4000-8000-000000000001');
    -- DARK
    if public.honor_credit(v_me, 'land', 5) <> 0 then
      raise exception '0530 self-assert FAIL: dark, badges were booked';
    end if;
    if exists (select 1 from public.honor_balance hx where hx.player_id = v_me) or world.captains() ? 'honor' then
      raise exception '0530 self-assert FAIL: dark, something is open';
    end if;
    update public.world_config set value = 'true'::jsonb where key = 'honor_enabled';
    if (world.captains()->>'honor')::int <> 0 then
      raise exception '0530 self-assert FAIL: a new company''s badges are not 0';
    end if;
    -- a merchant: a company of this file's own marked so
    v_np := public.new_house(null, 'Mercador 0530', 'NLD', p_is_npc => true);
    if public.honor_credit(v_np, 'land', 5) <> 0 or public.honor_credit(null, 'land', 5) <> 0 or public.honor_credit(v_me, 'land', 0) <> 0 then
      raise exception '0530 self-assert FAIL: booked what it must not';
    end if;
    -- signs and kinds
    begin perform public.honor_credit(v_me, 'land', -5); exception when invalid_parameter_value then v_bad := v_bad + 1; end;
    begin perform public.honor_credit(v_me, 'captain_upgrade', 5); exception when invalid_parameter_value then v_bad := v_bad + 1; end;
    begin perform public.honor_credit(v_me, 'raid', 5); exception when invalid_parameter_value then v_bad := v_bad + 1; end;
    begin insert into public.honor_kinds (code, sign, word) values ('raid', 1, 'Raid'); exception when check_violation then v_bad := v_bad + 1; end;
    if v_bad <> 4 then
      raise exception '0530 self-assert FAIL: a wrong sign or kind was taken (% of 4 refused)', v_bad;
    end if;
    -- earn, the key once, spend, the floor
    v_n := public.honor_credit(v_me, 'land', 7, 'land:a');
    v_n := v_n + public.honor_credit(v_me, 'land', 7, 'land:a');
    v_n := v_n + public.honor_credit(v_me, 'land', 3, 'land:b');
    v_n := v_n + public.honor_credit(v_me, 'captain_upgrade', -4);
    if v_n <> 6 or (select hx.balance from public.honor_balance hx where hx.player_id = v_me) <> 6 or (world.captains()->>'honor')::int <> 6
       or (select string_agg(k.seq || ':' || k.delta || ':' || k.balance_after, ',' order by k.seq) from public.honor_book k where k.player_id = v_me) <> '1:7:7,2:3:10,3:-4:6' then
      raise exception '0530 self-assert FAIL: the book is not 7, 3, -4';
    end if;
    begin
      perform public.honor_credit(v_me, 'captain_upgrade', -7);
      raise exception '0530 self-assert FAIL: spent more than she has';
    exception when others then
      if sqlerrm !~ '^E_NOT_ENOUGH_HONOR' then raise; end if;
    end;
    -- the chain, the append-only book, the reconcile
    v_bad := 0;
    begin insert into public.honor_book (player_id, seq, kind, delta, balance_after) values (v_me, 4, 'land', 5, 99); exception when check_violation then v_bad := v_bad + 1; end;
    begin insert into public.honor_book (player_id, seq, kind, delta, balance_after) values (v_me, 4, 'captain_upgrade', 5, 11); exception when check_violation then v_bad := v_bad + 1; end;
    begin update public.honor_book set delta = 8 where player_id = v_me and seq = 1; exception when others then v_bad := v_bad + 1; end;
    begin delete from public.honor_book where player_id = v_me and seq = 3; exception when others then v_bad := v_bad + 1; end;
    begin
      update public.honor_balance set balance = 60 where player_id = v_me;
      set constraints public.honor_book_reconciles, public.honor_balance_reconciles immediate;
      raise exception '0530 self-assert FAIL: a balance that is not the book''s stood';
    exception when check_violation then v_bad := v_bad + 1;
    end;
    if v_bad <> 5 then
      raise exception '0530 self-assert FAIL: the book or the balance could be bent (% of 5 refused)', v_bad;
    end if;
    set constraints public.honor_book_reconciles, public.honor_balance_reconciles immediate;
    raise exception using errcode = 'ZX530', message = 'PROBE_ROLLBACK_0530';
  exception when sqlstate 'ZX530' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0530 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.auth_uid::text like '00000000-0530-4000-8000-%') or public.wc('honor_enabled') is distinct from 'false'::jsonb then
    raise exception '0530 self-assert FAIL: the probe left something behind';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0530 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0530 self-assert ok: HONOR BADGES (dark). One hunk once and reversing; four new functions server only; one earn kind and one spend kind; no other function or knob moved. Probe (rolled back) whole. % ms. %', round(extract(epoch from clock_timestamp() - v_t0) * 1000), v_note;
end $m$;
