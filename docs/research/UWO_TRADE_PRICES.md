# How Uncharted Waters prices a trade good, and what byeharu-voyage takes from it

Researched 2026-10-18 for the owner's order (2026-10-17 ~23:50 UTC): *"the distance ratio should make kimchi
higher for cash. for example korea - london is one of the longest trip. you bought for 100, it should sell for
like 50k each. Or something like that. Do a thorough research on 대항해시대 오리진 again, and check for trading
prices and apply."*

Covers Uncharted Waters Origin (대항해시대 오리진, 2020–), Uncharted Waters Online (대항해시대 온라인 / 大航海時代
Online, 2005–), and the offline games Origin descends from (UW2, UW4). Every statement is marked **SOURCED** (with
its URL) or **INFERENCE**. The section at the end says what migration 0173 does with it.

**The limit, stated first.** No source publishes Origin's distance-to-multiplier formula or table. Line Games
confirms only that a distance-based sale multiplier ("판매 배율") exists and was re-measured on sailing distance.
The shape of the curve is therefore inferred from the prices players quote.

## 1. Distance, cultural sphere and the famous-product premium

### Origin

- **SOURCED.** The sale multiplier is distance-based, and since December 2024 it uses the sailing distance:
  "[교역] 교역품의 판매 배율 규칙이 소폭 개선 — 이전보다 정확한 항해 거리를 기준으로 적용되었습니다."
  - High-value goods (art, gems, precious metals) got "기본 가격이 대폭 증가" and a reset sale multiplier, so
    that "근거리 판매 시 손해를 볼 수도 있게 변경".
  - The cultural-sphere preference (문화권 우대) for basic goods went 10/15/20 % → 10/30/50 %, and for
    high-value goods 10/15/20 % → 5/10/15 %.
  - Extra distance coefficients for disaster and breeding goods were cut as "과도한".
  - Source: official KR notice 2024-12-24 "교역 밸런스 상세",
    https://uwo.floor.line.games/kr/bbsCmn/detail/1735028367968000283
- **SOURCED.** The English patch note says the same: "Applied based on more accurate sailing distances than
  before"; "These trade goods may result in losses when sold at short distances"; the premium limit was raised
  from 40 % to 70 % per category; the maximum purchase discount was set to 90 %.
  https://uwo.floor.line.games/us/bbs/guide/guide_us/1/detail/1736232803694014470
- **SOURCED.** April 2025: national capitals were split into their own cultural zones, and about 80 cities
  were re-zoned. A seasonal 5 % preferential rate was added for spices, gems and firearms.
  https://uwo.floor.line.games/us/bbsCmn/detail/1743482581594026184
- **SOURCED.** October 2023: some goods carry a regional preference, for example "아줄레주 : 일본, +60%",
  "네롤리 : 일본, +40%", "니시진오리 : 이베리아, +40%". Goodwill is "교역품 가격 및 거리에 대체로 비례합니다".
  https://uwo.floor.line.games/kr/bbsCmn/detail/1698050278274002785
- **SOURCED.** Namu: "거리에 따른 가치 상승 보정이 굉장히 강력하게 걸려 있어 대부분의 경우 멀리 나가서 팔수록 그만큼의
  값을 하게 되며". Special ports pay more for particular goods (England for tea). Islamic ports fix alcohol and
  pork at "0두캇". Language level 5 gives a 5 % buy discount and sale surcharge.
  https://namu.wiki/w/%EB%8C%80%ED%95%AD%ED%95%B4%EC%8B%9C%EB%8C%80%20%EC%98%A4%EB%A6%AC%EC%A7%84/%EA%B2%8C%EC%9E%84%20%EA%B4%80%EB%A0%A8%20%EC%A0%95%EB%B3%B4
- **SOURCED.** Namu, city list: "항해 거리가 곧 교역품의 판매가를 결정하는 오리진".
  - Distance is not strictly monotone. Palembang pays more for pineapple "than the farther Joseon / Ming",
    "105% 이상일 경우 27000 두캇까지도 가능".
  - Southeast Asian specialties should go to the Caribbean ("동남아 무역 구간에서는 굳이 유럽으로 갈 필요가 없다").
  - An Indian cargo of musk and gems fetches "1000만 두캇 이상".
  - https://namu.wiki/w/%EB%8C%80%ED%95%AD%ED%95%B4%EC%8B%9C%EB%8C%80%20%EC%98%A4%EB%A6%AC%EC%A7%84/%EA%B2%8C%EC%9E%84%20%EA%B4%80%EB%A0%A8%20%EC%A0%95%EB%B3%B4/%EB%8F%84%EC%8B%9C%20%EC%9D%BC%EB%9E%8C
- **SOURCED.** Inven 1–75 guide (2022-12): East Asian perfumes (진달래, 치자나무, 해당화, 금목서) average about
  **40,000 net profit a unit** sold in the North Sea, the eastern Mediterranean or the Caribbean. Luxury goods
  make about 20,000 net, and pink diamond 50,000 net. The end-game route is the Caribbean, North Sea or eastern
  Mediterranean ↔ East Asia. https://www.inven.co.kr/board/uwo/5714/896
