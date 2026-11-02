"""Copy existing phone files without installing/updating/restoring or launching the app.
Requires owner-authorized USB debugging. Keep phone offline and app closed.
Private release preferences may be inaccessible; never root/unlock/wipe to bypass.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--serial')
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
adb = '/Users/raghuwansh/Library/Android/sdk/platform-tools/adb'
devices = subprocess.run([adb, 'devices'], capture_output=True, check=True).stdout.decode().splitlines()
serials = [line.split()[0] for line in devices if len(line.split()) == 2 and line.split()[1] == 'device']
serial = args.serial or (serials[0] if len(serials) == 1 else None)
if serial not in serials:
    raise SystemExit('No single authorized phone selected. Connect/unlock phone and authorize USB debugging; use --serial for multiple devices.')
folder = root / '.checkpoints/rollout-20261010' / f'phone-{int(time.time()*1000)}'
folder.mkdir(mode=0o700)
package = 'com.hotelpro1.app'
prefix = [adb, '-s', serial]

def run(*parts):
    return subprocess.run(prefix + list(parts), capture_output=True, timeout=120)

def save(name, data):
    p = folder / name
    p.write_bytes(data)
    p.chmod(0o600)

summary = {'productionWrites': False, 'phoneDataWrites': False, 'appLaunched': False, 'appUpdated': False,
           'trialActivationVerified': False, 'rawPreferencesCopied': False}
meta = run('shell', 'dumpsys', 'package', package)
save('installed-package.txt', meta.stdout)
if meta.returncode != 0 or b'Unable to find package' in meta.stdout:
    raise SystemExit('Hotel Pro package not found; no backup assumed.')
prefs = run('exec-out', 'run-as', package, 'cat', 'shared_prefs/FlutterSharedPreferences.xml')
if prefs.returncode == 0 and prefs.stdout.lstrip().startswith(b'<?xml'):
    ET.fromstring(prefs.stdout)  # Invalid/truncated XML is never called a successful backup.
    save('FlutterSharedPreferences.xml', prefs.stdout)
    summary['rawPreferencesCopied'] = True
    values = {node.attrib.get('name', '').removeprefix('flutter.'): node.attrib.get('value', node.text) for node in ET.fromstring(prefs.stdout)}
    save('app-preferences-decoded.json', json.dumps(values, ensure_ascii=False, indent=2).encode())
    pin_hashes = set(re.findall(r'[a-f0-9]{64}', (root / 'lib/data/pin_hash_set.dart').read_text()))
    summary['license'] = {'trialStartPresent': bool(values.get('hp1_trial_start')), 'activationFlag': values.get('hp1_license_on'),
                          'recognizedPinHash': values.get('hp1_license_hash') in pin_hashes}
    summary['trialActivationVerified'] = bool(values.get('hp1_trial_start')) and values.get('hp1_license_on') == 'true' and values.get('hp1_license_hash') in pin_hashes
else:
    summary['privatePreferencesAccess'] = 'Unavailable; release app may be non-debuggable. No privilege bypass attempted.'

external = folder / 'external-files'
copied = run('pull', f'/sdcard/Android/data/{package}/files', str(external))
summary['externalFilesCopyExitCode'] = copied.returncode
summary['jsonBackupsCopied'] = [str(p.relative_to(folder)) for p in external.rglob('Hotel_Pro_1_Backup_*.json')] if external.exists() else []
if copied.returncode != 0: summary['externalFilesAccess'] = 'Partial/unavailable; do not assume a complete photo/data backup.'
hashes = {}
for file in folder.rglob('*'):
    if file.is_file():
        file.chmod(0o600)
        hashes[str(file.relative_to(folder))] = hashlib.sha256(file.read_bytes()).hexdigest()
    elif file.is_dir(): file.chmod(0o700)
save('sha256-manifest.json', json.dumps(hashes, indent=2).encode())
save('backup-summary.json', json.dumps(summary, indent=2).encode())
print(json.dumps({'privateBackup': str(folder), 'rawPreferencesCopied': summary['rawPreferencesCopied'],
                  'jsonBackupCount': len(summary['jsonBackupsCopied']), 'trialActivationVerified': summary['trialActivationVerified'],
                  'productionWrites': False, 'appUpdated': False}))
