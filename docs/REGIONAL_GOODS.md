# REGIONAL GOODS — where each of the 243 trade goods comes from, and why every port sells what it sells

> The owner, 2026-08-26, verbatim:
>
> *"Also the 243 trade goods, they should be regional, meaning that for example rice - was a main
> food in eastern asia and india, haggis for example is only in scotland, unique, etc. I want
> something like this not a bunch of list with randomness. I want uniqueness taylored to a location.
> make a list, make a table, file, and orgnize and show how you've organized"*

This file is that list, that table, and the explanation of how it is organised. Everything in it is the
human-readable face of data the game actually runs on, and it is written to be read straight through
rather than compiled.

---

## 0. HOW THIS IS ORGANISED — every question, its one authority, and where that lives on disk

**There is exactly one authority for each question.** Nothing below is derived twice.

| the question | the authority | where it lives | who reads it |
|---|---|---|---|
| **Where does this good come from?** | `origin` — the list of regions that PRODUCE it | `data/goods.json`, one array per good | carried into `public.goods.origin_regions` by migration `0062` |
| **Where else is it sold, and why?** | `entrepots` — the ports outside those regions that historically RE-EXPORTED it | `data/goods.json`, one array per good | carried into `public.goods.entrepot_ports` by `0062` |
| **What does this port trade?** | `goods` — the port's roster | `data/ports.json`, one array per port | carried into `public.port_specialties`; drives price, stock, rarity and the market |
| **Who refuses to touch it at all?** | `cultureMask` — the cultures that will not trade it | `data/goods.json`, one array per good | `public.goods.culture_mask`, read by `cmd.do_buy`, `cmd.do_sell`, arrival, and the market's `available` flag |
| **How MANY goods may a port carry?** | `public.roster_target_count(tier, authored, draw)` | migration `0058` — untouched, still the only place the numbers 10 / 4-8 / 4 exist | `0062` calls it; it does not retype it |
| **Are all four in agreement?** | `scripts/db/world-guard.mjs`, run on every `npm run db:apply` | — | fails the build the moment the database and `data/*.json` disagree, in either direction |

### The law that ties them together

> **Every single (port, good) offer in the world is either NATIVE — the port's region appears in the
> good's `origin` — or a NAMED ENTREPOT — the port appears in the good's `entrepots`. There is no
> third case.**

Migration `0062` asserts that in the transaction that applies it, over all 1,288 offers, and refuses
to land if even one falls through. Measured on the world this file describes:

| | |
|---|---:|
| offers in the world | **1,288** |
| **native** — the port's own coast grew it | **1,241** (96.4%) |
| **entrepot** — a re-export, hand-written and defended in §D | **47** (3.6%) |
| neither | **0** |

### Why the entrepot list is hand-written, and why that IS the guard

The 47 exceptions are not a loophole; they are the age of sail. Lisbon sold pepper and grew none.
Seville sold Peruvian silver. Calais, by statute, was the only place English wool could be landed for
the continent. A model that forbade all of that would be a worse model, not a stricter one.

But every one of the 47 had to be **typed by a person into that good's `entrepots` list and defended
by name in §D of this file.** That is the whole guard, and it is aimed at exactly the failure this
file exists to repair: **a seeded hash can invent an offer, but it cannot write an entrepot row.**

### The two classes the owner named, kept apart on purpose

The instruction names both in one sentence — *rice, "a main food in eastern asia and india"*, against
*haggis, "only in scotland, unique"* — and the design has to express the difference rather than
flatten it. `origin`'s **length** is what does that:

| | count | example |
|---|---:|---|
| goods from **exactly one region** | **83** of 243 | Banda nutmeg, Chian mastic, Jamaica allspice, Prussian amber, Joseon tiger skins |
| goods sold at **exactly one port on earth** | **54** of 243 | mace at Banda Neira, narwhal horn at Nuuk, Mecca balsam at Jeddah, gamboge at Ayutthaya |
| goods from **five regions or more** | **38** of 243 | salt (21 regions), hides (20), timber (17), dried fish (16), wheat (15) |
| **rice**, the owner's own example | **8 regions** | Bengal, Siam and Java, Kanara, Japan, Korea, the China coast — and the two the research added: Valencia, and the Chamorro rice of Guam |

Rice is broad and is written broad. Nutmeg is singular and is written singular. Neither was rounded
towards the other.

---

## A. THE 243 GOODS, FILED BY WHERE THEY COME FROM

Grouped by **region of origin**, because that is the question the owner asked — *where is this
from?* — and because a category grouping (spice / textile / metal) would scatter the Moluccas
across five headings and put Banda nutmeg beside Andalusian saffron. A good that comes from more
than one region appears under **each** of them, with the full origin list in its row, so you can
read a region top to bottom and see everything that coast makes. The 38 goods whose origin spans
five regions or more are pulled out into §B instead; they belong to no single place and filing
them under twenty headings would be noise.

`ports` names every harbour that offers the good today. **bold** = the port is outside the
good's origin regions and holds it as a named entrepot (§D).

### Iberia

*11 ports — 4 capital, 4 mid, 3 small. 16 goods have their origin here.*

| good | origin | ports that sell it | why here |
|---|---|---|---|
| `saffron` Saffron | Arabia & the Gulf · Iberia | Bandar Abbas, Barcelona, Valencia | La Mancha and Persian crocus threads, picked by hand; the dearest spice in the world by weight. |
| `anise` Aniseed | Adriatic & Ionian · Iberia · Western Mediterranean | Malaga, Naples | Spanish and Apulian aniseed for comfits, cordials and the still-house. |
| `coriander` Coriander | Iberia · Levant & Egypt | Beirut, Valencia | Levantine and Spanish coriander seed, ballast-cheap and asked for everywhere. |
| `quicksilver` Quicksilver | Adriatic & Ionian · Iberia · Pacific Americas | Callao, Seville | Mercury of Almaden, Idria and Huancavelica; without it no silver amalgam, so crowns fought over every flask. |
| `glassware` Glassware | Adriatic & Ionian · Iberia | Barcelona, Venice | Murano cristallo and mirrors, and the fine glass of Barcelona; Venice guarded the craft as a state secret. |
| `coral` Coral | Iberia · Maghreb · Western Mediterranean | Algiers, Barcelona, Cagliari, Genoa, Livorno, Marseille, Tunis | Red coral fished off Sardinia, Corsica and the Barbary coast, worked at Genoa and Livorno and sold into India. |
| `silver-plate` Silverware & Plate | Baltic & the Hanse · Iberia | Cadiz, Hamburg, Seville | Augsburg workshops and Seville shops turned bullion into cups and salvers that travelled as gifts of state. |
| `majolica` Majolica | Iberia · Western Mediterranean | Livorno, Valencia | Tin-glazed ware of Montelupo and Manises, the bright pottery of every Mediterranean table. |
| `sea-charts` Sea Charts & Globes | France & the Low Countries · Iberia | Amsterdam | Waggoners, portolans and globes from the Low Countries presses; a good rutter was worth a cargo. |
| `sword-blades` Sword Blades | Baltic & the Hanse · Iberia · Japan & the Ryukyus | Cadiz, Hamburg, Sakai, Tokyo | Japanese blades shipped to China by the thousand, with Toledo and Solingen steel for the western trade. |
| `figs` Figs | Aegean, Anatolia & Black Sea · Iberia · Maghreb · Western Mediterranean | Algiers, Izmir, Malaga | Smyrna and Malaga figs, drummed and shipped north for winter tables. |
| `citrus` Lemons & Oranges | Adriatic & Ionian · Iberia · Maghreb · Western Mediterranean | Algiers, Cadiz, Malaga, Messina, Palermo, Seville, Valencia | Sicilian and Valencian citrus; ship captains bought them without knowing why they kept crews standing. |
| `almonds` Almonds | Adriatic & Ionian · Iberia · Maghreb · Western Mediterranean | Agadir, Barcelona, Malaga, Marseille, Naples | Andalusian, Apulian and Sous almonds, the marzipan and banquet nut of Europe. |
| `salted-tuna` Salt Tuna | Iberia · Maghreb · Western Mediterranean | Cadiz, Gibraltar, Palermo | The almadraba tunny of the straits, netted at the season and salted down by the thousand. |
| `cork` Cork | **only Iberia** | Lisbon, Porto | Stripped oak bark of Portugal: floats, soles and the stoppers in every bottle. |
| `soap` Soap | Adriatic & Ionian · Iberia · Levant & Egypt · Western Mediterranean | Beirut, Marseille, Seville, Tripoli, Venice | Olive-oil soap of Marseille, Aleppo and Venice, boxed and shipped as a finished ware. |

### Atlantic Isles

*6 ports — 0 capital, 3 mid, 3 small. 3 goods have their origin here.*

| good | origin | ports that sell it | why here |
|---|---|---|---|
| `molasses` Molasses | Atlantic Isles · Caribbean & the Spanish Main · South America, Atlantic Coast | Bridgetown, Recife, Salvador | The mill syrup left when sugar is struck; sold cheap, and the seed of every rum still. |
| `woad` Woad | Atlantic Isles · France & the Low Countries · Western Mediterranean | Bordeaux, Ponta Delgada | The blue dye balls of Toulouse and the Azores, fighting a losing war against Indian indigo. |
| `orchil` Orchil | Atlantic Isles · Maghreb | Cidade Velha, Las Palmas | Purple lichen dye scraped from Atlantic island rocks; the reason crowns quarrelled over bare cliffs. |

### British Isles

*8 ports — 1 capital, 4 mid, 3 small. 14 goods have their origin here.*

| good | origin | ports that sell it | why here |
|---|---|---|---|
| `linen` Linen | Baltic & the Hanse · British Isles · France & the Low Countries · Levant & Egypt | Alexandria, Antwerp, Bordeaux, Bruges, Calais, Dublin, Hamburg, La Rochelle … (12 in all) | Brittany, Flanders, Silesia and Egypt; the ordinary cloth of shirts, sails and paper rag. |
| `stockings` Knitted Stockings | British Isles · France & the Low Countries | London, Saint-Malo | Jersey and English worsted stockings, knitted by the thousand dozen for every market in Europe. |
| `felt-hats` Felt Hats | British Isles · France & the Low Countries | Le Havre, London | Beaver felt hats of London and Normandy — the reason the beaver pelts crossed the Atlantic at all. |
| `tin` Tin | British Isles · Eastern India, Ceylon & Burma · Southeast Asia | London, Malacca, Myeik, Plymouth | Cornwall in Europe, and the Malay peninsula and Bangka in Asia, where tin ingots served as money. |
| `lead` Lead | Baltic & the Hanse · British Isles | Bristol, Kingston upon Hull | Derbyshire and Polish lead in pigs and rolls, for shot, roofs and the assay office. |
| `cannon` Cannon | Baltic & the Hanse · British Isles · Scandinavia & the Arctic | London, Stockholm | Wealden cast-iron guns and Swedish pieces; a strategic export every state tried and failed to embargo. |
| `pewter` Pewterware | **only British Isles** | Bristol, London | English pewter plates and flagons, the everyday shine of every tavern from Danzig to Barbados. |
| `smallwares` Nuremberg Smallwares | Baltic & the Hanse · British Isles · France & the Low Countries | Hamburg, Lubeck | Knives, needles, mirrors and bells by the barrel — the small iron goods every factor bartered. |
| `gunpowder` Gunpowder | Adriatic & Ionian · British Isles · France & the Low Countries | Amsterdam, London | Corned powder from the Amsterdam, London and Venetian mills; every fort and fleet ran dry without it. |
| `herring` Herring | Baltic & the Hanse · British Isles · France & the Low Countries · Scandinavia & the Arctic | Amsterdam, Bergen, Calais, Copenhagen, Hoorn, Kingston upon Hull, Leith, Lubeck … (9 in all) | The North Sea and Baltic fishery, gutted and barrelled at sea by the Dutch buss fleets. |
| `barley` Barley | Baltic & the Hanse · British Isles · Scandinavia & the Arctic | Copenhagen, Leith | Malting barley of the northern firths and sounds; the brewhouse bought all of it. |
| `beer` Beer | Baltic & the Hanse · British Isles · France & the Low Countries | Copenhagen, Gdansk, Hamburg, London, Lubeck, Rotterdam | Hamburg and Danzig hopped beer and English ale, safer than water and shipped by the hundred barrels. |
| `butter` Butter | Baltic & the Hanse · British Isles · France & the Low Countries | Copenhagen, Cork, Dublin, Saint-Malo | Irish and Dutch salted butter in firkins, victualling fleets and plantations alike. |
| `coal` Sea Coal | **only British Isles** | Bristol, Kingston upon Hull, Leith, London | Tyne and Forth coal carried coastwise and across the North Sea; the fuel of salt pans and smithies. |

### France & the Low Countries

*12 ports — 3 capital, 4 mid, 5 small. 25 goods have their origin here.*

| good | origin | ports that sell it | why here |
|---|---|---|---|
| `linen` Linen | Baltic & the Hanse · British Isles · France & the Low Countries · Levant & Egypt | Alexandria, Antwerp, Bordeaux, Bruges, Calais, Dublin, Hamburg, La Rochelle … (12 in all) | Brittany, Flanders, Silesia and Egypt; the ordinary cloth of shirts, sails and paper rag. |
| `says-serges` Says & Serges | **only France & the Low Countries** | Antwerp, Middelburg | The light "new draperies" of Flanders and Zeeland that undercut old broadcloth in every warm market. |
| `lace` Lace | Adriatic & Ionian · France & the Low Countries | Bruges, Venice | Venetian needle lace and Flemish bobbin lace, worth more than the linen it trimmed. |
| `tapestries` Tapestries | **only France & the Low Countries** | Antwerp | Brussels and Oudenaarde hangings sold through Antwerp; a single suite could furnish a palace. |
| `stockings` Knitted Stockings | British Isles · France & the Low Countries | London, Saint-Malo | Jersey and English worsted stockings, knitted by the thousand dozen for every market in Europe. |
| `felt-hats` Felt Hats | British Isles · France & the Low Countries | Le Havre, London | Beaver felt hats of London and Normandy — the reason the beaver pelts crossed the Atlantic at all. |
| `firearms` Muskets | France & the Low Countries · Japan & the Ryukyus | Antwerp, Sakai | Sakai matchlocks and Low Countries muskets; a chest of them opened doors on every coast. |
| `brassware` Brassware & Manillas | Baltic & the Hanse · France & the Low Countries | Hamburg | Nuremberg and Aachen basins, kettles and manilla bracelets — the currency goods of the Guinea trade. |
| `smallwares` Nuremberg Smallwares | Baltic & the Hanse · British Isles · France & the Low Countries | Hamburg, Lubeck | Knives, needles, mirrors and bells by the barrel — the small iron goods every factor bartered. |
| `gunpowder` Gunpowder | Adriatic & Ionian · British Isles · France & the Low Countries | Amsterdam, London | Corned powder from the Amsterdam, London and Venetian mills; every fort and fleet ran dry without it. |
| `books` Printed Books | Adriatic & Ionian · France & the Low Countries | Antwerp, Venice | The presses of Venice and the Plantin house at Antwerp; bales of books moved like any other cloth. |
| `clocks` Clocks & Instruments | Baltic & the Hanse · France & the Low Countries | Hamburg | Nuremberg and Augsburg clockwork and Dutch instruments; the Jesuits opened Peking with such gifts. |
| `paintings` Paintings | **only France & the Low Countries** | Antwerp | Antwerp's picture market sold devotional panels and landscapes by the crate, sight unseen. |
| `stoneware` Rhenish Stoneware | Baltic & the Hanse · France & the Low Countries | Hamburg, Rotterdam | Salt-glazed jugs and bellarmines of the Rhine kilns, shipped down to every North Sea harbour. |
| `glass-beads` Trade Beads | Adriatic & Ionian · France & the Low Countries | Amsterdam, Venice | Murano conterie and Dutch beads by the barrel, the small change of the Guinea and fur trades. |
| `sea-charts` Sea Charts & Globes | France & the Low Countries · Iberia | Amsterdam | Waggoners, portolans and globes from the Low Countries presses; a good rutter was worth a cargo. |
| `herring` Herring | Baltic & the Hanse · British Isles · France & the Low Countries · Scandinavia & the Arctic | Amsterdam, Bergen, Calais, Copenhagen, Hoorn, Kingston upon Hull, Leith, Lubeck … (9 in all) | The North Sea and Baltic fishery, gutted and barrelled at sea by the Dutch buss fleets. |
| `beer` Beer | Baltic & the Hanse · British Isles · France & the Low Countries | Copenhagen, Gdansk, Hamburg, London, Lubeck, Rotterdam | Hamburg and Danzig hopped beer and English ale, safer than water and shipped by the hundred barrels. |
| `brandy` Brandy | **only France & the Low Countries** | Bordeaux, La Rochelle, Nantes | Burnt wine of the Charente and Gironde, distilled so it could survive any voyage and improve for it. |
| `butter` Butter | Baltic & the Hanse · British Isles · France & the Low Countries | Copenhagen, Cork, Dublin, Saint-Malo | Irish and Dutch salted butter in firkins, victualling fleets and plantations alike. |
| `woad` Woad | Atlantic Isles · France & the Low Countries · Western Mediterranean | Bordeaux, Ponta Delgada | The blue dye balls of Toulouse and the Azores, fighting a losing war against Indian indigo. |
| `madder` Madder | Aegean, Anatolia & Black Sea · France & the Low Countries | Izmir, Middelburg | The red root of Anatolia and Zeeland, the everyday scarlet of the cloth trade. |
| `hops` Hops | Baltic & the Hanse · France & the Low Countries | Lubeck | The bitter cone that turned ale into beer; grown in Brabant and the Elbe country, sold by the sack. |
| `vermilion` Vermilion | China Coast · France & the Low Countries | Amsterdam, Guangzhou | The scarlet mercury pigment, made in China and Holland and sold by the pound to painters and printers. |
| `rosin` Rosin & Turpentine | Baltic & the Hanse · France & the Low Countries · Scandinavia & the Arctic | Bordeaux, Gdansk | Pine gum of the Landes and the Baltic forests, for caulkers, coopers and fiddlers alike. |

### Baltic & the Hanse

*10 ports — 4 capital, 3 mid, 3 small. 25 goods have their origin here.*

| good | origin | ports that sell it | why here |
|---|---|---|---|
| `linen` Linen | Baltic & the Hanse · British Isles · France & the Low Countries · Levant & Egypt | Alexandria, Antwerp, Bordeaux, Bruges, Calais, Dublin, Hamburg, La Rochelle … (12 in all) | Brittany, Flanders, Silesia and Egypt; the ordinary cloth of shirts, sails and paper rag. |
| `fustian` Fustian | Baltic & the Hanse · Western Mediterranean | Genoa | The cotton-linen workhorse cloth of Milan and Augsburg, shipped out through Genoa and the Elbe. |
| `lead` Lead | Baltic & the Hanse · British Isles | Bristol, Kingston upon Hull | Derbyshire and Polish lead in pigs and rolls, for shot, roofs and the assay office. |
| `cannon` Cannon | Baltic & the Hanse · British Isles · Scandinavia & the Arctic | London, Stockholm | Wealden cast-iron guns and Swedish pieces; a strategic export every state tried and failed to embargo. |
| `brassware` Brassware & Manillas | Baltic & the Hanse · France & the Low Countries | Hamburg | Nuremberg and Aachen basins, kettles and manilla bracelets — the currency goods of the Guinea trade. |
| `smallwares` Nuremberg Smallwares | Baltic & the Hanse · British Isles · France & the Low Countries | Hamburg, Lubeck | Knives, needles, mirrors and bells by the barrel — the small iron goods every factor bartered. |
| `amber` Amber | **only Baltic & the Hanse** | Copenhagen, Gdansk, Kaliningrad | The Samland coast of Prussia held a ducal monopoly; worked at Konigsberg and Gdansk, sold as far as China. |
| `clocks` Clocks & Instruments | Baltic & the Hanse · France & the Low Countries | Hamburg | Nuremberg and Augsburg clockwork and Dutch instruments; the Jesuits opened Peking with such gifts. |
| `silver-plate` Silverware & Plate | Baltic & the Hanse · Iberia | Cadiz, Hamburg, Seville | Augsburg workshops and Seville shops turned bullion into cups and salvers that travelled as gifts of state. |
| `stoneware` Rhenish Stoneware | Baltic & the Hanse · France & the Low Countries | Hamburg, Rotterdam | Salt-glazed jugs and bellarmines of the Rhine kilns, shipped down to every North Sea harbour. |
| `sword-blades` Sword Blades | Baltic & the Hanse · Iberia · Japan & the Ryukyus | Cadiz, Hamburg, Sakai, Tokyo | Japanese blades shipped to China by the thousand, with Toledo and Solingen steel for the western trade. |
| `herring` Herring | Baltic & the Hanse · British Isles · France & the Low Countries · Scandinavia & the Arctic | Amsterdam, Bergen, Calais, Copenhagen, Hoorn, Kingston upon Hull, Leith, Lubeck … (9 in all) | The North Sea and Baltic fishery, gutted and barrelled at sea by the Dutch buss fleets. |
| `rye` Rye | **only Baltic & the Hanse** | Copenhagen, Gdansk, Kaliningrad, Lubeck, Riga, Tallinn | The black bread grain of the Baltic, floated down the Vistula and sold by the last; Amsterdam lived on it. |
| `barley` Barley | Baltic & the Hanse · British Isles · Scandinavia & the Arctic | Copenhagen, Leith | Malting barley of the northern firths and sounds; the brewhouse bought all of it. |
| `beer` Beer | Baltic & the Hanse · British Isles · France & the Low Countries | Copenhagen, Gdansk, Hamburg, London, Lubeck, Rotterdam | Hamburg and Danzig hopped beer and English ale, safer than water and shipped by the hundred barrels. |
| `butter` Butter | Baltic & the Hanse · British Isles · France & the Low Countries | Copenhagen, Cork, Dublin, Saint-Malo | Irish and Dutch salted butter in firkins, victualling fleets and plantations alike. |
| `honey` Honey | Aegean, Anatolia & Black Sea · Baltic & the Hanse · Maghreb · Western Mediterranean | Heraklion, Kaliningrad, Safi, Tangier, Valletta | Lithuanian forest honey and Barbary honey, the sweetener of everyone the sugar ships passed by. |
| `potash` Potash | Baltic & the Hanse · Scandinavia & the Arctic | Arkhangelsk, Gdansk, Riga | Forest ash of Poland and Muscovy, burned by the ton for the soap, glass and dye trades. |
| `isinglass` Isinglass | Aegean, Anatolia & Black Sea · Baltic & the Hanse · Scandinavia & the Arctic | Arkhangelsk | Sturgeon bladder glue of the Volga fisheries, the finest clarifier and adhesive money could buy. |
| `russia-leather` Russia Leather | Aegean, Anatolia & Black Sea · Baltic & the Hanse · Scandinavia & the Arctic | Arkhangelsk, Tallinn | Birch-oil dressed yuft, red and waterproof; bookbinders and saddlers knew it by smell alone. |
| `linseed` Linseed | **only Baltic & the Hanse** | Kaliningrad, Riga | Baltic flax seed, crushed for the oil that binds every painter’s colour and printer’s ink. |
| `hops` Hops | Baltic & the Hanse · France & the Low Countries | Lubeck | The bitter cone that turned ale into beer; grown in Brabant and the Elbe country, sold by the sack. |
| `naval-timber` Masts & Spars | Baltic & the Hanse · North America, Atlantic Coast · Scandinavia & the Arctic · Western Mediterranean | Boston, Gdansk, New York, **Portsmouth**, Quebec City, Riga, Stockholm, Toulon | Riga and Norwegian mast pine, and later New England white pine; a strategic good every navy competed for. |
| `tar` Tar & Pitch | Baltic & the Hanse · Scandinavia & the Arctic | Bergen, Gdansk, Stockholm, Turku | Finnish and Swedish pine tar through Stockholm and Turku; without it no hull or rigging stayed sound. |
| `rosin` Rosin & Turpentine | Baltic & the Hanse · France & the Low Countries · Scandinavia & the Arctic | Bordeaux, Gdansk | Pine gum of the Landes and the Baltic forests, for caulkers, coopers and fiddlers alike. |

