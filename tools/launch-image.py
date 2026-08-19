#!/usr/bin/env python3
"""Generate the iOS launch image from the app icon.

The launch screen shows the balloon from the icon, in the icon's cream, on the
app's own dark background. Taking it from the icon rather than drawing it again
is the point: the two cannot drift apart, and a rename or a redraw of the icon
regenerates the launch screen from the same source.

The balloon is isolated by redness rather than by a colour equality test, because
the icon is antialiased. Every pixel gets an alpha from how far toward the
balloon's red (#EA212A) it sits, away from the amber ground (#FBC204):

    redness = R - max(G, B)      amber 57, red 192, cream 7, cyan negative

so the amber ground, the cream Land Rover and the cyan chevrons all fall to zero
while the balloon's edges keep their smooth alpha. Masking on equality instead
would produce a hard, aliased cutout with an amber fringe.

The floor sits at 90 rather than at amber's 57, and anything fainter than alpha
32 is zeroed outright. The icon's amber is not one flat value - it is dozens of
near-amber shades - so a floor set just above amber let noise across the whole
square score a few units of alpha. Faint as it was, it was enough to put the
bounding box around the entire icon and shrink the balloon to a quarter of the
frame, with a ghost of the Land Rover behind it.

Only the alpha is resampled; the colour is filled flat afterwards. Resampling a
coloured bitmap blends the balloon's red into the amber behind it and leaves an
orange halo around the rigging.

    tools/launch-image.py
"""

from __future__ import annotations

import pathlib
import sys

from PIL import Image

ICON = "apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"
IMAGESET = "apps/mobile/ios/Runner/Assets.xcassets/LaunchImage.imageset"

# The Land Rover's cream, so the launch screen is the icon's own palette.
CREAM = (252, 245, 225)

# Point height of the launch image. Big enough to read as a balloon on a phone,
# small enough that it is not competing with the app that replaces it.
HEIGHT_POINTS = 160

REDNESS_FLOOR = 90
BALLOON_REDNESS = 192

# Below this the pixel is icon noise, not a soft balloon edge.
ALPHA_NOISE_FLOOR = 32


def balloon_alpha(icon: Image.Image) -> Image.Image:
    alpha = Image.new("L", icon.size)
    span = BALLOON_REDNESS - REDNESS_FLOOR
    raw = icon.convert("RGB").tobytes()
    pixels = bytearray(len(raw) // 3)
    for index in range(len(pixels)):
        red, green, blue = raw[index * 3], raw[index * 3 + 1], raw[index * 3 + 2]
        redness = red - max(green, blue)
        scaled = (redness - REDNESS_FLOOR) * 255 // span
        if scaled < ALPHA_NOISE_FLOOR:
            scaled = 0
        pixels[index] = 255 if scaled > 255 else scaled
    alpha.frombytes(bytes(pixels))
    return alpha


def main() -> int:
    root = pathlib.Path(__file__).resolve().parent.parent
    icon_path = root / ICON
    if not icon_path.is_file():
        print(f"launch-image: no icon at {ICON}", file=sys.stderr)
        return 1

    alpha = balloon_alpha(Image.open(icon_path))
    box = alpha.getbbox()
    if box is None:
        print("launch-image: no balloon found in the icon", file=sys.stderr)
        return 1
    alpha = alpha.crop(box)

    for scale in (1, 2, 3):
        height = HEIGHT_POINTS * scale
        width = round(alpha.width * height / alpha.height)
        resized = alpha.resize((width, height), Image.LANCZOS)
        image = Image.new("RGBA", resized.size, (*CREAM, 0))
        image.putalpha(resized)
        suffix = "" if scale == 1 else f"@{scale}x"
        out = root / IMAGESET / f"LaunchImage{suffix}.png"
        image.save(out)
        print(f"{out.relative_to(root)}  {width}x{height}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
