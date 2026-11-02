<?php
declare(strict_types=1);

const HOTELPRO_ENTITIES = [
    'rooms', 'bookings', 'guests', 'bills', 'payments', 'future_bookings',
    'expenses', 'extra_charges', 'closed_rooms', 'settings',
];
const HOTELPRO_FINANCIAL = ['bills', 'payments'];

function hotelpro_request_headers(): array
{
    if (function_exists('getallheaders')) {
        $headers = getallheaders();
        if (is_array($headers) && $headers !== []) {
            return $headers;
        }
    }
    $headers = [];
    foreach ($_SERVER as $name => $value) {
        if (!is_string($name) || !str_starts_with($name, 'HTTP_')) {
            continue;
        }
        $key = str_replace(' ', '-', ucwords(strtolower(str_replace('_', ' ', substr($name, 5)))));
        $headers[$key] = $value;
    }
    return $headers;
}

function hotelpro_pdo(array $config): PDO
{
    $db = $config['db'];
    $dsn = sprintf('mysql:host=%s;dbname=%s;charset=%s', $db['host'], $db['name'], $db['charset'] ?? 'utf8mb4');
    $pdo = new PDO($dsn, $db['user'], $db['pass'], [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]);
    $pdo->exec("SET time_zone = '+00:00'");
    return $pdo;
}

function hotelpro_now(): DateTimeImmutable
{
    return new DateTimeImmutable('now', new DateTimeZone('UTC'));
}

function hotelpro_fmt(DateTimeImmutable $time): string
{
    return $time->format('Y-m-d H:i:s.u');
}

function hotelpro_parse(string $value): DateTimeImmutable
{
    return new DateTimeImmutable($value, new DateTimeZone('UTC'));
}

function hotelpro_add_year(DateTimeImmutable $date): DateTimeImmutable
{
    $month = (int) $date->format('n');
    $day = (int) $date->format('j');
    if ($month === 2 && $day === 29) {
        $day = 28;
    }
    return $date->setDate(((int) $date->format('Y')) + 1, $month, $day);
}

function hotelpro_phone(string $countryCode, string $mobile): string
{
    $country = preg_replace('/\D+/', '', $countryCode) ?? '';
    $national = preg_replace('/\D+/', '', $mobile) ?? '';
    if ($national !== '' && str_starts_with($national, $country)) {
        $national = substr($national, strlen($country));
    }
    if ($country === '' || strlen($national) < 6 || strlen($national) > 12) {
        throw new InvalidArgumentException('Enter a valid mobile number');
    }
    return '+' . $country . $national;
}

function hotelpro_hash(string $value): string
{
    return hash('sha256', $value);
}

function hotelpro_pin_key(string $pin, string $secret): string
{
    if (!preg_match('/^\d{8}$/', $pin) || $secret === '') {
        throw new InvalidArgumentException('Invalid activation input');
    }
    return hash_hmac('sha256', $pin, $secret);
}

function hotelpro_pin_export_csv(array $rows): string
{
    $handle = fopen('php://temp', 'r+');
    fputcsv($handle, ['Serial Number', 'PIN', 'Validity'], ',', '"', '\\');
    foreach ($rows as $row) {
        $pin = (string) $row['pin'];
        fputcsv($handle, [(string) $row['serial'], '="' . $pin . '"', (string) $row['validity']], ',', '"', '\\');
    }
    rewind($handle);
    $csv = (string) stream_get_contents($handle);
    fclose($handle);
    return $csv;
}

function hotelpro_issue_pins(PDO $pdo, array $config, int $count = 100, ?string $adminId = null): array
{
    if ($count !== 100) {
        throw new InvalidArgumentException('A batch contains 100 PINs');
    }
    $secret = (string) ($config['pin_hmac_secret'] ?? '');
    $pins = [];
    $seen = [];
    while (count($pins) < $count) {
        $pin = str_pad((string) random_int(0, 99999999), 8, '0', STR_PAD_LEFT);
        if (isset($seen['k' . $pin])) {
            continue;
        }
        $seen['k' . $pin] = true;
        $pins[] = $pin;
    }
    $batchId = bin2hex(random_bytes(16));
    $serial = (int) $pdo->query('SELECT COALESCE(MAX(serial_no), 0) FROM activation_codes')->fetchColumn();
    $firstSerial = $serial + 1;
    $pdo->beginTransaction();
    try {
        $insert = $pdo->prepare('INSERT INTO activation_codes (code_hmac, serial_no, batch_id, last4, status, plan) VALUES (?, ?, ?, ?, ?, ?)');
        $rows = [];
        foreach ($pins as $pin) {
            $serial++;
            $insert->execute([hotelpro_pin_key($pin, $secret), $serial, $batchId, substr($pin, -4), 'issued', 'annual']);
            $rows[] = ['serial' => $serial, 'pin' => $pin, 'validity' => '1 year'];
        }
        if ($adminId !== null) {
            $audit = $pdo->prepare('INSERT INTO audit_log (admin_id, action, subject, detail, created_at) VALUES (?, ?, ?, ?, ?)');
            $audit->execute([$adminId, 'pins_issued', $batchId, json_encode(['count' => $count, 'firstSerial' => $firstSerial, 'lastSerial' => $serial]), hotelpro_fmt(hotelpro_now())]);
        }
        $pdo->commit();
    } catch (Throwable $error) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        throw $error;
    }
    return ['batchId' => $batchId, 'rows' => $rows];
}

