-- The same law as sea.path_is_navigable, stated as ONE SET-BASED QUERY instead of a plpgsql loop.
-- plpgsql pays interpreter overhead per statement; a single SQL statement over generate_series
-- pays it once. This file exists to find out how much that is worth, measured, not assumed.
create or replace function sea.path_is_navigable_set(
  p_path jsonb, p_head_nm double precision default 0, p_tail_nm double precision default 0
)
returns boolean
language sql stable as $$
  with r as (select cols, rows, cell_deg::double precision deg, cells from sea.raster where id = 1),
  seg as (
    select i,
           (p_path->(i-1)->>0)::double precision lat1, (p_path->(i-1)->>1)::double precision lon1,
           (p_path->i->>0)::double precision     lat2, (p_path->i->>1)::double precision     lon2,
           jsonb_array_length(p_path) n
      from generate_series(1, jsonb_array_length(p_path) - 1) i
  ),
  m as (
    select seg.*, r.*,
           sea.gc_nm(lat1::numeric, lon1::numeric, lat2::numeric, lon2::numeric)::double precision nm
      from seg cross join r
  ),
  st as (
    select m.*, greatest(2, ceil(nm / (deg * 60 * 0.5))::int) steps,
           case when i = 1     then p_head_nm else 0 end head,
           case when i = n - 1 then p_tail_nm else 0 end tail
      from m
  ),
  samples as (
    select st.*, s::double precision / steps f
      from st cross join lateral generate_series(1, steps - 1) s
  )
  select not exists (
    select 1 from samples
     where f * nm >= head and (1 - f) * nm >= tail
       and get_byte(cells,
             (floor((90 - (lat1 + (lat2 - lat1) * f)) / deg)::int) * cols
             + ((( floor(((lon1 + (lon2 - lon1) * f) + 180) / deg)::int % cols) + cols) % cols)) = 0
  ) and not exists (select 1 from seg where abs(lon2 - lon1) > 180)
     and jsonb_array_length(p_path) >= 2
$$;
