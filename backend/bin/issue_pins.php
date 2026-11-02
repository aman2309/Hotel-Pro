<?php
declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

require dirname(__DIR__) . '/src/app.php';

$out = null;
foreach (array_slice($argv, 1) as $arg) {
    if (str_starts_with($arg, '--out=')) {
        $out = substr($arg, 6);
    }
}
if ($out === null || $out === '' || str_contains($out, "\0") || str_contains($out, '/public/') || str_contains($out, 'public_html')) {
    fwrite(STDERR, "Pass --out=/private/path/pins.csv outside the public web folder.\n");
    exit(1);
}

$config = require (getenv('HOTELPRO_CONFIG') ?: dirname(__DIR__) . '/config/config.php');
$pdo = hotelpro_pdo($config);
try {
    $issued = hotelpro_issue_pins($pdo, $config, 100);
    $csv = hotelpro_pin_export_csv($issued['rows']);
} catch (Throwable) {
    fwrite(STDERR, "PIN issuance failed.\n");
    exit(1);
}
$dir = dirname($out);
if (!is_dir($dir) && !mkdir($dir, 0700, true)) {
    fwrite(STDERR, "Could not write the private export\n");
    exit(1);
}
if (file_put_contents($out, $csv) === false) {
    fwrite(STDERR, "Could not write the private export\n");
    exit(1);
}
chmod($out, 0600);
fwrite(STDOUT, "Issued 100 annual PINs. Plaintext exists only in the private export.\n");
