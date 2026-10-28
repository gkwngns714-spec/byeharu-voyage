-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0268 — THE SWITCH READS THE WORLD WITH NO COIN IN FLIGHT  (economy_close_switch takes the quay and the
--        mint gate before it reads the flag and the total; mint_guard holds the gate, shared, before it
--        reads the flag)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE BUG, MEASURED (prod, read-only, head 0267, 2026-10-28 12:22 UTC) ─────────────────────────
-- economy_closed_total = 1,986,693,521 (stamped 2026-10-26 06:52:21.857924 UTC); world.stats_now() total =
-- 1,986,693,659: +138, the whole of what has moved since the close. The 138 is one IMPORT_DEMAND premium
-- (cmd.do_sell, 0174 :184-186) of a sale that ran under the OPEN rules and committed after the switch read
-- its total. Owner: the 138 and economy_closed_total stay as they are; fix the race only.
-- WHY IT COULD HAPPEN (0240):
--   * economy_close_switch takes NO lock. It reads economy_closed() in its DECLARE (0240 :354) and the world
--     total at :368, then flips the flag. A beat (or a player's sale) that started before the flip and
--     commits after the reading has its new money outside the stamp.
--   * mint_guard is STABLE (0240 :239). A STABLE plpgsql function runs on its caller's snapshot, so even a
--     sale that asks the guard after the flip committed is judged by the flag as it stood when the calling
--     statement began.
--
-- ── WHAT THIS FILE DOES (supersedes two 0240 bodies whole; re-cuts nothing else) ─────────────────
-- (1) NEW public.mint_gate(exclusive): THE mint gate, one transaction-scoped advisory lock
--     (hashtextextended('byeharu.mint_gate', 268)). Shared: a writer about to make new money. Exclusive: the
--     switch. One authority of the key, as public.hold_the_quay() (0249) and public.treasury_lock (0123) are.
-- (2) public.mint_guard SUPERSEDED (same signature, ACL, definer, config; STABLE → VOLATILE): a positive delta
--     of a minted kind first takes the gate SHARED (held to the commit), then reads the flags — in a NEW
--     statement, so on a NEW snapshot taken after the gate is held. The decision is 0240's, unchanged:
--     refused (E_NO_NEW_GOLD) iff delta > 0, the kind is minted, economy_closed() and city_treasury_on().
-- (3) public.economy_close_switch SUPERSEDED (same signature, ACL, definer, config): FIRST the quay
--     (public.hold_the_quay), THEN the gate EXCLUSIVE, and only then every reading — the flag (it left the
--     DECLARE), the total, the purses, the knobs. The rows it writes are locked NOWAIT before they are written
--     (the three economy_* knobs; the harbours whose `invested` is still null), so after the gate it never
--     waits. Everything it writes and answers is 0240's.
--
-- ── WHY BOTH LOCKS (the existing lock design, checked) ───────────────────────────────────────────
-- The quay alone does not fit: it is taken by the arrivals beat, the hourly tend / companies steps and the
-- lap-open step only (0249, 0265, 0266, 0267). A PLAYER's sale (cmd.do_sell from cmd.issue), a sign-up's
-- FOUNDING and the city tick's EARNINGS (public.city_day, pg_cron :37) mint without it. So the race is closed
-- at THE GUARD, which every new coin passes (public.credit and public.treasury_post, the two money writers):
-- the gate. The quay is taken as well, first, because it is the beats' own serialiser: with the quay, no beat
-- is ever cut by the flip — a beat that began open commits whole before the switch reads, and the next beat
-- reads the closed flag from its first statement. Without it, a beat that had not yet minted when the gate
-- closed would block at its first mint and then be refused there.
-- AFTER THE SWITCH HOLDS BOTH: every writer that could still mint under the open rules has committed (the
-- quay's beats, by the quay; everyone else, by the gate's shared holders), so the total it reads holds every
-- coin made open. Every mint that comes after waits at the gate until the switch commits, then reads the
-- flag on a snapshot taken after that commit — the closed rules. Stamped total = the real total.
--
-- ── NO NEW DEADLOCK, BY CONSTRUCTION (the lock order 0265 / 0267 proved is kept: quay first) ─────
-- A deadlock is a cycle of waits; a transaction that holds nothing while it waits is on no cycle.
--   * THE SWITCH waits at two places only: for the quay, holding nothing; for the gate, holding only the
--     quay. After the gate every row lock it takes is NOWAIT (a busy row is an error, 55P03, the switch rolls
--     back whole and is asked again — it never waits), it inserts one events row (a fresh uuid: no key to
--     wait on), and its reads take no row lock (asserted below on its body; the triggers it fires are
--     asserted to be only world_config's time_compression trigger, which its keys never satisfy).
--   * A cycle through the switch's GATE wait needs a gate holder that waits, directly or through others, for
--     the QUAY. Every writer that takes the quay takes it FIRST in its transaction (the beat after its commit,
--     each tend / company step after its commit, lap_start_open as its first statement: 0249 / 0265 / 0266 /
--     0267, the takers asserted below to be those plus this switch). A quay taker therefore holds no gate when
--     it asks for the quay, and a transaction that holds the gate never asks for the quay. Nothing else waits
--     for a lock the switch holds (it holds only the quay and the gate, and the three knob rows / null harbours
--     taken NOWAIT, which no minter holds-and-waits on: they are written only by this switch, city_day,
--     restock / depth / invested rolls, and city_treasury_switch).
--   * THE GATE's SHARED holders never wait for one another (shared ⟂ shared). A shared request re-asked inside
--     its own transaction is granted at once (the lock is already held). A NEW shared request that queues
--     behind the switch's exclusive request while it holds a row an earlier holder wants is a SOFT edge: the
--     lock manager's deadlock check reorders the queue (shared before the waiting exclusive) and nothing
--     aborts; the cost is at most deadlock_timeout (1 s, prod) once per flip, and the switch is flipped by the
--     owner, by hand.
--   * THE MINTERS' own order is unchanged: house row (credit), harbour lock (treasury_post's outflows), then
--     the gate inside the guard — the gate is the LAST lock of an act and is never waited for while the
--     economy is not being switched (no exclusive holder exists).
--
-- ── RESULTS ARE BYTE-IDENTICAL WHEN NOTHING FLIPS ───────────────────────────────────────────────
-- (b) below: the OLD guard (run before anything is replaced) and the NEW guard answer the same for every
-- flow kind (+ a moved kind and an unknown one) × delta (−7, 0, 7, null) × (closed, purses) in all four states.
-- The switch, old and new, from the same state: asked for what is (no change), flipped, flipped back, asked
-- again — the same answers, events, knobs and `invested` (the totals excepted: on prod the world moves between
-- the two runs; each run's total is checked against its own stamp).
--
-- ── WHAT IT SELF-ASSERTS (every probe a rolled-back sub-transaction; nothing a probe flips is committed) ─
--   (a) credit, treasury_post, city_pays, cmd.do_sell, hold_the_quay, economy_closed, world.stats_now,
--       emit_event unmoved (md5); the two superseded functions keep ACL / definer / config; the guard is
--       VOLATILE; mint_gate server-only; registry unchanged; walls 0.
--   (b) old guard = new guard, every verdict (above); old switch = new switch (above), as the world is and
--       with the purses lit.
--   (c) THE ORDER, on the bodies (comments stripped): the switch takes the quay, then the gate exclusive, then
--       reads the flag, then the total; no reading before the locks; exactly two lock clauses, both NOWAIT; the
--       guard takes the gate shared before it reads the flag. The quay's takers are the old set plus the
--       switch; the gate's takers are the guard and the switch; the guard's callers are credit and
--       treasury_post, as before; the triggers on the switch's tables are the two known.
--   (d) AN IN-FLIGHT MINT ACROSS A FLIP (open, purses lit): an IMPORT_DEMAND of 777 at Lisbon (the 138's kind,
--       as do_sell posts it) is made and NOT committed; the gate is then held shared and the quay not at all.
--       The switch closes: it holds the quay and the gate exclusive; its stamp = its answer's total, and lies
--       between the totals read just before and just after it (one session: all three equal, the 777 inside);
--       the next IMPORT_DEMAND is refused (E_NO_NEW_GOLD) — the flag the switch wrote, read through the gate.
--       After the rollback this transaction holds neither lock.
--   The cross-session interleaving itself (a second backend's sale in flight while the switch waits) cannot run
--   in one migration transaction; it rests on the construction above and the order asserted in (c).
--
-- ── ROLLBACK (forward) ─────────────────────────────────────────────────────────────────────────
-- Re-create 0240's mint_guard (STABLE) and economy_close_switch bodies verbatim (0240 §3, §5); drop mint_gate.
--
-- VERSION: 0268 (prod head 0267 when cut). Superseded bodies cut from 0240, md5-checked equal to prod's at
-- head 0267 (mint_guard 6c6c5199…, economy_close_switch 0dea1b67…), LF-normalised.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '5min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.mint_guard(text,bigint)') is null or to_regprocedure('public.economy_close_switch(boolean)') is null
     or to_regprocedure('public.hold_the_quay()') is null or to_regprocedure('public.lap_start_open(uuid)') is null then
    raise exception '0268 refuses: 0240 (the guard and the switch), 0249 (the quay) or 0266 is not in this world';
  end if;
  if to_regprocedure('public.mint_gate(boolean)') is not null then
    raise exception '0268 refuses: it has been applied once';
  end if;
  if md5(replace(pg_get_functiondef('public.mint_guard(text,bigint)'::regprocedure), E'\r', '')) <> '6c6c5199da7aa5233b645334573b35e6'
     or md5(replace(pg_get_functiondef('public.economy_close_switch(boolean)'::regprocedure), E'\r', '')) <> '0dea1b674be08c5c7cbbe74ec18cebcf' then
    raise exception '0268 refuses: the guard or the switch is not the body 0240 wrote (this file supersedes exactly those)';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0268(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- a body without its comments, lower case (a comment may name what the code must not do)
create or replace function pg_temp.code_0268(p_fn text)
returns text
language sql
as $$ select lower(regexp_replace(replace(pg_get_functiondef(p_fn::regprocedure), E'\r', ''), '--[^\n]*', '', 'g')) $$;

-- the modes this backend holds on one advisory bigint key
create or replace function pg_temp.held_0268(p_key bigint)
returns text
language sql
as $$
  select coalesce(string_agg(l.mode, ',' order by l.mode), '')
    from pg_locks l
   where l.locktype = 'advisory' and l.pid = pg_backend_pid() and l.granted
     and l.classid = ((p_key >> 32) & 4294967295)::bigint::oid
     and l.objid = (p_key & 4294967295)::bigint::oid
     and l.objsubid = 1
$$;

-- ── 0. THE PRE-IMAGES ───────────────────────────────────────────────────────────────────────────
create temp table before_0268 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select string_agg(f.fn || '=' || md5(replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '')), ',' order by f.fn)
          from (values ('public.credit(uuid,text,bigint,uuid)'), ('public.treasury_post(uuid,text,bigint,uuid,uuid,boolean)'),
                       ('public.city_pays(uuid,uuid,text,bigint,uuid)'), ('cmd.do_sell(uuid,jsonb)'), ('public.hold_the_quay()'),
                       ('public.economy_closed()'), ('world.stats_now()'), ('public.emit_event(uuid,text,jsonb)')) f(fn)) as kept_md5,
       (select string_agg(f.fn || '=' || coalesce(p.proacl::text, '') || '|' || p.prosecdef || '|' || coalesce(p.proconfig::text, ''), ',' order by f.fn)
          from (values ('public.mint_guard(text,bigint)'), ('public.economy_close_switch(boolean)')) f(fn)
          join pg_proc p on p.oid = f.fn::regprocedure) as posture,
       (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%'
           and p.prokind in ('f', 'p') and p.prosrc like '%hold_the_quay()%') as quay_takers,
       (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%'
           and p.prokind in ('f', 'p') and p.prosrc like '%mint_guard(%') as guard_callers,
       (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR') as lis;

-- ── 1. THE PROBES (run once through the OLD bodies here, once through the NEW below) ────────────
-- THE GUARD's verdicts: every flow kind, a moved kind and an unknown one, four deltas, in all four states of
-- (closed, purses lit). Rolled back; answers {state|kind|delta: 'ok' | sqlstate + message}.
create or replace function pg_temp.verdicts_0268()
returns jsonb
language plpgsql
as $$
declare
  v     jsonb := '{}'::jsonb;
  s     record;
  k     text;
  d     bigint;
  v_key text;
begin
  begin
    for s in select c, t from (values (false, false), (false, true), (true, false), (true, true)) x(c, t) loop
      update public.world_config set value = to_jsonb(s.c) where key = 'economy_closed';
      update public.world_config set value = to_jsonb(s.t) where key = 'city_treasury_enabled';
      for k in select w.kind from public.stats_flow_words w union select 'BUY' union select 'PROBE_0268' order by 1 loop
        foreach d in array array[-7, 0, 7, null]::bigint[] loop
          v_key := s.c || '/' || s.t || '|' || k || '|' || coalesce(d::text, 'null');
          begin
            perform public.mint_guard(k, d);
            v := v || jsonb_build_object(v_key, 'ok');
          exception when others then
            v := v || jsonb_build_object(v_key, sqlstate || ' ' || sqlerrm);
          end;
        end loop;
      end loop;
    end loop;
    raise exception using errcode = 'ZY268', message = v::text;
  exception when sqlstate 'ZY268' then
    return sqlerrm::jsonb;
  end;
end $$;

-- one ask of the switch: its answer and its event (the totals apart — checked against its own stamp)
create or replace function pg_temp.ask_0268(p_on boolean)
returns jsonb
language plpgsql
as $$
declare
  x  jsonb;
  ev jsonb;
begin
  begin
    x := public.economy_close_switch(p_on);
  exception when others then
    return jsonb_build_object('refused', sqlstate || ' ' || sqlerrm);
  end;
  select e.payload into ev from public.events e where e.id = (x->>'event')::uuid;
  return jsonb_build_object(
    'answer', x - 'event' - 'world_total',
    'event', ev - 'world_total' - 'total_moved',
    'an_event', (x->>'event') is null or ev is not null,
    'stamp_is_its_total', case when public.economy_closed() and (x->>'changed')::boolean
                               then public.wc('economy_closed_total') = x->'world_total'
                                    and ev->'world_total' = x->'world_total' end,
    'knobs', jsonb_build_object('closed', public.wc('economy_closed'), 'at', public.wc('economy_closed_at'),
                                'total_set', jsonb_typeof(public.wc('economy_closed_total'))),
    'invested', (select jsonb_build_array(count(*) filter (where t.invested is null), coalesce(sum(t.invested), 0))
                   from public.port_treasury t));
end $$;

-- THE SWITCH from the world as it is (p_lit: the purses lit first): asked for what is, flipped, flipped back,
-- asked again. Rolled back.
create or replace function pg_temp.switch_0268(p_lit boolean)
returns jsonb
language plpgsql
as $$
declare
  s0 boolean;
  r  jsonb;
begin
  begin
    if p_lit then
      update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
    end if;
    s0 := public.economy_closed();
    r := jsonb_build_object('s0', s0, 'noop', pg_temp.ask_0268(s0));
    r := r || jsonb_build_object('flip', pg_temp.ask_0268(not s0));
    r := r || jsonb_build_object('back', pg_temp.ask_0268(s0));
    r := r || jsonb_build_object('again', pg_temp.ask_0268(s0));
    raise exception using errcode = 'ZY268', message = r::text;
  exception when sqlstate 'ZY268' then
    return sqlerrm::jsonb;
  end;
end $$;

create temp table old_0268 on commit drop as
select pg_temp.verdicts_0268() as verdicts, pg_temp.switch_0268(false) as switch_as_is, pg_temp.switch_0268(true) as switch_lit;

-- ── 2. THE MINT GATE ────────────────────────────────────────────────────────────────────────────
create function public.mint_gate(p_exclusive boolean)
returns void
language plpgsql
volatile
as $$
-- 0268: THE mint gate, held to the end of the transaction. SHARED: a writer about to make new money (public.mint_guard,
-- for a positive minted kind). EXCLUSIVE: public.economy_close_switch, so the world total it reads holds every coin made
-- under the rules it is changing, and every coin after it is judged by the rules it wrote. The one authority of the key.
begin
  if p_exclusive then
    perform pg_advisory_xact_lock(hashtextextended('byeharu.mint_gate', 268));
  else
    perform pg_advisory_xact_lock_shared(hashtextextended('byeharu.mint_gate', 268));
  end if;
end $$;
comment on function public.mint_gate(boolean) is
  '0268: THE mint gate (advisory, to the end of the transaction): shared by mint_guard for a positive minted kind, exclusive by economy_close_switch, which takes it after the quay and before it reads the flag or the total. Server-only.';
revoke all on function public.mint_gate(boolean) from public, anon, authenticated;

-- ── 3. THE GUARD (supersedes 0240 §3; VOLATILE: it reads the flag on a snapshot taken after the gate) ─
create or replace function public.mint_guard(p_kind text, p_delta bigint)
returns void
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
-- 0240 (docs/CLOSED_ECONOMY.md §0.2, §8 E7): NO NEW GOLD. THE one judge, asked by the two money writers (public.credit,
-- public.treasury_post) for a positive delta: while the economy is closed (and the purses lit — 0234's founding_credit
-- test), a MINTED kind (public.stats_flow_words.side = 'minted') is refused, E_NO_NEW_GOLD. Open: nothing, ever.
-- A city that pays (public.city_pays) is not asked: its credit is money moved, not made.
-- 0268: a positive minted kind first holds THE MINT GATE, shared, to the commit (public.mint_gate), and only then reads
-- the flags — in a new statement of a VOLATILE function, so on a snapshot taken after the gate is held. The switch takes
-- the gate exclusive before it reads the world total: a coin made under the open rules is inside its stamp, and a coin
-- asked for after the flip is judged by the flag the switch wrote. (0240's guard was STABLE: it read the caller's
-- snapshot, and a sale in flight across the flip minted 138 past the stamp on 2026-10-26.) The verdict is 0240's.
begin
  if coalesce(p_delta, 0) > 0
     and exists (select 1 from public.stats_flow_words w where w.kind = p_kind and w.side = 'minted') then
    perform public.mint_gate(false);
    if public.economy_closed() and public.city_treasury_on() then
      perform cmd.refuse('E_NO_NEW_GOLD',
        format('the economy is closed: no %s is made from nothing (%s d.) — a city must pay it', p_kind, p_delta),
        cmd.figures(0, p_delta, 'ducats'));
    end if;
  end if;
end $$;

-- ── 4. THE SWITCH (supersedes 0240 §5: the locks first, then every reading) ─────────────────────
create or replace function public.economy_close_switch(p_on boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0240 (docs/CLOSED_ECONOMY.md §6): THE one switch of the closed economy. Owner / service role only.
--   true:  refused while the city purses are dark (E_PURSES_DARK). Seeds port_treasury.invested = Σ city_shares.paid
--          where it is null (§3; a re-light keeps what E5 has rolled since). Records economy_closed_at = now() and
--          economy_closed_total = the world total this second (world.stats_now() `total`), flips economy_closed, and
--          writes ONE events row ECONOMY_SWITCH (no player: the world's own news).
--   false: economy_closed false, economy_closed_at / economy_closed_total null, ONE events row ECONOMY_SWITCH.
--          Money already moved stays where it is; `invested` stays (read by nothing while open).
--   Asked for what already is: {changed: false}, nothing written. No money moves either way.
-- The drift knobs of §6 are not this switch's: they ride with E6 (0240's header says why).
-- 0268: THE LOCKS FIRST, THEN EVERY READING. The quay (public.hold_the_quay: no arrivals beat, tend, company or lap-open
-- step is half done), then THE MINT GATE exclusive (public.mint_gate: every other writer that made new money under the
-- rules being changed has committed; every one after waits here and is judged by the flag written here). Only then the
-- flag, the total, the purses and the knobs are read, each on a snapshot taken after both locks. The rows written are
-- locked NOWAIT first (a busy row raises 55P03 and the switch is asked again), so after the gate it never waits.
declare
  v_was    boolean;
  v_total  bigint;
  v_n      int := 0;
  v_inv    bigint;
  v_ev     uuid;
  v_at     jsonb;
  v_atotal jsonb;
  v_ports  uuid[];
begin
  if p_on is null then
    raise exception 'economy_close_switch(): say true (close) or false (open)';
  end if;
  perform public.hold_the_quay();
  perform public.mint_gate(true);
  v_was := public.economy_closed();
  if p_on = v_was then
    return jsonb_build_object('closed', v_was, 'changed', false);
  end if;
  perform 1 from public.world_config c
   where c.key in ('economy_closed', 'economy_closed_at', 'economy_closed_total')
   for no key update nowait;
  v_total := (world.stats_now()->>'total')::bigint;
  if p_on then
    if not public.city_treasury_on() then
      perform cmd.refuse('E_PURSES_DARK',
        'the city purses are dark — light them (public.city_treasury_switch) before the economy is closed');
    end if;
    select coalesce(array_agg(x.port_id), '{}') into v_ports
      from (select t.port_id from public.port_treasury t where t.invested is null order by t.port_id
            for no key update nowait) x;
    update public.port_treasury t
       set invested = coalesce((select sum(s.paid) from public.city_shares s where s.port_id = t.port_id), 0)
     where t.port_id = any(v_ports) and t.invested is null;
    get diagnostics v_n = row_count;
    select coalesce(sum(t.invested), 0) into v_inv from public.port_treasury t;
    update public.world_config set value = 'true'::jsonb where key = 'economy_closed';
    update public.world_config set value = to_jsonb(now()) where key = 'economy_closed_at';
    update public.world_config set value = coalesce(to_jsonb(v_total), 'null'::jsonb) where key = 'economy_closed_total';
    v_ev := public.emit_event(null, 'ECONOMY_SWITCH', jsonb_build_object(
              'closed', true, 'at', now(), 'world_total', v_total, 'invested_seeded', v_n, 'invested', v_inv));
  else
    v_at := public.wc('economy_closed_at');
    v_atotal := public.wc('economy_closed_total');
    update public.world_config set value = 'false'::jsonb where key = 'economy_closed';
    update public.world_config set value = 'null'::jsonb where key in ('economy_closed_at', 'economy_closed_total');
    v_ev := public.emit_event(null, 'ECONOMY_SWITCH', jsonb_build_object(
              'closed', false, 'at', now(), 'world_total', v_total, 'closed_at', v_at, 'total_at_close', v_atotal,
              'total_moved', case when jsonb_typeof(v_atotal) = 'number' and v_total is not null
                                  then v_total - (v_atotal #>> '{}')::bigint end));
  end if;
  return jsonb_build_object('closed', public.economy_closed(), 'changed', true, 'world_total', v_total,
                            'invested_seeded', v_n, 'event', v_ev);
end $$;

-- ── 5. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  b        record;
  o        record;
  v_def    text;
  v_new    jsonb;
  v_gate   bigint := hashtextextended('byeharu.mint_gate', 268);
  v_quay   bigint := hashtextextended('byeharu.quay_or_upkeep', 249);
  v_p      int[];
  v_r      jsonb;
  v_flight jsonb;
  v_t0 bigint; v_t1 bigint; v_t2 bigint; v_s bigint;
  v_held1 text; v_held2q text; v_held2g text;
  v_after  text;
begin
  select * into b from before_0268;
  select * into o from old_0268;

  -- (a) WHAT STAYS
  if (select string_agg(f.fn || '=' || md5(replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '')), ',' order by f.fn)
        from (values ('public.credit(uuid,text,bigint,uuid)'), ('public.treasury_post(uuid,text,bigint,uuid,uuid,boolean)'),
                     ('public.city_pays(uuid,uuid,text,bigint,uuid)'), ('cmd.do_sell(uuid,jsonb)'), ('public.hold_the_quay()'),
                     ('public.economy_closed()'), ('world.stats_now()'), ('public.emit_event(uuid,text,jsonb)')) f(fn)) <> b.kept_md5 then
    raise exception '0268 self-assert FAIL: a money writer, do_sell, the quay, the flag reader, the world total or the event writer moved';
  end if;
  if (select string_agg(f.fn || '=' || coalesce(p.proacl::text, '') || '|' || p.prosecdef || '|' || coalesce(p.proconfig::text, ''), ',' order by f.fn)
        from (values ('public.mint_guard(text,bigint)'), ('public.economy_close_switch(boolean)')) f(fn)
        join pg_proc p on p.oid = f.fn::regprocedure) <> b.posture then
    raise exception '0268 self-assert FAIL: the guard or the switch changed its ACL, definer or config';
  end if;
  if (select p.provolatile from pg_proc p where p.oid = 'public.mint_guard(text,bigint)'::regprocedure) <> 'v'
     or (select p.provolatile from pg_proc p where p.oid = 'public.economy_close_switch(boolean)'::regprocedure) <> 'v'
     or (select p.provolatile from pg_proc p where p.oid = 'public.mint_gate(boolean)'::regprocedure) <> 'v' then
    raise exception '0268 self-assert FAIL: the guard, the switch or the gate is not VOLATILE (a STABLE guard reads its caller''s snapshot)';
  end if;
  if has_function_privilege('anon', 'public.mint_gate(boolean)', 'execute') or has_function_privilege('authenticated', 'public.mint_gate(boolean)', 'execute')
     or has_function_privilege('anon', 'public.economy_close_switch(boolean)', 'execute') or has_function_privilege('authenticated', 'public.economy_close_switch(boolean)', 'execute')
     or has_function_privilege('anon', 'public.mint_guard(text,bigint)', 'execute') or has_function_privilege('authenticated', 'public.mint_guard(text,bigint)', 'execute') then
    raise exception '0268 self-assert FAIL: a client can reach the gate, the guard or the switch';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> b.entry_points then
    raise exception '0268 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0268 self-assert FAIL: a wall moved';
  end if;
  if v_gate = v_quay then
    raise exception '0268 self-assert FAIL: the gate''s key is the quay''s';
  end if;

  -- (b) THE SAME ANSWERS, OLD AND NEW
  v_new := pg_temp.verdicts_0268();
  if v_new is distinct from o.verdicts
     or (select count(*) from jsonb_object_keys(v_new)) < 4 * 4 * 8
     or (select count(*) from jsonb_each_text(v_new) e where e.value like '%E_NO_NEW_GOLD%')
        <> (select count(*) from public.stats_flow_words w where w.side = 'minted') then   -- closed + lit, delta 7, each minted kind
    raise exception '0268 self-assert FAIL: the guard''s verdicts moved (old %, new %)', o.verdicts, v_new;
  end if;
  v_new := pg_temp.switch_0268(false);
  if v_new is distinct from o.switch_as_is then
    raise exception '0268 self-assert FAIL: the switch, as the world is, answered otherwise (old %, new %)', o.switch_as_is, v_new;
  end if;
  v_new := pg_temp.switch_0268(true);
  if v_new is distinct from o.switch_lit
     or v_new->'flip'->'answer'->>'changed' <> 'true' or v_new->'back'->'answer'->>'changed' <> 'true'
     or v_new->'noop'->'answer'->>'changed' <> 'false' or v_new->'again'->'answer'->>'changed' <> 'false'
     or coalesce((v_new->'flip'->>'stamp_is_its_total')::boolean, (v_new->'back'->>'stamp_is_its_total')::boolean) is not true then
    raise exception '0268 self-assert FAIL: the switch, purses lit, answered otherwise or its stamp is not its total (old %, new %)', o.switch_lit, v_new;
  end if;

  -- (c) THE ORDER, ON THE BODIES
  v_def := pg_temp.code_0268('public.economy_close_switch(boolean)');
  v_p := array[position('perform public.hold_the_quay();' in v_def), position('perform public.mint_gate(true);' in v_def),
               position('v_was := public.economy_closed();' in v_def), position('v_total := (world.stats_now()->>''total'')::bigint;' in v_def)];
  if v_p[1] = 0 or not (v_p[1] < v_p[2] and v_p[2] < v_p[3] and v_p[3] < v_p[4])
     or pg_temp.occurs_0268(v_def, 'hold_the_quay') <> 1 or pg_temp.occurs_0268(v_def, 'mint_gate') <> 1
     or pg_temp.occurs_0268(v_def, 'stats_now') <> 1
     or position('economy_closed()' in v_def) < v_p[2] or position('public.wc(' in v_def) < v_p[2]
     or position('city_treasury_on()' in v_def) < v_p[2] or position('port_treasury' in v_def) < v_p[2] then
    raise exception '0268 self-assert FAIL: the switch does not take the quay, then the gate, then read the flag, then the total — or it reads before its locks';
  end if;
  if (select count(*) from regexp_matches(v_def, '\mfor\s+(update|share|key\s+share|no\s+key\s+update)\M', 'g')) <> 2
     or pg_temp.occurs_0268(v_def, 'for no key update nowait') <> 2 or v_def like '%advisory%' or v_def like '%skip locked%' then
    raise exception '0268 self-assert FAIL: the switch takes a lock after the gate that can wait';
  end if;
  v_def := pg_temp.code_0268('public.mint_guard(text,bigint)');
  if pg_temp.occurs_0268(v_def, 'perform public.mint_gate(false);') <> 1 or pg_temp.occurs_0268(v_def, 'mint_gate') <> 1
     or position('public.economy_closed()' in v_def) < position('perform public.mint_gate(false);' in v_def)
     or position('public.city_treasury_on()' in v_def) < position('perform public.mint_gate(false);' in v_def) then
    raise exception '0268 self-assert FAIL: the guard does not hold the gate before it reads the flags';
  end if;
  v_def := pg_temp.code_0268('public.mint_gate(boolean)');
  if pg_temp.occurs_0268(v_def, 'perform pg_advisory_xact_lock(hashtextextended(''byeharu.mint_gate'', 268));') <> 1
     or pg_temp.occurs_0268(v_def, 'perform pg_advisory_xact_lock_shared(hashtextextended(''byeharu.mint_gate'', 268));') <> 1
     or pg_temp.occurs_0268(v_def, 'pg_advisory') <> 2 then
    raise exception '0268 self-assert FAIL: the gate is not one transaction lock, shared or exclusive, on its one key';
  end if;
  if (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%'
         and p.prokind in ('f', 'p') and p.prosrc like '%hold_the_quay()%')
     is distinct from (select string_agg(x, ',' order by x)
                         from unnest(string_to_array(b.quay_takers, ',') || 'economy_close_switch(boolean)'::text) x) then
    raise exception '0268 self-assert FAIL: the quay''s takers are not the old ones and the switch';
  end if;
  if (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%'
         and p.prokind in ('f', 'p') and p.prosrc like '%mint_gate(%') is distinct from 'economy_close_switch(boolean),mint_guard(text,bigint)'
     or (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%'
            and p.prokind in ('f', 'p') and p.prosrc like '%mint_guard(%') is distinct from b.guard_callers then
    raise exception '0268 self-assert FAIL: the gate is taken by more than the guard and the switch, or the guard''s callers moved';
  end if;
  if (select string_agg(t.tgrelid::regclass::text || '.' || t.tgname, ',' order by t.tgrelid::regclass::text, t.tgname)
        from pg_trigger t
       where not t.tgisinternal
         and t.tgrelid in ('public.world_config'::regclass, 'public.port_treasury'::regclass, 'public.events'::regclass))
     is distinct from 'events.events_append_only,world_config.world_config_time_compression_keeps_due_at'
     or position('(new.key = ''time_compression''::text)' in lower(pg_get_triggerdef(
          (select t.oid from pg_trigger t where t.tgname = 'world_config_time_compression_keeps_due_at')))) = 0
     or (select t.tgtype::int & 4 from pg_trigger t where t.tgname = 'events_append_only') <> 0 then
    raise exception '0268 self-assert FAIL: a trigger the switch fires is not one this file checked';
  end if;

  -- (d) AN IN-FLIGHT MINT ACROSS A FLIP
  if pg_temp.held_0268(v_gate) <> '' or pg_temp.held_0268(v_quay) <> '' then
    raise exception '0268 self-assert FAIL: this transaction holds the gate or the quay before the probe';
  end if;
  begin
    update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
    update public.world_config set value = 'false'::jsonb where key = 'economy_closed';
    update public.world_config set value = 'null'::jsonb where key in ('economy_closed_at', 'economy_closed_total');
    v_t0 := (world.stats_now()->>'total')::bigint;
    perform public.treasury_post(b.lis, 'IMPORT_DEMAND', 777, null, null);   -- the sale's premium, not committed
    v_held1 := pg_temp.held_0268(v_gate) || '/' || pg_temp.held_0268(v_quay);
    v_t1 := (world.stats_now()->>'total')::bigint;
    v_r := public.economy_close_switch(true);
    v_held2q := pg_temp.held_0268(v_quay);
    v_held2g := pg_temp.held_0268(v_gate);
    v_s := (public.wc('economy_closed_total') #>> '{}')::bigint;
    v_t2 := (world.stats_now()->>'total')::bigint;
    v_flight := jsonb_build_object('t0', v_t0, 't1', v_t1, 'stamp', v_s, 'answer', v_r->'world_total', 't2', v_t2,
                                   'held_after_mint', v_held1, 'quay_after_switch', v_held2q, 'gate_after_switch', v_held2g,
                                   'closed', public.economy_closed());
    begin
      perform public.treasury_post(b.lis, 'IMPORT_DEMAND', 5, null, null);
      v_flight := v_flight || jsonb_build_object('next_mint', 'passed');
    exception when others then
      v_flight := v_flight || jsonb_build_object('next_mint', split_part(sqlerrm, ':', 1));
    end;
    raise exception using errcode = 'ZY268', message = v_flight::text;
  exception when sqlstate 'ZY268' then
    v_flight := sqlerrm::jsonb;
  end;
  v_after := pg_temp.held_0268(v_gate) || '/' || pg_temp.held_0268(v_quay);
  if v_flight->>'held_after_mint' <> 'ShareLock/'
     or v_flight->>'quay_after_switch' <> 'ExclusiveLock'
     or v_flight->>'gate_after_switch' <> 'ExclusiveLock,ShareLock'
     or v_flight->>'closed' <> 'true' or v_flight->>'next_mint' <> 'E_NO_NEW_GOLD'
     or (v_flight->>'stamp')::bigint is distinct from (v_flight->>'answer')::bigint
     or (v_flight->>'stamp')::bigint < least((v_flight->>'t1')::bigint, (v_flight->>'t2')::bigint)
     or (v_flight->>'stamp')::bigint > greatest((v_flight->>'t1')::bigint, (v_flight->>'t2')::bigint)
     or v_after <> '/' then
    raise exception '0268 self-assert FAIL: an in-flight mint across the flip: %, after the rollback %', v_flight, v_after;
  end if;

  raise notice '0268 self-assert ok: THE SWITCH READS THE WORLD WITH NO COIN IN FLIGHT. public.mint_gate (one advisory transaction lock, server-only); mint_guard superseded VOLATILE: a positive minted kind holds the gate shared, then reads the flags; economy_close_switch superseded: the quay, then the gate exclusive, then the flag and the total, its two row locks NOWAIT (asserted on the bodies; the quay''s takers = the old set + the switch; the gate''s = the guard + the switch; the guard''s callers, ACLs, definers, configs, credit, treasury_post, city_pays, do_sell, the quay, the flag reader, stats_now, emit_event unmoved). OLD = NEW: % guard verdicts; the switch as the world is (%) and purses lit (no-op, flip, back, no-op). IN FLIGHT (rolled back): IMPORT_DEMAND 777 made open and not committed (gate %), the switch closed holding quay % and gate %: totals before %, after the mint %, stamp % (= its answer), after %; the next mint %; neither lock held after. Registry unchanged; walls 0.',
    (select count(*) from jsonb_object_keys(o.verdicts)), coalesce(o.switch_as_is->'flip'->'answer', o.switch_as_is->'flip'->'refused'),
    v_flight->>'held_after_mint', v_flight->>'quay_after_switch', v_flight->>'gate_after_switch',
    v_flight->>'t0', v_flight->>'t1', v_flight->>'stamp', v_flight->>'t2', v_flight->>'next_mint';
end $$;