### Scandinavia & the Arctic

*8 ports — 0 capital, 2 mid, 6 small. 16 goods have their origin here.*

| good | origin | ports that sell it | why here |
|---|---|---|---|
| `cannon` Cannon | Baltic & the Hanse · British Isles · Scandinavia & the Arctic | London, Stockholm | Wealden cast-iron guns and Swedish pieces; a strategic export every state tried and failed to embargo. |
| `gyrfalcons` Gyrfalcons | **only Scandinavia & the Arctic** | Reykjavik | White Iceland falcons, a trade so royal the Danish crown kept it to itself. |
| `herring` Herring | Baltic & the Hanse · British Isles · France & the Low Countries · Scandinavia & the Arctic | Amsterdam, Bergen, Calais, Copenhagen, Hoorn, Kingston upon Hull, Leith, Lubeck … (9 in all) | The North Sea and Baltic fishery, gutted and barrelled at sea by the Dutch buss fleets. |
| `barley` Barley | Baltic & the Hanse · British Isles · Scandinavia & the Arctic | Copenhagen, Leith | Malting barley of the northern firths and sounds; the brewhouse bought all of it. |
| `caviar` Caviar | Aegean, Anatolia & Black Sea · Scandinavia & the Arctic | Arkhangelsk, Feodosia | Pressed sturgeon roe of the Black Sea and Volga, barrelled for Italy since Genoese Kaffa. |
| `sulphur` Sulphur | Japan & the Ryukyus · Scandinavia & the Arctic · Western Mediterranean | Kagoshima, Nagasaki, Naha, Reykjavik | Sicily, Iceland and the Japanese and Ryukyuan volcanoes; the other half of gunpowder. |
| `potash` Potash | Baltic & the Hanse · Scandinavia & the Arctic | Arkhangelsk, Gdansk, Riga | Forest ash of Poland and Muscovy, burned by the ton for the soap, glass and dye trades. |
| `sealskins` Sealskins | North America, Atlantic Coast · Oceania & the Far Pacific · Scandinavia & the Arctic | Nuuk, Sydney, Torshavn | Oiled skins of the northern hunt, waterproof before anything else was. |
| `walrus-ivory` Walrus Ivory | **only Scandinavia & the Arctic** | Arkhangelsk, Longyearbyen, Nuuk | Morse teeth of the White Sea and Spitsbergen hunts, carved where elephant ivory never reached. |
| `narwhal-horn` Narwhal Horn | **only Scandinavia & the Arctic** | Nuuk | The spiral tusk sold in Europe as unicorn horn, proof against poison and priced like a province. |
| `eiderdown` Eiderdown | **only Scandinavia & the Arctic** | Reykjavik, Torshavn | Nest down of the eider duck, gathered on the skerries; the warmest thing the north ever sold. |
| `isinglass` Isinglass | Aegean, Anatolia & Black Sea · Baltic & the Hanse · Scandinavia & the Arctic | Arkhangelsk | Sturgeon bladder glue of the Volga fisheries, the finest clarifier and adhesive money could buy. |
| `russia-leather` Russia Leather | Aegean, Anatolia & Black Sea · Baltic & the Hanse · Scandinavia & the Arctic | Arkhangelsk, Tallinn | Birch-oil dressed yuft, red and waterproof; bookbinders and saddlers knew it by smell alone. |
| `naval-timber` Masts & Spars | Baltic & the Hanse · North America, Atlantic Coast · Scandinavia & the Arctic · Western Mediterranean | Boston, Gdansk, New York, **Portsmouth**, Quebec City, Riga, Stockholm, Toulon | Riga and Norwegian mast pine, and later New England white pine; a strategic good every navy competed for. |
| `tar` Tar & Pitch | Baltic & the Hanse · Scandinavia & the Arctic | Bergen, Gdansk, Stockholm, Turku | Finnish and Swedish pine tar through Stockholm and Turku; without it no hull or rigging stayed sound. |
| `rosin` Rosin & Turpentine | Baltic & the Hanse · France & the Low Countries · Scandinavia & the Arctic | Bordeaux, Gdansk | Pine gum of the Landes and the Baltic forests, for caulkers, coopers and fiddlers alike. |

### Western Mediterranean

*10 ports — 2 capital, 4 mid, 4 small. 19 goods have their origin here.*

| good | origin | ports that sell it | why here |
|---|---|---|---|
| `anise` Aniseed | Adriatic & Ionian · Iberia · Western Mediterranean | Malaga, Naples | Spanish and Apulian aniseed for comfits, cordials and the still-house. |
| `velvet` Velvet | Adriatic & Ionian · Western Mediterranean | Genoa, Venice | Genoese and Venetian silk velvet, the cloth of cardinals and council chambers. |
| `fustian` Fustian | Baltic & the Hanse · Western Mediterranean | Genoa | The cotton-linen workhorse cloth of Milan and Augsburg, shipped out through Genoa and the Elbe. |
| `gold-thread` Gold Thread | Levant & Egypt · Western Mediterranean | Famagusta, Genoa | Gilt-silver thread of Genoa and Cyprus for brocades and church work, sold by the spool like treasure. |
| `armour` Armour | **only Western Mediterranean** | Genoa | Milanese corslets and morions shipped through Genoa; a fading trade, but princes still paid. |
| `coral` Coral | Iberia · Maghreb · Western Mediterranean | Algiers, Barcelona, Cagliari, Genoa, Livorno, Marseille, Tunis | Red coral fished off Sardinia, Corsica and the Barbary coast, worked at Genoa and Livorno and sold into India. |
| `majolica` Majolica | Iberia · Western Mediterranean | Livorno, Valencia | Tin-glazed ware of Montelupo and Manises, the bright pottery of every Mediterranean table. |
| `honey` Honey | Aegean, Anatolia & Black Sea · Baltic & the Hanse · Maghreb · Western Mediterranean | Heraklion, Kaliningrad, Safi, Tangier, Valletta | Lithuanian forest honey and Barbary honey, the sweetener of everyone the sugar ships passed by. |
| `figs` Figs | Aegean, Anatolia & Black Sea · Iberia · Maghreb · Western Mediterranean | Algiers, Izmir, Malaga | Smyrna and Malaga figs, drummed and shipped north for winter tables. |
| `citrus` Lemons & Oranges | Adriatic & Ionian · Iberia · Maghreb · Western Mediterranean | Algiers, Cadiz, Malaga, Messina, Palermo, Seville, Valencia | Sicilian and Valencian citrus; ship captains bought them without knowing why they kept crews standing. |
| `almonds` Almonds | Adriatic & Ionian · Iberia · Maghreb · Western Mediterranean | Agadir, Barcelona, Malaga, Marseille, Naples | Andalusian, Apulian and Sous almonds, the marzipan and banquet nut of Europe. |
| `salted-tuna` Salt Tuna | Iberia · Maghreb · Western Mediterranean | Cadiz, Gibraltar, Palermo | The almadraba tunny of the straits, netted at the season and salted down by the thousand. |
| `alum` Alum | Adriatic & Ionian · Aegean, Anatolia & Black Sea · Western Mediterranean | **Bruges**, Genoa, Istanbul, Livorno | The papal alum of Tolfa and the Anatolian alum of the old Phocaea works: the mordant that fixed dye to cloth. |
| `sulphur` Sulphur | Japan & the Ryukyus · Scandinavia & the Arctic · Western Mediterranean | Kagoshima, Nagasaki, Naha, Reykjavik | Sicily, Iceland and the Japanese and Ryukyuan volcanoes; the other half of gunpowder. |
| `woad` Woad | Atlantic Isles · France & the Low Countries · Western Mediterranean | Bordeaux, Ponta Delgada | The blue dye balls of Toulouse and the Azores, fighting a losing war against Indian indigo. |
| `marble` Marble | Adriatic & Ionian · Aegean, Anatolia & Black Sea · Western Mediterranean | Genoa, Livorno | Carrara blocks and sawn slabs, shipped from the Ligurian shore to palaces and altars abroad. |
| `verdigris` Verdigris | **only Western Mediterranean** | Marseille | The green copper pigment of Montpellier, raised on wine lees and sold by the barrel. |
| `soap` Soap | Adriatic & Ionian · Iberia · Levant & Egypt · Western Mediterranean | Beirut, Marseille, Seville, Tripoli, Venice | Olive-oil soap of Marseille, Aleppo and Venice, boxed and shipped as a finished ware. |
| `naval-timber` Masts & Spars | Baltic & the Hanse · North America, Atlantic Coast · Scandinavia & the Arctic · Western Mediterranean | Boston, Gdansk, New York, **Portsmouth**, Quebec City, Riga, Stockholm, Toulon | Riga and Norwegian mast pine, and later New England white pine; a strategic good every navy competed for. |

### Adriatic & Ionian

*7 ports — 1 capital, 1 mid, 5 small. 15 goods have their origin here.*

| good | origin | ports that sell it | why here |
|---|---|---|---|
| `anise` Aniseed | Adriatic & Ionian · Iberia · Western Mediterranean | Malaga, Naples | Spanish and Apulian aniseed for comfits, cordials and the still-house. |
| `velvet` Velvet | Adriatic & Ionian · Western Mediterranean | Genoa, Venice | Genoese and Venetian silk velvet, the cloth of cardinals and council chambers. |
| `lace` Lace | Adriatic & Ionian · France & the Low Countries | Bruges, Venice | Venetian needle lace and Flemish bobbin lace, worth more than the linen it trimmed. |
| `quicksilver` Quicksilver | Adriatic & Ionian · Iberia · Pacific Americas | Callao, Seville | Mercury of Almaden, Idria and Huancavelica; without it no silver amalgam, so crowns fought over every flask. |
| `gunpowder` Gunpowder | Adriatic & Ionian · British Isles · France & the Low Countries | Amsterdam, London | Corned powder from the Amsterdam, London and Venetian mills; every fort and fleet ran dry without it. |
| `glassware` Glassware | Adriatic & Ionian · Iberia | Barcelona, Venice | Murano cristallo and mirrors, and the fine glass of Barcelona; Venice guarded the craft as a state secret. |
| `books` Printed Books | Adriatic & Ionian · France & the Low Countries | Antwerp, Venice | The presses of Venice and the Plantin house at Antwerp; bales of books moved like any other cloth. |
| `glass-beads` Trade Beads | Adriatic & Ionian · France & the Low Countries | Amsterdam, Venice | Murano conterie and Dutch beads by the barrel, the small change of the Guinea and fur trades. |
| `theriac` Venice Treacle | **only Adriatic & Ionian** | Venice | The sixty-ingredient cure-all compounded in public in Venice and faked everywhere else. |
| `citrus` Lemons & Oranges | Adriatic & Ionian · Iberia · Maghreb · Western Mediterranean | Algiers, Cadiz, Malaga, Messina, Palermo, Seville, Valencia | Sicilian and Valencian citrus; ship captains bought them without knowing why they kept crews standing. |
| `almonds` Almonds | Adriatic & Ionian · Iberia · Maghreb · Western Mediterranean | Agadir, Barcelona, Malaga, Marseille, Naples | Andalusian, Apulian and Sous almonds, the marzipan and banquet nut of Europe. |
| `alum` Alum | Adriatic & Ionian · Aegean, Anatolia & Black Sea · Western Mediterranean | **Bruges**, Genoa, Istanbul, Livorno | The papal alum of Tolfa and the Anatolian alum of the old Phocaea works: the mordant that fixed dye to cloth. |
| `sponges` Sponges | Adriatic & Ionian · Aegean, Anatolia & Black Sea | Antalya, Rhodes | Diver-gathered sponges of the Aegean and Lycian coasts, sold from surgeons’ shops to stables. |
| `marble` Marble | Adriatic & Ionian · Aegean, Anatolia & Black Sea · Western Mediterranean | Genoa, Livorno | Carrara blocks and sawn slabs, shipped from the Ligurian shore to palaces and altars abroad. |
| `soap` Soap | Adriatic & Ionian · Iberia · Levant & Egypt · Western Mediterranean | Beirut, Marseille, Seville, Tripoli, Venice | Olive-oil soap of Marseille, Aleppo and Venice, boxed and shipped as a finished ware. |

### Aegean, Anatolia & Black Sea

*9 ports — 1 capital, 3 mid, 5 small. 14 goods have their origin here.*

| good | origin | ports that sell it | why here |
|---|---|---|---|
| `carpets` Carpets | Aegean, Anatolia & Black Sea · Arabia & the Gulf | Antalya, Bandar Abbas, Basra, Istanbul, Izmir, Trabzon | Safavid Persia and Ottoman Anatolia; carried west overland to Aleppo and by sea from Bandar Abbas. |
| `camlets` Camlets | **only Aegean, Anatolia & Black Sea** | Istanbul, Izmir | The watered mohair cloth of Angora goats, carried down to Smyrna for the Levant Company ships. |
| `mastic` Mastic | **only Aegean, Anatolia & Black Sea** | Izmir | The resin tears of Chios, chewed in the harems and guarded by the Ottomans on pain of death. |
| `honey` Honey | Aegean, Anatolia & Black Sea · Baltic & the Hanse · Maghreb · Western Mediterranean | Heraklion, Kaliningrad, Safi, Tangier, Valletta | Lithuanian forest honey and Barbary honey, the sweetener of everyone the sugar ships passed by. |
| `figs` Figs | Aegean, Anatolia & Black Sea · Iberia · Maghreb · Western Mediterranean | Algiers, Izmir, Malaga | Smyrna and Malaga figs, drummed and shipped north for winter tables. |
| `caviar` Caviar | Aegean, Anatolia & Black Sea · Scandinavia & the Arctic | Arkhangelsk, Feodosia | Pressed sturgeon roe of the Black Sea and Volga, barrelled for Italy since Genoese Kaffa. |
| `hazelnuts` Hazelnuts | **only Aegean, Anatolia & Black Sea** | Trabzon | The filbert groves of the Pontic shore behind Trebizond, shipped west since antiquity. |
| `alum` Alum | Adriatic & Ionian · Aegean, Anatolia & Black Sea · Western Mediterranean | **Bruges**, Genoa, Istanbul, Livorno | The papal alum of Tolfa and the Anatolian alum of the old Phocaea works: the mordant that fixed dye to cloth. |
| `madder` Madder | Aegean, Anatolia & Black Sea · France & the Low Countries | Izmir, Middelburg | The red root of Anatolia and Zeeland, the everyday scarlet of the cloth trade. |
| `gallnuts` Gallnuts | Aegean, Anatolia & Black Sea · Arabia & the Gulf · Levant & Egypt | Basra, Tripoli | Aleppo and Kurdish oak galls, the heart of every good black ink and dye. |
| `sponges` Sponges | Adriatic & Ionian · Aegean, Anatolia & Black Sea | Antalya, Rhodes | Diver-gathered sponges of the Aegean and Lycian coasts, sold from surgeons’ shops to stables. |
| `marble` Marble | Adriatic & Ionian · Aegean, Anatolia & Black Sea · Western Mediterranean | Genoa, Livorno | Carrara blocks and sawn slabs, shipped from the Ligurian shore to palaces and altars abroad. |
| `isinglass` Isinglass | Aegean, Anatolia & Black Sea · Baltic & the Hanse · Scandinavia & the Arctic | Arkhangelsk | Sturgeon bladder glue of the Volga fisheries, the finest clarifier and adhesive money could buy. |
| `russia-leather` Russia Leather | Aegean, Anatolia & Black Sea · Baltic & the Hanse · Scandinavia & the Arctic | Arkhangelsk, Tallinn | Birch-oil dressed yuft, red and waterproof; bookbinders and saddlers knew it by smell alone. |

### Levant & Egypt

*4 ports — 1 capital, 1 mid, 2 small. 14 goods have their origin here.*

| good | origin | ports that sell it | why here |
|---|---|---|---|
| `cumin` Cumin | Levant & Egypt · Western India | Alexandria, Khambhat | Egyptian and Gujarati cumin seed, a workhorse spice sold in sacks rather than caskets. |
| `coriander` Coriander | Iberia · Levant & Egypt | Beirut, Valencia | Levantine and Spanish coriander seed, ballast-cheap and asked for everywhere. |
| `linen` Linen | Baltic & the Hanse · British Isles · France & the Low Countries · Levant & Egypt | Alexandria, Antwerp, Bordeaux, Bruges, Calais, Dublin, Hamburg, La Rochelle … (12 in all) | Brittany, Flanders, Silesia and Egypt; the ordinary cloth of shirts, sails and paper rag. |
| `gold-thread` Gold Thread | Levant & Egypt · Western Mediterranean | Famagusta, Genoa | Gilt-silver thread of Genoa and Cyprus for brocades and church work, sold by the spool like treasure. |
| `rosewater` Rosewater | Arabia & the Gulf · Levant & Egypt | Bandar Abbas, Beirut | Distilled roses of Shiraz and Damascus, shipped in glass carboys packed in straw. |
| `dates` Dates | Arabia & the Gulf · Levant & Egypt · Maghreb | Bandar Abbas, Basra, Manama, Muscat | Basra and Oman dates pressed into baskets, the cheap sweet cargo of every Gulf and Barbary sailing. |
| `sesame-oil` Sesame Oil | Arabia & the Gulf · Eastern India, Ceylon & Burma · Levant & Egypt | Alexandria, Chittagong | The lamp and cooking oil of Egypt and Bengal, pressed where the olive will not grow. |
| `pistachios` Pistachios | Arabia & the Gulf · Levant & Egypt | Tripoli | Aleppo and Persian pistachios, the banquet nut of the Ottoman and Safavid courts. |
| `henna` Henna | Arabia & the Gulf · East Africa & the Horn · Levant & Egypt · Maghreb | Tripoli, Tunis | The leaf dye of the oases, sold through the Barbary ports to half the world’s markets. |
| `senna` Senna | Arabia & the Gulf · East Africa & the Horn · Levant & Egypt | Alexandria, Mocha | The purging leaf of the upper Nile country, sold through Cairo to every apothecary in Europe. |
| `gallnuts` Gallnuts | Aegean, Anatolia & Black Sea · Arabia & the Gulf · Levant & Egypt | Basra, Tripoli | Aleppo and Kurdish oak galls, the heart of every good black ink and dye. |
| `safflower` Safflower | Eastern India, Ceylon & Burma · Levant & Egypt · Western India | Alexandria | The rouge and dye thistle of Egypt and India, the poor man’s saffron. |
| `soap` Soap | Adriatic & Ionian · Iberia · Levant & Egypt · Western Mediterranean | Beirut, Marseille, Seville, Tripoli, Venice | Olive-oil soap of Marseille, Aleppo and Venice, boxed and shipped as a finished ware. |
| `cedar` Cedar Timber | Caribbean & the Spanish Main · Levant & Egypt · North America, Atlantic Coast | Beirut, Havana, St. George's | Bermuda cedar built the fastest small hulls afloat; Lebanon’s groves were already legend. |

### Maghreb

*9 ports — 0 capital, 2 mid, 7 small. 11 goods have their origin here.*