function hotelpro_default_rooms(): array
{
    $path = dirname(__DIR__) . '/shared/default_rooms.json';
    if (!is_file($path)) {
        $path = dirname(__DIR__, 2) . '/shared/default_rooms.json';
    }
    $specs = json_decode((string) file_get_contents($path), true);
    $rooms = [];
    foreach ($specs as $spec) {
        $rooms[] = [
            'id' => 'room_' . $spec['roomNumber'],
            'payload' => [
                'roomNumber' => $spec['roomNumber'],
                'roomName' => '',
                'roomType' => $spec['roomType'],
                'normalRent' => $spec['normalRent'],
                'status' => 'EMPTY',
                'faultReason' => '',
                'mobile' => '',
                'guestName' => '',
                'idNumber' => '',
                'guestAddress' => '',
                'bookingRate' => $spec['normalRent'],
                'days' => 0,
                'advance' => 0,
                'paymentMode' => '',
                'billNumber' => '',
                'applyGst' => false,
                'futureBooking' => false,
                'charges' => [],
                'partPayments' => [],
                'extraGuests' => [],
                'futureExtraGuests' => [],
                'deleted' => false,
            ],
        ];
    }
    return $rooms;
}

function hotelpro_public_license(array $license, DateTimeImmutable $now): array
{
    $trialEnd = hotelpro_parse($license['trial_ends_at']);
    $expires = $license['expires_at'] ? hotelpro_parse($license['expires_at']) : null;
    $writable = ($expires && $now < $expires) || (!$expires && $now < $trialEnd && (int) $license['activated'] !== 1);
    if ((int) $license['activated'] === 1 && $expires && $now < $expires) {
        $writable = true;
    }
    if ($expires && $now < $expires) {
        $writable = true;
    }
    return [
        'trialStartedAt' => hotelpro_parse($license['trial_started_at'])->format(DATE_ATOM),
        'trialEndsAt' => $trialEnd->format(DATE_ATOM),
        'expiresAt' => $expires?->format(DATE_ATOM),
        'activated' => (int) $license['activated'] === 1,
        'canWrite' => $writable,
    ];
}

function hotelpro_can_write(array $license, DateTimeImmutable $now): bool
{
    return hotelpro_public_license($license, $now)['canWrite'] === true;
}

function hotelpro_issue_tokens(PDO $pdo, array $config, string $userId, ?string $family = null): array
{
    $now = hotelpro_now();
    $access = bin2hex(random_bytes(32));
    $refresh = bin2hex(random_bytes(32));
    $family ??= bin2hex(random_bytes(16));
    $insertAccess = $pdo->prepare('INSERT INTO access_tokens (token_hash, user_id, expires_at, revoked) VALUES (?, ?, ?, 0)');
    $insertAccess->execute([
        hotelpro_hash($config['token_pepper'] . $access),
        $userId,
        hotelpro_fmt($now->modify('+' . (int) $config['access_ttl_seconds'] . ' seconds')),
    ]);
    $insertRefresh = $pdo->prepare('INSERT INTO refresh_tokens (token_hash, user_id, family_id, expires_at, revoked) VALUES (?, ?, ?, ?, 0)');
    $insertRefresh->execute([
        hotelpro_hash($config['token_pepper'] . $refresh),
        $userId,
        $family,
        hotelpro_fmt($now->modify('+' . (int) $config['refresh_ttl_seconds'] . ' seconds')),
    ]);
    return ['accessToken' => $access, 'refreshToken' => $refresh, 'tokenType' => 'Bearer'];
}

function hotelpro_user_from_access(PDO $pdo, array $config, array $headers): ?array
{
    $header = '';
    foreach ($headers as $name => $value) {
        if (strtolower((string) $name) === 'authorization') {
            $header = (string) $value;
        }
    }
    if (!preg_match('/^Bearer\s+([a-f0-9]{64})$/', $header, $match)) {
        return null;
    }
    $statement = $pdo->prepare(
        'SELECT u.id, u.owner_name, u.phone_e164, m.business_id, m.role
         FROM access_tokens t
         JOIN users u ON u.id = t.user_id
         JOIN business_members m ON m.user_id = u.id
         WHERE t.token_hash = ? AND t.revoked = 0 AND t.expires_at > UTC_TIMESTAMP(6)'
    );
    $statement->execute([hotelpro_hash($config['token_pepper'] . $match[1])]);
    $user = $statement->fetch();
    return $user ?: null;
}

