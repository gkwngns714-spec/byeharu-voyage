-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights it)
-- 0527 - CAPTAIN TRACKS  (dark: captain_works_enabled, false)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25 (R4): "Each captains will have levels like RS3, where you will be able level up by doing a designated work."
--   docs/design/captains-land-2026-11-25.md section 3; docs/dev-log/2026-11-25-captain-works.md. This REVERSES hq-corp A2.3 and extends the
--   one captain level system (0160): the three tracks stay where they are (public.captain_xp); a WORK is one more track.
--
-- WHAT (lit; dark every body answers as before):
--   public.captain_works           DATA: the works (mining, smithing, woodcutting, arms), each with its curve (public.level_curves, 1 to 100)
--                                  and the company level whose experience the captain is given too (null: the captain alone).
--   public.captain_work_xp         a signing's experience in a work. A player's captain alone; gone with the signing (cascade), so a dismissal
--                                  and a closed company (0509 deletes player_officers) need nothing more.
--   public.captain_work_credit     THE ONE WRITER of it: whole points, with Leadership as public.captain_xp_credit lifts the three.
--   public.captain_work_level      THE ONE READING of a work's level: the curve's highest level begun. No company cap: the company's level opened
--                                  the work, the captain does it.
--   public.captain_level (1 hunk)  a focus that is not one of the three is a work: its level lit, 1 dark. The three: the body as it was.
--   public.captain_work_perk       what her level gives, for Send to freeze: {level, time_pct, crew_pct, forage}: time a round down, crew lost a
--                                  round down (a share of itself), one round in `forage` gives provisions (null: none yet).
--   world.captains (1 hunk)        lit, each captain's `works` [{work, word, level, xp, from, next_at, time_pct, crew_pct, forage}]; dark no key.
-- NOTHING CALLS THE WRITER YET: the land party's captain is 0528's.
-- NOT CHANGED: crew_terms, crew_pct, any figure at sea; the three tracks, their cap and their writer; promotion; skills.
-- ROWS: 4 data rows, 6 config rows. 0 new rows a minute (0528: one update a Collect, at most one in land_book_minutes a party).
-- budget: no cron job, no autovacuum or fillfactor change; one small table, one row a captain and work, written at a Collect alone.
-- LOCKS: CREATE TABLE x2 (a foreign key on player_officers: SHARE ROW EXCLUSIVE for an instant); CREATE OR REPLACE x2 by hunks.
-- ROLLBACK (forward, owner only): captain_works_enabled false (the rows stay and are read by nothing).
-- SELF-ASSERT: hunks once and reversing; no other function or knob moved; then a probe company of this file's own, rolled back: the three
--   tracks answer by their own rule dark and lit; a work reads 1 dark; the writer books nothing dark and nothing for a captain who is no
--   player's; lit the curve, its ends and the perks' caps. It asks the market, the dice and other companies nothing.
-- VERSION: 0527.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $m$
declare
  c_hunked constant text[] := array['public.captain_level(uuid,text)', 'world.captains()']::text[];
  c_new    constant text[] := array['public.captain_works_on()', 'public.captain_work_level(uuid,text)', 'public.captain_work_credit(uuid,text,numeric)', 'public.captain_work_perk(uuid,text)', 'public.captain_works_card(uuid)']::text[];
  c_doors  constant text[] := array[]::text[];
  c_knobs  constant text[] := array['captain_works_enabled', 'captain_work_time_pct', 'captain_work_time_most', 'captain_work_crew_pct', 'captain_work_crew_most', 'captain_work_forage']::text[];
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_q         text;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_cfg_before text;
  v_lived     boolean := false;
  v_note      text := '';
  v_me  uuid;
  v_off uuid;
  v_po  uuid;
  v_top int;
  v_p   jsonb;
  v_co  int;
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = any (c_knobs)) or exists (select 1 from unnest(c_new) u(q) where to_regprocedure(u.q) is not null) then
    raise exception '0527 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked) u(q) where to_regprocedure(u.q) is null) then
    raise exception '0527 refuses: a body it cuts or a reading it asks is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE TABLES ──

  -- retention: none, bounded by the catalogue (one row a work, data of this file)
  create table public.captain_works (
    code  text primary key,
    ord   int  not null,
    word  text not null,
    curve text not null check (curve = 'long'),
    skill text references public.level_skills(code),
    check (code not in ('exploration', 'trading', 'combat')));
  alter table public.captain_works enable row level security;
  revoke all on table public.captain_works from public, anon, authenticated, service_role;
  comment on table public.captain_works is '0527: the works a captain levels in (docs/design/captains-land-2026-11-25.md). curve: public.level_curves. skill: the company level raised by the same work, null: none. Never one of the three sea tracks. Server only.';
  insert into public.captain_works (code, ord, word, curve, skill) values
    ('mining', 1, 'Mining', 'long', 'mining'), ('smithing', 2, 'Smithing', 'long', 'smithing'), ('woodcutting', 3, 'Woodcutting', 'long', null), ('arms', 4, 'Arms', 'long', null);
  -- retention: none, bounded by one row a captain and work (4 works); a captain's rows go with her signing
  create table public.captain_work_xp (
    player_officer_id uuid not null references public.player_officers(id) on delete cascade,
    work              text not null references public.captain_works(code),
    xp                int  not null default 0 check (xp >= 0),
    primary key (player_officer_id, work));
  alter table public.captain_work_xp enable row level security;
  revoke all on table public.captain_work_xp from public, anon, authenticated, service_role;
  comment on table public.captain_work_xp is '0527: a PLAYER''s signing''s experience in a work. Written by public.captain_work_credit alone; read by public.captain_work_level. A merchant''s captain has none. Server only.';

  -- ── 3. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('captain_works_enabled', 'false'::jsonb, '0527: THE SWITCH (the owner''s). true: a captain gains levels in the works she does ashore and they shorten rounds and save crew. false: the three sea tracks alone, as before.'),
    ('captain_work_time_pct', '0.25'::jsonb, '0527: per cent of a rounds time a captains work level above 1 saves.'),
    ('captain_work_time_most', '25'::jsonb, '0527: the most per cent of time a captain''s work level saves.'),
    ('captain_work_crew_pct', '0.5'::jsonb, '0527: per cent of the crew lost a round a captain''s work level above 1 saves (a share of the loss itself).'),
    ('captain_work_crew_most', '50'::jsonb, '0527: the most per cent of the crew lost that a captain''s work level saves.'),
    ('captain_work_forage', '[{"level": 40, "one_in": 6}, {"level": 80, "one_in": 3}]'::jsonb, '0527: from which work level one round in how many gives provisions.');

  -- ── 4. THE RULES ──

  execute $f$
