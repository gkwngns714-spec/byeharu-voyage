# The flags — where each one comes from, and why it may be used

Every file in this folder is `public/flags/<nation code>.svg`, one per row of `public.nations`
(23 on 2026-10-18; `tests/flags.spec.ts` fails if a nation has no file here, or a file here has
no row in this table). They are bundled with the game and never hotlinked.

**The rule they were chosen by (the owner, 2026-10-18):** a flag is taken from Wikimedia Commons
only when the Commons licence is **Public Domain** (PD-self, PD-old, PD-shape, PD-user,
PD-ineligible and the national PD-flag templates) or **CC0**. CC BY, CC BY-SA and GFDL-only files
were rejected, however good. Where no PD/CC0 file fits the game's age (c. 1500-1650), or the only
one is tagged fictional on Commons, or the only one is too heavy to draw beside a name on the map,
the flag is an **original drawing** made for this game: a plain historical design, simple
geometry, no third-party artwork. An original drawing is released by the project under CC0.

**How each sourced file was handled:** downloaded into a new empty directory with its Commons
page text, read, run through `svgo` 3.3.2 (`convertStyleToAttrs`, `preset-default`,
`removeScriptElement`, `removeDimensions`, `removeXlink`; metadata, comments and editor
namespaces removed by the preset), then scanned: no `<script>`, no `<style>`, no `<image>`, no
`<foreignObject>`, no `on*=` handler, no `href` or `url()` outside the file. The pixels are the
Commons file's; only the markup was minified (and JOS.svg's `svg:`-prefixed markup rewritten to
the default namespace, its width and height turned into a viewBox, so it scales into the 3:2 box).

Total: **23 files, 52,584 bytes (51.4 KB)**.

