const functions = require('firebase-functions');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();
const googleMapsApiKeySecret = defineSecret('GOOGLE_MAPS_API_KEY');

function googleMapsApiKey() {
  return (process.env.GOOGLE_MAPS_API_KEY || '').toString().trim();
}

function setCors(res) {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
}

function numberFromBody(body, key) {
  const value = Number(body && body[key]);
  return Number.isFinite(value) ? value : null;
}

function parseDurationSeconds(raw) {
  if (typeof raw === 'number') return raw;
  if (typeof raw === 'string') {
    const clean = raw.endsWith('s') ? raw.slice(0, -1) : raw;
    const parsed = Number(clean);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function estimateMeters(startLat, startLng, endLat, endLng) {
  const earthRadius = 6371000;
  const toRadians = (degrees) => degrees * Math.PI / 180;
  const dLat = toRadians(endLat - startLat);
  const dLng = toRadians(endLng - startLng);
  const lat1 = toRadians(startLat);
  const lat2 = toRadians(endLat);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1) * Math.cos(lat2) *
      Math.sin(dLng / 2) * Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return Math.round(earthRadius * c);
}

function formatEta(minutes) {
  if (minutes < 60) return `${minutes} min`;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return rest === 0 ? `${hours}h` : `${hours}h ${rest}m`;
}

function formatDistance(meters) {
  if (meters < 1000) return `${meters} m`;
  return `${(meters / 1000).toFixed(1)} km`;
}

exports.fetchRoutePolyline = functions
  .runWith({ secrets: [googleMapsApiKeySecret] })
  .https.onRequest(async (req, res) => {
  setCors(res);
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }
  if (req.method !== 'POST') {
    res.status(405).json({ success: false, error: 'Method not allowed' });
    return;
  }

  const startLatitude = numberFromBody(req.body, 'startLatitude');
  const startLongitude = numberFromBody(req.body, 'startLongitude');
  const endLatitude = numberFromBody(req.body, 'endLatitude');
  const endLongitude = numberFromBody(req.body, 'endLongitude');
  if (
    startLatitude == null ||
    startLongitude == null ||
    endLatitude == null ||
    endLongitude == null
  ) {
    res.status(400).json({
      success: false,
      error: 'Missing start/end coordinates',
    });
    return;
  }

  const key = googleMapsApiKey();
  if (!key) {
    res.status(500).json({
      success: false,
      error: 'Google Maps API key is not configured.',
      details:
        'Set it with: firebase functions:secrets:set GOOGLE_MAPS_API_KEY',
    });
    return;
  }

  const url = new URL('https://maps.googleapis.com/maps/api/directions/json');
  url.searchParams.set('origin', `${startLatitude},${startLongitude}`);
  url.searchParams.set('destination', `${endLatitude},${endLongitude}`);
  url.searchParams.set('mode', 'driving');
  url.searchParams.set('departure_time', 'now');
  url.searchParams.set('key', key);

  console.log('[fetchRoutePolyline] startLocation', {
    lat: startLatitude,
    lng: startLongitude,
  });
  console.log('[fetchRoutePolyline] endLocation', {
    lat: endLatitude,
    lng: endLongitude,
  });
  console.log('[fetchRoutePolyline] provider', 'google_directions');

  try {
    const response = await fetch(url);
    const raw = await response.text();
    let data;
    try {
      data = JSON.parse(raw);
    } catch (e) {
      console.error('[fetchRoutePolyline] invalid JSON response', raw);
      res.status(502).json({
        success: false,
        error: 'Could not generate route polyline',
        details: 'Invalid Google Directions response',
      });
      return;
    }

    if (!response.ok || data.status !== 'OK') {
      console.error('[fetchRoutePolyline] Google Directions response', data);
      res.status(502).json({
        success: false,
        error: 'Could not generate route polyline',
        details: data.error_message || data.status || `HTTP ${response.status}`,
      });
      return;
    }

    const route = Array.isArray(data.routes) ? data.routes[0] : null;
    const encoded =
      route &&
      route.overview_polyline &&
      typeof route.overview_polyline.points === 'string'
        ? route.overview_polyline.points.trim()
        : '';
    console.log('[fetchRoutePolyline] raw API response polyline field', encoded);

    if (!encoded) {
      res.status(502).json({
        success: false,
        error: 'Could not generate route polyline',
        details: 'Missing routes[0].overview_polyline.points',
      });
      return;
    }

    const leg = route.legs && route.legs[0] ? route.legs[0] : {};
    const distanceMeters =
      leg.distance && typeof leg.distance.value === 'number'
        ? leg.distance.value
        : estimateMeters(startLatitude, startLongitude, endLatitude, endLongitude);
    const seconds =
      (leg.duration_in_traffic && leg.duration_in_traffic.value) ||
      (leg.duration && leg.duration.value) ||
      parseDurationSeconds(route.duration) ||
      Math.max(60, Math.round(distanceMeters / 1000 / 35 * 3600));
    const etaMinutes = Math.max(1, Math.ceil(seconds / 60));

    res.json({
      success: true,
      data: {
        polyline: encoded,
        distanceMeters,
        distanceText: leg.distance && leg.distance.text
          ? leg.distance.text
          : formatDistance(distanceMeters),
        etaMinutes,
        etaText: formatEta(etaMinutes),
        provider: 'google_directions_function',
      },
    });
  } catch (error) {
    console.error('[fetchRoutePolyline] error', error);
    res.status(500).json({
      success: false,
      error: 'Could not generate route polyline',
      details: error.message || String(error),
    });
  }
});

