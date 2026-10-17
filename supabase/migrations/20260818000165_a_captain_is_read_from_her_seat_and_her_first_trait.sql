-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0165 — A CAPTAIN IS READ FROM HER SEAT AND HER FIRST TRAIT  (K9 "retire")
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW ─────────────────────────────────────────────────────────────────────────────────────
-- docs/SKILLS_AND_CAPTAINS.md §2, §6.2 and §8 row K9. K5–K8 gave every concept of a captain its one home:
-- where she sits is public.captain_seats (K5), her experience is public.captain_xp (K6), her job and its value
-- are her first trait, public.captain_traits ord 1 (K4, mirrored since). What they replaced is still in the
-- schema — player_officers.fleet_id (written, read by nothing), public.officer_xp (empty; its aboard clock read
-- by one writer), cmd.post_officer (a door no screen opens), officers.specialty / bonus_pct (mirrors). Two
-- copies of one fact are one drift away from two answers, so they go.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
--   THE ONE READING OF HER JOB   public.captain_job (view, server-only): officer → job (ord 1's trait) and
--       job_pct (ord 1's value at officers.bonus_pct's scale, numeric(5,2), so every answer prints as before).
--   THE RE-CUTS (hunks sliced from the bodies LIVE at 0164, unchanged since 0163, LF, each occurring once and reversing, ACLs
--       unchanged): world.inn, world.inn_chance (the scarcity), world.officers, world.npc_fleet_card,
--       world.ship_seats, public.crew_terms (dark arm), public.promotion_next, public.captain_seat_pick read
--       public.captain_job; public.sign_officer stops writing fleet_id and reads her job there;
--       public.captain_xp_credit stops reading officer_xp (below); public.client_rpc_entry_points −1.
--   public.captain_seat_put loses p_came_aboard (it only set officer_xp.aboard_since): dropped and re-made
--       (uuid, uuid, int), ACL asserted equal; its two callers already call it with three arguments (one hunk
--       in sign_officer).
--   THE ABOARD CLOCK. 0127: a voyage teaches only the captains aboard when she departed. Since 0157 that is the
--       seat's own rule — a captain is seated, moved or hired into a fleet ONLY while it is docked (D9), and no
--       body moves a ship between fleets — so every captain seated in a sailing fleet was seated before she
--       sailed. officer_xp.aboard_since added nothing (and holds no row on production); the credit keeps
--       "signed by then". Asserted on the live voyages: old filter = new filter for every seated captain.
--   DROPPED  cmd.post_officer, public.post_officer_to; and LAST (§7): player_officers.fleet_id (+ its index and
--       FK), public.officer_xp, officers.specialty and officers.bonus_pct (+ their FK and CHECK).
--   ALSO (found by the K8 / S16 agents):
--     * public.item_use: K8's three promotion items had no row (0158: one per item). They are spent by
--       cmd.promote_captain and never fitted: trigger null (never wears), consumes [] — from data/captains.json
--       promotion_items through the world guard.
--     * ALBUQUERQ and GARCIAORTA were homed at GOA, which is GENOA; they are of Goa — OLD (Old Goa). Their home
--       (homesickness K6, the inn's region weight) and their languages (the generator: home first) are fixed
--       here (data/officers.json, data/captains.generated.json).
--
-- ── THE PROOF ───────────────────────────────────────────────────────────────────────────────────
-- (a) the mirror holds for every officer (ord 1 = specialty at bonus_pct, scale and all) before anything moves.
-- (b) OLD = NEW, at the same instant (the old bodies kept under pg_temp names): world.inn at every inn,
--     world.inn_chance for every captain × harbour, world.officers for every company with a sign-in and for
--     nobody, world.npc_fleet_card for every fleet (the same card, or the same refusal), world.ship_seats for every ship, crew_terms (dark)
--     for every fleet, promotion_next and captain_seat_pick for every signing.
-- (c) the aboard clock: for every captain seated in a fleet now at sea, old filter = new; no officer_xp
--     experience is left behind (K6 moved it).
-- (d) THE PROBE (own house, rolled back): hired into her docked fleet she is seated, fleet_id is not written
--     and no officer_xp row; the answer names her job at its old value; ashore and seated again; credited once
--     signed before the departure, not before.
-- (e) the re-cuts reverse; seat_put's ACL = the old; entry points −1; item_use one row per item (the three
--     promotion codes counted by name); the two captains read Old Goa and its region.
-- (f) AFTER the drops: no function body names a dropped object (comments and string literals stripped; a
--     player_officers alias read for fleet_id), the columns and table are gone, the readers run.
--
-- ── LOCKS (db push holds every lock until this file commits) ───────────────────────────────────
-- Until §7 nothing a live statement waits on: ACCESS SHARE on what it reads; CREATE OR REPLACE / DROP FUNCTION
-- (no table lock); a view over captain_traits (ACCESS SHARE); ROW EXCLUSIVE on item_use, officers (two rows,
-- non-key columns) and captain_languages (two captains). Every probe write is in a rolled-back subtransaction.
-- §7, LAST, ONE retried step, every lock NOWAIT, fixed order (0133 §7: a parent before the table whose FK
-- triggers live on it) — measured on Postgres: dropping player_officers.fleet_id takes ACCESS EXCLUSIVE on
-- fleets (its FK) and player_officers; dropping officers.specialty takes ACCESS EXCLUSIVE on traits (its FK)
-- and officers:
--     1. fleets  2. player_officers  3. officer_xp  4. traits  5. officers  → the three drops.
-- NOWAIT: this file never WAITS holding a lock, so it is never in a cycle; a busy table is 55P03 at once, the
-- step's subtransaction rolls back what it took, sleeps 0.2 s, retries (25 tries), then fails as LOCK
-- CONTENTION, not a result. After it: catalogue reads and five reader calls (ms); the held time is printed.
-- Push with the clock unwound (DEPLOY_RUNBOOK §2): fewer readers on fleets, so the step gets its gap.
--
-- ROLLBACK: a forward slice — re-add officers.specialty / bonus_pct filled from public.captain_job, the empty
-- officer_xp, player_officers.fleet_id filled from the seats; restore the bodies from the hunks' OLD text. The
-- two captains' home and item_use rows are corrections and are not reverted.
-- VERSION: 0165. Applies on prod head 0164 (0164, the arrivals fix, touches none of these bodies — checked on prod).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  perform set_config('random_page_cost', '1.1', true);
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0165(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- Run a statement that takes a lock; a lock the live world holds (55P03, 40P01) is not an answer: retry, then
-- fail as LOCK CONTENTION. Returns the milliseconds it took.
create or replace function pg_temp.locked_0165(p_sql text, p_what text)
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
    if v_try >= 25 then
      raise exception '0165 self-assert FAIL: LOCK CONTENTION, not a result — % could not get its locks in 25 tries (%: %). Re-run the push.',
        p_what, v_state, v_msg;
    end if;
    perform pg_sleep(0.2);
  end loop;
end $$;

-- A body with its comments and string literals blanked: what is left names objects, never a key or a sentence.
create or replace function pg_temp.code_0165(p_src text)
returns text
language sql
immutable
as $$ select regexp_replace(regexp_replace(p_src, '--[^\n]*', '', 'g'), '''(?:[^'']|'''')*''', '''''', 'g') $$;

-- An answer with one array re-sorted by (specialty, name, the element): OLD's order among captains who share job
-- and name was the plan's choice (two PURSERs are both "Virji Vora"), so OLD and NEW are compared in one order.
create or replace function pg_temp.canon_0165(p jsonb, p_key text)
returns jsonb
language sql
immutable
as $$
  select case when jsonb_typeof(p -> p_key) = 'array'
              then jsonb_set(p, array[p_key], (select coalesce(jsonb_agg(e order by e ->> 'specialty', e ->> 'name', e::text), '[]'::jsonb)
                                                 from jsonb_array_elements(p -> p_key) e))
              else p end
$$;

-- ── 1. THE PRE-IMAGES ─────────────────────────────────────────────────────────────────────────
-- (a) the mirror, before anything moves
do $$
begin
  if exists (select 1 from public.officers o
               left join public.captain_traits ct on ct.officer_id = o.id and ct.ord = 1
              where ct.trait is distinct from o.specialty
                 or ct.base_pct is distinct from o.bonus_pct
                 or ct.base_pct::numeric(5,2)::text is distinct from o.bonus_pct::text) then
    raise exception '0165 self-assert FAIL: officers.specialty / bonus_pct are not ord 1 of her kit for every captain — the mirror K4 asserted is broken, so nothing can be retired onto it';
  end if;
end $$;

create temp table defs_before_0165 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('world.inn(uuid)'), ('world.inn_chance(uuid, uuid)'), ('world.officers()'),
               ('world.npc_fleet_card(uuid)'), ('world.ship_seats(uuid)'),
               ('public.crew_terms(uuid, timestamp with time zone)'), ('public.promotion_next(uuid)'),
               ('public.captain_seat_pick(uuid, uuid, uuid)'), ('public.sign_officer(uuid, text, uuid)'),
               ('public.captain_xp_credit(uuid, numeric, numeric, numeric, timestamp with time zone)'),
               ('public.client_rpc_entry_points()')) f(fn);

create temp table seat_put_before_0165 on commit drop as
select coalesce(p.proacl::text, '') as acl, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg, p.provolatile as vol
  from pg_proc p where p.oid = 'public.captain_seat_put(uuid, uuid, integer, boolean)'::regprocedure;

create temp table hunks_0165 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0165 (fn, n, old, new) values
  -- world.inn: her job and its value, and the room's order, from public.captain_job
  ('world.inn(uuid)', 1, $o$        'code', o.code, 'name', o.name, 'specialty', o.specialty,
        'bonus_pct', o.bonus_pct, 'wage', public.captain_wage(v_player, o.id), 'blurb', o.blurb,$o$,
   $n$        -- 0165 (K9): her job and its value are her first trait's (public.captain_job)
        'code', o.code, 'name', o.name, 'specialty', j.job,
        'bonus_pct', j.job_pct, 'wage', public.captain_wage(v_player, o.id), 'blurb', o.blurb,$n$),
  ('world.inn(uuid)', 2, $o$        order by o.specialty, o.name), '[]'::jsonb)
      from public.officers o
