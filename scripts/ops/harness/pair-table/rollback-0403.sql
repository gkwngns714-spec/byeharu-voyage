-- 0403 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number, add its news line and
-- deploy it as any migration (owner only). It puts public.sea_leg_asks back to the straight-line derivation (public.sea_leg_asks_derive, as 0401 ran it)
-- and its comments back. Trade and the server's pathfinder then read straight lines again: they list harbours the door refuses. In the same change remove
-- data/sea-legs.json and its block in scripts/db/world-guard.mjs (the guard holds the table to that file).
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite).
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
begin
  if coalesce(obj_description('public.sea_leg_asks'::regclass, 'pg_class'), '') not like '%0403%' then
    raise exception '0403 rollback refuses: 0403 is not applied in this world';
  end if;
  delete from public.sea_leg_asks;
  insert into public.sea_leg_asks (from_port, to_port, wave_min, title_min, zones)
  select d.from_port, d.to_port, d.wave_min, d.title_min, d.zones from public.sea_leg_asks_derive() d;
  comment on table public.sea_leg_asks is
    '0215, 0222: what the STRAIGHT line between two roadsteads asks (wave_min, title_min, zones), land ignored, with the destination''s own zone. DERIVED by '
    'public.sea_leg_asks_derive(); re-derived whenever a zone or a box moves; never hand-edited.';
  comment on function public.sea_leg_asks_derive(uuid) is '0215, 0222: THE ONE DERIVATION of public.sea_leg_asks, from the straight line between two roadsteads.';
  raise notice '0403 rollback draft: % pair rows are the straight line''s again', (select count(*) from public.sea_leg_asks);
end
$r$;
