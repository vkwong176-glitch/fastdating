/* eslint-disable no-undef */
// FCM Web：必須放在 web/ 根目錄，與 lib/firebase_options.dart（Web）一致。
// 參考：https://firebase.google.com/docs/cloud-messaging/js/client

importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBYRWyMQmnLgTP7moRIRPxL2EObrxBo5cM',
  authDomain: 'fast-dating-vk.firebaseapp.com',
  projectId: 'fast-dating-vk',
  storageBucket: 'fast-dating-vk.firebasestorage.app',
  messagingSenderId: '780058794247',
  appId: '1:780058794247:web:deaca7455344856a6b0da2',
  measurementId: 'G-RWNCRS3EYV',
});

const messaging = firebase.messaging();
