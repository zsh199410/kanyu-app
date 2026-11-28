#!/usr/bin/env python3
"""Original hand-drawn vector artwork; no SF Symbols, font glyphs or external assets.
The four architectural/ornamental compositions are independent, not recolored copies.
CairoSVG 2.8.2 (LGPL-3.0-or-later) is an authoring tool only; PNGs are bundled, no runtime dependency.
"""
from pathlib import Path
import cairosvg
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'Resources/V5Artwork'; SRC=Path(__file__).parent/'vectors'
DEFS='''<defs><linearGradient id="gold" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#fff0c6"/><stop offset=".34" stop-color="#b98b44"/><stop offset=".62" stop-color="#f8dc94"/><stop offset="1" stop-color="#92662e"/></linearGradient><radialGradient id="jade" cx=".32" cy=".22" r=".85"><stop stop-color="#b9d7bd"/><stop offset=".48" stop-color="#52896b"/><stop offset="1" stop-color="#174e3e"/></radialGradient><linearGradient id="pearl" x2=".8" y2="1"><stop stop-color="#fffef2"/><stop offset=".5" stop-color="#d7e7d8"/><stop offset="1" stop-color="#6faaa0"/></linearGradient><linearGradient id="lacquer" x2="1" y2="1"><stop stop-color="#bb3c29"/><stop offset=".5" stop-color="#6a1714"/><stop offset="1" stop-color="#30100e"/></linearGradient></defs>'''
ART={
'song':{
'home':'''<path fill="url(#jade)" d="M23 55H105V62H98V99H30V62H23Z"/><path fill="url(#gold)" d="M12 52Q35 47 55 25Q61 18 64 14Q67 20 73 25Q93 47 116 52L109 61Q82 55 64 41Q46 55 19 61Z"/><path d="M26 50Q49 43 64 26Q79 43 102 50M26 66H102M22 105H106M17 112H111"/><path d="M39 67V98M52 67V98M76 67V98M89 67V98"/><path fill="#e9dcae" d="M58 98V77Q64 69 70 77V98Z"/>''',
'measure':'''<circle cx="64" cy="64" r="47" fill="none"/><circle cx="64" cy="64" r="40" opacity=".5"/><path d="M64 12V23M64 105V116M12 64H23M105 64H116M27 27L34 34M94 94L101 101M27 101L34 94M94 34L101 27"/><path fill="url(#jade)" d="M83 38L73 75L43 91L54 54Z"/><path fill="url(#gold)" d="M83 38L54 54L64 64Z"/><circle cx="64" cy="64" r="5" fill="#f9e6b6"/>''',
'reports':'''<path fill="#f5efda" d="M14 26Q39 19 62 33V108Q39 93 14 101ZM66 33Q89 19 114 26V101Q89 93 66 108Z"/><path d="M14 26Q39 19 62 33V108Q39 93 14 101ZM66 33Q89 19 114 26V101Q89 93 66 108ZM64 31V109"/><path stroke="#2d6752" d="M22 76L34 57L42 67L52 45M76 76Q85 66 91 72L105 49M24 86Q39 79 53 88M75 87Q91 79 105 86"/><path d="M11 32H7V109Q37 101 62 116H66Q91 101 121 109V32H117"/>''',
'profiles':'''<circle cx="64" cy="39" r="21" fill="url(#jade)"/><path fill="url(#jade)" d="M21 110V96Q22 75 42 70Q64 86 86 70Q106 75 107 96V110Z"/><path d="M43 39Q44 16 64 16Q84 16 85 39M39 111H89M22 110H106M34 86Q45 99 64 99Q83 99 94 86"/><path d="M54 65Q64 73 74 65"/>'''
},
'night':{
'home':'''<path fill="#162f45" d="M32 57H96V107H32Z"/><path fill="url(#gold)" d="M17 52Q35 48 51 31L64 18L77 31Q93 48 111 52L101 60L64 45L27 60Z"/><path d="M27 69H101M24 111H104M43 71V106M85 71V106"/><path d="M54 106V83Q64 69 74 83V106"/><path d="M50 11Q64 25 78 11Q69 42 50 11Z" fill="#f9df9e"/><path d="M12 21L15 28L22 31L15 34L12 41L9 34L2 31L9 28ZM111 77L114 83L120 86L114 89L111 95L108 89L102 86L108 83Z" fill="url(#gold)" stroke-width="1"/>''',
'measure':'''<ellipse cx="64" cy="66" rx="49" ry="32" transform="rotate(-32 64 66)"/><ellipse cx="64" cy="66" rx="31" ry="49" transform="rotate(-32 64 66)" opacity=".6"/><circle cx="64" cy="66" r="35" fill="#152e44"/><path fill="url(#gold)" d="M64 13L71 51L106 35L79 65L114 78L76 78L84 115L64 85L43 115L51 78L13 78L48 65L22 35L57 51Z" stroke-width="1"/><circle cx="64" cy="66" r="10" fill="#102437"/><circle cx="64" cy="66" r="4" fill="#fff0be"/>''',
'reports':'''<path fill="#18344a" d="M23 31Q40 22 61 37L63 104Q41 91 23 98ZM67 37Q88 22 105 31V98Q86 91 65 104Z"/><path d="M23 31Q40 22 61 37L63 104Q41 91 23 98ZM67 37Q88 22 105 31V98Q86 91 65 104ZM18 36Q5 33 8 47L12 105Q34 97 62 114H66Q94 97 116 105L120 47Q123 33 110 36"/><path d="M32 73L40 47L52 62L43 83M77 52L91 46L99 68L81 80Z" stroke-width="1.5"/><g fill="#fff0bd"><circle cx="32" cy="73" r="3"/><circle cx="40" cy="47" r="3"/><circle cx="52" cy="62" r="3"/><circle cx="91" cy="46" r="3"/><circle cx="99" cy="68" r="3"/></g>''',
'profiles':'''<circle cx="64" cy="41" r="20" fill="#19394c"/><path d="M44 41Q45 21 64 21Q83 21 84 41M45 45Q49 66 64 66Q79 66 83 45"/><path fill="#18364c" d="M25 111Q21 84 44 76Q64 89 84 76Q107 84 103 111Z"/><path d="M25 111Q21 84 44 76Q64 89 84 76Q107 84 103 111ZM33 14Q13 36 21 66M95 14Q115 36 107 66"/><path d="M16 75L20 83L28 87L20 91L16 99L12 91L4 87L12 83ZM105 17L108 23L114 26L108 29L105 35L102 29L96 26L102 23Z" fill="url(#gold)" stroke-width="1"/>'''
},
'celadon':{
'home':'''<path fill="url(#pearl)" d="M20 110V48Q64 -3 108 48V110H91V51Q64 20 37 51V110Z"/><path d="M20 110V48Q64 -3 108 48V110H91V51Q64 20 37 51V110ZM38 110H90M14 116H114"/><path d="M43 75Q56 69 64 58Q72 69 85 75L79 81H49ZM52 82V105M76 82V105" fill="url(#pearl)"/><path d="M4 87Q13 74 24 80M96 35Q106 29 116 35M8 96Q17 89 28 94" opacity=".55"/>''',
'measure':'''<path fill="url(#pearl)" d="M64 9Q96 18 108 48Q117 82 90 105Q64 123 38 105Q11 82 20 48Q32 18 64 9Z"/><path d="M64 9Q96 18 108 48Q117 82 90 105Q64 123 38 105Q11 82 20 48Q32 18 64 9Z"/><path stroke="#397b70" d="M37 88Q55 49 91 33Q75 71 37 88ZM43 82L82 43M64 64L64 49M64 64L79 64"/><circle cx="64" cy="64" r="5" fill="#f9f5df"/>''',
'reports':'''<path fill="url(#pearl)" d="M24 22L42 18L49 106L31 110ZM46 17L64 16L66 105L53 106ZM69 16L87 18L80 106L70 105ZM91 19L109 24L98 112L85 108Z"/><path d="M24 22L42 18L49 106L31 110ZM46 17L64 16L66 105L53 106ZM69 16L87 18L80 106L70 105ZM91 19L109 24L98 112L85 108ZM24 47Q65 59 106 48M28 86Q65 77 101 87"/><path stroke="#478c7b" d="M15 28Q4 56 21 93M13 48L3 37M14 64L3 59M17 78L6 80" stroke-width="2"/>''',
'profiles':'''<ellipse cx="49" cy="40" rx="17" ry="21" fill="url(#pearl)"/><ellipse cx="88" cy="51" rx="13" ry="16" fill="url(#pearl)"/><path fill="url(#pearl)" d="M16 102Q17 74 38 69Q49 78 60 69Q80 75 82 102ZM82 82Q91 76 102 80Q117 88 114 108H87Z"/><path d="M16 102Q17 74 38 69Q49 78 60 69Q80 75 82 102ZM82 82Q91 76 102 80Q117 88 114 108H87ZM33 117Q48 105 64 117Q80 105 96 117"/><path d="M33 117Q40 126 48 117M64 117Q72 126 80 117" stroke-width="1.7"/>'''
},
'collection':{
'home':'''<path fill="url(#lacquer)" d="M24 53H104V106H24Z"/><path fill="url(#gold)" d="M8 43Q35 45 49 26L64 13L79 26Q93 45 120 43L110 55Q86 52 64 38Q42 52 18 55Z"/><path d="M16 66H112M32 57V102M96 57V102M19 110H109M13 117H115"/><path fill="#211713" d="M47 104V78Q64 62 81 78V104Z"/><path d="M64 76V104M38 26L43 18M90 26L85 18M26 89H39M89 89H102"/>''',
'measure':'''<path fill="url(#lacquer)" d="M21 21H107V107H21Z"/><path d="M21 21H107V107H21ZM14 14H114V114H14"/><circle cx="64" cy="64" r="35"/><circle cx="64" cy="64" r="26"/><path fill="url(#gold)" d="M77 40L71 72L45 89L56 56Z"/><path d="M64 24V32M64 96V104M24 64H32M96 64H104M32 32L37 37M91 91L96 96M32 96L37 91M91 37L96 32" stroke-width="2"/><path d="M26 11H43M85 11H102M26 117H43M85 117H102M11 26V43M11 85V102M117 26V43M117 85V102" stroke-width="1.5"/>''',
'reports':'''<path fill="url(#lacquer)" d="M27 17L104 25V113L27 105Z"/><path d="M27 17L104 25V113L27 105ZM20 24V109L98 119M34 20V106M43 30L94 35V98L43 92Z"/><path d="M49 57Q60 41 72 52Q79 59 89 53M49 70Q63 80 75 65Q82 58 90 68M49 84Q59 74 72 84Q83 91 91 80" stroke-width="2"/><path d="M17 36L33 38M17 60L33 62M17 84L33 86" stroke-width="4"/>''',
'profiles':'''<ellipse cx="64" cy="45" rx="21" ry="25" fill="url(#gold)"/><path fill="url(#lacquer)" d="M43 41Q42 15 64 15Q86 15 85 41Q72 31 64 33Q56 31 43 41Z"/><path fill="url(#lacquer)" d="M22 111Q21 82 44 76L64 94L84 76Q107 82 106 111Z"/><path d="M22 111Q21 82 44 76L64 94L84 76Q107 82 106 111ZM39 87L49 109M89 87L79 109M54 9Q64 1 74 9"/><path d="M13 64Q2 50 13 39M115 64Q126 50 115 39M7 75Q16 67 24 75M104 75Q112 67 121 75" stroke-width="2"/>'''
}}

