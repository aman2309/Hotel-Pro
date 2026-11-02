<?php
/**
 * Hotel Silver Cloud — shared JSON store (Mac + Android + Windows).
 *
 * GET  /api/silver_cloud_store.php
 *   → { ok, revision, updatedAt, deviceId, data }
 *
 * PUT  /api/silver_cloud_store.php
 *   Body JSON: { revision, data, deviceId? }
 *   If client revision != server revision → 409 conflict
 *   Else saves and bumps revision
 *
 * Auth: header X-Api-Key: <api_key>
 *
 * IMPORTANT: Uses table silver_cloud_store (NOT parkland_store).
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, X-Api-Key');
header('Access-Control-Allow-Methods: GET, PUT, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
  http_response_code(204);
  exit;
}

$configFile = __DIR__ . '/config.php';
if (!is_file($configFile)) {
  http_response_code(500);
  echo json_encode(['ok' => false, 'error' => 'config_missing']);
  exit;
}

$config = require $configFile;
$apiKey = (string)($config['api_key'] ?? '');
$provided = $_SERVER['HTTP_X_API_KEY'] ?? '';
if ($apiKey === '' || !hash_equals($apiKey, $provided)) {
  http_response_code(401);
  echo json_encode(['ok' => false, 'error' => 'unauthorized']);
  exit;
}

try {
  $pdo = new PDO(
    'mysql:host=' . $config['db_host'] . ';dbname=' . $config['db_name'] . ';charset=utf8mb4',
    $config['db_user'],
    $config['db_pass'],
    [
      PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
      PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]
  );
} catch (Throwable $e) {
  http_response_code(500);
  echo json_encode([
    'ok' => false,
    'error' => 'db_connect_failed',
    'detail' => $e->getMessage(),
  ]);
  exit;
}

ensureSchema($pdo);

$method = $_SERVER['REQUEST_METHOD'];
if ($method === 'GET') {
  $row = fetchStore($pdo);
  echo json_encode([
    'ok' => true,
    'revision' => (int)$row['revision'],
    'updatedAt' => $row['updated_at'],
    'deviceId' => $row['device_id'],
    'data' => json_decode($row['payload'], true) ?? new stdClass(),
  ]);
  exit;
}

if ($method === 'PUT') {
  $raw = file_get_contents('php://input');
  $body = json_decode($raw, true);
  if (!is_array($body) || !array_key_exists('data', $body) || !array_key_exists('revision', $body)) {
    http_response_code(400);
    echo json_encode(['ok' => false, 'error' => 'invalid_body']);
    exit;
  }

  $clientRev = (int)$body['revision'];
  $deviceId = isset($body['deviceId']) ? substr((string)$body['deviceId'], 0, 64) : null;
  $payload = json_encode($body['data'], JSON_UNESCAPED_UNICODE);
  if ($payload === false) {
    http_response_code(400);
    echo json_encode(['ok' => false, 'error' => 'invalid_data']);
    exit;
  }

  $pdo->beginTransaction();
  try {
    $row = fetchStoreForUpdate($pdo);
    $serverRev = (int)$row['revision'];
    if ($clientRev !== $serverRev) {
      $pdo->rollBack();
      http_response_code(409);
      echo json_encode([
        'ok' => false,
        'error' => 'conflict',
        'revision' => $serverRev,
        'updatedAt' => $row['updated_at'],
        'deviceId' => $row['device_id'],
        'data' => json_decode($row['payload'], true) ?? new stdClass(),
      ]);
      exit;
    }

    $newRev = $serverRev + 1;
    $stmt = $pdo->prepare(
      'UPDATE silver_cloud_store SET revision = ?, payload = ?, updated_at = UTC_TIMESTAMP(), device_id = ? WHERE id = 1'
    );
    $stmt->execute([$newRev, $payload, $deviceId]);
    $pdo->commit();

    $fresh = fetchStore($pdo);
    echo json_encode([
      'ok' => true,
      'revision' => (int)$fresh['revision'],
      'updatedAt' => $fresh['updated_at'],
      'deviceId' => $fresh['device_id'],
    ]);
  } catch (Throwable $e) {
    if ($pdo->inTransaction()) {
      $pdo->rollBack();
    }
    http_response_code(500);
    echo json_encode(['ok' => false, 'error' => 'save_failed', 'detail' => $e->getMessage()]);
  }
  exit;
}

http_response_code(405);
echo json_encode(['ok' => false, 'error' => 'method_not_allowed']);

function ensureSchema(PDO $pdo): void {
  $pdo->exec(
    'CREATE TABLE IF NOT EXISTS silver_cloud_store (
      id TINYINT UNSIGNED NOT NULL PRIMARY KEY DEFAULT 1,
      revision INT UNSIGNED NOT NULL DEFAULT 0,
      payload LONGTEXT NOT NULL,
      updated_at DATETIME NOT NULL,
      device_id VARCHAR(64) NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
  );
  $count = (int)$pdo->query('SELECT COUNT(*) FROM silver_cloud_store WHERE id = 1')->fetchColumn();
  if ($count === 0) {
    $stmt = $pdo->prepare(
      'INSERT INTO silver_cloud_store (id, revision, payload, updated_at, device_id) VALUES (1, 0, ?, UTC_TIMESTAMP(), NULL)'
    );
    $stmt->execute(['{}']);
  }
}

function fetchStore(PDO $pdo): array {
  $stmt = $pdo->query('SELECT revision, payload, updated_at, device_id FROM silver_cloud_store WHERE id = 1 LIMIT 1');
  $row = $stmt->fetch();
  if (!$row) {
    return [
      'revision' => 0,
      'payload' => '{}',
      'updated_at' => gmdate('Y-m-d H:i:s'),
      'device_id' => null,
    ];
  }
  return $row;
}

function fetchStoreForUpdate(PDO $pdo): array {
  $stmt = $pdo->query('SELECT revision, payload, updated_at, device_id FROM silver_cloud_store WHERE id = 1 LIMIT 1 FOR UPDATE');
  $row = $stmt->fetch();
  if (!$row) {
    $ins = $pdo->prepare(
      'INSERT INTO silver_cloud_store (id, revision, payload, updated_at, device_id) VALUES (1, 0, ?, UTC_TIMESTAMP(), NULL)'
    );
    $ins->execute(['{}']);
    return fetchStoreForUpdate($pdo);
  }
  return $row;
}
