# Authorized owner hotel-data reset

The user selected option 2 (real owner hotel, local/cloud, including trial/PIN)
and explicitly said to remove everything. Reset scope was restricted to the
verified Auth UID's two business paths. Other owners and rules were excluded.

- Fresh private typed-document/photo backup:
  `.checkpoints/owner-reset-1791749909722/`.
- Firestore: 63 descendant documents removed in one version-conditional commit.
- Storage: 2 objects removed with generation preconditions, after byte/hash backup.
- Both business paths verified to have no descendant documents or Storage objects.
- Business roots retain only owner UID, phone routing identity and reset timestamp.
  Hotel names/settings and licensing contents were removed. Auth account,
  UID mapping and phoneIndex remain to prevent a new accidental businessId.
- Samsung RZCX60SD5AR and Sony QV7711KNCG: `pm clear --user 0 com.hotelpro1.app`
  both returned Success. Main APK remains installed. LOCAL TEST is separate.
- Existing private backups and prior phone Downloads backups were retained.
- No production security rules were deployed. No new trial/license was created.
- PHP/MySQL could not be deleted: direct account/database access is unavailable.

The current main APK deliberately blocks returning owners with a missing license.
Deleting data does not bypass that guard. A reviewed fresh-start/activation flow
and any required production rule rollout must be handled separately. Do not
restore old phone/JSON/PHP snapshots into the reset business automatically.

Fresh pre-reset audit additionally observed two active booking records and an
active guest/payment projection in production (different from the earlier
soft-deleted snapshot). Those exact current records were backed up before reset;
the earlier claim that deploying rules or an explicit migration was not done
does not imply that opening the production app never wrote business records.
