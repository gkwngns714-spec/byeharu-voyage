-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0037 — SHE ANSWERS HER HELM AT SEA
--        cmd.divert(fleet, dest): change a sailing fleet's destination mid-passage. She finishes
--        the water she is on, turns at the next node, and makes for the new mark.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE ASK ─────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-08-23: "and my clicking location and sending a fleet, i should be able to
-- change direction easily." Today a SAIL is a commitment to the whole passage: an order issued at
-- sea waits in the queue and runs only after she arrives where she was first sent. This file makes
-- the fleet answer her helm — and it does so WITHOUT the from-a-point router that free-coordinate
-- steering would need, which is the machine docs/PLATFORM.md §1 records being built, never lit,
-- and deleted in the predecessor.
--
-- ── THE FIVE DECISIONS, ANSWERED BEFORE THE SQL ────────────────────────────────────────────────
--
-- 1. WHERE DOES SHE DIVERT FROM? THE FAR NODE OF THE LEG SHE IS ON. Not from the open-sea point
--    under her keel: a mid-leg lat/lon is not a node of the leg graph, and routing from it needs
--    a water-legality oracle at runtime — most of OSN, rebuilt to finish a ticket. Turning at the
--    node instead means the diverted route is COMPOSED ENTIRELY OF AUTHORED LEGS, every one of
--    them a sailed A* path through the water raster — so the owner's law "the fleet never touches
--    land" holds for a diverted passage BY CONSTRUCTION, exactly as it holds for a plain one.
--    The leg stays the one spatial primitive (PLATFORM §2); the cost is honest and small: she
--    answers the helm at the next mark, not on a dime — which is also what a square-rigged fleet
--    on a plotted course would actually do.
--
-- 2. WHAT HAPPENS TO THE FROZEN SPEED PROFILE? NOTHING — THAT IS THE DESIGN. The sailing voyage
--    is TRUNCATED: its path keeps exactly the legs already sailed plus the one under her keel,
--    each keeping the speed frozen for it at departure, and voyage.recompute_eta — the one ETA
--    authority — re-derives the arrival from the shorter path and the delays already recorded.
--    The passage onward is a NEW voyage, born later through the one door every voyage is born
--    through (voyage.depart, via the queued SAIL below), freezing its own profile at its own
--    departure. No third state, no re-freeze, no touched invariant: proof 01's offline
--    equivalence is about each voyage being a pure function of its own frozen row, and both
--    voyages here are exactly that.
--
-- 3. WHAT HAS HAPPENED STAYS HAPPENED. Truncation removes only UNSAILED tail legs — she is
--    mid-leg, so the truncated ETA is strictly ahead of now, and every kept leg is byte-identical.
--    voyage.progress_nm(v, t) for any past t therefore answers exactly as before (asserted below
--    on a real diverted voyage), every settled voyage_events row keeps its PK, and no die is ever
--    re-rolled: the rng is keyed (voyage_id, day), settled days stay settled, and the days after
--    the turn belong to a NEW voyage id whose days were never rolled before. Turning around
--    cannot launder a storm.
--
-- 4. WHAT DOES IT COST? WHAT IT HONESTLY COSTS, AND NOTHING INVENTED. Days sailed are spent,
--    stores drunk are drunk, and the water between her and the turn node is still hers to cross.
--    The new route is priced from the node — not from where she wishes she were — and the pending
--    orders she composed against the OLD destination's market are CANCELLED (a BUY priced for
--    Cádiz executing at Porto is the wrong-market defect the Port screen's history records; the
--    DIVERTED ledger line says the queue was cleared). No fee is minted: commitment is real in
--    this game because distance is real.
--
-- 5. CAN SHE BE REFUSED? YES, THROUGH THE AUTHORITIES THAT EXIST. cmd.divert itself refuses only
--    what it alone can know: E_NOT_SAILING (she is not under way — from a quay, SAIL is the
--    order), E_NO_SUCH_PORT, E_SAME_DEST, and E_NO_ROUTE from THE router. The stores/crew/draft/
--    ice gate is deliberately NOT re-implemented here: the onward passage is a real SAIL order,
--    queued through cmd.issue (the ONE parser) and executed at the node through cmd.do_sail →
--    voyage.sail_refusal — the one gate, asked at the one moment it can answer truthfully (her
--    stores AT the node, not a forecast of them). If it refuses there, she halts DOCKED at a real
--    port with the refusal written and the fix one tap away — 0007's halt rule and 0008's CLEAR
--    as the release. Both outcomes are acceptable, so the branch is a real choice (§7C).
--
-- ── WHY A DIRECT RPC AND NOT A VERB ────────────────────────────────────────────────────────────
-- DIVERT is not an order a fleet works through her queue — it is an act upon the queue and the
-- voyage, like cmd.cancel_at and cmd.clear, and it must take effect NOW while SAIL-the-verb
-- (correctly) queues. Making it a verb would either fork SAIL's meaning by fleet status or put a
-- queued order that edits the queue it sits in. So it is the fourth cmd.* act beside issue,
-- cancel_at and clear: catalogued in client_rpc_entry_points (re-cut below, superseding 0034's),
-- named in src/lib/rpc/catalog.ts, granted to authenticated only, reading current_player_id().
--
-- ── SUPERSEDES ─────────────────────────────────────────────────────────────────────────────────
--   public.client_rpc_entry_points   0034 — re-cut whole: one row added, ('cmd','divert',
--                                    'uuid, uuid'). Everything else byte-identical.
--
-- ── WHAT IT SELF-ASSERTS (every one break-tested red; the reds are in the worktree report) ─────
--   (a) THE WHOLE ACT, on a real house: she departs Lisboa for a three-leg passage, is diverted
--       mid-SECOND-leg back to Lisboa, and the voyage truncates to exactly the two legs she has
--       touched, dest = the second leg's far node, ETA earlier than the old one and still ahead
--       of now, recomputed by the one authority.
--   (b) HISTORY IS UNTOUCHED: progress at a PAST instant and the settled event count are
--       byte-identical across the divert; the kept legs are the same rows.
--   (c) THE QUEUE IS HONEST: the BUY she had pending for the old destination is CANCELLED, and
--       exactly one pending SAIL TO <new dest> stands, composed through cmd.issue (the parser —
--       its raw_text is asserted, so no second grammar was minted).
--   (d) SHE TURNS: settled past the truncated ETA she docks at the node, the queue runs itself,
--       and she is SAILING again on a NEW voyage — new id, origin = the node, dest = the new
--       mark, its own frozen profile sized to its own path — and she ARRIVES there.
--   (e) EVERY LEG OF THE DIVERTED PASSAGE IS AN AUTHORED LEG (the never-touch-land law, held by
--       construction and asserted by joining the new path back to public.legs).
--   (f) THE REFUSALS: a docked fleet E_NOT_SAILING; the current destination E_SAME_DEST; a
--       made-up uuid E_NO_SUCH_PORT; another captain's fleet refused as not yours; and the
--       DIVERTED ledger line exists with the node, the old mark and the new.
--   (g) POSTURE: cmd.divert is catalogued and resolves, executable by authenticated and NOT by
--       anon; the read-wall authorities still read zero; the catalogue re-cut is its 0034
--       pre-image plus exactly the one row.
--
-- Depends ONLY on: 0004 (players/fleets/events), 0006 (voyages, progress, recompute_eta, depart),
--                  0007 (settle/advance/orders), 0008 (issue/clear/parse), 0019 (route/do_sail/
--                  sail_refusal), 0034 (client_rpc_entry_points pre-image), 0036 (sea places ride
--                  along: a diversion to one meets the same round-trip stores gate at the node).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- Pre-image of the catalogue, for the (g) parity assert.
create temporary table defs_before_0037 as
  select pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure) as def;

