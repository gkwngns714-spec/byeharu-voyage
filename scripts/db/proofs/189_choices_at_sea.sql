-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 189 - CHOICES AT SEA  (migration 0486; docs/design/roadmap-2026-11-23.md slice 16; docs/dev-log/2026-11-23-sea-choices.md)
--
--   The migration's self-assert sets an event, takes her pick and settles it at her arrival. This proof holds the rest: the voyage's own
--   settle is the same with the switch lit and dark (every day's event, to the byte), and settled in one call or day by day; the end of a
--   choice is the same however and whenever it is settled; the odds served are the odds drawn (2,000 voyages); a loss larger than her purse
--   takes what she has; a pick at her arrival is refused; the cost of a departure, an arrival and the read. Rolled back by proof.mjs.
--   NO TIME-BUDGETED READ IS ASKED. THE DAY: every sailing scene starts at 01:00 UTC of the day it runs, so none straddles a UTC midnight.
--
-- @pass SC_SETTLE_SAME   the voyage's days (voyage_events) are byte-identical lit and dark, and in one settle or day by day; the choice's end too
-- @pass SC_ODDS          over 2,000 voyages the good ends match each option's served odds (within 0.04), and the chance and the kinds' mix
-- @pass SC_PURSE         a loss larger than her purse takes what she has: the amount cut, the full loss kept on the record
-- @pass SC_LATE          a pick at her arrival, or after it, is refused E_TOO_LATE; before it is shown, E_NO_CHOICE
-- @pass SC_COST          a lit departure's plan, a lit arrival's settle, a dark arrival's probe and the read, timed
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a     constant uuid := '00000000-0486-4000-8000-0000000001a1';
  v_day   timestamptz := date_trunc('day', now() at time zone 'utc') at time zone 'utc';
  v_lis   uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_to    uuid;
  v_tocode text;
  v_good  text;
  v_a     uuid;
  v_fa    uuid;
  v_vy    uuid;
  v_eta   timestamptz;
  v_dep   timestamptz := v_day + interval '1 hour';
  v_segs  jsonb;
  v_days  int;
  v_dark  text;
  v_lit   text;
  v_step  text;
  v_end1  jsonb;
  v_end2  jsonb;
  v_c     public.sea_choices%rowtype;
  v_opt   jsonb;
  v_r     jsonb;
  v_n     int;
  v_good_n int;
  v_p     numeric;
  v_rate  numeric;
  v_kinds jsonb;
  v_t     timestamptz;
  v_ms1   numeric;
  v_ms2   numeric;
  v_ms3   numeric;
  v_ms4   numeric;
  v_lived boolean;
  d       int;
begin
  v_a := public.new_house(c_a, 'Casa do Mar 189', 'PRT');
  select f.id into v_fa from public.fleets f where f.player_id = v_a;
  update public.players set ducats = 200000 where id = v_a;
  update public.fleets set status = 'DOCKED', port_id = v_lis, lat = null, lon = null where id = v_fa;
  select g.code into v_good from public.goods g where g.bulk > 0 order by g.bulk, g.code limit 1;
  update public.ships set water_t = 500, food_t = 500, cargo = jsonb_build_object(v_good, 100), cargo_basis = jsonb_build_object(v_good, 500) where fleet_id = v_fa;
  -- the farthest harbour within 1,500 miles of Lisbon with a stored course: several days at sea
  select r.port_id, r.code into v_to, v_tocode
    from voyage.reach_from(v_lis) r join public.ports p on p.id = r.port_id and p.kind = 'HARBOUR'
   where r.nm between 600 and 1500 and public.sea_course(v_lis, r.port_id) is not null
   order by r.nm desc, r.code limit 1;
  v_segs := voyage.segments_from_course(public.sea_course(v_lis, v_to));
  update public.world_config set value = 'true'::jsonb where key = 'sea_choices_enabled';
  update public.world_config set value = to_jsonb(1) where key = 'sea_choices_chance';
  update public.world_config set value = to_jsonb(0) where key = 'sea_choices_trip_min_s';

  -- ── SC_COST (1): a lit departure's plan ──
  v_t := clock_timestamp();
  v_vy := voyage.depart(v_fa, v_segs, v_lis, v_to, v_dep);
  v_ms1 := round(extract(epoch from clock_timestamp() - v_t) * 1000, 2);
  select * into v_c from public.sea_choices c where c.voyage_id = v_vy;
  select v.eta into v_eta from public.voyages v where v.id = v_vy;
  v_days := voyage.total_days(v_vy);
  if v_c.voyage_id is null or v_days < 2 then
    raise exception 'SC: no event was set, or the trip to % is under two sea days (%)', v_tocode, v_days;
  end if;
  -- her pick: the last option (never the safe one)
  v_opt := v_c.options->(jsonb_array_length(v_c.options) - 1);
  perform public.sea_choice_pick(v_a, v_vy, v_opt->>'key', v_c.appears_at + interval '1 second');

  -- ── SC_SETTLE_SAME: the same voyage settled three ways, each rolled back: dark in one call, lit in one call, lit day by day ──
  begin
    update public.world_config set value = 'false'::jsonb where key = 'sea_choices_enabled';
    perform voyage.settle(v_fa, v_eta + interval '1 second');
    select md5(string_agg(e.day_index || ':' || e.kind || ':' || e.payload::text || ':' || e.resolved_at::text, '|' order by e.day_index)) into v_dark
      from public.voyage_events e where e.voyage_id = v_vy;
    if exists (select 1 from public.events e where e.player_id = v_a and e.kind = 'SEA_CHOICE') then
      raise exception 'SC: dark, the arrival settled a choice';
    end if;
    raise exception using errcode = 'ZP189';
  exception when sqlstate 'ZP189' then null;
  end;
  begin
    v_t := clock_timestamp();
    perform voyage.settle(v_fa, v_eta + interval '1 second');
    v_ms2 := round(extract(epoch from clock_timestamp() - v_t) * 1000, 2);
    select md5(string_agg(e.day_index || ':' || e.kind || ':' || e.payload::text || ':' || e.resolved_at::text, '|' order by e.day_index)) into v_lit
      from public.voyage_events e where e.voyage_id = v_vy;
    select c.outcome into v_end1 from public.sea_choices c where c.voyage_id = v_vy;
    raise exception using errcode = 'ZP189';
  exception when sqlstate 'ZP189' then null;
  end;
  begin
    for d in 1 .. v_days loop
      perform voyage.settle(v_fa, voyage.day_ends_at(v_vy, d) + interval '1 second');
    end loop;
    perform voyage.settle(v_fa, v_eta + interval '1 day');
    select md5(string_agg(e.day_index || ':' || e.kind || ':' || e.payload::text || ':' || e.resolved_at::text, '|' order by e.day_index)) into v_step
      from public.voyage_events e where e.voyage_id = v_vy;
    select c.outcome into v_end2 from public.sea_choices c where c.voyage_id = v_vy;
    raise exception using errcode = 'ZP189';
  exception when sqlstate 'ZP189' then null;
  end;
  if v_dark is null or v_dark <> v_lit or v_lit <> v_step or v_end1 is null or v_end1 <> v_end2
     or v_end1->>'option' <> v_opt->>'key' or (v_end1->>'full')::bigint <> (public.sea_choice_result(v_vy, v_opt)->>'amount')::bigint then
    raise exception 'SC: the settle is not the same three ways: % / % / % ; % / %', v_dark, v_lit, v_step, v_end1, v_end2;
  end if;
  raise notice 'PASS: SC_SETTLE_SAME — LIS-% (% sea days): voyage_events % dark = lit = day by day; % % -> % (the same in one call and day by day)',
    v_tocode, v_days, left(v_lit, 8), v_c.kind, v_opt->>'key', v_end1->>'amount';

  -- ── SC_ODDS: 2,000 voyages' draws against the served odds, the chance and the kinds ──
  for v_opt in select e from jsonb_array_elements(public.sea_choice_options('wreck', 1000, 1, 0)
                                                  || public.sea_choice_options('sail', 1000, 3, 20)
                                                  || public.sea_choice_options('storm', 1000, 3, 0)) e
                where (e->>'p')::numeric < 1 loop
    v_p := (v_opt->>'p')::numeric;
    select count(*) filter (where (public.sea_choice_result(u.v, v_opt)->>'good')::boolean) into v_good_n
      from (select md5('189:' || g)::uuid as v from generate_series(1, 2000) g) u;
    if abs(v_good_n / 2000.0 - v_p) > 0.04 then
      raise exception 'SC: option % at odds % came good % of 2,000', v_opt->>'key', v_p, v_good_n;
    end if;
  end loop;
  select count(*) filter (where voyage.rng(u.v, 0, 'sea_choice') < 0.35) / 2000.0,
         jsonb_build_object('storm', count(*) filter (where voyage.rng(u.v, 0, 'sea_choice_kind') < 0.40),
                            'wreck', count(*) filter (where voyage.rng(u.v, 0, 'sea_choice_kind') >= 0.40 and voyage.rng(u.v, 0, 'sea_choice_kind') < 0.75),
                            'sail', count(*) filter (where voyage.rng(u.v, 0, 'sea_choice_kind') >= 0.75))
    into v_rate, v_kinds
    from (select md5('189k:' || g)::uuid as v from generate_series(1, 2000) g) u;
  if abs(v_rate - 0.35) > 0.04 or abs((v_kinds->>'storm')::int / 2000.0 - 0.40) > 0.04 or abs((v_kinds->>'sail')::int / 2000.0 - 0.25) > 0.04 then
    raise exception 'SC: the chance % or the kinds % are not as served', v_rate, v_kinds;
  end if;
  raise notice 'PASS: SC_ODDS — every option of wreck, sail and storm within 0.04 of its odds over 2,000 voyages; met % (0.35); kinds %', round(v_rate, 3), v_kinds;

  -- ── SC_LATE: a pick at or after her arrival is refused; before it is shown, refused ──
  begin
    perform public.sea_choice_pick(v_a, v_vy, v_opt->>'key', v_eta);
    raise exception 'SC: a pick at her arrival was taken';
  exception when others then
    if sqlerrm not like 'E_TOO_LATE:%' then raise; end if;
  end;
  begin
    perform public.sea_choice_pick(v_a, v_vy, (v_c.options->0)->>'key', v_c.appears_at - interval '1 second');
    raise exception 'SC: a pick before the event was shown was taken';
  exception when others then
    if sqlerrm not like 'E_NO_CHOICE:%' then raise; end if;
  end;
  raise notice 'PASS: SC_LATE — at her arrival E_TOO_LATE; before the event is shown E_NO_CHOICE';

  -- ── SC_PURSE: a loss larger than her purse takes what she has ──
  v_lived := false;
  begin
    update public.players set ducats = 100 where id = v_a;
    -- the worst bad end of her options, forced: the option's odds set to 0 on her row
    update public.sea_choices set options = jsonb_build_array(jsonb_build_object('key', 'shelter', 'p', 1, 'win', -1250, 'lose', -1250, 'ev', -1250, 'safe', true)),
                                  chosen = null where voyage_id = v_vy;
    perform voyage.settle(v_fa, v_eta + interval '1 second');
    select * into v_c from public.sea_choices c where c.voyage_id = v_vy;
    if v_c.state <> 'settled' or (v_c.outcome->>'amount')::bigint <> -100 or (v_c.outcome->>'full')::bigint <> -1250
       or (select coalesce(sum(l.ducats_delta), 0) from public.ledger l where l.player_id = v_a and l.kind = 'SEA_LOSS') <> -100 then
      raise exception 'SC: the loss was not cut to her purse: %', v_c.outcome;
    end if;
    v_lived := true;
    raise exception using errcode = 'ZP189';
  exception when sqlstate 'ZP189' then null;
  end;
  if not v_lived then raise exception 'SC: the purse scene did not run'; end if;
  raise notice 'PASS: SC_PURSE — purse 100, loss 1,250: 100 taken (SEA_LOSS -100), full -1,250 on the record';

  -- ── SC_COST (2): a dark arrival's probe and the read ──
  begin
    update public.world_config set value = 'false'::jsonb where key = 'sea_choices_enabled';
    v_t := clock_timestamp();
    for d in 1 .. 200 loop perform public.sea_choice_settle(v_vy); end loop;
    v_ms3 := round(extract(epoch from clock_timestamp() - v_t) * 1000 / 200, 4);
    raise exception using errcode = 'ZP189';
  exception when sqlstate 'ZP189' then null;
  end;
  perform cmd.assume_identity(c_a);
  v_t := clock_timestamp();
  for d in 1 .. 50 loop v_r := world.sea_choices(); end loop;
  v_ms4 := round(extract(epoch from clock_timestamp() - v_t) * 1000 / 50, 3);
  raise notice 'PASS: SC_COST — lit departure % ms (voyage.depart whole); lit arrival % ms (voyage.settle whole, % days); dark settle probe % ms; read % ms',
    v_ms1, v_ms2, v_days, v_ms3, v_ms4;
end
$p$;
