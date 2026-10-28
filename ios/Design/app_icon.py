# MonkeyFit app icons ("Wink", #845). Writes 1024 SVGs for the main icon and the
# Iron / Titan / Legend reward icons:  python3 ios/Design/app_icon.py <outdir>
# Render to PNG (no alpha) with ios/Design/render_icons.js.
import sys, os

PALETTES = {
    "AppIcon": dict(bg=("#3C6CFF", "#8B4DFF", "#F54FCF"), fur=("#F1FF9E", "#C9F443", "#7DC21C"),
                    edge="#6FAE16", ear="#2A1046", accent="#D7FA5C", band=("#FF6FA6", "#E8306F", "#FFB3CF"),
                    shadow="#2A0A5E", dots="#fff", extra=""),
    "Iron": dict(bg=("#3A4458", "#1E2433", "#0D1018"), fur=("#FFFFFF", "#D3D8E2", "#8E97A8"),
                 edge="#6E7788", ear="#1C2130", accent="#EEF1F6", band=("#7E93B8", "#4F6487", "#B8C6DE"),
                 shadow="#000", dots="#9AA6BC", extra=""),
    "Titan": dict(bg=("#8E4BFF", "#5A1FC4", "#2A0A5E"), fur=("#FFF3B0", "#FFCF3F", "#D8920F"),
                  edge="#B9780A", ear="#2A1046", accent="#FFE27A", band=("#B57BFF", "#7B3FE4", "#DCC2FF"),
                  shadow="#14002E", dots="#FFD84D", extra="bolt"),
    "Legend": dict(bg=("#F0365A", "#B0123A", "#4A0718"), fur=("#FFF3B0", "#FFCF3F", "#D8920F"),
                   edge="#B9780A", ear="#3A0A18", accent="#FFE27A", band=("#FFFFFF", "#FFD6DE", "#FFFFFF"),
                   shadow="#2A0010", dots="#FFD84D", extra="crown"),
}

def defs(p):
    bg, fur, band = p["bg"], p["fur"], p["band"]
    return f'''<defs>
<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{bg[0]}"/><stop offset=".55" stop-color="{bg[1]}"/><stop offset="1" stop-color="{bg[2]}"/></linearGradient>
<radialGradient id="halo" cx=".5" cy=".55" r=".5"><stop offset="0" stop-color="#fff" stop-opacity=".28"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>
<radialGradient id="fur" cx=".36" cy=".28" r=".85"><stop offset="0" stop-color="{fur[0]}"/><stop offset=".45" stop-color="{fur[1]}"/><stop offset="1" stop-color="{fur[2]}"/></radialGradient>
<linearGradient id="handle" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="{fur[0]}"/><stop offset=".5" stop-color="{fur[1]}"/><stop offset="1" stop-color="{fur[2]}"/></linearGradient>
<radialGradient id="ear" cx=".4" cy=".35" r=".8"><stop offset="0" stop-color="{fur[0]}"/><stop offset="1" stop-color="{fur[2]}"/></radialGradient>
<radialGradient id="mask" cx=".45" cy=".3" r=".9"><stop offset="0" stop-color="#3B1A5C"/><stop offset="1" stop-color="#1A0830"/></radialGradient>
<radialGradient id="eye" cx=".4" cy=".35" r=".75"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#E4E0F2"/></radialGradient>
<radialGradient id="iris" cx=".4" cy=".35" r=".7"><stop offset="0" stop-color="#6B4A2B"/><stop offset="1" stop-color="#2A1608"/></radialGradient>
<linearGradient id="band" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{band[0]}"/><stop offset="1" stop-color="{band[1]}"/></linearGradient>
<linearGradient id="gold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFF3B0"/><stop offset="1" stop-color="#FFB81C"/></linearGradient>
<filter id="sh" x="-20%" y="-20%" width="140%" height="150%"><feDropShadow dx="0" dy="26" stdDeviation="26" flood-color="{p["shadow"]}" flood-opacity=".45"/></filter>
<clipPath id="headc"><circle cx="512" cy="600" r="262"/></clipPath>
</defs>'''

def extra(kind):
    if kind == "bolt":
        return ('<path d="M 204 170 L 304 380 L 224 380 L 272 540 L 124 300 L 212 300 L 154 170 Z" fill="url(#gold)" stroke="#B9780A" stroke-width="10" stroke-linejoin="round"/>')
    if kind == "crown":
        return ('<path d="M392 132 L 420 40 L 466 100 L 512 22 L 558 100 L 604 40 L 632 132 Z" fill="url(#gold)" stroke="#B9780A" stroke-width="10" stroke-linejoin="round"/>'
                '<circle cx="420" cy="40" r="18" fill="#FF3B6B"/><circle cx="512" cy="22" r="20" fill="#FF3B6B"/><circle cx="604" cy="40" r="18" fill="#FF3B6B"/>')
    return ''

