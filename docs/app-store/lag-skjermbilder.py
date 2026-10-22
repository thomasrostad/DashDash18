#!/usr/bin/env python3
"""Lager App Store-skjermbildene (6,9 tommer, 1320 × 2868) fra AppStoreScreenshotTests.

1. Kjør UI-testen på iPhone 17 Pro Max (gjerne med statuslinjen satt til 9:41 først):

   xcrun simctl status_bar 'iPhone 17 Pro Max' override --time 9:41 --batteryState charged --batteryLevel 100
   xcodebuild test -project DashDash18.xcodeproj -scheme DashDash18 \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
     -derivedDataPath ~/Library/Developer/Xcode/DerivedData/DashDash18-cli \
     -only-testing:DashDash18UITests/AppStoreScreenshotTests \
     -resultBundlePath ~/Library/Developer/Xcode/skjermbilder.xcresult

2. Lag bildene:

   python3 docs/app-store/lag-skjermbilder.py ~/Library/Developer/Xcode/skjermbilder.xcresult ~/Desktop/Atten-skjermbilder

Henter vedleggene `01-…` til `06-…` med xcresulttool og setter overskriften øverst i Figtree,
krem på skoggrønt (DDToken.forest og .onDark). Krever Pillow. Bildene sjekkes ikke inn i git.
"""

import json
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# Overskriftene står i App Store-søket (Apple leser teksten i bildet), så de må være store og tydelige.
HEADLINES = {
    "01-kvelden": "Golfkvelden med gjengen, samlet",
    "02-hullkort": "Scorekort hull for hull",
    "03-tavla": "Tavla oppdateres mens dere spiller",
    "04-sesong": "Liga og cup hele sesongen",
    "05-nyturnering": "Stableford, slagspill og matchspill",
    "06-feiring": "Hvem tar jakka i år?",
}

WIDTH, HEIGHT = 1320, 2868
# Fra DashDash18/DesignSystem/DDPalette.swift (lys modus).
FOREST = (0x1C, 0x48, 0x3A)
ON_DARK = (0xFF, 0xF9, 0xDF)
GOLD = (0xE4, 0xC7, 0x67)

REPO = Path(__file__).resolve().parents[2]
FONT = REPO / "DashDash18/Resources/Fonts/Figtree-Variable.ttf"

HEADLINE_SIZE = 116
SIDE_MARGIN = 90
SHOT_SCALE = 0.76
SHOT_TOP = 640
BORDER = 6
BORDER_COLOR = (0x3D, 0x6B, 0x5B)


def export_attachments(xcresult: Path, out: Path) -> dict[str, Path]:
    subprocess.run(
        ["xcrun", "xcresulttool", "export", "attachments", "--path", str(xcresult), "--output-path", str(out)],
        check=True,
    )
    found = {}
    for test in json.loads((out / "manifest.json").read_text()):
        for attachment in test.get("attachments", []):
            name = attachment.get("suggestedHumanReadableName", "")
            for key in HEADLINES:
                if name.startswith(key):
                    found[key] = out / attachment["exportedFileName"]
    return found


def wrap(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont, max_width: int) -> list[str]:
    """Én linje hvis den får plass, ellers to linjer delt så de blir omtrent like lange (ingen enslige ord)."""
    if draw.textlength(text, font=font) <= max_width:
        return [text]
    words = text.split()
    splits = [(" ".join(words[:i]), " ".join(words[i:])) for i in range(1, len(words))]
    return list(min(splits, key=lambda pair: max(draw.textlength(part, font=font) for part in pair)))


def compose(shot_path: Path, headline: str, target: Path) -> None:
    canvas = Image.new("RGB", (WIDTH, HEIGHT), FOREST)
    draw = ImageDraw.Draw(canvas)

    font = ImageFont.truetype(str(FONT), HEADLINE_SIZE)
    font.set_variation_by_name("Bold")
    line_height = int(HEADLINE_SIZE * 1.12)
    lines = wrap(draw, headline, font, WIDTH - 2 * SIDE_MARGIN)
    # Sentrer overskriften og streken i feltet over skjermbildet.
    block = len(lines) * line_height + 42
    y = (SHOT_TOP - block) // 2
    for line in lines:
        draw.text((WIDTH / 2, y), line, font=font, fill=ON_DARK, anchor="ma")
        y += line_height
    draw.rounded_rectangle((WIDTH / 2 - 60, y + 30, WIDTH / 2 + 60, y + 42), radius=6, fill=GOLD)

    shot = Image.open(shot_path).convert("RGB")
    w = int(WIDTH * SHOT_SCALE)
    h = int(shot.height * w / shot.width)
    shot = shot.resize((w, h), Image.LANCZOS)
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), radius=int(w * 0.11), fill=255)
    x = (WIDTH - w) // 2
    radius = int(w * 0.11)
    # Tynn lys kant, så mørke skjermer (feiringen) skiller seg fra bakgrunnen.
    draw.rounded_rectangle((x - BORDER, SHOT_TOP - BORDER, x + w + BORDER - 1, SHOT_TOP + h + BORDER - 1),
                           radius=radius + BORDER, fill=BORDER_COLOR)
    canvas.paste(shot, (x, SHOT_TOP), mask)

    canvas.save(target, "PNG")


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("Bruk: lag-skjermbilder.py <resultat.xcresult> <mappe for PNG-ene>")
    xcresult, out = Path(sys.argv[1]).expanduser(), Path(sys.argv[2]).expanduser()
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        shots = export_attachments(xcresult, Path(tmp))
        missing = [key for key in HEADLINES if key not in shots]
        if missing:
            sys.exit(f"Mangler vedlegg i {xcresult}: {', '.join(missing)}")
        for key, headline in HEADLINES.items():
            target = out / f"{key}.png"
            compose(shots[key], headline, target)
            print(target)


if __name__ == "__main__":
    main()