$o$, $n$        -- 0165: ties broken by her code — two captains share job and name (MUGPURSER, NPCPURSERMUG: Virji Vora)
        order by j.job, o.name, o.code), '[]'::jsonb)
      from public.officers o
      join public.captain_job j on j.officer_id = o.id
$n$),
  -- world.inn_chance: the scarcity of her job's value
  ('world.inn_chance(uuid, uuid)', 1, $o$  select world.officer_scarcity(o.bonus_pct) *$o$,
   $n$  select world.officer_scarcity(j.job_pct) *   -- 0165 (K9): her job's value (public.captain_job)$n$),
  ('world.inn_chance(uuid, uuid)', 2, $o$    from public.officers o
    join public.ports p on p.id = p_port
$o$, $n$    from public.officers o
    join public.captain_job j on j.officer_id = o.id
    join public.ports p on p.id = p_port
$n$),
  -- world.officers
  ('world.officers()', 1, $o$               'code', o.code, 'name', o.name, 'specialty', o.specialty,
               'bonus_pct', o.bonus_pct, 'wage', public.captain_wage(v_player, o.id), 'blurb', o.blurb,$o$,
   $n$               -- 0165 (K9): her job and its value are her first trait's (public.captain_job)
               'code', o.code, 'name', o.name, 'specialty', j.job,
               'bonus_pct', j.job_pct, 'wage', public.captain_wage(v_player, o.id), 'blurb', o.blurb,$n$),
  ('world.officers()', 2, $o$               'takes_effect', (o.specialty = any(v_read)),$o$,
   $n$               'takes_effect', (j.job = any(v_read)),$n$),
  ('world.officers()', 3, $o$                          (select jt.focus from public.traits jt where jt.code = o.specialty)) end
             ) order by o.specialty, o.code), '[]'::jsonb)
        from public.officers o