| good | origin | ports that sell it | why here |
|---|---|---|---|
| `coral` Coral | Iberia · Maghreb · Western Mediterranean | Algiers, Barcelona, Cagliari, Genoa, Livorno, Marseille, Tunis | Red coral fished off Sardinia, Corsica and the Barbary coast, worked at Genoa and Livorno and sold into India. |
| `honey` Honey | Aegean, Anatolia & Black Sea · Baltic & the Hanse · Maghreb · Western Mediterranean | Heraklion, Kaliningrad, Safi, Tangier, Valletta | Lithuanian forest honey and Barbary honey, the sweetener of everyone the sugar ships passed by. |
| `dates` Dates | Arabia & the Gulf · Levant & Egypt · Maghreb | Bandar Abbas, Basra, Manama, Muscat | Basra and Oman dates pressed into baskets, the cheap sweet cargo of every Gulf and Barbary sailing. |
| `figs` Figs | Aegean, Anatolia & Black Sea · Iberia · Maghreb · Western Mediterranean | Algiers, Izmir, Malaga | Smyrna and Malaga figs, drummed and shipped north for winter tables. |
| `citrus` Lemons & Oranges | Adriatic & Ionian · Iberia · Maghreb · Western Mediterranean | Algiers, Cadiz, Malaga, Messina, Palermo, Seville, Valencia | Sicilian and Valencian citrus; ship captains bought them without knowing why they kept crews standing. |
| `almonds` Almonds | Adriatic & Ionian · Iberia · Maghreb · Western Mediterranean | Agadir, Barcelona, Malaga, Marseille, Naples | Andalusian, Apulian and Sous almonds, the marzipan and banquet nut of Europe. |
| `salted-tuna` Salt Tuna | Iberia · Maghreb · Western Mediterranean | Cadiz, Gibraltar, Palermo | The almadraba tunny of the straits, netted at the season and salted down by the thousand. |
| `orchil` Orchil | Atlantic Isles · Maghreb | Cidade Velha, Las Palmas | Purple lichen dye scraped from Atlantic island rocks; the reason crowns quarrelled over bare cliffs. |
| `henna` Henna | Arabia & the Gulf · East Africa & the Horn · Levant & Egypt · Maghreb | Tripoli, Tunis | The leaf dye of the oases, sold through the Barbary ports to half the world’s markets. |
| `ostrich-feathers` Ostrich Feathers | Maghreb · West Africa | Tripoli | Saharan plumes carried to the coast by caravan, nodding on every helmet and hat in Europe. |
| `morocco-leather` Morocco Leather | **only Maghreb** | Sale | Goatskin dressed soft and scarlet in Fez and Marrakesh; the binding of every fine library. |

### West Africa

*11 ports — 0 capital, 2 mid, 9 small. 12 goods have their origin here.*

| good | origin | ports that sell it | why here |
|---|---|---|---|
| `black-pepper` Black Pepper | Southeast Asia · West Africa · Western India | **Aden**, **Alexandria**, **Amsterdam**, **Antwerp**, Banda Aceh, Banten, Calabar, Elmina … (23 in all) | Malabar and Sumatra were the great sources; pepper was the bulk cargo that paid for the Carreira da India. |
| `grains-of-paradise` Grains of Paradise | **only West Africa** | Accra | The pungent seed of the Guinea coast that named the Grain Coast; a cheap stand-in for pepper. |
| `raffia-cloth` Raffia Cloth | **only West Africa** | Luanda, Soyo | The palm-fibre cloth of Kongo and Loango, so trusted it passed as money on the coast. |
| `ivory` Ivory | East Africa & the Horn · Eastern India, Ceylon & Burma · Southeast Asia · West Africa | Accra, Calabar, Cape Coast, Colombo, Elmina, Goree, Kilwa, Lagos … (24 in all) | African elephant ivory from the Guinea, Kongo and Swahili coasts, carved in Lisbon, Dieppe and Gujarat. |
| `rhino-horn` Rhinoceros Horn | East Africa & the Horn · Eastern India, Ceylon & Burma · Southeast Asia · West Africa | Chittagong, Mombasa, Zanzibar | African and Asian horn, carved into cups that were said to sweat at the touch of poison. |
| `parrots` Parrots & Monkeys | South America, Atlantic Coast · West Africa | Belem | Live curiosities of Brazil and Guinea; a talking bird paid a sailor better than his wages. |
| `cassava` Cassava Flour | Caribbean & the Spanish Main · South America, Atlantic Coast · West Africa | Luanda, Recife, Rio de Janeiro, Salvador | Farinha de guerra, the toasted root flour that provisioned every Brazil and Angola voyage. |
| `palm-oil` Palm Oil | **only West Africa** | Calabar, Lagos, Ouidah, Sao Tome | The red cooking oil of the Guinea coast, bought by every factory to feed its own people. |
| `gum-arabic` Gum Arabic | Arabia & the Gulf · East Africa & the Horn · West Africa | Jeddah, Mocha, Saint-Louis, Suakin | Acacia gum of the Senegal river marts, indispensable to dyers, printers and apothecaries. |
| `camwood` Camwood | **only West Africa** | Calabar, Soyo | The red dyewood of the Guinea and Kongo forests, ground to a paste for cloth and skin alike. |
| `kola-nuts` Kola Nuts | **only West Africa** | Accra, Elmina, Goree | The bitter caffeine nut of the Guinea forest, traded north by caravan and along the coast by canoe. |
| `ostrich-feathers` Ostrich Feathers | Maghreb · West Africa | Tripoli | Saharan plumes carried to the coast by caravan, nodding on every helmet and hat in Europe. |

### East Africa & the Horn

*11 ports — 0 capital, 4 mid, 7 small. 11 goods have their origin here.*

| good | origin | ports that sell it | why here |
|---|---|---|---|
| `ivory` Ivory | East Africa & the Horn · Eastern India, Ceylon & Burma · Southeast Asia · West Africa | Accra, Calabar, Cape Coast, Colombo, Elmina, Goree, Kilwa, Lagos … (24 in all) | African elephant ivory from the Guinea, Kongo and Swahili coasts, carved in Lisbon, Dieppe and Gujarat. |
| `frankincense` Frankincense | Arabia & the Gulf · East Africa & the Horn | Aden, Hadibu, Jeddah, Mocha, Mogadishu, Muscat | Dhofar in southern Arabia and the Somali coast behind Berbera, shipped through Aden and Mocha. |
| `myrrh` Myrrh | Arabia & the Gulf · East Africa & the Horn | Aden, Jeddah, Mocha | The same Arabian and Somali dry country as frankincense; used as incense, medicine and embalming resin. |
| `civet` Civet | **only East Africa & the Horn** | Massawa, Mogadishu | Ethiopian civet paste scraped by the ounce, the base note of every great perfume house. |
| `rhino-horn` Rhinoceros Horn | East Africa & the Horn · Eastern India, Ceylon & Burma · Southeast Asia · West Africa | Chittagong, Mombasa, Zanzibar | African and Asian horn, carved into cups that were said to sweat at the touch of poison. |
| `gum-arabic` Gum Arabic | Arabia & the Gulf · East Africa & the Horn · West Africa | Jeddah, Mocha, Saint-Louis, Suakin | Acacia gum of the Senegal river marts, indispensable to dyers, printers and apothecaries. |
| `henna` Henna | Arabia & the Gulf · East Africa & the Horn · Levant & Egypt · Maghreb | Tripoli, Tunis | The leaf dye of the oases, sold through the Barbary ports to half the world’s markets. |
| `ebony` Ebony | East Africa & the Horn · Eastern India, Ceylon & Burma | Galle, Island of Mozambique | The black heartwood of Ceylon and the Mozambique coast, turned into cabinets and crucifixes. |
| `senna` Senna | Arabia & the Gulf · East Africa & the Horn · Levant & Egypt | Alexandria, Mocha | The purging leaf of the upper Nile country, sold through Cairo to every apothecary in Europe. |
| `copal` Copal | Caribbean & the Spanish Main · East Africa & the Horn | Zanzibar | Incense and varnish resin, dug fossil on the Swahili coast and tapped fresh in New Spain. |
| `mangrove-poles` Mangrove Poles | **only East Africa & the Horn** | Kilwa, Mombasa, Island of Mozambique | Boriti poles of the Swahili creeks, the roof timber of every treeless Gulf town. |

### Arabia & the Gulf

*10 ports — 0 capital, 7 mid, 3 small. 22 goods have their origin here.*

| good | origin | ports that sell it | why here |
|---|---|---|---|
| `saffron` Saffron | Arabia & the Gulf · Iberia | Bandar Abbas, Barcelona, Valencia | La Mancha and Persian crocus threads, picked by hand; the dearest spice in the world by weight. |
| `carpets` Carpets | Aegean, Anatolia & Black Sea · Arabia & the Gulf | Antalya, Bandar Abbas, Basra, Istanbul, Izmir, Trabzon | Safavid Persia and Ottoman Anatolia; carried west overland to Aleppo and by sea from Bandar Abbas. |
| `frankincense` Frankincense | Arabia & the Gulf · East Africa & the Horn | Aden, Hadibu, Jeddah, Mocha, Mogadishu, Muscat | Dhofar in southern Arabia and the Somali coast behind Berbera, shipped through Aden and Mocha. |
| `myrrh` Myrrh | Arabia & the Gulf · East Africa & the Horn | Aden, Jeddah, Mocha | The same Arabian and Somali dry country as frankincense; used as incense, medicine and embalming resin. |
| `rosewater` Rosewater | Arabia & the Gulf · Levant & Egypt | Bandar Abbas, Beirut | Distilled roses of Shiraz and Damascus, shipped in glass carboys packed in straw. |
| `bezoar` Bezoar Stones | Arabia & the Gulf · Southeast Asia · Western India | Malacca, Old Goa | Stones from the stomachs of goats and porcupines, sworn to defeat any poison; Goa even made its own. |
| `lapis-lazuli` Lapis Lazuli | **only Arabia & the Gulf** | Hormuz | The blue stone of Badakhshan, ground in Europe into ultramarine dearer than gold leaf. |
| `turquoise` Turquoise | **only Arabia & the Gulf** | Bandar Abbas | Nishapur turquoise of Persia, the sky-blue stone of daggers and turban jewels. |
| `coffee` Coffee | **only Arabia & the Gulf** | Aden, **Alexandria**, Jeddah, **Marseille**, Mocha, Suez | Grown in the Yemeni highlands and shipped through Mocha, its only outlet until the 18th century. |
| `dates` Dates | Arabia & the Gulf · Levant & Egypt · Maghreb | Bandar Abbas, Basra, Manama, Muscat | Basra and Oman dates pressed into baskets, the cheap sweet cargo of every Gulf and Barbary sailing. |
| `sesame-oil` Sesame Oil | Arabia & the Gulf · Eastern India, Ceylon & Burma · Levant & Egypt | Alexandria, Chittagong | The lamp and cooking oil of Egypt and Bengal, pressed where the olive will not grow. |
| `pistachios` Pistachios | Arabia & the Gulf · Levant & Egypt | Tripoli | Aleppo and Persian pistachios, the banquet nut of the Ottoman and Safavid courts. |
| `gum-arabic` Gum Arabic | Arabia & the Gulf · East Africa & the Horn · West Africa | Jeddah, Mocha, Saint-Louis, Suakin | Acacia gum of the Senegal river marts, indispensable to dyers, printers and apothecaries. |
| `henna` Henna | Arabia & the Gulf · East Africa & the Horn · Levant & Egypt · Maghreb | Tripoli, Tunis | The leaf dye of the oases, sold through the Barbary ports to half the world’s markets. |
| `dragons-blood` Dragon’s Blood | **only Arabia & the Gulf** | Aden | The red resin of Socotra’s dragon trees, sold as medicine, varnish and pigment. |
| `socotra-aloes` Socotrine Aloes | **only Arabia & the Gulf** | Aden | Bitter aloe juice dried on Socotra, the purge in every ship surgeon’s chest. |
| `senna` Senna | Arabia & the Gulf · East Africa & the Horn · Levant & Egypt | Alexandria, Mocha | The purging leaf of the upper Nile country, sold through Cairo to every apothecary in Europe. |
| `mother-of-pearl` Mother-of-Pearl | Arabia & the Gulf · Japan & the Ryukyus · Southeast Asia | Cebu, Manama, Manila, Naha | Nacre shell of the Gulf and Sulu banks, cut for inlay in Gujarat, Canton and Kyoto. |
| `gallnuts` Gallnuts | Aegean, Anatolia & Black Sea · Arabia & the Gulf · Levant & Egypt | Basra, Tripoli | Aleppo and Kurdish oak galls, the heart of every good black ink and dye. |
| `cobalt` Cobalt Blue | **only Arabia & the Gulf** | Hormuz | The Persian ore behind Mohammedan blue; Jingdezhen’s best porcelain was painted with it. |
| `asafoetida` Asafoetida | Arabia & the Gulf · Western India | Bandar Abbas, Karachi | The foul-smelling gum of Persia and Afghanistan that Indian cooking cannot do without. |
| `mecca-balsam` Balm of Mecca | **only Arabia & the Gulf** | Jeddah | The true balsam of the Hejaz gardens, so scarce that most of what sold under the name was not it. |

### Western India

*12 ports — 4 capital, 2 mid, 6 small. 24 goods have their origin here.*

| good | origin | ports that sell it | why here |
|---|---|---|---|
| `black-pepper` Black Pepper | Southeast Asia · West Africa · Western India | **Aden**, **Alexandria**, **Amsterdam**, **Antwerp**, Banda Aceh, Banten, Calabar, Elmina … (23 in all) | Malabar and Sumatra were the great sources; pepper was the bulk cargo that paid for the Carreira da India. |
| `ginger` Ginger | Caribbean & the Spanish Main · Eastern India, Ceylon & Burma · South America, Atlantic Coast · Western India | Kannur, Kochi, Kozhikode, Salvador, San Juan, Santo Domingo | Malabar and Bengal, and from the 1520s a transplanted crop on Hispaniola and Jamaica. |
| `cardamom` Cardamom | **only Western India** | Kannur, Kochi, Kozhikode | The Cardamom Hills of the Western Ghats behind the Malabar pepper ports. |
| `turmeric` Turmeric | Eastern India, Ceylon & Burma · Western India | Chennai, Kozhikode, Machilipatnam | The yellow root of India, dye and spice in one; every bazaar of the Indian Ocean priced it. |
| `cumin` Cumin | Levant & Egypt · Western India | Alexandria, Khambhat | Egyptian and Gujarati cumin seed, a workhorse spice sold in sacks rather than caskets. |
| `shawls` Kashmir Shawls | **only Western India** | Karachi, Surat | Goat-down shawls woven in Kashmir and carried down to the Gujarat and Sind ports; a season each on the loom. |
| `wootz-steel` Wootz Steel | Eastern India, Ceylon & Burma · Western India | Machilipatnam | The crucible steel cakes of the Deccan that Damascus smiths forged into watered blades. |
| `carnelian` Carnelian & Agate | **only Western India** | Khambhat, Surat | The banded stones of Cambay, cut and polished there into beads for three continents. |
| `bezoar` Bezoar Stones | Arabia & the Gulf · Southeast Asia · Western India | Malacca, Old Goa | Stones from the stomachs of goats and porcupines, sworn to defeat any poison; Goa even made its own. |
| `arrack` Arrack | Eastern India, Ceylon & Burma · Southeast Asia · Western India | Colombo, Jakarta, Old Goa | Palm and rice spirit of Batavia, Ceylon and Goa; the sailor’s punch on every eastern voyage. |
| `ghee` Ghee | **only Western India** | Karachi, Khambhat, Surat | Clarified butter of Gujarat and Sind, shipped in jars wherever Indian crews and kitchens went. |
| `palm-sugar` Palm Sugar | Eastern India, Ceylon & Burma · Southeast Asia · Western India | Banten | Jaggery boiled from palm sap, the everyday sweet of Bengal and the Indies. |
| `tamarind` Tamarind | Eastern India, Ceylon & Burma · Southeast Asia · Western India | Mumbai | The sour pod of India, packed in jars as ship’s physic and kitchen souring both. |
| `saltpetre` Saltpetre | Eastern India, Ceylon & Burma · Western India | Chennai, Hooghly, Surat | Bihar and the Ganges plain; refined at Patna and shipped down the Hugli as the powder trade's key ingredient. |
| `sandalwood` Sandalwood | Oceania & the Far Pacific · Southeast Asia · Western India | Banda Aceh, Banten, Dili, Hoi An, Honolulu, Kozhikode, Kupang, Makassar … (10 in all) | The fragrant heartwood of Timor and the lesser Sundas, burned in Chinese temples and carved for the gods. |
| `myrobalans` Myrobalans | Eastern India, Ceylon & Burma · Western India | Khambhat, Surat | The tanning and dyeing fruit of India, bought by the bale for leather and ink. |
| `opium` Opium | Eastern India, Ceylon & Burma · Western India | Hooghly, Khambhat, Old Goa | Malwa and Patna opium, already a staple of the Indian Ocean drug trade the Portuguese taxed at Goa. |
| `areca-nuts` Areca Nuts | Eastern India, Ceylon & Burma · Southeast Asia · Western India | Colombo, Kannur, Kochi, Kozhikode | The betel nut of Ceylon and Malabar, chewed from Arabia to the Moluccas; a bulk trade in its own right. |
| `cowries` Cowrie Shells | Eastern India, Ceylon & Burma · Western India | Colombo, Galle | Maldive shells shipped by the ton through Ceylon and Bengal; the small money of three continents. |
| `coir` Coir | Eastern India, Ceylon & Burma · Southeast Asia · Western India | Kochi, Kollam, Kozhikode, Old Goa | Coconut husk fibre of Malabar and the isles; the sewn ships of the Indian Ocean are stitched with it. |
| `safflower` Safflower | Eastern India, Ceylon & Burma · Levant & Egypt · Western India | Alexandria | The rouge and dye thistle of Egypt and India, the poor man’s saffron. |
| `catechu` Catechu | Eastern India, Ceylon & Burma · Western India | Mumbai | Cutch, the dark tanning extract of Pegu and India, boiled from heartwood and sold in cakes. |
| `asafoetida` Asafoetida | Arabia & the Gulf · Western India | Bandar Abbas, Karachi | The foul-smelling gum of Persia and Afghanistan that Indian cooking cannot do without. |
| `teak` Teak | Eastern India, Ceylon & Burma · Western India | Kochi, Kozhikode, Mangaluru | The shipbuilding wood of Malabar and Pegu that laughs at worm and weather; every eastern yard ran on it. |

### Eastern India, Ceylon & Burma

*10 ports — 0 capital, 3 mid, 7 small. 35 goods have their origin here.*

