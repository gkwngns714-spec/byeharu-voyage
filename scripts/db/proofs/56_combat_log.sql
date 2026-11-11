-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 56 — A FIGHT KEEPS ITS LOG, AND A FLEET HAS A STANDING ORDER  (migration 0353, slices C1 + C2 of docs/COMBAT_LOG.md, owner row 315)
--
--   The migration's self-assert proves the engine and the skin on crafted hulls (parity as text, Flee, Pay, the prefix). This proof plays the game: real fleets of real hulls,
--   the REAL departure (voyage.depart), the REAL day (voyage.settle's PIRATES arm), the REAL door (cmd.raid_order), the REAL purses. The sea is stubbed on one setting, as proofs 37,
--   38 and 46 stub it: '' quiet, 'PIRATES' a raid of magnitude 0.5. OLD AGAINST NEW is not taken on trust: the migration's own 20 hunks are held below (written by
--   scripts/ops/harness/combat-log/gen-checks.mjs --proof from the migration's text), each is found once in the live body and reversed, every old body is held to its digest, and the
--   same passage (the voyage id pinned: it is the fight's seed) is sailed under the old bodies and the new, each in a subtransaction that is rolled back.
--   Everything rolls back with proof.mjs's transaction; every switch this proof needs it writes here.
--
-- @pass LOG_NPC_PARITY     a merchant's forced raid passage (12 raid days), old bodies against new: every day's payload, the report, the purse and the hulls, byte for byte; no log anywhere; the same with the switch lit
-- @pass LOG_HUMAN          a company's raid keeps fight.log (v 1): its rounds are rounds_fought, `after` is her hull, the report's entry carries the same log and the day's losses; without the log every day and the report are the old bodies', word for word
-- @pass LOG_LATE           for each order (Fight, Flee, Pay): settled day by day and settled once at the eta are identical: days, events, ledger, purse, hulls
-- @pass ORDER_FROZEN       Flee, depart, Pay at sea: the raid runs Flee; the next voyage is frozen Pay; voyage.depart is the only writer of a voyage, so a turn freezes again
-- @pass ORDER_FLEE         through the real settle: away is EVADED with `fled`, no shot of hers, no hands lost, her hull the log's `after`; caught is boarded after six rounds
-- @pass ORDER_PAY          through the real settle: RANSOM before a shot; her purse down by ransom_share of the cargo at cost, the Brethren's capital up by the same, kind RANSOM, W unchanged; no hull, no hands, no cargo, no insurance claim; a short purse pays what it holds
-- @pass ORDER_PAY_REFUSED  an empty hold, and no payee (the purses dark): she fights, nothing is paid, and the log says why (EMPTY, NO_PAYEE)
-- @pass ORDER_DARK         the switch off: the door refuses and keeps the row, the read says off, a departure's path is 0339's byte for byte, and an order frozen while lit is ignored
-- @pass ORDER_DOOR         each refusal (no house, dark, another company's fleet, a bad word); FIGHT leaves no row; anon cannot call either door; both are client entry points
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

create temp table hunks_56 (fn text, n int, old text, new text) on commit drop;
insert into hunks_56 (fn, n, old, new) values
  ('public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)', 1, $h$  v_ratio  numeric;
begin
$h$, $h$  v_ratio  numeric;
  -- 0353: her standing order (p_opts.a_order: FIGHT, FLEE or PAY, one word or a list with a word a round whose last stands for the rest) and the round the fight stops at (p_opts.rounds). Absent: the fight as it was.
  v_ord    jsonb := p_opts->'a_order';
  v_ao     text;
  v_cap    int := greatest(1, coalesce((p_opts->>'rounds')::int, 1000000));
  v_fled   boolean := false;
  v_paid   boolean := false;
  v_open   boolean := false;
  v_pf     numeric;
begin
$h$),
  ('public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)', 2, $h$  for g in 1 .. jsonb_array_length(v_ranges) loop
    v_fought := g;
$h$, $h$  for g in 1 .. jsonb_array_length(v_ranges) loop
    -- 0353: PAY ends it before a shot (RANSOM, `paid`); past p_opts.rounds the fight is left `open`
    v_ao := case jsonb_typeof(v_ord) when 'string' then v_ord #>> '{}'
                                     when 'array' then coalesce(v_ord ->> (g - 1), v_ord ->> -1) end;
    if g > v_cap or v_ao = 'PAY' then
      if g = 1 then v_la := v_h0a; v_lb := v_h0b; end if;
      if g > v_cap then v_open := true; else v_paid := true; v_outcome := 'RANSOM'; end if;
      exit;
    end if;
    v_fought := g;
$h$),
  ('public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)', 3, $h$v_range, v_mult, g = 1 and v_first = 'B', v_k,
$h$, $h$v_range, v_mult, (g = 1 and v_first = 'B') or coalesce(v_ao = 'FLEE', false), v_k,   -- 0353: a side that runs fires nothing
$h$),
  ('public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)', 4, $h$      v_broke := true;
      exit;
    end if;
  end loop;
$h$, $h$      v_broke := true;
      exit;
    end if;
    -- 0353: FLEE. She took this round's fire; now she rolls to slip, on her own stream. Away is EVADED with `fled`.
    if v_ao = 'FLEE' then
      v_pf := least(public.wc_num('fight_evade_max'), greatest(public.wc_num('fight_flee_floor'),
                public.wc_num('fight_flee_base') + (v_sa - v_sb) * public.wc_num('fight_evade_per_sighting')));
      v_rows := jsonb_set(v_rows, array[(g - 1)::text, 'flee'], to_jsonb(round(v_pf, 4)));
      if voyage.rng(p_seed, p_round, format('fight:%s:flee', g)) < v_pf then
        v_fled := true; v_outcome := 'EVADED'; exit;
      end if;
    end if;
  end loop;
$h$),
  ('public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)', 5, $h$  if v_outcome is null then
    for i in 1 .. v_na loop
$h$, $h$  if v_outcome is null and not v_open then
    for i in 1 .. v_na loop
$h$),
  ('public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)', 6, $h$    'hits', jsonb_build_object('a', v_tot_a, 'b', v_tot_b));
$h$, $h$    'hits', jsonb_build_object('a', v_tot_a, 'b', v_tot_b))
    -- 0353: said only when true, so a fight with no order and no round limit is the answer it was
    || case when v_fled then '{"fled": true}'::jsonb else '{}'::jsonb end
    || case when v_paid then '{"paid": true}'::jsonb else '{}'::jsonb end
    || case when v_open then '{"open": true}'::jsonb else '{}'::jsonb end;
$h$),
  ('voyage.fight_round_line(jsonb,integer,text,jsonb,numeric,text)', 1, $h$  v_you := case when p_g = 1 and p_first = 'THEY' then 'you are caught unready'
$h$, $h$  v_you := case when p_round ? 'flee' then 'you run before them'   -- 0353: a side that runs (public.fight_sides writes `flee` on such a round only)
                when p_g = 1 and p_first = 'THEY' then 'you are caught unready'
$h$),
  ('voyage.fight(uuid,integer,uuid,numeric)', 1, $h$  return voyage.fight_resolve(p_voyage, p_day, p_raider, voyage.escort_score(p_fleet), voyage.fleet_hulls(p_fleet));   -- 0323: the side, cut to its own leaf
$h$, $h$  return voyage.raid_report(p_voyage, p_day, p_raider, voyage.escort_score(p_fleet), voyage.fleet_hulls(p_fleet),   -- 0323: the side, cut to its own leaf
                            voyage.raid_opts(p_voyage, p_day, p_fleet));   -- 0353: {} for a merchant; a company's log and her frozen order
$h$),
  ('voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)', 1, $h$  values (p_fleet, v_player, voyage.freeze_raiders(voyage.freeze_danger(p_segments, p_at), p_fleet), v_total, v_profile, p_at,   -- 0330: each segment keeps the danger of its sea as she left; 0339: and the pirate ship cruising it, if any
$h$, $h$  values (p_fleet, v_player, voyage.freeze_order(voyage.freeze_raiders(voyage.freeze_danger(p_segments, p_at), p_fleet), p_fleet), v_total, v_profile, p_at,   -- 0330: each segment keeps the danger of its sea as she left; 0339: and the pirate ship cruising it, if any; 0353: and her standing order, if she has one
$h$),
  ('voyage.settle(uuid,timestamp with time zone)', 1, $h$      if v_pirate is not null and v_outcome = 'RANSOM' then   -- 0339: paid off a named raider$h$, $h$      if coalesce((v_fight->>'paid')::boolean, false) then   -- 0353: she chose to pay (her standing order): the same share, to the raider's home or, for an anonymous raid, the Brethren's capital (public.raid_ransom)
        v_ransom := public.raid_ransom(v_pirate, f.player_id, public.fleet_stock_at_cost(p_fleet));
      elsif v_pirate is not null and v_outcome = 'RANSOM' then   -- 0339: paid off a named raider$h$),
  ('voyage.settle(uuid,timestamp with time zone)', 2, $h$                                                     'stowed', coalesce(v_stow, '{}'::jsonb), 'ransom', v_ransom, 'booked', v_booked)) end
$h$, $h$                                                     'stowed', coalesce(v_stow, '{}'::jsonb), 'ransom', v_ransom, 'booked', v_booked)) end
                   -- 0353: what she paid by her standing order, on such a day only
                   || case when coalesce((v_fight->>'paid')::boolean, false) then jsonb_build_object('ransom_paid', v_ransom) else '{}'::jsonb end
