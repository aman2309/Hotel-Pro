<?php
declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

$config = require (getenv('HOTELPRO_CONFIG') ?: dirname(__DIR__) . '/config/config.php');
$name = (string) ($config['db']['name'] ?? '');
$phrase = (string) ($config['backup_passphrase'] ?? '');
if ($name === '' || $name === 'a2ndhm2a_hotel' || $phrase === '') {
    fwrite(STDERR, "Backup is not configured.\n");
    exit(1);
}

$root = dirname(__DIR__);
$backupDir = $root . '/backups';
if (!is_dir($backupDir) && !mkdir($backupDir, 0700, true)) {
    fwrite(STDERR, "Backup directory is not available.\n");
    exit(1);
}

$stamp = gmdate('Ymd-His');
$sqlFile = $backupDir . '/db-' . $stamp . '.sql.enc';
$photoFile = $backupDir . '/photos-' . $stamp . '.tar.gz.enc';
$cnf = $backupDir . '/.client-' . getmypid() . '.cnf';
$db = $config['db'];
file_put_contents($cnf, "[client]\nhost=" . $db['host'] . "\nuser=" . $db['user'] . "\npassword=" . $db['pass'] . "\n");
chmod($cnf, 0600);

$dump = 'mysqldump --defaults-extra-file=' . escapeshellarg($cnf)
    . ' --single-transaction --skip-comments ' . escapeshellarg($name)
    . ' | openssl enc -aes-256-cbc -pbkdf2 -pass env:HOTELPRO_BACKUP_PASS -out ' . escapeshellarg($sqlFile);
$photos = 'tar -C ' . escapeshellarg($root) . ' -czf - storage/photos'
    . ' | openssl enc -aes-256-cbc -pbkdf2 -pass env:HOTELPRO_BACKUP_PASS -out ' . escapeshellarg($photoFile);
putenv('HOTELPRO_BACKUP_PASS=' . $phrase);
$okDump = 0;
$okPhotos = 0;
system($dump, $okDump);
system($photos, $okPhotos);
unlink($cnf);
putenv('HOTELPRO_BACKUP_PASS');

if ($okDump !== 0 || $okPhotos !== 0 || !is_file($sqlFile)) {
    fwrite(STDERR, "Backup failed.\n");
    exit(1);
}
chmod($sqlFile, 0600);
if (is_file($photoFile)) {
    chmod($photoFile, 0600);
}
fwrite(STDOUT, "Backup written outside the public folder.\n");