| good | origin | ports that sell it | why here |
|---|---|---|---|
| `cinnamon` Cinnamon | **only Eastern India, Ceylon & Burma** | Colombo, Galle, **Kochi**, **Lisbon**, **Old Goa** | The true cinnamon of Ceylon's western lowlands; Portugal and then the Dutch fought for the peeling monopoly. |
| `ginger` Ginger | Caribbean & the Spanish Main · Eastern India, Ceylon & Burma · South America, Atlantic Coast · Western India | Kannur, Kochi, Kozhikode, Salvador, San Juan, Santo Domingo | Malabar and Bengal, and from the 1520s a transplanted crop on Hispaniola and Jamaica. |
| `long-pepper` Long Pepper | **only Eastern India, Ceylon & Burma** | Chittagong | The hotter catkin pepper of Bengal, sold beside the round Malabar berry since Roman times. |
| `turmeric` Turmeric | Eastern India, Ceylon & Burma · Western India | Chennai, Kozhikode, Machilipatnam | The yellow root of India, dye and spice in one; every bazaar of the Indian Ocean priced it. |
| `zedoary` Zedoary | Eastern India, Ceylon & Burma · Southeast Asia | Galle | A bitter camphor-scented root of Ceylon and the Indies, sold to European apothecaries as a drug. |
| `muslin` Muslin | **only Eastern India, Ceylon & Burma** | Hooghly | The gossamer cottons of Dhaka and the Bengal delta, the finest woven cloth of the period. |
| `chintz` Chintz | **only Eastern India, Ceylon & Burma** | Chennai, Machilipatnam, Pulicat | Painted and mordant-dyed Coromandel cottons; kalamkari from Machilipatnam and Pulicat. |
| `quilts` Bengal Quilts | **only Eastern India, Ceylon & Burma** | Hooghly | The embroidered colchas of Satgaon, stitched in silk on cotton; a Portuguese favourite from the first. |
| `tin` Tin | British Isles · Eastern India, Ceylon & Burma · Southeast Asia | London, Malacca, Myeik, Plymouth | Cornwall in Europe, and the Malay peninsula and Bangka in Asia, where tin ingots served as money. |
| `wootz-steel` Wootz Steel | Eastern India, Ceylon & Burma · Western India | Machilipatnam | The crucible steel cakes of the Deccan that Damascus smiths forged into watered blades. |
| `diamonds` Diamonds | Eastern India, Ceylon & Burma · Southeast Asia | **Antwerp**, Colombo, Machilipatnam | Golconda stones sold through Machilipatnam, and the Landak diamonds of Borneo; cut and set in Antwerp and Goa. |
| `ivory` Ivory | East Africa & the Horn · Eastern India, Ceylon & Burma · Southeast Asia · West Africa | Accra, Calabar, Cape Coast, Colombo, Elmina, Goree, Kilwa, Lagos … (24 in all) | African elephant ivory from the Guinea, Kongo and Swahili coasts, carved in Lisbon, Dieppe and Gujarat. |
| `rubies` Rubies | **only Eastern India, Ceylon & Burma** | Thanlyin | The stones of the Mogok mines above Pegu, carried out through the Burma ports sewn into clothing. |
| `rhino-horn` Rhinoceros Horn | East Africa & the Horn · Eastern India, Ceylon & Burma · Southeast Asia · West Africa | Chittagong, Mombasa, Zanzibar | African and Asian horn, carved into cups that were said to sweat at the touch of poison. |
| `martaban-jars` Martaban Jars | **only Eastern India, Ceylon & Burma** | Thanlyin | The great glazed storage jars of Martaban, prized from Japan to Arabia for keeping water sweet. |
| `arrack` Arrack | Eastern India, Ceylon & Burma · Southeast Asia · Western India | Colombo, Jakarta, Old Goa | Palm and rice spirit of Batavia, Ceylon and Goa; the sailor’s punch on every eastern voyage. |
| `sesame-oil` Sesame Oil | Arabia & the Gulf · Eastern India, Ceylon & Burma · Levant & Egypt | Alexandria, Chittagong | The lamp and cooking oil of Egypt and Bengal, pressed where the olive will not grow. |
| `palm-sugar` Palm Sugar | Eastern India, Ceylon & Burma · Southeast Asia · Western India | Banten | Jaggery boiled from palm sap, the everyday sweet of Bengal and the Indies. |
| `tamarind` Tamarind | Eastern India, Ceylon & Burma · Southeast Asia · Western India | Mumbai | The sour pod of India, packed in jars as ship’s physic and kitchen souring both. |
| `saltpetre` Saltpetre | Eastern India, Ceylon & Burma · Western India | Chennai, Hooghly, Surat | Bihar and the Ganges plain; refined at Patna and shipped down the Hugli as the powder trade's key ingredient. |
| `lac` Lac & Shellac | **only Eastern India, Ceylon & Burma** | Thanlyin | The insect resin of Pegu and Bengal: scarlet dye, sealing wax and the polish on every cabinet. |
| `myrobalans` Myrobalans | Eastern India, Ceylon & Burma · Western India | Khambhat, Surat | The tanning and dyeing fruit of India, bought by the bale for leather and ink. |
| `sappanwood` Sappanwood | Eastern India, Ceylon & Burma · Southeast Asia | Ayutthaya, Hoi An, Myeik, **Naha**, Pattani | The red dyewood of Siam; junk after junk carried it to Japan, where it paid for silver. |
| `red-sanders` Red Sanders | **only Eastern India, Ceylon & Burma** | Chennai | The Coromandel red wood, cousin to sappan, cut in the Palakonda hills for the dye vats. |
| `ebony` Ebony | East Africa & the Horn · Eastern India, Ceylon & Burma | Galle, Island of Mozambique | The black heartwood of Ceylon and the Mozambique coast, turned into cabinets and crucifixes. |
| `opium` Opium | Eastern India, Ceylon & Burma · Western India | Hooghly, Khambhat, Old Goa | Malwa and Patna opium, already a staple of the Indian Ocean drug trade the Portuguese taxed at Goa. |
| `areca-nuts` Areca Nuts | Eastern India, Ceylon & Burma · Southeast Asia · Western India | Colombo, Kannur, Kochi, Kozhikode | The betel nut of Ceylon and Malabar, chewed from Arabia to the Moluccas; a bulk trade in its own right. |
| `cowries` Cowrie Shells | Eastern India, Ceylon & Burma · Western India | Colombo, Galle | Maldive shells shipped by the ton through Ceylon and Bengal; the small money of three continents. |
| `chank-shells` Chank Shells | **only Eastern India, Ceylon & Burma** | Jaffna | The sacred conch of the Mannar banks, sawn into bangles for Bengal. |
| `coir` Coir | Eastern India, Ceylon & Burma · Southeast Asia · Western India | Kochi, Kollam, Kozhikode, Old Goa | Coconut husk fibre of Malabar and the isles; the sewn ships of the Indian Ocean are stitched with it. |
| `safflower` Safflower | Eastern India, Ceylon & Burma · Levant & Egypt · Western India | Alexandria | The rouge and dye thistle of Egypt and India, the poor man’s saffron. |
| `catechu` Catechu | Eastern India, Ceylon & Burma · Western India | Mumbai | Cutch, the dark tanning extract of Pegu and India, boiled from heartwood and sold in cakes. |
| `elephants` War Elephants | **only Eastern India, Ceylon & Burma** | Colombo, Thanlyin | Ceylon and Pegu elephants, shipped standing to the courts of India; the grandest cargo afloat. |
| `spikenard` Spikenard | **only Eastern India, Ceylon & Burma** | Hooghly | The aromatic root of the high Himalaya, carried down the Ganges as it had been since Rome. |
| `teak` Teak | Eastern India, Ceylon & Burma · Western India | Kochi, Kozhikode, Mangaluru | The shipbuilding wood of Malabar and Pegu that laughs at worm and weather; every eastern yard ran on it. |

### Southeast Asia

*16 ports — 3 capital, 8 mid, 5 small. 38 goods have their origin here.*

| good | origin | ports that sell it | why here |
|---|---|---|---|
| `black-pepper` Black Pepper | Southeast Asia · West Africa · Western India | **Aden**, **Alexandria**, **Amsterdam**, **Antwerp**, Banda Aceh, Banten, Calabar, Elmina … (23 in all) | Malabar and Sumatra were the great sources; pepper was the bulk cargo that paid for the Carreira da India. |
| `cloves` Cloves | **only Southeast Asia** | Ambon, Jakarta, Makassar, Malacca, Ternate, Tidore | Grew only on Ternate, Tidore and their neighbouring islets in the northern Moluccas before transplantation. |
| `nutmeg` Nutmeg | **only Southeast Asia** | Ambon, Banda Neira, Jakarta, Malacca | The Banda islands were the world's only source; the VOC seized them outright in 1621. |
| `mace` Mace | **only Southeast Asia** | Banda Neira | The scarlet aril of the same Banda nutmeg fruit, scarcer than the nut itself and priced above it. |
| `cubeb` Cubeb | **only Southeast Asia** | Banten, Surabaya | The tailed pepper of Java, sold by apothecaries as much as by cooks. |
| `cassia` Cassia | China Coast · Southeast Asia | Guangzhou, Hanoi, Hoi An | The thick cinnamon bark of south China and Tonkin, coarser and cheaper than the Ceylon peel. |
| `galangal` Galangal | **only Southeast Asia** | Ayutthaya, Hoi An | The ginger-like root of Siam and Champa, prized by apothecaries as far away as Europe. |
| `star-anise` Star Anise | China Coast · Southeast Asia | Guangzhou, Hanoi | The eight-pointed pod of the Tonkin borderlands, sweeter than aniseed and dearer. |
| `zedoary` Zedoary | Eastern India, Ceylon & Burma · Southeast Asia | Galle | A bitter camphor-scented root of Ceylon and the Indies, sold to European apothecaries as a drug. |
| `batik` Batik Cloth | **only Southeast Asia** | Banten, Jakarta, Surabaya | Wax-resist patterned cottons of Java, traded through the pasisir ports alongside Indian cloth. |
| `tin` Tin | British Isles · Eastern India, Ceylon & Burma · Southeast Asia | London, Malacca, Myeik, Plymouth | Cornwall in Europe, and the Malay peninsula and Bangka in Asia, where tin ingots served as money. |
| `porcelain` Porcelain | China Coast · Japan & the Ryukyus · Southeast Asia | **Acapulco**, Fukuoka, Guangzhou, Hirado, Hoi An, Jakarta, **Lisbon**, Macau … (15 in all) | Jingdezhen blue-and-white shipped through Canton and Macau; the kraak ware the Dutch took from Portuguese carracks. |
| `lacquerware` Lacquerware | China Coast · Japan & the Ryukyus · Korea · Southeast Asia | Fuzhou, Guangzhou, Hanoi, Nagasaki, Naha, Osaka, Tokyo, Tongyeong | Japanese and Ryukyuan urushi ware, and Vietnamese and Korean lacquer, prized as cabinet goods in Europe. |
| `diamonds` Diamonds | Eastern India, Ceylon & Burma · Southeast Asia | **Antwerp**, Colombo, Machilipatnam | Golconda stones sold through Machilipatnam, and the Landak diamonds of Borneo; cut and set in Antwerp and Goa. |
| `ivory` Ivory | East Africa & the Horn · Eastern India, Ceylon & Burma · Southeast Asia · West Africa | Accra, Calabar, Cape Coast, Colombo, Elmina, Goree, Kilwa, Lagos … (24 in all) | African elephant ivory from the Guinea, Kongo and Swahili coasts, carved in Lisbon, Dieppe and Gujarat. |
| `tortoiseshell` Tortoiseshell | Caribbean & the Spanish Main · Japan & the Ryukyus · Southeast Asia | Cebu, Manila, Naha, Tidore | Hawksbill shell from the Ryukyus, the Visayas and the Caribbean, worked into combs and inlay. |
| `bezoar` Bezoar Stones | Arabia & the Gulf · Southeast Asia · Western India | Malacca, Old Goa | Stones from the stomachs of goats and porcupines, sworn to defeat any poison; Goa even made its own. |
| `rhino-horn` Rhinoceros Horn | East Africa & the Horn · Eastern India, Ceylon & Burma · Southeast Asia · West Africa | Chittagong, Mombasa, Zanzibar | African and Asian horn, carved into cups that were said to sweat at the touch of poison. |
| `celadon` Celadon Ware | Korea · Southeast Asia | Ayutthaya, Busan | Sawankhalok green ware out of Siam and Korean bowls the Japanese tea masters ruined themselves for. |
| `paradise-plumes` Bird-of-Paradise Plumes | Oceania & the Far Pacific · Southeast Asia | Banda Neira, Ternate | Legless skins from the Aru islands, sold in Europe as birds that lived their whole lives on the wing. |
| `arrack` Arrack | Eastern India, Ceylon & Burma · Southeast Asia · Western India | Colombo, Jakarta, Old Goa | Palm and rice spirit of Batavia, Ceylon and Goa; the sailor’s punch on every eastern voyage. |
| `sago` Sago | Oceania & the Far Pacific · Southeast Asia | Ambon, Banda Neira, Makassar, Ternate | Palm-pith flour of the eastern islands, the bread of the spice country. |
| `birds-nests` Edible Birds’ Nests | **only Southeast Asia** | Makassar | Swiftlet nests gathered from cliff caves for the soup kitchens of Canton; worth their weight in silver. |
| `sharks-fin` Shark Fin | China Coast · Japan & the Ryukyus · Oceania & the Far Pacific · Southeast Asia | Kupang, Ternate | Dried fins from the eastern seas, bound for the Chinese banquet trade. |
| `trepang` Trepang | Oceania & the Far Pacific · Southeast Asia | Dili, Kupang, Makassar | Smoked sea cucumber of the Makassar praus, fished as far as the dry south land for Chinese kitchens. |
| `palm-sugar` Palm Sugar | Eastern India, Ceylon & Burma · Southeast Asia · Western India | Banten | Jaggery boiled from palm sap, the everyday sweet of Bengal and the Indies. |
| `tamarind` Tamarind | Eastern India, Ceylon & Burma · Southeast Asia · Western India | Mumbai | The sour pod of India, packed in jars as ship’s physic and kitchen souring both. |
| `sandalwood` Sandalwood | Oceania & the Far Pacific · Southeast Asia · Western India | Banda Aceh, Banten, Dili, Hoi An, Honolulu, Kozhikode, Kupang, Makassar … (10 in all) | The fragrant heartwood of Timor and the lesser Sundas, burned in Chinese temples and carved for the gods. |
| `camphor` Borneo Camphor | Japan & the Ryukyus · Southeast Asia | Banda Aceh, Banten, Malacca, Nagasaki | Crystal camphor of Barus and Borneo, worth many times the Chinese sort; medicine, incense and embalming. |
| `benzoin` Benzoin | **only Southeast Asia** | Ayutthaya, Banda Aceh, Malacca | The sweet resin of Sumatra and Siam, burned as incense from Lisbon to Nagasaki. |
| `aloeswood` Aloeswood | China Coast · Southeast Asia | Hoi An, Hong Kong | Agarwood of the Champa hills; a single resinous log could ransom the ship that carried it. |
| `sappanwood` Sappanwood | Eastern India, Ceylon & Burma · Southeast Asia | Ayutthaya, Hoi An, Myeik, **Naha**, Pattani | The red dyewood of Siam; junk after junk carried it to Japan, where it paid for silver. |
| `rattan` Rattan | **only Southeast Asia** | Surabaya | The climbing cane of the Indies: cables, baskets and chairs from one forest vine. |
| `areca-nuts` Areca Nuts | Eastern India, Ceylon & Burma · Southeast Asia · Western India | Colombo, Kannur, Kochi, Kozhikode | The betel nut of Ceylon and Malabar, chewed from Arabia to the Moluccas; a bulk trade in its own right. |
| `mother-of-pearl` Mother-of-Pearl | Arabia & the Gulf · Japan & the Ryukyus · Southeast Asia | Cebu, Manama, Manila, Naha | Nacre shell of the Gulf and Sulu banks, cut for inlay in Gujarat, Canton and Kyoto. |
| `coir` Coir | Eastern India, Ceylon & Burma · Southeast Asia · Western India | Kochi, Kollam, Kozhikode, Old Goa | Coconut husk fibre of Malabar and the isles; the sewn ships of the Indian Ocean are stitched with it. |
| `gamboge` Gamboge | **only Southeast Asia** | Ayutthaya | The golden gum of the Cambodian forests, at once a pigment and a violent purge. |
| `abaca` Manila Hemp | **only Southeast Asia** | Cebu, Manila | Banana-fibre cordage of the Philippines; the galleons rigged themselves with it. |

### China Coast

*8 ports — 2 capital, 4 mid, 2 small. 17 goods have their origin here.*

| good | origin | ports that sell it | why here |
|---|---|---|---|
| `cassia` Cassia | China Coast · Southeast Asia | Guangzhou, Hanoi, Hoi An | The thick cinnamon bark of south China and Tonkin, coarser and cheaper than the Ceylon peel. |
| `star-anise` Star Anise | China Coast · Southeast Asia | Guangzhou, Hanoi | The eight-pointed pod of the Tonkin borderlands, sweeter than aniseed and dearer. |
| `ramie-cloth` Ramie Cloth | China Coast · Korea | Busan, Guangzhou, Incheon, Mokpo, **Tsushima** | Korean mosi, a fine summer bast cloth, among the goods traded through the Busan Waegwan to Tsushima. |
| `copper-cash` Copper Cash | **only China Coast** | Ningbo, Quanzhou, Xiamen | Strings of Chinese cash, shipped as money itself to Japan and Java where the coin was current. |
| `porcelain` Porcelain | China Coast · Japan & the Ryukyus · Southeast Asia | **Acapulco**, Fukuoka, Guangzhou, Hirado, Hoi An, Jakarta, **Lisbon**, Macau … (15 in all) | Jingdezhen blue-and-white shipped through Canton and Macau; the kraak ware the Dutch took from Portuguese carracks. |
| `lacquerware` Lacquerware | China Coast · Japan & the Ryukyus · Korea · Southeast Asia | Fuzhou, Guangzhou, Hanoi, Nagasaki, Naha, Osaka, Tokyo, Tongyeong | Japanese and Ryukyuan urushi ware, and Vietnamese and Korean lacquer, prized as cabinet goods in Europe. |
| `musk` Musk | **only China Coast** | Macau | Himalayan and Chinese musk pods, carried down to Canton and Macau and sold by the ounce. |
| `ink-sticks` Ink & Brushes | China Coast · Korea | Busan, Incheon, Ningbo | Huizhou ink sticks and Korean brushes, the tools of every yamen and academy. |
| `tea` Tea | China Coast · Japan & the Ryukyus | Fuzhou, Guangzhou, Macau, Nagasaki, Ningbo, Quanzhou, Sakai, Xiamen | Fujian and Zhejiang leaf; the first Dutch shipment reached Europe from Java in 1610. |
| `soy-sauce` Soy Sauce | China Coast · Japan & the Ryukyus · Korea | Nagasaki, Osaka, Tokyo | Brewed soy of Japan, casked at Nagasaki; the Dutch carried it as far as Batavia and beyond. |
| `sharks-fin` Shark Fin | China Coast · Japan & the Ryukyus · Oceania & the Far Pacific · Southeast Asia | Kupang, Ternate | Dried fins from the eastern seas, bound for the Chinese banquet trade. |
| `lychees` Dried Lychees | **only China Coast** | Fuzhou, Xiamen | The Fujian orchard fruit, dried to raisins of the south and shipped up the whole China coast. |
| `ginseng` Ginseng | China Coast · Korea | Busan, Guangzhou, Incheon, Nampo, **Tsushima** | Korean mountain root, the highest-value good of the Joseon-Tsushima trade, sold on to Chinese physicians. |
| `aloeswood` Aloeswood | China Coast · Southeast Asia | Hoi An, Hong Kong | Agarwood of the Champa hills; a single resinous log could ransom the ship that carried it. |
| `rhubarb` Chinese Rhubarb | **only China Coast** | Macau, Ningbo, Quanzhou | The dried medicinal root of the Chinese northwest, dearer in Europe than cinnamon. |
| `china-root` China Root | **only China Coast** | Macau, Xiamen | The smilax root the Portuguese carried from Macau as the new cure for the French disease. |
| `vermilion` Vermilion | China Coast · France & the Low Countries | Amsterdam, Guangzhou | The scarlet mercury pigment, made in China and Holland and sold by the pound to painters and printers. |

### Korea

*8 ports — 1 capital, 2 mid, 5 small. 9 goods have their origin here.*

| good | origin | ports that sell it | why here |
|---|---|---|---|
| `ramie-cloth` Ramie Cloth | China Coast · Korea | Busan, Guangzhou, Incheon, Mokpo, **Tsushima** | Korean mosi, a fine summer bast cloth, among the goods traded through the Busan Waegwan to Tsushima. |
| `lacquerware` Lacquerware | China Coast · Japan & the Ryukyus · Korea · Southeast Asia | Fuzhou, Guangzhou, Hanoi, Nagasaki, Naha, Osaka, Tokyo, Tongyeong | Japanese and Ryukyuan urushi ware, and Vietnamese and Korean lacquer, prized as cabinet goods in Europe. |
| `celadon` Celadon Ware | Korea · Southeast Asia | Ayutthaya, Busan | Sawankhalok green ware out of Siam and Korean bowls the Japanese tea masters ruined themselves for. |
| `ink-sticks` Ink & Brushes | China Coast · Korea | Busan, Incheon, Ningbo | Huizhou ink sticks and Korean brushes, the tools of every yamen and academy. |
| `soy-sauce` Soy Sauce | China Coast · Japan & the Ryukyus · Korea | Nagasaki, Osaka, Tokyo | Brewed soy of Japan, casked at Nagasaki; the Dutch carried it as far as Batavia and beyond. |
| `dried-abalone` Dried Abalone | Japan & the Ryukyus · Korea | Hirado, Jeju | Diver-gathered abalone of Jeju and Kyushu, dried hard and prized in China above fresh pearl. |
| `seaweed` Dried Seaweed | Japan & the Ryukyus · Korea | Jeju, Mokpo, Tokyo, Yeosu | Kelp and laver of the Korea Strait, dried on every foreshore and eaten in every kitchen. |
| `ginseng` Ginseng | China Coast · Korea | Busan, Guangzhou, Incheon, Nampo, **Tsushima** | Korean mountain root, the highest-value good of the Joseon-Tsushima trade, sold on to Chinese physicians. |
| `tiger-skins` Tiger Skins | **only Korea** | Busan, Nampo | Joseon tiger and leopard skins, the prestige export the Japanese daimyo paid silver for. |

### Japan & the Ryukyus

*11 ports — 3 capital, 4 mid, 4 small. 15 goods have their origin here.*

| good | origin | ports that sell it | why here |
|---|---|---|---|
| `firearms` Muskets | France & the Low Countries · Japan & the Ryukyus | Antwerp, Sakai | Sakai matchlocks and Low Countries muskets; a chest of them opened doors on every coast. |
| `porcelain` Porcelain | China Coast · Japan & the Ryukyus · Southeast Asia | **Acapulco**, Fukuoka, Guangzhou, Hirado, Hoi An, Jakarta, **Lisbon**, Macau … (15 in all) | Jingdezhen blue-and-white shipped through Canton and Macau; the kraak ware the Dutch took from Portuguese carracks. |
| `lacquerware` Lacquerware | China Coast · Japan & the Ryukyus · Korea · Southeast Asia | Fuzhou, Guangzhou, Hanoi, Nagasaki, Naha, Osaka, Tokyo, Tongyeong | Japanese and Ryukyuan urushi ware, and Vietnamese and Korean lacquer, prized as cabinet goods in Europe. |
| `tortoiseshell` Tortoiseshell | Caribbean & the Spanish Main · Japan & the Ryukyus · Southeast Asia | Cebu, Manila, Naha, Tidore | Hawksbill shell from the Ryukyus, the Visayas and the Caribbean, worked into combs and inlay. |
| `folding-fans` Folding Fans | **only Japan & the Ryukyus** | Osaka, Sakai | Kyoto folding fans shipped through Sakai; Europe copied the idea and never the finish. |
| `sword-blades` Sword Blades | Baltic & the Hanse · Iberia · Japan & the Ryukyus | Cadiz, Hamburg, Sakai, Tokyo | Japanese blades shipped to China by the thousand, with Toledo and Solingen steel for the western trade. |
| `tea` Tea | China Coast · Japan & the Ryukyus | Fuzhou, Guangzhou, Macau, Nagasaki, Ningbo, Quanzhou, Sakai, Xiamen | Fujian and Zhejiang leaf; the first Dutch shipment reached Europe from Java in 1610. |
| `sake` Sake | **only Japan & the Ryukyus** | Fukuoka, Osaka, Sakai | The rice brew of Itami and Nada, casked at Osaka for every castle town on the seaway. |
| `soy-sauce` Soy Sauce | China Coast · Japan & the Ryukyus · Korea | Nagasaki, Osaka, Tokyo | Brewed soy of Japan, casked at Nagasaki; the Dutch carried it as far as Batavia and beyond. |
| `sharks-fin` Shark Fin | China Coast · Japan & the Ryukyus · Oceania & the Far Pacific · Southeast Asia | Kupang, Ternate | Dried fins from the eastern seas, bound for the Chinese banquet trade. |
| `dried-abalone` Dried Abalone | Japan & the Ryukyus · Korea | Hirado, Jeju | Diver-gathered abalone of Jeju and Kyushu, dried hard and prized in China above fresh pearl. |
| `seaweed` Dried Seaweed | Japan & the Ryukyus · Korea | Jeju, Mokpo, Tokyo, Yeosu | Kelp and laver of the Korea Strait, dried on every foreshore and eaten in every kitchen. |
| `sulphur` Sulphur | Japan & the Ryukyus · Scandinavia & the Arctic · Western Mediterranean | Kagoshima, Nagasaki, Naha, Reykjavik | Sicily, Iceland and the Japanese and Ryukyuan volcanoes; the other half of gunpowder. |
| `camphor` Borneo Camphor | Japan & the Ryukyus · Southeast Asia | Banda Aceh, Banten, Malacca, Nagasaki | Crystal camphor of Barus and Borneo, worth many times the Chinese sort; medicine, incense and embalming. |
| `mother-of-pearl` Mother-of-Pearl | Arabia & the Gulf · Japan & the Ryukyus · Southeast Asia | Cebu, Manama, Manila, Naha | Nacre shell of the Gulf and Sulu banks, cut for inlay in Gujarat, Canton and Kyoto. |

