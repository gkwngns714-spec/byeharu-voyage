-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0356 - A LEVEL CROSSED IS A MOMENT  (slice R4 of docs/REPUTATION.md sections 1.5, 1.6, 5, 6; owner row 317)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
-- WHY: docs/SUCCESS_PLAN.md: "Nothing fires when a level is crossed; no spendable reward for doing well." A company's
-- levels stay DERIVED (public.player_progress). This file adds only a MARK: which crossings were already paid.
--
-- WHAT THIS FILE MAKES
--   THE MARK      public.house_level_marks (player, track, level): the highest level of a track whose crossing was paid.
--                 A company with no row counts as 1. It is NOT a level: nothing reads a level from it.
--   THE SETTLE    public.level_marks_settle(player): a merchant returns null after one players probe (no other read, no
--                 write). A human: ONE public.player_progress read; for each track (combat only while it is playable), for
--                 each level from the mark + 1 to the derived level: public.reputation_credit(player, 'level',
--                 rep_level_per_level x L, 'level:<track>:<L>'), one event LEVEL_UP {track, level, reputation}, then the
--                 mark rises. Twice safe: by the mark (its row is locked before a crossing is paid) and by the book's key.
--   THE DOOR      cmd.level_up(): the caller's own settle. The client calls it once when a served level stands above its
--                 served mark (a level crossed at the quay, by a buy or a sale).
--   THE LAP       public.reputation_lap(player, lap, net, route, lap number): a standing-route lap closed at a gain pays
--                 rep_lap (R1's knob, 10) once a lap, key lap:<lap id>. A lap with no gain returns before any read.
--   THE HUNKS     one each, sliced from the live bodies (pg_get_functiondef at head 0353, LF), each once and reversing:
--                 public.reputation_arrival (R1's own function: the settle runs at a human arrival's own moment, so there
--                 is NO new hunk on voyage.settle), public.reputation_card (serves level_marks and level_gift),
--                 cmd.standing_route_close_lap (one line after its ROUTE_LAP emit), public.client_rpc_entry_points (+1:
--                 cmd.level_up, on 0325's `levels` row, a line 0354 and 0355 do not cut).
--   THE KNOB      rep_level_per_level 10: the gift for reaching level L is 10 x L. 0 = no gift (the moment still fires).
--   NO BACK-PAY   a mark is seeded at every human's level as it stands at this deploy (one player_progress read a human).
--
-- WHERE THIS FILE LEAVES docs/REPUTATION.md (the code was followed; each is in docs/dev-log/2026-11-12-level-up.md):
--   * the lap hook calls a helper, public.reputation_lap, not public.reputation_credit: plpgsql evaluates a call's
--     arguments first, and public.wc_int('rep_lap') in the lap job's line would be a knob read on every merchant lap.
--   * reputation_card also serves level_gift (the knob), so the Levels page prints "Next +60" without a second authority.
--   * reputation_on false: the settle writes nothing (R1's rule: the switch stops every write), and pays when it is lit.
--   * the mark's row is locked before a crossing is paid, so an arrival and the door at one instant emit one event.
--   * the table's foreign key to players is added LAST (see LOCKS).
--   * this file's own probe crosses levels by miles (events only). Turnover through the real doors is CI's proof 59: the
--     probe cannot know what prod's economy switches would refuse.
--
-- COST: a merchant's arrival: nothing (the hunk is in a function voyage.settle calls for a human only, after its own
-- is_npc return). A merchant's lap: one call that compares a number; at a gain, one players probe. A human arrival: one
-- player_progress read (about 22 ms warm, 690 ms cold on prod, measured 2026-11-07) and one index probe of the marks.
-- cmd.do_sell does not call the settle. world.player(): one more index probe and one more knob read.
-- ROLLBACK (forward, owner only): rep_level_per_level 0 stops the gift; reputation_on false stops every write of this file
-- too; a migration restoring the four OLD hunks takes the hooks out. The table stays.
-- SELF-ASSERT: the catalog, then probe houses of this file's own rows, rolled back by a raised sentinel. No table is
-- counted or summed. Each part's time is printed. The measurements stop themselves after 2 s each and never gate.
-- NEWS: this file posts its own UPDATE row once, outside the rolled-back probe (0347's law, tests/news.lint.spec.ts).
-- BUDGET: ONE DO block, statement_timeout 60 s, lock_timeout 5 s. THE SEED READS COME FIRST AND HOLD NO LOCK: if prod is
-- slow there, the statement is cancelled at 60 s with nothing made, and a second push finds the pages warm.
-- LOCKS: public.players is locked (SHARE ROW EXCLUSIVE, under lock_timeout 5 s) only by the foreign key, which is added as
-- the LAST statement that touches a table: it is held for the news row and the receipt, not for the seed or the probe.
-- VERSION: 0356. 0354 (fleet room) and 0355 (captain skills) share no function with this file but the registry, and
-- each cuts it on another line.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0          timestamptz := clock_timestamp();
  v_t           timestamptz;
  v_tm          timestamptz;
  v_ms_pre      numeric;
  v_ms_seed     numeric;
  v_ms_seed_max numeric := 0;
  v_ms_make     numeric;
  v_ms_catalog  numeric;
  v_ms_probe    numeric;
  v_ms_fk       numeric;
  v_seeded      int := 0;
  v_fn_before   text;
  v_cfg_before  text;
  v_entry       int;
  v_def         text;
  v_lap_old     text;
  v_arr_old     text;
  d             record;
  h             record;
  v_p           record;
  s             record;
  v_n           int;
  v_m           int;
  v_ok          boolean;
  v_lived       boolean := false;
  v_pp          jsonb;
  v_pp2         jsonb;
  v_pl          uuid;
  v_pl2         uuid;
  v_pl3         uuid;
  v_npc         uuid;
  v_fl1         uuid;
  v_fl2         uuid;
  v_nfl         uuid;
  v_lis         uuid;
  v_far         uuid;
  v_voy         uuid;
  v_route       uuid;
  v_nroute      uuid;
  v_lap         uuid;
  v_good_code   text;
  v_r           jsonb;
  v_nm4         numeric;
  v_nm2         numeric;
  v_gift        int;
  v_lap_pay     int;
  v_seq         int;
  v_combat_note text := 'not run';
  v_lap_note    text := 'not run';
  v_old_ms      numeric := 0;
  v_new_ms      numeric := 0;
  v_pairs       int := 0;
  v_aold_ms     numeric := 0;
  v_anew_ms     numeric := 0;
  v_apairs      int := 0;
  v_meas_note   text := '';
  t1            timestamptz;
  t2            timestamptz;
  t3            timestamptz;
  c_uid   constant uuid := '00000000-0356-4000-8000-000000000001';
  c_uid2  constant uuid := '00000000-0356-4000-8000-000000000002';
  c_uid3  constant uuid := '00000000-0356-4000-8000-000000000003';
  c_new_fns constant text[] := array[
    'public.level_marks_settle(uuid)', 'cmd.level_up()', 'public.reputation_lap(uuid,uuid,bigint,text,integer)'];
  c_cut_fns constant text[] := array[
    'public.reputation_arrival(uuid,uuid)', 'public.reputation_card(uuid)',
    'cmd.standing_route_close_lap(uuid,timestamp with time zone)', 'public.client_rpc_entry_points()'];
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regclass('public.house_level_marks') is not null or to_regprocedure('public.level_marks_settle(uuid)') is not null
     or to_regprocedure('cmd.level_up()') is not null or to_regprocedure('public.reputation_lap(uuid,uuid,bigint,text,integer)') is not null
     or exists (select 1 from public.world_config c where c.key = 'rep_level_per_level') then
    raise exception '0356 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.reputation_credit(uuid,text,integer,text,jsonb)') is null or to_regclass('public.reputation_book') is null
     or to_regprocedure('public.player_progress(uuid)') is null or to_regprocedure('public.emit_event(uuid,text,jsonb)') is null
     or to_regprocedure('public.current_player_id()') is null or to_regprocedure('public.wc(text)') is null
     or to_regprocedure('public.wc_int(text)') is null or to_regprocedure('public.client_write_grants()') is null
     or to_regprocedure('public.levels_bite_on()') is null
     or not exists (select 1 from public.reputation_kinds k where k.code = 'level' and k.sign = 1 and not k.capped)
     or not exists (select 1 from public.reputation_kinds k where k.code = 'lap' and k.sign = 1 and k.capped)
     or not exists (select 1 from public.world_config c where c.key = 'rep_lap')
     or exists (select 1 from unnest(c_cut_fns) f where to_regprocedure(f) is null) then
    raise exception '0356 refuses: a function, kind or knob it calls or cuts is not in this world (0004 / 0069 / 0092 / 0352)';
  end if;
  if to_regprocedure('public.news_update(text,text,text)') is null then
    raise exception '0356 refuses: this world keeps no news (public.news_update, 0347)';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table defs_0356 on commit drop as
  select f.fn,
         replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
         coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
         (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
         (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
         (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
    from unnest(c_cut_fns) f(fn);
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (select f::regprocedure::oid from unnest(c_cut_fns) f);
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
    into v_cfg_before from public.world_config c;
  v_entry := (select count(*) from public.client_rpc_entry_points());
  v_ms_pre := extract(epoch from clock_timestamp() - v_t0) * 1000;

  -- ── 2. THE SEED READS: every human's levels as they stand now. Reads only; no lock on players; nothing made yet. ──
  v_t := clock_timestamp();
  create temp table seed_0356 (player_id uuid, track text, level int) on commit drop;
  for s in select p.id from public.players p where not p.is_npc order by p.created_at, p.id loop
    t1 := clock_timestamp();
    v_pp := public.player_progress(s.id);
    insert into seed_0356 (player_id, track, level)
    select s.id, x.track, greatest((v_pp -> x.track ->> 'level')::int, 1)
      from unnest(array['trading', 'exploration', 'combat']) x(track);
    v_seeded := v_seeded + 1;
    v_ms_seed_max := greatest(v_ms_seed_max, extract(epoch from clock_timestamp() - t1) * 1000);
  end loop;
  v_ms_seed := extract(epoch from clock_timestamp() - v_t) * 1000;

  -- ── 3. THE HUNKS (each OLD text once in its live body) ──
  v_t := clock_timestamp();
  create temp table hunks_0356 (fn text, n int, old text, new text) on commit drop;
  insert into hunks_0356 (fn, n, old, new) values
    ('public.reputation_arrival(uuid,uuid)', 1,
$o$  select v.total_nm, v.dest_port_id, v.departed_at into v_nm, v_dest, v_sailed
$o$,
$n$  -- 0356 (R4): every level she has crossed and not been paid for fires here, at the arrival's own moment (public.level_marks_settle)
  perform public.level_marks_settle(p_player);
  select v.total_nm, v.dest_port_id, v.departed_at into v_nm, v_dest, v_sailed
$n$),
    ('public.reputation_card(uuid)', 1,
$o$    'seq',     coalesce(b.seq, 0),
$o$,
$n$    'seq',     coalesce(b.seq, 0),
    -- 0356 (R4): the level of each track whose crossing was paid (no row counts as 1), and the gift a level: level L pays level_gift x L
    'level_marks', (select jsonb_build_object(
                      'trading',     coalesce(max(m.level) filter (where m.track = 'trading'), 1),
                      'exploration', coalesce(max(m.level) filter (where m.track = 'exploration'), 1),
                      'combat',      coalesce(max(m.level) filter (where m.track = 'combat'), 1))
                      from public.house_level_marks m where m.player_id = p_player),
    'level_gift', public.wc_int('rep_level_per_level'),
$n$),
    ('cmd.standing_route_close_lap(uuid,timestamp with time zone)', 1,
$o$    'skipped', jsonb_array_length(l.skipped), 'skipped_lines', l.skipped));
$o$,
$n$    'skipped', jsonb_array_length(l.skipped), 'skipped_lines', l.skipped));
  -- 0356 (R4): a lap closed at a gain earns Reputation, once a lap (public.reputation_lap: no gain returns before any read; a merchant after one players probe)
  perform public.reputation_lap(sr.player_id, l.id, l.net, sr.name, l.lap_no);
$n$),
    ('public.client_rpc_entry_points()', 1,
$o$      ('world',       'levels',                ''),
$o$,
$n$      ('world',       'levels',                ''),
      -- 0356: the caller's level crossings paid (public.level_marks_settle). No argument, no player id.
      ('cmd',         'level_up',              ''),
$n$);

  -- ── 4. THE TABLE (its foreign key to players is added at the end: see LOCKS) ──
  create table public.house_level_marks (
    player_id uuid not null,
    track     text not null check (track in ('trading', 'exploration', 'combat')),
    level     int  not null check (level >= 1),
    primary key (player_id, track)
  );
  comment on table public.house_level_marks is
    '0356: the highest level of each track whose crossing was PAID (the LEVEL_UP event and its Reputation gift). NOT a level: a level is derived by public.player_progress, and no row counts as 1. Written by public.level_marks_settle alone; read by it and by public.reputation_card.';
  alter table public.house_level_marks enable row level security;
  revoke all on table public.house_level_marks from public, anon, authenticated;

  -- ── 5. THE KNOB ──
  insert into public.world_config (key, value, description) values
    ('rep_level_per_level', to_jsonb(10),
     '0356: reaching level L of a track (Trading, Exploration, Combat while it is counted) gives this much Reputation times L, once a level. 0 = no gift: the LEVEL_UP event still fires, with reputation 0.');

  -- ── 6. THE FUNCTIONS ──
  execute $f$
create function public.level_marks_settle(p_player uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0356 (R4): EVERY LEVEL CROSSED AND NOT YET PAID. A merchant: null, after one players probe and nothing else. A human: ONE
-- public.player_progress read (the levels stay derived there); for each track (combat only while it is playable), each level
-- from the mark + 1 to the derived level books its gift (kind level, key level:<track>:<L>), emits LEVEL_UP and the mark
-- rises. Safe twice: the mark's row is locked before a crossing is paid, and the book's key pays once ever.
-- reputation_on false: nothing is written. Returns {levels: [{track, level, reputation}]}: what this call paid.
declare
  v_pp    jsonb;
  v_marks jsonb;
  v_track text;
  v_level int;
  v_mark  int;
  v_per   int;
  v_got   int;
  v_out   jsonb := '[]'::jsonb;
begin
  if p_player is null or coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then
    return null;
  end if;
  if public.wc('reputation_on') is distinct from 'true'::jsonb then
    return jsonb_build_object('levels', v_out);
  end if;
  v_pp := public.player_progress(p_player);
  select coalesce(jsonb_object_agg(m.track, m.level), '{}'::jsonb) into v_marks
    from public.house_level_marks m where m.player_id = p_player;
  foreach v_track in array array['trading', 'exploration', 'combat'] loop
    continue when v_track = 'combat' and not coalesce((v_pp -> 'combat' ->> 'playable')::boolean, false);
    v_level := coalesce((v_pp -> v_track ->> 'level')::int, 1);
    continue when v_level <= coalesce((v_marks ->> v_track)::int, 1);
    -- a level was crossed: take the mark's own row (made at 1 when she has none), so two settles at one instant pay once
    insert into public.house_level_marks (player_id, track, level) values (p_player, v_track, 1)
    on conflict (player_id, track) do nothing;
    select m.level into v_mark from public.house_level_marks m where m.player_id = p_player and m.track = v_track for update;
    continue when v_level <= v_mark;
    if v_per is null then
      v_per := coalesce(public.wc_int('rep_level_per_level'), 0);
    end if;
    for v_l in v_mark + 1 .. v_level loop
      v_got := 0;
      if v_per > 0 then
        v_got := public.reputation_credit(p_player, 'level', v_per * v_l, 'level:' || v_track || ':' || v_l,
                                          jsonb_build_object('track', v_track, 'level', v_l));
      end if;
      perform public.emit_event(p_player, 'LEVEL_UP', jsonb_build_object('track', v_track, 'level', v_l, 'reputation', v_got));
      v_out := v_out || jsonb_build_object('track', v_track, 'level', v_l, 'reputation', v_got);
    end loop;
    update public.house_level_marks set level = v_level where player_id = p_player and track = v_track;
  end loop;
  return jsonb_build_object('levels', v_out);
end
$body$
  $f$;
  execute $f$
create function cmd.level_up()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0356 (R4): THE CALLER'S LEVEL CROSSINGS, PAID (public.level_marks_settle). The client calls it once when a served level
-- stands above its served mark. {ok, levels: [{track, level, reputation}]}, or E_NO_HOUSE. It takes no argument.
declare
  v_player uuid := public.current_player_id();
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE', 'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  return jsonb_build_object('ok', true)
         || coalesce(public.level_marks_settle(v_player), jsonb_build_object('levels', '[]'::jsonb));
end
$body$
  $f$;
  execute $f$
create function public.reputation_lap(p_player uuid, p_lap uuid, p_net bigint, p_route text, p_lap_no int)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0356 (R4): A STANDING-ROUTE LAP CLOSED AT A GAIN. rep_lap, once a lap (her id is the key), inside the day's cap. A lap with
-- no gain returns before any read; a merchant after one players probe. Called by cmd.standing_route_close_lap alone.
begin
  if p_net is null or p_net <= 0 or p_player is null or p_lap is null then
    return 0;
  end if;
  if coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then
    return 0;
  end if;
  if public.wc('reputation_on') is distinct from 'true'::jsonb then
    return 0;
  end if;
  return public.reputation_credit(p_player, 'lap', public.wc_int('rep_lap'), 'lap:' || p_lap,
                                  jsonb_build_object('route', p_route, 'lap', p_lap_no));
end
$body$
  $f$;
  revoke all on function public.level_marks_settle(uuid) from public, anon, authenticated;
  revoke all on function public.reputation_lap(uuid, uuid, bigint, text, int) from public, anon, authenticated;
  revoke all on function cmd.level_up() from public, anon;
  grant execute on function cmd.level_up() to authenticated;

  -- ── 7. THE SEED: no back-pay. Every human's mark stands at her level as it was read in part 2. ──
  insert into public.house_level_marks (player_id, track, level)
  select x.player_id, x.track, x.level from seed_0356 x;

  -- ── 8. THE RE-CUTS (each hunk once) ──
  for d in select * from defs_0356 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0356 x where x.fn = d.fn order by x.n loop
      v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
      if v_n <> 1 then
        raise exception '0356 slice: hunk % of % occurs % time(s), expected exactly 1: the deployed body is not what this migration was written against', h.n, d.fn, v_n;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;
  select x.def into v_lap_old from defs_0356 x where x.fn = 'cmd.standing_route_close_lap(uuid,timestamp with time zone)';
  select x.def into v_arr_old from defs_0356 x where x.fn = 'public.reputation_arrival(uuid,uuid)';
  v_ms_make := extract(epoch from clock_timestamp() - v_t) * 1000;

  -- ── 9. THE SELF-ASSERT: the catalog ──
  v_t := clock_timestamp();
  for d in select * from defs_0356 order by fn loop
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0356 x where x.fn = d.fn order by x.n desc loop
      if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
        raise exception '0356 self-assert FAIL: hunk % of % is not in the new body exactly once', h.n, d.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> d.def then
      raise exception '0356 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
      into v_p from pg_proc pr where pr.oid = d.fn::regprocedure;
    if v_p.acl <> d.acl or v_p.vol <> d.vol or v_p.secdef <> d.secdef or v_p.cfg <> d.cfg then
      raise exception '0356 self-assert FAIL: % changed its ACL, volatility, definer or config', d.fn;
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (select f::regprocedure::oid from unnest(c_cut_fns || c_new_fns) f)) <> v_fn_before then
    raise exception '0356 self-assert FAIL: a function this file does not name moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> 'rep_level_per_level') <> v_cfg_before
     or (select c.value from public.world_config c where c.key = 'rep_level_per_level') is distinct from to_jsonb(10) then
    raise exception '0356 self-assert FAIL: an existing world_config row moved, or this file''s knob is not 10';
  end if;
  if has_function_privilege('anon', 'cmd.level_up()', 'execute') or not has_function_privilege('authenticated', 'cmd.level_up()', 'execute')
     or exists (select 1 from unnest(array['public.level_marks_settle(uuid)', 'public.reputation_lap(uuid,uuid,bigint,text,integer)']) f
                 cross join unnest(array['anon', 'authenticated']) r(role) where has_function_privilege(r.role, f, 'execute')) then
    raise exception '0356 self-assert FAIL: the door is not the signed-in caller''s alone, or a client may call a server function';
  end if;
  if exists (select 1 from unnest(array['anon', 'authenticated']) r(role)
              where has_table_privilege(r.role, 'public.house_level_marks', 'select,insert,update,delete'))
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.house_level_marks'::regclass) then
    raise exception '0356 self-assert FAIL: a client can read or write the marks, or the table has no row level security';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0356 self-assert FAIL: % client write grant(s)', (select count(*) from public.client_write_grants());
  end if;
  if (select count(*) from public.client_rpc_entry_points()) is distinct from v_entry + 1
     or not exists (select 1 from public.client_rpc_entry_points() e
                     where e.schema_name = 'cmd' and e.function_name = 'level_up' and e.arg_types = '' and e.fn = 'cmd.level_up()'::regprocedure) then
    raise exception '0356 self-assert FAIL: the registry did not gain cmd.level_up() and nothing else';
  end if;
  -- THE MARK IS NOT A LEVEL: only the settle and the card name the table (docs/REPUTATION.md 1.7), and the levels' own reader does not
  select string_agg(n.nspname || '.' || p.proname, ',' order by n.nspname, p.proname) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace where p.prokind in ('f', 'p') and p.prosrc like '%house_level_marks%';
  if v_def is distinct from 'public.level_marks_settle,public.reputation_card' then
    raise exception '0356 self-assert FAIL: the marks are named by other bodies than the settle and the card: %', v_def;
  end if;
  -- THE HOT PATH: a sale does not settle levels, and voyage.settle gained no line of this file
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where ((n.nspname = 'cmd' and p.proname like 'do\_sell%') or (n.nspname = 'voyage' and p.proname = 'settle'))
                and (p.prosrc like '%level_marks_settle%' or p.prosrc like '%level_up%')) then
    raise exception '0356 self-assert FAIL: a sale or voyage.settle names the level settle';
  end if;
  select string_agg(n.nspname || '.' || p.proname, ',' order by n.nspname, p.proname) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace where p.prokind in ('f', 'p') and p.prosrc like '%level_marks_settle(%';
  if v_def is distinct from 'cmd.level_up,public.reputation_arrival' then
    raise exception '0356 self-assert FAIL: the settle has other callers than the arrival and the door: %', v_def;
  end if;
  -- the seed: every human read in part 2 has her three marks, at the levels read (this file's own rows, by key)
  if exists (select 1 from seed_0356 x
              where not exists (select 1 from public.house_level_marks m where m.player_id = x.player_id and m.track = x.track and m.level = x.level)) then
    raise exception '0356 self-assert FAIL: a seeded mark did not land';
  end if;
  v_ms_catalog := extract(epoch from clock_timestamp() - v_t) * 1000;

  -- ── 10. THE SELF-ASSERT: probe houses of this file's own rows, rolled back ──
  v_t := clock_timestamp();
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    select p.id into v_far from public.ports p where p.kind = 'HARBOUR' and p.code <> 'LIS' order by p.code limit 1;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid, 'Casa do Nivel 0356', (select n.id from public.nations n where n.code = 'PRT'), 0, false) returning id into v_pl;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid2, 'Casa da Marca 0356', (select n.id from public.nations n where n.code = 'PRT'), 0, false) returning id into v_pl2;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid3, 'Casa da Porta 0356', (select n.id from public.nations n where n.code = 'PRT'), 0, false) returning id into v_pl3;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (null, 'Casa Mercante 0356', (select n.id from public.nations n where n.code = 'PRT'), 0, true) returning id into v_npc;
    v_gift := public.wc_int('rep_level_per_level');
    -- the miles that make Exploration level 4 and level 2 exactly, from the knobs the levels are derived by (one port reached each)
    v_nm4 := greatest(public.wc_num('level_points_per_step') * 9 - public.wc_num('fame_per_port'), 0) * public.wc_num('fame_nm_per_point');
    v_nm2 := greatest(public.wc_num('level_points_per_step') * 1 - public.wc_num('fame_per_port'), 0) * public.wc_num('fame_nm_per_point');

    -- (a) A NEW HOUSE: no mark, level 1 everywhere: nothing is paid, no row is made
    v_r := public.level_marks_settle(v_pl);
    if v_r is distinct from jsonb_build_object('levels', '[]'::jsonb)
       or exists (select 1 from public.house_level_marks m where m.player_id = v_pl)
       or exists (select 1 from public.events e where e.player_id = v_pl) then
      raise exception '0356 self-assert FAIL: a new house at level 1 was paid or marked: %', v_r;
    end if;

    -- (b) AT MARK 1 WITH THE MILES OF LEVEL 4: three LEVEL_UP events, 20 + 30 + 40 = 90, the mark at 4
    insert into public.events (player_id, kind, payload) values (v_pl, 'VOYAGE_REPORT', jsonb_build_object('to', 'P0356', 'total_nm', v_nm4));
    v_pp := public.player_progress(v_pl);
    if (v_pp -> 'exploration' ->> 'level')::int <> 4 or (v_pp -> 'trading' ->> 'level')::int <> 1 then
      raise exception '0356 self-assert FAIL: the probe''s miles did not make Exploration level 4: %', v_pp;
    end if;
    v_r := public.level_marks_settle(v_pl);
    if jsonb_array_length(v_r -> 'levels') <> 3
       or (select string_agg((e.payload ->> 'track') || ':' || (e.payload ->> 'level') || ':' || (e.payload ->> 'reputation'), ',' order by (e.payload ->> 'level')::int)
             from public.events e where e.player_id = v_pl and e.kind = 'LEVEL_UP')
          is distinct from format('exploration:2:%s,exploration:3:%s,exploration:4:%s', v_gift * 2, v_gift * 3, v_gift * 4)
       or (select string_agg(k.kind || ':' || k.delta || ':' || k.key, ',' order by k.seq) from public.reputation_book k where k.player_id = v_pl)
          is distinct from format('level:%s:level:exploration:2,level:%s:level:exploration:3,level:%s:level:exploration:4', v_gift * 2, v_gift * 3, v_gift * 4)
       or (select b.balance from public.reputation_balance b where b.player_id = v_pl) <> v_gift * 9
       or (select b.day_earned from public.reputation_balance b where b.player_id = v_pl) <> 0
       or (select string_agg(m.track || ':' || m.level, ',' order by m.track) from public.house_level_marks m where m.player_id = v_pl) is distinct from 'exploration:4' then
      raise exception '0356 self-assert FAIL: three crossings did not pay 20 + 30 + 40 with three events and the mark at 4: %', v_r;
    end if;
    if v_gift = 10 and (select b.balance from public.reputation_balance b where b.player_id = v_pl) <> 90 then
      raise exception '0356 self-assert FAIL: 20 + 30 + 40 is not 90';
    end if;

    -- (c) A SECOND CALL WRITES NOTHING; and the levels are still derived: player_progress is byte-equal
    select b.seq into v_seq from public.reputation_balance b where b.player_id = v_pl;
    v_r := public.level_marks_settle(v_pl);
    v_pp2 := public.player_progress(v_pl);
    if jsonb_array_length(v_r -> 'levels') <> 0 or v_pp2::text <> v_pp::text
       or (select b.seq from public.reputation_balance b where b.player_id = v_pl) <> v_seq
       or (select count(*) from public.events e where e.player_id = v_pl and e.kind = 'LEVEL_UP') <> 3
       or (select m.level from public.house_level_marks m where m.player_id = v_pl and m.track = 'exploration') <> 4 then
      raise exception '0356 self-assert FAIL: a second settle wrote something, or the settle moved her derived levels';
    end if;

    -- (d) COMBAT. Dark (not playable): her fights make no combat mark and no event. Lit: the track is settled as the others.
    v_fl1 := public.form_fleet(v_pl, 'Nivel', v_lis);
    v_voy := gen_random_uuid();
    insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
    values (v_voy, v_fl1, v_pl, '[]', 1, '{}', now() - interval '10 minutes', now() - interval '1 minute', 'ARRIVED', v_lis, v_lis);
    insert into public.voyage_events (voyage_id, day_index, kind, payload)
    select v_voy, g, 'PIRATES', jsonb_build_object('outcome', 'DRIVEN_OFF') from generate_series(1, 4) g;
    insert into public.events (player_id, kind, payload) values (v_pl, 'VOYAGE_REPORT', jsonb_build_object('to', 'P0356', 'total_nm', 0, 'voyage_id', v_voy));
    v_pp := public.player_progress(v_pl);
    v_r := public.level_marks_settle(v_pl);
    if not coalesce((v_pp -> 'combat' ->> 'playable')::boolean, false) then
      if jsonb_array_length(v_r -> 'levels') <> 0
         or exists (select 1 from public.house_level_marks m where m.player_id = v_pl and m.track = 'combat')
         or exists (select 1 from public.events e where e.player_id = v_pl and e.kind = 'LEVEL_UP' and e.payload ->> 'track' = 'combat') then
        raise exception '0356 self-assert FAIL: combat is not playable and was settled: %', v_r;
      end if;
      v_combat_note := 'combat is not playable in this world: four fights seen off made no mark and no event';
    else
      v_n := (v_pp -> 'combat' ->> 'level')::int;
      if (select count(*) from public.events e where e.player_id = v_pl and e.kind = 'LEVEL_UP' and e.payload ->> 'track' = 'combat') <> v_n - 1
         or coalesce((select m.level from public.house_level_marks m where m.player_id = v_pl and m.track = 'combat'), 1) <> v_n then
        raise exception '0356 self-assert FAIL: combat is playable and its % level(s) were not settled: %', v_n - 1, v_r;
      end if;
      v_combat_note := format('combat is playable in this world: four fights seen off reached level %s and each crossing fired once (the dark arm is CI''s proof 59)', v_n);
    end if;

    -- (e) NO BACK-PAY: a house whose mark stands at her level (as the seed leaves every human) is paid nothing
    insert into public.events (player_id, kind, payload) values (v_pl2, 'VOYAGE_REPORT', jsonb_build_object('to', 'P0356', 'total_nm', v_nm4));
    insert into public.house_level_marks (player_id, track, level)
    select v_pl2, x.track, (public.player_progress(v_pl2) -> x.track ->> 'level')::int from unnest(array['trading', 'exploration', 'combat']) x(track);
    v_r := public.level_marks_settle(v_pl2);
    if jsonb_array_length(v_r -> 'levels') <> 0 or (select m.level from public.house_level_marks m where m.player_id = v_pl2 and m.track = 'exploration') <> 4
       or exists (select 1 from public.reputation_book k where k.player_id = v_pl2)
       or exists (select 1 from public.events e where e.player_id = v_pl2 and e.kind = 'LEVEL_UP') then
      raise exception '0356 self-assert FAIL: a mark seeded at her level paid back: %', v_r;
    end if;

    -- (f) A MERCHANT: null, no mark, no event, no book row (with the miles of level 4 behind her)
    insert into public.events (player_id, kind, payload) values (v_npc, 'VOYAGE_REPORT', jsonb_build_object('to', 'P0356', 'total_nm', v_nm4));
    if public.level_marks_settle(v_npc) is not null or public.level_marks_settle(null) is not null
       or exists (select 1 from public.house_level_marks m where m.player_id = v_npc)
       or exists (select 1 from public.events e where e.player_id = v_npc and e.kind = 'LEVEL_UP')
       or exists (select 1 from public.reputation_book k where k.player_id = v_npc) then
      raise exception '0356 self-assert FAIL: a merchant was settled';
    end if;

    -- (g) THE DOOR AND THE READ, as she calls them: nobody signed in is refused; her crossing is paid once; the card serves the mark and the gift
    if (cmd.level_up() ->> 'error_code') is distinct from 'E_NO_HOUSE' then
      raise exception '0356 self-assert FAIL: the door answered a caller with no house';
    end if;
    insert into public.events (player_id, kind, payload) values (v_pl3, 'VOYAGE_REPORT', jsonb_build_object('to', 'P0356', 'total_nm', v_nm2));
    perform cmd.assume_identity(c_uid3);
    v_r := world.player() -> 'player';
    if (v_r -> 'levels' -> 'exploration' ->> 'level')::int <> 2
       or (v_r -> 'reputation' -> 'level_marks') is distinct from jsonb_build_object('trading', 1, 'exploration', 1, 'combat', 1)
       or (v_r -> 'reputation' ->> 'level_gift')::int <> v_gift then
      raise exception '0356 self-assert FAIL: before the door, world.player() does not serve level 2 over a mark of 1 and the gift: %', v_r -> 'reputation';
    end if;
    v_r := cmd.level_up();
    if (v_r ->> 'ok')::boolean is not true
       or (v_r -> 'levels') is distinct from jsonb_build_array(jsonb_build_object('track', 'exploration', 'level', 2, 'reputation', v_gift * 2)) then
      raise exception '0356 self-assert FAIL: the door did not pay her one crossing: %', v_r;
    end if;
    v_r := cmd.level_up();
    if (v_r ->> 'ok')::boolean is not true or jsonb_array_length(v_r -> 'levels') <> 0
       or (select count(*) from public.events e where e.player_id = v_pl3 and e.kind = 'LEVEL_UP') <> 1 then
      raise exception '0356 self-assert FAIL: the door paid twice: %', v_r;
    end if;
    v_r := world.player() -> 'player' -> 'reputation';
    if (v_r -> 'level_marks' ->> 'exploration')::int <> 2 or (v_r ->> 'balance')::int <> v_gift * 2
       or (v_r -> 'recent' -> 0 ->> 'kind') <> 'level' then
      raise exception '0356 self-assert FAIL: after the door, the card does not serve the mark at 2 and the gift: %', v_r;
    end if;

    -- (h) THE KNOB AT 0 (this file's own knob, put back by the rollback): the moment fires, with no gift and no book row
    update public.world_config set value = to_jsonb(0) where key = 'rep_level_per_level';
    insert into public.events (player_id, kind, payload) values (v_pl3, 'VOYAGE_REPORT', jsonb_build_object('to', 'Q0356', 'total_nm', v_nm4));
    select b.seq into v_seq from public.reputation_balance b where b.player_id = v_pl3;
    v_r := cmd.level_up();
    v_n := (public.player_progress(v_pl3) -> 'exploration' ->> 'level')::int;
    if v_n < 3 or jsonb_array_length(v_r -> 'levels') <> v_n - 2
       or exists (select 1 from jsonb_array_elements(v_r -> 'levels') x where (x ->> 'reputation')::int <> 0)
       or (select b.seq from public.reputation_balance b where b.player_id = v_pl3) <> v_seq
       or (select m.level from public.house_level_marks m where m.player_id = v_pl3 and m.track = 'exploration') <> v_n then
      raise exception '0356 self-assert FAIL: with the gift at 0 a crossing booked something, or did not fire: %', v_r;
    end if;
    update public.world_config set value = to_jsonb(10) where key = 'rep_level_per_level';

    -- (i) AN ARRIVAL calls the settle (public.reputation_arrival, a stub voyage: voyage.settle itself is CI's proof 59), and OLD against NEW
    v_fl2 := public.form_fleet(v_pl2, 'Marca', v_lis);
    delete from public.house_level_marks m where m.player_id = v_pl2 and m.track = 'exploration';   -- the probe's own row: she stands unpaid at level 4 again
    v_voy := gen_random_uuid();
    insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
    values (v_voy, v_fl2, v_pl2, '[]', 50, '{}', now() - interval '10 minutes', now() - interval '1 minute', 'ARRIVED', v_lis, null);
    v_n := public.reputation_arrival(v_pl2, v_voy);
    if v_n <> 0 or (select count(*) from public.events e where e.player_id = v_pl2 and e.kind = 'LEVEL_UP') <> 3
       or (select m.level from public.house_level_marks m where m.player_id = v_pl2 and m.track = 'exploration') <> 4
       or (select b.balance from public.reputation_balance b where b.player_id = v_pl2) <> v_gift * 9 then
      raise exception '0356 self-assert FAIL: an arrival did not settle her three crossings (its own earn stays its own: %)', v_n;
    end if;
    begin
      execute replace(v_arr_old, 'FUNCTION public.reputation_arrival(', 'FUNCTION pg_temp.arrival_old_0356(');
      v_tm := clock_timestamp();
      for i in 1 .. 40 loop
        exit when clock_timestamp() - v_tm > interval '2 seconds';
        v_voy := gen_random_uuid();
        insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
        values (v_voy, v_fl2, v_pl2, '[]', 50, '{}', now() - interval '10 minutes', now() - interval '1 minute', 'ARRIVED', v_lis, null);
        if i % 2 = 0 then
          t1 := clock_timestamp(); perform pg_temp.arrival_old_0356(v_pl2, v_voy);
          t2 := clock_timestamp(); perform public.reputation_arrival(v_pl2, v_voy);
          t3 := clock_timestamp();
          v_aold_ms := v_aold_ms + extract(epoch from t2 - t1) * 1000; v_anew_ms := v_anew_ms + extract(epoch from t3 - t2) * 1000;
        else
          t1 := clock_timestamp(); perform public.reputation_arrival(v_pl2, v_voy);
          t2 := clock_timestamp(); perform pg_temp.arrival_old_0356(v_pl2, v_voy);
          t3 := clock_timestamp();
          v_anew_ms := v_anew_ms + extract(epoch from t2 - t1) * 1000; v_aold_ms := v_aold_ms + extract(epoch from t3 - t2) * 1000;
        end if;
        v_apairs := v_apairs + 1;
      end loop;
    exception when others then   -- a measurement, never a gate
      v_meas_note := v_meas_note || ' (the arrival measurement stopped: ' || left(sqlerrm, 80) || ')';
    end;

    -- (j) A LAP. The helper's arithmetic first: a gain pays rep_lap once a lap; no gain, a loss and a merchant pay nothing.
    v_lap_pay := public.wc_int('rep_lap');
    v_lap := gen_random_uuid();
    select b.seq into v_seq from public.reputation_balance b where b.player_id = v_pl;
    v_n := public.reputation_lap(v_pl, v_lap, 500, 'Rota', 1);
    v_m := public.reputation_lap(v_pl, v_lap, 500, 'Rota', 1);
    if v_n <> v_lap_pay or v_m <> 0
       or public.reputation_lap(v_pl, gen_random_uuid(), -500, 'Rota', 2) <> 0 or public.reputation_lap(v_pl, gen_random_uuid(), 0, 'Rota', 3) <> 0
       or public.reputation_lap(v_npc, gen_random_uuid(), 500, 'Rota', 1) <> 0
       or (select b.seq from public.reputation_balance b where b.player_id = v_pl) <> v_seq + sign(v_lap_pay)::int
       or (v_lap_pay > 0 and (select k.kind || ':' || k.delta || ':' || k.key from public.reputation_book k where k.player_id = v_pl and k.seq = v_seq + 1)
                              is distinct from 'lap:' || v_lap_pay || ':lap:' || v_lap)
       or exists (select 1 from public.reputation_book k where k.player_id = v_npc) then
      raise exception '0356 self-assert FAIL: a lap at a gain did not pay % once, or a lap with no gain, a loss or a merchant paid (% then %)', v_lap_pay, v_n, v_m;
    end if;
    -- Then the real door, cmd.standing_route_close_lap, on a probe route of each kind. Where this world refuses a probe its
    -- route or its cargo, that is printed and the real lap is left to CI's proof 59.
    v_ok := false;
    begin
      select g.code into v_good_code
        from public.port_goods pg join public.goods g on g.id = pg.good_id
       where pg.port_id = v_lis and g.bulk <= 1 and pg.stock_target > 0
       order by pg.stock_target desc, g.code limit 1;
      perform public.commission_ship(v_pl, v_fl1, 'barca', 'Nivel', true, true);
      v_nfl := public.form_fleet(v_npc, 'Mercante', v_lis);
      perform public.commission_ship(v_npc, v_nfl, 'barca', 'Mercante', true, true);
      insert into public.standing_routes (player_id, name, fleet_id) values (v_pl, 'Rota 0356', v_fl1) returning id into v_route;
      insert into public.standing_routes (player_id, name, fleet_id) values (v_npc, 'Rota 0356 M', v_nfl) returning id into v_nroute;
      if v_good_code is null or public.fleet_load(v_fl1, v_good_code, 5, 100) <> 5 then
        raise exception 'no good to load at Lisbon';
      end if;
      v_ok := true;
    exception when others then
      v_lap_note := 'this world refused the probe its route or its cargo (' || left(sqlerrm, 90) || '): the real lap was NOT RUN HERE, proved in CI by proof 59';
    end;
    if v_ok then
      -- lap 1: 5 units aboard at cost and none carried in: a gain. It pays once. Lap 2: the same cargo carried in and out: no gain, nothing.
      select b.seq into v_seq from public.reputation_balance b where b.player_id = v_pl;
      insert into public.standing_route_laps (route_id, lap_no, started_at) values (v_route, 1, now()) returning id into v_lap;
      update public.standing_routes set lap_id = v_lap, lap_no = 1 where id = v_route;
      perform cmd.standing_route_close_lap(v_route, now());
      if (select x.net from public.standing_route_laps x where x.id = v_lap) <= 0
         or (select b.seq from public.reputation_balance b where b.player_id = v_pl) <> v_seq + sign(v_lap_pay)::int
         or (v_lap_pay > 0 and (select k.kind || ':' || k.delta || ':' || k.key || ':' || (k.note ->> 'route') || ':' || (k.note ->> 'lap')
                                  from public.reputation_book k where k.player_id = v_pl and k.seq = v_seq + 1)
                                is distinct from 'lap:' || v_lap_pay || ':lap:' || v_lap || ':Rota 0356:1') then
        raise exception '0356 self-assert FAIL: a real lap closed at a gain of % did not book % once', (select x.net from public.standing_route_laps x where x.id = v_lap), v_lap_pay;
      end if;
      select b.seq into v_seq from public.reputation_balance b where b.player_id = v_pl;
      insert into public.standing_route_laps (route_id, lap_no, started_at) values (v_route, 2, now()) returning id into v_lap;
      update public.standing_routes set lap_id = v_lap, lap_no = 2 where id = v_route;
      perform cmd.standing_route_close_lap(v_route, now());
      if (select x.net from public.standing_route_laps x where x.id = v_lap) <> 0
         or (select b.seq from public.reputation_balance b where b.player_id = v_pl) <> v_seq
         or (select count(*) from public.events e where e.player_id = v_pl and e.kind = 'ROUTE_LAP') <> 2 then
        raise exception '0356 self-assert FAIL: a real lap closed with no gain booked something, or the two laps did not report';
      end if;
      v_lap_note := format('a real lap closed at a gain booked %s once; a real lap with no gain booked nothing', v_lap_pay);
      -- OLD against NEW cmd.standing_route_close_lap on a probe merchant, every lap at a gain (the dearest arm for her: one players probe), interleaved, 2 s
      begin
        execute replace(v_lap_old, 'FUNCTION cmd.standing_route_close_lap(', 'FUNCTION pg_temp.close_lap_old_0356(');
        v_tm := clock_timestamp();
        for i in 1 .. 60 loop
          exit when clock_timestamp() - v_tm > interval '2 seconds';
          for j in 0 .. 1 loop
            perform public.fleet_load(v_nfl, v_good_code, 0.2, 100);   -- more aboard than the lap before: this lap closes at a gain
            insert into public.standing_route_laps (route_id, lap_no, started_at) values (v_nroute, i * 2 + j, now()) returning id into v_lap;
            update public.standing_routes set lap_id = v_lap, lap_no = i * 2 + j where id = v_nroute;
            t1 := clock_timestamp();
            if (i + j) % 2 = 0 then
              perform pg_temp.close_lap_old_0356(v_nroute, now());
              v_old_ms := v_old_ms + extract(epoch from clock_timestamp() - t1) * 1000;
            else
              perform cmd.standing_route_close_lap(v_nroute, now());
              v_new_ms := v_new_ms + extract(epoch from clock_timestamp() - t1) * 1000;
            end if;
            if (select x.net from public.standing_route_laps x where x.id = v_lap) <= 0 then
              raise exception 'a probe merchant lap did not close at a gain';
            end if;
          end loop;
          v_pairs := v_pairs + 1;
        end loop;
      exception when others then   -- a measurement, never a gate
        v_meas_note := v_meas_note || ' (the lap measurement stopped: ' || left(sqlerrm, 80) || ')';
      end;
      if exists (select 1 from public.reputation_book k where k.player_id = v_npc) or exists (select 1 from public.reputation_balance b where b.player_id = v_npc)
         or exists (select 1 from public.house_level_marks m where m.player_id = v_npc) then
        raise exception '0356 self-assert FAIL: a merchant''s real laps wrote a Reputation row or a mark';
      end if;
    end if;
    set constraints public.reputation_reconciles immediate;   -- every probe row of this transaction reconciles
    set constraints public.reputation_reconciles deferred;
    raise exception using errcode = 'ZX356', message = 'PROBE_ROLLBACK_0356';
  exception when sqlstate 'ZX356' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0356 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like 'Casa % 0356' or p.auth_uid in (c_uid, c_uid2, c_uid3))
     or (select c.value from public.world_config c where c.key = 'rep_level_per_level') is distinct from to_jsonb(10)
     or to_regprocedure('pg_temp.close_lap_old_0356(uuid,timestamp with time zone)') is not null
     or to_regprocedure('pg_temp.arrival_old_0356(uuid,uuid)') is not null
     or exists (select 1 from public.house_level_marks m where not exists (select 1 from seed_0356 x where x.player_id = m.player_id and x.track = m.track)) then
    raise exception '0356 self-assert FAIL: the probe left something behind';
  end if;
  if public.current_player_id() is not null then
    raise exception '0356 self-assert FAIL: the probe''s identity outlived its rollback';
  end if;
  v_ms_probe := extract(epoch from clock_timestamp() - v_t) * 1000;

  -- ── 11. THE FOREIGN KEY, LAST: the one lock this file takes on public.players, held from here to the commit ──
  v_t := clock_timestamp();
  alter table public.house_level_marks
    add constraint house_level_marks_player_id_fkey foreign key (player_id) references public.players(id) on delete cascade;
  v_ms_fk := extract(epoch from clock_timestamp() - v_t) * 1000;

  -- THIS FILE'S OWN UPDATE ROW (0347's news law), counted by its own key
  perform public.news_update('0356', 'Level up: Reputation gift', '레벨 업: 평판 선물');
  if (select count(*) from public.world_news w where w.key = 'update:0356') <> 1 then
    raise exception '0356 self-assert FAIL: this file''s UPDATE row is not one row';
  end if;
  raise notice '0356 time: pre-images % ms; the seed reads % ms for % human(s) (the slowest % ms; no lock held); table, knob, functions, seed and re-cuts % ms; catalog asserts % ms; probe % ms; the foreign key (the lock on players starts here) % ms; in all % ms.',
    round(v_ms_pre), round(v_ms_seed), v_seeded, round(v_ms_seed_max), round(v_ms_make), round(v_ms_catalog), round(v_ms_probe), round(v_ms_fk, 1),
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  raise notice '0356 cost: public.reputation_arrival on a probe human (a stub voyage in open water, a few events behind her), OLD and NEW interleaved, % pair(s): OLD % ms, NEW % ms an arrival. cmd.standing_route_close_lap on a probe merchant, every lap at a gain, OLD and NEW interleaved, % lap(s) each: OLD % ms, NEW % ms a lap%.',
    v_apairs, case when v_apairs > 0 then round(v_aold_ms / v_apairs, 2) end, case when v_apairs > 0 then round(v_anew_ms / v_apairs, 2) end,
    v_pairs, case when v_pairs > 0 then round(v_old_ms / v_pairs, 2) end, case when v_pairs > 0 then round(v_new_ms / v_pairs, 2) end, v_meas_note;
  raise notice '0356 self-assert ok: A LEVEL CROSSED IS A MOMENT (R4). One table no client reads or writes, one knob (rep_level_per_level 10), three functions (one door for the signed-in caller, two no client calls); 4 hunks, each once and reversing, ACL, volatility, definer and config unmoved; no other function and no existing knob moved; the registry gained cmd.level_up() alone; 0 client write grants; only the settle and the card name the marks; only the arrival and the door call the settle; no sale and no line of voyage.settle names it. % human(s) seeded at their levels (no back-pay). The probe (rolled back): a new house was paid nothing; at mark 1 with the miles of level 4, three LEVEL_UP events paid 20 + 30 + 40 = 90 and the mark stood at 4; a second call wrote nothing and player_progress was byte-equal; %; a mark at her level paid nothing back; a merchant: null and no row; the door refused nobody-signed-in, paid her crossing once, and the card served the mark and the gift; with the gift at 0 the moment fired with no book row; an arrival settled three crossings; a lap at a gain paid % once, and no gain, a loss and a merchant nothing; %. Turnover through the real doors and the real arrival are proved in CI (proof 59).',
    v_seeded, v_combat_note, v_lap_pay, v_lap_note;
end
$m$;
