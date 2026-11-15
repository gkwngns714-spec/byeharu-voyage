-- ═══════════════════════════════════════════════════════════════════════════════
-- PROOF 148 - THE REAL STRAITS ARE OPEN  (migration 0446; docs/dev-log/2026-11-16-straits.md; the owner, 2026-11-15: the fix
--   over-corrected, Messina to Zakynthos is 630 nm where it was 291, "a real, wide strait that ships must be able to pass")
--
--   On the world itself, read only but for a ruler that is rolled back. The chart's land is not in the database: the courses the
--   browser plots through every real strait are held by tests/sea.straits.spec.ts (scripts/straits.mjs). What the database holds is
--   held here. FAILS BEFORE 0446: the four straits were raster land, Messina lay 14 nm off in the Tyrrhenian and was quoted 630 nm
--   from Zakynthos, and a cell a channel opened answered no sea.
--
-- @pass ST_CHANNELS  the four straits (Messina, the Great Belt, Bangka, Surabaya's fairway) are in voyage.channels, every cell they opened is raster water, and each strait's own line is accepted by the server's law with every sample read (no approach)
-- @pass ST_RULER     with a strait's cells closed again (rolled back) its own line is refused: the law sees a closed strait
-- @pass ST_MESSINA   Messina is reached from the strait itself: its roadstead lies in a cell the channel opened, is what voyage.water_roadstead answers, and has a sea of its own
-- @pass ST_QUOTES    the quay quotes a passage through each strait: Messina and Naples to Zakynthos, Lubeck to Bergen, Banten to Lingga and Jakarta to Surabaya are each within their multiple of the straight line between the two roadsteads, one figure both ways
-- @pass ST_ZONES     every carved cell of every channel is water with a zone or land with none, and every harbour's roadstead answers a sea
-- ═══════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_ids constant text[] := array['messina', 'great-belt', 'bangka', 'surabaya'];
  v_bad  text;
  v_n    int;
  r      record;
  v_ref  text;
begin
  -- ST_CHANNELS
  if (select count(*) from voyage.channels c where c.id = any (c_ids) and jsonb_array_length(c.carved_cells) = c.opens_land and c.opens_land > 0) <> 4 then
    raise exception 'PROOF 148 FAIL: the four straits are not all in voyage.channels';
  end if;
  select string_agg(c.id || ':' || k.v, ' '), count(*) into v_bad, v_n
    from voyage.channels c cross join lateral jsonb_array_elements_text(c.carved_cells) k(v), public.sea_raster s
   where s.id = 1 and c.id = any (c_ids) and get_bit(s.cells, k.v::int * s.bits_per_cell) <> 1;
  if v_n > 0 then
    raise exception 'PROOF 148 FAIL: a strait''s cell(s) are not water: %', v_bad;
  end if;
  for r in select c.id, c.points from voyage.channels c where c.id = any (c_ids) order by c.id loop
    v_ref := voyage.path_refusal(r.points, (r.points -> 0 ->> 0)::numeric, (r.points -> 0 ->> 1)::numeric,
                                 (r.points -> -1 ->> 0)::numeric, (r.points -> -1 ->> 1)::numeric, 0, 0, 0);
    if v_ref is not null then
      raise exception 'PROOF 148 FAIL: % is refused down its own line: %', r.id, v_ref;
    end if;
  end loop;
  raise notice 'PASS: ST_CHANNELS — 4 straits, % cells, every one water; each strait''s own line accepted with every sample read',
    (select sum(c.opens_land) from voyage.channels c where c.id = any (c_ids));

  -- ST_RULER: close each strait again and its line is refused (the sub-block is rolled back)
  begin
    for r in select c.id, c.points, c.carved_cells from voyage.channels c where c.id = any (c_ids) order by c.id loop
      update public.sea_raster s
         set cells = (select set_bit(s.cells, (k.v)::int * s.bits_per_cell, 0) from jsonb_array_elements_text(r.carved_cells) k(v) limit 1)
       where s.id = 1;
      if voyage.path_refusal(r.points, (r.points -> 0 ->> 0)::numeric, (r.points -> 0 ->> 1)::numeric,
                             (r.points -> -1 ->> 0)::numeric, (r.points -> -1 ->> 1)::numeric, 0, 0, 0) is null then
        raise exception 'PROOF 148 FAIL: with a cell of % closed its own line is still accepted: the law does not see a closed strait', r.id;
      end if;
    end loop;
    raise exception using errcode = 'ZP148', message = 'ruler';
  exception when sqlstate 'ZP148' then
    null;
  end;
  if exists (select 1 from voyage.channels c cross join lateral jsonb_array_elements_text(c.carved_cells) k(v), public.sea_raster s
              where s.id = 1 and c.id = any (c_ids) and get_bit(s.cells, k.v::int * s.bits_per_cell) <> 1) then
    raise exception 'PROOF 148 FAIL: the ruler was not rolled back';
  end if;
  raise notice 'PASS: ST_RULER — each of the 4 straits, one cell closed again, refuses its own line; rolled back';

  -- ST_MESSINA
  select string_agg(x.why, '; ') into v_bad
    from (select case
                   when not exists (select 1 from voyage.channels c where c.id = 'messina'
                                      and c.carved_cells @> to_jsonb(floor((90 - sr.roadstead_lat) / s.cell_deg)::int * s.cols + floor((sr.roadstead_lon + 180) / s.cell_deg)::int))
                     then 'its roadstead ' || sr.roadstead_lat || ',' || sr.roadstead_lon || ' is not in the strait'
                   when w.lat <> sr.roadstead_lat or w.lon <> sr.roadstead_lon or w.channel is distinct from 'messina'
                     then 'voyage.water_roadstead answers ' || w.lat || ',' || w.lon || ' on ' || coalesce(w.channel, 'no channel')
                   when public.harbour_zone(p.id) is null then 'its roadstead answers no sea'
                   when voyage.gc_distance_nm(p.lat::float8, p.lon::float8, sr.roadstead_lat::float8, sr.roadstead_lon::float8) > 5 then 'its roadstead is over 5 nm from the quay'
                 end as why
            from public.ports p join public.sea_reaches sr on sr.port_id = p.id
           cross join lateral voyage.water_roadstead(p.lat, p.lon) w
           cross join public.sea_raster s
           where p.code = 'MES' and s.id = 1) x
   where x.why is not null;
  if v_bad is not null or not exists (select 1 from public.ports p where p.code = 'MES') then
    raise exception 'PROOF 148 FAIL: Messina: %', coalesce(v_bad, 'no such harbour');
  end if;
  raise notice 'PASS: ST_MESSINA — Messina is reached from %, in the strait, % nm off its quay, in the sea %',
    (select sr.roadstead_lat || ',' || sr.roadstead_lon from public.sea_reaches sr where sr.code = 'MES'),
    (select round(sr.snap_nm, 2) from public.sea_reaches sr where sr.code = 'MES'),
    (select public.harbour_zone(p.id) from public.ports p where p.code = 'MES');

  -- ST_QUOTES
  select string_agg(v.a || '-' || v.b || ' ' || coalesce(ra.reaches ->> v.b, 'none') || ' nm (straight '
                    || round(voyage.gc_distance_nm(ra.roadstead_lat::float8, ra.roadstead_lon::float8, rb.roadstead_lat::float8, rb.roadstead_lon::float8)::numeric, 1) || ')', '; '),
         count(*) into v_bad, v_n
    from (values ('MES', 'ZAK', 1.2), ('NAP', 'ZAK', 1.3), ('LUB', 'BER', 1.3), ('BNT', 'LGA', 1.15), ('JAK', 'SUR', 1.1)) v(a, b, within)
    join public.sea_reaches ra on ra.code = v.a join public.sea_reaches rb on rb.code = v.b
   where (ra.reaches ->> v.b) is null or (ra.reaches ->> v.b)::numeric <> (rb.reaches ->> v.a)::numeric
      or (ra.reaches ->> v.b)::numeric > v.within * voyage.gc_distance_nm(ra.roadstead_lat::float8, ra.roadstead_lon::float8, rb.roadstead_lat::float8, rb.roadstead_lon::float8)::numeric;
  if v_n > 0 then
    raise exception 'PROOF 148 FAIL: the quay quotes a passage round, not through, a strait: %', v_bad;
  end if;
  raise notice 'PASS: ST_QUOTES — Messina to Zakynthos % nm (630 after 0440, 291 before), Naples to Zakynthos %, Lubeck to Bergen %, Banten to Lingga %, Jakarta to Surabaya %',
    (select sr.reaches ->> 'ZAK' from public.sea_reaches sr where sr.code = 'MES'),
    (select sr.reaches ->> 'ZAK' from public.sea_reaches sr where sr.code = 'NAP'),
    (select sr.reaches ->> 'BER' from public.sea_reaches sr where sr.code = 'LUB'),
    (select sr.reaches ->> 'LGA' from public.sea_reaches sr where sr.code = 'BNT'),
    (select sr.reaches ->> 'SUR' from public.sea_reaches sr where sr.code = 'JAK');

  -- ST_ZONES
  select string_agg(c.id || ':' || k.v, ' '), count(*) into v_bad, v_n
    from voyage.channels c cross join lateral jsonb_array_elements_text(c.carved_cells) k(v)
    join public.sea_cells s on s.row_idx = (k.v)::int / 1440
    join public.sea_zone_cells z on z.row_idx = s.row_idx
   where (get_byte(s.seas, (k.v)::int % 1440) <> 0) <> (get_byte(z.zones, (k.v)::int % 1440) <> 0);
  if v_n > 0 then
    raise exception 'PROOF 148 FAIL: carved cell(s) that are water with no zone, or land with one: %', left(v_bad, 600);
  end if;
  select string_agg(p.code, ' '), count(*) into v_bad, v_n from public.ports p where p.kind = 'HARBOUR' and public.harbour_zone(p.id) is null;
  if v_n > 0 then
    raise exception 'PROOF 148 FAIL: harbours whose roadstead answers no sea: %', v_bad;
  end if;
  raise notice 'PASS: ST_ZONES — % carved cells of % channels each water with a zone or land with none; every one of % harbours has a sea',
    (select count(*) from voyage.channels c cross join lateral jsonb_array_elements_text(c.carved_cells) k(v)),
    (select count(*) from voyage.channels), (select count(*) from public.ports p where p.kind = 'HARBOUR');
end
$$;
