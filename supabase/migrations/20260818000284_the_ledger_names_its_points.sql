-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0284 — THE LEDGER NAMES ITS POINTS  (R4, Report: every new ledger row carries the fleet, the port
--        and the voyage its money moved at — one BEFORE INSERT trigger, filled at insert, never a guess)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY (docs/COMMAND_REDESIGN.md §4, "What is missing today, and what R4 adds") ────────────────
--   The ledger (0004: kind, ducats_delta, balance_after, ref_event_id, created_at) names no port, no
--   fleet and no voyage. ref_event_id points at an event whose payload usually has only the fleet's
--   NAME (BOUGHT, PROVISIONED, REPAIRED); INSURED alone carries port and voyage_id. Report (§4) groups
--   by point (port / voyage / earlier), so the point must live on the row.
--
-- ── THE ONE RULE (decided by default; the owner may reverse it) ──────────────────────────────────
--   At INSERT, when a row arrives with every point null (every writer today):
--     fleet  = the ref event's payload->>'fleet' name, resolved to EXACTLY ONE of THIS player's fleets
--              at this instant (lower(name); fleets_player_name_unique (player_id, lower(name)) makes
--              two impossible — the group-by is the rule stated, not a defence). Zero (renamed, gone)
--              reads null.
--     port   = that fleet's own dock, public.fleets.port_id — null while she sails
--              (fleets_position_is_unambiguous). NEVER the payload's port code: one authority, the fleet.
--     voyage = that fleet's current voyage (the one SAILING; at most one, voyages_one_sailing_per_fleet),
--              else the one she most recently ARRIVED on (voyages_fleet_ended_0249 serves the read).
--              An ABORTED voyage is never attributed.
--   NEVER A GUESS, NEVER A RAISE: no event, an event that names no fleet, a name that names no fleet
--   of hers, an event of ANOTHER player, a fleet with no voyage — all read as null. No cast that can
--   fail (payload->>'fleet' is text-or-null), no lookup that can error (every read is an indexed
--   probe or a keyed row), and a null point is always acceptable.
--   A row that arrives with a point already set keeps it — a writer that knows better has spoken
--   (none does today).
--
-- ── THE WRITERS, VERIFIED IN THE CHAIN (the design's claim, checked) ─────────────────────────────
--   "public.credit and public.pay_city are the only writers" — TRUE for every gameplay row, with two
--   refinements: public.pay_city (0122:344-361) never inserts into the ledger directly, it COMPOSES
--   public.credit; and one compactor body inserts directly — public.npc_compact_houses (0257/0258,
--   the NPC_CARRIED roll; npc_compact and npc_compact_house compose it, and the gate's scan found the
--   insert lives there alone at head 0272). The roll row has a NULL ref event. So every direct
--   ledger INSERT lives in public.credit or public.npc_compact_houses, and the self-assert pins that
--   set by a body scan. The trigger sits on the table, so EVERY writer gets the points for free by
--   construction; the compactor's rows (no event) read null — correct: a roll-up row has no single
--   point.
--
-- ── WHAT STAYS NULL, BY KIND (and why) ───────────────────────────────────────────────────────────
--   FOUNDING (FOUNDED carries no fleet), TAX (no event — 0122:542, 0128), WAGES (no event —
--   do_sell 0128:249, settle 0122:615), DONATION (DONATED: a port code only), SHARE (INVESTED: a port
--   code only), DIVIDEND (SURPLUS_GIVEN: no fleet), TUITION (ENROLLED: no fleet), NPC_REFOUND
--   (NPC_REFOUNDED: no fleet), MERCHANT_SURPLUS (SURPLUS_GIVEN), GRANT (no event), NPC_CARRIED (no
--   event), PROBE_* (rolled back), and every old row (append-only; no backfill) — "Earlier". A row
--   whose event names a fleet renamed since — null, never guessed. INSURANCE fills fleet and voyage
--   but not port (she sails); INSURANCE_PAID fills whatever the fleet's instant state gives.
--
-- ── WHAT THIS FILE TOUCHES ────────────────────────────────────────────────────────────────────────
--   ADDS TO one existing object, the TABLE public.ledger: three nullable uuid columns
--   port_id / fleet_id / voyage_id. NO foreign keys, by decision: a restricting FK would make
--   npc_compact's deletion of an NPC's ended voyages fail the hourly reconcile; ON DELETE SET NULL
--   and CASCADE would run an UPDATE / DELETE against the append-only trigger (0004 forbid_mutation)
--   and raise. The columns are Report's points, advisory by design; a dangling id reads null there.
--   Creates TWO new objects: the trigger function public.tg_ledger_points() and the BEFORE INSERT
--   row trigger ledger_points on public.ledger. NO existing function is re-cut: the self-assert
--   holds the md5 of every other function in public / cmd / world / voyage equal, and the client
--   registry unmoved. No new index: every read the trigger makes is served by an existing one
--   (events PK, fleets_player_name_unique, voyages_one_sailing_per_fleet, voyages_fleet_ended_0249).
--   The trigger's cost on a row with no event (WAGES, TAX, the compactor's roll) is one null check.
--
-- ── WHAT IT SELF-ASSERTS (probe rows only, rolled back; never a DELETE from an append-only table) ─
--   (a) the three columns are three nullable uuids; the trigger is the one BEFORE INSERT row trigger;
--       the append-only and reconcile triggers are still there;
--   (b) nothing else moved: the md5 of every other function in the four schemas, the registry count;
--   (c) the writers: every live body that inserts into public.ledger is credit or npc_compact_houses;
--   (d) the rule, through the REAL writer public.credit on a probe house (rolled back):
--       1 a row with NO ref event keeps all three null (the old writers' shape, and the compactor's);
--       2 an event that names no fleet — null;
--       3 an event whose fleet name is no fleet of hers (renamed / gone — the only reachable
--         ambiguity; two fleets of one name is structurally impossible, the unique index is pinned
--         in the guard) — null;
--       4 an event of ANOTHER player (whose own fleet answers to the name) — null;
--       5 her fleet, by name, docked, never sailed — fleet and port fill, voyage null;
--       6 the same after an ARRIVED voyage — all three fill (voyage = the arrived one);
--       7 the fleet put to sea with a SAILING voyage — fleet and voyage fill, port null;
--       8 a re-run of the same insert on the same state — the same triple;
--       9 a row that arrives with points already set keeps them;
--      10 the append-only positive control still bites (an UPDATE of a filled row is refused);
--      11 nothing survives the rollback (players, fleets, events, ledger rows, voyages).
--
-- ── ROLLBACK (forward; this file is purely additive) ─────────────────────────────────────────────
--   drop trigger ledger_points on public.ledger;
--   drop function public.tg_ledger_points();
--   alter table public.ledger drop column port_id, drop column fleet_id, drop column voyage_id;
--
-- VERSION: 0284 — RENUMBERED 2026-10-30, twice: from the 0277 this slice was authored under (prod
--          passed it while it waited — 0278–0282 deployed — and a version below the prod head can
--          never be pushed), and then from 0283, which went to the hull-durability fix that had to
--          land first (a new hull started above her own rolled max). Unchanged in substance.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regclass('public.ledger') is null
     or to_regprocedure('public.credit(uuid,text,bigint,uuid)') is null
     or to_regprocedure('public.npc_compact(timestamptz)') is null then
    raise exception '0284 refuses: 0004 / 0097 is not in this world';
  end if;
  if not exists (select 1 from pg_indexes
                  where schemaname = 'public' and tablename = 'fleets' and indexname = 'fleets_player_name_unique') then
    raise exception '0284 refuses: fleets_player_name_unique is gone — a name could resolve to two fleets';
  end if;
  if not exists (select 1 from pg_indexes
                  where schemaname = 'public' and tablename = 'voyages' and indexname = 'voyages_one_sailing_per_fleet')
     or not exists (select 1 from pg_indexes
                  where schemaname = 'public' and tablename = 'voyages' and indexname = 'voyages_fleet_ended_0249') then
    raise exception '0284 refuses: a voyage index this file reads by is gone';
  end if;
  if to_regprocedure('public.tg_ledger_points()') is not null
     or exists (select 1 from information_schema.columns c
                 where c.table_schema = 'public' and c.table_name = 'ledger' and c.column_name = 'port_id') then
    raise exception '0284 refuses: public.tg_ledger_points or ledger.port_id already exists — this has been applied once';
  end if;
