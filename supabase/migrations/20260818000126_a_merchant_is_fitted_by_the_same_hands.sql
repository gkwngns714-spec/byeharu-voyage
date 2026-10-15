-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0126 — A MERCHANT IS FITTED BY THE SAME HANDS  (docs/SHIPS_AND_GEAR.md §3.2, step S2)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- docs/RESUME.md queue item 3, 2026-10-15: *"Merchant ships: serve slots + combat stats (server
-- change), and make more ship types and more gear"*. 0124 served a merchant's slots and stats; her
-- slots were all empty, because nothing ever put gear on a merchant's hull. This file does. Owner
-- decisions of the same evening: merchant gear is FIXED (it never upgrades, for now); merchant
-- captains, skills and levels are constant.
--
-- ── WHAT WAS FOUND ──────────────────────────────────────────────────────────────────────────────
-- "Mount a fitting on a hull" lived inline in cmd.do_fit (0074, re-cut by 0077): the slot check
-- (class_slots, E_NO_SLOT / E_SLOTS_FULL) and the ship_fittings upsert, between the store lookup
-- and the store debit. A merchant has no store and never docks to FIT, so the only way to give her
-- gear would have been a second writer of ship_fittings — a second copy of the slot rule.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) public.mount_fitting(ship, item) — THE ONE CORE that puts a fitting on a hull: her slots of
--     that kind (class_slots), what she already carries there, the refusal in 0074/0077's words,
--     the upsert. Its lines are the ones cut out of do_fit, moved verbatim. Server-only. No
--     `is_npc` in it: a merchant's hull and a player's are fitted by the same lines.
-- (2) cmd.do_fit — re-cut (two hunks, sliced from the LIVE body) into a DOOR: DOCKED, the item, the
--     hull, the store (E_NONE_HERE), then `mount_fitting`, then the store debit, the event and the
--     same return. Reverse substitution proves it is its pre-image plus the call.
-- (3) public.npc_loadouts — authored data (data/npc-loadouts.json, same rows): patterns by ship
--     class. None spends hold (owner: prefer loadouts that do not reduce hold), none fills every
--     slot. RLS on, no client grant.
-- (4) public.npc_fit_loadout(ship) — the pattern for her FLEET, md5(fleet_id) mod the class's
--     pattern count (deterministic, no secret: nothing here is a lottery a player could replay),
--     each item through mount_fitting. A hull that already carries anything is left alone (FIXED).
--     Server-only.
-- (5) public.npc_found — re-cut (one hunk): once a fleet's hulls are commissioned, each is fitted.
-- (6) THE BACKFILL: every merchant hull carrying nothing gets her loadout, once, timed.
--
-- ── WHAT IT DOES NOT DO ─────────────────────────────────────────────────────────────────────────
-- Nothing is added to the arrivals tick or to any cron: the backfill is this file, new merchants
-- are fitted in npc_found (a migration-time founder). Gear does not change COMBAT: the escort score
-- reads ship_classes.guns, not the stats (S4 does that, last). What it DOES change, said plainly:
-- a suit of sails is +0.6 kn and a nau trader's hold fittings +25 t, so merchants sail a little
-- faster and a few nau carry a little more — no hull loses a tun. The receipt prints the measured
-- effect on speed and hold and the read cost of a hull's speed + hold (the arrivals tick's
-- per-hull reads), before and after.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
-- The gear: `delete from public.ship_fittings sf using public.ships s, public.fleets f, public.players p
-- where s.id = sf.ship_id and f.id = s.fleet_id and p.id = f.player_id and p.is_npc` (one DELETE).
-- The code: one forward migration re-cutting do_fit and npc_found back — every OLD hunk is in this
-- file verbatim (hunks_0126.old) and the self-assert proves each live body reverses to its
-- pre-image by them; then drop npc_fit_loadout, mount_fitting and npc_loadouts.
--
-- SUPERSEDES: cmd.do_fit (0074 as re-cut by 0077), public.npc_found (0097) — hunks sliced from the
-- LIVE bodies, each asserted to occur exactly once. Self-asserts hold AS FOUND; every probe rolls
-- back. No new entry point, no client write.
-- VERSION: 0126. Applies on 0124 (prod head). 0125 (merchants dock) touches none of these bodies.

do $guard$ begin perform set_config('statement_timeout', '20min', true); end $guard$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0126 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from unnest(array['cmd.do_fit(uuid, jsonb)', 'public.npc_found(jsonb)']) f(fn);