create function public.captain_works_on()
returns boolean language sql stable security definer set search_path = public, pg_temp
as $body$
  -- 0527: THE SWITCH, read once: world_config captain_works_enabled.
  select public.wc('captain_works_enabled') = 'true'::jsonb
$body$
  $f$;

  execute $f$
create function public.captain_work_level(p_signing uuid, p_work text)
returns int language sql stable security definer set search_path = public, pg_temp
as $body$
  -- 0527: THE ONE READING of a captain's level in a work: the highest level of the work's curve begun by her experience; 1 with none, for a
  -- work nobody knows, and while the works are dark.
  select case when not public.captain_works_on() then 1
              else coalesce((select max(c.level) from public.captain_works w
                               join public.level_curves c on c.curve = w.curve
                              where w.code = p_work
                                and c.xp <= coalesce((select x.xp from public.captain_work_xp x where x.player_officer_id = p_signing and x.work = p_work), 0)), 1) end
$body$
  $f$;

  execute $f$
create function public.captain_work_credit(p_signing uuid, p_work text, p_xp numeric)
returns int language plpgsql security definer set search_path = public, pg_temp
as $body$
-- 0527: THE ONE WRITER of public.captain_work_xp. Whole points (down), lifted by Leadership while skills bite exactly as
-- public.captain_xp_credit lifts the three tracks; 0 and nothing written while dark, for no captain, for a captain who is no player's
-- (no public.captain_state row), an unknown work, or nothing to give. Returns what was booked.
declare
  v_player uuid;
  v_give   int;
begin
  if not public.captain_works_on() or p_signing is null or coalesce(p_xp, 0) <= 0
     or not exists (select 1 from public.captain_works w where w.code = p_work) then
    return 0;
  end if;
  select po.player_id into v_player
    from public.player_officers po join public.captain_state st on st.player_officer_id = po.id where po.id = p_signing;
  if v_player is null then
    return 0;
  end if;
  v_give := floor(p_xp * case when public.skills_bite_on() then 1 + coalesce(world.skill_pct(v_player, null, 'captain_xp'), 0) / 100.0 else 1 end)::int;
  if v_give < 1 then
    return 0;
  end if;
  insert into public.captain_work_xp (player_officer_id, work, xp) values (p_signing, p_work, v_give)
  on conflict (player_officer_id, work) do update set xp = public.captain_work_xp.xp + excluded.xp;
  return v_give;
end
$body$
  $f$;

  execute $f$