### Caribbean & the Spanish Main

*10 ports — 3 capital, 2 mid, 5 small. 18 goods have their origin here.*

| good | origin | ports that sell it | why here |
|---|---|---|---|
| `ginger` Ginger | Caribbean & the Spanish Main · Eastern India, Ceylon & Burma · South America, Atlantic Coast · Western India | Kannur, Kochi, Kozhikode, Salvador, San Juan, Santo Domingo | Malabar and Bengal, and from the 1520s a transplanted crop on Hispaniola and Jamaica. |
| `vanilla` Vanilla | **only Caribbean & the Spanish Main** | Veracruz | The cured orchid pod of the Totonac country behind Veracruz, drunk with chocolate in Mexico and Madrid. |
| `allspice` Allspice | **only Caribbean & the Spanish Main** | Port Royal | Jamaica pimento, tasting of clove, cinnamon and nutmeg at once; the island was its only source. |
| `emeralds` Emeralds | **only Caribbean & the Spanish Main** | Cartagena | Muzo emeralds of New Granada, greener than anything the old world had cut. |
| `tortoiseshell` Tortoiseshell | Caribbean & the Spanish Main · Japan & the Ryukyus · Southeast Asia | Cebu, Manila, Naha, Tidore | Hawksbill shell from the Ryukyus, the Visayas and the Caribbean, worked into combs and inlay. |
| `cacao` Cacao | Caribbean & the Spanish Main · Pacific Americas · South America, Atlantic Coast | Acapulco, Belem, Callao, Cartagena, Cumana, Panama City, Portobelo, Santo Domingo … (9 in all) | Soconusco, Guayaquil and the Venezuelan coast; drunk in New Spain long before the Spanish court took it up. |
| `rum` Rum | **only Caribbean & the Spanish Main** | Bridgetown, Port Royal | The kill-devil spirit of the Barbados cane mills, aged into currency in every buccaneer port. |
| `cassava` Cassava Flour | Caribbean & the Spanish Main · South America, Atlantic Coast · West Africa | Luanda, Recife, Rio de Janeiro, Salvador | Farinha de guerra, the toasted root flour that provisioned every Brazil and Angola voyage. |
| `molasses` Molasses | Atlantic Isles · Caribbean & the Spanish Main · South America, Atlantic Coast | Bridgetown, Recife, Salvador | The mill syrup left when sugar is struck; sold cheap, and the seed of every rum still. |
| `cochineal` Cochineal | Caribbean & the Spanish Main · Pacific Americas | **Seville**, Veracruz | The dried insect of Oaxaca, worth more by weight than most spices and second only to silver in New Spain's exports. |
| `logwood` Logwood | **only Caribbean & the Spanish Main** | Port Royal, Veracruz, Willemstad | Campeche and the Yucatan lagoons; a black and purple dyewood that later drew English cutters and buccaneers. |
| `annatto` Annatto | Caribbean & the Spanish Main · South America, Atlantic Coast | Belem, Paramaribo | The orange seed paste of the Amazon and the Main, sold to dyers and Dutch cheese makers alike. |
| `sarsaparilla` Sarsaparilla | **only Caribbean & the Spanish Main** | Cartagena, Portobelo, Veracruz | The Honduras root sworn by half of Europe to cure the pox; apothecaries paid whatever was asked. |
| `copal` Copal | Caribbean & the Spanish Main · East Africa & the Horn | Zanzibar | Incense and varnish resin, dug fossil on the Swahili coast and tapped fresh in New Spain. |
| `peru-balsam` Balsam of Peru | Caribbean & the Spanish Main · Pacific Americas | Acapulco | The dark healing balsam of the Guatemalan coast, shipped through New Spain under a misleading name. |
| `jalap` Jalap | **only Caribbean & the Spanish Main** | Veracruz | The purging root of the Veracruz hills, a New World drug every European apothecary stocked. |
| `guaiacum` Guaiacum | **only Caribbean & the Spanish Main** | Havana, Santo Domingo | The iron-heavy holy wood of Hispaniola, sold as a pox cure and turned into blocks and mortars. |
| `cedar` Cedar Timber | Caribbean & the Spanish Main · Levant & Egypt · North America, Atlantic Coast | Beirut, Havana, St. George's | Bermuda cedar built the fastest small hulls afloat; Lebanon’s groves were already legend. |

### North America, Atlantic Coast

*7 ports — 0 capital, 5 mid, 2 small. 4 goods have their origin here.*

| good | origin | ports that sell it | why here |
|---|---|---|---|
| `sassafras` Sassafras | **only North America, Atlantic Coast** | Jamestown, St. Augustine | The ague-tree bark of Virginia and Florida, the first paying cargo the English colonies ever found. |
| `sealskins` Sealskins | North America, Atlantic Coast · Oceania & the Far Pacific · Scandinavia & the Arctic | Nuuk, Sydney, Torshavn | Oiled skins of the northern hunt, waterproof before anything else was. |
| `naval-timber` Masts & Spars | Baltic & the Hanse · North America, Atlantic Coast · Scandinavia & the Arctic · Western Mediterranean | Boston, Gdansk, New York, **Portsmouth**, Quebec City, Riga, Stockholm, Toulon | Riga and Norwegian mast pine, and later New England white pine; a strategic good every navy competed for. |
| `cedar` Cedar Timber | Caribbean & the Spanish Main · Levant & Egypt · North America, Atlantic Coast | Beirut, Havana, St. George's | Bermuda cedar built the fastest small hulls afloat; Lebanon’s groves were already legend. |

### South America, Atlantic Coast

*7 ports — 1 capital, 3 mid, 3 small. 7 goods have their origin here.*

| good | origin | ports that sell it | why here |
|---|---|---|---|
| `ginger` Ginger | Caribbean & the Spanish Main · Eastern India, Ceylon & Burma · South America, Atlantic Coast · Western India | Kannur, Kochi, Kozhikode, Salvador, San Juan, Santo Domingo | Malabar and Bengal, and from the 1520s a transplanted crop on Hispaniola and Jamaica. |
| `parrots` Parrots & Monkeys | South America, Atlantic Coast · West Africa | Belem | Live curiosities of Brazil and Guinea; a talking bird paid a sailor better than his wages. |
| `cacao` Cacao | Caribbean & the Spanish Main · Pacific Americas · South America, Atlantic Coast | Acapulco, Belem, Callao, Cartagena, Cumana, Panama City, Portobelo, Santo Domingo … (9 in all) | Soconusco, Guayaquil and the Venezuelan coast; drunk in New Spain long before the Spanish court took it up. |
| `cassava` Cassava Flour | Caribbean & the Spanish Main · South America, Atlantic Coast · West Africa | Luanda, Recife, Rio de Janeiro, Salvador | Farinha de guerra, the toasted root flour that provisioned every Brazil and Angola voyage. |
| `molasses` Molasses | Atlantic Isles · Caribbean & the Spanish Main · South America, Atlantic Coast | Bridgetown, Recife, Salvador | The mill syrup left when sugar is struck; sold cheap, and the seed of every rum still. |
| `brazilwood` Brazilwood | **only South America, Atlantic Coast** | Recife, Rio de Janeiro, Salvador, Santos | The red dyewood that named Brazil, cut along the coast the Portuguese found it on. |
| `annatto` Annatto | Caribbean & the Spanish Main · South America, Atlantic Coast | Belem, Paramaribo | The orange seed paste of the Amazon and the Main, sold to dyers and Dutch cheese makers alike. |

### Pacific Americas

*4 ports — 1 capital, 2 mid, 1 small. 6 goods have their origin here.*

| good | origin | ports that sell it | why here |
|---|---|---|---|
| `quicksilver` Quicksilver | Adriatic & Ionian · Iberia · Pacific Americas | Callao, Seville | Mercury of Almaden, Idria and Huancavelica; without it no silver amalgam, so crowns fought over every flask. |
| `cacao` Cacao | Caribbean & the Spanish Main · Pacific Americas · South America, Atlantic Coast | Acapulco, Belem, Callao, Cartagena, Cumana, Panama City, Portobelo, Santo Domingo … (9 in all) | Soconusco, Guayaquil and the Venezuelan coast; drunk in New Spain long before the Spanish court took it up. |
| `cochineal` Cochineal | Caribbean & the Spanish Main · Pacific Americas | **Seville**, Veracruz | The dried insect of Oaxaca, worth more by weight than most spices and second only to silver in New Spain's exports. |
| `cinchona-bark` Jesuit’s Bark | **only Pacific Americas** | Callao | The fever bark of the Peruvian montana, carried to Rome by the Jesuits from the 1630s. |
| `peru-balsam` Balsam of Peru | Caribbean & the Spanish Main · Pacific Americas | Acapulco | The dark healing balsam of the Guatemalan coast, shipped through New Spain under a misleading name. |
| `vicuna-wool` Vicuña Wool | **only Pacific Americas** | Callao | The finest fleece in the world, combed from wild Andean vicuña and reserved once for the Inca. |

### Oceania & the Far Pacific

*5 ports — 0 capital, 0 mid, 5 small. 7 goods have their origin here.*

| good | origin | ports that sell it | why here |
|---|---|---|---|
| `barkcloth` Barkcloth | **only Oceania & the Far Pacific** | Dili, Honolulu | Beaten bark tapa of the Pacific islands, patterned and traded from canoe to canoe. |
| `paradise-plumes` Bird-of-Paradise Plumes | Oceania & the Far Pacific · Southeast Asia | Banda Neira, Ternate | Legless skins from the Aru islands, sold in Europe as birds that lived their whole lives on the wing. |
| `sago` Sago | Oceania & the Far Pacific · Southeast Asia | Ambon, Banda Neira, Makassar, Ternate | Palm-pith flour of the eastern islands, the bread of the spice country. |
| `sharks-fin` Shark Fin | China Coast · Japan & the Ryukyus · Oceania & the Far Pacific · Southeast Asia | Kupang, Ternate | Dried fins from the eastern seas, bound for the Chinese banquet trade. |
| `trepang` Trepang | Oceania & the Far Pacific · Southeast Asia | Dili, Kupang, Makassar | Smoked sea cucumber of the Makassar praus, fished as far as the dry south land for Chinese kitchens. |
| `sandalwood` Sandalwood | Oceania & the Far Pacific · Southeast Asia · Western India | Banda Aceh, Banten, Dili, Hoi An, Honolulu, Kozhikode, Kupang, Makassar … (10 in all) | The fragrant heartwood of Timor and the lesser Sundas, burned in Chinese temples and carved for the gods. |
| `sealskins` Sealskins | North America, Atlantic Coast · Oceania & the Far Pacific · Scandinavia & the Arctic | Nuuk, Sydney, Torshavn | Oiled skins of the northern hunt, waterproof before anything else was. |

## B. THE BROAD GOODS — the ones that belong to no single place

The owner named both classes in one sentence: *"rice — was a main food in eastern asia and
india"* is broad; *"haggis … is only in scotland, unique"* is singular. This is the broad half.
These 38 goods carry five or more origin regions, and the design must not pretend otherwise: a
world where salt comes from one coast is not a world where a salt voyage means anything.

| good | regions of origin | ports | one line |
|---|---:|---:|---|
| `salt` Salt | 21 — Adriatic & Ionian, Aegean, Anatolia & Black Sea, Arabia & the Gulf, Atlantic Isles, Baltic & the Hanse, British Isles, Caribbean & the Spanish Main, China Coast, East Africa & the Horn, Eastern India, Ceylon & Burma, France & the Low Countries, Iberia, Japan & the Ryukyus, Korea, Levant & Egypt, Maghreb, North America, Atlantic Coast, Oceania & the Far Pacific, West Africa, Western India, Western Mediterranean | 53 | Setubal, the Bay of Bourgneuf and the Punta de Araya pans; without it no fishery or long voyage was possible. |
| `hides` Hides | 20 — Adriatic & Ionian, Aegean, Anatolia & Black Sea, Arabia & the Gulf, Atlantic Isles, Baltic & the Hanse, British Isles, Caribbean & the Spanish Main, China Coast, East Africa & the Horn, Iberia, Japan & the Ryukyus, Korea, Levant & Egypt, Maghreb, North America, Atlantic Coast, Pacific Americas, South America, Atlantic Coast, Southeast Asia, West Africa, Western Mediterranean | 45 | Plata and Hispaniola cattle hides, Irish and Barbary skins; the raw side of every leather trade. |
| `timber` Timber | 17 — Aegean, Anatolia & Black Sea, Atlantic Isles, Baltic & the Hanse, British Isles, Caribbean & the Spanish Main, China Coast, East Africa & the Horn, Eastern India, Ceylon & Burma, France & the Low Countries, Iberia, Japan & the Ryukyus, Korea, North America, Atlantic Coast, Oceania & the Far Pacific, Scandinavia & the Arctic, South America, Atlantic Coast, Western India | 39 | Baltic oak and fir, wainscot and clapboard; the planking trade no shipyard could live without. |
| `dried-fish` Dried & Salt Fish | 16 — Arabia & the Gulf, Atlantic Isles, Baltic & the Hanse, British Isles, China Coast, East Africa & the Horn, France & the Low Countries, Iberia, Japan & the Ryukyus, Korea, North America, Atlantic Coast, Oceania & the Far Pacific, Scandinavia & the Arctic, Southeast Asia, Western India, Western Mediterranean | 50 | Newfoundland and Iceland cod and Norwegian stockfish; the protein that provisioned Catholic Europe and its ships. |
| `wheat` Wheat | 15 — Adriatic & Ionian, Aegean, Anatolia & Black Sea, Arabia & the Gulf, Atlantic Isles, Baltic & the Hanse, East Africa & the Horn, France & the Low Countries, Iberia, Korea, Levant & Egypt, Maghreb, North America, Atlantic Coast, Pacific Americas, South America, Atlantic Coast, Western Mediterranean | 37 | Sicilian and Egyptian wheat, and the Vistula grain fleets out of Gdansk; the great bulk trade of every sea. |
| `sugar` Sugar | 12 — Atlantic Isles, Caribbean & the Spanish Main, China Coast, East Africa & the Horn, Eastern India, Ceylon & Burma, Japan & the Ryukyus, Levant & Egypt, Maghreb, South America, Atlantic Coast, Southeast Asia, West Africa, Western Mediterranean | 32 | Madeira and Sao Tome first, then the Pernambuco and Bahia mills and, from the 1640s, Barbados. |
| `wax` Beeswax | 11 — Adriatic & Ionian, Baltic & the Hanse, Caribbean & the Spanish Main, East Africa & the Horn, Maghreb, Oceania & the Far Pacific, Pacific Americas, Scandinavia & the Arctic, South America, Atlantic Coast, Southeast Asia, West Africa | 19 | Baltic, Barbary and Guinea beeswax for church candles and seals; a steady cargo on every coast. |
| `silk-raw` Raw Silk | 9 — Adriatic & Ionian, Aegean, Anatolia & Black Sea, Arabia & the Gulf, China Coast, Eastern India, Ceylon & Burma, Iberia, Levant & Egypt, Southeast Asia, Western Mediterranean | 20 | Chinese and Persian filature silk; the Macau-Nagasaki run traded it for Japanese silver. |
| `wine` Wine | 9 — Adriatic & Ionian, Aegean, Anatolia & Black Sea, Atlantic Isles, East Africa & the Horn, France & the Low Countries, Iberia, Levant & Egypt, Pacific Americas, Western Mediterranean | 35 | Bordeaux claret, Canary sack, Madeira and Cretan malmsey — the grape wines every northern fleet came south for. |
| `wool-cloth` Woollen Cloth | 8 — Adriatic & Ionian, Aegean, Anatolia & Black Sea, British Isles, France & the Low Countries, Iberia, Maghreb, Scandinavia & the Arctic, Western Mediterranean | 20 | England's broadcloth and kerseys, and Flemish and Florentine cloth, were Europe's chief export westward and east. |
| `cotton-cloth` Cotton Cloth | 8 — Atlantic Isles, East Africa & the Horn, Eastern India, Ceylon & Burma, Japan & the Ryukyus, Korea, West Africa, Western India, Western Mediterranean | 22 | Gujarati and Coromandel calicoes were the currency of the Indian Ocean, bought in India to buy spices elsewhere. |
| `silk-cloth` Silk Cloth | 8 — Adriatic & Ionian, Aegean, Anatolia & Black Sea, Arabia & the Gulf, China Coast, Iberia, Japan & the Ryukyus, Western India, Western Mediterranean | 12 | Chinese damasks and satins, Persian brocades, and the woven silks of Bursa, Valencia and Lucca. |
| `copper` Copper | 8 — Aegean, Anatolia & Black Sea, Arabia & the Gulf, Baltic & the Hanse, Japan & the Ryukyus, Maghreb, Pacific Americas, Scandinavia & the Arctic, West Africa | 15 | Swedish Falun and Hungarian copper in Europe; Japanese bar copper became a major VOC export good. |
| `iron` Iron | 8 — Baltic & the Hanse, British Isles, China Coast, Iberia, Japan & the Ryukyus, Korea, Scandinavia & the Arctic, West Africa | 12 | Biscayan and Swedish bar iron, and the trade iron bartered by the bundle on the African and American coasts. |
| `rice` Rice | 8 — China Coast, Eastern India, Ceylon & Burma, Iberia, Japan & the Ryukyus, Korea, Oceania & the Far Pacific, Southeast Asia, Western India | 32 | Bengal, Siam, Java and Kanara fed the rice-deficit ports of the Indian Ocean and the Moluccas. |
| `salted-beef` Salt Meat | 8 — Atlantic Isles, Baltic & the Hanse, British Isles, Caribbean & the Spanish Main, East Africa & the Horn, France & the Low Countries, North America, Atlantic Coast, South America, Atlantic Coast | 11 | Irish and Baltic barrelled beef and pork; also the hide-and-tallow cattle economy of the Plata and Hispaniola. |
| `dried-fruit` Raisins & Currants | 8 — Adriatic & Ionian, Aegean, Anatolia & Black Sea, Atlantic Isles, France & the Low Countries, Iberia, Levant & Egypt, Maghreb, Western Mediterranean | 13 | Malaga raisins, Ionian currants and the sun-dried vine fruit of the Aegean, shipped north by the shipload. |
| `wool-raw` Raw Wool | 8 — Adriatic & Ionian, Aegean, Anatolia & Black Sea, British Isles, Iberia, Maghreb, Oceania & the Far Pacific, Scandinavia & the Arctic, Western Mediterranean | 13 | Castilian merino shipped from Bilbao to Flanders, and English wool before the cloth trade absorbed it. |
| `gold` Gold | 7 — Caribbean & the Spanish Main, China Coast, East Africa & the Horn, Maghreb, Pacific Americas, Southeast Asia, West Africa | 22 | Akan gold through Elmina, Zimbabwean gold through Sofala, and New Granada placer gold through Cartagena. |
| `cotton-raw` Raw Cotton | 7 — Aegean, Anatolia & Black Sea, Caribbean & the Spanish Main, Eastern India, Ceylon & Burma, Levant & Egypt, Maghreb, South America, Atlantic Coast, Western India | 11 | Gujarat, western Anatolia, Cyprus and the Levant, spun in India and, increasingly, in Europe. |
| `whale-oil` Whale & Train Oil | 7 — British Isles, France & the Low Countries, Iberia, Korea, North America, Atlantic Coast, Scandinavia & the Arctic, South America, Atlantic Coast | 10 | Basque and later Dutch and English whaling off Spitsbergen; lamp oil, soap stock and cloth dressing. |
| `silver` Silver | 6 — Adriatic & Ionian, Caribbean & the Spanish Main, Japan & the Ryukyus, Korea, Pacific Americas, South America, Atlantic Coast | 17 | Potosi and Zacatecas fed Seville and, via the Manila galleon, China; Japan's Iwami mines fed the same demand. |
| `pearls` Pearls | 6 — Arabia & the Gulf, Caribbean & the Spanish Main, China Coast, Eastern India, Ceylon & Burma, Pacific Americas, Western India | 11 | The Gulf banks off Bahrain and Julfar, the Gulf of Mannar between India and Ceylon, and Venezuela's Cubagua. |
| `ambergris` Ambergris | 6 — Arabia & the Gulf, Atlantic Isles, East Africa & the Horn, North America, Atlantic Coast, Southeast Asia, Western India | 10 | Found washed up on Indian Ocean and Atlantic island shores; a fixative that made perfume scent last. |
| `paper` Paper | 6 — China Coast, France & the Low Countries, Iberia, Japan & the Ryukyus, Korea, Western Mediterranean | 9 | Ligurian reams, Chinese bamboo paper and Korean hanji; the clerks of the world never had enough. |
| `olive-oil` Olive Oil | 6 — Adriatic & Ionian, Aegean, Anatolia & Black Sea, Iberia, Levant & Egypt, Maghreb, Western Mediterranean | 24 | Andalusia, Apulia and the Levant; used as much for soap-making and cloth fulling as for food. |
| `tobacco` Tobacco | 6 — Aegean, Anatolia & Black Sea, Caribbean & the Spanish Main, Eastern India, Ceylon & Burma, Levant & Egypt, North America, Atlantic Coast, South America, Atlantic Coast | 13 | Virginia from 1614, Trinidad and the Orinoco earlier still, and Ottoman Latakia by the 17th century. |
| `indigo` Indigo | 6 — Arabia & the Gulf, Atlantic Isles, Caribbean & the Spanish Main, Eastern India, Ceylon & Burma, Southeast Asia, Western India | 13 | Gujarat's Sarkhej and Bengal indigo displaced European woad as the blue dye of the wool trade. |
| `horses` Horses | 6 — Arabia & the Gulf, Atlantic Isles, Japan & the Ryukyus, Korea, Levant & Egypt, Maghreb | 9 | Arabian, Persian and Barbary horses shipped from Hormuz and Aden to Goa and the Deccan; the Portuguese taxed the trade hard. |
| `hemp` Hemp & Cordage | 6 — Baltic & the Hanse, East Africa & the Horn, France & the Low Countries, Scandinavia & the Arctic, Western India, Western Mediterranean | 12 | Riga and Russian hemp for European rope-walks; the rigging of every fleet began as this fibre. |
| `chillies` Chillies | 5 — Caribbean & the Spanish Main, Pacific Americas, South America, Atlantic Coast, Southeast Asia, Western India | 5 | The New World pepper the Portuguese carried to Goa, where it conquered every kitchen in a generation. |
| `cheese` Cheese | 5 — Aegean, Anatolia & Black Sea, Atlantic Isles, British Isles, France & the Low Countries, Western Mediterranean | 6 | Holland's Edam and Gouda rounds kept at sea for months and provisioned fleets on every ocean route. |
| `coconuts` Coconuts & Copra | 5 — East Africa & the Horn, Eastern India, Ceylon & Burma, Oceania & the Far Pacific, Southeast Asia, Western India | 6 | Nut, oil and coir from the same palm; the Indian Ocean’s tree of everything. |
| `maize` Maize | 5 — Caribbean & the Spanish Main, North America, Atlantic Coast, Pacific Americas, South America, Atlantic Coast, West Africa | 4 | The Indian corn of the Americas, already feeding garrisons and slave ships on both shores. |
| `furs` Furs | 5 — Aegean, Anatolia & Black Sea, Baltic & the Hanse, Japan & the Ryukyus, North America, Atlantic Coast, Scandinavia & the Arctic | 19 | Canadian beaver through Tadoussac and the Hudson, and Russian sable and ermine through Arkhangelsk. |
| `tallow` Tallow | 5 — Baltic & the Hanse, Caribbean & the Spanish Main, Pacific Americas, Scandinavia & the Arctic, South America, Atlantic Coast | 3 | Rendered fat of the Russian and Plata herds; candles, soap and greased rigging all began here. |
| `baleen` Whalebone | 5 — British Isles, France & the Low Countries, Iberia, North America, Atlantic Coast, Scandinavia & the Arctic | 4 | The springy jaw plates of the Greenland whale: stays, whips and window panes of the north. |
| `flax` Flax & Sailcloth | 5 — Arabia & the Gulf, Baltic & the Hanse, France & the Low Countries, Levant & Egypt, Scandinavia & the Arctic | 4 | Baltic and Dutch flax woven into the canvas that every ocean-going ship carried in bolts as spare sail. |

