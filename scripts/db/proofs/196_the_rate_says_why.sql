-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 196 - THE RATE SAYS WHY  (migration 0493; docs/design/hq-corp-2026-11-24.md B4)
--
--   The owner, 2026-11-24: "i am -19.649 / hour. it should say why", then "why investing causes les money? wtf?". Her figure was
--   -471,566 over 24 hours: SHARE -461,384 in two rows, TOW -6,932, OFFICER_WAGE -3,250 (the lead's prod read). This proof plants
--   exactly those rows on a fresh company and reads the one authority (public.company_rate_for) and the board that serves it.
--   Rolled back by proof.mjs.
--
-- @pass RW_OWNER_DAY    her day: the old figure was -19,649 an hour; now the headline is the tow alone (-289 an hour), investing
--                       and the captain's fee stand beside it as one-time lines, and all_24h is still -471,566
-- @pass RW_SUMS         the running lines sum to net_24h, the one-time lines to one_time_24h, all lines to 0480's old sum
-- @pass RW_WINDOW       a row a minute outside the 24 hours, a PROBE_ row and her FOUNDING row are left out, as 0480 left them
-- @pass RW_EVERY_KIND   every ledger kind a function of the chain writes by name maps to a named line (none falls to Other)
-- @pass RW_BOARD        world.hq_board() lit serves the authority's own object as `rate`, with per_hour, net_24h and since kept
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a   constant uuid := '00000000-0493-4000-8000-0000000000a1';
  v_a   uuid;
  v_r   jsonb;
  v_b   jsonb;
  v_old numeric;
  v_n   int;
  v_bad text;
begin
  v_a := public.new_house(c_a, 'Casa do Porque A 196', 'PRT');

  -- ── RW_OWNER_DAY ──
  insert into public.ledger (player_id, kind, ducats_delta, balance_after, created_at) values
    (v_a, 'SHARE',        -400000, 1, now() - interval '2 hours'),
    (v_a, 'SHARE',         -61384, 1, now() - interval '3 hours'),
    (v_a, 'TOW',            -6932, 1, now() - interval '4 hours'),
    (v_a, 'OFFICER_WAGE',   -3250, 1, now() - interval '5 hours');
  select public.company_rate_for(v_a),
         (select coalesce(sum(l.ducats_delta), 0) from public.ledger l
           where l.player_id = v_a and l.created_at > now() - interval '24 hours' and l.kind <> 'FOUNDING' and left(l.kind, 6) <> 'PROBE_')
    into v_r, v_old;
  if v_old <> -471566 or round(v_old / 24.0) <> -19649 then
    raise exception 'PROOF 196 FAILED: the planted day is not the owner''s (0480''s sum %, % an hour)', v_old, round(v_old / 24.0);
  end if;
  if (v_r->>'net_24h')::numeric <> -6932 or (v_r->>'per_hour')::numeric <> -289 or (v_r->>'one_time_24h')::numeric <> -464634
     or (v_r->>'all_24h')::numeric <> -471566 or v_r->'top' is distinct from '["tow"]'::jsonb
     or (select jsonb_agg(jsonb_build_array(e->>'line', (e->>'total_24h')::numeric, (e->>'count')::int, (e->>'one_time')::boolean) order by k)
           from jsonb_array_elements(v_r->'lines') with ordinality z(e, k))
          is distinct from '[["tow", -6932, 1, false], ["invest", -461384, 2, true], ["hiring", -3250, 1, true]]'::jsonb then
    raise exception 'PROOF 196 FAILED: her day does not read as written: %', v_r;
  end if;
  raise notice 'PASS: RW_OWNER_DAY - 0480 said % an hour; now % an hour (%), one time % (invest -461,384 in 2 rows, hiring -3,250), all %',
    round(v_old / 24.0), v_r->>'per_hour', v_r->'top', v_r->>'one_time_24h', v_r->>'all_24h';

  -- ── RW_SUMS (with running income and a kind nobody wrote) ──
  insert into public.ledger (player_id, kind, ducats_delta, balance_after, created_at) values
    (v_a, 'SELL', 52000, 1, now() - interval '1 hour'), (v_a, 'BUY', -31000, 1, now() - interval '90 minutes'),
    (v_a, 'DIVIDEND', 700, 1, now() - interval '1 hour'), (v_a, 'WAGES', -900, 1, now() - interval '1 hour'),
    (v_a, 'BUILD', -52000, 1, now() - interval '8 hours'), (v_a, 'KIND_OF_196', -5, 1, now() - interval '1 hour');
  select public.company_rate_for(v_a),
         (select coalesce(sum(l.ducats_delta), 0) from public.ledger l
           where l.player_id = v_a and l.created_at > now() - interval '24 hours' and l.kind <> 'FOUNDING' and left(l.kind, 6) <> 'PROBE_')
    into v_r, v_old;
  if (select sum((e->>'total_24h')::numeric) from jsonb_array_elements(v_r->'lines') e where not (e->>'one_time')::boolean) <> (v_r->>'net_24h')::numeric
     or (select sum((e->>'total_24h')::numeric) from jsonb_array_elements(v_r->'lines') e where (e->>'one_time')::boolean) <> (v_r->>'one_time_24h')::numeric
     or (select sum((e->>'total_24h')::numeric) from jsonb_array_elements(v_r->'lines') e) <> v_old
     or (v_r->>'all_24h')::numeric <> v_old or (v_r->>'net_24h')::numeric <> 13863 or (v_r->>'per_hour')::numeric <> round(13863 / 24.0)
     or v_r->'top' is distinct from '["trade", "dividends"]'::jsonb
     or not exists (select 1 from jsonb_array_elements(v_r->'lines') e where e->>'line' = 'other' and (e->>'total_24h')::numeric = -5 and not (e->>'one_time')::boolean)
     or exists (select 1 from jsonb_array_elements(v_r->'lines') e where (e->>'per_hour')::numeric <> round((e->>'total_24h')::numeric / 24.0)) then
    raise exception 'PROOF 196 FAILED: the lines do not sum to the figures: % (0480''s sum %)', v_r, v_old;
  end if;
  raise notice 'PASS: RW_SUMS - running % = net_24h, one time %, all % = 0480''s sum, over % lines; in profit the headline names %',
    v_r->>'net_24h', v_r->>'one_time_24h', v_r->>'all_24h', jsonb_array_length(v_r->'lines'), v_r->'top';

  -- ── RW_WINDOW ──
  v_b := v_r;
  insert into public.ledger (player_id, kind, ducats_delta, balance_after, created_at) values
    (v_a, 'SELL', 7777, 1, now() - interval '24 hours 1 minute'), (v_a, 'PROBE_196', 8888, 1, now() - interval '1 hour');
  v_r := public.company_rate_for(v_a);
  if v_r is distinct from v_b or not exists (select 1 from public.ledger l where l.player_id = v_a and l.kind = 'FOUNDING') then
    raise exception 'PROOF 196 FAILED: a row outside the window, a probe row or the founding moved the rate: % / %', v_b, v_r;
  end if;
  raise notice 'PASS: RW_WINDOW - a row 24 h 1 min old, a PROBE_ row and her FOUNDING row leave the rate as it was';

  -- ── RW_EVERY_KIND: the kinds the chain's functions write by name (public.credit's 2nd argument, pay_city's and city_pays' 3rd) ──
  select count(distinct m.kind), string_agg(distinct m.kind, ', ') filter (where (select k.line from public.company_rate_line(m.kind) k) = 'other')
    into v_n, v_bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   cross join lateral (select (regexp_matches(p.prosrc, '\m(?:credit|pay_city|city_pays)\s*\(\s*[^,()]+,\s*(?:[^,()'']+,\s*)?''([A-Z][A-Z_0-9]+)''', 'g'))[1] as kind) m
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind = 'f'
     and m.kind <> 'FOUNDING' and left(m.kind, 6) <> 'PROBE_';
  if v_n < 30 or v_bad is not null then
    raise exception 'PROOF 196 FAILED: % kinds read from the chain''s functions (want 30 or more); falling to Other: %', v_n, v_bad;
  end if;
  raise notice 'PASS: RW_EVERY_KIND - % ledger kinds written by name in the chain, each on a named line', v_n;

  -- ── RW_BOARD ──
  update public.world_config set value = 'true'::jsonb where key = 'hq_board_enabled';
  update public.world_config set value = to_jsonb(0) where key = 'hq_board_fleets';
  perform cmd.assume_identity(c_a);
  select world.hq_board(), public.company_rate_for(v_a) into v_b, v_r;
  if (v_b->>'company')::boolean is not true or v_b->'rate' is distinct from v_r or world.company_rate() is distinct from v_r
     or not (v_b->'rate' ? 'per_hour' and v_b->'rate' ? 'net_24h' and v_b->'rate' ? 'since' and v_b->'rate' ? 'lines') then
    raise exception 'PROOF 196 FAILED: the board does not serve the one authority: % / %', left(v_b::text, 600), v_r;
  end if;
  raise notice 'PASS: RW_BOARD - world.hq_board().rate is public.company_rate_for''s object (% lines), and world.company_rate() is hers',
    jsonb_array_length(v_b->'rate'->'lines');
end $p$;
