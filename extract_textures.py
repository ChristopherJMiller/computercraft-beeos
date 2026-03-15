#!/usr/bin/env python3
"""Extract block textures from mod JARs for BeeOS isometric diagram."""

import zipfile
import os

MODS_DIR = "/home/chris/.local/share/PrismLauncher/instances/MeatballCraft, Dimensional Ascension/minecraft/mods"
OUTPUT_DIR = "/home/chris/Repos/computercraft-beeos/beeos-textures"

JARS_AND_PATTERNS = {
    "cc-tweaked-1.12.2-1.89.2.jar": {
        "patterns": ["computer", "monitor", "turtle", "modem", "cable"],
        "label": "CC-Tweaked"
    },
    "gendustry-1.6.5.8-mc1.12.2.jar": {
        "patterns": ["apiary", "sampler", "imprinter", "mutatron", "extractor"],
        "label": "Gendustry"
    },
    "forestry_1.12.2-5.8.2.426.jar": {
        "patterns": ["analy"],
        "label": "Forestry"
    },
    "ae2-uel-v0.56.5.jar": {
        "patterns": ["chest", "import", "export", "interface"],
        "label": "AE2"
    },
}

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    for jar_name, info in JARS_AND_PATTERNS.items():
        jar_path = os.path.join(MODS_DIR, jar_name)
        print(f"\n=== {info['label']} ({jar_name}) ===")
        if not os.path.exists(jar_path):
            print(f"  NOT FOUND")
            continue

        with zipfile.ZipFile(jar_path, 'r') as z:
            all_block = sorted([n for n in z.namelist()
                        if 'textures/block' in n.lower() and n.lower().endswith('.png')])
            print(f"  All block textures ({len(all_block)}):")
            for t in all_block:
                print(f"    {t}")

            matches = []
            for n in z.namelist():
                nl = n.lower()
                if 'textures/block' in nl and nl.endswith('.png'):
                    for pat in info['patterns']:
                        if pat in nl:
                            matches.append(n)
                            break

            subdir = os.path.join(OUTPUT_DIR, info['label'].lower())
            os.makedirs(subdir, exist_ok=True)
            for tex in matches:
                basename = os.path.basename(tex)
                out_path = os.path.join(subdir, basename)
                with z.open(tex) as src, open(out_path, 'wb') as dst:
                    dst.write(src.read())
                print(f"  EXTRACTED: {out_path}")

    print(f"\nDone. Output in: {OUTPUT_DIR}")

if __name__ == "__main__":
    main()
