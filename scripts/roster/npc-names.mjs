// ═══════════════════════════════════════════════════════════════════════════════════════════════
// npc-names.mjs — the per-NATION naming habit a merchant company is composed from (0105).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// WHY THIS IS NOT data/npc-houses.json. 26 companies can be authored by hand and 760 cannot:
// docs/NPC_FLEET_SCALE.md §2 says so, and 20,000 lines of invented names nobody could check would
// be the opposite of authorship. What IS authored here is the HABIT — how a Portuguese house, a
// Hanseatic Kontor and an Osaka donya each name themselves — over family and given-name pools a
// reader can check against the period. The PLACE element is not authored at all: it is read off
// public.ports by the generator, so a company is named for a coast the world actually has.
//
// `patterns` take {family} or {place}. A company's name, its master and its hulls are all drawn
// from these pools by a hash of (nation, index) — never Math.random() — so the same chain builds
// the same roster twice.
//
// `ink` is the chart's palette key, and public.npc_houses constrains it to eight values
// (0097:115). The sixteen nations 0098 already uses keep exactly the ink 0098 gave them
// (data/npc-houses.json "inks"), so no coast changes colour between two migrations; the four
// nations 0105 founds for the first time — Poland-Lithuania, Sweden, Muscovy, Morocco — are placed
// by their sea: the Baltic with the Hanse, Morocco with the other Mediterranean Islamic houses.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** Chart ink per nation. The sixteen 0098 already founded keep 0098's own choice. */
export const INK = {
  PRT: 'prt', ESP: 'esp', NLD: 'nld', ENG: 'eng', FRA: 'eng', DNK: 'eng',
  HAN: 'han', GEN: 'ita', VEN: 'ita', OTT: 'ott', MUG: 'ott', PER: 'ott',
  MNG: 'east', JPN: 'east', JOS: 'east', AYU: 'east',
  // new in 0105
  POL: 'han', SWE: 'han', RUS: 'han', MAR: 'ott',
}

