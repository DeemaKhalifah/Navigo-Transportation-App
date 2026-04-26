const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

async function getUserTokens(userId) {
  const userRef = db.collection('users').doc(userId);
  const [userSnap, tokenSnap] = await Promise.all([
    userRef.get(),
    userRef.collection('fcmTokens').get(),
  ]);

  const tokens = new Set();
  if (userSnap.exists) {
    const data = userSnap.data() || {};
    const primary = (data.fcm || '').toString().trim();
    if (primary) tokens.add(primary);
  }

  for (const doc of tokenSnap.docs) {
    const token = ((doc.data() || {}).token || doc.id || '').toString().trim();
    if (token) tokens.add(token);
  }

  return Array.from(tokens);
}

exports.sendNotificationOnCreate = functions.firestore
  .document('notifications/{notificationId}')
  .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    const notificationId = context.params.notificationId;
    const userId = (data.userId || '').toString().trim();
    if (!userId) return null;

    const tokens = await getUserTokens(userId);
    if (!tokens.length) return null;

    const title = (data.title || 'Navigo').toString();
    const body = (data.message || data.body || '').toString();
    const type = (data.type || '').toString();
    const tripId = (data.tripId || '').toString();
    const routeId = (data.routeId || '').toString();

    const message = {
      tokens,
      notification: {
        title,
        body,
      },
      data: {
        type,
        tripId,
        routeId,
        notificationId: notificationId.toString(),
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'navigo_default',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
          },
        },
      },
    };

    const result = await admin.messaging().sendEachForMulticast(message);
    const batch = db.batch();
    result.responses.forEach((response, index) => {
      if (response.success) return;
      const code = response.error && response.error.code;
      if (
        code === 'messaging/invalid-registration-token' ||
        code === 'messaging/registration-token-not-registered'
      ) {
        const token = tokens[index];
        if (!token) return;
        batch.delete(
          db.collection('users').doc(userId).collection('fcmTokens').doc(token),
        );
      }
    });
    await batch.commit();
    return null;
  });