$o$, $n$                          (select jt.focus from public.traits jt where jt.code = j.job)) end
             ) order by j.job, o.code), '[]'::jsonb)
        from public.officers o
        join public.captain_job j on j.officer_id = o.id
$n$),
  -- world.npc_fleet_card
  ('world.npc_fleet_card(uuid)', 1, $o$                   'name', o.name, 'specialty', o.specialty, 'bonus_pct', o.bonus_pct,$o$,
   $n$                   'name', o.name, 'specialty', j.job, 'bonus_pct', j.job_pct,   -- 0165 (K9): public.captain_job$n$),
  ('world.npc_fleet_card(uuid)', 2, $o$                   order by o.specialty, o.name), '[]'::jsonb)
                   from public.player_officers po join public.officers o on o.id = po.officer_id
$o$, $n$                   order by j.job, o.name, o.code), '[]'::jsonb)   -- 0165: ties broken by her code
                   from public.player_officers po join public.officers o on o.id = po.officer_id
                   join public.captain_job j on j.officer_id = o.id
$n$),
  -- world.ship_seats
  ('world.ship_seats(uuid)', 1, $o$    left join public.traits t on t.code = o.specialty
$o$, $n$    left join public.captain_job j on j.officer_id = o.id   -- 0165 (K9): her job, her first trait
    left join public.traits t on t.code = j.job
$n$),
  -- public.crew_terms, the dark arm
  ('public.crew_terms(uuid, timestamp with time zone)', 1, $o$-- DARK (crew_bite off): each seated captain's JOB (officers.specialty), at her value × her level,$o$,
   $n$-- DARK (crew_bite off): each seated captain's JOB (her first trait, public.captain_job), at her value × her level,$n$),
  ('public.crew_terms(uuid, timestamp with time zone)', 2, $o$      select po.id, po.officer_id, cs.ship_id, cs.seat, o.specialty, te.effect,
             o.bonus_pct * public.captain_level_mult(po.id, jt.focus)
        from public.ships s
        join public.captain_seats cs on cs.ship_id = s.id
        join public.player_officers po on po.id = cs.player_officer_id
        join public.officers o on o.id = po.officer_id
        join public.traits jt on jt.code = o.specialty   -- 0160: her job's track
        join public.trait_effects te on te.trait = o.specialty
$o$, $n$      select po.id, po.officer_id, cs.ship_id, cs.seat, j.job, te.effect,
             j.job_pct * public.captain_level_mult(po.id, jt.focus)
        from public.ships s
        join public.captain_seats cs on cs.ship_id = s.id
        join public.player_officers po on po.id = cs.player_officer_id
        join public.captain_job j on j.officer_id = po.officer_id   -- 0165 (K9): her job, her first trait
        join public.traits jt on jt.code = j.job   -- 0160: her job's track
        join public.trait_effects te on te.trait = j.job
$n$),
  -- public.promotion_next
  ('public.promotion_next(uuid)', 1, $o$    from public.player_officers po join public.officers o on o.id = po.officer_id join public.traits t on t.code = o.specialty
$o$, $n$    from public.player_officers po join public.captain_job j on j.officer_id = po.officer_id join public.traits t on t.code = j.job
$n$),
  -- public.captain_seat_pick
  ('public.captain_seat_pick(uuid, uuid, uuid)', 1, $o$    join public.officers o on o.id = po.officer_id
    join public.traits t on t.code = o.specialty
$o$, $n$    join public.captain_job j on j.officer_id = po.officer_id   -- 0165 (K9): her job, her first trait
    join public.traits t on t.code = j.job
$n$),
  -- public.sign_officer: no fleet_id, the three-argument seat core, her job from public.captain_job
  ('public.sign_officer(uuid, text, uuid)', 1, $o$  v_pick   record;
begin$o$, $n$  v_pick   record;
  v_job    record;    -- 0165 (K9): her job and its value (public.captain_job)
begin$n$),
  ('public.sign_officer(uuid, text, uuid)', 2, $o$  v_off.wage_ducats := public.captain_wage(v_player, v_off.id);
$o$, $n$  v_off.wage_ducats := public.captain_wage(v_player, v_off.id);
  select cj.job, cj.job_pct into v_job from public.captain_job cj where cj.officer_id = v_off.id;
$n$),
  ('public.sign_officer(uuid, text, uuid)', 3, $o$  insert into public.player_officers (player_id, officer_id, fleet_id)
  values (v_player, v_off.id, p_fleet)
  returning id into v_id;
$o$, $n$  -- 0165 (K9): where she sits is her seat's alone (public.captain_seat_put, below)
  insert into public.player_officers (player_id, officer_id)
  values (v_player, v_off.id)
  returning id into v_id;
$n$),
  ('public.sign_officer(uuid, text, uuid)', 4, $o$    perform public.captain_seat_put(v_id, v_pick.ship_id, v_pick.seat, not v_npc);
$o$, $n$    perform public.captain_seat_put(v_id, v_pick.ship_id, v_pick.seat);
$n$),
  ('public.sign_officer(uuid, text, uuid)', 5, $o$      'officer', v_off.name, 'code', v_off.code, 'specialty', v_off.specialty,
      'bonus_pct', v_off.bonus_pct, 'cost', v_off.wage_ducats)));$o$,
   $n$      'officer', v_off.name, 'code', v_off.code, 'specialty', v_job.job,
      'bonus_pct', v_job.job_pct, 'cost', v_off.wage_ducats)));$n$),
  ('public.sign_officer(uuid, text, uuid)', 6, $o$    'specialty', v_off.specialty, 'bonus_pct', v_off.bonus_pct, 'fleet', p_fleet, 'paid', v_off.wage_ducats);$o$,
   $n$    'specialty', v_job.job, 'bonus_pct', v_job.job_pct, 'fleet', p_fleet, 'paid', v_off.wage_ducats);$n$),
  -- public.captain_xp_credit: aboard when she departed = seated (D9) and signed by then
  ('public.captain_xp_credit(uuid, numeric, numeric, numeric, timestamp with time zone)', 1, $o$     and (p_since is null
          or coalesce((select ox.aboard_since from public.officer_xp ox where ox.player_officer_id = z.player_officer_id),
                      z.hired_at) <= p_since);$o$,
   $n$     -- 0165 (K9): aboard when she departed = seated in the fleet now (captains change ships only in port, D9)
     -- and signed by then; officer_xp's aboard clock is retired
     and (p_since is null or z.hired_at <= p_since);$n$),
  -- public.client_rpc_entry_points: −1
  ('public.client_rpc_entry_points()', 1, $o$      ('cmd',         'post_officer',        'text, uuid'),
$o$, $n$      -- 0165 (K9): cmd.post_officer retired — a captain is seated by cmd.seat_captain
$n$);

