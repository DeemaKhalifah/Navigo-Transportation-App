const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();

function toRad(x) {
  return (x * Math.PI) / 180;
}

function distanceMeters(lat1, lon1, lat2, lon2) {
  const R = 6371000; // meters
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) *
      Math.cos(toRad(lat2)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

async function getUserTokens(uid) {
  const snap = await db.collection('users').doc(uid).collection('fcmTokens').get();
  return snap.docs.map((d) => (d.data().token || d.id)).filter(Boolean);
}

async function createInAppNotification(uid, payload) {
  await db.collection('users').doc(uid).collection('notifications').add({
    title: payload.title || '',
    body: payload.body || '',
    from: payload.from || '',
    type: payload.type || '',
    tripId: payload.tripId || null,
    requestId: payload.requestId || null,
    isRead: false,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function sendPushToUser(uid, payload) {
  const tokens = await getUserTokens(uid);
  if (!tokens.length) return;

  // Always write in-app notification too.
  await createInAppNotification(uid, payload);

  const message = {
    tokens,
    notification: {
      title: payload.title || 'Navigo',
      body: payload.body || '',
    },
    data: {
      type: (payload.type || '').toString(),
      tripId: (payload.tripId || '').toString(),
      requestId: (payload.requestId || '').toString(),
    },
  };

  const res = await admin.messaging().sendEachForMulticast(message);

  // Cleanup invalid tokens.
  const batch = db.batch();
  res.responses.forEach((r, idx) => {
    if (r.success) return;
    const code = r.error && r.error.code;
    if (
      code === 'messaging/registration-token-not-registered' ||
      code === 'messaging/invalid-registration-token'
    ) {
      const token = tokens[idx];
      const ref = db.collection('users').doc(uid).collection('fcmTokens').doc(token);
      batch.delete(ref);
    }
  });
  await batch.commit();
}

// 1) When driver accepts/declines a trip request, notify passenger.
exports.onTripDriverRequestUpdate = functions.firestore
  .document('tripDriverRequests/{requestId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};

    const beforeStatus = (before.status || '').toString();
    const afterStatus = (after.status || '').toString();
    if (beforeStatus === afterStatus) return;

    const passengerId = (after.passengerId || '').toString().trim();
    const driverId = (after.driverId || '').toString().trim();
    if (!passengerId || !driverId) return;

    const requestId = context.params.requestId;

    if (afterStatus === 'accepted') {
      await sendPushToUser(passengerId, {
        title: 'Trip request accepted',
        body: 'Your driver accepted your trip request.',
        type: 'trip_request_accepted',
        requestId,
      });

      // Optional: "nearby" rule (<500m) based on driver vs passenger pickup coords.
      const driverSnap = await db.collection('drivers').doc(driverId).get();
      const d = driverSnap.exists ? driverSnap.data() : null;
      const dLat = d && (d.latitude ?? (d.location && d.location.lat));
      const dLng = d && (d.longitude ?? (d.location && d.location.lng));

      const passengerSnap = await db.collection('passengers').doc(passengerId).get();
      const p = passengerSnap.exists ? passengerSnap.data() : null;
      const pLat = p && (p.latitude ?? (p.location && p.location.lat));
      const pLng = p && (p.longitude ?? (p.location && p.location.lng));

      if (typeof dLat === 'number' && typeof dLng === 'number' && typeof pLat === 'number' && typeof pLng === 'number') {
        const meters = distanceMeters(dLat, dLng, pLat, pLng);
        if (meters <= 500) {
          await sendPushToUser(passengerId, {
            title: 'Driver nearby',
            body: 'Your driver is within 500 meters of your pickup location.',
            type: 'driver_nearby',
            requestId,
          });
        }
      }
      return;
    }

    if (afterStatus === 'declined') {
      await sendPushToUser(passengerId, {
        title: 'Trip request declined',
        body: 'Your driver declined your trip request.',
        type: 'trip_request_declined',
        requestId,
      });
      return;
    }
  });

// 2) When a trip slot status changes (started/cancelled) notify passengers in that slot.
exports.onRouteScheduleSlotStatusChange = functions.firestore
  .document('route/{routeId}')
  .onUpdate(async (change) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};

    const beforeSlots = Array.isArray(before.scheduleSlots) ? before.scheduleSlots : [];
    const afterSlots = Array.isArray(after.scheduleSlots) ? after.scheduleSlots : [];

    // Build a map slotId -> status for before.
    const beforeStatusMap = new Map();
    for (const s of beforeSlots) {
      if (!s || typeof s !== 'object') continue;
      const id = (s.slotId || '').toString().trim();
      if (!id) continue;
      beforeStatusMap.set(id, (s.status || '').toString());
    }

    // Find changed statuses in after.
    const tasks = [];
    for (const s of afterSlots) {
      if (!s || typeof s !== 'object') continue;
      const slotId = (s.slotId || '').toString().trim();
      if (!slotId) continue;

      const prev = (beforeStatusMap.get(slotId) || '').toString();
      const next = (s.status || '').toString();
      if (!next || prev === next) continue;

      const passengers = Array.isArray(s.passengersIds) ? s.passengersIds : [];
      const passengerIds = passengers.map((x) => (x || '').toString().trim()).filter(Boolean);
      if (!passengerIds.length) continue;

      if (next === 'ongoing') {
        for (const pid of passengerIds) {
          tasks.push(
            sendPushToUser(pid, {
              title: 'Trip started',
              body: 'Your trip has started.',
              type: 'trip_started',
              tripId: slotId,
            })
          );
        }
      } else if (next === 'cancelled') {
        for (const pid of passengerIds) {
          tasks.push(
            sendPushToUser(pid, {
              title: 'Trip cancelled',
              body: 'Your trip was cancelled by the driver.',
              type: 'trip_cancelled',
              tripId: slotId,
            })
          );
        }
      }
    }

    await Promise.all(tasks);
  });

// 3) Send a push notification to a TOPIC (role-based).
// Usage example (HTTP POST):
//   curl -X POST https://<region>-<project>.cloudfunctions.net/sendToTopic \
//     -H "Content-Type: application/json" \
//     -d "{\"topic\":\"role_driver\",\"title\":\"Hello\",\"body\":\"New job\",\"data\":{\"type\":\"driver_job\"}}"
exports.sendToTopic = functions.https.onRequest(async (req, res) => {
  try {
    if (req.method !== 'POST') {
      res.status(405).send('Use POST');
      return;
    }

    const topic = ((req.body && req.body.topic) || '').toString().trim();
    const title = ((req.body && req.body.title) || 'Navigo').toString();
    const body = ((req.body && req.body.body) || '').toString();
    const data = (req.body && req.body.data) || {};

    if (!topic) {
      res.status(400).json({ ok: false, error: 'topic is required' });
      return;
    }

    // Send BOTH notification + data so Android/iOS show it in background automatically,
    // while `data` is used for click navigation in the app.
    const message = {
      topic,
      notification: { title, body },
      data: Object.fromEntries(
        Object.entries(data).map(([k, v]) => [k, (v ?? '').toString()])
      ),
      android: {
        priority: 'high',
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
          },
        },
      },
    };

    const id = await admin.messaging().send(message);
    res.json({ ok: true, id });
  } catch (e) {
    console.error(e);
    res.status(500).json({ ok: false, error: e && e.message ? e.message : String(e) });
  }
});

