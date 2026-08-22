# UI DIRECTION — from a document to a game

> The owner, 2026-08-20: *"this is not a proper game. see other games such as 대항해시대 오리진 …
> Refer to them and make the UI the same, or even better. Refer to Runescape 3, EVE online as well."*

This document is the standing art and interaction direction for the client. It **overrides the
austerity of `docs/DESIGN.md` §UI** where the two disagree — the owner's instruction outranks the
earlier design intent. What it does **not** touch is the architecture: the server still owns every
rule, `docs/SECTIONS.md` boundaries still hold, and the map still accepts no orders.

Every claim below marked **[seen]** was taken from a screenshot that was downloaded and looked at,
not from memory. The reference captures live outside the repo — they are Line Games' copyright, not
ours. This file records what was *learned*, and never reproduces their art.

---

## 1. The diagnosis — why the current build reads as a web form

Measured on the running app at 390×844: the screen is a **document**. A page title, a horizontal
rule, stacked bordered boxes, prose paragraphs, and a row of text buttons. Nothing is made of
anything. There is no world behind the glass, no material, no weight, and — the tell — **no number
is ever the hero.** In a trade game the number *is* the game.

Three specific failures, each of which 대항해시대 오리진 solves inside a single screenshot:

1. **No frame.** Every screen re-invents its own layout. There is no persistent chrome that says
   "you are inside a game" — no currency cluster, no clock, no ship status.
2. **No density.** One fact per row, wrapped in a card, with an explanatory sentence beneath it. UWO
   puts a good's icon, name, price index and price on **one ~40px row**, and fits eleven of them on
   screen at once. **[seen]**
3. **No material hierarchy.** Everything is the same grey box. Nothing is brass, nothing is
   parchment, nothing is lit.

---

## 2. What 대항해시대 오리진 actually does — the layout grammar

The most useful capture is the 세계지도 (world map) screen: **three zones, and every other screen is
a variation of them.** **[seen]**

```
+------------+------------------------------------+------------------------+
| <  세계지도       [ 항구 | 탐험 ]        (gold) 1,051,050   (gem) 103   ? |  top bar
+------------+------------------------------------+------------------------+
| LEFT RAIL  |                                    |  DOCKED PANEL          |
| searchable |            THE WORLD               |  +------------------+  |
| goods list |         (the art / the map)        |  |   항구 정보     X |  |
| with stars |                                    |  +------------------+  |
|            |      port markers + labels         |  | 기본 교역 시설 투자 |  tabs
|  돌소금  * |                                    |  | [ 교역소 | 선창 ]  |  sub-tabs
|   +리스보아|                                    |  | (i) 포탄  101%  574|  <- THE ROW
|  동판      |                                    |  | (i) 돌소금 105% 516|  |
|  도자기    |                                    |  | (i) 인쇄물  99% 306|  |
|            |                                    |  +------------------+  |
| [내 위치]  |            <   이동   >             |  | 선창    276/457  |  |  footer meter
+------------+------------------------------------+------------------------+
```

**The row is the whole lesson.** `icon · name · index% · price` — four facts, one line, no prose.
The index is a **coloured pill immediately after the name**, not a column you must scroll to reach.
D11h moved `%NBR` to second position by reasoning about it; UWO proves the position by shipping it.
**[seen]**

### Other patterns worth taking, each from a capture

| pattern | what it is | where it goes here |
|---|---|---|
| **Currency cluster** | top-right, round icon + monospace figure, on EVERY screen **[seen]** | ducats now, fame later — persistent, never re-rendered per screen |
| **Back-chevron + title + (?)** | top-left triad, identical everywhere **[seen]** | replaces the per-screen `PageHeader`; the `(?)` is our existing `Explain` dot |
| **Docked panel** | opaque body, darker header bar with a gold hairline, ✕ to dismiss **[seen]** | the one panel primitive every screen composes |
| **Tabs, then sub-tabs** | `기본/교역/시설/투자`, then `교역소/선창` **[seen]** | PORT becomes exactly this: one place with faces, not four sibling tabs |
| **Footer meter** | `선창 276/457` with a fill bar pinned to the panel bottom **[seen]** | hold used / hold total, always visible while trading |
| **Hero action card** | art + requirement bars + one gold CTA; unavailable actions greyed **with the reason printed** (*"특별한 탐험이 없습니다"*) **[seen]** | every verb on COMMAND becomes one of these |
| **Requirement bars** | `전투력 37/5`, `관찰력 45/5` — green bar, have/need **[seen]** | stores, crew and hull against what a voyage demands |
| **Negotiation modal** | before → after price, the delta as a signed %, a success-probability bar **[seen]** | `cmd.preview()` already returns this shape; today we print it as a sentence |
| **Starred good → port highlight** | star a good in the rail; ports carrying it light green on the map **[seen]** | the best single feature to copy — it answers *"where do I sell this?"* on the map |
| **Cut-corner frames** | clipped corners and a doubled gold rule, not rounded rectangles **[seen]** | the panel border treatment |
| **Clock in the corner** | real time bottom-left, total wealth bottom-right **[seen]** | game date, and wealth |