function hotelpro_membership(array $user, array $body): array
{
    $requested = $body['businessId'] ?? null;
    if (is_string($requested) && $requested !== '' && $requested !== $user['business_id']) {
        throw new RuntimeException('forbidden');
    }
    return $user;
}

function hotelpro_register(PDO $pdo, array $config, array $body): array
{
    $owner = trim((string) ($body['ownerName'] ?? ''));
    $hotel = trim((string) ($body['hotelName'] ?? ''));
    $password = (string) ($body['password'] ?? '');
    $confirm = (string) ($body['passwordAgain'] ?? '');
    $email = trim((string) ($body['email'] ?? ''));
    if ($owner === '' || $hotel === '' || strlen($password) < 8 || $password !== $confirm) {
        return ['status' => 422, 'body' => ['error' => 'Check the registration details']];
    }
    try {
        $phone = hotelpro_phone((string) ($body['countryCode'] ?? ''), (string) ($body['mobile'] ?? ''));
    } catch (InvalidArgumentException) {
        return ['status' => 422, 'body' => ['error' => 'Check the registration details']];
    }
    if ($email !== '' && !filter_var($email, FILTER_VALIDATE_EMAIL)) {
        return ['status' => 422, 'body' => ['error' => 'Check the registration details']];
    }
    $now = hotelpro_now();
    $userId = bin2hex(random_bytes(16));
    $businessId = 'biz_' . bin2hex(random_bytes(12));
    try {
        $pdo->beginTransaction();
        $insertUser = $pdo->prepare('INSERT INTO users (id, owner_name, phone_e164, email, password_hash, created_at) VALUES (?, ?, ?, ?, ?, ?)');
        $insertUser->execute([$userId, $owner, $phone, $email === '' ? null : $email, password_hash($password, PASSWORD_DEFAULT), hotelpro_fmt($now)]);
        $trialEnd = $now->modify('+10 days');
        $insertBusiness = $pdo->prepare('INSERT INTO businesses (id, name, owner_user_id, created_at, trial_started_at, trial_ends_at, default_rooms_created, next_revision) VALUES (?, ?, ?, ?, ?, ?, 0, 0)');
        $insertBusiness->execute([$businessId, $hotel, $userId, hotelpro_fmt($now), hotelpro_fmt($now), hotelpro_fmt($trialEnd)]);
        $insertMember = $pdo->prepare('INSERT INTO business_members (business_id, user_id, role, created_at) VALUES (?, ?, ?, ?)');
        $insertMember->execute([$businessId, $userId, 'owner', hotelpro_fmt($now)]);
        $insertLicense = $pdo->prepare('INSERT INTO licenses (business_id, trial_started_at, trial_ends_at, activated) VALUES (?, ?, ?, 0)');
        $insertLicense->execute([$businessId, hotelpro_fmt($now), hotelpro_fmt($trialEnd)]);
        hotelpro_create_default_rooms($pdo, $businessId, $now);
        $tokens = hotelpro_issue_tokens($pdo, $config, $userId);
        $pdo->commit();
    } catch (PDOException $error) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        if ((string) $error->getCode() === '23000') {
            return ['status' => 409, 'body' => ['error' => 'An account already exists for this mobile number']];
        }
        return ['status' => 500, 'body' => ['error' => 'Registration failed']];
    }
    $license = $pdo->prepare('SELECT * FROM licenses WHERE business_id = ?');
    $license->execute([$businessId]);
    return ['status' => 201, 'body' => $tokens + [
        'userId' => $userId,
        'businessId' => $businessId,
        'hotelName' => $hotel,
        'license' => hotelpro_public_license($license->fetch(), $now),
        'rooms' => array_map(fn ($room) => $room['payload'] + ['recordId' => $room['id']], hotelpro_default_rooms()),
    ]];
}

function hotelpro_create_default_rooms(PDO $pdo, string $businessId, DateTimeImmutable $now): int
{
    $lock = $pdo->prepare('SELECT default_rooms_created, next_revision FROM businesses WHERE id = ? FOR UPDATE');
    $lock->execute([$businessId]);
    $business = $lock->fetch();
    if (!$business || (int) $business['default_rooms_created'] === 1) {
        return 0;
    }
    $revision = (int) $business['next_revision'];
    $insert = $pdo->prepare('INSERT INTO hotel_records (business_id, entity, record_id, revision, deleted, payload, bill_number, updated_at) VALUES (?, ?, ?, ?, 0, ?, NULL, ?)');
    $added = 0;
    foreach (hotelpro_default_rooms() as $room) {
        $exists = $pdo->prepare('SELECT record_id FROM hotel_records WHERE business_id = ? AND entity = ? AND record_id = ?');
        $exists->execute([$businessId, 'rooms', $room['id']]);
        if ($exists->fetch()) {
            continue;
        }
        $revision++;
        $insert->execute([$businessId, 'rooms', $room['id'], $revision, json_encode($room['payload']), hotelpro_fmt($now)]);
        $added++;
    }
    $mark = $pdo->prepare('UPDATE businesses SET default_rooms_created = 1, next_revision = ? WHERE id = ?');
    $mark->execute([$revision, $businessId]);
    return $added;
}

