<?php
declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

require dirname(__DIR__) . '/src/app.php';
require dirname(__DIR__) . '/src/admin.php';

$username = null;
$out = null;
foreach (array_slice($argv, 1) as $arg) {
    if (str_starts_with($arg, '--username=')) {
        $username = substr($arg, 11);
    }
    if (str_starts_with($arg, '--out=')) {
        $out = substr($arg, 6);
    }
}
if ($username === null || $out === null || $out === '' || str_contains($out, "\0") || str_contains($out, '/public/') || str_contains($out, 'public_html')) {
    fwrite(STDERR, "Pass --username=NAME --out=/private/path/admin-password.txt outside the public web folder.\n");
    exit(1);
}

$config = require (getenv('HOTELPRO_CONFIG') ?: dirname(__DIR__) . '/config/config.php');
$pdo = hotelpro_pdo($config);
$password = bin2hex(random_bytes(18));
try {
    $id = hotelpro_admin_create($pdo, $username, $password);
} catch (Throwable) {
    fwrite(STDERR, "Admin account was not created.\n");
    exit(1);
}
$dir = dirname($out);
if (!is_dir($dir) && !mkdir($dir, 0700, true)) {
    $pdo->prepare('DELETE FROM admins WHERE id = ?')->execute([$id]);
    fwrite(STDERR, "Could not write the private password file\n");
    exit(1);
}
$written = "username: {$username}\npassword: {$password}\n";
if (file_put_contents($out, $written) === false) {
    $pdo->prepare('DELETE FROM admins WHERE id = ?')->execute([$id]);
    fwrite(STDERR, "Could not write the private password file\n");
    exit(1);
}
chmod($out, 0600);
fwrite(STDOUT, "Admin account created. The password is only in the private file you named.\n");
