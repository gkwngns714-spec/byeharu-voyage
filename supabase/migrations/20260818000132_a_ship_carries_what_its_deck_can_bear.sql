-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0132 — A SHIP CARRIES WHAT ITS DECK CAN BEAR  (gear racks, one row per mounted unit, two budgets)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW ─────────────────────────────────────────────────────────────────────────────────────
-- docs/SHIPS_AND_SKILLS.md §8, step S10 "Gear I: racks, units, budgets" (§6.1, §6.2, §6.9). The owner:
-- *"the gear should be like eve too, plus rs3"*. EVE's half starts here: a hull has RACKS (High / Mid /
-- Low / Refit, + the Flourish) that take any item of their rack, and two fitting BUDGETS — Deck (EVE's
-- CPU) and Hands (EVE's powergrid). RS3's half (grades, wear, perks) needs a mounted piece to be a
-- ROW of its own, so this file also turns "what is mounted" from a stacked count into one row per unit.
--
-- ── WHAT SAYS THE OPPOSITE TODAY, NAMED ─────────────────────────────────────────────────────────
--   * public.class_slots (0074) is TYPED: seven kinds (rig, weapon, ground-tackle, steering, hull,
--     lookout, flourish), read by world.ship_slots (0127) and so by public.mount_fitting (0126 as cut
--     by 0127) — a barca could not carry two suits of sails though it has two Mid places.
--   * public.ship_fittings (0074) stacks a fitting by qty — no identity per unit, so no wear, no perk.
--   * Nothing knows what a fitting COSTS a hull: every legal loadout is "fill the slots".
--   * Writers/readers of ship_fittings, every one in a LIVE body (scanned, not remembered): writes —
--     public.mount_fitting (insert), cmd.do_unfit (delete/decrement); reads — world.ship_stats,
--     world.ship_view, public.npc_fit_loadout, cmd.do_unfit (which hull), public.mount_fitting (used
--     count). No client code reads it (grep src: nothing) and no client role holds a grant on it.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) public.gear_racks (5 rows) — the one home of a RACK: its code, the word the player reads, its
--     order. data/gear.json; the world guard holds it, item_profile and the rack rows to the file.
-- (2) public.item_profile (12 rows) — each live item is GRADE 1 of its base type: base_type, rack,
--     grade, meta, deck, hands, active (§6.3). item_kinds and item_effects are untouched (asserted).
-- (3) public.class_slots REWRITTEN BY RACK: barca High 1 / Mid 2; carlat High 2 / Mid 3 / Refit 1;
--     nau High 3 / Mid 5 / Low 1 / Refit 2 / Flourish 1 — the live typed counts summed by rack
--     (asserted, kind by kind) plus the new Refit rows. public.class_slot_unlocks converted kind →
--     rack (barca Mid +1 @3, carlat Low +1 @4, nau High +1 @6; dark). world.ship_slots needs NO hunk:
--     it reads class_slots generically, so it now answers by rack (its body is asserted unchanged).
-- (4) public.fitted_units — ONE ROW PER MOUNTED UNIT (id, ship, item, wear 0-100, perks ≤ 2,
--     mounted_at), backfilled from ship_fittings (qty → rows). Written ONLY by public.mount_fitting
--     (insert) and public.unmount_fitting (delete) — a live-body scan with a planted control proves it.
--     wear/perks are recorded and read by nothing until S13/S16 (wear factor 1).
-- (5) public.class_budget(class) / world.ship_budget(ship) — THE ONE READING of the two budgets:
--     Deck = class_profile.deck (0130); Hands = crew_max − ⌈crew_required / 2⌉ (no new column);
--     used = Σ item_profile costs over her units. Read by mount_fitting and world.ship_view.
-- (6) THE CORES, re-cut by hunks sliced from the LIVE bodies: public.mount_fitting — a house lock
--     first, capacity by RACK, then the budgets (E_OVER_DECK / E_OVER_HANDS with figures; checked on
--     FIT only, so nothing mounted today is ever refused after the fact), the insert into
--     fitted_units. NEW public.unmount_fitting — do_unfit's core: one unit off (counted), refits
--     destroyed, perks go with the unit; returns whether the piece goes back to the store.
-- (7) THE DOORS: cmd.do_fit takes the house lock FIRST and counts its store debit (GET DIAGNOSTICS:
--     a double tap that lost the race takes nothing twice); cmd.do_unfit takes the lock first, finds
--     the hull by its units and calls unmount_fitting. public.npc_fit_loadout reads units (lock first).
-- (8) THE READS: world.ship_stats reads units (sum(delta) per unit = 0124's sum(delta × qty), to the
--     digit); world.ship_view serves `fittings` from units (same values) plus two NEW keys — `racks`
--     (world.ship_racks: each rack's word, open / locked counts and the units in it, with their costs) and `budget`
--     ({deck, hands} × {used, max}). The client renders them; it derives none.
-- (9) public.ship_fittings becomes a READ-ONLY VIEW over fitted_units (ship_id, item_code, qty) for
--     one release (security_invoker, server-only). It is not updatable (a GROUP BY view): insert,
--     update and delete are refused (asserted). No live body reads it any more (scan; positive control:
--     the five pre-images did). The old TABLE is RENAMED public.ship_fittings_retired_0132, not dropped:
--     dropping it removes its FK triggers on public.ships, which takes ACCESS EXCLUSIVE on ships (every
--     ship read in the game would queue behind it). It is read by nothing, written by nothing (its FK
--     still cascades a deleted hull's rows), and is DROPPED IN THE NEXT GEAR STEP with the clock unwound.
-- (10) A merchant's card (world.npc_fleet_card = ship_view less id / water / food) now carries `racks`
--     and `budget` too — INTENTIONALLY: what a merchant's hull carries is already public on her card
--     (`fittings`, 0124), and racks / budget are that same fact arranged; no handle, no provisioning.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- No stat moves (every hull's ten stats are the pre-image to the digit), no new item, no wear, no
-- perk, no refit item (the Refit rack is empty until S13 — nothing can be fitted there yet), no skill
-- requirement (S11), no new entry point, no client write, no cron, no knob. Felt change, said plainly:
-- a FIT may now go in any free place of its RACK (two suits of sails on a barca), and a FIT that would
-- overdraw Deck or Hands is refused. `slots` / `slots_locked` in world.ship_view are now keyed by rack
-- (high/mid/…) — that IS the change; the self-assert proves each is the exact rack-sum of the typed
-- pre-image. Every other key is the pre-image, as text.
--
-- ── LOCKS (db push holds every lock until this file commits) ───────────────────────────────────
-- Until §7 this file takes NO lock that any live statement could wait on: only ACCESS SHARE on what it
-- reads (ships, ship_fittings, class_slots …), ROW EXCLUSIVE + row locks on class_slots /
-- class_slot_unlocks (nothing live writes them), and its own new tables. The new tables carry NO FK
-- to item_kinds or ships until §7: an FK takes SHARE ROW EXCLUSIVE on the referenced table until
-- commit, and every player_items / ship_fittings insert's FK check needs ROW SHARE on item_kinds — a
-- FIT parked there while holding ship_fittings would deadlock with §7. Every probe write is inside a
-- rolled-back subtransaction (its locks are released with it).
--   (§1) every heavy pre-image read;  (§2-§4) new tables, functions, re-cuts;
--   (§5) a SNAPSHOT copy of ship_fittings (pg_temp) — the backfill and every comparison read the copy,
--        so a FIT/UNFIT during §5-§6 cannot fake a difference — then the class_slots / unlock rows;
--   (§6) every comparison and the probe house (the old computation re-pointed at the copy);
--   (§7) LAST, ONE short retried step, lock_timeout 2 s, LOCK ORDER fixed:
--          1. ACCESS EXCLUSIVE on public.ship_fittings (the only hot lock; ships itself is never locked
--             beyond ACCESS SHARE — the old table is renamed, not dropped);
--          2. re-sync the units of any hull whose fittings moved since the snapshot (counted);
--          3. rename → ship_fittings_retired_0132, the view in its place;
--          4. SHARE ROW EXCLUSIVE on item_kinds and gear_racks (the FKs of item_profile / fitted_units,
--             and class_slots / class_slot_unlocks → gear_racks) — the same order every FIT takes
--             (ship_fittings, then item_kinds), so no cycle can form.
--        After it: catalogue reads and one Σ check (ms). A live transaction cannot be waiting on this
--        file while it waits on them (nothing they need is held before §7), so a deadlock needs a cycle
--        that does not exist; a lock_timeout is retried (5 × 0.2 s), then LOCK CONTENTION, not a result.
--        Player ship reads block only while step 1 queues (≤ 2 s per try) and for the ms after it.
--
-- SUPERSEDES, by hunks sliced from the LIVE bodies (LF-normalised), each asserted to occur exactly once
-- and to reverse to its pre-image, ACLs unchanged: public.mount_fitting (0126 as cut by 0127),
-- cmd.do_fit (0126), cmd.do_unfit (0074), public.npc_fit_loadout (0126), world.ship_stats (0127),
-- world.ship_view (0127).
--
-- ROLLBACK (forward migration): drop the view; re-fill public.ship_fittings_retired_0132 from
-- `select ship_id, item_code, count(*) from fitted_units group by 1, 2` and rename it back to
-- public.ship_fittings (0074's table, its FK and policy intact); reverse the six bodies' hunks
-- (old text is in hunks_0132); restore class_slots' fourteen typed rows and the three unlocks (listed in
-- slots_before_0132 / unlocks below, and in 0074 / 0127); drop unmount_fitting, ship_racks, ship_budget,
-- class_budget, fitting_lock, fitted_units, item_profile, gear_racks.
-- VERSION: 0132. Applies on prod head 0131.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);   -- never queue the arrivals sweep for long
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
-- Run a statement that takes a lock; a lock the live world holds (55P03 lock_timeout, 40P01 deadlock)
-- is not an answer: retry, then fail as LOCK CONTENTION. Returns the milliseconds it took.
create or replace function pg_temp.locked_0132(p_sql text, p_what text)
returns numeric
language plpgsql
as $$
declare
  v_try   int := 0;
  v_state text;
  v_msg   text;
  v_t0    timestamptz := clock_timestamp();
begin
  loop
    v_try := v_try + 1;
    begin
      execute p_sql;
      return round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
    exception when lock_not_available or deadlock_detected then
      get stacked diagnostics v_msg = message_text, v_state = returned_sqlstate;
    end;
    if v_try >= 5 then
      raise exception '0132 self-assert FAIL: LOCK CONTENTION, not a result — % could not get its locks in 5 tries (%: %). Re-run the push.',
        p_what, v_state, v_msg;
    end if;
    perform pg_sleep(0.2);
  end loop;
end $$;

-- ── 1. THE PRE-IMAGES (every heavy read happens here, before any lock) ─────────────────────────
create temp table defs_before_0132 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from unnest(array['public.mount_fitting(uuid, text)',
                    'cmd.do_fit(uuid, jsonb)',
                    'cmd.do_unfit(uuid, jsonb)',
                    'public.npc_fit_loadout(uuid)',
                    'world.ship_stats(uuid)',
                    'world.ship_view(uuid)']) f(fn);

-- world.ship_slots is NOT re-cut: its body must come out of this file exactly as it went in.
create temp table slots_fn_before_0132 on commit drop as
select replace(pg_get_functiondef('world.ship_slots(uuid)'::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = 'world.ship_slots(uuid)'::regprocedure), '') as acl;

create temp table before_0132 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select md5(string_agg(to_jsonb(k)::text, '|' order by k.code)) from public.item_kinds k) as kinds_hash,
       (select md5(string_agg(to_jsonb(e)::text, '|' order by e.item_code, e.stat)) from public.item_effects e) as effects_hash,
       (select md5(string_agg(to_jsonb(c)::text, '|' order by c.code)) from public.ship_classes c) as classes_hash,
       (select md5(string_agg(to_jsonb(p)::text, '|' order by p.class_code)) from public.class_profile p) as profile_hash;

-- class_slots and the unlocks as they stand: TYPED (0074 / 0127). The rollback list, and the source of
-- the rack-sum check.
create temp table slots_before_0132 on commit drop as
select class_code, slot, count from public.class_slots;
create temp table unlocks_before_0132 on commit drop as
select class_code, slot, count, min_level from public.class_slot_unlocks;

-- every hull's served slots, as found (static: class data, levels dark) — the rack-sum source.
create temp table hulls_before_0132 on commit drop as
select s.id as ship_id, c.code as class_code, p.is_npc,
       world.ship_view(s.id) as view, world.ship_stats(s.id) as stats
  from public.ships s
  join public.ship_classes c on c.id = s.class_id
  join public.players p on p.id = s.player_id;

-- What the arrivals tick and a merchant card read per merchant hull — speed + hold, and the whole
-- ship — timed over every merchant hull, before.
create temp table reads_0132 (phase text, what text, hulls bigint, ms numeric) on commit drop;
do $$
declare
  v_t0 timestamptz;
  v_n  bigint := (select count(*) from hulls_before_0132 where is_npc);
begin
  v_t0 := clock_timestamp();
  perform voyage.ship_speed(h.ship_id), public.ship_hold_capacity(h.ship_id) from hulls_before_0132 h where h.is_npc;
  insert into reads_0132 values ('before', 'speed+hold', v_n, round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
  v_t0 := clock_timestamp();
  perform world.ship_view(h.ship_id) from hulls_before_0132 h where h.is_npc;
  insert into reads_0132 values ('before', 'ship_view', v_n, round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
end $$;

-- ── 2. THE CATALOGUE: racks and item profiles (data/gear.json) ─────────────────────────────────
create table if not exists public.gear_racks (
  code text primary key check (code ~ '^[a-z]+$'),
  word text not null,
  ord  int  not null unique check (ord > 0)
);
comment on table public.gear_racks is
  '0132: THE one home of a gear RACK (docs/SHIPS_AND_SKILLS.md §6.1): code, the word the player reads, '
  'the order a ship is read in. class_slots, class_slot_unlocks and item_profile name a rack by its code '
  '(FK). Authored in data/gear.json; the world guard holds it to the file.';
alter table public.gear_racks enable row level security;
revoke all on table public.gear_racks from public, anon, authenticated;

insert into public.gear_racks (code, word, ord) values
  ('high', 'High', 1), ('mid', 'Mid', 2), ('low', 'Low', 3), ('refit', 'Refit', 4), ('flourish', 'Flourish', 5)
on conflict (code) do nothing;

create table if not exists public.item_profile (
  item_code text primary key,      -- FK to item_kinds added in §7 (see LOCKS)
  base_type text not null,
  rack      text not null references public.gear_racks(code),
  grade     int  not null check (grade between 1 and 5),
  meta      int  not null default 0 check (meta >= 0),
  deck      int  not null check (deck >= 0),
  hands     int  not null check (hands >= 0),
  active    boolean not null default false
);
comment on table public.item_profile is
  '0132: an item''s place in the gear model (§6.2): base type, the RACK it goes in, grade 1-5 and meta '
  '(the twelve live items are grade 1, meta 0), what one mounted unit costs of the two fitting budgets '
  '(deck, hands), and whether it is an active module (bites from S13). item_kinds stays the catalogue '
  'and item_effects the effects. Read by mount_fitting, ship_budget and ship_view. data/gear.json.';
alter table public.item_profile enable row level security;
revoke all on table public.item_profile from public, anon, authenticated;

insert into public.item_profile (item_code, base_type, rack, grade, meta, deck, hands, active) values
  ('broadside-guns',   'Long Guns',       'high',     1, 0, 6, 8, true),
  ('boarding-gear',    'Boarding Gear',   'high',     1, 0, 2, 5, true),
  ('powder-magazine',  'Powder Magazine', 'high',     1, 0, 3, 2, false),
  ('suit-of-sails',    'Sails',           'mid',      1, 0, 3, 4, false),
  ('bowsprit-and-jib', 'Headsails',       'mid',      1, 0, 2, 2, false),
  ('rudder-and-helm',  'Rudder',          'mid',      1, 0, 2, 2, false),
  ('anchor-and-cable', 'Anchor',          'mid',      1, 0, 3, 2, false),
  ('crows-nest',       'Lookout',         'mid',      1, 0, 1, 1, false),
  ('ballast',          'Ballast',         'low',      1, 0, 2, 0, false),
  ('copper-sheathing', 'Sheathing',       'low',      1, 0, 3, 0, false),
  ('hold-fittings',    'Hold Frames',     'low',      1, 0, 2, 0, false),
  ('figurehead',       'Figurehead',      'flourish', 1, 0, 0, 0, false)
on conflict (item_code) do nothing;

-- the rack rows (applied in §5, under the lock)
create temp table racks_0132 (class_code text, rack text, count int) on commit drop;
insert into racks_0132 values
  ('barca', 'high', 1), ('barca', 'mid', 2),
  ('carlat', 'high', 2), ('carlat', 'mid', 3), ('carlat', 'refit', 1),
  ('nau', 'high', 3), ('nau', 'mid', 5), ('nau', 'low', 1), ('nau', 'refit', 2), ('nau', 'flourish', 1);

-- ── 3. ONE ROW PER MOUNTED UNIT ────────────────────────────────────────────────────────────────
-- No FK to ships, as 0127's ship_xp has none (0127:125): an FK would hold SHARE ROW EXCLUSIVE on ships
-- — the arrivals tick's table — until commit. No live body deletes a ship; a unit whose hull is gone is
-- never read (every read joins by ship_id). The FK to item_kinds is added in §7 (see LOCKS).
create table if not exists public.fitted_units (
  id         uuid primary key default gen_random_uuid(),
  ship_id    uuid not null,
  item_code  text not null,
  wear       numeric(5,2) not null default 0 check (wear between 0 and 100),
  perks      text[] not null default '{}' check (cardinality(perks) <= 2),
  mounted_at timestamptz not null default now()
);
create index if not exists fitted_units_ship_item_idx on public.fitted_units (ship_id, item_code);
comment on table public.fitted_units is
  '0132: ONE ROW PER MOUNTED UNIT (docs/SHIPS_AND_SKILLS.md §2, §6.2) — its own wear (0-100) and up to two '
  'perks, which go with the unit when it comes off. Written ONLY by public.mount_fitting (insert) and '
  'public.unmount_fitting (delete); read by world.ship_stats, world.ship_view, world.ship_budget. wear and '
  'perks are recorded and read by nothing until S13 / S16 (wear factor 1). public.ship_fittings is a '
  'read-only view over this table for one release.';
alter table public.fitted_units enable row level security;
revoke all on table public.fitted_units from public, anon, authenticated;

-- ── 4. THE NEW FUNCTIONS AND THE RE-CUTS ───────────────────────────────────────────────────────
create or replace function public.fitting_lock(p_player uuid)
returns void
language sql
set search_path = public, pg_temp
as $$
  -- 0132: ONE HOUSE'S FITTINGS, ONE AT A TIME — a transaction-scoped advisory lock on the house
  -- (re-entrant), taken FIRST by every door and core that reads the store or the mounted units before
  -- it writes them. No table row is locked, so nothing the ticks hold is waited on.
  select pg_advisory_xact_lock(hashtextextended('fitting:' || p_player::text, 132))
$$;
comment on function public.fitting_lock(uuid) is
  '0132: the per-house advisory lock of fitting writes (do_fit, do_unfit, mount_fitting, unmount_fitting, '
  'npc_fit_loadout). Server-only.';
revoke all on function public.fitting_lock(uuid) from public, anon, authenticated;

create or replace function public.class_budget(p_class text)
returns table (deck int, hands int)
language sql
stable
set search_path = public, pg_temp
as $$
  -- 0132: A HULL CLASS'S TWO FITTING BUDGETS. Deck = class_profile.deck (0130, EVE's CPU); Hands =
  -- crew_max − ⌈crew_required / 2⌉ (EVE's powergrid), from columns the class already has.
  select coalesce(cp.deck, 0), c.crew_max - (c.crew_required + 1) / 2
    from public.ship_classes c
    left join public.class_profile cp on cp.class_code = c.code
   where c.code = p_class
$$;
comment on function public.class_budget(text) is
  '0132: THE one formula of a class''s Deck and Hands budgets. Read by world.ship_budget. Server-only.';
revoke all on function public.class_budget(text) from public, anon, authenticated;

create or replace function world.ship_budget(p_ship uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0132: THE ONE READING OF A HULL'S BUDGETS — {deck, hands} × {used, max}: her class's budgets
  -- (public.class_budget) and what her mounted units cost (item_profile). Null for no such ship.
  select jsonb_build_object(
           'deck',  jsonb_build_object('used', coalesce(u.deck, 0),  'max', b.deck),
           'hands', jsonb_build_object('used', coalesce(u.hands, 0), 'max', b.hands))
    from public.ships s
    join public.ship_classes c on c.id = s.class_id
   cross join lateral public.class_budget(c.code) b
    left join lateral (select sum(ip.deck)::int as deck, sum(ip.hands)::int as hands
                         from public.fitted_units fu
                         join public.item_profile ip on ip.item_code = fu.item_code
                        where fu.ship_id = s.id) u on true
   where s.id = p_ship
$$;
comment on function world.ship_budget(uuid) is
  '0132: THE one reading of a hull''s Deck and Hands, used and max. Read by public.mount_fitting (the FIT '
  'check) and world.ship_view (served as `budget`). Server-only.';
revoke all on function world.ship_budget(uuid) from public, anon, authenticated;

create or replace function world.ship_racks(p_ship uuid, p_slots jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $sr$
begin
  -- 0132: A HULL'S RACKS, AS SERVED — every rack she has places in (or that a level opens), in the
  -- order a ship is read (gear_racks.ord), with the word the player reads, how many places are open
  -- and locked (p_slots = world.ship_slots(ship), the one reading of capacity, passed in so it is
  -- read once), and the units mounted there with what each costs. PL/pgSQL so the plan is cached:
  -- inlined into ship_view's SQL body it was re-planned per hull (measured: ×1.8 the builder's time).
  return (select coalesce(jsonb_agg(jsonb_build_object(
                   'rack', gr.code, 'word', gr.word,
                   'open', coalesce((p_slots->'open'->>gr.code)::int, 0),
                   'locked', coalesce((p_slots->'locked'->gr.code->>'count')::int, 0),
                   'at_level', (p_slots->'locked'->gr.code->>'at_level')::int,
                   'fitted', coalesce(fu.fitted, '[]'::jsonb))
                   order by gr.ord), '[]'::jsonb)
            from public.gear_racks gr
            left join (select ip.rack,
                              jsonb_agg(jsonb_build_object('code', ik.code, 'name', ik.name, 'slot', ik.slot,
                                                           'deck', ip.deck, 'hands', ip.hands)
                                        order by ik.slot, ik.name, u.mounted_at, u.id) as fitted
                         from public.fitted_units u
                         join public.item_kinds ik on ik.code = u.item_code
                         join public.item_profile ip on ip.item_code = u.item_code
                        where u.ship_id = p_ship
                        group by ip.rack) fu on fu.rack = gr.code
           where (p_slots->'open') ? gr.code or (p_slots->'locked') ? gr.code or fu.rack is not null);
end $sr$;
comment on function world.ship_racks(uuid, jsonb) is
  '0132: a hull''s racks as world.ship_view serves them (`racks`): capacity from world.ship_slots, units '
  'from public.fitted_units, words from public.gear_racks. Server-only.';
revoke all on function world.ship_racks(uuid, jsonb) from public, anon, authenticated;

create or replace function public.unmount_fitting(p_ship uuid, p_item_code text)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $uf$
declare
  k       public.item_kinds%rowtype;
  v_ship  public.ships%rowtype;
  v_unit  uuid;
  v_rack  text;
  v_n     int;
begin
  -- 0132: TAKE ONE UNIT OFF ONE HULL — cmd.do_unfit's core. The most worn unit of the item comes off
  -- first (all are 0 until S13), then the newest. Its perks go with it (they live on the row). A
  -- refit is destroyed (false: nothing goes back to the store); any other piece goes back (true).
  -- Repair on the way off is S13's: at wear 0 there is nothing to charge.
  select * into k from public.item_kinds where code = p_item_code;
  if k.code is null then
    raise exception 'E_NO_SUCH_ITEM: nothing is called "%"', coalesce(p_item_code, '') using errcode = 'P0001';
  end if;
  select * into v_ship from public.ships where id = p_ship;
  if v_ship.id is null then
    raise exception 'E_NO_SUCH_SHIP: there is no ship %', p_ship using errcode = 'P0001';
  end if;
  perform public.fitting_lock(v_ship.player_id);

  select u.id, ip.rack into v_unit, v_rack
    from public.fitted_units u
    left join public.item_profile ip on ip.item_code = u.item_code
   where u.ship_id = v_ship.id and u.item_code = k.code
   order by u.wear desc, u.mounted_at desc, u.id
   limit 1;
  if v_unit is null then
    raise exception 'E_NOT_FITTED: % carries no %', v_ship.name, k.name using errcode = 'P0001';
  end if;
  delete from public.fitted_units where id = v_unit;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'E_NOT_FITTED: % carries no %', v_ship.name, k.name using errcode = 'P0001';
  end if;
  return coalesce(v_rack, '') <> 'refit';
end $uf$;
comment on function public.unmount_fitting(uuid, text) is
  '0132: THE one core that takes a fitting off a hull (one unit, counted; refits destroyed). Called by '
  'cmd.do_unfit. With public.mount_fitting, the only writer of public.fitted_units. Server-only.';
revoke all on function public.unmount_fitting(uuid, text) from public, anon, authenticated;

-- THE HUNKS (old → new), sliced from the live bodies
create temp table hunks_0132 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0132 values
-- public.mount_fitting: lock, capacity by RACK, the budgets, the unit row
('public.mount_fitting(uuid, text)', 1,
$h$  v_open  jsonb;
  v_lvl   int;
  v_ask   int;
begin
$h$,
$h$  v_open  jsonb;
  v_lvl   int;
  v_ask   int;
  v_rack  text;      -- 0132: the RACK this item goes in, and the word the player reads for it
  v_word  text;
  v_deck  int;       -- 0132: what one unit costs of the two fitting budgets
  v_hands int;
  v_bud   jsonb;
begin
$h$),
('public.mount_fitting(uuid, text)', 2,
$h$  select * into v_ship from public.ships where id = p_ship;
  if v_ship.id is null then
    raise exception 'E_NO_SUCH_SHIP: there is no ship %', p_ship using errcode = 'P0001';
  end if;
$h$,
$h$  select * into v_ship from public.ships where id = p_ship;
  if v_ship.id is null then
    raise exception 'E_NO_SUCH_SHIP: there is no ship %', p_ship using errcode = 'P0001';
  end if;
  -- 0132: ONE HOUSE'S FITTINGS, ONE AT A TIME (re-entrant: the doors took it first).
  perform public.fitting_lock(v_ship.player_id);
  -- 0132: the item's RACK and its costs — public.item_profile, the one home of both — and what she
  -- carries in that rack, counted unit by unit ONCE (a RACK takes any item of its rack, EVE).
  select ip.rack, gr.word, ip.deck, ip.hands into v_rack, v_word, v_deck, v_hands
    from public.item_profile ip join public.gear_racks gr on gr.code = ip.rack
   where ip.item_code = k.code;
  select count(*) into v_used
    from public.fitted_units u join public.item_profile ip on ip.item_code = u.item_code
   where u.ship_id = v_ship.id and ip.rack = v_rack;
$h$),
('public.mount_fitting(uuid, text)', 3,
$h$  v_slots := coalesce((v_open->'open'->>k.slot)::int, 0);
$h$,
$h$  v_slots := coalesce((v_open->'open'->>v_rack)::int, 0);   -- 0132: her slots of this item's RACK
$h$),
('public.mount_fitting(uuid, text)', 4,
$h$    if v_open->'locked' ? k.slot
       and (select coalesce(sum(sf.qty), 0) from public.ship_fittings sf join public.item_kinds ik on ik.code = sf.item_code
             where sf.ship_id = v_ship.id and ik.slot = k.slot) >= v_slots then
      perform cmd.refuse('E_SLOT_LOCKED',
        format('%s opens another %s slot at level %s', v_ship.name, k.slot, v_open->'locked'->k.slot->>'at_level'),
        cmd.figures(v_lvl, (v_open->'locked'->k.slot->>'at_level')::int, 'level'));
    end if;
$h$,
$h$    if v_open->'locked' ? v_rack and v_used >= v_slots then
      perform cmd.refuse('E_SLOT_LOCKED',
        format('%s opens another %s slot at level %s', v_ship.name, v_word, v_open->'locked'->v_rack->>'at_level'),
        cmd.figures(v_lvl, (v_open->'locked'->v_rack->>'at_level')::int, 'level'));
    end if;
$h$),
('public.mount_fitting(uuid, text)', 5,
$h$  select coalesce(sum(sf.qty), 0) into v_used
    from public.ship_fittings sf join public.item_kinds ik on ik.code = sf.item_code
   where sf.ship_id = v_ship.id and ik.slot = k.slot;
  if v_used >= v_slots then
    raise exception 'E_SLOTS_FULL: % already fills her % % slot(s)',
      v_ship.name, v_slots, k.slot using errcode = 'P0001';
  end if;

  insert into public.ship_fittings (ship_id, item_code, qty) values (v_ship.id, k.code, 1)
  on conflict (ship_id, item_code) do update set qty = public.ship_fittings.qty + 1;
$h$,
$h$  -- 0132: her places in the item's RACK, against what she carries there (counted above, once).
  if v_used >= v_slots then
    perform cmd.refuse('E_SLOTS_FULL',
      format('%s has no free %s slot (%s / %s used)', v_ship.name, v_word, v_used, v_slots));
  end if;

  -- 0132: THE TWO FITTING BUDGETS (world.ship_budget, the one reading). Checked on a FIT only, so
  -- nothing already mounted is ever refused after the fact; an item that costs nothing never is.
  v_bud := world.ship_budget(v_ship.id);
  if v_deck > 0 and (v_bud->'deck'->>'used')::int + v_deck > (v_bud->'deck'->>'max')::int then
    perform cmd.refuse('E_OVER_DECK',
      format('Fitting %s takes %s deck; %s has %s / %s deck left', k.name, v_deck, v_ship.name,
             greatest(0, (v_bud->'deck'->>'max')::int - (v_bud->'deck'->>'used')::int), (v_bud->'deck'->>'max')::int),
      cmd.figures(greatest(0, (v_bud->'deck'->>'max')::int - (v_bud->'deck'->>'used')::int), v_deck, 'deck'));
  end if;
  if v_hands > 0 and (v_bud->'hands'->>'used')::int + v_hands > (v_bud->'hands'->>'max')::int then
    perform cmd.refuse('E_OVER_HANDS',
      format('Fitting %s takes %s hands; %s has %s / %s hands left', k.name, v_hands, v_ship.name,
             greatest(0, (v_bud->'hands'->>'max')::int - (v_bud->'hands'->>'used')::int), (v_bud->'hands'->>'max')::int),
      cmd.figures(greatest(0, (v_bud->'hands'->>'max')::int - (v_bud->'hands'->>'used')::int), v_hands, 'hands'));
  end if;

  -- 0132: ONE ROW PER MOUNTED UNIT.
  insert into public.fitted_units (ship_id, item_code) values (v_ship.id, k.code);
$h$),
-- cmd.do_fit: the house lock FIRST, and a store debit that counts its row
('cmd.do_fit(uuid, jsonb)', 1,
$h$  v_have  int;
begin
$h$,
$h$  v_have  int;
  v_rows  int;   -- 0132: the store debit's row count
begin
$h$),
('cmd.do_fit(uuid, jsonb)', 2,
$h$  select * into f from public.fleets where id = p_fleet;
$h$,
$h$  select * into f from public.fleets where id = p_fleet;
  -- 0132: ONE HOUSE'S FITTINGS, ONE AT A TIME — taken before the store is read (a double tap waits here).
  perform public.fitting_lock(f.player_id);
$h$),
('cmd.do_fit(uuid, jsonb)', 3,
$h$  update public.player_items set qty = qty - 1
   where player_id = f.player_id and port_id = f.port_id and item_code = k.code;
$h$,
$h$  -- 0132: the store debit COUNTS its row — a tap that finds the piece already gone takes nothing.
  update public.player_items set qty = qty - 1
   where player_id = f.player_id and port_id = f.port_id and item_code = k.code and qty >= 1;
  get diagnostics v_rows = row_count;
  if v_rows <> 1 then
    raise exception 'E_NONE_HERE: you keep no % in this city', k.name using errcode = 'P0001';
  end if;
$h$),
-- cmd.do_unfit: the house lock FIRST; the hull is found by its units; the core takes the unit off
('cmd.do_unfit(uuid, jsonb)', 1,
$h$  select * into f from public.fleets where id = p_fleet;
$h$,
$h$  select * into f from public.fleets where id = p_fleet;
  -- 0132: ONE HOUSE'S FITTINGS, ONE AT A TIME — taken before anything is read (a double tap waits here).
  perform public.fitting_lock(f.player_id);
$h$),
('cmd.do_unfit(uuid, jsonb)', 2,
$h$      join public.ship_fittings sf on sf.ship_id = s.id and sf.item_code = k.code
$h$,
$h$      join public.fitted_units sf on sf.ship_id = s.id and sf.item_code = k.code   -- 0132: her mounted units
$h$),
('cmd.do_unfit(uuid, jsonb)', 3,
$h$  if not exists (select 1 from public.ship_fittings where ship_id = v_ship.id and item_code = k.code) then
    raise exception 'E_NOT_FITTED: % carries no %', v_ship.name, k.name using errcode = 'P0001';
  end if;

  -- DELETE THE LAST ONE RATHER THAN DECREMENT IT TO ZERO: ship_fittings carries check (qty > 0),
  -- so an update to 0 is refused before any tidying delete could run. The check is right - a row
  -- saying "she carries none of these" is not a fact worth keeping - so the code bends, not it.
  if (select qty from public.ship_fittings where ship_id = v_ship.id and item_code = k.code) <= 1 then
    delete from public.ship_fittings where ship_id = v_ship.id and item_code = k.code;
  else
    update public.ship_fittings set qty = qty - 1 where ship_id = v_ship.id and item_code = k.code;
  end if;

  -- BACK INTO THE STORE IN THIS CITY, which is the same door it came out of.
  insert into public.player_items (player_id, port_id, item_code, qty)
  values (f.player_id, f.port_id, k.code, 1)
  on conflict (player_id, port_id, item_code) do update set qty = public.player_items.qty + 1;
$h$,
$h$  -- 0132: THE TAKING-OFF IS public.unmount_fitting — one unit off this hull, counted (E_NOT_FITTED in
  -- the same words when there is none). A refit is destroyed; anything else comes BACK INTO THE STORE
  -- IN THIS CITY, which is the same door it came out of.
  if public.unmount_fitting(v_ship.id, k.code) then
    insert into public.player_items (player_id, port_id, item_code, qty)
    values (f.player_id, f.port_id, k.code, 1)
    on conflict (player_id, port_id, item_code) do update set qty = public.player_items.qty + 1;
  end if;
$h$),
-- public.npc_fit_loadout: the lock first, and "already fitted" read off the units
('public.npc_fit_loadout(uuid)', 1,
$h$  if exists (select 1 from public.ship_fittings where ship_id = p_ship) then
    return 0;
  end if;
$h$,
$h$  -- 0132: one house's fittings one at a time, and "already fitted" is read off the mounted units.
  perform public.fitting_lock((select s.player_id from public.ships s where s.id = p_ship));
  if exists (select 1 from public.fitted_units where ship_id = p_ship) then
    return 0;
  end if;
$h$),
-- world.ship_stats: one row per unit
('world.ship_stats(uuid)', 1,
$h$  with d as (
    select e.stat, sum(e.delta * f.qty) as delta
      from public.ship_fittings f
      join public.item_effects e on e.item_code = f.item_code
     where f.ship_id = p_ship
     group by e.stat
  )
$h$,
$h$  with d as (
    -- 0132: ONE ROW PER MOUNTED UNIT (public.fitted_units). A unit counts whole — its wear factor is 1
    -- until S13 makes wear bite — so sum(delta) over units is 0124's sum(delta × qty), to the digit.
    select e.stat, sum(e.delta) as delta
      from public.fitted_units f
      join public.item_effects e on e.item_code = f.item_code
     where f.ship_id = p_ship
     group by e.stat
  )
$h$),
-- world.ship_view: fittings from units (same values); NEW racks + budget
('world.ship_view(uuid)', 1,
$h$             from public.ship_fittings sf join public.item_kinds ik on ik.code = sf.item_code
            where sf.ship_id = s.id),
$h$,
$h$             -- 0132: her mounted UNITS, counted per item — the same `qty` the stacked rows carried.
             from (select u.item_code, count(*)::int as qty from public.fitted_units u
                    where u.ship_id = s.id group by u.item_code) sf
             join public.item_kinds ik on ik.code = sf.item_code),
$h$),
('world.ship_view(uuid)', 2,
$h$           'slots_locked', y.sl->'locked',
$h$,
$h$           'slots_locked', y.sl->'locked',
           -- 0132: HER RACKS (world.ship_racks: each rack's word, open / locked places, the units in it and
           -- what each costs) — drawn by the client, which derives no rack and no count.
           'racks', world.ship_racks(s.id, y.sl),
           -- 0132: her two fitting budgets — world.ship_budget, the one reading.
           'budget', world.ship_budget(s.id),
$h$);

create or replace function pg_temp.recut_0132(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0132 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0132 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0132(fn) from defs_before_0132 order by fn;

comment on function public.mount_fitting(uuid, text) is
  '0126/0132: THE one core that puts a fitting on a hull — the house lock, her slots of the item''s RACK '
  '(world.ship_slots: E_NO_SLOT / E_SLOTS_FULL), the two budgets on FIT only (world.ship_budget: E_OVER_DECK '
  '/ E_OVER_HANDS), one row into public.fitted_units. Called by cmd.do_fit and public.npc_fit_loadout. '
  'Server-only.';

-- ── 5. THE SNAPSHOT, the backfill from it, and the rack rows (no lock anyone waits on) ──────────
-- ship_fittings as it stands NOW, copied: the backfill and every §6 comparison read this copy, so a
-- FIT / UNFIT landing during §5-§6 cannot fake a difference; §7 re-syncs any hull that moved since.
create temp table sf_snap_0132 on commit drop as
select ship_id, item_code, qty from public.ship_fittings;

insert into public.fitted_units (ship_id, item_code)
select sf.ship_id, sf.item_code
  from sf_snap_0132 sf
 cross join lateral generate_series(1, sf.qty)
 order by sf.ship_id, sf.item_code;
analyze public.fitted_units;

-- The OLD stat computation and ship builder, kept under pg_temp names and re-pointed at the snapshot:
-- §6 compares old against new on the SAME statement (one snapshot, STABLE functions) over the SAME
-- fittings (the copy, and the units backfilled from it).
do $$
declare
  v_def text;
begin
  v_def := (select def from defs_before_0132 where fn = 'world.ship_stats(uuid)');
  v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION world.ship_stats(', 'CREATE OR REPLACE FUNCTION pg_temp.ship_stats_before_0132(');
  if strpos(v_def, 'from public.ship_fittings f') = 0 then
    raise exception '0132 self-assert FAIL: the old ship_stats does not read ship_fittings where expected';
  end if;
  execute replace(v_def, 'from public.ship_fittings f', 'from pg_temp.sf_snap_0132 f');
  v_def := (select def from defs_before_0132 where fn = 'world.ship_view(uuid)');
  v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION world.ship_view(', 'CREATE OR REPLACE FUNCTION pg_temp.ship_view_before_0132(');
  if strpos(v_def, 'from public.ship_fittings sf') = 0 then
    raise exception '0132 self-assert FAIL: the old ship_view does not read ship_fittings where expected';
  end if;
  v_def := replace(v_def, 'from public.ship_fittings sf', 'from pg_temp.sf_snap_0132 sf');
  execute replace(v_def, 'world.ship_stats(s.id)', 'pg_temp.ship_stats_before_0132(s.id)');
end $$;

delete from public.class_slots cs
 where not exists (select 1 from racks_0132 r where r.class_code = cs.class_code and r.rack = cs.slot);
insert into public.class_slots (class_code, slot, count)
select class_code, rack, count from racks_0132
on conflict (class_code, slot) do update set count = excluded.count;

update public.class_slot_unlocks u
   set slot = v.rack
  from (values ('barca', 'lookout', 'mid'), ('carlat', 'hull', 'low'), ('nau', 'weapon', 'high')) v(class_code, kind, rack)
 where u.class_code = v.class_code and u.slot = v.kind;

comment on table public.class_slots is
  '0132: how many places a hull has in each gear RACK (high / mid / low / refit / flourish — public.gear_racks). '
  'A rack takes any item of its rack (item_profile.rack). Read only by world.ship_slots. The typed rows of '
  '0074 were summed by rack here; the seven kinds stay the item''s TYPE word (item_kinds.slot), not a capacity. '
  'data/gear.json.';
comment on table public.class_slot_unlocks is
  '0127/0132: places in a RACK a hull''s level opens beyond her class_slots. Read only by world.ship_slots. data/gear.json.';

-- ── 6. THE COMPARISONS AND THE PROBES (before any hot DDL) ─────────────────────────────────────
create temp table probe_0132 (j jsonb) on commit drop;
do $$
declare
  c_uid    constant uuid := '00000000-0132-4000-8000-000000000001';
  v_player uuid;
  v_fleet  uuid;
  v_port   uuid;
  v_barca  uuid;
  v_carlat uuid;
  v_out    jsonb := '{}'::jsonb;
  v_err    text;
  v_det    text;
  v_n      int;
  v_view   jsonb;
  v_res    jsonb;
  v_fit    int;
  v_pat    jsonb;
begin
  begin
    v_player := public.new_house(c_uid, 'Casa do Convés', 'PRT');
    select id, port_id into v_fleet, v_port from public.fleets where player_id = v_player;
    select id into v_barca from public.ships where fleet_id = v_fleet;
    -- a new house's fleet sails two hulls (0107's earned caps): the barca it was founded with + a carlat
    v_carlat := public.commission_ship(v_player, v_fleet, 'carlat', 'Prova Carlat', false, true);
    insert into public.player_items (player_id, port_id, item_code, qty) values
      (v_player, v_port, 'suit-of-sails', 6), (v_player, v_port, 'broadside-guns', 3),
      (v_player, v_port, 'anchor-and-cable', 1)
    on conflict (player_id, port_id, item_code) do update set qty = excluded.qty;

    -- (P1) A RACK TAKES ANY ITEM OF ITS RACK: two suits of sails in the barca's two Mid places (the
    --      typed rig slot was 1), guns in High — through the door, from the store.
    perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'suit-of-sails', 'ship', 'Gaivota'));
    perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'suit-of-sails', 'ship', 'Gaivota'));
    perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'broadside-guns', 'ship', 'Gaivota'));
    v_view := world.ship_view(v_barca);
    v_out := v_out || jsonb_build_object('barca_units', (select count(*) from public.fitted_units where ship_id = v_barca),
                                         'barca_budget', v_view->'budget', 'barca_racks', v_view->'racks',
                                         'store_sails', (select qty from public.player_items where player_id = v_player and port_id = v_port and item_code = 'suit-of-sails'),
                                         'store_guns', (select qty from public.player_items where player_id = v_player and port_id = v_port and item_code = 'broadside-guns'));
    -- (P2) a third piece for Mid is refused E_SLOTS_FULL in its words, and takes nothing from the store
    v_err := null;
    begin
      perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'suit-of-sails', 'ship', 'Gaivota'));
    exception when sqlstate 'P0001' then v_err := sqlerrm;
    end;
    v_out := v_out || jsonb_build_object('mid_full', v_err,
                                         'store_sails_after_refusal', (select qty from public.player_items where player_id = v_player and port_id = v_port and item_code = 'suit-of-sails'));

    -- (P3) HANDS BIND: the carlat with two guns (16 hands) and two suits of sails (8) is at 24 / 24;
    --      a third suit has a free Mid place and the deck for it, and is refused E_OVER_HANDS.
    perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'broadside-guns', 'ship', 'Prova Carlat'));
    perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'broadside-guns', 'ship', 'Prova Carlat'));
    perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'suit-of-sails', 'ship', 'Prova Carlat'));
    perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'suit-of-sails', 'ship', 'Prova Carlat'));
    v_err := null; v_det := null;
    begin
      perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'suit-of-sails', 'ship', 'Prova Carlat'));
    exception when sqlstate 'P0001' then
      get stacked diagnostics v_err = message_text, v_det = pg_exception_detail;
    end;
    v_out := v_out || jsonb_build_object('hands_refusal', v_err, 'hands_figures', v_det,
                                         'carlat_budget', world.ship_view(v_carlat)->'budget',
                                         'store_sails_after_hands', (select qty from public.player_items where player_id = v_player and port_id = v_port and item_code = 'suit-of-sails'));

    -- (P4) DECK BINDS: the carlat's deck lowered to 20 (in this rolled-back block only) — at 18 / 20
    --      deck, an anchor (3 deck) for its last free Mid place is refused E_OVER_DECK with its figures
    --      (Deck is checked before Hands), and the store keeps the anchor.
    update public.class_profile set deck = 20 where class_code = 'carlat';
    v_err := null; v_det := null;
    begin
      perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'anchor-and-cable', 'ship', 'Prova Carlat'));
    exception when sqlstate 'P0001' then
      get stacked diagnostics v_err = message_text, v_det = pg_exception_detail;
    end;
    v_out := v_out || jsonb_build_object('deck_refusal', v_err, 'deck_figures', v_det,
                                         'store_anchor', (select qty from public.player_items where player_id = v_player and port_id = v_port and item_code = 'anchor-and-cable'));
    update public.class_profile set deck = 22 where class_code = 'carlat';

    -- (P5) UNFIT through the door: a unit off, back into the store; the last one off; then nothing to
    --      take off is refused E_NOT_FITTED and the store is not paid twice (the double tap).
    perform cmd.do_unfit(v_fleet, jsonb_build_object('item', 'suit-of-sails', 'ship', 'Gaivota'));
    v_out := v_out || jsonb_build_object('after_unfit_units', (select count(*) from public.fitted_units where ship_id = v_barca and item_code = 'suit-of-sails'),
                                         'after_unfit_store', (select qty from public.player_items where player_id = v_player and port_id = v_port and item_code = 'suit-of-sails'));
    perform cmd.do_unfit(v_fleet, jsonb_build_object('item', 'suit-of-sails', 'ship', 'Gaivota'));
    v_err := null;
    begin
      perform cmd.do_unfit(v_fleet, jsonb_build_object('item', 'suit-of-sails', 'ship', 'Gaivota'));
    exception when sqlstate 'P0001' then v_err := sqlerrm;
    end;
    v_out := v_out || jsonb_build_object('unfit_twice', v_err,
                                         'after_unfit_twice_store', (select qty from public.player_items where player_id = v_player and port_id = v_port and item_code = 'suit-of-sails'),
                                         'after_unfit_twice_units', (select count(*) from public.fitted_units where ship_id = v_barca and item_code = 'suit-of-sails'));
    -- the core, alone: nothing left to take off → E_NOT_FITTED, nothing written
    v_err := null;
    begin
      perform public.unmount_fitting(v_barca, 'suit-of-sails');
    exception when sqlstate 'P0001' then v_err := sqlerrm;
    end;
    v_out := v_out || jsonb_build_object('core_unfit_none', v_err);

    -- (P6) A MERCHANT'S PATH: the barca's guns off through the door (bare now), then npc_fit_loadout
    --      mounts its fleet's pattern on it through the same core, inside the budgets.
    perform cmd.do_unfit(v_fleet, jsonb_build_object('item', 'broadside-guns', 'ship', 'Gaivota'));
    v_fit := public.npc_fit_loadout(v_barca);
    select jsonb_object_agg(l.item_code, l.qty) into v_pat
      from public.npc_loadouts l
     where l.class_code = 'barca'
       and l.pattern = mod(mod(('x' || left(md5(v_fleet::text), 8))::bit(32)::int,
                               (select count(distinct pattern) from public.npc_loadouts where class_code = 'barca')::int)
                           + (select count(distinct pattern) from public.npc_loadouts where class_code = 'barca')::int,
                           (select count(distinct pattern) from public.npc_loadouts where class_code = 'barca')::int);
    v_out := v_out || jsonb_build_object('npc_fit', v_fit, 'npc_pattern', v_pat,
                                         'npc_units', (select jsonb_object_agg(item_code, n) from (select item_code, count(*) as n from public.fitted_units where ship_id = v_barca group by 1) x),
                                         'npc_again', public.npc_fit_loadout(v_barca));

    raise exception 'PROBE_ROLLBACK_0132';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0132' then raise; end if;
  end;
  insert into probe_0132 values (v_out);
