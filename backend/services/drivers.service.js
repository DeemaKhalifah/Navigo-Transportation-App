const { getFirestore } = require('../config/firebase');
const admin = require('firebase-admin');

const DRIVERS = 'drivers';
const USERS = 'users';
const VEHICLES = 'vehicles';
const ROUTES = 'route';

/**
 * Get driver profile by UID — includes user info, driver info, and vehicle info.
 */
async function getDriverProfile(uid) {
  const db = getFirestore();

  const driverDoc = await db.collection(DRIVERS).doc(uid).get();
  if (!driverDoc.exists) return null;

  const driverData = driverDoc.data();

  // Get user info
  const userDoc = await db.collection(USERS).doc(uid).get();
  const userData = userDoc.exists ? userDoc.data() : {};

  // Get vehicle info
  let vehicleData = {};
  const vehicleId = (driverData.vehicleId || '').toString().trim();
  if (vehicleId) {
    const vDoc = await db.collection(VEHICLES).doc(vehicleId).get();
    if (vDoc.exists) vehicleData = vDoc.data();
  }

  return {
    uid,
    firstName: userData.firstName || '',
    lastName: userData.lastName || '',
    fullName: `${userData.firstName || ''} ${userData.lastName || ''}`.trim(),
    phone: userData.phone || '',
    image: userData.image || null,
    role: userData.role || 'driver',
    routeId: driverData.routeId || '',
    status: driverData.status || 'offline',
    isOnline: driverData.isOnline || false,
    isApproved: driverData.isApproved || false,
    vehicleId: vehicleId,
    plateNumber: vehicleData.plateNumber || '',
    vehicleType: vehicleData.type || 'bus',
    latitude: driverData.latitude || null,
    longitude: driverData.longitude || null,
  };
}

/**
 * Update driver status (online/offline).
 * When going online: joins the route's driver queue.
 * When going offline: leaves the driver queue.
 */
async function updateStatus(uid, status) {
  const db = getFirestore();
  const batch = db.batch();

  const isOnline = status === 'online';
  const driverRef = db.collection(DRIVERS).doc(uid);
  const driverDoc = await driverRef.get();

  if (!driverDoc.exists) {
    throw Object.assign(new Error('Driver not found'), { statusCode: 404 });
  }

  const driverData = driverDoc.data();
  const routeId = (driverData.routeId || '').trim();

  // Update driver status
  batch.update(driverRef, {
    status: isOnline ? 'online' : 'offline',
    isOnline,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Update user online status
  const userRef = db.collection(USERS).doc(uid);
  batch.update(userRef, { isOnline });

  // Manage driver queue for the route
  if (routeId) {
    const routeRef = db.collection(ROUTES).doc(routeId);
    if (isOnline) {
      batch.update(routeRef, {
        driverQueueIds: admin.firestore.FieldValue.arrayUnion(uid),
      });
    } else {
      batch.update(routeRef, {
        driverQueueIds: admin.firestore.FieldValue.arrayRemove(uid),
      });
    }
  }

  await batch.commit();

  return { uid, status: isOnline ? 'online' : 'offline', isOnline };
}

/**
 * Update driver GPS location.
 */
async function updateLocation(uid, latitude, longitude) {
  const db = getFirestore();
  await db.collection(DRIVERS).doc(uid).update({
    latitude,
    longitude,
    location: { lat: latitude, lng: longitude },
    locationUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { uid, latitude, longitude };
}

/**
 * Complete a trip — update schedule slot status and driver status.
 */
async function completeTrip(uid, routeId, slotId) {
  const db = getFirestore();
  const routeRef = db.collection(ROUTES).doc(routeId);
  const routeDoc = await routeRef.get();

  if (!routeDoc.exists) {
    throw Object.assign(new Error('Route not found'), { statusCode: 404 });
  }

  const routeData = routeDoc.data();
  const slots = routeData.scheduleSlots || [];

  const updatedSlots = slots.map(slot => {
    if ((slot.slotId || '') === slotId && (slot.driverId || '') === uid) {
      return { ...slot, status: 'completed' };
    }
    return slot;
  });

  await routeRef.update({ scheduleSlots: updatedSlots });

  // Set driver back to online (available for next trip)
  await db.collection(DRIVERS).doc(uid).update({
    status: 'online',
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { routeId, slotId, status: 'completed' };
}

module.exports = { getDriverProfile, updateStatus, updateLocation, completeTrip };
