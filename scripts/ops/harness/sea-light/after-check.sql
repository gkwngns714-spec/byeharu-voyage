-- 0393 PROD CHECK (the window after sea_conditions_bite is lit), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-light/after-check.sql
-- Run at +1, +5 and +30 minutes after `select public.sea_conditions_light()`, beside `bash scripts/ops/health.sh`. Compare with before.sql's row. What to read:
--   switch                   true
--   news_row                 1 (update:0393)
--   fleets_in_closed_seas    TOLD (no longer wanted 0: the way home, 0391, lets such a fleet sail her own waters; it was 1 on prod before the light). Before the way home: a company's fleet lying in, or under way to, a sea that refuses her cannot leave it. It was 0 at the light
--                            (the step's guard); above 0 afterwards means she got there after the light, which the gate should have refused: ROLL BACK and read why.
--   sea_refusals_since       QUEUED orders of companies refused E_SEA_CLOSED when they ran, since the light, by the sea that refused. A plan refused at the
--                            press (cmd.issue_lines refuses the whole plan and queues nothing) is told to the page and WRITTEN NOWHERE, so it is not counted
--                            here: this figure is only the SAILs already queued at the light, or queued through a path that did not ask first. Expected: at
--                            most before.sql's queued_sails_closed. More means a page queued a SAIL the gate then refused: note which company and screen.
--   refusals_1h              every code of companies' failed orders over the last hour, against the baseline: only E_SEA_CLOSED should be new.
--   departures_1h            departures of companies over the last hour, against the baseline: a fall to 0 with players online is the rollback signal.
--   merchant_refusals        merchants refused E_SEA_CLOSED since the light. WANTED 0, always (the door never judges a merchant).
--   beats                    the arrivals beat over the last 30 minutes: WANTED errors 0, avg_ms <= 3000, p95_ms < 5000, no worse than the baseline.
-- ROLLBACK, at once (owner): update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite' returning key, value;
begin transaction read only;
with lit as (
  select coalesce((select min(n.at) from public.world_news n where n.key = 'update:0393'), now()) as at
)
select now() as read_at,
       (select value from public.world_config where key = 'sea_conditions_bite') as switch,
       (select at from lit) as lit_at,
       (select count(*) from public.world_news n where n.key = 'update:0393') as news_row,
       (public.sea_conditions_ready() ->> 'fleets_in_closed_seas')::int as fleets_in_closed_seas,
       public.sea_conditions_ready() -> 'first_fleets' as first_fleets,
       (public.sea_conditions_ready() ->> 'queued_sails_closed')::int as queued_sails_closed,
       (select coalesce(jsonb_object_agg(q.sea, q.n), '{}'::jsonb)
          from (select coalesce(o.error_figures ->> 'zone_name', '?') as sea, count(*) as n
                  from public.orders o join public.players p on p.id = o.player_id and not p.is_npc, lit
                 where o.error_code = 'E_SEA_CLOSED' and o.issued_at >= lit.at group by 1) q) as sea_refusals_since,
       (select count(distinct o.player_id) from public.orders o join public.players p on p.id = o.player_id and not p.is_npc, lit
         where o.error_code = 'E_SEA_CLOSED' and o.issued_at >= lit.at) as companies_refused_since,
       (select coalesce(jsonb_object_agg(q.code, q.n), '{}'::jsonb)
          from (select o.error_code as code, count(*) as n from public.orders o join public.players p on p.id = o.player_id and not p.is_npc
                 where o.status = 'failed' and o.issued_at >= now() - interval '1 hour' group by o.error_code) q) as refusals_1h,
       (select count(*) from public.voyages v join public.players p on p.id = v.player_id and not p.is_npc where v.departed_at >= now() - interval '1 hour') as departures_1h,
       (select count(*) from public.orders o join public.players p on p.id = o.player_id and p.is_npc, lit
         where o.error_code = 'E_SEA_CLOSED' and o.issued_at >= lit.at) as merchant_refusals,
       (select jsonb_build_object('n', count(*), 'avg_ms', round(avg(b.ms)::numeric, 1), 'p95_ms', round((percentile_cont(0.95) within group (order by b.ms))::numeric, 1),
                                  'errors', count(*) filter (where b.error is not null))
          from public.arrivals_beats b where b.at >= now() - interval '30 minutes') as beats;
commit;
