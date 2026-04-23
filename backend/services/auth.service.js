const { getFirestore } = require('../config/firebase');

const USERS = 'users';
const DRIVERS = 'drivers';
const VEHICLES = 'vehicles';
const PASSENGERS = 'passengers';

/**
 * Get user document by UID.
 */
async function getUserByUid(uid) {
  const db = getFirestore();
  const doc = await db.collection(USERS).doc(uid).get();

  if (!doc.exists) return null;

  const data = doc.data();
  return {
    uid: doc.id,
    firstName: data.firstName || '',
    lastName: data.lastName || '',
    phone: data.phone || '',
    role: data.role || 'passenger',
    image: data.image || null,
    isVerified: data.isVerified || false,
    language: data.language || 'en',
  };
}

/**
 * Create a passenger user.
 */
async function createPassenger({ uid, firstName, lastName, phone }) {
  const db = getFirestore();
  const batch = db.batch();

  // Create user document
  const userRef = db.collection(USERS).doc(uid);
  batch.set(userRef, {
    firstName,
    lastName,
    phone,
    role: 'passenger',
    isVerified: true,
    isOnline: false,
    createdAt: new Date(),
  }, { merge: true });

  // Create passenger document
  const passengerRef = db.collection(PASSENGERS).doc(uid);
  batch.set(passengerRef, {
    userId: uid,
    passengerId: uid,
    fullName: `${firstName} ${lastName}`.trim(),
    phoneNumber: phone,
    createdAt: new Date(),
  }, { merge: true });

  await batch.commit();

  return {
    uid,
    firstName,
    lastName,
    phone,
    role: 'passenger',
  };
}

/**
 * Create a driver user.
 */
async function createDriver({
  uid, firstName, lastName, phone,
  routeId, plateNumber, vehicleType, licenseNumber,
}) {
  const db = getFirestore();
  const batch = db.batch();

  // Create user document
  const userRef = db.collection(USERS).doc(uid);
  batch.set(userRef, {
    firstName,
    lastName,
    phone,
    role: 'driver',
    isVerified: false,
    isOnline: false,
    createdAt: new Date(),
  }, { merge: true });

  // Create driver document
  const driverRef = db.collection(DRIVERS).doc(uid);
  batch.set(driverRef, {
    userId: uid,
    driverId: uid,
    fullName: `${firstName} ${lastName}`.trim(),
    phoneNumber: phone,
    routeId: routeId,
    status: 'offline',
    isOnline: false,
    isApproved: false,
    createdAt: new Date(),
  }, { merge: true });

  // Create vehicle document if plate number given
  if (plateNumber) {
    const vehicleRef = db.collection(VEHICLES).doc();
    batch.set(vehicleRef, {
      driverId: uid,
      plateNumber,
      type: vehicleType || 'bus',
      createdAt: new Date(),
    });

    // Link vehicle to driver
    batch.update(driverRef, { vehicleId: vehicleRef.id });
  }

  await batch.commit();

  return {
    uid,
    firstName,
    lastName,
    phone,
    role: 'driver',
    isApproved: false,
  };
}

module.exports = { getUserByUid, createPassenger, createDriver };
