<?php
declare(strict_types=1);

function hotelpro_admin_e(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES, 'UTF-8');
}

function hotelpro_admin_create(PDO $pdo, string $username, string $password): string
{
    if (!preg_match('/^[A-Za-z0-9._-]{3,40}$/', $username) || strlen($password) < 16) {
        throw new InvalidArgumentException('Admin username or password is not acceptable');
    }
    $id = bin2hex(random_bytes(16));
    $insert = $pdo->prepare('INSERT INTO admins (id, username, password_hash, created_at) VALUES (?, ?, ?, ?)');
    $insert->execute([$id, $username, password_hash($password, PASSWORD_DEFAULT), hotelpro_fmt(hotelpro_now())]);
    return $id;
}

function hotelpro_admin_from_session(PDO $pdo, array $session): ?array
{
    $id = (string) ($session['admin_id'] ?? '');
    $expires = (string) ($session['expires_at'] ?? '');
    if (!preg_match('/^[a-f0-9]{32}$/', $id) || $expires === '') {
        return null;
    }
    try {
        if (hotelpro_parse($expires) <= hotelpro_now()) {
            return null;
        }
    } catch (Throwable) {
        return null;
    }
    $statement = $pdo->prepare('SELECT id, username FROM admins WHERE id = ?');
    $statement->execute([$id]);
    $admin = $statement->fetch();
    return $admin ?: null;
}

function hotelpro_admin_safe_detail(array $detail): array
{
    unset($detail['pin'], $detail['password'], $detail['code_hmac'], $detail['password_hash']);
    return $detail;
}

function hotelpro_admin_audit(PDO $pdo, string $adminId, string $action, string $subject, array $detail): void
{
    $insert = $pdo->prepare('INSERT INTO audit_log (admin_id, action, subject, detail, created_at) VALUES (?, ?, ?, ?, ?)');
    $insert->execute([
        $adminId,
        substr($action, 0, 80),
        substr($subject, 0, 80),
        json_encode(hotelpro_admin_safe_detail($detail), JSON_UNESCAPED_UNICODE),
        hotelpro_fmt(hotelpro_now()),
    ]);
}

function hotelpro_admin_login(PDO $pdo, string $username, string $password): array
{
    $now = hotelpro_now();
    $hash = hotelpro_hash(strtolower($username));
    $attempt = $pdo->prepare('SELECT * FROM admin_login_attempts WHERE username_hash = ?');
    $attempt->execute([$hash]);
    $prior = $attempt->fetch() ?: null;
    if ($prior && $prior['locked_until'] && hotelpro_parse($prior['locked_until']) > $now) {
        return ['ok' => false, 'status' => 429, 'error' => 'Too many attempts. Try later.'];
    }
    $statement = $pdo->prepare('SELECT id, username, password_hash FROM admins WHERE username = ?');
    $statement->execute([$username]);
    $admin = $statement->fetch() ?: null;
    if (!$admin || !password_verify($password, (string) $admin['password_hash'])) {
        $count = 1;
        $start = $now;
        if ($prior && hotelpro_parse($prior['window_start']) > $now->modify('-15 minutes')) {
            $count = ((int) $prior['fail_count']) + 1;
            $start = hotelpro_parse($prior['window_start']);
        }
        $locked = $count >= 5 ? $now->modify('+15 minutes') : null;
        $save = $pdo->prepare('REPLACE INTO admin_login_attempts (username_hash, window_start, fail_count, locked_until) VALUES (?, ?, ?, ?)');
        $save->execute([$hash, hotelpro_fmt($start), $count >= 5 ? 0 : $count, $locked ? hotelpro_fmt($locked) : null]);
        return ['ok' => false, 'status' => 401, 'error' => 'Login failed'];
    }
    $pdo->prepare('DELETE FROM admin_login_attempts WHERE username_hash = ?')->execute([$hash]);
    return ['ok' => true, 'status' => 200, 'admin' => ['id' => $admin['id'], 'username' => $admin['username']]];
}

