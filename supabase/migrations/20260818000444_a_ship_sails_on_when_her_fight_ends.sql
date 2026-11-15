-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0444: A SHIP SAILS ON WHEN HER FIGHT ENDS, on the map too - the roster serves a fleet again when her battle closes
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Owner, 2026-11-15: "right now when there is a fight made? ships inside the circle still move. wtf is this?"
--
-- WHAT PROD DOES (read 2026-11-15, read only, 8 raids and their sides; docs/dev-log/2026-11-16-battle-fix2.md):
--   THE SERVER HOLDS THE SHIP. public.battle_open stops every side (public.battle_stop): a ship under sail is held where she is by voyage.hold,
--     and her point was the same at the open, the middle and the end of every battle read. The hold is written for battle_seconds (600 s) and
--     her eta moves by that much; the fight is 1 to 73 s (0435), and at its close public.battle_resolve cuts the hold to the fight's own length
--     (voyage.hold_cut) and the eta comes back. So she stands for the fight and sails on, her eta later by exactly the fight. That is right.
--   THE ROSTER DOES NOT SAY SO. The map places the world's ships from world.sea_roster's frozen facts (course, departure, eta, holds), asked every
--     30 s as a delta. A held fleet is served again while she is held (0323: `f.busy_until >= p_since`). When her battle closes, busy_until is
--     null again and NOTHING serves her: the map keeps the row it has, the one with a TEN-MINUTE hold and the eta ten minutes late. On the map she
--     lies still for ten minutes after a fight of one, then jumps (at the next full read or her arrival). A map that read too late to see the hold
--     at all keeps the eta from before the fight instead.
-- WHAT THIS FILE CHANGES: world.sea_roster, ONE hunk. A delta also serves every fleet on a battle that closed since p_since less
--   3 minutes (a battle closes up to a minute after its end, on the minute job; `resolves_at` is its end, and 3 minutes covers a late job).
--   The row is the fleet's own row as it is now: the hold cut, the eta right, a wrecked ship as she lies. Nothing else in the roster moves; a full
--   read (p_since null) is byte for byte what it was.
-- NOT IN THIS FILE (the client's, PR battle-fix2): while a battle is fought the map stands every fleet on its card at the battle (the raider
--   strikes from her port up to attack_reach_nm, 240 nm, away: she is not in the circle on any read), and it ends a tick battle at its last tick
--   through cmd.battle_end. Until this file is live the client cuts the kept hold itself (src/live/fightCuts.ts); with it that code does nothing.
-- LOAD: -- budget: no new rows, no table, no job, no index. Each delta read runs one more hashed sub-select: public.battles by battles_ended
--   (resolves_at, status <> FIGHTING) over the last ~4 minutes (about 8 battles at 116 raids an hour) and their sides by the key. It serves
--   ~15 more rows a delta (2 fleets a battle, each for ~4 minutes of deltas). No statement of the beat or of a command is touched.
-- LOCKS: CREATE OR REPLACE x1 by a hunk. BUDGET: statement_timeout 45 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): the hunk reversed (swap `old` and `new` below in a new migration). No knob, no data.
-- SELF-ASSERT: the hunk once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved.
--   THE PROBE, rolled back by a raised sentinel, on its own rows only: a fleet of the world that a delta does not serve is put on a battle that
--   closed 2 minutes ago and the same delta serves her; on one that closed 10 minutes ago it does not; a full read serves the same fleets as before.
-- VERSION: 0444 (0442 seas-memo and 0443 are queued ahead and touch no body here). Written on the chain to 0441; prod head 0441/0442 when cut.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_fn constant text := 'world.sea_roster(timestamp with time zone)';
  c_old constant text :=
$h$      -- 0323: a hold moved her eta: she is served again while she is held, or the kept row would place her on the old one
      or f.busy_until >= p_since;$h$;
  c_new constant text :=
