<?php
/**
 * Copy this file to config.php on cPanel and fill real values.
 *
 * Same MySQL DB as Parkland OK hai — table alag hai (silver_cloud_store).
 * api_key MUST match the app default / Hotel Settings cloud key.
 */
return [
  'db_host' => 'localhost',
  'db_name' => 'CHANGE_ME_DB',
  'db_user' => 'CHANGE_ME_USER',
  'db_pass' => 'CHANGE_ME_PASSWORD',
  // Prefer same api_key as existing Parkland config.php so one file works for both.
  'api_key' => '80a2d3cdf38216577c3bf7734c05331ab8906cbd7dcfe5ba',
];