end $guard$;

-- ── 0. AS FOUND ─────────────────────────────────────────────────────────────────────────────────
create temp table before_0284 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) as fns,
       (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) as fns_md5;

-- ── 1. THE POINT COLUMNS ────────────────────────────────────────────────────────────────────────
alter table public.ledger add column port_id uuid;
alter table public.ledger add column fleet_id uuid;
alter table public.ledger add column voyage_id uuid;

comment on column public.ledger.port_id is
  '0284: Report''s point — the port the money moved at, filled at insert by public.tg_ledger_points from the ref '
  'event''s fleet: the fleet''s own dock, so null while she sails. Nullable on purpose — no event, no fleet, no '
  'dock: all read null, and old rows read "Earlier". No FK by decision (see the header).';
comment on column public.ledger.fleet_id is
  '0284: the fleet the money moved with, filled at insert when the ref event''s fleet name resolves to exactly one '
  'of this player''s fleets (fleets_player_name_unique). Nullable: a nameless event, a renamed fleet — null.';
comment on column public.ledger.voyage_id is
  '0284: the voyage the money belongs to — the fleet''s SAILING voyage, else her most recent ARRIVED one. '
  'Nullable: never attributed when there is none (an ABORTED voyage is never attributed).';

-- ── 2. THE ONE FILLER ───────────────────────────────────────────────────────────────────────────
create function public.tg_ledger_points()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0284: THE LEDGER'S POINTS, AT INSERT — the one rule of the header, stated once. A row that
-- arrives with every point null is given the point its ref event names: the fleet (the event's
-- `fleet` name, exactly one of THIS player's fleets now), the port (that fleet's own dock), the
-- voyage (the one she is on, else the one she most recently arrived on). Everything else reads
-- null — never a guess, never a raise. Every read here is an indexed probe or a keyed row; no
-- cast can fail. The trigger writes nothing and takes no lock the inserting statement did not.
declare
  v_name text;
