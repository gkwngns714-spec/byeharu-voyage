-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0112 — A FIRST CROSSING IS OPEN, AND NO CAPTAIN IS SHUT IN THE SEA SHE IS ALREADY IN
--        A forward fix to 0107 (owner rows 113/117). 0107 is on production and is not edited.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHAT WAS RED, AND WHY IT WAS NOT THE ROSTER ─────────────────────────────────────────────────
-- PR #94's pglite-gate failed two proofs that had been green on every chain before 0107:
--
--     PROOF 1 SETUP FAILED: the fleet did not depart for Tunis on attempt 1
--     PROOF 5 FAILED: 8 of 32 (port, market) pairs offer no profitable first voyage at all
--
-- The hand-over guessed 0105 (761 more merchants drawing the spread out of the markets). MEASURED,
-- 2026-10-13, on the chain applied to 0104 and then to 0105 alone: both proofs PASS at 0105, with
-- the same figures to the digit (median first voyage 19.2 %, all 32 pairs dry-free). The roster is
-- not the cause. 0107 is, and each red names one of its two gates:
--
--   (1) THE LEG GATE REFUSES THE GAME'S OWN FIRST CROSSING. `nav_leg_nm_base` 900 nm is the whole
--       reach of a captain who has never studied navigation, and the sailed distances from the
--       founding frame are: Lisbon → Tunis 1,086 nm (proof 1's Barbary run), Lisbon → Antwerp 1,073,
--       Lisbon → Amsterdam 1,102. DESIGN.md names Lisboa → Amsterdam as THE sea crossing a new
--       player makes ("Sea crossing | Lisboa → Amsterdam | 25 min | A lunch break"), and 0107
--       refused it to every new house — on production, to every live player who has not studied
--       navigation, since 0107 was pushed. 0107's own header said a beginner "may work a coast and
--       the near Atlantic"; the Biscay run to the Low Countries and the Barbary coast ARE the near
--       Atlantic and its inland sea, and 900 shut both.
--
--   (2) THE REGION GATE SHUTS A CAPTAIN INSIDE THE SEA SHE IS ALREADY IN. Proof 5 founds a house at
--       each of the eight greatest harbours; two of them are Busan (Korea, level 5) and Cartagena
--       (the Spanish Main, level 2). With exploration level 1 a house lying AT Busan was refused
--       every harbour of Korea — including the one she is moored in — so she could not trade at all,
--       and the leg gate kept her from sailing anywhere else. 8 pairs = those 2 ports × 4 markets.
--       On production the same shape strands any house that reached a far region before 0107
--       existed, or whose record otherwise outran its derived level: she is IN the region the gate
--       says she has not earned, and the rule had no idea.
--
-- ── WHAT CHANGES ────────────────────────────────────────────────────────────────────────────────
-- (1) `nav_leg_nm_base` 900 → 1,700 nm, which is `sea_scan_radius_nm` — THE QUAY'S OWN HORIZON
--     (0047: the radius `world.trade_routes` searches by default for a trade to offer). Not a figure
--     picked by eye; it is the one number the game already uses for "how far is a voyage worth
--     showing a captain", and it was MEASURED to be the floor, through proof 5 itself:
--
--         nav_leg_nm_base       900     1,200    1,500   >1,700<   2,000    2,500
--         Lisbon → Tunis        shut    open     open     open     open     open
--         far half / near half   —      11.07    12.81    14.30    14.30    14.30   (% of stake)
--                                       /11.93   /13.19   /13.57   /13.57   /13.57
--         BALANCE_DISTANCE_PAYS  —      FAIL     FAIL     PASS     PASS     PASS
--
--     Below the horizon the gate quietly strikes the far half of what the quay offers a beginner,
--     and with it the only reason to leave home waters (proof 5: "there is no reason to sail far").
--     At 1,700 a beginner may make every voyage the quay offers her — 79 routes over the 8 sampled
--     ports, exactly the set offered before 0107 — and from 1,700 up nothing changes, so the
--     horizon is the floor and not merely a value that happens to pass. The ocean is still earned:
--     Lisbon → the Caribbean (~4,000 nm) asks NAVIGATION 3, Lisbon → Nagasaki (~13,000) asks 4.
--     The ladder keeps doubling, so level 5 reaches 27,200 nm and the world stays open at 5. Every
--     reader of the knob (passage_gate, route_requirement, the board) reads it live, so nothing else
--     has to move with it; the self-assert holds the two knobs equal on the day this lands.
--
-- (2) A captain's EXPLORATION, for the gate, is `public.exploration_reach(player)`: the greater of
--     her derived exploration level (0069, unchanged) and the dearest region she has ALREADY made
--     harbour in — a VOYAGE_REPORT naming one of its harbours — or in which one of her fleets lies
--     now. A region she has demonstrably entered cannot be refused as one she has not, and it is
--     derived from the append-only record like every other level here: never stored, never
--     granted, retroactively right. A Lisbon house that has been nowhere reads exactly what 0107 read.
--
--     ONE READING, TWO CALLERS, and they are the same two that read the old one: passage_gate (the
--     refusal) and world.route_board (its `closed`, which 0108 holds to agreeing with the gate on
--     every row). Re-cutting only the gate would have made the board call a lane shut that the gate
--     lets her sail — the two-authorities defect docs/NO_SPAGHETTI.md §1 forbids — so both move, by
--     one hunk each, and the agreement is asserted below on a captain the new rule actually changes.
--
-- ── WHAT THIS SUPERSEDES ────────────────────────────────────────────────────────────────────────
-- `public.passage_gate` (0107) and `world.route_board` (0106, re-cut by 0108/0109/0110), each by one
-- hunk, each proven below to be its pre-image plus only this file's hunk with its ACL unmoved. The
-- `nav_leg_nm_base` row's value and description. Nothing else.
--
-- ── WHAT THIS DELIBERATELY DOES NOT DO ──────────────────────────────────────────────────────────
-- A house already lying beyond her leg reach of home (one that crossed an ocean before 0107) can
-- trade inside the region she is in — (2) — but still needs NAVIGATION to cross back. Grandfathering
-- legs by "the longest passage she has already sailed" would need a second reach figure the board's
-- integer `navigation` cannot express; it is named here as the next question, not slipped in.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- Same ceiling as 0105-0111, for the same reason: the self-assert reads the board over the whole
-- roster, and a hosted Postgres cancels long statements (0110's header carries the 57014 account).
do $guard$ begin perform set_config('statement_timeout', '20min', true); end $guard$;

-- ── 1. THE FIRST CROSSING ──────────────────────────────────────────────────────────────────────
do $$
begin
  -- The value being moved is the one 0107 wrote. If someone has already moved it, this file is not
  -- the place to overwrite their decision silently.
  if public.wc_num('nav_leg_nm_base') <> 900 then
    raise exception '0112: nav_leg_nm_base reads %, not the 900 0107 wrote — refusing to move a knob someone else has set',
      public.wc_num('nav_leg_nm_base');
  end if;
  -- ...and the horizon it is set to is the one measured in the header. If the quay's horizon has
  -- moved, the table above is about a different world and must be re-measured, not trusted.
  if public.wc_num('sea_scan_radius_nm') <> 1700 then
    raise exception '0112: sea_scan_radius_nm reads %, not the 1,700 this file measured against',
      public.wc_num('sea_scan_radius_nm');
  end if;
end $$;

update public.world_config
   set value = to_jsonb(public.wc_num('sea_scan_radius_nm')),
       description =
         '0107 (owner row 113a), re-set by 0112: the longest single leg a captain with NO navigation '
         'may sail, nautical miles. Each NAVIGATION level doubles it — nav_leg_nm_base x '
         '2^(NAVIGATION-1). 0112 set it to sea_scan_radius_nm (1,700), the quay''s own horizon, so a '
         'beginner may make every voyage the quay offers her; 0107''s 900 refused the designed first '
         'crossing (Lisboa -> Amsterdam, 1,102 nm) and struck the far half of a first voyage''s offers.'
 where key = 'nav_leg_nm_base';

-- ── 2. THE ONE READING OF HOW FAR SHE HAS EXPLORED, FOR THE GATE ───────────────────────────────
create or replace function public.exploration_reach(p_player uuid)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0112: the EXPLORATION a region's door is asked against. Her derived level (0069) — or, when it
  -- is higher, the dearest region she has ALREADY entered: a harbour named by one of her voyage
  -- reports, or the harbour one of her fleets lies in now. Derived from the record every time; a
  -- region she is standing in is never one she "has not earned".
  select greatest(
    coalesce((public.player_progress(p_player)->'exploration'->>'level')::int, 1),
    coalesce((
      select max(r.min_exploration_level)
        from public.ports po
        join public.regions r on r.id = po.region_id
       where po.kind = 'HARBOUR'
         and (po.id in (select f.port_id from public.fleets f
                         where f.player_id = p_player and f.port_id is not null)
              or po.code in (select e.payload->>'to' from public.events e
                              where e.player_id = p_player and e.kind = 'VOYAGE_REPORT'
                                and e.payload ? 'to'))), 1))
$$;

comment on function public.exploration_reach(uuid) is
  '0112: THE exploration figure a region''s door is asked against — the greater of the derived '
  'exploration level (public.player_progress, 0069) and the dearest min_exploration_level among the '
  'regions she has already made harbour in (VOYAGE_REPORT) or lies in now. Read by '
  'public.passage_gate and world.route_board, so the refusal and the board''s `closed` cannot '
  'disagree. Server-only.';

revoke all on function public.exploration_reach(uuid) from public, anon, authenticated;

-- ── 3. THE TWO CALLERS, RE-CUT ─────────────────────────────────────────────────────────────────
create temporary table hunks_0112 (fn text not null, n int not null, old text not null, new text not null);
create temporary table defs_before_0112 (fn text primary key, def text not null, acl text not null);

insert into hunks_0112 values
('public.passage_gate(uuid, numeric, uuid)', 1,
$h$      v_level := (public.player_progress(p_player)->'exploration'->>'level')::int;$h$,
$h$      -- 0112: the region she is already in, or has already made harbour in, is never shut to her.
      v_level := public.exploration_reach(p_player);$h$),
('world.route_board()', 1,
$h$  v_exp := coalesce((public.player_progress(v_me)->'exploration'->>'level')::int, 1);$h$,
$h$  v_exp := public.exploration_reach(v_me);   -- 0112: the gate's own reading, so `closed` agrees$h$);

insert into defs_before_0112
select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', ''),
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '')
  from (select distinct fn from hunks_0112) as f(fn);

create or replace function pg_temp.recut_0112(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0112 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0112 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0112: hunk % of % matches the pre-image % time(s), not once', h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0112(fn) from (select distinct fn from hunks_0112) x order by fn;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_auth_a  constant uuid := '00000000-0112-4000-8000-0000000000a1';
  c_auth_b  constant uuid := '00000000-0112-4000-8000-0000000000b2';
  c_auth_c  constant uuid := '00000000-0112-4000-8000-0000000000c3';
  v_fn      text;
  v_def     text;
  v_back    text;
  h         record;
  v_n       int;
  v_base    int;
  v_npc_on  boolean := public.npc_traders_on();
  v_lis     uuid;
  v_far     uuid;     -- a harbour in the far region the probe lies in
  v_far_reg uuid;
  v_car     uuid;
  v_a       uuid;
  v_b       uuid;
  v_c       uuid;
  v_fleet   uuid;
  v_gate    jsonb;
  v_nm      numeric;
  v_need    int;
  v_board   jsonb;
  v_bad     int;
  v_rows    int;
  v_moved   int;
  v_offer   int;
  v_sig_on   text;
  v_sig_free text;
  v_sig_900  text;
  v_rec     record;
begin
  -- (a) EVERY RE-CUT IS ITS PRE-IMAGE PLUS ONLY THIS FILE'S HUNK, ACLs UNMOVED.
  for v_fn in select distinct fn from hunks_0112 loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0112 where fn = v_fn order by n desc loop
      v_n := (length(v_back) - length(replace(v_back, h.new, ''))) / length(h.new);
      if v_n <> 1 then
        raise exception '0112 self-assert FAIL: hunk % of % is in the new body % time(s), not once', h.n, v_fn, v_n;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back <> (select def from defs_before_0112 where fn = v_fn) or v_def = v_back then
      raise exception '0112 self-assert FAIL: % is not its pre-image plus only 0112''s hunk', v_fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0112 where fn = v_fn) then
      raise exception '0112 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
    -- and the old reading is gone from both callers: one authority, not two.
    if position($x$player_progress$x$ in v_def) <> 0 and v_fn = 'public.passage_gate(uuid, numeric, uuid)' then
      raise exception '0112 self-assert FAIL: passage_gate still reads player_progress beside exploration_reach';
    end if;
  end loop;

  -- (b) THE NEW READING IS REACHABLE BY NOBODY; the walls still read zero.
  if has_function_privilege('authenticated', 'public.exploration_reach(uuid)', 'execute')
     or has_function_privilege('anon', 'public.exploration_reach(uuid)', 'execute') then
    raise exception '0112 self-assert FAIL: exploration_reach is reachable by a client';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0112 self-assert FAIL: the grant wall or the read wall';
  end if;

  select id into v_lis from public.ports where code = 'LIS';
  select id into v_car from public.ports where code = 'CAR';
  select count(*) into v_base from public.players;

  begin
    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
    update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';

    -- (c) THE FIRST CROSSINGS ARE OPEN TO A HOUSE THAT HAS DONE NOTHING, and the ocean is not.
    v_a := public.new_house(c_auth_a, 'Casa da Travessia', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_a;
    update public.fleets set port_id = v_lis, status = 'DOCKED' where id = v_fleet;
    perform cmd.assume_identity(c_auth_a);   -- the quay is read as HER, as a player reads it
    if public.exploration_reach(v_a) <> 1 then
      raise exception '0112 self-assert FAIL: a house that has been nowhere reads exploration reach %',
        public.exploration_reach(v_a);
    end if;
    for v_rec in select p.id, p.code, (sr.reaches->>p.code)::numeric as nm
                   from public.ports p, public.sea_reaches sr
                  where sr.port_id = v_lis and p.code in ('AMS', 'TUN', 'ARP', 'FNC', 'CAD') loop
      if v_rec.nm is null then
        raise exception '0112 self-assert FAIL: Lisbon has no sailed figure to %', v_rec.code;
      end if;
      v_gate := public.passage_gate(v_a, v_rec.nm, v_rec.id);
      if v_gate is not null then
        raise exception '0112 self-assert FAIL: Lisbon to % (% nm) is refused a beginner: %', v_rec.code, v_rec.nm, v_gate;
      end if;
      -- and the FLEET's own door agrees, not only the predicate: the one "may she sail?" authority
      if voyage.sail_refusal(v_fleet, v_rec.id, null, v_rec.nm) is not null
         and voyage.sail_refusal(v_fleet, v_rec.id, null, v_rec.nm)->>'code' in ('E_LEG_TOO_FAR', 'E_REGION_CLOSED') then
        raise exception '0112 self-assert FAIL: sail_refusal still gates Lisbon to %: %', v_rec.code,
          voyage.sail_refusal(v_fleet, v_rec.id, null, v_rec.nm);
      end if;
    end loop;
    -- THE KNOB IS THE QUAY'S HORIZON, on the day this lands.
    if public.wc_num('nav_leg_nm_base') <> public.wc_num('sea_scan_radius_nm') then
      raise exception '0112 self-assert FAIL: nav_leg_nm_base % is not the quay''s horizon %',
        public.wc_num('nav_leg_nm_base'), public.wc_num('sea_scan_radius_nm');
    end if;
    -- EVERY VOYAGE THE QUAY OFFERS HER, SHE MAY MAKE: the beginner's default offer at Lisbon is the
    -- same set with the leg gate lifted entirely. Non-vacuous — the offer is asserted non-empty.
    v_rows := jsonb_array_length(coalesce(world.trade_routes(v_lis, v_fleet, null, null)->'routes', '[]'::jsonb));
    v_sig_on := (select md5(coalesce(string_agg(e::text, '|' order by e::text), '')) from jsonb_array_elements(world.trade_routes(v_lis, v_fleet, null, null)->'routes') e);
    update public.world_config set value = to_jsonb(1000000) where key = 'nav_leg_nm_base';
    v_sig_free := (select md5(coalesce(string_agg(e::text, '|' order by e::text), '')) from jsonb_array_elements(world.trade_routes(v_lis, v_fleet, null, null)->'routes') e);
    -- POSITIVE CONTROL: at 0107's 900 the same read offers FEWER, or the comparison above could not
    -- fail (a read that ignored the gate would match itself at any value).
    update public.world_config set value = to_jsonb(900) where key = 'nav_leg_nm_base';
    v_sig_900 := (select md5(coalesce(string_agg(e::text, '|' order by e::text), '')) from jsonb_array_elements(world.trade_routes(v_lis, v_fleet, null, null)->'routes') e);
    update public.world_config set value = to_jsonb(public.wc_num('sea_scan_radius_nm')) where key = 'nav_leg_nm_base';
    if v_rows < 1 or v_sig_on <> v_sig_free then
      raise exception '0112 self-assert FAIL: the quay''s offer to a Lisbon beginner (% route(s)) is not the offer with no leg gate at all',
        v_rows;
    end if;
    if v_sig_900 = v_sig_on then
      raise exception '0112 self-assert FAIL: at 0107''s 900 nm the quay offered the very same routes — the read does not see the gate, so the check above proves nothing';
    end if;
    v_offer := v_rows;
    -- THE LEG GATE STILL BITES, at the new figure: an ocean leg is refused, carrying the horizon.
    v_gate := public.passage_gate(v_a, 4000, null);
    if v_gate is null or v_gate->>'code' <> 'E_LEG_TOO_FAR'
       or (v_gate->'figures'->>'reach_nm')::numeric <> 1700 then
      raise exception '0112 self-assert FAIL: a 4,000 nm leg was not refused at reach 1,700: %', v_gate;
    end if;
    -- THE REGION GATE STILL BITES for a captain who has been nowhere: the Spanish Main is shut.
    v_gate := public.passage_gate(v_a, 1, v_car);
    if v_gate is null or v_gate->>'code' <> 'E_REGION_CLOSED' then
      raise exception '0112 self-assert FAIL: a Lisbon beginner was not refused the Spanish Main: %', v_gate;
    end if;

    -- (d) A CAPTAIN LYING IN A FAR REGION IS NOT SHUT INSIDE IT. The dearest region the world has,
    --     at its greatest harbour; the probe is moved there exactly as proof 5 founds its houses.
    select po.id, po.region_id, r.min_exploration_level into v_far, v_far_reg, v_need
      from public.ports po join public.regions r on r.id = po.region_id
     where po.kind = 'HARBOUR'
       and (select count(*) from public.ports p2
             where p2.region_id = po.region_id and p2.kind = 'HARBOUR') >= 2
     order by r.min_exploration_level desc, po.size_tier desc, po.code limit 1;
    if v_need < 3 then
      raise exception '0112 self-assert FAIL: the dearest region asks only %, so (d) proves nothing', v_need;
    end if;
    v_b := public.new_house(c_auth_b, 'Casa do Mar Longe', 'PRT');
    -- POSITIVE CONTROL FIRST: before she lies there, the far region is shut to her.
    if public.passage_gate(v_b, 1, v_far) is null then
      raise exception '0112 self-assert FAIL: the far region was open to a house that has never been near it';
    end if;
    update public.fleets set port_id = v_far, status = 'DOCKED' where player_id = v_b;
    if public.exploration_reach(v_b) < v_need then
      raise exception '0112 self-assert FAIL: a house lying in a level-% region reads exploration reach %',
        v_need, public.exploration_reach(v_b);
    end if;
    if (public.player_progress(v_b)->'exploration'->>'level')::int >= v_need then
      raise exception '0112 self-assert FAIL: the probe''s DERIVED level already covers the region, so (d) proves nothing';
    end if;
    select count(*), count(*) filter (where public.passage_gate(v_b, 1, po.id) is not null)
      into v_rows, v_bad
      from public.ports po where po.region_id = v_far_reg and po.kind = 'HARBOUR';
    if v_rows < 2 or v_bad <> 0 then
      raise exception '0112 self-assert FAIL: % of % harbour(s) of her own region are shut to a captain lying in it',
        v_bad, v_rows;
    end if;

    -- (e) A REGION SHE HAS MADE HARBOUR IN STAYS OPEN after she leaves it — the record, not her
    --     berth. The probe's voyage report is the shape voyage.settle writes.
    v_c := public.new_house(c_auth_c, 'Casa do Caribe', 'PRT');
    update public.fleets set port_id = v_lis, status = 'DOCKED' where player_id = v_c;
    if public.passage_gate(v_c, 1, v_car) is null then
      raise exception '0112 self-assert FAIL: the Spanish Main was open before the report (no control)';
    end if;
    perform public.emit_event(v_c, 'VOYAGE_REPORT',
      jsonb_build_object('fleet', 'probe', 'from', 'LIS', 'to', 'CAR', 'total_nm', 0, 'lines', '[]'::jsonb));
    if public.passage_gate(v_c, 1, v_car) is not null then
      raise exception '0112 self-assert FAIL: a region she has made harbour in is still shut: %',
        public.passage_gate(v_c, 1, v_car);
    end if;

    -- (f) THE BOARD AGREES WITH THE GATE for the captain the new rule changed — every row. 0108's own
    --     licence for computing `closed` from levels, re-proven on a reading 0108 never saw.
    perform cmd.assume_identity(c_auth_b);
    -- The merchants' lanes are on the board when the FLAG reads on; the board does not need them at
    -- sea. So the flag is set (rolled back below) rather than `npc_traders_switch(true)` being run:
    -- the switch plans and starts all 837 fleets, measured at 554 s on PGlite, to prove nothing this
    -- assertion is about. On production the flag is already on and this write changes nothing.
    update public.world_config set value = 'true'::jsonb where key = 'npc_traders_enabled';
    v_board := world.route_board();
    select count(*),
           count(*) filter (where x.said is distinct from x.gated),
           count(*) filter (where not x.said and x.exp_asked > x.derived)
      into v_rows, v_bad, v_moved
      from (select (r->>'closed')::boolean as said,
                   exists (select 1 from public.standing_route_stops st
                            where st.route_id = (r->>'id')::uuid
                              and public.passage_gate(v_b, st.course_nm, st.port_id) is not null) as gated,
                   coalesce((r->'requires'->>'exploration')::int, 1) as exp_asked,
                   (public.player_progress(v_b)->'exploration'->>'level')::int as derived
              from jsonb_array_elements(v_board->'routes') r) x;
    if v_rows < 10 then
      raise exception '0112 self-assert FAIL: the board served % row(s) to the probe, so agreement means nothing', v_rows;
    end if;
    if v_bad <> 0 then
      raise exception '0112 self-assert FAIL: % of % board row(s) disagree with public.passage_gate about being closed',
        v_bad, v_rows;
    end if;
    if v_moved < 1 then
      raise exception '0112 self-assert FAIL: no lane above her derived level reads open, so the board did not follow the new reading';
    end if;

    raise exception 'ROLLBACK_0112';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0112' then raise; end if;
  end;

  if (select count(*) from public.players) <> v_base or public.npc_traders_on() is distinct from v_npc_on then
    raise exception '0112 self-assert FAIL: the probe did not leave the world as it found it';
  end if;

  raise notice '0112 self-assert ok: A FIRST CROSSING IS OPEN, AND NO CAPTAIN IS SHUT IN. nav_leg_nm_base '
    'is the quay''s horizon (1,700), so a house that has done nothing may sail Lisbon to Amsterdam, Antwerp, '
    'Tunis, Funchal and Cadiz, may make every voyage the quay offers her at Lisbon (% shown, a different offer at 0107''s 900), '
    'and is still refused a 4,000 nm leg and the Spanish Main. public.exploration_reach '
    'is the one reading both callers ask — passage_gate and world.route_board are each their pre-image '
    'plus one hunk, ACL unmoved — and it is reachable by nobody. A captain lying in a level-% region has '
    'all % of its harbours open; a region named by her voyage report stays open after she leaves it; and '
    'the board''s `closed` agrees with the gate on all % row(s) it served her, % of them lanes above her '
    'derived level that now read open.', v_offer, v_need, (select count(*) from public.ports po
                                                  where po.region_id = v_far_reg and po.kind = 'HARBOUR'),
    v_rows, v_moved;
end $$;