$h$),
  ('voyage.settle(uuid,timestamp with time zone)', 3, $h$                      else jsonb_build_object('fights', jsonb_agg(jsonb_build_object('line', z.n - 1, 'rounds', z.payload->'rounds')
$h$, $h$                      else jsonb_build_object('fights', jsonb_agg(jsonb_build_object('line', z.n - 1, 'rounds', z.payload->'rounds')
                                                                  -- 0353: a day that kept a log (a company's raid) carries it, and what the day cost; any other entry is what it was
                                                                  || case when z.payload->'fight' ? 'log'
                                                                          then jsonb_build_object('log', z.payload->'fight'->'log',
                                                                                 'loss', jsonb_build_object('crew_before', z.payload->'crew_before', 'crew', z.payload->'crew_lost',
                                                                                           'cargo', coalesce(z.payload->'cargo_lost', '{}'::jsonb),
                                                                                           'ransom', coalesce(z.payload->'ransom_paid', z.payload->'pirate'->'ransom', '0'::jsonb)))
                                                                          else '{}'::jsonb end
$h$),
  ('public.client_rpc_entry_points()', 1, $h$      ('world',       'pirate_ship_card',      'uuid'),
$h$, $h$      ('world',       'pirate_ship_card',      'uuid'),
      -- 0353: a fleet's standing order when raiders close (Fight, Flee, Pay), and the read beside the picker.
      ('cmd',         'raid_order',            'uuid, text'),
      ('world',       'raid_read',             'uuid'),
$h$),
  ('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)', 1, $h$CREATE OR REPLACE FUNCTION voyage.fight_resolve(p_voyage uuid, p_day integer, p_raider numeric, p_escort numeric, p_ships jsonb)
$h$, $h$CREATE OR REPLACE FUNCTION voyage.raid_report(p_voyage uuid, p_day integer, p_raider numeric, p_escort numeric, p_ships jsonb, p_opts jsonb)
$h$),
  ('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)', 2, $h$jsonb_build_object('a_score', p_escort, 'b_score', p_raider));
$h$, $h$jsonb_build_object('a_score', p_escort, 'b_score', p_raider)
                     -- 0353: p_opts {order: FLEE or PAY, log, pay_refused, foe_ship} (voyage.raid_opts). {} is the raid as it was, word for word: voyage.fight_resolve passes it.
                     || case when p_opts->>'order' in ('FLEE', 'PAY') then jsonb_build_object('a_order', p_opts->>'order') else '{}'::jsonb end);
$h$),
  ('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)', 3, $h$                              'hits', jsonb_build_object('yours', 0, 'theirs', 0));
  end if;

  v_lines := v_lines || case when r_n < 0.75
$h$, $h$                              'hits', jsonb_build_object('yours', 0, 'theirs', 0))
           || case when p_opts = '{}'::jsonb then '{}'::jsonb else voyage.raid_extras(p_ships, v_r, v_f, p_opts) end;   -- 0353
  end if;

  v_lines := v_lines || case when r_n < 0.75
$h$),
  ('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)', 4, $h$                              'hits', jsonb_build_object('yours', 0, 'theirs', 0));
  elsif v_first = 'YOU' then
$h$, $h$                              'hits', jsonb_build_object('yours', 0, 'theirs', 0))
           || case when p_opts = '{}'::jsonb then '{}'::jsonb else voyage.raid_extras(p_ships, v_r, v_f, p_opts) end;   -- 0353
  elsif v_first = 'YOU' then
$h$),
  ('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)', 5, $h$  -- THE ROUNDS
  for g in 1 .. (v_f->>'rounds_fought')::int loop
$h$, $h$  -- 0353: her standing order, in words
  if p_opts->>'pay_refused' = 'EMPTY' then
    v_lines := v_lines || 'You have nothing aboard to pay them with.'::text;
  elsif p_opts->>'pay_refused' = 'NO_PAYEE' then
    v_lines := v_lines || 'They will take no ransom.'::text;
  elsif p_opts->>'order' = 'FLEE' then
    v_lines := v_lines || 'You turn and run.'::text;
  end if;

  -- THE ROUNDS
  for g in 1 .. (v_f->>'rounds_fought')::int loop
$h$),
  ('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)', 6, $h$  -- HOW IT ENDED
  if (v_f->>'broke_off')::boolean then
$h$, $h$  -- HOW IT ENDED
  if coalesce((v_f->>'paid')::boolean, false) then   -- 0353: Pay, before a shot
    v_lines := v_lines || 'You pay their price, and they let you pass.'::text;
    v_sentence := 'We paid their price and they let us pass.';
  elsif coalesce((v_f->>'fled')::boolean, false) then   -- 0353: Flee, and away
    v_lines := v_lines || 'You get clear of them.'::text;
    v_sentence := 'We ran, and got clear of them.';
  elsif (v_f->>'broke_off')::boolean then
$h$),
  ('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)', 7, $h$    'hits', jsonb_build_object('yours', (v_f->'hits'->>'a')::int, 'theirs', (v_f->'hits'->>'b')::int));
