-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0146 — THE FLAG FOLLOWS THE MONEY  (docs/INFLUENCE.md slice I4)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- O1 (2026-10-17): "each country will have 3~4 cities around them, and rest of them can be
-- competitive" — a contested city goes to the country with the most influence.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) public.tick_influence(p_now) — THE DAILY COUNT (D4), steps of docs/INFLUENCE.md §4.3:
--       1 DECAY   every row × (1 − influence_decay) (D6), today's gifts reset (D7's day); rows under
--                 one point go.
--       2 RANK    per contested harbour, public.influence_shares → the leader and the holder's points.
--       3 CHANGE  a held city goes to a challenger with ≥ influence_flip_lead × the holder's (D5);
--                 a free city to a leader with ≥ influence_claim_min (D5). A home city is never
--                 written (its row's trigger, 0143, would refuse it anyway). A city never goes back
--                 to no country. Each change: port_allegiance (nation, since) and one FLAG_CHANGED
--                 event for every PLAYER company of the two countries concerned (the History line —
--                 merchants have no History to read).
--       6 RECEIPT jsonb: decayed, removed, changed [{port, from, to}], claimed, ms per step.
--     lock_timeout 2 s; each step in its own exception block, the error in the receipt; contested
--     rows taken FOR UPDATE SKIP LOCKED. Dark (influence_enabled false) it does nothing at all.
-- (2) Cron `byeharu-voyage:influence` at influence_count_utc (00:47 UTC, 09:47 KST) daily, DEFINED
--     INACTIVE (0078's rule). wind_the_clock() would start it — harmless dark: tick_influence writes
--     nothing while the race is off.
-- (3) public.influence_switch(p_on): true lights the race (influence_enabled — Donate, the
--     merchants' where-rule, the count) and starts the job; false puts every consequence back at
--     once. The book is left alone either way (posting runs lit or dark, I2). NOT CALLED HERE.
-- (4) public.influence_next_count(p_now): the one reading of when the next count runs, from the
--     same knob the job was scheduled from; the Town Hall serves it (`influence.next_count`).
-- (5) Knobs influence_decay 0.10 (D6), influence_count_utc '00:47' (D4).
--
-- ── DECISIONS TAKEN HERE (stated, not hidden) ───────────────────────────────────────────────────
-- * NOT THE OWNER'S — a change of flag writes a History line to the PLAYER companies of the two
--   countries (the plan said "every company"; a merchant has no History to read, and 200 rows a
--   change would be noise in the event table).
--
-- ── THE PROOF (in this file) ────────────────────────────────────────────────────────────────────
-- On probe rows (rolled back, the race lit inside the probe): decay to the coin; a 9 % lead keeps
-- the holder and an 11 % lead changes it; a free city is claimed at the minimum and not below; a
-- home city never changes, however far behind; a probe player of the old country gets the
-- FLAG_CHANGED line; the receipt equals a recount; dark it writes nothing. The run on the live world
-- is timed by raise notice only. town_hall_influence reverses to its pre-image.
--
-- ROLLBACK: influence_switch(false); cron.unschedule('byeharu-voyage:influence'). Flags already
-- changed stay (they are true facts of the game so far).
-- SUPERSEDES, by a hunk sliced from the LIVE body: world.town_hall_influence (0144).
-- VERSION: 0146. Applies on 0145.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0146(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

create temp table defs_before_0146 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from (values ('world.town_hall_influence(uuid, uuid)')) f(fn);

-- ── 1. THE KNOBS ───────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('influence_decay', to_jsonb(0.10),
   '0146 (D6): the share of every country''s influence that wears away at each daily count.'),
  ('influence_count_utc', to_jsonb('00:47'::text),
   '0146 (D4): the time of day (UTC, HH:MM) the daily count runs. The cron job is scheduled from it '
   'here and public.influence_next_count reads it; re-schedule the job if it moves.')
on conflict (key) do nothing;

-- ── 2. THE COUNT ───────────────────────────────────────────────────────────────────────────────
create or replace function public.influence_next_count(p_now timestamptz default now())
returns timestamptz
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0146: THE one reading of when the next daily count runs — the first influence_count_utc after
-- p_now. The job's schedule was built from the same knob (this file).
declare
  v_at time := (public.wc('influence_count_utc') #>> '{}')::time;
  v_day timestamptz := date_trunc('day', p_now at time zone 'UTC') at time zone 'UTC';
begin
  if v_day + v_at > p_now then
    return v_day + v_at;
  end if;
  return v_day + interval '1 day' + v_at;
end $$;
revoke all on function public.influence_next_count(timestamptz) from public, anon, authenticated;

create or replace function public.tick_influence(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0146: THE DAILY COUNT (docs/INFLUENCE.md §4.3, D4 D5 D6). Dark, nothing. Lit: decay, rank,
-- change of country, receipt. Never waits on a lock longer than 2 s; a contested row someone else
-- holds is skipped (counted) and counted again tomorrow. Mayor (I5) and fame (I6) are its later
-- steps.
declare
  v_t       timestamptz;
  v_ms      jsonb := '{}'::jsonb;
  v_err     jsonb := '[]'::jsonb;
  v_decayed int := 0;
  v_removed int := 0;
  v_changed jsonb := '[]'::jsonb;
  v_claimed int := 0;
  v_skipped int := 0;
  v_lead    numeric := public.wc_num('influence_flip_lead');
  v_claim   numeric := public.wc_num('influence_claim_min');
  a         record;
  v_top     record;
  v_held    numeric;
  v_total   numeric;
  v_from    public.nations%rowtype;
  v_to      public.nations%rowtype;
  v_pname   text;
begin
  if not public.influence_on() then
    return jsonb_build_object('enabled', false, 'at', p_now);
  end if;
  perform set_config('lock_timeout', '2s', true);

  -- 1 DECAY (D6) and the day's gifts reset (D7)
  v_t := clock_timestamp();
  begin
    update public.port_influence set points = points * (1 - public.wc_num('influence_decay')), day_given = 0, updated_at = p_now;
    get diagnostics v_decayed = row_count;
    delete from public.port_influence where points < 1;
    get diagnostics v_removed = row_count;
  exception when others then
    v_err := v_err || jsonb_build_object('step', 'decay', 'error', sqlerrm);
  end;
  v_ms := v_ms || jsonb_build_object('decay', round(extract(epoch from clock_timestamp() - v_t) * 1000));

  -- 2 RANK and 3 CHANGE — contested harbours only
  v_t := clock_timestamp();
  begin
    for a in select pa.port_id from public.port_allegiance pa where not pa.home order by pa.port_id loop
      begin
        perform 1 from public.port_allegiance x where x.port_id = a.port_id for update skip locked;
        if not found then
          v_skipped := v_skipped + 1;
          continue;
        end if;
        select s.nation_id, s.points into v_top from public.influence_shares(a.port_id) s limit 1;
        continue when v_top.nation_id is null;
        select coalesce(sum(s.points), 0) into v_total from public.influence_shares(a.port_id) s;
        select coalesce((select s.points from public.influence_shares(a.port_id) s where s.nation_id = public.port_nation(a.port_id)), 0)
          into v_held;
        select n.* into v_from from public.nations n where n.id = public.port_nation(a.port_id);
        continue when v_from.id = v_top.nation_id;
        if v_from.id is null then
          continue when v_top.points < v_claim;
          v_claimed := v_claimed + 1;
        else
          continue when v_top.points < v_lead * v_held;
        end if;
        select n.* into v_to from public.nations n where n.id = v_top.nation_id;
        select p.name into v_pname from public.ports p where p.id = a.port_id;
        update public.port_allegiance set nation_id = v_to.id, since = p_now where port_id = a.port_id;
        perform public.emit_event(pl.id, 'FLAG_CHANGED', jsonb_build_object(
                  'port', (select p.code from public.ports p where p.id = a.port_id), 'port_name', v_pname,
                  'from', v_from.code, 'from_name', v_from.name, 'to', v_to.code, 'to_name', v_to.name,
                  'share_to', round(v_top.points / nullif(v_total, 0), 4),
                  'share_from', round(v_held / nullif(v_total, 0), 4)))
           from public.players pl
          where not pl.is_npc and pl.nation_id in (v_to.id, v_from.id);
        v_changed := v_changed || jsonb_build_object('port', (select p.code from public.ports p where p.id = a.port_id),
                                                     'from', v_from.code, 'to', v_to.code);
      exception when others then
        v_err := v_err || jsonb_build_object('step', 'change', 'port', a.port_id, 'error', sqlerrm);
      end;
    end loop;
  exception when others then
    v_err := v_err || jsonb_build_object('step', 'rank', 'error', sqlerrm);
  end;
  v_ms := v_ms || jsonb_build_object('change', round(extract(epoch from clock_timestamp() - v_t) * 1000));

  -- 6 RECEIPT
  return jsonb_build_object('enabled', true, 'at', p_now, 'decayed', v_decayed, 'removed', v_removed,
                            'changed', v_changed, 'claimed', v_claimed, 'skipped', v_skipped,
                            'errors', v_err, 'ms', v_ms);
end $$;
comment on function public.tick_influence(timestamptz) is
  '0146: THE daily count (decay, change of country; I5 adds the mayor, I6 the fame). Cron '
  'byeharu-voyage:influence. Dark it writes nothing. Server-only.';
revoke all on function public.tick_influence(timestamptz) from public, anon, authenticated;

-- ── 3. THE JOB (defined inactive) AND THE SWITCH ───────────────────────────────────────────────
do $$
declare
  v_at time := (public.wc('influence_count_utc') #>> '{}')::time;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice '0146: pg_cron is not installed here, so byeharu-voyage:influence was NOT scheduled — as expected under PGlite. Call public.tick_influence() by hand.';
    return;
  end if;
  perform cron.schedule('byeharu-voyage:influence',
                        format('%s %s * * *', extract(minute from v_at)::int, extract(hour from v_at)::int),
                        'select public.tick_influence()');
  -- 0078: DEFINED, NOT RUNNING. public.influence_switch(true) starts it (and wind_the_clock() would
  -- too — harmless dark: tick_influence writes nothing while the race is off).
  perform cron.alter_job(jobid, active := false) from cron.job where jobname = 'byeharu-voyage:influence';
  raise notice '0146: pg_cron present — byeharu-voyage:influence SCHEDULED BUT INACTIVE until influence_switch(true).';
end $$;

create or replace function public.influence_switch(p_on boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0146: THE switch of the country race (docs/INFLUENCE.md §7). true: influence_enabled — Donate
-- opens, the merchants give where their country's race is closest, the daily count runs (its job is
-- started). false: every consequence back at once; the job stays scheduled and does nothing. The
-- book is never touched (Invest counts lit or dark).
begin
  update public.world_config set value = to_jsonb(coalesce(p_on, false)) where key = 'influence_enabled';
  if coalesce(p_on, false) and exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $c$select cron.alter_job(j.jobid, active := true) from public.clock_jobs() j
                where j.jobname = 'byeharu-voyage:influence' and not j.active$c$;
  end if;
  return jsonb_build_object('enabled', public.influence_on(), 'next_count', public.influence_next_count(now()));
end $$;
revoke all on function public.influence_switch(boolean) from public, anon, authenticated;

-- ── 4. THE TOWN HALL SAYS WHEN THE NEXT COUNT IS ───────────────────────────────────────────────
create temp table hunks_0146 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0146 values
('world.town_hall_influence(uuid, uuid)', 1,
$h$    'open', public.city_treasury_on() and public.influence_on(),$h$,
$h$    'open', public.city_treasury_on() and public.influence_on(),
    -- 0146: when the daily count next runs (null while the race is off).
    'next_count', case when public.influence_on() then public.influence_next_count(now()) end,$h$);

do $$
declare
  v_def text := (select def from defs_before_0146);
  h record;
begin
  for h in select * from hunks_0146 order by n loop
    if pg_temp.occurs_0146(v_def, h.old) <> 1 then
      raise exception '0146 self-assert FAIL: hunk % of % does not occur exactly once in the live body', h.n, h.fn;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
  v_def := replace(pg_get_functiondef('world.town_hall_influence(uuid, uuid)'::regprocedure), E'\r', '');
  for h in select * from hunks_0146 order by n desc loop
    v_def := replace(v_def, h.new, h.old);
  end loop;
  if v_def <> (select def from defs_before_0146)
     or (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'world.town_hall_influence(uuid, uuid)'::regprocedure)
        <> (select acl from defs_before_0146) then
    raise exception '0146 self-assert FAIL: world.town_hall_influence does not reverse to its pre-image, or its ACL moved';
  end if;
end $$;

-- ── 5. THE PROOF ───────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.probe_0146()
returns jsonb
language plpgsql
as $$
declare
  c_uid  constant uuid := '00000000-0146-4000-8000-000000000001';
  v_prt  uuid := (select id from public.nations where code = 'PRT');
  v_esp  uuid := (select id from public.nations where code = 'ESP');
  v_x    uuid;
  v_y    uuid;
  v_me   uuid;
  v_keep uuid;
  v_flip uuid;
  v_free uuid;
  v_few  uuid;
  v_home uuid;
  v_r    jsonb;
  v_dark jsonb;
  v_t    timestamptz;
  v_live jsonb;
  v_out  jsonb;
begin
  begin
    -- dark: nothing at all
    v_dark := public.tick_influence(now());
    if v_dark->>'enabled' <> 'false' then
      raise exception '0146 self-assert FAIL: the count ran dark: %', v_dark;
    end if;
    -- the live world, lit, timed (a notice, never a gate: prod CPU is burstable)
    update public.world_config set value = 'true'::jsonb where key = 'influence_enabled';
    v_t := clock_timestamp();
    v_live := public.tick_influence(now());
    raise notice '0146: the daily count on this world took % ms (%)', round(extract(epoch from clock_timestamp() - v_t) * 1000), v_live;
    if jsonb_array_length(v_live->'errors') > 0 then
      raise exception '0146 self-assert FAIL: the count on this world reported errors: %', v_live->'errors';
    end if;

    -- the probe rows: two merchant companies stand for PRT and ESP, a probe player sails for PRT
    select h.player_id into v_x from public.npc_houses h order by md5(h.player_id::text || '0146x') limit 1;
    select h.player_id into v_y from public.npc_houses h where h.player_id <> v_x order by md5(h.player_id::text || '0146y') limit 1;
    update public.players set nation_id = v_prt where id = v_x;
    update public.players set nation_id = v_esp where id = v_y;
    v_me := public.new_house(c_uid, 'Casa da Contagem 0146', 'PRT');
    select port_id into v_keep from public.port_allegiance where not home order by md5(port_id::text || 'k') limit 1;
    select port_id into v_flip from public.port_allegiance where not home and port_id <> v_keep order by md5(port_id::text || 'f') limit 1;
    select port_id into v_free from public.port_allegiance where not home and port_id not in (v_keep, v_flip) order by md5(port_id::text || 'c') limit 1;
    select port_id into v_few from public.port_allegiance where not home and port_id not in (v_keep, v_flip, v_free) order by md5(port_id::text || 'w') limit 1;
    select port_id into v_home from public.port_allegiance where home and nation_id = v_prt order by port_id limit 1;
    delete from public.port_influence where port_id in (v_keep, v_flip, v_free, v_few, v_home);
    update public.port_allegiance set nation_id = v_prt where port_id in (v_keep, v_flip);
    update public.port_allegiance set nation_id = null where port_id in (v_free, v_few);
    insert into public.port_influence (port_id, nation_id, player_id, points, day_given) values
      (v_keep, v_prt, v_x, 1000, 500), (v_keep, v_esp, v_y, 1090, 0),          -- ESP +9 %: PRT keeps it
      (v_flip, v_prt, v_x, 1000, 0),   (v_flip, v_esp, v_y, 1110, 0),          -- ESP +11 %: ESP takes it
      (v_free, v_esp, v_y, 11200, 0),                                           -- 10,080 after decay: claimed
      (v_few, v_esp, v_y, 11000, 0),                                            -- 9,900 after decay: not
      (v_home, v_esp, v_y, 1000000000, 0);                                      -- a home city never changes

    v_r := public.tick_influence(now());

    if (select points from public.port_influence where port_id = v_keep and nation_id = v_prt) <> 1000 * (1 - public.wc_num('influence_decay'))
       or (select day_given from public.port_influence where port_id = v_keep and nation_id = v_prt) <> 0 then
      raise exception '0146 self-assert FAIL: decay is not to the coin, or the day''s gifts were not reset';
    end if;
    if public.port_nation(v_keep) <> v_prt then raise exception '0146 self-assert FAIL: a 9 %% lead changed the flag'; end if;
    if public.port_nation(v_flip) <> v_esp then raise exception '0146 self-assert FAIL: an 11 %% lead did not change the flag'; end if;
    if public.port_nation(v_free) is distinct from v_esp then raise exception '0146 self-assert FAIL: a free city at the minimum was not claimed'; end if;
    if public.port_nation(v_few) is not null then raise exception '0146 self-assert FAIL: a free city under the minimum was claimed'; end if;
    if public.port_nation(v_home) <> v_prt then raise exception '0146 self-assert FAIL: a home city changed hands'; end if;
    if not exists (select 1 from public.events e where e.player_id = v_me and e.kind = 'FLAG_CHANGED'
                    and e.payload->>'port' = (select code from public.ports where id = v_flip) and e.payload->>'to' = 'ESP')
       or exists (select 1 from public.events e where e.player_id in (v_x, v_y) and e.kind = 'FLAG_CHANGED') then
      raise exception '0146 self-assert FAIL: the History line went to the wrong companies';
    end if;
    -- the receipt is a recount
    if not exists (select 1 from jsonb_array_elements(v_r->'changed') c where c->>'port' = (select code from public.ports where id = v_flip) and c->>'to' = 'ESP')
       or not exists (select 1 from jsonb_array_elements(v_r->'changed') c where c->>'port' = (select code from public.ports where id = v_free) and c->>'from' is null)
       or exists (select 1 from jsonb_array_elements(v_r->'changed') c where c->>'port' in ((select code from public.ports where id = v_keep), (select code from public.ports where id = v_few), (select code from public.ports where id = v_home)))
       or (v_r->>'claimed')::int < 1
       or (v_r->>'decayed')::int <> (select count(*) from public.port_influence) + (v_r->>'removed')::int then
      raise exception '0146 self-assert FAIL: the receipt is not the recount: %', v_r;
    end if;
    -- the switch and the town hall's next count
    v_out := public.influence_switch(false);
    if (v_out->>'enabled')::boolean or (world.town_hall_influence(v_keep, v_me)->'next_count') <> 'null'::jsonb then
      raise exception '0146 self-assert FAIL: the switch did not put the race out: %', v_out;
    end if;
    v_out := public.influence_switch(true);
    if not (v_out->>'enabled')::boolean or (v_out->>'next_count')::timestamptz <= now()
       or (v_out->>'next_count')::timestamptz > now() + interval '1 day'
       or (world.town_hall_influence(v_keep, v_me)->>'next_count')::timestamptz <> (v_out->>'next_count')::timestamptz then
      raise exception '0146 self-assert FAIL: the switch / next count read %', v_out;
    end if;
    v_out := jsonb_build_object('live_ms', v_live->'ms', 'probe', v_r - 'ms' - 'at');
    raise exception 'PROBE_ROLLBACK_0146';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0146' then raise; end if;
  end;
  return v_out;
end $$;

do $$
declare
  v_p jsonb := pg_temp.probe_0146();
begin
  if (select value from public.world_config where key = 'influence_enabled') <> 'false'::jsonb then
    raise exception '0146 self-assert FAIL: the probe left the race lit';
  end if;
  raise notice '0146 self-assert ok: THE FLAG FOLLOWS THE MONEY — decay to the coin and the day reset; a 9 %% lead keeps the holder, an 11 %% lead changes it; a free city claimed at the minimum and not below; a home city never; the History line to the players of the two countries only; the receipt a recount; dark nothing; the switch both ways; town_hall_influence reverses to its pre-image. %', v_p;
end $$;