/**
 * Best-effort extraction of FCM tokens from a document, without assuming a
 * single canonical field name. This is intentionally permissive to support
 * legacy fields or multiple app roles (e.g. user/passenger/driver).
 */
function extractTokensFromDocData(docData) {
  const data = docData || {};

  // Common single-token fields used across many projects.
  const singleCandidates = [
    data.fcm,
    data.fcmToken,
    data.fcm_token,
    data.token,
    data.deviceToken,
    data.device_token,
  ];

  // Common multi-token fields.
  const listCandidates = [data.fcmTokens, data.tokens, data.deviceTokens];

  const out = [];

  for (const v of singleCandidates) {
    const token = (v || '').toString().trim();
    if (token) out.push(token);
  }

  for (const v of listCandidates) {
    if (!Array.isArray(v)) continue;
    for (const item of v) {
      const token = (item || '').toString().trim();
      if (token) out.push(token);
    }
  }

  return out;
}

/**
 * Collect FCM tokens for a user from multiple related documents and token
 * subcollections, while preserving references to token-docs for cleanup when
 * Firebase reports invalid/expired tokens.
 *
 * - De-dupes tokens (same device token will only be sent once)
 * - Supports tokens stored as fields on related docs (not deletable individually)
 * - Supports tokens stored as docs in a token subcollection (deletable on failure)
 */
async function collectUserFcmTokens(userId) {
  const userDocRef = db.collection('users').doc(userId);
  const passengerDocRef = db.collection('passengers').doc(userId);
  const driverDocRef = db.collection('drivers').doc(userId);

  const tokenCollections = [
    userDocRef.collection('fcmTokens'),
    passengerDocRef.collection('fcmTokens'),
    driverDocRef.collection('fcmTokens'),
  ];

  const [userSnap, passengerSnap, driverSnap, ...tokenSnaps] =
    await Promise.all([
      userDocRef.get(),
      passengerDocRef.get(),
      driverDocRef.get(),
      ...tokenCollections.map((c) => c.get()),
    ]);

  // token => Set<DocumentReference> (token docs we can delete if invalid)
  const tokenToRefs = new Map();

  const addToken = (token, deletableRef) => {
    const t = (token || '').toString().trim();
    if (!t) return;
    if (!tokenToRefs.has(t)) tokenToRefs.set(t, new Set());
    if (deletableRef) tokenToRefs.get(t).add(deletableRef);
  };

  // Tokens coming from user/passenger/driver docs (fields/arrays).
  if (userSnap.exists) {
    for (const token of extractTokensFromDocData(userSnap.data())) addToken(token);
  }
  if (passengerSnap.exists) {
    for (const token of extractTokensFromDocData(passengerSnap.data())) addToken(token);
  }
  if (driverSnap.exists) {
    for (const token of extractTokensFromDocData(driverSnap.data())) addToken(token);
  }

  // Tokens coming from token subcollections.
  for (const snap of tokenSnaps) {
    for (const doc of snap.docs) {
      const docData = doc.data() || {};
      const token = (docData.token || doc.id || '').toString().trim();
      if (!token) continue;
      addToken(token, doc.ref);
    }
  }

  return {
    tokens: Array.from(tokenToRefs.keys()),
    tokenToRefs,
  };
}

function chunkArray(arr, chunkSize) {
  const out = [];
  for (let i = 0; i < arr.length; i += chunkSize) {
    out.push(arr.slice(i, i + chunkSize));
  }
  return out;
}

