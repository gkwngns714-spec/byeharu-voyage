-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0062 — A GOOD COMES FROM SOMEWHERE
--        Every trade good gains the regions that PRODUCE it and the ports that RE-EXPORT it, and
--        the roster stops being a seeded hash draw: a port offers what its own coast grew, or a
--        cargo history can name it as an entrepot for. Nothing else.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM ─────────────────────────────────────────────────────────────────────────
--   "Also the 243 trade goods, they should be regional, meaning that for example rice - was a main
--    food in eastern asia and india, haggis for example is only in scotland, unique, etc. I want
--    something like this not a bunch of list with randomness. I want uniqueness taylored to a
--    location. make a list, make a table, file, and orgnize and show how you've organized"
--
-- The owner names TWO classes in one breath and the design must express both, not flatten them:
-- rice is BROAD (eight regions grow it), a Banda nutmeg is SINGULAR (one archipelago, and the good's
-- own note says the VOC seized it outright in 1621). `goods.origin_regions` is what tells them
-- apart: 83 of 243 goods name exactly one region; rice names eight; salt names twenty-one.
--
-- ── AND THE AUDIT SAYS THE SAME THING IN ONE LINE ─────────────────────────────────────────────
-- `docs/OWNER_AUDIT.md` row 37, re-checking the owner's *"1000 trade goods, by regions"* against the
-- code: **PARTLY TRUE — "by regions does not exist"**. That half is what this file closes. The other
-- half — 243 goods rather than 1,000 — is deliberately NOT closed here: the count is a decision about
-- the world (docs/WORLD_DATA.md carries the arithmetic), not a gap in this pass, and padding the
-- catalogue to a thousand would give every port four goods no history could tell apart. Row 38's
-- concrete miss (Korean gochujang is not in the catalogue) is answered in docs/REGIONAL_GOODS.md §H
-- as a PROPOSAL with the displacement it would cost, not silently added: a new good moves
-- public.rarity_scale()'s whole histogram (0051) and adds a port_goods row at all 224 harbours, so it
-- is its own migration with its own measurement.
--
-- ── WHAT SAYS THE OPPOSITE, NAMED ───────────────────────────────────────────────────────────────
-- 0058 (`a_city_offers_what_its_size_earns`) installed the owner's COUNT law — capital 10, mid 4-8,
-- small 4 — and that law is correct and is KEPT here, composed, not re-derived: this file calls
-- `public.roster_target_count` (0058:246) rather than writing the three numbers again. What 0058
-- also did, and what this file supersedes, is choose WHICH goods by
-- `public.roster_rng(port_code || '|' || good_code)` (0058:212, 0058:296-317) — a seeded md5 rank,
-- deterministic but historically arbitrary. Its own receipt records the damage:
--
--     "0058: 78 offer(s) dropped, 56 offer(s) filled; total port_specialties 1310 -> 1288"
--
-- MEASURED on this machine, 2026-08-26, by diffing data/ports.json at 6991814 against its parent:
--
--   * all 78 drops fell on small harbours, and the hash rank, not history, picked the casualty.
--     Konigsberg lost AMBER — the port whose own note reads "ducal Prussian capital holding the
--     Baltic amber monopoly", and amber's own note reads "worked at Konigsberg and Gdansk".
--     Saint-Louis lost GUM-ARABIC, from the port whose note reads "controlling the gum-arabic
--     trade". Trondheim lost COPPER ("outlet for Roros copper from 1644"). Willemstad lost SALT
--     ("took Curacao in 1634 for its salt pans"). Machilipatnam lost DIAMONDS ("the outlet for
--     Deccan diamonds"). Jaffna lost PEARLS ("commanded the Palk Strait pearl and elephant
--     trades"). Accra, on the Gold Coast, lost GOLD. Fuzhou, on the Min, lost TEA.
--   * all 56 fills landed on capitals, drawn from the whole 243-good catalogue with no regard for
--     region, culture or history: Tokyo gained caviar, gold thread, lychees, molasses and sealskins
--     (five of its ten); Jakarta gained herring; Copenhagen gained camwood; Gdansk gained celadon;
--     Genoa gained mangrove poles; Barcelona gained cassava; Callao gained Tuscan majolica and
--     Chian mastic; Bordeaux gained Deccan crucible steel.
--   * and three goods fell out of the world entirely. ALLSPICE, PISTACHIOS and LAC were each
--     carried by exactly one small harbour (Port Royal, Tripoli of Syria, Syriam); each lost it to
--     the hash. Before 0058 all 243 goods had at least one producer. After 0058, 240 did — while
--     all three stayed in the catalogue, stayed priced, and stayed in the compendium, buyable
--     nowhere on earth. Allspice's own note says why that is impossible: "the island was its only
--     source."
--
-- ── THE MECHANISM, AND WHY IT IS ONE RULE AND NOT A SECOND LIST ────────────────────────────────
-- `public.goods` gains TWO columns, both authored in data/goods.json, both carried here:
--
--     origin_regions  text[]   the region CODES that produced the good        (>= 1, always)
--     entrepot_ports  text[]   the port CODES outside those regions that
--                              historically re-exported it                    (usually empty)
--
-- and the roster law is one sentence with no third case:
--
--     EVERY (port, good) offer is either NATIVE — the port's region is in the good's
--     origin_regions — or a NAMED ENTREPOT — the port's code is in the good's entrepot_ports.
--
-- Measured on the world this file writes: 1,288 offers, 1,241 native, 47 entrepot, 0 neither.
-- The 47 are not a loophole, they are the age of sail: black pepper at Lisbon, Amsterdam, Antwerp,
-- Alexandria, Istanbul, Aden, Hormuz and Jeddah; American silver at Seville, Cadiz, Manila and
-- Macau; Chinese porcelain and silk at Acapulco; Ceylon cinnamon at Cochin, Goa and Lisbon; English
-- wool at the Calais Staple; Canada furs at Saint-Malo and La Rochelle; Baltic hemp and mast pine
-- in Portsmouth's King's Yard; Korean ginseng and ramie at Tsushima, whose So clan held the only
-- licence for it. Every one of the 47 is defended by name in docs/REGIONAL_GOODS.md.
--
-- This is deliberately NOT a per-pair exception table. A hash CANNOT write an entrepot row: to
-- re-introduce "Tokyo sells caviar" somebody would have to type Tokyo's code into caviar's
-- entrepot list and then defend it in the doc. That is the whole guard.
--
-- ── WHAT THIS FILE KEEPS FROM 0058, ON PURPOSE ──────────────────────────────────────────────────
-- The COUNT law and its two functions (`roster_target_count`, `roster_rng`) are NOT dropped.
-- `roster_target_count` is still THE authority on how many goods a port offers and is CALLED by
-- assert (e) below. `roster_rng` survives because dropping a function 0058's applied history
-- created would break the chain's own record; what it loses is its JOB — after this file nothing
-- chooses a good with it, and assert (j) proves the hash's own 56 picks are gone from the world.
--
-- ── WHAT THIS FILE DOES TO A LIVE GAME, REASONED BEFORE IT WAS WRITTEN ─────────────────────────
-- Production carries real players; PGlite and CI's disposable Supabase both boot EMPTY, so neither
-- can see the following and it is reasoned here instead of assumed away (the lesson 0057 cost):
--
--   * CARGO IS NOT TOUCHED. A hold is `public.fleet_cargo`, keyed on (fleet, good). This file
--     writes `public.port_specialties` and UPDATEs `public.port_goods`; it never reads or writes a
--     fleet. A captain carrying camwood when Copenhagen stops producing it still owns every tun.
--   * NOTHING CASCADES. `public.port_specialties` is a leaf: it holds FKs OUT to ports and goods
--     and NOTHING in the schema references it. Assert (k) reads `pg_constraint` and re-proves that
--     rather than trusting this paragraph, so a future inbound FK turns this file's descendants red
--     instead of silently deleting rows.
--   * SELLING STILL WORKS EVERYWHERE. `public.port_goods` holds one row per (harbour, good) — all
--     54,432 of them — and this file only UPDATEs those rows' affinity and stock figures. It
--     deletes none. A good a port no longer PRODUCES is still a good that port will BUY, at the
--     price its (worse) affinity now implies. That is the intended consequence: rarity is what
--     makes a distant port worth the voyage, and it is the owner's own stated reason for the count
--     rule ("there should be a purpose to go to a city that is far away to get rare trade goods").
--   * PRICES MOVE, IN BOTH DIRECTIONS, AND ARE NEVER MINTED. `world.affinity_for` (0005/0048) is
--     re-run over the whole market because a producer added at one port can become the nearest
--     source for a good at OTHER ports; `stock` is CLAMPED DOWN to the restated target and never
--     raised, so no cargo is created out of a schema change (assert (i)).
--   * IT IS IDEMPOTENT ON REPLAY. The roster is written as an explicit target SET, not as a
--     delta, so applying this file twice writes the same rows. Assert (l) proves it by recomputing
--     the whole target against the world this file just produced and demanding a zero diff.
--   * NO NEW SURFACE. Two columns on a table `anon`/`authenticated` may only SELECT; no new
--     function, no new grant. Assert (m) re-reads `public.client_write_grants()` and demands zero
--     rather than assuming the default.
--
-- ── CULTURE MASKS: A BUILT MECHANISM THAT WAS NEARLY DEAD ──────────────────────────────────────
-- `public.goods.culture_mask` (0002:131) is read in eleven places — `cmd.do_buy` (0007:438),
-- `cmd.do_sell` (0007:515), arrival (0007:1130), `world.goods` (0009:96), the `available` flag
-- (0009:135), 0014:264, 0017:522/600/874, 0019:744, 0022:488 — and carried SIX goods, all alcohol.
-- It gains one, and only one, because only one more is defensible as a REFUSAL rather than a
-- preference: `salted-beef` is masked to `indic` and `japanese`. No Hindu or Jain port bought
-- barrelled beef, and Tokugawa Japan's prohibition on four-legged meat is a matter of edict, not
-- taste. Alcohol is NOT extended to `malay` even though the archipelago sultanates were Muslim,
-- because arrack's own note names Batavia as its distillery and the Dutch, Chinese and Portuguese
-- communities there traded it openly; a mask that contradicted the catalogue would be worse than
-- none. Assert (h) proves the masks BITE: no port of a masked culture may produce the good.
--
-- The mask's own authority moves in this file too. It was a hand-typed table inside
-- `scripts/lib/world-derive.mjs` (`ALCOHOL_MASK`, six entries) — a second author for a fact about a
-- good, sitting in a build script rather than beside the good. It is deleted there and read from
-- data/goods.json's `cultureMask`, so ONE file now answers every geographic question about a good:
-- where it comes from, who re-exports it, and who will not touch it.
--
-- ── WHAT THIS FILE DELIBERATELY DOES NOT TOUCH ─────────────────────────────────────────────────
-- `public.port_goods`' SHAPE or row set (one row per harbour x good since 0005; another slice is
-- making a city sell only its roster and this file must not open a second door to that).
-- `cmd.do_buy` / `cmd.do_sell` / `cmd.preview` — no verb changes. `scripts/sea-grid.mjs`,
-- `public.sea_raster`, `public.sea_reaches` — the water is not this file's business. `base_value`,
-- `bulk`, `perishable_pct_day`, `category` — a good's price and physics are unchanged; only its
-- geography is authored. `size_tier`, `crew_pool`, `yard_tier`, `culture`, `nation_id`. SEA_PLACE
-- ports, which carry no roster and gain none (assert (d)). `public.roster_rng` and
-- `public.roster_target_count` stay, for the reasons above.
--
-- ── SUPERSEDES ─────────────────────────────────────────────────────────────────────────────────
-- The seeded-hash ASSIGNMENT of 0058 (`20260818000058_a_city_offers_what_its_size_earns.sql`
-- :296-334, the `roster_drop_0058` / `roster_fill_0058` ranking and the delete/insert it drove).
-- No SQL object is dropped: like 0058 itself, what is superseded is DATA — the offer set — so the
-- supersession is proven by assert (j), which requires all 56 of the hash's own picks to be absent
-- from the world, and by assert (c), which requires every remaining offer to satisfy a law the hash
-- knows nothing about.
--
-- Depends on: 0002 (goods, port_specialties, culture_mask), 0003 (the seeded world), 0005/0048
-- (port_goods, world.affinity_for), 0032/0051 (good_rarity, rarity_scale — re-read, not moved),
-- 0036 (SEA_PLACE), 0058 (roster_target_count, composed; roster_rng, retired as an author).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. BEFORE, captured for the receipt and for the asserts ────────────────────────────────────
create temporary table geo_before_0062 as
select
  (select count(*) from public.port_specialties)                                as offers,
  (select count(*) from public.ports where kind = 'HARBOUR')                    as harbours,
  (select count(*) from public.goods)                                           as goods,
  (select count(*) from public.goods where culture_mask <> '{}')                as masked,
  (select count(*) from public.goods g
     where not exists (select 1 from public.port_specialties s where s.good_id = g.id)) as orphans;