### The material, read off the captures **[seen]**

* Panel body: warm neutral — never pure grey, always pushed toward brown.
* Panel header: a brown gradient, roughly `#4a3728 → #2f231a`, with a 1px gold hairline `#c9a227`.
* Primary action: a brass gradient with a darker rim. Secondary: flat warm grey.
* Selected: gold. Locked: desaturated with a lock badge — **shown, never hidden.**
* Price-index pills: olive/gold near 100%; the number carries the meaning, not the pill alone.
* The background is always **the world** — sea, port, or map — never a flat colour.

---

## 3. What RuneScape 3 and EVE Online add

UWO gives the *material*. These two give the *behaviour under density*, which is what a game with
214 ports and 70 goods actually needs.

* **EVE's Overview → our MARKET.** A sortable, column-configurable table with saved presets is the
  right answer to "eleven numeric facts, a 390px screen". The player picks the columns that matter
  and the game remembers.
* **EVE's price-history graph** is the one thing a trade game must have. It could not be drawn
  until 0013 gave the market a memory; MARKET now carries a TREND sparkline per row. The full
  instrument — median with a hi/lo band, two moving averages, a volume histogram — stays a desktop
  idea; at 390px the honest form is the shape of the line, with the exact figures beside it.
* **EVE's number formatting**: tabular numerals, thousands separators, units always attached
  (`m³` there; `t` and `d.` here). Numbers align down a column.
* **EVE's colour language**: one meaning per colour, everywhere, permanently.
* **RS3's left-click default / right-click everything** → on touch: **tap does the obvious thing,
  long-press opens the full verb list.** This is how a 26-verb grammar stops being a menu crawl.
* **RS3's ribbon** → the bottom tab rail we already have; the lesson is icon-first with the label
  under it, plus a notification badge.
* **RS3's status orbs** → status as a ringed dial rather than a text row: hull, stores, crew, hold.
* **RS3's filtered chat/log** → LEDGER becomes a filterable event log, not a table dump.

**What NOT to take:** RS3's draggable free-floating windows (a phone has neither the room nor a
mouse), and EVE's every-thing-is-a-window model. Take the density and the colour discipline; leave
the window manager.

---

## 3a. ⚠ COPY THE MATERIAL, NOT THE DEPTH

The most important research finding, and it inverts the naive reading of the owner's instruction.

**대항해시대 오리진's interface is the single most criticised thing about the game in its own
Korean community.** 나무위키's evaluation page gives it a top-level heading — **「최악의 UX」**,
"the worst UX" — the only interface-specific heading in the whole negative section:

> *"대항해시대 오리진은 노골적으로 말해 유저의 편의성을 전혀 신경 쓰지 않은 엉망진창인 UI를 들고 나왔다."*
> — bluntly, it shipped a shambolic UI that pays no attention to player convenience.

And the complaint is **quantified**, which makes it usable:

| task | cost |
|---|---|
| dump water and food | **9 taps** (`ESC-창고-선창-물-휴지통-확인-식량-휴지통-확인`) |
| change a fleet preset | 4+, no hotkey — and direct preset shortcuts were *removed* |
| swap one component across 9 presets | ~27 clicks |
| sponsor officers | ~20 clicks, with a confirmation popup after **each one** |
| reach a bottle quest | 4 levels deep (`메뉴-창고-도구함-기타`) |

