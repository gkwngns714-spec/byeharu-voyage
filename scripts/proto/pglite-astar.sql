-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- THE REJECTED OPTION, KEPT AS EVIDENCE.
--
-- The same A* as scripts/proto/pathfind.mjs, in plpgsql, so its cost inside the shipping runtime
-- (PGlite / WebAssembly PostgreSQL, in the player's browser tab) is a MEASURED number and not an
-- opinion. Loaded by scripts/proto/bench-pglite.mjs. What it measured, 2026-08-24:
--
--   Lisboa → Cádiz       (74 cells expanded)        358 ms
--   Lisboa → Amsterdam   (957)                    4,455 ms
--   Lisboa → Salvador    (11,150)                45,839 ms
--   Amsterdam → Venice   (17,775)                69,560 ms
--   Lisboa → Calicut     (85,316)               405,890 ms
--   Lisboa → Nagasaki    (165,619)              582,971 ms   ← 9.7 MINUTES
--
-- The same search in JavaScript: 110 ms. A 5,300x gap, because plpgsql pays interpreter overhead
-- per statement and the inner loop runs ~1.3 million times. THE SEARCH CANNOT LIVE IN THE DATABASE.
-- This file exists so that conclusion stays a measurement instead of becoming a remembered opinion.
--
-- The raster is ONE bytea: 1,440 x 720 = 1,036,800 bytes, one per cell, 1 = sailable. get_byte() is
-- O(1) on it, so the grid needs no table of a million rows and no index. (Note that for the
-- VERIFICATION path this single-bytea storage is itself a 100x mistake — see verify3.sql.)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- Requires raster.sql to have been applied first (bench-pglite.mjs applies both, in order).

create or replace function sea.snap(p_cells bytea, p_cols int, p_rows int, p_node int)
returns int language plpgsql immutable as $$
declare
  r0 int := p_node / p_cols;
  c0 int := p_node % p_cols;
  ring int; dr int; dc int; rr int; cc int;
begin
  if get_byte(p_cells, p_node) = 1 then return p_node; end if;
  for ring in 1 .. 12 loop
    for dr in -ring .. ring loop
      rr := r0 + dr;
      continue when rr < 0 or rr >= p_rows;
      for dc in -ring .. ring loop
        continue when greatest(abs(dr), abs(dc)) <> ring;
        cc := ((c0 + dc) % p_cols + p_cols) % p_cols;
        if get_byte(p_cells, rr * p_cols + cc) = 1 then return rr * p_cols + cc; end if;
      end loop;
    end loop;
  end loop;
  return null;
end $$;

create or replace function sea.find_path(
  p_lat1 double precision, p_lon1 double precision,
  p_lat2 double precision, p_lon2 double precision
)
returns table (nm double precision, expanded int, cells int)
language plpgsql
as $$
declare
  v_cols int; v_rows int; v_deg double precision; v_cells bytea;
  v_ns double precision; v_ew double precision[];
  g double precision[]; prev int[]; seen int[];          -- 0 unseen, 1 open, 2 closed
  hp double precision[]; hn int[]; hsize int := 0;       -- the binary heap
  v_start int; v_goal int; v_glat double precision; v_glon double precision;
  v_cur int; v_row int; v_col int; v_nrow int; v_ncol int; v_next int;
  v_cost double precision; v_step double precision; v_dx double precision; v_dy double precision;
  v_tent double precision; v_exp int := 0;
  i int; j int; k int; tp double precision; tn int; dr int; dc int;
  v_n int; v_found boolean := false; v_len int := 0;
begin
  select r.cols, r.rows, r.cell_deg::double precision, r.cells
    into v_cols, v_rows, v_deg, v_cells from sea.raster r where r.id = 1;
  v_n  := v_cols * v_rows;
  v_ns := v_deg * 60;

  v_ew := array_fill(0::double precision, array[v_rows]);
  for i in 0 .. v_rows - 1 loop
    v_ew[i + 1] := v_deg * 60 * cos(radians(90 - (i + 0.5) * v_deg));
  end loop;

  v_start := (floor((90 - p_lat1) / v_deg)::int) * v_cols + (floor((p_lon1 + 180) / v_deg)::int % v_cols);
  v_goal  := (floor((90 - p_lat2) / v_deg)::int) * v_cols + (floor((p_lon2 + 180) / v_deg)::int % v_cols);
  v_start := sea.snap(v_cells, v_cols, v_rows, v_start);
  v_goal  := sea.snap(v_cells, v_cols, v_rows, v_goal);
  if v_start is null or v_goal is null then return; end if;

  v_glat := 90 - ((v_goal / v_cols) + 0.5) * v_deg;
  v_glon := -180 + ((v_goal % v_cols) + 0.5) * v_deg;

  g    := array_fill(0::double precision, array[v_n]);
  prev := array_fill(-1, array[v_n]);
  seen := array_fill(0, array[v_n]);
  hp := array_fill(0::double precision, array[1024]);
  hn := array_fill(0, array[1024]);
  hsize := 1; hp[1] := 0; hn[1] := v_start;
  seen[v_start + 1] := 1;

  while hsize > 0 loop
    v_cur := hn[1];
    hp[1] := hp[hsize]; hn[1] := hn[hsize]; hsize := hsize - 1;
    i := 1;
    loop
      j := 2 * i; k := j + 1;
      if j > hsize then exit; end if;
      if k <= hsize and hp[k] < hp[j] then j := k; end if;
      exit when hp[i] <= hp[j];
      tp := hp[i]; tn := hn[i]; hp[i] := hp[j]; hn[i] := hn[j]; hp[j] := tp; hn[j] := tn;
      i := j;
    end loop;

    if v_cur = v_goal then v_found := true; exit; end if;
    continue when seen[v_cur + 1] = 2;
    seen[v_cur + 1] := 2;
    v_exp := v_exp + 1;

    v_row := v_cur / v_cols;
    v_col := v_cur % v_cols;
    v_cost := g[v_cur + 1];

    for dr in -1 .. 1 loop
      v_nrow := v_row + dr;
      continue when v_nrow < 0 or v_nrow >= v_rows;
      for dc in -1 .. 1 loop
        continue when dr = 0 and dc = 0;
        v_ncol := ((v_col + dc) % v_cols + v_cols) % v_cols;
        v_next := v_nrow * v_cols + v_ncol;
        continue when get_byte(v_cells, v_next) = 0;
        continue when seen[v_next + 1] = 2;
        v_dy := case when dr = 0 then 0 else v_ns end;
        v_dx := case when dc = 0 then 0 else (v_ew[v_row + 1] + v_ew[v_nrow + 1]) / 2 end;
        v_step := case when v_dx = 0 then v_dy when v_dy = 0 then v_dx
                       else sqrt(v_dx * v_dx + v_dy * v_dy) end;
        v_tent := v_cost + v_step;
        continue when seen[v_next + 1] = 1 and v_tent >= g[v_next + 1];
        g[v_next + 1] := v_tent;
        prev[v_next + 1] := v_cur;
        seen[v_next + 1] := 1;
        hsize := hsize + 1;
        if hsize > array_length(hp, 1) then
          hp := hp || array_fill(0::double precision, array[array_length(hp, 1)]);
          hn := hn || array_fill(0, array[array_length(hn, 1)]);
        end if;
        hp[hsize] := v_tent + sea.gc_nm(
          (90 - (v_nrow + 0.5) * v_deg)::numeric, (-180 + (v_ncol + 0.5) * v_deg)::numeric,
          v_glat::numeric, v_glon::numeric)::double precision;
        hn[hsize] := v_next;
        i := hsize;
        while i > 1 loop
          j := i / 2;
          exit when hp[j] <= hp[i];
          tp := hp[i]; tn := hn[i]; hp[i] := hp[j]; hn[i] := hn[j]; hp[j] := tp; hn[j] := tn;
          i := j;
        end loop;
      end loop;
    end loop;
  end loop;

  if not v_found then return; end if;
  i := v_goal;
  while i <> -1 loop
    v_len := v_len + 1;
    exit when i = v_start;
    i := prev[i + 1];
  end loop;

  nm := g[v_goal + 1];
  expanded := v_exp;
  cells := v_len;
  return next;
end $$;
