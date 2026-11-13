-- 0354 PROD CHECK (volatility-0354), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/fleet-room/volatility-0354.sql
-- Run it FIRST. It prints provolatile of every game function the other 0354 checks call (over-caps.sql, after-light.sql, after-0354.sql): each must be 's' or 'i'. world.fleets() is 'v' and no check calls it.
-- After the deploy it also prints the new functions: world.house_room 's', public.fleet_totals 's', public.room_steps 'i'; the doors and cores 'v' (never called by a check). Before the deploy those rows read null.
begin transaction read only;
select f.fn, p.provolatile as volatility, p.prosecdef as definer, case when f.called then 'called by a check' else 'never called by a check' end as use
  from (values ('public.fleet_room_caps(uuid)', true), ('public.house_ship_max(uuid)', true), ('public.earned_caps(uuid)', true), ('public.fleet_room_on()', true),
               ('public.player_progress(uuid)', true), ('public.skill_level(uuid,text)', true), ('public.skill_level_at(uuid,text,timestamp with time zone)', true),
               ('public.skills_bite_on()', true), ('public.wc(text)', true), ('public.wc_int(text)', true),
               ('public.client_rpc_entry_points()', true),
               ('world.house_room()', false), ('public.fleet_totals(uuid,jsonb)', false), ('public.room_steps(jsonb,integer,jsonb,jsonb,integer,boolean,bigint)', false),
               ('world.fleets()', false), ('public.buy_room_for(uuid,text)', false), ('cmd.buy_room(text)', false), ('public.rename_fleet(uuid,uuid,text)', false), ('cmd.rename_fleet(uuid,text)', false)) f(fn, called)
  left join pg_proc p on p.oid = to_regprocedure(f.fn)
 order by f.called desc, f.fn;
commit;
