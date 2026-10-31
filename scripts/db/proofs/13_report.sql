-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 13 — THE REPORT ADDS UP  (migration 0286, docs/COMMAND_REDESIGN.md §4; owner rows 192, 244)
--
-- WHAT THIS PROOF IS FOR, AND WHY IT IS NOT THE MIGRATION'S SELF-ASSERT AGAIN
--   0286 proves in its own transaction, as the owner and on planted rows, every section, the point
--   partition, the span boundary, the empty shape and the registry/grant changes. It cannot prove
--   what a PLAYER meets:
--
--     1. THE DOOR. A player is `authenticated`: world.report must answer through the granted entry
--        point, world.books — the door 0286 retires — must be refused 42501, and an unknown span
--        must be refused rather than defaulted.
--     2. THE REAL WRITER'S POINTS. Rows the one money mover public.credit writes carry 0284's
--        points: a receipt while docked reads its PORT, a receipt while SAILING reads its VOYAGE
--        (the from/to codes and the departure game day), and a receipt with no ref event reads
--        EARLIER. The report groups them into a partition, so the places sum to the sections.
--     3. THE PURSE IS THE TOTAL. With every row a real credit, the report's total equals the
--        purse's change over the span (FOUNDING excluded; a PROBE row never served, though its
--        money did move the purse — asserted separately).
--     4. THE CLOCK. A row planted 1 s before today's game-day boundary is outside Day; a row at
--        the exact start of today−6 is inside Week; at the exact start of today−7 it is outside
--        Week but inside All. The axes are 1 / 7 / folded entries, zero-filled, each summing to
--        its span's total.
--     5. THE EMPTY SHAPE. A fresh house has made nothing: total 0, eight empty sections, no
--        places, [today 0] / seven zeros / no days.
--
-- Everything rolls back with proof.mjs's transaction; every row read is this probe's own (player
-- id, its voyage id, its PROBE_13 kind). Nothing counts or sums a growing table.
--
-- @pass REPORT_DOOR      as authenticated the read answers through the door, and world.books (retired 0286) is refused 42501; an unknown span is refused
-- @pass REPORT_EMPTY     a fresh house's report is the empty shape: total 0, eight empty sections, no places, [today 0] / seven zeros / no days
-- @pass REPORT_SECTIONS  through public.credit's real rows: each kind stands in its design section, the sections are their lines, and the total is the purse's change less the hidden PROBE row
-- @pass REPORT_POINTS    a docked receipt reads its port, an at-sea receipt reads its voyage (codes + departure day), the no-point rows read Earlier LAST, and the places sum to the sections
-- @pass REPORT_SPANS     the exact game-day boundary splits Day / Week / All; the axes are 1 / 7 / folded zero-filled entries summing to their totals
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_uid   constant uuid := '00000000-0f13-4000-8000-000000000001';
  c_nil   constant uuid := '00000000-0000-0000-0000-000000000000';
  v_p     uuid;
  v_f     uuid;
  v_lis   uuid;
  v_fnc   uuid;
  v_voy   uuid;
  v_e     uuid;
  v_today int;
  v_gds   numeric;
  v_start timestamptz;
  v_voy_day int;
  v_p0    bigint;
  v_p1    bigint;
  v_mid   jsonb;
  v_day   jsonb;
  v_week  jsonb;
  v_all   jsonb;
  v_empty jsonb;
  v_empty_week jsonb;
  v_empty_all jsonb;
  v_sec   jsonb;
  v_sum   bigint;
  v_bad_read boolean := false;
  v_bad_span boolean := false;
