-- Idempotent reset: drop dependents first via CASCADE.
DROP TABLE IF EXISTS invites CASCADE;
DROP TABLE IF EXISTS friend_requests CASCADE;
DROP TABLE IF EXISTS sessions CASCADE;
DROP TABLE IF EXISTS summary_overrides CASCADE;
DROP TABLE IF EXISTS gestures CASCADE;
DROP TABLE IF EXISTS nudges CASCADE;
DROP TABLE IF EXISTS signals CASCADE;
DROP TABLE IF EXISTS emails CASCADE;
DROP TABLE IF EXISTS events CASCADE;
DROP TABLE IF EXISTS connections CASCADE;
DROP TABLE IF EXISTS friendships CASCADE;
DROP TABLE IF EXISTS users CASCADE;

CREATE TABLE users (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  home_location TEXT NOT NULL DEFAULT '',
  preferences JSONB NOT NULL DEFAULT '{}'::jsonb,
  surprise_opt_in BOOLEAN NOT NULL DEFAULT false,
  paused BOOLEAN NOT NULL DEFAULT false
);

CREATE TABLE sessions (
  token TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE friendships (
  user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  friend_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  tier TEXT NOT NULL CHECK (tier IN ('friend', 'close', 'closest')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, friend_id),
  CHECK (user_id <> friend_id)
);

-- A friendship exists only after the recipient accepts; each side picks its own circle.
CREATE TABLE friend_requests (
  id TEXT PRIMARY KEY,
  from_user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  to_user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  from_tier TEXT NOT NULL CHECK (from_tier IN ('friend', 'close', 'closest')),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  responded_at TIMESTAMPTZ,
  CHECK (from_user_id <> to_user_id)
);

CREATE UNIQUE INDEX friend_requests_one_pending
  ON friend_requests (from_user_id, to_user_id) WHERE status = 'pending';

-- Invite links sent by text or email; opening one becomes a request from the inviter.
CREATE TABLE invites (
  code TEXT PRIMARY KEY,
  from_user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  from_tier TEXT NOT NULL CHECK (from_tier IN ('friend', 'close', 'closest')),
  channel TEXT NOT NULL CHECK (channel IN ('sms', 'email', 'link')),
  contact TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  redeemed_by TEXT REFERENCES users (id) ON DELETE SET NULL,
  redeemed_at TIMESTAMPTZ
);

CREATE TABLE connections (
  user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  provider TEXT NOT NULL,
  access_token TEXT,
  refresh_token TEXT,
  scopes TEXT,
  PRIMARY KEY (user_id, provider)
);

-- "start" / "end" are quoted: END is reserved in SQL.
CREATE TABLE events (
  id SERIAL PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  "start" TIMESTAMPTZ NOT NULL,
  "end" TIMESTAMPTZ NOT NULL,
  location TEXT,
  source TEXT NOT NULL CHECK (source IN ('google', 'ics')),
  CHECK ("end" > "start")
);

CREATE INDEX events_user_start_idx ON events (user_id, "start");

-- Temporary inbox rows; deleted after twin signal extraction.
CREATE TABLE emails (
  id SERIAL PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  from_addr TEXT NOT NULL,
  subject TEXT NOT NULL DEFAULT '',
  snippet TEXT NOT NULL DEFAULT '',
  date TIMESTAMPTZ NOT NULL
);

CREATE INDEX emails_user_date_idx ON emails (user_id, date DESC);

CREATE TABLE signals (
  id SERIAL PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  support_level TEXT NOT NULL,
  stressors JSONB NOT NULL DEFAULT '[]'::jsonb,
  busy_hours INT NOT NULL DEFAULT 0,
  likely_location TEXT,
  summary_for_closest TEXT NOT NULL DEFAULT '',
  summary_for_close TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX signals_user_created_idx ON signals (user_id, created_at DESC);

CREATE TABLE nudges (
  id TEXT PRIMARY KEY,
  from_user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  to_friend_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  message TEXT NOT NULL,
  context_level TEXT NOT NULL CHECK (context_level IN ('closest', 'close')),
  status TEXT NOT NULL CHECK (status IN ('sent', 'seen', 'acted')),
  -- Muse's starter surprise note; the friend can edit it before sending.
  draft_note TEXT,
  -- Why the twin nudged, for the sender's privacy log.
  reason TEXT,
  -- When and where the friend's twin found they can show up.
  moment TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The person's own wording for what each tier hears; survives twin refreshes.
CREATE TABLE summary_overrides (
  user_id TEXT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
  summary_for_closest TEXT NOT NULL,
  summary_for_close TEXT NOT NULL
);

CREATE INDEX nudges_to_friend_idx ON nudges (to_friend_id, created_at DESC);
CREATE INDEX nudges_from_user_idx ON nudges (from_user_id, created_at DESC);

CREATE TABLE gestures (
  id TEXT PRIMARY KEY,
  nudge_id TEXT NOT NULL REFERENCES nudges (id) ON DELETE CASCADE,
  from_friend_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  place_name TEXT,
  place_address TEXT,
  note TEXT NOT NULL DEFAULT '',
  delivered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- How the person helped said it landed ('helped' or 'space'); their twin reads it next time.
  reaction TEXT,
  reacted_at TIMESTAMPTZ
);

CREATE INDEX gestures_nudge_idx ON gestures (nudge_id);
CREATE INDEX gestures_from_friend_idx ON gestures (from_friend_id);
