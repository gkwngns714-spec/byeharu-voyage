# 2026-11-25: 0517 `premium-goods`: one made good, one city that pays 3 to 5 times (dark, proof 221)

The owner: "Each PREMIUM TRADE GOOD will be needed by one city only, and it will pay 300~500% more. PREMIUM TRADE GOODS by themselves costs more",
"3-5 times, with daily limits yes", R7 (near 3, far 5: YES), R8 (reuse the made goods). Switch `premium_goods_enabled`, false. No production read.

## What 0517 does, lit

- The good's city (`goods.premium_port_id`, data) pays a company 3 to 5 times ITS OWN normal price: 3 at 500 sailed miles or fewer from the
  nearest city that offers the good (`port_goods.haul_nm`), 5 from 12,000, straight between. Any other city: the normal price.
- 30 units a day (real, UTC) a city, for all companies together; the rest of a load at the normal price in the same quote.
- **Only what she MADE.** The premium is paid for no more units than the company forged (`cmd.forge_good`, its FORGE on HQ) and has not yet sold
  at a premium: `public.premium_made`, one row a company and good, server only, counted dark too. Bought units: the normal price. A count, not a
  mark on each unit: who makes 10, sells them at the normal price and buys 10 others, sells those at the premium. Merchants never.
- What was made before the deploy: the chain records a `FORGED` event a forging (product, quantity; 0281), so those count. The land's smith
  (0461) writes no such record and is not counted, before or after.
- Its base price is 1.25 times everywhere ("costs more"), buying and selling, so margins elsewhere scale with it. Merchants' prices too.
- One place: `public.premium_left`, asked by `world.quote_priced` and the door's tally. No re-cut of `run_day`, the sale's face or never-lose.
- Needs the closed economy and the city purses (an open economy would mint the pay).

## A small purse

- Units are also capped by 5 % of (purse less the greater of reserve and floor), paid whole, at each sale. None to spare: the normal price.
- Measured on the chain's numbers (a city's standing purse is 10 M, a capital's 50 M, 0172 / 0285; the chain's own purses are empty): a full day at
  all 100 cities is 17.7 M, 177,000 a city on average; the dearest, Bilbao (Ukiyo-e), 1.27 M, an eighth of a 10 M purse. The purses measured in
  October (p10 21,900, p50 528,000, before the x5) would pay few units or none: the cap is what holds them.
- **Before lighting the lead reads `scripts/ops/harness/premium-goods/purses.sql`** (one statement): spare coin, units payable, a full day's cost.
- No coin is made: one SELL through `public.city_pays`. Proof 221 PG_WORLD: players + cities + flows unmoved; PG_PURSE: 30 sales in a row stay
  over the floor.

## The goods and cities (DECIDED BY DEFAULT, the owner may reverse; not the deck's twelve)

The 100 recipes whose good is worth most against its materials. At base prices 205 of the 287 are worth LESS than their materials, so most of the
rest would not pay to make even at a premium; and a good no city offers has no maker to measure from. The dearer the good, the farther its city.
Each city (size 3 or 5) once; never one that offers or makes the good, or whose culture refuses it. "Made at" is `city_production`; where it is
"-" the good is offered at quays but is no city's product. Some cities lie beyond seas a new company may enter. To move one: update
`goods.premium_port_id`.