def write(name,body,w=384,h=384,view='0 0 128 128'):
    svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="{view}">{DEFS}<g fill="none" stroke="url(#gold)" stroke-width="3" stroke-linejoin="round" stroke-linecap="round">{body}</g></svg>'
    path=SRC/(name+'.svg');path.write_text(svg)
    cairosvg.svg2png(bytestring=svg.encode(), write_to=str(OUT/(name+'.png')), output_width=w, output_height=h)

for theme,icons in ART.items():
    for role,body in icons.items(): write(f'v5-{theme}-nav-{role}',body)

# Four independent wide ornaments, not scaled or recolored versions of one path.
FLOURISH={
'song':'''<path d="M20 273Q149 188 268 234T509 215Q651 144 795 193T1183 145M24 292Q151 220 281 251T521 235Q681 173 814 216T1188 169M20 307Q165 254 296 270T537 255Q693 205 839 240T1180 193"/><path d="M86 248Q147 149 227 192Q284 112 353 183Q420 92 482 174Q533 122 584 178M771 183Q822 103 890 133Q951 58 1009 119Q1066 63 1125 109" stroke-width="2"/>''',
'night':'''<path d="M16 280Q353 317 567 181Q755 72 1185 86M27 312Q365 339 587 211Q798 82 1181 109M105 328Q416 340 638 226Q840 127 1184 136"/><path d="M325 219L419 133L553 155L692 70L827 124L960 58L1107 84" stroke-width="1.5"/><g fill="url(#gold)"><circle cx="325" cy="219" r="6"/><circle cx="419" cy="133" r="8"/><circle cx="553" cy="155" r="5"/><circle cx="692" cy="70" r="9"/><circle cx="827" cy="124" r="6"/><circle cx="960" cy="58" r="8"/></g><path d="M692 47V93M669 70H715M960 38V78M940 58H980" stroke-width="2"/>''',
'celadon':'''<path d="M12 278Q164 193 330 251Q485 296 596 180Q741 40 916 155Q1012 218 1184 157M20 302Q197 236 350 277Q510 316 625 208Q751 93 908 181Q1040 249 1183 190" stroke="#72aaa0"/><path d="M298 235Q205 201 216 132Q300 134 323 204Q345 111 427 114Q433 195 344 234Q399 247 433 208M778 118Q715 55 760 18Q825 58 795 119Q839 54 901 77Q887 137 807 136" fill="url(#pearl)" stroke-width="2"/><path d="M41 276Q54 246 81 258Q82 219 114 226Q142 230 132 256Q162 242 175 266" stroke-width="2"/>''',
'collection':'''<path d="M20 286Q164 301 270 222Q384 140 493 202Q602 274 719 186Q855 91 1018 157Q1114 193 1187 161M20 307Q167 327 283 246Q393 166 501 227Q604 292 733 211Q870 117 1025 183Q1120 220 1188 188"/><path d="M84 268Q78 207 129 201Q143 153 194 166Q238 178 217 214Q242 214 252 238M884 131Q895 71 941 83Q967 32 1010 59Q1047 83 1014 110Q1056 101 1073 142" stroke-width="2"/><path d="M529 204Q565 147 601 204Q565 260 529 204ZM540 204Q565 179 590 204Q565 229 540 204Z" fill="url(#lacquer)" stroke-width="2"/><path d="M273 222L302 193L331 215L360 176L389 193M724 186L754 154L784 173L814 139L844 151" stroke-width="2"/>'''
}
for theme,body in FLOURISH.items():write(f'v5-{theme}-flourish',body,1200,360,'0 0 1200 360')
print('Rendered 16 original navigation icons and 4 independent ornaments')
