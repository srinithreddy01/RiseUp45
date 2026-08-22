# Backend

This boundary is ready for a future synced account service. The current mobile
app is local-first and does not send task data to a server.

- `api/`: task and profile HTTP endpoints
- `authentication/`: identity, sessions, and access control
- `database/`: server-side persistence and migrations

Keep alarm scheduling on the device even after sync is added: the backend is
not a replacement for Android AlarmManager or iOS local notifications.