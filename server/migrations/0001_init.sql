-- Devices registered for pushes. No location: the app sends a 5-degree
-- geomagnetic latitude band (signed, south negative) and its UTC offset.
CREATE TABLE devices (
  token TEXT PRIMARY KEY,
  environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
  band INTEGER NOT NULL,
  utc_offset_minutes INTEGER NOT NULL,
  aurora INTEGER NOT NULL DEFAULT 1,
  last_seen TEXT NOT NULL
);

CREATE INDEX devices_band ON devices (band) WHERE aurora = 1;

-- One alert per kind, band and event key (e.g. aurora per band per storm window).
CREATE TABLE alerts_sent (
  kind TEXT NOT NULL,
  band INTEGER NOT NULL,
  event TEXT NOT NULL,
  sent_at TEXT NOT NULL,
  PRIMARY KEY (kind, band, event)
);

-- Latest result per upstream feed.
CREATE TABLE feed_snapshots (
  feed TEXT PRIMARY KEY,
  fetched_at TEXT NOT NULL,
  ok INTEGER NOT NULL,
  body TEXT
);
