-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0023 — THE READ WALL IS STANDING AGAIN
--        0018 swept EXECUTE off every SECURITY DEFINER function, including the one ELEVEN row
--        level security policies call. Every one of them has been raising 42501 in production
--        since. This restores what a policy needs to be evaluable, by sweeping the catalogue for
--        the whole class rather than by naming the one function that was noticed.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHAT IS ACTUALLY BROKEN, MEASURED ON THIS CHAIN 2026-08-23 ─────────────────────────────────
-- 0018:200 revokes EXECUTE from `public`, `anon` and `authenticated` on EVERY SECURITY DEFINER
-- function in the four schemas, then grants back only the RPCs `client_rpc_entry_points()` names.
-- `public.current_player_id()` (0004:262) is SECURITY DEFINER and is not an entry point, so it was
-- swept. It is also the body of ELEVEN policies:
--
--     events · fleets · haggle_daily · ledger · orders · player_officers · player_skills
--     ships  · trade_daily · voyage_events · voyages
--
-- A policy expression is evaluated AS THE CALLER. So since 0018, a signed-in captain doing a plain
-- `select * from public.fleets` gets **42501 permission denied for function current_player_id** —
-- measured, as `authenticated`, on all eleven. `public.players` is the exception and reads fine,
-- because its policy calls `auth.uid()`, which is not a definer and was never swept.
--
-- The game still works by ACCIDENT: every client read goes through a `world.*` SECURITY DEFINER
-- function, which runs as its definer and never evaluates the policy as the caller. So the wall
-- has been down and nothing has walked through it yet.
--
-- ── AND IT IS WORSE THAN A DEAD POLICY: THE CATALOGUE ADVERTISES A LIE ─────────────────────────
-- 0004:336, 0005:97, 0015:80/105 and 0016:75/94 all `grant select` on those tables to
-- `authenticated`. A grant that the row filter cannot evaluate is a read the schema promises and
-- the database refuses. That is the defect, not merely the missing EXECUTE.
--
-- ── THE SAME BUG WEARS FIVE HATS, AND FOUR OF THEM WERE NOT LOOKED AT ─────────────────────────
-- A policy body is not the only expression PostgreSQL evaluates as the caller. Measured here on
-- PGlite 0.5.5 / PostgreSQL 18.3, by building each case and inserting as `authenticated`:
--
--     object                              EXECUTE checked as the caller?   instances in this chain
--     ─────────────────────────────────   ──────────────────────────────   ──────────────────────
--     RLS policy body                     YES  -> 42501                    11, ALL BROKEN
--     CHECK constraint                    YES  -> 42501                    0
--     column DEFAULT                      YES  -> 42501                    0
--     GENERATED column                    YES  -> 42501                    0
--     index expression                    YES  -> 42501                    0
--     TRIGGER function                    NO   -> allowed                   4, all fine
--
-- The trigger row is the one that surprised: a trigger function is invoked by the system and its
-- EXECUTE privilege is checked when the trigger is CREATED, not when it fires. So
-- `public.tg_house_caps` (0021), `public.tg_reconcile_from_ledger` and
-- `public.tg_reconcile_from_player` (0004) are unreachable to a client and that costs nothing.
-- That is why triggers are deliberately OUT of the authority below — and the measurement is
-- recorded here so the next person does not have to re-derive it to know why.
--
-- ── SO THE FIX IS A SWEEP, NOT A NAME ──────────────────────────────────────────────────────────
--     public.caller_evaluated_functions()   THE one authority for "the database will evaluate this
--                                           function AS a client role, and that role may not
--                                           execute it". Zero rows is the law, exactly as it is
--                                           for public.client_write_grants() (0001:291) and
--                                           public.client_executable_writers() (0018:228). It is
--                                           the third member of that family and it is queried the
--                                           same way: by the migration that changes posture, and
--                                           by scripts/db/proofs/03_grant_lockdown.sql at the end
--                                           of the chain.
--
-- The grant loop below is a loop OVER THAT FUNCTION. Nothing here names `current_player_id`: if a
-- later migration writes a policy calling something else, this same rule covers it, and if one
-- writes a policy calling a WRITER the loop REFUSES rather than granting it (see below).
--
-- ── 0018'S PROPERTY IS NOT WEAKENED, AND THAT IS ENFORCED, NOT PROMISED ───────────────────────
-- 0018's rule is that no client role may EXECUTE a SECURITY DEFINER function that WRITES. The
-- grant loop refuses to grant anything VOLATILE — the same `provolatile = 'v'` definition
-- `client_executable_writers()` uses — and raises instead, so this file can never hand back a
-- writer by accident. `current_player_id()` is `stable` and returns the caller's own id derived
-- from the caller's own JWT; it reads nothing the caller does not already know about themselves.
-- The self-assert re-reads `client_executable_writers()` and `client_write_grants()` after the
-- loop and requires both to be zero.
--
-- ── AND THE PROOF THAT LET THIS THROUGH IS FIXED IN THE SAME SLICE ────────────────────────────
-- scripts/db/proofs/03_grant_lockdown.sql sweeps every table with an INSERT and requires 42501.
-- It never once did a SELECT. So it proved the write wall and was structurally blind to the read
-- wall — which is why this survived from 0018 to today with a green proof suite on every run.
-- Three markers are added there: the client can read its own rows, a second house sees NONE of
-- them, and `caller_evaluated_functions()` is empty with a positive control.
--
-- ── FOLDED IN: THE SKILL BLURBS STOP DUPLICATING `takes_effect` ───────────────────────────────
-- 0016 seeded three blurbs ending "Not yet read by any rule." while `world.skills()` serves a
-- `takes_effect` boolean for the same statement, computed from the one list of effects a rule
-- reads. Two authorities for one disclosure — and the prose is the copy that goes stale: HAGGLING's
-- said "Not yet read by any rule" until 0022 wired it and had to rewrite the sentence by hand.
-- The blurbs become pure flavour, `takes_effect` becomes the single source, and the self-assert
-- sweeps `skills` AND `officers` for the phrase so the class cannot come back in either table.
--
-- ── THIS MIGRATION GRANTS ──────────────────────────────────────────────────────────────────────
-- One `grant execute` per row the sweep reports (today: `public.current_player_id()` to
-- `authenticated`, one statement). `supabase db push` connects as `postgres.<ref>` through the
-- pooler and cannot do this on these schemas — apply through the Management API as `postgres`, the
-- path 0018 and 0022 took. There is NO revoke in this file.
--
-- Depends ONLY on: 0001 (client_write_grants, wc), 0004 (current_player_id, new_house, the
--                  policies), 0016 (skills), 0018 (client_executable_writers, the sweep this
--                  repairs), 0021/0022 (the newest policies and triggers the sweep must see).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 1. THE THIRD MEMBER OF THE LOCKDOWN FAMILY ─────────────────────────────────────────────────
create or replace function public.caller_evaluated_functions()
returns table (
  role_name          text,
  object_kind        text,
  table_name         text,
  object_name        text,
  schema_name        text,
  function_name      text,
  identity_arguments text,
  volatility         "char"
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- Every expression PostgreSQL evaluates AS THE CALLER, joined to the client roles that can
  -- reach the table it hangs on, filtered to the ones that role may not EXECUTE.
  --
  -- TRIGGERS ARE DELIBERATELY ABSENT. Measured 2026-08-23: a trigger function's EXECUTE privilege
  -- is checked when the trigger is created, not when it fires, so a client with no grant on the
  -- function still fires it successfully. Including them would report four rows that are not
  -- defects and teach everyone to ignore this list.
  with refs as (
      -- (a) row level security policy bodies — USING and WITH CHECK alike
      select 'policy'::text as kind, pol.polrelid as relid,
             pol.polname::text as obj, d.refobjid as fnoid, pol.polroles as roles
        from pg_policy pol
        join pg_depend d on d.classid = 'pg_policy'::regclass and d.objid = pol.oid
                        and d.refclassid = 'pg_proc'::regclass
    union all
      -- (b) CHECK constraints
      select 'check constraint', con.conrelid, con.conname::text, d.refobjid, null::oid[]
        from pg_constraint con
        join pg_depend d on d.classid = 'pg_constraint'::regclass and d.objid = con.oid
                        and d.refclassid = 'pg_proc'::regclass
       where con.contype = 'c'
    union all
      -- (c) column DEFAULTs and (d) GENERATED columns — both live in pg_attrdef
      select case when a.attgenerated <> '' then 'generated column' else 'column default' end,
             ad.adrelid, (c0.relname || '.' || a.attname)::text, d.refobjid, null::oid[]
        from pg_attrdef ad
        join pg_class c0 on c0.oid = ad.adrelid
        join pg_attribute a on a.attrelid = ad.adrelid and a.attnum = ad.adnum
        join pg_depend d on d.classid = 'pg_attrdef'::regclass and d.objid = ad.oid
                        and d.refclassid = 'pg_proc'::regclass
    union all
      -- (e) index expressions
      select 'index expression', i.indrelid, ic.relname::text, d.refobjid, null::oid[]
        from pg_index i
        join pg_class ic on ic.oid = i.indexrelid
        join pg_depend d on d.classid = 'pg_class'::regclass and d.objid = i.indexrelid
                        and d.refclassid = 'pg_proc'::regclass
  )
  select g.role_name::text,
         refs.kind,
         (n.nspname || '.' || c.relname)::text,
         refs.obj,
         pn.nspname::text,
         p.proname::text,
         pg_get_function_identity_arguments(p.oid)::text,
         p.provolatile
    from refs
    join pg_class c      on c.oid = refs.relid
    join pg_namespace n  on n.oid = c.relnamespace
    join pg_proc p       on p.oid = refs.fnoid
    join pg_namespace pn on pn.oid = p.pronamespace
   cross join (values ('anon'), ('authenticated')) as g(role_name)
   where n.nspname in ('public', 'world', 'cmd', 'voyage')
     -- the policy names its own roles; an empty polroles means PUBLIC, so everyone
     and (refs.roles is null
          or refs.roles = '{}'::oid[]
          or (select r.oid from pg_roles r where r.rolname = g.role_name) = any(refs.roles))
     -- and the role must actually be able to touch the table, or the expression never runs for it
     and (has_table_privilege(g.role_name, c.oid, 'select')
          or has_table_privilege(g.role_name, c.oid, 'insert')
          or has_table_privilege(g.role_name, c.oid, 'update')
          or has_table_privilege(g.role_name, c.oid, 'delete'))
     and not has_function_privilege(g.role_name, p.oid, 'execute')
$$;

comment on function public.caller_evaluated_functions() is
  'THE ONE authority for the third hole in the lockdown: an expression the database evaluates AS A '
  'CLIENT ROLE — a policy body, a CHECK, a column default, a generated column or an index '
  'expression — that calls a function that role may not EXECUTE. Zero rows is the law, as it is '
  'for client_write_grants() (0001) and client_executable_writers() (0018). Triggers are excluded '
  'deliberately: a trigger function''s EXECUTE is checked at CREATE TRIGGER, not at fire time '
  '(measured 2026-08-23), so they are not this bug.';

-- THE PRE-IMAGE, captured before the repair, so "this file fixed something real" is a comparison
-- and not a sentence. Scaffolding for one assert; dropped at the foot of this file.
create temporary table caller_gaps_before_0023 as
  select * from public.caller_evaluated_functions();

-- ── 2. THE REPAIR — A LOOP OVER THE AUTHORITY, NOT A LIST OF NAMES ────────────────────────────
do $$
declare
  r      record;
  v_done int := 0;
begin
  for r in select distinct schema_name, function_name, identity_arguments, role_name, volatility
             from public.caller_evaluated_functions()
            order by 1, 2, 3, 4
  loop
    -- 0018'S PROPERTY, ENFORCED RATHER THAN PROMISED. A policy has no business calling a function
    -- that writes, and if one ever does, handing a client EXECUTE on it would re-open exactly the
    -- hole 0018 closed. Refuse, loudly, and make somebody look at it.
    if r.volatility = 'v' then
      raise exception '0023 FAIL: %.%(%) is VOLATILE — a WRITER — and something evaluates it as %. Granting EXECUTE would re-open 0018''s hole; the expression that calls it is the thing to change',
        r.schema_name, r.function_name, r.identity_arguments, r.role_name;
    end if;
    execute format('grant execute on function %I.%I(%s) to %I',
                   r.schema_name, r.function_name, r.identity_arguments, r.role_name);
    v_done := v_done + 1;
    raise notice '0023: granted EXECUTE on %.%(%) to % — a policy, check or default evaluates it as that role',
      r.schema_name, r.function_name, r.identity_arguments, r.role_name;
  end loop;
  raise notice '0023: % caller-evaluated grant(s) restored', v_done;
end $$;

-- ── 3. THE SKILL BLURBS STOP SAYING WHAT `takes_effect` ALREADY SAYS ──────────────────────────
-- Supersedes the blurbs 0016:294-300 seeded. Pure flavour now: what the trade IS, never whether a
-- rule reads it. `world.skills()`.takes_effect (0016:252, superseded by 0022) is the one place
-- that answers the second question, computed from the one list of effects the rules read.
update public.skills
   set blurb = 'Reading the sky, the set of a current, and what the water under the keel is doing.'
 where code = 'NAVIGATION';
update public.skills
   set blurb = 'Books kept well enough that a factor will let you move more in a day.'
 where code = 'ACCOUNTING';

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_a       constant uuid := '00000000-0023-4000-8000-00000000000a';
  c_b       constant uuid := '00000000-0023-4000-8000-00000000000b';
  v_a       uuid;
  v_b       uuid;
  v_fleet_a uuid;
  v_before  int;
  v_after   int;
  v_tables  int;
  v_names   text;
  v_n       int;
  v_left    int;
  v_probe   int;
  r         record;
  v_state   text;
  v_unread  text;
  v_read_ok int := 0;
  v_iso_ok  int := 0;
  v_iso_n   int := 0;
  v_broken  text := '';   -- the isolation loop's findings
  v_unread_t text := '';  -- the read loop's, kept separate: an error message that prints a
                          -- variable a later loop overwrote sends the reader to the wrong place
  -- findings, recorded inside the throwaway subtransaction and read after it is gone
  f_bit       boolean := false;
  f_fixed     boolean := false;
  f_reads     boolean := false;
  f_isolates  boolean := false;
  f_finds_chk boolean := false;
  f_posture   boolean := false;
  f_blurbs    boolean := false;
begin
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- (a) THE SWEEP FOUND SOMETHING REAL, AND THEN FOUND NOTHING. The pre-image IS the positive
  --     control: if it were empty this file repaired nothing and every check below would be
  --     passing over an untouched database.
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  select count(*), count(distinct table_name) into v_before, v_tables from caller_gaps_before_0023;
  select string_agg(distinct schema_name || '.' || function_name, ', ') into v_names
    from caller_gaps_before_0023;
  if v_before > 0 and v_tables >= 5 then f_bit := true; end if;

  select count(*) into v_after from public.caller_evaluated_functions();
  if v_after = 0 then f_fixed := true; end if;

  -- ════════════════════════════════════════════════════════════════════════════════════════════
  -- (b) AND THE PROPERTY THE GRANT IS FOR, WHICH A GRANT ASSERT CANNOT SEE. Two houses, and a
  --     real `set local role authenticated` doing a real SELECT on every table that was broken.
  --     A catalogue read would pass here while the wall was still down; this is the check that
  --     would have caught the bug on the day 0018 landed.
  -- ════════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_a := public.new_house(c_a, 'Casa Alfa 0023', 'PRT');
    v_b := public.new_house(c_b, 'Casa Beta 0023', 'PRT');
    select id into v_fleet_a from public.fleets where player_id = v_a;

    -- Give house A a row in the tables `new_house` does not touch, so the isolation half below is
    -- not vacuous on them. An assert over an empty table reports a safety it never examined.
    insert into public.trade_daily (player_id, port_id, good_id, game_day, qty)
    select v_a, f.port_id, g.id, world.game_day(), 1
      from public.fleets f, public.goods g where f.id = v_fleet_a order by g.code limit 1;
    insert into public.haggle_daily (player_id, port_id, good_id, game_day, attempts, wins, concession)
    select v_a, f.port_id, g.id, world.game_day(), 1, 0, 0
      from public.fleets f, public.goods g where f.id = v_fleet_a order by g.code limit 1;
    insert into public.player_skills (player_id, skill_id, level)
    select v_a, s.id, 1 from public.skills s order by s.code limit 1;
    insert into public.player_officers (player_id, officer_id, fleet_id)
    select v_a, o.id, v_fleet_a from public.officers o order by o.code limit 1;
    perform cmd.assume_identity(c_a);
    perform cmd.issue(v_fleet_a, 'PROVISION FULL');   -- so `orders` is not empty either

    -- (b.1) EVERY BROKEN TABLE IS READABLE AGAIN, BY THE ROLE THE POLICY IS WRITTEN FOR. The list
    --       comes from the pre-image, so it is exactly the set this file repaired — never a list
    --       typed from a bug report.
    perform cmd.assume_identity(c_a);
    for r in select distinct table_name from caller_gaps_before_0023 order by 1 loop
      begin
        execute 'set local role authenticated';
        begin
          execute format('select count(*) from %s', r.table_name);
          v_read_ok := v_read_ok + 1;
        exception when others then
          get stacked diagnostics v_state = returned_sqlstate;
          v_unread_t := v_unread_t || format(' %s(%s)', r.table_name, v_state);
        end;
        execute 'set local role none';
      exception when others then
        execute 'set local role none';
        raise;
      end;
    end loop;
    if v_read_ok = v_tables and v_unread_t = '' then f_reads := true; end if;

    -- (b.2) AND ONE HOUSE SEES NOTHING OF THE OTHER, WHICH IS WHAT RLS IS ACTUALLY FOR. A read
    --       that works but shows everybody everything is a worse bug than the one being fixed.
    --       Only tables where BOTH houses could have rows are counted, and the count is asserted,
    --       so a table that happens to be empty cannot pass this by saying nothing.
    for r in select t from unnest(array['public.fleets', 'public.ships', 'public.ledger',
                                        'public.events', 'public.orders', 'public.trade_daily',
                                        'public.haggle_daily', 'public.player_skills',
                                        'public.player_officers']) t loop
      v_iso_n := v_iso_n + 1;
      -- Each read is GUARDED. Unguarded, a 42501 here aborts the whole block and the carefully
      -- worded asserts below never get to speak — the reader sees a raw SQLSTATE instead of the
      -- sentence naming which table and which house. A -1 records "could not read at all".
      perform cmd.assume_identity(c_a);
      begin
        execute 'set local role authenticated';
        begin execute format('select count(*) from %s', r.t) into v_n;
        exception when others then v_n := -1; end;
        execute 'set local role none';
      exception when others then execute 'set local role none'; raise; end;
      begin
        execute 'set local role authenticated';
        begin execute format('select count(*) from %s where player_id = %L', r.t, v_b) into v_probe;
        exception when others then v_probe := -1; end;
        execute 'set local role none';
      exception when others then execute 'set local role none'; raise; end;
      -- THE PROPERTY IS ABOUT OWNERSHIP, AND IT MUST NOT DEPEND ON WHO ELSE EXISTS.
      --
      -- Two earlier drafts of this check were wrong, and the second would have ABORTED THIS
      -- MIGRATION ON THE LIVE PROJECT:
      --   1. "B sees zero rows" — wrong on every table where B legitimately owns rows of its own,
      --      and it went red on four correct tables.
      --   2. "A + B = the whole table" — correct on an empty local database and FALSE on
      --      production, which already carries a real house whose fleets, ships, ledger and events
      --      rows this migration must not care about. Two probe houses cannot account for three.
      --
      -- What actually must hold is exact and local: A sees EXACTLY the rows A owns, and A sees
      -- NONE of B's. Both halves are asserted; the first stops an over-tight policy passing as
      -- isolation, the second IS the isolation.
      execute format('select count(*) from %s where player_id = %L', r.t, v_a) into v_left;
      if v_left >= 1 and v_n = v_left and v_probe = 0 then
        v_iso_ok := v_iso_ok + 1;
      else
        v_broken := v_broken || format(' %s(A-sees=%s A-owns=%s of-B-visible-to-A=%s)', r.t, v_n, v_left, v_probe);
      end if;
    end loop;
    if v_iso_ok = v_iso_n then f_isolates := true; end if;
    perform cmd.assume_identity(c_a);

    -- (c) THE FOUR BRANCHES OF THE SWEEP THAT HAVE NO INSTANCES TODAY ARE NOT DEAD CODE. Build a
    --     CHECK-constraint case on purpose and require the authority to report it; without this,
    --     four fifths of that function is never executed by anything and could be nonsense.
    create function public.probe_0023_chk(x int) returns boolean
      language sql immutable as $c$ select x > 0 $c$;
    revoke all on function public.probe_0023_chk(int) from public, anon, authenticated;
    create table public.probe_0023_t (x int check (public.probe_0023_chk(x)));
    grant select on public.probe_0023_t to authenticated;
    select count(*) into v_probe from public.caller_evaluated_functions()
     where function_name = 'probe_0023_chk' and object_kind = 'check constraint'
       and role_name = 'authenticated';
    if v_probe = 1 then f_finds_chk := true; end if;
    drop table public.probe_0023_t;
    drop function public.probe_0023_chk(int);

    raise exception '__PROBE_ROLLBACK_0023__' using errcode = 'P0001';
  exception when others then
    begin execute 'set local role none'; exception when others then null; end;
    if sqlerrm <> '__PROBE_ROLLBACK_0023__' then raise; end if;
  end;
  -- ── the subtransaction is gone; plpgsql variables are not transactional, so the findings
  --    survived it. Assert on them now. ────────────────────────────────────────────────────────

  if not f_bit then
    raise exception '0023 self-assert FAIL: the sweep found % gap(s) across % table(s) before the repair. If it found nothing this file fixed nothing and every check below passes over an untouched database', v_before, v_tables;
  end if;
  if not f_fixed then
    raise exception '0023 self-assert FAIL: % caller-evaluated function(s) are STILL unreachable after the repair: %', v_after,
      (select string_agg(role_name || ' -> ' || schema_name || '.' || function_name, ', ')
         from public.caller_evaluated_functions());
  end if;
  if not f_reads then
    raise exception '0023 self-assert FAIL: as `authenticated`, % of % repaired table(s) could be read; these still refuse:%', v_read_ok, v_tables, v_unread_t;
  end if;
  if not f_isolates then
    raise exception '0023 self-assert FAIL: row level security isolated only % of % table(s) — a house did not see exactly its own rows, saw some of the other house''s, or owned none so the check was vacuous:%', v_iso_ok, v_iso_n, v_broken;
  end if;
  if not f_finds_chk then
    raise exception '0023 self-assert FAIL: a CHECK constraint calling a deliberately unreachable function was NOT reported by caller_evaluated_functions(); four of its five branches are unexercised and may be nonsense';
  end if;

  -- (d) 0018'S PROPERTY SURVIVED. Nothing volatile was granted, no writer became reachable, and
  --     no table write grant appeared. Re-read, never assumed.
  select count(*) into v_n from caller_gaps_before_0023 where volatility = 'v';
  if v_n = 0
     and (select count(*) from public.client_executable_writers()) = 0
     and (select count(*) from public.client_write_grants()) = 0
     and has_function_privilege('authenticated', 'public.current_player_id()', 'execute')
     and not has_function_privilege('anon', 'public.current_player_id()', 'execute') then
    f_posture := true;
  end if;
  if not f_posture then
    raise exception '0023 self-assert FAIL: the repair granted % volatile function(s), or a client write/execute grant appeared, or current_player_id is still unreachable to authenticated / newly reachable to anon', v_n;
  end if;

  -- (e) THE DISCLOSURE HAS ONE AUTHORITY. No blurb in either catalogue table says whether a rule
  --     reads it; `world.skills().takes_effect` does. Swept as a CLASS, over both tables, with a
  --     positive control proving the pattern can match something.
  select string_agg(t || ':' || code, ', ') into v_unread from (
    select 'skills'::text as t, code from public.skills
     where blurb ~* 'not (yet )?read by any rule'
    union all
    select 'officers', code from public.officers
     where blurb ~* 'not (yet )?read by any rule') s;
  if v_unread is null
     and ('Not yet read by any rule.' ~* 'not (yet )?read by any rule')   -- the pattern DOES match
     and (select count(*) from public.skills) >= 4
     and (world.skills()->'effects_read') ? 'SPREAD'
     and (world.skills()->'effects_read') ? 'ENDURANCE' then
    f_blurbs := true;
  end if;
  if not f_blurbs then
    raise exception '0023 self-assert FAIL: % catalogue blurb(s) still duplicate what takes_effect says, or the sweep pattern matches nothing, or world.skills() stopped reporting the effects it reads', coalesce(v_unread, 'no');
  end if;

  -- The probe rolled back and left nothing of its own — houses, rows, probe objects and all. NOT
  -- "the tables are empty": this chain deploys onto a live world with a real house in it.
  select count(*) into v_left from public.players where auth_uid in (c_a, c_b);
  if v_left <> 0 then
    raise exception '0023 self-assert FAIL: % probe house(s) survived the subtransaction', v_left;
  end if;
  if to_regclass('public.probe_0023_t') is not null
     or to_regprocedure('public.probe_0023_chk(int)') is not null then
    raise exception '0023 self-assert FAIL: the probe left its CHECK-constraint fixture in the world';
  end if;

  raise notice '0023 self-assert ok: the read wall is standing again — before this file, % caller-evaluated grant(s) were missing across % table(s) (%), so a signed-in captain doing a plain SELECT on any of them got 42501 while the game only worked because every read detours through a world.* definer; the repair is a LOOP OVER public.caller_evaluated_functions() and names no function, and it now reports 0; as `authenticated` all % repaired table(s) read, and on % table(s) one house saw EXACTLY the rows it owns and ZERO of the other house''s — asserted per owner rather than as a sum, so it holds on a live project that already carries other houses; a CHECK constraint built on purpose WAS reported by the same authority, so its non-policy branches are live code; 0018 is intact — 0 volatile functions granted, 0 client write grants, 0 client-executable writers, current_player_id reachable by authenticated and still not by anon; triggers are excluded on a measurement, not a hunch (EXECUTE on a trigger body is checked at CREATE TRIGGER, not at fire time); and no blurb in `skills` or `officers` states whether a rule reads it any more — world.skills().takes_effect is the one place that says so; the probe left 0 houses and 0 fixtures behind',
    v_before, v_tables, v_names, v_read_ok, v_iso_n;
end $$;

drop table caller_gaps_before_0023;