function hotelpro_login(PDO $pdo, array $config, array $body): array
{
    try {
        $phone = hotelpro_phone((string) ($body['countryCode'] ?? ''), (string) ($body['mobile'] ?? ''));
    } catch (InvalidArgumentException) {
        return ['status' => 401, 'body' => ['error' => 'Login failed']];
    }
    $password = (string) ($body['password'] ?? '');
    $phoneHash = hotelpro_hash($phone);
    $now = hotelpro_now();
    $attempt = $pdo->prepare('SELECT * FROM login_attempts WHERE phone_hash = ?');
    $attempt->execute([$phoneHash]);
    $prior = $attempt->fetch();
    if ($prior && $prior['locked_until'] && hotelpro_parse($prior['locked_until']) > $now) {
        return ['status' => 429, 'body' => ['error' => 'Too many attempts. Try later.']];
    }
    $user = $pdo->prepare('SELECT id, password_hash FROM users WHERE phone_e164 = ?');
    $user->execute([$phone]);
    $row = $user->fetch();
    if (!$row || !password_verify($password, $row['password_hash'])) {
        $count = 1;
        $start = $now;
        if ($prior && hotelpro_parse($prior['window_start']) > $now->modify('-15 minutes')) {
            $count = ((int) $prior['fail_count']) + 1;
            $start = hotelpro_parse($prior['window_start']);
        }
        $locked = $count >= 5 ? $now->modify('+15 minutes') : null;
        $save = $pdo->prepare('REPLACE INTO login_attempts (phone_hash, window_start, fail_count, locked_until) VALUES (?, ?, ?, ?)');
        $save->execute([$phoneHash, hotelpro_fmt($start), $count >= 5 ? 0 : $count, $locked ? hotelpro_fmt($locked) : null]);
        return ['status' => 401, 'body' => ['error' => 'Login failed']];
    }
    $clear = $pdo->prepare('DELETE FROM login_attempts WHERE phone_hash = ?');
    $clear->execute([$phoneHash]);
    $member = $pdo->prepare('SELECT b.id, b.name, m.role FROM business_members m JOIN businesses b ON b.id = m.business_id WHERE m.user_id = ?');
    $member->execute([$row['id']]);
    $business = $member->fetch();
    $license = $pdo->prepare('SELECT * FROM licenses WHERE business_id = ?');
    $license->execute([$business['id']]);
    $pdo->beginTransaction();
    $tokens = hotelpro_issue_tokens($pdo, $config, $row['id']);
    $pdo->commit();
    return ['status' => 200, 'body' => $tokens + [
        'userId' => $row['id'],
        'businessId' => $business['id'],
        'role' => $business['role'],
        'hotelName' => $business['name'],
        'license' => hotelpro_public_license($license->fetch(), $now),
    ]];
}

function hotelpro_refresh(PDO $pdo, array $config, array $body): array
{
    $refresh = (string) ($body['refreshToken'] ?? '');
    if (!preg_match('/^[a-f0-9]{64}$/', $refresh)) {
        return ['status' => 401, 'body' => ['error' => 'Login again']];
    }
    $hash = hotelpro_hash($config['token_pepper'] . $refresh);
    $pdo->beginTransaction();
    $statement = $pdo->prepare('SELECT * FROM refresh_tokens WHERE token_hash = ? FOR UPDATE');
    $statement->execute([$hash]);
    $row = $statement->fetch();
    if (!$row || (int) $row['revoked'] === 1 || hotelpro_parse($row['expires_at']) <= hotelpro_now()) {
        if ($row && (int) $row['revoked'] === 1) {
            $revoke = $pdo->prepare('UPDATE refresh_tokens SET revoked = 1 WHERE family_id = ?');
            $revoke->execute([$row['family_id']]);
        }
        $pdo->commit();
        return ['status' => 401, 'body' => ['error' => 'Login again']];
    }
    $revoke = $pdo->prepare('UPDATE refresh_tokens SET revoked = 1 WHERE token_hash = ?');
    $revoke->execute([$hash]);
    $tokens = hotelpro_issue_tokens($pdo, $config, $row['user_id'], $row['family_id']);
    $pdo->commit();
    return ['status' => 200, 'body' => $tokens];
}

function hotelpro_logout(PDO $pdo, array $config, array $user, array $headers): array
{
    $header = '';
    foreach ($headers as $name => $value) {
        if (strtolower((string) $name) === 'authorization') {
            $header = (string) $value;
        }
    }
    if (preg_match('/^Bearer\s+([a-f0-9]{64})$/', $header, $match)) {
        $revoke = $pdo->prepare('UPDATE access_tokens SET revoked = 1 WHERE token_hash = ?');
        $revoke->execute([hotelpro_hash($config['token_pepper'] . $match[1])]);
    }
    $revokeRefresh = $pdo->prepare('UPDATE refresh_tokens SET revoked = 1 WHERE user_id = ?');
    $revokeRefresh->execute([$user['id']]);
    return ['status' => 200, 'body' => ['loggedOut' => true]];
}

