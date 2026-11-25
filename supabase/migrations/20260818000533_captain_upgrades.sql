-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights it)
-- 0533 - CAPTAIN UPGRADES  (dark: honor_enabled, 0530's switch)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25 (R4): "HONOR BADGE - where you can use to upgrade CAPTAINS." docs/design/captains-land-2026-11-25.md section 7.
--
-- WHAT (lit; dark every body answers as before):
--   public.captain_upgrade_kinds   DATA: Quartermaster (+4 % carried by each of her crew), Surgeon's hand (-6 % crew lost), Pathfinder (-3 % time a
--                                  round), Drill (+3 % attack in a raid), a rank; five ranks; a rank costs honor_upgrade_base x r x (r + 1) badges.
--   public.captain_upgrades        the ranks of a signing; gone with her (cascade).
--   public.captain_upgrade_for     the core of cmd.captain_upgrade(code, upgrade): her captain, the next rank, the badges (public.honor_credit, the one
--                                  writer); ashore, docked, or with a party at home.
--   public.captain_work_perk (1 hunk)  what a Send freezes of her: time and crew with her ranks beside her level's, and lit the keys carry_pct and
--                                  attack_pct. THEY ACT ON HER LAND PARTY ALONE: no body at sea reads this function.
--   world.captains (1 hunk)        lit, each captain's `upgrades` with the next rank's price.
--   public.client_rpc_entry_points (1 hunk) the door.
-- Reputation keeps the captain skill steps (0355), promotion its items (0162): neither is touched.
-- ROWS: 4 data rows, 1 config row; a press writes 3; 0 a minute. budget: no cron job, no autovacuum or fillfactor change; two small tables.
-- LOCKS: CREATE TABLE x2; CREATE OR REPLACE x3 by hunks. ROLLBACK (forward, owner only): honor_enabled false.
-- SELF-ASSERT: hunks once and reversing; no other function or knob moved; no body at sea reads the perk; then a probe company, rolled back: dark the
--   door refuses and the perk is the perk with a rank standing; lit the price, the five ranks, the refusals, the perk by rank; a dismissal takes them.
-- VERSION: 0533.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $m$
declare
  c_hunked constant text[] := array['public.captain_work_perk(uuid,text)', 'world.captains()', 'public.client_rpc_entry_points()']::text[];
  c_new    constant text[] := array['public.captain_upgrade_pct(uuid,text)', 'public.captain_upgrades_card(uuid)', 'public.captain_upgrade_for(uuid,text,text)', 'cmd.captain_upgrade(text,text)']::text[];
  c_doors  constant text[] := array['cmd.captain_upgrade(text,text)']::text[];
  c_knobs  constant text[] := array['honor_upgrade_base']::text[];
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
  v_me uuid; v_po uuid; v_code text; v_p0 jsonb; v_p1 jsonb; v_r jsonb; v_fl uuid; v_sh uuid; i int; v_bal int;
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = any (c_knobs)) or exists (select 1 from unnest(c_new) u(q) where to_regprocedure(u.q) is not null) then
    raise exception '0533 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked) u(q) where to_regprocedure(u.q) is null) or to_regprocedure('public.honor_credit(uuid,text,integer,text,jsonb)') is null then
    raise exception '0533 refuses: a body it cuts or a reading it asks is not in this world';
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
  create table public.captain_upgrade_kinds (
    code text primary key check (code in ('quartermaster', 'surgeon', 'pathfinder', 'drill')),
    ord  int not null, word text not null,
    pct  numeric not null check (pct > 0),
    top  int not null check (top between 1 and 10));
  alter table public.captain_upgrade_kinds enable row level security;
  revoke all on table public.captain_upgrade_kinds from public, anon, authenticated, service_role;
  insert into public.captain_upgrade_kinds (code, ord, word, pct, top) values
    ('quartermaster', 1, 'Quartermaster', 4, 5), ('surgeon', 2, 'Surgeon''s hand', 6, 5), ('pathfinder', 3, 'Pathfinder', 3, 5), ('drill', 4, 'Drill', 3, 5);
  comment on table public.captain_upgrade_kinds is '0533: what HONOR BADGES buy for a captain: pct a rank, to top. They act on her land party alone. Server only.';
  -- retention: none, bounded by four rows a captain; they go with her signing
  create table public.captain_upgrades (
    player_officer_id uuid not null references public.player_officers(id) on delete cascade,
    upgrade           text not null references public.captain_upgrade_kinds(code),
    rank              int  not null check (rank >= 1),
    primary key (player_officer_id, upgrade));
  alter table public.captain_upgrades enable row level security;
  revoke all on table public.captain_upgrades from public, anon, authenticated, service_role;
  comment on table public.captain_upgrades is '0533: the ranks a player bought for a signing with HONOR BADGES. Writer: public.captain_upgrade_for. Server only.';

  -- ── 3. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('honor_upgrade_base', '5'::jsonb, '0533: a captain upgrades rank r costs this x r x (r + 1) HONOR BADGES.');

  -- ── 4. THE RULES ──

  execute $f$
