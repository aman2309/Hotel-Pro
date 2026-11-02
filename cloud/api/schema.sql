-- Optional: run once in cPanel → phpMyAdmin
-- (PHP also auto-creates this table on first request)

CREATE TABLE IF NOT EXISTS silver_cloud_store (
  id TINYINT UNSIGNED NOT NULL PRIMARY KEY DEFAULT 1,
  revision INT UNSIGNED NOT NULL DEFAULT 0,
  payload LONGTEXT NOT NULL,
  updated_at DATETIME NOT NULL,
  device_id VARCHAR(64) NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO silver_cloud_store (id, revision, payload, updated_at, device_id)
VALUES (1, 0, '{}', UTC_TIMESTAMP(), NULL)
ON DUPLICATE KEY UPDATE id = id;