The developers now say it themselves. They created a dedicated 편의성 개선팀 in January 2025, and
the director's stated goal is worth keeping on the wall:

> *"목표는 게임 내의 정보들을 열람하기 위해 인게임이 아니라 커뮤니티나 유저 공략 등을 별도로 참조하는
> 부분들을 최소화하는 것입니다."* — minimise the parts where a player has to leave the game and
> consult a community wiki to read the game's own information.

Their design principle for the convenience pass, verbatim, is the one line to steal outright:

> *"UI 및 게임 정보 확인의 용이함, 시인성 개선, **조작 횟수 및 depth 감소**에 중점"*

### The three traps, named

1. **A convenience feature that becomes a blocker.** The cargo-ratio screen is elegant *and* one of
   the most hated in the game: exceeding the ratio **blocks departure outright**, and it is set in
   percentages so an exact quantity is unreachable. Take the stacked allocation bar; **never let an
   allocation gate an action.** A target, not a constraint.
2. **The action lives on the wrong screen.** Auto-supply sits in Supply but is needed at Departure;
   dumping cargo sits in Storage but is needed at the trading post. The most-praised patch in four
   years added no feature at all — it moved *selling provisions* onto the buy screen, where the
   need arises. *"교역소 구매 화면에서 바로 물빵을 전부 파는게 가능하니까 정말 편하네요."*
3. **Invisible rules are bugs, not content.** A 2026 patch **deleted** a quest-eligibility rule
   outright rather than document it, because *"기존 규칙은 인게임 내 확인이 어려워"*.

### What players actually praise — one thing, over and over

**One-tap intent.** Tap the quest → she sails there. Tap the port → she sails there. Tap the
minimap → he walks there. Plus consolidation: the tavern absorbed the pub, the departure office
absorbed repair and crew hiring. (The art is the other consistent praise — the illustration quality
is credited with *lowering* the entry barrier.)

**This is the half we already have.** Orders are composed, not typed; a good on MARKET is one tap
to a filled-in order; PORT prints every action as the literal order line it will become. The thing
their four-year convenience backlog exists to fix is the thing this project started from.

### So the instruction resolves as

**Take the material, the density and the layout grammar. Refuse the menu tree.** Every pattern in
§2 is about how a panel LOOKS and how much it can say per row. None of it is about how many taps
sit between the player and an act — and on that axis the reference is the cautionary tale, not the
model. A tap count is a design fact: if something is done more than five times a session and has no
bulk form, that is a defect, and their history says it will take a year to notice.

---

## 4. The rules this project now builds to

1. **Every screen is the same frame.** Top bar (back · title · help · currency), a world layer, one
   or two docked panels, the tab rail. A screen that invents its own layout is a bug.
2. **The number is the hero.** Tabular numerals, right-aligned, larger than its label. The label is
   small-caps and dim; the figure is bright.
3. **One row, four facts.** Icon, name, index, price. No row gets a paragraph.
4. **Prose is a tooltip, not a layout.** Explanatory sentences move behind the existing `Explain`
   dot.
5. **Unavailable is shown with its reason** — never hidden, never silently disabled.
6. **The world is always behind the glass.** Sea at sea, the port when docked, the map when looking.
7. **Colour means one thing.** Gold = you may act. Green = gain / cheap / safe. Red = loss / dear /
   danger. Blue = information. Grey = you may not, and it says why.
8. **Nothing the client shows is decided by the client.** Unchanged, and non-negotiable.

---

## 5. What the redesign needs that the server cannot yet give

Recorded here rather than faked in the UI:

* ~~price history~~ — **closed by 0013.** `world.price_history()` serves it and MARKET draws it.
* **ship art / class silhouettes** — there is no art in this repository at all.
* **buffs** — still no table. ~~officers~~ closed by 0015, ~~skills~~ by 0016; each got its own
  migration exactly where `docs/SECTIONS.md` said it would land.
* **rank standings** — still nothing computes a table, and that half is a design decision (who may
  see whose figures) rather than a missing SELECT. The house's OWN figures are served by 0014.
* ~~fame / reputation~~ — **closed by 0014**, and DERIVED from the ledger rather than counted, so
  it cannot drift from the record it is computed from.

Each of these is a migration, not a component. They are why the UI looks empty even where it is
behaving correctly.