function hotelpro_admin_totals(PDO $pdo): array
{
    $now = hotelpro_fmt(hotelpro_now());
    $one = static function (PDO $pdo, string $sql) use ($now): int {
        $statement = $pdo->prepare($sql);
        $statement->execute([$now]);
        return (int) $statement->fetchColumn();
    };
    return [
        'hotels' => (int) $pdo->query('SELECT COUNT(*) FROM businesses')->fetchColumn(),
        'trial' => $one($pdo, 'SELECT COUNT(*) FROM licenses WHERE activated = 0 AND trial_ends_at > ?'),
        'active' => $one($pdo, 'SELECT COUNT(*) FROM licenses WHERE expires_at IS NOT NULL AND expires_at > ?'),
        'expired' => $one($pdo, 'SELECT COUNT(*) FROM licenses WHERE activated = 1 AND expires_at IS NOT NULL AND expires_at <= ?'),
        'unused' => (int) $pdo->query("SELECT COUNT(*) FROM activation_codes WHERE status = 'issued'")->fetchColumn(),
        'redeemed' => (int) $pdo->query("SELECT COUNT(*) FROM activation_codes WHERE status = 'redeemed'")->fetchColumn(),
        'revoked' => (int) $pdo->query("SELECT COUNT(*) FROM activation_codes WHERE status = 'revoked'")->fetchColumn(),
    ];
}

function hotelpro_admin_license_label(array $license): string
{
    $now = hotelpro_now();
    $expires = $license['expires_at'] ? hotelpro_parse((string) $license['expires_at']) : null;
    if ($expires && $expires > $now) {
        return 'active';
    }
    if ((int) $license['activated'] !== 1 && hotelpro_parse((string) $license['trial_ends_at']) > $now) {
        return 'trial';
    }
    if ((int) $license['activated'] === 1 && $expires && $expires <= $now) {
        return 'expired';
    }
    return 'trial ended';
}

function hotelpro_admin_like(string $value): string
{
    return '%' . str_replace(['|', '%', '_'], ['||', '|%', '|_'], $value) . '%';
}

function hotelpro_admin_customers(PDO $pdo, array $config, string $query): array
{
    $query = trim($query);
    $sql = 'SELECT u.owner_name, u.phone_e164, u.created_at AS registered_at, b.id AS business_id, b.name AS hotel_name,
        l.trial_ends_at, l.activated, l.expires_at,
        (SELECT MAX(updated_at) FROM hotel_records r WHERE r.business_id = b.id) AS last_sync
        FROM businesses b
        JOIN users u ON u.id = b.owner_user_id
        JOIN licenses l ON l.business_id = b.id';
    $params = [];
    if ($query !== '') {
        $like = hotelpro_admin_like($query);
        $sql .= ' WHERE u.owner_name LIKE ? ESCAPE \'|\' OR u.phone_e164 LIKE ? ESCAPE \'|\' OR b.name LIKE ? ESCAPE \'|\' OR b.id LIKE ? ESCAPE \'|\'
            OR EXISTS (SELECT 1 FROM activation_codes c WHERE c.business_id = b.id AND (CAST(c.serial_no AS CHAR) = ? OR c.last4 = ?))';
        $params = [$like, $like, $like, $like, $query, $query];
        if (preg_match('/^\d{8}$/', $query) === 1) {
            $sql .= ' OR b.id = (SELECT business_id FROM activation_codes WHERE code_hmac = ? LIMIT 1)';
            $params[] = hotelpro_pin_key($query, (string) $config['pin_hmac_secret']);
        }
    }
    $sql .= ' ORDER BY u.created_at DESC LIMIT 200';
    $statement = $pdo->prepare($sql);
    $statement->execute($params);
    return $statement->fetchAll();
}

function hotelpro_admin_pins(PDO $pdo, array $config, string $query): array
{
    $query = trim($query);
    $sql = 'SELECT serial_no, batch_id, last4, status, assigned_label, assigned_at, business_id, redeemed_at, revoked_at
        FROM activation_codes';
    $params = [];
    if ($query !== '') {
        $like = hotelpro_admin_like($query);
        $sql .= ' WHERE CAST(serial_no AS CHAR) = ? OR last4 = ? OR batch_id = ? OR assigned_label LIKE ? ESCAPE \'|\' OR business_id = ?';
        $params = [$query, $query, $query, $like, $query];
        if (preg_match('/^\d{8}$/', $query) === 1) {
            $sql .= ' OR code_hmac = ?';
            $params[] = hotelpro_pin_key($query, (string) $config['pin_hmac_secret']);
        }
    }
    $sql .= ' ORDER BY serial_no DESC LIMIT 300';
    $statement = $pdo->prepare($sql);
    $statement->execute($params);
    return $statement->fetchAll();
}