const notificationTextByKey = {
  driverApprovalNotificationTitle: {
    en: 'Driver request accepted',
    ar: 'تم قبول طلب السائق',
  },
  driverApprovalNotificationMessage: {
    en: 'Your driver account has been approved. You can now start accepting trips.',
    ar: 'تمت الموافقة على حساب السائق الخاص بك. يمكنك الآن قبول الرحلات.',
  },
  waitingTripCreatedTitle: {
    en: 'New trip created',
    ar: 'تم إنشاء رحلة جديدة',
  },
  waitingTripCreatedMessage: {
    en: 'A new trip was created for your requested date and time.',
    ar: 'تم إنشاء رحلة جديدة في التاريخ والوقت المطلوبين.',
  },
  waitingTripManagerTitle: {
    en: 'Waiting list trip request',
    ar: 'طلب رحلة من قائمة الانتظار',
  },
  waitingTripManagerMessage: {
    en: 'Passengers are waiting for a trip at the requested date and time.',
    ar: 'يوجد ركاب بانتظار رحلة في التاريخ والوقت المطلوبين.',
  },
};

function localizedNotificationText(key, languageCode, fallback) {
  const safeKey = (key || '').toString().trim();
  const safeLanguage = (languageCode || 'en').toString().trim().toLowerCase();
  if (!safeKey || !notificationTextByKey[safeKey]) {
    return (fallback || '').toString();
  }

  return (
    notificationTextByKey[safeKey][safeLanguage] ||
    notificationTextByKey[safeKey].en ||
    fallback ||
    ''
  ).toString();
}

/**
 * Reusable helper to create a notification document.
 *
 * Other Cloud Functions should call this helper (or mirror its shape) to create
 * a doc in the existing `notifications` collection, and rely on the existing
 * onCreate trigger below to actually send the push notification.
 */
async function createNotificationDoc(input) {
  const data = input || {};
  const userId = (data.userId || '').toString().trim();
  if (!userId) {
    throw new Error('createNotificationDoc: userId is required');
  }

  const doc = {
    notificationId: '',
    userId,
    title: (data.title || 'Navigo').toString(),
    // Keep compatibility with clients that read either `message` or `body`.
    message: (data.message || data.body || '').toString(),
    body: (data.body || data.message || '').toString(),
    type: (data.type || '').toString(),
    tripId: data.tripId == null ? '' : data.tripId.toString(),
    routeId: data.routeId == null ? '' : data.routeId.toString(),
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    isRead: false,
    // Allow callers to attach arbitrary structured metadata without changing
    // push logic. This does not affect the existing trigger unless used there.
    meta: data.meta && typeof data.meta === 'object' ? data.meta : undefined,
  };

  // Optional: allow additional fields to be written to the notification doc
  // (e.g. requestId / driverId / status) without changing the push trigger.
  // This keeps future functions flexible while still relying on the same
  // `notifications` onCreate trigger for delivery.
  if (data.extra && typeof data.extra === 'object' && !Array.isArray(data.extra)) {
    Object.keys(data.extra).forEach((k) => {
      if (k in doc) return; // do not override core keys
      doc[k] = data.extra[k];
    });
  }

  // Remove undefined fields to avoid writing them to Firestore.
  Object.keys(doc).forEach((k) => doc[k] === undefined && delete doc[k]);

  const ref = db.collection('notifications').doc();
  doc.notificationId = ref.id;
  await ref.set(doc);
  return ref;
}

exports.sendNotificationOnCreate = functions.firestore
  .document('notifications/{notificationId}')
  .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    const notificationId = context.params.notificationId;
    const userId = (data.userId || '').toString().trim();
    if (!userId) return null;

    const { tokens, tokenToRefs } = await collectUserFcmTokens(userId);
    if (!tokens.length) return null;

    const userSnap = await db.collection('users').doc(userId).get();
    const languageCode = userSnap.exists
      ? (userSnap.data().language || 'en').toString()
      : 'en';

    const title = localizedNotificationText(
      data.titleKey,
      languageCode,
      data.title || 'Navigo',
    );
    const body = localizedNotificationText(
      data.messageKey,
      languageCode,
      data.message || data.body || '',
    );
    const type = (data.type || '').toString();
    const tripId = (data.tripId || '').toString();
    const routeId = (data.routeId || '').toString();

    // sendEachForMulticast supports up to 500 tokens per call.
    const tokenChunks = chunkArray(tokens, 500);
    const refsToDelete = new Set();

    for (const tokenChunk of tokenChunks) {
      const message = {
        tokens: tokenChunk,
        notification: {
          title,
          body,
        },
        data: {
          // FCM data payload values must be strings.
          type: type || '',
          tripId: tripId || '',
          routeId: routeId || '',
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

      // Keep the existing invalid/expired token handling, but delete the actual
      // token docs we discovered (supports different subcollection locations).
      result.responses.forEach((response, index) => {
        if (response.success) return;
        const code = response.error && response.error.code;
        if (
          code === 'messaging/invalid-registration-token' ||
          code === 'messaging/registration-token-not-registered'
        ) {
          const token = tokenChunk[index];
          if (!token) return;

          const refs = tokenToRefs.get(token);
          if (refs) {
            for (const ref of refs) refsToDelete.add(ref);
          }

          // Backward-compat: if older code used token as docId under users/{id}/fcmTokens,
          // try deleting that doc too (safe even if it doesn't exist).
          refsToDelete.add(
            db.collection('users').doc(userId).collection('fcmTokens').doc(token),
          );
        }
      });
    }

    if (refsToDelete.size) {
      const batch = db.batch();
      for (const ref of refsToDelete) batch.delete(ref);
      await batch.commit();
    }
    return null;
  });

