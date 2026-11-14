-- ROLLBACK DRAFT for 0418 (forward, OWNER ONLY; never run by an agent). Puts public.pirate_add back to its 0414 body (the two hunks reversed) and drops public.pirate_add_roster.
-- After it, the add again stops while the head of the queue needs the day's room (0414's behaviour). Roster fleets already built stay (a built fleet stands for ever).
-- As a migration it would be prod head + 1, with its own self-assert; this file is the body of that migration.
do $r$
declare
  v_def text := replace(pg_get_functiondef('public.pirate_add(timestamp with time zone)'::regprocedure), E'\r', '');
  v_new1 text := $h$      return public.pirate_add_roster(p_now);   -- 0418: a wake the day's room cannot pay does not hold the roster back: the next roster fleet is built instead, outside the room
$h$;
  v_new2 text := $h$      return case when exists (select 1 from public.pirate_roster r where r.ord = v_ord) then null else public.pirate_add_roster(p_now) end;   -- 0418: a 0339 hull the day's room cannot pay does not hold the roster back
$h$;
begin
  if (length(v_def) - length(replace(v_def, v_new1, ''))) / length(v_new1) <> 1 or (length(v_def) - length(replace(v_def, v_new2, ''))) / length(v_new2) <> 1 then
    raise exception 'rollback-0418 refuses: public.pirate_add is not the body 0418 left';
  end if;
  v_def := replace(replace(v_def, v_new1, E'      return null;\n'), v_new2, E'      return null;\n');
  execute v_def;
  drop function public.pirate_add_roster(timestamp with time zone);
  raise notice 'rollback-0418 ok: public.pirate_add is 0414''s again; public.pirate_add_roster dropped';
end
$r$;
