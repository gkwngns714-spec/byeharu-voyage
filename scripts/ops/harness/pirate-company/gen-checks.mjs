// gen-checks.mjs — writes the prod checks and the rollback drafts of 0380 (the snapshot names the pirate power) and 0381 (lights pirates_joinable).
//
//   node scripts/ops/harness/pirate-company/gen-checks.mjs
//
// 0380's hunk is read out of the migration itself (its c_old and c_new constants), so before.sql, after.sql and rollback-0380.sql test and reverse the very
// text the file applies. Every *.sql it writes is one of the harness's two classes (README.md): a PROD CHECK (one read-only statement between
// `begin transaction read only;` and `commit;`) or a LOCAL SCENE (the guard line first).
import { readFile, readdir, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const MIGRATIONS = path.resolve(HERE, '..', '..', '..', '..', 'supabase', 'migrations')
const file = (await readdir(MIGRATIONS)).find((f) => f.startsWith('20260818000380_'))
const sql = (await readFile(path.join(MIGRATIONS, file), 'utf8')).replaceAll('\r', '')
const hunk = (name) => {
  const m = new RegExp(`${name}\\s+constant text :=\\n\\$h\\$([\\s\\S]*?)\\$h\\$;`).exec(sql)
  if (!m) throw new Error(`0380 holds no ${name}`)
  return m[1]
}
const OLD = hunk('c_old')
const NEW = hunk('c_new')
const GUARD = `do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;`
const RUN = (f) => `npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/pirate-company/${f}`
const CAPITAL = `public.great_powers g join public.nations n on n.id = g.nation_id join public.ports p on p.code = n.capital_port_code where g.pirate`
const START = `(select (c.value)::text::bigint from public.world_config c where c.key = 'starting_ducats')`

const out = {}

out['volatility.sql'] = `-- 0380 / 0381 PROD CHECK (run FIRST, either side of either deploy), read-only, ONE statement: ${RUN('volatility.sql')}
-- Wanted: every value 's' or 'i'. These are the functions the other check files here call; one that reads 'v' must not be selected on prod.
begin transaction read only;
select jsonb_object_agg(f.name, (select p.provolatile from pg_proc p where p.oid = to_regprocedure(f.name))) as volatility
  from unnest(array['world.snapshot()', 'public.treasury_balance(uuid)', 'public.pirate_power(uuid)', 'public.nation_joinable(uuid)', 'public.port_nation(uuid)',
                    'public.economy_closed()', 'public.city_treasury_on()', 'public.port_is_free(uuid)']) f(name);
commit;
`

out['before.sql'] = `-- 0380 PROD CHECK (before the deploy), read-only, ONE statement: ${RUN('before.sql')}
-- Wanted: head is the migration before 0380 in the deploy order; old_times 1 and new_times 0 (the live world.snapshot is the body the hunk was cut against, and
-- 0380 is not in); pirate_power_volatility 's'; pirate_powers 1; knob false. now_md5 is the live body's hash: keep it, after.sql's without_hunk_md5 must equal it.
begin transaction read only;
select (select max(version) from supabase_migrations.schema_migrations) as head,
       (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old) as old_times,
       (length(d.def) - length(replace(d.def, h.new, ''))) / length(h.new) as new_times,
       md5(d.def) as now_md5,
       (select p.provolatile from pg_proc p where p.oid = 'public.pirate_power(uuid)'::regprocedure) as pirate_power_volatility,
       (select count(*) from public.great_powers g where g.pirate) as pirate_powers,
       (select c.value from public.world_config c where c.key = 'pirates_joinable') as knob
  from (select replace(pg_get_functiondef('world.snapshot()'::regprocedure), E'\\r', '') as def) d,
       (select $h$${OLD}$h$ as old,
               $h$${NEW}$h$ as new) h;
commit;
`

out['after.sql'] = `-- 0380 PROD CHECK (after the deploy), read-only, ONE statement: ${RUN('after.sql')}
-- Wanted: head 20260818000380 (or later); new_times 1 and old_times 0; without_hunk_md5 = before.sql's now_md5; volatility 's'; pirates ["PIR"]; nations 24;
-- joinable 10 (11 once 0381 is in); knob false (true once 0381 is in): 0380 itself sets no knob.
begin transaction read only;
select (select max(version) from supabase_migrations.schema_migrations) as head,
       (length(d.def) - length(replace(d.def, h.new, ''))) / length(h.new) as new_times,
       (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old) as old_times,
       md5(replace(d.def, h.new, h.old)) as without_hunk_md5,
       (select p.provolatile from pg_proc p where p.oid = 'world.snapshot()'::regprocedure) as volatility,
       (select jsonb_agg(e.value ->> 'code' order by e.value ->> 'code') from jsonb_array_elements(world.snapshot() -> 'nations') e where (e.value ->> 'pirate')::boolean) as pirates,
       (select count(*) from jsonb_array_elements(world.snapshot() -> 'nations') e) as nations,
       (select count(*) from jsonb_array_elements(world.snapshot() -> 'nations') e where (e.value ->> 'joinable')::boolean) as joinable,
       (select c.value from public.world_config c where c.key = 'pirates_joinable') as knob
  from (select replace(pg_get_functiondef('world.snapshot()'::regprocedure), E'\\r', '') as def) d,
       (select $h$${OLD}$h$ as old,
               $h$${NEW}$h$ as new) h;
commit;
`

out['before-light.sql'] = `-- 0381 PROD CHECK (BEFORE lighting pirates_joinable), read-only, ONE statement: ${RUN('before-light.sql')}
-- Wanted, or do not light:
--   snapshot_names_pirates true (0380 is live: 0381 refuses without it); knob false; joinable 10; update_rows 0;
--   capital 'POR', capital_held_by_pirates true, pirate_homes 4;
--   closed and purses as production runs them; capital_can_pay true (closed, Port Royal's purse must hold starting_ducats: it pays every founding under the skull
--     and every gift to a broke pirate company; if false a founding under the skull is refused, and 0381's own probe stops the file);
--   companies_of_pirates 0 (no human company sails for them yet: any other figure means the knob was lit before);
--   switches: regard_enabled as the lead means it (lit, it puts the Wary band's factor on her war factor), attack_enabled false, the rest for the record;
--   war_factor x wary_factor is what a crown port asks of her on its tax and dock fee; war_regard_base is where her regard with every crown starts.
begin transaction read only;
select (select max(version) from supabase_migrations.schema_migrations) as head,
       (select p.prosrc like '%0380: THE PIRATE POWER%' from pg_proc p where p.oid = 'world.snapshot()'::regprocedure) as snapshot_names_pirates,
       (select c.value from public.world_config c where c.key = 'pirates_joinable') as knob,
       (select count(*) from public.nations n where public.nation_joinable(n.id)) as joinable,
       (select n.capital_port_code from ${CAPITAL}) as capital,
       (select public.port_nation(p.id) = g.nation_id from ${CAPITAL}) as capital_held_by_pirates,
       (select count(*) from public.ports p where p.kind = 'HARBOUR' and public.port_is_free(p.id)) as pirate_homes,
       public.economy_closed() as closed,
       public.city_treasury_on() as purses,
       (select public.treasury_balance(p.id) from ${CAPITAL}) as capital_purse,
       (select public.treasury_balance(p.id) >= ${START} from ${CAPITAL}) as capital_can_pay,
       (select count(*) from public.players pl where not pl.is_npc and public.pirate_power(pl.nation_id)) as companies_of_pirates,
       (select jsonb_object_agg(c.key, c.value) from public.world_config c
         where c.key in ('regard_enabled', 'attack_enabled', 'pirates_bite', 'pirate_ports_free', 'navy_enabled', 'navy_hunt_per_day', 'starting_ducats', 'nation_change_cooldown_days')) as switches,
       (select (c.value ->> 'war')::numeric from public.world_config c where c.key = 'country_tax_factor') as war_factor,
       (select (b.value ->> 'factor')::numeric from public.world_config c cross join lateral jsonb_array_elements(c.value) b where c.key = 'regard_bands' and b.value ->> 'band' = 'wary') as wary_factor,
       (select (c.value ->> 'war')::numeric from public.world_config c where c.key = 'regard_stance_base') as war_regard_base,
       (select count(*) from public.world_news w where w.key = 'update:0381') as update_rows;
commit;
`

out['after-light.sql'] = `-- 0381 PROD CHECK (AFTER lighting pirates_joinable: at once, then at +5 and +30 minutes), read-only, ONE statement: ${RUN('after-light.sql')}
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
       (select public.treasury_balance(p.id) from ${CAPITAL}) as capital_purse,
       (select public.treasury_balance(p.id) >= ${START} from ${CAPITAL}) as capital_can_pay,
       (select count(*) from public.players pl where pl.company_name = 'Probe 0381 Brethren') as probe_left;
commit;
`

out['rollback-0380.sql'] = `${GUARD}
-- THE FORWARD ROLLBACK OF 0380, A DRAFT. LOCAL SCENE while it carries the guard line above. To deploy it: copy it into supabase/migrations/ under the next number,
-- delete the guard line and add the line "-- news: none". It reverses 0380's one hunk on world.snapshot (the \`pirate\` key goes; the client reads the key as
-- optional, so the picker says nothing about the skull again). Refuses unless the live body holds the new text exactly once.
do $m$
declare
  v_def text := replace(pg_get_functiondef('world.snapshot()'::regprocedure), E'\\r', '');
  c_old constant text :=
$h$${OLD}$h$;
  c_new constant text :=
$h$${NEW}$h$;
begin
  if (length(v_def) - length(replace(v_def, c_new, ''))) / length(c_new) <> 1 then
    raise exception 'rollback of 0380 refuses: the live world.snapshot does not hold the text of 0380 once';
  end if;
  execute replace(v_def, c_new, c_old);
  if replace(pg_get_functiondef('world.snapshot()'::regprocedure), E'\\r', '') like '%0380%' then
    raise exception 'rollback of 0380 self-assert FAIL: the snapshot still carries 0380';
  end if;
  raise notice 'rollback of 0380 self-assert ok: world.snapshot is its body before 0380';
end
$m$;
`

out['rollback-0381.sql'] = `${GUARD}
-- THE ROLLBACK OF 0381, A DRAFT. LOCAL SCENE while it carries the guard line above. On production it is the owner's one line (CLAUDE.md: a knob is the owner's):
--   update public.world_config set value = 'false'::jsonb where key = 'pirates_joinable' returning key, value;
-- After it the picker offers the ten again at the next load and nobody new may join. NOT UNDONE: a company that joined stays a company of the Brethren until she
-- changes country herself, and the influence she gave under the skull stays with the Brethren.
update public.world_config set value = 'false'::jsonb, updated_at = now() where key = 'pirates_joinable';
do $m$
begin
  if exists (select 1 from public.nations n join public.great_powers g on g.nation_id = n.id where g.pirate and public.nation_joinable(n.id)) then
    raise exception 'rollback of 0381 self-assert FAIL: the Brethren are still joinable';
  end if;
  raise notice 'rollback of 0381 self-assert ok: pirates_joinable is false';
end
$m$;
`

for (const [name, text] of Object.entries(out)) {
  await writeFile(path.join(HERE, name), text)
  console.log(`wrote ${name}`)
}
