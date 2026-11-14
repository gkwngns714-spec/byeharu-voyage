-- 0408 PROD CHECK, BEFORE the deploy AND AGAIN AFTER IT (the same read; after.sql is this file under its own name), read-only, ONE statement:
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/pirate-gift/before.sql
-- One row, one jsonb column `r`.
-- BEFORE, wanted: head 20260818000407; applied false; hunks: every count 1 (each old text once in the live body: prod's bodies are the pre-images);
--   volatility s (every function this read calls); economy_closed and pirates_on true; pirate_capital POR; on_roster 0;
--   pirates.gifts_7d 0. Write down pirates.broke, pirates.under_100 and laid_up (2026-11-14 08:39 UTC: 24 houses, 15 broke, 13 under 100 d., 13 laid up; room_today 4,773,280).
-- AFTER, wanted: head 20260818000408; applied true; hunks 1: 0, 2: 1, 3: 1 (0341's line is gone; the other two old texts stand inside the new). Then, at the first hourly pass (the reconcile, minute 7 of the hour):
--   pirates.gifts_7d rises by up to pirates.broke (each 250,000 d.), spend_today rises by the same ducats, pirates.under_100 falls toward 0, and within
--   the hour after (a broke laid-up merchant is asked once in fifty minutes, 0407) laid_up falls as they sail. on_roster is who still waits: more than 0
--   a pass after the deploy means the day's room is spent (room_today under 250,000): they are paid after 00:00 UTC.
--   crowns.gifts_24h is the crowns' own pass, unchanged by this file: about what it was before.
-- AT +24 h AND +7 d: pirates.gifts_7d is at most 3 a house; hoard has fallen by gifts x 250,000 at most and never by more than room a day;
--   if the same houses are broke again the cause is their loops (0406, 0409), not this rule.
begin transaction read only;
with hk(ord, fn, old) as (values
  (1, 'public.capital_gift_roster(timestamp with time zone,uuid)', E'       and (h.human or not public.pirate_power(pl.nation_id))   -- 0341 (W18): a merchant of the pirates is never gifted: the hoard pays her founding and nothing after (docs/WORLD_POWERS.md 7.4, decided by default)\n'),
  (2, 'public.capital_gift_one(timestamp with time zone,uuid)', E'      v_res := public.capital_pays(r.cap_id, r.nation_id, r.player_id, ''CAPITAL_GIFT'', r.capital, null, false,\n                 jsonb_build_object(''kind'', ''CAPITAL_GIFT'', ''payload'', jsonb_build_object(\n                   ''port'', r.cap_code, ''port_name'', r.cap_name, ''ducats'', r.capital, ''worth'', r.worth)));\n      if v_res ? ''waiting'' then\n'),
  (3, 'public.capital_gift_one(timestamp with time zone,uuid)', E'      when others then\n        v_fail := v_fail + 1;\n')
), body as (
  select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def
    from (values ('public.capital_gift_roster(timestamp with time zone,uuid)'), ('public.capital_gift_one(timestamp with time zone,uuid)')) f(fn)
), pm as (
  select nh.player_id, nh.capital, pl.ducats,
         (select count(*) from public.capital_gifts g where g.player_id = nh.player_id and g.created_at > now() - interval '7 days') as gifts_7d,
         exists (select 1 from public.npc_fleets nf join public.standing_routes sr on sr.id = nf.route_id where nf.player_id = nh.player_id and sr.paused_reason = 'laid_up') as laid_up
    from public.npc_houses nh join public.players pl on pl.id = nh.player_id and pl.is_npc
   where public.pirate_power(pl.nation_id)
)
select jsonb_build_object(
  'at', now(),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'applied', (select position('0408' in b.def) > 0 from body b where b.fn = 'public.capital_gift_one(timestamp with time zone,uuid)'),
  'hunks', (select jsonb_object_agg(hk.ord, (length(b.def) - length(replace(b.def, hk.old, ''))) / length(hk.old)) from hk join body b on b.fn = hk.fn),
  'bodies', (select jsonb_object_agg(b.fn, md5(b.def)) from body b),
  'volatility', (select jsonb_object_agg(p.oid::regprocedure::text, p.provolatile)
                   from pg_proc p where p.oid in ('public.capital_gift_roster(timestamp with time zone,uuid)'::regprocedure, 'public.pirate_power(uuid)'::regprocedure,
                                                  'public.pirate_capital()'::regprocedure, 'public.pirate_hoard()'::regprocedure, 'public.pirate_spend_room(timestamp with time zone)'::regprocedure,
                                                  'public.economy_closed()'::regprocedure, 'public.pirates_on()'::regprocedure, 'public.wc_num(text)'::regprocedure, 'public.wc_int(text)'::regprocedure,
                                                  'pg_catalog.pg_get_functiondef(oid)'::regprocedure)),
  'knobs', (select jsonb_object_agg(w.key, w.value) from public.world_config w
             where w.key in ('merchant_broke_pct', 'gift_max_per_week', 'gift_cooldown_hours', 'gift_max_per_hour', 'pirate_spend_day_pct', 'pirate_merchant_capital', 'npc_ask_broke_under')),
  'economy_closed', public.economy_closed(), 'pirates_on', public.pirates_on(),
  'pirate_capital', (select p.code from public.ports p where p.id = public.pirate_capital()),
  'hoard', public.pirate_hoard(), 'room_today', public.pirate_spend_room(now()),
  'spend_today', (select d.spent from public.pirate_spend_day d where d.day = (now() at time zone 'UTC')::date),
  'on_roster', (select count(*) from public.capital_gift_roster(now()) g join pm on pm.player_id = g.player_id),
  'pirates', (select jsonb_build_object('houses', count(*), 'broke', count(*) filter (where pm.ducats < pm.capital * public.wc_num('merchant_broke_pct')),
                                        'under_100', count(*) filter (where pm.ducats < 100), 'laid_up', count(*) filter (where pm.laid_up),
                                        'gifts_7d', coalesce(sum(pm.gifts_7d), 0), 'gifts_7d_max_a_house', max(pm.gifts_7d), 'purses', coalesce(sum(pm.ducats), 0)) from pm),
  'crowns', (select jsonb_build_object('gifts_24h', count(*), 'ducats_24h', coalesce(sum(g.ducats), 0)) from public.capital_gifts g
              where g.created_at > now() - interval '24 hours' and not exists (select 1 from pm where pm.player_id = g.player_id))
) as r;
commit;
