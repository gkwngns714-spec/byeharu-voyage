-- 0514: THE READ BEFORE THE LIGHT (and before the deploy of 0514 it is refused: the function is this file's). READ ONLY, ONE statement:
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/seas-relit/before-0514.sql
-- WHAT IT LISTS, one row a section:
--   table      the rung table with its `mark`: SHOW IT TO THE OWNER. The light step asks for this mark and refuses any other.
--   totals     harbours each rung opens from Lisbon; companies, fleets, how many fleets are beyond their company's rung, `trapped` (must be 0), jobs whose buy or sale harbour would be shut
--   company    ONE ROW A LIVE COMPANY: Trading, Exploration, her rung (the lower), home, and each fleet: where she lies (or is bound), that sea and its rung, her wave resistance,
--              inside (her own level and hull open that sea), way_home (home / open / pass / none), the harbours open to her, the seas kept (0510), the job's shut harbour
-- Cost: about 80 ms a fleet once (16 fleets 1.3 s on the local world); run it with the gate green, once. Every function called is STABLE.
with r as materialized (select public.seas_relit_ready() as j)
select 1 as ord, 'table' as section, jsonb_build_object('mark', r.j->'mark', 'rungs', r.j->'rungs') as data from r
union all select 2, 'totals', r.j - 'rungs' - 'companies' from r
union all select 3, 'company', c.e from r cross join lateral jsonb_array_elements(r.j->'companies') c(e)
order by 1, 3;
