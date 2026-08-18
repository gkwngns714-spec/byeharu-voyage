-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0004 — A HOUSE, ITS FLEETS, AND AN HONEST LEDGER
--        Players, fleets, ships — and the rule that a player's purse is not a number somebody
--        writes, it is the sum of an append-only ledger.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE INVARIANT THIS FILE EXISTS FOR ──────────────────────────────────────────────────────────
--   docs/DESIGN.md Appendix 1: "Σ ledger.ducats_delta = players.ducats per player."
--   §G.7.8: "an exploit that inflates ducats does not silently inflate rank; the two are
--   separately auditable and CAN BE RECONCILED."
--
--   Reconciliation you run hourly and hope about is not an invariant. This file makes it a
--   CONSTRAINT: two DEFERRABLE INITIALLY DEFERRED constraint triggers, one on each side of the
--   equation, both calling ONE check function. Deferred, because `credit()` must move the purse
--   and write the ledger row in the same breath and an immediate trigger would fire between them
--   and reject a correct write. At COMMIT the two sides must agree or the whole transaction dies.
--
-- ── ONE AUTHORITY PER CONCEPT ───────────────────────────────────────────────────────────────────
--   public.credit()               — THE ONLY way ducats move. Nothing else may UPDATE players.ducats.
--   public.emit_event()           — THE ONLY way a row enters `events`.
--   public.current_player_id()    — THE ONLY translation from auth.uid() to a player id. Every RLS
--                                   policy in the chain calls it; none re-derives it.
--   public.assert_ledger_reconciles() — THE ONLY statement of the purse invariant, called from
--                                   both triggers, from 0010's reconcile tick, and from the proof.
--   public.forbid_mutation()      — THE ONLY append-only enforcement, attached to events + ledger.
--
-- ── STRUCTURAL RULES, NOT CONVENTIONS ───────────────────────────────────────────────────────────
--   * A ship's fleet must belong to the SAME player: enforced by a composite FK
--     (fleet_id, player_id) -> fleets(id, player_id), so no writer can produce a crossed pair.
--   * A fleet has AT MOST ONE flagship: a partial UNIQUE index, not a check in application code.
--   * `players.ducats` carries CHECK (ducats >= 0). A house cannot go into debt by any path.
--
-- ── WHAT IT SELF-ASSERTS ────────────────────────────────────────────────────────────────────────
--   Every assert below runs against a PROBE HOUSE created inside a plpgsql subtransaction which is
--   then deliberately rolled back, so the migration leaves no rows behind. plpgsql variables are
--   not transactional, so the findings survive the rollback and are asserted outside it.
--     * credit() moves the purse AND writes a ledger row whose balance_after matches;
--     * a bare UPDATE of players.ducats with no ledger row is REJECTED (positive control — the
--       invariant is proven to bite, not merely to exist);
--     * UPDATE on ledger and DELETE on events are both REJECTED (append-only bites);
--     * a second flagship in one fleet is REJECTED;
--     * an overdraft is REJECTED;
--     * and after the rollback, the tables are empty again.
--
-- Depends ONLY on: 0001 (lockdown, knobs), 0002 (nations, ports, ship_classes), 0003 (the seed).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── Players ────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.players (
  id            uuid primary key default gen_random_uuid(),
  auth_uid      uuid unique,
  company_name  text not null unique check (length(btrim(company_name)) between 3 and 24),
  nation_id     uuid references public.nations(id),
  ducats        bigint not null default 0 check (ducats >= 0),
  company_level int not null default 1 check (company_level between 1 and 7),
  title_level   int not null default 1 check (title_level between 1 and 11),
  created_at    timestamptz not null default now(),
  version       int not null default 1
);
comment on column public.players.ducats is
  'DERIVED TRUTH, held denormalised for speed: it must always equal sum(ledger.ducats_delta) for '
  'this player. Only public.credit() may change it; a deferred constraint trigger kills any '
  'transaction that leaves the two disagreeing.';

-- The composite key ships will point at, so a ship can never join another player''s fleet.
create table if not exists public.fleets (
  id         uuid primary key default gen_random_uuid(),
  player_id  uuid not null references public.players(id) on delete cascade,
  name       text not null check (length(btrim(name)) between 3 and 24),
  status     text not null default 'DOCKED'
             check (status in ('DOCKED','ANCHORED','SAILING','REPAIRING','ADRIFT','UNABLE_TO_SAIL')),
  port_id    uuid references public.ports(id),
  version    int not null default 1,
  created_at timestamptz not null default now(),
  constraint fleets_id_player_unique unique (id, player_id),
  -- DESIGN B.3/D.2: a fleet is either at a port or at sea. A fleet not SAILING must have a port;
  -- a SAILING fleet must not claim one, because its position is the voyage's closed-form function.
  constraint fleets_position_is_unambiguous check (
    (status = 'SAILING' and port_id is null) or (status <> 'SAILING' and port_id is not null)
  )
);
create unique index if not exists fleets_player_name_unique
  on public.fleets (player_id, lower(name));

