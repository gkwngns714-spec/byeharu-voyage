-- 0364 FORWARD ROLLBACK, A DRAFT (docs/dev-log/2026-11-13-fight-rings.md). NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number,
-- and deploy it as any migration (owner only). THE FIRST ROLLBACK IS THE SWITCH: attack_enabled false stops new battles, so no ring is drawn once the running ones end. The client
-- needs nothing: a map that cannot reach world.fights keeps its last answer (none) and draws no ring.
-- This draft is the second: it takes the two rows out of the registry (the hunk reversed, judged as a round trip on the live body) and drops the three functions and the index.
-- It writes no table and no knob. Tested locally 2026-11-13 on the cached world at head 0364: after it, the statement of before.sql reads old_times 1, new_times 0, made 0.
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite).
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  c_old constant text := $h$      ('world',       'battle',                'uuid'),
$h$;
  c_new constant text := $h$      ('world',       'battle',                'uuid'),
      -- 0364: every battle being fought, for the map's rings, and any battle's log for a watcher. Reads.
      ('world',       'fights',                ''),
      ('world',       'fight',                 'uuid'),
$h$;
  v_live text;
  v_back text;
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('world.fights()') is null or to_regprocedure('world.fight(uuid)') is null then
    raise exception '0364 rollback refuses: 0364 is not applied in this world';
  end if;
  v_live := replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '');
  if (length(v_live) - length(replace(v_live, c_new, ''))) / length(c_new) is distinct from 1 then
    raise exception '0364 rollback refuses: the registry does not carry the rows of 0364 exactly once';
  end if;
  v_back := replace(v_live, c_new, c_old);
  if replace(v_back, c_old, c_new) is distinct from v_live then
    raise exception '0364 rollback refuses: the hunk does not round-trip on the live registry';
  end if;
  execute v_back;
  drop function world.fights();
  drop function world.fight(uuid);
  drop function public.fight_card(uuid, uuid);
  drop index public.battles_ended;
  raise notice '0364 rollback ok: the two doors are out of the registry; the three functions and the index are dropped.';
end
$r$;
