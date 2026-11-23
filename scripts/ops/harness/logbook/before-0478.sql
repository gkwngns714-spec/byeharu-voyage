-- THE LOGBOOK (0478), BEFORE. A PROD CHECK: read-only, ONE statement, small. The gate first (db-health/gate.sql).
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/logbook/before-0478.sql
-- Expect: head 20260818000477; knobs {} (none of the four); table false; fn_absent true; kind_absent true; each of the four hunks' OLD
-- text once (old 1) and its new marker absent (new 0): voyage.settle, cmd.do_sell, public.port_fee, public.client_rpc_entry_points.
-- `lit`: economy_closed, city_treasury_enabled and reputation_on as prod runs them (the dock fee a finished region cuts is charged only
-- while the economy is closed and the purses are lit; a set's Reputation is booked only while reputation_on).
-- THE BACK-FILL the migration writes, read here without writing it (`backfill`): for each company that is not a merchant (players
-- not is_npc), the harbours of her VOYAGE_REPORT events (to, from), her first-landfall Reputation keys and the harbour her fleets lie
-- in; the goods of her SOLD events (by name or code); the classes of her ships; the captains she signed. `events` is how many of her
-- VOYAGE_REPORT / SOLD events the migration reads (its time budget). Merchants (`merchants`) keep no logbook and are not read.
-- Reads: the catalog (four pg_get_functiondef), world_config by key, reputation_kinds, players (humans), their events by the
-- (player_id, created_at) index, reputation_book by player, fleets / ships / player_officers by player, ports / goods / ship_classes /
-- officers. No function that writes is called.
begin transaction read only;
with h(fn, old, new) as (values
  ('voyage.settle(uuid,timestamp with time zone)', '           where z.payload ? ''rounds''));', 'logbook_arrival'),
  ('cmd.do_sell(uuid,jsonb)', '      ''haggle_saved'', q.haggle_saved)));', 'logbook_sale'),
  ('public.port_fee(uuid,uuid,numeric)', '* public.regard_factor(p_player, p_port)))::bigint;', 'logbook_fee_factor'),
  ('public.client_rpc_entry_points()', '      (''world'',       ''early_sighting'',        ''''),', '''logbook''')
), d as (select h.fn, h.old, h.new, replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '') as def from h),
hu as (select p.id from public.players p where not p.is_npc),
ev as (select e.player_id, e.kind, e.payload, e.created_at
         from hu cross join lateral (select x.player_id, x.kind, x.payload, x.created_at from public.events x
                                      where x.player_id = hu.id and x.kind in ('VOYAGE_REPORT', 'SOLD')) e),
hb as (select distinct q.player_id, q.code from (
         select ev.player_id, ev.payload ->> 'to' as code from ev where ev.kind = 'VOYAGE_REPORT'
         union all select ev.player_id, ev.payload ->> 'from' from ev where ev.kind = 'VOYAGE_REPORT'
         union all select rb.player_id, substr(rb.key, 10) from hu join public.reputation_book rb on rb.player_id = hu.id and rb.key like 'landfall:%'
         union all select f.player_id, p.code from hu join public.fleets f on f.player_id = hu.id join public.ports p on p.id = f.port_id where f.status = 'DOCKED'
       ) q join public.ports p on p.code = q.code and p.kind = 'HARBOUR'),
gd as (select distinct ev.player_id, g.code from ev join public.goods g on g.name = ev.payload ->> 'good' or g.code = ev.payload ->> 'good' where ev.kind = 'SOLD')
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select coalesce(jsonb_object_agg(c.key, c.value), '{}'::jsonb) from public.world_config c where c.key like 'logbook\_%'),
  'table', to_regclass('public.logbook') is not null,
  'fn_absent', to_regprocedure('world.logbook()') is null,
  'kind_absent', not exists (select 1 from public.reputation_kinds k where k.code = 'logbook'),
  'hunks', (select jsonb_object_agg(d.fn, jsonb_build_object(
                     'old', (length(d.def) - length(replace(d.def, d.old, ''))) / length(d.old),
                     'new', (length(d.def) - length(replace(d.def, d.new, ''))) / length(d.new))) from d),
  'lit', (select jsonb_object_agg(c.key, c.value) from public.world_config c
           where c.key in ('economy_closed', 'city_treasury_enabled', 'reputation_on', 'rep_landfall', 'rep_built')),
  'companies', (select count(*) from hu),
  'merchants', (select count(*) from public.players p where p.is_npc),
  'events', (select coalesce(jsonb_object_agg(s.kind, s.n), '{}'::jsonb) from (select ev.kind, count(*) as n from ev group by ev.kind) s),
  'backfill', jsonb_build_object(
    'harbours', (select count(*) from hb),
    'goods', (select count(*) from gd),
    'hulls', (select count(distinct (s.player_id, s.class_id)) from hu join public.ships s on s.player_id = hu.id),
    'captains', (select count(*) from hu join public.player_officers o on o.player_id = hu.id),
    'most_harbours', (select coalesce(max(n), 0) from (select count(*) as n from hb group by hb.player_id) x),
    'most_goods', (select coalesce(max(n), 0) from (select count(*) as n from gd group by gd.player_id) x)));
rollback;