create table if not exists public.ships (
  id          uuid primary key default gen_random_uuid(),
  player_id   uuid not null references public.players(id) on delete cascade,
  fleet_id    uuid not null,
  class_id    uuid not null references public.ship_classes(id),
  name        text not null check (length(btrim(name)) between 3 and 24),
  durability  numeric(8,2) not null check (durability >= 0),
  crew        int not null default 0 check (crew >= 0),
  cargo       jsonb not null default '{}'::jsonb,
  water_t     numeric(10,3) not null default 0 check (water_t >= 0),
  food_t      numeric(10,3) not null default 0 check (food_t >= 0),
  store_ratio numeric(4,3) not null default 0.450 check (store_ratio between 0 and 1),
  is_flagship boolean not null default false,
  created_at  timestamptz not null default now(),
  constraint ships_fleet_belongs_to_same_player
    foreign key (fleet_id, player_id) references public.fleets (id, player_id) on delete cascade
);
create unique index if not exists ships_one_flagship_per_fleet
  on public.ships (fleet_id) where is_flagship;
create unique index if not exists ships_player_name_unique
  on public.ships (player_id, lower(name));
comment on column public.ships.cargo is
  'jsonb map of goods.code -> tuns aboard. Water and food are separate columns because DESIGN C.5 '
  'treats them as stores, not cargo: they are consumed per voyage-day and priced as provisions.';