// Export helper for reuse by other Cloud Functions files (or tests).
exports.createNotificationDoc = createNotificationDoc;

async function authenticatedUidFromRequest(req) {
  const header = (req.get('Authorization') || '').toString();
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Authentication is required.',
    );
  }

  const decoded = await admin.auth().verifyIdToken(match[1]);
  return decoded.uid;
}

async function resolveRouteIdForTrip(routeId, tripId) {
  const safeRouteId = (routeId || '').toString().trim();
  const safeTripId = (tripId || '').toString().trim();

  if (safeRouteId) return safeRouteId;
  if (!safeTripId) return '';

  const snap = await db.collection('route').get();
  for (const doc of snap.docs) {
    const slots = doc.data().scheduleSlots;
    if (!Array.isArray(slots)) continue;
    if (
      slots.some(
        (slot) =>
          slot &&
          (slot.slotId || '').toString().trim() === safeTripId,
      )
    ) {
      return doc.id;
    }
  }

  return '';
}

/**
 * HTTPS endpoint: start a driver trip quickly and atomically.
 *
 * The app can call this with a Firebase ID token. If this function has not
 * been deployed yet, the app falls back to its existing direct Firestore write.
 */
exports.startDriverTrip = functions.https.onRequest(async (req, res) => {
  setCors(res);
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }
  if (req.method !== 'POST') {
    res.status(405).json({ success: false, error: 'Method not allowed' });
    return;
  }

  try {
    const uid = await authenticatedUidFromRequest(req);
    const body = req.body || {};
    const tripId = (body.tripId || '').toString().trim();
    const driverId = (body.driverId || uid).toString().trim();
    const routeId = await resolveRouteIdForTrip(body.routeId, tripId);
    const startLatitude =
      typeof body.startLatitude === 'number' ? body.startLatitude : null;
    const startLongitude =
      typeof body.startLongitude === 'number' ? body.startLongitude : null;

    if (!tripId) {
      res.status(400).json({ success: false, error: 'Trip ID is missing.' });
      return;
    }
    if (!driverId || driverId !== uid) {
      res.status(403).json({ success: false, error: 'Driver mismatch.' });
      return;
    }
    if (!routeId) {
      res.status(404).json({ success: false, error: 'Trip route not found.' });
      return;
    }

    const routeRef = db.collection('route').doc(routeId);
    const driverRef = db.collection('drivers').doc(driverId);

    await db.runTransaction(async (tx) => {
      const routeSnap = await tx.get(routeRef);
      if (!routeSnap.exists) {
        throw new functions.https.HttpsError('not-found', 'Route not found.');
      }

      const routeData = routeSnap.data() || {};
      const rawSlots = routeData.scheduleSlots;
      if (!Array.isArray(rawSlots)) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'scheduleSlots is missing in this route.',
        );
      }

      const slots = rawSlots.map((slot) =>
        slot && typeof slot === 'object' && !Array.isArray(slot)
          ? { ...slot }
          : {},
      );
      const index = slots.findIndex(
        (slot) => (slot.slotId || '').toString().trim() === tripId,
      );

      if (index === -1) {
        throw new functions.https.HttpsError('not-found', 'Trip slot not found.');
      }

      const slotDriverId = (slots[index].driverId || driverId).toString().trim();
      if (slotDriverId && slotDriverId !== driverId) {
        throw new functions.https.HttpsError(
          'permission-denied',
          'This trip is assigned to another driver.',
        );
      }

      slots[index] = {
        ...slots[index],
        slotId: tripId,
        routeId,
        driverId,
        status: 'onTrip',
        startedAt: admin.firestore.Timestamp.now(),
      };

      const driverUpdate = {
        status: 'onTrip',
        isOnline: true,
        currentRouteId: routeId,
        currentTripId: tripId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      if (startLatitude != null && startLongitude != null) {
        driverUpdate.latitude = startLatitude;
        driverUpdate.longitude = startLongitude;
        driverUpdate.location = { lat: startLatitude, lng: startLongitude };
        driverUpdate.lastLocationUpdate =
          admin.firestore.FieldValue.serverTimestamp();
      }

      tx.update(routeRef, {
        scheduleSlots: slots,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      tx.set(driverRef, driverUpdate, { merge: true });
    });

    res.json({ success: true, routeId, tripId, driverId });
  } catch (error) {
    const code = error && error.code;
    const message = error && error.message ? error.message : String(error);
    console.error('[startDriverTrip] error', error);

    if (code === 'unauthenticated') {
      res.status(401).json({ success: false, error: message });
    } else if (code === 'permission-denied') {
      res.status(403).json({ success: false, error: message });
    } else if (code === 'not-found') {
      res.status(404).json({ success: false, error: message });
    } else if (code === 'failed-precondition') {
      res.status(412).json({ success: false, error: message });
    } else {
      res.status(500).json({ success: false, error: message });
    }
  }
});

