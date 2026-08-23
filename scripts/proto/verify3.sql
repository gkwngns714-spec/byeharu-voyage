-- THIRD SHAPE. The first two both cost ~750 ms on the longest path and the reason is not the
-- arithmetic: `cells` is a 1 MB bytea, so it lives in TOAST, and every get_byte() against it pays a
-- detoast. Storing the sea as ONE ROW PER GRID ROW — 720 rows of 1,440 bytes — puts every value
-- inline, and a sample becomes an index lookup plus a get_byte on a 1.4 KB string.
--
-- Same law, same answer, different storage. Measured by bench-verify3.mjs.
create table if not exists sea.raster_rows (
  row_idx int primary key,
  cells   bytea not null
);

create or replace function sea.row_is_water(p_row int, p_col int)
returns boolean language sql stable as $$
  select get_byte(cells, p_col) = 1 from sea.raster_rows where row_idx = p_row
$$;

create or replace function sea.path_is_navigable_rows(
  p_path jsonb, p_head_nm double precision default 0, p_tail_nm double precision default 0
)
returns boolean
language plpgsql stable as $$
declare
  v_cols int; v_deg double precision;
  n int; i int; s int; steps int;
  lat1 double precision; lon1 double precision; lat2 double precision; lon2 double precision;
  la double precision; lo double precision; f double precision; nm double precision;
  head double precision; tail double precision;
  v_row int; v_col int; v_last_row int := -1; v_bytes bytea;
begin
  select r.cols, r.cell_deg::double precision into v_cols, v_deg from sea.raster r where r.id = 1;
  n := jsonb_array_length(p_path);
  if n < 2 then return false; end if;

  for i in 0 .. n - 2 loop
    lat1 := (p_path->i->>0)::double precision;     lon1 := (p_path->i->>1)::double precision;
    lat2 := (p_path->(i+1)->>0)::double precision; lon2 := (p_path->(i+1)->>1)::double precision;
    if abs(lon2 - lon1) > 180 then return false; end if;
    nm := sea.gc_nm(lat1::numeric, lon1::numeric, lat2::numeric, lon2::numeric)::double precision;
    steps := greatest(2, ceil(nm / (v_deg * 60 * 0.5))::int);
    head := case when i = 0 then p_head_nm else 0 end;
    tail := case when i = n - 2 then p_tail_nm else 0 end;
    for s in 1 .. steps - 1 loop
      f := s::double precision / steps;
      continue when f * nm < head or (1 - f) * nm < tail;
      la := lat1 + (lat2 - lat1) * f;
      lo := lon1 + (lon2 - lon1) * f;
      v_row := floor((90 - la) / v_deg)::int;
      v_col := ((floor((lo + 180) / v_deg)::int % v_cols) + v_cols) % v_cols;
      -- CONSECUTIVE SAMPLES SHARE A ROW almost always: a segment crosses a row boundary once every
      -- two samples at worst, so this caches the fetch rather than repeating it.
      if v_row <> v_last_row then
        select cells into v_bytes from sea.raster_rows where row_idx = v_row;
        v_last_row := v_row;
      end if;
      if v_bytes is null or get_byte(v_bytes, v_col) = 0 then return false; end if;
    end loop;
  end loop;
  return true;
end $$;