-- ── The append-only ledgers ────────────────────────────────────────────────────────────────────
create table if not exists public.events (
  id         uuid primary key default gen_random_uuid(),
  player_id  uuid references public.players(id) on delete cascade,
  kind       text not null,
  payload    jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
comment on table public.events is
  'DESIGN E.6: "Every row is an immutable events record. The Ledger is not a UI convenience — it '
  'is the source of truth." Append-only, enforced by a trigger.';

create table if not exists public.ledger (
  id            uuid primary key default gen_random_uuid(),
  player_id     uuid not null references public.players(id) on delete cascade,
  kind          text not null,
  ducats_delta  bigint not null,
  balance_after bigint not null,
  ref_event_id  uuid references public.events(id),
  created_at    timestamptz not null default now()
);
create index if not exists ledger_player_created on public.ledger (player_id, created_at desc);
create index if not exists events_player_created on public.events (player_id, created_at desc);

-- ── Append-only enforcement: ONE function, two tables ──────────────────────────────────────────
create or replace function public.forbid_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception '% is append-only: % is not permitted', tg_table_name, tg_op
    using errcode = '42501';
end $$;

create trigger events_append_only
  before update or delete on public.events
  for each row execute function public.forbid_mutation();

create trigger ledger_append_only
  before update or delete on public.ledger
  for each row execute function public.forbid_mutation();

-- ── The purse invariant: ONE statement of it, two triggers ─────────────────────────────────────
create or replace function public.ledger_sum(p_player uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$ select coalesce(sum(ducats_delta), 0)::bigint from public.ledger where player_id = p_player $$;

create or replace function public.assert_ledger_reconciles(p_player uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_purse bigint;
  v_sum   bigint;
begin
  select ducats into v_purse from public.players where id = p_player;
  if v_purse is null then
    return;  -- the player was deleted in this transaction; the cascade took the ledger with it.
  end if;
  v_sum := public.ledger_sum(p_player);
  if v_purse <> v_sum then
    raise exception 'LEDGER RECONCILIATION FAILED for player %: purse = %, sum(ledger.ducats_delta) = %, difference = %',
      p_player, v_purse, v_sum, v_purse - v_sum
      using errcode = '23514';
  end if;
end $$;

create or replace function public.tg_reconcile_from_ledger()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.assert_ledger_reconciles(new.player_id);
  return null;
end $$;

create or replace function public.tg_reconcile_from_player()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.assert_ledger_reconciles(new.id);
  return null;
end $$;

create constraint trigger ledger_reconciles
  after insert on public.ledger
  deferrable initially deferred
  for each row execute function public.tg_reconcile_from_ledger();

create constraint trigger players_purse_reconciles
  after insert or update of ducats on public.players
  deferrable initially deferred
  for each row execute function public.tg_reconcile_from_player();

-- ── THE ONE money mover ────────────────────────────────────────────────────────────────────────
create or replace function public.credit(
  p_player uuid, p_kind text, p_delta bigint, p_ref_event uuid default null
)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_before bigint;
  v_after  bigint;
begin
  select ducats into v_before from public.players where id = p_player for update;
  if v_before is null then
    raise exception 'credit(): no such player %', p_player using errcode = '23503';
  end if;
  v_after := v_before + p_delta;
  if v_after < 0 then
    raise exception 'E_INSUFFICIENT_FUNDS: % has % ducats and the order costs %',
      p_player, v_before, -p_delta using errcode = 'P0001';
  end if;
  update public.players set ducats = v_after where id = p_player;
  insert into public.ledger (player_id, kind, ducats_delta, balance_after, ref_event_id)
  values (p_player, p_kind, p_delta, v_after, p_ref_event);
  return v_after;
end $$;

comment on function public.credit(uuid, text, bigint, uuid) is
  'THE ONE way ducats move. Every purchase, sale, wage, fee and salvage in the chain calls this. '
  'Nothing else may UPDATE players.ducats; the deferred constraint triggers make that structural.';

-- ── The ONE event writer ───────────────────────────────────────────────────────────────────────
create or replace function public.emit_event(p_player uuid, p_kind text, p_payload jsonb default '{}'::jsonb)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_id uuid;
begin
  insert into public.events (player_id, kind, payload) values (p_player, p_kind, p_payload)
  returning id into v_id;
  return v_id;
end $$;

-- ── The ONE auth.uid() -> player translation ───────────────────────────────────────────────────
create or replace function public.current_player_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$ select id from public.players where auth_uid = auth.uid() $$;

comment on function public.current_player_id() is
  'THE ONE translation from the JWT subject to a player id. Every RLS policy in this chain calls '
  'it. A policy that re-derives it with its own subquery is a second authority and will drift.';

-- ── Bootstrap: a new house, exactly as DESIGN §K.1 opens ───────────────────────────────────────
create or replace function public.new_house(
  p_auth_uid uuid, p_company_name text, p_nation_code text default 'PRT'
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid;
  v_fleet  uuid;
  v_nation uuid;
  v_port   uuid;
  v_class  public.ship_classes%rowtype;
  v_start  bigint := public.wc_int('starting_ducats');
begin
  select id into v_nation from public.nations where code = p_nation_code;
  select id into v_port   from public.ports   where code = 'LIS';
  select * into v_class   from public.ship_classes where code = 'barca';

  insert into public.players (auth_uid, company_name, nation_id, ducats)
  values (p_auth_uid, p_company_name, v_nation, 0)
  returning id into v_player;

  -- DESIGN K.1, 0:00 — "One Barca, 'Gaivota', docked at Lisboa. 8,000 ducats."
  perform public.credit(v_player, 'FOUNDING', v_start,
                        public.emit_event(v_player, 'FOUNDED',
                          jsonb_build_object('company', p_company_name, 'port', 'LIS')));

  insert into public.fleets (player_id, name, status, port_id)
  values (v_player, 'Gaivota', 'DOCKED', v_port)
  returning id into v_fleet;

  insert into public.ships (player_id, fleet_id, class_id, name, durability, crew,
                            water_t, food_t, store_ratio, is_flagship)
  values (v_player, v_fleet, v_class.id, 'Gaivota', v_class.durability, v_class.crew_required,
          2.400, 1.800, public.wc_num('store_ratio_default'), true);

  return v_player;
end $$;

-- ── RLS: a player sees their own rows and nothing else ─────────────────────────────────────────
alter table public.players enable row level security;
alter table public.fleets  enable row level security;
alter table public.ships   enable row level security;
alter table public.events  enable row level security;
alter table public.ledger  enable row level security;

create policy players_read_own on public.players for select to authenticated
  using (auth_uid = auth.uid());
create policy fleets_read_own  on public.fleets  for select to authenticated
  using (player_id = public.current_player_id());
create policy ships_read_own   on public.ships   for select to authenticated
  using (player_id = public.current_player_id());
create policy events_read_own  on public.events  for select to authenticated
  using (player_id = public.current_player_id());
create policy ledger_read_own  on public.ledger  for select to authenticated
  using (player_id = public.current_player_id());

grant select on public.players, public.fleets, public.ships, public.events, public.ledger
  to authenticated;
grant execute on function public.current_player_id() to authenticated;

-- The money mover, the event writer and the bootstrap are SERVER-ONLY. Handing `credit` to a
-- client role would be handing it the mint.
revoke all on function public.credit(uuid, text, bigint, uuid)   from public, anon, authenticated;
revoke all on function public.emit_event(uuid, text, jsonb)      from public, anon, authenticated;
revoke all on function public.new_house(uuid, text, text)        from public, anon, authenticated;
revoke all on function public.ledger_sum(uuid)                   from public, anon, authenticated;
revoke all on function public.assert_ledger_reconciles(uuid)     from public, anon, authenticated;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_probe_auth  constant uuid := '00000000-0004-4000-8000-000000000001';
  v_player      uuid;
  v_purse       bigint;
  v_sum         bigint;
  v_bal_after   bigint;
  v_ships       int;
  v_start       bigint := public.wc_int('starting_ducats');
  -- findings, recorded inside the subtransaction and read after it is rolled back
  f_created     boolean := false;
  f_unbacked    boolean := false;
  f_ledger_upd  boolean := false;
  f_event_del   boolean := false;
  f_two_flags   boolean := false;
  f_overdraft   boolean := false;
  v_grants      int;
  v_left        int;
begin
  begin
    -- ── inside the throwaway subtransaction ────────────────────────────────────────────────────
    v_player := public.new_house(v_probe_auth, 'Casa Probe', 'PRT');

    select ducats into v_purse from public.players where id = v_player;
    v_sum := public.ledger_sum(v_player);
    select count(*) into v_ships from public.ships where player_id = v_player;
    select balance_after into v_bal_after from public.ledger where player_id = v_player order by created_at limit 1;

    if v_purse = v_start and v_sum = v_start and v_bal_after = v_start and v_ships = 1 then
      f_created := true;
    end if;

    -- POSITIVE CONTROL 1: an unbacked purse write must be rejected. SET CONSTRAINTS forces the
    -- deferred trigger to fire here rather than at commit, so the failure is catchable.
    begin
      update public.players set ducats = ducats + 500 where id = v_player;
      set constraints all immediate;
      set constraints all deferred;
    exception when others then
      f_unbacked := true;
      set constraints all deferred;
    end;

    -- POSITIVE CONTROL 2: the ledger is append-only.
    begin
      update public.ledger set ducats_delta = 999999 where player_id = v_player;
    exception when others then f_ledger_upd := true;
    end;

    begin
      delete from public.events where player_id = v_player;
    exception when others then f_event_del := true;
    end;

    -- POSITIVE CONTROL 3: two flagships in one fleet.
    begin
      insert into public.ships (player_id, fleet_id, class_id, name, durability, crew, is_flagship)
      select s.player_id, s.fleet_id, s.class_id, 'Segunda', 400, 8, true
        from public.ships s where s.player_id = v_player limit 1;
    exception when others then f_two_flags := true;
    end;

    -- POSITIVE CONTROL 4: an overdraft.
    begin
      perform public.credit(v_player, 'PROBE_OVERDRAFT', -(v_start + 1));
    exception when others then f_overdraft := true;
    end;

    raise exception '__PROBE_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK__' then raise; end if;
  end;
  -- ── the subtransaction is gone; the findings survive because plpgsql variables are not
  --    transactional. Now assert on them. ──────────────────────────────────────────────────────

  if not f_created then
    raise exception '0004 self-assert FAIL: new_house() did not produce purse=% sum=% balance_after=% ships=1 (got % / % / % / %)',
      v_start, v_start, v_start, v_purse, v_sum, v_bal_after, v_ships;
  end if;
  if not f_unbacked then
    raise exception '0004 self-assert FAIL: an UPDATE of players.ducats with no ledger row was ACCEPTED. The purse invariant does not bite.';
  end if;
  if not f_ledger_upd then
    raise exception '0004 self-assert FAIL: UPDATE on the append-only ledger was accepted';
  end if;
  if not f_event_del then
    raise exception '0004 self-assert FAIL: DELETE on the append-only events table was accepted';
  end if;
  if not f_two_flags then
    raise exception '0004 self-assert FAIL: a second flagship was accepted into one fleet';
  end if;
  if not f_overdraft then
    raise exception '0004 self-assert FAIL: an overdraft was accepted; a house went into debt';
  end if;

  -- The rollback really rolled back: the migration leaves no probe rows in the world.
  select count(*) into v_left from public.players;
  if v_left <> 0 then
    raise exception '0004 self-assert FAIL: % player row(s) survived the probe subtransaction', v_left;
  end if;

  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0004 self-assert FAIL: the player tables minted % client write grant(s)', v_grants;
  end if;

  raise notice '0004 self-assert ok: new_house() opens with % ducats reconciled on both sides; REJECTED an unbacked purse write, a ledger UPDATE, an events DELETE, a second flagship and an overdraft (5 positive controls, all bit); probe rolled back leaving 0 players; 0 client write grants',
    v_start;
end $$;