- **SOURCED.** Inven, 2023-02: profit "rises with the physical distance between the purchase port and the sale
  port". https://www.inven.co.kr/webzine/news/?news=282044&site=uwo
- **SOURCED.** DC gallery survey (2022-08): a map price is the unmodified base. Base prices at 100 %: pepper
  8,971, western cannon 1,748, ambergris 1,566, saffron 1,462, perfume 1,418.
  https://gall.dcinside.com/mgallery/board/view/?id=bigtimeofnavigation&no=43357
- **SOURCED.** A Japanese guide gives the rule as "端の地域で買って逆の端の地域で売るのが最大利益を得る基本".
  https://oyururi.info/dak-koueki-route/
- **SOURCED.** Steam forum: "longer routes are usually better".
  https://steamcommunity.com/app/1574360/discussions/0/3819655463297857506

### Online (UWO / DOL)

- **SOURCED.** A 名産 (famous product) bonus applies only when the good is sold outside its own and the adjacent
  cultural circles. "Sell too close to home, and ye'll get naught but the common rate."
  - https://news.17173.com/z/dol/content/2006-03-24/20060324163606659.shtml
  - https://uwo-hq.blogspot.com/2019/01/rare-trade-goods.html
- **SOURCED.** Players measured 명산 distance scores, for example Netherlands goods at Calais 1, at Arguin 5 and in
  the Caribbean 8. "명산품의 이익과 명성치 획득은 거리에 비례합니다."
  - https://www.inven.co.kr/board/dho/498/13516
  - https://www.inven.co.kr/board/dho/486/440
- **SOURCED.** The only published distance formula is for experience points, not price:
  Specialty exp = min(500, qty × specialty distance × 50 / (merchant lv + 50)).
  http://aikaspage.blogspot.com/p/uwo-guides.html
- **SOURCED.** Long-haul prices players quote:
  - East Asian 南蠻 goods at 100 % in Europe: ginseng 52,400, Korean tea 50,000, Song white porcelain 52,600,
    Goryeo celadon 50,300. The same goods fetch 12,000–16,000 in Southeast Asia, so Europe pays **3.3–4.2×** what
    the nearer market pays. https://forum.gamer.com.tw/C.php?bsn=7200&snA=46399
  - Nutmeg and mace bought at ~1,000 in Southeast Asia sell for ~16,000 in Europe, **16×**.
    https://www.inven.co.kr/board/dho/2597/147
  - Silver bought at 1,000 in the Caribbean sells for 5,500 in Europe, **5.5×**. Tea sells for ~5,600 in Europe
    and ~8,600 in Britain, so its special port pays **1.5×**.
    https://namu.wiki/w/%EB%8C%80%ED%95%AD%ED%95%B4%EC%8B%9C%EB%8C%80%20%EC%98%A8%EB%9D%BC%EC%9D%B8/%EA%B5%90%EC%97%AD%ED%92%88
  - Caribbean tobacco sold in Lisbon: 5,300, with 4,790 profit, about **10×**.
    https://www.inven.co.kr/board/dho/498/19878
  - Diamonds from Luanda to northern Europe ~3×. Ceylon rubies to Antwerp 3–5×. Velvet from Genoa to northern
    Europe 1.2–1.5×. http://japanmmorpg.blogspot.com/2011/03/basic-trade-routes-in-uncharted-waters.html
  - 동방 무역 goods sell "2배 더 높고".
    https://namu.wiki/w/%EB%8C%80%ED%95%AD%ED%95%B4%EC%8B%9C%EB%8C%80%20%EC%98%A8%EB%9D%BC%EC%9D%B8/%EA%B5%90%EC%97%AD

### UW2 / UW4

- **SOURCED.** Both use per-town or per-region tables. UW4's price is f(town, 相場, 等級) with no stated distance
  term. Its 黄金航路 is a sale at ≥ 5× the buy price, which the guild rewards.
  - https://www.gamecity.ne.jp/manual/dk4HeN38/jp/3300.html
  - https://namu.wiki/w/%EB%8C%80%ED%95%AD%ED%95%B4%EC%8B%9C%EB%8C%80%202
- **INFERENCE.** In the offline games distance was authored into regional tables. Origin made it a continuous
  multiplier on sailing distance.

## 2. Market rate (시세)

- **SOURCED (Origin).**
  - The normal band is "유행이나 과잉이 없으면 90~110%" (namu, above).
  - Event bands after 2024-12: 유행 160/130, 과잉 70/45, 폭등 190/160, 폭락 45/20 (official KR notice, above).
  - After a Major Trend ends, the price stays within 100–125 %.
    https://guide.floor.line.games/UWO/en_US/detail/1167031329446900354
  - The highest rate observed was 319 %. https://www.inven.co.kr/webzine/news/?news=281107&site=uwo
- **SOURCED (Online).**
  - The usual range is 60–130 %, with ~50 % in a crash.
  - Crashes recover after about 4 changes, roughly 4 hours. https://wikiwiki.jp/gvo/TradeItem
