-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 192 - REPUTATION IS CHECKED AS ITS OWNER  (migration 0489; docs/dev-log/2026-11-24-reputation-deferred-trigger.md)
--
--   The fault: public.reputation_reconciles(), the function of two DEFERRABLE INITIALLY DEFERRED constraint triggers on
--   public.reputation_book and public.reputation_balance, ran with invoker rights. PostgreSQL 17 (prod, and the disposable chain)
--   runs a deferred trigger as the role current at COMMIT, `authenticated` for a player, which may not read either table: every
--   press of a signed-in player that wrote a Reputation book row failed with 42501 and rolled back whole. 0489 makes it SECURITY DEFINER.
--
--   WHAT THIS PROOF CANNOT SHOW, said plainly: this proof runs on PGlite, PostgreSQL 18, which runs a deferred trigger as the role
--   that QUEUED it (the security definer door), so the fault never happened here and no scene on this engine can make it fail by
--   role. The failure before the fix is shown by 0489's own self-assert where the engine is 17: the disposable chain on CI and prod's
--   push (it requires 42501 there before the fix). This proof holds the PROPERTY that makes the fault impossible on any engine, and
--   plays one real press as `authenticated`, its deferred checks fired while still `authenticated`, as a commit would.
--
-- @pass PO_SHAPE   public.reputation_reconciles() is SECURITY DEFINER (owner postgres, search path public, pg_temp), both deferred triggers on it, no client or service_role execute; no deferrable trigger in public, world, cmd or voyage runs an invoker-rights function
-- @pass PO_SCENE   as `authenticated` with a player's jwt claims, cmd.captain_skill_up books its Reputation row, the deferred checks fire as `authenticated` and pass, and the house's book and balance reconcile
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_uid  constant uuid := '00000000-0192-4000-8000-000000000001';
  c_fn   constant regprocedure := 'public.reputation_reconciles()'::regprocedure;
  v_p    uuid;
  v_r    jsonb;
  v_bal0 int;
  v_bal  int;
  v_seq  int;
  v_rows int;
  v_bad  text;
  v_role text;
  v_was  text := current_user;
begin
  -- ══ PO_SHAPE ══
  if not (select p.prosecdef from pg_proc p where p.oid = c_fn)
     or (select p.proconfig::text from pg_proc p where p.oid = c_fn) is distinct from '{"search_path=public, pg_temp"}'
     or (select pg_get_userbyid(p.proowner) from pg_proc p where p.oid = c_fn) <> 'postgres' then
    raise exception 'PO_SHAPE: public.reputation_reconciles() is not SECURITY DEFINER, owner postgres, search path public, pg_temp';
  end if;
  if (select count(*) from pg_trigger t where t.tgfoid = c_fn and not t.tgisinternal and t.tgdeferrable and t.tginitdeferred
         and t.tgrelid in ('public.reputation_book'::regclass, 'public.reputation_balance'::regclass)) <> 2 then
    raise exception 'PO_SHAPE: the two deferred reputation_reconciles triggers are not on it';
  end if;
  select string_agg(distinct t.tgrelid::regclass::text || ' ' || t.tgname || ' -> ' || t.tgfoid::regprocedure::text, ', ') into v_bad
    from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace join pg_proc f on f.oid = t.tgfoid
   where not t.tgisinternal and t.tgdeferrable and not f.prosecdef and n.nspname in ('public', 'world', 'cmd', 'voyage');
  if v_bad is not null then
    raise exception 'PO_SHAPE: a deferrable trigger runs an invoker-rights function (on PostgreSQL 17 it runs as the committing client role): %', v_bad;
  end if;
  if has_function_privilege('anon', c_fn, 'execute') or has_function_privilege('authenticated', c_fn, 'execute')
     or has_function_privilege('service_role', c_fn, 'execute') then
    raise exception 'PO_SHAPE: a client role or service_role may execute public.reputation_reconciles()';
  end if;
  raise notice 'PASS: PO_SHAPE — public.reputation_reconciles() SECURITY DEFINER, owner postgres, search path public, pg_temp, revoked from anon, authenticated and service_role; its 2 deferred triggers on it; % deferrable trigger(s) in public, world, cmd and voyage, every one on a SECURITY DEFINER function',
    (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
      where not t.tgisinternal and t.tgdeferrable and n.nspname in ('public', 'world', 'cmd', 'voyage'));

  -- ══ PO_SCENE ══ (the switches this scene needs are set here, in this transaction, and go back with it)
  update public.world_config set value = 'true'::jsonb where key in ('crew_bite', 'reputation_on');
  v_p := public.new_house(c_uid, 'Casa da Prova 192', 'PRT');
  v_r := public.sign_officer(v_p, 'ELCANO', null);
  if not coalesce((v_r ->> 'ok')::boolean, false) then
    raise exception 'PO_SCENE: ELCANO''s signing was refused: %', v_r;
  end if;
  v_r := public.captain_traits_set_for(v_p, 'ELCANO', array['NAVIGATOR']);
  if not coalesce((v_r ->> 'ok')::boolean, false) then
    raise exception 'PO_SCENE: ELCANO''s skill was not set: %', v_r;
  end if;
  if public.reputation_credit(v_p, 'built', 1000, 'proof192:seed') <> 1000 then
    raise exception 'PO_SCENE: the seed was not booked';
  end if;
  -- the seed's checks fire now, as this proof's role, so what fires below as `authenticated` is the press's own
  set constraints public.reputation_reconciles immediate;
  set constraints public.reputation_reconciles deferred;
  v_bal0 := (select b.balance from public.reputation_balance b where b.player_id = v_p);

  perform cmd.assume_identity(c_uid);
  set local role authenticated;
  v_role := current_user;
  v_r := cmd.captain_skill_up('elcano', 'navigator');
  set constraints public.reputation_reconciles immediate;   -- the press's deferred checks, fired as `authenticated`, as its commit would
  set constraints public.reputation_reconciles deferred;
  execute format('set local role %I', v_was);   -- by name, never `reset role` (it drops to the session's login role)
  if v_role <> 'authenticated' then
    raise exception 'PO_SCENE: the press did not run as authenticated (%)', v_role;
  end if;
  if (v_r ->> 'ok')::boolean is not true or (v_r ->> 'cost')::int <> 50 then
    raise exception 'PO_SCENE: the press was refused or did not cost 50: %', v_r;
  end if;
  select b.balance, b.seq into v_bal, v_seq from public.reputation_balance b where b.player_id = v_p;
  select count(*) into v_rows from public.reputation_book k where k.player_id = v_p;
  if v_bal <> v_bal0 - 50 or v_rows <> v_seq or v_seq <> 2
     or not exists (select 1 from public.reputation_book k where k.player_id = v_p and k.seq = v_seq and k.balance_after = v_bal and k.kind = 'skill' and k.delta = -50) then
    raise exception 'PO_SCENE: the book and the balance do not reconcile: balance % (was %), seq %, rows %', v_bal, v_bal0, v_seq, v_rows;
  end if;
  raise notice 'PASS: PO_SCENE — as authenticated (claims of a probe house), cmd.captain_skill_up(ELCANO, NAVIGATOR) booked -50; its deferred checks fired as authenticated and passed; balance % -> %, book rows 1..% chained, the newest its balance (server %: this engine could not have failed before the fix; 0489''s self-assert shows that on 17)',
    v_bal0, v_bal, v_seq, current_setting('server_version');
end $p$;