| Good (recipe) | Made at | Pays here | Miles | Times |
|---|---|---|---|---|
| Dried Squid (1 Salt + 2 Squid) | - | Naha | 541 | 3.01 |
| Baijiu (2 Fresh Water + 3 Sorghum) | - | Hirado | 820 | 3.06 |
| Doenjang (1 Fresh Water + 1 Salt + 2 Soybean) | Ulsan | Quanzhou | 835 | 3.06 |
| Perry (1 Fresh Water + 3 Pear) | - | Stockholm | 928 | 3.07 |
| Ramie Cloth (1 Fresh Water + 3 Ramie) | Tsushima | Guangzhou | 1,113 | 3.11 |
| Pulque (3 Agave + 1 Fresh Water) | - | Panama City | 1,363 | 3.15 |
| Shrimp Paste (1 Salt + 2 Shrimp) | - | Yeosu | 1,380 | 3.15 |
| Sesame Oil (1 Fresh Water + 2 Sesame) | - | Marseille | 1,399 | 3.16 |
| Palm Sugar (1 Fresh Water + 2 Sugar Cane) | - | Manila | 1,517 | 3.18 |
| Cheese (2 Milk + 1 Salt) | Heraklion, Ponta Delgada | Hamburg | 1,828 | 3.23 |
| Butter (2 Milk + 1 Salt) | Dublin | Tunis | 1,874 | 3.24 |
| Cider (3 Apple + 1 Fresh Water) | - | Naples | 2,139 | 3.29 |
| Soy Sauce (1 Salt + 2 Soybean + 1 Wheat) | - | Banda Neira | 2,265 | 3.31 |
| Sake (2 Fresh Water + 3 Rice) | - | Ayutthaya | 2,535 | 3.35 |
| Wine (2 Grapes + 1 Timber) | - | Riga | 2,547 | 3.36 |
| Chianti (3 Grapes + 1 Timber) | Toulon | Copenhagen | 2,626 | 3.37 |
| Trepang (1 Salt + 2 Sea Cucumber) | - | Incheon | 2,626 | 3.37 |
| Sugar (1 Fresh Water + 1 Lime + 3 Sugar Cane) | Funchal | Quebec City | 2,690 | 3.38 |
| Arrack (2 Fresh Water + 2 Rice + 1 Sugar Cane) | - | Nagasaki | 2,708 | 3.38 |
| Maple Sugar (3 Fresh Water + 1 Timber) | Jamestown | Dublin | 2,722 | 3.39 |
| Witch Hazel (2 Fresh Water + 2 Witch Hazel Bark) | Quebec City | London | 3,081 | 3.45 |
| Crossbows (1 Iron Bars + 2 Planks + 1 Yarn) | Dubrovnik, Venice | Bergen | 3,211 | 3.47 |
| Palm Wine (1 Fresh Water + 2 Palm Sap) | Soyo | Valencia | 3,215 | 3.47 |
| Cassava Flour (2 Cassava Root + 1 Fresh Water) | Luanda | Porto | 3,283 | 3.48 |
| Toddy (1 Fresh Water + 2 Palm Sap) | - | Macau | 3,344 | 3.49 |
| Maghreb Brasswork (2 Brass Ingots + 1 Sea Coal) | - | Arkhangelsk | 3,418 | 3.51 |
| Flanders Lace (1 Linen + 2 Yarn) | - | Jamestown | 3,519 | 3.53 |
| Glassware (3 Glass + 1 Potash) | - | Boston | 3,569 | 3.53 |
| Rum (1 Fresh Water + 3 Molasses) | - | Plymouth | 3,577 | 3.54 |
| Martaban Jars (3 Clay + 1 Pine Pitch + 1 Sand) | - | Fukuoka | 3,587 | 3.54 |
| Prussian Blue (2 Iron + 1 Potash + 1 Sea Coal) | - | Izmir | 3,741 | 3.56 |
| Shark Fin (1 Salt + 2 Shark) | - | Mumbai | 3,917 | 3.59 |
| Lead White (1 Fresh Water + 1 Grapes + 2 Lead) | - | Recife | 3,929 | 3.60 |
| Folding Fans (1 Bamboo + 1 Rattan + 1 Timber) | - | Chennai | 3,990 | 3.61 |
| War Bows (1 Goose Feathers + 2 Planks + 1 Yarn) | - | Hooghly | 4,171 | 3.64 |
| Rosewater (2 Fresh Water + 2 Rose) | - | St. John's | 4,225 | 3.65 |
| Isinglass (1 Fresh Water + 2 Sturgeon) | - | New York | 4,282 | 3.66 |
| Pike Heads (2 Iron Bars + 1 Planks + 1 Sea Coal) | - | Cartagena | 4,423 | 3.68 |
| Armour (2 Iron Bars + 1 Leather + 1 Woollen Cloth) | Genoa | Havana | 4,473 | 3.69 |
| Worsted (1 Fresh Water + 3 Raw Wool) | - | Portobelo | 4,565 | 3.71 |
| Tapa Cloth (3 Bark + 1 Fresh Water) | - | Bandar Abbas | 4,798 | 3.75 |
| Dried Abalone (2 Abalone + 1 Salt) | Hirado | Surat | 4,907 | 3.77 |
| Steel Billets (3 Iron Bars + 2 Sea Coal) | Hormuz | Xiamen | 5,005 | 3.78 |
| Mission Wine (1 Fresh Water + 3 Grapes) | - | Osaka | 5,050 | 3.79 |
| Korean Ramie (1 Fresh Water + 3 Ramie) | Tongyeong | Khambhat | 5,059 | 3.79 |
| Celadon Ware (3 Clay + 1 Feldspar + 1 Potash) | Ayutthaya, Busan | San Francisco | 5,156 | 3.81 |
| Attar of Roses (1 Fresh Water + 3 Rose + 1 Tallow) | Basra | Ningbo | 5,222 | 3.82 |
| Porcelain (2 Clay + 1 Feldspar + 1 Quartz) | Lisbon | Basra | 5,352 | 3.84 |
| Caviar (1 Salt + 2 Sturgeon) | - | Santo Domingo | 5,358 | 3.84 |
| Parchment (1 Fresh Water + 2 Hides + 1 Lime) | - | Rio de Janeiro | 5,498 | 3.87 |
| Dried Shrimp (1 Salt + 2 Shrimp) | - | Tokyo | 5,989 | 3.95 |
| Iznik Tiles (3 Clay + 1 Cobalt Blue + 1 Quartz + 1 Sand) | - | Veracruz | 6,442 | 4.03 |
| Guayaquil Cacao (3 Cacao Bean + 1 Fresh Water) | - | Salvador | 6,452 | 4.04 |
| Coffee (2 Coffee Bean + 2 Fresh Water) | - | Sakai | 6,504 | 4.04 |
| Hide Shields (1 Iron Bars + 2 Leather + 1 Planks) | Mombasa | Malaga | 6,690 | 4.08 |
| Matchlocks (2 Iron Bars + 1 Planks + 1 Saltpetre + 1 Sulphur) | Osaka | Jeddah | 6,798 | 4.10 |
| Pandanus Mats (3 Pandanus + 1 Turmeric) | - | Arica | 6,811 | 4.10 |
| Shot and Ball (2 Iron Bars + 2 Lead + 1 Sea Coal) | - | Buenos Aires | 7,013 | 4.13 |
| Block-printed Books (1 Ink & Brushes + 1 Paper + 1 Planks) | Guangzhou | Cape Town | 7,042 | 4.14 |
| Soconusco Cacao (3 Cacao Bean + 1 Fresh Water + 1 Honey) | - | Busan | 7,342 | 4.19 |
| Tea (2 Fresh Water + 2 Tea Leaf) | - | Acapulco | 7,644 | 4.24 |
| Lace (1 Linen + 2 Yarn) | - | Island of Mozambique | 8,029 | 4.31 |
| Antwerp Imprints (1 Ink & Brushes + 1 Leather + 2 Paper) | Bordeaux, Nantes | Zanzibar | 8,276 | 4.35 |
| Paintings (1 Linen + 1 Ochre + 1 Planks) | - | Mombasa | 8,360 | 4.37 |
| Sword Blades (1 Fresh Water + 1 Sea Coal + 2 Steel Billets) | Tokyo | Callao | 8,615 | 4.41 |
| Muskets (2 Iron Bars + 1 Planks + 1 Saltpetre + 1 Sea Coal + 1 Sulphur) | Hirado, Sakai | Guayaquil | 8,616 | 4.41 |
| Cacao (2 Cacao Bean + 1 Fresh Water + 1 Honey) | Acapulco | Ponta Delgada | 8,968 | 4.47 |
| Carved Doors (1 Coir + 1 Iron Bars + 3 Planks) | Island of Mozambique | Tallinn | 9,168 | 4.51 |
| Palm-leaf Manuscripts (1 Ink & Brushes + 2 Palm Leaf) | Colombo | Cadiz | 9,483 | 4.56 |
| Saffian Leather (1 Alum + 3 Leather + 2 Madder) | - | Kozhikode | 9,522 | 4.57 |
| Goryeo Celadon (3 Clay + 1 Feldspar + 1 Potash) | - | Luanda | 9,648 | 4.59 |
| Slow Match (1 Fresh Water + 2 Hemp & Cordage + 1 Saltpetre) | - | Hormuz | 9,852 | 4.63 |
| Falconet (2 Iron Bars + 1 Planks + 1 Saltpetre + 1 Tin) | Naples | Aden | 9,956 | 4.64 |
| Wootz Steel (1 Clay + 3 Iron Bars + 2 Sea Coal) | - | Barcelona | 9,977 | 4.65 |
| Rocket Tubes (1 Planks + 2 Saltpetre + 1 Sea Coal + 1 Sulphur) | Mumbai, Old Goa | Bordeaux | 10,180 | 4.68 |
| Arquebus (2 Iron Bars + 1 Planks + 1 Saltpetre + 1 Sulphur) | Saint-Malo | Colombo | 10,257 | 4.70 |
| Cannon (3 Iron Bars + 1 Planks + 1 Saltpetre + 1 Tin) | - | Mocha | 10,295 | 4.70 |
| Muslin (1 Fresh Water + 3 Raw Cotton) | - | Algiers | 10,328 | 4.71 |
| Movable Type (2 Brass Ingots + 1 Lead + 1 Planks + 1 Tin) | - | Elmina | 10,552 | 4.75 |
| Kashmir Shawls (1 Madder + 3 Yarn) | - | Valletta | 10,644 | 4.76 |
| Astrolabes (1 Brass Ingots + 1 Iron Bars + 1 Planks) | Bandar Abbas, Jeddah | Amsterdam | 10,721 | 4.78 |
| Venetian Imprints (1 Ink & Brushes + 1 Leather + 2 Paper) | - | Kochi | 10,879 | 4.81 |
| Swivel Gun (2 Iron Bars + 1 Planks + 1 Saltpetre + 1 Tin) | - | Muscat | 10,910 | 4.81 |
| Murano Glass (1 Cobalt Blue + 3 Glass) | Dubrovnik | Old Goa | 11,006 | 4.83 |
| Nipa Mats (1 Fresh Water + 3 Nipa Palm) | - | Nantes | 11,094 | 4.84 |
| Tapestries (1 Madder + 1 Silk Cloth + 2 Woollen Cloth) | - | Banten | 11,094 | 4.84 |
| Nautical Clocks (1 Brass Ingots + 1 Glass + 1 Iron Bars + 1 Planks) | Dublin | Jakarta | 11,277 | 4.87 |
| Clocks & Instruments (1 Brass Ingots + 1 Glass + 1 Iron Bars + 1 Planks) | - | Banda Aceh | 11,306 | 4.88 |
| Rice Paper (2 Bark + 1 Fresh Water) | - | Las Palmas | 11,391 | 4.89 |
| Sea Charts & Globes (1 Ochre + 1 Paper + 1 Planks) | - | Ternate | 11,689 | 4.95 |
| Flemish Panels (1 Linen + 1 Ochre + 2 Planks) | Rotterdam | Malacca | 11,695 | 4.95 |
| Armillary Spheres (1 Brass Ingots + 1 Iron Bars + 1 Planks) | Barcelona, Malaga | Tainan | 12,251 | 5.00 |
| Italian Canvases (2 Linen + 1 Ochre + 1 Planks) | Palermo, Valletta | Ambon | 12,358 | 5.00 |
| Portolan Charts (1 Ochre + 1 Paper + 1 Planks) | - | Makassar | 12,479 | 5.00 |
| Kyoto Fans (1 Bamboo + 1 Rattan + 1 Timber) | - | Funchal | 12,603 | 5.00 |
| Terrestrial Globes (1 Copper + 1 Ochre + 1 Planks) | - | Hoi An | 12,696 | 5.00 |
| Scroll Paintings (1 Ochre + 2 Paper + 1 Planks) | Macau | La Rochelle | 12,786 | 5.00 |
| Sutra Scrolls (1 Ink & Brushes + 1 Paper + 1 Planks) | Fukuoka, Sakai | Seville | 13,144 | 5.00 |
| Nacre Inlay (1 Gum Arabic + 2 Mother-of-Pearl + 2 Planks) | - | Lisbon | 13,244 | 5.00 |
| Ukiyo-e Prints (1 Indigo + 1 Paper + 1 Planks) | Fukuoka | Bilbao | 13,739 | 5.00 |

