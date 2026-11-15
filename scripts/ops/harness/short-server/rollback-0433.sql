-- 0433 FORWARD ROLLBACK, A DRAFT. NOT a prod check and NOT a migration yet: to use it, strip the guard line, give it the next number, add "-- news: none"
-- and deploy it as any migration (owner only).
-- THE BODIES: every hunk of 0433 reversed (found once in the live body, the new text put back to the old). They are read from the migration file itself
-- by rollback.mjs beside this file, so the rollback cannot drift from what 0433 applied:
--   node scripts/ops/harness/short-server/rollback.mjs > rollback-0433-bodies.sql   (then append it below this file's own block)
-- THE ROWS (this file): the old news templates and voyage prose back, each matched on 0433's words. cmd.refusal_line and cmd.refusal_figure stay
-- (unreached once cmd.refusal is reversed). The six shortened update titles stay short (world_news is append-only).
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $r$
begin
  update public.news_kinds k set en = v.en, ko = v.ko
    from (values
      ('UPDATE', '{title}', 'Update: {title}', '업데이트: {title}'),
      ('NEW_HARBOUR', 'New port: {city}', 'New harbour: {city}', '새 항구: {city}'),
      ('RELATIONS', '{a}–{b}: {stance}', '{a} and {b}: now {stance}', '{a}–{b}: {stance}'),
      ('BIG_SALE', '{company} sold {qty} {good}: {n} · {city}', '{company} sold {qty} {good} at {city}: {n}', '{company}, {city}에 {good} {qty} 판매: {n}'),
      ('BIG_BUY', '{company} bought {qty} {good}: {n} · {city}', '{company} bought {qty} {good} at {city}: {n}', '{company}, {city}에서 {good} {qty} 구매: {n}'),
      ('PRICE_SPIKE', '{good} {p} · {city}', '{good} at {city} {p} in an hour', '{city} {good} 1시간 {p}'),
      ('PIRATES', '{company} raided: {n}', 'Pirates took {n} from {company}', '해적이 {company}에서 {n} 약탈'),
      ('CAPITAL_GIFT', '{capital} → {company}: {n}', '{capital} gave {company} {n}', '{capital}, {company}에 {n} 지원')) v(kind, now_en, en, ko)
   where k.kind = v.kind and k.en = v.now_en;
  update public.voyage_event_kinds k set prose = v.prose, prose_fallbacks = coalesce(v.fb, k.prose_fallbacks)
    from (values
      ('BATTLE', 'Fought: %s hours lost.', 'We hove to and fought, and lost %s hours.', null::text[]),
      ('CALM', 'Becalmed: %s hours lost.', 'The wind died away. We lay becalmed and lost %s hours.', null),
      ('CLEAR', 'Quiet day.', 'A quiet watch; nothing to report.', null),
      ('CONSORT', 'Spoke a ship; swapped news.', 'We spoke a sail on the other tack and swapped what news we had.', null),
      ('DERELICT', 'Salvaged a wreck: %s.', 'A hull lay low in the water, abandoned. We took what we could off her: %s.', null),
      ('FAIR_WIND', 'Fair wind: %s hours gained.', 'A soldier''s wind all day, and she ran her easting down. We made up %s hours.', null),
      ('FORCED_HOME', 'Out of stores: back to %s, hold empty, hulls hurt.', 'The water and the food are gone. We bore up for %s and came in with the hold empty and the hulls hurt.', null),
      ('FOUL_WATER', 'Water spoiled: %s tuns lost.', 'The casks were broached and the water in them had turned. We started %s tuns over the side.', null),
      ('LANDFALL', 'Sighted %s. %s', 'We raised %s and hove to. %s', array['the mark', 'The sea ran empty to every horizon.']),
      ('NAVY', '%s', '%s', array['A navy ship stopped us.']),
      ('PIRATES', 'Pirates. %s', 'Sail sighted to windward. %s', array['They closed with us.']),
      ('SHOAL_WATER', 'Aground: hull −%s.', 'She touched on ground that was on no chart, and came off with %s points off her hull.', null),
      ('SHORT_RATIONS', 'Stores low: short rations, wages up.', 'Stores are low. The crew are on short rations and their wages are up.', null),
      ('STORM', 'Gale: hull −%s.', 'A gale took us on the beam. We ran under bare poles and lost %s points of hull.', null)) v(code, now_prose, prose, fb)
   where k.code = v.code and k.prose = v.now_prose;
  raise notice 'rollback-0433 (rows) ok: the news templates and the voyage prose are 0432''s again; the bodies are rollback.mjs''s output';
end $r$;
