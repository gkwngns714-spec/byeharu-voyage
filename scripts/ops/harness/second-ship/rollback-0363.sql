-- 0363 FORWARD ROLLBACK, A DRAFT (docs/SECOND_SHIP.md S2; docs/dev-log/2026-11-13-second-ship.md). NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it
-- the next number, add its news line (a public.news_update row or "-- news: none"), and deploy it as any migration (owner only). It puts the two part rows of the Barca back, and her old note.
-- WHO IT TOUCHES: after it a Barca asks for a Suit of Sails and an Anchor & Cable again. It writes to no row of any player. A company that stored the four hull goods under 0363 keeps
-- them and must then make the two parts; a Barca already built stays built. data/hulls.json must go back in the same PR (the world guard).
-- Tested locally: the self-assert of 0363 plays these two statements inside its probe (the yard then refuses E_NO_FITTINGS), proofs 61 and 65 run on a world with the rows put back,
-- and this file itself was run on the local world after 0363 (dev-log).
-- LOCAL PGlite WORLD ONLY while it carries this line (scripts/ops/harness/README.md): it writes. The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite).
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
declare
  v_n int;
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);
  if exists (select 1 from public.hull_recipe_items hi where hi.class_code = 'barca')
     or (select r.note from public.hull_recipes r where r.class_code = 'barca') is distinct from 'A coaster. A stack of deal boards, tar, cordage and nails - the hull a house builds first.' then
    raise exception '0363 rollback refuses: the recipe of the Barca is not as 0363 left it (0363 is not applied, or it was rolled back once)';
  end if;
  insert into public.hull_recipe_items (class_code, item_code, qty) values ('barca', 'suit-of-sails', 1), ('barca', 'anchor-and-cable', 1);
  get diagnostics v_n = row_count;
  if v_n <> 2 then raise exception '0363 rollback FAIL: % row(s) put back, not 2', v_n; end if;
  update public.hull_recipes r set note = 'A coaster. Two fittings and a stack of deal boards - the hull a house builds first.' where r.class_code = 'barca';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception '0363 rollback FAIL: % note(s) put back, not 1', v_n; end if;
  if (select jsonb_agg(jsonb_build_object('item', hi.item_code, 'qty', hi.qty) order by hi.item_code) from public.hull_recipe_items hi where hi.class_code = 'barca')
       is distinct from '[{"item": "anchor-and-cable", "qty": 1}, {"item": "suit-of-sails", "qty": 1}]'::jsonb then
    raise exception '0363 rollback FAIL: the parts of the Barca are not the two rows 0363 deleted';
  end if;
  raise notice '0363 rollback self-assert ok: the Barca takes a Suit of Sails and an Anchor & Cable again, and her note is the old one. No row of any player was written.';
end
$r$;