## C. THE REGION-LOCKED GOODS — the "haggis is only in Scotland" class

**83 of 243 goods come from exactly one region.** **54 of 243 can be bought at exactly one port on earth.** Those 54 are the sharpest expression of the owner's rule: there is one harbour in the world that sells them, and if you want them you sail there.

| good | the one port | region | why it exists nowhere else |
|---|---|---|---|
| `mace` Mace | **Banda Neira** (mid) | Southeast Asia | The scarlet aril of the same Banda nutmeg fruit, scarcer than the nut itself and priced above it. |
| `long-pepper` Long Pepper | **Chittagong** (small) | Eastern India, Ceylon & Burma | The hotter catkin pepper of Bengal, sold beside the round Malabar berry since Roman times. |
| `grains-of-paradise` Grains of Paradise | **Accra** (small) | West Africa | The pungent seed of the Guinea coast that named the Grain Coast; a cheap stand-in for pepper. |
| `vanilla` Vanilla | **Veracruz** (capital) | Caribbean & the Spanish Main | The cured orchid pod of the Totonac country behind Veracruz, drunk with chocolate in Mexico and Madrid. |
| `allspice` Allspice | **Port Royal** (small) | Caribbean & the Spanish Main | Jamaica pimento, tasting of clove, cinnamon and nutmeg at once; the island was its only source. |
| `zedoary` Zedoary | **Galle** (small) | Eastern India, Ceylon & Burma | A bitter camphor-scented root of Ceylon and the Indies, sold to European apothecaries as a drug. |
| `muslin` Muslin | **Hooghly** (mid) | Eastern India, Ceylon & Burma | The gossamer cottons of Dhaka and the Bengal delta, the finest woven cloth of the period. |
| `tapestries` Tapestries | **Antwerp** (capital) | France & the Low Countries | Brussels and Oudenaarde hangings sold through Antwerp; a single suite could furnish a palace. |
| `quilts` Bengal Quilts | **Hooghly** (mid) | Eastern India, Ceylon & Burma | The embroidered colchas of Satgaon, stitched in silk on cotton; a Portuguese favourite from the first. |
| `fustian` Fustian | **Genoa** (capital) | Western Mediterranean | The cotton-linen workhorse cloth of Milan and Augsburg, shipped out through Genoa and the Elbe. |
| `wootz-steel` Wootz Steel | **Machilipatnam** (small) | Eastern India, Ceylon & Burma | The crucible steel cakes of the Deccan that Damascus smiths forged into watered blades. |
| `brassware` Brassware & Manillas | **Hamburg** (capital) | Baltic & the Hanse | Nuremberg and Aachen basins, kettles and manilla bracelets — the currency goods of the Guinea trade. |
| `armour` Armour | **Genoa** (capital) | Western Mediterranean | Milanese corslets and morions shipped through Genoa; a fading trade, but princes still paid. |
| `musk` Musk | **Macau** (capital) | China Coast | Himalayan and Chinese musk pods, carried down to Canton and Macau and sold by the ounce. |
| `rubies` Rubies | **Thanlyin** (small) | Eastern India, Ceylon & Burma | The stones of the Mogok mines above Pegu, carried out through the Burma ports sewn into clothing. |
| `emeralds` Emeralds | **Cartagena** (capital) | Caribbean & the Spanish Main | Muzo emeralds of New Granada, greener than anything the old world had cut. |
| `mastic` Mastic | **Izmir** (mid) | Aegean, Anatolia & Black Sea | The resin tears of Chios, chewed in the harems and guarded by the Ottomans on pain of death. |
| `clocks` Clocks & Instruments | **Hamburg** (capital) | Baltic & the Hanse | Nuremberg and Augsburg clockwork and Dutch instruments; the Jesuits opened Peking with such gifts. |
| `paintings` Paintings | **Antwerp** (capital) | France & the Low Countries | Antwerp's picture market sold devotional panels and landscapes by the crate, sight unseen. |
| `lapis-lazuli` Lapis Lazuli | **Hormuz** (mid) | Arabia & the Gulf | The blue stone of Badakhshan, ground in Europe into ultramarine dearer than gold leaf. |
| `turquoise` Turquoise | **Bandar Abbas** (mid) | Arabia & the Gulf | Nishapur turquoise of Persia, the sky-blue stone of daggers and turban jewels. |
| `martaban-jars` Martaban Jars | **Thanlyin** (small) | Eastern India, Ceylon & Burma | The great glazed storage jars of Martaban, prized from Japan to Arabia for keeping water sweet. |
| `sea-charts` Sea Charts & Globes | **Amsterdam** (capital) | France & the Low Countries | Waggoners, portolans and globes from the Low Countries presses; a good rutter was worth a cargo. |
| `theriac` Venice Treacle | **Venice** (capital) | Adriatic & Ionian | The sixty-ingredient cure-all compounded in public in Venice and faked everywhere else. |
| `parrots` Parrots & Monkeys | **Belem** (small) | South America, Atlantic Coast | Live curiosities of Brazil and Guinea; a talking bird paid a sailor better than his wages. |
| `gyrfalcons` Gyrfalcons | **Reykjavik** (small) | Scandinavia & the Arctic | White Iceland falcons, a trade so royal the Danish crown kept it to itself. |
| `birds-nests` Edible Birds’ Nests | **Makassar** (mid) | Southeast Asia | Swiftlet nests gathered from cliff caves for the soup kitchens of Canton; worth their weight in silver. |
| `palm-sugar` Palm Sugar | **Banten** (mid) | Southeast Asia | Jaggery boiled from palm sap, the everyday sweet of Bengal and the Indies. |
| `tamarind` Tamarind | **Mumbai** (mid) | Western India | The sour pod of India, packed in jars as ship’s physic and kitchen souring both. |
| `hazelnuts` Hazelnuts | **Trabzon** (small) | Aegean, Anatolia & Black Sea | The filbert groves of the Pontic shore behind Trebizond, shipped west since antiquity. |
| `pistachios` Pistachios | **Tripoli** (small) | Levant & Egypt | Aleppo and Persian pistachios, the banquet nut of the Ottoman and Safavid courts. |
| `lac` Lac & Shellac | **Thanlyin** (small) | Eastern India, Ceylon & Burma | The insect resin of Pegu and Bengal: scarlet dye, sealing wax and the polish on every cabinet. |
| `dragons-blood` Dragon’s Blood | **Aden** (mid) | Arabia & the Gulf | The red resin of Socotra’s dragon trees, sold as medicine, varnish and pigment. |
| `socotra-aloes` Socotrine Aloes | **Aden** (mid) | Arabia & the Gulf | Bitter aloe juice dried on Socotra, the purge in every ship surgeon’s chest. |
| `red-sanders` Red Sanders | **Chennai** (mid) | Eastern India, Ceylon & Burma | The Coromandel red wood, cousin to sappan, cut in the Palakonda hills for the dye vats. |
| `rattan` Rattan | **Surabaya** (small) | Southeast Asia | The climbing cane of the Indies: cables, baskets and chairs from one forest vine. |
| `chank-shells` Chank Shells | **Jaffna** (small) | Eastern India, Ceylon & Burma | The sacred conch of the Mannar banks, sawn into bangles for Bengal. |
| `cinchona-bark` Jesuit’s Bark | **Callao** (capital) | Pacific Americas | The fever bark of the Peruvian montana, carried to Rome by the Jesuits from the 1630s. |
| `ostrich-feathers` Ostrich Feathers | **Tripoli** (small) | Maghreb | Saharan plumes carried to the coast by caravan, nodding on every helmet and hat in Europe. |
| `narwhal-horn` Narwhal Horn | **Nuuk** (small) | Scandinavia & the Arctic | The spiral tusk sold in Europe as unicorn horn, proof against poison and priced like a province. |
| `copal` Copal | **Zanzibar** (mid) | East Africa & the Horn | Incense and varnish resin, dug fossil on the Swahili coast and tapped fresh in New Spain. |
| `isinglass` Isinglass | **Arkhangelsk** (mid) | Scandinavia & the Arctic | Sturgeon bladder glue of the Volga fisheries, the finest clarifier and adhesive money could buy. |
| `morocco-leather` Morocco Leather | **Sale** (small) | Maghreb | Goatskin dressed soft and scarlet in Fez and Marrakesh; the binding of every fine library. |
| `peru-balsam` Balsam of Peru | **Acapulco** (mid) | Pacific Americas | The dark healing balsam of the Guatemalan coast, shipped through New Spain under a misleading name. |
| `jalap` Jalap | **Veracruz** (capital) | Caribbean & the Spanish Main | The purging root of the Veracruz hills, a New World drug every European apothecary stocked. |
| `vicuna-wool` Vicuña Wool | **Callao** (capital) | Pacific Americas | The finest fleece in the world, combed from wild Andean vicuña and reserved once for the Inca. |
| `verdigris` Verdigris | **Marseille** (capital) | Western Mediterranean | The green copper pigment of Montpellier, raised on wine lees and sold by the barrel. |
| `cobalt` Cobalt Blue | **Hormuz** (mid) | Arabia & the Gulf | The Persian ore behind Mohammedan blue; Jingdezhen’s best porcelain was painted with it. |
| `gamboge` Gamboge | **Ayutthaya** (mid) | Southeast Asia | The golden gum of the Cambodian forests, at once a pigment and a violent purge. |
| `safflower` Safflower | **Alexandria** (capital) | Levant & Egypt | The rouge and dye thistle of Egypt and India, the poor man’s saffron. |
| `catechu` Catechu | **Mumbai** (mid) | Western India | Cutch, the dark tanning extract of Pegu and India, boiled from heartwood and sold in cakes. |
| `spikenard` Spikenard | **Hooghly** (mid) | Eastern India, Ceylon & Burma | The aromatic root of the high Himalaya, carried down the Ganges as it had been since Rome. |
| `mecca-balsam` Balm of Mecca | **Jeddah** (mid) | Arabia & the Gulf | The true balsam of the Hejaz gardens, so scarce that most of what sold under the name was not it. |
| `hops` Hops | **Lubeck** (capital) | Baltic & the Hanse | The bitter cone that turned ale into beer; grown in Brabant and the Elbe country, sold by the sack. |

The remaining 46 single-region goods are sold at two or more ports **within that one region** — Moluccan cloves at six ports of the archipelago (Ambon, Ternate, Tidore, Makassar, Malacca, Batavia); Caribbean rum at Bridgetown and Port Royal. Region-locked, not port-locked.

## D. THE ENTREPOT REGISTER — the 47 offers that are NOT native, and why each one stands

47 of the world's 1,288 offers sit at a port outside the good's own origin regions. Each is written by hand into that good's `entrepots` list in `data/goods.json`, carried into `public.goods.entrepot_ports`, and defended below. A seeded hash can invent an offer; it cannot write a row here.

| good | entrepot port(s) | the trade |
|---|---|---|
| `black-pepper` Black Pepper | Aden (mid), Alexandria (capital), Amsterdam (capital), Antwerp (capital), Hormuz (mid), Istanbul (capital), Jeddah (mid), Lisbon (capital) | **The pepper route, both halves of it.** Malabar and Sumatran pepper reached Europe two ways, and neither of them grew a peppercorn on the way: up the Red Sea and the Gulf through Aden, Jeddah and Hormuz to Cairo, Alexandria and Istanbul — the road the Ottomans taxed — and, from 1501, round the Cape into Lisbon and out again through Antwerp and Amsterdam. The good's own note calls it "the bulk cargo that paid for the Carreira da India". |
| `cinnamon` Cinnamon | Kochi (capital), Lisbon (capital), Old Goa (capital) | **The Portuguese peel monopoly.** True cinnamon grows only in Ceylon's western lowlands. It was carried up the Malabar coast to Cochin and Goa and home to Lisbon; Cochin and Goa are the two ports the Estado weighed and sealed it at. |
| `wool-cloth` Woollen Cloth | Hamburg (capital) | **The Merchant Adventurers' cloth staple.** English broadcloth left London undyed for a continental staple town; when Antwerp fell in 1585 the staple moved to Hamburg, which wove none of it. |
| `cotton-cloth` Cotton Cloth | Jeddah (mid) | **The Hajj trade.** Jeddah is the pilgrim port; Gujarati and Coromandel cloth arrived there by the shipload and was sold to pilgrims from three continents. Arabia wove none of it. |
| `silk-cloth` Silk Cloth | Acapulco (mid), Manila (capital) | **The Manila galleon.** Chinese damasks and satins crossed to Manila, and from Manila to Acapulco, in exchange for American silver. Neither city held a loom. |
| `silk-raw` Raw Silk | Fukuoka (mid), Hirado (mid) | **Chinese raw silk landing in Japan.** Hirado and Fukuoka took the Chinese and Portuguese silk that Japan's own filature could not supply; Hirado held the Dutch and English factories that traded it. |
| `ramie-cloth` Ramie Cloth | Tsushima (small) | **The Waegwan.** Tsushima's So clan held the sole licence for Japan's trade with Joseon Korea, and Korean ramie (mosi) was one of the two goods that licence was worth having for. The island grew none of it — it could not even feed itself. |
| `silver` Silver | Cadiz (capital), Macau (capital), Manila (capital), Seville (capital) | **The two bullion routes.** Potosi and Zacatecas silver came home through Cadiz and Seville under the Casa de Contratacion's monopoly; the other stream crossed the Pacific to Manila and went up to Macau to buy Chinese silk. Andalusia has no silver mine and neither has the Pearl River. |
| `porcelain` Porcelain | Acapulco (mid), Lisbon (capital), Old Goa (capital) | **Kraak ware, westward and eastward.** Jingdezhen blue-and-white left through Canton and Macau; Goa and Lisbon sold it to Europe, and Acapulco to New Spain. Portugal fired none of it and would not for two centuries. |
| `diamonds` Diamonds | Antwerp (capital) | **The cutting trade.** Golconda stones were rough when they left India. Antwerp cut and set them — the good's own note says so — which is why Antwerp sells diamonds and mines none. |
| `ivory` Ivory | Lisbon (capital) | **Carved in Lisbon.** The good's own note names the workshops: Guinea and Kongo tusks came up the Atlantic and were worked in Lisbon, Dieppe and Gujarat. |
| `sugar` Sugar | Antwerp (capital), Lisbon (capital), Nantes (mid) | **The refineries.** Madeira, Sao Tome and Brazil grew the cane; Lisbon, Antwerp and Nantes boiled and clayed it. A refining town sells sugar and grows none. |
| `coffee` Coffee | Alexandria (capital), Marseille (capital) | **Mocha, up the Red Sea and across the Levant.** Yemen was coffee's only source until the 18th century. It reached Europe through Cairo and Alexandria, and Marseille was the port that landed it there — France's Levant gateway under the 1536 capitulations. |
| `indigo` Indigo | Bordeaux (capital), Seville (capital) | **Two colonial indigos, two staple ports.** Guatemalan anil came home to Seville with the Indies fleet; Antillean indigo came up the Gironde to Bordeaux. Neither Andalusia nor Aquitaine grows the plant. |
| `cochineal` Cochineal | Seville (capital) | **Second only to silver in New Spain's exports** — and it left New Spain. Seville held the Crown monopoly on the Indies trade and sold Oaxacan cochineal to every dyer in Europe. |
| `alum` Alum | Bruges (small) | **The alum staple.** Tolfa and Phocaea alum was shipped north to the Flemish dye vats, and Bruges was the staple where it was weighed. Flanders has no alum rock. |
| `furs` Furs | La Rochelle (mid), Saint-Malo (mid) | **The Canada trade.** Saint-Malo and La Rochelle fitted out the Saint Lawrence voyages and landed the beaver that became a London or Rouen hat. Nothing is trapped in Brittany or Aunis. |
| `cotton-raw` Raw Cotton | Marseille (capital) | **The Levant trade's chief import.** Marseille's ships came home from Smyrna and Sidon full of Anatolian and Syrian cotton for the fustian looms inland. |
| `wool-raw` Raw Wool | Calais (small) | **The Calais Staple**, one of the most literal entrepots in this file: by statute, English wool for the continent had to be landed and taxed at Calais, which grazes none of it. |
| `sandalwood` Sandalwood | Nagasaki (capital) | **Timor sandalwood, bound for the temple.** It went up through Macau and Batavia to Nagasaki, where it was burned as incense. Japan grows no sandal. |
| `ginseng` Ginseng | Tsushima (small) | **The other half of the Tsushima licence.** Korean mountain root was the highest-value good of the Joseon-Tsushima trade, sold on to Chinese physicians — the good's own note says exactly that. |
| `horses` Horses | Diu (small), Old Goa (capital) | **The Hormuz horse trade.** Arabian and Persian horses were shipped standing to Diu and Goa for the Deccan sultans' cavalry, and the Portuguese taxed the traffic hard — again, the good's own note. The Gujarat coast bred none of them. |
| `sappanwood` Sappanwood | Naha (mid) | **Ryukyu's re-export.** Naha bought Siamese sappanwood and sold it into China and Japan; it was the kingdom's stock in trade as a tribute middleman, and no dyewood grows on Okinawa. |
| `naval-timber` Masts & Spars | Portsmouth (mid) | **The King's Yard.** Riga and Norwegian mast pine was stockpiled at Portsmouth, the navy's arsenal. Hampshire grows oak, not mast pine. |
| `hemp` Hemp & Cordage | Portsmouth (mid) | **The King's Yard, again.** Every rope in the fleet began as Riga hemp landed and spun at Portsmouth's ropery. |

## E. WHAT MIGRATION 0058 BROKE, AND WHAT WAS DONE ABOUT IT

Migration `0058` (*a city offers what its size earns*) installed the owner's **count** law from
`docs/OWNER_REQUESTS.md` row 48 — *"capital cities - 10 items, mid sized cities - 4~8, small cities
4"* — and that law is correct. **It is kept.** `0062` does not retype the numbers; it calls
`public.roster_target_count`, which is still the one place they exist.