def icon(p):
    a, band = p["accent"], p["band"]
    s = defs(p)
    s += '<rect width="1024" height="1024" fill="url(#bg)"/><circle cx="512" cy="560" r="470" fill="url(#halo)"/>'
    s += f'<g fill="{p["dots"]}" opacity=".55"><circle cx="150" cy="190" r="10"/><circle cx="880" cy="150" r="7"/><circle cx="905" cy="840" r="9"/><circle cx="118" cy="860" r="6"/></g>'
    s += '<g filter="url(#sh)">'
    s += extra(p["extra"])
    hp = 'M360 430 C 336 230, 396 150, 512 150 C 628 150, 688 230, 664 430'
    s += f'<path d="{hp}" fill="none" stroke="{p["edge"]}" stroke-width="86" stroke-linecap="round"/>'
    s += f'<path d="{hp}" fill="none" stroke="url(#handle)" stroke-width="70" stroke-linecap="round"/>'
    s += '<path d="M372 360 C 362 240, 410 178, 500 172" fill="none" stroke="#fff" stroke-width="14" stroke-linecap="round" opacity=".55"/>'
    for cx in (258, 766):
        s += f'<circle cx="{cx}" cy="622" r="92" fill="url(#ear)"/><circle cx="{cx}" cy="626" r="52" fill="{p["ear"]}"/><circle cx="{cx + (8 if cx < 512 else -8)}" cy="634" r="30" fill="#FF7FAE" opacity=".55"/>'
    s += '<circle cx="512" cy="600" r="262" fill="url(#fur)"/>'
    s += '<path d="M330 470 A 262 262 0 0 1 560 342" fill="none" stroke="#fff" stroke-width="16" stroke-linecap="round" opacity=".45"/>'
    # headband with short rounded tails
    s += f'<g clip-path="url(#headc)"><path d="M230 440 Q 512 380 794 440 L 794 512 Q 512 452 230 512 Z" fill="url(#band)"/><path d="M230 448 Q 512 388 794 448" fill="none" stroke="{band[2]}" stroke-width="10"/>'
    s += '<rect x="496" y="410" width="32" height="36" rx="10" fill="#fff" opacity=".9"/></g>'
    s += '<path d="M770 470 C 820 450, 860 420, 880 380 C 892 400, 890 430, 870 452 C 850 476, 816 486, 782 496 Z" fill="url(#band)"/>'
    s += f'<path d="M776 490 C 830 500, 862 530, 872 572 C 852 572, 830 560, 812 540 C 798 524, 786 512, 772 506 Z" fill="{band[1]}"/>'
    s += f'<circle cx="778" cy="486" r="22" fill="{band[0]}"/>'
    s += '</g>'
    # face mask, wink, nose, blush, grin
    s += '<path d="M512 548 C 470 492, 352 500, 352 604 C 352 650, 372 676, 388 694 C 356 724, 354 778, 384 812 C 420 852, 470 862, 512 862 C 554 862, 604 852, 640 812 C 670 778, 668 724, 636 694 C 652 676, 672 650, 672 604 C 672 500, 554 492, 512 548 Z" fill="url(#mask)"/>'
    s += '<ellipse cx="444" cy="626" rx="46" ry="46" fill="url(#eye)"/><circle cx="450" cy="634" r="29" fill="url(#iris)"/><circle cx="450" cy="634" r="17" fill="#0A0410"/><circle cx="462" cy="620" r="11" fill="#fff"/>'
    s += f'<path d="M532 640 Q 580 600 628 640" fill="none" stroke="{a}" stroke-width="20" stroke-linecap="round"/>'
    s += f'<ellipse cx="494" cy="718" rx="12" ry="9" fill="{a}" opacity=".9"/><ellipse cx="530" cy="718" rx="12" ry="9" fill="{a}" opacity=".9"/>'
    s += '<ellipse cx="392" cy="742" rx="34" ry="20" fill="#FF6FA8" opacity=".55"/><ellipse cx="632" cy="742" rx="34" ry="20" fill="#FF6FA8" opacity=".55"/>'
    s += ('<path d="M420 760 Q 512 776 604 760 Q 590 850 512 852 Q 434 850 420 760 Z" fill="#0A0410"/>'
          '<path d="M432 764 Q 512 778 592 764 L 588 786 Q 512 798 436 786 Z" fill="#fff"/>'
          '<path d="M462 830 Q 512 806 562 830 Q 540 850 512 851 Q 484 850 462 830 Z" fill="#FF6F91"/>')
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">{s}</svg>\n'

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    for name, p in PALETTES.items():
        open(os.path.join(out, f"{name}.svg"), "w").write(icon(p))
