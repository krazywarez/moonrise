-- APNs broadcast channels for launch Live Activities, one per launch and APNs environment.
-- A row with no launch is in the pool (created by scripts/channels.ts or the Worker).
-- net and status are the state last broadcast; ended_at is set once the activity is ended.
CREATE TABLE launch_channels (
  channel_id TEXT PRIMARY KEY,
  environment TEXT NOT NULL,
  launch_id TEXT,
  net TEXT,
  status TEXT,
  created_at TEXT NOT NULL,
  ended_at TEXT
);

CREATE UNIQUE INDEX launch_channels_launch ON launch_channels (launch_id, environment);