-- ── 1. THE ACT ─────────────────────────────────────────────────────────────────────────────────
create or replace function cmd.divert(p_fleet uuid, p_dest uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player   uuid := public.current_player_id();
  v_now      timestamptz := now();
  f          public.fleets%rowtype;
  v          public.voyages%rowtype;
  v_done     numeric;
  v_acc      numeric := 0;
  v_keep     int := 0;
  e          jsonb;
  v_node     uuid;
  v_node_c   text;
  v_dest_c   text;
  v_was_c    text;
  v_new_path jsonb;
  v_new_prof jsonb;
  v_total    numeric;
  v_eta      timestamptz;
  v_issue    jsonb;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.id is null or v_player is null or f.player_id <> v_player then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_SUCH_FLEET',
      'error_message', 'That fleet is not yours.', 'fixes', '[]'::jsonb);
  end if;

  -- Catch up first: the read is the catch-up (D.2), and an act must not reason about a stale
  -- position. She may prove to have ARRIVED, in which case the answer below is the true one.
  perform voyage.settle(p_fleet, v_now);
  select * into f from public.fleets where id = p_fleet;
  if f.status <> 'SAILING' then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_SAILING',
      'error_message', format('%s is %s, not under way — from a quay, SAIL is the order.', f.name, f.status),
      'fixes', jsonb_build_array(format('SAIL %s TO <the new port>', f.name)));
  end if;

  select p.code into v_dest_c from public.ports p where p.id = p_dest;
  if v_dest_c is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_SUCH_PORT',
      'error_message', 'There is no such port to make for.', 'fixes', '[]'::jsonb);
  end if;

  select * into v from public.voyages where fleet_id = p_fleet and status = 'SAILING';
  if v.dest_port_id = p_dest then
    return jsonb_build_object('ok', false, 'error_code', 'E_SAME_DEST',
      'error_message', format('%s is already bound for %s.', f.name,
        (select name from public.ports where id = p_dest)),
      'fixes', '[]'::jsonb);
  end if;

  -- THE TURN NODE: the far end of the leg under her keel. Progress is the closed form (0006) —
  -- no stored position, so nothing here can be stale. She keeps every leg she has entered.
  v_done := voyage.progress_nm(v.id, v_now);
  for e in select * from jsonb_array_elements(v.path) loop
    v_keep := v_keep + 1;
    v_acc  := v_acc + (e->>'nm')::numeric;
    v_node := (e->>'to_id')::uuid;
    exit when v_done < v_acc;
  end loop;
  select p.code into v_node_c from public.ports p where p.id = v_node;
  select p.code into v_was_c  from public.ports p where p.id = v.dest_port_id;

  -- THE ROUTER — the one there is — must know a road from the node before anything is touched.
  if v_node <> p_dest and voyage.route(v_node, p_dest) is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_ROUTE',
      'error_message', format('There is no sea road from %s to %s.', v_node_c, v_dest_c),
      'fixes', '[]'::jsonb);
  end if;

  -- TRUNCATE. Kept legs and their frozen speeds are byte-identical; only the unsailed tail goes.
  select jsonb_agg(t.value order by t.ordinality),
         jsonb_agg(v.speed_profile->(t.ordinality::int - 1) order by t.ordinality),
         sum((t.value->>'nm')::numeric)
    into v_new_path, v_new_prof, v_total
    from jsonb_array_elements(v.path) with ordinality t
   where t.ordinality <= v_keep;
  update public.voyages
     set path = v_new_path, speed_profile = v_new_prof, total_nm = v_total, dest_port_id = v_node
   where id = v.id;
  -- The ONE ETA authority, over the shorter path and the delays already recorded (0006).
  v_eta := voyage.recompute_eta(v.id);

  -- THE QUEUE WAS COMPOSED FOR ANOTHER MARKET. Pending (and failed) orders are cancelled — the
  -- same release CLEAR is (0008) — and the onward passage goes through the ONE parser, so no
  -- second grammar and no second writer of orders rows is minted here.
  perform cmd.clear(p_fleet);
  if v_node <> p_dest then
    v_issue := cmd.issue(p_fleet, format('SAIL TO %s', v_dest_c), null);
    if coalesce(v_issue->>'ok', 'false') <> 'true' then
      -- §7C: a half-landed diversion (voyage truncated, no onward order) is not an acceptable
      -- else. Raising rolls the WHOLE act back — truncation included — so a refused divert
      -- changes nothing at all.
      raise exception 'E_DIVERT_FAILED: the onward order was refused — %',
        coalesce(v_issue->>'error_message', 'no reason given') using errcode = 'P0001';
    end if;
  end if;

  perform public.emit_event(f.player_id, 'DIVERTED', jsonb_build_object(
    'fleet', f.name, 'voyage_id', v.id,
    'at', v_node_c, 'was', v_was_c, 'now', v_dest_c,
    'node_eta', v_eta, 'queue_cleared', true));

  return jsonb_build_object('ok', true, 'node', v_node_c, 'was', v_was_c, 'dest', v_dest_c,
                            'node_eta', v_eta, 'queue', cmd.queue(p_fleet));