-- ── 1. A GOOD GAINS ITS GEOGRAPHY ──────────────────────────────────────────────────────────────
alter table public.goods add column origin_regions text[] not null default '{}';
alter table public.goods add column entrepot_ports text[] not null default '{}';

comment on column public.goods.origin_regions is
  'THE regions (public.regions.code) that PRODUCE this good, authored in data/goods.json from the '
  'good''s own historical note. Never empty. Its LENGTH is what tells a broad good from a singular '
  'one: rice names eight regions, a Banda nutmeg names one. Half of the roster law of 0062: an offer '
  'is legal at a port whose region is listed here.';
comment on column public.goods.entrepot_ports is
  'THE ports (public.ports.code) OUTSIDE origin_regions that historically re-exported this good — '
  'Lisbon''s pepper, Seville''s silver, the Calais wool staple, Tsushima''s Korean ginseng. The '
  'other half of the roster law of 0062, and deliberately hand-authored: a seeded hash can invent '
  'an offer but it cannot write an entrepot row, so this column is what stops 0058''s draw from '
  'ever coming back. Usually empty; 47 rows across 25 goods on the world 0062 writes.';

update public.goods g
   set origin_regions = v.origin::text[],
       entrepot_ports = v.entrepot::text[],
       culture_mask   = v.mask::text[]
  from (values
  ('black-pepper', '{SOU,WIA,WST}', '{ADE,ALE,AMS,ARP,HOR,IST,JED,LIS}', '{}'),
  ('cloves', '{SOU}', '{}', '{}'),
  ('nutmeg', '{SOU}', '{}', '{}'),
  ('mace', '{SOU}', '{}', '{}'),
  ('cinnamon', '{EST}', '{KOC,LIS,OLD}', '{}'),
  ('ginger', '{CAR,EST,STH,WIA}', '{}', '{}'),
  ('cardamom', '{WIA}', '{}', '{}'),
  ('long-pepper', '{EST}', '{}', '{}'),
  ('cubeb', '{SOU}', '{}', '{}'),
  ('grains-of-paradise', '{WST}', '{}', '{}'),
  ('cassia', '{CHI,SOU}', '{}', '{}'),
  ('turmeric', '{EST,WIA}', '{}', '{}'),
  ('saffron', '{ARA,IBE}', '{}', '{}'),
  ('chillies', '{CAR,PAC,SOU,STH,WIA}', '{}', '{}'),
  ('vanilla', '{CAR}', '{}', '{}'),
  ('anise', '{ADR,IBE,WES}', '{}', '{}'),
  ('cumin', '{LEV,WIA}', '{}', '{}'),
  ('coriander', '{IBE,LEV}', '{}', '{}'),
  ('galangal', '{SOU}', '{}', '{}'),
  ('star-anise', '{CHI,SOU}', '{}', '{}'),
  ('allspice', '{CAR}', '{}', '{}'),
  ('zedoary', '{EST,SOU}', '{}', '{}'),
  ('wool-cloth', '{ADR,AEG,BRI,FRA,IBE,MAG,SCA,WES}', '{HAM}', '{}'),
  ('linen', '{BAL,BRI,FRA,LEV}', '{}', '{}'),
  ('cotton-cloth', '{ATL,EAS,EST,JAP,KOR,WES,WIA,WST}', '{JED}', '{}'),
  ('muslin', '{EST}', '{}', '{}'),
  ('chintz', '{EST}', '{}', '{}'),
  ('silk-cloth', '{ADR,AEG,ARA,CHI,IBE,JAP,WES,WIA}', '{ACA,MNL}', '{}'),
  ('silk-raw', '{ADR,AEG,ARA,CHI,EST,IBE,LEV,SOU,WES}', '{FUK,HIR}', '{}'),
  ('carpets', '{AEG,ARA}', '{}', '{}'),
  ('ramie-cloth', '{CHI,KOR}', '{TSU}', '{}'),
  ('says-serges', '{FRA}', '{}', '{}'),
  ('velvet', '{ADR,WES}', '{}', '{}'),
  ('lace', '{ADR,FRA}', '{}', '{}'),
  ('tapestries', '{FRA}', '{}', '{}'),
  ('batik', '{SOU}', '{}', '{}'),
  ('raffia-cloth', '{WST}', '{}', '{}'),
  ('barkcloth', '{OCE}', '{}', '{}'),
  ('camlets', '{AEG}', '{}', '{}'),
  ('quilts', '{EST}', '{}', '{}'),
  ('shawls', '{WIA}', '{}', '{}'),
  ('fustian', '{BAL,WES}', '{}', '{}'),
  ('gold-thread', '{LEV,WES}', '{}', '{}'),
  ('stockings', '{BRI,FRA}', '{}', '{}'),
  ('felt-hats', '{BRI,FRA}', '{}', '{}'),
  ('gold', '{CAR,CHI,EAS,MAG,PAC,SOU,WST}', '{}', '{}'),
  ('silver', '{ADR,CAR,JAP,KOR,PAC,STH}', '{CAD,MAC,MNL,SVQ}', '{}'),
  ('copper', '{AEG,ARA,BAL,JAP,MAG,PAC,SCA,WST}', '{}', '{}'),
  ('tin', '{BRI,EST,SOU}', '{}', '{}'),
  ('iron', '{BAL,BRI,CHI,IBE,JAP,KOR,SCA,WST}', '{}', '{}'),
  ('lead', '{BAL,BRI}', '{}', '{}'),
  ('quicksilver', '{ADR,IBE,PAC}', '{}', '{}'),
  ('wootz-steel', '{EST,WIA}', '{}', '{}'),
  ('firearms', '{FRA,JAP}', '{}', '{}'),
  ('cannon', '{BAL,BRI,SCA}', '{}', '{}'),
  ('brassware', '{BAL,FRA}', '{}', '{}'),
  ('pewter', '{BRI}', '{}', '{}'),
  ('copper-cash', '{CHI}', '{}', '{}'),
  ('smallwares', '{BAL,BRI,FRA}', '{}', '{}'),
  ('armour', '{WES}', '{}', '{}'),
  ('gunpowder', '{ADR,BRI,FRA}', '{}', '{}'),
  ('porcelain', '{CHI,JAP,SOU}', '{ACA,LIS,OLD}', '{}'),
  ('lacquerware', '{CHI,JAP,KOR,SOU}', '{}', '{}'),
  ('glassware', '{ADR,IBE}', '{}', '{}'),
  ('pearls', '{ARA,CAR,CHI,EST,PAC,WIA}', '{}', '{}'),
  ('diamonds', '{EST,SOU}', '{ARP}', '{}'),
  ('ivory', '{EAS,EST,SOU,WST}', '{LIS}', '{}'),
  ('ambergris', '{ARA,ATL,EAS,NOR,SOU,WIA}', '{}', '{}'),
  ('musk', '{CHI}', '{}', '{}'),
  ('coral', '{IBE,MAG,WES}', '{}', '{}'),
  ('amber', '{BAL}', '{}', '{}'),
  ('frankincense', '{ARA,EAS}', '{}', '{}'),
  ('myrrh', '{ARA,EAS}', '{}', '{}'),
  ('rubies', '{EST}', '{}', '{}'),
  ('emeralds', '{CAR}', '{}', '{}'),
  ('carnelian', '{WIA}', '{}', '{}'),
  ('books', '{ADR,FRA}', '{}', '{}'),
  ('paper', '{CHI,FRA,IBE,JAP,KOR,WES}', '{}', '{}'),
  ('tortoiseshell', '{CAR,JAP,SOU}', '{}', '{}'),
  ('mastic', '{AEG}', '{}', '{}'),
  ('civet', '{EAS}', '{}', '{}'),
  ('rosewater', '{ARA,LEV}', '{}', '{}'),
  ('clocks', '{BAL,FRA}', '{}', '{}'),
  ('paintings', '{FRA}', '{}', '{}'),
  ('bezoar', '{ARA,SOU,WIA}', '{}', '{}'),
  ('rhino-horn', '{EAS,EST,SOU,WST}', '{}', '{}'),
  ('lapis-lazuli', '{ARA}', '{}', '{}'),
  ('turquoise', '{ARA}', '{}', '{}'),
  ('folding-fans', '{JAP}', '{}', '{}'),
  ('silver-plate', '{BAL,IBE}', '{}', '{}'),
  ('majolica', '{IBE,WES}', '{}', '{}'),
  ('celadon', '{KOR,SOU}', '{}', '{}'),
  ('stoneware', '{BAL,FRA}', '{}', '{}'),
  ('martaban-jars', '{EST}', '{}', '{}'),
  ('glass-beads', '{ADR,FRA}', '{}', '{}'),
  ('sea-charts', '{FRA,IBE}', '{}', '{}'),
  ('ink-sticks', '{CHI,KOR}', '{}', '{}'),
  ('sword-blades', '{BAL,IBE,JAP}', '{}', '{}'),
  ('theriac', '{ADR}', '{}', '{}'),
  ('parrots', '{STH,WST}', '{}', '{}'),
  ('gyrfalcons', '{SCA}', '{}', '{}'),
  ('paradise-plumes', '{OCE,SOU}', '{}', '{}'),
  ('wheat', '{ADR,AEG,ARA,ATL,BAL,EAS,FRA,IBE,KOR,LEV,MAG,NOR,PAC,STH,WES}', '{}', '{}'),
  ('rice', '{CHI,EST,IBE,JAP,KOR,OCE,SOU,WIA}', '{}', '{}'),
  ('sugar', '{ATL,CAR,CHI,EAS,EST,JAP,LEV,MAG,SOU,STH,WES,WST}', '{ARP,LIS,NAN}', '{}'),
  ('salt', '{ADR,AEG,ARA,ATL,BAL,BRI,CAR,CHI,EAS,EST,FRA,IBE,JAP,KOR,LEV,MAG,NOR,OCE,WES,WIA,WST}', '{}', '{}'),
  ('olive-oil', '{ADR,AEG,IBE,LEV,MAG,WES}', '{}', '{}'),
  ('wine', '{ADR,AEG,ATL,EAS,FRA,IBE,LEV,PAC,WES}', '{}', '{islamic,swahili}'),
  ('dried-fish', '{ARA,ATL,BAL,BRI,CHI,EAS,FRA,IBE,JAP,KOR,NOR,OCE,SCA,SOU,WES,WIA}', '{}', '{}'),
  ('herring', '{BAL,BRI,FRA,SCA}', '{}', '{}'),
  ('cheese', '{AEG,ATL,BRI,FRA,WES}', '{}', '{}'),
  ('salted-beef', '{ATL,BAL,BRI,CAR,EAS,FRA,NOR,STH}', '{}', '{indic,japanese}'),
  ('coffee', '{ARA}', '{ALE,MRS}', '{}'),
  ('tea', '{CHI,JAP}', '{}', '{}'),
  ('cacao', '{CAR,PAC,STH}', '{}', '{}'),
  ('dried-fruit', '{ADR,AEG,ATL,FRA,IBE,LEV,MAG,WES}', '{}', '{}'),
  ('rye', '{BAL}', '{}', '{}'),
  ('barley', '{BAL,BRI,SCA}', '{}', '{}'),
  ('beer', '{BAL,BRI,FRA}', '{}', '{islamic,swahili}'),
  ('sake', '{JAP}', '{}', '{islamic,swahili}'),
  ('rum', '{CAR}', '{}', '{islamic,swahili}'),
  ('brandy', '{FRA}', '{}', '{islamic,swahili}'),
  ('arrack', '{EST,SOU,WIA}', '{}', '{islamic,swahili}'),
  ('butter', '{BAL,BRI,FRA}', '{}', '{}'),
  ('honey', '{AEG,BAL,MAG,WES}', '{}', '{}'),
  ('dates', '{ARA,LEV,MAG}', '{}', '{}'),
  ('figs', '{AEG,IBE,MAG,WES}', '{}', '{}'),
  ('citrus', '{ADR,IBE,MAG,WES}', '{}', '{}'),
  ('almonds', '{ADR,IBE,MAG,WES}', '{}', '{}'),
  ('coconuts', '{EAS,EST,OCE,SOU,WIA}', '{}', '{}'),
  ('sago', '{OCE,SOU}', '{}', '{}'),
  ('maize', '{CAR,NOR,PAC,STH,WST}', '{}', '{}'),
  ('cassava', '{CAR,STH,WST}', '{}', '{}'),
  ('caviar', '{AEG,SCA}', '{}', '{}'),
  ('salted-tuna', '{IBE,MAG,WES}', '{}', '{}'),
  ('soy-sauce', '{CHI,JAP,KOR}', '{}', '{}'),
  ('ghee', '{WIA}', '{}', '{}'),
  ('sesame-oil', '{ARA,EST,LEV}', '{}', '{}'),
  ('palm-oil', '{WST}', '{}', '{}'),
  ('birds-nests', '{SOU}', '{}', '{}'),
  ('sharks-fin', '{CHI,JAP,OCE,SOU}', '{}', '{}'),
  ('trepang', '{OCE,SOU}', '{}', '{}'),
  ('dried-abalone', '{JAP,KOR}', '{}', '{}'),
  ('seaweed', '{JAP,KOR}', '{}', '{}'),
  ('palm-sugar', '{EST,SOU,WIA}', '{}', '{}'),
  ('molasses', '{ATL,CAR,STH}', '{}', '{}'),
  ('tamarind', '{EST,SOU,WIA}', '{}', '{}'),
  ('hazelnuts', '{AEG}', '{}', '{}'),
  ('pistachios', '{ARA,LEV}', '{}', '{}'),
  ('lychees', '{CHI}', '{}', '{}'),
  ('tobacco', '{AEG,CAR,EST,LEV,NOR,STH}', '{}', '{}'),
  ('indigo', '{ARA,ATL,CAR,EST,SOU,WIA}', '{BOR,SVQ}', '{}'),
  ('cochineal', '{CAR,PAC}', '{SVQ}', '{}'),
  ('brazilwood', '{STH}', '{}', '{}'),
  ('logwood', '{CAR}', '{}', '{}'),
  ('alum', '{ADR,AEG,WES}', '{BRU}', '{}'),
  ('saltpetre', '{EST,WIA}', '{}', '{}'),
  ('sulphur', '{JAP,SCA,WES}', '{}', '{}'),
  ('hides', '{ADR,AEG,ARA,ATL,BAL,BRI,CAR,CHI,EAS,IBE,JAP,KOR,LEV,MAG,NOR,PAC,SOU,STH,WES,WST}', '{}', '{}'),
  ('furs', '{AEG,BAL,JAP,NOR,SCA}', '{LAR,SNT}', '{}'),
  ('wax', '{ADR,BAL,CAR,EAS,MAG,OCE,PAC,SCA,SOU,STH,WST}', '{}', '{}'),
  ('cotton-raw', '{AEG,CAR,EST,LEV,MAG,STH,WIA}', '{MRS}', '{}'),
  ('wool-raw', '{ADR,AEG,BRI,IBE,MAG,OCE,SCA,WES}', '{CLS}', '{}'),
  ('gum-arabic', '{ARA,EAS,WST}', '{}', '{}'),
  ('sandalwood', '{OCE,SOU,WIA}', '{NAG}', '{}'),
  ('ginseng', '{CHI,KOR}', '{TSU}', '{}'),
  ('horses', '{ARA,ATL,JAP,KOR,LEV,MAG}', '{DIU,OLD}', '{}'),
  ('potash', '{BAL,SCA}', '{}', '{}'),
  ('tallow', '{BAL,CAR,PAC,SCA,STH}', '{}', '{}'),
  ('woad', '{ATL,FRA,WES}', '{}', '{}'),
  ('madder', '{AEG,FRA}', '{}', '{}'),
  ('lac', '{EST}', '{}', '{}'),
  ('annatto', '{CAR,STH}', '{}', '{}'),
  ('orchil', '{ATL,MAG}', '{}', '{}'),
  ('henna', '{ARA,EAS,LEV,MAG}', '{}', '{}'),
  ('camphor', '{JAP,SOU}', '{}', '{}'),
  ('benzoin', '{SOU}', '{}', '{}'),
  ('aloeswood', '{CHI,SOU}', '{}', '{}'),
  ('dragons-blood', '{ARA}', '{}', '{}'),
  ('socotra-aloes', '{ARA}', '{}', '{}'),
  ('myrobalans', '{EST,WIA}', '{}', '{}'),
  ('sappanwood', '{EST,SOU}', '{NAH}', '{}'),
  ('red-sanders', '{EST}', '{}', '{}'),
  ('camwood', '{WST}', '{}', '{}'),
  ('ebony', '{EAS,EST}', '{}', '{}'),
  ('rattan', '{SOU}', '{}', '{}'),
  ('opium', '{EST,WIA}', '{}', '{}'),
  ('areca-nuts', '{EST,SOU,WIA}', '{}', '{}'),
  ('kola-nuts', '{WST}', '{}', '{}'),
  ('sarsaparilla', '{CAR}', '{}', '{}'),
  ('sassafras', '{NOR}', '{}', '{}'),
  ('senna', '{ARA,EAS,LEV}', '{}', '{}'),
  ('rhubarb', '{CHI}', '{}', '{}'),
  ('china-root', '{CHI}', '{}', '{}'),
  ('mother-of-pearl', '{ARA,JAP,SOU}', '{}', '{}'),
  ('cowries', '{EST,WIA}', '{}', '{}'),
  ('chank-shells', '{EST}', '{}', '{}'),
  ('coir', '{EST,SOU,WIA}', '{}', '{}'),
  ('gallnuts', '{AEG,ARA,LEV}', '{}', '{}'),
  ('cinchona-bark', '{PAC}', '{}', '{}'),
  ('ostrich-feathers', '{MAG,WST}', '{}', '{}'),
  ('sponges', '{ADR,AEG}', '{}', '{}'),
  ('baleen', '{BRI,FRA,IBE,NOR,SCA}', '{}', '{}'),
  ('sealskins', '{NOR,OCE,SCA}', '{}', '{}'),
  ('walrus-ivory', '{SCA}', '{}', '{}'),
  ('narwhal-horn', '{SCA}', '{}', '{}'),
  ('eiderdown', '{SCA}', '{}', '{}'),
  ('coal', '{BRI}', '{}', '{}'),
  ('marble', '{ADR,AEG,WES}', '{}', '{}'),
  ('cork', '{IBE}', '{}', '{}'),
  ('copal', '{CAR,EAS}', '{}', '{}'),
  ('tiger-skins', '{KOR}', '{}', '{}'),
  ('isinglass', '{AEG,BAL,SCA}', '{}', '{}'),
  ('russia-leather', '{AEG,BAL,SCA}', '{}', '{}'),
  ('morocco-leather', '{MAG}', '{}', '{}'),
  ('peru-balsam', '{CAR,PAC}', '{}', '{}'),
  ('jalap', '{CAR}', '{}', '{}'),
  ('vicuna-wool', '{PAC}', '{}', '{}'),
  ('guaiacum', '{CAR}', '{}', '{}'),
  ('verdigris', '{WES}', '{}', '{}'),
  ('cobalt', '{ARA}', '{}', '{}'),
  ('gamboge', '{SOU}', '{}', '{}'),
  ('safflower', '{EST,LEV,WIA}', '{}', '{}'),
  ('catechu', '{EST,WIA}', '{}', '{}'),
  ('elephants', '{EST}', '{}', '{}'),
  ('spikenard', '{EST}', '{}', '{}'),
  ('asafoetida', '{ARA,WIA}', '{}', '{}'),
  ('mecca-balsam', '{ARA}', '{}', '{}'),
  ('linseed', '{BAL}', '{}', '{}'),
  ('hops', '{BAL,FRA}', '{}', '{}'),
  ('soap', '{ADR,IBE,LEV,WES}', '{}', '{}'),
  ('vermilion', '{CHI,FRA}', '{}', '{}'),
  ('timber', '{AEG,ATL,BAL,BRI,CAR,CHI,EAS,EST,FRA,IBE,JAP,KOR,NOR,OCE,SCA,STH,WIA}', '{}', '{}'),
  ('naval-timber', '{BAL,NOR,SCA,WES}', '{PTH}', '{}'),
  ('tar', '{BAL,SCA}', '{}', '{}'),
  ('hemp', '{BAL,EAS,FRA,SCA,WES,WIA}', '{PTH}', '{}'),
  ('flax', '{ARA,BAL,FRA,LEV,SCA}', '{}', '{}'),
  ('whale-oil', '{BRI,FRA,IBE,KOR,NOR,SCA,STH}', '{}', '{}'),
  ('teak', '{EST,WIA}', '{}', '{}'),
  ('rosin', '{BAL,FRA,SCA}', '{}', '{}'),
  ('cedar', '{CAR,LEV,NOR}', '{}', '{}'),
  ('mangrove-poles', '{EAS}', '{}', '{}'),
  ('abaca', '{SOU}', '{}', '{}')
  ) as v(code, origin, entrepot, mask)
 where g.code = v.code;