create function public.captain_work_perk(p_signing uuid, p_work text)
returns jsonb language sql stable security definer set search_path = public, pg_temp
as $body$
  -- 0527: WHAT HER LEVEL IN A WORK GIVES (frozen at Send by whoever sends her): {level, time_pct, crew_pct, forage}. Level 1, dark or no
  -- captain: {1, 0, 0, null}, the round as it is without her.
  select jsonb_build_object('level', l.n,
           'time_pct', least(public.wc_num('captain_work_time_most'), public.wc_num('captain_work_time_pct') * (l.n - 1)),
           'crew_pct', least(public.wc_num('captain_work_crew_most'), public.wc_num('captain_work_crew_pct') * (l.n - 1)),
           'forage', (select min((e->>'one_in')::int) from jsonb_array_elements(public.wc('captain_work_forage')) e where (e->>'level')::int <= l.n and l.n > 1))
    from (select public.captain_work_level(p_signing, p_work) as n) l
$body$
  $f$;

  execute $f$
create function public.captain_works_card(p_signing uuid)
returns jsonb language sql stable security definer set search_path = public, pg_temp
as $body$
  -- 0527: her works for her card (world.captains): every work, with her level line and what it gives now.
  select coalesce(jsonb_agg(jsonb_build_object('work', w.code, 'word', w.word, 'xp', z.xp,
             'from', (select c.xp from public.level_curves c where c.curve = w.curve and c.level = (z.perk->>'level')::int),
             'next_at', (select c.xp from public.level_curves c where c.curve = w.curve and c.level = (z.perk->>'level')::int + 1)) || z.perk order by w.ord), '[]'::jsonb)
    from public.captain_works w
   cross join lateral (select coalesce((select x.xp from public.captain_work_xp x where x.player_officer_id = p_signing and x.work = w.code), 0) as xp,
                              public.captain_work_perk(p_signing, w.code) as perk) z
$body$
  $f$;

  foreach v_q in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_q::regprocedure);
  end loop;
  foreach v_q in array c_doors loop
    execute format('grant execute on function %s to authenticated', v_q::regprocedure);
  end loop;

  -- ── 5. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0527 (fn text, ord int, old text, new text) on commit drop;

  insert into hunks_0527 values ('public.captain_level(uuid,text)', 1,
$h$begin
  select case p_focus when 'exploration' then x.exploration$h$,
$h$begin
  -- 0527: a focus that is not one of the three is a WORK (public.captain_work_level: 1 while the works are dark)
  if p_focus not in ('exploration', 'trading', 'combat') then
    return public.captain_work_level(p_signing, p_focus);
  end if;
  select case p_focus when 'exploration' then x.exploration$h$);

  insert into hunks_0527 values ('world.captains()', 1,
$h$                             (select r.name from public.regions r where r.id = hp.region_id))) end
    ) order by o.name$h$,
