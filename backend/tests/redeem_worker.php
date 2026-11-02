<?php
declare(strict_types=1);
require dirname(__DIR__) . '/src/app.php';
$config = require getenv('HOTELPRO_CONFIG');
$input = json_decode(stream_get_contents(STDIN), true);
$result = hotelpro_handle($config, 'POST', '/v1/license/redeem', $input['body'], $input['headers']);
fwrite(STDOUT, json_encode(['status' => $result['status'], 'activated' => $result['body']['activated'] ?? false, 'idempotent' => $result['body']['idempotent'] ?? false, 'expiresAt' => $result['body']['expiresAt'] ?? null]));
