<?php
/**
 * Copy this file to config.php on the server, outside public_html if possible.
 * Do not commit config.php. Do not paste the real passwords into chat.
 */
return [
    'db' => [
        'host' => 'localhost',
        'name' => 'REPLACE_DATABASE_NAME',
        'user' => 'REPLACE_DATABASE_USER',
        'pass' => 'REPLACE_IN_SERVER_CONFIG_ONLY',
        'charset' => 'utf8mb4',
    ],
    'pin_hmac_secret' => 'REPLACE_WITH_A_LONG_RANDOM_SECRET',
    'token_pepper' => 'REPLACE_WITH_ANOTHER_LONG_RANDOM_SECRET',
    'backup_passphrase' => 'REPLACE_WITH_A_THIRD_LONG_RANDOM_SECRET',
    'require_https' => true,
    'storage_dir' => dirname(__DIR__) . '/storage',
    'access_ttl_seconds' => 900,
    'refresh_ttl_seconds' => 2592000,
    'photo_max_bytes' => 5242880,
];