export const NATIONS = {
  PRT: {
    patterns: ['Casa de {family}', 'Companhia de {place}', 'Casa {family} & Filhos', 'Armação de {place}', 'Sociedade {family}'],
    titles: ['Capitão', 'Mestre', 'Feitor', 'Senhor'],
    given: ['Afonso', 'Álvaro', 'André', 'Antão', 'Bartolomeu', 'Diogo', 'Duarte', 'Estêvão', 'Fernão', 'Francisco', 'Gaspar', 'Gil', 'Gonçalo', 'Henrique', 'Jorge', 'Lourenço', 'Manuel', 'Martim', 'Nuno', 'Pedro', 'Rui', 'Simão', 'Tristão', 'Vasco'],
    family: ['Albuquerque', 'Almeida', 'Andrade', 'Barbosa', 'Barreto', 'Botelho', 'Braga', 'Cabral', 'Caldeira', 'Carvalho', 'Coelho', 'Correia', 'Costa', 'Cunha', 'Esteves', 'Faria', 'Ferreira', 'Fonseca', 'Freitas', 'Gama', 'Godinho', 'Gonçalves', 'Guerreiro', 'Lobo', 'Lopes', 'Macedo', 'Magalhães', 'Marques', 'Mascarenhas', 'Matos', 'Melo', 'Mendes', 'Meneses', 'Moniz', 'Noronha', 'Nunes', 'Pacheco', 'Pereira', 'Pimentel', 'Pinto', 'Queirós', 'Resende', 'Ribeiro', 'Rocha', 'Sampaio', 'Sequeira', 'Silveira', 'Sousa', 'Teixeira', 'Valadares', 'Vasconcelos', 'Veloso', 'Zarco'],
    hulls: ['São Gabriel', 'São Rafael', 'São Miguel', 'São João', 'São Pedro', 'Santa Catarina', 'Santa Maria', 'Nossa Senhora da Graça', 'Bom Jesus', 'Espírito Santo', 'Flor do Mar', 'Conceição', 'Madre de Deus', 'São Bento', 'Santo André', 'Esperança', 'Garça', 'Botafogo', 'São Tomé', 'Chagas', 'Penha de França', 'Reis Magos', 'Santa Cruz', 'Berrio', 'Anunciada', 'São Jerónimo'],
  },
  ESP: {
    patterns: ['Casa de {family}', 'Compañía de {place}', 'Hermanos {family}', 'Casa {family} y Cía', 'Factoría de {place}'],
    titles: ['Don', 'Capitán', 'Maestre', 'Factor'],
    given: ['Alonso', 'Álvar', 'Andrés', 'Bartolomé', 'Cristóbal', 'Diego', 'Domingo', 'Fernando', 'Francisco', 'Gonzalo', 'Gregorio', 'Hernán', 'Íñigo', 'Jerónimo', 'Juan', 'Lope', 'Luis', 'Martín', 'Melchor', 'Nicolás', 'Pedro', 'Rodrigo', 'Sancho', 'Sebastián'],
    family: ['Acuña', 'Aguilar', 'Alarcón', 'Albornoz', 'Alvarado', 'Arellano', 'Ayala', 'Balboa', 'Bazán', 'Benavides', 'Cárdenas', 'Carranza', 'Castañeda', 'Cepeda', 'Cisneros', 'Dávila', 'Enríquez', 'Escobar', 'Espinosa', 'Figueroa', 'Gálvez', 'Guzmán', 'Herrera', 'Hurtado', 'Lara', 'Leyva', 'Maldonado', 'Medrano', 'Mendoza', 'Montalvo', 'Narváez', 'Ocampo', 'Olivares', 'Ordóñez', 'Osorio', 'Padilla', 'Peñalosa', 'Quesada', 'Quiñones', 'Ramírez', 'Rivadeneira', 'Salazar', 'Sandoval', 'Sarmiento', 'Solís', 'Tapia', 'Toledo', 'Ulloa', 'Valdés', 'Vargas', 'Velázquez', 'Villalobos', 'Zúñiga'],
    hulls: ['Santa María', 'La Niña', 'La Pinta', 'San Antonio', 'Concepción', 'Victoria', 'Trinidad', 'Santiago', 'San Cristóbal', 'Espíritu Santo', 'Na Señora del Rosario', 'San Juan', 'San Pedro', 'La Gallega', 'Santa Ana', 'San Salvador', 'Esperanza', 'La Capitana', 'San Nicolás', 'Buen Viaje', 'San Lorenzo', 'Magdalena', 'San Felipe', 'Nuestra Señora de Begoña'],
  },
  NLD: {
    patterns: ['Handelshuis {family}', '{family} & Zonen', 'Compagnie van {place}', 'Huis {family}', 'Kamer van {place}'],
    titles: ['Koopman', 'Schipper', 'Meester'],
    given: ['Adriaen', 'Albert', 'Barent', 'Cornelis', 'Dirck', 'Evert', 'Frederick', 'Gerrit', 'Hendrick', 'Jacob', 'Jan', 'Joost', 'Klaas', 'Lambert', 'Maarten', 'Nicolaes', 'Olivier', 'Pieter', 'Reinier', 'Simon', 'Thijs', 'Willem', 'Wouter'],
    family: ['Backer', 'Bicker', 'Blaeu', 'Boelens', 'Bontekoe', 'Cuyper', 'Coymans', 'Dedel', 'Graeff', 'Hasselaer', 'Heyn', 'Hooft', 'Houtman', 'Huydecoper', 'Keyser', 'Linschoten', 'Mostaert', 'Nuyts', 'Oetgens', 'Pauw', 'Poppen', 'Reael', 'Reynst', 'Ruychaver', 'Specx', 'Spiegel', 'Trip', 'Valckenier', 'Verburgh', 'Vlooswijck', 'Witsen'],
    hulls: ['Hollandia', 'Mauritius', 'Duyfken', 'Amsterdam', 'Hoorn', 'Zeelandia', 'De Gouden Leeuw', 'Vliegende Draeck', 'Witte Leeuw', 'Eendracht', 'Nieuw Hoorn', 'De Hoop', 'Batavia', 'Zeehaen', 'Arnhem', 'Haarlem', 'Gelderland', 'Wapen van Enkhuizen', 'Rode Leeuw', 'Tijger', 'Zwarte Raaf', 'Fortuyn'],
  },
  ENG: {
    patterns: ['{family} & Sons', 'The {place} Company', '{family} Brothers', 'The {place} Trade', '{family} & Partners'],
    titles: ['Master', 'Captain', 'Alderman', 'Factor'],
    given: ['Ambrose', 'Anthony', 'Bartholomew', 'Christopher', 'Edmund', 'Francis', 'Geoffrey', 'Gilbert', 'Henry', 'Humphrey', 'Jerome', 'John', 'Laurence', 'Martin', 'Nicholas', 'Oliver', 'Peter', 'Ralph', 'Richard', 'Roger', 'Simon', 'Thomas', 'Walter', 'William'],
    family: ['Ashley', 'Bagshaw', 'Barnaby', 'Blount', 'Carew', 'Cavendish', 'Chandler', 'Coverdale', 'Crowther', 'Danvers', 'Drayton', 'Egerton', 'Fenwick', 'Fortescue', 'Gresham', 'Hakluyt', 'Harcourt', 'Hawkridge', 'Holbrook', 'Kingsley', 'Lambton', 'Lydgate', 'Marchmont', 'Nettleton', 'Osbourne', 'Pakenham', 'Pembroke', 'Quarles', 'Radcliffe', 'Sackville', 'Thorne', 'Trenchard', 'Underhill', 'Vaughan', 'Wadham', 'Warbeck', 'Whitlock', 'Wyndham'],
    hulls: ['Golden Hind', 'Pelican', 'Mary Rose', 'Red Dragon', 'Hector', 'Susan', 'Ascension', 'Edward Bonaventure', 'Merchant Royal', 'Trades Increase', 'Clove', 'Hosiander', 'Peppercorn', 'Minion', 'Primrose', 'Swallow', 'Elizabeth', 'Dainty', 'Roebuck', 'Centurion', 'Globe', 'Expedition', 'Hopewell'],
  },
  FRA: {
    patterns: ['Maison {family}', 'Compagnie de {place}', '{family} et Fils', 'Société de {place}', 'Comptoir {family}'],
    titles: ['Sieur', 'Capitaine', 'Maître', 'Facteur'],
    given: ['Antoine', 'Baptiste', 'Charles', 'Claude', 'Denis', 'Étienne', 'François', 'Gaspard', 'Guillaume', 'Henri', 'Jacques', 'Jean', 'Louis', 'Marin', 'Mathurin', 'Nicolas', 'Olivier', 'Philippe', 'Pierre', 'Raoul', 'René', 'Simon', 'Thomas', 'Vincent'],
    family: ['Aubriot', 'Barbier', 'Beaulieu', 'Bénard', 'Boisseau', 'Boucher', 'Chastellain', 'Coulombe', 'Courtois', 'Dauphin', 'Delacourt', 'Desmarais', 'Dufresne', 'Durand', 'Fauchet', 'Gaillard', 'Gervais', 'Granville', 'Hachette', 'Jacquart', 'Lamoureux', 'Langlois', 'Lefebvre', 'Lemoine', 'Marchand', 'Mercier', 'Montbrun', 'Nourrisson', 'Pelletier', 'Perrault', 'Quesnel', 'Rouillard', 'Sabatier', 'Thibault', 'Vaillant', 'Verrier'],
    hulls: ['Grande Hermine', 'Petite Hermine', 'Émerillon', 'Saint-Louis', 'Notre-Dame', 'Croissant', 'Espérance', 'Sainte-Anne', 'Le Dauphin', 'La Licorne', 'Le Soleil', 'Bonne Aventure', 'Le Lion', 'Sainte-Croix', 'Le Pélican', 'Marie-Thérèse', 'Le Griffon', 'La Rochelaise', 'Saint-Jacques'],
  },
  DNK: {
    patterns: ['{family} & Søn', 'Handelshuset {family}', '{place} Kompagni', 'Huset {family}', '{family} Rederi'],
    titles: ['Skipper', 'Kaptajn', 'Købmand'],
    given: ['Anders', 'Bendt', 'Christen', 'Erik', 'Frederik', 'Hans', 'Iver', 'Jens', 'Jørgen', 'Knud', 'Lauritz', 'Mogens', 'Niels', 'Oluf', 'Peder', 'Rasmus', 'Søren', 'Thorkild', 'Valdemar'],
    family: ['Ahlefeldt', 'Bang', 'Bille', 'Bjørn', 'Brahe', 'Dahl', 'Falk', 'Friis', 'Gyldenløve', 'Hansen', 'Holst', 'Juel', 'Kaas', 'Krabbe', 'Lange', 'Lindegaard', 'Munk', 'Nielsen', 'Oxe', 'Parsberg', 'Qvist', 'Rantzau', 'Rosenkrantz', 'Sehested', 'Skram', 'Trolle', 'Urne', 'Vind', 'Wessel'],
    hulls: ['Dannebroge', 'Trefoldighed', 'Den Hvide Falk', 'Christianus', 'Norske Løve', 'Havfruen', 'Elefanten', 'Sorte Rytter', 'Oldenborg', 'Gyldenløve', 'Jægeren', 'Haabet', 'Prins Christian', 'Nordstjernen', 'Svanen', 'Ørnen'],
  },
  SWE: {
    patterns: ['{family} & Söner', 'Handelshuset {family}', '{place} Kompani', 'Huset {family}', '{family} Sjöfart'],
    titles: ['Skeppare', 'Kapten', 'Handelsman'],
    given: ['Anders', 'Axel', 'Bengt', 'Carl', 'Erik', 'Gustaf', 'Hans', 'Johan', 'Klas', 'Lars', 'Magnus', 'Nils', 'Olof', 'Per', 'Sten', 'Svante', 'Tord'],
    family: ['Banér', 'Bielke', 'Bonde', 'Brahe', 'Ekeblad', 'Falkenberg', 'Fleming', 'Gyllenstierna', 'Horn', 'Kurck', 'Leijonhufvud', 'Lilliehöök', 'Oxenstierna', 'Posse', 'Ribbing', 'Rosenhane', 'Sparre', 'Stenbock', 'Tott', 'Uggla', 'Wachtmeister', 'Åkerhielm'],
    hulls: ['Vasa', 'Äpplet', 'Kronan', 'Göteborg', 'Riksnyckeln', 'Scepter', 'Tre Kronor', 'Svärdet', 'Nyckeln', 'Draken', 'Mars', 'Elefanten', 'Solen', 'Enhörningen', 'Jupiter', 'Stora Sofia'],
  },
  HAN: {
    patterns: ['Handelshaus {family}', '{family} & Söhne', 'Kontor {place}', 'Haus {family}', '{family} Seefahrt'],
    titles: ['Kaufmann', 'Schiffer', 'Ratsherr'],
    given: ['Albrecht', 'Bernd', 'Claus', 'Detlev', 'Eberhard', 'Gottfried', 'Hartwig', 'Heinrich', 'Hinrich', 'Johann', 'Jürgen', 'Klaus', 'Lorenz', 'Matthias', 'Nikolaus', 'Otto', 'Reimar', 'Simon', 'Tideman', 'Volkmar', 'Wulf'],
    family: ['Angermünde', 'Bramstedt', 'Brömse', 'Castorp', 'Dankwerth', 'Ehlers', 'Fehling', 'Gerdes', 'Greverade', 'Hoyer', 'Kerkring', 'Krummediek', 'Lüneburg', 'Moller', 'Netzband', 'Osthusen', 'Plönnies', 'Querfurt', 'Ravensburg', 'Rodde', 'Schepenstede', 'Stiten', 'Tanneberg', 'Überhorst', 'Vorrath', 'Warendorp', 'Wittenborg', 'Zelmer'],
    hulls: ['Adler von Lübeck', 'Löwe', 'Greif', 'Sankt Jürgen', 'Bunte Kuh', 'Hanseat', 'Wappen von Bremen', 'Fortuna', 'Seeadler', 'Roter Löwe', 'Hoffnung', 'Elbe', 'Trave', 'Weser', 'Sankt Nikolaus', 'Marienschiff'],
  },
  POL: {
    patterns: ['Dom Handlowy {family}', '{family} i Synowie', 'Kantor {place}', 'Spółka {place}', 'Skład {family}'],
    titles: ['Pan', 'Kupiec', 'Szyper'],
    given: ['Andrzej', 'Bartosz', 'Dobrogost', 'Feliks', 'Grzegorz', 'Hieronim', 'Jakub', 'Jan', 'Kasper', 'Krzysztof', 'Marcin', 'Mikołaj', 'Paweł', 'Piotr', 'Stanisław', 'Szymon', 'Tomasz', 'Wawrzyniec', 'Zygmunt'],
    family: ['Baryczka', 'Bonar', 'Chodkiewicz', 'Ciołek', 'Dembiński', 'Firlej', 'Gostomski', 'Grudziński', 'Herburt', 'Jazłowiecki', 'Kmita', 'Koniecpolski', 'Leszczyński', 'Łaski', 'Montelupi', 'Myszkowski', 'Ossoliński', 'Podlodowski', 'Radziwiłł', 'Sapieha', 'Sierakowski', 'Tarnowski', 'Tęczyński', 'Wielopolski', 'Zamoyski', 'Zborowski'],
    hulls: ['Czarny Orzeł', 'Biały Lew', 'Wisła', 'Nadzieja', 'Święty Jerzy', 'Panna Wodna', 'Gryf', 'Krzysztof', 'Fortuna', 'Jaskółka', 'Złoty Kłos', 'Świętej Trójcy', 'Sokół', 'Dzwon', 'Niedźwiedź', 'Perła'],
  },
  RUS: {
    patterns: ['Torgovyi Dom {family}', "{family} i Synov'ya", 'Gostinyi {place}', '{family} Kompaniya', 'Artel {family}'],
    titles: ['Kupets', 'Gost', 'Promyshlennik'],
    given: ['Afanasy', 'Bogdan', 'Danila', 'Feodor', 'Gavrila', 'Grigory', 'Ignaty', 'Ivan', 'Kirill', 'Kuzma', 'Luka', 'Maksim', 'Nikifor', 'Osip', 'Pyotr', 'Rodion', 'Semyon', 'Stepan', 'Timofey', 'Vasily', 'Yakov'],
    family: ['Anikiev', 'Basargin', 'Bazhenin', 'Buldakov', 'Chirikov', 'Demidov', 'Filatev', 'Golikov', 'Guselnikov', 'Khlebnikov', 'Kologrivov', 'Lazarev', 'Mylnikov', 'Nikitin', 'Osokin', 'Panfilov', 'Pokhodyashin', 'Revyakin', 'Shelikhov', 'Shorin', 'Sirotkin', 'Stroganov', 'Suvorov', 'Tverdyshev', 'Usov', 'Vologzhanin', 'Yuryev', 'Zhigarev'],
    hulls: ['Svyatoy Nikolay', 'Orel', 'Sokol', 'Nadezhda', 'Tri Svyatitelya', 'Lebed', 'Beloye More', 'Zarya', 'Pomor', 'Groznyy', 'Dvina', 'Arkhangel', 'Vostok', 'Mezen', 'Severnaya Zvezda', 'Solovets'],
  },
  GEN: {
    patterns: ['Casa {family}', 'Compagnia di {place}', 'Banco {family}', '{family} e Fratelli', 'Maona di {place}'],
    titles: ['Messer', 'Capitano', 'Padrone'],
    given: ['Agostino', 'Ambrogio', 'Andrea', 'Antoniotto', 'Benedetto', 'Cristoforo', 'Domenico', 'Filippo', 'Francesco', 'Gerolamo', 'Giacomo', 'Lazzaro', 'Lorenzo', 'Luciano', 'Manuele', 'Nicolò', 'Ottobuono', 'Paolo', 'Raffaele', 'Simone', 'Tommaso', 'Ugolino'],
    family: ['Adorno', 'Boccanegra', 'Campofregoso', 'Cattaneo', 'Centurione', 'Cibo', 'Doria', 'Fieschi', 'Gentile', 'Giustiniani', 'Grimaldi', 'Imperiale', 'Lercari', 'Lomellini', 'Malocello', 'Negrone', 'Pallavicino', 'Pessagno', 'Pinelli', 'Promontorio', 'Salvago', 'Sauli', 'Spinola', 'Usodimare', 'Vivaldi', 'Zaccaria'],
    hulls: ['San Giorgio', 'Grimaldina', 'Santa Maria di Genova', 'Doria', 'Lomellina', 'San Lorenzo', 'La Fortuna', 'Sant Antonio', 'Aquila Nera', 'Madonna del Monte', 'Spinolina', 'San Michele', 'La Genovese', 'Leon d Oro', 'Santa Chiara'],
  },
  VEN: {
    patterns: ["Ca' {family}", 'Compagnia di {place}', 'Fraterna {family}', 'Colleganza {family}', 'Banco {family}'],
    titles: ['Messer', 'Ser', 'Capitano', 'Patrono'],
    given: ['Alvise', 'Andrea', 'Benedetto', 'Bernardo', 'Domenico', 'Francesco', 'Giacomo', 'Giovanni', 'Girolamo', 'Jacopo', 'Leonardo', 'Lorenzo', 'Marco', 'Marin', 'Nicolò', 'Paolo', 'Pietro', 'Sebastiano', 'Tomà', 'Vettor', 'Zaccaria'],
    family: ['Badoer', 'Barbarigo', 'Bembo', 'Bragadin', 'Cappello', 'Contarini', 'Corner', 'Dandolo', 'Dolfin', 'Donà', 'Emo', 'Falier', 'Foscari', 'Gradenigo', 'Grimani', 'Gritti', 'Loredan', 'Malipiero', 'Marcello', 'Memmo', 'Michiel', 'Mocenigo', 'Morosini', 'Nani', 'Pisani', 'Querini', 'Sagredo', 'Sanudo', 'Soranzo', 'Tiepolo', 'Tron', 'Valier', 'Venier', 'Zane', 'Zeno', 'Ziani'],
    hulls: ['Bucintoro', 'Leone di San Marco', 'Querina', 'Pisana', 'Contarina', 'Serenissima', 'Santa Maria Formosa', 'Grifone', 'San Teodoro', 'La Veneziana', 'Fortuna Grande', 'Mocenigo', 'Dolfina', 'Aquila d Oro', 'Santa Giustina', 'Galeone Nuovo'],
  },
  OTT: {
    patterns: ['{family} Ortaklığı', '{place} Tüccarları', 'Hacı {family} ve Oğlu', '{family} Kumpanyası', '{family} Ticaret Evi'],
    titles: ['Hacı', 'Reis', 'Tüccar', 'Hoca'],
    given: ['Ahmed', 'Ali', 'Bayram', 'Cafer', 'Davud', 'Emin', 'Ferhat', 'Gazi', 'Halil', 'Hasan', 'Hüseyin', 'İbrahim', 'İskender', 'Kasım', 'Kemal', 'Mahmud', 'Mehmed', 'Murad', 'Mustafa', 'Osman', 'Piyale', 'Rüstem', 'Sinan', 'Süleyman', 'Turgut', 'Yusuf'],
    family: ['Abdülkerim', 'Arslanoğlu', 'Barbaros', 'Çandarlı', 'Çelebi', 'Demirci', 'Ebubekir', 'Eminoğlu', 'Feridun', 'Gazanfer', 'Hamzaoğlu', 'Hasanoğlu', 'Hüseyinoğlu', 'İbrahimoğlu', 'Karaman', 'Kasımoğlu', 'Kemaloğlu', 'Köprülü', 'Mahmudoğlu', 'Mehmedoğlu', 'Murtaza', 'Mustafaoğlu', 'Nişancı', 'Osmanoğlu', 'Rüstemoğlu', 'Sinanoğlu', 'Şahinoğlu', 'Tahiroğlu', 'Veliyüddin', 'Yakuboğlu', 'Zülfikar'],
    hulls: ['Kaplan', 'Şahin', 'Yıldız', 'Hilal', 'Burak', 'Ejder', 'Mavi Deniz', 'Gülbahar', 'Sancak', 'Kılıç', 'Zafer', 'Bereket', 'Rüzgâr', 'Çelebi', 'Nurbahar', 'Deryadil'],
  },
  MAR: {
    patterns: ['Dar {family}', 'Tujjar {place}', 'Bayt {family}', '{family} wa Awlad', 'Shirkat {place}'],
    titles: ['Hajji', 'Rais', 'Muallim', 'Sayyid'],
    given: ['Abdallah', 'Ahmad', 'Ali', 'Bilal', 'Driss', 'Hamid', 'Hasan', 'Ibrahim', 'Idris', 'Ismail', 'Khalid', 'Mahmud', 'Muhammad', 'Mustafa', 'Omar', 'Rashid', 'Said', 'Salih', 'Tahar', 'Umar', 'Yusuf', 'Zakariya'],
    family: ['Alami', 'Ammari', 'Benjelloun', 'Bennani', 'Berrada', 'Chaoui', 'Doukkali', 'Fassi', 'Ghannami', 'Hajji', 'Idrissi', 'Jamai', 'Kabbaj', 'Lahlou', 'Mansouri', 'Marrakchi', 'Mekouar', 'Naciri', 'Ouazzani', 'Qadiri', 'Rifai', 'Sabti', 'Sallaoui', 'Sqalli', 'Tazi', 'Wazzani', 'Zouiten'],
    hulls: ['Al-Mansur', 'Bahr al-Khayr', 'Nujum', 'Sabra', 'Al-Barakah', 'Riyah', 'Lulu', 'Mizan', 'Dhahab', 'Fath', 'Zuhra', 'Nasr', 'Amal', 'Safar', 'Hilal al-Gharb'],
  },
  PER: {
    patterns: ['Khaneh-ye {family}', 'Tujjar-e {place}', 'Karvansara {family}', '{family} va Pesaran', 'Shirkat-e {place}'],
    titles: ['Khwaja', 'Mirza', 'Hajji', 'Tujjar'],
    given: ['Abbas', 'Aqa', 'Bahram', 'Daryush', 'Esmail', 'Farhad', 'Ghiyas', 'Hossein', 'Iskandar', 'Jafar', 'Kamran', 'Mahmud', 'Nader', 'Parviz', 'Qasim', 'Rostam', 'Shahrokh', 'Tahmasp', 'Vali', 'Yusuf', 'Zahir'],
    family: ['Ardabili', 'Astarabadi', 'Bastami', 'Dehkhoda', 'Esfahani', 'Farahani', 'Ghaffari', 'Golestani', 'Hamadani', 'Jahanbani', 'Kashani', 'Kermani', 'Lahijani', 'Mazandarani', 'Naraqi', 'Qazvini', 'Rashti', 'Sabzevari', 'Shirazi', 'Tabrizi', 'Yazdi', 'Zanjani'],
    hulls: ['Darya', 'Khorshid', 'Simurgh', 'Gohar', 'Setareh', 'Firuz', 'Bahar', 'Rakhsh', 'Nilufar', 'Shahbaz', 'Tufan', 'Zarrin', 'Mehregan', 'Payam', 'Sadaf', 'Yakut'],
  },
  MUG: {
    patterns: ['{family} Kothi', 'Seth {family} & Sons', '{place} Pedhi', '{family} Sarraf', 'Shah {family} Kothi'],
    titles: ['Seth', 'Shah', 'Nakhuda', 'Mahajan'],
    given: ['Amarchand', 'Bhagwandas', 'Chhotalal', 'Damodar', 'Gokuldas', 'Harilal', 'Jagannath', 'Kalyandas', 'Lakshmichand', 'Madhavji', 'Narayan', 'Premchand', 'Ratanji', 'Shantidas', 'Tribhovan', 'Virji'],
    family: ['Ahuja', 'Banarasi', 'Bhansali', 'Chinai', 'Dalal', 'Desai', 'Dhanji', 'Gandhi', 'Hirji', 'Jhaveri', 'Kamdar', 'Karamchand', 'Lalbhai', 'Mehta', 'Modi', 'Nanji', 'Pandya', 'Parekh', 'Premji', 'Raichand', 'Sanghvi', 'Shah', 'Tarachand', 'Vora', 'Zaveri'],
    hulls: ['Rahimi', 'Salimi', 'Ganj-i-Sawai', 'Fath Jang', 'Sahibi', 'Rahmani', 'Ilahi', 'Noor Jahan', 'Karim', 'Mubarak', 'Daryabad', 'Shahjahani', 'Barkat', 'Sagar', 'Moti', 'Hira'],
  },
  MNG: {
    patterns: ['{family} Hang', '{family} Shangtang', '{place} Hao', '{family} Yanghang', '{family} Chuanhang'],
    titles: ['Laoban', 'Zhangkui', 'Shangren'],
    given: ['Baoshan', 'Chengen', 'Daoyuan', 'Dengyun', 'Guangzu', 'Hongji', 'Jingfu', 'Kuiyuan', 'Liangchen', 'Mingde', 'Pengju', 'Qinghe', 'Ruilin', 'Shiyuan', 'Tingyu', 'Weiming', 'Xiangzhi', 'Yanqing', 'Yuanhao', 'Zhaolin'],
    family: ['Cai', 'Chen', 'Cheng', 'Dai', 'Ding', 'Fang', 'Feng', 'Gao', 'Guo', 'Han', 'Hong', 'Hu', 'Huang', 'Jiang', 'Lin', 'Liu', 'Lu', 'Luo', 'Ma', 'Pan', 'Peng', 'Qian', 'Shen', 'Su', 'Sun', 'Tang', 'Wang', 'Wei', 'Wu', 'Xie', 'Xu', 'Yang', 'Ye', 'Yu', 'Zeng', 'Zhang', 'Zhao', 'Zheng', 'Zhou', 'Zhu'],
    hulls: ['Fuxing', 'Haitong', 'Jinlong', 'Changsheng', 'Baoshun', 'Tianhe', 'Yongli', 'Ruian', 'Shunfeng', 'Dehai', 'Lianyun', 'Jixiang', 'Yuanyang', 'Qianli', 'Mingzhu', 'Huifeng'],
  },
  JPN: {
    patterns: ['{family}-ya', '{family} Shokai', '{place} Kaisen', '{family} Kaisen', '{family} Donya'],
    titles: ['Toji', 'Sendo', 'Aruji'],
    given: ['Buzaemon', 'Chubei', 'Denbei', 'Gorozaemon', 'Hachirobei', 'Heisuke', 'Ichibei', 'Jinzaemon', 'Kanbei', 'Kyuzaemon', 'Magoemon', 'Matazaemon', 'Rihei', 'Sozaemon', 'Tarobei', 'Toemon', 'Yasubei', 'Zenbei'],
    family: ['Asano', 'Chaya', 'Daikoku', 'Echigo', 'Fujita', 'Hirano', 'Hishi', 'Ichijo', 'Izumi', 'Kaga', 'Kashiwa', 'Kawamura', 'Konoike', 'Masu', 'Mitsui', 'Nara', 'Omi', 'Owari', 'Sakai', 'Sumi', 'Suminokura', 'Tatsu', 'Tennoji', 'Yodo', 'Yamato'],
    hulls: ['Takarabune', 'Shirasagi', 'Kaiyomaru', 'Tenryumaru', 'Fukujumaru', 'Horai', 'Sumiyoshimaru', 'Daikokumaru', 'Kinryumaru', 'Chidorimaru', 'Ebisumaru', 'Hakuhomaru', 'Myojinmaru', 'Jinbeimaru', 'Tsurumaru', 'Kameyamamaru'],
  },
  JOS: {
    patterns: ['{family} Sangdan', '{family} Gaekju', '{place} Sanghoe', '{family} Dohoe', '{family} Pogaek'],
    titles: ['Haengsu', 'Seonju', 'Jujin'],
    given: ['Bokman', 'Changsu', 'Deokhyeon', 'Gyeongju', 'Hakchun', 'Ilseon', 'Jeongbo', 'Kwangjin', 'Myeongseok', 'Pilseung', 'Sangcheol', 'Sunjae', 'Taeyeong', 'Uijin', 'Wonbo', 'Yeongdal'],
    family: ['An', 'Bae', 'Baek', 'Cha', 'Cho', 'Choe', 'Chung', 'Gang', 'Go', 'Ha', 'Han', 'Heo', 'Hong', 'Hwang', 'Im', 'Jang', 'Jeon', 'Jeong', 'Jin', 'Ju', 'Kim', 'Kwon', 'Lee', 'Min', 'Mun', 'Nam', 'No', 'Pak', 'Ryu', 'Seo', 'Shim', 'Sin', 'Song', 'Won', 'Yang', 'Yu', 'Yun'],
    hulls: ['Cheonghae', 'Byeokpajeong', 'Haedong', 'Sinmi', 'Maenghoseon', 'Pungnyeon', 'Namhaeseon', 'Ilseong', 'Dongryeong', 'Baekhak', 'Wolmyeong', 'Cheongryong', 'Hwangho', 'Sinpung', 'Jangsu'],
  },
  AYU: {
    patterns: ['Hong {family}', '{family} Phanit', '{place} Samphao', 'Hong {place}', '{family} Nawa'],
    titles: ['Khun', 'Nai', 'Nakhuda'],
    given: ['Boonma', 'Chaem', 'Det', 'Inthorn', 'Mani', 'Nopphadon', 'Phet', 'Prajak', 'Samran', 'Sawat', 'Thong', 'Udom', 'Wichit'],
    family: ['Akarat', 'Bunnag', 'Chanthorn', 'Intharat', 'Kalahom', 'Krisada', 'Mahanop', 'Nakhon', 'Pichai', 'Prasert', 'Sakdina', 'Saowarat', 'Siriwat', 'Sombun', 'Suphan', 'Thepharat', 'Wichai', 'Yotha'],
    hulls: ['Suphannahong', 'Narai', 'Krabi', 'Thepha', 'Chaiya', 'Maenam', 'Phetcharat', 'Sumphao Thong', 'Bunrueang', 'Lamphun', 'Mongkut', 'Sawan', 'Anuphap', 'Rattana', 'Chaisuk', 'Thawi'],
  },
}

