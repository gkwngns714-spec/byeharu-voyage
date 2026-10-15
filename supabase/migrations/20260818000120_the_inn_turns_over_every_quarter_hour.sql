-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0120 — THE INN TURNS OVER EVERY QUARTER HOUR
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- The owner, 2026-10-15:
--
--     "by clicking inn i should see captains. captains should be randomly distributed and change
--      locations every few time (set real 15min for now)"
--
-- ── WHAT WAS THERE ──────────────────────────────────────────────────────────────────────────────
-- Captains already HAVE a place (0073): who drinks in which inn is world.inn_present(officer,
-- port, p_day), a pure function of (officer, port, key, world secret), weighted toward her own
-- nation, region and culture and rarer the better she is. Its two callers, world.inn (the read)
-- and cmd.hire_officer (the gate: you sign only somebody in the room you lie in), both keyed it on
-- world.game_day() — and a game day is `game_day_seconds` = 2880 real seconds, so the room turned
-- over every 48 real minutes, on the same beat as every price in the world.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- ONE NEW AUTHORITY, world.inn_shift(at): which quarter-hour of real time it is, by a knob of its
-- own (`inn_captain_rotate_minutes`, 15). Its own knob and not the game day, because the owner
-- asked for REAL minutes and a game day is a price beat that moves when `game_day_seconds` does.
-- The two callers are re-cut to key the room on world.inn_shift() in place of world.game_day()
-- — one hunk each, nothing else in either body moves — so the read and the gate cannot disagree
-- about who is in the room: they ask the same function at the same instant.
--
-- ── WHY NO CRON AND NO TABLE ────────────────────────────────────────────────────────────────────
-- The rotation is DERIVED, exactly as the day was. A stored "who is where" re-shuffled by a cron
-- UPDATE every fifteen minutes would cost a write per turn, a job to keep alive (the clock was
-- found stopped for 37 hours on 10-13), and it would break 0073's hard rule: an inn derived from
-- (officer, port, shift, secret) cannot be re-rolled by anybody, is the same room for every player,
-- and turns over at the shift boundary with nothing running at all. The cheapest UPDATE is none.
--
-- ── WHAT THE READ GAINS ─────────────────────────────────────────────────────────────────────────
-- world.inn serves `shift` and `turns_at` (when this room turns over), so a screen can say
-- "new faces in 12 min" and re-ask then, and never offer a captain who has already left.
-- `game_day` is still served, unchanged, for a client that reads it.
--
-- ── WHAT IT DOES NOT CHANGE ─────────────────────────────────────────────────────────────────────
-- world.inn_present and world.inn_chance are untouched: the same weights, the same roster, the
-- same roll. Only the KEY the callers hand in turns faster.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── THE KNOB ────────────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('inn_captain_rotate_minutes', to_jsonb(15),
   '0120: how many REAL minutes the captains stay in one inn before the room turns over. The owner, '
   '2026-10-15: "change locations every few time (set real 15min for now)". Read by world.inn_shift; '
   'nothing is stored or scheduled - the room is derived from the shift.')
on conflict (key) do update set value = excluded.value, description = excluded.description;

-- ── THE ONE AUTHORITY FOR "WHICH ROOM IS IT NOW" ────────────────────────────────────────────────
create or replace function world.inn_shift(p_at timestamptz default now())
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $is$
  -- Whole quarter-hours since the epoch: the same number for every caller in the same quarter hour,
  -- the next number the instant it turns. An int holds this for another 40,000 years at 15 min.
  select floor(extract(epoch from p_at) / (public.wc_num('inn_captain_rotate_minutes') * 60))::int
$is$;

comment on function world.inn_shift(timestamptz) is
  '0120: which turn of the inns it is at this instant - floor(epoch / inn_captain_rotate_minutes). '
  'The ONE key world.inn and cmd.hire_officer hand to world.inn_present, so the room a player reads '
  'is the room the gate checks.';

revoke all on function world.inn_shift(timestamptz) from public, anon, authenticated;

