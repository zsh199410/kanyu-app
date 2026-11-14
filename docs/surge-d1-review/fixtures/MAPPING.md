# D1 fixture mapping (synthetic, mirrors 13:24 native test)

All connection parameters are synthetic (TEST-NET hosts, password TEST-ONLY-NOT-A-REAL-NODE). Only the DECISION structure mirrors the real 13:24 test: names, native ms, P0 ms, pass/slow/fail.

| tag | mirrors | proto | native | P0 | verdict |
|---|---|---|---|---|---|
| T01 | 美国9 🇺🇸 | trojan | 232 | 241 | PASS |
| T02 | 美国11 🇺🇸 | trojan | 271 | 280 | PASS |
| T03 | 美国12 🇺🇸 | trojan | 265 | 279 | PASS |
| T04 | 香港 🇭🇰 | trojan | 119 | 105 | PASS |
| T05 | 美国1 🇺🇸 | trojan | 240 | 237 | PASS |
| T06 | 美国7 🇺🇸 | trojan | 264 | 237 | PASS |
| T07 | 美国10 🇺🇸 | trojan | 242 | 252 | PASS |
| T08 | 美国5 🇺🇸 | trojan | 280 | 245 | PASS |
| T09 | 美国2 🇺🇸 | trojan | 260 | 297 | PASS (conditional: P0 281-297) |
| T10 | 香港2 🇭🇰 | trojan | 131 | 106 | PASS |
| T11 | 美国3 🇺🇸 | trojan | 320 | 254 | REJECT (native slow) |
| T12 | 美国13 🇺🇸 | trojan | 264 | 281 | PASS (conditional: P0 281-297) |
| T13 | 美国8 🇺🇸 | trojan | 232 | 296 | PASS (conditional: P0 281-297) |
| T14 | 美国4 🇺🇸 | trojan | 264 | 245 | PASS |
| T15 | 美国6 🇺🇸 | trojan | 1018 | 252 | REJECT (native slow) |
| T16 | 香港8 🇭🇰 | trojan | 983 | 255 | REJECT (native slow) |
| T17 | 香港24 🇭🇰 | trojan | 321 | 199 | REJECT (native slow) |
| T18 | 香港25 🇭🇰 | trojan | fail | fail | REJECT (native fail) |
| T19 | 香港34 🇭🇰 | trojan | fail | fail | REJECT (native fail) |
| T20 | 香港36 🇭🇰 | trojan | 75 | 90 | PASS |
| T21 | 香港39 🇭🇰 | trojan | fail | fail | REJECT (native fail) |
| T22 | 美国14 🇺🇸 | trojan | fail | fail | REJECT (native fail) |
| T23 | 伊朗5 🇮🇷 | ss | fail | fail | REJECT (native fail) |
| T24 | 美国20 🇺🇸 | ss | fail | fail | REJECT (native fail) |
| T25 | 伊朗9 🇮🇷 | ss | fail | fail | REJECT (native fail) |
| T26 | 美国30 🇺🇸 | ss | fail | fail | REJECT (native fail) |
| T27 | 伊朗10 🇮🇷 | ss | fail | fail | REJECT (native fail) |
| T28 | 伊朗13 🇮🇷 | ss | fail | fail | REJECT (native fail) |
| T29 | 美国34 🇺🇸 | ss | fail | fail | REJECT (native fail) |
| T30 | 美国35 🇺🇸 | ss | fail | fail | REJECT (native fail) |
| T31 | 美国36 🇺🇸 | trojan | fail | fail | REJECT (native fail) |
| T32 | 美国40 🇺🇸 | trojan | fail | fail | REJECT (native fail) |
| T33 | 伊朗3 🇮🇷 | ss | fail | fail | REJECT (native fail) |
| T34 | 美国 🇺🇸 | ss | fail | fail | REJECT (native fail) |
| T35 | 伊朗 🇮🇷 | ss | fail | fail | REJECT (native fail) |
| T36 | 美国15 🇺🇸 | ss | fail | fail | REJECT (native fail) |
| T37 | 美国16 🇺🇸 | ss | fail | fail | REJECT (native fail) |
| T38 | 伊朗2 🇮🇷 | ss | fail | fail | REJECT (native fail) |
| T39 | 美国17 🇺🇸 | ss | fail | fail | REJECT (native fail) |
| T40 | 美国18 🇺🇸 | ss | fail | fail | REJECT (native fail) |
| T41 | 伊朗4 🇮🇷 | ss | fail | fail | REJECT (native fail) |
| T42 | 美国19 🇺🇸 | ss | fail | fail | REJECT (native fail) |
| T43 | 伊朗6 🇮🇷 | ss | fail | fail | REJECT (native fail) |
| T44 | 美国21 🇺🇸 | ss | fail | fail | REJECT (native fail) |

Fixture pool SHA256: `f6083ad90eacb422af5cc1dbc84d616864fc5e2071a0931ddc6672c379b468ed`
Fixture clean-14 SHA256: `6074082847c3deee566313c625445579fad8c345c6ad5815a3655fa4a0c55286`
Real 13:24 pool SHA256: `1360ab7ca83b75427a616c03c84bcdf69bd9a0af3aee69befd849636db9421d6` (44 lines); real clean-14 SHA256: `32a0a0fb24160a15bd2fd8edf188d631a76848b67e36a8605c46eb3540aae8b1`.
Fixture SHAs differ because connection parameters are synthetic; fingerprints are computed with the identical algorithm.
