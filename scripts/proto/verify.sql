-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PROTOTYPE — the SERVER SIDE of the free-water mover.
--
-- The measurement in scripts/proto/bench-pglite.mjs settles that the SEARCH cannot live in
-- plpgsql: 583 seconds for Lisboa→Nagasaki against 110 ms for the same algorithm in JavaScript.
-- So the server does not search. It does the two things that actually have to be authoritative:
--
--   1. sea.path_is_navigable(path) — EVERY sample along the polyline is sailable water.
--      This is the never-touch-land law, enforced rather than intended.
--   2. sea.path_nm(path)           — the length the server computes FROM THE SHAPE, so a client
--      supplies a shape and never a number.
--
-- Optimality is deliberately NOT verified, and the reason is that it does not need to be: a longer
-- path costs more voyage-days, more wages and more hazard rolls. A client that submits a worse
-- route punishes itself. A client cannot submit a BETTER one, because better means shorter, and
-- shorter than the water allows means crossing land — which check 1 refuses.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

create or replace function sea.cell_is_water(p_lat double precision, p_lon double precision)
returns boolean language sql stable as $$
  select get_byte(r.cells,
           (floor((90 - p_lat) / r.cell_deg::double precision)::int) * r.cols
           + (((floor((p_lon + 180) / r.cell_deg::double precision)::int % r.cols) + r.cols) % r.cols)
         ) = 1
    from sea.raster r where r.id = 1
$$;

-- THE LAW. A path is a jsonb array of [lat, lon] pairs. Every sample at half-cell spacing along
-- every segment must be water. The two ENDS are exempt by exactly the snap distance the harbour
-- needed and no more — sea-grid.mjs exempts a flat 25 nm at both ends, which is how 41 ports came
-- to teleport up to 72 nm for free.
create or replace function sea.path_is_navigable(
  p_path jsonb, p_head_nm double precision default 0, p_tail_nm double precision default 0
)
returns boolean
language plpgsql stable as $$
declare
  v_cols int; v_rows int; v_deg double precision; v_cells bytea;
  n int; i int; s int; steps int;
  lat1 double precision; lon1 double precision; lat2 double precision; lon2 double precision;
  la double precision; lo double precision; f double precision; nm double precision;
  head double precision; tail double precision;
begin
  select r.cols, r.rows, r.cell_deg::double precision, r.cells
    into v_cols, v_rows, v_deg, v_cells from sea.raster r where r.id = 1;
  n := jsonb_array_length(p_path);
  if n < 2 then return false; end if;

  for i in 0 .. n - 2 loop
    lat1 := (p_path->i->>0)::double precision;  lon1 := (p_path->i->>1)::double precision;
    lat2 := (p_path->(i+1)->>0)::double precision; lon2 := (p_path->(i+1)->>1)::double precision;
    if abs(lon2 - lon1) > 180 then return false; end if;      -- no segment may wrap the seam
    nm := sea.gc_nm(lat1::numeric, lon1::numeric, lat2::numeric, lon2::numeric)::double precision;
    steps := greatest(2, ceil(nm / (v_deg * 60 * 0.5))::int);
    head := case when i = 0 then p_head_nm else 0 end;
    tail := case when i = n - 2 then p_tail_nm else 0 end;
    for s in 1 .. steps - 1 loop
      f := s::double precision / steps;
      continue when f * nm < head or (1 - f) * nm < tail;
      la := lat1 + (lat2 - lat1) * f;
      lo := lon1 + (lon2 - lon1) * f;
      if get_byte(v_cells,
           (floor((90 - la) / v_deg)::int) * v_cols
           + (((floor((lo + 180) / v_deg)::int % v_cols) + v_cols) % v_cols)) = 0 then
        return false;
      end if;
    end loop;
  end loop;
  return true;
end $$;

-- THE DISTANCE, computed from the shape. The client never sends a number.
create or replace function sea.path_nm(p_path jsonb)
returns numeric language sql stable as $$
  select coalesce(sum(sea.gc_nm(
           (p_path->(i-1)->>0)::numeric, (p_path->(i-1)->>1)::numeric,
           (p_path->i->>0)::numeric,     (p_path->i->>1)::numeric)), 0)
    from generate_series(1, jsonb_array_length(p_path) - 1) i
$$;