What `0058` also did was decide **which** goods, and it decided them with
`public.roster_rng(port_code || '|' || good_code)` — a seeded md5 rank. Deterministic, reproducible,
and historically blind. Its own receipt, in the deploy log:

```
0058: 78 offer(s) dropped, 56 offer(s) filled; total port_specialties 1310 -> 1288
```

Measured by diffing `data/ports.json` at commit `6991814` against its parent, all 134 pairs are
reconstructed below, port by port and good by good.

### E.1 — The three goods that fell out of the world entirely

This is the sharpest damage, and nothing red happened anywhere when it did.

| good | its only port before 0058 | what its own note says | now |
|---|---|---|---|
| `allspice` Allspice | **Port Royal**, Jamaica | *"Jamaica pimento … **the island was its only source**"* | **restored to Port Royal** |
| `pistachios` Pistachios | **Tripoli**, Syria | *"Aleppo and Persian pistachios"* — and Tripoli is Aleppo's port | **restored to Tripoli** |
| `lac` Lac | **Syriam** (Thanlyin), Pegu | *"The insect resin of Pegu and Bengal"* | **restored to Syriam** |

Before `0058`, all 243 goods had at least one producer. After it, 240 did. Allspice, pistachios and
lac stayed in the catalogue, stayed priced, stayed in the compendium, and were buyable **nowhere on
earth**. Migration `0062` asserts (d) that this can never happen again — every good must be carried
by at least one port, **and** by at least one port inside its own origin regions, so a good can never
survive only in re-export.

### E.2 — The 78 offers 0058 dropped (all of them from small harbours)

The count law is right: a small harbour carries exactly four. What `0058` got wrong was **which
four**, because the hash rank picked the casualty. Where the good it deleted was the port's most
defining trade, it is **restored** and a weaker one goes in its place; where the four that survived
were genuinely the four, the loss is **accepted** and said so.

**35 restored. 43 accepted.** Every one is named.

| port | region | the good 0058 deleted | the four it carries now | verdict |
|---|---|---|---|---|
| **Accra** | west-africa | `gold` — **back** | `gold` `ivory` `grains-of-paradise` `kola-nuts` | **Restored.** Accra stands on the Gold Coast. Cotton cloth — imported Indian and European stuff, not an Accra product — goes instead. |
| **Agadir** | maghreb | `sugar` — **back** | `sugar` `gold` `wax` `almonds` | **Restored.** The port's own note: the Saadians stormed it in 1541, "opening the Sous to their sugar trade". Copper, the weakest of the five, goes instead. |
| **Ancona** | adriatic-ionian | `olive-oil`  | `wool-cloth` `wax` `hides` `wheat` | Accepted. Ancona was a papal free port living on the Ragusa and Ottoman-Balkan transit — wool cloth, wax, hides, grain. Marche olive oil is real but was never what a ship called there for. |
| **Antalya** | aegean-anatolia | `timber` — **back** | `timber` `wheat` `carpets` `sponges` | **Restored.** The note: "outlet for Taurus cedar and pine". Camlets go instead — Angora mohair came down to Smyrna, not Antalya. |
| **Belem** | south-america-atlantic | `timber` — **back** | `cacao` `annatto` `parrots` `timber` | **Restored.** Amazon timber at the river mouth. Rice goes instead: it was not a 17th-century Amazon export, and the port sits outside rice's origin regions. |
| **Bridgetown** | caribbean | `cotton-raw`  | `sugar` `tobacco` `rum` `molasses` | Accepted. Barbados grew cotton before the 1640s, but the island the game models is the sugar island: cane, rum, molasses and the tobacco that preceded them. |
| **Bruges** | france-low-countries | `lace` — **back** | `wool-cloth` `linen` `alum` `lace` | **Restored.** Flemish bobbin lace, which lace's own note names. Gascon wine goes instead — Bruges landed it, it never made it, and by 1500 the Zwin was silting anyway. |
| **Calabar** | west-africa | `palm-oil` — **back** | `palm-oil` `ivory` `black-pepper` `camwood` | **Restored.** Calabar is the palm-oil river. Parrots go instead. |
| **Cape Coast** | west-africa | `ivory` — **back** | `gold` `ivory` `maize` `salt` | **Restored** — ivory back, and kola nuts out for maize, so the fort reads differently from Accra 130 km along the same shore: Kormantin corn provisioned every ship on that coast. |
| **Cebu** | southeast-asia | `abaca` — **back** | `gold` `abaca` `tortoiseshell` `mother-of-pearl` | **Restored.** Abaca is a Visayan fibre before it is a Manila export. Shark's fin goes instead. |
| **Chittagong** | eastern-india | `areca-nuts`  | `long-pepper` `rice` `sesame-oil` `rhino-horn` | Accepted. Betel nut was real here, but the four that stand — Bengal long pepper, rice, sesame oil and Arakanese rhino horn — are the Great Port of Bengal's own basket, and Colombo still sells areca. |
| **Cidade Velha** | atlantic-isles | `hides`  | `salt` `cotton-cloth` `orchil` `horses` | Accepted. Salt, panos cloth, orchil and horses ARE Cape Verde's four exports. Hides were the fifth. |
| **Cork** | british-isles | `butter` — **back** | `salted-beef` `butter` `hides` `wool-raw` | **Restored.** The port's own note reads "salt beef and butter". Cheese goes instead; Irish cheese was not a trade. |
| **Cumana** | caribbean | `annatto`  | `pearls` `salt` `cacao` `tobacco` | Accepted. Pearls, Araya salt, cacao and tobacco is exactly Cumana. Annatto was the fifth. |
| **Dili** | oceania | `rice`  | `sandalwood` `wax` `barkcloth` `trepang` | Accepted, and it improved the file: Timor imported its rice. Sandalwood, wax, barkcloth and trepang are what it sold. |
| **Diu** | western-india | `horses` — **back** | `cotton-cloth` `indigo` `silk-cloth` `horses` | **Restored.** The 1509 sea battle off Diu was about the horse trade; Gujarat imported Arabian horses through this fortress. Raw cotton goes instead — the port already sells the cloth. |
| **Famagusta** | levant | `salt` — **back** | `salt` `cotton-raw` `wine` `gold-thread` | **Restored.** The Venetian Cyprus salt lake. Sugar goes instead: Cypriot cane collapsed after the Ottoman conquest of 1571, which is the very siege this port's note describes. |
| **Feodosia** | aegean-anatolia | `wheat` — **back** | `wheat` `salt` `furs` `caviar` | **Restored.** Kaffa was the Black Sea grain port that fed Istanbul. Hides go instead. |
| **Fuzhou** | china-coast | `tea` — **back** | `tea` `lacquerware` `lychees` `sugar` | **Restored.** The Min river is the tea river. Cassia goes instead — it is a Guangxi and Tonkin bark. |
| **Galle** | eastern-india | `areca-nuts`  | `cinnamon` `zedoary` `ebony` `cowries` | Accepted. Cinnamon, zedoary, ebony and cowries are all named in their own notes as Ceylon goods; Colombo carries the areca. |
| **Goree** | west-africa | `ostrich-feathers`  | `ivory` `hides` `wax` `kola-nuts` | Accepted. The island's trade was hides, wax, ivory and kola. Ostrich feathers came down the Saharan roads to Barbary, not to Cape Verde. |
| **Hanoi** | southeast-asia | `rice`  | `silk-raw` `lacquerware` `cassia` `star-anise` | Accepted. Tonkin silk, lacquer, cassia and star anise is a perfect Red River basket; Tonkin ate its rice. |
| **Hong Kong** | china-coast | `salt` — **back** | `salt` `dried-fish` `pearls` `aloeswood` | **Restored** — and corrected. The note says "a salt and fishing district", so salt comes back. **Frankincense was also replaced with aloeswood**: the harbour is called fragrant after the Dongguan incense wood shipped from it, not after an Arabian resin it never saw. Porcelain goes. |
| **Honolulu** | oceania | `sandalwood` — **back** | `sandalwood` `salt` `barkcloth` `dried-fish` | **Restored.** Hawaiian sandalwood is the one thing these islands sold to the world. Coconuts go instead. |
| **Hoorn** | france-low-countries | `butter`  | `cheese` `herring` `baleen` `salted-beef` | Accepted. Hoorn was a cheese market, a herring town and a whaling port. Butter was the fifth. |
| **Jaffna** | eastern-india | `pearls` — **back** | `pearls` `chank-shells` `coconuts` `tobacco` | **Restored.** The note: "commanded the Palk Strait pearl and elephant trades". Coir goes instead — three Malabar ports already sell it. |
| **Kagoshima** | japan | `sulphur` — **back** | `sulphur` `sugar` `rice` `timber` | **Restored.** Satsuma's sulphur, from the volcanoes off its own coast. Silver goes instead: Japan's silver was Iwami's, in Chugoku, not Satsuma's. |
| **Kaliningrad** | baltic | `amber` — **back** | `amber` `rye` `honey` `linseed` | **Restored, and this is the worst single thing 0058 did.** The port's note: "ducal Prussian capital holding the Baltic amber monopoly". Amber's note: "worked at Konigsberg and Gdansk". A hash deleted amber from Konigsberg. Linen goes instead. |
| **Kannur** | western-india | `coir`  | `black-pepper` `ginger` `cardamom` `areca-nuts` | Accepted. Pepper, ginger, cardamom and areca is Cannanore. Coir survives at Cochin, Quilon and Jaffna. |
| **Karachi** | western-india | `cotton-cloth`  | `indigo` `shawls` `ghee` `asafoetida` | Accepted. Indigo, Kashmir shawls down the Indus, ghee and Persian asafoetida is a coherent Sind basket; Gujarat sells the cloth. |
| **Kilwa** | east-africa | `cotton-cloth`  | `gold` `ivory` `ambergris` `mangrove-poles` | Accepted. Sofala gold, ivory, ambergris and the mangrove poles of its own creeks. Mogadishu keeps the Benadir cloth. |
| **Kingston upon Hull** | british-isles | `barley`  | `wool-cloth` `herring` `coal` `lead` | Accepted. Hull exported cloth and lead and imported the Baltic; malting barley was the fifth. |
| **Kollam** | western-india | `ginger`  | `black-pepper` `coconuts` `hemp` `coir` | Accepted. Quilon is pepper, coconut and coir. |
| **Kupang** | oceania | `wax` — **back** | `sandalwood` `wax` `sharks-fin` `trepang` | **Restored.** Timor beeswax was a genuine export beside the sandalwood. Rice goes instead — Timor bought its rice from Java. |
| **Le Havre** | france-low-countries | `linen` — **back** | `linen` `wine` `salt` `felt-hats` | **Restored.** Norman linen, the toiles that made Rouen rich, shipped from the Seine mouth. Woollen cloth goes instead. |
| **Leith** | british-isles | `salt` — **back** | `salt` `coal` `herring` `barley` | **Restored.** The Forth salt pans stood beside the Forth coal pits and both fed the same ships. Scots wool goes instead; the export had all but ended by 1600. |
| **Machilipatnam** | eastern-india | `diamonds` — **back** | `chintz` `diamonds` `wootz-steel` `turmeric` | **Restored.** The note: "the outlet for Deccan diamonds". Tamarind goes instead. |
| **Malindi** | east-africa | `hides`  | `ivory` `ambergris` `hemp` `wheat` | Accepted. Ivory, ambergris, cordage fibre and highland grain. Hides were the fifth. |
| **Mangaluru** | western-india | `hemp`  | `rice` `black-pepper` `sandalwood` `teak` | Accepted. The note calls it a rice port; rice, pepper, Mysore sandal and teak is Kanara exactly. |
| **Massawa** | east-africa | `hides`  | `ivory` `gold` `civet` `salt` | Accepted. The Ethiopian highland trade — ivory, gold, civet — plus Danakil salt. A clean four. |
| **Messina** | western-mediterranean | `wine`  | `silk-raw` `dried-fruit` `citrus` `salt` | Accepted. Messina's own export was raw silk, and citrus, dried fruit and salt round it out. Faro wine was the fifth. |
| **Middelburg** | france-low-countries | `wool-cloth`  | `wine` `salt` `says-serges` `madder` | Accepted, and it is a good four: Zeeland was the wine staple, wove the says, grew the madder and refined the salt. |
| **Mogadishu** | east-africa | `myrrh`  | `cotton-cloth` `ivory` `frankincense` `civet` | Accepted. Maqdishi cloth, ivory, frankincense and civet. Myrrh survives at Aden, Mocha and Jeddah. |
| **Mokpo** | korea | `ramie-cloth` — **back** | `rice` `cotton-cloth` `ramie-cloth` `seaweed` | **Restored.** Jeolla is the ramie country; Hansan mosi is woven there still. Salt goes instead. |
| **Myeik** | eastern-india | `tin` — **back** | `tin` `sappanwood` `ivory` `timber` | **Restored.** Tenasserim tin. Rubies go instead — Mogok stones left through Pegu and Syriam, which is where this file keeps them. |
| **Nampo** | korea | `iron`  | `ginseng` `tiger-skins` `wheat` `hides` | Accepted. Ginseng, tiger skins, grain and hides is the Pyongyang hinterland; Joseon's iron came from Chungcheong, and Ulsan, Shimonoseki and Osaka still sell it. |
| **Nuuk** | scandinavia-arctic | `walrus-ivory` — **back** | `walrus-ivory` `whale-oil` `sealskins` `narwhal-horn` | **Restored.** Walrus ivory is the Greenland trade — the reason anyone sailed there at all. Furs go instead. |
| **Palma de Mallorca** | western-mediterranean | `wine`  | `olive-oil` `salt` `wool-cloth` `cheese` | Accepted. Mallorca sold oil, salt, cloth and cheese. Its wine was the fifth. |
| **Paramaribo** | south-america-atlantic | `logwood`  | `sugar` `tobacco` `annatto` `cotton-raw` | Accepted for logwood, which is a Campeche wood and not a Suriname one. **But cochineal was also replaced with annatto**: cochineal is Oaxacan, and Guiana annatto is the dye this coast actually sold. |
| **Pattani** | southeast-asia | `birds-nests`  | `black-pepper` `gold` `sappanwood` `rice` | Accepted. Pepper, Malay gold, sappanwood and rice. Birds' nests survive at Makassar. |
| **Port Royal** | caribbean | `allspice` — **back** | `sugar` `rum` `allspice` `logwood` | **Restored, and it had to be.** Jamaica pimento is allspice, and allspice's own note says "the island was its only source" — so 0058 did not merely thin a roster, it deleted a good from the world. Tortoiseshell goes instead. |
| **Pulicat** | eastern-india | `red-sanders`  | `cotton-cloth` `indigo` `chintz` `salt` | Accepted. Painted cloth, indigo and the Coromandel salt pans. Red sanders survives at Madras, cut in the same Palakonda hills. |
| **Reykjavik** | scandinavia-arctic | `wool-raw`  | `dried-fish` `sulphur` `gyrfalcons` `eiderdown` | Accepted. Stockfish, sulphur, gyrfalcons and eiderdown are the four most Icelandic things in the catalogue; raw wool was the fifth, and Torshavn still weaves the wadmal. |
| **Safi** | maghreb | `morocco-leather`  | `sugar` `copper` `honey` `wax` | Accepted. Sous sugar, copper, honey and wax. Sale keeps the Fez and Marrakesh leather. |
| **Saint-Louis** | west-africa | `gum-arabic` — **back** | `gum-arabic` `ivory` `hides` `wax` | **Restored.** The port's own note: "controlling the gum-arabic trade". Gold goes instead — Senegal's gold was a trickle beside Bambuk's. |
| **Sale** | maghreb | `dates`  | `hides` `wax` `wool-raw` `morocco-leather` | Accepted. The corsair republic sold hides, wax, wool and leather. Dates were the fifth. |
| **San Juan** | caribbean | `ginger` — **back** | `sugar` `ginger` `hides` `timber` | **Restored.** Puerto Rican ginger was a real 16th-century boom that briefly displaced the island's sugar. Cacao goes instead. |
| **Setubal** | iberia | `cork`  | `salt` `wine` `dried-fish` `olive-oil` | Accepted, and the four are perfect: the note says the Sado pans salted northern Europe's herring and cod. Cork went, and Lisbon still sells it. |
| **Shimonoseki** | japan | `seaweed`  | `rice` `dried-fish` `salt` `iron` | Accepted. Rice, fish, Setouchi salt and Chugoku tatara iron, at the funnel of the Inland Sea. Seaweed was the fifth. |
| **Soyo** | west-africa | `salt`  | `ivory` `raffia-cloth` `camwood` `copper` | Accepted. Kongo ivory, raffia, takula redwood and copper. Salt was the fifth. |
| **Split** | adriatic-ionian | `salt`  | `wool-cloth` `wax` `hides` `wine` | Accepted. The scala funnelled Ottoman caravan wax, hides and wool to Venice; that is what stands. |
| **St. George's** | north-america-atlantic | `salt`  | `tobacco` `ambergris` `cedar` `dried-fish` | Accepted. Cedar, ambergris, tobacco and fish is Bermuda in 1620. The Turks Islands salt rake belongs to the 1670s. |
| **Suakin** | east-africa | `senna`  | `gold` `ivory` `gum-arabic` `hides` | Accepted. Sudanese gum arabic, gold, ivory and hides. Senna survives at Mocha and Alexandria. |
| **Suez** | arabia-gulf | `black-pepper`  | `coffee` `wheat` `copper` `flax` | Accepted. Mocha coffee coming up the Red Sea is the better 17th-century fact, and it stands. Pepper survives at Aden, Jeddah and Hormuz. |
| **Surabaya** | southeast-asia | `sugar`  | `rice` `cubeb` `batik` `rattan` | Accepted. Rice, Javanese cubeb, batik and rattan. Java sugar survives at Batavia. |
| **Tangier** | maghreb | `wax`  | `hides` `wheat` `wool-raw` `honey` | Accepted. Hides, wool and grain. Wax was the fifth and Barbary wax survives at Agadir, Safi and Sale. |
| **Thanlyin** | eastern-india | `lac` — **back** | `rubies` `lac` `martaban-jars` `elephants` | **Restored, and it had to be.** Lac's note names "Pegu and Bengal", and Syriam was its only port — 0058 left lac buyable nowhere on earth. Teak goes instead; Cochin and Mangalore still cut it. |
| **Torshavn** | scandinavia-arctic | `wool-raw`  | `dried-fish` `wool-cloth` `sealskins` `eiderdown` | Accepted. The Faroes sold wadmal — woven cloth, which the port keeps — not raw wool. |
| **Trabzon** | aegean-anatolia | `carpets` — **back** | `silk-raw` `carpets` `copper` `hazelnuts` | **Restored.** Trebizond is the Tabriz caravan terminus, and Persian carpets came down that road with the silk. Timber goes instead. |
| **Tripoli** | levant | `pistachios` — **back** | `silk-raw` `soap` `gallnuts` `pistachios` | **Restored, and it had to be.** Pistachios' note names Aleppo, and Tripoli was Aleppo's port — 0058 left pistachios buyable nowhere on earth. Raw cotton goes instead. |
| **Tripoli** | maghreb | `dates`  | `henna` `ostrich-feathers` `gold` `hides` | Accepted. The Fezzan caravan brought gold, ostrich feathers, henna and hides to this quay. Dates were the fifth. |
| **Trondheim** | scandinavia-arctic | `copper` — **back** | `copper` `dried-fish` `timber` `whale-oil` | **Restored.** The port's own note: "outlet for Roros copper from 1644". Furs go instead. |
| **Tsushima** | japan | `ramie-cloth` — **back** | `ginseng` `ramie-cloth` `silver` `dried-fish` | **Restored, and it sharpens the island.** Tsushima existed to trade with Korea; ramie and ginseng are what the licence was for. **Rice goes instead** — Tsushima notoriously could not grow its own, which is the reason it needed the licence at all. |
| **Turku** | baltic | `timber` — **back** | `tar` `timber` `furs` `dried-fish` | **Restored.** Abo shipped Finnish deals as well as Finnish tar. Hemp goes instead. |
| **Ulsan** | korea | `dried-fish`  | `whale-oil` `salt` `iron` `rice` | Accepted. Whale oil (the Bangudae coast), salt, iron and rice. Dried fish was the fifth and every neighbour sells it. |
| **Valparaiso** | pacific-americas | `wax`  | `wheat` `wine` `hides` `copper` | Accepted, and the four are exactly the note: Chilean wheat north to Peru, plus wine, hides and copper. |
| **Visby** | baltic | `tar`  | `wax` `furs` `dried-fish` `timber` | Accepted. By 1500 Gotland lived on Baltic transit — wax, furs, fish and timber. Tar was the fifth, and Turku and Stockholm carry it. |
| **Willemstad** | caribbean | `salt` — **back** | `salt` `hides` `salted-beef` `logwood` | **Restored.** The port's own note: the Dutch "took Curacao in 1634 for its salt pans". Guaiacum goes instead; Havana keeps it. |

### E.3 — The 56 offers 0058 invented (all of them at capitals)

A capital carries ten. Where a capital's authored history did not run to ten, `0058` drew the balance
from the whole 243-good catalogue by hash — with no regard for region, culture or history. Tokyo got
five of its ten that way, and every one was wrong.

**48 replaced. 8 kept**, because a blind draw can land on a true fact, and deleting a true fact to
tidy the story would be its own dishonesty. Each of the 8 is named as KEPT below.

