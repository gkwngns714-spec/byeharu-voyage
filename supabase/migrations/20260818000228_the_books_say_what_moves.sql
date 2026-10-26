-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0228 — THE BOOKS SAY WHAT MOVES
--        (slice E1 of docs/CLOSED_ECONOMY.md: the closed-economy flag, dark; the Stats words that call
--         city-to-city money "new money" corrected; the capital's gift book, empty; the investment column)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM (docs/OWNER_REQUESTS.md row 212, 2026-10-26) ────────────────────────────
--   "i want city to restock trade goods based on their invested amount. i want prices to be moved like
--    stocks, and i want the gold to be stopped here, meaning no more excess gold produced - so that the
--    economy circulates like real world."  … "yes, but broke merchants will receive donation (starting
--    money) from their capital city (show this too). lets try this model and see the stats after few days."
--
-- ── WHAT THIS FILE DOES (and nothing else; every later slice reads what it lays down) ───────────
--   1. THE FLAG. world_config.economy_closed = false, and ONE reader, public.economy_closed(). Nothing reads
--      it yet: E3–E7 gate on it; E7 lights it by `select public.economy_close_switch(true)`.
--   2. THE WORDS (public.stats_flow_words, 0214). CROWN_AID and CROWN_TAX are a city paying a city (0123's
--      crown: a capital's aid to its realm, a city's tenth to its capital) — no company on either side, but
--      no ducat is printed or burned either: the world's total does not move. 0214 sided them minted /
--      removed, so the Stats tab's "new money" and "burned" counted money that only changed purse. Both are
--      now MOVED. Two kinds are added, MOVED, for E4: CAPITAL_GIFT (a capital pays a broke merchant her
--      starting money) and CROWN_CALL (a capital calls the gap from its realm's richest harbour). After this
--      file the minted kinds are exactly EARNINGS, IMPORT_DEMAND, SEED, GRANT, FOUNDING, NPC_REFOUND and the
--      one removed kind is none. Only the Stats tab's reading changes, from the next count on; no purse,
--      price or flow moves. (Rows already counted keep the figures they were counted with.)
--   3. THE GIFT BOOK. public.capital_gifts(id, port_id, player_id, ducats, called_from, created_at), indexed
--      (port_id, created_at), APPEND-ONLY by 0004's one trigger function public.forbid_mutation (the same
--      rule as events and ledger, its 0097 exemption included: npc_compact alone may delete a merchant's
--      row). RLS on, read by any signed-in player (the Town Hall's "Gifts" list, E4), written by nobody yet.
--   4. THE INVESTMENT. port_treasury.invested bigint, NULLABLE, null everywhere: E5's tick_city roll is its
--      one writer, E7's switch seeds it. A null reads as "not tracked yet".
--
-- ── DARK ────────────────────────────────────────────────────────────────────────────────────────
--   No body is re-cut. The flag is false and read by nothing; the table is empty; the column is null.
--
-- ── WHAT IT SELF-ASSERTS (own probe rows; the probe is rolled back whole) ───────────────────────
--   (a) the knob is false and described; economy_closed() returns false; server-only (no client executes it).
--   (b) the words: CROWN_AID and CROWN_TAX moved; CAPITAL_GIFT and CROWN_CALL present and moved; the minted
--       set is exactly the six kinds above; the removed set is empty; every other row is as 0214 wrote it.
--   (c) capital_gifts exists, is EMPTY, has RLS, SELECT to authenticated only (not anon), no client write;
--       a probe gift (a probe company at Lisbon) is written, then UPDATE and DELETE of it are refused with
--       42501; the probe is rolled back and the table is empty again.
--   (d) port_treasury.invested exists, is nullable, and is null on every row (a new column: nothing wrote it).
--   (e) the three walls at 0; the registry unchanged.
-- ROLLBACK (forward): drop the table, the column, the reader and the knob; restore the four word rows to
-- 0214's ('CROWN_AID' minted 'New money: crown aid' 4; 'CROWN_TAX' removed 'Crown tax' 10); delete the two
-- added word rows.
-- VERSION: 0228 = prod head 0226 + 0227 (in flight) + 1 at the time of writing — RENUMBER TO PROD HEAD + 1
-- AT PUSH (and the _0228 suffixes, the probe uuid and this header's tags with it).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '5min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regclass('public.stats_flow_words') is null or to_regclass('public.port_treasury') is null
     or to_regprocedure('public.forbid_mutation()') is null or to_regprocedure('public.new_house(uuid,text,text,text,text,text,text,bigint,boolean)') is null then
    raise exception '0228 refuses: 0004, 0122 or 0214 is not in this world';
  end if;
  if exists (select 1 from public.world_config where key = 'economy_closed') or to_regclass('public.capital_gifts') is not null then
    raise exception '0228 refuses: economy_closed or capital_gifts already exists — this has been applied once';
  end if;
end $guard$;

create temp table before_0228 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select jsonb_object_agg(w.kind, jsonb_build_array(w.side, w.word, w.ord)) from public.stats_flow_words w
         where w.kind not in ('CROWN_AID', 'CROWN_TAX', 'CAPITAL_GIFT', 'CROWN_CALL')) as other_words;

-- ── 1. THE FLAG AND ITS ONE READER ─────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('economy_closed', to_jsonb(false),
   '0228 (docs/CLOSED_ECONOMY.md): false = today''s economy, byte for byte. true = no new gold: EARNINGS, IMPORT_DEMAND and SEED stop, FOUNDING is paid by the country''s capital, broke merchants get a CAPITAL_GIFT. Read only through public.economy_closed(); set only by public.economy_close_switch (E7), never by hand.');

create function public.economy_closed()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0228: THE ONE reader of the closed-economy flag (docs/CLOSED_ECONOMY.md §0.1). Every gate of E3–E7 asks here.
  select (public.wc('economy_closed'))::boolean
$$;
comment on function public.economy_closed() is
  '0228: THE ONE reader of world_config.economy_closed — false while dark. Server-only.';
revoke all on function public.economy_closed() from public, anon, authenticated;

-- ── 2. THE WORDS: city-to-city money is MOVED, and the two kinds of E4 are named ───────────────
update public.stats_flow_words set side = 'moved', word = 'Crown aid', ord = 37 where kind = 'CROWN_AID';
update public.stats_flow_words set side = 'moved', word = 'Crown tax', ord = 38 where kind = 'CROWN_TAX';
insert into public.stats_flow_words (kind, side, word, ord) values
  ('CAPITAL_GIFT', 'moved', 'Capital gifts', 39),
  ('CROWN_CALL',   'moved', 'Crown calls',   40);

-- ── 3. THE GIFT BOOK (append-only, empty) ──────────────────────────────────────────────────────
create table public.capital_gifts (
  id          bigint generated always as identity primary key,
  port_id     uuid   not null references public.ports(id),
  player_id   uuid   not null references public.players(id) on delete cascade,
  ducats      bigint not null check (ducats > 0),
  called_from uuid   references public.ports(id),
  created_at  timestamptz not null default now()
);
create index capital_gifts_port_created on public.capital_gifts (port_id, created_at);
comment on table public.capital_gifts is
  '0228 (docs/CLOSED_ECONOMY.md §5.2): one row per gift a country''s capital (port_id) paid a broke merchant company '
  '(player_id) — her starting money, `ducats`; called_from = the realm harbour the capital called the gap from '
  '(CROWN_CALL), null when the capital paid alone. APPEND-ONLY (public.forbid_mutation, as events and ledger). '
  'Written by E4''s gift pass alone; read by any signed-in player.';
create trigger capital_gifts_append_only
  before update or delete on public.capital_gifts
  for each row execute function public.forbid_mutation();
alter table public.capital_gifts enable row level security;
revoke all on table public.capital_gifts from public, anon, authenticated;
revoke all on sequence public.capital_gifts_id_seq from public, anon, authenticated;
grant select on table public.capital_gifts to authenticated;
create policy capital_gifts_read on public.capital_gifts for select to authenticated using (true);

-- ── 4. THE INVESTMENT COLUMN (null until E5 writes it) ─────────────────────────────────────────
alter table public.port_treasury add column invested bigint check (invested >= 0);
comment on column public.port_treasury.invested is
  '0228 (docs/CLOSED_ECONOMY.md §3): the money put into this city, decayed (half-life 3 real days): '
  'I ← round(I × 0.5^(1/72)) + this hour''s SHARE + DONATION. One writer: tick_city''s roll (E5); seeded by '
  'economy_close_switch (E7). Null = not tracked yet.';

-- ── 5. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid    constant uuid := '00000000-0228-4000-8000-000000000001';
  v_before record;
  v_p      uuid;
  v_port   uuid;
  v_id     bigint;
  v_state  text;
  v_out    jsonb;
begin
  select * into v_before from before_0228;

  -- (a) the flag
  if (select value from public.world_config where key = 'economy_closed') <> 'false'::jsonb
     or public.economy_closed() is distinct from false then
    raise exception '0228 self-assert FAIL: the flag is not false (knob %, reader %)',
      (select value from public.world_config where key = 'economy_closed'), public.economy_closed();
  end if;
  if has_function_privilege('authenticated', 'public.economy_closed()', 'execute')
     or has_function_privilege('anon', 'public.economy_closed()', 'execute') then
    raise exception '0228 self-assert FAIL: a client role can execute public.economy_closed()';
  end if;

  -- (b) the words
  if (select count(*) from public.stats_flow_words where kind in ('CROWN_AID', 'CROWN_TAX', 'CAPITAL_GIFT', 'CROWN_CALL') and side = 'moved') <> 4 then
    raise exception '0228 self-assert FAIL: CROWN_AID, CROWN_TAX, CAPITAL_GIFT, CROWN_CALL are not all moved';
  end if;
  if (select array_agg(kind order by kind) from public.stats_flow_words where side = 'minted')
       <> array['EARNINGS', 'FOUNDING', 'GRANT', 'IMPORT_DEMAND', 'NPC_REFOUND', 'SEED'] then
    raise exception '0228 self-assert FAIL: the minted kinds are %, not the six', (select array_agg(kind order by kind) from public.stats_flow_words where side = 'minted');
  end if;
  if exists (select 1 from public.stats_flow_words where side = 'removed') then
    raise exception '0228 self-assert FAIL: a removed kind is still named: %', (select array_agg(kind) from public.stats_flow_words where side = 'removed');
  end if;
  if (select jsonb_object_agg(w.kind, jsonb_build_array(w.side, w.word, w.ord)) from public.stats_flow_words w
       where w.kind not in ('CROWN_AID', 'CROWN_TAX', 'CAPITAL_GIFT', 'CROWN_CALL')) is distinct from v_before.other_words then
    raise exception '0228 self-assert FAIL: a word row other than the four moved';
  end if;

  -- (c) the gift book: empty, readable by authenticated alone, append-only on a probe row
  if exists (select 1 from public.capital_gifts) then
    raise exception '0228 self-assert FAIL: capital_gifts is not empty';
  end if;
  if not (select c.relrowsecurity from pg_class c where c.oid = 'public.capital_gifts'::regclass)
     or not has_table_privilege('authenticated', 'public.capital_gifts', 'select')
     or has_table_privilege('anon', 'public.capital_gifts', 'select')
     or has_table_privilege('authenticated', 'public.capital_gifts', 'insert')
     or has_table_privilege('authenticated', 'public.capital_gifts', 'update')
     or has_table_privilege('authenticated', 'public.capital_gifts', 'delete')
     or not exists (select 1 from pg_policy p where p.polrelid = 'public.capital_gifts'::regclass and p.polname = 'capital_gifts_read') then
    raise exception '0228 self-assert FAIL: capital_gifts is not RLS-on, read by authenticated only, written by no client';
  end if;
  begin
    if exists (select 1 from public.players p where p.auth_uid = c_uid or p.company_name = 'Casa das Dádivas 0228') then
      raise exception '0228 self-assert FAIL: the probe house already exists';
    end if;
    v_p := public.new_house(c_uid, 'Casa das Dádivas 0228', 'PRT', 'LIS');
    select p.id into v_port from public.ports p where p.code = 'LIS';
    insert into public.capital_gifts (port_id, player_id, ducats) values (v_port, v_p, 5000) returning id into v_id;
    if (select count(*) from public.capital_gifts g where g.id = v_id and g.player_id = v_p and g.ducats = 5000 and g.called_from is null) <> 1 then
      raise exception '0228 self-assert FAIL: the probe gift was not written';
    end if;
    v_state := null;
    begin
      update public.capital_gifts set ducats = 1 where id = v_id;
    exception when others then
      get stacked diagnostics v_state = returned_sqlstate;
    end;
    if v_state is distinct from '42501' then
      raise exception '0228 self-assert FAIL: an UPDATE of a gift was not refused (sqlstate %)', v_state;
    end if;
    v_state := null;
    begin
      delete from public.capital_gifts where id = v_id;
    exception when others then
      get stacked diagnostics v_state = returned_sqlstate;
    end;
    if v_state is distinct from '42501' then
      raise exception '0228 self-assert FAIL: a DELETE of a gift was not refused (sqlstate %)', v_state;
    end if;
    if (select count(*) from public.capital_gifts g where g.id = v_id and g.ducats = 5000) <> 1 then
      raise exception '0228 self-assert FAIL: the probe gift changed under a refused write';
    end if;
    raise exception using errcode = 'ZX228', message = jsonb_build_object('gift', v_id)::text;
  exception when sqlstate 'ZX228' then
    v_out := sqlerrm::jsonb;
  end;
  if exists (select 1 from public.capital_gifts) or exists (select 1 from public.players p where p.auth_uid = c_uid) then
    raise exception '0228 self-assert FAIL: the probe left rows behind';
  end if;

  -- (d) the investment column
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'port_treasury' and column_name = 'invested'
                    and data_type = 'bigint' and is_nullable = 'YES')
     or exists (select 1 from public.port_treasury t where t.invested is not null) then
    raise exception '0228 self-assert FAIL: port_treasury.invested is not a nullable bigint, null on every row';
  end if;

  -- (e) the walls and the registry
  if (select count(*) from public.client_rpc_entry_points()) <> v_before.entry_points then
    raise exception '0228 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0228 self-assert FAIL: a wall moved';
  end if;

  raise notice '0228 self-assert ok: THE BOOKS SAY WHAT MOVES. economy_closed false (one reader, server-only); CROWN_AID and CROWN_TAX now moved, CAPITAL_GIFT and CROWN_CALL added (moved); minted = EARNINGS, FOUNDING, GRANT, IMPORT_DEMAND, NPC_REFOUND, SEED; nothing removed. capital_gifts empty, RLS read by authenticated, append-only (probe gift % refused UPDATE and DELETE with 42501, rolled back). port_treasury.invested null on every row. Registry unchanged; walls 0.',
    v_out->>'gift';
end $$;
