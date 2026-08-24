-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 8 — THE SEA ANSWERS  (migration 0040's property, held for ever)
--
--   "Every point of navigable water answers which sea it is in, the answer is read from the one
--    raster, and no client role can reach either the table or the lookup."
--
-- WHY THIS IS NOT JUST 0040's SELF-ASSERT AGAIN
--   The self-assert replays at 0040's chain position: it can never see a port a LATER migration
--   seeds (the island ports of OWNER_REQUESTS row 38 are already written into data/ports.json and
--   await their slice). This proof runs against the FINISHED chain, so the day a new port lands on
--   water the raster cannot name — or a rework of the raster orphans one — this goes red, not the
--   player's screen.
--
-- THE POSITIVE CONTROL
--   A lookup function could pass every geography probe by accident (a copy of the table baked into
--   an index, a stale materialisation). So the proof CORRUPTS one cell inside its own transaction
--   and requires voyage.sea_at to change its answer — proving the function reads the raster it
--   claims to read. The transaction is rolled back by the harness like every proof.
--
-- @pass SEA_TOTAL_AT_EVERY_PORT   every ports row (harbour and sea place) resolves to a sea within 8 rings
-- @pass SEA_STRICT_ON_LAND        deep land answers NULL — sea_at is membership, never navigability
-- @pass SEA_NAMES_REAL_WATERS     six real waters from the Channel to the Sea of Japan answer by name
-- @pass SEA_AT_READS_THE_RASTER   corrupting one cell in-txn changes the answer (the lookup is live, not baked)
-- @pass SEA_WALL_HOLDS            no client role can execute sea_at or select sea_cells
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_port record;
  v_ord int;
  v_r0 int; v_c0 int; v_row int; v_col int; v_ring int; v_dr int; v_dc int;
  v_found boolean;
  v_unresolved text;
  v_n int := 0;
  v_before uuid;
  v_after uuid;
  v_expect uuid;
begin
  -----------------------------------------------------------------------------------------------
  -- (a) TOTAL AT EVERY PORT — derived from the table as it stands NOW, not from any seed count.
  -----------------------------------------------------------------------------------------------
  for v_port in select p.name || '/' || p.country as key, p.lat, p.lon from public.ports p loop
    v_n := v_n + 1;
    v_r0 := least(719, greatest(0, floor((90 - v_port.lat) / 0.25)::int));
    v_c0 := ((floor((v_port.lon + 180) / 0.25)::int % 1440) + 1440) % 1440;
    v_found := false;
    <<rings>>
    for v_ring in 0 .. 8 loop
      for v_dr in -v_ring .. v_ring loop
        for v_dc in -v_ring .. v_ring loop
          continue when greatest(abs(v_dr), abs(v_dc)) <> v_ring;
          v_row := v_r0 + v_dr;
          continue when v_row < 0 or v_row > 719;
          v_col := ((v_c0 + v_dc) % 1440 + 1440) % 1440;
          select get_byte(c.seas, v_col) into v_ord from public.sea_cells c where c.row_idx = v_row;
          if v_ord > 0 then v_found := true; exit rings; end if;
        end loop;
      end loop;
    end loop;
    if not v_found then
      v_unresolved := coalesce(v_unresolved || ', ', '') || v_port.key;
    end if;
  end loop;
  if v_n = 0 then
    raise exception 'SEA proof is VACUOUS: the ports table is empty';
  end if;
  if v_unresolved is not null then
    raise exception 'SEA proof FAIL: port(s) on water the raster cannot name: %', v_unresolved;
  end if;
  raise notice 'PASS: SEA_TOTAL_AT_EVERY_PORT — all % ports resolve within 8 rings', v_n;

  -----------------------------------------------------------------------------------------------
  -- (b) STRICT ON LAND.
  -----------------------------------------------------------------------------------------------
  if voyage.sea_at(23, 10) is not null or voyage.sea_at(46.5, 2.5) is not null then
    raise exception 'SEA proof FAIL: dry land answered a sea (Sahara: %, central France: %)',
      voyage.sea_at(23, 10), voyage.sea_at(46.5, 2.5);
  end if;
  raise notice 'PASS: SEA_STRICT_ON_LAND — the Sahara and central France answer NULL';

  -----------------------------------------------------------------------------------------------
  -- (c) REAL WATERS BY NAME — geography, not seed.
  -----------------------------------------------------------------------------------------------
  declare
    v_probe record;
  begin
    for v_probe in
      select * from (values
        (35.0::float8,  -40.0::float8, 'North Atlantic Ocean'),
        (50.5,   -1.0, 'English Channel'),
        (42.8,   15.0, 'Adriatic Sea'),
        (3.0,   100.4, 'Strait of Malacca'),
        (25.0,  -90.0, 'Gulf of Mexico'),
        (40.0,  135.0, 'Sea of Japan')
      ) as t(lat, lon, expect)
    loop
      if voyage.sea_at(v_probe.lat, v_probe.lon) is distinct from
         (select id from public.seas where name = v_probe.expect) then
        raise exception 'SEA proof FAIL: (%, %) should be %, got %', v_probe.lat, v_probe.lon,
          v_probe.expect,
          coalesce((select name from public.seas where id = voyage.sea_at(v_probe.lat, v_probe.lon)), 'NULL');
      end if;
    end loop;
  end;
  raise notice 'PASS: SEA_NAMES_REAL_WATERS — six waters from the Channel to the Sea of Japan answer by name';

  -----------------------------------------------------------------------------------------------
  -- (d) POSITIVE CONTROL — the lookup reads the raster it claims to read.
  -----------------------------------------------------------------------------------------------
  v_before := voyage.sea_at(35, -40);
  update public.sea_cells
     set seas = set_byte(seas, ((floor((-40 + 180) / 0.25)::int % 1440) + 1440) % 1440,
                (select raster_ordinal from public.seas where name = 'Baltic Sea'))
   where row_idx = least(719, greatest(0, floor((90 - 35) / 0.25)::int));
  v_after := voyage.sea_at(35, -40);
  select id into v_expect from public.seas where name = 'Baltic Sea';
  if v_after is distinct from v_expect or v_after is not distinct from v_before then
    raise exception 'SEA proof FAIL: corrupting the cell did not move the answer (before %, after %) — sea_at is not reading the raster',
      v_before, v_after;
  end if;
  raise notice 'PASS: SEA_AT_READS_THE_RASTER — one poked byte moved mid-Atlantic into the Baltic (rolled back)';

  -----------------------------------------------------------------------------------------------
  -- (e) THE WALL.
  -----------------------------------------------------------------------------------------------
  if has_function_privilege('anon', 'voyage.sea_at(double precision, double precision)', 'execute')
     or has_function_privilege('authenticated', 'voyage.sea_at(double precision, double precision)', 'execute')
     or has_table_privilege('anon', 'public.sea_cells', 'select')
     or has_table_privilege('authenticated', 'public.sea_cells', 'select') then
    raise exception 'SEA proof FAIL: a client role can reach the sea raster directly';
  end if;
  raise notice 'PASS: SEA_WALL_HOLDS — no client role can execute sea_at or select sea_cells';
end $$;