/**
 * A FLEET's name: a nation's own word for the run, over the far stop's place name. Not authored
 * per company — the same habit the company name follows, one level down.
 */
export const RUN_WORDS = {
  PRT: ['Carreira', 'Rota', 'Viagem', 'Derrota'],
  ESP: ['Carrera', 'Ruta', 'Derrota', 'Flota'],
  NLD: ['Vaart', 'Reis', 'Route', 'Koers'],
  ENG: ['Run', 'Voyage', 'Trade', 'Passage'],
  FRA: ['Route', 'Voyage', 'Course', 'Traverse'],
  DNK: ['Fart', 'Rejse', 'Rute', 'Kurs'],
  SWE: ['Fart', 'Resa', 'Rutt', 'Kurs'],
  HAN: ['Fahrt', 'Reise', 'Route', 'Kurs'],
  POL: ['Szlak', 'Droga', 'Kurs', 'Podróż'],
  RUS: ['Khod', 'Put', 'Doroga', 'Kurs'],
  GEN: ['Viaggio', 'Rotta', 'Corso', 'Muda'],
  VEN: ['Muda', 'Viaggio', 'Rotta', 'Corso'],
  OTT: ['Sefer', 'Yol', 'Hat', 'Güzergah'],
  MAR: ['Safar', 'Tariq', 'Rihla', 'Darb'],
  PER: ['Safar', 'Rah', 'Tariq', 'Gozar'],
  MUG: ['Safar', 'Yatra', 'Vepar', 'Daur'],
  MNG: ['Hangxian', 'Lucheng', 'Haidao', 'Shuilu'],
  JPN: ['Kairo', 'Michi', 'Kaido', 'Watari'],
  JOS: ['Haero', 'Gil', 'Baetgil', 'Hanggil'],
  AYU: ['Senthang', 'Thang', 'Rue', 'Doen'],
}