-- ── THE SLICES ──────────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.slice_0120(p_fn text, p_old text, p_new text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  v_n   int  := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
begin
  if v_n <> 1 then
    raise exception '0120 self-assert FAIL: a hunk of % occurs % time(s), not once — the live body is not what this file was cut against: %',
      p_fn, v_n, left(p_old, 120);
  end if;
  execute replace(v_def, p_old, p_new);
end $$;

-- THE GATE: she must be in the room you lie in THIS quarter hour.
select pg_temp.slice_0120('cmd.hire_officer(text, uuid)',
$h$           and world.inn_present(v_off.id, f.port_id, world.game_day())) then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_IN_THE_ROOM',
      'error_message', format('%s is not drinking anywhere you are lying today.', v_off.name),$h$,
$h$           and world.inn_present(v_off.id, f.port_id, world.inn_shift())) then
    -- 0120: the room is keyed on the quarter hour (world.inn_shift), the same key world.inn reads.
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_IN_THE_ROOM',
      'error_message', format('%s is not drinking anywhere you are lying right now.', v_off.name),$h$);

-- THE READ: the room of this quarter hour, and when it turns.
select pg_temp.slice_0120('world.inn(uuid)',
$h$  v_day    int  := world.game_day();
  v_has    boolean;$h$,
$h$  v_day    int  := world.game_day();
  -- 0120: WHO IS HERE turns over every inn_captain_rotate_minutes REAL minutes, not every game day.
  v_shift  int  := world.inn_shift();
  v_has    boolean;$h$);

select pg_temp.slice_0120('world.inn(uuid)',
$h$    'game_day', v_day,$h$,
$h$    'game_day', v_day,
    'shift', v_shift,
    -- When this room turns over: a screen counts down to it and re-asks then.
    'turns_at', to_timestamp((v_shift + 1)::numeric * public.wc_num('inn_captain_rotate_minutes') * 60),$h$);

select pg_temp.slice_0120('world.inn(uuid)',
$h$     where v_has and world.inn_present(o.id, p_port, v_day)));$h$,
$h$     where v_has and world.inn_present(o.id, p_port, v_shift)));$h$);

-- ── SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid constant uuid := '00000000-0120-4000-8000-000000000001';
  v_k       int;
  v_t0      timestamptz;
  v_shift   int;
  v_room    jsonb;
  v_port    uuid;
  v_want    jsonb;
  v_moved   int;
  v_avg     numeric;
  v_max     int;
  v_player  uuid;
  v_fleet   uuid;
  v_in      uuid;
  v_dayonly uuid;
  v_dayport uuid;
  v_r       jsonb;
  v_grants  int;
  v_open    int;
