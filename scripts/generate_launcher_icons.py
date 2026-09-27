"""Resize the approved logo for launcher assets. Requires Pillow."""
from pathlib import Path
import json
from PIL import Image

root = Path(__file__).resolve().parents[1]
image = Image.open(root / 'assets/branding/qr-app-logo.png').convert('RGB')
res = root / 'android/app/src/main/res'
for density, size in [('mdpi',48), ('hdpi',72), ('xhdpi',96), ('xxhdpi',144), ('xxxhdpi',192)]:
    image.resize((size, size), Image.Resampling.LANCZOS).save(res / f'mipmap-{density}/ic_launcher.png')
(res / 'drawable-nodpi').mkdir(exist_ok=True)
image.resize((432, 432), Image.Resampling.LANCZOS).save(res / 'drawable-nodpi/launcher_logo.png')
(res / 'mipmap-anydpi-v26').mkdir(exist_ok=True)
(res / 'mipmap-anydpi-v26/ic_launcher.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/launcher_background" />
    <foreground android:drawable="@drawable/launcher_foreground" />
</adaptive-icon>
''')
(res / 'values/launcher_colors.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<resources><color name="launcher_background">#006AFF</color></resources>
''')
(res / 'drawable/launcher_foreground.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<inset xmlns:android="http://schemas.android.com/apk/res/android" android:inset="18%">
    <bitmap android:src="@drawable/launcher_logo" android:gravity="fill" />
</inset>
''')
icons = root / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for entry in json.loads((icons / 'Contents.json').read_text())['images']:
    if 'filename' in entry:
        size = round(float(entry['size'].split('x')[0]) * float(entry['scale'].removesuffix('x')))
        image.resize((size, size), Image.Resampling.LANCZOS).save(icons / entry['filename'])
print('Android and iOS launcher assets updated.')
