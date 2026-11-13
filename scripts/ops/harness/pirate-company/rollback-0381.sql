do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
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
