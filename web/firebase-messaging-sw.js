importScripts("https://www.gstatic.com/firebasejs/9.10.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/9.10.0/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyDbj1g-gkr6HsFmLfGrfyj8EbTwDdNPxQ0",
  authDomain: "feed-609dd.firebaseapp.com",
  projectId: "feed-609dd",
  storageBucket: "feed-609dd.firebasestorage.app",
  messagingSenderId: "536909553761",
  appId: "1:536909553761:web:275f9f88fabd505b4e8a20",
  measurementId: "G-KV46ETPZ2P"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);
});