$h$                             (select r.name from public.regions r where r.id = hp.region_id))) end
    ) || case when public.captain_works_on() then jsonb_build_object('works', public.captain_works_card(po.id)) else '{}'::jsonb end   -- 0527
      order by o.name$h$);


  for v_h in select h.fn from hunks_0527 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0527 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0527 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0527 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0527 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0527 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 6. SELF-ASSERT: the catalog, the grants, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0527 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) is distinct from v_meta then
    raise exception '0527 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('anon', u.q::regprocedure, 'execute') or has_function_privilege('service_role', u.q::regprocedure, 'execute')
                 or has_function_privilege('authenticated', u.q::regprocedure, 'execute') <> (u.q = any (c_doors)))
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0527 self-assert FAIL: a new function is reachable by a client that should not reach it, or a client may write';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before then
    raise exception '0527 self-assert FAIL: a knob of another file moved';
  end if;

  -- ── 7. THE PROBE, rolled back by a raised sentinel (its own companies' rows) ──
  begin

    v_me := public.new_house('00000000-0527-4000-8000-000000000001', 'Casa do Trabalho 0527', 'PRT');
    perform cmd.assume_identity('00000000-0527-4000-8000-000000000001');
    select o.id into v_off from public.officers o join public.captain_profile cp on cp.officer_id = o.id
     where not exists (select 1 from public.player_officers po where po.player_id = v_me and po.officer_id = o.id) order by o.code limit 1;
    insert into public.player_officers (player_id, officer_id) values (v_me, v_off) returning id into v_po;
    insert into public.captain_xp (player_officer_id, trading) values (v_po, 100000);
    -- DARK
    v_co := (public.player_progress(v_me) #>> '{trading,level}')::int;
    if public.captain_works_on() or public.captain_level(v_po, 'trading') <> least(public.level_from_points(100000), v_co) or public.captain_level(v_po, 'combat') <> 1
       or public.captain_level(v_po, 'mining') <> 1 or public.captain_work_perk(v_po, 'mining') <> '{"level": 1, "time_pct": 0, "crew_pct": 0, "forage": null}'::jsonb
       or public.captain_work_credit(v_po, 'mining', 1000) <> 0 or exists (select 1 from public.captain_work_xp cw where cw.player_officer_id = v_po)
       or world.captains() #> '{captains,0}' ? 'works' then
      raise exception '0527 self-assert FAIL: dark, something moved';
    end if;
    -- LIT: a captain who is no player's earns nothing; then a player's does
    update public.world_config set value = 'true'::jsonb where key = 'captain_works_enabled';
    if public.captain_work_credit(v_po, 'mining', 1000) <> 0 then
      raise exception '0527 self-assert FAIL: a captain with no state row (a merchant''s) was credited';
    end if;
    insert into public.captain_state (player_officer_id, grade, home_seen_at) values (v_po, 'C', now());
    if public.captain_work_credit(v_po, 'trading', 10) <> 0 or public.captain_work_credit(v_po, 'nothing', 10) <> 0 or public.captain_work_credit(v_po, 'mining', 0.4) <> 0
       or public.captain_work_credit(null, 'mining', 10) <> 0 or public.captain_work_credit(v_po, 'mining', 0) <> 0 then
      raise exception '0527 self-assert FAIL: the writer booked what it must not';
    end if;
    v_n := public.captain_work_credit(v_po, 'mining', 50);
    if v_n < 50 or (select cw.xp from public.captain_work_xp cw where cw.player_officer_id = v_po and cw.work = 'mining') <> v_n
       or public.captain_level(v_po, 'trading') <> least(public.level_from_points(100000), v_co) then
      raise exception '0527 self-assert FAIL: 50 of mining booked %, or the three tracks moved', v_n;
    end if;
    -- the curve, its ends, the perks and their caps (from public.level_curves' own rows)
    v_top := (select max(c.level) from public.level_curves c where c.curve = 'long');
    for x in select c.level, c.xp from public.level_curves c where c.curve = 'long' and c.level in (1, 2, 40, 80, v_top) order by c.level loop
      update public.captain_work_xp z set xp = x.xp where z.player_officer_id = v_po and z.work = 'mining';
      v_p := public.captain_work_perk(v_po, 'mining');
      if public.captain_level(v_po, 'mining') <> x.level or (v_p->>'level')::int <> x.level
         or (v_p->>'time_pct')::numeric <> least(25, 0.25 * (x.level - 1)) or (v_p->>'crew_pct')::numeric <> least(50, 0.5 * (x.level - 1))
         or (v_p->>'forage')::int is distinct from (case when x.level >= 80 then 3 when x.level >= 40 then 6 end) then
        raise exception '0527 self-assert FAIL: at % xp the level or what it gives is wrong: %', x.xp, v_p;
      end if;
      if x.level > 1 then
        update public.captain_work_xp z set xp = x.xp - 1 where z.player_officer_id = v_po and z.work = 'mining';
        if public.captain_level(v_po, 'mining') <> x.level - 1 then
          raise exception '0527 self-assert FAIL: one point short of level % reads %', x.level, public.captain_level(v_po, 'mining');
        end if;
      end if;
    end loop;
    v_p := (select e->'works' from jsonb_array_elements(world.captains()->'captains') e where e->>'code' = (select o.code from public.officers o where o.id = v_off));
    if jsonb_array_length(v_p) <> 4 or v_p #>> '{0,work}' <> 'mining' or (v_p #>> '{0,level}')::int <> v_top - 1 or (v_p #>> '{3,level}')::int <> 1 then
      raise exception '0527 self-assert FAIL: her card''s works: %', v_p;
    end if;
    delete from public.player_officers where id = v_po;
    if exists (select 1 from public.captain_work_xp z where z.player_officer_id = v_po) then
      raise exception '0527 self-assert FAIL: a dismissed captain left her works behind';
    end if;
    raise exception using errcode = 'ZX527', message = 'PROBE_ROLLBACK_0527';
  exception when sqlstate 'ZX527' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0527 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.auth_uid::text like '00000000-0527-4000-8000-%') or public.wc('captain_works_enabled') is distinct from 'false'::jsonb then
    raise exception '0527 self-assert FAIL: the probe left something behind';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0527 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0527 self-assert ok: CAPTAIN TRACKS (dark). Two hunks once and reversing; five new functions server only; no other function or knob moved; four works on the long curve. Probe (rolled back) whole. % ms. %', round(extract(epoch from clock_timestamp() - v_t0) * 1000), v_note;
end $m$;
