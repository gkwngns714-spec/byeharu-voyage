-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0104 — A HARBOUR KNOWS WHICH MERCHANTS IT CONCERNS, AND WHAT EACH ONE IS DOING THERE
--        Owner row 121 (docs/OWNER_REQUESTS.md, docs/NPC_FLEET_SCALE.md §1 slice E, 2026-10-11):
--        *"By clicking the city, i get to see what trading ships started, resting, ending etc."*
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE ASK, AND WHAT WAS ALREADY THERE ─────────────────────────────────────────────────────────
-- PORT has listed the merchant fleets LYING at a harbour since 0099, and a tap opens the read-only
-- sheet. Two halves of the owner's sentence were missing: WHAT EACH ONE IS DOING there, and the
-- merchants whose loop CALLS at this harbour but who are not in it right now.
--
-- ── NO SECOND STATE COLUMN, AND NO SECOND READING OF ONE ────────────────────────────────────────
-- docs/NPC_FLEET_SCALE.md §2: *"Not a new state column for 'resting'. A merchant resting at home is
-- a route whose hold has not expired at stop 0 — three facts the schema already holds. A fourth
-- copy of her state is how two readings of the same thing come to disagree."* So the word is
-- DERIVED, in ONE function, from facts that already exist:
--
--   npc_fleets.route_id           whose route this is — the world's own record (0097), and the
--                                 authority both of 0099's reads use. NOT `standing_routes.fleet_id`:
--                                 0097's upkeep DETACHES a laid-up route from its fleet, so reading
--                                 the link that way round drops the merchants lying at their quay
--   standing_route_stops.ord      where this harbour sits on her loop (0 is home, 0092)
--   standing_routes.stop_cursor   the stop in play — the one she sits at, or is heading for (0092)
--   standing_routes.hold_until    she may not sail on yet: the pacing hold, and from 0101 the
--                                 fortnight at home (`next_lap_at` is already served from it)
--   standing_routes.paused_reason she cannot sail on at all (0096 'laid_up', 0097's upkeep)
--   fleets.status / fleets.port_id   where she actually is
--   voyages.dest_port_id          where she is actually going, while she is at sea
--
-- Six words, each one fact away from the next (the order below IS the rule, and it is total — every
-- merchant whose loop touches this harbour gets exactly one of them):
--
--   laid_up   she is here and her route is paused: she cannot sail on (docs/WORDS.md's own word)
--   resting   she is here and held — 0101's fortnight at home, or the pace
--   starting  she is here and this harbour is the HEAD of her loop: the lap begins here
--   ending    she is inbound and this harbour is the head of her loop: this lap ends here
--   passing   she is here, or inbound here, mid-loop
--   away      her loop calls here and she is somewhere else on it right now
--
-- ── WHICH READ CARRIES IT: A NEW `world.port_merchants(port)`, NOT `world.sea_traffic` ──────────
-- The two candidates were weighed on the numbers, because that is the only honest way to pick:
--
--   EXTEND `world.sea_traffic()` — REJECTED. It is read on the shell's 3-second beat by every
--   viewer with MAP or PORT up, and it serves EVERY merchant fleet in the world on every call. The
--   roster is about to grow tenfold (docs/NPC_FLEET_SCALE.md: ~76 fleets today, ~760 planned, at
--   which point the read is already ~120 KB a call and slice B must give it a viewport and a cap).
--   Carrying `doing` would mean carrying her ROUTE'S STOPS too — up to eight port codes per fleet,
--   0101 raised the maximum — on every row of every beat, for the sake of one harbour's worth of
--   rows. Worse, `doing` is a question ABOUT A HARBOUR: a traffic row has no harbour to be about,
--   so the key would have to be an array of (port, word) pairs — the whole loop's worth, on every
--   row — which is the same defect wearing a bigger coat. And a capped, viewported traffic read
--   cannot answer the question at all: the merchant who is AWAY (three legs from here, on her way
--   back) is exactly the row a viewport drops, and she is exactly the row the owner asked for.
--
--   A NEW `world.port_merchants(p_port)` — TAKEN. One harbour, read at TAP TIME, exactly as
--   `world.npc_fleet_card` is (docs/NPC_TRADERS.md §7.3). The rows are bounded by the harbour: at
--   the planned ~200 routes over ~238 harbours with 2-8 stops each, a harbour sits on ~4 loops and
--   ~16 merchant fleets sail them, so this is a ~16-row answer asked once when a city is opened —
--   not a 760-row answer asked twenty times a minute. It also REMOVES a reading: PORT no longer
--   needs `world.sea_traffic` at all, so opening a harbour stops pulling the whole world's traffic.
--
-- ── WHAT THIS FILE SUPERSEDES — SLICED, NOT RETYPED (the 0096 method) ───────────────────────────
--   public.client_rpc_entry_points()   gains one row, by hunk substitution on the DEPLOYED body
--                                      (0083's cut, re-cut by 0087/0092/0099). The hunk anchors on
--                                      `from (values` and inserts FIRST, so a row appended at the
--                                      end of the list by another file in this batch cannot move it.
-- Nothing else is re-cut. `world.sea_traffic` is deliberately left exactly as 0099 wrote it: it is
-- docs/NPC_FLEET_SCALE.md slice B's to rewrite, and this file must not be in its way.
--
-- ── THE ONE SEAM, NAMED RATHER THAN TIDIED (docs/NO_SPAGHETTI.md §7) ───────────────────────────
-- A row of `world.port_merchants` carries THE SAME KEY SET as a row of `world.sea_traffic`, plus
-- `doing` and `stops` — deliberately, so the client keeps ONE type (`PortMerchant extends
-- TrafficFleet`) and ONE writer of the line beside a merchant's name (`src/live/merchantLine.ts`),
-- which is the part that could actually drift in words. The jsonb EXPRESSION that builds those
-- shared keys is written twice, as `world.npc_fleet_card`'s `fleet` object already writes a third
-- copy of them (0099): in this chain a read owns its own shape and the DERIVATIONS are the shared
-- authorities (`world.voyage_view`, `public.standing_route_state`, `public.route_earnings`, and now
-- `public.merchant_doing_at`). Collapsing the three onto one row builder would cost a per-row
-- function call inside `world.sea_traffic`, which 0099's own planner self-assert forbids — so it is
-- the job of slice B's rewrite of that read, and this header is the note that says so.
--
-- ── DARK, LIKE EVERY MERCHANT READ ──────────────────────────────────────────────────────────────
-- `public.npc_traders_on()` false → `{enabled: false, merchants: []}`, whatever exists. Granted to
-- `authenticated` and to nobody else, registered in `public.client_rpc_entry_points()`, and it
-- refuses a player's own fleet by the one predicate every merchant read rests on: `players.is_npc`.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 1. THE SLICE TOOL (its own copy, by necessity — tests/duplication.spec.ts) ─────────────────
create temporary table hunks_0104 (fn text not null, n int not null, old text not null, new text not null,
                                   primary key (fn, n));
insert into hunks_0104 values
('public.client_rpc_entry_points()', 1,
$h$    from (values
$h$,
$h$    from (values
      -- 0104 (owner row 121): the harbour's own merchants — which companies this quay concerns and
      -- what each one is doing here. A READ, at tap time, no player id, dark until
      -- npc_traders_switch(true); a player's fleet is never a row. Inserted at the HEAD of the
      -- list so a row appended at its tail by another file cannot move this hunk.
      ('world'::text, 'port_merchants'::text,  'uuid'::text),
$h$);

create temporary table defs_before_0104 as
  select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
         coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
    from (select distinct fn from hunks_0104) as f(fn);

create or replace function pg_temp.recut_0104(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0104 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0104 slice: hunk % of % occurs % time(s), expected exactly 1 — the deployed body is not what this migration was generated against.',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0104('public.client_rpc_entry_points()');

-- ── 2. THE ONE DERIVATION: WHAT IS THIS MERCHANT DOING AT THIS HARBOUR ─────────────────────────
create or replace function public.merchant_doing_at(p_route uuid, p_fleet uuid, p_port uuid,
                                                   p_now timestamptz)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $md$
-- 0104: THE word, derived — never stored (docs/NPC_FLEET_SCALE.md §2). Null when this harbour is
-- not on the route's loop at all, which is the caller's own filter stated twice so the function is
-- total on its own. Server-only: the harbour's read is the only door, exactly as
-- public.standing_route_state (0099) is reached only through the reads that print it.
--
-- THE FLEET IS AN ARGUMENT, NOT `standing_routes.fleet_id`, and that is not a style choice: 0097's
-- upkeep DETACHES a laid-up merchant's route (nine of seventy-six in the shipped roster carry
-- `fleet_id = null`), and `public.npc_fleets.route_id` is the world's record of whose route this is
-- — the authority both of 0099's reads already use. Deriving the fleet from the route here instead
-- dropped exactly the merchants LYING AT THEIR QUAY, which is the first thing the owner asked to
-- see; tests/port.merchants.spec.ts found it on the shipped image.
declare
  sr      public.standing_routes%rowtype;
  f       public.fleets%rowtype;
  v_n     int;
  v_ord   int;   -- where this harbour sits on her loop: the stop IN PLAY if that is this one
  v_cur   int;   -- the stop in play (0092: the one she is at, or heading for)
  v_here  boolean;
  v_bound boolean;
begin
  select * into sr from public.standing_routes where id = p_route;
  if sr.id is null then return null; end if;
  select count(*) into v_n from public.standing_route_stops where route_id = sr.id;
  select min(ord) into v_ord from public.standing_route_stops where route_id = sr.id and port_id = p_port;
  if v_ord is null or v_n = 0 then return null; end if;
  -- A LOOP MAY CALL AT THE SAME HARBOUR TWICE, so "which stop is this harbour" is answered by the
  -- stop IN PLAY when that stop is this harbour, and by the first of them otherwise. Without this
  -- a merchant working a second call at a harbour that is also her home would read 'starting'.
  v_cur := sr.stop_cursor % v_n;
  if exists (select 1 from public.standing_route_stops s
              where s.route_id = sr.id and s.ord = v_cur and s.port_id = p_port) then
    v_ord := v_cur;
  end if;
  select * into f from public.fleets where id = p_fleet;
  v_here  := f.id is not null and f.port_id = p_port;
  v_bound := f.id is not null and f.status = 'SAILING'
             and exists (select 1 from public.voyages v
                          where v.fleet_id = f.id and v.status = 'SAILING' and v.dest_port_id = p_port);
  return case
    -- SHE CANNOT SAIL ON. Checked first and without reading her ord, because a laid-up merchant at
    -- her home quay is not "starting" anything (docs/WORDS.md: a merchant that cannot sail on is
    -- LAID UP), and 0097's upkeep lays one up for six hours at a time.
    when v_here and sr.paused_reason is not null then 'laid_up'
    -- SHE MAY NOT SAIL ON YET. 0101's fortnight at home is a FLOOR on this same hold, so one
    -- reading answers both it and the pace — which is why 0101 made it a floor and not a second
    -- hold. Written as "here and held" rather than "at stop 0 and held" so that a rule which ever
    -- holds her mid-loop still reads as the true thing: she is lying in port, not sailing on.
    when v_here and sr.hold_until > p_now then 'resting'
    when v_here  and v_ord = 0 then 'starting'
    when v_bound and v_ord = 0 then 'ending'
    when v_here or v_bound     then 'passing'
    else 'away' end;
end $md$;
comment on function public.merchant_doing_at(uuid, uuid, uuid, timestamptz) is
  '0104 (owner row 121): THE one derivation of what a merchant is doing at a harbour — laid_up / '
  'resting / starting / ending / passing / away — from the route''s own stops, cursor, hold and '
  'pause and from where the fleet is. The fleet is an argument because 0097 detaches a laid-up '
  'route from it. No state column, and no second reading of one. Server-only.';

-- ── 3. THE READ ────────────────────────────────────────────────────────────────────────────────
create or replace function world.port_merchants(p_port uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $pm$
  -- 0104: WHICH MERCHANTS THIS HARBOUR CONCERNS, AND WHAT EACH ONE IS DOING (owner row 121). Read
  -- at tap time, like world.npc_fleet_card and unlike world.sea_traffic — the header argues the
  -- choice on the numbers. One row per merchant FLEET whose route calls here, even when she is
  -- nowhere near: `away` is a true answer and a capped traffic read could never give it.
  --
  -- The key set is world.sea_traffic's row EXACTLY, plus `doing` and `stops`, so the client keeps
  -- one type and one writer of the line beside her name. An `ord` is deliberately NOT served: the
  -- screen already knows which harbour it is and marks it in `stops` by code, which is one fact
  -- fewer to disagree about.
  select case when not public.npc_traders_on()
    then jsonb_build_object('enabled', false, 'at', now(),
                            'port', (select code from public.ports where id = p_port),
                            'merchants', '[]'::jsonb)
    else jsonb_build_object('enabled', true, 'at', now(),
      'port', (select code from public.ports where id = p_port),
      'merchants', coalesce((
        select jsonb_agg(r.row order by r.rank, r.roster_ord, r.id)
          from (
            select f.id,
                   nf.roster_ord,
                   -- THE ONES WHO ARE HERE FIRST, then the ones coming, then the rest — the order
                   -- is the server's, so every screen lists them the same way.
                   case d.doing when 'laid_up'  then 1
                                when 'resting'  then 2
                                when 'starting' then 3
                                when 'ending'   then 4
                                when 'passing'  then 5
                                else 6 end as rank,
                   jsonb_build_object(
                     'id', f.id, 'company', p.company_name, 'nation_code', n.code, 'ink', h.ink,
                     'name', f.name, 'status', f.status,
                     'ships', (select count(*) from public.ships s where s.fleet_id = f.id),
                     -- WHAT THOSE HULLS ARE (0102, owner row 120) — `ship_classes.code` per hull,
                     -- flagship first then the order she was built in. Carried because this row IS
                     -- a traffic row plus two keys, and a shared key that only one of the two reads
                     -- serves is the drift this file's header promises not to start; the key-set
                     -- self-asserts on both sides are what keep that promise checkable.
                     'hulls', (select coalesce(jsonb_agg(sc.code order by s.is_flagship desc, s.created_at, s.id), '[]'::jsonb)
                                 from public.ships s join public.ship_classes sc on sc.id = s.class_id
                                where s.fleet_id = f.id),
                     'port', po.code,
                     'roadstead', case when f.port_id is not null
                                       then jsonb_build_array(rs.roadstead_lat, rs.roadstead_lon) end,
                     'anchor', case when f.lat is not null then jsonb_build_array(f.lat, f.lon) end,
                     'voyage', (select world.voyage_view(v.id, false) from public.voyages v
                                 where v.fleet_id = f.id and v.status = 'SAILING'),
                     'next_lap_at', case when sr.hold_until > now() then sr.hold_until end,
                     'doing', d.doing,
                     -- HER LOOP, as codes in sailing order. The codes alone, never the baked
                     -- courses: those are hundreds of points a leg and they are served on the
                     -- CARD, for the one fleet a player tapped (0099).
                     'stops', (select coalesce(jsonb_agg(po2.code order by s2.ord), '[]'::jsonb)
                                 from public.standing_route_stops s2
                                 join public.ports po2 on po2.id = s2.port_id
                                where s2.route_id = sr.id)) as row
              from public.fleets f
              -- THE ONE PREDICATE. A player's fleet is never a row of a merchant read.
              join public.players p on p.id = f.player_id and p.is_npc
              join public.npc_houses h on h.player_id = p.id
              -- WHOSE ROUTE IS THIS — `npc_fleets.route_id`, the world's own record and the
              -- authority both of 0099's reads use, NOT `standing_routes.fleet_id`: 0097's upkeep
              -- detaches a laid-up route from its fleet, and reading it the other way round drops
              -- exactly the merchants lying at their quay.
              join public.npc_fleets nf on nf.fleet_id = f.id
              join public.standing_routes sr on sr.id = nf.route_id
              left join public.nations n on n.id = p.nation_id
              left join public.ports po on po.id = f.port_id
              left join public.sea_reaches rs on rs.port_id = f.port_id
              cross join lateral (select public.merchant_doing_at(sr.id, f.id, p_port, now()) as doing) d
             where exists (select 1 from public.standing_route_stops st
                            where st.route_id = sr.id and st.port_id = p_port)
          ) r), '[]'::jsonb)) end
$pm$;
comment on function world.port_merchants(uuid) is
  '0104 (owner row 121): one harbour''s merchants — every merchant FLEET whose route calls here, '
  'with what she is doing (public.merchant_doing_at) and her loop. Read at a tap, not on the beat: '
  'world.sea_traffic serves the whole world every 3 s and must not grow. Dark until '
  'npc_traders_switch(true); authenticated-only; a player''s fleet is never a row.';

-- ── 4. GRANTS ──────────────────────────────────────────────────────────────────────────────────
revoke all on function public.merchant_doing_at(uuid, uuid, uuid, timestamptz) from public, anon, authenticated;
revoke all on function world.port_merchants(uuid)                        from public, anon;
grant execute on function world.port_merchants(uuid)                     to authenticated;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.okeys_0104(p jsonb)
returns text[]
language sql
immutable
as $$
  -- one object's own keys, in byte order (collation-proof)
  select coalesce(array_agg(k order by k collate "C"), '{}') from jsonb_object_keys(p) k
$$;

create or replace function pg_temp.keys_0104(p jsonb)
returns text[]
language plpgsql
as $$
-- every object key anywhere in the tree
declare
  v_out text[] := '{}';
  v_k   text;
  v_v   jsonb;
begin
  if jsonb_typeof(p) = 'object' then
    for v_k, v_v in select key, value from jsonb_each(p) loop
      v_out := v_out || v_k || pg_temp.keys_0104(v_v);
    end loop;
  elsif jsonb_typeof(p) = 'array' then
    for v_v in select value from jsonb_array_elements(p) loop
      v_out := v_out || pg_temp.keys_0104(v_v);
    end loop;
  end if;
  return v_out;
end $$;

do $$
declare
  c_auth   constant uuid := '00000000-0104-4000-8000-0000000000e1';
  v_fn     text;
  v_def    text;
  v_back   text;
  h        record;
  v_n      int;
  v_lis    uuid;
  v_fnc    uuid;
  v_set    uuid;
  v_m      uuid;
  v_m2     uuid;
  v_m3     uuid;
  v_fleet  uuid;
  v_fleet2 uuid;
  v_fleet3 uuid;
  v_route  uuid;
  v_route2 uuid;
  v_route3 uuid;
  v_i1     int;
  v_i2     int;
  v_i3     int;
  v_order  text[];
  v_leg    jsonb;
  v_back_c jsonb;
  v_out    jsonb;
  v_row    jsonb;
  v_keys   text[];
  v_tkeys  text[];
  v_bad    text[];
  v_words  text[];
  v_player uuid;
  v_pfleet uuid;
  v_proute uuid;
  v_res    jsonb;
  v_base   int;
  v_rows   int;
  v_seen   int;
  v_expect int;
begin
  -- (a) PARITY BY REVERSE SUBSTITUTION, and the ACL did not move.
  for v_fn in select distinct fn from hunks_0104 loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0104 where fn = v_fn order by n desc loop
      v_n := (length(v_back) - length(replace(v_back, h.new, ''))) / length(h.new);
      if v_n <> 1 then
        raise exception '0104 self-assert FAIL: hunk % of % is in the new body % time(s), not once', h.n, v_fn, v_n;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back <> (select def from defs_before_0104 where fn = v_fn) or v_def = v_back then
      raise exception '0104 self-assert FAIL: % is not its pre-image plus only 0104''s hunk', v_fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0104 where fn = v_fn) then
      raise exception '0104 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
  end loop;

  -- (b) THE REGISTRY AND THE GRANTS — one door, authenticated-only, and the derivation is nobody's.
  if not has_function_privilege('authenticated', 'world.port_merchants(uuid)', 'execute')
     or has_function_privilege('anon', 'world.port_merchants(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.merchant_doing_at(uuid, uuid, uuid, timestamptz)', 'execute')
     or has_function_privilege('anon', 'public.merchant_doing_at(uuid, uuid, uuid, timestamptz)', 'execute') then
    raise exception '0104 self-assert FAIL: the read is not exactly authenticated-only, or the derivation is reachable';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e
       where e.function_name = 'port_merchants' and e.fn is not null) <> 1
     or exists (select 1 from public.client_rpc_entry_points() e
                 where e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute'))
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0 then
    raise exception '0104 self-assert FAIL: the registry, the grant wall or the writer wall';
  end if;

  select id into v_lis from public.ports where code = 'LIS';
  select id into v_fnc from public.ports where code = 'FNC';
  select id into v_set from public.ports where code = 'SET';
  if v_lis is null or v_fnc is null or v_set is null then
    raise exception '0104 self-assert FAIL: the probe harbours LIS/FNC/SET are not all in this world';
  end if;

  -- (c) DARK: the switch ships off, and the read says nothing even though 0098 founded 26 companies.
  if public.npc_traders_on() then
    raise exception '0104 self-assert FAIL: the merchants are already switched on in the chain';
  end if;
  if (select count(*) from public.npc_fleets) = 0 then
    raise exception '0104 self-assert FAIL: no merchant fleet exists, so a dark read would be vacuous';
  end if;
  v_out := world.port_merchants(v_lis);
  if (v_out->>'enabled')::boolean or jsonb_array_length(v_out->'merchants') <> 0
     or v_out->>'port' <> 'LIS' then
    raise exception '0104 self-assert FAIL: the harbour served merchants while dark: %', left(v_out::text, 300);
  end if;
  if pg_temp.okeys_0104(v_out) <> array['at', 'enabled', 'merchants', 'port'] then
    raise exception '0104 self-assert FAIL: dark top-level keys are %', pg_temp.okeys_0104(v_out);
  end if;

  -- (d) THE SIX WORDS, ON PROBE MERCHANTS WHOSE LOOP IS KNOWN, each driven by ONE changed fact,
  --     over the REAL roster put to sea by the one switch, and a PLAYER with the same loop as the
  --     control. Rolled back.
  select count(*) into v_base from public.players;
  begin
    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
    update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';
    -- THE ONE SWITCH, not a hand-set flag: it plans and starts the whole roster through the one
    -- executor (0097), so the harbour below answers over merchants that are really sailing rather
    -- than over a probe alone.
    perform public.npc_traders_switch(true);
    if not public.npc_traders_on() then
      raise exception '0104 self-assert FAIL: the probe could not switch the merchants on';
    end if;

    select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon),
                             jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
      into v_leg from public.sea_reaches a, public.sea_reaches b
     where a.port_id = v_lis and b.port_id = v_fnc;
    v_back_c := jsonb_build_array(v_leg->1, v_leg->0);

    -- A company whose loop is LIS (stop 0, her home) then FNC (stop 1), and nothing else.
    v_m := public.npc_found(jsonb_build_object(
      'company', 'Casa da Vista', 'alt_company', 'Casa do Mirante', 'nation', 'PRT', 'ink', 'prt',
      'master', 'Capitao Olheiro',
      'blurb', 'A probe company founded so a harbour can be asked what she is doing.',
      'capital', 40000, 'patience', 0.20, 'wares', '[]'::jsonb, 'roster_ord', 9104,
      'skills', jsonb_build_object('SEAMANSHIP', 1),
      'fleets', jsonb_build_array(jsonb_build_object(
        'name', 'Vigia', 'roster_ord', 9104, 'days', 12,
        'ships', jsonb_build_array(jsonb_build_object('class', 'carlat', 'name', 'Vigia')),
        'officers', '[]'::jsonb,
        'stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                   jsonb_build_object('port', 'FNC', 'course', v_back_c)),
        'alt_stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                       jsonb_build_object('port', 'FNC', 'course', v_back_c))))));
    select fleet_id, route_id into v_fleet, v_route from public.npc_fleets where player_id = v_m;
    if v_fleet is null or v_route is null then
      raise exception '0104 self-assert FAIL: the probe merchant was founded without a fleet and a route';
    end if;

    -- A SECOND company on the SAME loop, so the harbour's own ORDER can be read back: two rows that
    -- differ only in what they are doing must come back in the server's rank order.
    v_m2 := public.npc_found(jsonb_build_object(
      'company', 'Casa da Espera', 'alt_company', 'Casa do Adiamento', 'nation', 'PRT', 'ink', 'prt',
      'master', 'Capitao Paciente',
      'blurb', 'A second probe company, founded to be somewhere else while the first one sails.',
      'capital', 40000, 'patience', 0.20, 'wares', '[]'::jsonb, 'roster_ord', 9105,
      'skills', jsonb_build_object('SEAMANSHIP', 1),
      'fleets', jsonb_build_array(jsonb_build_object(
        'name', 'Espera', 'roster_ord', 9105, 'days', 12,
        'ships', jsonb_build_array(jsonb_build_object('class', 'carlat', 'name', 'Espera')),
        'officers', '[]'::jsonb,
        'stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                   jsonb_build_object('port', 'FNC', 'course', v_back_c)),
        'alt_stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                       jsonb_build_object('port', 'FNC', 'course', v_back_c))))));
    select fleet_id, route_id into v_fleet2, v_route2 from public.npc_fleets where player_id = v_m2;
    if v_fleet2 is null or v_route2 is null then
      raise exception '0104 self-assert FAIL: the second probe merchant was founded without a fleet and a route';
    end if;
    -- She lies at the SECOND call of the loop and may sail on: from LIS she is AWAY, and nothing
    -- below moves her again.
    update public.fleets set port_id = v_fnc, status = 'DOCKED', lat = null, lon = null where id = v_fleet2;
    update public.standing_routes set fleet_id = v_fleet2, paused_reason = null, hold_until = null,
                                      stop_cursor = 1, lap_id = null
     where id = v_route2;
    if public.merchant_doing_at(v_route2, v_fleet2, v_lis, now()) <> 'away' then
      raise exception '0104 self-assert FAIL: the second probe reads "%" at LIS and not "away"',
        public.merchant_doing_at(v_route2, v_fleet2, v_lis, now());
    end if;

    -- A THIRD company on the same loop, LAID UP at LIS and left that way, so the harbour's order is
    -- read back over THREE of the six ranks rather than two. Without her the rank of 'laid_up' is
    -- never observed, and a wrong one would pass unseen — which is what the positive control for
    -- the ordering found when it was first run (the `laid_up => 9` variant went green).
    v_m3 := public.npc_found(jsonb_build_object(
      'company', 'Casa do Repouso', 'alt_company', 'Casa do Sossego', 'nation', 'PRT', 'ink', 'prt',
      'master', 'Capitao Parado',
      'blurb', 'A third probe company, founded to lie at her quay unable to sail on.',
      'capital', 40000, 'patience', 0.20, 'wares', '[]'::jsonb, 'roster_ord', 9106,
      'skills', jsonb_build_object('SEAMANSHIP', 1),
      'fleets', jsonb_build_array(jsonb_build_object(
        'name', 'Repouso', 'roster_ord', 9106, 'days', 12,
        'ships', jsonb_build_array(jsonb_build_object('class', 'carlat', 'name', 'Repouso')),
        'officers', '[]'::jsonb,
        'stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                   jsonb_build_object('port', 'FNC', 'course', v_back_c)),
        'alt_stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                       jsonb_build_object('port', 'FNC', 'course', v_back_c))))));
    select fleet_id, route_id into v_fleet3, v_route3 from public.npc_fleets where player_id = v_m3;
    if v_fleet3 is null or v_route3 is null then
      raise exception '0104 self-assert FAIL: the third probe merchant was founded without a fleet and a route';
    end if;
    -- AND HER ROUTE IS DETACHED FROM HER FLEET, which is how 0097's upkeep leaves a laid-up
    -- merchant (nine of the shipped seventy-six carry `fleet_id = null`). `npc_fleets.route_id`
    -- still says whose route it is, and the harbour must still name her: reading the link the other
    -- way round dropped every merchant lying at her quay, and this is the control for it.
    update public.fleets set port_id = v_lis, status = 'DOCKED', lat = null, lon = null where id = v_fleet3;
    update public.standing_routes set fleet_id = null, paused_reason = 'laid_up', hold_until = null,
                                      stop_cursor = 0, lap_id = null
     where id = v_route3;
    if public.merchant_doing_at(v_route3, v_fleet3, v_lis, now()) <> 'laid_up' then
      raise exception '0104 self-assert FAIL: the third probe reads "%" at LIS and not "laid_up"',
        public.merchant_doing_at(v_route3, v_fleet3, v_lis, now());
    end if;

    -- ── SHE IS HERE, AT THE HEAD OF HER LOOP, FREE TO SAIL ON ──────────────────────────────────
    update public.fleets set port_id = v_lis, status = 'DOCKED', lat = null, lon = null where id = v_fleet;
    update public.standing_routes set fleet_id = v_fleet, paused_reason = null, hold_until = null,
                                      stop_cursor = 0, lap_id = null
     where id = v_route;
    if public.merchant_doing_at(v_route, v_fleet, v_lis, now()) <> 'starting' then
      raise exception '0104 self-assert FAIL: at the head of her loop, free to sail, she reads "%" and not "starting"',
        public.merchant_doing_at(v_route, v_fleet, v_lis, now());
    end if;
    -- …and the SAME harbour, from her SECOND stop's point of view, is not the head of anything.
    if public.merchant_doing_at(v_route, v_fleet, v_fnc, now()) <> 'away' then
      raise exception '0104 self-assert FAIL: docked at LIS, her FNC call reads "%" and not "away"',
        public.merchant_doing_at(v_route, v_fleet, v_fnc, now());
    end if;

    -- ── THE POSITIVE CONTROL ON 0101'S FORTNIGHT: the ONLY fact changed is the hold ────────────
    update public.standing_routes set hold_until = now() + interval '10 minutes' where id = v_route;
    if public.merchant_doing_at(v_route, v_fleet, v_lis, now()) <> 'resting' then
      raise exception '0104 self-assert FAIL: held at home for ten minutes she reads "%" and not "resting"',
        public.merchant_doing_at(v_route, v_fleet, v_lis, now());
    end if;
    -- …AND THE HARBOUR'S READ SAYS THE SAME THING, with the hold as the only fact that changed:
    -- the word on the wire is the derivation's and not a second copy of it.
    if (select x->>'doing' from jsonb_array_elements(world.port_merchants(v_lis)->'merchants') x
         where (x->>'id')::uuid = v_fleet) <> 'resting' then
      raise exception '0104 self-assert FAIL: the derivation says resting and the harbour serves "%"',
        (select x->>'doing' from jsonb_array_elements(world.port_merchants(v_lis)->'merchants') x
          where (x->>'id')::uuid = v_fleet);
    end if;
    -- …and her `next_lap_at` is the hold, which is the instant the screen prints.
    if (select x->>'next_lap_at' from jsonb_array_elements(world.port_merchants(v_lis)->'merchants') x
         where (x->>'id')::uuid = v_fleet) is null then
      raise exception '0104 self-assert FAIL: a resting merchant was served no next_lap_at';
    end if;
    -- and a hold that has RUN OUT is no hold at all: the same row, the same instant, one sign apart
    update public.standing_routes set hold_until = now() - interval '1 second' where id = v_route;
    if public.merchant_doing_at(v_route, v_fleet, v_lis, now()) <> 'starting' then
      raise exception '0104 self-assert FAIL: a hold a second in the past still reads "%"',
        public.merchant_doing_at(v_route, v_fleet, v_lis, now());
    end if;

    -- ── SHE CANNOT SAIL ON AT ALL ─────────────────────────────────────────────────────────────
    update public.standing_routes set hold_until = null, paused_reason = 'laid_up' where id = v_route;
    if public.merchant_doing_at(v_route, v_fleet, v_lis, now()) <> 'laid_up' then
      raise exception '0104 self-assert FAIL: a paused merchant at her home quay reads "%" and not "laid_up"',
        public.merchant_doing_at(v_route, v_fleet, v_lis, now());
    end if;
    -- a pause outranks a hold, because "cannot" outranks "not yet"
    update public.standing_routes set hold_until = now() + interval '10 minutes' where id = v_route;
    if public.merchant_doing_at(v_route, v_fleet, v_lis, now()) <> 'laid_up' then
      raise exception '0104 self-assert FAIL: paused AND held she reads "%" and not "laid_up"',
        public.merchant_doing_at(v_route, v_fleet, v_lis, now());
    end if;
    update public.standing_routes set hold_until = null, paused_reason = null where id = v_route;

    -- ── SHE IS MID-LOOP, LYING AT THE SECOND CALL ─────────────────────────────────────────────
    update public.fleets set port_id = v_fnc, status = 'DOCKED' where id = v_fleet;
    update public.standing_routes set stop_cursor = 1 where id = v_route;
    if public.merchant_doing_at(v_route, v_fleet, v_fnc, now()) <> 'passing' then
      raise exception '0104 self-assert FAIL: lying at her second call she reads "%" and not "passing"',
        public.merchant_doing_at(v_route, v_fleet, v_fnc, now());
    end if;
    if public.merchant_doing_at(v_route, v_fleet, v_lis, now()) <> 'away' then
      raise exception '0104 self-assert FAIL: lying at FNC, her LIS call reads "%" and not "away"',
        public.merchant_doing_at(v_route, v_fleet, v_lis, now());
    end if;

    -- ── SHE IS AT SEA, INBOUND. Where she is BOUND decides the word, not where she set out. ───
    update public.fleets set port_id = null, status = 'SAILING' where id = v_fleet;
    insert into public.voyages (fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta,
                                status, origin_port_id, dest_port_id)
    values (v_fleet, v_m, jsonb_build_array(jsonb_build_object('a', v_leg->1, 'b', v_leg->0, 'nm', 500)),
            500, jsonb_build_array(5), now() - interval '1 minute', now() + interval '10 minutes',
            'SAILING', v_fnc, v_lis);
    update public.standing_routes set stop_cursor = 0 where id = v_route;
    if public.merchant_doing_at(v_route, v_fleet, v_lis, now()) <> 'ending' then
      raise exception '0104 self-assert FAIL: inbound to the head of her loop she reads "%" and not "ending"',
        public.merchant_doing_at(v_route, v_fleet, v_lis, now());
    end if;
    if public.merchant_doing_at(v_route, v_fleet, v_fnc, now()) <> 'away' then
      raise exception '0104 self-assert FAIL: inbound to LIS, her FNC call reads "%" and not "away"',
        public.merchant_doing_at(v_route, v_fleet, v_fnc, now());
    end if;
    -- THE SAME VOYAGE, TURNED AROUND: bound mid-loop is 'passing', and LIS becomes 'away'.
    update public.voyages set dest_port_id = v_fnc, origin_port_id = v_lis
     where fleet_id = v_fleet and status = 'SAILING';
    update public.standing_routes set stop_cursor = 1 where id = v_route;
    if public.merchant_doing_at(v_route, v_fleet, v_fnc, now()) <> 'passing'
       or public.merchant_doing_at(v_route, v_fleet, v_lis, now()) <> 'away' then
      raise exception '0104 self-assert FAIL: bound for her second call she reads % at FNC and % at LIS',
        public.merchant_doing_at(v_route, v_fleet, v_fnc, now()), public.merchant_doing_at(v_route, v_fleet, v_lis, now());
    end if;
    -- A HARBOUR SHE NEVER CALLS AT GETS NO WORD AT ALL (the function is total on its own).
    if public.merchant_doing_at(v_route, v_fleet, v_set, now()) is not null then
      raise exception '0104 self-assert FAIL: a harbour off her loop got the word "%"',
        public.merchant_doing_at(v_route, v_fleet, v_set, now());
    end if;

    -- ── THE READ ITSELF: she is a row of her own harbour, and of no harbour off her loop ──────
    update public.fleets set port_id = v_lis, status = 'DOCKED' where id = v_fleet;
    update public.voyages set status = 'ARRIVED' where fleet_id = v_fleet and status = 'SAILING';
    update public.standing_routes set stop_cursor = 0 where id = v_route;

    v_out := world.port_merchants(v_lis);
    v_rows := jsonb_array_length(v_out->'merchants');
    select count(*) into v_expect
      from public.fleets f
      join public.players p on p.id = f.player_id and p.is_npc
      join public.npc_fleets nf on nf.fleet_id = f.id
      join public.standing_routes sr on sr.id = nf.route_id
     where exists (select 1 from public.standing_route_stops st
                    where st.route_id = sr.id and st.port_id = v_lis);
    if not (v_out->>'enabled')::boolean or v_rows <> v_expect or v_rows = 0 then
      raise exception '0104 self-assert FAIL: LIS served % row(s) for % merchant route(s) that call there',
        v_rows, v_expect;
    end if;
    if not exists (select 1 from jsonb_array_elements(v_out->'merchants') x where (x->>'id')::uuid = v_fleet) then
      raise exception '0104 self-assert FAIL: the probe merchant is not a row of her own home harbour';
    end if;
    -- EVERY row is a merchant's, and every row's loop really calls here.
    if exists (select 1 from jsonb_array_elements(v_out->'merchants') x
                where not exists (select 1 from public.fleets f
                                    join public.players p on p.id = f.player_id and p.is_npc
                                   where f.id = (x->>'id')::uuid))
       or exists (select 1 from jsonb_array_elements(v_out->'merchants') x
                   where not (x->'stops' ? 'LIS')) then
      raise exception '0104 self-assert FAIL: a row is not a merchant''s, or its loop does not call at LIS';
    end if;
    -- …and every row carries one of the six words, with the probe's own being the one just planted.
    v_words := array(select distinct x->>'doing' from jsonb_array_elements(v_out->'merchants') x order by 1);
    if cardinality(v_words) < 3
       or exists (select 1 from unnest(v_words) w
                   where w is null or w not in ('laid_up', 'resting', 'starting', 'ending', 'passing', 'away')) then
      raise exception '0104 self-assert FAIL: the harbour served the word(s) % — fewer than three distinct, or one that is not a word',
        v_words;
    end if;
    select x into v_row from jsonb_array_elements(v_out->'merchants') x where (x->>'id')::uuid = v_fleet;
    if v_row->>'doing' <> 'starting' then
      raise exception '0104 self-assert FAIL: the read says the probe is "%" where the derivation says "starting"',
        v_row->>'doing';
    end if;
    -- HER LOOP IS SERVED IN SAILING ORDER, not in some order. The probe's loop is LIS then FNC and
    -- the screen prints it as it comes, so the array itself is the assertion (a positive control
    -- that aggregated the stops by descending `ord` went green until this line existed).
    if v_row->'stops' is distinct from jsonb_build_array('LIS', 'FNC') then
      raise exception '0104 self-assert FAIL: the probe''s loop was served as % and not ["LIS", "FNC"]',
        v_row->'stops';
    end if;
    -- THE ROW'S KEY SET IS THE CONTRACT: world.sea_traffic's row exactly, plus doing and stops.
    v_keys := pg_temp.okeys_0104(v_row);
    if v_keys <> array['anchor', 'company', 'doing', 'hulls', 'id', 'ink', 'name', 'nation_code',
                       'next_lap_at', 'port', 'roadstead', 'ships', 'status', 'stops', 'voyage'] then
      raise exception '0104 self-assert FAIL: a merchant row''s keys are %', v_keys;
    end if;
    -- AND IT REALLY IS world.sea_traffic'S ROW PLUS TWO KEYS, read off that read rather than
    -- claimed in a comment: the whole world's traffic is asked for, the probe's row found in it,
    -- and the two key sets compared with `doing` and `stops` struck out. A key added to one of the
    -- two reads and not the other is caught here, on the day it is added.
    v_tkeys := pg_temp.okeys_0104((select x from jsonb_array_elements(world.sea_traffic(null)->'fleets') x
                                    where (x->>'id')::uuid = v_fleet));
    if cardinality(v_tkeys) = 0 or pg_temp.okeys_0104(v_row - 'doing' - 'stops') is distinct from v_tkeys then
      raise exception '0104 self-assert FAIL: the harbour''s row is not sea_traffic''s row plus doing and stops: % vs %',
        pg_temp.okeys_0104(v_row - 'doing' - 'stops'), v_tkeys;
    end if;
    if pg_temp.okeys_0104(v_out) <> array['at', 'enabled', 'merchants', 'port'] then
      raise exception '0104 self-assert FAIL: the read''s top-level keys are %', pg_temp.okeys_0104(v_out);
    end if;
    -- THE ORDER IS THE SERVER'S: the ones here before the ones coming before the rest. Read back as
    -- a rank per row and required to be non-decreasing down the list — and the two probes, which
    -- differ in NOTHING but what they are doing, are the pair that makes it non-vacuous.
    if exists (select 1 from (
                 select b.rk, lag(b.rk) over (order by b.i) as prev from (
                   select row_number() over () as i,
                          case x->>'doing' when 'laid_up'  then 1 when 'resting' then 2
                                           when 'starting' then 3 when 'ending'  then 4
                                           when 'passing'  then 5 else 6 end as rk
                     from jsonb_array_elements(v_out->'merchants') x) b) c
                where c.prev is not null and c.rk < c.prev) then
      raise exception '0104 self-assert FAIL: the harbour''s rows are not in the server''s order: %',
        (select jsonb_agg(x->>'doing') from jsonb_array_elements(v_out->'merchants') x);
    end if;
    -- THE THREE PROBES, which differ in NOTHING but what they are doing, come back in the stated
    -- order: laid up at the quay, then starting out, then away on her loop.
    select min(y.i) filter (where y.id = v_fleet3),
           min(y.i) filter (where y.id = v_fleet),
           min(y.i) filter (where y.id = v_fleet2)
      into v_i1, v_i2, v_i3
      from (select row_number() over () as i, (x->>'id')::uuid as id
              from jsonb_array_elements(v_out->'merchants') x) y;
    if v_i1 is null or v_i2 is null or v_i3 is null then
      raise exception '0104 self-assert FAIL: the three probes are not all rows of LIS (% / % / %)',
        v_i1, v_i2, v_i3;
    end if;
    v_order := array(select x->>'doing' from jsonb_array_elements(v_out->'merchants') x);
    if not (v_i1 < v_i2 and v_i2 < v_i3) then
      raise exception '0104 self-assert FAIL: LAID UP / STARTING / AWAY came back at positions %, %, % of %',
        v_i1, v_i2, v_i3, v_order;
    end if;
    v_bad := array(select k from unnest(pg_temp.keys_0104(v_out)) k
                    where k in ('queue', 'orders', 'cargo', 'cargo_basis', 'version', 'reserve', 'ducats',
                                'fortune', 'ledger', 'provision', 'endurance_days', 'voyage_id'));
    if cardinality(v_bad) > 0 then
      raise exception '0104 self-assert FAIL: the harbour serves forbidden key(s) %', v_bad;
    end if;
    -- A HARBOUR OFF HER LOOP DOES NOT SERVE HER, however many merchants of its own it has.
    v_out := world.port_merchants(v_set);
    if exists (select 1 from jsonb_array_elements(v_out->'merchants') x where (x->>'id')::uuid = v_fleet) then
      raise exception '0104 self-assert FAIL: a harbour off her loop served the probe merchant';
    end if;

    -- ── THE CONTROL: A PLAYER'S OWN ROUTE, THE SAME TWO HARBOURS, IS NEVER A ROW ──────────────
    -- WHAT THIS CONTROL PINS, EXACTLY. It asserts the PROPERTY (a player's fleet is not a row and
    -- does not change the count), not one line of SQL: the read has TWO independent walls between a
    -- player and this answer — the stated `players.is_npc` predicate and the inner join to
    -- `public.npc_houses`, which only a merchant company has a row in. Dropping either one alone
    -- still serves nothing of hers, which the positive control confirmed by going GREEN with the
    -- predicate removed; it is the `v_rows = v_expect` equality above, computed independently from
    -- `is_npc`, that goes red when both walls are gone. Defence in depth, said out loud rather than
    -- mistaken for a one-line assert.
    perform cmd.assume_identity(c_auth);
    v_res := cmd.found_house('Casa da Vigia', 'PRT');
    v_player := (v_res->>'player_id')::uuid;
    if v_player is null then
      raise exception '0104 self-assert FAIL: the control player was not founded: %', left(v_res::text, 200);
    end if;
    select id into v_pfleet from public.fleets where player_id = v_player;
    update public.fleets set port_id = v_lis, status = 'DOCKED' where id = v_pfleet;
    v_res := cmd.standing_route_save(null, 'Vigia', jsonb_build_array(
               jsonb_build_object('port', 'LIS', 'course', v_leg),
               jsonb_build_object('port', 'FNC', 'course', v_back_c)), 0, 20);
    -- her ONLY route, so this is one row by construction
    select id into v_proute from public.standing_routes where player_id = v_player;
    if v_proute is null then
      raise exception '0104 self-assert FAIL: the control player got no route (%), so the control is vacuous',
        left(v_res::text, 200);
    end if;
    update public.standing_routes set fleet_id = v_pfleet, paused_reason = null, hold_until = null,
                                      stop_cursor = 0, lap_id = null
     where id = v_proute;
    -- her route really does call at LIS — the control is live, not vacuous…
    if not exists (select 1 from public.standing_route_stops st
                    where st.route_id = v_proute and st.port_id = v_lis) then
      raise exception '0104 self-assert FAIL: the control route does not call at LIS';
    end if;
    -- …and the derivation would have a word for her, which the READ must still refuse to serve.
    if public.merchant_doing_at(v_proute, v_pfleet, v_lis, now()) is null then
      raise exception '0104 self-assert FAIL: the control route has no derived word, so the refusal below is vacuous';
    end if;
    v_out := world.port_merchants(v_lis);
    select count(*) into v_seen from jsonb_array_elements(v_out->'merchants') x
     where (x->>'id')::uuid = v_pfleet;
    if v_seen <> 0 then
      raise exception '0104 self-assert FAIL: the harbour served a PLAYER''s fleet (% row(s))', v_seen;
    end if;
    if jsonb_array_length(v_out->'merchants') <> v_rows then
      raise exception '0104 self-assert FAIL: the player''s route changed the harbour''s count (% -> %)',
        v_rows, jsonb_array_length(v_out->'merchants');
    end if;

    raise exception 'ROLLBACK_0104';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0104' then raise; end if;
  end;

  if (select count(*) from public.players) <> v_base then
    raise exception '0104 self-assert FAIL: a probe company survived the subtransaction';
  end if;
  if public.npc_traders_on() then
    raise exception '0104 self-assert FAIL: the merchant switch survived the subtransaction';
  end if;

  raise notice '0104 self-assert ok: A HARBOUR KNOWS WHICH MERCHANTS IT CONCERNS. '
    'client_rpc_entry_points is its pre-image plus only this file''s one hunk, ACL unmoved; '
    'world.port_merchants is registered and authenticated-only, and public.merchant_doing_at is '
    'reachable by nobody. Dark, with % merchant fleet(s) already founded: enabled false, no rows, '
    'the four top-level keys. Then the one switch put the roster to sea, and on three probe '
    'companies sharing the loop LIS then FNC, rolled back: she reads STARTING at her home quay and '
    'AWAY at her second call; held ten minutes she reads RESTING and the harbour serves that same '
    'word with her next_lap_at, and with that hold one second in the past STARTING again (the '
    'fortnight''s positive control, one fact apart); paused she reads LAID UP, and a pause outranks '
    'a hold; lying at her second call PASSING with LIS AWAY; at sea bound for home ENDING, and the '
    'same voyage turned around PASSING; a harbour off her loop gets no word at all. The read served '
    '% row(s) at LIS for % merchant route(s) that call there, every row a merchant''s and every '
    'loop really calling there, three or more distinct words among them, the rows non-decreasing in '
    'the server''s rank and the three probes back in the order LAID UP, STARTING, AWAY; the row''s '
    'key set read back EQUAL to world.sea_traffic''s own row for the same fleet with doing and '
    'stops struck out, and no forbidden key anywhere. A '
    'PLAYER''s identical LIS-FNC route — one the derivation does have a word for — was not a row '
    'and did not change the count.',
    (select count(*) from public.npc_fleets), v_rows, v_expect;
end $$;
