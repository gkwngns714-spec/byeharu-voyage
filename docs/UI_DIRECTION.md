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
* **EVE's price-history graph** is the one thing a trade game must have and that we cannot draw
  today — there is no `history7` on the RPC surface. That is a *server* gap.
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

* **price history** — no `history7`, so a sparkline or an EVE-style graph cannot be drawn honestly.
* **ship art / class silhouettes** — there is no art in this repository at all.
* **officers, skills, buffs** — named by the owner; no tables exist. `docs/SECTIONS.md` says where
  each one lands.
* **rank standings** — RANK is an 18-line placeholder; nothing computes a table.
* **fame / reputation** — the currency cluster has room for it and no such number exists yet.

Each of these is a migration, not a component. They are why the UI looks empty even where it is
behaving correctly.