$h$, $h$    'hits', jsonb_build_object('yours', (v_f->'hits'->>'a')::int, 'theirs', (v_f->'hits'->>'b')::int))
    || case when p_opts = '{}'::jsonb then '{}'::jsonb else voyage.raid_extras(p_ships, v_r, v_f, p_opts) end;   -- 0353: `paid`, `fled` and the log, for a company's raid only
$h$);

-- the pre-images 0353 was cut against, by digest (pg_get_functiondef, LF)
create temp table pre_56 (fn text primary key, md5 text) on commit drop;
insert into pre_56 values
  ('public.client_rpc_entry_points()', '04141692005b6e8a22b36c7483e576f9'),
  ('voyage.fight(uuid,integer,uuid,numeric)', 'a4694aca0f213537d184a319f7ef75d9'),
  ('voyage.settle(uuid,timestamp with time zone)', '7e3233a44e9ad1ba9fe17adae2f544ce'),
  ('public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)', '2fd7ebc8a572ed14a792f72eeda9dd37'),
  ('voyage.fight_resolve(uuid,integer,numeric,numeric,jsonb)', '97bbb6d8cd557853e1e3246fcfba15fe'),
  ('voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)', 'd8cb03b14dddffb1adbacf1997a09e73'),
  ('voyage.fight_round_line(jsonb,integer,text,jsonb,numeric,text)', '3952c3fd7ca19295117a0d5886899a9b');

-- THE OLD BODIES, put back from the live ones: each hunk's NEW text once, reversed; each result held to its digest. voyage.raid_report reversed IS the old voyage.fight_resolve.
-- Called only inside a subtransaction that is rolled back.
create function pg_temp.to_old_56() returns void language plpgsql as $b$
declare
  f     record;
  h     record;
  v_def text;
begin
  for f in select distinct x.fn from hunks_56 x order by x.fn loop
    v_def := replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '');
    for h in select * from hunks_56 x where x.fn = f.fn order by x.n desc loop
      if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
        raise exception 'PROOF 56 FAIL: hunk % of % is not in the live body exactly once', h.n, f.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    execute v_def;
  end loop;
  if exists (select 1 from pre_56 p where md5(replace(pg_get_functiondef(p.fn::regprocedure), E'\r', '')) <> p.md5) then
    raise exception 'PROOF 56 FAIL: an old body did not go back to its digest: %',
      (select string_agg(p.fn, ', ') from pre_56 p where md5(replace(pg_get_functiondef(p.fn::regprocedure), E'\r', '')) <> p.md5);
  end if;
end
$b$;

