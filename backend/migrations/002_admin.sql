-- Admin accounts, PIN assignment, and redemption history.
-- MySQL 5.7.23. No MySQL 8 collation or syntax.
-- Plaintext PINs are not stored. last4 is the only PIN fragment kept for the panel.

ALTER TABLE activation_codes
  ADD COLUMN batch_id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NULL AFTER serial_no,
  ADD COLUMN last4 CHAR(4) CHARACTER SET ascii COLLATE ascii_bin NULL AFTER batch_id,
  ADD COLUMN assigned_label VARCHAR(160) NULL AFTER business_id,
  ADD COLUMN assigned_at DATETIME(6) NULL AFTER assigned_label,
  ADD COLUMN assigned_by CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NULL AFTER assigned_at,
  ADD COLUMN revoked_at DATETIME(6) NULL AFTER redeemed_at,
  ADD KEY activation_batch (batch_id),
  ADD KEY activation_status (status);

CREATE TABLE admins (
  id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  username VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  password_hash VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  created_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY admins_username (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE admin_login_attempts (
  username_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  window_start DATETIME(6) NOT NULL,
  fail_count INT NOT NULL DEFAULT 0,
  locked_until DATETIME(6) NULL,
  PRIMARY KEY (username_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE audit_log (
  id BIGINT NOT NULL AUTO_INCREMENT,
  admin_id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NULL,
  action VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  subject VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  detail JSON NOT NULL,
  created_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  KEY audit_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE pin_redemptions (
  id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  code_hmac CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  serial_no INT NOT NULL,
  user_id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  business_id VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  activated_at DATETIME(6) NOT NULL,
  expires_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY redemption_once (code_hmac),
  KEY redemption_business (business_id),
  CONSTRAINT redemption_code FOREIGN KEY (code_hmac) REFERENCES activation_codes (code_hmac),
  CONSTRAINT redemption_user FOREIGN KEY (user_id) REFERENCES users (id),
  CONSTRAINT redemption_business FOREIGN KEY (business_id) REFERENCES businesses (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
