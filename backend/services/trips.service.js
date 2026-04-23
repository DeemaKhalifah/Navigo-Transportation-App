const { getFirestore } = require('../config/firebase');
const admin = require('firebase-admin');

const ROUTES = 'route';
const USERS = 'users';

/**
 * Create a trip request (passenger requests ride from driver).
 * Creates a notification in the driver's notifications sub-collection
 * and stores the request in a `tripRequests` collection.
 */
async function createTripRequest({
  passengerId, driverId, routeId, scheduleId,
  seatsRequested, lineLabel, startPoint, endPoint, pickupDescription,
}) {
  const db = getFirestore();

  // Get passenger name
  const userDoc = await db.collection(USERS).doc(passengerId).get();
  const userData = userDoc.exists ? userDoc.data() : {};
  const passengerName = `${userData.firstName || ''} ${userData.lastName || ''}`.trim() || 'Passenger';

  const requestData = {
    passengerId,
    driverId,
    routeId,
    scheduleId,
    seatsRequested,
    lineLabel,
    startPoint,
    endPoint,
    pickupDescription,
    passengerName,
    status: 'pending',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  // Save to tripRequests collection
  const requestRef = await db.collection('tripRequests').add(requestData);

  // Send notification to driver
  await db.collection(USERS).doc(driverId).collection('notifications').add({
    title: 'New Trip Request',
    body: `${passengerName} requested ${seatsRequested} seat(s) on ${lineLabel}`,
    from: passengerName,
    type: 'trip_request',
    requestId: requestRef.id,
    isRead: false,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    requestId: requestRef.id,
    ...requestData,
  };
}

/**
 * Get trip history for a passenger.
 */
async function getTripHistory(passengerId) {
  const db = getFirestore();

  const snap = await db.collection('tripRequests')
    .where('passengerId', '==', passengerId)
    .orderBy('createdAt', 'desc')
    .limit(50)
    .get();

  return snap.docs.map(doc => ({
    id: doc.id,
    ...doc.data(),
    createdAt: doc.data().createdAt ? doc.data().createdAt.toDate().toISOString() : null,
  }));
}

/**
 * Cancel a trip request.
 */
async function cancelTrip(passengerId, requestId) {
  const db = getFirestore();
  const ref = db.collection('tripRequests').doc(requestId);
  const doc = await ref.get();

  if (!doc.exists) {
    throw Object.assign(new Error('Trip request not found'), { statusCode: 404 });
  }

  const data = doc.data();
  if (data.passengerId !== passengerId) {
    throw Object.assign(new Error('Not authorized'), { statusCode: 403 });
  }

  await ref.update({
    status: 'cancelled',
    cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { requestId, status: 'cancelled' };
}

module.exports = { createTripRequest, getTripHistory, cancelTrip };