/** A deterministic 32-bit hash. Never Math.random(): the same chain must build the same roster. */
export function hash32(s) {
  let h = 2166136261 >>> 0
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i)
    h = Math.imul(h, 16777619) >>> 0
  }
  // one avalanche pass, so neighbouring seeds ("ESP|7" / "ESP|8") are not neighbouring draws
  h ^= h >>> 16; h = Math.imul(h, 2246822507) >>> 0
  h ^= h >>> 13; h = Math.imul(h, 3266489909) >>> 0
  return (h ^ (h >>> 16)) >>> 0
}

/** mulberry32: a seeded stream, so any jitter is reproducible from (nation, route index). */
export function rng(seedStr) {
  let a = hash32(seedStr)
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

/** The ASCII spelling the second name is built on (npc_found's fallback, 0097:277-285). */
/** players.company_name is `check (length(btrim(company_name)) between 3 and 24)` — 0004:52. */
export const NAME_MAX = 24

/**
 * The SECOND SPELLING. npc_found takes it when the first is taken and raises when both are
 * (0097:277-285), so every company owes one, it has to be a real variant of the same name rather
 * than a different house, and it has to fit the same 24 characters. These are the variants a
 * period clerk would actually have written: the accents dropped, the ampersand spelt out (or the
 * other way about), the definite article dropped, and only then a plain "& Co".
 */
export function altSpellings(name) {
  const out = []
  const push = (x) => { if (x && x !== name && x.length >= 3 && x.length <= NAME_MAX && !out.includes(x)) out.push(x) }
  push(deburr(name))
  push(name.replace(' & ', ' and '))
  push(name.replace(' and ', ' & '))
  push(deburr(name.replace(' & ', ' and ')))
  push(name.replace(/^The /, ''))
  push(deburr(name).replace(/^The /, ''))
  push(`${name} & Co`)
  push(`${deburr(name)} & Co`)
  push(`${name} Co`)
  return out
}

export function deburr(s) {
  const map = { Đ: 'D', đ: 'd', Ł: 'L', ł: 'l', Ø: 'O', ø: 'o', Æ: 'Ae', æ: 'ae', Œ: 'Oe', œ: 'oe', ß: 'ss', Þ: 'Th', þ: 'th', İ: 'I', ı: 'i', Ş: 'S', ş: 's', Ğ: 'G', ğ: 'g' }
  return s.normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/[ĐđŁłØøÆæŒœßÞþİıŞşĞğ]/g, (c) => map[c] ?? c)
    .replace(/[^\x20-\x7e]/g, '')
}
