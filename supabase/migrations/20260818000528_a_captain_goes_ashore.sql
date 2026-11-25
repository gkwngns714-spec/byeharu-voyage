-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights it)
-- 0528 - A CAPTAIN GOES ASHORE  (dark: captain_works_enabled, 0527's switch)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-25 (R4): "The captains can be used to send on land sites, or it can even be assigned to a fleet - ship, and give perks."
--   docs/design/captains-land-2026-11-25.md section 5; docs/dev-log/2026-11-25-captain-works.md.
--
-- WHAT:
--   public.captain_seats     a seat is a ship's cabin OR a land party, never both: ship_id and seat may be null, party_id (NEW), one check, and a
--                            party has one captain (unique). ONE SEAT A CAPTAIN is the table's primary key, as it was.
--   public.captain_seat_put  (1 hunk) a cabin taken clears her party (the writer of cabins).
--   public.captain_land_put  the writer of a party's seat: her cabin is cleared, the party's captain before her comes ashore.
--   public.captain_land_for  the core of cmd.captain_land(code, party): lit alone (E_NOT_IN_USE); her captain (E_NOT_SIGNED); her ship docked
--                            (E_NOT_IN_PORT); the party she leaves and the party she joins are home (E_LAND_OUT); the party exists (E_NO_SUCH_PARTY).
--                            party null: she leaves the land.
--   public.seat_captain_for  (1 hunk) a captain with a party that is out boards no ship (E_LAND_OUT).
--   public.land_terms        (1 hunk) the party's captain shortens a turn by her level in the job's work (public.captain_work_perk), frozen at Send
--                            as everything there is; her name on the terms. No captain, or dark: the terms to the letter.
--   public.land_settle       (1 hunk) the experience a booking gives the company is given to the party's captain too.
--   world.captains           (2 hunks) lit, `party` (its number) and can_change for a captain ashore with a party.
--   public.client_rpc_entry_points (1 hunk) the door.
-- DARK, NO LAND SEAT CAN EXIST, so every reader of captain_seats answers as before; they all join a ship by ship_id, and a land row has none.
-- PARTIES: the check `ord = 1` becomes `ord >= 1`; only party 1 is made by any door of this file (the land's doors know no other). 0531 opens
--   the second, with a captain on it.
-- ROWS: a press writes 1; a Collect 1 more at most once in land_book_minutes a party. No table, no cron, no beat step: 0 new rows a minute.
-- budget: no cron job, no autovacuum or fillfactor change, no new table; two columns relaxed and one added on a table of one row a seated captain.
-- LOCKS: ALTER captain_seats and land_parties (ACCESS EXCLUSIVE for an instant, under lock_timeout 5 s; a foreign key between the two).
-- ROLLBACK (forward, owner only): captain_works_enabled false: the door refuses and land_terms asks nothing; a captain left with a party boards a
--   ship as ever (the party home).
-- SELF-ASSERT: hunks once and reversing; no other function or knob moved; then a probe company of this file's own, rolled back: the table itself
--   refuses two seats, none and two captains a party; dark the door refuses and the terms are the terms; lit she joins, the terms are shorter by
--   her level alone, a fleet's crew terms are what they are without her, she earns what a Collect books, and nobody leaves a party that is out.
-- VERSION: 0528.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $m$
declare
  c_hunked constant text[] := array['public.captain_seat_put(uuid,uuid,integer)', 'public.seat_captain_for(uuid,text,uuid,integer)', 'public.land_terms(uuid,text)', 'public.land_settle(uuid,timestamp with time zone)', 'world.captains()', 'public.client_rpc_entry_points()']::text[];
  c_new    constant text[] := array['public.captain_land_put(uuid,uuid)', 'public.captain_land_for(uuid,text,integer)', 'cmd.captain_land(text,integer)']::text[];
  c_doors  constant text[] := array['cmd.captain_land(text,integer)']::text[];
  c_knobs  constant text[] := array[]::text[];
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
  v_me   uuid; v_fl uuid; v_sh uuid; v_pa uuid; v_pb uuid; v_a uuid; v_b uuid; v_ca text; v_cb text; v_act text;
  v_t0j  jsonb; v_t1 jsonb; v_r jsonb; v_terms text; v_terms1 text; v_bad int := 0; v_at timestamptz; v_xp int;
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = any (c_knobs)) or exists (select 1 from unnest(c_new) u(q) where to_regprocedure(u.q) is not null) then
    raise exception '0528 refuses: it has been applied once';
  end if;
  if exists (select 1 from unnest(c_hunked) u(q) where to_regprocedure(u.q) is null) then
    raise exception '0528 refuses: a body it cuts or a reading it asks is not in this world';
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

  alter table public.land_parties drop constraint if exists land_parties_ord_check;
  alter table public.land_parties add constraint land_parties_ord_check check (ord >= 1);
  alter table public.captain_seats alter column ship_id drop not null;
  alter table public.captain_seats alter column seat drop not null;
  alter table public.captain_seats add column party_id uuid references public.land_parties(id) on delete cascade;
  alter table public.captain_seats add constraint captain_seats_one_place check ((ship_id is null) = (seat is null) and (ship_id is null) <> (party_id is null));
  alter table public.captain_seats add constraint captain_seats_one_captain_a_party unique (party_id);
  comment on column public.captain_seats.party_id is '0528: the land party she leads, when she sits in no ship. Written by public.captain_land_put.';

  -- ── 4. THE RULES ──

  execute $f$
create function public.captain_land_put(p_signing uuid, p_party uuid)
returns void language plpgsql security definer set search_path = public, pg_temp
as $body$
-- 0528: THE WRITER of a land party's seat (public.captain_seat_put writes cabins). Party null: she leaves the land. The party's captain
-- before her comes ashore. Judges nothing: public.captain_land_for does.
begin
  if p_party is null then
    delete from public.captain_seats cs where cs.player_officer_id = p_signing and cs.party_id is not null;
    return;
  end if;
  delete from public.captain_seats cs where cs.party_id = p_party and cs.player_officer_id <> p_signing;
  insert into public.captain_seats (player_officer_id, party_id) values (p_signing, p_party)
  on conflict (player_officer_id) do update set ship_id = null, seat = null, party_id = excluded.party_id;
end
$body$
  $f$;

  execute $f$
create function public.captain_land_for(p_player uuid, p_code text, p_party int)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $body$
-- 0528: CORE of cmd.captain_land: a captain of hers leads a land party, or leaves it (party null). The refusals: 0528's header. The party that
-- is out keeps the captain it was sent with: its terms were frozen on her level. Server only.
declare
  v_code  text := upper(btrim(coalesce(p_code, '')));
  v_po    uuid;
  v_name  text;
  v_now   record;
  v_party uuid;
begin
  if not public.captain_works_on() or not public.land_on() then
    perform cmd.refuse('E_NOT_IN_USE', 'captains ashore are not open yet');
  end if;
  select po.id, o.name into v_po, v_name
    from public.player_officers po join public.officers o on o.id = po.officer_id where po.player_id = p_player and o.code = v_code;
  if v_po is null then
    perform cmd.refuse('E_NOT_SIGNED', 'You do not keep that captain.');
  end if;
  select s.name as ship, f.status, lp.action into v_now
    from public.captain_seats cs
    left join public.ships s on s.id = cs.ship_id
    left join public.fleets f on f.id = s.fleet_id
    left join public.land_parties lp on lp.id = cs.party_id
   where cs.player_officer_id = v_po;
  if v_now.ship is not null and v_now.status is distinct from 'DOCKED' then
    perform cmd.refuse('E_NOT_IN_PORT', format('%s is at sea aboard %s. Captains change only in port.', v_name, v_now.ship));
  end if;
  if v_now.action is not null then
    perform cmd.refuse('E_LAND_OUT', format('%s is out with the party; call it home first', v_name));
  end if;
  if p_party is null then
    perform public.captain_land_put(v_po, null);
    return jsonb_build_object('ok', true, 'officer', v_code, 'party', null, 'sentence', format('%s is ashore.', v_name));
  end if;
  if p_party = 1 then
    v_party := public.land_party(p_player);   -- made at its first press, as every land door makes it
  else
    select lp.id into v_party from public.land_parties lp where lp.player_id = p_player and lp.ord = p_party;
  end if;
  if v_party is null then
    perform cmd.refuse('E_NO_SUCH_PARTY', 'there is no such party');
  end if;
  if exists (select 1 from public.land_parties lp where lp.id = v_party and lp.action is not null) then
    perform cmd.refuse('E_LAND_OUT', 'the party is out; call it home first');
  end if;
  perform public.captain_land_put(v_po, v_party);
  return jsonb_build_object('ok', true, 'officer', v_code, 'party', p_party, 'sentence', format('%s leads the land party.', v_name));
end
$body$
  $f$;

  execute $f$
create function cmd.captain_land(p_code text, p_party int default 1)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $body$
-- 0528: your captain leads your land party, or leaves it (party null). The rule is public.captain_land_for's.
declare
  v_player uuid := public.current_player_id();
  v_det    text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_SIGNED_IN', 'error_message', 'Nobody is signed in.', 'fixes', jsonb_build_array('(sign in)'));
  end if;
  begin
    return public.captain_land_for(v_player, p_code, p_party);
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
  create temp table hunks_0528 (fn text, ord int, old text, new text) on commit drop;

  insert into hunks_0528 values ('public.captain_seat_put(uuid,uuid,integer)', 1,
$h$do update set ship_id = excluded.ship_id, seat = excluded.seat;$h$,
$h$do update set ship_id = excluded.ship_id, seat = excluded.seat, party_id = null;   -- 0528: a cabin taken clears her party$h$);

  insert into hunks_0528 values ('public.seat_captain_for(uuid,text,uuid,integer)', 1,
$h$  if p_ship is null then
    perform public.captain_seat_put(v_po, null, null);$h$,
$h$  -- 0528: her land party is out: she stays with it
  if exists (select 1 from public.captain_seats cs join public.land_parties lp on lp.id = cs.party_id where cs.player_officer_id = v_po and lp.action is not null) then
    return jsonb_build_object('ok', false, 'error_code', 'E_LAND_OUT',
      'error_message', format('%s is out with the land party.', v_name), 'fixes', jsonb_build_array('(call the party home first)'));
  end if;
  if p_ship is null then
    perform public.captain_seat_put(v_po, null, null);$h$);

  insert into hunks_0528 values ('public.land_terms(uuid,text)', 1,
$h$  v_lack  text;
begin
  select * into j from public.land_actions a$h$,
$h$  v_lack  text;
  v_capt  jsonb;   -- 0528: the party's captain and what her level in the job's work gives
begin
  select * into j from public.land_actions a$h$);

  insert into hunks_0528 values ('public.land_terms(uuid,text)', 2,
$h$  v_m := coalesce((select s.march_seconds$h$,
$h$  -- 0528 (captain_works_enabled): the party's captain, by her level in the work (public.captain_work_perk); no captain or no such work: nothing
  if v_party.id is not null and public.captain_works_on() then
    select public.captain_work_perk(cs.player_officer_id, w.code) || jsonb_build_object('name', o.name, 'code', o.code, 'work', w.code) into v_capt
      from public.captain_seats cs
      join public.player_officers po on po.id = cs.player_officer_id
      join public.officers o on o.id = po.officer_id
      join public.captain_works w on w.skill = j.skill
     where cs.party_id = v_party.id;
    if v_capt is not null then
      v_a := greatest(1, round(v_a * (1 - (v_capt->>'time_pct')::numeric / 100)))::int;
    end if;
  end if;
  v_m := coalesce((select s.march_seconds$h$);

  insert into hunks_0528 values ('public.land_terms(uuid,text)', 3,
$h$    || case when v_make is not null then jsonb_build_object('make', $h$,
$h$    || case when v_capt is not null then jsonb_build_object('captain', v_capt) else '{}'::jsonb end   -- 0528
    || case when v_make is not null then jsonb_build_object('make', $h$);

  insert into hunks_0528 values ('public.land_settle(uuid,timestamp with time zone)', 1,
$h$    v_xp := lp.xp_due;
    lp.xp_due := 0;
$h$,
$h$    v_xp := lp.xp_due;
    -- 0528: the party's captain earns what the company earns, in the same work (public.captain_work_credit: nothing while dark or with none)
    if public.captain_works_on() then
      perform public.captain_work_credit((select cs.player_officer_id from public.captain_seats cs where cs.party_id = lp.id),
                                         (select w.code from public.captain_works w where w.skill = lp.xp_skill), v_xp);
    end if;
    lp.xp_due := 0;
$h$);

  insert into hunks_0528 values ('world.captains()', 1,
$h$      'can_change', (cs.player_officer_id is null or fl.status = 'DOCKED'),
$h$,
$h$      -- 0528: or she leads a party that is home (a land seat is in no fleet: fl.status is null)
      'can_change', (cs.player_officer_id is null or fl.status = 'DOCKED' or (cs.party_id is not null and not exists (select 1 from public.land_parties lp where lp.id = cs.party_id and lp.action is not null))),
$h$);

  insert into hunks_0528 values ('world.captains()', 2,
$h$jsonb_build_object('works', public.captain_works_card(po.id))$h$,
$h$jsonb_build_object('works', public.captain_works_card(po.id), 'party', (select lp.ord from public.land_parties lp where lp.id = cs.party_id))$h$);

  insert into hunks_0528 values ('public.client_rpc_entry_points()', 1,
$h$      ('cmd',         'captain_skill_up',      'text, text'),
$h$,
$h$      ('cmd',         'captain_skill_up',      'text, text'),
      -- 0528: a captain leads a land party, or leaves it (dark: E_NOT_IN_USE)
      ('cmd',         'captain_land',          'text, int'),
$h$);


  for v_h in select h.fn from hunks_0528 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0528 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0528 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0528 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0528 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0528 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 6. SELF-ASSERT: the catalog, the grants, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0528 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) is distinct from v_meta then
    raise exception '0528 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('anon', u.q::regprocedure, 'execute') or has_function_privilege('service_role', u.q::regprocedure, 'execute')
                 or has_function_privilege('authenticated', u.q::regprocedure, 'execute') <> (u.q = any (c_doors)))
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0528 self-assert FAIL: a new function is reachable by a client that should not reach it, or a client may write';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before then
    raise exception '0528 self-assert FAIL: a knob of another file moved';
  end if;

  -- ── 7. THE PROBE, rolled back by a raised sentinel (its own companies' rows) ──
  begin

    v_me := public.new_house('00000000-0528-4000-8000-000000000001', 'Casa da Praia 0528', 'PRT');
    perform cmd.assume_identity('00000000-0528-4000-8000-000000000001');
    select f.id into v_fl from public.fleets f where f.player_id = v_me;
    select s.id into v_sh from public.ships s where s.fleet_id = v_fl and s.is_flagship;
    update public.world_config set value = 'true'::jsonb where key = 'land_enabled';
    update public.world_config set value = 'false'::jsonb where key in ('crew_bite', 'skills_bite');   -- her level alone; the other switches are not asked
    select o.code into v_ca from public.officers o join public.captain_profile cp on cp.officer_id = o.id order by o.code limit 1;
    select o.code into v_cb from public.officers o join public.captain_profile cp on cp.officer_id = o.id order by o.code offset 1 limit 1;
    for x in select o.id, o.code from public.officers o where o.code in (v_ca, v_cb) loop
      insert into public.player_officers (player_id, officer_id) values (v_me, x.id);
      insert into public.captain_state (player_officer_id, grade, home_seen_at)
      select po.id, 'C', now() from public.player_officers po where po.player_id = v_me and po.officer_id = x.id;
    end loop;
    select po.id into v_a from public.player_officers po join public.officers o on o.id = po.officer_id where po.player_id = v_me and o.code = v_ca;
    select po.id into v_b from public.player_officers po join public.officers o on o.id = po.officer_id where po.player_id = v_me and o.code = v_cb;
    v_pa := public.land_party(v_me);
    insert into public.land_parties (player_id, port_id, ord) select v_me, lp.port_id, 2 from public.land_parties lp where lp.id = v_pa returning id into v_pb;

    -- THE TABLE: no seat with neither place, none with both, one captain a party, one seat a captain
    begin insert into public.captain_seats (player_officer_id) values (v_a); exception when check_violation then v_bad := v_bad + 1; end;
    begin insert into public.captain_seats (player_officer_id, ship_id, seat, party_id) values (v_a, v_sh, 1, v_pa); exception when check_violation then v_bad := v_bad + 1; end;
    begin insert into public.captain_seats (player_officer_id, seat, party_id) values (v_a, 1, v_pa); exception when check_violation then v_bad := v_bad + 1; end;
    begin insert into public.captain_seats (player_officer_id, party_id) values (v_a, v_pa), (v_b, v_pa); exception when unique_violation then v_bad := v_bad + 1; end;
    begin insert into public.captain_seats (player_officer_id, party_id) values (v_a, v_pa), (v_a, v_pb); exception when unique_violation then v_bad := v_bad + 1; end;
    if v_bad <> 5 then
      raise exception '0528 self-assert FAIL: the table took a seat it must refuse (% of 5 refused)', v_bad;
    end if;
    -- the job: the first mining job she may do at level 1 whose land is in reach of Lisbon (static rows)
    select a.code into v_act from public.land_actions a
     where a.skill = 'mining' and a.level = 1 and jsonb_typeof(public.land_terms(v_me, a.code)->'short') = 'null' order by a.code limit 1;
    if v_act is null then
      raise exception '0528 self-assert FAIL: the probe found no mining job of level 1 in reach (static rows)';
    end if;

    -- DARK: the door refuses; a row put there by hand moves no term
    if cmd.captain_land(v_ca, 1) ->> 'error_code' is distinct from 'E_NOT_IN_USE' then
      raise exception '0528 self-assert FAIL: dark, the door does not refuse';
    end if;
    v_t0j := public.land_terms(v_me, v_act);
    select string_agg(to_jsonb(t)::text, ',' order by to_jsonb(t)::text) into v_terms from public.crew_terms(v_fl, now()) t;
    perform public.captain_land_put(v_a, v_pa);
    if public.land_terms(v_me, v_act) is distinct from v_t0j then
      raise exception '0528 self-assert FAIL: dark, a captain with the party moved its terms';
    end if;
    delete from public.captain_seats where player_officer_id = v_a;

    -- LIT: refusals, then she joins from a cabin
    update public.world_config set value = 'true'::jsonb where key = 'captain_works_enabled';
    if public.land_terms(v_me, v_act) is distinct from v_t0j or cmd.captain_land('NOBODY-0528', 1) ->> 'error_code' <> 'E_NOT_SIGNED' or cmd.captain_land(v_ca, 9) ->> 'error_code' <> 'E_NO_SUCH_PARTY' then
      raise exception '0528 self-assert FAIL: lit with no captain the terms moved, or a refusal is missing';
    end if;
    perform public.captain_seat_put(v_a, v_sh, 1);
    update public.fleets set status = 'UNABLE_TO_SAIL' where id = v_fl;
    if cmd.captain_land(v_ca, 1) ->> 'error_code' is distinct from 'E_NOT_IN_PORT' then
      raise exception '0528 self-assert FAIL: a captain whose fleet is not docked went ashore';
    end if;
    update public.fleets set status = 'DOCKED' where id = v_fl;
    v_r := cmd.captain_land(v_ca, 1);
    select string_agg(to_jsonb(t)::text, ',' order by to_jsonb(t)::text) into v_terms1 from public.crew_terms(v_fl, now()) t;
    if (v_r->>'ok')::boolean is not true or (select cs.ship_id is null and cs.seat is null and cs.party_id = v_pa from public.captain_seats cs where cs.player_officer_id = v_a) is not true
       or v_terms1 is distinct from v_terms
       or not exists (select 1 from jsonb_array_elements(world.captains()->'captains') e where e->>'code' = v_ca and (e->>'party')::int = 1 and (e->>'can_change')::boolean and e->'ship' = 'null'::jsonb) then
      raise exception '0528 self-assert FAIL: she did not leave her cabin for the party, or the fleet still counts her: %', v_r;
    end if;
    -- level 1 gives nothing; level 41 gives 10 % off a turn and nothing else
    v_t1 := public.land_terms(v_me, v_act);
    if v_t1 - 'captain' is distinct from v_t0j or v_t1 #>> '{captain,code}' is distinct from v_ca then
      raise exception '0528 self-assert FAIL: a level-1 captain moved the terms: % / %', v_t1, v_t0j;
    end if;
    insert into public.captain_work_xp (player_officer_id, work, xp) select v_a, 'mining', c.xp from public.level_curves c where c.curve = 'long' and c.level = 41;
    v_t1 := public.land_terms(v_me, v_act);
    if (v_t1->>'a')::int <> greatest(1, round((v_t0j->>'a')::int * 0.9))::int or (v_t1->>'trip')::numeric <> (v_t0j->>'trip')::numeric - (v_t0j->>'p')::int * ((v_t0j->>'a')::int - (v_t1->>'a')::int)
       or v_t1 - 'captain' - 'a' - 'trip' - 'over_cap' is distinct from v_t0j - 'a' - 'trip' - 'over_cap' then
      raise exception '0528 self-assert FAIL: a level-41 captain does not shorten a turn by 10 per cent alone: % / %', v_t1, v_t0j;
    end if;
    -- SENT: the party is out, nobody leaves it and nobody joins it; a Collect gives her what it gives the company
    v_at := now();
    perform public.land_send_for(v_me, v_act, v_at);
    if cmd.captain_land(v_ca, null) ->> 'error_code' is distinct from 'E_LAND_OUT' or cmd.captain_land(v_cb, 1) ->> 'error_code' is distinct from 'E_LAND_OUT'
       or public.seat_captain_for(v_me, v_ca, v_sh, null) ->> 'error_code' is distinct from 'E_LAND_OUT' or public.seat_captain_for(v_me, v_ca, null, null) ->> 'error_code' is distinct from 'E_LAND_OUT' then
      raise exception '0528 self-assert FAIL: a captain left, or joined, a party that is out';
    end if;
    select z.xp into v_xp from public.captain_work_xp z where z.player_officer_id = v_a and z.work = 'mining';
    v_r := public.land_collect_for(v_me, v_at + make_interval(secs => (v_t1->>'trip')::double precision + 1));
    if (v_r->>'xp')::int < 1 or (select z.xp from public.captain_work_xp z where z.player_officer_id = v_a and z.work = 'mining') <> v_xp + (v_r->>'xp')::int then
      raise exception '0528 self-assert FAIL: she did not earn what the Collect booked: %', v_r;
    end if;
    -- home again: the second captain takes the party, the first comes ashore; then a cabin clears the party
    update public.land_parties set action = null, terms = null, started_at = null, region_id = null, touched_at = null, booked = 0 where id = v_pa;
    v_r := cmd.captain_land(v_cb, 1);
    if (v_r->>'ok')::boolean is not true or exists (select 1 from public.captain_seats cs where cs.player_officer_id = v_a) then
      raise exception '0528 self-assert FAIL: the second captain did not take the party: %', v_r;
    end if;
    v_r := public.seat_captain_for(v_me, v_cb, v_sh, null);
    if (v_r->>'ok')::boolean is not true or (select cs.party_id from public.captain_seats cs where cs.player_officer_id = v_b) is not null then
      raise exception '0528 self-assert FAIL: a cabin did not clear her party: %', v_r;
    end if;
    v_note := format('job %s: a turn %s s, %s s with her at level 41', v_act, v_t0j->>'a', v_t1->>'a');
    raise exception using errcode = 'ZX528', message = 'PROBE_ROLLBACK_0528';
  exception when sqlstate 'ZX528' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0528 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.auth_uid::text like '00000000-0528-4000-8000-%') then
    raise exception '0528 self-assert FAIL: the probe left something behind';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0528 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0528 self-assert ok: A CAPTAIN GOES ASHORE (dark). Nine hunks once and reversing; three new functions, one door; no other function or knob moved. Probe (rolled back) whole. % ms. %', round(extract(epoch from clock_timestamp() - v_t0) * 1000), v_note;
end $m$;