create temp table entry_points_before_0126 on commit drop as
select count(*) as n from public.client_rpc_entry_points();

-- Every player's fittings, as text: the backfill must not move one of them.
create temp table player_fittings_before_0126 on commit drop as
select count(*) as n,
       coalesce(md5(string_agg(sf.ship_id::text || ':' || sf.item_code || ':' || sf.qty, ',' order by sf.ship_id, sf.item_code)), '') as h
  from public.ship_fittings sf
  join public.ships s on s.id = sf.ship_id
  join public.fleets f on f.id = s.fleet_id
  join public.players p on p.id = f.player_id
 where not p.is_npc;

-- Every merchant hull's hold and speed rating, before her gear.
create temp table merchant_hulls_before_0126 on commit drop as
select s.id as ship_id, c.code as class_code,
       world.ship_stat(s.id, 'hold') as hold, world.ship_stat(s.id, 'speed') as speed,
       exists (select 1 from public.ship_fittings sf where sf.ship_id = s.id) as fitted
  from public.ships s
  join public.ship_classes c on c.id = s.class_id
  join public.fleets f on f.id = s.fleet_id
  join public.players p on p.id = f.player_id
 where p.is_npc;

-- What the arrivals tick reads per hull — her speed and her hold — timed over every merchant hull.
create temp table reads_before_0126 (ms numeric) on commit drop;
do $$
declare
  v_t0 timestamptz := clock_timestamp();