function hotelpro_strip_photo_bytes(array $payload): array
{
    foreach (['idFrontPhoto', 'idBackPhoto', 'idFrontPhotoPath', 'idBackPhotoPath', 'idFrontBase64', 'idBackBase64', 'frontPhoto', 'backPhoto', 'idPhotoPath', 'photoData', 'photo'] as $field) {
        if (isset($payload[$field]) && is_string($payload[$field]) && strlen($payload[$field]) > 80) {
            unset($payload[$field]);
        }
    }
    foreach (['extraGuests', 'futureExtraGuests'] as $list) {
        if (!isset($payload[$list]) || !is_array($payload[$list])) {
            continue;
        }
        foreach ($payload[$list] as $index => $guest) {
            if (is_array($guest)) {
                $payload[$list][$index] = hotelpro_strip_photo_bytes($guest);
            }
        }
    }
    return $payload;
}

function hotelpro_push(PDO $pdo, array $user, array $body): array
{
    $changes = $body['changes'] ?? null;
    if (!is_array($changes) || $changes === []) {
        return ['status' => 422, 'body' => ['error' => 'No changes']];
    }
    $now = hotelpro_now();
    $licenseStatement = $pdo->prepare('SELECT * FROM licenses WHERE business_id = ?');
    $licenseStatement->execute([$user['business_id']]);
    $license = $licenseStatement->fetch();
    if (!$license || !hotelpro_can_write($license, $now)) {
        return ['status' => 403, 'body' => ['error' => 'License required for new changes. Existing data remains.']];
    }
    $businessId = $user['business_id'];
    $key = (string) ($body['idempotencyKey'] ?? '');
    if (!preg_match('/^[A-Za-z0-9_-]{16,80}$/', $key)) {
        return ['status' => 422, 'body' => ['error' => 'Missing idempotency key']];
    }
    $pdo->beginTransaction();
    $seen = $pdo->prepare('SELECT response_json FROM idempotency_keys WHERE business_id = ? AND idempotency_key = ?');
    $seen->execute([$businessId, $key]);
    $previous = $seen->fetch();
    if ($previous) {
        $pdo->commit();
        return ['status' => 200, 'body' => json_decode($previous['response_json'], true)];
    }
    $lock = $pdo->prepare('SELECT next_revision FROM businesses WHERE id = ? FOR UPDATE');
    $lock->execute([$businessId]);
    $revision = (int) $lock->fetch()['next_revision'];
    $applied = [];
    $conflicts = [];
    foreach ($changes as $change) {
        $entity = (string) ($change['entity'] ?? '');
        $recordId = (string) ($change['recordId'] ?? '');
        $base = (int) ($change['baseRevision'] ?? 0);
        if (!in_array($entity, HOTELPRO_ENTITIES, true) || !preg_match('/^[A-Za-z0-9_.:-]{1,80}$/', $recordId)) {
            $pdo->rollBack();
            return ['status' => 422, 'body' => ['error' => 'Invalid record']];
        }
        $current = $pdo->prepare('SELECT revision, payload, deleted FROM hotel_records WHERE business_id = ? AND entity = ? AND record_id = ? FOR UPDATE');
        $current->execute([$businessId, $entity, $recordId]);
        $row = $current->fetch();
        if ($row && (int) $row['revision'] !== $base) {
            $conflicts[] = [
                'entity' => $entity,
                'recordId' => $recordId,
                'serverRevision' => (int) $row['revision'],
                'financial' => in_array($entity, HOTELPRO_FINANCIAL, true),
            ];
            continue;
        }
        if (!$row && $base !== 0) {
            $conflicts[] = ['entity' => $entity, 'recordId' => $recordId, 'serverRevision' => 0, 'financial' => in_array($entity, HOTELPRO_FINANCIAL, true)];
            continue;
        }
        $payload = $change['payload'] ?? [];
        if (!is_array($payload)) {
            $pdo->rollBack();
            return ['status' => 422, 'body' => ['error' => 'Invalid record']];
        }
        $payload = hotelpro_strip_photo_bytes($payload);
        $deleted = !empty($change['deleted']) || !empty($payload['deleted']);
        $payload['deleted'] = $deleted;
        $billNumber = null;
        if ($entity === 'bills') {
            $billNumber = trim((string) ($payload['billNumber'] ?? ''));
            if ($billNumber === '') {
                $pdo->rollBack();
                return ['status' => 422, 'body' => ['error' => 'Bill number required']];
            }
            $duplicate = $pdo->prepare('SELECT record_id FROM hotel_records WHERE business_id = ? AND entity = ? AND bill_number = ? AND record_id <> ? AND deleted = 0');
            $duplicate->execute([$businessId, 'bills', $billNumber, $recordId]);
            if ($duplicate->fetch() && !$deleted) {
                $pdo->rollBack();
                return ['status' => 409, 'body' => ['error' => 'Duplicate bill', 'conflicts' => [['entity' => 'bills', 'recordId' => $recordId, 'financial' => true]]]];
            }
        }
        $revision++;
        $save = $pdo->prepare(
            'INSERT INTO hotel_records (business_id, entity, record_id, revision, deleted, payload, bill_number, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE revision = VALUES(revision), deleted = VALUES(deleted), payload = VALUES(payload), bill_number = VALUES(bill_number), updated_at = VALUES(updated_at)'
        );
        $save->execute([$businessId, $entity, $recordId, $revision, $deleted ? 1 : 0, json_encode($payload), $billNumber, hotelpro_fmt($now)]);
        $applied[] = ['entity' => $entity, 'recordId' => $recordId, 'revision' => $revision];
    }
    if ($conflicts !== []) {
        $pdo->rollBack();
        return ['status' => 409, 'body' => ['error' => 'Conflict needs a choice. Financial records were not overwritten.', 'conflicts' => $conflicts]];
    }
    $bump = $pdo->prepare('UPDATE businesses SET next_revision = ? WHERE id = ?');
    $bump->execute([$revision, $businessId]);
    $response = ['applied' => $applied, 'cursor' => $revision];
    $remember = $pdo->prepare('INSERT INTO idempotency_keys (business_id, idempotency_key, response_json, created_at) VALUES (?, ?, ?, ?)');
    $remember->execute([$businessId, $key, json_encode($response), hotelpro_fmt($now)]);
    $pdo->commit();
    return ['status' => 200, 'body' => $response];
}

