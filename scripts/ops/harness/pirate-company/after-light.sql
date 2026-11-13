-- 0381 PROD CHECK (AFTER lighting pirates_joinable: at once, then at +5 and +30 minutes), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/pirate-company/after-light.sql
-- Wanted: head 20260818000381 (or later); knob true; joinable 11; update_rows 1; probe_left 0 (0381's probe company was rolled back);
--   companies_of_pirates: the human companies under the skull now (0 until somebody joins; it grows only by a founding or a change of country);
--   pirate_companies_at: where their fleets lie (a new one: the capital);
--   capital_purse: Port Royal's purse (closed, it falls by starting_ducats for each founding under the skull; nothing else of 0381 moves it);
--   capital_can_pay true (false: the next founding under the skull is refused; the owner tops the purse up or switches the knob off).
-- It reads rule tables, the knob, the companies of one power and one purse. It sums no growing table.
begin transaction read only;
select (select max(version) from supabase_migrations.schema_migrations) as head,
       (select c.value from public.world_config c where c.key = 'pirates_joinable') as knob,
       (select c.updated_at from public.world_config c where c.key = 'pirates_joinable') as lit_at,
       (select count(*) from public.nations n where public.nation_joinable(n.id)) as joinable,
       (select count(*) from public.world_news w where w.key = 'update:0381') as update_rows,
       (select count(*) from public.players pl where not pl.is_npc and public.pirate_power(pl.nation_id)) as companies_of_pirates,
       (select coalesce(jsonb_object_agg(x.at, x.n), '{}'::jsonb)
          from (select coalesce(p.code, 'at sea') as at, count(*) as n
                  from public.players pl join public.fleets f on f.player_id = pl.id left join public.ports p on p.id = f.port_id
                 where not pl.is_npc and public.pirate_power(pl.nation_id) group by 1) x) as pirate_companies_at,
       (select public.treasury_balance(p.id) from public.great_powers g join public.nations n on n.id = g.nation_id join public.ports p on p.code = n.capital_port_code where g.pirate) as capital_purse,
       (select public.treasury_balance(p.id) >= (select (c.value)::text::bigint from public.world_config c where c.key = 'starting_ducats') from public.great_powers g join public.nations n on n.id = g.nation_id join public.ports p on p.code = n.capital_port_code where g.pirate) as capital_can_pay,
       (select count(*) from public.players pl where pl.company_name = 'Probe 0381 Brethren') as probe_left;
commit;
