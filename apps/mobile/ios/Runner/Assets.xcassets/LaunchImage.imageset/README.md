# Launch screen

`LaunchImage*.png` is the balloon from the app icon, in the icon's cream
(#FCF5E1) on transparency, 160pt tall. It is generated from
`AppIcon.appiconset/Icon-App-1024x1024@1x.png` by `tools/launch-image.py`, which
isolates the balloon by how far each pixel sits toward the balloon's red
(#EA212A) and away from the amber ground (#FBC204), crops to its bounding box,
and resamples the alpha rather than a coloured bitmap — resampling colour blends
red into amber and leaves an orange halo around the rigging.

The storyboard paints #0D1117 behind it, the app's `scaffoldBackgroundColor`. It
used to be white, so every launch of a dark app flashed white first.

Regenerate from the icon rather than editing these by hand, so the launch screen
cannot drift away from the icon it is taken from:

```bash
apps/server/.venv/bin/python tools/launch-image.py
```
