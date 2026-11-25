-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights it)
-- 0529 - CAPTAIN PLACES  (dark: captain_places_enabled, false)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25 (R4): "First you will start with 2 captains, and later with levels and reputation, as well as gold, you will be able
--   to unlock more captains." The owner sets the price of the third and up; a company whose places are full dismisses first (the lead's word).
--   docs/design/captains-land-2026-11-25.md section 4; docs/dev-log/2026-11-25-captain-works.md.
--
-- WHAT (lit; dark every body answers as before):
--   public.captain_places          DATA: the places and what each asks {total_level, reputation, ducats}. 1 and 2 are free; 3 to 8 are NULL, so
--                                  not open: no door opens them until the owner writes the prices.
--   public.captain_places_open     a company's opened places (one row once it opens its third); none: 2.
--   public.captain_sign_rows       the rows of a signing, MOVED WHOLE out of public.sign_officer (its one hunk calls it): one body signs.
--   public.captains_found          tops a player's company up to two: of her country first, the lowest grade first, a focus she does not hold first,
--                                  then by code; no wage (nothing is paid, nothing is minted), a SIGNED_OFFICER event at cost 0.
--   public.new_house     (1 hunk)  lit, a player's new company gets its two.
--   cmd.hire_officer     (1 hunk)  lit, every place taken: E_CAPTAIN_ROOM. public.hq_board_for (1 hunk) offers no hire the Inn would refuse.
--   cmd.captain_place              opens the next place: a price the owner has set, her total level, Reputation (public.reputation_credit, a new
--                                  spend kind) and coin (public.pay_city SLOT to her home), all or nothing.
--   cmd.captain_dismiss            lets a captain go (none could before): ashore, docked or with a party at home. Her levels, skills and works go
--                                  with her, as 0127 decided; nothing is refunded.
--   world.captains       (1 hunk)  lit, `places` {places, used, next}.
--   public.captain_places_light    THE ONE STEP that lights it: the switch true and every company of a player topped up. Run by the lead.
-- CAPTAINS ABOVE THE PLACES ARE KEPT: nothing ever removes one. Merchants: public.sign_officer asks no place (the door does).
-- ROWS: 8 data rows, 1 config row. Lit: 0 rows a minute idle; a founding 2 x 8 rows once; the light step the same a company with none.
-- budget: no cron job, no autovacuum or fillfactor change; two small tables.
-- LOCKS: CREATE TABLE x2; CREATE OR REPLACE x6 by hunks. TIME: under a second.
-- ROLLBACK (forward, owner only): captain_places_enabled false (the captains given stay).
-- SELF-ASSERT: hunks once and reversing; no other function or knob moved; then probe companies of this file's own, rolled back: dark nothing; a
--   company with none, with one and with three is topped to two, two and three; a founding lit gives two and moves no coin; the Inn's gate; a
--   price that is NULL opens nothing; a priced place asks each of its three and takes all or nothing; a dismissal frees one.
-- VERSION: 0529. 0528 stands below it (the registry row and world.captains' first hunk are 0528's and 0527's).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $m$
declare
  c_hunked constant text[] := array['public.sign_officer(uuid,text,uuid)', 'public.new_house(uuid,text,text,text,text,text,text,bigint,boolean)', 'cmd.hire_officer(text,uuid)', 'world.captains()', 'public.hq_board_for(uuid)', 'public.client_rpc_entry_points()']::text[];
  c_new    constant text[] := array['public.captain_places_on()', 'public.captain_sign_rows(uuid,uuid)', 'public.captains_found(uuid)', 'public.captain_places_count(uuid)', 'public.captain_places_full(uuid)', 'public.captain_places_card(uuid)', 'public.captain_place_for(uuid)', 'public.captain_dismiss_for(uuid,text)', 'public.captain_places_light()', 'cmd.captain_place()', 'cmd.captain_dismiss(text)']::text[];
  c_doors  constant text[] := array['cmd.captain_place()', 'cmd.captain_dismiss(text)']::text[];
  c_knobs  constant text[] := array['captain_places_enabled']::text[];
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
  v_a uuid; v_b uuid; v_c uuid; v_fl uuid; v_sh uuid; v_r jsonb; v_k jsonb; v_p0 bigint; v_tl int; v_rep int; v_seq0 int; v_code text; i int;
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = any (c_knobs)) or exists (select 1 from unnest(c_new) u(q) where to_regprocedure(u.q) is not null) then
    raise exception '0529 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked) u(q) where to_regprocedure(u.q) is null) or to_regprocedure('public.captain_works_on()') is null then
    raise exception '0529 refuses: a body it cuts or a reading it asks is not in this world';
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
  -- retention: none, bounded by the catalogue (8 places, data of this file; the owner prices them)
  create table public.captain_places (
    place       int primary key check (place between 1 and 20),
    total_level int    check (total_level >= 0),
    reputation  int    check (reputation >= 0),
    ducats      bigint check (ducats >= 0),
    check (place > 2 or (total_level, reputation, ducats) = (0, 0, 0)));
  alter table public.captain_places enable row level security;
  revoke all on table public.captain_places from public, anon, authenticated, service_role;
  comment on table public.captain_places is '0529: a company''s captain places and what each asks. A NULL anywhere: the place is not open (the owner sets the price). Server only.';
  insert into public.captain_places (place, total_level, reputation, ducats)
  values (1, 0, 0, 0), (2, 0, 0, 0), (3, null, null, null), (4, null, null, null), (5, null, null, null), (6, null, null, null), (7, null, null, null), (8, null, null, null);
  -- retention: none, bounded by one row a company that opened its third place
  create table public.captain_places_open (
    player_id uuid primary key references public.players(id) on delete cascade,
    opened    int not null check (opened >= 3));
  alter table public.captain_places_open enable row level security;
  revoke all on table public.captain_places_open from public, anon, authenticated, service_role;
  comment on table public.captain_places_open is '0529: how many captain places a company has opened, once more than the two it starts with. Writer: public.captain_place_for. Server only.';
  insert into public.reputation_kinds (code, sign, capped, word) values ('captain_place', -1, false, 'Captain place');

  -- ── 3. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('captain_places_enabled', 'false'::jsonb, '0529: THE SWITCH (the owner''s; lit by public.captain_places_light alone, which also gives every company its first two). true: a company starts with two captains and hires no more than its places; places 3 and up are opened by level, Reputation and coin where the owner has priced them. false: the Inn as before.');

  -- ── 4. THE RULES ──

  execute $f$