end $$;

-- after: the same reads, now over units
do $$
declare
  v_t0 timestamptz;
  v_n  bigint := (select count(*) from hulls_before_0132 where is_npc);
begin
  v_t0 := clock_timestamp();
  perform voyage.ship_speed(h.ship_id), public.ship_hold_capacity(h.ship_id) from hulls_before_0132 h where h.is_npc;
  insert into reads_0132 values ('after', 'speed+hold', v_n, round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
  v_t0 := clock_timestamp();
  perform world.ship_view(h.ship_id) from hulls_before_0132 h where h.is_npc;
  insert into reads_0132 values ('after', 'ship_view', v_n, round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
end $$;

-- THE HEAVY SELF-ASSERT, while only SHARE on ship_fittings is held. Old and new, every hull, read in
-- ONE statement (one snapshot: STABLE functions see what the statement sees), then compared at leisure.
create temp table hulls_after_0132 on commit drop as
select s.id as ship_id,
       world.ship_stats(s.id) as new_stats, pg_temp.ship_stats_before_0132(s.id) as old_stats,
       world.ship_view(s.id) as new_view, pg_temp.ship_view_before_0132(s.id) as old_view
  from public.ships s;
create temp table proven_0132 (k text primary key, v text) on commit drop;
do $$
declare
  v_bad     bigint;
  v_n       bigint;
  v_hulls   bigint;
  v_list    text;
  v_def     text;
  h         record;
  d         record;
  v_p       jsonb := (select j from probe_0132);
  v_enum    text := '';
  v_writers text[];
  v_readers int;
begin
  -- (a) EVERY HULL'S TEN STATS = THE PRE-IMAGE, to the digit: the old computation (over the snapshot
  --     of ship_fittings) against the new (over the units backfilled from it), one statement, as text.
  select count(*), count(*) filter (where a.old_stats::text is distinct from a.new_stats::text)
    into v_hulls, v_bad from hulls_after_0132 a;
  if v_hulls = 0 or v_bad <> 0 then   -- hulls_after_0132 IS public.ships, read in one statement
    raise exception '0132 self-assert FAIL: % of % hull(s) read different stats over units', v_bad, v_hulls;
  end if;
  if exists (select 1 from hulls_after_0132 a where (select count(*) from jsonb_object_keys(a.new_stats)) <> 10) then
    raise exception '0132 self-assert FAIL: a hull''s ship_stats does not carry exactly ten stats';
  end if;
  -- and against the pre-image of §1 (live play may have fitted a hull between §1 and §5: counted)
  select count(*) into v_n from hulls_before_0132 b join hulls_after_0132 a on a.ship_id = b.ship_id
   where b.stats::text is distinct from a.new_stats::text;
  insert into proven_0132 values ('stats', format('%s hulls, 0 differ old/new; %s moved by play since the pre-image', v_hulls, v_n));

  -- (b) SHIP_VIEW = THE PRE-IMAGE PLUS THE NEW KEYS: every key but slots/slots_locked equal to the old
  --     builder's (same snapshot, as text); `racks` and `budget` added; `slots` = the exact rack-sum of
  --     the typed pre-image (+ the new Refit rows); `slots_locked` = {} (dark) as before.
  select count(*) into v_bad from hulls_after_0132 a
   where (a.new_view - array['racks', 'budget', 'slots', 'slots_locked'])::text
         is distinct from (a.old_view - array['slots', 'slots_locked'])::text
      or not (a.new_view ? 'racks' and a.new_view ? 'budget')
      or (select count(*) from jsonb_object_keys(a.new_view)) <> (select count(*) from jsonb_object_keys(a.old_view)) + 2;
  if v_bad <> 0 then
    raise exception '0132 self-assert FAIL: % hull(s) whose ship_view is not the pre-image plus racks and budget', v_bad;
  end if;
  -- every kind maps to exactly one rack (item_profile), so the rack-sum is well defined
  if exists (select 1 from public.item_kinds k left join public.item_profile ip on ip.item_code = k.code
              group by k.slot having count(distinct ip.rack) <> 1 or bool_or(ip.rack is null)) then
    raise exception '0132 self-assert FAIL: a kind of item has no rack, or more than one';
  end if;
  select count(*) into v_bad
    from hulls_before_0132 b join hulls_after_0132 a on a.ship_id = b.ship_id
   where (select coalesce(jsonb_object_agg(x.rack, x.n), '{}'::jsonb) from (
            select r.rack, sum(r.n)::int as n from (
              select (select distinct ip.rack from public.item_kinds k join public.item_profile ip on ip.item_code = k.code where k.slot = e.key) as rack,
                     e.value::int as n
                from jsonb_each_text(b.view->'slots') e
              union all
              select 'refit', rr.count from racks_0132 rr where rr.class_code = b.class_code and rr.rack = 'refit') r
            group by r.rack) x)
         is distinct from a.new_view->'slots'
      or (b.view->'slots_locked') is distinct from '{}'::jsonb
      or (a.new_view->'slots_locked') is distinct from '{}'::jsonb;
  if v_bad <> 0 then
    raise exception '0132 self-assert FAIL: % hull(s) whose rack slots are not the exact rack-sum of the typed pre-image', v_bad;
  end if;
  -- `racks` agrees with `slots`, the units and the item costs; `budget` with the units
  select count(*) into v_bad from hulls_after_0132 a
   cross join lateral (select a.ship_id as id, a.new_view as v) s
   cross join lateral (select s.v) x
   where (select coalesce(sum((r->>'open')::int), 0) from jsonb_array_elements(x.v->'racks') r)
         <> (select coalesce(sum(value::int), 0) from jsonb_each_text(x.v->'slots'))
      or (select coalesce(sum(jsonb_array_length(r->'fitted')), 0) from jsonb_array_elements(x.v->'racks') r)
         <> (select count(*) from public.fitted_units u where u.ship_id = s.id)
      or (x.v->'budget'->'deck'->>'used')::int <> (select coalesce(sum(ip.deck), 0) from sf_snap_0132 sf
                                                     join public.item_profile ip on ip.item_code = sf.item_code
                                                     cross join lateral generate_series(1, sf.qty) where sf.ship_id = s.id)
      or (x.v->'budget'->'hands'->>'used')::int <> (select coalesce(sum(ip.hands), 0) from sf_snap_0132 sf
                                                      join public.item_profile ip on ip.item_code = sf.item_code
                                                      cross join lateral generate_series(1, sf.qty) where sf.ship_id = s.id);
  if v_bad <> 0 then
    raise exception '0132 self-assert FAIL: % hull(s) whose racks or budget disagree with their slots and units', v_bad;
  end if;
  insert into proven_0132 values ('view', format('%s hulls', v_hulls));

  -- (c) Σ UNITS = Σ QTY, per hull and per item (both directions), and in total — against the snapshot
  --     here; §7 re-syncs any hull that moved since and the last assert repeats this against the table.
  select count(*) into v_bad from (
    select coalesce(a.ship_id, b.ship_id) from
      (select ship_id, item_code, qty from sf_snap_0132) a
      full join (select ship_id, item_code, count(*)::int as qty from public.fitted_units group by 1, 2) b
        on b.ship_id = a.ship_id and b.item_code = a.item_code
     where a.qty is distinct from b.qty) z;
  if v_bad <> 0 or (select count(*) from public.fitted_units) <> (select coalesce(sum(qty), 0) from sf_snap_0132)
     or (select count(*) from public.fitted_units) = 0 then
    raise exception '0132 self-assert FAIL: % (hull, item) pair(s) whose units are not their qty (% units, % qty)',
      v_bad, (select count(*) from public.fitted_units), (select coalesce(sum(qty), 0) from sf_snap_0132);
  end if;
  insert into proven_0132 values ('units', format('%s units on %s hulls = Σ qty of %s rows',
    (select count(*) from public.fitted_units), (select count(distinct ship_id) from public.fitted_units), (select count(*) from sf_snap_0132)));

  -- (d) EVERY MOUNTED ITEM FITS ITS RACK: per hull per rack, units ≤ the rack's open places.
  select count(*), string_agg(distinct x.rack, ',') into v_bad, v_list from (
    select u.ship_id, ip.rack, count(*) as used
      from public.fitted_units u join public.item_profile ip on ip.item_code = u.item_code
     group by 1, 2) x
   where x.used > coalesce((world.ship_slots(x.ship_id)->'open'->>x.rack)::int, 0);
  if v_bad <> 0 then
    raise exception '0132 self-assert FAIL: % (hull, rack) pair(s) carry more than the rack holds (%)', v_bad, v_list;
  end if;
  if exists (select 1 from public.fitted_units u where not exists (select 1 from public.item_profile ip where ip.item_code = u.item_code)) then
    raise exception '0132 self-assert FAIL: a mounted unit''s item has no profile (no rack)';
  end if;

  -- (e) EVERY LOADOUT LEGAL UNDER THE OLD TYPED CAPS FITS THE BUDGETS — enumerated, class by class:
  --     every multiset of items per kind up to its typed cap, crossed over the kinds.
  for h in
    with recursive kinds as (
      select class_code, slot, count, row_number() over (partition by class_code order by slot) as k
        from slots_before_0132),
    items as (
      select ik.slot, ip.deck, ip.hands, row_number() over (partition by ik.slot order by ik.code) as i
        from public.item_kinds ik join public.item_profile ip on ip.item_code = ik.code),
    ms (class_code, slot, n, last_i, deck, hands, cap) as (
      select class_code, slot, 0, 0::bigint, 0, 0, count from kinds
      union all
      select m.class_code, m.slot, m.n + 1, it.i, m.deck + it.deck, m.hands + it.hands, m.cap
        from ms m join items it on it.slot = m.slot and it.i >= m.last_i
       where m.n < m.cap),
    combo (class_code, k, deck, hands) as (
      select distinct class_code, 0::bigint, 0, 0 from kinds
      union all
      select c.class_code, c.k + 1, c.deck + m.deck, c.hands + m.hands
        from combo c
        join kinds kd on kd.class_code = c.class_code and kd.k = c.k + 1
        join ms m on m.class_code = c.class_code and m.slot = kd.slot)
    select c.class_code, count(*) as loadouts, max(c.deck) as max_deck, max(c.hands) as max_hands,
           b.deck as deck, b.hands as hands,
           count(*) filter (where c.deck > b.deck or c.hands > b.hands) as over
      from combo c
     cross join lateral public.class_budget(c.class_code) b
     where c.k = (select max(k) from kinds where kinds.class_code = c.class_code)
     group by c.class_code, b.deck, b.hands
     order by c.class_code
  loop
    if h.over <> 0 then
      raise exception '0132 self-assert FAIL: % of % loadouts legal under the typed caps overdraw the % budgets (max % / % deck, % / % hands)',
        h.over, h.loadouts, h.class_code, h.max_deck, h.deck, h.max_hands, h.hands;
    end if;
    v_enum := v_enum || format('%s %s loadouts, worst %s / %s deck, %s / %s hands; ', h.class_code, h.loadouts, h.max_deck, h.deck, h.max_hands, h.hands);
  end loop;
  if v_enum not like '%barca %' or v_enum not like '%carlat %' or v_enum not like '%nau %' then
    raise exception '0132 self-assert FAIL: the enumeration did not cover barca, carlat and nau (%)', v_enum;
  end if;
  insert into proven_0132 values ('enum', v_enum);

  -- (f) OVER-BUDGET HULLS, counted (expect 0): every hull afloat, through the one reading.
  select count(*) into v_bad from public.ships s cross join lateral (select world.ship_budget(s.id) as b) x
   where (x.b->'deck'->>'used')::int > (x.b->'deck'->>'max')::int
      or (x.b->'hands'->>'used')::int > (x.b->'hands'->>'max')::int;
  if v_bad <> 0 then
    raise exception '0132 self-assert FAIL: % hull(s) carry more than their Deck or Hands', v_bad;
  end if;
  insert into proven_0132 values ('over', '0');

  -- (g) ONLY mount_fitting AND unmount_fitting WRITE fitted_units — every live body in the game's
  --     schemas scanned; POSITIVE CONTROL: a planted writer (rolled back) is seen by the same scan.
  create or replace function pg_temp.fitted_writers_0132()
  returns text[]
  language sql
  stable
  as $f$
    -- ordered by the entry ITSELF (an `order by 1` inside an aggregate orders by the constant 1)
    select coalesce(array_agg(w.entry order by w.entry), '{}')
      from (select n.nspname || '.' || p.proname || ':' ||
                   case when p.prosrc ~* 'insert\s+into\s+public\.fitted_units' then 'insert' else '' end ||
                   case when p.prosrc ~* 'delete\s+from\s+public\.fitted_units' then 'delete' else '' end ||
                   case when p.prosrc ~* 'update\s+public\.fitted_units' then 'update' else '' end as entry
              from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg\_%'
               and p.prosrc ~* '(insert\s+into|delete\s+from|update|truncate)\s+(table\s+)?public\.fitted_units') w
  $f$;
  v_writers := pg_temp.fitted_writers_0132();
  if v_writers is distinct from array['public.mount_fitting:insert', 'public.unmount_fitting:delete'] then
    raise exception '0132 self-assert FAIL: the live writers of fitted_units are %, not mount_fitting (insert) and unmount_fitting (delete)', v_writers;
  end if;
  begin
    execute $planted$create function public.zz_planted_writer_0132() returns void language sql as
      'delete from public.fitted_units where false'$planted$;
    if cardinality(pg_temp.fitted_writers_0132()) <> 3 then
      raise exception '0132 self-assert FAIL: the writer scan did not see a planted writer — it proves nothing';
    end if;
    raise exception 'CONTROL_ROLLBACK_0132';
  exception when others then
    if sqlerrm <> 'CONTROL_ROLLBACK_0132' then raise; end if;
  end;
  if exists (select 1 from pg_proc where proname = 'zz_planted_writer_0132') then
    raise exception '0132 self-assert FAIL: the planted writer was not rolled back';
  end if;
  -- no live body reads or writes ship_fittings any more (positive control: the five pre-images did)
  select count(*) into v_readers from defs_before_0132
   where def ~* '(from|join|into|update)\s+public\.ship_fittings\M';
  if v_readers <> 5 then
    raise exception '0132 self-assert FAIL: the reader scan''s positive control — % pre-image(s) named ship_fittings, expected 5', v_readers;
  end if;
  select count(*), string_agg(n.nspname || '.' || p.proname, ', ') into v_bad, v_list
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg\_%'
     and p.prosrc ~* '(from|join|into|update)\s+public\.ship_fittings\M';
  if v_bad <> 0 then
    raise exception '0132 self-assert FAIL: live bodies still name ship_fittings as a table: %', v_list;
  end if;
  -- the cores tell no merchant from a player; the doors take the lock BEFORE they read the store / units
  if strpos(pg_get_functiondef('public.mount_fitting(uuid, text)'::regprocedure), 'is_npc') > 0
     or strpos(pg_get_functiondef('public.unmount_fitting(uuid, text)'::regprocedure), 'is_npc') > 0
     or strpos(pg_get_functiondef('world.ship_budget(uuid)'::regprocedure), 'is_npc') > 0
     or strpos(pg_get_functiondef('world.ship_racks(uuid, jsonb)'::regprocedure), 'is_npc') > 0 then
    raise exception '0132 self-assert FAIL: a fitting core or the budget reads is_npc';
  end if;
  v_def := pg_get_functiondef('cmd.do_fit(uuid, jsonb)'::regprocedure);
  if strpos(v_def, 'public.fitting_lock(f.player_id)') = 0
     or strpos(v_def, 'public.fitting_lock(f.player_id)') > strpos(v_def, 'from public.player_items')
     or strpos(v_def, 'get diagnostics v_rows = row_count') = 0 then
    raise exception '0132 self-assert FAIL: cmd.do_fit does not take the house lock before reading the store, or does not count its debit';
  end if;
  v_def := pg_get_functiondef('cmd.do_unfit(uuid, jsonb)'::regprocedure);
  if strpos(v_def, 'public.fitting_lock(f.player_id)') = 0
     or strpos(v_def, 'public.fitting_lock(f.player_id)') > strpos(v_def, 'public.fitted_units') then
    raise exception '0132 self-assert FAIL: cmd.do_unfit does not take the house lock before reading the units';
  end if;
  v_def := pg_get_functiondef('public.unmount_fitting(uuid, text)'::regprocedure);
  if strpos(v_def, 'get diagnostics v_n = row_count') = 0
     or strpos(v_def, 'public.fitting_lock(') > strpos(v_def, 'from public.fitted_units') then
    raise exception '0132 self-assert FAIL: unmount_fitting does not lock first or does not count its delete';
  end if;

  -- (h) MERCHANT HULLS' UNITS = THEIR 0126 LOADOUT: her fleet's pattern (md5(fleet) mod count), item by item.
  select count(*), count(*) filter (where
           (select coalesce(jsonb_object_agg(x.item_code, x.n), '{}'::jsonb)
              from (select u.item_code, count(*)::int as n from public.fitted_units u where u.ship_id = s.id group by 1) x)
           is distinct from
           (select coalesce(jsonb_object_agg(l.item_code, l.qty), '{}'::jsonb) from public.npc_loadouts l
             where l.class_code = c.code
               and l.pattern = mod(mod(('x' || left(md5(s.fleet_id::text), 8))::bit(32)::int,
                                       (select count(distinct pattern) from public.npc_loadouts where class_code = c.code)::int)
                                   + (select count(distinct pattern) from public.npc_loadouts where class_code = c.code)::int,
                                   (select count(distinct pattern) from public.npc_loadouts where class_code = c.code)::int)))
    into v_n, v_bad
    from public.ships s join public.ship_classes c on c.id = s.class_id join public.players p on p.id = s.player_id
   where p.is_npc;
  if v_n = 0 or v_bad <> 0 then
    raise exception '0132 self-assert FAIL: % of % merchant hull(s) do not carry exactly their 0126 loadout as units', v_bad, v_n;
  end if;
  insert into proven_0132 values ('merchants', v_n::text);

  -- (i) THE RE-CUTS: each new body reverses to its pre-image hunk by hunk; ACLs unmoved; ship_slots
  --     untouched; the catalogue (item_kinds, item_effects, ship_classes, class_profile) untouched.
  for d in select * from defs_before_0132 loop
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0132 where fn = d.fn order by n desc loop
      if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
        raise exception '0132 self-assert FAIL: hunk % of % is not in the new body exactly once', h.n, d.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> d.def then
      raise exception '0132 self-assert FAIL: % does not reverse to its pre-image — something beyond the hunks moved', d.fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = d.fn::regprocedure), '') <> d.acl then
      raise exception '0132 self-assert FAIL: the ACL of % moved', d.fn;
    end if;
  end loop;
  if replace(pg_get_functiondef('world.ship_slots(uuid)'::regprocedure), E'\r', '') <> (select def from slots_fn_before_0132)
     or coalesce((select p.proacl::text from pg_proc p where p.oid = 'world.ship_slots(uuid)'::regprocedure), '') <> (select acl from slots_fn_before_0132) then
    raise exception '0132 self-assert FAIL: world.ship_slots moved — it was to answer by rack with its body untouched';
  end if;
  if (select md5(string_agg(to_jsonb(k)::text, '|' order by k.code)) from public.item_kinds k) <> (select kinds_hash from before_0132)
     or (select md5(string_agg(to_jsonb(e)::text, '|' order by e.item_code, e.stat)) from public.item_effects e) <> (select effects_hash from before_0132)
     or (select md5(string_agg(to_jsonb(c)::text, '|' order by c.code)) from public.ship_classes c) <> (select classes_hash from before_0132)
     or (select md5(string_agg(to_jsonb(p)::text, '|' order by p.class_code)) from public.class_profile p) <> (select profile_hash from before_0132) then
    raise exception '0132 self-assert FAIL: item_kinds, item_effects, ship_classes or class_profile moved';
  end if;
  -- the catalogue: every item profiled once; the rack rows are the data; the unlocks converted
  if (select count(*) from public.item_profile) <> (select count(*) from public.item_kinds)
     or exists (select 1 from public.item_profile ip where not exists (select 1 from public.item_kinds k where k.code = ip.item_code))
     or exists (select 1 from public.fitted_units u where not exists (select 1 from public.item_kinds k where k.code = u.item_code))
     or (select count(*) from public.gear_racks) <> 5 then
    raise exception '0132 self-assert FAIL: % item profile(s) for % item(s), % rack(s)',
      (select count(*) from public.item_profile), (select count(*) from public.item_kinds), (select count(*) from public.gear_racks);
  end if;
  if exists (select class_code, slot, count from public.class_slots except select class_code, rack, count from racks_0132)
     or exists (select class_code, rack, count from racks_0132 except select class_code, slot, count from public.class_slots) then
    raise exception '0132 self-assert FAIL: class_slots is not the rack rows';
  end if;
  if (select string_agg(class_code || ':' || slot || ':' || count || '@' || min_level, ',' order by class_code) from public.class_slot_unlocks)
     is distinct from 'barca:mid:1@3,carlat:low:1@4,nau:high:1@6'
     or (select count(*) from public.class_slot_unlocks) <> (select count(*) from unlocks_before_0132) then
    raise exception '0132 self-assert FAIL: the unlocks were not converted kind → rack';
  end if;

  -- (j) THE WALL: no new entry point; the new tables and functions server-only; no client write.
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0132)
     or exists (select 1 from public.client_rpc_entry_points() e
                 where e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute'))
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0132 self-assert FAIL: the registry, the grant wall or the read wall moved';
  end if;
  if exists (select 1 from unnest(array['public.fitting_lock(uuid)', 'public.class_budget(text)', 'world.ship_budget(uuid)', 'world.ship_racks(uuid, jsonb)',
                                        'public.unmount_fitting(uuid, text)', 'public.mount_fitting(uuid, text)']) f(fn),
                           unnest(array['anon', 'authenticated']) r(role)
              where has_function_privilege(r.role, f.fn, 'execute'))
     or exists (select 1 from unnest(array['public.gear_racks', 'public.item_profile', 'public.fitted_units']) t(tbl),
                              unnest(array['anon', 'authenticated']) r(role)
                 where has_table_privilege(r.role, t.tbl, 'select,insert,update,delete')) then
    raise exception '0132 self-assert FAIL: a client role can reach a fitting core, the budget or a new table';
  end if;

  -- (k) THE PROBE HOUSE (rolled back): racks take any item of their rack; Mid full refused in its
  --     words taking nothing; Hands and Deck bind on FIT with their figures; UNFIT returns to the store
  --     once, a second is refused; a merchant's loadout mounts through the same core, inside budgets.
  if (v_p->>'barca_units')::int <> 3 or v_p->>'store_sails' <> '4' or v_p->>'store_guns' is distinct from '2'
     or v_p->'barca_budget' is distinct from '{"deck": {"max": 12, "used": 12}, "hands": {"max": 16, "used": 16}}'::jsonb
     or (select jsonb_array_length(r->'fitted') from jsonb_array_elements(v_p->'barca_racks') r where r->>'rack' = 'mid') <> 2
     or (select r->>'word' from jsonb_array_elements(v_p->'barca_racks') r where r->>'rack' = 'mid') <> 'Mid' then
    raise exception '0132 self-assert FAIL: the barca did not take two suits of sails in Mid and guns in High from the store: %', v_p;
  end if;
  if v_p->>'mid_full' is distinct from 'E_SLOTS_FULL: Gaivota has no free Mid slot (2 / 2 used)'
     or v_p->>'store_sails_after_refusal' <> '4' then
    raise exception '0132 self-assert FAIL: a third Mid piece was not refused in its words, or took from the store: %', v_p;
  end if;
  if v_p->>'hands_refusal' is distinct from 'E_OVER_HANDS: Fitting Suit of Sails takes 4 hands; Prova Carlat has 0 / 24 hands left'
     or (v_p->>'hands_figures')::jsonb is distinct from '{"have": 0, "need": 4, "unit": "hands"}'::jsonb
     or v_p->'carlat_budget' is distinct from '{"deck": {"max": 22, "used": 18}, "hands": {"max": 24, "used": 24}}'::jsonb
     or v_p->>'store_sails_after_hands' <> '2' then
    raise exception '0132 self-assert FAIL: Hands did not bind on the carlat with its figures: %', v_p;
  end if;
  if v_p->>'deck_refusal' is distinct from 'E_OVER_DECK: Fitting Anchor & Cable takes 3 deck; Prova Carlat has 2 / 20 deck left'
     or (v_p->>'deck_figures')::jsonb is distinct from '{"have": 2, "need": 3, "unit": "deck"}'::jsonb
     or v_p->>'store_anchor' is distinct from '1' then
    raise exception '0132 self-assert FAIL: Deck did not bind with its figures: %', v_p;
  end if;
  if (v_p->>'after_unfit_units')::int <> 1 or (v_p->>'after_unfit_store')::int <> 3
     or v_p->>'unfit_twice' is distinct from 'E_NOT_FITTED: Gaivota carries no Suit of Sails'
     or (v_p->>'after_unfit_twice_store')::int <> 4 or (v_p->>'after_unfit_twice_units')::int <> 0
     or v_p->>'core_unfit_none' is distinct from 'E_NOT_FITTED: Gaivota carries no Suit of Sails' then
    raise exception '0132 self-assert FAIL: UNFIT did not return one piece per unit, or a second UNFIT paid the store: %', v_p;
  end if;
  if (v_p->>'npc_fit')::int < 2 or v_p->'npc_units' is distinct from v_p->'npc_pattern' or (v_p->>'npc_again')::int <> 0 then
    raise exception '0132 self-assert FAIL: a merchant loadout did not mount its pattern through the core: %', v_p;
  end if;
  if exists (select 1 from public.players where auth_uid = '00000000-0132-4000-8000-000000000001')
     or (select deck from public.class_profile where class_code = 'carlat') <> 22 then
    raise exception '0132 self-assert FAIL: the probe world was not rolled back';
  end if;
end $$;

-- ── 7. LAST: THE SWAP — one short retried step, locks in the fixed order of the header ──────────
create temp table swap_0132 (what text, n bigint, ms numeric, at timestamptz) on commit drop;
select set_config('lock_timeout', '2s', true);   -- step 1 queues player ship reads behind it: keep the wait short
insert into swap_0132 (what, ms, at)
select 'swap', pg_temp.locked_0132($swap$
  -- 1. the one hot lock
  lock table public.ship_fittings in access exclusive mode;
  -- 2. the hulls whose fittings moved since the §5 snapshot (a FIT / UNFIT during §5-§6): rebuilt
  create temp table moved_0132 on commit drop as
  select distinct coalesce(a.ship_id, b.ship_id) as ship_id
    from public.ship_fittings a
    full join sf_snap_0132 b on b.ship_id = a.ship_id and b.item_code = a.item_code
   where a.qty is distinct from b.qty;
  delete from public.fitted_units u using moved_0132 m where u.ship_id = m.ship_id;
  insert into public.fitted_units (ship_id, item_code)
  select sf.ship_id, sf.item_code
    from public.ship_fittings sf join moved_0132 m on m.ship_id = sf.ship_id
   cross join lateral generate_series(1, sf.qty);
  -- 3. the table retired (renamed — dropping it would take ACCESS EXCLUSIVE on ships), the view in its place
  alter table public.ship_fittings rename to ship_fittings_retired_0132;
  revoke all on table public.ship_fittings_retired_0132 from public, anon, authenticated;
  comment on table public.ship_fittings_retired_0132 is
    '0132: RETIRED — the stacked fittings table of 0074, frozen at the swap. Read and written by nothing '
    '(public.fitted_units is the one home of a mounted unit). Dropped in the next gear step, with the clock unwound.';
  create view public.ship_fittings with (security_invoker = true) as
    select u.ship_id, u.item_code, count(*)::int as qty
      from public.fitted_units u
     group by u.ship_id, u.item_code;
  comment on view public.ship_fittings is
    '0132: READ-ONLY, FOR ONE RELEASE — what a hull carries, stacked by qty, over public.fitted_units (one '
    'row per unit). Not updatable (GROUP BY): writes go through public.mount_fitting / unmount_fitting. '
    'security_invoker: it reads as its caller (no client role holds a grant on it or on fitted_units). '
    'No live body reads it; it is dropped in the next gear step.';
  revoke all on table public.ship_fittings from public, anon, authenticated;
  -- 4. the catalogue FKs (SHARE ROW EXCLUSIVE on item_kinds, then gear_racks)
  alter table public.item_profile add constraint item_profile_item_code_fkey
    foreign key (item_code) references public.item_kinds(code);
  alter table public.fitted_units add constraint fitted_units_item_code_fkey
    foreign key (item_code) references public.item_kinds(code);
  alter table public.class_slots add constraint class_slots_rack_fkey
    foreign key (slot) references public.gear_racks(code);
  alter table public.class_slot_unlocks add constraint class_slot_unlocks_rack_fkey
    foreign key (slot) references public.gear_racks(code);
$swap$, 'the swap (LOCK ship_fittings, re-sync, rename, the view, four FKs)'), clock_timestamp();

-- ── SELF-ASSERT (light: catalogue reads and one refused insert) ────────────────────────────────
do $$
declare
  v_err   text;
  v_state text;
  r       record;
  v_p     jsonb := (select j from probe_0132);
  v_notes text := '';
begin
  -- the view: a view, the units grouped, server-only, and NOT writable (positive control on each verb)
  if (select relkind from pg_class where oid = 'public.ship_fittings'::regclass) <> 'v' then
    raise exception '0132 self-assert FAIL: public.ship_fittings is not a view';
  end if;
  if (select coalesce(sum(qty), 0) from public.ship_fittings) <> (select count(*) from public.fitted_units)
     or (select count(*) from public.ship_fittings) <> (select count(*) from (select distinct ship_id, item_code from public.fitted_units) x) then
    raise exception '0132 self-assert FAIL: the view does not stack the units';
  end if;
  -- Σ UNITS = Σ QTY once more, now against the table as it stood at the swap (after the re-sync)
  if exists (select 1 from public.ship_fittings_retired_0132 a
               full join public.ship_fittings b on b.ship_id = a.ship_id and b.item_code = a.item_code
              where a.qty is distinct from b.qty)
     or (select relkind from pg_class where oid = 'public.ship_fittings_retired_0132'::regclass) <> 'r' then
    raise exception '0132 self-assert FAIL: after the swap the units are not the retired table''s fittings';
  end if;
  if not coalesce((select 'security_invoker=true' = any(reloptions) from pg_class where oid = 'public.ship_fittings'::regclass), false)
     or has_table_privilege('authenticated', 'public.ship_fittings_retired_0132', 'select,insert,update,delete')
     or has_table_privilege('anon', 'public.ship_fittings_retired_0132', 'select,insert,update,delete') then
    raise exception '0132 self-assert FAIL: the view is not security_invoker, or a client role can reach the retired table';
  end if;
  foreach v_err in array array[
    'insert into public.ship_fittings (ship_id, item_code, qty) values (gen_random_uuid(), ''figurehead'', 1)',
    'update public.ship_fittings set qty = qty + 1',
    'delete from public.ship_fittings'] loop
    v_state := null;
    begin
      execute v_err;
    exception when others then
      v_state := sqlstate;
    end;
    if v_state is null then
      raise exception '0132 self-assert FAIL: the view took a write (%)', v_err;
    end if;
  end loop;
  if has_table_privilege('authenticated', 'public.ship_fittings', 'select,insert,update,delete')
     or has_table_privilege('anon', 'public.ship_fittings', 'select,insert,update,delete') then
    raise exception '0132 self-assert FAIL: a client role can reach the ship_fittings view';
  end if;
  -- the catalogue FKs are in place; and NO FK reaches public.ships from the new table (see LOCKS)
  if (select count(*) from pg_constraint
       where conname in ('item_profile_item_code_fkey', 'fitted_units_item_code_fkey', 'class_slots_rack_fkey', 'class_slot_unlocks_rack_fkey')
         and contype = 'f') <> 4
     or exists (select 1 from pg_constraint where conrelid = 'public.fitted_units'::regclass and confrelid = 'public.ships'::regclass) then
    raise exception '0132 self-assert FAIL: the foreign keys are not as the header says';
  end if;

  for r in select b.what, b.ms as before_ms, a.ms as after_ms, b.hulls
             from reads_0132 b join reads_0132 a on a.what = b.what and a.phase = 'after'
            where b.phase = 'before' order by b.what desc loop
    v_notes := v_notes || format('%s over %s merchant hull(s) %s ms → %s ms; ', r.what, r.hulls, r.before_ms, r.after_ms);
  end loop;

  raise notice '0132 self-assert ok: A SHIP CARRIES WHAT ITS DECK CAN BEAR. STATS: % — every hull''s ten stats over units = the pre-image to the digit (old computation vs new, same snapshot, as text). VIEW: % — ship_view = the pre-image plus `racks` and `budget` on every key, `slots` the exact rack-sum of the typed pre-image (+ Refit), `slots_locked` {} as before, racks/budget agree with slots and units. UNITS: %. RACKS: every mounted item fits its rack. ENUMERATED (every loadout legal under the typed caps): %all within budget. OVER-BUDGET HULLS: %. WRITERS: only mount_fitting (insert) and unmount_fitting (delete) write fitted_units (planted writer seen by the same scan, rolled back); no live body names ship_fittings (5 pre-images did); doors lock the house before reading, debits counted. MERCHANTS: % hull(s) carry exactly their 0126 loadout as units. Six bodies reverse to their pre-images, ACLs unmoved; ship_slots untouched; item_kinds / item_effects / ship_classes / class_profile unmoved; 12 profiles, 5 racks, rack rows = data, unlocks converted; no new entry point, the new tables and cores server-only. PROBE (own house, rolled back): two suits of sails in a barca''s Mid + guns in High (budget 12/12 deck, 16/16 hands); a third Mid piece: %; carlat: %; carlat at deck 20: %; UNFIT returns one per unit, a second: %; a merchant loadout mounts its pattern through the core (% units). VIEW ship_fittings: read-only (insert/update/delete refused), security_invoker, stacks the units, server-only; the old table retired by rename (no lock on ships), Σ units = its Σ qty after % hull(s) re-synced; item / rack FKs in place. READS: %LOCKS: nothing anyone waits on before §7; the swap step % ms; held % ms from the swap to the end of the file.',
    (select v from proven_0132 where k = 'stats'), (select v from proven_0132 where k = 'view'),
    (select v from proven_0132 where k = 'units'), (select v from proven_0132 where k = 'enum'),
    (select v from proven_0132 where k = 'over'), (select v from proven_0132 where k = 'merchants'),
    v_p->>'mid_full', v_p->>'hands_refusal', v_p->>'deck_refusal', v_p->>'unfit_twice', v_p->>'npc_fit',
    (select count(*) from moved_0132), v_notes, (select ms from swap_0132 where what = 'swap'),
    round(extract(epoch from clock_timestamp() - (select at from swap_0132 where what = 'swap')) * 1000, 1);
end $$;
