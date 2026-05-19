/* وازن — Service Worker لإشعارات لوحة الإدارة */
importScripts('https://www.gstatic.com/firebasejs/10.12.4/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.4/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyD9y9FED7L-s0unONweN-5LhmwEdipXYUo',
  authDomain: 'wazenfapp.firebaseapp.com',
  projectId: 'wazenfapp',
  storageBucket: 'wazenfapp.appspot.com',
  messagingSenderId: '209409669834',
  appId: '1:209409669834:web:9e33eba07509ee28a29233'
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const data = payload && payload.data ? payload.data : {};
  const notification = payload && payload.notification ? payload.notification : {};
  const title = notification.title || data.title || 'تنبيه من وازن';
  const body = notification.body || data.body || 'لديك تنبيه جديد في لوحة وازن.';
  const url = data.url || data.deeplink || '/support/';

  self.registration.showNotification(title, {
    body,
    icon: '/wazen_logo.png',
    badge: '/wazen_logo.png',
    tag: data.sourceId || data.type || 'wazen-admin-notification',
    renotify: true,
    requireInteraction: data.type === 'staff_call' || data.type === 'support_ticket_new',
    data: {url}
  });
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const rawUrl = event.notification && event.notification.data ? event.notification.data.url : '/support/';
  const targetUrl = rawUrl && rawUrl.startsWith('http') ? rawUrl : new URL(rawUrl || '/support/', self.location.origin).href;

  event.waitUntil((async () => {
    const allClients = await clients.matchAll({type: 'window', includeUncontrolled: true});
    for (const client of allClients) {
      if ('focus' in client && client.url && client.url.startsWith(self.location.origin)) {
        await client.focus();
        if ('navigate' in client) {
          return client.navigate(targetUrl);
        }
        return;
      }
    }
    if (clients.openWindow) {
      return clients.openWindow(targetUrl);
    }
  })());
});