begin
  -- ── THE PRECONDITIONS THIS PROOF OWNS ────────────────────────────────────────────────────────
  update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
  select id into v_lis from public.ports where code = 'LIS';
  select id into v_fnc from public.ports where code = 'FNC';
  v_p := public.new_house(c_uid, 'Casa do Relatorio 0f13', 'PRT', 'LIS');
  select f.id into v_f from public.fleets f where f.player_id = v_p;
  v_today := world.game_day();
  v_gds   := public.wc_num('game_day_seconds');
  v_start := to_timestamp((v_today * v_gds)::double precision);
  perform cmd.assume_identity(c_uid);

  -- ── 1. THE DOOR ──────────────────────────────────────────────────────────────────────────────
  v_empty      := world.report('day');
  v_empty_week := world.report('week');
  v_empty_all  := world.report('all');
  set local role authenticated;
  v_mid := world.report('day');
  begin
    perform world.books(7);
  exception when insufficient_privilege then v_bad_read := true;
  end;
  begin
    perform world.report('month');
  exception when others then v_bad_span := true;
  end;
  reset role;
  if v_bad_read is not true or v_bad_span is not true
     or (v_mid->>'span') <> 'day' or (v_mid->>'total')::bigint <> 0 then
    raise exception 'PROOF 13 FAILED: the door — report served %, books refused %, an unknown span refused %',
      v_mid, v_bad_read, v_bad_span;
  end if;
  raise notice 'PASS: REPORT_DOOR — as authenticated world.report(''day'') answered (span day, total 0) and world.books(7) was refused 42501; an unknown span was refused';

  -- ── 2. THE EMPTY SHAPE ───────────────────────────────────────────────────────────────────────
  if (v_empty->>'total')::bigint <> 0
     or (v_empty->>'game_day')::int <> v_today
     or jsonb_array_length(v_empty->'sections') <> 8
     or exists (select 1 from jsonb_array_elements(v_empty->'sections') s
                 where (s->>'ducats')::bigint <> 0 or jsonb_array_length(s->'lines') <> 0)
     or jsonb_array_length(v_empty->'places') <> 0
     or jsonb_array_length(v_empty->'days') <> 1
     or (v_empty->'days'->0->>'net')::bigint <> 0 then
    raise exception 'PROOF 13 FAILED: a fresh house''s Day report is not the empty shape: %', v_empty;
  end if;
  if jsonb_array_length(v_empty_week->'days') <> 7
     or exists (select 1 from jsonb_array_elements(v_empty_week->'days') d where (d->>'net')::bigint <> 0)
     or jsonb_array_length(v_empty_all->'days') <> 0
     or jsonb_array_length(v_empty_all->'places') <> 0 then
    raise exception 'PROOF 13 FAILED: the empty Week/All axes are not 7 zeros / no days: % / %', v_empty_week, v_empty_all;
  end if;
  raise notice 'PASS: REPORT_EMPTY — a fresh house reads total 0, eight empty sections, no places, one zero Day, seven zero Week days and an empty All axis (its starting money is capital)';

  -- ── 3. THE SECTIONS, THROUGH THE REAL WRITER AND ITS POINTS ─────────────────────────────────
  v_p0 := (select ducats from public.players where id = v_p);

  -- DOCKED: an event naming her fleet lets 0284's trigger fill the fleet and the PORT.
  v_e := public.emit_event(v_p, 'PROBE_13', jsonb_build_object('fleet', 'Gaivota'));
  perform public.credit(v_p, 'SELL', 250, v_e);

  -- AT SEA: a SAILING voyage; the same event now fills the fleet and the VOYAGE, with no port.
  v_voy := gen_random_uuid();
  insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status,
                              origin_port_id, dest_port_id, created_at)
  values (v_voy, v_f, v_p, '[]', 100, '{}', now() - interval '1 day', now() + interval '1 day', 'SAILING',
          v_lis, v_fnc, now() - interval '1 day');
  update public.fleets set status = 'SAILING', port_id = null where id = v_f;
  v_voy_day := world.game_day(now() - interval '1 day');
  v_e := public.emit_event(v_p, 'PROBE_13', jsonb_build_object('fleet', 'Gaivota'));
  perform public.credit(v_p, 'INSURANCE_PAID', 300, v_e);

  -- THE NO-EVENT ROWS (points null by 0284's rule): every design section has its witness.
  perform public.credit(v_p, 'BUY',        -200);
  perform public.credit(v_p, 'TAX',         -50);
  perform public.credit(v_p, 'PORT_FEE',    -60);   -- the city-visit fee: INSIDE Trade, never its own section
  perform public.credit(v_p, 'WAGES',       -30);
  perform public.credit(v_p, 'HIRE',        -20);
  perform public.credit(v_p, 'PROVISION',   -70);
  perform public.credit(v_p, 'REPAIR',      -40);
  perform public.credit(v_p, 'INSURANCE',   -90);
  perform public.credit(v_p, 'SHARE',      -400);
  perform public.credit(v_p, 'DIVIDEND',    100);
  perform public.credit(v_p, 'DONATION',    -60);
  perform public.credit(v_p, 'BUILD',     -1000);
  perform public.credit(v_p, 'TUITION',     -80);
  perform public.credit(v_p, 'TOW',         -25);
  perform public.credit(v_p, 'GRANT',        55);   -- an unlisted kind: Other, under its own name
  perform public.credit(v_p, 'PROBE_13',    999);   -- money that moved, but never served

  v_p1 := (select ducats from public.players where id = v_p);
  v_day := world.report('day');
  if v_p1 - v_p0 <> -421 then
    raise exception 'PROOF 13 FAILED: the purse moved %, not −421', v_p1 - v_p0;
  end if;
  if (v_day->>'total')::bigint <> -1420 then
    raise exception 'PROOF 13 FAILED: the report total is %, not −1,420 (the hidden PROBE row must not move it)', v_day->>'total';
  end if;
  select jsonb_object_agg(s->>'id', (s->>'ducats')::bigint) into v_sec
    from jsonb_array_elements(v_day->'sections') s;
  if (v_sec->>'trade')::bigint <> -60 or (v_sec->>'crew')::bigint <> -50
     or (v_sec->>'supplies')::bigint <> -70 or (v_sec->>'repairs')::bigint <> -40
     or (v_sec->>'insurance')::bigint <> 210 or (v_sec->>'invest')::bigint <> -360
     or (v_sec->>'ships')::bigint <> -1000 or (v_sec->>'other')::bigint <> -50 then
    raise exception 'PROOF 13 FAILED: a section''s sum is wrong: %', v_sec;
  end if;
  if exists (select 1 from jsonb_array_elements(v_day->'sections') s
              where coalesce((select sum((l->>'ducats')::bigint) from jsonb_array_elements(s->'lines') l), 0) <> (s->>'ducats')::bigint) then
    raise exception 'PROOF 13 FAILED: a section is not the sum of its lines';
  end if;
  select coalesce(sum((s->>'ducats')::bigint), 0) into v_sum from jsonb_array_elements(v_day->'sections') s;
  if v_sum <> (v_day->>'total')::bigint then
    raise exception 'PROOF 13 FAILED: the sections do not sum to the total';
  end if;
  if not exists (select 1 from jsonb_array_elements(v_day->'sections') s, jsonb_array_elements(s->'lines') l
                  where s->>'id' = 'other' and l->>'kind' = 'GRANT' and (l->>'ducats')::bigint = 55 and l->>'word' = 'Grant')
     or not exists (select 1 from jsonb_array_elements(v_day->'sections') s, jsonb_array_elements(s->'lines') l
                  where s->>'id' = 'trade' and l->>'kind' = 'PORT_FEE' and (l->>'ducats')::bigint = -60 and l->>'word' = 'Port fee')
     or exists (select 1 from jsonb_array_elements(v_day->'sections') s, jsonb_array_elements(s->'lines') l
                 where l->>'kind' = 'PROBE_13') then
    raise exception 'PROOF 13 FAILED: the unlisted GRANT is not under its own name, PORT_FEE is not inside Trade, or a PROBE row was served';
  end if;
  raise notice 'PASS: REPORT_SECTIONS — through public.credit: Trade % · Crew % · Supplies % · Repairs % · Insurance % · Invest % · Ships % · Other % (an unlisted GRANT under its own name); every section is its lines; the total % equals the purse change % less the hidden PROBE 999',
    v_sec->>'trade', v_sec->>'crew', v_sec->>'supplies', v_sec->>'repairs',
    v_sec->>'insurance', v_sec->>'invest', v_sec->>'ships', v_sec->>'other',
    v_day->>'total', v_p1 - v_p0;

  -- ── 4. THE POINTS: THE REAL WRITER'S FILLS, AS A PARTITION ──────────────────────────────────
  if not exists (select 1 from jsonb_array_elements(v_day->'places') p
                  where p->>'kind' = 'port' and p->>'code' = 'LIS' and (p->>'ducats')::bigint = 250) then
    raise exception 'PROOF 13 FAILED: the docked receipt did not read Lisbon: %', v_day->'places';
  end if;
  if not exists (select 1 from jsonb_array_elements(v_day->'places') p
                  where p->>'kind' = 'voyage' and (p->>'id')::uuid = v_voy
                    and p->>'from' = 'LIS' and p->>'to' = 'FNC'
                    and (p->>'day')::int = v_voy_day and (p->>'ducats')::bigint = 300) then
    raise exception 'PROOF 13 FAILED: the at-sea receipt did not read voyage LIS→FNC d%: %', v_voy_day, v_day->'places';
  end if;
  if v_day->'places'->-1->>'kind' <> 'earlier'
     or (v_day->'places'->-1->>'ducats')::bigint <> -1970
     or (select count(*) from jsonb_array_elements(v_day->'places') p where p->>'kind' = 'earlier') <> 1 then
    raise exception 'PROOF 13 FAILED: Earlier is not the LAST and only no-point place at −1,970: %', v_day->'places';
  end if;
  select coalesce(sum((p->>'ducats')::bigint), 0) into v_sum from jsonb_array_elements(v_day->'places') p;
  if v_sum <> (v_day->>'total')::bigint then
    raise exception 'PROOF 13 FAILED: the places do not sum to the sections (not a partition)';
  end if;
  raise notice 'PASS: REPORT_POINTS — the docked receipt reads Lisbon +250; the at-sea receipt reads voyage LIS→FNC d% +300; the no-point rows read Earlier −1,970 LAST; the places sum to the sections',
    v_voy_day;

  -- ── 5. THE CLOCK: THE EXACT GAME-DAY BOUNDARY, AND THE AXES ─────────────────────────────────
  -- Planted as the owner, in this rolled-back proof: no committed row is touched or deleted.
  insert into public.ledger (player_id, kind, ducats_delta, balance_after, port_id, fleet_id, created_at) values
    (v_p, 'TOW',     111, v_p1, null, null, v_start - interval '1 second'),
    (v_p, 'TUITION', 222, v_p1, v_lis, v_f, to_timestamp(((v_today - 6) * v_gds)::double precision)),
    (v_p, 'GRANT',   333, v_p1, v_fnc, v_f, to_timestamp(((v_today - 7) * v_gds)::double precision));
  v_day  := world.report('day');
  v_week := world.report('week');
  v_all  := world.report('all');
  if (v_day->>'total')::bigint <> -1420 or (v_week->>'total')::bigint <> -1087 or (v_all->>'total')::bigint <> -754 then
    raise exception 'PROOF 13 FAILED: the span totals are % / % / %, not −1,420 / −1,087 / −754',
      v_day->>'total', v_week->>'total', v_all->>'total';
  end if;
  -- the boundary is witnessed by Other: −50 Day (the 111 row excluded), 283 Week (222 in, 333 out),
  -- 616 All (333 in).
  if ((select (s->>'ducats')::bigint from jsonb_array_elements(v_day->'sections') s where s->>'id' = 'other') <> -50)
     or ((select (s->>'ducats')::bigint from jsonb_array_elements(v_week->'sections') s where s->>'id' = 'other') <> 283)
     or ((select (s->>'ducats')::bigint from jsonb_array_elements(v_all->'sections') s where s->>'id' = 'other') <> 616) then
    raise exception 'PROOF 13 FAILED: the game-day boundary filter is wrong (Other should be −50 / 283 / 616)';
  end if;
  if jsonb_array_length(v_day->'days') <> 1
     or (v_day->'days'->0->>'net')::bigint <> -1420
     or jsonb_array_length(v_week->'days') <> 7
     or (v_week->'days'->0->>'game_day')::int <> v_today - 6
     or (v_week->'days'->0->>'net')::bigint <> 222
     or (v_week->'days'->6->>'net')::bigint <> -1420
     or jsonb_array_length(v_all->'days') <> 8
     or (v_all->'days'->0->>'game_day')::int <> v_today - 7
     or (v_all->'days'->0->>'net')::bigint <> 333
     or (v_all->'days'->-1->>'net')::bigint <> -1420 then
    raise exception 'PROOF 13 FAILED: a day axis is not 1 / 7 / 8 at the right edges: % / % / %',
      jsonb_array_length(v_day->'days'), jsonb_array_length(v_week->'days'), jsonb_array_length(v_all->'days');
  end if;
  if (select sum((d->>'net')::bigint) from jsonb_array_elements(v_week->'days') d) <> (v_week->>'total')::bigint
     or (select sum((d->>'net')::bigint) from jsonb_array_elements(v_all->'days') d) <> (v_all->>'total')::bigint then
    raise exception 'PROOF 13 FAILED: a day axis does not sum to its span''s total';
  end if;
  raise notice 'PASS: REPORT_SPANS — the 1 s-before row is outside Day, the exact today−6 row is inside Week, the exact today−7 row is outside Week but inside All: Other −50 / 283 / 616; totals −1,420 / −1,087 / −754; axes 1 / 7 / 8 zero-filled, each summing to its total';

  perform cmd.assume_identity(c_nil);
end $$;
