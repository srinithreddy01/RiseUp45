# Database layer

The current app is local-first and stores its workspace through
`shared_preferences` in the app shell. Move that persistence into this layer
before enabling cloud sync; the task schema is documented in `ARCHITECTURE.md`.