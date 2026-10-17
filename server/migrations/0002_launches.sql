-- Upcoming launches, normalized from Launch Library 2.
CREATE TABLE launches (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  net TEXT NOT NULL,
  window_start TEXT,
  window_end TEXT,
  status TEXT NOT NULL,
  status_name TEXT NOT NULL,
  provider TEXT NOT NULL,
  rocket TEXT NOT NULL,
  mission TEXT,
  mission_type TEXT,
  mission_description TEXT,
  orbit TEXT,
  pad TEXT NOT NULL,
  location TEXT NOT NULL,
  pad_latitude REAL,
  pad_longitude REAL,
  last_updated TEXT NOT NULL
);

CREATE INDEX launches_net ON launches (net);
