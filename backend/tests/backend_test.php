<?php
declare(strict_types=1);

require dirname(__DIR__) . '/src/app.php';
require dirname(__DIR__) . '/src/admin.php';

$failed = 0;
function check(bool $condition, string $label): void
{
    global $failed;
    if ($condition) {
        fwrite(STDOUT, "PASS {$label}\n");
        return;
    }
    $failed++;
    fwrite(STDOUT, "FAIL {$label}\n");
}

$leap = hotelpro_add_year(new DateTimeImmutable('2028-02-29 08:30:00', new DateTimeZone('UTC')));
check($leap->format('Y-m-d H:i:s') === '2029-02-28 08:30:00', '29 February rolls to 28 February');
check(hotelpro_phone('+91', '9000000001') === '+919000000001', 'mobile normalization');
check(hotelpro_phone('91', '919000000001') === '+919000000001', 'country code is not doubled');
$secret = 'test-secret';
check(hotelpro_pin_key('00001234', $secret) === hash_hmac('sha256', '00001234', $secret), 'leading zero PIN stays text');
foreach (glob(dirname(__DIR__) . '/migrations/*.sql') ?: [] as $migrationFile) {
    $migrationSql = (string) file_get_contents($migrationFile);
    check(!preg_match('/utf8mb4_0900|JSON_TABLE|WITH RECURSIVE|GENERATED ALWAYS|->>/i', $migrationSql), basename($migrationFile) . ' has no MySQL 8-only syntax');
}
$migration = (string) file_get_contents(dirname(__DIR__) . '/migrations/001_init.sql');
check(preg_match('/UNIQUE KEY photo_slot \(business_id, guest_id, slot, sha256\)/', $migration) === 1, 'photo lookup stays one unique key');
preg_match_all('/CHARACTER SET ascii COLLATE ascii_bin NOT NULL,\n  guest_id VARCHAR\(80\) CHARACTER SET ascii/', $migration, $asciiPhoto);
check($asciiPhoto[0] !== [], 'photo index columns are ascii and fit the MySQL 5.7 767-byte limit');

$checkpoint = '/Users/raghuwansh/HotelPro-safe-backups/owner-reset-1791749909722/documents.json';
$reportFile = sys_get_temp_dir() . '/hotelpro-dry-run.json';
passthru(escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg(dirname(__DIR__) . '/bin/migrate_dry_run.php') . ' --checkpoint=' . escapeshellarg($checkpoint) . ' --report=' . escapeshellarg($reportFile), $code);
check($code === 0, 'migration dry-run exits cleanly');
$report = json_decode((string) file_get_contents($reportFile), true);
$main = $report['byBusiness']['biz_xehC63jAFQWvlgKRwabV'] ?? null;
check($report['applied'] === false && $report['recovered'] === false, 'dry-run does not claim recovery');
check($main && $main['documents'] === 49 && $main['counts']['rooms'] === 12 && $main['counts']['bookings'] === 11 && $main['counts']['guests'] === 4 && $main['counts']['payments'] === 9 && $main['deleted'] === 31 && $main['live'] === 18 && $main['paymentAmountTotal'] === 6700, 'verified backup counts match the restore report');
unlink($reportFile);

function db_available(): ?array
{
    $user = getenv('USER') ?: 'root';
    $tries = [
        ['mysql:host=127.0.0.1;charset=utf8mb4', 'root', '', '127.0.0.1'],
        ['mysql:unix_socket=/tmp/mysql.sock;charset=utf8mb4', $user, '', 'localhost'],
    ];
    foreach ($tries as [$dsn, $dbUser, $pass, $host]) {
        try {
            return [
                'pdo' => new PDO($dsn, $dbUser, $pass, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]),
                'user' => $dbUser,
                'pass' => $pass,
                'host' => $host,
            ];
        } catch (Throwable) {
        }
    }
    return null;
}

$db = db_available();
if ($db === null) {
    fwrite(STDOUT, "SKIP database flows: local MySQL is not running\n");
    exit($failed > 0 ? 1 : 0);
}
$admin = $db['pdo'];

