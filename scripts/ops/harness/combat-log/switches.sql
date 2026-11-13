-- 0353 PROD CHECK (switches), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/combat-log/switches.sql
-- READ THIS FIRST (docs/COMBAT_LOG.md 0.1, 7 R1; docs/SUCCESS_PLAN.md section 4: two reports disagree on combat_bite).
-- combat_bite false: a raid is settled by DESIGN B.6's table, no fight is fought, and C1 and C2 show NOTHING until the fight is lit (its own step, with raid/after-check.sh).
-- city_treasury_enabled false: Pay has no payee and is refused (she fights). pirates_bite false: every raid is anonymous and a Pay goes to the Brethren's capital.
-- Wanted, to know what the deploy will show: every row printed; nothing is asserted here. Only world_config is read.
begin transaction read only;
select c.key, c.value, c.updated_at
  from public.world_config c
 where c.key in ('combat_bite', 'armour_turns_pct', 'pirates_bite', 'attack_enabled', 'navy_enabled', 'ransom_share', 'time_compression',
                 'city_treasury_enabled', 'economy_closed', 'pirate_hoard_cap', 'attack_word_bands', 'sea_danger_bands', 'raid_orders_enabled')
    or c.key like 'fight%'
 order by c.key;
commit;
