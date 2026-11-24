-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (a fault fix: a press that earned or spent Reputation failed for signed-in players; nothing new is told)
-- 0489 - REPUTATION IS CHECKED AS ITS OWNER  (no switch; a fault fix: public.reputation_reconciles() becomes SECURITY DEFINER)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE WORK: docs/dev-log/2026-11-24-reputation-deferred-trigger.md; harness scripts/ops/harness/reputation/ (before-0489.sql,
--   after-0489.sql); proof 192 (scripts/db/proofs/192_reputation_is_checked_as_its_owner.sql).
--
-- THE FAULT (the owner, a player, on the live game: "permission denied for table reputation_balance", again and again).
--   0352 made public.reputation_reconciles() the function of two CONSTRAINT TRIGGERS, DEFERRABLE INITIALLY DEFERRED: after insert on
--   public.reputation_book and after insert or update of balance, seq on public.reputation_balance. It is plpgsql, owner postgres, and
--   NOT security definer (invoker rights); it SELECTs public.reputation_balance and public.reputation_book, which only postgres and
--   service_role may read (RLS on, no policy). A deferred trigger runs at COMMIT. Prod runs PostgreSQL 17.6, which runs it as the role
--   current AT COMMIT: for a signed-in player's request that is `authenticated`, not the SECURITY DEFINER door (owner postgres) that wrote
--   the row and queued the trigger. So every transaction of a signed-in player that writes a Reputation book row (an earn or a spend)
--   failed at commit with 42501 and rolled back WHOLE: the press, the sale, the arrival settled inside a read. Merchant houses write none
--   (public.reputation_credit leaves at the players probe) and the cron runs as postgres, so nothing else ever showed it.
--   PostgreSQL 18 runs a deferred trigger as the role that queued it; PGlite (every local proof and the pglite-gate) is 18.3, which is
--   why no proof saw it. The disposable chain is 17 (supabase/config.toml [db].major_version), and this file's probe shows the fault there.
--   Prod's catalog (before-0489.sql, 2026-11-24): these two are the ONLY deferrable triggers in public, world, cmd and voyage whose
--   function is not SECURITY DEFINER (public.ledger and public.players' reconcile triggers already are).
--
-- WHAT (DECIDED BY DEFAULT; the owner may reverse it):
--   alter function public.reputation_reconciles() security definer set search_path = public, pg_temp   (the house style of its
--   neighbours, public.reputation_credit and the rest of 0352: the same proconfig, asserted). The body is not touched (md5 before and
--   after, asserted); the owner stays postgres, so the check reads both tables as their owner, whoever commits. Its EXECUTE is revoked
--   from public, anon, authenticated AND service_role (prod's default privilege had granted service_role at 0352; a trigger function
--   is never called as a statement, so no caller loses anything). No switch, knob, table, row or other function moves.
--
-- THE SELF-ASSERT (one DO block; the probe rolled back by a raised sentinel). Budget 30 s.
--   THE PROBE: a probe house (public.new_house) signed in by its jwt claims (cmd.assume_identity); reputation_on lit for the probe only
--   where it is not already on (on prod it is). THE SCENE, run twice, each in its own subtransaction: as role `authenticated`, a door
--   shaped like every door that earns (pg_temp, SECURITY DEFINER, owner the migrating role: public.current_player_id() then
--   public.reputation_credit) books 40, then `set constraints public.reputation_reconciles immediate` fires the queued checks STILL AS
--   `authenticated`, as a commit would. BEFORE the fix (0352's function): on an engine before 18 it MUST fail 42501 on
--   reputation_balance (the fault, reproduced; on prod this is the push itself showing it); on 18 or later it must pass (the engine runs
--   it as the queuing role). AFTER the fix (tried inside the probe): it must pass on every engine, and the probe house's book and
--   balance reconcile (its balance is its newest row's balance_after, its rows chained 1..n).
--   THE CATALOG, after the fix for real: SECURITY DEFINER, the search path of public.reputation_credit, owner postgres, the body's md5
--   as found; both triggers there, deferrable, initially deferred, on it; NO deferrable trigger in public, world, cmd or voyage has a
--   function without SECURITY DEFINER; no client role, service_role or public may execute it; no other function moved; 0 client write grants.
-- ROLLBACK (forward, not expected): `alter function public.reputation_reconciles() security invoker reset search_path` brings the fault back.
-- VERSION: 0489, prod head 0488.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. THE PROBE'S DOOR (pg_temp: this session's alone, dropped at the end of the file) ──
create function pg_temp.earn_0489(p_key text)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
begin
  return public.reputation_credit(public.current_player_id(), 'built', 40, 'probe0489:' || p_key, '{}'::jsonb);
end
$body$;
grant execute on function pg_temp.earn_0489(text) to authenticated;

-- THE SCENE: as `authenticated`, earn, then fire the deferred checks still as `authenticated`. 'ok' or '<sqlstate>: <message>'.
create function pg_temp.scene_0489(p_uid uuid, p_key text)
returns text
language plpgsql
as $body$
declare
  v_got int;
begin
  perform cmd.assume_identity(p_uid);
  set local role authenticated;
  v_got := pg_temp.earn_0489(p_key);
  set constraints public.reputation_reconciles immediate;
  set constraints public.reputation_reconciles deferred;
  reset role;
  if v_got is distinct from 40 then
    return 'booked ' || coalesce(v_got::text, 'null') || ', not 40';
  end if;
  return 'ok';
exception when others then
  return sqlstate || ': ' || sqlerrm;
end
$body$;

do $m$
declare
  c_uid      constant uuid := '00000000-0489-4000-8000-000000000001';
  c_fn       constant regprocedure := 'public.reputation_reconciles()'::regprocedure;
  c_md5      constant text := '3d25b3b1ff9d7eea7b6d9d92544c4d34';   -- 0352's body, as prod holds it (before-0489.sql)
  v_t0       timestamptz := clock_timestamp();
  v_user     text := current_user;
  v_fn_before text;
  v_p        uuid;
  v_lit      boolean := false;
  v_pre      text;
  v_post     text;
  v_bal      int;
  v_seq      int;
  v_rows     int;
  v_lived    boolean := false;
  v_bad      text;
begin
  perform set_config('statement_timeout', '60s', true);
  -- ── 1. GUARD: the function and the two triggers are 0352's, as found ──
  if (select p.prosecdef from pg_proc p where p.oid = c_fn) then
    raise exception '0489 refuses: public.reputation_reconciles() is already SECURITY DEFINER';
  end if;
  if (select md5(replace(p.prosrc, E'\r', '')) from pg_proc p where p.oid = c_fn) <> c_md5 then
    raise exception '0489 refuses: public.reputation_reconciles() is not the body this file was written against';
  end if;
  if (select count(*) from pg_trigger t where t.tgfoid = c_fn and not t.tgisinternal and t.tgdeferrable and t.tginitdeferred
         and t.tgname = 'reputation_reconciles' and t.tgrelid in ('public.reputation_book'::regclass, 'public.reputation_balance'::regclass)) <> 2 then
    raise exception '0489 refuses: the two deferred reputation_reconciles triggers are not as 0352 made them';
  end if;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_fn;

  -- ── 2. THE PROBE, rolled back by a raised sentinel ──
  begin
    if public.wc('reputation_on') is distinct from 'true'::jsonb then
      update public.world_config set value = 'true'::jsonb where key = 'reputation_on';
      v_lit := true;
    end if;
    v_p := public.new_house(c_uid, 'Casa da Prova 0489', 'PRT');
    -- whatever the house's founding queued is checked now, as the migrating role, so the scenes fire only their own
    set constraints public.reputation_reconciles immediate;
    set constraints public.reputation_reconciles deferred;

    v_pre := pg_temp.scene_0489(c_uid, 'pre');
    if current_setting('server_version_num')::int < 180000 then
      if v_pre not like '42501: %reputation_balance%' then
        raise exception '0489 self-assert FAIL: on PostgreSQL % the fault did not reproduce before the fix (expected 42501 on reputation_balance): %',
          current_setting('server_version'), v_pre;
      end if;
    elsif v_pre <> 'ok' then
      raise exception '0489 self-assert FAIL: on PostgreSQL % (a deferred trigger runs as the role that queued it) the scene failed before the fix: %',
        current_setting('server_version'), v_pre;
    end if;

    alter function public.reputation_reconciles() security definer set search_path = public, pg_temp;
    v_post := pg_temp.scene_0489(c_uid, 'post');
    if v_post <> 'ok' then
      raise exception '0489 self-assert FAIL: as authenticated, an earn and its deferred check failed after the fix: %', v_post;
    end if;
    -- the probe house's own rows reconcile: the balance is the newest row's, and the rows are chained 1..n
    select b.balance, b.seq into v_bal, v_seq from public.reputation_balance b where b.player_id = v_p;
    select count(*) into v_rows from public.reputation_book k where k.player_id = v_p;
    if v_seq is null or v_rows <> v_seq or v_bal <> 40 * (case when v_pre = 'ok' then 2 else 1 end)
       or not exists (select 1 from public.reputation_book k where k.player_id = v_p and k.seq = v_seq and k.balance_after = v_bal)
       or exists (select 1 from public.reputation_book k where k.player_id = v_p and k.key = 'probe0489:pre') is distinct from (v_pre = 'ok') then
      raise exception '0489 self-assert FAIL: the probe house''s book and balance do not reconcile: balance %, seq %, rows %, pre %', v_bal, v_seq, v_rows, v_pre;
    end if;
    raise exception using errcode = 'ZX489', message = 'PROBE_ROLLBACK_0489';
  exception when sqlstate 'ZX489' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0489 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.auth_uid = c_uid) or (select p.prosecdef from pg_proc p where p.oid = c_fn)
     or current_user <> v_user then
    raise exception '0489 self-assert FAIL: the probe left something behind';
  end if;

  -- ── 3. THE FIX, for real ──
  alter function public.reputation_reconciles() security definer set search_path = public, pg_temp;
  revoke all on function public.reputation_reconciles() from public, anon, authenticated, service_role;

  -- ── 4. SELF-ASSERT: the catalog ──
  if not (select p.prosecdef from pg_proc p where p.oid = c_fn)
     or (select p.proconfig from pg_proc p where p.oid = c_fn) is distinct from
        (select p.proconfig from pg_proc p where p.oid = 'public.reputation_credit(uuid,text,int,text,jsonb)'::regprocedure)
     or (select p.proconfig::text from pg_proc p where p.oid = c_fn) is distinct from '{"search_path=public, pg_temp"}'
     or (select pg_get_userbyid(p.proowner) from pg_proc p where p.oid = c_fn) <> 'postgres'
     or (select md5(replace(p.prosrc, E'\r', '')) from pg_proc p where p.oid = c_fn) <> c_md5 then
    raise exception '0489 self-assert FAIL: public.reputation_reconciles() is not SECURITY DEFINER, owner postgres, search path public, pg_temp, with 0352''s body';
  end if;
  if (select count(*) from pg_trigger t where t.tgfoid = c_fn and not t.tgisinternal and t.tgdeferrable and t.tginitdeferred
         and t.tgname = 'reputation_reconciles' and t.tgrelid in ('public.reputation_book'::regclass, 'public.reputation_balance'::regclass)) <> 2 then
    raise exception '0489 self-assert FAIL: the two deferred reputation_reconciles triggers moved';
  end if;
  select string_agg(distinct t.tgrelid::regclass::text || ' ' || t.tgname || ' -> ' || t.tgfoid::regprocedure::text, ', ') into v_bad
    from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace join pg_proc f on f.oid = t.tgfoid
   where not t.tgisinternal and t.tgdeferrable and not f.prosecdef and n.nspname in ('public', 'world', 'cmd', 'voyage');
  if v_bad is not null then
    raise exception '0489 self-assert FAIL: a deferrable trigger runs a function without SECURITY DEFINER (it would run as the committing client role): %', v_bad;
  end if;
  if has_function_privilege('anon', c_fn, 'execute') or has_function_privilege('authenticated', c_fn, 'execute')
     or (exists (select 1 from pg_roles r where r.rolname = 'service_role') and has_function_privilege('service_role', c_fn, 'execute'))
     or exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = c_fn and a.grantee = 0) then
    raise exception '0489 self-assert FAIL: a client role, service_role or public may execute public.reputation_reconciles()';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_fn) is distinct from v_fn_before then
    raise exception '0489 self-assert FAIL: another function moved, or one more was added';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0489 self-assert FAIL: a client write grant appeared';
  end if;

  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0489 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0489 self-assert ok: REPUTATION IS CHECKED AS ITS OWNER. public.reputation_reconciles() is SECURITY DEFINER (owner postgres, search path public, pg_temp, as public.reputation_credit), its body 0352''s (md5 as found), revoked from public, anon, authenticated and service_role; both deferred triggers on it; no deferrable trigger in public, world, cmd or voyage runs an invoker-rights function; no other function moved. Probe (rolled back; reputation_on lit for it: %), on PostgreSQL %: as authenticated, an earn and its deferred check BEFORE the fix: %; AFTER: %, the book and balance reconciled. % ms.',
    v_lit, current_setting('server_version'),
    case when v_pre = 'ok' then 'ok (this engine runs a deferred trigger as the role that queued it)' else v_pre end,
    v_post, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;

drop function pg_temp.scene_0489(uuid, text);
drop function pg_temp.earn_0489(text);