-- a path of p_days voyage-days, every day in sea p_sea (proof 46's: a day is her speed x 24 to the digit)
create function pg_temp.through(p_fleet uuid, p_sea uuid, p_days int) returns jsonb language sql stable as $b$
  select jsonb_agg(jsonb_build_object('a', jsonb_build_array(0, 0), 'b', jsonb_build_array(0, 0), 'nm', voyage.fleet_speed(p_fleet) * 24, 'sea_id', p_sea, 'hazard_mult', 1000))
    from generate_series(1, p_days)
$b$;

-- ── the sea on one setting (proof 37's, 38's and 46's stub): '' quiet, 'PIRATES' a raid of magnitude 0.5 ──
do $$
begin
  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_56;
  execute $f$
create function voyage.hazard_roll(p_voyage uuid, p_day integer)
returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
language plpgsql stable
as $b$
declare
  v_s text := coalesce(current_setting('byeharu.proof_sea', true), '');
begin
  return query select v_s <> '', nullif(v_s, ''), 0.5::numeric, 1::numeric;
end
$b$
  $f$;
end
$$;

-- she sails to the end of her voyage on a quiet sea
create function pg_temp.reach_port(p_fleet uuid) returns void language plpgsql as $b$
declare
  v_v uuid;
  v_e timestamptz;
begin
  perform set_config('byeharu.proof_sea', '', true);
  loop
    select o.id, o.eta into v_v, v_e from public.voyages o where o.fleet_id = p_fleet and o.status = 'SAILING';
    exit when v_v is null;
    perform voyage.settle(p_fleet, v_e);
  end loop;
  update public.fleets f set ready_at = null where f.id = p_fleet;
end
$b$;

-- one raid day through the real settle; answers the day's payload
create function pg_temp.raid_day(p_fleet uuid, p_voy uuid, p_day int) returns jsonb language plpgsql as $b$
begin
  perform set_config('byeharu.proof_sea', 'PIRATES', true);
  perform voyage.settle(p_fleet, voyage.day_ends_at(p_voy, p_day));
  perform set_config('byeharu.proof_sea', '', true);
  return (select e.payload from public.voyage_events e where e.voyage_id = p_voy and e.day_index = p_day and e.kind = 'PIRATES');
end
$b$;

-- her hull and hands made good, and the probe cargo aboard again (10 at 2,000 d.: a ransom of 8 per cent is 1,600)
create function pg_temp.refit_56(p_fleet uuid) returns void language plpgsql as $b$
begin
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b), crew = (select c.crew_required from public.ship_classes c where c.id = s.class_id),
                            cargo = '{"baltic-amber": 10}'::jsonb, cargo_basis = '{"baltic-amber": 2000}'::jsonb   -- written straight: her casks fill the probe's hold, and the hold is not what this proof reads
   where s.fleet_id = p_fleet;
  if public.raid_price(p_fleet) <> floor(20000 * public.wc_num('ransom_share')) then
    raise exception 'PROOF 56 FAIL: the probe cargo did not load: 10 at 2,000 d. should price a ransom at %', floor(20000 * public.wc_num('ransom_share'));
  end if;
end
$b$;

create function pg_temp.w_56() returns numeric language sql as $b$
  select (select coalesce(sum(public.treasury_balance(t.port_id)), 0) from public.port_treasury t)::numeric
       + (select coalesce(sum(p.ducats), 0) from public.players p)::numeric + public.funds_aboard()::numeric
$b$;

-- A WHOLE PASSAGE OF RAID DAYS, in a subtransaction that is rolled back: under the old bodies or the new, settled day by day or once at the eta. The voyage id is pinned (the fight's seed).
-- Answers everything it left: every day, every event of the company, her ledger rows, her purse, her hulls.
create function pg_temp.passage_56(p_fleet uuid, p_sea uuid, p_days int, p_at timestamptz, p_by_day boolean, p_old boolean) returns jsonb language plpgsql as $b$
declare
  c_voy  constant uuid := '00000000-0356-4000-8000-0000000000aa';
  v_pl   uuid := (select f.player_id from public.fleets f where f.id = p_fleet);
  v_port uuid := (select f.port_id from public.fleets f where f.id = p_fleet);
  v_ev   uuid[] := array(select e.id from public.events e where e.player_id = v_pl);
  v_led  uuid[] := array(select l.id from public.ledger l where l.player_id = v_pl);
  v_voy  uuid;
  v_out  jsonb;
  d      int;
begin
  begin
    if p_old then
      perform pg_temp.to_old_56();
    end if;
    v_voy := voyage.depart(p_fleet, pg_temp.through(p_fleet, p_sea, p_days), v_port, v_port, p_at);
    update public.voyages set id = c_voy where id = v_voy;
    perform set_config('byeharu.proof_sea', 'PIRATES', true);
    if p_by_day then
      for d in 1 .. p_days loop
        perform voyage.settle(p_fleet, voyage.day_ends_at(c_voy, d));
      end loop;
    end if;
    perform voyage.settle(p_fleet, (select o.eta from public.voyages o where o.id = c_voy));
    perform set_config('byeharu.proof_sea', '', true);
    if (select o.status from public.voyages o where o.id = c_voy) <> 'ARRIVED' then
      raise exception 'PROOF 56 FAIL: the passage did not arrive';
    end if;
    v_out := jsonb_build_object(
      'path', (select o.path from public.voyages o where o.id = c_voy),
      'days', (select jsonb_agg(jsonb_build_object('d', e.day_index, 'kind', e.kind, 'payload', e.payload, 'at', e.resolved_at) order by e.day_index)
                 from public.voyage_events e where e.voyage_id = c_voy),
      'events', (select coalesce(jsonb_agg(jsonb_build_object('kind', e.kind, 'payload', e.payload) order by e.kind, e.payload::text), '[]'::jsonb)
                   from public.events e where e.player_id = v_pl and e.id <> all (v_ev)),
      'ledger', (select coalesce(jsonb_agg(jsonb_build_array(l.kind, l.ducats_delta, l.balance_after) order by l.balance_after desc, l.kind), '[]'::jsonb)
                   from public.ledger l where l.player_id = v_pl and l.id <> all (v_led)),
      'purse', (select p.ducats from public.players p where p.id = v_pl),
      'ships', (select jsonb_agg(jsonb_build_array(s.name, s.durability, s.crew, s.cargo) order by s.name) from public.ships s where s.fleet_id = p_fleet));
    raise exception using errcode = 'ZX356', message = 'PASSAGE_ROLLBACK_56';
  exception when sqlstate 'ZX356' then
    null;
  end;
  perform set_config('byeharu.proof_sea', '', true);
  return v_out;
end
$b$;

do $p$
declare
  c_uid   constant uuid := '00000000-0356-4000-8000-000000000001';
  c_uid2  constant uuid := '00000000-0356-4000-8000-000000000002';
  v_t     timestamptz := date_trunc('day', now() at time zone 'UTC') at time zone 'UTC' + interval '2 hours';
  v_lis   uuid;
  v_por   uuid;
  v_sea   uuid;
  v_hum   uuid;
  v_oth   uuid;
  v_hfl   uuid;
  v_ofl   uuid;
  v_npc   uuid;
  v_nfl   uuid;
  v_ship  uuid;
  v_maxd  numeric;
  v_voy   uuid;
  v_a     jsonb;
  v_b     jsonb;
  v_r     jsonb;
  v_x     jsonb;
  v_log   jsonb;
  v_p     jsonb;
  v_i     int;
  v_n     int;
  v_fled  int := 0;
  v_caught int := 0;
  v_paid  int := 0;
  v_purse bigint;
  v_take  bigint;
  v_w     numeric;
  v_mark  bigint;
  v_ev    int;
  v_hull  numeric;
  v_ord   text;
begin
  -- ── THE WORLD: the fight lit (as the chain leaves it), the purses lit, the pirates' ships dark (every raid anonymous), standing orders dark until said ──
  update public.world_config set value = 'true'::jsonb where key in ('combat_bite', 'city_treasury_enabled');
  update public.world_config set value = 'false'::jsonb where key in ('pirates_bite', 'navy_enabled', 'attack_enabled', 'npc_refits_enabled', 'raid_orders_enabled');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  select p.id into v_lis from public.ports p where p.code = 'LIS';
  v_por := public.pirate_capital();
  v_sea := (select s.id from public.seas s order by s.piracy_index desc, s.code limit 1);
  if v_por is null or v_sea is null or public.raid_payee(null) is distinct from v_por then
    raise exception 'PROOF 56 FAIL: no Brethren capital, no sea, or the payee is not the capital with the purses lit';
  end if;

  insert into public.players (auth_uid, company_name, nation_id, ducats) values (c_uid, 'Proof 56 house', (select n.id from public.nations n where n.code = 'PRT'), 300000) returning id into v_hum;
  insert into public.players (auth_uid, company_name, nation_id, ducats) values (c_uid2, 'Proof 56 other', (select n.id from public.nations n where n.code = 'PRT'), 1000) returning id into v_oth;
  v_hfl := public.form_fleet(v_hum, 'Proof 56 fleet', v_lis);
  perform public.commission_ship(v_hum, v_hfl, 'jacht', 'Proof 56 jacht', true, true);   -- a gunless hull: the raid closes on her
  v_ofl := public.form_fleet(v_oth, 'Proof 56 other fleet', v_lis);
  perform public.commission_ship(v_oth, v_ofl, 'jacht', 'Proof 56 other hull', true, true);
  v_npc := public.new_house(null, 'Proof 56 merchant', 'PRT', p_ducats => 20000, p_is_npc => true);
  select f.id into v_nfl from public.fleets f where f.player_id = v_npc;
  update public.ships s set water_t = 100000, food_t = 100000 where s.fleet_id in (v_hfl, v_nfl, v_ofl);
  select s.id, (select b.durability from public.ship_base(s.id) b) into v_ship, v_maxd from public.ships s where s.fleet_id = v_hfl;
  perform pg_temp.refit_56(v_hfl);
  perform pg_temp.refit_56(v_nfl);

  -- ── LOG_NPC_PARITY: a merchant's 12 raid days, old bodies against new ──
  v_a := pg_temp.passage_56(v_nfl, v_sea, 12, v_t, false, false);
  v_b := pg_temp.passage_56(v_nfl, v_sea, 12, v_t, false, true);
  if v_a is null or v_a::text is distinct from v_b::text then
    raise exception 'PROOF 56 FAIL: a merchant''s raid passage changed: % against %', v_a, v_b;
  end if;
  if (select count(*) from jsonb_array_elements(v_a -> 'days') e where e ->> 'kind' = 'PIRATES' and e -> 'payload' ? 'fight' and e -> 'payload' ? 'rounds') is distinct from 12
     or v_a::text like '%"log"%' or v_a::text like '%ransom_paid%' or not exists (select 1 from jsonb_array_elements(v_a -> 'events') e where e ->> 'kind' = 'VOYAGE_REPORT' and e -> 'payload' ? 'fights') then
    raise exception 'PROOF 56 FAIL: the merchant''s passage is not 12 fought raid days and a report with fights, with no log: %', v_a -> 'days';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'raid_orders_enabled';
  if pg_temp.passage_56(v_nfl, v_sea, 12, v_t, false, false)::text is distinct from v_b::text then
    raise exception 'PROOF 56 FAIL: with the switch lit a merchant''s raid passage changed';
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'raid_orders_enabled';
  if exists (select 1 from public.voyages o where o.fleet_id = v_nfl) or (select md5(replace(pg_get_functiondef('voyage.settle(uuid,timestamp with time zone)'::regprocedure), E'\r', '')) = (select p.md5 from pre_56 p where p.fn like 'voyage.settle%')) then
    raise exception 'PROOF 56 FAIL: a passage outlived its rollback, or the old bodies stayed';
  end if;
  raise notice 'PASS: LOG_NPC_PARITY — 12 raid days of a merchant, the 7 old bodies (each to its digest) against the new: days, report, purse and hulls byte for byte (% bytes); no log; the same with the switch lit', length(v_a::text);

  -- ── LOG_HUMAN: a company's 6 raid days, new against old ──
  v_a := pg_temp.passage_56(v_hfl, v_sea, 6, v_t, false, false);
  v_b := pg_temp.passage_56(v_hfl, v_sea, 6, v_t, false, true);
  if (v_a - 'days' - 'events')::text is distinct from (v_b - 'days' - 'events')::text or jsonb_array_length(v_a -> 'days') is distinct from jsonb_array_length(v_b -> 'days') then
    raise exception 'PROOF 56 FAIL: a company''s raid passage with no order moved her purse, her ledger, her hulls or her path: % against %', v_a - 'days' - 'events', v_b - 'days' - 'events';
  end if;
  v_n := 0;
  for v_i in 0 .. jsonb_array_length(v_a -> 'days') - 1 loop
    v_r := v_a -> 'days' -> v_i;
    if ((v_r #- '{payload,fight,log}')::text) is distinct from (v_b -> 'days' -> v_i)::text then
      raise exception 'PROOF 56 FAIL: day % of a company''s raid, less its log, is not the old body''s: % against %', v_i + 1, v_r, v_b -> 'days' -> v_i;
    end if;
    continue when v_r ->> 'kind' is distinct from 'PIRATES';
    v_n := v_n + 1;
    v_log := v_r -> 'payload' -> 'fight' -> 'log';
    if v_log is null or (v_log ->> 'v')::int is distinct from 1 or jsonb_array_length(v_log -> 'r') is distinct from (v_r -> 'payload' -> 'fight' ->> 'rounds_fought')::int
       or v_log ? 'order' or v_log ? 'no_pay' or v_log ->> 'first' is distinct from v_r -> 'payload' -> 'fight' ->> 'first'
       or v_log -> 'you' -> 0 ->> 0 is distinct from 'Proof 56 jacht' or (v_log -> 'you' -> 0 ->> 2)::numeric is distinct from v_maxd
       or (v_log -> 'you' -> 0 ->> 1)::numeric - (v_log -> 'after' -> 0 ->> 1)::numeric is distinct from (v_r -> 'payload' -> 'fight' ->> 'hull_lost')::numeric
       or v_log -> 'foe' ->> 'n' is distinct from (select c.name from public.ship_classes c where c.code = public.wc_text('fight_raider_class'))
       or coalesce(v_log ->> 'end', '') not in ('STOOD', 'SLIP', 'BROKE', 'THREW', 'TERMS', 'TAKEN', 'GAVE')
       or exists (select 1 from jsonb_array_elements(v_log -> 'r') e where jsonb_array_length(e) is distinct from 14 or e -> 13 is distinct from 'null'::jsonb) then
      raise exception 'PROOF 56 FAIL: day % keeps no log, or not the fight''s own numbers: %', v_i + 1, v_r -> 'payload' -> 'fight';
    end if;
  end loop;
  -- the last day's `after` is the hull she arrived with
  if v_n is distinct from 6 or (v_log -> 'after' -> 0 ->> 1)::numeric is distinct from (v_a -> 'ships' -> 0 ->> 1)::numeric then
    raise exception 'PROOF 56 FAIL: % raid days, or the last log''s after (%) is not her hull (%)', v_n, v_log -> 'after', v_a -> 'ships';
  end if;
  -- the report: each fight entry carries the day's log and the day's losses; less those two keys it is the old body's entry
  v_x := (select e -> 'payload' from jsonb_array_elements(v_a -> 'events') e where e ->> 'kind' = 'VOYAGE_REPORT');
  v_p := (select e -> 'payload' from jsonb_array_elements(v_b -> 'events') e where e ->> 'kind' = 'VOYAGE_REPORT');
  if v_x is null or v_p is null or jsonb_array_length(v_x -> 'fights') is distinct from 6 or (v_x - 'fights')::text is distinct from (v_p - 'fights')::text
     or (select jsonb_agg(f - 'log' - 'loss' order by o) from jsonb_array_elements(v_x -> 'fights') with ordinality q(f, o))::text is distinct from (v_p -> 'fights')::text then
    raise exception 'PROOF 56 FAIL: the report, less each fight''s log and loss, is not the old body''s: % against %', v_x, v_p;
  end if;
  for v_i in 0 .. 5 loop
    v_r := v_a -> 'days' -> ((v_x -> 'fights' -> v_i ->> 'line')::int) -> 'payload';
    if v_x -> 'fights' -> v_i -> 'log' is distinct from v_r -> 'fight' -> 'log' or v_x -> 'fights' -> v_i -> 'rounds' is distinct from v_r -> 'rounds'
       or v_x -> 'fights' -> v_i -> 'loss' is distinct from jsonb_build_object('crew_before', v_r -> 'crew_before', 'crew', v_r -> 'crew_lost',
            'cargo', coalesce(v_r -> 'cargo_lost', '{}'::jsonb), 'ransom', 0) then
      raise exception 'PROOF 56 FAIL: the report''s fight % does not carry the day''s log and losses: % against the day %', v_i, v_x -> 'fights' -> v_i, v_r;
    end if;
  end loop;
  raise notice 'PASS: LOG_HUMAN — 6 raid days of a company: each keeps a log of its own rounds (ends %), `after` her hull (% at arrival), the report carries each log and loss; less the log, days and report are the old bodies'' word for word',
    (select string_agg(e -> 'payload' -> 'fight' -> 'log' ->> 'end', ' ' order by (e ->> 'd')::int) from jsonb_array_elements(v_a -> 'days') e where e ->> 'kind' = 'PIRATES'), v_a -> 'ships' -> 0 ->> 1;

  -- ── LOG_LATE: each order, day by day against once at the eta ──
  update public.world_config set value = 'true'::jsonb where key = 'raid_orders_enabled';
  perform cmd.assume_identity(c_uid);
  foreach v_ord in array array['FIGHT', 'FLEE', 'PAY'] loop
    v_r := cmd.raid_order(v_hfl, v_ord);
    if v_r is distinct from jsonb_build_object('ok', true, 'order', v_ord) then
      raise exception 'PROOF 56 FAIL: the door did not take %: %', v_ord, v_r;
    end if;
    v_a := pg_temp.passage_56(v_hfl, v_sea, 8, v_t, true, false);
    v_b := pg_temp.passage_56(v_hfl, v_sea, 8, v_t, false, false);
    if v_a is null or v_a::text is distinct from v_b::text then
      raise exception 'PROOF 56 FAIL: under % a passage settled day by day is not the passage settled once: % against %', v_ord, v_a, v_b;
    end if;
    if (select count(*) from jsonb_array_elements(v_a -> 'days') e where e ->> 'kind' = 'PIRATES') is distinct from 8
       or exists (select 1 from jsonb_array_elements(v_a -> 'path') e where e ->> 'order' is distinct from nullif(v_ord, 'FIGHT'))
       or exists (select 1 from jsonb_array_elements(v_a -> 'days') e
                   where e ->> 'kind' = 'PIRATES' and e -> 'payload' -> 'fight' -> 'log' ->> 'order' is distinct from nullif(v_ord, 'FIGHT')) then
      raise exception 'PROOF 56 FAIL: under % the path or a day''s log does not carry the order: %', v_ord, v_a -> 'path';
    end if;
    if v_ord = 'PAY' and (not exists (select 1 from jsonb_array_elements(v_a -> 'days') e where (e -> 'payload' ->> 'ransom_paid')::bigint > 0)
                          or not exists (select 1 from jsonb_array_elements(v_a -> 'ledger') l where l ->> 0 = 'RANSOM')) then
      raise exception 'PROOF 56 FAIL: eight Pay days paid nothing: %', v_a -> 'ledger';
    end if;
    if v_ord = 'FLEE' and not exists (select 1 from jsonb_array_elements(v_a -> 'days') e where jsonb_array_length(e -> 'payload' -> 'fight' -> 'log' -> 'r') > 0
                                                                                               and (e -> 'payload' -> 'fight' -> 'log' -> 'r' -> 0 ->> 13) is not null) then
      raise exception 'PROOF 56 FAIL: eight Flee days rolled no slip';
    end if;
  end loop;
  raise notice 'PASS: LOG_LATE — Fight, Flee and Pay: 8 raid days settled day by day and once at the eta are the same days, events, ledger, purse and hulls';

  -- ── ORDER_FROZEN: Flee, depart, Pay at sea ──
  perform cmd.raid_order(v_hfl, 'FLEE');
  v_p := pg_temp.through(v_hfl, v_sea, 2);
  v_voy := voyage.depart(v_hfl, v_p, v_lis, v_lis, v_t);
  v_a := (select o.path from public.voyages o where o.id = v_voy);
  if jsonb_array_length(v_a) is distinct from 2 or exists (select 1 from jsonb_array_elements(v_a) e where e ->> 'order' is distinct from 'FLEE' or not e ? 'danger')
     or (select jsonb_agg(e - 'order' order by o) from jsonb_array_elements(v_a) with ordinality q(e, o))::text is distinct from voyage.freeze_raiders(voyage.freeze_danger(v_p, v_t), v_hfl)::text then
    raise exception 'PROOF 56 FAIL: Flee was not frozen on each segment beside the danger, or something else moved: %', v_a;
  end if;
  v_r := cmd.raid_order(v_hfl, 'PAY');
  if v_r ->> 'order' is distinct from 'PAY' or (select o.path from public.voyages o where o.id = v_voy)::text is distinct from v_a::text then
    raise exception 'PROOF 56 FAIL: an order changed at sea moved the water behind';
  end if;
  v_purse := (select p.ducats from public.players p where p.id = v_hum);
  v_r := pg_temp.raid_day(v_hfl, v_voy, 1);
  if v_r -> 'fight' -> 'log' ->> 'order' is distinct from 'FLEE' or v_r ? 'ransom_paid' or (select p.ducats from public.players p where p.id = v_hum) is distinct from v_purse then
    raise exception 'PROOF 56 FAIL: the raid did not run the order she left under (Flee): %', v_r;
  end if;
  perform pg_temp.reach_port(v_hfl);
  perform pg_temp.refit_56(v_hfl);
  v_voy := voyage.depart(v_hfl, v_p, v_lis, v_lis, v_t + interval '1 hour');
  if exists (select 1 from jsonb_array_elements((select o.path from public.voyages o where o.id = v_voy)) e where e ->> 'order' is distinct from 'PAY') then
    raise exception 'PROOF 56 FAIL: the next voyage was not frozen Pay';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc ~* 'insert\s+into\s+public\.voyages\M' and p.oid is distinct from 'voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)'::regprocedure)
     or (select p.prosrc from pg_proc p where p.oid = 'voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)'::regprocedure) not like '%voyage.freeze_order(%' then
    raise exception 'PROOF 56 FAIL: a voyage is written somewhere that does not freeze the order (a turn would keep none)';
  end if;
  raise notice 'PASS: ORDER_FROZEN — left under Flee, changed to Pay at sea: the raid ran Flee and paid nothing; the next voyage is frozen Pay; voyage.depart alone writes a voyage';

  -- ── ORDER_PAY: this voyage is frozen Pay; three raid days through the real settle ──
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_ev := (select count(*) from public.events e where e.player_id = v_hum and e.kind = 'INSURANCE_PAID');
  v_w := pg_temp.w_56();
  v_take := public.raid_price(v_hfl);
  v_purse := (select p.ducats from public.players p where p.id = v_hum);
  v_r := pg_temp.raid_day(v_hfl, v_voy, 1);
  if v_r ->> 'outcome' is distinct from 'RANSOM' or (v_r ->> 'ransom_paid')::bigint is distinct from v_take or v_take is distinct from 1600 or (v_r -> 'fight' ->> 'paid')::boolean is not true
     or v_r -> 'fight' -> 'log' ->> 'end' is distinct from 'PAID' or v_r -> 'fight' -> 'log' ->> 'order' is distinct from 'PAY' or v_r -> 'fight' -> 'log' -> 'r' is distinct from '[]'::jsonb
     or v_r ->> 'prose' is distinct from 'We paid their price and they let us pass.' or (v_r ->> 'crew_lost')::numeric is distinct from 0 or v_r ? 'cargo_lost' or (v_r -> 'fight' ->> 'hull_lost')::numeric is distinct from 0
     or (v_r -> 'fight' ->> 'rounds_fought')::int is distinct from 0 or v_r ? 'pirate' then
    raise exception 'PROOF 56 FAIL: a Pay day is not RANSOM before a shot with the price paid: %', v_r;
  end if;
  if (select p.ducats from public.players p where p.id = v_hum) is distinct from v_purse - v_take
     or (select count(*) from public.treasury_flows f where f.id > v_mark) is distinct from 1
     or not exists (select 1 from public.treasury_flows f where f.id > v_mark and f.port_id = v_por and f.kind = 'RANSOM' and f.ducats = v_take and f.player_id = v_hum)
     or not exists (select 1 from public.ledger l where l.player_id = v_hum and l.kind = 'RANSOM' and l.ducats_delta = -v_take and l.balance_after = v_purse - v_take)
     or pg_temp.w_56() is distinct from v_w
     or (select s.durability from public.ships s where s.id = v_ship) is distinct from v_maxd or (select s.crew from public.ships s where s.id = v_ship) is distinct from 4
     or public.raid_price(v_hfl) is distinct from v_take
     or (select count(*) from public.events e where e.player_id = v_hum and e.kind = 'INSURANCE_PAID') is distinct from v_ev then
    raise exception 'PROOF 56 FAIL: the ransom did not move from her purse to Port Royal alone, or the day cost hull, hands, cargo or a claim';
  end if;
  -- a purse that cannot pay pays what it holds; the outcome is the same
  update public.players p set ducats = 100 where p.id = v_hum;
  v_w := pg_temp.w_56();
  v_r := pg_temp.raid_day(v_hfl, v_voy, 2);
  if v_r ->> 'outcome' is distinct from 'RANSOM' or (v_r ->> 'ransom_paid')::bigint is distinct from 100 or (select p.ducats from public.players p where p.id = v_hum) is distinct from 0 or pg_temp.w_56() is distinct from v_w
     or not exists (select 1 from public.treasury_flows f where f.id > v_mark and f.port_id = v_por and f.kind = 'RANSOM' and f.ducats = 100) then
    raise exception 'PROOF 56 FAIL: a short purse did not pay what it held: %', v_r;
  end if;
  -- an empty purse pays nothing and still passes (docs/COMBAT_LOG.md R4), and the report carries each day's ransom
  perform pg_temp.reach_port(v_hfl);
  v_x := (select e.payload from public.events e where e.player_id = v_hum and e.kind = 'VOYAGE_REPORT' and e.payload ->> 'voyage_id' = v_voy::text);
  if jsonb_array_length(v_x -> 'fights') is distinct from 2 or (v_x -> 'fights' -> 0 -> 'loss' ->> 'ransom')::bigint is distinct from 1600 or (v_x -> 'fights' -> 1 -> 'loss' ->> 'ransom')::bigint is distinct from 100
     or v_x -> 'fights' -> 0 -> 'log' ->> 'end' is distinct from 'PAID' then
    raise exception 'PROOF 56 FAIL: the report does not carry the two ransoms: %', v_x -> 'fights';
  end if;
  update public.players p set ducats = 300000 where p.id = v_hum;
  raise notice 'PASS: ORDER_PAY — RANSOM before a shot: 1,600 d. (8 per cent of 20,000 at cost) from her purse to Port Royal, kind RANSOM, W unchanged; no hull, hands, cargo or claim; a purse of 100 paid 100; the report carries both';

  -- ── ORDER_PAY_REFUSED: an empty hold; then no payee ──
  update public.ships s set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where s.id = v_ship;
  v_voy := voyage.depart(v_hfl, v_p, v_lis, v_lis, v_t + interval '2 hours');
  v_purse := (select p.ducats from public.players p where p.id = v_hum);
  v_r := pg_temp.raid_day(v_hfl, v_voy, 1);
  if v_r ? 'ransom_paid' or v_r -> 'fight' ? 'paid' or v_r -> 'fight' -> 'log' ->> 'no_pay' is distinct from 'EMPTY' or v_r -> 'fight' -> 'log' ? 'order'
     or not exists (select 1 from jsonb_array_elements_text(v_r -> 'rounds') t where t = 'You have nothing aboard to pay them with.')
     or (v_r -> 'fight' ->> 'rounds_fought')::int < 1 or (select p.ducats from public.players p where p.id = v_hum) is distinct from v_purse then
    raise exception 'PROOF 56 FAIL: Pay with an empty hold was not refused into a fight: %', v_r;
  end if;
  perform pg_temp.refit_56(v_hfl);
  update public.world_config set value = 'false'::jsonb where key = 'city_treasury_enabled';
  v_r := pg_temp.raid_day(v_hfl, v_voy, 2);
  if public.raid_payee(null) is not null or v_r ? 'ransom_paid' or v_r -> 'fight' ? 'paid' or v_r -> 'fight' -> 'log' ->> 'no_pay' is distinct from 'NO_PAYEE'
     or not exists (select 1 from jsonb_array_elements_text(v_r -> 'rounds') t where t = 'They will take no ransom.')
     or (select p.ducats from public.players p where p.id = v_hum) is distinct from v_purse then
    raise exception 'PROOF 56 FAIL: Pay with no payee was not refused into a fight: %', v_r;
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
  perform pg_temp.reach_port(v_hfl);
  raise notice 'PASS: ORDER_PAY_REFUSED — an empty hold (EMPTY) and the purses dark (NO_PAYEE): she fought (% and % rounds), nothing was paid, the log says why', 'day 1', v_r -> 'fight' ->> 'rounds_fought';

  -- ── ORDER_FLEE: day after day through the real settle, her hull and hands made good before each ──
  perform cmd.raid_order(v_hfl, 'FLEE');
  perform pg_temp.refit_56(v_hfl);
  v_voy := voyage.depart(v_hfl, pg_temp.through(v_hfl, v_sea, 40), v_lis, v_lis, v_t + interval '3 hours');
  for v_i in 1 .. 40 loop
    perform pg_temp.refit_56(v_hfl);
    v_r := pg_temp.raid_day(v_hfl, v_voy, v_i);
    v_log := v_r -> 'fight' -> 'log';
    v_hull := (select s.durability from public.ships s where s.id = v_ship);
    if v_log ->> 'order' is distinct from 'FLEE' or (v_log -> 'after' -> 0 ->> 1)::numeric is distinct from v_hull or v_r -> 'fight' -> 'hits' ->> 'yours' is distinct from '0'
       or exists (select 1 from jsonb_array_elements(v_log -> 'r') e where (e ->> 3)::int is distinct from 0 or (e ->> 13)::numeric is distinct from round(public.fight_flee_chance(10 - 11), 4))
       or (jsonb_array_length(v_log -> 'r') > 0 and not exists (select 1 from jsonb_array_elements_text(v_r -> 'rounds') t where t like 'Round 1 %you run before them%')) then
      raise exception 'PROOF 56 FAIL: Flee day %: she fired, the chance is not the rule''s, or `after` is not her hull (%): %', v_i, v_hull, v_r;
    end if;
    if coalesce((v_r -> 'fight' ->> 'fled')::boolean, false) then
      v_fled := v_fled + 1;
      if v_r ->> 'outcome' is distinct from 'EVADED' or v_log ->> 'end' is distinct from 'FLED' or v_r ->> 'prose' is distinct from 'We ran, and got clear of them.' or (v_r ->> 'crew_lost')::numeric is distinct from 0 or v_r ? 'cargo_lost'
         or v_log ? 'board' or v_maxd - v_hull is distinct from (v_r -> 'fight' ->> 'hull_lost')::numeric then
        raise exception 'PROOF 56 FAIL: a flight that got away (day %) is not EVADED with her hull and hands as the fire left them: %', v_i, v_r;
      end if;
    else
      v_caught := v_caught + 1;
      if coalesce(v_log ->> 'end', '') not in ('THREW', 'TERMS', 'TAKEN', 'GAVE') or not v_log ? 'board' or jsonb_array_length(v_log -> 'r') is distinct from jsonb_array_length(public.wc('fight_ranges'))
         or coalesce(v_r ->> 'outcome', '') not in ('DRIVEN_OFF', 'RANSOM', 'PLUNDERED') then
        raise exception 'PROOF 56 FAIL: a flight that was caught (day %) was not boarded after every round: %', v_i, v_r;
      end if;
    end if;
  end loop;
  if v_fled = 0 or v_caught = 0 then
    raise exception 'PROOF 56 FAIL: 40 Flee days met % away and % caught: both are needed', v_fled, v_caught;
  end if;
  perform pg_temp.reach_port(v_hfl);
  raise notice 'PASS: ORDER_FLEE — 40 raid days of a gunless jacht under Flee (% a round): % away (EVADED, fled, no hands lost, her hull the log''s after), % caught and boarded after six rounds',
    round(public.fight_flee_chance(10 - 11), 4), v_fled, v_caught;

  -- ── ORDER_DARK: the switch off ──
  perform pg_temp.refit_56(v_hfl);
  perform cmd.raid_order(v_hfl, 'PAY');
  v_voy := voyage.depart(v_hfl, v_p, v_lis, v_lis, v_t + interval '6 hours');   -- frozen Pay, lit
  update public.world_config set value = 'false'::jsonb where key = 'raid_orders_enabled';
  v_purse := (select p.ducats from public.players p where p.id = v_hum);
  v_r := cmd.raid_order(v_hfl, 'FIGHT');
  if v_r ->> 'error_code' is distinct from 'E_NOT_IN_USE' or (select o.raid_order from public.fleet_raid_orders o where o.fleet_id = v_hfl) is distinct from 'PAY'
     or world.raid_read(v_hfl) is distinct from '{"on": false}'::jsonb or voyage.leg_order((select o.path -> 0 from public.voyages o where o.id = v_voy)) is not null then
    raise exception 'PROOF 56 FAIL: dark, the door or the read answered, or a frozen order was read: %', v_r;
  end if;
  v_r := pg_temp.raid_day(v_hfl, v_voy, 1);
  if v_r ? 'ransom_paid' or v_r -> 'fight' ? 'paid' or v_r -> 'fight' -> 'log' ? 'order' or v_r -> 'fight' -> 'log' ? 'no_pay' or (v_r -> 'fight' ->> 'rounds_fought')::int < 1
     or (select p.ducats from public.players p where p.id = v_hum) is distinct from v_purse then
    raise exception 'PROOF 56 FAIL: dark, an order frozen while lit was still obeyed: %', v_r;
  end if;
  perform pg_temp.reach_port(v_hfl);
  perform pg_temp.refit_56(v_hfl);
  v_voy := voyage.depart(v_hfl, v_p, v_lis, v_lis, v_t + interval '7 hours');
  if (select o.path from public.voyages o where o.id = v_voy)::text is distinct from voyage.freeze_raiders(voyage.freeze_danger(v_p, v_t + interval '7 hours'), v_hfl)::text then
    raise exception 'PROOF 56 FAIL: dark, with an order row standing, a departure''s path is not 0339''s byte for byte';
  end if;
  perform pg_temp.reach_port(v_hfl);
  raise notice 'PASS: ORDER_DARK — off: the door refuses (E_NOT_IN_USE) and keeps the row, the read says off, a path frozen Pay is fought as Fight, a new path carries no order';

  -- ── ORDER_DOOR ──
  if cmd.raid_order(v_hfl, 'FLEE') ->> 'error_code' is distinct from 'E_NOT_IN_USE' then
    raise exception 'PROOF 56 FAIL: dark, the door did not refuse';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'raid_orders_enabled';
  if cmd.raid_order(v_ofl, 'FLEE') ->> 'error_code' is distinct from 'E_NO_SUCH_FLEET' or cmd.raid_order(v_nfl, 'PAY') ->> 'error_code' is distinct from 'E_NO_SUCH_FLEET'
     or cmd.raid_order(gen_random_uuid(), 'FLEE') ->> 'error_code' is distinct from 'E_NO_SUCH_FLEET' or cmd.raid_order(null, 'FLEE') ->> 'error_code' is distinct from 'E_NO_SUCH_FLEET'
     or cmd.raid_order(v_hfl, 'RUN') ->> 'error_code' is distinct from 'E_BAD_ORDER' or cmd.raid_order(v_hfl, 'flee') ->> 'error_code' is distinct from 'E_BAD_ORDER' or cmd.raid_order(v_hfl, null) ->> 'error_code' is distinct from 'E_BAD_ORDER'
     or world.raid_read(v_ofl) is distinct from '{"on": false}'::jsonb or world.raid_read(v_nfl) is distinct from '{"on": false}'::jsonb
     or (select o.raid_order from public.fleet_raid_orders o where o.fleet_id = v_hfl) is distinct from 'PAY'
     or exists (select 1 from public.fleet_raid_orders o where o.fleet_id is distinct from v_hfl) then
    raise exception 'PROOF 56 FAIL: another company''s fleet or a bad word was taken, or a refusal moved a row';
  end if;
  v_r := world.raid_read(v_hfl);
  if (v_r ->> 'on')::boolean is not true or v_r ->> 'order' is distinct from 'PAY' or (v_r ->> 'guns')::boolean is not false or v_r ->> 'slip' is distinct from 'fair' or (v_r ->> 'pay')::bigint is distinct from 1600
     or (select count(*) from jsonb_array_elements(v_r -> 'foes') e where e ->> 'word' in ('weaker', 'even', 'stronger', 'far_stronger') and (e ->> 'danger')::int between 1 and 5) is distinct from jsonb_array_length(v_r -> 'foes')
     or coalesce(jsonb_array_length(v_r -> 'foes'), 0) < 1 then
    raise exception 'PROOF 56 FAIL: the read of a gunless jacht with 20,000 d. aboard under Pay: %', v_r;
  end if;
  v_x := cmd.raid_order(v_hfl, 'FIGHT');
  if v_x is distinct from '{"ok": true, "order": "FIGHT"}'::jsonb or exists (select 1 from public.fleet_raid_orders) or world.raid_read(v_hfl) ->> 'order' is distinct from 'FIGHT' then
    raise exception 'PROOF 56 FAIL: Fight left a row: %', v_x;
  end if;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  if cmd.raid_order(v_hfl, 'FLEE') ->> 'error_code' is distinct from 'E_NO_HOUSE' or world.raid_read(v_hfl) is distinct from '{"on": false}'::jsonb or exists (select 1 from public.fleet_raid_orders) then
    raise exception 'PROOF 56 FAIL: a caller with no house set or read an order';
  end if;
  if has_function_privilege('anon', 'cmd.raid_order(uuid,text)', 'execute') or has_function_privilege('anon', 'world.raid_read(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'cmd.raid_order(uuid,text)', 'execute') or not has_function_privilege('authenticated', 'world.raid_read(uuid)', 'execute')
     or (select count(*) from public.client_rpc_entry_points() e where (e.schema_name, e.function_name) in (('cmd', 'raid_order'), ('world', 'raid_read')) and e.fn is not null) is distinct from 2
     or has_table_privilege('authenticated', 'public.fleet_raid_orders', 'select,insert,update,delete') then
    raise exception 'PROOF 56 FAIL: anon can call a door, authenticated cannot, a door is not a client entry point, or a client can touch the table';
  end if;
  raise notice 'PASS: ORDER_DOOR — E_NO_HOUSE, E_NOT_IN_USE, E_NO_SUCH_FLEET (another company''s, a merchant''s, none), E_BAD_ORDER; the read: %; Fight leaves no row; anon cannot call; both doors registered', v_r - 'foes';
end
$p$;