| Code | Nation | File here | Source | Licence | Author |
|---|---|---|---|---|---|
| AYU | Ayutthaya | AYU.svg | original drawing: the plain red ensign of Siam (attested c. 1680) | CC0 (this project) | byeharu-voyage |
| BAN | Banten | BAN.svg | [File:Flag of the Sultanate of Banten.svg](https://commons.wikimedia.org/wiki/File:Flag_of_the_Sultanate_of_Banten.svg) | CC0 | Prawiroatmodjo |
| DNK | Denmark-Norway | DNK.svg | [File:Flag of Denmark.svg](https://commons.wikimedia.org/wiki/File:Flag_of_Denmark.svg) | Public domain (PD-shape) | Madden and others |
| ENG | England | ENG.svg | [File:Flag of England.svg](https://commons.wikimedia.org/wiki/File:Flag_of_England.svg) | Public domain (PD-shape) | traditional; vector Nicholas Shanks |
| ESP | Castile-Spain | ESP.svg | [File:Flag of Cross of Burgundy.svg](https://commons.wikimedia.org/wiki/File:Flag_of_Cross_of_Burgundy.svg) | Public domain (PD-self) | Ningyou |
| FRA | France | FRA.svg | original drawing (2026-10-18): the banner of the royal arms of France, *azure, three fleurs-de-lis or* (France moderne, borne by the kings from c. 1376), two over one, drawn large for 12–20 px, with a 1.5 px mid-grey edge. Replaced the Commons *Pavillon royal de France* (PD-user, Zippanova), whose small gold fleurs on white vanished into a blank cream chip at the sizes the game draws | CC0 (this project) | byeharu-voyage |
| GEN | Genoa | GEN.svg | [File:Flag of Genoa.svg](https://commons.wikimedia.org/wiki/File:Flag_of_Genoa.svg) | Public domain (PD-self) | see the file history on Commons |
| GUJ | Gujarat Sultanate | GUJ.svg | original drawing: a golden rosette on green (no attested flag; the CC0 Commons file is in "Fictional SVG flags of India") | CC0 (this project) | byeharu-voyage |
| HAN | The Hanse | HAN.svg | [File:Flag of the Free City of Lübeck.svg](https://commons.wikimedia.org/wiki/File:Flag_of_the_Free_City_of_L%C3%BCbeck.svg) — Lübeck's white over red, the Hanseatic colours | Public domain (PD-Flag-Germany) | not stated on Commons |
| JOS | Joseon | JOS.svg | [File:Flag of the king of Joseon.svg](https://commons.wikimedia.org/wiki/File:Flag_of_the_king_of_Joseon.svg) | Public domain (PD-old-100, PD-South Korea, PD-old-assumed) | not stated on Commons |
| JPN | Japan | JPN.svg | [File:Flag of Japan.svg](https://commons.wikimedia.org/wiki/File:Flag_of_Japan.svg) — the hinomaru | Public domain (PD-JapanGov, PD-shape) | various |
| MAR | Morocco | MAR.svg | [File:Flag of Marinid and Saadi Dynasty (1258-1420) (1554-1659).svg](https://commons.wikimedia.org/wiki/File:Flag_of_Marinid_and_Saadi_Dynasty_(1258-1420)_(1554-1659).svg) | Public domain (PD-self) | Flad |
| MLB | Malabar | MLB.svg | original drawing: a golden eight-pointed star on red (no attested flag of the Zamorin found on Commons) | CC0 (this project) | byeharu-voyage |
| MNG | Ming China | MNG.svg | original drawing: a sun-and-moon banner (日 + 月 = 明) on red; the only PD Commons file is titled "(fictitious)" | CC0 (this project) | byeharu-voyage |
| MUG | Mughal India | MUG.svg | original drawing: a golden sun on green (both Commons Mughal standards are CC BY-SA) | CC0 (this project) | byeharu-voyage |
| NLD | The Netherlands | NLD.svg | [File:Prinsenvlag.svg](https://commons.wikimedia.org/wiki/File:Prinsenvlag.svg) | Public domain (PD-self) | Miyamaki, Oren neu dag, Artem Karimov, Golradir |
| OTT | Ottoman Empire | OTT.svg | original drawing: a white crescent on red; the PD Commons "1517-1793" file is in "Fictional flags of historical entities" | CC0 (this project) | byeharu-voyage |
| PER | Safavid Persia | PER.svg | [File:Safavid Flag.svg](https://commons.wikimedia.org/wiki/File:Safavid_Flag.svg) — the lion and sun on green | Public domain (PD-user-w) | Orange Tuesday (en.wikipedia) |
| POL | Poland-Lithuania | POL.svg | [File:Flag of the Kingdom of Poland.svg](https://commons.wikimedia.org/wiki/File:Flag_of_the_Kingdom_of_Poland.svg) | Public domain (PD-self) | Alex Tora |
| PRT | Portugal | PRT.svg | original drawing after the PD design [File:Flag of Portugal (1521).svg](https://commons.wikimedia.org/wiki/File:Flag_of_Portugal_(1521).svg): the crowned royal shield on white, simplified (the Commons file is 335 KB) | CC0 (this project) | byeharu-voyage |
| RUS | Muscovy | RUS.svg | [File:Flag of Russia (1668–1693).svg](https://commons.wikimedia.org/wiki/File:Flag_of_Russia_(1668%E2%80%931693).svg) | Public domain (PD-RU-exempt) | Milop |
| SWE | Sweden | SWE.svg | [File:Flag of Sweden.svg](https://commons.wikimedia.org/wiki/File:Flag_of_Sweden.svg) | Public domain (PD-shape) | Jon Harald Søby and others |
| VEN | Venice | VEN.svg | original drawing after the PD design [File:Flag of Most Serene Republic of Venice.svg](https://commons.wikimedia.org/wiki/File:Flag_of_Most_Serene_Republic_of_Venice.svg): the six-tailed crimson gonfalon with St Mark's gold halo and open book (the Commons file is 787 KB) | CC0 (this project) | byeharu-voyage |

Rejected on licence (not used): Royal Standard of the King of France (CC BY-SA 3.0), Flag of the
Polish-Lithuanian Commonwealth (2-3) (CC BY-SA 4.0), Russian Banner Of The Tsar (1613-1693)
(CC BY-SA 4.0), Flag of the Republic of Venice (GFDL), Flag of the Serene Republic of Venice
(CC BY-SA 3.0), Alam of the Mughal Empire (CC BY-SA 3.0), Flag of the Mughal Empire (triangular)
(CC BY-SA 3.0), Saadi flag (CC BY-SA 4.0), Banner of the Kingdom of Poland (CC BY 3.0),
Bourbonic banners - France (CC BY-SA 3.0).

Note on insignia: several Commons pages carry `{{insignia}}` (and Sweden's names Act 1970:498).
That is a non-copyright restriction on using a state's insignia as a trademark or to imply
official endorsement; drawing a historical flag beside a city's name in a game does neither.

## Licence evidence — the licence lines of each Commons page, as read on 2026-10-18

Fetched with the Commons API (`action=query&prop=imageinfo|revisions`), verbatim:

- **BAN** — `== {{int:license-header}} ==` `{{self|Cc-zero}}`; extmetadata LicenseShortName `CC0`.
- **DNK** — `|permission= {{Insignia}}{{PD-shape}}`; LicenseShortName `Public domain`.
- **ENG** — `== {{int:license-header}} ==` `{{PD-shape}}{{insignia}}`; LicenseShortName `Public domain`.
- **ESP** — `{{PD-Self}}{{insignia}}`; LicenseShortName `Public domain`.
- **GEN** — `== {{int:license-header}} ==` `{{PD-self}}` `{{insignia}}`; LicenseShortName `Public domain`.
- **HAN** — `{{PD-Flag-Germany}}`; LicenseShortName `Public domain`.
- **JOS** — `=={{int:license-header}}==` `{{PD-South Korea}}` `{{PD-US-expired|country= KR|hide_us_warning= 1}}` `{{PD-old-assumed}}` (the page also carries `{{PD-old-100}}`); LicenseShortName `Public domain`.
- **JPN** — `== {{int:license-header}} ==` `{{PD-JapanGov|type=flags}}` `{{PD-shape}}` `{{Insignia}}`; LicenseShortName `Public domain`.
- **MAR** — `== {{int:license-header}} ==` `{{PD-self}}`; LicenseShortName `Public domain`.
- **NLD** — `== {{int:license-header}} ==` `{{PD-self}}`; LicenseShortName `Public domain`.
- **PER** — `{{self|PD-user-w}}`; LicenseShortName `Public domain`.
- **POL** — `=={{int:license-header}}==` `{{PD-self}}`; LicenseShortName `Public domain`.
- **RUS** — `|Permission={{insignia}}{{PD-RU-exempt|type=flags}}`; LicenseShortName `Public domain`.
- **SWE** — `|permission={{PD-shape}}{{insignia}}`; LicenseShortName `Public domain`.
- Reference designs for two original drawings: **PRT** (1521) — `== {{int:license-header}} ==` `{{PD-self}}` `{{PD-old}}` `{{insignia}}`; **VEN** — `{{PD-self}}`.
