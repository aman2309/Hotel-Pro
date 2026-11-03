"""Brand the independent admin build without changing the Android app assets."""
import json
from pathlib import Path
root = Path(__file__).resolve().parent.parent / 'build' / 'admin_web'
index = root / 'index.html'
text = index.read_text().replace('<title>Hotel Pro</title>', '<title>Hotel Pro</title>')
text = text.replace('A new Flutter project.', 'Hotel Pro hotel workspace, reports, administration and license management.')
index.write_text(text)
manifest = root / 'manifest.json'
data = json.loads(manifest.read_text())
data.update(name='Hotel Pro', short_name='Hotel Pro', background_color='#f5f6f8', theme_color='#202124',
            description='Hotel Pro hotel and admin workspace')
manifest.write_text(json.dumps(data, indent=2))