begin
  if new.ref_event_id is null
     or new.port_id is not null or new.fleet_id is not null or new.voyage_id is not null then
    return new;   -- nothing to name, or a writer that knows better has spoken (none does today)
  end if;
  select e.payload->>'fleet' into v_name
    from public.events e
   where e.id = new.ref_event_id and e.player_id = new.player_id;   -- never another player's event
  if v_name is null or btrim(v_name) = '' then
    return new;   -- the event names no fleet: all three stay null
  end if;
  select f.id, f.port_id into new.fleet_id, new.port_id
    from public.fleets f
   where f.player_id = new.player_id and lower(f.name) = lower(btrim(v_name))
   group by f.id, f.port_id
   having count(*) = 1;   -- EXACTLY ONE of her fleets, now (fleets_player_name_unique); zero reads null
  if new.fleet_id is null then
    return new;   -- the name does not name one fleet of hers: port and voyage stay null too
  end if;
  select v.id into new.voyage_id
    from public.voyages v
   where v.fleet_id = new.fleet_id and v.status = 'SAILING' limit 1;   -- at most one (the unique index)
  if new.voyage_id is null then
    select v.id into new.voyage_id
      from public.voyages v
     where v.fleet_id = new.fleet_id and v.status = 'ARRIVED'
     order by v.eta desc limit 1;   -- the just-arrived (voyages_fleet_ended_0249 serves the read)
  end if;
  return new;
end $$;

comment on function public.tg_ledger_points() is
  '0284: fills ledger.port_id / fleet_id / voyage_id at insert from the ref event''s fleet (the one rule of the '
  'header) — the fleet by name, the port that fleet''s dock, the voyage her SAILING else her latest ARRIVED one. '
  'Null whenever the name is absent or resolves to no fleet of the player''s: never a guess, never a raise. Server-only.';
revoke all on function public.tg_ledger_points() from public, anon, authenticated;

create trigger ledger_points
  before insert on public.ledger
  for each row execute function public.tg_ledger_points();