function hotelpro_pull(PDO $pdo, array $user, array $query): array
{
    $cursor = max(0, (int) ($query['cursor'] ?? 0));
    $limit = min(200, max(1, (int) ($query['limit'] ?? 100)));
    $statement = $pdo->prepare(
        'SELECT entity, record_id, revision, deleted, payload FROM hotel_records
         WHERE business_id = ? AND revision > ? ORDER BY revision ASC LIMIT ' . $limit
    );
    $statement->execute([$user['business_id'], $cursor]);
    $rows = $statement->fetchAll();
    $next = $cursor;
    $changes = [];
    foreach ($rows as $row) {
        $next = (int) $row['revision'];
        $payload = json_decode($row['payload'], true) ?: [];
        $changes[] = [
            'entity' => $row['entity'],
            'recordId' => $row['record_id'],
            'revision' => $next,
            'deleted' => (int) $row['deleted'] === 1,
            'payload' => $payload,
        ];
    }
    $license = $pdo->prepare('SELECT * FROM licenses WHERE business_id = ?');
    $license->execute([$user['business_id']]);
    return ['status' => 200, 'body' => [
        'changes' => $changes,
        'cursor' => $next,
        'userId' => $user['id'],
        'businessId' => $user['business_id'],
        'role' => $user['role'],
        'license' => hotelpro_public_license($license->fetch(), hotelpro_now()),
    ]];
}