/**
 * Firestore trigger: notify passenger when a trip request status changes.
 *
 * Watches `tripDriverRequests/{requestId}` and creates a document in the existing
 * `notifications` collection (push is delivered by `sendNotificationOnCreate`).
 */
exports.notifyPassengerOnTripRequestStatusChange = functions.firestore
  .document('tripDriverRequests/{requestId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};

    const prevStatus = (before.status || '').toString().trim().toLowerCase();
    const nextStatus = (after.status || '').toString().trim().toLowerCase();
    if (!nextStatus || nextStatus === prevStatus) return null;

    const requestId = context.params.requestId;

    // Determine passenger to notify. (App model uses `passengerId`.)
    const passengerId = (after.passengerId || after.userId || '').toString().trim();
    if (!passengerId) return null;

    const routeId = (after.routeId || '').toString().trim();
    const driverId = (after.driverId || '').toString().trim();
    const tripId = (after.tripId || '').toString().trim();

    const statusTemplates = {
      assigned: {
        title: 'Driver Assigned',
        message: 'A driver has been assigned to your trip request.',
        type: 'trip_request_assigned',
      },
      accepted: {
        title: 'Request Accepted',
        message: 'Your trip request was accepted by the driver.',
        type: 'trip_request_accepted',
      },
      declined: {
        title: 'Request Declined',
        message: 'Your trip request was declined by the driver.',
        type: 'trip_request_declined',
      },
      arrived: {
        title: 'Driver Arrived',
        message: 'Your driver has arrived at the pickup location.',
        type: 'trip_request_arrived',
      },
      started: {
        title: 'Trip Started',
        message: 'Your trip has started.',
        type: 'trip_request_started',
      },
      completed: {
        title: 'Trip Completed',
        message: 'Your trip has been completed.',
        type: 'trip_request_completed',
      },
      cancelled: {
        title: 'Trip Cancelled',
        message: 'Your trip request was cancelled.',
        type: 'trip_request_cancelled',
      },
      'no-driver-available': {
        title: 'No Driver Available',
        message: 'No driver is available for this request right now.',
        type: 'trip_request_no_driver_available',
      },
      no_driver_available: {
        title: 'No Driver Available',
        message: 'No driver is available for this request right now.',
        type: 'trip_request_no_driver_available',
      },
      nodriveravailable: {
        title: 'No Driver Available',
        message: 'No driver is available for this request right now.',
        type: 'trip_request_no_driver_available',
      },
    };

    const tpl =
      statusTemplates[nextStatus] || {
        title: 'Trip Request Updated',
        message: `Your trip request status changed to "${nextStatus}".`,
        type: 'trip_request_status_changed',
      };

    await createNotificationDoc({
      userId: passengerId,
      title: tpl.title,
      type: tpl.type,
      message: tpl.message,
      tripId: tripId || '',
      routeId: routeId || '',
      extra: {
        requestId,
        status: nextStatus,
        driverId: driverId || '',
        // Keep a copy of routeId/tripId for easier querying in-app.
        routeId: routeId || '',
        tripId: tripId || '',
      },
      meta: {
        requestId,
        status: nextStatus,
        driverId: driverId || '',
        routeId: routeId || '',
        tripId: tripId || '',
      },
    });

    return null;
  });

/**
 * Firestore trigger: create a trip record when a trip request is accepted.
 *
 * Adds a `trips/{tripId}` history/reporting record (does NOT replace the existing
 * schedule/slot-based flow). This trigger is idempotent: it uses the trip request
 * id as the trip document id to avoid duplicates.
 */