| capital | the good the hash chose | what it carries now | why |
|---|---|---|---|
| **Alexandria** | `salted-tuna` Salt Tuna | `coffee` Coffee | Mocha coffee came up the Red Sea and through Cairo; Alexandria was where Europe bought it. Straits tunny is an Andalusian and Barbary fishery. |
| **Amsterdam** | `ramie-cloth` Ramie Cloth | `whale-oil` Whale & Train Oil | Amsterdam ran the Spitsbergen fishery and the Greenland Company. Korean grasscloth never crossed the Zuiderzee. |
| **Antwerp** | `mastic` Mastic | `linen` Linen | Flemish linen, through the market that sold Flanders' cloth. Mastic grows only on Chios and was an Ottoman state monopoly. |
| **Barcelona** | `benzoin` Benzoin | `almonds` Almonds | Catalan and Valencian almonds. Benzoin is a Sumatran resin. |
| **Barcelona** | `cassava` Cassava Flour | `salt` Salt | Ibiza salt, shipped through Barcelona. Cassava is Brazilian farinha and was never a Catalan cargo. |
| **Bordeaux** | `sugar` Sugar | `timber` Timber | Aquitaine oak staves went down the Garonne with the wine they were made into casks for. |
| **Bordeaux** | `wootz-steel` Wootz Steel | `paper` Paper | Angoumois paper, floated down the Charente and Garonne — France's great paper export. Wootz is Deccan crucible steel. |
| **Busan** | `cowries` Cowrie Shells | `paper` Paper | Korean hanji, which paper's own note names, and which Joseon sent to Ming and Japan by the bale. |
| **Busan** | `fustian` Fustian | `ink-sticks` Ink & Brushes | Korean brushes and ink, the tools of every academy — again, the good's own note. Fustian is Milanese and Augsburg cloth. |
| **Cadiz** | `myrrh` Myrrh | `citrus` Lemons & Oranges | Andalusian citrus. Myrrh comes from Dhofar and the Somali coast. |
| **Cadiz** | `silver-plate` Silverware & Plate | *(unchanged)* | KEPT. The hash landed on a true fact: silver-plate's own note names "Augsburg workshops and Seville shops", and Cadiz was Seville's Atlantic outport. Deleting a true fact to tidy the story would be its own dishonesty. |
| **Callao** | `majolica` Majolica | `copper` Copper | Chilean copper came north to Lima. Majolica is Montelupo and Manises tin-glaze. |
| **Callao** | `mastic` Mastic | `tallow` Tallow | Andean tallow for the candle and soap trade, shipped up to Panama. Mastic, again, is Chios only. |
| **Cartagena** | `rosewater` Rosewater | `salt` Salt | The Guajira and Manaure pans on the same coast. Rosewater is distilled at Shiraz and Damascus. |
| **Copenhagen** | `camwood` Camwood | `hides` Hides | The Jutland ox trade — Denmark's great export, driven south on the hoof and shipped as hides. Camwood is a Guinea and Kongo dyewood. |
| **Gdansk** | `celadon` Celadon Ware | `naval-timber` Masts & Spars | Prussian oak wainscot and Vistula masts, which is what the Dutch came to Danzig for. Celadon is Sawankhalok and Korean ware. |
| **Genoa** | `mangrove-poles` Mangrove Poles | `olive-oil` Olive Oil | Ligurian oil, and Genoa was its market. Mangrove poles are cut in Swahili creeks to roof treeless Gulf towns. |
| **Guangzhou** | `ramie-cloth` Ramie Cloth | *(unchanged)* | KEPT. Canton grasscloth is a real Chinese export and china-coast is one of ramie's two origin regions, so the draw happened to land inside the law. |
| **Hamburg** | `muslin` Muslin | `copper` Copper | Hamburg was a copper market for Sweden and Hungary. Muslin is woven at Dhaka. |
| **Havana** | `brandy` Brandy | `wax` Beeswax | Cuban beeswax, shipped to Veracruz and Cartagena. Brandy is burnt wine of the Charente. |
| **Havana** | `guaiacum` Guaiacum | *(unchanged)* | KEPT. Guaiacum's own note names Hispaniola, and the Caribbean is its origin region. The draw landed inside the law. |
| **Istanbul** | `coir` Coir | `camlets` Camlets | Angora mohair camlets, sold in the capital that consumed them. Coir is coconut husk from Malabar. |
| **Istanbul** | `timber` Timber | *(unchanged)* | KEPT. Black Sea and Taurus timber built the Ottoman arsenal, and aegean-anatolia is one of timber's origin regions. |
| **Jakarta** | `chillies` Chillies | *(unchanged)* | KEPT. Chillies' own note has the Portuguese carrying them east, where they conquered every kitchen in a generation — the Indies included. |
| **Jakarta** | `herring` Herring | `indigo` Indigo | Java indigo, a genuine VOC export. North Sea herring in Batavia is the single most absurd thing the hash produced. |
| **Kochi** | `majolica` Majolica | `coconuts` Coconuts & Copra | Cochin sits in the coconut backwaters and already sells the coir made from the same husk. |
| **Kozhikode** | `linen` Linen | `teak` Teak | Malabar teak, which teak's own note names first. |
| **Kozhikode** | `pearls` Pearls | `areca-nuts` Areca Nuts | The Malabar betel trade, which areca's own note names beside Ceylon. |
| **Kozhikode** | `vicuna-wool` Vicuña Wool | `sandalwood` Sandalwood | Mysore sandal, carried down to the Malabar ports. Vicuna is combed from wild Andean herds and was reserved once for the Inca. |
| **Lisbon** | `opium` Opium | `cinnamon` Cinnamon | Ceylon cinnamon, the Carreira's own cargo. Malwa opium was taxed at Goa, which is where this file puts it. |
| **Lisbon** | `saffron` Saffron | `ivory` Ivory | Ivory's own note: "carved in Lisbon, Dieppe and Gujarat". |
| **London** | `cowries` Cowrie Shells | `coal` Sea Coal | Tyne coal into the Thames — the largest coastal trade in Europe. Cowries are Maldive shells. |
| **Lubeck** | `paintings` Paintings | `linen` Linen | Westphalian and Saxon linen through the Hanse's leading city. Antwerp's picture market is 700 miles away. |
| **Macau** | `ambergris` Ambergris | `rhubarb` Chinese Rhubarb | Chinese medicinal rhubarb, "dearer in Europe than cinnamon" by its own note, shipped out through Macau. |
| **Macau** | `grains-of-paradise` Grains of Paradise | `sugar` Sugar | Chinese sugar, which Macau carried to Japan. Grains of paradise named the Grain Coast of Guinea. |
| **Macau** | `paper` Paper | *(unchanged)* | KEPT. Chinese bamboo paper is named in paper's own note and china-coast is one of its origin regions. |
| **Malacca** | `cotton-raw` Raw Cotton | `camphor` Borneo Camphor | Barus camphor from Sumatra, whose outlet Malacca was. Raw cotton is a Gujarat and Anatolian crop. |
| **Malacca** | `emeralds` Emeralds | `benzoin` Benzoin | Sumatran and Siamese benzoin, burned as incense from Lisbon to Nagasaki. Emeralds are Muzo's, in New Granada. |
| **Malacca** | `ostrich-feathers` Ostrich Feathers | `gold` Gold | Malay and Sumatran gold. Ostrich plumes cross the Sahara by caravan. |
| **Manila** | `ivory` Ivory | *(unchanged)* | KEPT. The Hispano-Philippine ivories carved at Manila from Chinese-worked tusks are a real trade, and southeast-asia is one of ivory's origin regions. |
| **Marseille** | `tamarind` Tamarind | `cotton-raw` Raw Cotton | Levant cotton was the chief import of the Marseille ships. Tamarind is an Indian pod. |
| **Nagasaki** | `isinglass` Isinglass | `camphor` Borneo Camphor | Kyushu camphor, shipped to China and Europe. Isinglass is Volga sturgeon glue. |
| **Nagasaki** | `palm-sugar` Palm Sugar | `sulphur` Sulphur | Japanese volcanic sulphur, which sulphur's own note names. Palm jaggery is Bengali and Indies. |
| **Old Goa** | `star-anise` Star Anise | `opium` Opium | Opium's own note: "Malwa and Patna opium, already a staple of the Indian Ocean drug trade the Portuguese taxed at Goa". |
| **Osaka** | `sandalwood` Sandalwood | `salt` Salt | Setouchi salt, the Inland Sea trade that fed Osaka's market. Sandalwood grows on Timor. |
| **Salvador** | `chillies` Chillies | *(unchanged)* | KEPT. Brazilian malagueta is a New World pepper in a New World port, and south-america-atlantic is one of chillies' origin regions. |
| **Salvador** | `dried-fruit` Raisins & Currants | `molasses` Molasses | The mill syrup struck off in the Bahia engenhos. Dried fruit is Malaga raisins and Ionian currants. |
| **Seville** | `ginger` Ginger | `indigo` Indigo | Guatemalan anil, home with the Indies fleet under the Casa's monopoly. |
| **Surat** | `folding-fans` Folding Fans | `ghee` Ghee | Gujarati ghee, which ghee's own note names, "shipped in jars wherever Indian crews and kitchens went". Folding fans are made in Kyoto. |
| **Tokyo** | `caviar` Caviar | `soy-sauce` Soy Sauce | Choshi and Noda soy, brewed for Edo and casked into Edo Bay. Black Sea sturgeon roe is 5,000 miles away. |
| **Tokyo** | `gold-thread` Gold Thread | `salt` Salt | Gyotoku salt, made on Edo Bay for the city on it. Gilt-silver thread is Genoese and Cypriot. |
| **Tokyo** | `lychees` Dried Lychees | `seaweed` Dried Seaweed | Asakusa nori, laver from Edo Bay itself. Lychees are a Fujian orchard fruit. |
| **Tokyo** | `molasses` Molasses | `paper` Paper | Japanese washi. Molasses runs off a Caribbean sugar mill. |
| **Tokyo** | `sealskins` Sealskins | `sword-blades` Sword Blades | Sword blades' own note has Japanese blades "shipped to China by the thousand" — and Edo was the shogun's city. Sealskins are taken on Arctic ice. |
| **Venice** | `sassafras` Sassafras | `dried-fruit` Raisins & Currants | Ionian currants, which dried fruit's own note names, and which were Venice's own island crop. Sassafras is Virginian ague-bark. |
| **Veracruz** | `camphor` Borneo Camphor | `logwood` Logwood | Campeche logwood, shipped through Veracruz. Camphor crystallises at Barus and in Borneo. |

### E.4 — Six restorations where the port's OWN note names the good the hash deleted

These are called out separately because they are not judgement calls. In each case the file already
said, in prose, that this port traded this good — and the hash removed it anyway. Migration `0062`
asserts all six by name.

| port | good | the port's own `notes` field, verbatim |
|---|---|---|
| Kaliningrad (Konigsberg) | `amber` | *"Founded 1255 as Konigsberg; ducal Prussian capital **holding the Baltic amber monopoly**."* |
| Saint-Louis | `gum-arabic` | *"French post founded 1659 … **controlling the gum-arabic trade**."* |
| Trondheim | `copper` | *"Nidaros … and **outlet for Roros copper from 1644**."* |
| Willemstad | `salt` | *"Dutch West India Company took Curacao in 1634 **for its salt pans** …"* |
| Machilipatnam | `diamonds` | *"Golconda's port … and **as the outlet for Deccan diamonds**."* |
| Jaffna | `pearls` | *"…**commanded the Palk Strait pearl** and elephant trades."* |

Amber's own note is the other half of the Konigsberg one: *"The Samland coast of Prussia held a ducal
monopoly; **worked at Konigsberg and Gdansk**, sold as far as China."* Two sentences in two files said
the same thing and a hash overruled both.

---

## F. CULTURE MASKS — a built mechanism that was nearly dead

`public.goods.culture_mask` has existed since migration `0002` and is read in eleven places:
`cmd.do_buy` (0007:438), `cmd.do_sell` (0007:515), arrival (0007:1130), `world.goods` (0009:96), the
market's `available` flag (0009:135), 0014:264, 0017:522/600/874, 0019:744 and 0022:488. A port whose
culture is masked will not buy the good and will not sell it, and the compendium says so on the good's
own face.

It carried **six** goods, all alcohol. It now carries **seven**.

| good | masked from | why it is a REFUSAL and not a preference |
|---|---|---|
| `wine`, `beer`, `sake`, `rum`, `brandy`, `arrack` | `islamic`, `swahili` | Unchanged. Alcohol, and the ports of an Islamic culture. |
| **`salted-beef`** | **`indic`, `japanese`** | **New.** No Hindu or Jain port bought barrelled beef; Gujarat's merchant houses had slaughter itself restricted. Tokugawa Japan's prohibition on four-legged meat is a matter of edict, not taste. |

**What was deliberately NOT masked, and why.** Alcohol is not extended to `malay`, even though the
archipelago sultanates were Muslim, because arrack's own note names **Batavia** as its distillery and
the Dutch, Chinese and Portuguese communities there traded spirit openly. A mask that contradicted the
catalogue would be worse than no mask. Tobacco is not masked to `islamic` either: Murad IV's ban of
1633 was real, was widely ignored, and was lifted in 1646 — an interdiction that lasted thirteen years
inside a 150-year window is not a standing rule about a culture.

**The mask now bites, and 0062 proves it.** Assert (h) refuses to let a harbour **produce** a good its
own culture will not trade — a port cannot be the cheapest source of something it will not sell — and
requires every one of the seven masks to darken at least one real harbour.

**It found two live incoherences on its first run**, and they were not data errors:

```
0062 self-assert FAIL: 2 port(s) produce a good their own culture will not trade: FAM/wine, RHO/wine
```

Famagusta and Rhodes were carrying `islamic`, inherited from their region, and selling wine.
`scripts/lib/world-derive.mjs` already overrides two Latin-ruled Greek islands whose vineyards
outlived the Ottoman conquest — `heraklion: 'latin'` (*"Venetian Crete until 1669"*) and
`chios: 'latin'` (*"the Genoese Maona held the island until 1566"*). **Rhodes**, Hospitaller until
Suleiman took the fortress in 1522, and **Famagusta**, Venetian Cyprus until the siege of 1571, are
the same case and were simply missed. Completing the override is the fix. Deleting Commandaria from
Cyprus to satisfy a coarse culture token would have been weakening a true fact to green.

**Where the mask lives now.** It used to be a hand-typed table inside `scripts/lib/world-derive.mjs`
(`const ALCOHOL_MASK = ['islamic','swahili']`, six entries) — a second author for a fact about a good,
sitting in a build script rather than beside the good. `0062` deletes it there and reads
`cultureMask` from `data/goods.json`, so **one file now answers every geographic question about a
good**: where it comes from, who re-exports it, and who will not touch it.

---

## G. WHERE I COULD NOT DEFEND A PLACEMENT

The brief said to say so rather than invent one. Eight authored pairs — none of them `0058`'s doing —
could not be defended from real trade history and were replaced in kind. They are listed here so the
change is visible rather than buried in a diff.

| port | pair removed | replaced with | why the original could not stand |
|---|---|---|---|
| Zanzibar | `cloves` | `rhino-horn` | Zanzibar's clove plantations are an **1818** transplant from the Moluccas, two centuries after this game's window. Cloves' own note says "before transplantation". East African rhino horn to Asia through the Swahili ports is contemporary and documented. |
| Makassar | `coral` | `gold` | Red coral is fished off Sardinia and Barbary. Gowa's hinterland gold is a real Makassar export. |
| Ternate | `coral` | `sharks-fin` | Same. Moluccan reef fins for the Chinese trade are real. |
| Tidore | `coral` | `tortoiseshell` | Same. Hawksbill shell from the same reefs. |
| Hong Kong | `frankincense` | `aloeswood` | The port's own note says its name comes from the incense trade — but that incense is **Dongguan agarwood**, grown in Guangdong, not an Arabian resin the harbour never handled. `aloeswood` gained `china-coast` as an origin region for the same reason. |
| Paramaribo | `cochineal` | `annatto` | Cochineal is Oaxacan. Annatto's own note names "the Amazon and the Main", which is this coast. |
| Cartagena | `diamonds` | `sarsaparilla` | New Granada cut **emeralds**, which Cartagena already sells; it never had a diamond. Brazilian diamonds are a 1720s discovery. |
| Sydney | `furs` | `sealskins` | There were no fur trappers in New South Wales. There were Bass Strait sealing gangs. |

**Three ports sit outside the 1500–1650 window entirely** and their rosters are the thinnest evidence
in the file. Each says so in its own `notes` field already, and none of them is fabricated further:

* **Honolulu** — Cook's landfall is 1778. Its sandalwood, salt, tapa and fish are the Hawaiian trade
  of the 1790s–1820s, restored because the sandalwood trade is what these islands are known for.
* **Sydney** — Port Jackson is settled in 1788. Timber, wool, sealskins and fish.
* **Hagatna** — a Spanish mission from 1668 and a galleon watering stop before that. Guam has almost
  no documented export trade in this period; `hemp` was replaced with `salt` as the least speculative
  thing an island victualling station sells, and this sentence is the honest limit of that claim.

---

## H. WHAT THE CATALOGUE STILL LACKS — proposed, not silently added

`docs/OWNER_AUDIT.md` (merged 2026-08-26) re-checked all 48 owner instructions against the code. Two
of its findings land on this file, and both are answered here rather than left implied.

**Row 37 — *"1000 trade goods, by regions"* — was marked PARTLY TRUE, with the reason given as
"*by regions does not exist*".** That half is what this file and migration `0062` close: every one of
the 243 goods now names the regions it comes from, and the roster law refuses an offer that is
neither native nor a named entrepot. The other half — **the count is 243, not 1,000** — is untouched
and is not a thing to fix by padding. `docs/WORLD_DATA.md` records the arithmetic for why 243 rather
than a thousand, and a thousand goods against 224 ports would put four goods in every port that no
history could tell apart. If the owner wants the number raised, that is a decision about the world,
not a gap in this pass.

**Row 38 named a concrete miss: *"korean gochujang is not in the catalogue; Jeju carries horses,
dried abalone, dried fish, seaweed."*** That is correct, and Jeju's four are unchanged by this
migration — they are all genuinely Jeju (the Mongol horse pastures, the haenyeo abalone divers, the
fishery, the laver). What is missing is the good itself.

**These are proposed and deliberately NOT added in 0062.** Adding a good is not a roster edit: it
changes the catalogue count that `public.rarity_scale()` (0051) derives the whole rarity histogram
from, it adds a row to `public.port_goods` for **every one of 224 harbours** (+224 market rows per
good), and it has to displace an existing good from some port's roster because the count law is
exact. That is its own migration with its own measurement, and folding it into a file whose job is to
repair 0058 would be two changes wearing one number.

| proposed good | region | what it would be | what it would displace |
|---|---|---|---|
| **gochujang** — fermented chilli paste | `korea` | The owner's own example. Historically honest and dateable: chillies reach Korea via Japan in the late 16th century and the paste is recorded by the 17th, which sits inside this game's window. Would give Korea a good that is *only* Korean — the region currently has just `tiger-skins` in that class. | A Korean port's fourth slot — Mokpo's `seaweed` or Ulsan's `rice` are the weakest of their fours. |
| **doenjang / soybean paste** | `korea`, `japan`, `china-coast` | The broad-class counterpart, beside the `soy-sauce` already in the catalogue. | Nothing; it would be a mid-port addition. |
| **hanji paper** | — | **Already covered.** `paper` names Korean hanji in its own note and `korea` is in its origin. Busan now carries it. No new good needed. |

**Where Korea stands after this pass, for comparison:** 21 goods have `korea` in their origin, one of
them (`tiger-skins`) exclusively so, and Busan gained `paper` and `ink-sticks` in place of two of
0058's hash picks (Maldive cowries and Milanese fustian). Korea is no longer thin — but it has one
region-locked good where Southeast Asia has eleven and Eastern India twelve, and gochujang is the
obvious second.

---

## I. HOW TO ADD A GOOD, OR CHANGE WHAT A PORT SELLS

Four steps, in this order, or the build goes red — which is the point.

1. **Give the good its geography.** In `data/goods.json`, set `origin` to every region that genuinely
   produced it. Never empty. If you cannot name one from a source, you cannot add the good.
2. **Put it on a port.** In `data/ports.json`, add the good to a port whose `region` is in that
   `origin` list. The port's count must still satisfy `0058`'s law — capital 10, mid 4–8, small 4 — so
   something else comes off.
3. **If the port is NOT in an origin region**, you are claiming a re-export. Add the port's id to the
   good's `entrepots` list **and write the trade into §D of this file.** Both, or neither.
4. **Write a migration.** `data/*.json` is the authorship; the database is the world. Nothing is real
   until a migration carries it, and `scripts/db/world-guard.mjs` fails every `npm run db:apply` while
   the two disagree.

**What will stop you if you skip a step**, all of it machine-checked:

| you did this | what goes red |
|---|---|
| added an offer that is neither native nor an entrepot | `0062` self-assert **(c)**, naming the pair |
| left a good with no origin region | `0062` self-assert **(b)** |
| named a region or port that does not exist | `0062` self-assert **(b)**, and `deriveWorld()` throws by name before that |
| listed an entrepot port that already sits in the good's origin | `0062` self-assert **(b)** — an entrepot is by definition elsewhere |
| listed an entrepot port that does not actually offer the good | `0062` self-assert **(b)** — a claim nobody checks is not a claim |
| dropped a good's last producer | `0062` self-assert **(d)** — the `allspice` failure, made impossible |
| left a good buyable only in re-export | `0062` self-assert **(d)** |
| broke the 10 / 4–8 / 4 count | `0062` self-assert **(e)**, which calls `0058`'s own function |
| let a port produce what its culture refuses | `0062` self-assert **(h)** |
| edited `data/*.json` without a migration | `world-guard`, on every apply, in both directions |

**Every figure in this file is migration `0062`'s own receipt**, not a number typed here and left to
rot. Re-read it any time with `npm run db:apply` — the last line of 0062's block prints the offer
count, the native/entrepot split, the single-region and broad counts, the mask count and how many of
0058's hash picks survive. If a figure here ever disagrees with that line, the receipt is right.