begin
  -- (a) THE KNOB, at the owner's figure.
  if public.wc_num('inn_captain_rotate_minutes') <> 15 then
    raise exception '0120 self-assert FAIL: inn_captain_rotate_minutes is %, the owner said 15',
      public.wc_num('inn_captain_rotate_minutes');
  end if;

  -- (b) THE SHIFT TURNS ON THE QUARTER HOUR AND NOT A SECOND BEFORE. Both edges, so a shift that
  --     never turned and one that turned early are both caught.
  v_k  := world.inn_shift();
  v_t0 := to_timestamp(v_k::numeric * 900);
  if world.inn_shift(v_t0) <> v_k
     or world.inn_shift(v_t0 + interval '899.999 seconds') <> v_k
     or world.inn_shift(v_t0 + interval '900 seconds') <> v_k + 1 then
    raise exception '0120 self-assert FAIL: the shift does not turn exactly on the quarter hour (% / % / %)',
      world.inn_shift(v_t0), world.inn_shift(v_t0 + interval '899.999 seconds'), world.inn_shift(v_t0 + interval '900 seconds');
  end if;
  -- and it is not the game day under another name (positive control: the two keys differ).
  if world.inn_shift() = world.game_day() then
    raise exception '0120 self-assert FAIL: the shift equals the game day - the room is still keyed on the day';
  end if;

  -- (c) THE READ SERVES THIS QUARTER HOUR'S ROOM. Find an inn with somebody in it now, and require
  --     the served faces to be exactly the ones inn_present names for the shift, and turns_at to lie
  --     within the next fifteen minutes.
  v_shift := world.inn_shift();
  select p.id into v_port
    from public.ports p
   where p.kind = 'HARBOUR'
     and exists (select 1 from public.port_buildings b where b.port_id = p.id and b.kind = 'inn')
     and exists (select 1 from public.officers o where world.inn_present(o.id, p.id, v_shift))
   order by p.code limit 1;
  if v_port is null then
    raise exception '0120 self-assert FAIL: not one inn in the world has anybody in it this quarter hour';
  end if;
  v_room := world.inn(v_port);
  select coalesce(jsonb_agg(o.code order by o.code), '[]'::jsonb) into v_want
    from public.officers o where world.inn_present(o.id, v_port, v_shift);
  if (select coalesce(jsonb_agg(g->>'code' order by g->>'code'), '[]'::jsonb)
        from jsonb_array_elements(v_room->'present') g) is distinct from v_want then
    raise exception '0120 self-assert FAIL: world.inn served % but the shift''s room is %', v_room->'present', v_want;
  end if;
  if (v_room->>'shift')::int <> v_shift then
    raise exception '0120 self-assert FAIL: world.inn served shift % against %', v_room->>'shift', v_shift;
  end if;
  if (v_room->>'turns_at')::timestamptz <= now()
     or (v_room->>'turns_at')::timestamptz > now() + interval '15 minutes' then
    raise exception '0120 self-assert FAIL: the room turns at %, not within the next quarter hour', v_room->>'turns_at';
  end if;

  -- (d) THE NEXT QUARTER HOUR IS A DIFFERENT ROOM SOMEWHERE (captains change places).
  select count(*) into v_moved
    from public.ports p, public.officers o
   where p.kind = 'HARBOUR'
     and world.inn_present(o.id, p.id, v_shift) is distinct from world.inn_present(o.id, p.id, v_shift + 1);
  if v_moved = 0 then
    raise exception '0120 self-assert FAIL: the next quarter hour shows exactly the same people everywhere';
  end if;

  -- (e) A ROOM IS STILL A ROOM: 0073's own bounds, measured on this shift.
  select avg(c)::numeric(6,2), max(c) into v_avg, v_max
    from (select p.id, count(*) filter (where world.inn_present(o.id, p.id, v_shift)) c
            from public.ports p cross join public.officers o
           where p.kind = 'HARBOUR' group by p.id) x;
  if v_avg < 0.5 or v_avg > 6 or v_max >= (select count(*) from public.officers) then
    raise exception '0120 self-assert FAIL: the average inn holds % and the fullest % - not a room', v_avg, v_max;
  end if;

  -- (f) THE GATE READS THE SAME KEY, proven through the verb by a house standing at a quay, and
  --     rolled back. Three cases: somebody in the room this quarter hour signs; somebody who would
  --     have been in the room by the old DAY key but is not this quarter hour is refused (the
  --     probe that tells the new key from the old one); somebody in no room here is refused.
  begin
    v_player := public.new_house(c_uid, 'Casa do Quarto de Hora', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_player;
    perform cmd.assume_identity(c_uid);
    perform public.credit(v_player, 'PROBE_INN', 40000,
      public.emit_event(v_player, 'PROBE', jsonb_build_object('why', '0120 self-assert')));

    -- the old key, refused: present by the day, absent this quarter hour, at an inn.
    select p.id, o.id into v_dayport, v_dayonly
      from public.ports p cross join public.officers o
     where p.kind = 'HARBOUR'
       and exists (select 1 from public.port_buildings b where b.port_id = p.id and b.kind = 'inn')
       and world.inn_present(o.id, p.id, world.game_day())
       -- the house lies only at p, so absent from p's room this quarter hour is absent for the gate
       and not world.inn_present(o.id, p.id, v_shift)
     order by p.code, o.code limit 1;
    if v_dayonly is not null then
      update public.fleets set port_id = v_dayport, status = 'DOCKED' where id = v_fleet;
      v_r := cmd.hire_officer((select code from public.officers where id = v_dayonly), null);
      if coalesce((v_r->>'ok')::boolean, false) or v_r->>'error_code' <> 'E_NOT_IN_THE_ROOM' then
        raise exception '0120 self-assert FAIL: the gate still reads the DAY - signed or refused otherwise: %', v_r;
      end if;
    end if;

    -- the room of this quarter hour, signed.
    update public.fleets set port_id = v_port, status = 'DOCKED' where id = v_fleet;
    select o.id into v_in from public.officers o
     where world.inn_present(o.id, v_port, v_shift) order by o.code limit 1;
    v_r := cmd.hire_officer((select code from public.officers where id = v_in), null);
    if not coalesce((v_r->>'ok')::boolean, false) then
      raise exception '0120 self-assert FAIL: could not sign the captain who IS in the room this quarter hour: %', v_r;
    end if;
    -- and the read now says she is yours.
    if not exists (select 1 from jsonb_array_elements(world.inn(v_port)->'present') g
                    where g->>'code' = (select code from public.officers where id = v_in) and (g->>'signed')::boolean) then
      raise exception '0120 self-assert FAIL: she signed and the room does not say so';
    end if;

    -- somebody not in THIS room this quarter hour (the only room the house lies at), refused.
    select o.id into v_in from public.officers o
     where not world.inn_present(o.id, v_port, v_shift)
       and not exists (select 1 from public.player_officers po where po.player_id = v_player and po.officer_id = o.id)
     order by o.code limit 1;
    if v_in is null then
      raise exception '0120 self-assert FAIL: every officer in the world is in this one inn';
    end if;
    v_r := cmd.hire_officer((select code from public.officers where id = v_in), null);
    if coalesce((v_r->>'ok')::boolean, false) or v_r->>'error_code' <> 'E_NOT_IN_THE_ROOM' then
      raise exception '0120 self-assert FAIL: a captain not in the room this quarter hour was not refused E_NOT_IN_THE_ROOM: %', v_r;
    end if;
    raise exception 'ROLLBACK_0120';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0120' then raise; end if;
  end;

  -- (g) POSTURE: the shift is the server's, and the lockdown holds.
  if has_function_privilege('authenticated', 'world.inn_shift(timestamptz)', 'execute')
     or has_function_privilege('anon', 'world.inn_shift(timestamptz)', 'execute') then
    raise exception '0120 self-assert FAIL: a client role may execute world.inn_shift';
  end if;
  if not has_function_privilege('authenticated', 'world.inn(uuid)', 'execute') then
    raise exception '0120 self-assert FAIL: the re-cut lost world.inn''s grant to authenticated';
  end if;
  select count(*) into v_grants from public.client_write_grants();
  select count(*) into v_open from public.client_executable_writers();
  if v_grants <> 0 or v_open <> 0 then
    raise exception '0120 self-assert FAIL: % client write grant(s), % client-executable writer(s)', v_grants, v_open;
  end if;

  raise notice '0120 self-assert ok: THE INN TURNS OVER EVERY QUARTER HOUR. world.inn_shift turns exactly on '
    'the 15-minute edge (knob inn_captain_rotate_minutes) and is not the game day; world.inn serves the shift''s '
    'room exactly (% at the probed inn) with turns_at inside the next quarter hour; the next shift moves % '
    '(officer, harbour) pair(s); the average inn holds % and the fullest %. The gate reads the same key: a house '
    'at the quay signed the captain in the room this quarter hour, % and a captain not in that room was refused '
    'E_NOT_IN_THE_ROOM. Rolled back. No cron, no table: the room is derived. 0 client write grants, 0 open writers.',
    jsonb_array_length(v_room->'present'), v_moved, v_avg, v_max,
    case when v_dayonly is null then 'no day-only captain existed to probe the old key,'
         else 'a captain present by the old DAY key but not this quarter hour was REFUSED,' end;
end $$;