begin
  perform voyage.ship_speed(b.ship_id), public.ship_hold_capacity(b.ship_id) from merchant_hulls_before_0126 b;
  insert into reads_before_0126 values (round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
end $$;

-- ── 2. THE HUNKS (old = verbatim from the live bodies; new = what replaces it) ─────────────────
create temp table hunks_0126 (fn text, n int, old text, new text) on commit drop;

insert into hunks_0126 values
('cmd.do_fit(uuid, jsonb)', 1,
$h$  v_have  int;
  v_slots int;
  v_used  int;
begin
$h$,
$h$  v_have  int;
begin
$h$),

('cmd.do_fit(uuid, jsonb)', 2,
$h$  -- HOW MANY OF THIS KIND SHE MAY CARRY. The weapon count lives on ship_classes.guns, which 0074
  -- retired from being a stat into being exactly this; every other kind is a class_slots row.
  -- 0077: ONE TABLE FOR EVERY KIND OF SLOT, weapons included. This was a branch on
  -- ship_classes.guns, which disagreed with class_slots and left a barca unable to mount the
  -- weapon the owner said she carries.
  select coalesce(cs.count, 0) into v_slots
    from public.ship_classes c
    left join public.class_slots cs on cs.class_code = c.code and cs.slot = k.slot
   where c.id = v_ship.class_id;
  if coalesce(v_slots, 0) < 1 then
    raise exception 'E_NO_SLOT: a % has nowhere to put a %',
      (select name from public.ship_classes where id = v_ship.class_id), k.name using errcode = 'P0001';
  end if;

  select coalesce(sum(sf.qty), 0) into v_used
    from public.ship_fittings sf join public.item_kinds ik on ik.code = sf.item_code
   where sf.ship_id = v_ship.id and ik.slot = k.slot;
  if v_used >= v_slots then
    raise exception 'E_SLOTS_FULL: % already fills her % % slot(s)',
      v_ship.name, v_slots, k.slot using errcode = 'P0001';
  end if;

  update public.player_items set qty = qty - 1
   where player_id = f.player_id and port_id = f.port_id and item_code = k.code;
  delete from public.player_items
   where player_id = f.player_id and port_id = f.port_id and item_code = k.code and qty <= 0;

  insert into public.ship_fittings (ship_id, item_code, qty) values (v_ship.id, k.code, 1)
  on conflict (ship_id, item_code) do update set qty = public.ship_fittings.qty + 1;
$h$,
$h$  -- 0126: THE MOUNTING IS public.mount_fitting — her slots of this kind, and the hull taking it. A
  -- player's FIT and a merchant's endowed loadout go through the same lines; this door keeps
  -- DOCKED, the item, the hull, the store, the event and the reply.
  perform public.mount_fitting(v_ship.id, k.code);

  update public.player_items set qty = qty - 1
   where player_id = f.player_id and port_id = f.port_id and item_code = k.code;
  delete from public.player_items
   where player_id = f.player_id and port_id = f.port_id and item_code = k.code and qty <= 0;
$h$),

('public.npc_found(jsonb)', 1,
$h$    for v_i in 1 .. jsonb_array_length(v_fl->'ships') - 1 loop
      v_sh := v_fl->'ships'->v_i;
      perform public.commission_ship(v_player, v_fleet, v_sh->>'class', v_sh->>'name', false, true);
    end loop;
$h$,
$h$    for v_i in 1 .. jsonb_array_length(v_fl->'ships') - 1 loop
      v_sh := v_fl->'ships'->v_i;
      perform public.commission_ship(v_player, v_fleet, v_sh->>'class', v_sh->>'name', false, true);
    end loop;
    -- 0126: HER GEAR, endowed as her hulls are — the pattern for this fleet, through the one core.
    perform public.npc_fit_loadout(s.id) from public.ships s where s.fleet_id = v_fleet order by s.is_flagship desc, s.name;
$h$);

-- ── 3. THE ONE CORE ────────────────────────────────────────────────────────────────────────────
create or replace function public.mount_fitting(p_ship uuid, p_item_code text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $mf$
declare
  k       public.item_kinds%rowtype;
  v_ship  public.ships%rowtype;
  v_slots int;
  v_used  int;
begin
  -- 0126: PUT ONE FITTING ON ONE HULL. The lines below the lookups are cut verbatim out of
  -- cmd.do_fit (0074, re-cut by 0077); the door that called them keeps the store and the event.
  select * into k from public.item_kinds where code = p_item_code;
  if k.code is null then
    raise exception 'E_NO_SUCH_ITEM: nothing is called "%"', coalesce(p_item_code, '') using errcode = 'P0001';
  end if;
  select * into v_ship from public.ships where id = p_ship;
  if v_ship.id is null then
    raise exception 'E_NO_SUCH_SHIP: there is no ship %', p_ship using errcode = 'P0001';
  end if;

  -- 0077: ONE TABLE FOR EVERY KIND OF SLOT, weapons included.
  select coalesce(cs.count, 0) into v_slots
    from public.ship_classes c
    left join public.class_slots cs on cs.class_code = c.code and cs.slot = k.slot
   where c.id = v_ship.class_id;
  if coalesce(v_slots, 0) < 1 then
    raise exception 'E_NO_SLOT: a % has nowhere to put a %',
      (select name from public.ship_classes where id = v_ship.class_id), k.name using errcode = 'P0001';
  end if;

  select coalesce(sum(sf.qty), 0) into v_used
    from public.ship_fittings sf join public.item_kinds ik on ik.code = sf.item_code
   where sf.ship_id = v_ship.id and ik.slot = k.slot;
  if v_used >= v_slots then
    raise exception 'E_SLOTS_FULL: % already fills her % % slot(s)',
      v_ship.name, v_slots, k.slot using errcode = 'P0001';
  end if;

  insert into public.ship_fittings (ship_id, item_code, qty) values (v_ship.id, k.code, 1)
  on conflict (ship_id, item_code) do update set qty = public.ship_fittings.qty + 1;
end $mf$;
comment on function public.mount_fitting(uuid, text) is
  '0126: THE one core that puts a fitting on a hull (class_slots capacity, E_NO_SLOT / E_SLOTS_FULL, '
  'the upsert). Called by cmd.do_fit (a player, from her store) and public.npc_fit_loadout (a '
  'merchant, endowed). Server-only.';
revoke all on function public.mount_fitting(uuid, text) from public, anon, authenticated;

-- ── 4. THE AUTHORED LOADOUTS (data/npc-loadouts.json, row for row) ─────────────────────────────
create table if not exists public.npc_loadouts (
  class_code text     not null references public.ship_classes(code) on delete cascade,
  pattern    smallint not null check (pattern >= 0),
  item_code  text     not null references public.item_kinds(code),
  qty        int      not null check (qty > 0),
  primary key (class_code, pattern, item_code)
);
comment on table public.npc_loadouts is
  '0126: what a merchant''s hull carries, by class and pattern — authored in data/npc-loadouts.json. '
  'Read only by public.npc_fit_loadout. FIXED: a merchant never changes her gear (owner, 2026-10-15).';
alter table public.npc_loadouts enable row level security;
revoke all on table public.npc_loadouts from public, anon, authenticated;

insert into public.npc_loadouts (class_code, pattern, item_code, qty) values
  ('barca',  0, 'suit-of-sails',    1), ('barca',  0, 'boarding-gear', 1),
  ('barca',  1, 'bowsprit-and-jib', 1), ('barca',  1, 'boarding-gear', 1),
  ('carlat', 0, 'suit-of-sails',    1), ('carlat', 0, 'boarding-gear', 1),
  ('carlat', 1, 'suit-of-sails',    1), ('carlat', 1, 'boarding-gear', 2),
  ('carlat', 2, 'bowsprit-and-jib', 1), ('carlat', 2, 'boarding-gear', 1),
  ('nau',    0, 'suit-of-sails',    2), ('nau',    0, 'hold-fittings', 1), ('nau', 0, 'crows-nest', 1),
  ('nau',    1, 'suit-of-sails',    2), ('nau',    1, 'boarding-gear', 2), ('nau', 1, 'crows-nest', 1),
  ('nau',    2, 'suit-of-sails',    2), ('nau',    2, 'copper-sheathing', 1), ('nau', 2, 'boarding-gear', 1),
  ('nau',    2, 'crows-nest',       1), ('nau',    2, 'figurehead',    1)
on conflict (class_code, pattern, item_code) do update set qty = excluded.qty;

-- ── 5. A MERCHANT'S HULL, FITTED ───────────────────────────────────────────────────────────────
create or replace function public.npc_fit_loadout(p_ship uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $nf$
declare
  v_class text;
  v_fleet uuid;
  v_n     int;
  v_pat   int;
  r       record;
  v_fit   int := 0;
begin
  -- 0126: HER GEAR IS ENDOWED, AS HER HULL IS, AND FIXED. A hull that carries anything already is
  -- left exactly as she is: this never adds to, swaps or upgrades a fitting.
  select c.code, s.fleet_id into v_class, v_fleet
    from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.id = p_ship;
  if v_class is null then
    raise exception 'E_NO_SUCH_SHIP: there is no ship %', p_ship using errcode = 'P0001';
  end if;
  if exists (select 1 from public.ship_fittings where ship_id = p_ship) then
    return 0;
  end if;

  select count(distinct pattern) into v_n from public.npc_loadouts where class_code = v_class;
  if v_n = 0 then
    raise exception 'E_NO_LOADOUT: no merchant loadout is authored for a % (data/npc-loadouts.json)', v_class
      using errcode = 'P0001';
  end if;
  -- ONE PATTERN PER FLEET: every hull of a fleet wears the same one, and a re-run picks it again.
  v_pat := mod(mod(('x' || left(md5(v_fleet::text), 8))::bit(32)::int, v_n) + v_n, v_n);

  for r in select l.item_code, l.qty from public.npc_loadouts l
            where l.class_code = v_class and l.pattern = v_pat order by l.item_code loop
    for i in 1 .. r.qty loop
      perform public.mount_fitting(p_ship, r.item_code);
      v_fit := v_fit + 1;
    end loop;
  end loop;
  return v_fit;
end $nf$;
comment on function public.npc_fit_loadout(uuid) is
  '0126: a merchant''s hull gets the pattern of her class chosen by her FLEET (md5 mod count), '
  'each item through public.mount_fitting. A hull already carrying anything is left alone. Server-only.';
revoke all on function public.npc_fit_loadout(uuid) from public, anon, authenticated;

-- ── 6. THE RE-CUTS ─────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.recut_0126(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0126 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0126 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0126(fn) from (values ('cmd.do_fit(uuid, jsonb)'), ('public.npc_found(jsonb)')) x(fn);

-- ── 7. THE BACKFILL: every merchant hull that carries nothing, once ────────────────────────────
create temp table backfill_0126 (hulls bigint, fitted bigint, ms numeric) on commit drop;
do $$
declare
  v_t0     timestamptz := clock_timestamp();
  v_fitted bigint := 0;
  r        record;
begin
  for r in select b.ship_id from merchant_hulls_before_0126 b where not b.fitted order by b.ship_id loop
    v_fitted := v_fitted + public.npc_fit_loadout(r.ship_id);
  end loop;
  insert into backfill_0126
  select count(*), v_fitted, round(extract(epoch from clock_timestamp() - v_t0) * 1000)
    from merchant_hulls_before_0126 where not fitted;
end $$;

-- ── 8. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid      constant uuid := '00000000-0126-4000-8000-000000000001';
  v_fn       text;
  v_def      text;
  v_back     text;
  h          record;
  v_n        int;
  v_bad      bigint;
  v_hulls    bigint;
  v_fitted   bigint;
  v_ms       numeric;
  v_err      text;
  v_player   uuid;
  v_fleet    uuid;
  v_ship     uuid;
  v_port     uuid;
  v_m        uuid;
  v_lis      uuid;
  v_fnc      uuid;
  v_leg      jsonb;
  v_back_c   jsonb;
  v_res      jsonb;
  v_writers  text[];
  v_spd      numeric;
  v_hold     numeric;
  v_hold_n   bigint;
  v_t0       timestamptz;
  v_read_ms  numeric;
  v_notes    text := '';
begin
  -- (a) PARITY BY REVERSE SUBSTITUTION; ACLs unmoved; each hunk in its new body exactly once.
  for v_fn in select fn from defs_before_0126 loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0126 where fn = v_fn order by n desc loop
      v_n := (length(v_back) - length(replace(v_back, h.new, ''))) / length(h.new);
      if v_n <> 1 then
        raise exception '0126 self-assert FAIL: hunk % of % is in the new body % time(s), not once', h.n, v_fn, v_n;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back <> (select def from defs_before_0126 where fn = v_fn) or v_def = v_back then
      raise exception '0126 self-assert FAIL: % is not its pre-image plus only 0126''s hunks', v_fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0126 where fn = v_fn) then
      raise exception '0126 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
  end loop;

  -- (b) ONE WRITER OF A MOUNTED FITTING. Positive control: the pre-image of do_fit carried the insert,
  --     so the scan can see the token. Now exactly one live body in the game's schemas does.
  if strpos((select def from defs_before_0126 where fn = 'cmd.do_fit(uuid, jsonb)'), 'insert into public.ship_fittings') = 0 then
    raise exception '0126 self-assert FAIL: the scan''s positive control — do_fit''s pre-image did not insert a fitting';
  end if;
  select array_agg(n.nspname || '.' || p.proname order by 1) into v_writers
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage')
     and strpos(lower(p.prosrc), 'insert into public.ship_fittings') > 0;
  if v_writers is distinct from array['public.mount_fitting'] then
    raise exception '0126 self-assert FAIL: the live writers of ship_fittings are %, not mount_fitting alone', v_writers;
  end if;
  -- the core is the moved lines (the refusals in their words), and tells no merchant from a player.
  v_def := pg_get_functiondef('public.mount_fitting(uuid, text)'::regprocedure);
  if strpos(v_def, 'E_SLOTS_FULL: % already fills her % % slot(s)') = 0 or strpos(v_def, 'E_NO_SLOT: a % has nowhere to put a %') = 0
     or strpos(v_def, 'is_npc') > 0 or strpos(pg_get_functiondef('cmd.do_fit(uuid, jsonb)'::regprocedure), 'E_SLOTS_FULL') > 0 then
    raise exception '0126 self-assert FAIL: the slot rule is not in mount_fitting alone, or the core reads is_npc';
  end if;

  -- (c) THE WALL: the two new functions and the table are server-only; no new entry point; no client write.
  if has_function_privilege('anon', 'public.mount_fitting(uuid, text)', 'execute')
     or has_function_privilege('authenticated', 'public.mount_fitting(uuid, text)', 'execute')
     or has_function_privilege('anon', 'public.npc_fit_loadout(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.npc_fit_loadout(uuid)', 'execute')
     or has_table_privilege('anon', 'public.npc_loadouts', 'select')
     or has_table_privilege('authenticated', 'public.npc_loadouts', 'select') then
    raise exception '0126 self-assert FAIL: mount_fitting, npc_fit_loadout or npc_loadouts is client-reachable';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select n from entry_points_before_0126)
     or exists (select 1 from public.client_rpc_entry_points() e
                 where e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute'))
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0126 self-assert FAIL: the registry, the grant wall or the read wall';
  end if;

  -- (d) THE AUTHORED PATTERNS: numbered 0..n-1 per class; each within her class's slots and leaving
  --     at least one slot empty; no item that spends hold; every class a merchant sails has one.
  if exists (select 1 from public.npc_loadouts group by class_code
              having max(pattern) + 1 <> count(distinct pattern)) then
    raise exception '0126 self-assert FAIL: a class''s patterns are not numbered 0..n-1';
  end if;
  select count(*) into v_bad from (
    select l.class_code, l.pattern, ik.slot, sum(l.qty) as used
      from public.npc_loadouts l join public.item_kinds ik on ik.code = l.item_code
     group by 1, 2, 3) u
   where u.used > coalesce((select cs.count from public.class_slots cs where cs.class_code = u.class_code and cs.slot = u.slot), 0);
  if v_bad > 0 then
    raise exception '0126 self-assert FAIL: % pattern slot(s) overfill their class''s slots', v_bad;
  end if;
  if exists (select 1 from (select class_code, pattern, sum(qty) as n from public.npc_loadouts group by 1, 2) p
              where p.n >= (select sum(cs.count) from public.class_slots cs where cs.class_code = p.class_code)
                 or p.n < 2) then
    raise exception '0126 self-assert FAIL: a pattern fills every slot, or carries fewer than two fittings';
  end if;
  if exists (select 1 from public.npc_loadouts l join public.item_effects e on e.item_code = l.item_code
              where e.stat = 'hold' and e.delta < 0) then
    raise exception '0126 self-assert FAIL: a pattern spends hold';
  end if;
  if exists (select 1 from merchant_hulls_before_0126 b
              where not exists (select 1 from public.npc_loadouts l where l.class_code = b.class_code)) then
    raise exception '0126 self-assert FAIL: a merchant sails a class with no authored loadout';
  end if;

  -- (e) THE BACKFILL: every merchant hull carries ≥ 2 fittings, none over her slots (recomputed from
  --     class_slots, not from the function), exactly her fleet's pattern; every player's fittings
  --     unmoved, row for row.
  select hulls, fitted, ms into v_hulls, v_fitted, v_ms from backfill_0126;
  if v_hulls = 0 then
    raise exception '0126 self-assert FAIL: no merchant hull to fit (the world has no merchants?)';
  end if;
  select count(*) into v_bad from merchant_hulls_before_0126 b
   where (select coalesce(sum(sf.qty), 0) from public.ship_fittings sf where sf.ship_id = b.ship_id) < 2;
  if v_bad > 0 then
    raise exception '0126 self-assert FAIL: % merchant hull(s) carry fewer than two fittings', v_bad;
  end if;
  select count(*) into v_bad from (
    select sf.ship_id, c.code, ik.slot, sum(sf.qty) as used
      from public.ship_fittings sf
      join public.item_kinds ik on ik.code = sf.item_code
      join public.ships s on s.id = sf.ship_id
      join public.ship_classes c on c.id = s.class_id
     where sf.ship_id in (select ship_id from merchant_hulls_before_0126)
     group by 1, 2, 3) u
   where u.used > coalesce((select cs.count from public.class_slots cs where cs.class_code = u.code and cs.slot = u.slot), 0);
  if v_bad > 0 then
    raise exception '0126 self-assert FAIL: % merchant hull slot(s) carry more than the class allows', v_bad;
  end if;
  select count(*) into v_bad from merchant_hulls_before_0126 b
    join public.ships s on s.id = b.ship_id
   where not b.fitted
     and (select coalesce(jsonb_object_agg(sf.item_code, sf.qty), '{}'::jsonb) from public.ship_fittings sf where sf.ship_id = b.ship_id)
         <> (select jsonb_object_agg(l.item_code, l.qty) from public.npc_loadouts l
              where l.class_code = b.class_code
                and l.pattern = mod(mod(('x' || left(md5(s.fleet_id::text), 8))::bit(32)::int,
                                        (select count(distinct pattern) from public.npc_loadouts where class_code = b.class_code)::int)
                                    + (select count(distinct pattern) from public.npc_loadouts where class_code = b.class_code)::int,
                                    (select count(distinct pattern) from public.npc_loadouts where class_code = b.class_code)::int));
  if v_bad > 0 then
    raise exception '0126 self-assert FAIL: % merchant hull(s) do not carry exactly their fleet''s pattern', v_bad;
  end if;
  if (select (x.n, x.h) from player_fittings_before_0126 x) is distinct from
     (select (count(*), coalesce(md5(string_agg(sf.ship_id::text || ':' || sf.item_code || ':' || sf.qty, ',' order by sf.ship_id, sf.item_code)), ''))
        from public.ship_fittings sf join public.ships s on s.id = sf.ship_id
        join public.fleets f on f.id = s.fleet_id join public.players p on p.id = f.player_id
       where not p.is_npc) then
    raise exception '0126 self-assert FAIL: a player''s fittings moved';
  end if;
  -- FIXED: a second call leaves a fitted hull exactly as she is.
  if (select coalesce(sum(public.npc_fit_loadout(b.ship_id)), 0) from merchant_hulls_before_0126 b) <> 0 then
    raise exception '0126 self-assert FAIL: npc_fit_loadout added to a hull that was already fitted';
  end if;

  -- (f) THE EFFECT, measured: no merchant hull loses a tun; mean speed rating gained; hold gained.
  select count(*) into v_bad from merchant_hulls_before_0126 b where world.ship_stat(b.ship_id, 'hold') < b.hold;
  if v_bad > 0 then
    raise exception '0126 self-assert FAIL: % merchant hull(s) lost hold to their gear', v_bad;
  end if;
  select round(avg(world.ship_stat(b.ship_id, 'speed') / b.speed - 1) * 100, 2),
         sum(world.ship_stat(b.ship_id, 'hold') - b.hold),
         count(*) filter (where world.ship_stat(b.ship_id, 'hold') > b.hold)
    into v_spd, v_hold, v_hold_n
    from merchant_hulls_before_0126 b where not b.fitted;
  v_notes := v_notes || format('speed rating +%s %% on average; hold +%s t over %s nau trader(s), none lower; ',
                               v_spd, v_hold, v_hold_n);
  for h in select b.class_code as fn, count(*)::int as n,
                  round(avg(world.ship_stat(b.ship_id, 'speed') - b.speed), 2)::text as old,
                  round(avg(world.ship_stat(b.ship_id, 'hold') - b.hold), 1)::text as new
             from merchant_hulls_before_0126 b where not b.fitted group by 1 order by 1 loop
    v_notes := v_notes || format('%s ×%s: +%s kn, +%s t; ', h.fn, h.n, h.old, h.new);
  end loop;
  -- what the arrivals tick reads per hull (speed and hold), now over mounted gear: timed for all.
  v_t0 := clock_timestamp();
  perform voyage.ship_speed(b.ship_id), public.ship_hold_capacity(b.ship_id) from merchant_hulls_before_0126 b;
  v_read_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);

  -- (g) THE PROBES, rolled back.
  select id into v_lis from public.ports where code = 'LIS';
  select id into v_fnc from public.ports where code = 'FNC';
  begin
    update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');

    -- A PLAYER's FIT still goes through the door: the store debited, the fitting on, and a full slot
    -- refused E_SLOTS_FULL in the same words (0077:163-174 replayed).
    v_player := public.new_house(c_uid, 'Casa do Aparelho', 'PRT');
    select id, port_id into v_fleet, v_port from public.fleets where player_id = v_player;
    select s.id into v_ship from public.ships s where s.fleet_id = v_fleet order by s.is_flagship desc, s.name limit 1;
    delete from public.ship_fittings where ship_id = v_ship;
    insert into public.player_items (player_id, port_id, item_code, qty) values (v_player, v_port, 'suit-of-sails', 2)
    on conflict (player_id, port_id, item_code) do update set qty = excluded.qty;
    v_res := cmd.do_fit(v_fleet, jsonb_build_object('item', 'suit-of-sails'));
    if (select qty from public.ship_fittings where ship_id = v_ship and item_code = 'suit-of-sails') is distinct from 1
       or (select qty from public.player_items where player_id = v_player and port_id = v_port and item_code = 'suit-of-sails') is distinct from 1
       or v_res->>'item' is distinct from 'suit-of-sails' or (v_res->>'speed') is null then
      raise exception '0126 self-assert FAIL: a player''s FIT did not mount from her store: %', v_res;
    end if;
    -- fill the rest of her rig slots through the door, then one more must be refused.
    update public.player_items set qty = 99 where player_id = v_player and port_id = v_port and item_code = 'suit-of-sails';
    for v_n in 2 .. (select cs.count from public.class_slots cs join public.ship_classes c on c.code = cs.class_code
                       join public.ships s on s.class_id = c.id where s.id = v_ship and cs.slot = 'rig') loop
      perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'suit-of-sails'));
    end loop;
    v_err := null;
    begin
      perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'suit-of-sails'));
    exception when sqlstate 'P0001' then
      v_err := sqlerrm;
    end;
    if v_err is null or v_err not like 'E_SLOTS_FULL: % already fills her % rig slot(s)' then
      raise exception '0126 self-assert FAIL: a full rig was not refused E_SLOTS_FULL through the door (%)', v_err;
    end if;
    if (select qty from public.player_items where player_id = v_player and port_id = v_port and item_code = 'suit-of-sails')
       <> 99 - ((select cs.count from public.class_slots cs join public.ship_classes c on c.code = cs.class_code
                  join public.ships s on s.class_id = c.id where s.id = v_ship and cs.slot = 'rig') - 1) then
      raise exception '0126 self-assert FAIL: a refused FIT took the item from the store';
    end if;
    -- A NEW MERCHANT is founded with her gear: two fleets (the house's own fleet and a formed one),
    -- three hulls of two classes; every hull carries her fleet's pattern.
    select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon),
                             jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
      into v_leg from public.sea_reaches a, public.sea_reaches b
     where a.port_id = v_lis and b.port_id = v_fnc;
    v_back_c := jsonb_build_array(v_leg->1, v_leg->0);
    v_m := public.npc_found(jsonb_build_object(
      'company', 'Casa do Enxoval', 'alt_company', 'Casa do Dote', 'nation', 'PRT', 'ink', 'prt',
      'master', 'Capitao Dotado',
      'blurb', 'A probe company founded so its hulls can be seen to carry their gear.',
      'capital', 40000, 'patience', 0.20, 'wares', '[]'::jsonb, 'roster_ord', 9126,
      'skills', '{}'::jsonb,
      'fleets', jsonb_build_array(
        jsonb_build_object(
          'name', 'Dotada', 'roster_ord', 9126, 'days', 12,
          'ships', jsonb_build_array(jsonb_build_object('class', 'nau', 'name', 'Dotada'),
                                     jsonb_build_object('class', 'carlat', 'name', 'Dotadinha')),
          'officers', '[]'::jsonb,
          'stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                     jsonb_build_object('port', 'FNC', 'course', v_back_c)),
          'alt_stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                         jsonb_build_object('port', 'FNC', 'course', v_back_c))),
        jsonb_build_object(
          'name', 'Prendada', 'roster_ord', 9127, 'days', 12,
          'ships', jsonb_build_array(jsonb_build_object('class', 'barca', 'name', 'Prendada')),
          'officers', '[]'::jsonb,
          'stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                     jsonb_build_object('port', 'FNC', 'course', v_back_c)),
          'alt_stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                         jsonb_build_object('port', 'FNC', 'course', v_back_c))))));
    select count(*), count(*) filter (where (select coalesce(sum(sf.qty), 0) from public.ship_fittings sf where sf.ship_id = s.id) >= 2)
      into v_n, v_bad
      from public.ships s join public.fleets f on f.id = s.fleet_id where f.player_id = v_m;
    if v_n <> 3 or v_bad <> 3 then
      raise exception '0126 self-assert FAIL: a newly founded merchant''s hulls were not fitted (% of % hulls)', v_bad, v_n;
    end if;
    -- and her card serves at least one fitted box (0124's builder draws what is mounted).
    select nf.fleet_id into v_fleet from public.npc_fleets nf where nf.player_id = v_m order by nf.roster_ord limit 1;
    if jsonb_array_length(world.npc_fleet_card(v_fleet)->'ships'->0->'fittings') < 1 then
      raise exception '0126 self-assert FAIL: the new merchant''s card serves no fitting';
    end if;

    raise exception 'ROLLBACK_0126';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0126' then raise; end if;
  end;
  if exists (select 1 from public.players where auth_uid = c_uid)
     or exists (select 1 from public.npc_houses where roster_ord = 9126) then
    raise exception '0126 self-assert FAIL: the probe world was not rolled back';
  end if;

  raise notice '0126 self-assert ok: A MERCHANT IS FITTED BY THE SAME HANDS. cmd.do_fit and public.npc_found reverse to their pre-images hunk by hunk, ACLs unmoved; public.mount_fitting is the ONLY live body that inserts a fitting (positive control: do_fit''s pre-image did), holds the slot rule in 0077''s words and reads no is_npc; mount_fitting, npc_fit_loadout and npc_loadouts server-only, no new entry point, no client write. Patterns numbered densely, within their slots, never full, none spending hold, every merchant class covered. BACKFILL: % bare merchant hull(s) given % fitting(s) in % ms; every merchant hull carries >= 2 and exactly her fleet''s pattern, none over her slots; every player''s fittings unmoved (% rows); a second call adds nothing. EFFECT: %speed + hold reads for all % merchant hull(s) % ms (bare: % ms). Probes: a player''s FIT mounts from her store through the door and a full rig refuses E_SLOTS_FULL taking nothing; a newly founded merchant (2 fleets, 3 hulls) carries her gear and her card serves it. Rolled back.',
    v_hulls, v_fitted, v_ms, (select n from player_fittings_before_0126), v_notes,
    (select count(*) from merchant_hulls_before_0126), v_read_ms, (select ms from reads_before_0126);
end $$;