-- ── 3. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  v_before  record;
  v_p       uuid;
  v_p2      uuid;
  v_f       uuid;
  v_lis     uuid;
  v_port2   uuid;
  v_voy1    uuid;
  v_voy2    uuid;
  e0        uuid;
  e1        uuid;
  e2        uuid;
  e3        uuid;
  r1        record;
  r2        record;
  r3        record;
  r4        record;
  r5        record;
  r6        record;
  r7        record;
  r8        record;
  r9        record;
  f_append  boolean := false;
  v_writers text[];
begin
  select * into v_before from before_0284;

  -- (a) THE COLUMNS AND THE TRIGGER
  if (select count(*) from information_schema.columns c
       where c.table_schema = 'public' and c.table_name = 'ledger'
         and c.column_name in ('port_id', 'fleet_id', 'voyage_id')
         and c.is_nullable = 'YES' and c.data_type = 'uuid') <> 3 then
    raise exception '0284 self-assert FAIL: the three point columns are not three nullable uuids';
  end if;
  if (select count(*) from pg_trigger t
       where t.tgrelid = 'public.ledger'::regclass and t.tgname = 'ledger_points'
         and (t.tgtype::int & 7) = 7 and t.tgconstraint = 0 and not t.tgisinternal) <> 1 then
    raise exception '0284 self-assert FAIL: the BEFORE INSERT row trigger ledger_points is not on public.ledger';
  end if;
  if (select count(*) from pg_trigger t
       where t.tgrelid = 'public.ledger'::regclass and t.tgname in ('ledger_append_only', 'ledger_reconciles')) <> 2 then
    raise exception '0284 self-assert FAIL: the append-only or reconcile trigger is gone';
  end if;

  -- (b) NOTHING ELSE MOVED: every other function in the four schemas, by md5, and the registry
  if (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> 'public.tg_ledger_points()'::regprocedure) is distinct from v_before.fns_md5
     or (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')) <> v_before.fns + 1 then
    raise exception '0284 self-assert FAIL: a function moved, or more than the one new function was minted';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> v_before.entry_points then
    raise exception '0284 self-assert FAIL: the registry moved';
  end if;

  -- (c) THE WRITERS, as found: every live body whose text inserts into public.ledger is the one
  --     money mover or the compactor's roll body (the NPC_CARRIED row, a null ref event — after
  --     0265 the insert lives in npc_compact_houses alone; npc_compact_house composes it).
  --     public.pay_city composes public.credit — it never inserts directly.
  select coalesce(array_agg(n.nspname || '.' || p.proname order by n.nspname || '.' || p.proname), '{}')
    into v_writers
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and pg_get_functiondef(p.oid) ~* 'insert\s+into\s+public\.ledger';
  if v_writers <> array['public.credit', 'public.npc_compact_houses'] then
    raise exception '0284 self-assert FAIL: the ledger''s writers are %, not credit and the compactor''s roll body', v_writers;
  end if;

  -- (d) THE RULE, through the REAL writer, on a probe house — rolled back whole
  begin
    v_p  := public.new_house('00000000-0284-4000-8000-000000000001', 'Casa dos Pontos 0284', 'PRT', 'LIS');
    v_p2 := public.new_house('00000000-0284-4000-8000-000000000002', 'Casa Alheia 0284', 'PRT', 'LIS');
    select f.id, f.port_id into v_f, v_lis from public.fleets f where f.player_id = v_p;
    select p.id into v_port2 from public.ports p where p.kind = 'HARBOUR' and p.id <> v_lis order by p.code limit 1;
    if v_f is null or v_lis is null or v_port2 is null then
      raise exception '0284 self-assert FAIL: no probe fleet or no second harbour';
    end if;
    e0 := public.emit_event(v_p,  'PROBE_0284', '{}'::jsonb);                                 -- names no fleet
    e1 := public.emit_event(v_p,  'PROBE_0284', jsonb_build_object('fleet', 'Ghost 0284'));   -- names no fleet of hers
    e2 := public.emit_event(v_p,  'PROBE_0284', jsonb_build_object('fleet', 'Gaivota'));      -- her fleet, by name
    e3 := public.emit_event(v_p2, 'PROBE_0284', jsonb_build_object('fleet', 'Gaivota'));      -- another player's event

    -- (1) NO REF EVENT: the old writers' shape, and the compactor's roll — all three null
    perform public.credit(v_p, 'PROBE_0284', 1, null);
    select l.port_id, l.fleet_id, l.voyage_id into r1 from public.ledger l
     where l.player_id = v_p and l.kind = 'PROBE_0284' and l.ducats_delta = 1;
    -- (2) AN EVENT THAT NAMES NO FLEET — null
    perform public.credit(v_p, 'PROBE_0284', 2, e0);
    select l.port_id, l.fleet_id, l.voyage_id into r2 from public.ledger l
     where l.player_id = v_p and l.kind = 'PROBE_0284' and l.ducats_delta = 2;
    -- (3) A NAME THAT IS NO FLEET OF HERS (renamed / gone) — null
    perform public.credit(v_p, 'PROBE_0284', 3, e1);
    select l.port_id, l.fleet_id, l.voyage_id into r3 from public.ledger l
     where l.player_id = v_p and l.kind = 'PROBE_0284' and l.ducats_delta = 3;
    -- (4) AN EVENT OF ANOTHER PLAYER, whose own fleet answers to the name — null
    perform public.credit(v_p, 'PROBE_0284', 4, e3);
    select l.port_id, l.fleet_id, l.voyage_id into r4 from public.ledger l
     where l.player_id = v_p and l.kind = 'PROBE_0284' and l.ducats_delta = 4;
    -- (5) HER FLEET BY NAME, docked, never sailed — fleet and port fill, voyage null
    perform public.credit(v_p, 'PROBE_0284', 5, e2);
    select l.port_id, l.fleet_id, l.voyage_id into r5 from public.ledger l
     where l.player_id = v_p and l.kind = 'PROBE_0284' and l.ducats_delta = 5;
    -- (6) AFTER AN ARRIVED VOYAGE — all three fill, the voyage is the arrived one
    v_voy1 := gen_random_uuid();
    insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status,
                                origin_port_id, dest_port_id, created_at)
    values (v_voy1, v_f, v_p, '[]', 100, '{}', now() - interval '2 days', now() - interval '1 day', 'ARRIVED',
            v_lis, v_port2, now() - interval '2 days');
    perform public.credit(v_p, 'PROBE_0284', 6, e2);
    select l.port_id, l.fleet_id, l.voyage_id into r6 from public.ledger l
     where l.player_id = v_p and l.kind = 'PROBE_0284' and l.ducats_delta = 6;
    -- (7) TO SEA — fleet and voyage fill (the SAILING one is preferred), port null
    v_voy2 := gen_random_uuid();
    insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status,
                                origin_port_id, dest_port_id, created_at)
    values (v_voy2, v_f, v_p, '[]', 100, '{}', now(), now() + interval '1 day', 'SAILING',
            v_lis, v_port2, now());
    update public.fleets set status = 'SAILING', port_id = null where id = v_f;
    perform public.credit(v_p, 'PROBE_0284', 7, e2);
    select l.port_id, l.fleet_id, l.voyage_id into r7 from public.ledger l
     where l.player_id = v_p and l.kind = 'PROBE_0284' and l.ducats_delta = 7;
    -- (8) A RE-RUN OF THE SAME INSERT on the same state — the same triple
    perform public.credit(v_p, 'PROBE_0284', 8, e2);
    select l.port_id, l.fleet_id, l.voyage_id into r8 from public.ledger l
     where l.player_id = v_p and l.kind = 'PROBE_0284' and l.ducats_delta = 8;
    -- (9) A ROW THAT ARRIVES WITH POINTS ALREADY SET KEEPS THEM (values the rule would not choose)
    insert into public.ledger (player_id, kind, ducats_delta, balance_after, ref_event_id, port_id, fleet_id, voyage_id)
    values (v_p, 'PROBE_0284', 9, (select pl.ducats from public.players pl where pl.id = v_p), e2, v_port2, v_f, v_voy1);
    select l.port_id, l.fleet_id, l.voyage_id into r9 from public.ledger l
     where l.player_id = v_p and l.kind = 'PROBE_0284' and l.ducats_delta = 9;
    -- (10) THE APPEND-ONLY POSITIVE CONTROL still bites on a filled row
    begin
      update public.ledger set fleet_id = null where player_id = v_p and kind = 'PROBE_0284' and ducats_delta = 5;
    exception when others then
      f_append := true;
    end;

    raise exception '__PROBE_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK__' then raise; end if;
  end;

  -- the subtransaction is gone; the findings survive (plpgsql variables are not transactional)
  if r1.port_id is not null or r1.fleet_id is not null or r1.voyage_id is not null then
    raise exception '0284 self-assert FAIL: a row with no ref event was given a point: %', r1;
  end if;
  if r2.port_id is not null or r2.fleet_id is not null or r2.voyage_id is not null then
    raise exception '0284 self-assert FAIL: an event that names no fleet was given a point: %', r2;
  end if;
  if r3.port_id is not null or r3.fleet_id is not null or r3.voyage_id is not null then
    raise exception '0284 self-assert FAIL: a name that is no fleet of hers was guessed: %', r3;
  end if;
  if r4.port_id is not null or r4.fleet_id is not null or r4.voyage_id is not null then
    raise exception '0284 self-assert FAIL: another player''s event was resolved: %', r4;
  end if;
  if r5.fleet_id is distinct from v_f or r5.port_id is distinct from v_lis or r5.voyage_id is not null then
    raise exception '0284 self-assert FAIL: her fleet by name, docked, never sailed, read %, not fleet % at %',
      r5, v_f, v_lis;
  end if;
  if r6.fleet_id is distinct from v_f or r6.port_id is distinct from v_lis or r6.voyage_id is distinct from v_voy1 then
    raise exception '0284 self-assert FAIL: after the arrived voyage the triple is %, not fleet %, port %, voyage %',
      r6, v_f, v_lis, v_voy1;
  end if;
  if r7.fleet_id is distinct from v_f or r7.port_id is not null or r7.voyage_id is distinct from v_voy2 then
    raise exception '0284 self-assert FAIL: to sea, the triple is %, not fleet % with no port and the sailing voyage %',
      r7, v_f, v_voy2;
  end if;
  if r8.fleet_id is distinct from r7.fleet_id or r8.port_id is distinct from r7.port_id or r8.voyage_id is distinct from r7.voyage_id then
    raise exception '0284 self-assert FAIL: the re-run of the same insert reads %, not %', r8, r7;
  end if;
  if r9.port_id is distinct from v_port2 or r9.fleet_id is distinct from v_f or r9.voyage_id is distinct from v_voy1 then
    raise exception '0284 self-assert FAIL: a row that arrived with points set was overwritten: %', r9;
  end if;
  if not f_append then
    raise exception '0284 self-assert FAIL: an UPDATE of a filled ledger row was accepted — the append-only bite is gone';
  end if;

  -- nothing of the probe survives (its own rows only: PROBE_0284 kinds, its company names, its voyages)
  if exists (select 1 from public.players p where p.company_name in ('Casa dos Pontos 0284', 'Casa Alheia 0284'))
     or exists (select 1 from public.events e where e.kind = 'PROBE_0284')
     or exists (select 1 from public.ledger l where l.kind = 'PROBE_0284')
     or exists (select 1 from public.voyages v where v.id in (v_voy1, v_voy2)) then
    raise exception '0284 self-assert FAIL: the probe left rows behind';
  end if;

  raise notice '0284 self-assert ok: THE LEDGER NAMES ITS POINTS. Three nullable point columns and one BEFORE INSERT row trigger on the ledger; every other function in the four schemas unmoved by md5, the registry unmoved; the writers are public.credit and public.npc_compact_houses (public.pay_city composes credit — verified); the rule through the real writer, rolled back: no event / no fleet name / a ghost name / another player''s event all read null; her fleet by name fills fleet + port at her dock, then all three with the arrived voyage, then fleet + voyage (port null) once she sails; the re-run is identical; points already set are kept; the append-only bite still bites; nothing left behind.';
end $$;
