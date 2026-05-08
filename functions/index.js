const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

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
    userId,
    title: (data.title || 'Navigo').toString(),
    // Keep compatibility with clients that read either `message` or `body`.
    message: (data.message || data.body || '').toString(),
    body: (data.body || data.message || '').toString(),
    type: (data.type || '').toString(),
    tripId: data.tripId == null ? '' : data.tripId.toString(),
    routeId: data.routeId == null ? '' : data.routeId.toString(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    // Many apps expect a "read" boolean; keep it optional and default false.
    read: data.read === true,
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

  return await db.collection('notifications').add(doc);
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

    const title = (data.title || 'Navigo').toString();
    const body = (data.message || data.body || '').toString();
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

function normalizeRole(role) {
  const value = (role || '').toString().trim().toLowerCase();
  if (
    value === 'route_manager' ||
    value === 'route manager' ||
    value === 'routemanager' ||
    value === 'manager'
  ) {
    return 'route_manager';
  }
  return value;
}

async function assertRouteManager(context) {
  // Route-manager permission check:
  // - Caller must be authenticated (Firebase Auth)
  // - Caller role must be `route_manager` as stored in Firestore `users/{uid}.role`
  // - No admin/special-casing; only this role is allowed for driver management
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Authentication is required.',
    );
  }

  const callerUid = context.auth.uid;
  const callerSnap = await db.collection('users').doc(callerUid).get();
  if (!callerSnap.exists) {
    // If the user profile doesn't exist, we can't verify role.
    throw new functions.https.HttpsError(
      'permission-denied',
      'User profile not found or not authorized.',
    );
  }

  const callerData = callerSnap.data() || {};
  const role = normalizeRole(callerData.role);

  if (role !== 'route_manager') {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Only route managers can perform this action.',
    );
  }

  return { callerUid, callerUser: callerData };
}

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

/**
 * Callable: Approve a driver account.
 *
 * - Requires authenticated caller
 * - Requires caller role `route_manager`
 * - Validates input and ensures driver + user records exist
 * - Updates `drivers/{driverId}` + `users/{driverId}` with approval state + metadata
 * - Creates a document in `notifications` (push is sent by the existing trigger)
 */
exports.approveDriverAccount = functions.https.onCall(async (data, context) => {
  const { callerUid } = await assertRouteManager(context);

  const driverId = assertNonEmptyString(data && data.driverId, 'driverId');

  const driverRef = db.collection('drivers').doc(driverId);
  const userRef = db.collection('users').doc(driverId);

  const [driverSnap, userSnap] = await Promise.all([driverRef.get(), userRef.get()]);
  if (!driverSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'Driver record not found.');
  }
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
    userId: driverId,
    title: 'Navigo',
    type: 'driver_approved',
    message: 'Your driver account has been approved. You can now start accepting trips.',
    meta: {
      action: 'approve_driver',
      performedBy: callerUid,
    },
  });

  return { ok: true, driverId };
});

/**
 * Callable: Reject a driver account.
 *
 * - Requires authenticated caller
 * - Requires caller role `route_manager`
 * - Validates input and ensures driver + user records exist
 * - Updates `drivers/{driverId}` + `users/{driverId}` with rejection state + metadata
 * - Supports optional `reason`
 * - Creates a document in `notifications` (push is sent by the existing trigger)
 */
exports.rejectDriverAccount = functions.https.onCall(async (data, context) => {
  const { callerUid } = await assertRouteManager(context);

  const driverId = assertNonEmptyString(data && data.driverId, 'driverId');
  const reason =
    data && data.reason != null ? data.reason.toString().trim() : '';

  const driverRef = db.collection('drivers').doc(driverId);
  const userRef = db.collection('users').doc(driverId);

  const [driverSnap, userSnap] = await Promise.all([driverRef.get(), userRef.get()]);
  if (!driverSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'Driver record not found.');
  }
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
    userId: driverId,
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

  return { ok: true, driverId };
});