create temp table before_0165 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.item_kinds) as items;

-- (b) the old bodies, kept under pg_temp names so OLD and NEW answer at the same instant
do $old$
declare
  d record;
  v_new text;
begin
  for d in select * from defs_before_0165
            where fn not in ('public.sign_officer(uuid, text, uuid)', 'public.client_rpc_entry_points()',
                             'public.captain_xp_credit(uuid, numeric, numeric, numeric, timestamp with time zone)') loop
    v_new := regexp_replace(d.def, '^CREATE OR REPLACE FUNCTION (\w+)\.(\w+)\(',
                            'CREATE OR REPLACE FUNCTION pg_temp.old_0165_\1_\2(');
    if v_new = d.def then
      raise exception '0165: could not name the old copy of %', d.fn;
    end if;
    execute v_new;
  end loop;
end $old$;

-- One merchant card, OLD or NEW, as text: the answer (officers in one order), or the refusal itself. The card
-- refuses a fleet that is not a merchant's (E_NOT_FOUND); comparing OUTCOMES over every fleet compares the
-- refusals too, and no planner can call it on a row the comparison meant to skip (prod 2026-10-18: the card's
-- qual was pushed below the join to players and called for the 17 player fleets).
create or replace function pg_temp.card_0165(p_fleet uuid, p_old boolean)
returns text
language plpgsql
as $$
begin
  if p_old then
    return pg_temp.canon_0165(pg_temp.old_0165_world_npc_fleet_card(p_fleet), 'officers')::text;
  end if;
  return pg_temp.canon_0165(world.npc_fleet_card(p_fleet), 'officers')::text;
exception when others then
  return 'REFUSED ' || sqlstate || ': ' || sqlerrm;
end $$;

-- ── 2. THE ONE READING OF HER JOB ───────────────────────────────────────────────────────────────
create or replace view public.captain_job as
select ct.officer_id, ct.trait as job, ct.base_pct::numeric(5,2) as job_pct
  from public.captain_traits ct
 where ct.ord = 1;
comment on view public.captain_job is
  '0165 (K9): a captain''s JOB is her first trait (captain_traits ord 1) at its value, at the scale officers.bonus_pct '
  'had (numeric(5,2)), so every answer prints as before. The one reading of it: world.inn, world.inn_chance, '
  'world.officers, world.npc_fleet_card, world.ship_seats, crew_terms (dark), promotion_next, captain_seat_pick, '
  'sign_officer, and the world guard. Server-only.';
revoke all on table public.captain_job from public, anon, authenticated;

do $$
begin
  if exists (select 1 from public.captain_traits ct where ct.ord = 1 and ct.base_pct <> ct.base_pct::numeric(5,2))
     or (select count(*) from public.captain_job) <> (select count(*) from public.officers)
     or exists (select 1 from public.officers o where not exists (select 1 from public.captain_job j where j.officer_id = o.id)) then
    raise exception '0165 self-assert FAIL: public.captain_job is not one row per captain at bonus_pct''s scale';
  end if;
end $$;

-- ── 3. WHAT WORKS A PROMOTION ITEM (item_use: one row per item, 0158) ───────────────────────────
-- data/captains.json promotion_items: spent by cmd.promote_captain, never fitted — never wears, spends no good.
insert into public.item_use (item_code, trigger, consumes) values
  ('sea-chart', null, '[]'),
  ('trade-seal', null, '[]'),
  ('battle-honour', null, '[]')
on conflict (item_code) do nothing;

-- ── 4. THE RE-CUTS ────────────────────────────────────────────────────────────────────────────
do $recut$
declare
  d record;
  h record;
  v_def text;
