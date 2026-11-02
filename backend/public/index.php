<?php
declare(strict_types=1);

require dirname(__DIR__) . '/src/app.php';

$configPath = getenv('HOTELPRO_CONFIG') ?: dirname(__DIR__) . '/config/config.php';
if (!is_file($configPath)) {
    http_response_code(500);
    header('Content-Type: application/json');
    echo json_encode(['error' => 'Server configuration is missing']);
    exit;
}
$config = require $configPath;
$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
$prefix = rtrim(dirname($_SERVER['SCRIPT_NAME'] ?? ''), '/');
if ($prefix !== '' && str_starts_with($path, $prefix)) {
    $path = substr($path, strlen($prefix)) ?: '/';
}
$raw = file_get_contents('php://input') ?: '';
$length = (int) ($_SERVER['CONTENT_LENGTH'] ?? 0);
if ($raw === '' && $length > 1024 && strtoupper((string) ($_SERVER['REQUEST_METHOD'] ?? '')) === 'POST') {
    http_response_code(413);
    header('Content-Type: application/json');
    echo json_encode(['error' => 'The change was too large. It is still saved on this phone.']);
    exit;
}
$body = json_decode($raw, true);
if (!is_array($body)) {
    $body = $_POST;
}
$result = hotelpro_handle($config, $_SERVER['REQUEST_METHOD'] ?? 'GET', $path, $body, hotelpro_request_headers());
http_response_code($result['status']);
if (($result['file'] ?? null) !== null) {
    header('Content-Type: image/jpeg');
    header('X-Content-Type-Options: nosniff');
    header('Cache-Control: private, no-store');
    readfile($result['file']);
    exit;
}
header('Content-Type: application/json');
echo json_encode($result['body'], JSON_UNESCAPED_UNICODE);