function hotelpro_redeem(PDO $pdo, array $config, array $user, array $body): array
{
    try {
        $key = hotelpro_pin_key((string) ($body['pin'] ?? ''), (string) $config['pin_hmac_secret']);
    } catch (InvalidArgumentException) {
        return ['status' => 422, 'body' => ['error' => 'Activation unsuccessful']];
    }
    $now = hotelpro_now();
    $pdo->beginTransaction();
    $attempt = $pdo->prepare('SELECT * FROM pin_attempts WHERE user_id = ? FOR UPDATE');
    $attempt->execute([$user['id']]);
    $prior = $attempt->fetch() ?: null;
    if ($prior && $prior['locked_until'] && hotelpro_parse($prior['locked_until']) > $now) {
        $pdo->commit();
        return ['status' => 429, 'body' => ['error' => 'Too many attempts. Try later.']];
    }
    $code = $pdo->prepare('SELECT * FROM activation_codes WHERE code_hmac = ? FOR UPDATE');
    $code->execute([$key]);
    $pin = $code->fetch();
    $licenseStatement = $pdo->prepare('SELECT * FROM licenses WHERE business_id = ? FOR UPDATE');
    $licenseStatement->execute([$user['business_id']]);
    $license = $licenseStatement->fetch();
    if ($pin && $pin['status'] === 'redeemed' && $pin['business_id'] === $user['business_id'] && $license['last_redemption_id'] === $key) {
        $pdo->commit();
        $public = hotelpro_public_license($license, $now);
        return ['status' => 200, 'body' => ['activated' => true, 'idempotent' => true, 'expiresAt' => $public['expiresAt'], 'license' => $public]];
    }
    $usable = $pin && $pin['status'] === 'issued' && $pin['plan'] === 'annual' && ($pin['business_id'] === null || $pin['business_id'] === '');
    if (!$usable) {
        $count = 1;
        $start = $now;
        if ($prior && hotelpro_parse($prior['window_start']) > $now->modify('-1 hour')) {
            $count = ((int) $prior['fail_count']) + 1;
            $start = hotelpro_parse($prior['window_start']);
        }
        $locked = $count >= 5 ? $now->modify('+15 minutes') : null;
        $save = $pdo->prepare('REPLACE INTO pin_attempts (user_id, window_start, fail_count, locked_until) VALUES (?, ?, ?, ?)');
        $save->execute([$user['id'], hotelpro_fmt($start), $count >= 5 ? 0 : $count, $locked ? hotelpro_fmt($locked) : null]);
        $pdo->commit();
        return ['status' => 403, 'body' => ['error' => 'Activation unsuccessful']];
    }
    $currentExpiry = $license['expires_at'] ? hotelpro_parse($license['expires_at']) : null;
    $base = ($currentExpiry && $currentExpiry > $now) ? $currentExpiry : $now;
    $expiry = hotelpro_add_year($base);
    $consume = $pdo->prepare('UPDATE activation_codes SET status = ?, business_id = ?, redeemed_at = ? WHERE code_hmac = ? AND status = ?');
    $consume->execute(['redeemed', $user['business_id'], hotelpro_fmt($now), $key, 'issued']);
    if ($consume->rowCount() !== 1) {
        $pdo->rollBack();
        return ['status' => 409, 'body' => ['error' => 'Activation unsuccessful']];
    }
    $update = $pdo->prepare('UPDATE licenses SET activated = 1, expires_at = ?, last_redemption_id = ?, plan = ? WHERE business_id = ?');
    $update->execute([hotelpro_fmt($expiry), $key, 'annual', $user['business_id']]);
    try {
        $record = $pdo->prepare('INSERT INTO pin_redemptions (id, code_hmac, serial_no, user_id, business_id, activated_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?)');
        $record->execute([bin2hex(random_bytes(16)), $key, (int) $pin['serial_no'], $user['id'], $user['business_id'], hotelpro_fmt($now), hotelpro_fmt($expiry)]);
    } catch (Throwable) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        return ['status' => 409, 'body' => ['error' => 'Activation unsuccessful']];
    }
    $clear = $pdo->prepare('REPLACE INTO pin_attempts (user_id, window_start, fail_count, locked_until) VALUES (?, ?, 0, NULL)');
    $clear->execute([$user['id'], hotelpro_fmt($now)]);
    $pdo->commit();
    $license['activated'] = 1;
    $license['expires_at'] = hotelpro_fmt($expiry);
    $license['last_redemption_id'] = $key;
    $public = hotelpro_public_license($license, $now);
    return ['status' => 200, 'body' => ['activated' => true, 'idempotent' => false, 'expiresAt' => $public['expiresAt'], 'businessId' => $user['business_id'], 'license' => $public]];
}

function hotelpro_save_photo(PDO $pdo, array $config, array $user, array $files, array $body): array
{
    $licenseStatement = $pdo->prepare('SELECT * FROM licenses WHERE business_id = ?');
    $licenseStatement->execute([$user['business_id']]);
    if (!hotelpro_can_write($licenseStatement->fetch(), hotelpro_now())) {
        return ['status' => 403, 'body' => ['error' => 'License required for new changes. Existing data remains.']];
    }
    $guestId = (string) ($body['guestId'] ?? '');
    $slot = (string) ($body['slot'] ?? '');
    $file = $files['photo'] ?? null;
    if (!preg_match('/^[A-Za-z0-9_.:-]{1,80}$/', $guestId) || !in_array($slot, ['front', 'back'], true) || !is_array($file)) {
        return ['status' => 422, 'body' => ['error' => 'Photo was not accepted']];
    }
    $tmp = (string) ($file['tmp_name'] ?? '');
    $size = (int) ($file['size'] ?? 0);
    $trustedCliFile = PHP_SAPI === 'cli' && !empty($config['cli_test_files']) && is_file($tmp);
    if ($size < 1 || $size > (int) $config['photo_max_bytes'] || (!$trustedCliFile && !is_uploaded_file($tmp))) {
        return ['status' => 422, 'body' => ['error' => 'Photo was not accepted']];
    }
    $info = @getimagesize($tmp);
    $mime = (new finfo(FILEINFO_MIME_TYPE))->file($tmp);
    if ($mime !== 'image/jpeg' || !$info || ($info[2] ?? 0) !== IMAGETYPE_JPEG) {
        return ['status' => 422, 'body' => ['error' => 'Photo was not accepted']];
    }
    $bytes = file_get_contents($tmp);
    $sha = hash('sha256', $bytes);
    $existing = $pdo->prepare('SELECT id, storage_name FROM photos WHERE business_id = ? AND guest_id = ? AND slot = ? AND sha256 = ?');
    $existing->execute([$user['business_id'], $guestId, $slot, $sha]);
    $prior = $existing->fetch();
    if ($prior) {
        return ['status' => 200, 'body' => ['photoId' => $prior['id'], 'duplicate' => true]];
    }
    $id = bin2hex(random_bytes(16));
    $name = $id . '.jpg';
    $dir = rtrim((string) $config['storage_dir'], '/') . '/photos/' . $user['business_id'];
    if (!is_dir($dir) && !mkdir($dir, 0700, true)) {
        return ['status' => 500, 'body' => ['error' => 'Photo was not accepted']];
    }
    $destination = $dir . '/' . $name;
    $stored = $trustedCliFile ? copy($tmp, $destination) : move_uploaded_file($tmp, $destination);
    if (!$stored) {
        return ['status' => 500, 'body' => ['error' => 'Photo was not accepted']];
    }
    chmod($destination, 0600);
    $insert = $pdo->prepare('INSERT INTO photos (id, business_id, guest_id, slot, sha256, byte_size, storage_name, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)');
    $insert->execute([$id, $user['business_id'], $guestId, $slot, $sha, $size, $name, hotelpro_fmt(hotelpro_now())]);
    return ['status' => 201, 'body' => ['photoId' => $id, 'duplicate' => false]];
}

