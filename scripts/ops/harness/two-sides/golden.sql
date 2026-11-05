-- golden.sql: READ-ONLY on prod, one pure SELECT of a STABLE function (voyage.fight_resolve, provolatile 's').
-- The digest of every answer of 0320's parity probe: 960 days of 0202's hulls and 120 of a convoy. Take it before the deploy and after it: the two must be the same text.
-- Run: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/two-sides/golden.sql
with s(ships, esc) as (values
  ('[{"id":"00000000-0320-4000-8000-0000000000a1","name":"Probe Carlat","tier":1,"hull":550,"maxd":550,"crew":12,"attack":55,"accuracy":40,"reach":25,"armour":12,"sighting":10,"gear":["Boarding Gear"]}]'::jsonb, 11.74::numeric),
  ('[{"id":"00000000-0320-4000-8000-0000000000a2","name":"Probe Barca","tier":1,"hull":400,"maxd":400,"crew":8,"attack":35,"accuracy":0,"reach":0,"armour":5,"sighting":8}]'::jsonb, 6.66::numeric)),
c(ships) as (values ('[{"id":"00000000-0320-4000-8000-0000000000a3","name":"Probe Nau","tier":3,"hull":1500,"maxd":1800,"crew":90,"attack":180,"accuracy":55,"reach":60,"armour":30,"sighting":40,"boarder_pct":0.12,"boarder":"Probe Boarder","gunner":"Probe Gunner","gear":["Swivel Guns","Boarding Gear"]},{"id":"00000000-0320-4000-8000-0000000000a4","name":"Probe Galion","tier":4,"hull":2400,"maxd":2400,"crew":140,"attack":260,"accuracy":48,"reach":40,"armour":44,"sighting":22},{"id":"00000000-0320-4000-8000-0000000000a5","name":"Probe Wreck","tier":1,"hull":0,"maxd":500,"crew":6,"attack":40,"accuracy":40,"reach":90,"armour":0,"sighting":5}]'::jsonb)),
f as materialized (
  select 1 as o, s.esc, r.r, d, voyage.fight_resolve('00000000-0320-4000-8000-0000000000ff'::uuid, d, r.r, s.esc, s.ships) j
    from s cross join (values (6.0), (12.0), (18.0), (24.0)) r(r) cross join generate_series(1, 120) d
  union all
  select 2, 30.5, r.r, d, voyage.fight_resolve('00000000-0320-4000-8000-0000000000ff'::uuid, d, r.r, 30.5, c.ships)
    from c cross join (values (10.0), (24.0), (60.0), (120.0)) r(r) cross join generate_series(1, 30) d)
select (select count(*) from f) as fights,
       (select md5(string_agg(j::text, E'\n' order by o, esc, r, d)) from f) as digest,
       (select jsonb_object_agg(k, n) from (select j->>'outcome' k, count(*) n from f group by 1) e) as endings;
