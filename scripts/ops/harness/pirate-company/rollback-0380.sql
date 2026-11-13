do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
-- THE FORWARD ROLLBACK OF 0380, A DRAFT. LOCAL SCENE while it carries the guard line above. To deploy it: copy it into supabase/migrations/ under the next number,
-- delete the guard line and add the line "-- news: none". It reverses 0380's one hunk on world.snapshot (the `pirate` key goes; the client reads the key as
-- optional, so the picker says nothing about the skull again). Refuses unless the live body holds the new text exactly once.
do $m$
declare
  v_def text := replace(pg_get_functiondef('world.snapshot()'::regprocedure), E'\r', '');
  c_old constant text :=
$h$        'joinable', public.nation_joinable(n.id)) order by n.code), '[]'::jsonb)   -- 0028 WIND; GP1: one of the great powers; 0338: one a company may sail for
$h$;
  c_new constant text :=
$h$        'joinable', public.nation_joinable(n.id),                                  -- 0028 WIND; GP1: one of the great powers; 0338: one a company may sail for
        'pirate', public.pirate_power(n.id)) order by n.code), '[]'::jsonb)        -- 0380: THE PIRATE POWER, named once, so the picker can say what the skull costs
$h$;
begin
  if (length(v_def) - length(replace(v_def, c_new, ''))) / length(c_new) <> 1 then
    raise exception 'rollback of 0380 refuses: the live world.snapshot does not hold the text of 0380 once';
  end if;
  execute replace(v_def, c_new, c_old);
  if replace(pg_get_functiondef('world.snapshot()'::regprocedure), E'\r', '') like '%0380%' then
    raise exception 'rollback of 0380 self-assert FAIL: the snapshot still carries 0380';
  end if;
  raise notice 'rollback of 0380 self-assert ok: world.snapshot is its body before 0380';
end
$m$;
