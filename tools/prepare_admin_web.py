"""Brand a web build without changing the Android app assets.

Usage: prepare_admin_web.py [build_dir] [hotel|superadmin]
"""
import json
import sys
from pathlib import Path

project = Path(__file__).resolve().parent.parent
root = project / (sys.argv[1] if len(sys.argv) > 1 else 'build/admin_web')
portal = sys.argv[2] if len(sys.argv) > 2 else 'hotel'
admin = portal == 'superadmin'
title = 'Hotel Pro Admin' if admin else 'Hotel Pro'
about = ('Hotel Pro super admin: hotels, analytics and license keys.' if admin
         else 'Hotel Pro hotel workspace: rooms, bookings and reports.')

index = root / 'index.html'
text = index.read_text().replace('<title>Hotel Pro</title>', f'<title>{title}</title>')
text = text.replace('A new Flutter project.', about)
if admin and 'name="robots"' not in text:
    text = text.replace('<head>', '<head>\n  <meta name="robots" content="noindex, nofollow">', 1)
index.write_text(text)

manifest = root / 'manifest.json'
data = json.loads(manifest.read_text())
data.update(name=title, short_name=title, background_color='#f5f6f8', theme_color='#202124',
            description=about)
manifest.write_text(json.dumps(data, indent=2))