end $$;

comment on function cmd.divert(uuid, uuid) is
  'THE helm order at sea (0037): truncate the sailing voyage at the far node of the current leg '
  '(the one ETA authority recomputes), cancel the queue composed for the old market, and queue '
  'SAIL <dest> through the one parser, to be gated at the node by the one refusal authority. '
  'History is untouched: kept legs, settled days and rolled hazards are byte-identical, and the '
  'onward passage is a NEW voyage with its own frozen profile. Refuses E_NOT_SAILING, '
  'E_NO_SUCH_PORT, E_SAME_DEST, E_NO_ROUTE; everything else is the gates that already exist.';

revoke all on function cmd.divert(uuid, uuid) from public, anon;
grant execute on function cmd.divert(uuid, uuid) to authenticated;

-- ── 2. SUPERSEDES 0034 — the catalogue gains the one row ───────────────────────────────────────
create or replace function public.client_rpc_entry_points()
returns table (schema_name text, function_name text, arg_types text, fn regprocedure)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select t.s, t.f, t.a,
         to_regprocedure(format('%I.%I(%s)', t.s, t.f, t.a))
    from (values
      -- the reads (world)
      ('world'::text, 'snapshot'::text,      ''::text),
      ('world',       'market',              'uuid'),
      ('world',       'fleets',              ''),
      ('world',       'ledger',              'timestamptz, int'),
      ('world',       'buy_capacity',        'uuid, uuid'),
      ('world',       'price_history',       'uuid, int'),
      ('world',       'player',              ''),
      ('world',       'officers',            ''),
      ('world',       'skills',              ''),
      ('world',       'trade_routes',        'uuid, uuid, int, int, uuid'),
      ('world',       'haggle_state',        'uuid, uuid'),
      ('world',       'standings',           'int'),
      ('world',       'buffs',               'uuid'),
      -- 0034: the book of standing orders. src/lib/rpc/catalog.ts names it worldProvisionPresets.
      ('world',       'provision_presets',   ''),
      -- the orders (cmd)
      ('cmd',         'issue',               'uuid, text, int'),
      ('cmd',         'preview',             'uuid, text'),
      ('cmd',         'cancel_at',           'uuid, int'),
      ('cmd',         'clear',               'uuid, boolean'),
      ('cmd',         'verb_schema',         ''),
      ('cmd',         'hire_officer',        'text, uuid'),
      ('cmd',         'post_officer',        'text, uuid'),
      ('cmd',         'study_skill',         'text, uuid'),
      ('cmd',         'found_house',         'text, text'),
      ('cmd',         'haggle',              'uuid, uuid, text'),
      -- 0034: write, adjust, strike and apply a standing provision order. None takes a player id.
      ('cmd',         'provision_preset_save',   'uuid, text, int'),
      ('cmd',         'provision_preset_delete', 'uuid'),
      ('cmd',         'provision_preset_apply',  'uuid, uuid'),
      -- 0037: the helm order at sea. Takes no player id; reads current_player_id() and refuses a
      -- fleet that is not yours — the property that makes an act safe for a browser to hold.
      ('cmd',         'divert',              'uuid, uuid')
    ) as t(s, f, a)