exports.createTripRecordOnTripRequestAccepted = functions.firestore
  .document('tripDriverRequests/{requestId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};

    const prevStatus = (before.status || '').toString().trim().toLowerCase();
    const nextStatus = (after.status || '').toString().trim().toLowerCase();
    if (!nextStatus || nextStatus === prevStatus) return null;

    if (nextStatus !== 'accepted') return null;

    const requestId = context.params.requestId;
    const requestRef = change.after.ref;

    // If the request already references a trip, do nothing.
    const existingTripId = (after.tripId || '').toString().trim();
    if (existingTripId) return null;

    const tripRef = db.collection('trips').doc(requestId);

    await db.runTransaction(async (tx) => {
      // Re-read request inside transaction for safety.
      const reqSnap = await tx.get(requestRef);
      if (!reqSnap.exists) return;

      const req = reqSnap.data() || {};
      const status = (req.status || '').toString().trim().toLowerCase();
      if (status !== 'accepted') return;

      const reqTripId = (req.tripId || '').toString().trim();
      if (reqTripId) return;

      const existingTripSnap = await tx.get(tripRef);
      if (existingTripSnap.exists) {
        // Trip already exists for this request, just backfill the request's tripId.
        tx.update(requestRef, {
          tripId: tripRef.id,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
      }

      const passengerId = (req.passengerId || '').toString().trim();
      const driverId = (req.driverId || '').toString().trim();
      const routeId = (req.routeId || '').toString().trim();
      const slotId = (req.scheduleId || req.slotId || '').toString().trim();

      // Best-effort: enrich from driver profile (vehicleId if available).
      let vehicleId = '';
      if (driverId) {
        const driverSnap = await tx.get(db.collection('drivers').doc(driverId));
        if (driverSnap.exists) {
          const d = driverSnap.data() || {};
          vehicleId = (d.vehicleId || '').toString().trim();
        }
      }

      const nowTs = admin.firestore.Timestamp.now();

      tx.set(tripRef, {
        tripId: tripRef.id, // equals requestId for idempotency
        requestId,
        passengerId,
        driverId,
        routeId,
        vehicleId,
        // Keep schedule/slot identifiers for linking to existing flow.
        scheduleId: slotId,
        slotId: slotId,
        seatsRequested: (req.seatsRequested || 1),
        lineLabel: (req.lineLabel || '').toString(),
        pickup: {
          startPoint: (req.startPoint || '').toString(),
          pickupDescription: (req.pickupDescription || '').toString(),
        },
        dropoff: {
          endPoint: (req.endPoint || '').toString(),
        },
        status: 'accepted',
        statusHistory: [
          {
            status: 'accepted',
            at: nowTs,
            by: driverId || null,
            source: 'tripDriverRequests',
          },
        ],
        requestCreatedAt: req.createdAt || null,
        requestRespondedAt: req.respondedAt || null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      tx.update(requestRef, {
        tripId: tripRef.id,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return null;
  });

function assertNonEmptyString(value, fieldName) {
  const v = (value || '').toString().trim();
  if (!v) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `${fieldName} is required.`,
    );
  }
  return v;
}

function normalizeAdminRole(role) {
  return (role || '').toString().trim().toLowerCase();
}

async function assertAdmin(context) {
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'You must be signed in to perform this action.',
    );
  }

  const callerUid = context.auth.uid;
  const callerSnap = await db.collection('users').doc(callerUid).get();
  if (!callerSnap.exists) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Your user profile was not found.',
    );
  }

  const callerData = callerSnap.data() || {};
  if (normalizeAdminRole(callerData.role) !== 'admin') {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Only admins can perform this action.',
    );
  }

  return { callerUid, callerUser: callerData };
}

function cleanCreateRouteManagerInput(data) {
  const firstName = assertNonEmptyString(data && data.firstName, 'firstName');
  const lastName = assertNonEmptyString(data && data.lastName, 'lastName');
  const email = assertNonEmptyString(data && data.email, 'email').toLowerCase();
  const phone = assertNonEmptyString(data && data.phone, 'phone');
  const password = assertNonEmptyString(data && data.password, 'password');
  const routeId = assertNonEmptyString(data && data.routeId, 'routeId');

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Please provide a valid email address.',
    );
  }

  if (password.length < 6) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Password must be at least 6 characters.',
    );
  }

  return { firstName, lastName, email, phone, password, routeId };
}

function isAuthEmailExistsError(error) {
  return error && error.code === 'auth/email-already-exists';
}

