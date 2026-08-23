-- The sea, in the database: ONE bytea of 1,440 x 720 = 1,036,800 bytes, one per cell, 1 = sailable.
-- get_byte() is O(1) on it, so the grid needs no table of a million rows and no index.
create schema if not exists sea;

create table if not exists sea.raster (
  id        int primary key default 1 check (id = 1),
  cols      int not null,
  rows      int not null,
  cell_deg  numeric not null,
  cells     bytea not null
);

-- Row 0 is the north pole end, exactly as scripts/sea-grid.mjs has it.
create or replace function sea.cell_lat(p_row int, p_deg numeric) returns numeric
  language sql immutable as $$ select 90 - (p_row + 0.5) * p_deg $$;
create or replace function sea.cell_lon(p_col int, p_deg numeric) returns numeric
  language sql immutable as $$ select -180 + (p_col + 0.5) * p_deg $$;

create or replace function sea.gc_nm(lat1 numeric, lon1 numeric, lat2 numeric, lon2 numeric)
returns numeric language sql immutable as $$
  select 2 * 3440.065 * asin(least(1, sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lon2 - lon1) / 2), 2))))
$$;