$$;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_probe   constant uuid := '00000000-0037-4000-8000-000000000001';
  c_other   constant uuid := '00000000-0037-4000-8000-000000000002';
  v_lis     uuid;
  v_far     uuid;
  v_player  uuid;
  v_other   uuid;
  v_fleet   uuid;
  v_nodes   uuid[];
  v_path    jsonb;
  v_speed   numeric;
  v_nm1     numeric;
  v_nm2     numeric;
  v_back    numeric;
  v_voyage  uuid;
  v_node    uuid;
  v_node_c  text;
  v_eta0    timestamptz;
  v_eta1    timestamptz;
  v_t_past  timestamptz;
  v_prog0   numeric;
  v_ev0     int;
  v_res     jsonb;
  v_n       int;
  v_new_v   public.voyages%rowtype;
  o         public.orders%rowtype;
  v_old     text;
  v_new     text;
  f_turn    boolean := false;  f_history boolean := false;
  f_queue   boolean := false;  f_onward  boolean := false;
  f_water   boolean := false;  f_refuse  boolean := false;
  f_ledger  boolean := false;  f_posture boolean := false;
begin
  select id into v_lis from public.ports where code = 'LIS';

  begin
    -- THE SUBJECT IS FOUND: the nearest harbour exactly three legs out of Lisboa, so there is a
    -- real tail to cut and the probe still settles in seconds.
    select r.port_id into v_far
      from voyage.reach_from(v_lis) r
      join public.ports hp on hp.id = r.port_id and hp.kind = 'HARBOUR'
     where r.hops = 3
     order by r.nm, r.port_id
     limit 1;
    if v_far is null then
      raise exception '0037 self-assert FAIL: no harbour lies exactly three legs from Lisboa — the probe needs a tail to cut and found none';
    end if;

    v_player := public.new_house(c_probe, 'Casa do Leme', 'PRT');
    -- cmd.divert reads current_player_id(), so the probe signs in as the house it founded.
    perform cmd.assume_identity(c_probe);
    select id into v_fleet from public.fleets where player_id = v_player;
    perform cmd.do_provision(v_fleet, jsonb_build_object('mode', 'FULL'));
    perform cmd.do_hire(v_fleet, jsonb_build_object('count',
      (select c.crew_max - sh.crew from public.ships sh
         join public.ship_classes c on c.id = sh.class_id where sh.fleet_id = v_fleet)));

    -- Depart BACKDATED so that "now" falls mid-SECOND-leg. now() is frozen in this transaction,
    -- so the probe moves the departure instead of waiting for the world to turn.
    v_nodes := voyage.route(v_lis, v_far);
    v_path  := voyage.path_from_nodes(v_nodes);
    v_speed := voyage.fleet_speed(v_fleet);
    v_nm1   := (v_path->0->>'nm')::numeric;
    v_nm2   := (v_path->1->>'nm')::numeric;
    v_voyage := voyage.depart(v_fleet, v_nodes,
      now() - make_interval(secs => (((v_nm1 + v_nm2 / 2) / v_speed) * 3600
                                     / public.wc_num('time_compression'))::double precision));

    -- Something pending, composed against the OLD passage, so (c) has something real to cancel.
    perform cmd.issue(v_fleet, 'SAIL TO CAD', null);
    select count(*) into v_n from public.orders where fleet_id = v_fleet and status = 'pending';
    if v_n <> 1 then
      raise exception '0037 self-assert FAIL: the fixture order did not queue (% pending)', v_n;
    end if;

    -- History markers, captured AFTER an explicit catch-up (a hazard settled between the capture
    -- and the act would otherwise move the ETA for its own true reasons and blur the assert).
    v_t_past := now() - make_interval(secs => ((v_nm1 / v_speed) * 3600
                                               / public.wc_num('time_compression'))::double precision);
    perform voyage.settle(v_fleet, now());
    select eta into v_eta0 from public.voyages where id = v_voyage;
    v_prog0 := voyage.progress_nm(v_voyage, v_t_past);
    select count(*) into v_ev0 from public.voyage_events where voyage_id = v_voyage;

    -- (f) THE REFUSALS FIRST, while she is under way: her own destination, and a made-up port.
    v_res := cmd.divert(v_fleet, v_far);
    if v_res->>'error_code' = 'E_SAME_DEST' then
      -- A fixed absent uuid, never a fresh random one: nothing on an assert path draws dice.
      v_res := cmd.divert(v_fleet, '00000000-0037-4000-8000-00000000dead');
      if v_res->>'error_code' = 'E_NO_SUCH_PORT' then f_refuse := true; end if;
    end if;
    if not f_refuse then
      raise exception '0037 self-assert FAIL: diverting to her own destination or to a made-up port was not refused as itself — got [%]', v_res->>'error_code';
    end if;
    -- Another captain's hand on her helm is refused as not yours.
    v_other := public.new_house(c_other, 'Casa Alheia', 'PRT');
    perform cmd.assume_identity(c_other);
    v_res := cmd.divert(v_fleet, v_lis);
    perform cmd.assume_identity(c_probe);
    if v_res->>'error_code' is distinct from 'E_NO_SUCH_FLEET' then
      raise exception '0037 self-assert FAIL: another captain diverted a fleet that is not his — got [%]', coalesce(v_res->>'error_code', 'ok');
    end if;

    -- (a) THE TURN: divert her home to Lisboa, mid-second-leg.
    v_res := cmd.divert(v_fleet, v_lis);
    if coalesce(v_res->>'ok', 'false') <> 'true' then
      raise exception '0037 self-assert FAIL: the diversion itself was refused — [%: %]',
        v_res->>'error_code', v_res->>'error_message';
    end if;
    select * into v_new_v from public.voyages where id = v_voyage;
    v_node   := (v_path->1->>'to_id')::uuid;
    v_node_c := (select code from public.ports where id = v_node);
    v_eta1   := v_new_v.eta;
    if jsonb_array_length(v_new_v.path) = 2
       and v_new_v.dest_port_id = v_node
       and v_res->>'node' = v_node_c
       and jsonb_array_length(v_new_v.speed_profile) = 2
       and abs(v_new_v.total_nm - (v_nm1 + v_nm2)) < 0.05
       and v_eta1 < v_eta0 and v_eta1 > now() then
      f_turn := true;
    end if;
    if not f_turn then
      raise exception '0037 self-assert FAIL: the truncation is wrong — % leg(s) kept, dest %, node said %, total % against % + %, eta % against old % — she is not turning at the far end of the leg she is on',
        jsonb_array_length(v_new_v.path),
        (select code from public.ports where id = v_new_v.dest_port_id),
        v_res->>'node', v_new_v.total_nm, v_nm1, v_nm2, v_eta1, v_eta0;
    end if;

    -- (b) HISTORY: the past did not move, the settled record did not move, the kept legs are the
    -- same rows.
    select count(*) into v_n from public.voyage_events where voyage_id = v_voyage;
    if voyage.progress_nm(v_voyage, v_t_past) = v_prog0
       and v_n = v_ev0
       and v_new_v.path->0 = v_path->0 and v_new_v.path->1 = v_path->1 then
      f_history := true;
    end if;
    if not f_history then
      raise exception '0037 self-assert FAIL: the diversion rewrote history — progress at a past instant moved (% -> %), or the settled record moved (% -> % events), or a kept leg changed',
        v_prog0, voyage.progress_nm(v_voyage, v_t_past), v_ev0, v_n;
    end if;

    -- (c) THE QUEUE: the old pending order is cancelled; exactly one pending SAIL TO LIS stands,
    -- written by the parser (raw_text proves no second grammar).
    select count(*) into v_n from public.orders
     where fleet_id = v_fleet and status = 'cancelled' and raw_text = 'SAIL TO CAD';
    select * into o from public.orders where fleet_id = v_fleet and status = 'pending';
    if v_n = 1 and o.verb = 'SAIL' and (o.args->>'dest')::uuid = v_lis
       and o.raw_text = 'SAIL TO LIS'
       and (select count(*) from public.orders where fleet_id = v_fleet and status = 'pending') = 1 then
      f_queue := true;
    end if;
    if not f_queue then
      raise exception '0037 self-assert FAIL: the queue after the turn is not [one pending SAIL TO LIS, old order cancelled] — pending verb %, raw [%], % cancelled fixture order(s)',
        o.verb, o.raw_text, v_n;
    end if;

    -- (f) the DIVERTED ledger line, with the node, the old mark and the new.
    if exists (select 1 from public.events ev
                where ev.player_id = v_player and ev.kind = 'DIVERTED'
                  and ev.payload->>'at' = v_node_c
                  and ev.payload->>'was' = (select code from public.ports where id = v_far)
                  and ev.payload->>'now' = 'LIS') then
      f_ledger := true;
    end if;
    if not f_ledger then
      raise exception '0037 self-assert FAIL: no DIVERTED ledger line names the turn (at %, was %, now LIS)',
        v_node_c, (select code from public.ports where id = v_far);
    end if;

    -- (d) SHE TURNS AND ARRIVES. Top the casks first (the probe owns its precondition: the gate
    -- at the node reads her REAL stores, and this probe is about the turn, not about thirst).
    update public.ships s
       set water_t = round(s.crew * public.wc_num('water_per_crew_day') * 30, 3),
           food_t  = round(s.crew * public.wc_num('food_per_crew_day')  * 30, 3)
     where s.fleet_id = v_fleet;
    perform voyage.settle(v_fleet, v_eta1 + interval '1 second');
    select * into v_new_v from public.voyages where fleet_id = v_fleet and status = 'SAILING';
    if v_new_v.id is not null and v_new_v.id <> v_voyage
       and v_new_v.origin_port_id = v_node and v_new_v.dest_port_id = v_lis
       and jsonb_array_length(v_new_v.speed_profile) = jsonb_array_length(v_new_v.path) then
      -- and the old voyage is closed at the node, not abandoned mid-sea.
      if (select status from public.voyages where id = v_voyage) = 'ARRIVED' then
        perform voyage.settle(v_fleet, v_new_v.eta + interval '1 second');
        if (select status from public.fleets where id = v_fleet) = 'DOCKED'
           and (select port_id from public.fleets where id = v_fleet) = v_lis then
          f_onward := true;
        end if;
      end if;
    end if;
    if not f_onward then
      raise exception '0037 self-assert FAIL: the queue did not carry her home — after the node she should sail a NEW voyage % -> LIS and dock there (voyage %, fleet % at %)',
        v_node_c, coalesce(v_new_v.id::text, '(none)'),
        (select status from public.fleets where id = v_fleet),
        (select coalesce(p.code, '(nowhere)') from public.fleets fl
           left join public.ports p on p.id = fl.port_id where fl.id = v_fleet);
    end if;

    -- (e) THE LAW: every leg of the diverted passage is an AUTHORED leg — she cannot have been
    -- routed across land, because she was only ever routed along rows of public.legs.
    select count(*) into v_n
      from jsonb_array_elements(v_new_v.path) t
     where not exists (select 1 from public.legs l where l.id = (t.value->>'leg_id')::uuid);
    if v_n = 0 then f_water := true; end if;
    if not f_water then
      raise exception '0037 self-assert FAIL: % leg(s) of the diverted passage are not rows of public.legs — a diversion has minted water of its own', v_n;
    end if;

    -- (f) and the plainest refusal: she is docked now, and the helm answers only at sea.
    v_res := cmd.divert(v_fleet, v_far);
    if v_res->>'error_code' is distinct from 'E_NOT_SAILING' then
      raise exception '0037 self-assert FAIL: diverting a DOCKED fleet was not refused E_NOT_SAILING — got [%]', coalesce(v_res->>'error_code', 'ok');
    end if;

    raise exception 'ROLLBACK_0037_PROBE';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0037_PROBE' then raise; end if;
  end;

  select count(*) into v_n from public.players pl where pl.auth_uid in (c_probe, c_other);
  if v_n <> 0 then
    raise exception '0037 self-assert FAIL: % probe house(s) survived the subtransaction', v_n;
  end if;

  ---------------------------------------------------------------------------------------------
  -- (g) POSTURE.
  ---------------------------------------------------------------------------------------------
  select def into v_old from defs_before_0037;
  v_new := pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure);
  if replace(v_new, $r$,
      -- 0037: the helm order at sea. Takes no player id; reads current_player_id() and refuses a
      -- fleet that is not yours — the property that makes an act safe for a browser to hold.
      ('cmd',         'divert',              'uuid, uuid')$r$, '') is distinct from v_old then
    raise exception '0037 self-assert FAIL: the catalogue re-cut is not its 0034 pre-image plus exactly the divert row — something else in the entry-point list moved';
  end if;
  if exists (select 1 from public.client_rpc_entry_points() e where e.fn is null)
     or not exists (select 1 from public.client_rpc_entry_points() e
                     where e.schema_name = 'cmd' and e.function_name = 'divert')
     or not has_function_privilege('authenticated', 'cmd.divert(uuid, uuid)', 'execute')
     or has_function_privilege('anon', 'cmd.divert(uuid, uuid)', 'execute')
     or (select count(*) from public.client_write_grants()) <> 0
     -- divert IS a client-executable writer, and 0018's authority already excludes CATALOGUED
     -- entry points — so this reads zero exactly because the catalogue row above exists.
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0037 self-assert FAIL: the posture is wrong — divert is uncatalogued, unresolvable, wrongly granted, or the read wall no longer reads zero beyond the sanctioned entry point';
  end if;
  f_posture := true;

  raise notice '0037 self-assert ok: SHE ANSWERS HER HELM AT SEA — a real house sailed Lisboa out on a three-leg passage, was diverted home mid-second-leg, and the voyage truncated to exactly the two legs she had touched (dest %, ETA pulled earlier and still ahead), recomputed by the one authority; the past did not move (progress at a past instant and % settled event(s) byte-identical, kept legs the same rows); the stale queue was cancelled and exactly one pending SAIL TO LIS stood, written by the one parser; at the node the queue ran itself and she sailed a NEW voyage — its own id, its own frozen profile — and docked at Lisboa; every leg of the diverted passage is an authored row of public.legs, so the fleet never touched land by construction; her own destination, a made-up port, a docked fleet and another captain''s hand were each refused as themselves; the DIVERTED ledger line names the turn; and cmd.divert is catalogued, authenticated-only, with the catalogue re-cut proven to be its 0034 pre-image plus exactly one row',
    v_node_c, v_ev0;
end $$;

drop table defs_before_0037;