function hotelpro_read_photo(PDO $pdo, array $config, array $user, string $photoId): array
{
    if (!preg_match('/^[a-f0-9]{32}$/', $photoId)) {
        return ['status' => 404, 'body' => ['error' => 'Not found']];
    }
    $statement = $pdo->prepare('SELECT * FROM photos WHERE id = ? AND business_id = ?');
    $statement->execute([$photoId, $user['business_id']]);
    $photo = $statement->fetch();
    if (!$photo) {
        return ['status' => 404, 'body' => ['error' => 'Not found']];
    }
    $path = rtrim((string) $config['storage_dir'], '/') . '/photos/' . $photo['business_id'] . '/' . $photo['storage_name'];
    if (!is_file($path)) {
        return ['status' => 404, 'body' => ['error' => 'Not found']];
    }
    return ['status' => 200, 'body' => [], 'file' => $path];
}

function hotelpro_handle(array $config, string $method, string $path, array $body, array $headers, array $files = [], array $query = []): array
{
    $https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') || (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https');
    if (!empty($config['require_https']) && !$https && PHP_SAPI !== 'cli') {
        return ['status' => 400, 'body' => ['error' => 'HTTPS required']];
    }
    try {
        if ($method === 'GET' && $path === '/v1/health') {
            try {
                hotelpro_pdo($config)->query('SELECT 1');
                $db = true;
            } catch (Throwable) {
                $db = false;
            }
            return ['status' => $db ? 200 : 503, 'body' => ['ok' => $db, 'time' => hotelpro_now()->format(DATE_ATOM)]];
        }
        $pdo = hotelpro_pdo($config);
        if ($method === 'POST' && $path === '/v1/auth/register') {
            return hotelpro_register($pdo, $config, $body);
        }
        if ($method === 'POST' && $path === '/v1/auth/login') {
            return hotelpro_login($pdo, $config, $body);
        }
        if ($method === 'POST' && $path === '/v1/auth/refresh') {
            return hotelpro_refresh($pdo, $config, $body);
        }
        $user = hotelpro_user_from_access($pdo, $config, $headers);
        if ($user === null) {
            return ['status' => 401, 'body' => ['error' => 'Login required']];
        }
        try {
            $user = hotelpro_membership($user, $body);
        } catch (RuntimeException) {
            return ['status' => 403, 'body' => ['error' => 'Not allowed']];
        }
        if (in_array($method . ' ' . $path, ['POST /v1/sync', 'POST /v1/photos', 'POST /v1/license/redeem'], true)
            && ($user['role'] ?? '') !== 'owner') {
            return ['status' => 403, 'body' => ['error' => 'This account cannot change this hotel.']];
        }
        if ($method === 'POST' && $path === '/v1/auth/logout') {
            return hotelpro_logout($pdo, $config, $user, $headers);
        }
        if ($method === 'GET' && $path === '/v1/sync') {
            return hotelpro_pull($pdo, $user, $query ?: $_GET);
        }
        if ($method === 'POST' && $path === '/v1/sync') {
            return hotelpro_push($pdo, $user, $body);
        }
        if ($method === 'POST' && $path === '/v1/license/redeem') {
            return hotelpro_redeem($pdo, $config, $user, $body);
        }
        if ($method === 'GET' && $path === '/v1/license') {
            $license = $pdo->prepare('SELECT * FROM licenses WHERE business_id = ?');
            $license->execute([$user['business_id']]);
            return ['status' => 200, 'body' => ['businessId' => $user['business_id'], 'license' => hotelpro_public_license($license->fetch(), hotelpro_now())]];
        }
        if ($method === 'POST' && $path === '/v1/photos') {
            return hotelpro_save_photo($pdo, $config, $user, $files ?: $_FILES, $body);
        }
        if ($method === 'GET' && preg_match('#^/v1/photos/([a-f0-9]{32})$#', $path, $match)) {
            return hotelpro_read_photo($pdo, $config, $user, $match[1]);
        }
        return ['status' => 404, 'body' => ['error' => 'Not found']];
    } catch (Throwable) {
        return ['status' => 500, 'body' => ['error' => 'Request failed']];
    }
}