## Which list? (the owner's to choose)

- **(a) made and profitable:** 85 recipes' goods are worth their materials at base, 108 with the 25 %, 219 with three times on top. The 100 above are
  the best of these that some quay offers. **This is the default as deployed.**
- **(b) only goods no quay sells: 17**, under 30, so it is not the default. All are cheap half-made stuff, none worth its materials at the normal
  price (leather and yarn not even at 3 times): Rice, Wheat, Barley, Maize, Rye and Oat Flour, Cream, Malt, Ship's Biscuit, Bread, Rye Bread, Iron Bars,
  Planks, Glass, Cake, Yarn, Leather. No quay sells them, so there is no distance (`haul_nm` is null): the near multiple, 3. On purses: 30 a day
  of all 17 is about 120,000 a day in base prices (201,000 at 5 times) against 17.7 M for (a).
- Honestly: **all 100 are sold at one to three quays.** 33 of them are everyday food, drink and pantry goods: Baijiu, Doenjang, Perry, Pulque,
  Shrimp Paste, Sesame Oil, Palm Sugar, Cheese, Butter, Cider, Soy Sauce, Sake, Wine, Chianti, Sugar, Arrack, Maple Sugar, Palm Wine, Cassava Flour,
  Toddy, Rum, Mission Wine, Caviar, Coffee, Tea, Cacao, Guayaquil Cacao, Soconusco Cacao, Dried Squid, Dried Shrimp, Dried Abalone, Trepang, Shark Fin.
  Recommended: (a) without those 33 (67 made things stay), now that only made units are paid.

## Not verified / known

- Production: digests, purses (`before-0517.sql`, `purses.sql`). Real PostgreSQL: CI.
- The multiple is on the city's own price, which already rises with distance (haul).
- A run's hourly figure is one game day's; the 30 units are a real day's, so once they are gone the figure falls to the normal price.
- A run that has bought may find the day's units taken by another company on arrival: it then sells at the normal price, as with any price move.
- The Forge averages its materials' cost a unit instead of adding them (`forge_take`, 0281): the profit (and its tax) on a made good is
  overstated. Not touched.