create function public.captain_places_on()
returns boolean language sql stable security definer set search_path = public, pg_temp
as $body$
  -- 0529: THE SWITCH, read once: world_config captain_places_enabled.
  select public.wc('captain_places_enabled') = 'true'::jsonb
$body$
  $f$;

  execute $f$
create function public.captain_sign_rows(p_player uuid, p_officer uuid)
returns uuid language plpgsql security definer set search_path = public, pg_temp
as $body$
-- 0529: THE ROWS OF A SIGNING, moved whole out of public.sign_officer (0157, 0160): the signing, the traits she uses (a merchant's captain her
-- job alone, a player's her first `slots` known traits) and, a player's, her state and her three tracks. No seat, no coin, no event.
declare
  v_id  uuid;
  v_npc boolean;
begin
  insert into public.player_officers (player_id, officer_id)
  values (p_player, p_officer)
  returning id into v_id;
  select pl.is_npc into v_npc from public.players pl where pl.id = p_player;
  insert into public.captain_active (player_officer_id, trait)
  select v_id, ct.trait
    from public.captain_profile cp
    join public.captain_grades g on g.code = cp.grade
    join public.captain_traits ct on ct.officer_id = cp.officer_id
   where cp.officer_id = p_officer and (case when v_npc then ct.ord = 1 else ct.ord <= g.slots end);
  if not v_npc then
    insert into public.captain_state (player_officer_id, grade, home_seen_at)
    select v_id, cp.grade, now() from public.captain_profile cp where cp.officer_id = p_officer;
    insert into public.captain_xp (player_officer_id) values (v_id);
  end if;
  return v_id;
end
$body$
  $f$;

  execute $f$
create function public.captains_found(p_player uuid)
returns int language plpgsql security definer set search_path = public, pg_temp
as $body$
-- 0529: A PLAYER'S COMPANY TOPPED UP TO TWO CAPTAINS, signed at no wage (no coin moves). Which: a focus she does not hold first, then the
-- lowest grade, her country, the code. A merchant: none. Returns how many were signed.
declare
  v_n   int := 0;
  v_o   record;
begin
  if coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then
    return 0;
  end if;
  while (select count(*) from public.player_officers po where po.player_id = p_player) < 2 loop
    select o.id, o.name, o.code, j.job, j.job_pct into v_o
      from public.officers o
      join public.captain_profile cp on cp.officer_id = o.id
      join public.captain_grades g on g.code = cp.grade
      join public.captain_job j on j.officer_id = o.id
      join public.traits t on t.code = j.job
     where not exists (select 1 from public.player_officers po where po.player_id = p_player and po.officer_id = o.id)
     order by exists (select 1 from public.player_officers po join public.captain_job j2 on j2.officer_id = po.officer_id join public.traits t2 on t2.code = j2.job
                       where po.player_id = p_player and (t2.focus = 'combat') = (t.focus = 'combat')),
              g.ord, o.nation_id is distinct from (select pl.nation_id from public.players pl where pl.id = p_player), o.code
     limit 1;
    exit when v_o.id is null;
    perform public.captain_sign_rows(p_player, v_o.id);
    perform public.emit_event(p_player, 'SIGNED_OFFICER', jsonb_build_object(
      'officer', v_o.name, 'code', v_o.code, 'specialty', v_o.job, 'bonus_pct', v_o.job_pct, 'cost', 0));
    v_n := v_n + 1;
  end loop;
  return v_n;
end
$body$
  $f$;

  execute $f$
create function public.captain_places_count(p_player uuid)
returns int language sql stable security definer set search_path = public, pg_temp
as $body$
  -- 0529: how many captain places a company has: two, or what it has opened.
  select coalesce((select o.opened from public.captain_places_open o where o.player_id = p_player), 2)
$body$
  $f$;

  execute $f$
create function public.captain_places_full(p_player uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp
as $body$
  -- 0529: is every captain place of hers taken? Dark: never.
  select public.captain_places_on()
         and (select count(*) from public.player_officers po where po.player_id = p_player) >= public.captain_places_count(p_player)
$body$
  $f$;

  execute $f$
create function public.captain_places_card(p_player uuid)
returns jsonb language sql stable security definer set search_path = public, pg_temp
as $body$
  -- 0529: {places, used, next: {place, open, total_level, reputation, ducats, have {total_level, reputation, ducats}}}; next null past the last
  -- place. open false: the owner has not priced it, and no figure is served. Her total level is the sum of the levels the Skills list shows.
  select jsonb_build_object(
    'places', public.captain_places_count(p_player),
    'used', (select count(*) from public.player_officers po where po.player_id = p_player),
    'next', (select jsonb_build_object('place', p.place, 'open', z.priced) || case when not z.priced then '{}'::jsonb else jsonb_build_object(
                      'total_level', p.total_level, 'reputation', p.reputation, 'ducats', p.ducats,
                      'have', jsonb_build_object(
                        'total_level', (select coalesce(sum((s->>'level')::int), 0) from jsonb_array_elements(public.level_skills_card(p_player, public.player_progress(p_player))->'skills') s),
                        'reputation', coalesce((select b.balance from public.reputation_balance b where b.player_id = p_player), 0),
                        'ducats', (select pl.ducats from public.players pl where pl.id = p_player))) end
               from public.captain_places p
              cross join lateral (select p.total_level is not null and p.reputation is not null and p.ducats is not null as priced) z
              where p.place = public.captain_places_count(p_player) + 1))
$body$
  $f$;

  execute $f$
create function public.captain_place_for(p_player uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $body$
-- 0529: CORE of cmd.captain_place: her next captain place, by the card it is shown by (public.captain_places_card). Refused: dark or not priced
-- (E_NOT_IN_USE), the last place open (E_AT_CAPACITY), her total level (E_LEVEL_TOO_LOW), her purse (E_NOT_ENOUGH_DUCATS), her Reputation
-- (public.reputation_credit's own refusal). All or nothing. Server only.
declare
  v_n jsonb;
  p   jsonb;
begin
  if not public.captain_places_on() then
    perform cmd.refuse('E_NOT_IN_USE', 'captain places are not open yet');
  end if;
  perform 1 from public.players pl where pl.id = p_player for update;
  v_n := public.captain_places_card(p_player)->'next';
  if jsonb_typeof(v_n) is distinct from 'object' then
    perform cmd.refuse('E_AT_CAPACITY', 'every captain place is open');
  end if;
  if not (v_n->>'open')::boolean then
    perform cmd.refuse('E_NOT_IN_USE', 'that place is not open yet');
  end if;
  p := v_n->'have';
  if (p->>'total_level')::int < (v_n->>'total_level')::int then
    perform cmd.refuse('E_LEVEL_TOO_LOW', format('Needs total level %s: you have %s', v_n->>'total_level', p->>'total_level'), cmd.figures((p->>'total_level')::numeric, (v_n->>'total_level')::numeric, 'level'));
  end if;
  if (p->>'ducats')::bigint < (v_n->>'ducats')::bigint then
    perform cmd.refuse('E_NOT_ENOUGH_DUCATS', format('Money %s / %s', p->>'ducats', v_n->>'ducats'), cmd.figures((p->>'ducats')::numeric, (v_n->>'ducats')::numeric, 'ducats'));
  end if;
  if (v_n->>'reputation')::int > 0 then
    if public.wc('reputation_on') is distinct from 'true'::jsonb then
      perform cmd.refuse('E_NOT_IN_USE', 'Reputation is not open now');
    end if;
    perform public.reputation_credit(p_player, 'captain_place', -(v_n->>'reputation')::int, 'captain_place:' || (v_n->>'place'));
  end if;
  if (v_n->>'ducats')::bigint > 0 then
    perform public.pay_city(p_player, public.home_port_of(p_player), 'SLOT', (v_n->>'ducats')::bigint, null);
  end if;
  insert into public.captain_places_open (player_id, opened) values (p_player, (v_n->>'place')::int)
  on conflict (player_id) do update set opened = excluded.opened;
  return jsonb_build_object('ok', true, 'places', (v_n->>'place')::int, 'sentence', format('%s captain places.', v_n->>'place'));
end
$body$
  $f$;

  execute $f$
create function public.captain_dismiss_for(p_player uuid, p_code text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $body$
-- 0529: CORE of cmd.captain_dismiss: a captain let go. Refused: dark (E_NOT_IN_USE), not hers (E_NOT_SIGNED), seated in a fleet that is not docked
-- (E_NOT_IN_PORT), out with a land party (E_LAND_OUT). Her signing's rows go with her (cascade). Nothing is paid or given back. Server only.
declare
  v_po   uuid;
  v_name text;
  v_now  record;
begin
  if not public.captain_places_on() then
    perform cmd.refuse('E_NOT_IN_USE', 'captain places are not open yet');
  end if;
  select po.id, o.name into v_po, v_name
    from public.player_officers po join public.officers o on o.id = po.officer_id where po.player_id = p_player and o.code = upper(btrim(coalesce(p_code, '')));
  if v_po is null then
    perform cmd.refuse('E_NOT_SIGNED', 'You do not keep that captain.');
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
  delete from public.player_officers where id = v_po;
  return jsonb_build_object('ok', true, 'officer', upper(btrim(p_code)), 'sentence', format('%s has left you.', v_name));
end
$body$
  $f$;

  execute $f$
create function public.captain_places_light()
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $body$
-- 0529: THE ONE STEP that lights the places (the lead's, on the owner's word): every company of a player with a login is topped up to two
-- captains (public.captains_found), then the switch. A second call tops up nobody and changes nothing. Server only.
declare
  v_n int := 0;
  x   record;
begin
  for x in select p.id from public.players p where not p.is_npc and p.auth_uid is not null order by p.id loop
    v_n := v_n + public.captains_found(x.id);
  end loop;
  update public.world_config set value = 'true'::jsonb where key = 'captain_places_enabled';
  return jsonb_build_object('signed', v_n, 'on', public.captain_places_on());
end
$body$
  $f$;

  execute $f$
create function cmd.captain_place()
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $body$
-- 0529: open your next captain place. The rule is public.captain_place_for's.
declare
  v_player uuid := public.current_player_id();
  v_det    text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_SIGNED_IN', 'error_message', 'Nobody is signed in.', 'fixes', jsonb_build_array('(sign in)'));
  end if;
  begin
    return public.captain_place_for(v_player);
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end
$body$
  $f$;

  execute $f$
create function cmd.captain_dismiss(p_code text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $body$
-- 0529: let a captain of yours go. The rule is public.captain_dismiss_for's.
declare
  v_player uuid := public.current_player_id();
  v_det    text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_SIGNED_IN', 'error_message', 'Nobody is signed in.', 'fixes', jsonb_build_array('(sign in)'));
  end if;
  begin
    return public.captain_dismiss_for(v_player, p_code);
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
  create temp table hunks_0529 (fn text, ord int, old text, new text) on commit drop;

  insert into hunks_0529 values ('public.sign_officer(uuid,text,uuid)', 1,
$h$  insert into public.player_officers (player_id, officer_id)
  values (v_player, v_off.id)
  returning id into v_id;

  -- 0157: what she USES — a merchant's captain her job alone (O8: fixed), a player's her first `slots`
  -- known traits — a player's state row, and, hired into a fleet, her seat by the one picker.
  select pl.is_npc into v_npc from public.players pl where pl.id = v_player;
  insert into public.captain_active (player_officer_id, trait)
  select v_id, ct.trait
    from public.captain_profile cp
    join public.captain_grades g on g.code = cp.grade
    join public.captain_traits ct on ct.officer_id = cp.officer_id
   where cp.officer_id = v_off.id and (case when v_npc then ct.ord = 1 else ct.ord <= g.slots end);
  if not v_npc then
    insert into public.captain_state (player_officer_id, grade, home_seen_at)
    select v_id, cp.grade, now() from public.captain_profile cp where cp.officer_id = v_off.id;
    insert into public.captain_xp (player_officer_id) values (v_id);   -- 0160: her three tracks, from nothing
  end if;
$h$,
$h$  -- 0529: the rows of a signing are public.captain_sign_rows' (moved there whole: a founding's two captains are signed by the same)
  v_id := public.captain_sign_rows(v_player, v_off.id);
$h$);

  insert into hunks_0529 values ('public.new_house(uuid,text,text,text,text,text,text,bigint,boolean)', 1,
$h$  perform public.commission_ship(v_player, v_fleet, p_class_code, p_ship_name, true, true);
$h$,
$h$  perform public.commission_ship(v_player, v_fleet, p_class_code, p_ship_name, true, true);
  -- 0529 (captain_places_enabled): a company of a player starts with two captains
  if public.captain_places_on() and not coalesce(p_is_npc, false) then
    perform public.captains_found(v_player);
  end if;
$h$);

  insert into hunks_0529 values ('cmd.hire_officer(text,uuid)', 1,
$h$  -- 0096: the signing, the wage and the record are public.sign_officer's$h$,
$h$  -- 0529: every place of hers is taken: she hires nobody until one is free
  if public.captain_places_full(v_player) then
    return jsonb_build_object('ok', false, 'error_code', 'E_CAPTAIN_ROOM',
      'error_message', format('Every captain place is taken (%s).', public.captain_places_count(v_player)),
      'fixes', jsonb_build_array('(dismiss a captain first, or open a place)'));
  end if;
  -- 0096: the signing, the wage and the record are public.sign_officer's$h$);

  insert into hunks_0529 values ('world.captains()', 1,
$h$  return jsonb_build_object('captains', ($h$,
$h$  return case when public.captain_places_on() then jsonb_build_object('places', public.captain_places_card(v_player)) else '{}'::jsonb end   -- 0529
      || jsonb_build_object('captains', ($h$);

  insert into hunks_0529 values ('public.hq_board_for(uuid)', 1,
$h$               and o.wage <= v_purse) c), '[]'::jsonb);$h$,
$h$               and not public.captain_places_full(p_player)   -- 0529: no hire is offered that the Inn would refuse
               and o.wage <= v_purse) c), '[]'::jsonb);$h$);

  insert into hunks_0529 values ('public.client_rpc_entry_points()', 1,
$h$      ('cmd',         'captain_land',          'text, int'),
$h$,
$h$      ('cmd',         'captain_land',          'text, int'),
      -- 0529: open the next captain place; dismiss a captain (dark: E_NOT_IN_USE)
      ('cmd',         'captain_place',         ''),
      ('cmd',         'captain_dismiss',       'text'),
$h$);


  for v_h in select h.fn from hunks_0529 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0529 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0529 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0529 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0529 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0529 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 6. SELF-ASSERT: the catalog, the grants, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0529 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) is distinct from v_meta then
    raise exception '0529 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('anon', u.q::regprocedure, 'execute') or has_function_privilege('service_role', u.q::regprocedure, 'execute')
                 or has_function_privilege('authenticated', u.q::regprocedure, 'execute') <> (u.q = any (c_doors)))
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0529 self-assert FAIL: a new function is reachable by a client that should not reach it, or a client may write';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before then
    raise exception '0529 self-assert FAIL: a knob of another file moved';
  end if;

  -- ── 7. THE PROBE, rolled back by a raised sentinel (its own companies' rows) ──
  begin
    v_a := public.new_house('00000000-0529-4000-8000-000000000001', 'Casa Um 0529', 'PRT');
    perform cmd.assume_identity('00000000-0529-4000-8000-000000000001');
    update public.world_config set value = 'true'::jsonb where key = 'reputation_on';
    -- DARK: no captain comes, no door opens, no card
    if exists (select 1 from public.player_officers po where po.player_id = v_a) or cmd.captain_place()->>'error_code' <> 'E_NOT_IN_USE'
       or cmd.captain_dismiss('NOBODY')->>'error_code' <> 'E_NOT_IN_USE' or world.captains() ? 'places' or public.captain_places_full(v_a) then
      raise exception '0529 self-assert FAIL: dark, something is open';
    end if;
    -- the moved rows: a company with three signed before (by the one body), each with her state, her tracks and her grade's traits
    v_b := public.new_house('00000000-0529-4000-8000-000000000002', 'Casa Tres 0529', 'NLD');
    for x in select o.id from public.officers o join public.captain_profile cp on cp.officer_id = o.id order by o.code limit 3 loop
      perform public.captain_sign_rows(v_b, x.id);
    end loop;
    if exists (select 1 from public.player_officers po join public.captain_profile cp on cp.officer_id = po.officer_id join public.captain_grades g on g.code = cp.grade
                where po.player_id = v_b
                  and ((select count(*) from public.captain_active ca where ca.player_officer_id = po.id) <> least(g.slots, (select count(*) from public.captain_traits ct where ct.officer_id = po.officer_id))
                       or not exists (select 1 from public.captain_state st where st.player_officer_id = po.id and st.grade = cp.grade)
                       or not exists (select 1 from public.captain_xp cx where cx.player_officer_id = po.id))) then
      raise exception '0529 self-assert FAIL: a signing''s rows are not what 0157 and 0160 made them';
    end if;
    -- TOP UP: none -> 2, three -> 3 (kept), again -> nothing; two different kinds, the lowest grade, no coin
    select ducats into v_p0 from public.players where id = v_a;
    v_n := public.captains_found(v_a);
    i := public.captains_found(v_a) + public.captains_found(v_b);
    if v_n <> 2 or i <> 0
       or (select count(*) from public.player_officers po where po.player_id = v_a) <> 2 or (select count(*) from public.player_officers po where po.player_id = v_b) <> 3
       or (select count(distinct (t.focus = 'combat')) from public.player_officers po join public.captain_job j on j.officer_id = po.officer_id join public.traits t on t.code = j.job where po.player_id = v_a) <> 2
       or exists (select 1 from public.player_officers po join public.captain_profile cp on cp.officer_id = po.officer_id join public.captain_grades g on g.code = cp.grade where po.player_id = v_a and g.ord > 1)
       or (select ducats from public.players where id = v_a) <> v_p0 or exists (select 1 from public.captain_seats cs join public.player_officers po on po.id = cs.player_officer_id where po.player_id = v_a) then
      raise exception '0529 self-assert FAIL: the top-up is not two captains of two kinds at the lowest grade, unseated, for nothing: %', (select jsonb_agg(jsonb_build_object('p', po.player_id = v_a, 'c', o.code, 'g', cp.grade, 'f', t.focus)) from public.player_officers po join public.officers o on o.id = po.officer_id join public.captain_profile cp on cp.officer_id = o.id join public.captain_job j on j.officer_id = o.id join public.traits t on t.code = j.job where po.player_id in (v_a, v_b));
    end if;
    delete from public.player_officers where id = (select po.id from public.player_officers po where po.player_id = v_a order by po.id limit 1);
    if public.captains_found(v_a) <> 1 then
      raise exception '0529 self-assert FAIL: a company with one was not topped up by one';
    end if;
    -- LIT: a founding gives two (a merchant's none)
    update public.world_config set value = 'true'::jsonb where key = 'captain_places_enabled';
    v_c := public.new_house('00000000-0529-4000-8000-000000000003', 'Casa Nova 0529', 'ESP');
    if (select count(*) from public.player_officers po where po.player_id = v_c) <> 2
       or (select count(*) from public.events e where e.player_id = v_c and e.kind = 'SIGNED_OFFICER' and (e.payload->>'cost')::numeric = 0) <> 2
       or (select count(*) from public.ledger l where l.player_id = v_c) <> 1 then
      raise exception '0529 self-assert FAIL: a founding lit is not two captains and the founding coin alone';
    end if;
    -- THE INN'S GATE (the door's own, after the room): full, not full; the board's reading is the same one
    if not public.captain_places_full(v_c) or not public.captain_places_full(v_b) or (public.captain_places_card(v_b)->>'used')::int <> 3 or (public.captain_places_card(v_b)->>'places')::int <> 2 then
      raise exception '0529 self-assert FAIL: full is not full';
    end if;
    -- NOT PRICED: nothing opens
    v_k := world.captains()->'places';
    if v_k <> '{"places": 2, "used": 2, "next": {"place": 3, "open": false}}'::jsonb or cmd.captain_place()->>'error_code' <> 'E_NOT_IN_USE' then
      raise exception '0529 self-assert FAIL: an unpriced place is served or opened: %', v_k;
    end if;
    -- PRICED (inside this probe alone): each of its three asked, all or nothing
    v_tl := (select sum((s->>'level')::int) from jsonb_array_elements(public.level_skills_card(v_a, public.player_progress(v_a))->'skills') s);
    update public.captain_places set total_level = v_tl + 1, reputation = 40, ducats = 1000 where place = 3;
    update public.players set ducats = 5000 where id = v_a;
    insert into public.reputation_balance (player_id) values (v_a) on conflict do nothing;
    if cmd.captain_place()->>'error_code' <> 'E_LEVEL_TOO_LOW' then raise exception '0529 self-assert FAIL: her total level was not asked'; end if;
    update public.captain_places set total_level = v_tl where place = 3;
    update public.players set ducats = 999 where id = v_a;
    if cmd.captain_place()->>'error_code' <> 'E_NOT_ENOUGH_DUCATS' then raise exception '0529 self-assert FAIL: her purse was not asked'; end if;
    update public.players set ducats = 5000 where id = v_a;
    v_r := cmd.captain_place();
    if v_r->>'error_code' <> 'E_NOT_ENOUGH_REPUTATION' or (select ducats from public.players where id = v_a) <> 5000 or public.captain_places_count(v_a) <> 2 then
      raise exception '0529 self-assert FAIL: her Reputation was not asked, or something was taken';
    end if;
    perform public.reputation_credit(v_a, 'level', 100, 'probe-0529');
    select b.balance into v_rep from public.reputation_balance b where b.player_id = v_a;
    v_r := cmd.captain_place();
    if (v_r->>'ok')::boolean is not true or public.captain_places_count(v_a) <> 3 or (select ducats from public.players where id = v_a) <> 4000
       or (select b.balance from public.reputation_balance b where b.player_id = v_a) <> v_rep - 40 or public.captain_places_full(v_a)
       or (select count(*) from public.ledger l where l.player_id = v_a and l.kind = 'SLOT' and l.ducats_delta = -1000) <> 1 then
      raise exception '0529 self-assert FAIL: the place was not opened for its price: % (reputation % of %)', v_r, (select b.balance from public.reputation_balance b where b.player_id = v_a), v_rep;
    end if;
    if cmd.captain_place()->>'error_code' <> 'E_NOT_IN_USE' then raise exception '0529 self-assert FAIL: the fourth, unpriced, opened'; end if;
    update public.captain_places_open set opened = 8 where player_id = v_a;
    if cmd.captain_place()->>'error_code' <> 'E_AT_CAPACITY' then raise exception '0529 self-assert FAIL: past the last place'; end if;
    -- DISMISS: not from a fleet that is not docked; ashore she goes, with all that is hers
    update public.captain_places_open set opened = 3 where player_id = v_a;
    select f.id into v_fl from public.fleets f where f.player_id = v_a;
    select s.id into v_sh from public.ships s where s.fleet_id = v_fl and s.is_flagship;
    select o.code into v_code from public.player_officers po join public.officers o on o.id = po.officer_id where po.player_id = v_a order by o.code limit 1;
    perform public.seat_captain_for(v_a, v_code, v_sh, 1);
    update public.fleets set status = 'UNABLE_TO_SAIL' where id = v_fl;
    if cmd.captain_dismiss(v_code)->>'error_code' <> 'E_NOT_IN_PORT' then raise exception '0529 self-assert FAIL: dismissed from a fleet that is not docked'; end if;
    update public.fleets set status = 'DOCKED' where id = v_fl;
    v_r := cmd.captain_dismiss(v_code);
    if (v_r->>'ok')::boolean is not true or (select count(*) from public.player_officers po where po.player_id = v_a) <> 1 or exists (select 1 from public.captain_seats cs where cs.ship_id = v_sh)
       or cmd.captain_dismiss(v_code)->>'error_code' <> 'E_NOT_SIGNED' then
      raise exception '0529 self-assert FAIL: she was not let go: %', v_r;
    end if;
    raise exception using errcode = 'ZX529', message = 'PROBE_ROLLBACK_0529';
  exception when sqlstate 'ZX529' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0529 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.auth_uid::text like '00000000-0529-4000-8000-%') or public.wc('captain_places_enabled') is distinct from 'false'::jsonb or exists (select 1 from public.captain_places p where p.place > 2 and (p.total_level is not null or p.reputation is not null or p.ducats is not null)) then
    raise exception '0529 self-assert FAIL: the probe left something behind';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0529 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0529 self-assert ok: CAPTAIN PLACES (dark). Six hunks once and reversing; eleven new functions, two doors; places 3 to 8 unpriced; no other function or knob moved. Probe (rolled back) whole. % ms. %', round(extract(epoch from clock_timestamp() - v_t0) * 1000), v_note;
end $m$;
