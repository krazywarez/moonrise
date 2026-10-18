-- Daily news digest opt-in.
ALTER TABLE devices ADD COLUMN news INTEGER NOT NULL DEFAULT 0;