function mapCreateRouteManagerError(error) {
  if (error instanceof functions.https.HttpsError) return error;

  if (isAuthEmailExistsError(error)) {
    return new functions.https.HttpsError(
      'already-exists',
      'A Firebase Authentication user already exists for this email.',
    );
  }

  if (error && error.code === 'auth/invalid-password') {
    return new functions.https.HttpsError(
      'invalid-argument',
      'Password does not meet Firebase Authentication requirements.',
    );
  }

  if (error && error.code === 'auth/invalid-email') {
    return new functions.https.HttpsError(
      'invalid-argument',
      'Please provide a valid email address.',
    );
  }

  if (
    error &&
    (error.code === 'auth/invalid-phone-number' ||
      error.code === 'auth/phone-number-already-exists')
  ) {
    return new functions.https.HttpsError(
      'invalid-argument',
      'The phone number could not be added to Firebase Authentication. It must be unique and use E.164 format.',
    );
  }

  if (error && typeof error.code === 'string' && error.code.startsWith('auth/')) {
    return new functions.https.HttpsError(
      'failed-precondition',
      error.message || 'Firebase Authentication could not create the user.',
    );
  }

  if (error && typeof error.message === 'string' && error.message.trim()) {
    return new functions.https.HttpsError(
      'failed-precondition',
      error.message.trim(),
    );
  }

  console.error('[createRouteManager] unexpected error', error);
  return new functions.https.HttpsError(
    'internal',
    'Could not create route manager. Please try again.',
  );
}

/**
 * Callable: Create a route manager in Firebase Authentication and Firestore.
 *
 * Security:
 * - Caller must be authenticated.
 * - Caller must have `users/{uid}.role == "admin"`.
 *
 * Writes:
 * - `users/{newUid}` profile document.
 * - `route_manger/{newUid}` route-manager document.
 */
exports.createRouteManager = functions.https.onCall(async (data, context) => {
  try {
    const { callerUid } = await assertAdmin(context);
    const input = cleanCreateRouteManagerInput(data);

    const existingUserSnap = await db
      .collection('users')
      .where('email', '==', input.email)
      .limit(1)
      .get();
    if (!existingUserSnap.empty) {
      throw new functions.https.HttpsError(
        'already-exists',
        'A user profile already exists for this email.',
      );
    }

    const existingPhoneSnap = await db
      .collection('users')
      .where('phone', '==', input.phone)
      .limit(1)
      .get();
    if (!existingPhoneSnap.empty) {
      throw new functions.https.HttpsError(
        'already-exists',
        'A user profile already exists for this phone number.',
      );
    }

    const existingPhoneNumberSnap = await db
      .collection('users')
      .where('phoneNumber', '==', input.phone)
      .limit(1)
      .get();
    if (!existingPhoneNumberSnap.empty) {
      throw new functions.https.HttpsError(
        'already-exists',
        'A user profile already exists for this phone number.',
      );
    }

    const routeSnap = await db.collection('route').doc(input.routeId).get();
    if (!routeSnap.exists) {
      const routeByFieldSnap = await db
        .collection('route')
        .where('routeId', '==', input.routeId)
        .limit(1)
        .get();
      if (routeByFieldSnap.empty) {
        throw new functions.https.HttpsError(
          'not-found',
          'The selected route was not found.',
        );
      }
    }

    const authUser = await admin.auth().createUser({
      email: input.email,
      password: input.password,
      displayName: `${input.firstName} ${input.lastName}`.trim(),
      emailVerified: true,
      disabled: false,
    });

    const uid = authUser.uid;
    const now = admin.firestore.FieldValue.serverTimestamp();
    const profileData = {
      userId: uid,
      uid,
      firstName: input.firstName,
      lastName: input.lastName,
      fullName: `${input.firstName} ${input.lastName}`.trim(),
      name: `${input.firstName} ${input.lastName}`.trim(),
      email: input.email,
      phone: input.phone,
      phoneNumber: input.phone,
      role: 'route_manager',
      routeId: input.routeId,
      isVerified: true,
      isOnline: false,
      createdAt: now,
      updatedAt: now,
      createdBy: callerUid,
    };
    const routeManagerData = {
      userId: uid,
      firstName: input.firstName,
      lastName: input.lastName,
      email: input.email,
      phone: input.phone,
      role: 'route_manager',
      routeId: input.routeId,
      isVerified: true,
      createdAt: now,
      updatedAt: now,
      createdBy: callerUid,
    };
    try {
      const batch = db.batch();
      batch.set(db.collection('users').doc(uid), profileData);
      batch.set(db.collection('route_manger').doc(uid), routeManagerData);
      await batch.commit();
      await admin.auth().setCustomUserClaims(uid, { role: 'route_manager' });
    } catch (writeError) {
      await admin.auth().deleteUser(uid).catch((cleanupError) => {
        console.error('[createRouteManager] auth cleanup failed', cleanupError);
      });
      throw writeError;
    }

    return {
      success: true,
      userId: uid,
      message: 'Route manager created successfully.',
    };
  } catch (error) {
    throw mapCreateRouteManagerError(error);
  }
});

