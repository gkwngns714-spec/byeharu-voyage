-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0418 - THE ROSTER DOES NOT WAIT ON THE DAY'S ROOM  (a hull or a wake the room cannot pay no longer holds back the fleets the owner ordered)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-14: 180 pirate ships in four oceans from five havens (0414). 0414 decided by default that the roster's build is paid
--   OUTSIDE the day's room (public.pirate_commission_fleet, kind BUILD_ROSTER, the hoard never below 400 M), "so that it neither takes forty
--   real days nor takes the room the fleets' pay needs".
--
-- WHAT PROD SHOWED (read-only, 13:48 and 14:28 UTC, 18 and 58 minutes after 0414; docs/dev-log/2026-11-14-roster-fix.md): roster built 0 of 108;
--   pirate_clock.added_at 2026-11-13 18:01 (nothing added since); public.pirate_next_ord() = 8; public.pirate_size() = 13; seven of 0339's ships
--   (ords 1-7), six of them wrecks waiting on a purse; the day's room 0 (spent 4,215,000 against about 2.34 M: the morning's gifts, before the clock change).
-- THE CAUSE, in public.pirate_add as 0414 left it: the next fleet is public.pirate_next_ord(), which puts 0339's ords (1 to public.pirate_size(),
--   13 at this hoard) BEFORE the roster. Ords 8-13 were never built, so the head of the queue is ord 8, a 0339 xebec, built by
--   public.pirate_commission -> public.pirate_pay('BUILD_NAVY', 160,000), which pays only INSIDE the day's room. With the room at 0 it answers
--   0, public.pirate_commission answers null, and public.pirate_add RETURNS NULL ("return null;" under the build), every ten minutes, without ever
--   reaching a roster fleet. The same holds for a laid-up fleet at the head of the queue (a wake needs the room: "if public.pirate_spend_room(p_now)
--   < v_slice ... return null;"), and a fleet is laid up whenever an hour's pay finds the room at 0. So the roster, paid outside the room, waited on it.
--   Proven in the local world (scripts/ops/harness/roster-fix/scene-prod-shape.sql on main's chain): 40 minutes of today's shape add nothing;
--   from 00:00 UTC the room renews, the wrecks are reborn, ords 8-13 are built 00:00-00:50 and the first roster fleet at 01:00; any day the room
--   runs out with a laid-up fleet or a 0339 ord at the head, it stops again.
--
-- WHAT THIS FILE DOES (one body re-cut by two hunks, one new function):
--   public.pirate_add: when the fleet at the head of the queue is a 0339 ship the room cannot build, or a laid-up fleet the room cannot wake, the
--   add does not stop: it builds the next roster fleet never built instead (public.pirate_add_roster: the roster's own order, public.pirate_next_ord's
--   turn, by public.pirate_commission_fleet, outside the room, under the 400 M floor, at the same pace of one in pirate_add_minutes). When the room
--   can pay, nothing changes: 0339's ships first, wakes first, as 0414. The room still pays what it paid: 0339's hulls, wakes, the hour's pay, the
--   refits, the gifts. A roster fleet built on a day whose room is spent is unpaid at the next hour and lies laid up at her haven until the room
--   renews (the pay is the room's, by 0414's decision; not changed here).
--
-- NOT DONE (said plainly): today's room is not re-measured from the clock change (13:30 UTC); it renews at 00:00 UTC as every day. A one-day seam.
-- LOCKS: CREATE OR REPLACE FUNCTION x1 by hunks; CREATE FUNCTION x1. BUDGET: statement_timeout 45 s, lock_timeout 5 s; fails above 20 s.
-- SELF-ASSERT: each hunk once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved; the new function
--   server-only. THE PROOF MARKER, rolled back: today's shape (the room spent, the head of the queue a 0339 ord or a laid-up fleet, the clock due)
--   is built twice, on the pre-image BEFORE the cut (it must add NOTHING: the fault reproduced) and on the new body AFTER it (it must BUILD the next
--   roster fleet, write nothing to the day's room, hold the pace for the next minute, and build the one after ten minutes on).
-- ROLLBACK (forward, owner only): scripts/ops/harness/roster-fix/rollback-0418.sql, a draft: the two hunks reversed, the new function dropped.
-- VERSION: 0418 = 0417 + 1 (production head 0417 on 2026-11-14).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_cut constant text[] := array['public.pirate_add(timestamp with time zone)'];
  c_new constant text[] := array['public.pirate_add_roster(timestamp with time zone)'];
  v_t0        timestamptz := clock_timestamp();
  v_now       timestamptz := date_trunc('minute', now());
  hk          record;
  v_z         record;
  v_def       text;
  v_n         int;
  v_fn_before text;
  v_r         jsonb;
  v_note_pre  text;
  v_note_post text;
  v_added     timestamptz := (select c.added_at from public.pirate_clock c);
  v_bite      jsonb := public.wc('pirates_bite');
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.pirate_add_roster(timestamp with time zone)') is not null then
    raise exception '0418 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.pirate_commission_fleet(integer,uuid,timestamp with time zone)') is null or to_regclass('public.pirate_roster') is null
     or to_regprocedure('public.pirate_next_ord()') is null or to_regprocedure('public.news_update(text,text,text)') is null then
    raise exception '0418 refuses: the pirates'' homes and grounds (0414) or the news are not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0418 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0418
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_cut) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid);

  -- ── 2. THE PROOF MARKER'S SCENE: today's shape, built in a rolled-back sub-transaction. Answers {expect, head, before, first, held, second, spent_moved}.
  --      The switches lit, the hoard as prod's (975.9 M) if it is less, the day's room spent to 0, the clock due. The head of the queue is whatever
  --      public.pirate_next_ord() names in this world (on prod ord 8, a 0339 hull; in a fresh chain ord 1); a head that is already a roster fleet
  --      never built is replaced by a laid-up roster fleet built here, so the head always needs the room.
  create function pg_temp.rf_0418_scene(p_now timestamptz) returns jsonb language plpgsql as $s$
  declare
    v_cap    uuid := public.pirate_capital();
    v_head   int;
    v_expect int;
    v_next   int;
    v_spent  bigint;
    v_first  text;
    v_held   text;
    v_second text;
    v_out    jsonb;
  begin
    begin
      update public.world_config set value = 'true'::jsonb
       where key in ('pirates_bite', 'city_treasury_enabled', 'npc_refits_enabled', 'economy_closed') and value is distinct from 'true'::jsonb;
      if v_cap is null or not public.pirates_on() then
        raise exception using errcode = 'ZR418', message = jsonb_build_object('none', 'no pirate capital in this world')::text;
      end if;
      update public.port_treasury t set ducats = greatest(t.ducats, 975934180) where t.port_id = v_cap;
      v_head := public.pirate_next_ord();
      if v_head is not null and exists (select 1 from public.pirate_roster r where r.ord = v_head) and not exists (select 1 from public.pirate_ships n where n.ord = v_head) then
        -- the head is a roster fleet never built: build her (the room whole), lay her up, so the head is a wake the room cannot pay
        if public.pirate_commission_fleet(v_head, public.refit_yard((select r.hub_port from public.pirate_roster r where r.ord = v_head)), p_now - interval '1 day') is null then
          raise exception using errcode = 'ZR418', message = jsonb_build_object('none', 'the roster fleet at the head could not be built')::text;
        end if;
        update public.pirate_ships n set laid_up_at = p_now - interval '1 hour', unpaid_since = p_now - interval '1 hour' where n.ord = v_head;
        v_head := public.pirate_next_ord();
      end if;
      select r.ord into v_expect from public.pirate_roster r
       where not exists (select 1 from public.pirate_ships n where n.ord = r.ord) order by r.ord % 1000, r.ord limit 1;
      select r.ord into v_next from public.pirate_roster r
       where not exists (select 1 from public.pirate_ships n where n.ord = r.ord) and r.ord <> v_expect order by r.ord % 1000, r.ord limit 1;
      insert into public.pirate_spend_day (day, spent) values ((p_now at time zone 'UTC')::date, floor(public.pirate_hoard() * public.wc_num('pirate_spend_day_pct'))::bigint + 1)
      on conflict (day) do update set spent = greatest(public.pirate_spend_day.spent, excluded.spent);
      v_spent := (select d.spent from public.pirate_spend_day d where d.day = (p_now at time zone 'UTC')::date);
      update public.pirate_clock set added_at = p_now - interval '1 day';
      if public.pirate_spend_room(p_now) <> 0 or v_expect is null or v_head is null or v_head = v_expect then
        raise exception using errcode = 'ZR418', message = jsonb_build_object('none', 'the shape could not be built', 'head', v_head, 'expect', v_expect)::text;
      end if;
      v_first := public.pirate_add(p_now);
      v_held := public.pirate_add(p_now + interval '1 minute');
      v_second := public.pirate_add(p_now + make_interval(mins => public.wc_int('pirate_add_minutes')));
      v_out := jsonb_build_object('head', v_head, 'expect', v_expect, 'next', v_next, 'first', v_first, 'held', v_held, 'second', v_second,
        'built_expect', exists (select 1 from public.pirate_ships n where n.ord = v_expect),
        'built_next', exists (select 1 from public.pirate_ships n where n.ord = v_next),
        'head_built', exists (select 1 from public.pirate_ships n where n.ord = v_head and n.laid_up_at is null),
        'spent_moved', (select d.spent from public.pirate_spend_day d where d.day = (p_now at time zone 'UTC')::date) <> v_spent,
        'room', public.pirate_spend_room(p_now));
      raise exception using errcode = 'ZR418', message = v_out::text;
    exception when sqlstate 'ZR418' then
      return sqlerrm::jsonb;
    end;
  end
  $s$;

  -- ── 3. THE MARKER ON THE PRE-IMAGE: today's behaviour. The room spent and the head needing it, nothing is added.
  v_r := pg_temp.rf_0418_scene(v_now);
  if v_r ? 'none' then
    v_note_pre := 'no marker: ' || (v_r ->> 'none');
  elsif v_r ->> 'first' is not null or (v_r ->> 'built_expect')::boolean then
    raise exception '0418 self-assert FAIL (marker, before): the pre-image added % with the room spent: this world is not the fault this file fixes (%)', v_r ->> 'first', v_r;
  else
    v_note_pre := format('before the cut, the room spent and ord %s at the head: nothing added (roster fleet %s not built), as on prod', v_r ->> 'head', v_r ->> 'expect');
  end if;

  -- ── 4. THE NEW FUNCTION ──
  execute $f$
