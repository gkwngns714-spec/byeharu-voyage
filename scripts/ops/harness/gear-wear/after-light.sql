-- gear_wear_bite PROD CHECK (THE AFTER-CHECK OF LIGHTING), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/gear-wear/after-light.sql
-- Run it once BEFORE lighting (the same shape, the switch false: the baseline), then at +1, +5 and +30 minutes, beside `bash scripts/ops/health.sh`.
-- WANTED after lighting:
--   switch_reads        true
--   news                1 (the lighting file's own UPDATE row; 0 when the switch was lit by hand)
--   merchants.worn      0, and merchant_repairs_with_fittings 0: a merchant's fitting never wears and she is never charged for one
--   over_100            0: no unit above 100
--   companies           `worn` and `bill_all` fall as companies repair and rise as they sail; nothing asserted. `weakest_works_pct` never below 50.
--   repairs_last_day    companies' REPAIR orders of the last day: `with_fittings` of them mended fittings, for `fittings_gold` in all (`largest` the dearest one).
--                       Against before-light.sql's `bill_all`: the gold paid for fittings cannot exceed the bills that stood, plus what a day's sailing wore.
--   refused_last_day    orders that failed with E_INSUFFICIENT_FUNDS on a REPAIR or an UNFIT in the last day (wanted: none that a fittings bill explains)
-- ROLLBACK (owner only; the same line that lights, with false): the wear stays on the units and no read, price or figure shows it (proof 72, WEAR_DARK_AGAIN).
begin transaction read only;
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'switch', (select jsonb_build_object('value', c.value, 'updated_at', c.updated_at) from public.world_config c where c.key = 'gear_wear_bite'),
  'switch_reads', public.gear_wear_on(),
  'news', (select count(*) from public.world_news w where w.key = 'update:0390'),
  'merchants', (select jsonb_build_object('fittings', count(*), 'worn', count(*) filter (where u.wear > 0))
                  from public.fitted_units u join public.ships s on s.id = u.ship_id join public.players p on p.id = s.player_id and p.is_npc),
  'over_100', (select count(*) from public.fitted_units u where u.wear > 100 or u.wear < 0),
  'companies', (select jsonb_build_object(
                  'fittings', count(*),
                  'worn', count(*) filter (where u.wear > 0),
                  'most_worn', coalesce(max(u.wear), 0),
                  'weakest_works_pct', round(public.wear_factor(coalesce(max(u.wear), 0)) * 100, 1),
                  'bill_all', coalesce(sum(public.unit_repair_cost(u.item_code, u.wear)) filter (where u.wear > 0), 0))
                  from public.fitted_units u join public.ships s on s.id = u.ship_id join public.players p on p.id = s.player_id and not p.is_npc),
  'repairs_last_day', (select jsonb_build_object(
                         'repairs', count(*),
                         'with_fittings', count(*) filter (where e.payload ? 'gear'),
                         'fittings_gold', coalesce(sum((e.payload -> 'gear' ->> 'cost')::bigint), 0),
                         'largest', coalesce(max((e.payload -> 'gear' ->> 'cost')::bigint), 0),
                         'all_gold', coalesce(sum((e.payload ->> 'cost')::bigint), 0),
                         'newest', max(e.created_at))
                         from public.events e join public.players p on p.id = e.player_id and not p.is_npc
                        where e.kind = 'REPAIRING' and e.created_at > now() - interval '1 day'),
  'merchant_repairs_with_fittings', (select count(*) from public.events e join public.players p on p.id = e.player_id and p.is_npc
                                      where e.kind = 'REPAIRING' and e.created_at > now() - interval '1 day' and e.payload ? 'gear'),
  'refused_last_day', (select coalesce(jsonb_agg(jsonb_build_object('verb', o.verb, 'at', o.issued_at, 'why', left(o.error_message, 120)) order by o.issued_at desc), '[]'::jsonb)
                         from public.orders o join public.players p on p.id = o.player_id and not p.is_npc
                        where o.issued_at > now() - interval '1 day' and o.status = 'failed' and o.error_code = 'E_INSUFFICIENT_FUNDS' and o.verb in ('REPAIR', 'UNFIT'))
) as after_light;
commit;
