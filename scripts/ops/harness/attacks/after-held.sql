-- ATTACKS, PROD CHECK (after-held), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/attacks/after-held.sql
-- Line 7 of the after-check of lighting attack_enabled (docs/COMBAT_LOG.md 3.5, 3.6): A HELD VOYAGE SETTLES THE DAYS OF A VOYAGE NEVER HELD.
-- A battle holds a sailing fleet where she is (voyage.hold, a `free` delay). 0357: that delay is no day: no stores, no wages, no hazard roll. Before 0357 a 600 s hold cost about 7 days.
-- Every voyage that a side of a battle of the last 24 hours was on (public.battle_sides, small; public.voyages by fleet), with what the columns themselves say:
--   unheld   = the days of the same voyage never held: ceil((sim hours + delay_hours - the free hold's hours) / 24), at least 1     (computed here, not through voyage.total_days)
--   burned   = the days the old rule would have counted: ceil((sim hours + delay_hours) / 24)
--   held                 voyages with a free hold.          arrived   of them, the ones that have arrived.
--   wrong_days           WANTED 0: an arrived held voyage whose settled days (last_settled_day) are not `unheld`.
--   over_days            WANTED 0: a held voyage still sailing that has settled more days than `unheld`.
--   function_differs     WANTED 0: voyage.total_days (STABLE) disagrees with `unheld`.
--   hold_would_have_cost how many of them the old rule would have charged a day or more (burned > unheld): the check has teeth only where this is above 0.
--   worst                the held voyages whose days are wrong, if any (at most 10).
-- A merchant's and a crown ship's finished voyages are compacted away after a while (public.npc_compact): what is still there is read.
begin transaction read only;
with h as (
  select distinct v.id, v.status, v.last_settled_day, v.delay_hours
    from public.battles b
    join public.battle_sides bs on bs.battle_id = b.id
    join public.voyages v on v.fleet_id = bs.fleet_id and v.departed_at <= b.started_at and v.eta >= b.started_at
   where b.sheet is not null and b.started_at > now() - interval '24 hours'),
x as (
  select h.*, voyage.hold_free_hours(h.id) as free, voyage.sim_hours(h.id) as sim, voyage.total_days(h.id) as days from h),
y as (
  select x.*, greatest(1, ceil((x.sim + greatest(0, x.delay_hours - x.free)) / 24)::int) as unheld, greatest(1, ceil((x.sim + x.delay_hours) / 24)::int) as burned from x)
select count(*) as voyages,
       count(*) filter (where y.free > 0) as held,
       count(*) filter (where y.free > 0 and y.status = 'ARRIVED') as arrived,
       count(*) filter (where y.free > 0 and y.status = 'ARRIVED' and y.last_settled_day <> y.unheld) as wrong_days,
       count(*) filter (where y.free > 0 and y.status = 'SAILING' and y.last_settled_day > y.unheld) as over_days,
       count(*) filter (where y.days <> y.unheld) as function_differs,
       count(*) filter (where y.free > 0 and y.burned > y.unheld) as hold_would_have_cost,
       (select coalesce(jsonb_agg(jsonb_build_object('voyage', z.id, 'status', z.status, 'settled', z.last_settled_day, 'unheld', z.unheld, 'burned', z.burned, 'free_hours', z.free)), '[]'::jsonb)
          from (select * from y y2 where y2.free > 0 and ((y2.status = 'ARRIVED' and y2.last_settled_day <> y2.unheld) or (y2.status = 'SAILING' and y2.last_settled_day > y2.unheld))
                 order by y2.id limit 10) z) as worst,
       (select max(version) from supabase_migrations.schema_migrations) as head
  from y;
commit;