$admin->exec('DROP DATABASE IF EXISTS hotelpro_cpanel_test');
$admin->exec('CREATE DATABASE hotelpro_cpanel_test CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci');
$appUser = 'hotelpro_test';
$appPass = bin2hex(random_bytes(12));
$appHost = '127.0.0.1';
$admin->exec('DROP USER IF EXISTS ' . $admin->quote($appUser) . '@' . $admin->quote($appHost));
$admin->exec('CREATE USER ' . $admin->quote($appUser) . '@' . $admin->quote($appHost) . ' IDENTIFIED BY ' . $admin->quote($appPass));
$admin->exec('GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER ON hotelpro_cpanel_test.* TO ' . $admin->quote($appUser) . '@' . $admin->quote($appHost));
$storage = sys_get_temp_dir() . '/hotelpro-storage-' . getmypid();
mkdir($storage, 0700, true);
$config = [
    'db' => ['host' => $appHost, 'name' => 'hotelpro_cpanel_test', 'user' => $appUser, 'pass' => $appPass, 'charset' => 'utf8mb4'],
    'pin_hmac_secret' => 'test-secret',
    'token_pepper' => 'test-pepper',
    'require_https' => false,
    'storage_dir' => $storage,
    'access_ttl_seconds' => 900,
    'refresh_ttl_seconds' => 2592000,
    'photo_max_bytes' => 5242880,
    'cli_test_files' => true,
];
$configPath = sys_get_temp_dir() . '/hotelpro-test-config.php';
file_put_contents($configPath, '<?php return ' . var_export($config, true) . ';');
putenv('HOTELPRO_CONFIG=' . $configPath);
$pdo = hotelpro_pdo($config);
$migrationFiles = glob(dirname(__DIR__) . '/migrations/*.sql') ?: [];
sort($migrationFiles);
foreach ($migrationFiles as $migrationFile) {
    foreach (preg_split('/;\s*\n/', (string) file_get_contents($migrationFile)) as $sql) {
        if (trim($sql) !== '') {
            $pdo->exec($sql);
        }
    }
}

function api(array $config, string $method, string $path, array $body = [], array $headers = []): array
{
    return hotelpro_handle($config, $method, $path, $body, $headers);
}

