-- 0023_notification_actor.sql
-- Notifications now record who caused the event, separately from who is meant
-- to read it (`user_id`). A sale a staff member records is business-wide news
-- for the owner, but it still has to say whose sale it was.

ALTER TABLE notifications
  ADD COLUMN actor_user_id TEXT REFERENCES users(id) ON DELETE SET NULL;

CREATE INDEX idx_notifications_actor
  ON notifications(actor_user_id, created_at DESC);