-- ── 1b. TWO CULTURES CORRECTED, BECAUSE THE MASK ASSERT FOUND THEM ─────────────────────────────
-- Assert (h) below refuses to let a harbour PRODUCE a good its own culture will not trade. Run for
-- the first time against the real world it went red on exactly two rows — FAM/wine and RHO/wine —
-- and they are not a data error, they are a gap in the culture table. `scripts/lib/world-derive.mjs`
-- already overrides two Latin-ruled Greek islands whose vineyards outlived the Ottoman conquest
-- (`heraklion: 'latin'`, "Venetian Crete until 1669"; `chios: 'latin'`, "the Genoese Maona held the
-- island until 1566"). Rhodes — Hospitaller until Suleiman took the fortress in 1522 — and
-- Famagusta — Venetian Cyprus until the siege of 1571 — are the same case and were simply missed.
-- Completing that override is the fix; deleting Commandaria from Cyprus to satisfy a coarse culture
-- token would have been weakening a true fact to green. This is the ONLY thing in this file that
-- touches `ports.culture`, and it moves two rows.
update public.ports set culture = 'latin' where code in ('RHO', 'FAM');

do $$
declare v_n int;
begin
  select count(*) into v_n from public.ports where code in ('RHO', 'FAM') and culture = 'latin';
  if v_n <> 2 then
    raise exception '0062 self-assert FAIL: % of the 2 named culture corrections landed (Rhodes, Famagusta)', v_n;
  end if;
end $$;

-- ── 2. THE ROSTER, REWRITTEN BY HISTORY ────────────────────────────────────────────────────────
-- The target set for the 75 harbours whose roster this file changes, written out in full rather
-- than as a delta, so replaying the file writes the same rows (assert (l)).
create temporary table geo_target_0062 (port_code text not null, good_code text not null);
insert into geo_target_0062 (port_code, good_code) values
  ('ACC', 'gold'),
  ('ACC', 'ivory'),
  ('ACC', 'grains-of-paradise'),
  ('ACC', 'kola-nuts'),
  ('AGA', 'sugar'),
  ('AGA', 'gold'),
  ('AGA', 'wax'),
  ('AGA', 'almonds'),
  ('ALE', 'black-pepper'),
  ('ALE', 'flax'),
  ('ALE', 'wheat'),
  ('ALE', 'sugar'),
  ('ALE', 'cumin'),
  ('ALE', 'sesame-oil'),
  ('ALE', 'senna'),
  ('ALE', 'safflower'),
  ('ALE', 'linen'),
  ('ALE', 'coffee'),
  ('AMS', 'black-pepper'),
  ('AMS', 'herring'),
  ('AMS', 'wheat'),
  ('AMS', 'timber'),
  ('AMS', 'gunpowder'),
  ('AMS', 'glass-beads'),
  ('AMS', 'sea-charts'),
  ('AMS', 'vermilion'),
  ('AMS', 'cheese'),
  ('AMS', 'whale-oil'),
  ('ANT', 'timber'),
  ('ANT', 'wheat'),
  ('ANT', 'carpets'),
  ('ANT', 'sponges'),
  ('ARP', 'wool-cloth'),
  ('ARP', 'black-pepper'),
  ('ARP', 'diamonds'),
  ('ARP', 'sugar'),
  ('ARP', 'says-serges'),
  ('ARP', 'tapestries'),
  ('ARP', 'firearms'),
  ('ARP', 'books'),
  ('ARP', 'paintings'),
  ('ARP', 'linen'),
  ('BAR', 'wool-cloth'),
  ('BAR', 'coral'),
  ('BAR', 'wine'),
  ('BAR', 'iron'),
  ('BAR', 'saffron'),
  ('BAR', 'olive-oil'),
  ('BAR', 'glassware'),
  ('BAR', 'hides'),
  ('BAR', 'almonds'),
  ('BAR', 'salt'),
  ('BEL', 'cacao'),
  ('BEL', 'annatto'),
  ('BEL', 'parrots'),
  ('BEL', 'timber'),
  ('BOR', 'wine'),
  ('BOR', 'indigo'),
  ('BOR', 'salt'),
  ('BOR', 'brandy'),
  ('BOR', 'woad'),
  ('BOR', 'rosin'),
  ('BOR', 'linen'),
  ('BOR', 'dried-fruit'),
  ('BOR', 'timber'),
  ('BOR', 'paper'),
  ('BRU', 'wool-cloth'),
  ('BRU', 'linen'),
  ('BRU', 'alum'),
  ('BRU', 'lace'),
  ('BUS', 'ginseng'),
  ('BUS', 'ramie-cloth'),
  ('BUS', 'rice'),
  ('BUS', 'dried-fish'),
  ('BUS', 'silver'),
  ('BUS', 'celadon'),
  ('BUS', 'tiger-skins'),
  ('BUS', 'cotton-cloth'),
  ('BUS', 'paper'),
  ('BUS', 'ink-sticks'),
  ('CAD', 'silver'),
  ('CAD', 'wine'),
  ('CAD', 'salt'),
  ('CAD', 'olive-oil'),
  ('CAD', 'sword-blades'),
  ('CAD', 'salted-tuna'),
  ('CAD', 'wool-raw'),
  ('CAD', 'hides'),
  ('CAD', 'citrus'),
  ('CAD', 'silver-plate'),
  ('CAL', 'palm-oil'),
  ('CAL', 'ivory'),
  ('CAL', 'black-pepper'),
  ('CAL', 'camwood'),
  ('CLL', 'silver'),
  ('CLL', 'wine'),
  ('CLL', 'cacao'),
  ('CLL', 'quicksilver'),
  ('CLL', 'cinchona-bark'),
  ('CLL', 'vicuna-wool'),
  ('CLL', 'wheat'),
  ('CLL', 'hides'),
  ('CLL', 'copper'),
  ('CLL', 'tallow'),
  ('CAP', 'gold'),
  ('CAP', 'ivory'),
  ('CAP', 'maize'),
  ('CAP', 'salt'),
  ('CAR', 'gold'),
  ('CAR', 'sarsaparilla'),
  ('CAR', 'hides'),
  ('CAR', 'sugar'),
  ('CAR', 'chillies'),
  ('CAR', 'emeralds'),
  ('CAR', 'tobacco'),
  ('CAR', 'pearls'),
  ('CAR', 'cacao'),
  ('CAR', 'salt'),
  ('CEB', 'gold'),
  ('CEB', 'abaca'),
  ('CEB', 'tortoiseshell'),
  ('CEB', 'mother-of-pearl'),
  ('COP', 'herring'),
  ('COP', 'wheat'),
  ('COP', 'salted-beef'),
  ('COP', 'amber'),
  ('COP', 'rye'),
  ('COP', 'barley'),
  ('COP', 'beer'),
  ('COP', 'butter'),
  ('COP', 'dried-fish'),
  ('COP', 'hides'),
  ('CRK', 'salted-beef'),
  ('CRK', 'butter'),
  ('CRK', 'hides'),
  ('CRK', 'wool-raw'),
  ('DIU', 'cotton-cloth'),
  ('DIU', 'indigo'),
  ('DIU', 'silk-cloth'),
  ('DIU', 'horses'),
  ('FAM', 'salt'),
  ('FAM', 'cotton-raw'),
  ('FAM', 'wine'),
  ('FAM', 'gold-thread'),
  ('FEO', 'wheat'),
  ('FEO', 'salt'),
  ('FEO', 'furs'),
  ('FEO', 'caviar'),
  ('FUZ', 'tea'),
  ('FUZ', 'lacquerware'),
  ('FUZ', 'lychees'),
  ('FUZ', 'sugar'),
  ('GDA', 'wheat'),
  ('GDA', 'rye'),
  ('GDA', 'timber'),
  ('GDA', 'tar'),
  ('GDA', 'amber'),
  ('GDA', 'beer'),
  ('GDA', 'potash'),
  ('GDA', 'rosin'),
  ('GDA', 'hemp'),
  ('GDA', 'naval-timber'),
  ('GOA', 'silk-cloth'),
  ('GOA', 'alum'),
  ('GOA', 'coral'),
  ('GOA', 'velvet'),
  ('GOA', 'fustian'),
  ('GOA', 'gold-thread'),
  ('GOA', 'armour'),
  ('GOA', 'paper'),
  ('GOA', 'marble'),
  ('GOA', 'olive-oil'),
  ('HAG', 'coconuts'),
  ('HAG', 'salt'),
  ('HAG', 'rice'),
  ('HAG', 'dried-fish'),
  ('HAM', 'beer'),
  ('HAM', 'linen'),
  ('HAM', 'wool-cloth'),
  ('HAM', 'brassware'),
  ('HAM', 'smallwares'),
  ('HAM', 'clocks'),
  ('HAM', 'silver-plate'),
  ('HAM', 'stoneware'),
  ('HAM', 'sword-blades'),
  ('HAM', 'copper'),
  ('HAV', 'sugar'),
  ('HAV', 'tobacco'),
  ('HAV', 'hides'),
  ('HAV', 'silver'),
  ('HAV', 'timber'),
  ('HAV', 'salted-beef'),
  ('HAV', 'salt'),
  ('HAV', 'cedar'),
  ('HAV', 'wax'),
  ('HAV', 'guaiacum'),
  ('HON', 'salt'),
  ('HON', 'dried-fish'),
  ('HON', 'pearls'),
  ('HON', 'aloeswood'),
  ('HNL', 'sandalwood'),
  ('HNL', 'salt'),
  ('HNL', 'barkcloth'),
  ('HNL', 'dried-fish'),
  ('IST', 'silk-cloth'),
  ('IST', 'carpets'),
  ('IST', 'wheat'),
  ('IST', 'furs'),
  ('IST', 'black-pepper'),
  ('IST', 'alum'),
  ('IST', 'wool-raw'),
  ('IST', 'hides'),
  ('IST', 'camlets'),
  ('IST', 'timber'),
  ('JAF', 'pearls'),
  ('JAF', 'chank-shells'),
  ('JAF', 'coconuts'),
  ('JAF', 'tobacco'),
  ('JAK', 'cloves'),
  ('JAK', 'nutmeg'),
  ('JAK', 'black-pepper'),
  ('JAK', 'porcelain'),
  ('JAK', 'sugar'),
  ('JAK', 'batik'),
  ('JAK', 'arrack'),
  ('JAK', 'rice'),
  ('JAK', 'chillies'),
  ('JAK', 'indigo'),
  ('KAG', 'sulphur'),
  ('KAG', 'sugar'),
  ('KAG', 'rice'),
  ('KAG', 'timber'),
  ('KAL', 'amber'),
  ('KAL', 'rye'),
  ('KAL', 'honey'),
  ('KAL', 'linseed'),
  ('KOC', 'black-pepper'),
  ('KOC', 'cinnamon'),
  ('KOC', 'ginger'),
  ('KOC', 'hemp'),
  ('KOC', 'timber'),
  ('KOC', 'teak'),
  ('KOC', 'coir'),
  ('KOC', 'cardamom'),
  ('KOC', 'areca-nuts'),
  ('KOC', 'coconuts'),
  ('KOZ', 'black-pepper'),
  ('KOZ', 'ginger'),
  ('KOZ', 'cotton-cloth'),
  ('KOZ', 'cardamom'),
  ('KOZ', 'turmeric'),
  ('KOZ', 'timber'),
  ('KOZ', 'coir'),
  ('KOZ', 'teak'),
  ('KOZ', 'areca-nuts'),
  ('KOZ', 'sandalwood'),
  ('KUP', 'sandalwood'),
  ('KUP', 'wax'),
  ('KUP', 'sharks-fin'),
  ('KUP', 'trepang'),
  ('LEH', 'linen'),
  ('LEH', 'wine'),
  ('LEH', 'salt'),
  ('LEH', 'felt-hats'),
  ('LEI', 'salt'),
  ('LEI', 'coal'),
  ('LEI', 'herring'),
  ('LEI', 'barley'),
  ('LIS', 'wine'),
  ('LIS', 'salt'),
  ('LIS', 'olive-oil'),
  ('LIS', 'black-pepper'),
  ('LIS', 'porcelain'),
  ('LIS', 'cork'),
  ('LIS', 'dried-fish'),
  ('LIS', 'sugar'),
  ('LIS', 'cinnamon'),
  ('LIS', 'ivory'),
  ('LON', 'wool-cloth'),
  ('LON', 'tin'),
  ('LON', 'iron'),
  ('LON', 'stockings'),
  ('LON', 'felt-hats'),
  ('LON', 'cannon'),
  ('LON', 'pewter'),
  ('LON', 'gunpowder'),
  ('LON', 'beer'),
  ('LON', 'coal'),
  ('LUB', 'salt'),
  ('LUB', 'herring'),
  ('LUB', 'wax'),
  ('LUB', 'furs'),
  ('LUB', 'wheat'),
  ('LUB', 'rye'),
  ('LUB', 'beer'),
  ('LUB', 'smallwares'),
  ('LUB', 'hops'),
  ('LUB', 'linen'),
  ('MAC', 'silk-raw'),
  ('MAC', 'porcelain'),
  ('MAC', 'gold'),
  ('MAC', 'silver'),
  ('MAC', 'musk'),
  ('MAC', 'china-root'),
  ('MAC', 'tea'),
  ('MAC', 'rhubarb'),
  ('MAC', 'sugar'),
  ('MAC', 'paper'),
  ('MCH', 'chintz'),
  ('MCH', 'diamonds'),
  ('MCH', 'wootz-steel'),
  ('MCH', 'turmeric'),
  ('MAK', 'cloves'),
  ('MAK', 'sandalwood'),
  ('MAK', 'gold'),
  ('MAK', 'rice'),
  ('MAK', 'sago'),
  ('MAK', 'birds-nests'),
  ('MAK', 'trepang'),
  ('MAL', 'cloves'),
  ('MAL', 'nutmeg'),
  ('MAL', 'black-pepper'),
  ('MAL', 'tin'),
  ('MAL', 'porcelain'),
  ('MAL', 'bezoar'),
  ('MAL', 'rice'),
  ('MAL', 'camphor'),
  ('MAL', 'benzoin'),
  ('MAL', 'gold'),
  ('MRS', 'olive-oil'),
  ('MRS', 'coral'),
  ('MRS', 'wool-cloth'),
  ('MRS', 'wheat'),
  ('MRS', 'coffee'),
  ('MRS', 'verdigris'),
  ('MRS', 'soap'),
  ('MRS', 'wine'),
  ('MRS', 'almonds'),
  ('MRS', 'cotton-raw'),
  ('MOK', 'rice'),
  ('MOK', 'cotton-cloth'),
  ('MOK', 'ramie-cloth'),
  ('MOK', 'seaweed'),
  ('MYE', 'tin'),
  ('MYE', 'sappanwood'),
  ('MYE', 'ivory'),
  ('MYE', 'timber'),
  ('NAG', 'silver'),
  ('NAG', 'copper'),
  ('NAG', 'lacquerware'),
  ('NAG', 'porcelain'),
  ('NAG', 'sandalwood'),
  ('NAG', 'soy-sauce'),
  ('NAG', 'tea'),
  ('NAG', 'dried-fish'),
  ('NAG', 'camphor'),
  ('NAG', 'sulphur'),
  ('NUU', 'walrus-ivory'),
  ('NUU', 'whale-oil'),
  ('NUU', 'sealskins'),
  ('NUU', 'narwhal-horn'),
  ('OLD', 'black-pepper'),
  ('OLD', 'cinnamon'),
  ('OLD', 'horses'),
  ('OLD', 'silk-cloth'),
  ('OLD', 'porcelain'),
  ('OLD', 'chillies'),
  ('OLD', 'bezoar'),
  ('OLD', 'arrack'),
  ('OLD', 'coir'),
  ('OLD', 'opium'),
  ('OSA', 'rice'),
  ('OSA', 'silver'),
  ('OSA', 'sake'),
  ('OSA', 'cotton-cloth'),
  ('OSA', 'folding-fans'),
  ('OSA', 'soy-sauce'),
  ('OSA', 'iron'),
  ('OSA', 'copper'),
  ('OSA', 'lacquerware'),
  ('OSA', 'salt'),
  ('PAR', 'sugar'),
  ('PAR', 'tobacco'),
  ('PAR', 'annatto'),
  ('PAR', 'cotton-raw'),
  ('POR', 'sugar'),
  ('POR', 'rum'),
  ('POR', 'allspice'),
  ('POR', 'logwood'),
  ('SAI', 'gum-arabic'),
  ('SAI', 'ivory'),
  ('SAI', 'hides'),
  ('SAI', 'wax'),
  ('SLV', 'sugar'),
  ('SLV', 'tobacco'),
  ('SLV', 'brazilwood'),
  ('SLV', 'hides'),
  ('SLV', 'cassava'),
  ('SLV', 'cotton-raw'),
  ('SLV', 'whale-oil'),
  ('SLV', 'ginger'),
  ('SLV', 'chillies'),
  ('SLV', 'molasses'),
  ('SAN', 'sugar'),
  ('SAN', 'ginger'),
  ('SAN', 'hides'),
  ('SAN', 'timber'),
  ('SVQ', 'silver'),
  ('SVQ', 'olive-oil'),
  ('SVQ', 'wine'),
  ('SVQ', 'cochineal'),
  ('SVQ', 'wheat'),
  ('SVQ', 'quicksilver'),
  ('SVQ', 'silver-plate'),
  ('SVQ', 'citrus'),
  ('SVQ', 'soap'),
  ('SVQ', 'indigo'),
  ('SRT', 'cotton-cloth'),
  ('SRT', 'indigo'),
  ('SRT', 'saltpetre'),
  ('SRT', 'silk-cloth'),
  ('SRT', 'black-pepper'),
  ('SRT', 'shawls'),
  ('SRT', 'carnelian'),
  ('SRT', 'cotton-raw'),
  ('SRT', 'myrobalans'),
  ('SRT', 'ghee'),
  ('SYD', 'timber'),
  ('SYD', 'sealskins'),
  ('SYD', 'wool-raw'),
  ('SYD', 'dried-fish'),
  ('TER', 'cloves'),
  ('TER', 'rice'),
  ('TER', 'sharks-fin'),
  ('TER', 'paradise-plumes'),
  ('TER', 'sago'),
  ('THA', 'rubies'),
  ('THA', 'lac'),
  ('THA', 'martaban-jars'),
  ('THA', 'elephants'),
  ('TID', 'cloves'),
  ('TID', 'rice'),
  ('TID', 'dried-fish'),
  ('TID', 'tortoiseshell'),
  ('TOK', 'rice'),
  ('TOK', 'lacquerware'),
  ('TOK', 'timber'),
  ('TOK', 'copper'),
  ('TOK', 'dried-fish'),
  ('TOK', 'soy-sauce'),
  ('TOK', 'salt'),
  ('TOK', 'seaweed'),
  ('TOK', 'paper'),
  ('TOK', 'sword-blades'),
  ('TRA', 'silk-raw'),
  ('TRA', 'carpets'),
  ('TRA', 'copper'),
  ('TRA', 'hazelnuts'),
  ('TRI', 'silk-raw'),
  ('TRI', 'soap'),
  ('TRI', 'gallnuts'),
  ('TRI', 'pistachios'),
  ('TRO', 'copper'),
  ('TRO', 'dried-fish'),
  ('TRO', 'timber'),
  ('TRO', 'whale-oil'),
  ('TSU', 'ginseng'),
  ('TSU', 'ramie-cloth'),
  ('TSU', 'silver'),
  ('TSU', 'dried-fish'),
  ('TUR', 'tar'),
  ('TUR', 'timber'),
  ('TUR', 'furs'),
  ('TUR', 'dried-fish'),
  ('VEN', 'glassware'),
  ('VEN', 'silk-cloth'),
  ('VEN', 'salt'),
  ('VEN', 'velvet'),
  ('VEN', 'lace'),
  ('VEN', 'books'),
  ('VEN', 'glass-beads'),
  ('VEN', 'theriac'),
  ('VEN', 'soap'),
  ('VEN', 'dried-fruit'),
  ('VER', 'silver'),
  ('VER', 'cochineal'),
  ('VER', 'cacao'),
  ('VER', 'chillies'),
  ('VER', 'vanilla'),
  ('VER', 'maize'),
  ('VER', 'sarsaparilla'),
  ('VER', 'jalap'),
  ('VER', 'indigo'),
  ('VER', 'logwood'),
  ('WIL', 'salt'),
  ('WIL', 'hides'),
  ('WIL', 'salted-beef'),
  ('WIL', 'logwood'),
  ('ZAN', 'ivory'),
  ('ZAN', 'rhino-horn'),
  ('ZAN', 'cotton-cloth'),
  ('ZAN', 'ambergris'),
  ('ZAN', 'coconuts'),
  ('ZAN', 'copal'),
  ('ZAN', 'timber');

create temporary table geo_target_ids_0062 as
select p.id as port_id, g.id as good_id, t.port_code, t.good_code
  from geo_target_0062 t
  join public.ports p on p.code = t.port_code
  join public.goods g on g.code = t.good_code;

do $$
declare v_n int;
begin
  select count(*) into v_n from geo_target_0062;
  if v_n <> (select count(*) from geo_target_ids_0062) then
    raise exception '0062 self-assert FAIL: % target row(s) name a port or good that does not exist',
      v_n - (select count(*) from geo_target_ids_0062);
  end if;
end $$;

delete from public.port_specialties s
 where s.port_id in (select distinct port_id from geo_target_ids_0062)
   and not exists (select 1 from geo_target_ids_0062 t
                    where t.port_id = s.port_id and t.good_id = s.good_id);

insert into public.port_specialties (port_id, good_id)
select t.port_id, t.good_id from geo_target_ids_0062 t
 where not exists (select 1 from public.port_specialties s
                    where s.port_id = t.port_id and s.good_id = t.good_id);

-- ── 3. WHAT MUST MOVE WITH IT — 0048/0058's own recompute, composed, not re-derived ────────────
update public.port_goods pg
   set affinity = world.affinity_for(pg.port_id, pg.good_id);

update public.port_goods pg
   set stock_target    = greatest(60, round(200 * p.size_tier * (1.60 - pg.affinity))),
       stock           = least(pg.stock, greatest(60, round(200 * p.size_tier * (1.60 - pg.affinity)))),
       production_rate = case when pg.affinity < 0.80
                               then round(greatest(60, 200 * p.size_tier * (1.60 - pg.affinity)) * 0.05, 2)
                               else 0 end
  from public.ports p
 where p.id = pg.port_id;

update public.ports p
   set dev_commerce = greatest(0, least(20, round(p.size_tier * 2.4 + coalesce(x.c_all, 0)))),
       dev_industry = greatest(0, least(20, round(p.size_tier * 2.0 + coalesce(x.c_ind, 0) * 1.5)))
  from (
         select s.port_id,
                count(*)::int as c_all,
                count(*) filter (where g.category in ('metal', 'textile', 'naval-stores'))::int as c_ind
           from public.port_specialties s
           join public.goods g on g.id = s.good_id
          group by s.port_id
       ) x
 where p.kind = 'HARBOUR' and x.port_id = p.id;

-- ── 4. THE 56 PAIRS 0058'S HASH INVENTED, kept only to prove they are gone (assert (j)) ────────
create temporary table geo_hash_picks_0062 (port_code text not null, good_code text not null);
insert into geo_hash_picks_0062 (port_code, good_code) values
  ('ALE', 'salted-tuna'),
  ('AMS', 'ramie-cloth'),
  ('ARP', 'mastic'),
  ('BAR', 'benzoin'),
  ('BAR', 'cassava'),
  ('BOR', 'sugar'),
  ('BOR', 'wootz-steel'),
  ('BUS', 'cowries'),
  ('BUS', 'fustian'),
  ('CAD', 'myrrh'),
  ('CAD', 'silver-plate'),
  ('CLL', 'majolica'),
  ('CLL', 'mastic'),
  ('CAR', 'rosewater'),
  ('COP', 'camwood'),
  ('GDA', 'celadon'),
  ('GOA', 'mangrove-poles'),
  ('GUA', 'ramie-cloth'),
  ('HAM', 'muslin'),
  ('HAV', 'brandy'),
  ('HAV', 'guaiacum'),
  ('IST', 'coir'),
  ('IST', 'timber'),
  ('JAK', 'chillies'),
  ('JAK', 'herring'),
  ('KOC', 'majolica'),
  ('KOZ', 'linen'),
  ('KOZ', 'pearls'),
  ('KOZ', 'vicuna-wool'),
  ('LIS', 'opium'),
  ('LIS', 'saffron'),
  ('LON', 'cowries'),
  ('LUB', 'paintings'),
  ('MAC', 'ambergris'),
  ('MAC', 'grains-of-paradise'),
  ('MAC', 'paper'),
  ('MAL', 'cotton-raw'),
  ('MAL', 'emeralds'),
  ('MAL', 'ostrich-feathers'),
  ('MNL', 'ivory'),
  ('MRS', 'tamarind'),
  ('NAG', 'isinglass'),
  ('NAG', 'palm-sugar'),
  ('OLD', 'star-anise'),
  ('OSA', 'sandalwood'),
  ('SLV', 'chillies'),
  ('SLV', 'dried-fruit'),
  ('SVQ', 'ginger'),
  ('SRT', 'folding-fans'),
  ('TOK', 'caviar'),
  ('TOK', 'gold-thread'),
  ('TOK', 'lychees'),
  ('TOK', 'molasses'),
  ('TOK', 'sealskins'),
  ('VEN', 'sassafras'),
  ('VER', 'camphor');

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_harbours   int;  v_offers int;  v_goods int;  v_bad int;  v_n int;
  v_list       text;
  v_native     int;  v_entrepot int;
  v_masked     int;
  v_orphans_before int;
  v_offers_before  int;
  v_hash_alive int;
  v_singular   int;  v_broad int;
  v_maxreg     int;
begin
  -- (a) NON-VACUOUS FLOOR. Nothing below proves anything against an empty world.
  select harbours, offers, goods, orphans into v_harbours, v_offers_before, v_goods, v_orphans_before
    from geo_before_0062;
  if v_harbours < 200 or v_offers_before < 1000 or v_goods <> 243 then
    raise exception '0062 self-assert FAIL: the world before this file held % harbour(s), % offer(s) and % good(s) — too small for anything below to be a real check',
      v_harbours, v_offers_before, v_goods;
  end if;
  if (select count(*) from geo_target_0062) < 400 then
    raise exception '0062 self-assert FAIL: only % roster row(s) written — this file claims to re-author 75 harbours', (select count(*) from geo_target_0062);
  end if;

  -- (b) THE GEOGRAPHY IS WELL FORMED. Never empty, never a code the world does not define.
  select count(*) into v_bad from public.goods where cardinality(origin_regions) = 0;
  if v_bad <> 0 then
    raise exception '0062 self-assert FAIL: % good(s) name no origin region — every good comes from somewhere', v_bad;
  end if;
  select count(*) into v_bad from public.goods g, unnest(g.origin_regions) c
   where not exists (select 1 from public.regions r where r.code = c);
  if v_bad <> 0 then
    raise exception '0062 self-assert FAIL: % origin region code(s) name no region in this world', v_bad;
  end if;
  select count(*) into v_bad from public.goods g, unnest(g.entrepot_ports) c
   where not exists (select 1 from public.ports p where p.code = c and p.kind = 'HARBOUR');
  if v_bad <> 0 then
    raise exception '0062 self-assert FAIL: % entrepot port code(s) name no harbour in this world', v_bad;
  end if;
  -- an entrepot is by definition OUTSIDE the origin: a port listed in both is a confused row
  select count(*) into v_bad from public.goods g
    join public.ports p on p.code = any(g.entrepot_ports)
    join public.regions r on r.id = p.region_id
   where r.code = any(g.origin_regions);
  if v_bad <> 0 then
    raise exception '0062 self-assert FAIL: % entrepot row(s) name a port that already sits in the good''s own origin region', v_bad;
  end if;
  -- an entrepot row that no roster uses is a claim nobody checks
  select count(*) into v_bad from public.goods g, unnest(g.entrepot_ports) c
   where not exists (select 1 from public.port_specialties s
                       join public.ports p on p.id = s.port_id
                      where p.code = c and s.good_id = g.id);
  if v_bad <> 0 then
    raise exception '0062 self-assert FAIL: % entrepot row(s) name a port that does not actually offer the good', v_bad;
  end if;

  -- (c) THE LAW, WITH NO THIRD CASE: every offer in the WHOLE world is native or a named entrepot.
  select count(*) into v_bad
    from public.port_specialties s
    join public.ports p on p.id = s.port_id
    join public.regions r on r.id = p.region_id
    join public.goods g on g.id = s.good_id
   where not (r.code = any(g.origin_regions))
     and not (p.code = any(g.entrepot_ports));
  if v_bad <> 0 then
    select string_agg(p.code || '/' || g.code, ', ' order by p.code) into v_list
      from public.port_specialties s
      join public.ports p on p.id = s.port_id
      join public.regions r on r.id = p.region_id
      join public.goods g on g.id = s.good_id
     where not (r.code = any(g.origin_regions)) and not (p.code = any(g.entrepot_ports));
    raise exception '0062 self-assert FAIL: % offer(s) are neither native to their port''s region nor a named entrepot: %', v_bad, left(v_list, 900);
  end if;

  -- (c2) AND BOTH BRANCHES ARE REAL. An OR whose second arm never fires is a law with a dead half;
  --      the entrepot arm must be carrying actual offers, or (c) proved only "everything is native".
  select count(*) into v_native
    from public.port_specialties s
    join public.ports p on p.id = s.port_id
    join public.regions r on r.id = p.region_id
    join public.goods g on g.id = s.good_id
   where r.code = any(g.origin_regions);
  select count(*) into v_entrepot
    from public.port_specialties s
    join public.ports p on p.id = s.port_id
    join public.regions r on r.id = p.region_id
    join public.goods g on g.id = s.good_id
   where not (r.code = any(g.origin_regions)) and p.code = any(g.entrepot_ports);
  if v_entrepot < 20 then
    raise exception '0062 self-assert FAIL: only % entrepot offer(s) in the whole world — the second arm of the roster law is not carrying the trade this file says it carries', v_entrepot;
  end if;
  select count(*) into v_offers from public.port_specialties;
  if v_native + v_entrepot <> v_offers then
    raise exception '0062 self-assert FAIL: % native + % entrepot <> % offers — the two arms do not partition the roster', v_native, v_entrepot, v_offers;
  end if;

  -- (d) EVERY GOOD EXISTS SOMEWHERE, AND AT ITS OWN SOURCE. This is exactly what 0058 broke: it
  --     left allspice, pistachios and lac priced, catalogued and buyable nowhere on earth.
  select count(*) into v_bad from public.goods g
   where not exists (select 1 from public.port_specialties s where s.good_id = g.id);
  if v_bad <> 0 then
    select string_agg(g.code, ', ' order by g.code) into v_list from public.goods g
     where not exists (select 1 from public.port_specialties s where s.good_id = g.id);
    raise exception '0062 self-assert FAIL: % good(s) are carried by no port at all: %', v_bad, v_list;
  end if;
  select count(*) into v_bad from public.goods g
   where not exists (
     select 1 from public.port_specialties s
       join public.ports p on p.id = s.port_id
       join public.regions r on r.id = p.region_id
      where s.good_id = g.id and r.code = any(g.origin_regions));
  if v_bad <> 0 then
    select string_agg(g.code, ', ' order by g.code) into v_list from public.goods g
     where not exists (
       select 1 from public.port_specialties s
         join public.ports p on p.id = s.port_id
         join public.regions r on r.id = p.region_id
        where s.good_id = g.id and r.code = any(g.origin_regions));
    raise exception '0062 self-assert FAIL: % good(s) can be bought only in re-export, never at a producer: %', v_bad, v_list;
  end if;
  -- and no SEA_PLACE gained a roster on the way past (0036/0058's door stays shut)
  select count(*) into v_bad from public.port_specialties s
    join public.ports p on p.id = s.port_id where p.kind = 'SEA_PLACE';
  if v_bad <> 0 then
    raise exception '0062 self-assert FAIL: % sea place offer(s) — a sea place carries no quay and this file must not open that door', v_bad;
  end if;

  -- (e) THE OWNER'S COUNT LAW STILL HOLDS EXACTLY — composed from 0058, not retyped here.
  select count(*) into v_bad
    from public.ports p
    join lateral (select count(*)::int as c from public.port_specialties s where s.port_id = p.id) sc on true
   where p.kind = 'HARBOUR'
     and public.roster_target_count(p.size_tier, sc.c, public.roster_rng(p.code || ':count')) <> sc.c;
  if v_bad <> 0 then
    select string_agg(p.code || '=' || sc.c, ', ' order by p.code) into v_list
      from public.ports p
      join lateral (select count(*)::int as c from public.port_specialties s where s.port_id = p.id) sc on true
     where p.kind = 'HARBOUR'
       and public.roster_target_count(p.size_tier, sc.c, public.roster_rng(p.code || ':count')) <> sc.c;
    raise exception '0062 self-assert FAIL: % harbour(s) no longer satisfy 0058''s count law (capital 10 / mid 4-8 / small 4): %', v_bad, left(v_list, 600);
  end if;

  -- (f) THE THREE GOODS 0058 ORPHANED ARE BACK, AT THE PORTS HISTORY GIVES THEM. Named subjects,
  --     no lottery: allspice at Port Royal (Jamaica pimento, its only source), pistachios at
  --     Tripoli of Syria (Aleppo's port), lac at Syriam (Pegu).
  if not exists (select 1 from public.port_specialties s
                   join public.ports p on p.id = s.port_id join public.goods g on g.id = s.good_id
                  where p.code = 'POR' and g.code = 'allspice') then
    raise exception '0062 self-assert FAIL: Port Royal does not carry allspice — Jamaica pimento had no other source and 0058 left it buyable nowhere';
  end if;
  if not exists (select 1 from public.port_specialties s
                   join public.ports p on p.id = s.port_id join public.goods g on g.id = s.good_id
                  where p.code = 'TRI' and g.code = 'pistachios') then
    raise exception '0062 self-assert FAIL: Tripoli of Syria does not carry pistachios';
  end if;
  if not exists (select 1 from public.port_specialties s
                   join public.ports p on p.id = s.port_id join public.goods g on g.id = s.good_id
                  where p.code = 'THA' and g.code = 'lac') then
    raise exception '0062 self-assert FAIL: Syriam does not carry lac';
  end if;

  -- (g) THE SIX RESTORATIONS THE HEADER NAMES, each a port whose own note names the good it lost.
  select count(*) into v_bad from (values
      ('KAL', 'amber'), ('SAI', 'gum-arabic'), ('TRO', 'copper'),
      ('WIL', 'salt'),  ('MCH', 'diamonds'),   ('JAF', 'pearls')
    ) as w(pc, gc)
   where not exists (select 1 from public.port_specialties s
                       join public.ports p on p.id = s.port_id join public.goods g on g.id = s.good_id
                      where p.code = w.pc and g.code = w.gc);
  if v_bad <> 0 then
    raise exception '0062 self-assert FAIL: % of the 6 named restorations did not land (Konigsberg amber, Saint-Louis gum arabic, Trondheim copper, Curacao salt, Machilipatnam diamonds, Jaffna pearls)', v_bad;
  end if;

  -- (h) THE CULTURE MASKS BITE. Seven goods carry one; a port of a masked culture may not produce
  --     the good it refuses to trade; and every culture named is a culture some port actually has.
  select count(*) into v_masked from public.goods where culture_mask <> '{}';
  if v_masked <> 7 then
    raise exception '0062 self-assert FAIL: % good(s) carry a culture mask, not the 7 this file authors (six spirits + salted beef)', v_masked;
  end if;
  if not exists (select 1 from public.goods where code = 'salted-beef' and 'indic' = any(culture_mask))
     or not exists (select 1 from public.goods where code = 'salted-beef' and 'japanese' = any(culture_mask)) then
    raise exception '0062 self-assert FAIL: salted-beef is not masked to both indic and japanese';
  end if;
  select count(*) into v_bad from public.goods g, unnest(g.culture_mask) c
   where not exists (select 1 from public.ports p where p.culture = c);
  if v_bad <> 0 then
    raise exception '0062 self-assert FAIL: % culture mask entr(y/ies) name a culture no port in this world has — a mask nothing can match refuses nothing', v_bad;
  end if;
  select count(*) into v_bad
    from public.port_specialties s
    join public.ports p on p.id = s.port_id
    join public.goods g on g.id = s.good_id
   where p.culture = any(g.culture_mask);
  if v_bad <> 0 then
    select string_agg(p.code || '/' || g.code, ', ' order by p.code) into v_list
      from public.port_specialties s
      join public.ports p on p.id = s.port_id
      join public.goods g on g.id = s.good_id
     where p.culture = any(g.culture_mask);
    raise exception '0062 self-assert FAIL: % port(s) produce a good their own culture will not trade: %', v_bad, v_list;
  end if;
  -- and each mask REFUSES SOMEWHERE. A mask whose cultures no harbour holds is a rule that never
  -- fires; every one of the seven must darken the quay of at least one real harbour, and the count
  -- of harbours it darkens is printed in the receipt rather than merely being non-zero.
  select count(*) into v_bad from public.goods g
   where g.culture_mask <> '{}'
     and not exists (select 1 from public.ports p
                      where p.kind = 'HARBOUR' and p.culture = any(g.culture_mask));
  if v_bad <> 0 then
    raise exception '0062 self-assert FAIL: % masked good(s) name only cultures no harbour holds — the refusal would never fire', v_bad;
  end if;
  select count(*) into v_n
    from public.ports p, public.goods g
   where p.kind = 'HARBOUR' and g.culture_mask <> '{}' and p.culture = any(g.culture_mask);
  if v_n < 100 then
    raise exception '0062 self-assert FAIL: the seven masks darken only % (harbour, good) pair(s) — too few for the mechanism to be doing anything', v_n;
  end if;

  -- (i) THE MARKET WAS RESTATED, NOT MINTED (0048/0058's own checks, re-run because the roster moved)
  select count(*) into v_n from public.port_goods;
  if v_n <> (select count(*) from public.ports where kind = 'HARBOUR') * v_goods then
    raise exception '0062 self-assert FAIL: port_goods holds % row(s); harbours x goods is % — this file deleted or added market rows and it must do neither',
      v_n, (select count(*) from public.ports where kind = 'HARBOUR') * v_goods;
  end if;
  select count(*) into v_bad from public.port_goods pg
   where pg.affinity is distinct from world.affinity_for(pg.port_id, pg.good_id);
  if v_bad <> 0 then
    raise exception '0062 self-assert FAIL: % of % port_goods affinities disagree with world.affinity_for after the roster moved', v_bad, v_n;
  end if;
  select count(*) into v_bad from public.port_goods where stock > stock_target;
  if v_bad <> 0 then
    raise exception '0062 self-assert FAIL: % port_goods row(s) hold stock above target — the roster move minted goods', v_bad;
  end if;
  select count(*) into v_bad from public.port_goods pg
   where pg.production_rate is distinct from
         case when pg.affinity < 0.80
              then round(greatest(60, 200 * (select size_tier from public.ports where id = pg.port_id) * (1.60 - pg.affinity)) * 0.05, 2)
              else 0 end;
  if v_bad <> 0 then
    raise exception '0062 self-assert FAIL: % port_goods row(s) hold a production_rate that does not restate 0005''s formula', v_bad;
  end if;
  select count(*) into v_bad
    from public.ports p
    join lateral (select count(*)::int as c_all,
                         count(*) filter (where g.category in ('metal','textile','naval-stores'))::int as c_ind
                    from public.port_specialties s join public.goods g on g.id = s.good_id
                   where s.port_id = p.id) x on true
   where p.kind = 'HARBOUR'
     and (p.dev_commerce <> greatest(0, least(20, round(p.size_tier * 2.4 + x.c_all)))
       or p.dev_industry <> greatest(0, least(20, round(p.size_tier * 2.0 + x.c_ind * 1.5))));
  if v_bad <> 0 then
    raise exception '0062 self-assert FAIL: % harbour(s) hold a dev_commerce/dev_industry that does not restate the roster that now stands', v_bad;
  end if;

  -- (j) THE POSITIVE CONTROL: 0058's hash is retired as an AUTHOR. All 56 pairs it invented for the
  --     capitals must be absent. If even one survives, the draw is still choosing what a city sells.
  select count(*) into v_hash_alive
    from geo_hash_picks_0062 h
    join public.ports p on p.code = h.port_code
    join public.goods g on g.code = h.good_code
    join public.port_specialties s on s.port_id = p.id and s.good_id = g.id;
  if (select count(*) from geo_hash_picks_0062) <> 56 then
    raise exception '0062 self-assert FAIL: the hash-pick control table holds % row(s), not the 56 the receipt of 0058 recorded', (select count(*) from geo_hash_picks_0062);
  end if;
  -- EIGHT of the 56 are KEPT ON PURPOSE, because a blind draw can land on a true fact and deleting
  -- a true fact to tidy a story would be its own dishonesty. Named, so "some survived" can never be
  -- a silent result: Cadiz silver plate (Seville and Cadiz silversmiths worked the bullion),
  -- Canton grasscloth, Havana lignum vitae, the Ottoman arsenal's timber at Istanbul, Batavia's and
  -- Bahia's chillies, Macau's Chinese bamboo paper, and Manila's carved ivory.
  if v_hash_alive > 8 then
    select string_agg(h.port_code || '/' || h.good_code, ', ' order by h.port_code) into v_list
      from geo_hash_picks_0062 h
      join public.ports p on p.code = h.port_code
      join public.goods g on g.code = h.good_code
      join public.port_specialties s on s.port_id = p.id and s.good_id = g.id;
    raise exception '0062 self-assert FAIL: % of 0058''s 56 hash picks are still in the world (only the 8 defensible ones may remain): %', v_hash_alive, v_list;
  end if;
  if v_hash_alive < 8 then
    raise exception '0062 self-assert FAIL: only % of the 8 deliberately-kept hash picks survive — this file dropped a pair it said it was keeping', v_hash_alive;
  end if;

  -- (k) NOTHING CASCADES OFF port_specialties. Re-read from the catalog, not from the header.
  select count(*) into v_bad from pg_constraint c
   where c.contype = 'f' and c.confrelid = 'public.port_specialties'::regclass;
  if v_bad <> 0 then
    raise exception '0062 self-assert FAIL: % foreign key(s) now reference public.port_specialties — deleting an offer would cascade somewhere this file has not reasoned about', v_bad;
  end if;

  -- (l) IDEMPOTENT ON REPLAY: the world this file produced is a fixed point of its own target set.
  select count(*) into v_bad from geo_target_ids_0062 t
   where not exists (select 1 from public.port_specialties s
                      where s.port_id = t.port_id and s.good_id = t.good_id);
  if v_bad <> 0 then
    raise exception '0062 self-assert FAIL: % target offer(s) did not land', v_bad;
  end if;
  select count(*) into v_bad from public.port_specialties s
   where s.port_id in (select distinct port_id from geo_target_ids_0062)
     and not exists (select 1 from geo_target_ids_0062 t
                      where t.port_id = s.port_id and t.good_id = s.good_id);
  if v_bad <> 0 then
    raise exception '0062 self-assert FAIL: % offer(s) survive at a re-authored port but are in no target row — replaying this file would move the world again', v_bad;
  end if;

  -- (m) POSTURE: two new columns on a read-only table change nothing a client may write.
  select count(*) into v_bad from public.client_write_grants();
  if v_bad <> 0 then
    raise exception '0062 self-assert FAIL: % client write grant(s) exist on public tables after this file ran', v_bad;
  end if;

  -- ── the receipt ──────────────────────────────────────────────────────────────────────────────
  select count(*) into v_singular from public.goods where cardinality(origin_regions) = 1;
  select count(*) into v_broad    from public.goods where cardinality(origin_regions) >= 5;
  select max(cardinality(origin_regions)) into v_maxreg from public.goods;
  raise notice '0062 self-assert ok: % offer(s) across % harbour(s) — % native to their port''s region, % at % named entrepot port(s); every one of % good(s) is produced somewhere and buyable at a producer (0058 had left 3 buyable nowhere); % good(s) come from exactly ONE region and % from five or more (widest: % regions); % good(s) carry a culture mask and no port produces what its own culture refuses; % of 0058''s 56 hash picks survive, all 8 defensible; 0058''s count law still exact on every harbour',
    v_offers, v_harbours, v_native, v_entrepot,
    (select count(*) from (select distinct unnest(entrepot_ports) from public.goods) x),
    v_goods, v_singular, v_broad, v_maxreg, v_masked, v_hash_alive;
end $$;
