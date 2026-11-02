<?php
declare(strict_types=1);

require dirname(__DIR__) . '/src/app.php';
require dirname(__DIR__) . '/src/admin.php';

if (PHP_SAPI === 'cli') {
    fwrite(STDERR, "Admin panel is a web page.\n");
    exit(1);
}

$configPath = getenv('HOTELPRO_CONFIG') ?: dirname(__DIR__) . '/config/config.php';
if (!is_file($configPath)) {
    http_response_code(500);
    header('Content-Type: text/plain; charset=utf-8');
    echo 'Server configuration is missing';
    exit;
}
$config = require $configPath;
$https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
    || (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https');
if (!empty($config['require_https']) && !$https) {
    http_response_code(400);
    header('Content-Type: text/plain; charset=utf-8');
    echo 'HTTPS required';
    exit;
}

session_name('hp_admin');
session_set_cookie_params([
    'lifetime' => 0,
    'path' => '/',
    'secure' => $https,
    'httponly' => true,
    'samesite' => 'Strict',
]);
session_start();
$pdo = hotelpro_pdo($config);
$result = hotelpro_admin_http(
    $pdo,
    $config,
    (string) ($_SERVER['REQUEST_METHOD'] ?? 'GET'),
    $_GET,
    $_POST,
    $_SESSION
);
$_SESSION = $result['session'];
if (!empty($result['regenerate'])) {
    session_regenerate_id(true);
}
http_response_code((int) $result['status']);
foreach ($result['headers'] as $name => $value) {
    header($name . ': ' . $value);
}
echo $result['body'];