begin
  for d in select * from defs_before_0165 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0165 where fn = d.fn order by n loop
      if pg_temp.occurs_0165(v_def, h.old) <> 1 then
        raise exception '0165 slice: hunk % of % occurs % time(s), expected exactly 1 — the deployed body is not what this migration was generated against',
          h.n, d.fn, pg_temp.occurs_0165(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
end $recut$;

-- THE ONE WRITER of where a captain sits, without the aboard clock (its only use of p_came_aboard)
drop function public.captain_seat_put(uuid, uuid, integer, boolean);
create function public.captain_seat_put(p_signing uuid, p_ship uuid, p_seat int)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0157: THE ONE WRITER of where a captain sits. Ship null = ashore.
-- 0165 (K9): nothing else is written — player_officers.fleet_id and officer_xp.aboard_since are retired (a
-- captain is seated only in port, D9, so whoever sits in a fleet at sea was aboard when she sailed).
begin
  if p_ship is null then
    delete from public.captain_seats where player_officer_id = p_signing;
    return;
  end if;
  insert into public.captain_seats (player_officer_id, ship_id, seat) values (p_signing, p_ship, p_seat)
  on conflict (player_officer_id) do update set ship_id = excluded.ship_id, seat = excluded.seat;
end $$;
revoke all on function public.captain_seat_put(uuid, uuid, int) from public, anon, authenticated;
comment on function public.captain_seat_put(uuid, uuid, int) is
  '0157 / 0165: THE ONE WRITER of where a captain sits (public.captain_seats). Ship null = ashore. Called by '
  'public.seat_captain_for and public.sign_officer. Server-only.';

-- the door no screen opens, and its core
drop function cmd.post_officer(text, uuid);
drop function public.post_officer_to(uuid, text, uuid);

-- ── 5. SELF-ASSERT (heavy: every comparison and the probe, before any lock anyone waits on) ─────
create temp table timing_0165 (what text, ms numeric) on commit drop;

do $$
declare
  b        record;
  d        record;
  h        record;
  v_p      record;
  v_q      record;
  v_def    text;
  v_bad    int;
  v_n      int;
  v_r      jsonb;
  v_t      timestamptz := now();
  v_t0     timestamptz := clock_timestamp();
  v_player uuid;
  v_fleet  uuid;
  v_ship   uuid;
  v_po     uuid;
  v_hired  timestamptz;
  v_uid    uuid;
  c_uid constant uuid := '00000000-0165-4000-8000-000000000001';
  c_nil constant uuid := '00000000-0000-0000-0000-000000000000';
  c_off constant text := 'BERGENNAV';   -- a C navigator at 5.00 (data/officers.json)
begin
  select * into b from before_0165;

  -- (b) OLD = NEW at the same instant
  select count(*) into v_bad from public.ports p
   where exists (select 1 from public.port_buildings pb where pb.port_id = p.id and pb.kind = 'inn')
     and pg_temp.canon_0165(pg_temp.old_0165_world_inn(p.id), 'present')::text is distinct from pg_temp.canon_0165(world.inn(p.id), 'present')::text;
  if v_bad <> 0 then raise exception '0165 self-assert FAIL: world.inn moved at % inn(s)', v_bad; end if;
  select count(*) into v_bad from public.ports p
   cross join lateral (select world.inn(p.id) -> 'present' as pr) x
   where exists (select 1 from public.port_buildings pb where pb.port_id = p.id and pb.kind = 'inn')
     and x.pr is distinct from (select coalesce(jsonb_agg(e order by e ->> 'specialty', e ->> 'name', e ->> 'code'), '[]'::jsonb)
                                  from jsonb_array_elements(x.pr) e);
  if v_bad <> 0 then raise exception '0165 self-assert FAIL: world.inn is not in (job, name, code) order at % inn(s)', v_bad; end if;

  select count(*) into v_bad from public.officers o cross join public.ports p
   where p.kind = 'HARBOUR' and pg_temp.old_0165_world_inn_chance(o.id, p.id) is distinct from world.inn_chance(o.id, p.id);
  if v_bad <> 0 then raise exception '0165 self-assert FAIL: world.inn_chance moved for % captain × harbour pair(s)', v_bad; end if;
  insert into timing_0165 values ('inns', round(extract(epoch from clock_timestamp() - v_t0) * 1000));

  v_n := 0;
  for v_uid in select c_nil union all select pl.auth_uid from public.players pl where pl.auth_uid is not null loop
    perform cmd.assume_identity(v_uid);
    if pg_temp.old_0165_world_officers()::text is distinct from world.officers()::text then
      raise exception '0165 self-assert FAIL: world.officers moved for the company signed in as %', v_uid;
    end if;
    v_n := v_n + 1;
  end loop;
  perform cmd.assume_identity(c_nil);
  insert into timing_0165 values ('companies compared', v_n);

  -- every fleet: the same card, or the same refusal
  select count(*) filter (where c.o is distinct from c.n), count(*) filter (where c.o like 'REFUSED %' and c.o = c.n)
    into v_bad, v_n
    from (select pg_temp.card_0165(f.id, true) as o, pg_temp.card_0165(f.id, false) as n from public.fleets f) c;
  if v_bad <> 0 then raise exception '0165 self-assert FAIL: world.npc_fleet_card answered or refused differently for % fleet(s)', v_bad; end if;
  insert into timing_0165 values ('fleets refused alike by the card', v_n);
  -- a world whose merchants are switched off refuses every card: there, compare them LIT too (rolled back), so the
  -- answers — not only the refusals — are compared on every chain
  if not public.npc_traders_on() then
    begin
      update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');
      select count(*) filter (where c.o is distinct from c.n), count(*) filter (where c.o not like 'REFUSED %')
        into v_bad, v_n
        from (select pg_temp.card_0165(f.id, true) as o, pg_temp.card_0165(f.id, false) as n from public.fleets f) c;
      raise exception 'LIT_ROLLBACK_0165 % %', v_bad, v_n;
    exception when others then
      if sqlerrm not like 'LIT_ROLLBACK_0165 %' then raise; end if;
      v_bad := split_part(sqlerrm, ' ', 2)::int;
      v_n := split_part(sqlerrm, ' ', 3)::int;
    end;
    if v_bad <> 0 then raise exception '0165 self-assert FAIL: lit, world.npc_fleet_card answered or refused differently for % fleet(s)', v_bad; end if;
    insert into timing_0165 values ('merchant cards compared lit (rolled back)', v_n);
  end if;
  insert into timing_0165 values ('cards', round(extract(epoch from clock_timestamp() - v_t0) * 1000));

  select count(*) into v_bad from public.ships s
   where pg_temp.old_0165_world_ship_seats(s.id)::text is distinct from world.ship_seats(s.id)::text;
  if v_bad <> 0 then raise exception '0165 self-assert FAIL: world.ship_seats moved for % ship(s)', v_bad; end if;

  select count(*) into v_bad from public.fleets f
   where (select coalesce(string_agg(x::text, '|' order by x::text), '') from pg_temp.old_0165_public_crew_terms(f.id, v_t) x)
         is distinct from
         (select coalesce(string_agg(x::text, '|' order by x::text), '') from public.crew_terms(f.id, v_t) x);
  if v_bad <> 0 then raise exception '0165 self-assert FAIL: crew_terms moved for % fleet(s)', v_bad; end if;

  select count(*) into v_bad from public.player_officers po
   where pg_temp.old_0165_public_promotion_next(po.id)::text is distinct from public.promotion_next(po.id)::text;
  if v_bad <> 0 then raise exception '0165 self-assert FAIL: promotion_next moved for % signing(s)', v_bad; end if;
  select count(*) into v_bad from public.captain_seats cs join public.ships sh on sh.id = cs.ship_id
   where (select row(k.ship_id, k.seat)::text from pg_temp.old_0165_public_captain_seat_pick(cs.player_officer_id, sh.fleet_id, null) k)
         is distinct from (select row(k.ship_id, k.seat)::text from public.captain_seat_pick(cs.player_officer_id, sh.fleet_id, null) k);
  if v_bad <> 0 then raise exception '0165 self-assert FAIL: captain_seat_pick moved for % seated signing(s)', v_bad; end if;
  insert into timing_0165 values ('all comparisons', round(extract(epoch from clock_timestamp() - v_t0) * 1000));

  -- (c) THE ABOARD CLOCK: every captain seated in a fleet at sea — old filter = new — and no experience left behind
  select count(*) into v_bad
    from public.captain_seats cs
    join public.ships sh on sh.id = cs.ship_id
    join public.voyages v on v.fleet_id = sh.fleet_id and v.status = 'SAILING'
    join public.player_officers po on po.id = cs.player_officer_id
   where (coalesce((select ox.aboard_since from public.officer_xp ox where ox.player_officer_id = po.id), po.hired_at) <= v.departed_at)
         is distinct from (po.hired_at <= v.departed_at);
  if v_bad <> 0 then
    raise exception '0165 self-assert FAIL: % captain(s) at sea would be taught differently without officer_xp.aboard_since', v_bad;
  end if;
  if exists (select 1 from public.officer_xp ox where ox.xp > 0
              and not exists (select 1 from public.captain_xp cx where cx.player_officer_id = ox.player_officer_id)) then
    raise exception '0165 self-assert FAIL: officer_xp holds experience K6 did not carry into captain_xp';
  end if;

  -- (d) THE PROBE — own house, rolled back
  begin
    v_player := public.new_house(c_uid, 'Casa da Cabine', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_player;
    select s.id into v_ship from public.ships s where s.fleet_id = v_fleet order by s.is_flagship desc, s.id limit 1;
    perform public.credit(v_player, 'PROBE_K9', 50000,
      public.emit_event(v_player, 'PROBE', jsonb_build_object('why', '0165 self-assert')));
    if (select status from public.fleets where id = v_fleet) <> 'DOCKED' then
      raise exception '0165 self-assert FAIL: the probe house''s fleet is not docked (status %)', (select status from public.fleets where id = v_fleet);
    end if;
    v_r := public.sign_officer(v_player, c_off, v_fleet);
    select po.id, po.hired_at into v_po, v_hired from public.player_officers po join public.officers o on o.id = po.officer_id
     where po.player_id = v_player and o.code = c_off;
    if not coalesce((v_r->>'ok')::boolean, false)
       or v_r->>'specialty' is distinct from (select o.specialty from public.officers o where o.code = c_off)
       or v_r->>'bonus_pct' is distinct from (select o.bonus_pct::text from public.officers o where o.code = c_off)
       or not exists (select 1 from public.captain_seats cs where cs.player_officer_id = v_po and cs.ship_id = v_ship)
       or (select po.fleet_id from public.player_officers po where po.id = v_po) is not null
       or exists (select 1 from public.officer_xp ox where ox.player_officer_id = v_po) then
      raise exception '0165 self-assert FAIL: hired into her fleet she was not seated in the flagship, named at her job''s old value, with no fleet_id and no officer_xp row: %', v_r;
    end if;
    v_r := public.seat_captain_for(v_player, c_off, null);
    if not coalesce((v_r->>'ok')::boolean, false) or exists (select 1 from public.captain_seats where player_officer_id = v_po) then
      raise exception '0165 self-assert FAIL: she was not put ashore: %', v_r;
    end if;
    v_r := public.seat_captain_for(v_player, c_off, v_ship);
    if not coalesce((v_r->>'ok')::boolean, false)
       or not exists (select 1 from public.captain_seats where player_officer_id = v_po and ship_id = v_ship)
       or exists (select 1 from public.officer_xp ox where ox.player_officer_id = v_po) then
      raise exception '0165 self-assert FAIL: she was not seated again (or an officer_xp row was written): %', v_r;
    end if;
    if not exists (select 1 from jsonb_array_elements(world.ship_seats(v_ship)->'list') e
                    where e->'captain'->>'code' = c_off
                      and e->'captain'->>'job_word' = (select t.word from public.traits t join public.captain_job j on j.job = t.code
                                                        join public.officers o on o.id = j.officer_id where o.code = c_off)) then
      raise exception '0165 self-assert FAIL: her cabin does not name her job: %', world.ship_seats(v_ship);
    end if;
    -- signed before the departure: taught; a departure before she signed: not
    v_n := public.captain_xp_credit(v_fleet, 10, 0, 0, v_hired + interval '1 day');
    if v_n <> 1 then
      raise exception '0165 self-assert FAIL: a captain seated and signed before the departure was not taught (% taught)', v_n;
    end if;
    v_n := public.captain_xp_credit(v_fleet, 10, 0, 0, v_hired - interval '1 day');
    if v_n <> 0 then
      raise exception '0165 self-assert FAIL: a voyage that departed before she signed taught her (% taught)', v_n;
    end if;
    raise exception 'PROBE_ROLLBACK_0165';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0165' then raise; end if;
  end;
  if exists (select 1 from public.players where company_name = 'Casa da Cabine') then
    raise exception '0165 self-assert FAIL: the probe world was not rolled back';
  end if;
  perform cmd.assume_identity(c_nil);

  -- (e) THE RE-CUTS reverse; ACL / volatility / definer / config unmoved
  for d in select * from defs_before_0165 order by fn loop
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0165 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0165(v_def, h.new) <> 1 then
        raise exception '0165 self-assert FAIL: hunk % of % is not in the new body exactly once', h.n, d.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> d.def then
      raise exception '0165 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
      into v_p from pg_proc pr where pr.oid = d.fn::regprocedure;
    if v_p.acl <> d.acl or v_p.vol <> d.vol or v_p.secdef <> d.secdef or v_p.cfg <> d.cfg then
      raise exception '0165 self-assert FAIL: % changed its ACL, volatility, definer or config', d.fn;
    end if;
  end loop;
  select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
    into v_p from pg_proc pr where pr.oid = 'public.captain_seat_put(uuid, uuid, integer)'::regprocedure;
  select * into v_q from seat_put_before_0165;
  if v_p.acl is distinct from v_q.acl or v_p.vol is distinct from v_q.vol or v_p.secdef is distinct from v_q.secdef
     or v_p.cfg is distinct from v_q.cfg
     or to_regprocedure('public.captain_seat_put(uuid, uuid, integer, boolean)') is not null then
    raise exception '0165 self-assert FAIL: captain_seat_put is not the old ACL / definer / config at three arguments';
  end if;
  if to_regprocedure('cmd.post_officer(text, uuid)') is not null or to_regprocedure('public.post_officer_to(uuid, text, uuid)') is not null
     or (select count(*) from public.client_rpc_entry_points()) <> b.entry_points - 1
     or exists (select 1 from public.client_rpc_entry_points() e where e.function_name = 'post_officer') then
    raise exception '0165 self-assert FAIL: the entry points are not the old ones less cmd.post_officer';
  end if;

  -- item_use: one row per item, and the three promotion items (by name) never wear and spend nothing
  if (select count(*) from public.item_use u where u.item_code in ('sea-chart', 'trade-seal', 'battle-honour')
         and u.trigger is null and u.consumes = '[]'::jsonb) <> 3
     or (select count(*) from public.item_use) <> (select count(*) from public.item_kinds)
     or exists (select 1 from public.item_kinds k where not exists (select 1 from public.item_use u where u.item_code = k.code)) then
    raise exception '0165 self-assert FAIL: item_use is not one row per item with the three promotion items at (null, [])';
  end if;
  if exists (select 1 from unnest(array['anon', 'authenticated']) r(role)
              where has_table_privilege(r.role, 'public.captain_job', 'select,insert,update,delete')) then
    raise exception '0165 self-assert FAIL: a client can read public.captain_job';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0165 self-assert FAIL: % client write grant(s)', (select count(*) from public.client_write_grants());
  end if;
  insert into timing_0165 values ('heavy self-assert', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end $$;

create temp table chance_before_0165 on commit drop as
select o.id as officer_id, o.code, p.id as port_id, world.inn_chance(o.id, p.id) as chance
  from public.officers o cross join public.ports p where p.kind = 'HARBOUR';

-- ── 6. TWO CAPTAINS OF GOA (data/officers.json; languages from data/captains.generated.json) ───
update public.officers o set home_port_id = (select p.id from public.ports p where p.code = 'OLD')
 where o.code in ('ALBUQUERQ', 'GARCIAORTA')
   and o.home_port_id = (select p.id from public.ports p where p.code = 'GOA');
delete from public.captain_languages cl
 using public.officers o where o.id = cl.officer_id and o.code in ('ALBUQUERQ', 'GARCIAORTA');
insert into public.captain_languages (officer_id, ord, language)
select o.id, v.ord, v.language
  from (values ('ALBUQUERQ', 1, 'PORTUGUESE'), ('ALBUQUERQ', 2, 'INDIC'),
               ('GARCIAORTA', 1, 'PORTUGUESE'), ('GARCIAORTA', 2, 'INDIC'), ('GARCIAORTA', 3, 'ARABIC')) v(code, ord, language)
  join public.officers o on o.code = v.code;

do $$
begin
  if (select count(*) from public.officers o join public.ports p on p.id = o.home_port_id
       where o.code in ('ALBUQUERQ', 'GARCIAORTA') and p.code = 'OLD' and p.name = 'Old Goa') <> 2 then
    raise exception '0165 self-assert FAIL: Albuquerque and Garcia de Orta are not homed at Old Goa';
  end if;
  -- what homesickness reads (0160: docking in her home REGION clears it) is Old Goa's region, not Genoa's
  if exists (select 1 from public.officers o join public.ports hp on hp.id = o.home_port_id
              where o.code in ('ALBUQUERQ', 'GARCIAORTA')
                and hp.region_id is distinct from (select p.region_id from public.ports p where p.code = 'OLD'))
     or (select region_id from public.ports where code = 'OLD') is not distinct from (select region_id from public.ports where code = 'GOA') then
    raise exception '0165 self-assert FAIL: their home region is not Old Goa''s';
  end if;
  if (select string_agg(o.code || ':' || cl.ord || ':' || cl.language, ',' order by o.code, cl.ord)
        from public.captain_languages cl join public.officers o on o.id = cl.officer_id
       where o.code in ('ALBUQUERQ', 'GARCIAORTA'))
     <> 'ALBUQUERQ:1:PORTUGUESE,ALBUQUERQ:2:INDIC,GARCIAORTA:1:PORTUGUESE,GARCIAORTA:2:INDIC,GARCIAORTA:3:ARABIC'
     or (select pl.language from public.port_language pl join public.ports p on p.id = pl.port_id where p.code = 'OLD') <> 'PORTUGUESE' then
    raise exception '0165 self-assert FAIL: their languages are not Old Goa''s first (the generator''s rule)';
  end if;
  -- THE ONLY ANSWERS MEANT TO MOVE: every other captain's odds at every harbour are as before; these two's
  -- moved somewhere (their home's region and culture weights now follow Old Goa)
  if exists (select 1 from chance_before_0165 c
              where c.code not in ('ALBUQUERQ', 'GARCIAORTA')
                and world.inn_chance(c.officer_id, c.port_id) is distinct from c.chance) then
    raise exception '0165 self-assert FAIL: moving two captains home changed another captain''s inn odds';
  end if;
  if (select count(distinct c.code) from chance_before_0165 c
       where c.code in ('ALBUQUERQ', 'GARCIAORTA') and world.inn_chance(c.officer_id, c.port_id) is distinct from c.chance) <> 2 then
    raise exception '0165 self-assert FAIL: their inn odds did not follow their new home';
  end if;
end $$;

-- ── 7. LAST: the drops — one short retried step, NOWAIT, fixed order ─────────────────────────────
create temp table swap_0165 (what text, ms numeric, at timestamptz) on commit drop;
insert into swap_0165 (what, ms, at)
select 'last', pg_temp.locked_0165($last$
  -- 1-2. fleets (player_officers.fleet_id's FK), then player_officers → fleet_id, its index and FK
  lock table public.fleets in access exclusive mode nowait;
  lock table public.player_officers in access exclusive mode nowait;
  -- 3. officer_xp
  lock table public.officer_xp in access exclusive mode nowait;
  -- 4-5. traits (officers.specialty's FK), then officers → specialty, bonus_pct, their FK and CHECK
  lock table public.traits in access exclusive mode nowait;
  lock table public.officers in access exclusive mode nowait;
  alter table public.player_officers drop column fleet_id;
  drop table public.officer_xp;
  alter table public.officers drop column specialty, drop column bonus_pct;
$last$, 'the last step (player_officers.fleet_id, officer_xp, officers.specialty / bonus_pct)'), clock_timestamp();

-- ── 8. SELF-ASSERT (light: the catalogue, and the readers run) ──────────────────────────────────
do $$
declare
  r        record;
  v_hits   text;
  v_times  text;
  v_port   uuid;
  v_ship   uuid;
  v_fleet  uuid;
begin
  if exists (select 1 from pg_attribute where attrelid = 'public.player_officers'::regclass and attname = 'fleet_id' and not attisdropped)
     or exists (select 1 from pg_attribute where attrelid = 'public.officers'::regclass and attname in ('specialty', 'bonus_pct') and not attisdropped)
     or to_regclass('public.officer_xp') is not null
     or to_regclass('public.player_officers_fleet') is not null then
    raise exception '0165 self-assert FAIL: a retired column, index or table is still there';
  end if;

  -- no function body names a dropped object (comments and string literals blanked: a jsonb key is not a read)
  select string_agg(distinct n.nspname || '.' || p.proname, ', ') into v_hits
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   cross join lateral (select pg_temp.code_0165(p.prosrc) as c) x
   where n.nspname not in ('pg_catalog', 'information_schema', 'pg_temp') and n.nspname not like 'pg_temp%' and n.nspname not like 'pg_toast%'
     and (x.c ~ '\mofficer_xp\M' or x.c ~ '\mpost_officer(_to)?\M' or x.c ~ '\mspecialty\M' or x.c ~ '\mbonus_pct\M'
          or x.c ~* 'player_officers\.fleet_id'
          or x.c ~* 'insert\s+into\s+public\.player_officers\s*\([^)]*fleet_id'
          or x.c ~* 'update\s+public\.player_officers\s+(\w+\s+)?set\s+fleet_id'
          or exists (select 1 from regexp_matches(x.c, 'player_officers\s+(?:as\s+)?(\w+)', 'gi') m
                      where lower(m[1]) not in ('on', 'join', 'left', 'where', 'set', 'using', 'values', 'select')
                        and x.c ~* ('\m' || m[1] || '\.fleet_id\M')));
  if v_hits is not null then
    raise exception '0165 self-assert FAIL: a function body still names a retired object: %', v_hits;
  end if;
  if exists (select 1 from pg_class c where c.relkind in ('v', 'm')
              and c.relnamespace::regnamespace::text in ('public', 'world', 'cmd', 'voyage')
              and pg_get_viewdef(c.oid) ~ '\mofficer_xp\M|\mspecialty\M|\mbonus_pct\M') then
    raise exception '0165 self-assert FAIL: a view still names a retired column';
  end if;

  -- the readers run without them (one call each; ms)
  select p.id into v_port from public.ports p
   where exists (select 1 from public.port_buildings b where b.port_id = p.id and b.kind = 'inn') order by p.code limit 1;
  select cs.ship_id, s.fleet_id into v_ship, v_fleet from public.captain_seats cs join public.ships s on s.id = cs.ship_id
   order by cs.player_officer_id limit 1;
  perform world.inn(v_port), world.officers(), world.ship_seats(v_ship), public.crew_pct(v_fleet, null, 'speed'),
          case when public.npc_traders_on() then world.npc_fleet_card((select s2.fleet_id from public.captain_seats c2
            join public.ships s2 on s2.id = c2.ship_id join public.fleets f2 on f2.id = s2.fleet_id
            join public.players p2 on p2.id = f2.player_id where p2.is_npc order by c2.player_officer_id limit 1)) end;

  select string_agg(t.what || ' ' || t.ms || (case when t.what in ('companies compared', 'fleets refused alike by the card', 'merchant cards compared lit (rolled back)') then '' else ' ms' end), ', ') into v_times from timing_0165 t;
  raise notice '0165 self-assert ok: A CAPTAIN IS READ FROM HER SEAT AND HER FIRST TRAIT (K9). The mirror held for all % captains; public.captain_job is the one reading of her job. OLD = NEW at the same instant: world.inn at every inn, world.inn_chance for every captain × harbour, world.officers for every company signed in and for nobody, world.npc_fleet_card for every fleet (the same card, or the same refusal), world.ship_seats for every ship, crew_terms for every fleet, promotion_next and the seat picker for every signing. The aboard clock: every captain at sea taught alike without it. The probe (rolled back): hired into her docked fleet she sat in the flagship with no fleet_id and no officer_xp row, at her job''s old value; ashore and seated again; taught once signed before the departure, not before. Eleven bodies reverse, ACLs unmoved; captain_seat_put at three arguments, ACL unmoved; cmd.post_officer and post_officer_to dropped (entry points −1). item_use: % rows = % items (sea-chart, trade-seal, battle-honour: never wear, spend nothing). Albuquerque and Garcia de Orta are of Old Goa (its region, its languages). DROPPED: player_officers.fleet_id, officer_xp, officers.specialty / bonus_pct — no function body or view names them, the readers run. TIMES: %. LOCKS: nothing anyone waits on before §7; the last step (NOWAIT) % ms; held % ms from it to the end of the file.',
    (select count(*) from public.officers), (select count(*) from public.item_use), (select count(*) from public.item_kinds), v_times,
    (select ms from swap_0165 where what = 'last'),
    round(extract(epoch from clock_timestamp() - (select at from swap_0165 where what = 'last')) * 1000, 1);
end $$;
