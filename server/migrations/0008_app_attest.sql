-- App Attest: one-time challenges, and keys attested by the app (not linked to devices or push tokens).
CREATE TABLE attest_challenges (
  challenge TEXT PRIMARY KEY,
  expires_at TEXT NOT NULL
);

CREATE TABLE app_keys (
  key_id TEXT PRIMARY KEY,
  spki TEXT NOT NULL,
  environment TEXT NOT NULL,
  counter INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  last_used TEXT NOT NULL
);
