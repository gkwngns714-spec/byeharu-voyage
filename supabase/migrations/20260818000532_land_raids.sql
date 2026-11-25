-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights it)
-- 0532 - LAND RAIDS, THE FIGHT  (dark: land_raids_enabled, false)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25 (R4): "more dungeon raids, mining, woodcutting etc. can be done"; (R5) "rather than chance of winning, it will show you the
--   consumed ammo, provision and crew". docs/design/captains-land-2026-11-25.md section 6; docs/design/land-2026-11.md 6.3 and 6.4 (the foes, the
--   party as a hull, one fight engine); docs/dev-log/2026-11-25-captain-works.md.
--
-- WHAT (lit; dark nothing answers):
--   public.land_foes          DATA: the foes by Arms level, as hulls of the one fight, and what beating one is worth. Figures are placeholders.
--   public.land_raid_party    a party as a hull: its hands and its captain's Arms level (health, attack, accuracy under the fight's ceiling, step).
--   public.land_raid_crew_cap the hands a company may send: 10 + 2 a COMBAT level above 1 (public.player_progress; asked at Send alone).
--   public.land_raid_terms    WHAT A SEND FREEZES: THE ONE FIGHT (public.tick_fight, the foe set upon, the party closing) played 16 times on seeds of
--                             the Send, each result kept (won | held | beaten, the share of the party's health lost). 0531's Send calls it once.
--   public.land_raid_round    the result of round n: one of the 16, by voyage.rng on the party and the Send; the hands it costs, whole, with the
--                             fraction carried by the dice, so booked in one go or in ten it is the same.
--   public.land_raid_card     what a screen may show: the MEAN hands and health a round costs, what it brings. NO CHANCE OF WINNING is in it, and the
--                             16 results are not.
-- NOT HERE: the Send, the settle, the stores, the gold (from the capital) and the badges: 0531's (land expedition), on the rounds (0518, 0519).
--   Company COMBAT is not raised by a raid (the lead's word). Weapons and armour carried: later (land-2026-11 6.4); the party fights with its tools.
-- ROWS: 7 data rows, 1 config row; 0 a minute. budget: no cron job, no autovacuum or fillfactor change; one data table.
-- COST: 16 tick_fight calls a Send (measured in proof 237); a round is one draw.
-- LOCKS: CREATE TABLE x1, CREATE FUNCTION x7. No body is cut.
-- ROLLBACK (forward, owner only): land_raids_enabled false.
-- SELF-ASSERT: no function or knob moved; nothing dark; then a probe, rolled back, on FOES OF ITS OWN (one that cannot be lost to, one that cannot be
--   beaten), so no knob of the sea's fight, no dice and no figure of the data is asked a sign: 16 results, the same for the same Send; a round's
--   hands whole, never above the party's, booked in one go as in ten; the card carries no result and no chance.
-- VERSION: 0532 (0531 stands between; this file needs only 0527 to 0530).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $m$
declare
  c_hunked constant text[] := array[]::text[];
  c_new    constant text[] := array['public.land_raids_on()', 'public.land_raid_crew_cap(uuid)', 'public.land_raid_party(integer,integer,numeric)', 'public.land_foe_side(text)', 'public.land_raid_terms(uuid,text,integer,uuid,uuid)', 'public.land_raid_round(jsonb,uuid,integer)', 'public.land_raid_card(jsonb)']::text[];
  c_doors  constant text[] := array[]::text[];
  c_knobs  constant text[] := array['land_raids_enabled', 'land_raid_crew_share', 'land_crew_cap']::text[];
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
  v_me uuid; v_off uuid; v_po uuid; v_t jsonb; v_t2 jsonb; v_c jsonb; v_h1 int; v_hh int; v_party uuid; i int;
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = any (c_knobs)) or exists (select 1 from unnest(c_new) u(q) where to_regprocedure(u.q) is not null) then
    raise exception '0532 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked) u(q) where to_regprocedure(u.q) is null) or to_regprocedure('public.captain_work_perk(uuid,text)') is null or to_regprocedure('public.tick_fight(uuid,jsonb,jsonb,jsonb)') is null or to_regprocedure('cmd.refusal(text,text,jsonb)') is null then
    raise exception '0532 refuses: a body it cuts or a reading it asks is not in this world';
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

  -- retention: none, bounded by the catalogue (data of this file)
  create table public.land_foes (
    code     text primary key check (code ~ '^[a-z_]+$'),
    ord      int  not null,
    word     text not null,
    level    int  not null check (level between 1 and 100),
    count    int  not null check (count between 1 and 12),
    health   numeric not null check (health > 0),
    attack   numeric not null check (attack > 0),
    accuracy numeric not null check (accuracy > 0),
    crew     int  not null check (crew >= 1),
    tier     int  not null check (tier >= 1),
    xp       int  not null check (xp >= 0),
    gold     int  not null check (gold >= 0),
    rp       int  not null check (rp >= 0));
  alter table public.land_foes enable row level security;
  revoke all on table public.land_foes from public, anon, authenticated, service_role;
  comment on table public.land_foes is '0532: what a land raid meets, as hulls of public.tick_fight (count of them, each with these figures), by the captain''s Arms level; xp, gold and rp a round won. Placeholders until measured. Server only.';
  insert into public.land_foes (code, ord, word, level, count, health, attack, accuracy, crew, tier, xp, gold, rp) values
    ('wolves',     1, 'Wolves',       1, 3,  4.1, 2.8,  60,  2, 1,  15,   30, 1),
    ('boar',       2, 'Boar',         8, 3,  4.8, 3.0,  65,  2, 1,  22,   50, 1),
    ('brigands',   3, 'Brigands',    15, 4,  5.8, 3.4,  70,  3, 1,  30,   90, 1),
    ('bear',       4, 'Bear',        25, 2,  17.6, 9.5,  80,  6, 2,  42,  140, 1),
    ('deserters',  5, 'Deserters',   35, 5,  10.8, 5.4,  90,  4, 2,  54,  220, 2),
    ('great_beast',6, 'Great beast', 50, 1, 81.0, 37.8, 105, 24, 3, 75,  360, 2),
    ('robbers',    7, 'Robber band', 65, 6,  21.0, 9.2, 115,  6, 3,  95,  520, 3);

  -- ── 3. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('land_raids_enabled', 'false'::jsonb, '0532: THE SWITCH (the owner''s). true: a land expedition may raid (0531 sends it). false: no raid is offered or fought.'),
    ('land_raid_crew_share', '0.15'::jsonb, '0532: the share of the partys health lost in a raid round that is hands lost for good.'),
    ('land_crew_cap', '[10, 2]'::jsonb, '0532: the hands a land expedition may take: the first figure, and the second for each COMBAT level above 1.');

  -- ── 4. THE RULES ──

  execute $f$
create function public.land_raids_on()
returns boolean language sql stable security definer set search_path = public, pg_temp
as $body$
  -- 0532: THE SWITCH: raids, and the land and the captains' works they stand on.
  select public.wc('land_raids_enabled') = 'true'::jsonb and public.captain_works_on() and public.land_on()
$body$
  $f$;

  execute $f$
create function public.land_raid_crew_cap(p_player uuid)
returns int language sql stable security definer set search_path = public, pg_temp
as $body$
  -- 0532: the hands a company may send on a land expedition: land_crew_cap, by her COMBAT level (level 1: the first figure, so the first crew
  -- needs none). Asked at Send alone: public.player_progress reads the record.
  select (public.wc('land_crew_cap')->>0)::int
         + (public.wc('land_crew_cap')->>1)::int * (greatest(1, coalesce((public.player_progress(p_player) #>> '{combat,level}')::int, 1)) - 1)
$body$
  $f$;

  execute $f$
create function public.land_raid_party(p_crew int, p_level int, p_attack_pct numeric default 0)
returns jsonb language sql immutable set search_path = public, pg_temp
as $body$
  -- 0532: a land party as a side of the one fight: one hull, its hands and its captain's Arms level. Reach is every land hull's one figure, armour 0
  -- (land-2026-11 6.3, points 1 and 2); accuracy stays under the fight's ceiling. p_attack_pct: her Drill (0533).
  select jsonb_build_array(jsonb_build_object(
    'id', '00000000-0532-4000-8000-0000000000b0', 'name', 'Party',
    'hull', round(p_crew * (6 + 0.06 * p_level), 2), 'maxd', round(p_crew * (6 + 0.06 * p_level), 2),
    'attack', round(p_crew * (1.2 + 0.03 * p_level) * (1 + p_attack_pct / 100), 2), 'accuracy', least(150, 75 + 0.75 * p_level),
    'reach', 10, 'armour', 0, 'crew', p_crew, 'tier', 1 + p_level / 25, 'sighting', 10, 'shots', greatest(1, least(12, p_crew / 4))))
$body$
  $f$;

  execute $f$
create function public.land_foe_side(p_foe text)
returns jsonb language sql stable security definer set search_path = public, pg_temp
as $body$
  -- 0532: a foe as a side of the one fight: `count` hulls of its row.
  select jsonb_agg(jsonb_build_object(
           'id', ('00000000-0532-4000-8000-0000000000' || lpad(to_hex(160 + n), 2, '0')), 'name', f.word, 'hull', f.health, 'maxd', f.health, 'attack', f.attack, 'accuracy', f.accuracy,
           'reach', 10, 'armour', 0, 'crew', f.crew, 'tier', f.tier, 'sighting', 10) order by n)
    from public.land_foes f cross join lateral generate_series(1, f.count) n where f.code = p_foe
$body$
  $f$;

  execute $f$
create function public.land_raid_terms(p_player uuid, p_foe text, p_crew int, p_captain uuid, p_seed uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp
as $body$
-- 0532: WHAT A RAID'S SEND WOULD FREEZE (0531 calls it once a Send): {foe, word, level, have, cap, crew, crew_pct (less), xp, gold, rp, seed, fights: [[r, lost]] x 16,
-- short}. r: 1 won, 0 held (nothing won), -1 beaten off; lost: the share of the party's health lost. The fight is public.tick_fight, the foe set
-- upon and the party closing (so the party breaks off as a raider does); its ends read as land-2026-11 6.3 point 5. short: the refusal a Send would
-- meet (E_NOT_IN_USE, E_NO_SUCH_JOB, E_NEEDS_SKILL, E_CREW_SHORT, E_AT_CAPACITY), and then no fight is played. Writes nothing.
declare
  f      public.land_foes%rowtype;
  v_perk jsonb;
  v_lv   int;
  v_cap  int;
  v_a    jsonb;
  v_b    jsonb;
  v_t    jsonb;
  v_max  numeric;
  v_out  jsonb := '[]'::jsonb;
  i      int;
begin
  if not public.land_raids_on() then
    return jsonb_build_object('short', cmd.refusal('E_NOT_IN_USE', 'raids are not open yet'));
  end if;
  select * into f from public.land_foes x where x.code = p_foe;
  if f.code is null then
    return jsonb_build_object('short', cmd.refusal('E_NO_SUCH_JOB', format('there is no raid called "%s"', coalesce(p_foe, ''))));
  end if;
  v_perk := public.captain_work_perk(p_captain, 'arms');
  v_lv := (v_perk->>'level')::int;
  v_cap := public.land_raid_crew_cap(p_player);
  if v_lv < f.level then
    return jsonb_build_object('short', cmd.refusal('E_NEEDS_SKILL', format('needs a captain of Arms %s', f.level), cmd.figures(v_lv, f.level, 'level')));
  end if;
  if coalesce(p_crew, 0) < 1 then
    return jsonb_build_object('short', cmd.refusal('E_CREW_SHORT', 'a raid needs hands', cmd.figures(0, 1, 'crew')));
  end if;
  if p_crew > v_cap then
    return jsonb_build_object('short', cmd.refusal('E_AT_CAPACITY', format('Crew %s / %s', p_crew, v_cap)));
  end if;
  v_a := public.land_foe_side(p_foe);
  v_b := public.land_raid_party(p_crew, v_lv, coalesce((v_perk->>'attack_pct')::numeric, 0));
  v_max := (v_b #>> '{0,maxd}')::numeric;
  for i in 1 .. 16 loop
    v_t := public.tick_fight(md5(p_seed::text || ':raid:' || i)::uuid, v_a, v_b, '{}'::jsonb);
    v_out := v_out || jsonb_build_array(jsonb_build_array(
      case when v_t->>'out' = 'PLUNDERED' or (v_t #>> '{r,hull,a}')::numeric <= 0 then 1 when v_t->>'out' = 'RANSOM' then 0 else -1 end,
      round(least(1, greatest(0, 1 - (v_t #>> '{r,hull,b}')::numeric / v_max)), 4)));
  end loop;
  return jsonb_build_object('foe', f.code, 'word', f.word, 'level', f.level, 'have', v_lv, 'cap', v_cap, 'crew', p_crew, 'crew_pct', v_perk->'crew_pct',
                            'share', public.wc_num('land_raid_crew_share'), 'xp', f.xp, 'gold', f.gold, 'rp', f.rp, 'seed', p_seed, 'fights', v_out);
end
$body$
  $f$;

  execute $f$
create function public.land_raid_round(p_terms jsonb, p_party uuid, p_n int)
returns table (result int, hands int, xp int, gold int, rp int) language sql stable security definer set search_path = public, pg_temp
as $body$
  -- 0532: ROUND n of a raid sent on p_terms: one of the 16 fights by voyage.rng on the party and the Send's seed; its hands lost: the health's share
  -- of the party the Send took, less the captain's, whole, the fraction decided by the round's own draw (so the rounds booked in one go or one by
  -- one cost the same). A win pays in full, a round held the experience, a round beaten off a quarter of it. Pure in (terms, party, n).
  select z.r, z.h, case z.r when -1 then z.x / 4 else z.x end, case z.r when 1 then (p_terms->>'gold')::int else 0 end, case z.r when 1 then (p_terms->>'rp')::int else 0 end
    from (select (w.f->>0)::int as r, (p_terms->>'xp')::int as x,
                 least((p_terms->>'crew')::int, floor(w.lost)::int + case when w.u2 < w.lost - floor(w.lost) then 1 else 0 end) as h
            from (select p_terms->'fights'->floor(voyage.rng(p_party, p_n, 'raid:' || (p_terms->>'seed')) * 16)::int as f,
                         voyage.rng(p_party, p_n, 'raid-hands:' || (p_terms->>'seed')) as u2) a
           cross join lateral (select a.f, a.u2, (a.f->>1)::numeric * (p_terms->>'crew')::int * (p_terms->>'share')::numeric * (1 - coalesce((p_terms->>'crew_pct')::numeric, 0) / 100) as lost) w) z
$body$
  $f$;

  execute $f$
create function public.land_raid_card(p_terms jsonb)
returns jsonb language sql immutable set search_path = public, pg_temp
as $body$
  -- 0532: WHAT A SCREEN MAY SHOW of a raid's terms: what a round costs and brings, as means of the 16. No result, no chance and no seed is in it.
  select case when p_terms ? 'short' then p_terms else
    (p_terms - 'fights' - 'seed' - 'share')
    || jsonb_build_object('cost', jsonb_build_object(
         'hands', (select round(avg((f->>1)::numeric) * (p_terms->>'crew')::int * (p_terms->>'share')::numeric * (1 - coalesce((p_terms->>'crew_pct')::numeric, 0) / 100), 2) from jsonb_array_elements(p_terms->'fights') f))) end
$body$
  $f$;

  foreach v_q in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_q::regprocedure);
  end loop;
  foreach v_q in array c_doors loop
    execute format('grant execute on function %s to authenticated', v_q::regprocedure);
  end loop;

  -- ── 5. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0532 (fn text, ord int, old text, new text) on commit drop;


  for v_h in select h.fn from hunks_0532 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0532 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0532 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0532 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0532 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0532 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 6. SELF-ASSERT: the catalog, the grants, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0532 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) is distinct from v_meta then
    raise exception '0532 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('anon', u.q::regprocedure, 'execute') or has_function_privilege('service_role', u.q::regprocedure, 'execute')
                 or has_function_privilege('authenticated', u.q::regprocedure, 'execute') <> (u.q = any (c_doors)))
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0532 self-assert FAIL: a new function is reachable by a client that should not reach it, or a client may write';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before then
    raise exception '0532 self-assert FAIL: a knob of another file moved';
  end if;

  -- ── 7. THE PROBE, rolled back by a raised sentinel (its own companies' rows) ──
  begin

    v_me := public.new_house('00000000-0532-4000-8000-000000000001', 'Casa do Covil 0532', 'PRT');
    select o.id into v_off from public.officers o join public.captain_profile cp on cp.officer_id = o.id
     where not exists (select 1 from public.player_officers po where po.player_id = v_me and po.officer_id = o.id) order by o.code limit 1;
    insert into public.player_officers (player_id, officer_id) values (v_me, v_off) returning id into v_po;
    insert into public.captain_state (player_officer_id, grade, home_seen_at) values (v_po, 'C', now());
    insert into public.land_foes (code, ord, word, level, count, health, attack, accuracy, crew, tier, xp, gold, rp) values
      ('probe_straw', 98, 'Straw 0532', 1, 1, 0.01, 0.0001, 1, 1, 1, 8, 5, 1), ('probe_stone', 99, 'Stone 0532', 1, 1, 100000000, 100000000, 100000, 1000000, 9, 8, 5, 1), ('probe_high', 97, 'High 0532', 50, 1, 1, 1, 1, 1, 1, 1, 1, 1);
    v_party := gen_random_uuid();
    -- DARK
    if public.land_raid_terms(v_me, 'probe_straw', 5, v_po, v_party) #>> '{short,error_code}' is distinct from 'E_NOT_IN_USE'
       and public.land_raid_terms(v_me, 'probe_straw', 5, v_po, v_party) #>> '{short,code}' is distinct from 'E_NOT_IN_USE' then
      raise exception '0532 self-assert FAIL: dark, a raid has terms: %', public.land_raid_terms(v_me, 'probe_straw', 5, v_po, v_party);
    end if;
    update public.world_config set value = 'true'::jsonb where key in ('land_raids_enabled', 'captain_works_enabled', 'land_enabled');
    update public.world_config set value = 'false'::jsonb where key = 'levels_bite';
    -- the crew cap at COMBAT 1, and the refusals
    if public.land_raid_crew_cap(v_me) <> 10 or not (public.land_raid_terms(v_me, 'probe_straw', 11, v_po, v_party) ? 'short') or not (public.land_raid_terms(v_me, 'probe_straw', 0, v_po, v_party) ? 'short')
       or not (public.land_raid_terms(v_me, 'probe_high', 5, v_po, v_party) ? 'short') or not (public.land_raid_terms(v_me, 'none', 5, v_po, v_party) ? 'short')
       or public.land_raid_terms(v_me, 'probe_straw', 10, v_po, v_party) ? 'short' then
      raise exception '0532 self-assert FAIL: the crew cap (%) or a refusal', public.land_raid_crew_cap(v_me);
    end if;
    -- 16 results, the same for the same Send; the straw never wins, the stone never loses
    v_t := public.land_raid_terms(v_me, 'probe_straw', 10, v_po, v_party);
    v_t2 := public.land_raid_terms(v_me, 'probe_stone', 10, v_po, v_party);
    if jsonb_array_length(v_t->'fights') <> 16 or v_t is distinct from public.land_raid_terms(v_me, 'probe_straw', 10, v_po, v_party)
       or exists (select 1 from jsonb_array_elements(v_t->'fights') f where (f->>0)::int = -1 or (f->>1)::numeric > 0.01)
       or exists (select 1 from jsonb_array_elements(v_t2->'fights') f where (f->>0)::int = 1 or (f->>1)::numeric not between 0 and 1) then
      raise exception '0532 self-assert FAIL: the 16 fights: % / %', v_t->'fights', v_t2->'fights';
    end if;
    -- a round: whole hands within the party, a pure function of (terms, party, n); one go as ten
    v_t2 := jsonb_set(v_t2, '{fights}', (select jsonb_agg(jsonb_build_array(case when n % 3 = 0 then -1 when n % 3 = 1 then 1 else 0 end, 0.02 * n)) from generate_series(1, 16) n));
    select sum(r.hands) into v_h1 from generate_series(1, 60) n cross join lateral public.land_raid_round(v_t2, v_party, n) r;
    v_hh := 0;
    for i in 0 .. 5 loop
      v_hh := v_hh + (select sum(r.hands) from generate_series(i * 10 + 1, i * 10 + 10) n cross join lateral public.land_raid_round(v_t2, v_party, n) r);
    end loop;
    if v_h1 <> v_hh or exists (select 1 from generate_series(1, 60) n cross join lateral public.land_raid_round(v_t2, v_party, n) r
                               where r.hands not between 0 and 10 or r.result not in (-1, 0, 1) or (r.result <> 1 and (r.gold <> 0 or r.rp <> 0)) or r.xp <> case r.result when -1 then 2 else 8 end) then
      raise exception '0532 self-assert FAIL: a round: % against %', v_h1, v_hh;
    end if;
    -- the card: a cost, no result, no chance, no seed
    v_c := public.land_raid_card(v_t2);
    if v_c ? 'fights' or v_c ? 'seed' or v_c::text ~* '(chance|odds|won|win)' or (v_c #>> '{cost,hands}')::numeric <> round(0.17 * 10 * 0.15, 2) then
      raise exception '0532 self-assert FAIL: the card: %', v_c;
    end if;
    raise exception using errcode = 'ZX532', message = 'PROBE_ROLLBACK_0532';
  exception when sqlstate 'ZX532' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0532 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.auth_uid::text like '00000000-0532-4000-8000-%') or public.wc('land_raids_enabled') is distinct from 'false'::jsonb or exists (select 1 from public.land_foes f where f.code like 'probe%') then
    raise exception '0532 self-assert FAIL: the probe left something behind';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0532 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0532 self-assert ok: LAND RAIDS, THE FIGHT (dark). Seven new functions server only; no body cut; no other function or knob moved; seven foes. Probe (rolled back) whole. % ms. %', round(extract(epoch from clock_timestamp() - v_t0) * 1000), v_note;
end $m$;
