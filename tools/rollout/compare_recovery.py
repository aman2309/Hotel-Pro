"""Offline, read-only record comparison. Never imports/deletes/reactivates data.

python3 tools/rollout/compare_recovery.py --audit PRIVATE_AUDIT_DIR
Optional --local-json original-phone-export.json. Output stays private in audit dir.
Unknown local state is never treated as an empty list.
"""
import argparse
import collections
import hashlib
import json
import os
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--audit', required=True)
p.add_argument('--local-json')
args = p.parse_args()
folder = Path(args.audit).resolve()
cloud = json.loads((folder / 'hotel-documents.json').read_text())
legacy_file = next(folder.glob('legacy-biz_*.json'))
legacy = json.loads(legacy_file.read_text())
ignore = {'id', '_firestoreMeta', 'deviceId', 'updatedAt', 'updatedAtMs', 'serverUpdatedAt', 'schemaVersion', 'deleted'}

def fingerprint(v):
    return hashlib.sha256(json.dumps(v, sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()

def business_data(v):
    return {k: x for k, x in v.items() if k not in ignore}

report = {'productionWrites': False, 'localAvailable': bool(args.local_json), 'phpAvailable': False,
          'intentProven': False, 'collections': {}, 'deletionEvents': {}, 'records': [], 'sourceHashes': {}}
for f in [folder / 'hotel-documents.json', legacy_file]:
    report['sourceHashes'][f.name] = hashlib.sha256(f.read_bytes()).hexdigest()
for name, records in cloud.items():
    a = {v['id']: v for v in records}
    b = {v['id']: v for v in legacy.get(name, [])}
    common = a.keys() & b.keys()
    report['collections'][name] = {'current': len(a), 'currentDeleted': sum(v.get('deleted') is True for v in a.values()),
        'legacy': len(b), 'sameIds': sorted(common), 'sameDataIds': sorted(i for i in common if business_data(a[i]) == business_data(b[i])),
        'currentOnlyIds': sorted(a.keys() - b.keys()), 'legacyOnlyIds': sorted(b.keys() - a.keys()),
        'changedFields': {i: sorted(k for k in (a[i].keys() | b[i].keys()) - ignore if a[i].get(k) != b[i].get(k)) for i in common if business_data(a[i]) != business_data(b[i])}}
    events = collections.Counter((v.get('updatedAt'), v.get('updatedAtMs'), v.get('deviceId'), v.get('schemaVersion')) for v in records if v.get('deleted'))
    report['deletionEvents'][name] = [{'updatedAt': t, 'updatedAtMs': ms, 'deviceId': dev, 'schemaVersion': schema, 'count': n} for (t, ms, dev, schema), n in events.items()]
    for v in records:
        report['records'].append({'path': f'{name}/{v["id"]}', 'snapshotSha256': fingerprint(v), 'deleted': v.get('deleted') is True,
                                 'createTime': v.get('_firestoreMeta', {}).get('createTime'), 'updateTime': v.get('_firestoreMeta', {}).get('updateTime'),
                                 'localComparison': 'unknown' if not args.local_json else 'pending'})

payment_groups = collections.defaultdict(list)
for v in cloud['payments']:
    signature = tuple(v.get(k) for k in ['kind', 'roomNumber', 'dateTime', 'amount', 'paymentMode'])
    payment_groups[signature].append(v)
report['paymentDuplicateCandidates'] = [{'ids': [v['id'] for v in vs], 'sources': [v.get('source') for v in vs],
        'kind': key[0], 'roomNumber': key[1], 'dateTime': key[2], 'amount': key[3], 'paymentMode': key[4], 'decision': 'review alias; do not count both or delete originals'}
        for key, vs in payment_groups.items() if len(vs) > 1]
report['billIds'] = [v['id'] for v in cloud['bills']]
report['duplicateBillNumberGroups'] = [ids for ids in ({n: [v['id'] for v in cloud['bills'] if v.get('billNumber') == n] for n in {v.get('billNumber') for v in cloud['bills']}}).values() if len(ids) > 1]
report['oldBookingsMatchedToCheckedOutBills'] = []
for v in cloud['bookings']:
    if v.get('status') != 'BOOKED': continue
    matches = [b['id'] for b in cloud['bills'] if b.get('roomNumber') == v.get('roomNumber') and b.get('bookingTime') == v.get('bookingTime')]
    report['oldBookingsMatchedToCheckedOutBills'].append({'bookingId': v['id'], 'billIds': matches,
        'decision': 'do not revive as occupied room; review history' if matches else 'occupancy/checkout unknown; quarantine'})
guests = {g['id']: g for g in cloud['guests']}
normalize_phone = lambda x: ''.join(c for c in str(x or '') if c.isdigit())
report['billGuestLinks'] = []
for b in cloud['bills']:
    g = guests.get(b.get('customerId'))
    report['billGuestLinks'].append({'billId': b['id'], 'guestId': b.get('customerId'), 'guestPresent': g is not None,
        'phoneMatches': normalize_phone(g.get('mobile')) == normalize_phone(b.get('mobile')) if g else None,
        'nameMatches': str(g.get('guestName', '')).strip().casefold() == str(b.get('guestName', '')).strip().casefold() if g else None})
report['guestHistoryLinks'] = []
for g in guests.values():
    for stay in g.get('stayHistory', []):
        ids = [b['id'] for b in cloud['bills'] if all(b.get(k) == stay.get(k) for k in ['roomNumber', 'bookingTime', 'checkoutTime'])]
        report['guestHistoryLinks'].append({'guestId': g['id'], 'matchingBillIds': ids, 'billNumberStoredInStay': stay.get('billNumber')})
photos = json.loads((folder / 'unreferenced-photo-checks.json').read_text())
report['photoGuestLinks'] = []
for o in photos:
    for g in guests.values():
        for side in ['Front', 'Back']:
            if g.get(f'id{side}StoragePath') == o['name']:
                report['photoGuestLinks'].append({'guestId': g['id'], 'guestDeleted': g.get('deleted') is True, 'side': side,
                    'storagePath': o['name'], 'jpegVerified': o.get('jpeg'), 'actualSha256': o['sha256'],
                    'metadataSha256': g.get(f'id{side}Sha256'), 'hashMatches': g.get(f'id{side}Sha256') == o['sha256'],
                    'generation': o.get('generation'), 'privateBytesBackup': o.get('privateBytesBackup')})

if args.local_json:
    original = Path(args.local_json).resolve()
    raw = original.read_bytes()
    source_hash = hashlib.sha256(raw).hexdigest()
    copied = folder / f'original-local-{source_hash}.json'
    if not copied.exists():
        with copied.open('xb') as f: f.write(raw)
        copied.chmod(0o600)
    data = json.loads(raw)
    if data.get('app') != 'Hotel Pro 1' or not isinstance(data.get('data'), dict):
        raise ValueError('Not an existing Hotel Pro 1 JSON backup. Original copied; no records changed.')
    data = data['data']
    keys = {'rooms': ('hotelpro1_rooms', 'roomNumber'), 'bills': ('hotelpro1_bills', 'billNumber'), 'guests': ('hotelpro1_customers', 'customerId'), 'expenses': ('hotelpro1_expenses', 'expenseId')}
    report['localComparison'] = {}
    for name, (key, id_field) in keys.items():
        if key not in data:
            report['localComparison'][name] = {'state': 'missing key; unknown, not empty'}; continue
        records = json.loads(data[key]) if isinstance(data[key], str) else data[key]
        if not isinstance(records, list): raise ValueError(f'Invalid {key}; comparison stopped')
        ids = []
        missing_ids = 0
        for v in records:
            value = (v.get(id_field) or (v.get('id') if name == 'expenses' else None)) if isinstance(v, dict) else None
            if value is None or str(value) == '': missing_ids += 1; continue
            ids.append(f'room_{value}' if name == 'rooms' else str(value))
        counts = collections.Counter(ids)
        remote = {v['id']: v for v in cloud.get(name, [])}
        report['localComparison'][name] = {'localCount': len(records), 'missingIds': missing_ids,
            'duplicateIds': [i for i, count in counts.items() if count > 1], 'matchedIds': sorted(set(ids) & remote.keys()),
            'localOnlyIds': sorted(set(ids) - remote.keys()), 'cloudOnlyIds': sorted(remote.keys() - set(ids)),
            'matchedDeletedCloudIds': sorted(i for i in set(ids) & remote.keys() if remote[i].get('deleted') is True)}
        differences = []
        for v in records:
            if not isinstance(v, dict): continue
            value = v.get(id_field) or (v.get('id') if name == 'expenses' else None)
            rid = f'room_{value}' if name == 'rooms' else str(value)
            other = remote.get(rid)
            if other is None: continue
            # Preserve opaque photo bytes/metadata for separate photo review.
            common = (v.keys() & other.keys()) - ignore
            common = {k for k in common if not any(x in k.lower() for x in ['photo','storage','sha256'])}
            changed = sorted(k for k in common if v[k] != other[k])
            differences.append({'id':rid,'sharedFieldsDifferent':changed,
                                'classification':'requires review' if changed else 'shared fields match; photos/omitted fields not proven'})
        report['localComparison'][name]['payloadReview'] = differences
    report['localSourceSha256'] = source_hash
    report['licenseIncluded'] = False  # Existing backupVersion 1 has only four lists.

output = folder / f'recovery-comparison-{"with-local" if args.local_json else "cloud-only"}.json'
with output.open('w') as f: json.dump(report, f, indent=2, ensure_ascii=False)
os.chmod(output, 0o600)
print(json.dumps({'privateComparison': str(output), 'localCompared': report['localAvailable'], 'phpCompared': False,
                  'paymentDuplicateCandidateGroups': len(report['paymentDuplicateCandidates']),
                  'photoLinks': len(report['photoGuestLinks']), 'intentProven': False}))
