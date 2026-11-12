-- 0353 PROD CHECK (payee), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/combat-log/payee.sql
-- Is there someone to take a ransom she chooses to pay? (docs/COMBAT_LOG.md 2.4.) Run volatility.sql first: every function here must be 's'.
-- Wanted, for Pay to be taken once the switch is lit: capital not null, purses_lit true, hoard below hoard_cap. If any fails, a Pay is refused (NO_PAYEE) and she fights:
-- the picker still offers Pay and the log says why. pirates_bite false means no raider is named: every Pay goes to the capital.
begin transaction read only;
select public.pirate_capital() as capital,
       (select p.code from public.ports p where p.id = public.pirate_capital()) as capital_code,
       public.city_treasury_on() as purses_lit,
       public.pirate_hoard() as hoard,
       public.wc_num('pirate_hoard_cap') as hoard_cap,
       public.wc('pirates_bite') as pirates_bite,
       public.wc_num('ransom_share') as ransom_share;
commit;
