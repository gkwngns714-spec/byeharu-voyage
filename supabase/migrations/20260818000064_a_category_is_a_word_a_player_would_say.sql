-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0064 — A CATEGORY IS A WORD A PLAYER WOULD SAY
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- The owner, reading the seven categories this catalogue had carried since 0002:
--
--     "wtf is foodstuff? are you fucking kidding me? liqure, meat etc. tobacco, etc.
--      did you research?"
--
-- They were right, and the measurement is worse than the complaint. `raw` held 82 goods: dyes
-- (indigo, cochineal, brazilwood, woad, madder), medicines (senna, rhubarb, cinchona, jalap,
-- opium), gunpowder stock (saltpetre, sulphur), hides and furs, LIVESTOCK (horses, war elephants),
-- timber, marble and coal. `foodstuff` held 48 -- grain, every liquor, every stimulant, salt meat,
-- oils, fruit and Cantonese delicacies -- while TOBACCO SAT IN `raw`. `luxury` held 41, mixing
-- gems, porcelain, aromatics, books, paintings, sword blades and live parrots.
--
-- That is not a taxonomy, it is a shelf everything was put on. And it BLOCKED a design: the owner
-- asked for trading captains who specialise by category (row 66), and a "foodstuff trader" would
-- have been a liquor merchant, a grain factor and a delicacy dealer wearing one coat.
--
-- ── SEVENTEEN, IN PLAIN WORDS (docs/DESIGN_V1.md 2.1) ──────────────────────────────────────────
-- grain, food, drink, tobacco, spice, medicine, dye, cloth, metal, gems, crafts, weapons, guns,
-- ship-supplies, art, books, animals
--
-- The owner's second correction shaped these: an earlier draft offered "Indulgences" and
-- "Dyestuff", and they answered "use simpler category i mean come on!" -- so every name is a word
-- a player would say out loud, and LIQUOR IS IN `drink`, where anyone would look for it.
--
-- ── WHAT THIS FILE IS, AND IS NOT ──────────────────────────────────────────────────────────────
-- It moves ONE column on 212 of 243 rows. It adds no table, no function, no grant, and it does not
-- touch a price, a roster, a stock or an affinity: `category` is read by the CLIENT (a good's
-- fallback glyph and the word under its name) and by NO server rule -- checked before writing, it
-- appears in no world.* or cmd.* body in this chain.
--
-- ── WHY THE DATA AND THE DATABASE MOVE TOGETHER ────────────────────────────────────────────────
-- scripts/db/world-guard.mjs compares the applied world to data/*.json field for field, both
-- directions, on every apply. So data/goods.json is edited in the same commit and this file
-- carries the same 243 pairs. If they ever disagree the guard fails the run, which is the whole
-- reason it exists (DEV_LOG D23: 0003 was edited after production had applied it, and "nothing red
-- happened anywhere" while the worlds diverged).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

create temporary table cats_0064 (code text primary key, category text not null);

insert into cats_0064 (code, category) values
  ('black-pepper','spice'), ('cloves','spice'), ('nutmeg','spice'), ('mace','spice'),
  ('cinnamon','spice'), ('ginger','spice'), ('cardamom','spice'), ('long-pepper','spice'),
  ('cubeb','spice'), ('grains-of-paradise','spice'), ('cassia','spice'), ('turmeric','spice'),
  ('saffron','spice'), ('chillies','spice'), ('vanilla','spice'), ('anise','spice'),
  ('cumin','spice'), ('coriander','spice'), ('galangal','spice'), ('star-anise','spice'),
  ('allspice','spice'), ('zedoary','spice'), ('wool-cloth','cloth'), ('linen','cloth'),
  ('cotton-cloth','cloth'), ('muslin','cloth'), ('chintz','cloth'), ('silk-cloth','cloth'),
  ('silk-raw','cloth'), ('carpets','cloth'), ('ramie-cloth','cloth'), ('says-serges','cloth'),
  ('velvet','cloth'), ('lace','cloth'), ('tapestries','cloth'), ('batik','cloth'),
  ('raffia-cloth','cloth'), ('barkcloth','cloth'), ('camlets','cloth'), ('quilts','cloth'),
  ('shawls','cloth'), ('fustian','cloth'), ('gold-thread','cloth'), ('stockings','cloth'),
  ('felt-hats','cloth'), ('gold','metal'), ('silver','metal'), ('copper','metal'),
  ('tin','metal'), ('iron','metal'), ('lead','metal'), ('quicksilver','metal'),
  ('wootz-steel','metal'), ('firearms','guns'), ('cannon','guns'), ('brassware','crafts'),
  ('pewter','crafts'), ('copper-cash','metal'), ('smallwares','crafts'), ('armour','weapons'),
  ('gunpowder','guns'), ('porcelain','crafts'), ('lacquerware','crafts'), ('glassware','crafts'),
  ('pearls','gems'), ('diamonds','gems'), ('ivory','gems'), ('ambergris','medicine'),
  ('musk','medicine'), ('coral','gems'), ('amber','gems'), ('frankincense','medicine'),
  ('myrrh','medicine'), ('rubies','gems'), ('emeralds','gems'), ('carnelian','gems'),
  ('books','books'), ('paper','books'), ('tortoiseshell','gems'), ('mastic','medicine'),
  ('civet','medicine'), ('rosewater','medicine'), ('clocks','art'), ('paintings','art'),
  ('bezoar','medicine'), ('rhino-horn','medicine'), ('lapis-lazuli','gems'), ('turquoise','gems'),
  ('folding-fans','crafts'), ('silver-plate','crafts'), ('majolica','crafts'), ('celadon','crafts'),
  ('stoneware','crafts'), ('martaban-jars','crafts'), ('glass-beads','crafts'), ('sea-charts','art'),
  ('ink-sticks','books'), ('sword-blades','weapons'), ('theriac','medicine'), ('parrots','animals'),
  ('gyrfalcons','animals'), ('paradise-plumes','crafts'), ('wheat','grain'), ('rice','grain'),
  ('sugar','food'), ('salt','food'), ('olive-oil','food'), ('wine','drink'),
  ('dried-fish','food'), ('herring','food'), ('cheese','food'), ('salted-beef','food'),
  ('coffee','drink'), ('tea','drink'), ('cacao','drink'), ('dried-fruit','food'),
  ('rye','grain'), ('barley','grain'), ('beer','drink'), ('sake','drink'),
  ('rum','drink'), ('brandy','drink'), ('arrack','drink'), ('butter','food'),
  ('honey','food'), ('dates','food'), ('figs','food'), ('citrus','food'),
  ('almonds','food'), ('coconuts','food'), ('sago','grain'), ('maize','grain'),
  ('cassava','grain'), ('caviar','food'), ('salted-tuna','food'), ('soy-sauce','food'),
  ('ghee','food'), ('sesame-oil','food'), ('palm-oil','food'), ('birds-nests','food'),
  ('sharks-fin','food'), ('trepang','food'), ('dried-abalone','food'), ('seaweed','food'),
  ('palm-sugar','food'), ('molasses','food'), ('tamarind','food'), ('hazelnuts','food'),
  ('pistachios','food'), ('lychees','food'), ('tobacco','tobacco'), ('indigo','dye'),
  ('cochineal','dye'), ('brazilwood','dye'), ('logwood','dye'), ('alum','dye'),
  ('saltpetre','guns'), ('sulphur','guns'), ('hides','cloth'), ('furs','cloth'),
  ('wax','crafts'), ('cotton-raw','cloth'), ('wool-raw','cloth'), ('gum-arabic','dye'),
  ('sandalwood','medicine'), ('ginseng','medicine'), ('horses','animals'), ('potash','dye'),
  ('tallow','crafts'), ('woad','dye'), ('madder','dye'), ('lac','dye'),
  ('annatto','dye'), ('orchil','dye'), ('henna','dye'), ('camphor','medicine'),
  ('benzoin','medicine'), ('aloeswood','medicine'), ('dragons-blood','dye'), ('socotra-aloes','medicine'),
  ('myrobalans','medicine'), ('sappanwood','dye'), ('red-sanders','dye'), ('camwood','dye'),
  ('ebony','crafts'), ('rattan','crafts'), ('opium','medicine'), ('areca-nuts','medicine'),
  ('kola-nuts','medicine'), ('sarsaparilla','medicine'), ('sassafras','medicine'), ('senna','medicine'),
  ('rhubarb','medicine'), ('china-root','medicine'), ('mother-of-pearl','gems'), ('cowries','crafts'),
  ('chank-shells','crafts'), ('coir','ship-supplies'), ('gallnuts','dye'), ('cinchona-bark','medicine'),
  ('ostrich-feathers','crafts'), ('sponges','crafts'), ('baleen','crafts'), ('sealskins','cloth'),
  ('walrus-ivory','gems'), ('narwhal-horn','gems'), ('eiderdown','crafts'), ('coal','metal'),
  ('marble','crafts'), ('cork','crafts'), ('copal','crafts'), ('tiger-skins','cloth'),
  ('isinglass','food'), ('russia-leather','cloth'), ('morocco-leather','cloth'), ('peru-balsam','medicine'),
  ('jalap','medicine'), ('vicuna-wool','cloth'), ('guaiacum','medicine'), ('verdigris','dye'),
  ('cobalt','dye'), ('gamboge','dye'), ('safflower','dye'), ('catechu','dye'),
  ('elephants','animals'), ('spikenard','medicine'), ('asafoetida','medicine'), ('mecca-balsam','medicine'),
  ('linseed','crafts'), ('hops','drink'), ('soap','crafts'), ('vermilion','dye'),
  ('timber','ship-supplies'), ('naval-timber','ship-supplies'), ('tar','ship-supplies'), ('hemp','ship-supplies'),
  ('flax','ship-supplies'), ('whale-oil','ship-supplies'), ('teak','ship-supplies'), ('rosin','ship-supplies'),
  ('cedar','ship-supplies'), ('mangrove-poles','ship-supplies'), ('abaca','ship-supplies');

-- ── 1. THE WORLD LEARNS THE NEW WORDS ─────────────────────────────────────────────────────────
update public.goods g
   set category = c.category
  from cats_0064 c
 where c.code = g.code
   and g.category is distinct from c.category;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_total   int;
  v_seeded  int;
  v_bad     int;
  v_old     int;
  v_cats    int;
  v_biggest int;
  v_name    text;
begin
  select count(*) into v_total  from public.goods;
  select count(*) into v_seeded from cats_0064;

  -- (a) THE SEED COVERS THE CATALOGUE. A file that re-filed 200 of 243 goods and left 43 on the
  --     old shelf would read as a success and leave the taxonomy half-applied.
  if v_seeded <> v_total then
    raise exception '0064 self-assert FAIL: seeded % category rows for % goods', v_seeded, v_total;
  end if;

  select count(*) into v_bad
    from public.goods g join cats_0064 c on c.code = g.code
   where g.category is distinct from c.category;
  if v_bad <> 0 then
    raise exception '0064 self-assert FAIL: % good(s) do not carry the category the data names', v_bad;
  end if;

  -- (b) POSITIVE CONTROL -- the OLD words are gone from the world entirely. Without this the file
  --     could have updated nothing and still passed (a) on a database already re-filed.
  select count(*) into v_old
    from public.goods
   where category in ('raw', 'foodstuff', 'luxury', 'textile', 'naval-stores');
  if v_old <> 0 then
    raise exception '0064 self-assert FAIL: % good(s) still carry a retired category', v_old;
  end if;

  -- (c) EVERY GOOD NAMES ONE OF THE SEVENTEEN, and nothing invented an eighteenth.
  select count(*) into v_bad
    from public.goods
   where category not in ('grain','food','drink','tobacco','spice','medicine','dye','cloth',
                          'metal','gems','crafts','weapons','guns','ship-supplies','art','books',
                          'animals');
  if v_bad <> 0 then
    raise exception '0064 self-assert FAIL: % good(s) carry a category outside the seventeen', v_bad;
  end if;

  -- (d) THE POINT OF THE EXERCISE, ASSERTED AS A NUMBER. The complaint was that one shelf held a
  --     third of the catalogue. If a future edit lets a bucket grow back past a quarter, this
  --     fails and says which one -- a taxonomy is a SHAPE, not just a list of names.
  select count(*) into v_cats from (select distinct category from public.goods) d;
  select count(*), category into v_biggest, v_name
    from public.goods group by category order by count(*) desc limit 1;
  if v_cats < 15 then
    raise exception '0064 self-assert FAIL: only % categories are inhabited', v_cats;
  end if;
  if v_biggest > v_total / 4 then
    raise exception '0064 self-assert FAIL: "%" holds % of % goods -- that is a shelf, not a category',
      v_name, v_biggest, v_total;
  end if;

  raise notice '0064 self-assert ok: every one of % good(s) carries one of the seventeen plain categories the data names, 0 disagreeing with data/goods.json and 0 still on a retired shelf (raw/foodstuff/luxury/textile/naval-stores, positive control); % categories inhabited and the biggest, "%", holds % -- where the retired "raw" held 82. category is read by no server rule, so no price, roster, stock or affinity moved.',
    v_total, v_cats, v_name, v_biggest;
end $$;