function hotelpro_admin_history(PDO $pdo, string $businessId): array
{
    $redemptions = $pdo->prepare('SELECT r.serial_no, r.user_id, r.business_id, r.activated_at, r.expires_at, c.last4, c.assigned_label, c.assigned_at
        FROM pin_redemptions r JOIN activation_codes c ON c.code_hmac = r.code_hmac
        WHERE r.business_id = ? ORDER BY r.activated_at');
    $redemptions->execute([$businessId]);
    $audit = $pdo->prepare('SELECT action, subject, detail, created_at FROM audit_log
        WHERE subject = ? OR JSON_UNQUOTE(JSON_EXTRACT(detail, \'$.businessId\')) = ?
        ORDER BY id');
    $audit->execute([$businessId, $businessId]);
    return ['redemptions' => $redemptions->fetchAll(), 'audit' => $audit->fetchAll()];
}

function hotelpro_admin_assign(PDO $pdo, string $adminId, int $serial, string $label): array
{
    $label = trim($label);
    if ($serial < 1 || $label === '' || strlen($label) > 160 || preg_match('/^\d{8}$/', $label) === 1) {
        return ['ok' => false, 'error' => 'Assignment was not saved'];
    }
    $pdo->beginTransaction();
    $update = $pdo->prepare('UPDATE activation_codes SET assigned_label = ?, assigned_at = ?, assigned_by = ? WHERE serial_no = ? AND status = \'issued\'');
    $update->execute([$label, hotelpro_fmt(hotelpro_now()), $adminId, $serial]);
    if ($update->rowCount() !== 1) {
        $pdo->rollBack();
        return ['ok' => false, 'error' => 'Only an unused PIN can be assigned'];
    }
    hotelpro_admin_audit($pdo, $adminId, 'pin_assigned', 'serial:' . $serial, ['serial' => $serial, 'assignedTo' => $label]);
    $pdo->commit();
    return ['ok' => true];
}

function hotelpro_admin_revoke(PDO $pdo, string $adminId, int $serial): array
{
    if ($serial < 1) {
        return ['ok' => false, 'error' => 'Only an unused PIN can be revoked'];
    }
    $pdo->beginTransaction();
    $update = $pdo->prepare('UPDATE activation_codes SET status = \'revoked\', revoked_at = ? WHERE serial_no = ? AND status = \'issued\'');
    $update->execute([hotelpro_fmt(hotelpro_now()), $serial]);
    if ($update->rowCount() !== 1) {
        $pdo->rollBack();
        return ['ok' => false, 'error' => 'Only an unused PIN can be revoked'];
    }
    hotelpro_admin_audit($pdo, $adminId, 'pin_revoked', 'serial:' . $serial, ['serial' => $serial]);
    $pdo->commit();
    return ['ok' => true];
}

function hotelpro_admin_cancel_license(PDO $pdo, string $adminId, string $businessId, string $confirmation): array
{
    if (!preg_match('/^biz_[a-f0-9]{24}$/', $businessId) || $confirmation !== $businessId) {
        return ['ok' => false, 'error' => 'Type the business ID to confirm. Hotel data is not deleted.'];
    }
    $pdo->beginTransaction();
    $license = $pdo->prepare('SELECT business_id FROM licenses WHERE business_id = ? FOR UPDATE');
    $license->execute([$businessId]);
    if (!$license->fetch()) {
        $pdo->rollBack();
        return ['ok' => false, 'error' => 'License was not changed'];
    }
    $expires = hotelpro_now()->modify('-1 second');
    $update = $pdo->prepare('UPDATE licenses SET expires_at = ? WHERE business_id = ?');
    $update->execute([hotelpro_fmt($expires), $businessId]);
    hotelpro_admin_audit($pdo, $adminId, 'license_cancelled', $businessId, ['businessId' => $businessId, 'expiresAt' => hotelpro_fmt($expires)]);
    $pdo->commit();
    return ['ok' => true];
}

function hotelpro_admin_layout(string $title, string $body, ?array $admin): string
{
    $nav = '';
    if ($admin) {
        $nav = '<nav><a href="admin.php?page=dashboard">Dashboard</a> <a href="admin.php?page=customers">Customers</a> <a href="admin.php?page=pins">PIN inventory</a>
            <form method="post" action="admin.php" style="display:inline"><input type="hidden" name="csrf" value="' . hotelpro_admin_e((string) ($admin['csrf'] ?? '')) . '"><input type="hidden" name="action" value="logout"><button type="submit">Logout</button></form></nav>';
    }
    return '<!DOCTYPE html><html lang="hi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>'
        . hotelpro_admin_e($title) . '</title><style>body{font-family:sans-serif;margin:24px;color:#17202a}table{border-collapse:collapse;width:100%}td,th{border:1px solid #d5d8dc;padding:6px;text-align:left;font-size:14px}form{margin:8px 0}input,button{padding:6px;margin:2px} .error{color:#b71c1c}</style></head><body><h1>Hotel Pro admin</h1>'
        . $nav . $body . '</body></html>';
}

function hotelpro_admin_headers(string $type): array
{
    return [
        'Content-Type' => $type,
        'X-Frame-Options' => 'DENY',
        'X-Content-Type-Options' => 'nosniff',
        'Cache-Control' => 'no-store',
        'Referrer-Policy' => 'no-referrer',
        'Content-Security-Policy' => "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'",
    ];
}

function hotelpro_admin_http(PDO $pdo, array $config, string $method, array $query, array $post, array $session): array
{
    if (empty($session['csrf']) || !preg_match('/^[a-f0-9]{64}$/', (string) $session['csrf'])) {
        $session['csrf'] = bin2hex(random_bytes(32));
    }
    $method = strtoupper($method);
    $notice = '';
    $status = 200;
    $regenerate = false;
    if ($method === 'POST' && !hash_equals((string) $session['csrf'], (string) ($post['csrf'] ?? ''))) {
        return [
            'status' => 400,
            'headers' => hotelpro_admin_headers('text/html; charset=utf-8'),
            'body' => hotelpro_admin_layout('Admin', '<p class="error">The form expired. Open the page again.</p>', null),
            'session' => $session,
            'regenerate' => false,
        ];
    }
    $action = (string) ($post['action'] ?? '');
    if ($method === 'POST' && $action === 'login') {
        $result = hotelpro_admin_login($pdo, (string) ($post['username'] ?? ''), (string) ($post['password'] ?? ''));
        if (!$result['ok']) {
            $status = $result['status'];
            $notice = (string) $result['error'];
        } else {
            $session = [
                'admin_id' => $result['admin']['id'],
                'expires_at' => hotelpro_fmt(hotelpro_now()->modify('+12 hours')),
                'csrf' => bin2hex(random_bytes(32)),
            ];
            hotelpro_admin_audit($pdo, $result['admin']['id'], 'admin_login', (string) $result['admin']['username'], []);
            $query['page'] = 'dashboard';
            $regenerate = true;
        }
    }
    $admin = hotelpro_admin_from_session($pdo, $session);
    if ($method === 'POST' && $action === 'logout' && $admin) {
        hotelpro_admin_audit($pdo, $admin['id'], 'admin_logout', $admin['username'], []);
        $session = ['csrf' => bin2hex(random_bytes(32))];
        $admin = null;
    }
    if (!$admin) {
        $body = '<p>यह पैनल केवल admin account के लिए है। होटल के customer account से नहीं खुलेगा।</p>'
            . ($notice !== '' ? '<p class="error">' . hotelpro_admin_e($notice) . '</p>' : '')
            . '<form method="post" action="admin.php"><input type="hidden" name="csrf" value="' . hotelpro_admin_e((string) $session['csrf']) . '"><input type="hidden" name="action" value="login">'
            . '<div><label>Username <input name="username" autocomplete="username" required></label></div>'
            . '<div><label>Password <input name="password" type="password" autocomplete="current-password" required></label></div>'
            . '<button type="submit">Login</button></form>';
        return [
            'status' => $status,
            'headers' => hotelpro_admin_headers('text/html; charset=utf-8'),
            'body' => hotelpro_admin_layout('Admin login', $body, null),
            'session' => $session,
            'regenerate' => false,
        ];
    }
    $admin['csrf'] = (string) $session['csrf'];
    if ($method === 'POST' && $action === 'assign') {
        $query['page'] = 'pins';
        $saved = hotelpro_admin_assign($pdo, $admin['id'], (int) ($post['serial'] ?? 0), (string) ($post['assigned_to'] ?? ''));
        $notice = $saved['ok'] ? 'Assignment saved. Redemption is still separate.' : (string) $saved['error'];
    } elseif ($method === 'POST' && $action === 'revoke') {
        $query['page'] = 'pins';
        $saved = hotelpro_admin_revoke($pdo, $admin['id'], (int) ($post['serial'] ?? 0));
        $notice = $saved['ok'] ? 'Unused PIN revoked.' : (string) $saved['error'];
    } elseif ($method === 'POST' && $action === 'cancel') {
        $query['page'] = 'customer';
        $query['id'] = (string) ($post['business_id'] ?? '');
        $saved = hotelpro_admin_cancel_license($pdo, $admin['id'], (string) ($post['business_id'] ?? ''), (string) ($post['confirmation'] ?? ''));
        $notice = $saved['ok'] ? 'License writes are blocked. Hotel data was not deleted.' : (string) $saved['error'];
    } elseif ($method === 'POST' && $action === 'generate') {
        $query['page'] = 'pins';
        if (($post['confirm'] ?? '') !== 'GENERATE') {
            $notice = 'Type GENERATE to export a new batch.';
        } else {
            $issued = hotelpro_issue_pins($pdo, $config, 100, $admin['id']);
            $headers = hotelpro_admin_headers('text/csv; charset=utf-8');
            $headers['Content-Disposition'] = 'attachment; filename="hotelpro-pins.csv"';
            return [
                'status' => 200,
                'headers' => $headers,
                'body' => hotelpro_pin_export_csv($issued['rows']),
                'session' => $session,
                'regenerate' => false,
            ];
        }
    }
    $page = (string) ($query['page'] ?? 'dashboard');
    $filter = trim((string) ($query['q'] ?? ''));
    if ($page === 'customers') {
        $rows = hotelpro_admin_customers($pdo, $config, $filter);
        $body = '<h2>Customers</h2><form method="get" action="admin.php"><input type="hidden" name="page" value="customers"><input name="q" value="' . hotelpro_admin_e($filter) . '" placeholder="नाम, मोबाइल, होटल, business ID, PIN serial"><button>Search</button></form>';
        $body .= $notice !== '' ? '<p>' . hotelpro_admin_e($notice) . '</p>' : '';
        $body .= '<table><tr><th>मालिक</th><th>मोबाइल</th><th>होटल</th><th>business ID</th><th>registration</th><th>status</th><th>expiry</th><th>last sync</th></tr>';
        foreach ($rows as $row) {
            $label = hotelpro_admin_license_label($row);
            $expiry = $label === 'trial' || $label === 'trial ended' ? (string) $row['trial_ends_at'] : (string) ($row['expires_at'] ?? '');
            $body .= '<tr><td>' . hotelpro_admin_e((string) $row['owner_name']) . '</td><td>' . hotelpro_admin_e((string) $row['phone_e164']) . '</td><td>' . hotelpro_admin_e((string) $row['hotel_name']) . '</td><td><a href="admin.php?page=customer&amp;id=' . hotelpro_admin_e((string) $row['business_id']) . '">' . hotelpro_admin_e((string) $row['business_id']) . '</a></td><td>' . hotelpro_admin_e((string) $row['registered_at']) . '</td><td>' . hotelpro_admin_e($label) . '</td><td>' . hotelpro_admin_e($expiry) . '</td><td>' . hotelpro_admin_e((string) ($row['last_sync'] ?? '')) . '</td></tr>';
        }
        $body .= '</table>';
    } elseif ($page === 'customer' && preg_match('/^biz_[a-f0-9]{24}$/', (string) ($query['id'] ?? '')) === 1) {
        $businessId = (string) $query['id'];
        $found = hotelpro_admin_customers($pdo, $config, $businessId);
        $history = hotelpro_admin_history($pdo, $businessId);
        $body = '<h2>Hotel history</h2>' . ($notice !== '' ? '<p>' . hotelpro_admin_e($notice) . '</p>' : '');
        $body .= '<p>' . hotelpro_admin_e($businessId) . '</p><h3>Activation and renewal</h3><table><tr><th>serial</th><th>masked PIN</th><th>user ID</th><th>business ID</th><th>activation time</th><th>expiry</th><th>assigned to</th><th>assigned at</th></tr>';
        foreach ($history['redemptions'] as $row) {
            $body .= '<tr><td>' . hotelpro_admin_e((string) $row['serial_no']) . '</td><td>****' . hotelpro_admin_e((string) $row['last4']) . '</td><td>' . hotelpro_admin_e((string) $row['user_id']) . '</td><td>' . hotelpro_admin_e((string) $row['business_id']) . '</td><td>' . hotelpro_admin_e((string) $row['activated_at']) . '</td><td>' . hotelpro_admin_e((string) $row['expires_at']) . '</td><td>' . hotelpro_admin_e((string) ($row['assigned_label'] ?? '')) . '</td><td>' . hotelpro_admin_e((string) ($row['assigned_at'] ?? '')) . '</td></tr>';
        }
        $body .= '</table><h3>Admin actions</h3><table><tr><th>time</th><th>action</th><th>detail</th></tr>';
        foreach ($history['audit'] as $row) {
            $body .= '<tr><td>' . hotelpro_admin_e((string) $row['created_at']) . '</td><td>' . hotelpro_admin_e((string) $row['action']) . '</td><td>' . hotelpro_admin_e((string) $row['detail']) . '</td></tr>';
        }
        $body .= '</table>';
        if ($found !== []) {
            $body .= '<h3>Cancel redeemed license</h3><p>यह होटल का डेटा delete नहीं करता। नया लिखना बंद होता है।</p><form method="post" action="admin.php"><input type="hidden" name="csrf" value="' . hotelpro_admin_e($admin['csrf']) . '"><input type="hidden" name="action" value="cancel"><input type="hidden" name="business_id" value="' . hotelpro_admin_e($businessId) . '"><input name="confirmation" placeholder="business ID दोबारा लिखें" required><button type="submit">Cancel license</button></form>';
        }
    } elseif ($page === 'pins') {
        $rows = hotelpro_admin_pins($pdo, $config, $filter);
        $body = '<h2>PIN inventory</h2><form method="get" action="admin.php"><input type="hidden" name="page" value="pins"><input name="q" value="' . hotelpro_admin_e($filter) . '" placeholder="serial, last 4, batch, assigned name, business ID"><button>Search</button></form>';
        $body .= $notice !== '' ? '<p>' . hotelpro_admin_e($notice) . '</p>' : '';
        $body .= '<form method="post" action="admin.php"><input type="hidden" name="csrf" value="' . hotelpro_admin_e($admin['csrf']) . '"><input type="hidden" name="action" value="generate"><input name="confirm" placeholder="GENERATE" required><button type="submit">100 PIN generate and export</button></form>';
        $body .= '<table><tr><th>batch</th><th>serial</th><th>masked PIN</th><th>status</th><th>assigned to</th><th>assigned at</th><th>redeemed business</th><th>redeemed at</th><th></th></tr>';
        foreach ($rows as $row) {
            $status = $row['status'] === 'issued' ? 'unused' : (string) $row['status'];
            $body .= '<tr><td>' . hotelpro_admin_e((string) $row['batch_id']) . '</td><td>' . hotelpro_admin_e((string) $row['serial_no']) . '</td><td>****' . hotelpro_admin_e((string) $row['last4']) . '</td><td>' . hotelpro_admin_e($status) . '</td><td>' . hotelpro_admin_e((string) ($row['assigned_label'] ?? '')) . '</td><td>' . hotelpro_admin_e((string) ($row['assigned_at'] ?? '')) . '</td><td>' . hotelpro_admin_e((string) ($row['business_id'] ?? '')) . '</td><td>' . hotelpro_admin_e((string) ($row['redeemed_at'] ?? '')) . '</td><td>';
            if ($row['status'] === 'issued') {
                $body .= '<form method="post" action="admin.php"><input type="hidden" name="csrf" value="' . hotelpro_admin_e($admin['csrf']) . '"><input type="hidden" name="action" value="assign"><input type="hidden" name="serial" value="' . hotelpro_admin_e((string) $row['serial_no']) . '"><input name="assigned_to" placeholder="Assigned to" required><button>Assign</button></form>';
                $body .= '<form method="post" action="admin.php"><input type="hidden" name="csrf" value="' . hotelpro_admin_e($admin['csrf']) . '"><input type="hidden" name="action" value="revoke"><input type="hidden" name="serial" value="' . hotelpro_admin_e((string) $row['serial_no']) . '"><button>Revoke unused</button></form>';
            }
            $body .= '</td></tr>';
        }
        $body .= '</table>';
    } else {
        $totals = hotelpro_admin_totals($pdo);
        $body = '<h2>Dashboard</h2>' . ($notice !== '' ? '<p>' . hotelpro_admin_e($notice) . '</p>' : '');
        $body .= '<ul><li>कुल होटल: ' . $totals['hotels'] . '</li><li>trial: ' . $totals['trial'] . '</li><li>active licenses: ' . $totals['active'] . '</li><li>expired licenses: ' . $totals['expired'] . '</li><li>unused PIN: ' . $totals['unused'] . '</li><li>redeemed PIN: ' . $totals['redeemed'] . '</li><li>revoked PIN: ' . $totals['revoked'] . '</li></ul>';
    }
    return [
        'status' => 200,
        'headers' => hotelpro_admin_headers('text/html; charset=utf-8'),
        'body' => hotelpro_admin_layout($page, $body, $admin),
        'session' => $session,
        'regenerate' => $regenerate,
    ];
}