create function public.captain_upgrade_pct(p_signing uuid, p_upgrade text)
returns numeric language sql stable security definer set search_path = public, pg_temp
as $body$
  -- 0533: what her ranks of one upgrade give, in per cent; 0 with none, and while the badges are dark.
  select case when not public.honor_on() then 0
              else coalesce((select u.rank * k.pct from public.captain_upgrades u join public.captain_upgrade_kinds k on k.code = u.upgrade
                              where u.player_officer_id = p_signing and u.upgrade = p_upgrade), 0) end
$body$
  $f$;

  execute $f$
create function public.captain_upgrades_card(p_signing uuid)
returns jsonb language sql stable security definer set search_path = public, pg_temp
as $body$
  -- 0533: her upgrades for her card: rank of top, per cent now and the next rank's price in badges (null at the top).
  select coalesce(jsonb_agg(jsonb_build_object('upgrade', k.code, 'word', k.word, 'rank', r.n, 'top', k.top, 'pct', r.n * k.pct,
           'cost', case when r.n < k.top then public.wc_int('honor_upgrade_base') * (r.n + 1) * (r.n + 2) end) order by k.ord), '[]'::jsonb)
    from public.captain_upgrade_kinds k
   cross join lateral (select coalesce((select u.rank from public.captain_upgrades u where u.player_officer_id = p_signing and u.upgrade = k.code), 0) as n) r
$body$
  $f$;

  execute $f$