$first = api($config, 'POST', '/v1/auth/register', [
    'ownerName' => 'Owner A',
    'hotelName' => 'Hotel A',
    'countryCode' => '+91',
    'mobile' => '9000000001',
    'password' => 'correct-horse',
    'passwordAgain' => 'correct-horse',
]);
check($first['status'] === 201 && count($first['body']['rooms']) === 12 && $first['body']['rooms'][0]['roomType'] === 'Deluxe' && $first['body']['rooms'][0]['normalRent'] === 1500, 'new account creates 12 default rooms once');
$again = api($config, 'POST', '/v1/auth/register', $first['body'] ? [
    'ownerName' => 'Owner A',
    'hotelName' => 'Hotel A2',
    'countryCode' => '+91',
    'mobile' => '9000000001',
    'password' => 'correct-horse',
    'passwordAgain' => 'correct-horse',
] : []);
check($again['status'] === 409, 'one mobile number cannot create two accounts');
$login = api($config, 'POST', '/v1/auth/login', ['countryCode' => '+91', 'mobile' => '9000000001', 'password' => 'correct-horse']);
check($login['status'] === 200 && $login['body']['businessId'] === $first['body']['businessId'], 'second login opens the same business');
$roomCount = $pdo->query("SELECT COUNT(*) FROM hotel_records WHERE entity = 'rooms' AND business_id = " . $pdo->quote($first['body']['businessId']))->fetchColumn();
check((int) $roomCount === 12, 'login does not create the 12 rooms again');
$sameHeaders = ['Authorization' => 'Bearer ' . $login['body']['accessToken']];
check($login['body']['userId'] === $first['body']['userId'] && $login['body']['role'] === 'owner', 'same account keeps the owner write membership');
$pulled = api($config, 'GET', '/v1/sync', [], $sameHeaders);
$roomRevision = 0;
foreach ($pulled['body']['changes'] as $change) {
    if ($change['entity'] === 'rooms' && $change['recordId'] === 'room_102') {
        $roomRevision = (int) $change['revision'];
    }
}
check($pulled['status'] === 200 && $pulled['body']['businessId'] === $first['body']['businessId'] && $pulled['body']['userId'] === $first['body']['userId'] && $pulled['body']['role'] === 'owner' && $roomRevision > 0, 'second login reads the same business and revision');
$fromSecondPhone = api($config, 'POST', '/v1/sync', [
    'idempotencyKey' => 'idempotency-second-phone',
    'businessId' => $login['body']['businessId'],
    'changes' => [[
        'entity' => 'rooms',
        'recordId' => 'room_102',
        'baseRevision' => $roomRevision,
        'payload' => [
            'roomNumber' => 102,
            'roomType' => 'Luxury',
            'normalRent' => 2000,
            'status' => 'BOOKED',
            'idFrontPhotoPath' => str_repeat('A', 240),
        ],
    ]],
], $sameHeaders);
$storedRoom = json_decode((string) $pdo->query('SELECT payload FROM hotel_records WHERE record_id = ' . $pdo->quote('room_102') . ' AND business_id = ' . $pdo->quote($first['body']['businessId']))->fetchColumn(), true);
check($fromSecondPhone['status'] === 200 && ($storedRoom['status'] ?? '') === 'BOOKED' && !isset($storedRoom['idFrontPhotoPath']), 'second login saves the booking without ID photo bytes');
$retrySecond = api($config, 'POST', '/v1/sync', [
    'idempotencyKey' => 'idempotency-second-phone',
    'changes' => [[
        'entity' => 'rooms',
        'recordId' => 'room_102',
        'baseRevision' => $roomRevision,
        'payload' => ['roomNumber' => 102, 'status' => 'EMPTY'],
    ]],
], $sameHeaders);
$afterRetry = json_decode((string) $pdo->query('SELECT payload FROM hotel_records WHERE record_id = ' . $pdo->quote('room_102') . ' AND business_id = ' . $pdo->quote($first['body']['businessId']))->fetchColumn(), true);
check($retrySecond['status'] === 200 && $retrySecond['body']['applied'][0]['revision'] === $fromSecondPhone['body']['applied'][0]['revision'] && ($afterRetry['status'] ?? '') === 'BOOKED', 'the same save retry does not create another booking');
$visibleToFirst = false;
$seenByFirst = api($config, 'GET', '/v1/sync', ['cursor' => (string) $roomRevision], ['Authorization' => 'Bearer ' . $first['body']['accessToken']]);
foreach ($seenByFirst['body']['changes'] as $change) {
    if ($change['recordId'] === 'room_102' && ($change['payload']['status'] ?? '') === 'BOOKED') {
        $visibleToFirst = true;
    }
}
check($visibleToFirst, 'the first login receives the booking saved by the second login');
$second = api($config, 'POST', '/v1/auth/register', [
    'ownerName' => 'Owner B',
    'hotelName' => 'Hotel B',
    'countryCode' => '+91',
    'mobile' => '9000000002',
    'password' => 'another-horse',
    'passwordAgain' => 'another-horse',
]);
check($second['status'] === 201 && $second['body']['businessId'] !== $first['body']['businessId'], 'a different account gets a different business');
$headersA = ['Authorization' => 'Bearer ' . $first['body']['accessToken']];
$cross = api($config, 'GET', '/v1/sync', ['businessId' => $second['body']['businessId']], $headersA);
check($cross['status'] === 403, 'a token cannot read another business');
$push = api($config, 'POST', '/v1/sync', [
    'idempotencyKey' => 'idempotency-key-0001',
    'changes' => [['entity' => 'rooms', 'recordId' => 'room_101', 'baseRevision' => 1, 'payload' => ['roomNumber' => 101, 'roomType' => 'Deluxe', 'normalRent' => 1800, 'status' => 'EMPTY']]],
], $headersA);
check($push['status'] === 200, 'authorized room edit syncs');
$retry = api($config, 'POST', '/v1/sync', [
    'idempotencyKey' => 'idempotency-key-0001',
    'changes' => [['entity' => 'rooms', 'recordId' => 'room_101', 'baseRevision' => 1, 'payload' => ['roomNumber' => 101, 'roomType' => 'Deluxe', 'normalRent' => 9999]]],
], $headersA);
check($retry['status'] === 200 && $retry['body']['applied'][0]['revision'] === $push['body']['applied'][0]['revision'], 'retry with the same idempotency key does not duplicate');
$rent = json_decode($pdo->query("SELECT payload FROM hotel_records WHERE record_id = 'room_101' AND business_id = " . $pdo->quote($first['body']['businessId']))->fetchColumn(), true);
check((int) $rent['normalRent'] === 1800, 'idempotent retry kept the first write');
$conflict = api($config, 'POST', '/v1/sync', [
    'idempotencyKey' => 'idempotency-key-conflict',
    'changes' => [['entity' => 'payments', 'recordId' => 'pay_1', 'baseRevision' => 4, 'payload' => ['amount' => 100]]],
], $headersA);
check($conflict['status'] === 409, 'a financial edit with the wrong revision is not overwritten');
$duplicateBill = api($config, 'POST', '/v1/sync', [
    'idempotencyKey' => 'idempotency-key-bills01',
    'changes' => [
        ['entity' => 'bills', 'recordId' => 'bill_1', 'baseRevision' => 0, 'payload' => ['billNumber' => 'B-1', 'totalBill' => 100]],
        ['entity' => 'bills', 'recordId' => 'bill_2', 'baseRevision' => 0, 'payload' => ['billNumber' => 'B-1', 'totalBill' => 100]],
    ],
], $headersA);
check($duplicateBill['status'] === 409, 'a duplicate live bill number is rejected');
$trialEnd = new DateTimeImmutable($first['body']['license']['trialEndsAt']);
$trialSeconds = $trialEnd->getTimestamp() - (new DateTimeImmutable('now', new DateTimeZone('UTC')))->getTimestamp();
check($trialSeconds > 9 * 86400 && $trialSeconds < 11 * 86400, 'trial is 10 days from server time');
$headersB = ['Authorization' => 'Bearer ' . $second['body']['accessToken']];
$foreignWrite = api($config, 'POST', '/v1/sync', [
    'idempotencyKey' => 'idempotency-key-0002',
    'businessId' => $first['body']['businessId'],
    'changes' => [['entity' => 'rooms', 'recordId' => 'room_101', 'baseRevision' => 1, 'payload' => ['normalRent' => 1]]],
], $headersB);
check($foreignWrite['status'] === 403, 'another account cannot write this hotel');