create function public.pirate_add_roster(p_now timestamp with time zone)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0418: THE ROSTER DOES NOT WAIT ON THE DAY'S ROOM. Called by public.pirate_add alone, after its pace and capital checks, when the fleet at the head of the queue needs the room (a 0339 hull,
-- public.pirate_commission, or a wake) and the room cannot pay her: the next roster fleet never built, in public.pirate_next_ord's turn (her place in her hub, then the hub), is built instead by
-- public.pirate_commission_fleet, outside the room, the hoard never below the 400 M floor. The pace is the add's: built, public.pirate_clock.added_at is now. Answers BUILT, or null (nothing to build, or the floor,
-- the capital's surplus or its purse busy: asked again at the next turn).
declare
  v_ord int;
  v_hub uuid;
begin
  select r.ord, r.hub_port into v_ord, v_hub from public.pirate_roster r
   where not exists (select 1 from public.pirate_ships n where n.ord = r.ord)
   order by r.ord % 1000, r.ord limit 1;
  if v_ord is null or public.pirate_commission_fleet(v_ord, public.refit_yard(v_hub), p_now) is null then
    return null;
  end if;
  update public.pirate_clock set added_at = p_now;
  return 'BUILT';
end
$$;
$f$;
  comment on function public.pirate_add_roster(timestamptz) is '0418: the next roster fleet never built, built outside the day''s room when the head of the add queue needs the room and it cannot pay (public.pirate_add). Server-only.';
  revoke all on function public.pirate_add_roster(timestamptz) from public, anon, authenticated;

  -- ── 5. THE HUNKS ──
  create temp table hunk_0418 (ord int primary key, fn text, old text, new text) on commit drop;
  insert into hunk_0418 values
  (1, c_cut[1],
$h$    if public.pirate_spend_room(p_now) < v_slice or public.city_surplus(v_cap) < v_slice then
      return null;
    end if;
$h$,
$h$    if public.pirate_spend_room(p_now) < v_slice or public.city_surplus(v_cap) < v_slice then
      return public.pirate_add_roster(p_now);   -- 0418: a wake the day's room cannot pay does not hold the roster back: the next roster fleet is built instead, outside the room
    end if;
$h$),
  (2, c_cut[1],
$h$                else public.pirate_commission(v_ord, v_home, v_yard, p_now) end) is null then
      return null;
