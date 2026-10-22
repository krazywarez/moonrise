-- APNs broadcast channels for geomagnetic storm Live Activities, one per storm and APNs environment.
-- active_at is the last time the storm rule held; sent is the StormState last broadcast, as JSON.
CREATE TABLE storm_channels (
  channel_id TEXT PRIMARY KEY,
  environment TEXT NOT NULL,
  started_at TEXT NOT NULL,
  active_at TEXT NOT NULL,
  sent TEXT,
  sent_at TEXT,
  ended_at TEXT
);