$csv = sys_get_temp_dir() . '/hotelpro-test-pins.csv';
passthru(escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg(dirname(__DIR__) . '/bin/issue_pins.php') . ' --out=' . escapeshellarg('/tmp/public_html/pins.csv'), $publicPinCode);
check($publicPinCode === 1 && !is_file('/tmp/public_html/pins.csv'), 'PIN export refuses a public web folder');
passthru(escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg(dirname(__DIR__) . '/bin/issue_pins.php') . ' --out=' . escapeshellarg($csv), $pinCode);
$lines = file($csv, FILE_IGNORE_NEW_LINES);
$csvHeaders = str_getcsv((string) $lines[0], ',', '"', '\\');
check($pinCode === 0 && count($lines) === 101 && $csvHeaders === ['Serial Number', 'PIN', 'Validity'] && (fileperms($csv) & 0777) === 0600, '100 PINs export once to a private file');
$issued = (int) $pdo->query("SELECT COUNT(*) FROM activation_codes WHERE status = 'issued'")->fetchColumn();
check($issued === 100, 'database stores hashes rather than a second plaintext copy');
$csvField = static function (string $line, int $index): string {
    $fields = str_getcsv($line, ',', '"', '\\');
    $value = (string) ($fields[$index] ?? '');
    if (preg_match('/^="(\d{8})"$/', $value, $matches) === 1) {
        return $matches[1];
    }
    return $value;
};
$samplePin = $csvField($lines[1], 1);
check(preg_match('/^\d{8}$/', $samplePin) === 1 && $csvField($lines[1], 2) === '1 year', 'exported PIN stays 8 digits with one-year validity');
$storedPin = $pdo->prepare('SELECT code_hmac, last4, batch_id FROM activation_codes WHERE code_hmac = ?');
$storedPin->execute([hotelpro_pin_key($samplePin, 'test-secret')]);
$storedPinRow = $storedPin->fetch();
check(is_array($storedPinRow) && $storedPinRow['code_hmac'] !== $samplePin && $storedPinRow['last4'] === substr($samplePin, -4) && strlen((string) $storedPinRow['batch_id']) === 32, 'database stores the PIN hash, batch, and last four digits');
$issuedPins = [];
foreach (array_slice($lines, 1) as $line) {
    $issuedPins['k' . $csvField($line, 1)] = true;
}
$badPin = '00000000';
while (isset($issuedPins['k' . $badPin])) {
    $badPin = str_pad((string) random_int(0, 99999999), 8, '0', STR_PAD_LEFT);
}
$invalid = api($config, 'POST', '/v1/license/redeem', ['pin' => $badPin], $headersA);
check($invalid['status'] === 403, 'an invalid PIN is rejected');
$redeem = api($config, 'POST', '/v1/license/redeem', ['pin' => $samplePin], $headersA);
check($redeem['status'] === 200 && $redeem['body']['activated'] === true, 'unused PIN activates one business');
$beforeRooms = $pdo->query('SELECT record_id, revision, payload FROM hotel_records WHERE business_id = ' . $pdo->quote($first['body']['businessId']) . ' ORDER BY record_id')->fetchAll();
$repeat = api($config, 'POST', '/v1/license/redeem', ['pin' => $samplePin], $headersA);
check($repeat['body']['idempotent'] === true && $repeat['body']['expiresAt'] === $redeem['body']['expiresAt'], 'repeating a PIN does not add another year');
$redemption = $pdo->prepare('SELECT user_id, business_id, expires_at FROM pin_redemptions WHERE code_hmac = ?');
$redemption->execute([hotelpro_pin_key($samplePin, 'test-secret')]);
$redemptionRows = $redemption->fetchAll();
check(count($redemptionRows) === 1 && $redemptionRows[0]['user_id'] === $first['body']['userId'] && $redemptionRows[0]['business_id'] === $first['body']['businessId'] && hotelpro_parse($redemptionRows[0]['expires_at'])->format(DATE_ATOM) === $redeem['body']['expiresAt'], 'redemption records user, business, and expiry once');
$stolen = api($config, 'POST', '/v1/license/redeem', ['pin' => $samplePin], $headersB);
check($stolen['status'] === 403, 'a redeemed PIN cannot activate another hotel');
$afterRooms = $pdo->query('SELECT record_id, revision, payload FROM hotel_records WHERE business_id = ' . $pdo->quote($first['body']['businessId']) . ' ORDER BY record_id')->fetchAll();
check($beforeRooms === $afterRooms, 'PIN redemption leaves hotel records unchanged');
unlink($csv);

