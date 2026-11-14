-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0418 - THE ROSTER IS NOT KEPT WAITING BEHIND A SHIP THE DAY'S ROOM CANNOT BUILD
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none
-- THE FAULT (production, 2026-11-14, 18 minutes after 0414: roster built 0 of 108; the day's room 0). public.pirate_add adds ONE fleet a turn, the one
--   public.pirate_next_ord names: 0339's own ships first (ords 1 to public.pirate_size(), 13 with today's hoard), then the roster's. Production had 7
--   of those 13, so the next was ord 8. Her build (public.pirate_commission, BUILD_NAVY, one xebec) is INSIDE the day's room (public.pirate_pay), and the
--   room was spent (the morning's gifts), so the build answered null, public.pirate_add returned null without moving its clock, and the very same ord
--   was asked for again a minute later, all day. The roster's builds are OUTSIDE the room (0414, decided by default the same day), but they were never
--   reached: they stood in line behind a ship the room could not pay for. It would have cleared only on a day whose room built ords 8 to 13 (six
--   builds of 160,000, ten minutes apart, before anything else spent the room): not a thing to rely on.
-- THE FIX, AT THAT LINE: when the fleet named is one of 0339's own and the day's room does not hold what she needs now (her class's build cost, or an
--   hour's pay to wake her), public.pirate_add takes the next UNBUILT roster fleet instead (the roster's own order). 0339's ship keeps her place and is
--   asked for again at the next turn the room holds her. With the room open nothing changes: 0339's ships first, as before. One hunk, one body.
-- NOT CHANGED: the roster's build (its kind, its once, its floor), the pace (pirate_add_minutes), public.pirate_next_ord, the day's room.
-- LOCKS: CREATE OR REPLACE of one function. BUDGET: statement_timeout 30 s, lock_timeout 5 s; fails above 15 s.
-- SELF-ASSERT: the hunk once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved; a probe rolled back by a
--   raised sentinel (the day's room spent, one of 0339's ords pending, a roster fleet unbuilt: the add must answer BUILT with a roster fleet).
-- ROLLBACK (forward, owner only): the hunk reversed (scripts/ops/harness/pirate-add/rollback-0418.sql, a draft).
-- VERSION: 0418 = 0417 + 1 (production head 0416 on 2026-11-14; 0417 is the level benefits, PR #683). It cuts public.pirate_add as 0414 left it.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_fn constant text := 'public.pirate_add(timestamp with time zone)';
  c_old constant text := $h$  v_ord := public.pirate_next_ord();   -- 0414: 0339's ships first, then the roster's fleets, a hub at a time in turn
$h$;
  c_new constant text := $h$  v_ord := public.pirate_next_ord();   -- 0414: 0339's ships first, then the roster's fleets, a hub at a time in turn
  -- 0418: THE ROSTER DOES NOT WAIT BEHIND A SHIP THE DAY'S ROOM CANNOT PAY FOR. One of 0339's own ships is built (public.pirate_commission) or woken INSIDE the day's room; a roster fleet's build is outside it (0414).
  -- When the room does not hold what 0339's ship needs now, the next unbuilt roster fleet is taken instead; she keeps her place and is asked for again when the room holds her.
  if v_ord is not null and not exists (select 1 from public.pirate_roster r where r.ord = v_ord)
     and public.pirate_spend_room(p_now) < (case when exists (select 1 from public.pirate_ships n where n.ord = v_ord) then v_slice
                                                else coalesce((select c.build_cost from public.ship_classes c where c.code = public.wc_text('pirate_ship_class')), 0) end) then
    v_ord := coalesce((select r.ord from public.pirate_roster r where not exists (select 1 from public.pirate_ships n where n.ord = r.ord) order by r.ord % 1000, r.ord limit 1), v_ord);
  end if;
$h$;
  v_t0        timestamptz := clock_timestamp();
  v_now       timestamptz := now();
  v_def       text;
  v_pre       text;
  v_meta      text;
  v_n         int;
  v_fn_before text;
  v_s         text;
  v_built     int;
  v_note      text := 'no probe: the pirates are dark, every roster fleet is built, or none of 0339''s ships is pending in this world';
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regclass('public.pirate_roster') is null or to_regprocedure('public.pirate_commission_fleet(integer,uuid,timestamp with time zone)') is null
     or to_regprocedure('public.wc_text(text)') is null then
    raise exception '0418 refuses: 0414 (the pirates'' homes and roster) is not in this world';
  end if;
  v_pre := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  if position('0418' in v_pre) > 0 then
    raise exception '0418 refuses: it has been applied once';
  end if;
  select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text into v_meta
    from pg_proc p where p.oid = c_fn::regprocedure;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_fn::regprocedure;

  -- ── 1. THE HUNK ──
  v_n := (length(v_pre) - length(replace(v_pre, c_old, ''))) / length(c_old);
  if v_n <> 1 then
    raise exception '0418 self-assert FAIL: the hunk occurs % time(s) in public.pirate_add, not once: the deployed body is not what this file was written against', v_n;
  end if;
  execute replace(v_pre, c_old, c_new);
  v_def := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  if (length(v_def) - length(replace(v_def, c_new, ''))) / length(c_new) <> 1 or replace(v_def, c_new, c_old) <> v_pre then
    raise exception '0418 self-assert FAIL: the hunk is not in the new body once, or does not reverse to the pre-image';
  end if;
  if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
        from pg_proc p where p.oid = c_fn::regprocedure) <> v_meta then
    raise exception '0418 self-assert FAIL: the grants, volatility, definer, search path or owner of public.pirate_add moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> c_fn::regprocedure) <> v_fn_before then
    raise exception '0418 self-assert FAIL: another function moved';
  end if;

  -- ── 2. THE PROBE, rolled back by a raised sentinel: lit inside the probe only; the day's room spent; the add's clock due. With one of 0339's ords pending and a roster
  --      fleet unbuilt, the add must build a ROSTER fleet (it reads only the rows it names: the clock's one row, the day's one spend row, the pirate ships).
  begin
    update public.world_config set value = 'true'::jsonb where key in ('pirates_bite', 'city_treasury_enabled') and value is distinct from 'true'::jsonb;
    if public.pirates_on() and public.pirate_capital() is not null
       and exists (select 1 from public.pirate_roster r where not exists (select 1 from public.pirate_ships n where n.ord = r.ord))
       and exists (select 1 from generate_series(1, public.pirate_size()) g(o) where not exists (select 1 from public.pirate_ships_at_work n where n.ord = g.o)) then
      update public.port_treasury t set ducats = greatest(t.ducats, 1000000000) where t.port_id = public.pirate_capital();
      insert into public.pirate_spend_day (day, spent) values ((v_now at time zone 'UTC')::date, 1000000000000)
      on conflict (day) do update set spent = excluded.spent;
      update public.pirate_clock set added_at = v_now - interval '1 day';
      select count(*) into v_built from public.pirate_ships n where n.ord > 1000;
      v_s := public.pirate_add(v_now);
      if v_s is distinct from 'BUILT' or (select count(*) from public.pirate_ships n where n.ord > 1000) <> v_built + 1
         or public.pirate_spend_room(v_now) <> 0 then
        raise exception '0418 self-assert FAIL (probe): the day''s room spent and one of 0339''s ships pending, the add answered %, not BUILT with one roster fleet more', v_s;
      end if;
      v_note := 'the day''s room spent and one of 0339''s ships pending, the add built a roster fleet (rolled back)';
    end if;
    raise exception using errcode = 'ZP418', message = v_note;
  exception when sqlstate 'ZP418' then
    v_note := sqlerrm;
  end;

  if clock_timestamp() - v_t0 > interval '15 seconds' then
    raise exception '0418 self-assert FAIL: the file took % (budget 15 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0418 self-assert ok: THE ROSTER IS NOT KEPT WAITING BEHIND A SHIP THE DAY''S ROOM CANNOT BUILD. One hunk in public.pirate_add, once and reversing; grants and volatility unmoved; no other function moved. Probe: %. % ms.',
    v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
