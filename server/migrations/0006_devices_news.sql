-- The news cron selects opted-in devices by UTC offset.
CREATE INDEX devices_news ON devices (news, utc_offset_minutes);
