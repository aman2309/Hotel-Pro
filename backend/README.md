# Historical Hotel Pro cPanel backend

This backend is retired from the production Flutter app. The active backend is Firebase; see [the complete Firebase data model](../docs/firebase-data-model.md). These files are retained only for historical reference and a separately reviewed migration. They are not part of Firebase deployment.

Deployment has not been run. This machine does not have the hotel's cPanel login, database password, or API domain.

## What you still need to fill on the server

Do not send the database password or HMAC secret in chat. Put them only in `config/config.php` on the server.

- API domain or subdomain, for example `https://api.your-domain.example`
- PHP version and extensions: PHP 8.1+ with `pdo_mysql`, `fileinfo`, and `openssl`
- MySQL 5.7.23 is the version on this hosting. PHP 8.3 is available. The migration uses ascii identifier indexes so it stays within MySQL 5.7's 767-byte index limit.
- Whether cron is allowed
- Database name and database user name

## Layout

Point the subdomain document root at `backend/public` only. Keep `config/`, `src/`, `storage/`, and `bin/` outside that public directory. `storage/` holds guest ID photos and must not be under `public_html`.

```
backend/public/index.php      HTTPS front controller
backend/src/app.php           API
backend/migrations/001_init.sql
backend/config/config.php     server-only, not in git
backend/storage/photos/       private JPEG files, mode 0700
```

## Database

In cPanel, create a database and a user that can use only that database. Grant `SELECT, INSERT, UPDATE, DELETE`. Do not use the account's full-privilege user for the API.

```bash
mysql -u REPLACE_DATABASE_USER -p REPLACE_DATABASE_NAME < backend/migrations/001_init.sql
```

Copy `config/config.example.php` to `config/config.php`. Replace the database name, user, password, `pin_hmac_secret`, and `token_pepper` with long random values generated on the server. Set `storage_dir` to the private directory.

## HTTPS

Enable the subdomain certificate in cPanel. Leave `require_https` true. The Apache file `public/.htaccess` routes requests to `index.php`.

Health check: `GET /v1/health` returns `{"ok":true}` when the database answers. It does not return credentials.

## Flutter

Build the signed APK only after the API is reachable:

```bash
flutter build apk --release --dart-define=HOTEL_API_BASE=https://api.your-domain.example
```

The signing file is the existing `android/key.properties`. cPanel mode does not initialize Firebase. The Firebase packages stay in the app until this API is deployed and a mapped migration is verified, so rollback remains `HotelBackend.firebase` in `lib/config/backend_config.dart`. Do not delete the Firebase project. A bill or payment edited on two phones at once is not overwritten: the status chip asks whether to keep this phone or the server copy.

## PIN batch

Run this on the server only after the new empty `hotelpro` database has been migrated. Do not point it at `a2ndhm2a_hotel`. The app cannot generate PINs.

```bash
mkdir -p /home4/a2ndhm2a/hotelpro/private-exports
chmod 700 /home4/a2ndhm2a/hotelpro/private-exports
HOTELPRO_CONFIG=/home4/a2ndhm2a/hotelpro/config/config.php \
  /usr/local/bin/ea-php83 /home4/a2ndhm2a/hotelpro/bin/issue_pins.php \
  --out=/home4/a2ndhm2a/hotelpro/private-exports/pins.csv
```

The command writes 100 unique 8-digit PINs and prints only the count. The CSV columns are `Serial Number`, `PIN`, and `Validity`. The PIN cell is an Excel text formula so a leading zero stays. The file mode is 0600. It is refused if the path contains `public` or `public_html`. The database stores an HMAC, a batch id, and the last four digits. Do not commit the CSV or copy it into the APK.

The same batch can be exported from the admin panel after login. That download is the only later view of the full PIN. The panel then shows `****` plus the last four digits.

## Admin panel

Create one admin from the server. There is no default password. The password is written only to the file you name:

```bash
HOTELPRO_CONFIG=/home4/a2ndhm2a/hotelpro/config/config.php \
  /usr/local/bin/ea-php83 /home4/a2ndhm2a/hotelpro/bin/create_admin.php \
  --username=YOUR_NAME --out=/home4/a2ndhm2a/hotelpro/config/admin-password.txt
chmod 600 /home4/a2ndhm2a/hotelpro/config/admin-password.txt
```

Open `https://api.2ndhealing.com/admin.php` after that host exists. Customer hotel accounts cannot sign in there. Login is rate limited, forms use a CSRF token, and actions are recorded without PINs or passwords. Assigning a PIN does not redeem it. Revoke applies only to an unused PIN. Cancelling a license asks for the business ID again and does not delete hotel data.

## Backups

A daily cron can dump and encrypt the database. Put the passphrase in the cron environment, not in the script.

```bash
mysqldump --single-transaction -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" \
  | openssl enc -aes-256-cbc -pbkdf2 -pass env:BACKUP_PASSPHRASE \
  > /home/USER/private-backups/hotelpro-$(date -u +%F).sql.enc
chmod 600 /home/USER/private-backups/hotelpro-*.sql.enc
```

Restore drill on a separate empty database, not on the live one:

```bash
openssl enc -d -aes-256-cbc -pbkdf2 -pass env:BACKUP_PASSPHRASE -in backup.sql.enc \
  | mysql -u "$DB_USER" -p"$DB_PASS" hotelpro_restore_drill
```

Compare `COUNT(*)` per entity and the sum of payment amounts with the values recorded when the backup was made.

## Migration dry-run

Firebase is not readable from this API. The dry-run reads a local checkpoint only and writes nothing:

```bash
php backend/bin/migrate_dry_run.php \
  --checkpoint=/path/documents.json \
  --report=/root/hotelpro-dry-run.json
```

`--apply` is refused. Importing the old hotel requires an explicit verified mapping from the old business to a new owner account, which this tool does not do.

## Behaviour

- Registration creates one business id on the server and, in the same transaction, 12 editable default rooms and a 10-day trial from server time.
- The same mobile number cannot register twice. Login is mobile number plus password. OTP is not included.
- Every later request uses the membership stored for the authenticated user. A client-supplied business id cannot cross hotels.
- An 8-digit PIN is one calendar year. A current license extends from its expiry. An expired or first license starts at redemption time. 29 February becomes 28 February.
- Expired licenses can still be read. New business writes are rejected.
- Push uses idempotency keys, revisions, tombstones, and a cursor. Conflicting financial edits return HTTP 409 and are not overwritten.
- Guest photos are JPEG-only, size-limited, and downloaded only by a member of that business.