- **SOURCED (UW2).** "물가는 최대 150%까지만 오르고, 최소 50%까지만 떨어진다."
- **Ours:** `drift` (an OU walk clamped at ±`drift_clamp`), `season_mod` and `demand` play this part. 0173 does not
  touch them.

## 3. Volume

- **SOURCED.**
  - Origin: the price falls as sales rise; the volume needed to move the rate was retuned in 2024-12, with no
    numbers published.
  - UWO: a sale of one category worth ≥ 100,000 profit can trigger a 폭락 that halves prices, so players split
    their sales into 20–50 units (namu 교역품; Inven 2597/146).
  - UW2: a 1,000-coin purchase moves the price 1 %, at most 13 % per transaction.
- **Ours:** the stock term √(stock_target / stock), walked 10 tuns at a time in `world.quote_priced`. It is
  untouched, so a big sale still walks its own price down.

## 4. Tax, investment, development

- **SOURCED.**
  - Origin: the base tariff is "20~30%", adjustable by the mayor −5…+15 %; an allied port charges none.
    https://guide.floor.line.games/UWO/en_US/detail/1167031186467500250
  - UWO: tariffs of 6–14 % by nation rank, and investor ranks get a 10/8/6/4/2 % discount (Inven 2597/147).
  - UW4: commerce investment raises the goods' grade, and so their price.
- **Ours:** `tax_rate`, the city purse (0122, `city_bid_factor`; the parallel 0172 slice), `dev_commerce`. 0173
  does not touch any of them.

## 5. Skills

- **SOURCED.**
  - Origin: Purchase / Sales Expert gives 2.5 % → 15 % (cap 20 %). Negotiation success 3 → 15 % (cap 35 %). The
    sale guild bonus is capped at ~54 %.
    - https://uwo.floor.line.games/us/bbsCmn/detail/1726144278318014479
    - https://www.inven.co.kr/board/uwo/5714/889
  - UWO: haggle up to 20 % (Inven 486/440).
- **Ours:** the haggle (0022) and the purser's spread shave (0017) act on the spread. 0173 does not touch them.

## 6. The curve: what the sources support, and the owner's scale

Sell ÷ buy ratios that players quote, by the length of the haul (**SOURCED** above):

| haul | example | ratio |
|---|---|---|
| adjacent sea | velvet, Genoa → northern Europe | 1.2–1.5× |
| one ocean | gems and silver, Africa / Caribbean → Europe | 3–5.5× |
| one ocean, cheap specialty | Caribbean tobacco → Lisbon | ~10× |
| the far side | nutmeg, Southeast Asia → Europe | ~16× |
| the far side, top goods (Origin) | East Asian perfume → Europe / Caribbean | ~40,000 net a unit on a ~1–1.5k-class base (≈ 25–40×) |

**INFERENCE.** The shape is convex. Near home the multiplier barely leaves 1, over one ocean it grows to a few
times, and at the far side of the world it is tens of times. Origin even lets a short sale of a high-value good
lose money, which a flat or linear curve could not do.

**The owner's number sets the scale.** Korea → London should take a ~100 jar to ~50,000, so the farthest haul
pays ~500× — an order of magnitude beyond any game's figure. That is a deliberate choice, and it is recorded here
so nobody "fixes" it back to the research's 40×. 0173 keeps the research's shape and stretches its far end to the
owner's figure:

    haul(nm) = haul_max ^ ((min(nm, haul_reach_nm) / haul_reach_nm) ^ haul_curve)
    haul_max 600, haul_reach_nm 14,500 nm, haul_curve 2.0

| sailing nm from the nearest maker | 1,000 | 2,000 | 3,000 | 5,000 | 7,000 | 10,000 | 12,000 | 14,006 (Mokpo → London) | ≥ 14,500 |
|---|---|---|---|---|---|---|---|---|---|
| haul | 1.03 | 1.13 | 1.32 | 2.14 | 4.45 | 20.9 | 79.8 | 391 | 600 |

These multiply the existing price, whose own affinity slope (0005) already adds 1.0–1.76 near to far. So the
whole distance gradient reads:
- adjacent sea ≈ 1.1–1.3×, as the research's 1.2–1.5;
- one ocean (5,000 nm) ≈ 3×, as its 3–5.5;
- 10,000 nm ≈ 30×, as its far-side 16–40;
- the last 4,000 nm to London, the owner's ~400×.

**What the research says to keep and 0173 keeps.**
- The distance is the SAILING distance (Origin's 2024 notice). Ours is `public.sea_reaches`, the water raster's
  own nm: Mokpo → London 14,006 nm round the Cape, not the 4,900 nm great circle.
- It is measured from the nearest place that MAKES the good (the 명산품 rule's "home").
- It multiplies the whole price, and the market rate, stock, tax and skills still act on top.

**What the research suggests that 0173 does NOT do, and why.**
- A per-cultural-sphere preference table (Origin's 10/30/50 %) is a second authored table; our `demand` (0066,
  per region × category) already plays that part.
- Non-monotone special ports (Palembang's pineapple) are the same: `demand`.
- A below-cost short sale of high-value goods: our makers' haul is exactly 1 and the producer discount (affinity
  0.93) already makes a short sale thin.
