-- HOUSES' BOARD (0467), BEFORE. A PROD CHECK: read-only, ONE statement, small. The gate first (db-health/gate.sql).
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/houses-board/before-0467.sql
-- Reads: players where not is_npc (about 19 rows, by the is_npc filter on a table of about 1,700), auth.users by primary key for those rows,
-- npc_houses' count, and history_company_day for THIS WEEK of the ~19 companies plus its total rows (one count of a small table).
-- No name, no address. It answers: how a test company is told from a played one, and that history_company_day is filled on production.
begin transaction read only;
with c as (
  select p.id, p.auth_uid is null as no_uid,
         exists (select 1 from auth.users u where u.id = p.auth_uid) as has_login,
         left(coalesce(p.auth_uid::text, ''), 9) = '00000000-' as probe_uid
    from public.players p where not p.is_npc
), wk as (select date_trunc('week', (now() at time zone 'UTC'))::date as w)
select jsonb_build_object(
  'companies', (select jsonb_agg(jsonb_build_object('no_uid', g.no_uid, 'has_login', g.has_login, 'probe_uid', g.probe_uid, 'n', g.n))
                  from (select no_uid, has_login, probe_uid, count(*) as n from c group by 1, 2, 3) g),
  'houses', (select count(*) from public.npc_houses),
  'week', (select w from wk),
  'history_rows', (select count(*) from public.history_company_day),
  'history_days', (select jsonb_build_object('min', min(day), 'max', max(day)) from public.history_company_day),
  'week_rows_companies', (select count(*) from public.history_company_day h join c on c.id = h.player_id, wk where h.day >= wk.w),
  'mark', (select to_jsonb(m) from public.history_mark m));
rollback;
