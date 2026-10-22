-- Push-to-start tokens for launch Live Activities and the rockets and providers each install follows (JSON arrays).
-- Kept apart from devices: the token is ActivityKit's, not the APNs device token.
CREATE TABLE launch_starts (
  token TEXT PRIMARY KEY,
  environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
  rockets TEXT NOT NULL,
  providers TEXT NOT NULL,
  last_seen TEXT NOT NULL
);