$h$      -- 0323: a hold moved her eta: she is served again while she is held, or the kept row would place her on the old one
      or f.busy_until >= p_since
      -- 0444: and again when her battle closes: its close cuts her hold to the fight's own length and moves her eta back (voyage.hold_cut), and
      -- busy_until is null by then. A battle closes up to a minute after its end (the minute job); 3 minutes covers a late one.
      or f.id in (select bs.fleet_id from public.battles b join public.battle_sides bs on bs.battle_id = b.id
                   where b.status <> 'FIGHTING' and b.resolves_at >= p_since - interval '3 minutes');$h$;
  v_t0        timestamptz := clock_timestamp();
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_note      text := 'no fleet of the world outside a delta in this world: proof 146 makes one';
  v_f         uuid;
  v_b         uuid;
  v_since     timestamptz;
  v_full0     text;
  v_served    uuid[];
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure(c_fn) is null or to_regprocedure('voyage.hold_cut(uuid,timestamp with time zone,timestamp with time zone)') is null
     or to_regclass('public.battles_ended') is null then
    raise exception '0444 refuses: 0118 (the roster), 0357 (the hold''s cut) or 0364 (battles_ended) is not in this world';
  end if;
  if position('0444:' in pg_get_functiondef(c_fn::regprocedure)) > 0 then
    raise exception '0444 refuses: it has been applied once';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_fn::regprocedure::oid;
  select p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
    into v_meta from pg_proc p where p.oid = c_fn::regprocedure::oid;

  -- ── 2. THE HUNK (it occurs exactly once in the live body, and reverses) ──
  v_def := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  v_pre := v_def;
  v_n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  if v_n <> 1 then
    raise exception '0444 self-assert FAIL: the hunk of % occurs % time(s), not once: the deployed body is not what this file was written against', c_fn, v_n;
  end if;
  v_def := replace(v_def, c_old, c_new);
  execute v_def;
  v_def := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  if (length(v_def) - length(replace(v_def, c_new, ''))) / length(c_new) <> 1 then
    raise exception '0444 self-assert FAIL: the hunk is not in the new body once';
  end if;
  if replace(v_def, c_new, c_old) <> v_pre then
    raise exception '0444 self-assert FAIL: % does not reverse to its pre-image', c_fn;
  end if;

  -- ── 3. SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_fn::regprocedure::oid) <> v_fn_before then
    raise exception '0444 self-assert FAIL: another function moved';
  end if;
  if (select p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
        from pg_proc p where p.oid = c_fn::regprocedure::oid) <> v_meta then
    raise exception '0444 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', c_fn;
  end if;

  -- ── 4. THE NEWS (0347's law) ──
  perform public.news_update('0444', 'A ship sails on when her fight ends, on the map too',
                             '전투가 끝나면 배는 지도에서도 다시 항해한다');

  -- ── 5. THE PROBE, rolled back by a raised sentinel: its own two rows (a battle and a side), nothing else ──
  begin
    update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled') and value is distinct from 'true'::jsonb;   -- the roster's two switches
    v_since := now() - interval '30 seconds';
    -- a fleet of the world that this delta does not serve (read once), and that is on no battle
    select coalesce(array_agg((e ->> 'id')::uuid), '{}') into v_served from jsonb_array_elements(world.sea_roster(v_since) -> 'fleets') e;
    select f.id into v_f
      from public.fleets f
      join public.sea_houses() h on h.player_id = f.player_id
     where f.busy_until is null
       and not exists (select 1 from public.battle_sides bs where bs.fleet_id = f.id)
       and f.id <> all (v_served)
     order by f.id limit 1;
    if v_f is not null then
      select md5(string_agg(e ->> 'id', ',' order by e ->> 'id')) into v_full0 from jsonb_array_elements(world.sea_roster(null) -> 'fleets') e;
      -- a battle that closed 10 minutes ago: the delta still does not serve her
      insert into public.battles (kind, site, started_at, resolves_at, status)
      values ('PROBE', '{"lat": 0, "lon": 0}'::jsonb, now() - interval '11 minutes', now() - interval '10 minutes', 'RESOLVED') returning id into v_b;
      insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at)
      values (v_b, v_f, 'DEFENDER', now() - interval '11 minutes', now() - interval '11 minutes');
      if exists (select 1 from jsonb_array_elements(world.sea_roster(v_since) -> 'fleets') e where (e ->> 'id')::uuid = v_f) then
        raise exception '0444 self-assert FAIL: a fleet whose battle closed 10 minutes ago is served by a delta';
      end if;
      -- the same battle, closed 2 minutes ago: the delta serves her, once
      update public.battles set resolves_at = now() - interval '2 minutes' where id = v_b;
      if (select count(*) from jsonb_array_elements(world.sea_roster(v_since) -> 'fleets') e where (e ->> 'id')::uuid = v_f) <> 1 then
        raise exception '0444 self-assert FAIL: a fleet whose battle closed 2 minutes ago is not served by a delta, once';
      end if;
      -- still being fought, with no busy_until: this file does not serve her (0323's line serves a held fleet)
      update public.battles set status = 'FIGHTING' where id = v_b;
      if exists (select 1 from jsonb_array_elements(world.sea_roster(v_since) -> 'fleets') e where (e ->> 'id')::uuid = v_f) then
        raise exception '0444 self-assert FAIL: a fleet on a battle still being fought is served by this file''s line';
      end if;
      -- a full read serves the fleets it served
      if (select md5(string_agg(e ->> 'id', ',' order by e ->> 'id')) from jsonb_array_elements(world.sea_roster(null) -> 'fleets') e) is distinct from v_full0 then
        raise exception '0444 self-assert FAIL: a full read of the roster moved';
      end if;
      v_note := 'a fleet outside a delta is served by it when her battle closed 2 minutes ago, not at 10, not while it is fought; a full read unmoved (rolled back)';
    end if;
    raise exception sqlstate 'BV444';
  exception when sqlstate 'BV444' then null;
  end;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0444 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0444 self-assert ok: A SHIP SAILS ON WHEN HER FIGHT ENDS. 1 hunk once and reversing; grants and volatility unmoved; no other function moved. Probe: %; % ms.',
    v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
