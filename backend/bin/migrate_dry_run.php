<?php
declare(strict_types=1);

$checkpoint = null;
$reportPath = null;
$apply = false;
foreach (array_slice($argv, 1) as $arg) {
    if (str_starts_with($arg, '--checkpoint=')) {
        $checkpoint = substr($arg, 13);
    } elseif (str_starts_with($arg, '--report=')) {
        $reportPath = substr($arg, 9);
    } elseif ($arg === '--apply') {
        $apply = true;
    }
}
if ($checkpoint === null || !is_file($checkpoint)) {
    fwrite(STDERR, "Pass --checkpoint=/path/documents.json\n");
    exit(1);
}
if ($apply) {
    fwrite(STDERR, "Apply is refused. Map the verified owner explicitly in a later reviewed import. This run stays a dry-run.\n");
    $apply = false;
}
$docs = json_decode((string) file_get_contents($checkpoint), true);
if (!is_array($docs)) {
    fwrite(STDERR, "Checkpoint is not a document list\n");
    exit(1);
}
$byBusiness = [];
foreach ($docs as $doc) {
    $name = (string) ($doc['name'] ?? '');
    if (!preg_match('#/documents/businesses/([^/]+)/([^/]+)/#', $name, $match)) {
        continue;
    }
    $businessId = $match[1];
    $collection = $match[2];
    $bucket =& $byBusiness[$businessId];
    $bucket['counts'][$collection] = ($bucket['counts'][$collection] ?? 0) + 1;
    $bucket['documents'] = ($bucket['documents'] ?? 0) + 1;
    $fields = $doc['fields'] ?? [];
    $isDeleted = (($fields['deleted']['booleanValue'] ?? false) === true);
    $key = $isDeleted ? 'deleted' : 'live';
    $bucket[$key] = ($bucket[$key] ?? 0) + 1;
    if ($collection === 'payments') {
        $bucket['paymentAmountTotal'] = ($bucket['paymentAmountTotal'] ?? 0) + (int) ($fields['amount']['integerValue'] ?? 0);
    }
    if ($collection === 'bills') {
        $bucket['billTotal'] = ($bucket['billTotal'] ?? 0) + (int) ($fields['totalBill']['integerValue'] ?? 0);
    }
    unset($bucket);
}
foreach ($byBusiness as &$bucket) {
    ksort($bucket['counts']);
    $bucket['deleted'] ??= 0;
    $bucket['live'] ??= 0;
    $bucket['paymentAmountTotal'] ??= 0;
    $bucket['billTotal'] ??= 0;
}
unset($bucket);
$report = [
    'mode' => 'dry-run',
    'applied' => false,
    'firebaseRead' => false,
    'recovered' => false,
    'checkpointSha256' => hash_file('sha256', $checkpoint),
    'documents' => count($docs),
    'businesses' => count($byBusiness),
    'byBusiness' => $byBusiness,
    'note' => 'Counts only. No database write and no claim that production data was restored.',
];
$json = json_encode($report, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n";
if ($reportPath !== null) {
    file_put_contents($reportPath, $json);
    chmod($reportPath, 0600);
}
fwrite(STDOUT, $json);