$renewPin = $csvField($lines[2], 1);
$assignPin = $csvField($lines[4], 1);
$revokePin = $csvField($lines[5], 1);
$renew = api($config, 'POST', '/v1/license/redeem', ['pin' => $renewPin], $headersA);
$firstExpiry = new DateTimeImmutable($redeem['body']['expiresAt']);
$renewedExpiry = new DateTimeImmutable($renew['body']['expiresAt']);
check($renew['status'] === 200 && $renewedExpiry->format('Y-m-d') === $firstExpiry->modify('+1 year')->format('Y-m-d'), 'active license renews from its expiry');

$pair = $csvField($lines[3], 1);
$worker = dirname(__DIR__) . '/tests/redeem_worker.php';
$open = static function (array $headers) use ($worker, $pair): array {
    $process = proc_open([PHP_BINARY, $worker], [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
    fwrite($pipes[0], json_encode(['body' => ['pin' => $pair], 'headers' => $headers]));
    fclose($pipes[0]);
    return [$process, $pipes];
};
[$leftProcess, $leftPipes] = $open($headersA);
[$rightProcess, $rightPipes] = $open($headersB);
$left = json_decode(stream_get_contents($leftPipes[1]), true);
$right = json_decode(stream_get_contents($rightPipes[1]), true);
foreach ([$leftPipes, $rightPipes] as $pipes) {
    fclose($pipes[1]);
    fclose($pipes[2]);
}
proc_close($leftProcess);
proc_close($rightProcess);
check((int) $left['activated'] + (int) $right['activated'] === 1, 'only one concurrent redemption succeeds');

$pdo->prepare('UPDATE licenses SET trial_ends_at = ?, expires_at = NULL, activated = 0 WHERE business_id = ?')->execute(['2020-01-01 00:00:00.000000', $second['body']['businessId']]);
$blocked = api($config, 'POST', '/v1/sync', [
    'idempotencyKey' => 'idempotency-key-0099',
    'changes' => [['entity' => 'expenses', 'recordId' => 'exp_1', 'baseRevision' => 0, 'payload' => ['amount' => 10]]],
], $headersB);
$readable = api($config, 'GET', '/v1/sync', [], $headersB);
check($blocked['status'] === 403 && $readable['status'] === 200, 'expired license stays readable and rejects new writes');

$image = imagecreatetruecolor(8, 8);
$photoPath = $storage . '/sample.jpg';
imagejpeg($image, $photoPath, 90);
$photo = hotelpro_save_photo($pdo, $config, ['id' => $first['body']['userId'], 'business_id' => $first['body']['businessId']], ['photo' => ['tmp_name' => $photoPath, 'size' => filesize($photoPath)]], ['guestId' => 'CUST-1', 'slot' => 'front']);
check($photo['status'] === 201, 'JPEG photo is stored privately');
$photoId = (string) ($photo['body']['photoId'] ?? '');
$download = $photoId === ''
    ? ['status' => 0]
    : hotelpro_read_photo($pdo, $config, ['id' => $second['body']['userId'], 'business_id' => $second['body']['businessId']], $photoId);
check($download['status'] === 404, 'another hotel cannot download the photo');

$recordsBeforeAdmin = $pdo->query('SELECT record_id, revision, payload FROM hotel_records WHERE business_id = ' . $pdo->quote($first['body']['businessId']) . ' ORDER BY record_id')->fetchAll();
$adminFile = sys_get_temp_dir() . '/hotelpro-admin-password.txt';
$adminStdout = shell_exec(escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg(dirname(__DIR__) . '/bin/create_admin.php') . ' --username=hotelpro-admin --out=' . escapeshellarg($adminFile));
$adminPrivate = is_file($adminFile) ? (string) file_get_contents($adminFile) : '';
preg_match('/password: (\\S+)/', $adminPrivate, $adminMatch);
$adminPassword = (string) ($adminMatch[1] ?? '');
check(is_string($adminStdout) && $adminPassword !== '' && is_file($adminFile) && !str_contains($adminStdout, $adminPassword) && (fileperms($adminFile) & 0777) === 0600, 'admin password is written only to the private file');
if (is_file($adminFile)) {
    unlink($adminFile);
}
$guest = hotelpro_admin_http($pdo, $config, 'GET', [], [], []);
$badCsrf = hotelpro_admin_http($pdo, $config, 'POST', [], ['action' => 'login', 'username' => 'hotelpro-admin', 'password' => $adminPassword, 'csrf' => 'bad'], $guest['session']);
check($badCsrf['status'] === 400 && empty($badCsrf['session']['admin_id']), 'admin login requires the CSRF token');
$loggedIn = hotelpro_admin_http($pdo, $config, 'POST', [], ['action' => 'login', 'username' => 'hotelpro-admin', 'password' => $adminPassword, 'csrf' => $guest['session']['csrf']], $guest['session']);
check(!empty($loggedIn['session']['admin_id']) && str_contains($loggedIn['body'], 'कुल होटल'), 'admin login opens the dashboard');
$customerSession = ['admin_id' => $first['body']['userId'], 'expires_at' => hotelpro_fmt(hotelpro_now()->modify('+1 hour')), 'csrf' => bin2hex(random_bytes(32))];
$customerPage = hotelpro_admin_http($pdo, $config, 'GET', ['page' => 'customers'], [], $customerSession);
check(!str_contains($customerPage['body'], 'Hotel A') && str_contains($customerPage['body'], 'customer account'), 'a customer account cannot open the admin panel');
$assignSerial = (int) $pdo->query('SELECT serial_no FROM activation_codes WHERE code_hmac = ' . $pdo->quote(hotelpro_pin_key($assignPin, 'test-secret')))->fetchColumn();
$assigned = hotelpro_admin_assign($pdo, (string) $loggedIn['session']['admin_id'], $assignSerial, 'Counter copy');
$assignedRow = $pdo->query('SELECT status, business_id, assigned_label FROM activation_codes WHERE serial_no = ' . $assignSerial)->fetch();
check($assigned['ok'] === true && $assignedRow['status'] === 'issued' && $assignedRow['business_id'] === null && $assignedRow['assigned_label'] === 'Counter copy', 'assignment stays separate from redemption');
$pinPage = hotelpro_admin_http($pdo, $config, 'GET', ['page' => 'pins', 'q' => 'Counter copy'], [], $loggedIn['session']);
check(str_contains($pinPage['body'], 'Counter copy') && str_contains($pinPage['body'], '****' . substr($assignPin, -4)) && !str_contains($pinPage['body'], $assignPin), 'PIN inventory shows the masked PIN and not the full PIN');
$assignedRedeem = api($config, 'POST', '/v1/license/redeem', ['pin' => $assignPin], $headersA);
$afterAssignRedeem = $pdo->query('SELECT record_id, revision, payload FROM hotel_records WHERE business_id = ' . $pdo->quote($first['body']['businessId']) . ' ORDER BY record_id')->fetchAll();
check($assignedRedeem['status'] === 200 && $afterAssignRedeem === $recordsBeforeAdmin, 'redeeming an assigned PIN keeps hotel records');
$revokeSerial = (int) $pdo->query('SELECT serial_no FROM activation_codes WHERE code_hmac = ' . $pdo->quote(hotelpro_pin_key($revokePin, 'test-secret')))->fetchColumn();
$revoked = hotelpro_admin_revoke($pdo, (string) $loggedIn['session']['admin_id'], $revokeSerial);
$revokedRedeem = api($config, 'POST', '/v1/license/redeem', ['pin' => $revokePin], $headersA);
$afterRevoke = $pdo->query('SELECT record_id, revision, payload FROM hotel_records WHERE business_id = ' . $pdo->quote($first['body']['businessId']) . ' ORDER BY record_id')->fetchAll();
check($revoked['ok'] === true && $revokedRedeem['status'] === 403 && $afterRevoke === $recordsBeforeAdmin, 'a revoked PIN is rejected and hotel records stay');
$recordCount = (int) $pdo->query('SELECT COUNT(*) FROM hotel_records')->fetchColumn();
$wrongCancel = hotelpro_admin_cancel_license($pdo, (string) $loggedIn['session']['admin_id'], $first['body']['businessId'], 'no');
$cancelled = hotelpro_admin_cancel_license($pdo, (string) $loggedIn['session']['admin_id'], $first['body']['businessId'], $first['body']['businessId']);
check($wrongCancel['ok'] === false && $cancelled['ok'] === true && (int) $pdo->query('SELECT COUNT(*) FROM hotel_records')->fetchColumn() === $recordCount, 'cancelling a license asks for confirmation and keeps hotel data');
$cancelledWrite = api($config, 'POST', '/v1/sync', [
    'idempotencyKey' => 'idempotency-key-cancel1',
    'changes' => [['entity' => 'expenses', 'recordId' => 'exp_cancel', 'baseRevision' => 0, 'payload' => ['amount' => 10]]],
], $headersA);
check($cancelledWrite['status'] === 403, 'a cancelled license cannot add hotel data');
$history = hotelpro_admin_history($pdo, $first['body']['businessId']);
check(count($history['redemptions']) >= 2 && count($history['audit']) >= 1, 'hotel history keeps activation and admin actions');
$found = hotelpro_admin_customers($pdo, $config, '9000000001');
check($found !== [] && $found[0]['hotel_name'] === 'Hotel A' && $found[0]['last_sync'] !== null, 'customer search finds the hotel and its last sync');
$totals = hotelpro_admin_totals($pdo);
check($totals['hotels'] === 2 && $totals['redeemed'] >= 3 && $totals['unused'] >= 1 && $totals['revoked'] === 1 && $totals['expired'] >= 1, 'dashboard counts hotels, licenses, and PINs');
for ($attempt = 0; $attempt < 5; $attempt++) {
    hotelpro_admin_login($pdo, 'no-such-admin', 'wrong-password-value');
}
$lockedLogin = hotelpro_admin_login($pdo, 'no-such-admin', 'wrong-password-value');
check($lockedLogin['status'] === 429, 'admin login locks after repeated failures');
$auditBlob = (string) $pdo->query('SELECT GROUP_CONCAT(detail) FROM audit_log')->fetchColumn();
check(!str_contains($auditBlob, $adminPassword) && !str_contains($auditBlob, $assignPin) && !str_contains($auditBlob, $revokePin), 'audit log does not store passwords or PINs');

$admin->exec('DROP DATABASE IF EXISTS hotelpro_cpanel_test');
$admin->exec('DROP USER IF EXISTS ' . $admin->quote('hotelpro_test') . '@' . $admin->quote('127.0.0.1'));
exit($failed > 0 ? 1 : 0);
