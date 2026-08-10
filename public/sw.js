self.addEventListener('install', () => self.skipWaiting())

// This worker is used for notification actions.  Do not cache the Vite app
// shell here: cache-first HTML and module requests can keep serving an older
// build whose asset filenames no longer exist, leaving the page blank.
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.map(key => caches.delete(key))))
      .then(() => self.clients.claim())
  )
})

self.addEventListener('notificationclick', event => {
  event.notification.close()

  event.waitUntil(
    (async () => {
      const data = event.notification.data || {}
      const action = event.action || 'open'

      const clients = await self.clients.matchAll({
        type: 'window',
        includeUncontrolled: true
      })

      let client = clients[0]

      if (!client) {
        client = await self.clients.openWindow('/')
      }

      if (client) {
        await client.focus()

        client.postMessage({
          type: 'reminder-action',
          action,
          taskId: data.taskId
        })
      }
    })()
  )
})