$h$,
$h$                else public.pirate_commission(v_ord, v_home, v_yard, p_now) end) is null then
      return case when exists (select 1 from public.pirate_roster r where r.ord = v_ord) then null else public.pirate_add_roster(p_now) end;   -- 0418: a 0339 hull the day's room cannot pay does not hold the roster back
$h$);
  for hk in select * from hunk_0418 order by ord loop
    v_def := replace(pg_get_functiondef(hk.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, hk.old, ''))) / length(hk.old);
    if v_n <> 1 then
      raise exception '0418 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', hk.ord, hk.fn, v_n;
    end if;
    execute replace(v_def, hk.old, hk.new);
    v_def := replace(pg_get_functiondef(hk.fn::regprocedure), E'\r', '');
    if (length(v_def) - length(replace(v_def, hk.new, ''))) / length(hk.new) <> 1 then
      raise exception '0418 self-assert FAIL: hunk % of % is not in the new body once', hk.ord, hk.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = hk.fn::regprocedure) <> (select p.meta from pre_0418 p where p.fn = hk.fn) then
      raise exception '0418 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', hk.fn;
    end if;
  end loop;
  for hk in select p.fn, p.def from pre_0418 p loop
    v_def := replace(pg_get_functiondef(hk.fn::regprocedure), E'\r', '');
    for v_z in select x.old, x.new from hunk_0418 x where x.fn = hk.fn order by x.ord desc loop
      v_def := replace(v_def, v_z.new, v_z.old);
    end loop;
    if v_def <> hk.def then
      raise exception '0418 self-assert FAIL: % does not reverse to its pre-image', hk.fn;
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and not exists (select 1 from unnest(c_cut || c_new) f where f::regprocedure = p.oid)) <> v_fn_before then
    raise exception '0418 self-assert FAIL: another function moved';
  end if;
  if exists (select 1 from unnest(c_new) f join pg_proc p on p.oid = f::regprocedure
              where not p.prosecdef or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')) then
    raise exception '0418 self-assert FAIL: a new function is not server-only';
  end if;

  -- ── 6. THE MARKER ON THE NEW BODY: the same shape builds the next roster fleet, outside the room, at the pace.
  v_r := pg_temp.rf_0418_scene(v_now);
  if v_r ? 'none' then
    v_note_post := 'no marker: ' || (v_r ->> 'none');
  elsif v_r ->> 'first' is distinct from 'BUILT' or not (v_r ->> 'built_expect')::boolean or (v_r ->> 'spent_moved')::boolean or (v_r ->> 'head_built')::boolean
        or v_r ->> 'held' is not null or (v_r ->> 'next' is not null and (v_r ->> 'second' is distinct from 'BUILT' or not (v_r ->> 'built_next')::boolean)) then
    raise exception '0418 self-assert FAIL (marker, after): with the room spent the add did not build roster fleet % outside the room at its pace (%)', v_r ->> 'expect', v_r;
  else
    v_note_post := format('after the cut, the same shape built roster fleet %s and, ten minutes on, %s; nothing written to the day''s room; the head (ord %s) still waits on the room; the next minute added nothing',
                          v_r ->> 'expect', v_r ->> 'next', v_r ->> 'head');
  end if;
  drop function pg_temp.rf_0418_scene(timestamptz);
  if (select c.added_at from public.pirate_clock c) is distinct from v_added or public.wc('pirates_bite') is distinct from v_bite
     or exists (select 1 from public.pirate_ships n where n.ord = (v_r ->> 'expect')::int and n.created_at = v_now) then
    raise exception '0418 self-assert FAIL: the marker was not rolled back';
  end if;

  -- ── 7. THE NEWS (0347's law) ──
  perform public.news_update('0418', 'Pirate fleets keep coming', '해적 함대가 계속 늘어납니다');

  if clock_timestamp() - v_t0 > interval '20 seconds' then
    raise exception '0418 self-assert FAIL: the file took % (budget 20 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0418 self-assert ok: THE ROSTER DOES NOT WAIT ON THE DAY''S ROOM. Two hunks over public.pirate_add, each once and reversing; grants and volatility unmoved; no other function moved; one new function, server-only. Marker: %; %. % ms.',
    v_note_pre, v_note_post, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
