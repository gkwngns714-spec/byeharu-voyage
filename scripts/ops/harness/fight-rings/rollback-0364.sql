-- 0364 FORWARD ROLLBACK, A DRAFT (docs/dev-log/2026-11-13-fight-rings.md). NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number,
-- and deploy it as any migration (owner only). The client needs nothing: a map that cannot reach world.fights keeps its last answer (none) and draws no ring.
-- It reverses both hunks (the registry's two rows, and the one line in public.navy_fight; each judged as a round trip on the live body) and drops the four functions, the table of
-- kept navy fights with its rows, and the index. It writes no knob. The navy's fights go on exactly as they did: the line it removes decided nothing.
-- Tested locally 2026-11-13 on the cached world at head 0364: after it, the statement of before.sql reads old_times 1, new_times 0, made 0 on both rows.
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite).
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  h      record;
  v_live text;
  v_back text;
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('world.fights()') is null or to_regprocedure('world.fight(uuid)') is null or to_regclass('public.navy_fight_log') is null then
    raise exception '0364 rollback refuses: 0364 is not applied in this world';
  end if;
  for h in select * from (values
      ('public.client_rpc_entry_points()'::text, $h$      ('world',       'battle',                'uuid'),
$h$::text, $h$      ('world',       'battle',                'uuid'),
      -- 0364: every battle being fought, for the map's rings, and any battle's log for a watcher. Reads.
      ('world',       'fights',                ''),
      ('world',       'fight',                 'uuid'),
$h$::text),
      ('public.navy_fight(uuid,uuid,timestamp with time zone)', $h$  update public.pirate_ships x set fought_at = p_now where x.fleet_id = p_pirate;
$h$, $h$  update public.pirate_ships x set fought_at = p_now where x.fleet_id = p_pirate;
  perform public.navy_fight_keep(p_navy, p_pirate, v_a, v_b, v_f, p_now);   -- 0364: the fight's log and its place, kept for the map (it never raises and moves nothing of the fight)
$h$)) x(fn, old, new) loop
    v_live := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    if (length(v_live) - length(replace(v_live, h.new, ''))) / length(h.new) is distinct from 1 then
      raise exception '0364 rollback refuses: % does not carry the text of 0364 exactly once', h.fn;
    end if;
    v_back := replace(v_live, h.new, h.old);
    if replace(v_back, h.old, h.new) is distinct from v_live then
      raise exception '0364 rollback refuses: the hunk of % does not round-trip on the live body', h.fn;
    end if;
    execute v_back;
  end loop;
  drop function world.fights();
  drop function world.fight(uuid);
  drop function public.fight_card(uuid, uuid);
  drop function public.navy_fight_keep(uuid, uuid, jsonb, jsonb, jsonb, timestamptz);
  drop table public.navy_fight_log;
  drop index public.battles_ended;
  raise notice '0364 rollback ok: both hunks are reversed; the four functions, the table and the index are dropped.';
end
$r$;
