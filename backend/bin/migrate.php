<?php
declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

require dirname(__DIR__) . '/src/app.php';

$config = require (getenv('HOTELPRO_CONFIG') ?: dirname(__DIR__) . '/config/config.php');
$name = (string) ($config['db']['name'] ?? '');
if ($name === '' || $name === 'a2ndhm2a_hotel' || !str_ends_with($name, 'hotelpro')) {
    fwrite(STDERR, "Refusing to migrate this database.\n");
    exit(1);
}

$pdo = hotelpro_pdo($config);
$existing = (int) $pdo->query('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE()')->fetchColumn();
if ($existing !== 0) {
    fwrite(STDERR, "Refusing to migrate because the database is not empty.\n");
    exit(1);
}

$files = glob(dirname(__DIR__) . '/migrations/*.sql') ?: [];
sort($files);
$pdo->beginTransaction();
try {
    foreach ($files as $file) {
        $sql = (string) file_get_contents($file);
        foreach (preg_split('/;\s*\n/', $sql) as $statement) {
            if (trim($statement) !== '') {
                $pdo->exec($statement);
            }
        }
    }
    $pdo->commit();
} catch (Throwable) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    fwrite(STDERR, "Migration failed.\n");
    exit(1);
}

$count = (int) $pdo->query('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE()')->fetchColumn();
fwrite(STDOUT, "Migration applied. Tables: {$count}.\n");
