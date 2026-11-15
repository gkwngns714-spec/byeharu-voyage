-- READ ONLY, one statement: every distinct frozen leg prod holds (cargo circuits, navy patrols), as Postgres's own text, with how many
-- rows hold it, for the land audit (owner row 352).
begin transaction read only;
select jsonb_build_object(
  'cargo', (select jsonb_agg(jsonb_build_array(x.n, x.t)) from (select g.segments::text as t, count(*) as n from public.cargo_circuit_legs g group by 1) x),
  'patrol', (select jsonb_agg(jsonb_build_array(x.n, x.t)) from (select l.segments::text as t, count(*) as n from public.navy_patrol_legs l group by 1) x));
rollback;
