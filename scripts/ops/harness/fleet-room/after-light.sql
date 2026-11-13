-- 0354 PROD CHECK (after-light), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/fleet-room/after-light.sql
-- THE AFTER-CHECK OF LIGHTING `fleet_room_bite` (F6): run it once before the switch (every figure 0 then), and every few minutes for 30 minutes after it.
-- Wanted: lit true; `unbalanced` 0 (for every company with bought room, the gold her SLOT ledger rows took is exactly the knob prices of the steps she holds: read by her own rows, no table is summed whole);
-- `past_top` 0; `merchant_rows` 0; `room_events` = `steps_held`; `empty_fleets`, `moves_1h` and `renames_1h` say what the doors did.
-- Every function called is STABLE (public.fleet_room_on, public.wc, public.wc_int, public.fleet_room_caps). Rollback, forward and the owner's: fleet_room_bite false.
begin transaction read only;
with r as (
  select h.player_id,
         coalesce(sum(h.steps) filter (where h.kind = 'FLEET'), 0)::int as fleet_steps,
         coalesce(sum(h.steps) filter (where h.kind = 'SHIP'), 0)::int as ship_steps
    from public.house_room h group by h.player_id
), w as (
  select r.*,
         (select coalesce(sum(p.value::bigint), 0) from jsonb_array_elements_text(public.wc('fleet_room_prices')) with ordinality p(value, ord) where p.ord <= r.fleet_steps)
       + (select coalesce(sum(p.value::bigint), 0) from jsonb_array_elements_text(public.wc('ship_room_prices')) with ordinality p(value, ord) where p.ord <= r.ship_steps) as owed,
         (select coalesce(-sum(l.ducats_delta), 0) from public.ledger l where l.player_id = r.player_id and l.kind = 'SLOT') as paid,
         (select count(*) from public.events e where e.player_id = r.player_id and e.kind = 'ROOM_OPENED') as events
    from r
)
select public.fleet_room_on() as lit,
       (select count(*) from w) as houses_with_room,
       (select coalesce(sum(w.fleet_steps + w.ship_steps), 0) from w) as steps_held,
       (select coalesce(sum(w.events), 0) from w) as room_events,
       (select coalesce(sum(w.paid), 0) from w) as gold_removed,
       (select count(*) from w where w.owed <> w.paid) as unbalanced,
       (select count(*) from w join public.players p on p.id = w.player_id where p.is_npc) as merchant_rows,
       (select count(*) from w where (public.fleet_room_caps(w.player_id) ->> 'fleet_max')::int > public.wc_int('fleet_hard_max')
                                  or (public.fleet_room_caps(w.player_id) ->> 'fleet_ship_max')::int > public.wc_int('fleet_ship_top')) as past_top,
       (select count(*) from public.fleets f where not exists (select 1 from public.ships s where s.fleet_id = f.id)) as empty_fleets,
       (select count(*) from public.events e where e.kind = 'SHIP_MOVED' and e.created_at > now() - interval '1 hour') as moves_1h,
       (select count(*) from public.events e where e.kind = 'FLEET_RENAMED' and e.created_at > now() - interval '1 hour') as renames_1h,
       (select max(version) from supabase_migrations.schema_migrations) as head;
commit;
