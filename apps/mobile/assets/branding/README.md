# Balloon Crumbs app icon

`balloon-crumbs-app-icon-master.png` is the opaque, square master. Derivative
iOS and Android sizes are checked into their respective platform asset folders
and are generated from this file — regenerate rather than edit them:

```bash
M=assets/branding/balloon-crumbs-app-icon-master.png
for f in ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png \
         $(find android/app/src/main/res -name 'ic_launcher*.png'); do
  W=$(sips -g pixelWidth "$f" | tail -1 | awk '{print $2}')
  sips -s format png -z "$W" "$W" "$M" --out "$f"
done
```

The mark is a cream Land Rover Defender on a yellow field with a red hot-air
balloon ahead of it and two cyan chevrons between the two: the balloon flies,
the chase vehicle follows. It replaces the inherited two-motorcycle relay mark
on a purple field.

It is original artwork and uses no Land Rover, Jaguar Land Rover or
Harley-Davidson artwork or trademarks. "Defender" is a Jaguar Land Rover
trademark; the silhouette here is a generic stylised utility 4x4 and the name is
not used in the product, the store listing, or any user-facing copy.

Every derivative must stay opaque with no alpha channel — the App Store rejects
a 1024x1024 icon that carries one.
