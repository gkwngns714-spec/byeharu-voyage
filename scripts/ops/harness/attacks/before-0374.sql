-- 0374 PROD CHECK (before and after), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/attacks/before-0374.sql
-- 0374 re-cuts ONE line of public.loot_take and ONE line of public.battle_sheet_freeze, and makes two functions and two knobs. Two rows, one a body. The same file is run before
-- the deploy and after it. For the freeze's row old_times is 1 both times (the new text begins with the old line): read new_times.
--   BEFORE: old_times 1, new_times 0 on both rows (each line 0374 replaces is in its live body exactly once, and nothing of 0374 is there), made 0, knobs 0, attack false, loot_callers 1
--           (public.attack_close is the only body that calls public.loot_take), head = the migration before 0374. Keep `body` for the dev-log.
--   AFTER:  new_times 1 on both rows (old_times 0 for public.loot_take), made 2 (public.loot_risk, public.attack_ready), knobs 2, client_fns 0 (neither new function, nor public.loot_take, can be called by a client),
--           attack false (0374 lights nothing), head 0374.
-- Only the catalog and world_config are read. Every function called is STABLE or IMMUTABLE (public.attack_on; the catalog's own).
begin transaction read only;
with h(fn, old, new) as (values ('public.loot_take(uuid,uuid,text,timestamp with time zone)'::text,
$h$  v_take := public.loot_due(p_outcome, v_left, public.loot_today(p_player, p_now));
$h$::text,
$h$  -- 0374: LOOT FOLLOWS THE RISK TAKEN (public.loot_risk): what is aboard counts for the share of her own hull the attacker lost in this fight, whole at loot_risk_full.
  -- Read from the kept result of the battle this ship was set upon in (public.battle_resolve writes it before the close). The caps are public.loot_due's, as they were.
  v_take := public.loot_due(p_outcome,
                            floor(v_left * public.loot_risk((select b.result from public.battle_sides bs join public.battles b on b.id = bs.battle_id
                                                               where bs.fleet_id = p_fleet and bs.side = 'DEFENDER' and bs.how = 'OPENED' and b.kind = 'ATTACK'
                                                               order by b.started_at desc, b.id desc limit 1)))::bigint,
                            public.loot_today(p_player, p_now));
$h$::text),
  ('public.battle_sheet_freeze(uuid,timestamp with time zone)',
$h$            where bs.battle_id = p_battle and bs.arrives_at <= p_now
$h$,
$h$            where bs.battle_id = p_battle and bs.arrives_at <= p_now
              and bs.how <> 'CALLED'   -- 0374: a called ship joins through public.battle_advance alone (round 1 if she is there already), once and marked: frozen here too she fought as two
$h$)),
d as (select h.*, replace(pg_get_functiondef(to_regprocedure(h.fn)), chr(13), '') as def from h)
select d.fn,
       (length(d.def) - length(replace(d.def, d.old, ''))) / length(d.old) as old_times,
       (length(d.def) - length(replace(d.def, d.new, ''))) / length(d.new) as new_times,
       (select count(*) from unnest(array['public.loot_risk(jsonb)', 'public.attack_ready()']) f where to_regprocedure(f) is not null) as made,
       (select count(*) from public.world_config c where c.key in ('loot_risk_full', 'loot_risk_floor')) as knobs,
       (select jsonb_object_agg(c.key, c.value) from public.world_config c where c.key in ('loot_risk_full', 'loot_risk_floor')) as knob_values,
       (select count(*) from unnest(array['public.loot_risk(jsonb)', 'public.attack_ready()', 'public.loot_take(uuid,uuid,text,timestamp with time zone)']) f
         where to_regprocedure(f) is not null and (has_function_privilege('anon', to_regprocedure(f), 'execute') or has_function_privilege('authenticated', to_regprocedure(f), 'execute'))) as client_fns,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind = 'f' and p.prosrc like '%public.loot_take(%' and p.proname <> 'loot_take') as loot_callers,
       public.attack_on() as attack,
       md5(d.def) as body,
       (select max(version) from supabase_migrations.schema_migrations) as head
  from d order by d.fn;
commit;
