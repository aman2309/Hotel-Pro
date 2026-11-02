-- MySQL 5.7.23 and PHP 8.3.
-- Identifier columns use ascii so indexes stay under InnoDB's 767-byte limit.
-- Names and JSON stay utf8mb4. No MySQL 8 collation or syntax.

CREATE TABLE users (
  id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  owner_name VARCHAR(120) NOT NULL,
  phone_e164 VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  email VARCHAR(190) NULL,
  password_hash VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  created_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY users_phone (phone_e164)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE businesses (
  id VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  name VARCHAR(160) NOT NULL,
  owner_user_id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  created_at DATETIME(6) NOT NULL,
  trial_started_at DATETIME(6) NOT NULL,
  trial_ends_at DATETIME(6) NOT NULL,
  default_rooms_created TINYINT(1) NOT NULL DEFAULT 0,
  next_revision BIGINT NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  CONSTRAINT businesses_owner FOREIGN KEY (owner_user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE business_members (
  business_id VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  user_id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  role VARCHAR(20) NOT NULL,
  created_at DATETIME(6) NOT NULL,
  PRIMARY KEY (business_id, user_id),
  UNIQUE KEY one_business_per_user (user_id),
  CONSTRAINT members_business FOREIGN KEY (business_id) REFERENCES businesses (id),
  CONSTRAINT members_user FOREIGN KEY (user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE hotel_records (
  business_id VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  entity VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  record_id VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  revision BIGINT NOT NULL,
  deleted TINYINT(1) NOT NULL DEFAULT 0,
  payload JSON NOT NULL,
  bill_number VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NULL,
  updated_at DATETIME(6) NOT NULL,
  PRIMARY KEY (business_id, entity, record_id),
  KEY records_cursor (business_id, revision),
  KEY records_bill (business_id, bill_number),
  CONSTRAINT records_business FOREIGN KEY (business_id) REFERENCES businesses (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE idempotency_keys (
  business_id VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  idempotency_key VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  response_json JSON NOT NULL,
  created_at DATETIME(6) NOT NULL,
  PRIMARY KEY (business_id, idempotency_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE licenses (
  business_id VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  trial_started_at DATETIME(6) NOT NULL,
  trial_ends_at DATETIME(6) NOT NULL,
  activated TINYINT(1) NOT NULL DEFAULT 0,
  expires_at DATETIME(6) NULL,
  last_redemption_id CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
  plan VARCHAR(20) NULL,
  PRIMARY KEY (business_id),
  CONSTRAINT licenses_business FOREIGN KEY (business_id) REFERENCES businesses (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE activation_codes (
  code_hmac CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  serial_no INT NOT NULL,
  status VARCHAR(20) NOT NULL,
  plan VARCHAR(20) NOT NULL,
  business_id VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NULL,
  redeemed_at DATETIME(6) NULL,
  PRIMARY KEY (code_hmac),
  UNIQUE KEY activation_serial (serial_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE pin_attempts (
  user_id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  window_start DATETIME(6) NOT NULL,
  fail_count INT NOT NULL DEFAULT 0,
  locked_until DATETIME(6) NULL,
  PRIMARY KEY (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE login_attempts (
  phone_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  window_start DATETIME(6) NOT NULL,
  fail_count INT NOT NULL DEFAULT 0,
  locked_until DATETIME(6) NULL,
  PRIMARY KEY (phone_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE access_tokens (
  token_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  user_id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  expires_at DATETIME(6) NOT NULL,
  revoked TINYINT(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (token_hash),
  KEY access_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE refresh_tokens (
  token_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  user_id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  family_id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  expires_at DATETIME(6) NOT NULL,
  revoked TINYINT(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (token_hash),
  KEY refresh_user (user_id),
  KEY refresh_family (family_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE photos (
  id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  business_id VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  guest_id VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  slot VARCHAR(10) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  sha256 CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  byte_size INT NOT NULL,
  storage_name VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  created_at DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY photo_slot (business_id, guest_id, slot, sha256),
  CONSTRAINT photos_business FOREIGN KEY (business_id) REFERENCES businesses (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