create function public.captain_upgrade_for(p_player uuid, p_code text, p_upgrade text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $body$
-- 0533: CORE of cmd.captain_upgrade: her next rank, for badges. Refused: dark (E_NOT_IN_USE), not hers (E_NOT_SIGNED), no such upgrade
-- (E_NO_SUCH_JOB), her ship not docked (E_NOT_IN_PORT), her party out (E_LAND_OUT: its terms are frozen), the top rank (E_TOP_RANK), the badges
-- (E_NOT_ENOUGH_HONOR, public.honor_credit's own). No refund, no way back. Server only.
declare
  k      public.captain_upgrade_kinds%rowtype;
  v_po   uuid;
  v_name text;
  v_now  record;
  v_rank int;
  v_cost int;
begin
  if not public.honor_on() then
    perform cmd.refuse('E_NOT_IN_USE', 'captain upgrades are not open yet');
  end if;
  perform 1 from public.players pl where pl.id = p_player for update;
  select po.id, o.name into v_po, v_name
    from public.player_officers po join public.officers o on o.id = po.officer_id where po.player_id = p_player and o.code = upper(btrim(coalesce(p_code, '')));
  if v_po is null then
    perform cmd.refuse('E_NOT_SIGNED', 'You do not keep that captain.');
  end if;
  select * into k from public.captain_upgrade_kinds x where x.code = p_upgrade;
  if k.code is null then
    perform cmd.refuse('E_NO_SUCH_JOB', format('there is no upgrade called "%s"', coalesce(p_upgrade, '')));
  end if;
  select cs.ship_id, f.status, lp.action into v_now
    from public.captain_seats cs
    left join public.ships s on s.id = cs.ship_id
    left join public.fleets f on f.id = s.fleet_id
    left join public.land_parties lp on lp.id = cs.party_id
   where cs.player_officer_id = v_po;
  if v_now.ship_id is not null and v_now.status is distinct from 'DOCKED' then
    perform cmd.refuse('E_NOT_IN_PORT', format('%s is aboard a ship that is not in port.', v_name));
  end if;
  if v_now.action is not null then
    perform cmd.refuse('E_LAND_OUT', format('%s is out with the land party; call it home first', v_name));
  end if;
  v_rank := coalesce((select u.rank from public.captain_upgrades u where u.player_officer_id = v_po and u.upgrade = k.code), 0) + 1;
  if v_rank > k.top then
    perform cmd.refuse('E_TOP_RANK', format('%s: %s is at the top', v_name, k.word));
  end if;
  v_cost := public.wc_int('honor_upgrade_base') * v_rank * (v_rank + 1);
  perform public.honor_credit(p_player, 'captain_upgrade', -v_cost, null, jsonb_build_object('officer', upper(btrim(p_code)), 'upgrade', k.code, 'rank', v_rank));
  insert into public.captain_upgrades (player_officer_id, upgrade, rank) values (v_po, k.code, v_rank)
  on conflict (player_officer_id, upgrade) do update set rank = excluded.rank;
  return jsonb_build_object('ok', true, 'officer', upper(btrim(p_code)), 'upgrade', k.code, 'rank', v_rank, 'top', k.top, 'cost', v_cost,
                            'honor', (select b.balance from public.honor_balance b where b.player_id = p_player), 'sentence', format('%s: %s %s', v_name, k.word, v_rank));
end
$body$
  $f$;

  execute $f$
create function cmd.captain_upgrade(p_code text, p_upgrade text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $body$
-- 0533: a captain's next rank of an upgrade, for HONOR BADGES. The rule is public.captain_upgrade_for's.
declare
  v_player uuid := public.current_player_id();
  v_det    text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_SIGNED_IN', 'error_message', 'Nobody is signed in.', 'fixes', jsonb_build_array('(sign in)'));
  end if;
  begin
    return public.captain_upgrade_for(v_player, p_code, p_upgrade);
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end
$body$
  $f$;

  foreach v_q in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_q::regprocedure);
  end loop;
  foreach v_q in array c_doors loop
    execute format('grant execute on function %s to authenticated', v_q::regprocedure);
  end loop;

  -- ── 5. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0533 (fn text, ord int, old text, new text) on commit drop;

  insert into hunks_0533 values ('public.captain_work_perk(uuid,text)', 1,
$h$least(public.wc_num('captain_work_time_most'), public.wc_num('captain_work_time_pct') * (l.n - 1)),$h$,
$h$least(public.wc_num('captain_work_time_most'), public.wc_num('captain_work_time_pct') * (l.n - 1)) + public.captain_upgrade_pct(p_signing, 'pathfinder'),   -- 0533$h$);

  insert into hunks_0533 values ('public.captain_work_perk(uuid,text)', 2,
$h$least(public.wc_num('captain_work_crew_most'), public.wc_num('captain_work_crew_pct') * (l.n - 1)),$h$,
$h$least(public.wc_num('captain_work_crew_most'), public.wc_num('captain_work_crew_pct') * (l.n - 1)) + public.captain_upgrade_pct(p_signing, 'surgeon'),   -- 0533$h$);

  insert into hunks_0533 values ('public.captain_work_perk(uuid,text)', 3,
$h$where (e->>'level')::int <= l.n and l.n > 1))$h$,
$h$where (e->>'level')::int <= l.n and l.n > 1))
         || case when public.honor_on() then jsonb_build_object('carry_pct', public.captain_upgrade_pct(p_signing, 'quartermaster'), 'attack_pct', public.captain_upgrade_pct(p_signing, 'drill')) else '{}'::jsonb end   -- 0533$h$);

  insert into hunks_0533 values ('world.captains()', 1,
$h$(select lp.ord from public.land_parties lp where lp.id = cs.party_id)) else '{}'::jsonb end   -- 0527$h$,
$h$(select lp.ord from public.land_parties lp where lp.id = cs.party_id)) else '{}'::jsonb end   -- 0527
      || case when public.honor_on() then jsonb_build_object('upgrades', public.captain_upgrades_card(po.id)) else '{}'::jsonb end   -- 0533$h$);

  insert into hunks_0533 values ('public.client_rpc_entry_points()', 1,
$h$      ('cmd',         'captain_dismiss',       'text'),
$h$,
$h$      ('cmd',         'captain_dismiss',       'text'),
      -- 0533: a captain's upgrade for HONOR BADGES (dark: E_NOT_IN_USE)
      ('cmd',         'captain_upgrade',       'text, text'),
$h$);


  for v_h in select h.fn from hunks_0533 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0533 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0533 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0533 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0533 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0533 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 6. SELF-ASSERT: the catalog, the grants, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0533 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) is distinct from v_meta then
    raise exception '0533 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('anon', u.q::regprocedure, 'execute') or has_function_privilege('service_role', u.q::regprocedure, 'execute')
                 or has_function_privilege('authenticated', u.q::regprocedure, 'execute') <> (u.q = any (c_doors)))
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0533 self-assert FAIL: a new function is reachable by a client that should not reach it, or a client may write';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before then
    raise exception '0533 self-assert FAIL: a knob of another file moved';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.prosrc ~ 'captain_(work_perk|upgrade_pct)'
                and p.proname !~ '^(land_|round_|captain_)') then
    raise exception '0533 self-assert FAIL: a body that is not the land''s reads a captain''s perk';
  end if;

  -- ── 7. THE PROBE, rolled back by a raised sentinel (its own companies' rows) ──
  begin

    v_me := public.new_house('00000000-0533-4000-8000-000000000001', 'Casa do Grau 0533', 'PRT');
    perform cmd.assume_identity('00000000-0533-4000-8000-000000000001');
    update public.world_config set value = 'true'::jsonb where key = 'captain_works_enabled';
    select o.code into v_code from public.officers o join public.captain_profile cp on cp.officer_id = o.id
     where not exists (select 1 from public.player_officers po where po.player_id = v_me and po.officer_id = o.id) order by o.code limit 1;
    v_po := public.captain_sign_rows(v_me, (select o.id from public.officers o where o.code = v_code));
    insert into public.captain_work_xp (player_officer_id, work, xp) select v_po, 'arms', c.xp from public.level_curves c where c.curve = 'long' and c.level = 11;
    -- DARK, a rank standing: the perk is the perk, the door refuses, no card
    v_p0 := public.captain_work_perk(v_po, 'arms');
    insert into public.captain_upgrades (player_officer_id, upgrade, rank) values (v_po, 'pathfinder', 5);
    if public.captain_work_perk(v_po, 'arms') is distinct from v_p0 or v_p0 ? 'carry_pct' or cmd.captain_upgrade(v_code, 'drill')->>'error_code' <> 'E_NOT_IN_USE'
       or exists (select 1 from jsonb_array_elements(world.captains()->'captains') e where e ? 'upgrades') then
      raise exception '0533 self-assert FAIL: dark, something moved: %', public.captain_work_perk(v_po, 'arms');
    end if;
    delete from public.captain_upgrades where player_officer_id = v_po;
    update public.world_config set value = 'true'::jsonb where key = 'honor_enabled';
    if public.captain_work_perk(v_po, 'arms') is distinct from v_p0 || '{"carry_pct": 0, "attack_pct": 0}'::jsonb then
      raise exception '0533 self-assert FAIL: lit with no rank the perk moved: %', public.captain_work_perk(v_po, 'arms');
    end if;
    -- the refusals
    if cmd.captain_upgrade('NOBODY-0533', 'drill')->>'error_code' <> 'E_NOT_SIGNED' or cmd.captain_upgrade(v_code, 'charm')->>'error_code' <> 'E_NO_SUCH_JOB'
       or cmd.captain_upgrade(v_code, 'drill')->>'error_code' <> 'E_NOT_ENOUGH_HONOR' then
      raise exception '0533 self-assert FAIL: a refusal is missing';
    end if;
    perform public.honor_credit(v_me, 'land', 1000, 'probe-0533');
    select f.id into v_fl from public.fleets f where f.player_id = v_me;
    select s.id into v_sh from public.ships s where s.fleet_id = v_fl and s.is_flagship;
    perform public.captain_seat_put(v_po, v_sh, 1);
    update public.fleets set status = 'UNABLE_TO_SAIL' where id = v_fl;
    if cmd.captain_upgrade(v_code, 'drill')->>'error_code' <> 'E_NOT_IN_PORT' then
      raise exception '0533 self-assert FAIL: upgraded aboard a ship that is not in port';
    end if;
    update public.fleets set status = 'DOCKED' where id = v_fl;
    -- five ranks of each: 350 badges an upgrade, the top refused, the perk by rank
    v_n := 0;
    for x in select k.code from public.captain_upgrade_kinds k where k.code in ('drill', 'surgeon') order by k.ord loop
      for i in 1 .. 5 loop
        v_r := cmd.captain_upgrade(v_code, x.code);
        if (v_r->>'ok')::boolean is not true or (v_r->>'rank')::int <> i or (v_r->>'cost')::int <> 5 * i * (i + 1) then
          raise exception '0533 self-assert FAIL: rank % of %: %', i, x.code, v_r;
        end if;
        v_n := v_n + (v_r->>'cost')::int;
      end loop;
      v_r := cmd.captain_upgrade(v_code, x.code);
      if v_r->>'error_code' <> 'E_TOP_RANK' then
        raise exception '0533 self-assert FAIL: past the top of %: %', x.code, v_r;
      end if;
    end loop;
    select b.balance into v_bal from public.honor_balance b where b.player_id = v_me;
    v_p1 := public.captain_work_perk(v_po, 'arms');
    if v_n <> 700 or v_bal <> 300 or (v_p1->>'attack_pct')::numeric <> 15 or (v_p1->>'crew_pct')::numeric <> (v_p0->>'crew_pct')::numeric + 30
       or v_p1->'time_pct' is distinct from v_p0->'time_pct' or (v_p1->>'carry_pct')::numeric <> 0
       or (select sum((u->>'rank')::int) from jsonb_array_elements(world.captains()->'captains') e, jsonb_array_elements(e->'upgrades') u where e->>'code' = v_code) <> 10 then
      raise exception '0533 self-assert FAIL: 700 badges, the perk: % spent, % left, %', v_n, v_bal, v_p1;
    end if;
    delete from public.player_officers where id = v_po;
    if exists (select 1 from public.captain_upgrades u where u.player_officer_id = v_po) then
      raise exception '0533 self-assert FAIL: a dismissed captain left her ranks';
    end if;
    raise exception using errcode = 'ZX533', message = 'PROBE_ROLLBACK_0533';
  exception when sqlstate 'ZX533' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0533 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.auth_uid::text like '00000000-0533-4000-8000-%') or public.wc('honor_enabled') is distinct from 'false'::jsonb then
    raise exception '0533 self-assert FAIL: the probe left something behind';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0533 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0533 self-assert ok: CAPTAIN UPGRADES (dark). Five hunks once and reversing; four new functions, one door; no other function or knob moved; no body at sea reads the perk. Probe (rolled back) whole. % ms. %', round(extract(epoch from clock_timestamp() - v_t0) * 1000), v_note;
end $m$;
