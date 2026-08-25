importScripts('firebase-config.js');
// Keep this version aligned with firebase_core_web's supported SDK version.
importScripts('https://www.gstatic.com/firebasejs/12.18.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.18.0/firebase-messaging-compat.js');

if (typeof self.WAMP_APP_FIREBASE_OPTIONS !== 'object') {
  throw new Error('WampApp Firebase configuration is unavailable.');
}

firebase.initializeApp(self.WAMP_APP_FIREBASE_OPTIONS);
const messaging = firebase.messaging();

messaging.onBackgroundMessage((message) => {
  const cursor = message?.data?.cursor;
  if (typeof cursor !== 'string' || !/^[1-9][0-9]{0,19}$/.test(cursor)) {
    return;
  }
  return self.clients
    .matchAll({includeUncontrolled: true, type: 'window'})
    .then((clients) => {
      for (const client of clients) {
        client.postMessage({type: 'wamp_app_mailbox_wakeup', cursor});
      }
    });
});