/**
 * Callable: Approve a driver account.
 *
 * - Requires authenticated caller
 * - Requires caller role `admin`
 * - Validates input and ensures driver + user records exist
 * - Updates `drivers/{driverId}` + `users/{driverId}` with approval state + metadata
 * - Creates a document in `notifications` (push is sent by the existing trigger)
 */
exports.approveDriverAccount = functions.https.onCall(async (data, context) => {
  const { callerUid } = await assertAdmin(context);

  const driverId = assertNonEmptyString(data && data.driverId, 'driverId');

  const driverRef = db.collection('drivers').doc(driverId);
  const driverSnap = await driverRef.get();
  if (!driverSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'Driver record not found.');
  }

  const driverData = driverSnap.data() || {};
  const userId = (
    (data && data.userId) ||
    driverData.userId ||
    driverData.uid ||
    driverId
  ).toString().trim();
  const userRef = db.collection('users').doc(userId);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'User record not found.');
  }

  const now = admin.firestore.FieldValue.serverTimestamp();

  const batch = db.batch();

  batch.set(
    driverRef,
    {
      isApproved: true,
      approvalStatus: 'approved',
      approvedAt: now,
      approvedBy: callerUid,
      rejectedAt: admin.firestore.FieldValue.delete(),
      rejectedBy: admin.firestore.FieldValue.delete(),
      rejectionReason: admin.firestore.FieldValue.delete(),
      updatedAt: now,
    },
    { merge: true },
  );

  // Avoid clobbering user schema: only add driver-specific approval fields.
  batch.set(
    userRef,
    {
      driverIsApproved: true,
      driverApprovalStatus: 'approved',
      driverApprovedAt: now,
      driverApprovedBy: callerUid,
      driverRejectedAt: admin.firestore.FieldValue.delete(),
      driverRejectedBy: admin.firestore.FieldValue.delete(),
      driverRejectionReason: admin.firestore.FieldValue.delete(),
      updatedAt: now,
    },
    { merge: true },
  );

  await batch.commit();

  await createNotificationDoc({
    userId,
    title: 'Navigo',
    type: 'driver_approved',
    message: 'Your driver account has been approved. You can now start accepting trips.',
    meta: {
      action: 'approve_driver',
      performedBy: callerUid,
    },
  });

  return { ok: true, driverId, userId };
});

/**
 * Callable: Reject a driver account.
 *
 * - Requires authenticated caller
 * - Requires caller role `admin`
 * - Validates input and ensures driver + user records exist
 * - Updates `drivers/{driverId}` + `users/{driverId}` with rejection state + metadata
 * - Supports optional `reason`
 * - Creates a document in `notifications` (push is sent by the existing trigger)
 */
exports.rejectDriverAccount = functions.https.onCall(async (data, context) => {
  const { callerUid } = await assertAdmin(context);

  const driverId = assertNonEmptyString(data && data.driverId, 'driverId');
  const reason =
    data && data.reason != null ? data.reason.toString().trim() : '';

  const driverRef = db.collection('drivers').doc(driverId);
  const driverSnap = await driverRef.get();
  if (!driverSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'Driver record not found.');
  }

  const driverData = driverSnap.data() || {};
  const userId = (
    (data && data.userId) ||
    driverData.userId ||
    driverData.uid ||
    driverId
  ).toString().trim();
  const userRef = db.collection('users').doc(userId);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'User record not found.');
  }

  const now = admin.firestore.FieldValue.serverTimestamp();

  const batch = db.batch();

  batch.set(
    driverRef,
    {
      isApproved: false,
      approvalStatus: 'rejected',
      rejectedAt: now,
      rejectedBy: callerUid,
      rejectionReason: reason || admin.firestore.FieldValue.delete(),
      approvedAt: admin.firestore.FieldValue.delete(),
      approvedBy: admin.firestore.FieldValue.delete(),
      updatedAt: now,
    },
    { merge: true },
  );

  batch.set(
    userRef,
    {
      driverIsApproved: false,
      driverApprovalStatus: 'rejected',
      driverRejectedAt: now,
      driverRejectedBy: callerUid,
      driverRejectionReason: reason || admin.firestore.FieldValue.delete(),
      driverApprovedAt: admin.firestore.FieldValue.delete(),
      driverApprovedBy: admin.firestore.FieldValue.delete(),
      updatedAt: now,
    },
    { merge: true },
  );

  await batch.commit();

  await createNotificationDoc({
    userId,
    title: 'Navigo',
    type: 'driver_rejected',
    message: reason
      ? `Your driver account was rejected. Reason: ${reason}`
      : 'Your driver account was rejected. Please contact support for details.',
    meta: {
      action: 'reject_driver',
      performedBy: callerUid,
      reason: reason || undefined,
    },
  });

  return { ok: true, driverId, userId };
});

