<?php
declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

foreach (['pdo_mysql', 'fileinfo', 'openssl'] as $extension) {
    echo $extension . '=' . (extension_loaded($extension) ? 'yes' : 'no') . "\n";
}
echo 'php=' . PHP_VERSION . "\n";
