const { getFirestore } = require('../config/firebase');
const admin = require('firebase-admin');

const ROUTES = 'route';
const DRIVERS = 'drivers';
const USERS = 'users';
const VEHICLES = 'vehicles';

/**
 * Get all schedule slots for a route.
 */
async function getSlots(routeId) {
  const db = getFirestore();
  const doc = await db.collection(ROUTES).doc(routeId).get();
  if (!doc.exists) return null;

  const data = doc.data();
  return (data.scheduleSlots || []).map(slot => ({
    slotId: slot.slotId || '',
    routeId: slot.routeId || routeId,
    departureAt: slot.departureAt ? slot.departureAt.toDate().toISOString() : null,
    arrivalAt: slot.arrivalAt ? slot.arrivalAt.toDate().toISOString() : null,
    capacity: slot.capacity || 0,
    vehicleType: slot.vehicleType || 'bus',
    driverId: slot.driverId || '',
    passengersIds: slot.passengersIds || [],
    status: slot.status || 'scheduled',
    price: slot.price || null,
  }));
}

/**
 * Add one or more schedule slots to a route.
 */
async function addSlots(routeId, newSlots) {
  const db = getFirestore();
  const routeRef = db.collection(ROUTES).doc(routeId);
  const routeDoc = await routeRef.get();

  if (!routeDoc.exists) {
    throw Object.assign(new Error('Route not found'), { statusCode: 404 });
  }

  const slotsToAdd = newSlots.map(slot => ({
    slotId: slot.slotId || db.collection('_').doc().id,
    routeId,
    departureAt: slot.departureAt ? admin.firestore.Timestamp.fromDate(new Date(slot.departureAt)) : null,
    arrivalAt: slot.arrivalAt ? admin.firestore.Timestamp.fromDate(new Date(slot.arrivalAt)) : null,
    capacity: slot.capacity || 0,
    vehicleType: slot.vehicleType || 'bus',
    driverId: slot.driverId || '',
    passengersIds: slot.passengersIds || [],
    status: slot.status || 'scheduled',
    price: slot.price || null,
  }));

  await routeRef.update({
    scheduleSlots: admin.firestore.FieldValue.arrayUnion(...slotsToAdd),
  });

  return slotsToAdd;
}

/**
 * Update a specific schedule slot.
 */
async function updateSlot(routeId, slotId, updates) {
  const db = getFirestore();
  const routeRef = db.collection(ROUTES).doc(routeId);
  const routeDoc = await routeRef.get();

  if (!routeDoc.exists) {
    throw Object.assign(new Error('Route not found'), { statusCode: 404 });
  }

  const data = routeDoc.data();
  const slots = data.scheduleSlots || [];

  let found = false;
  const updatedSlots = slots.map(slot => {
    if ((slot.slotId || '') === slotId) {
      found = true;
      return { ...slot, ...updates };
    }
    return slot;
  });

  if (!found) {
    throw Object.assign(new Error('Slot not found'), { statusCode: 404 });
  }

  await routeRef.update({ scheduleSlots: updatedSlots });
  return updatedSlots.find(s => s.slotId === slotId);
}

/**
 * Delete a specific schedule slot.
 */
async function deleteSlot(routeId, slotId) {
  const db = getFirestore();
  const routeRef = db.collection(ROUTES).doc(routeId);
  const routeDoc = await routeRef.get();

  if (!routeDoc.exists) {
    throw Object.assign(new Error('Route not found'), { statusCode: 404 });
  }

  const data = routeDoc.data();
  const slots = data.scheduleSlots || [];
  const filtered = slots.filter(s => (s.slotId || '') !== slotId);

  if (filtered.length === slots.length) {
    throw Object.assign(new Error('Slot not found'), { statusCode: 404 });
  }

  await routeRef.update({ scheduleSlots: filtered });
  return { routeId, slotId, deleted: true };
}

/**
 * Assign a driver to a specific schedule slot.
 */
async function assignDriverToSlot(routeId, slotId, driverId) {
  const db = getFirestore();
  const routeRef = db.collection(ROUTES).doc(routeId);
  const routeDoc = await routeRef.get();

  if (!routeDoc.exists) {
    throw Object.assign(new Error('Route not found'), { statusCode: 404 });
  }

  const data = routeDoc.data();
  const slots = data.scheduleSlots || [];

  let found = false;
  const updatedSlots = slots.map(slot => {
    if ((slot.slotId || '') === slotId) {
      found = true;
      return { ...slot, driverId };
    }
    return slot;
  });

  if (!found) {
    throw Object.assign(new Error('Slot not found'), { statusCode: 404 });
  }

  await routeRef.update({ scheduleSlots: updatedSlots });
  return { routeId, slotId, driverId };
}

/**
 * Get the driver queue for a route.
 */
async function getQueue(routeId) {
  const db = getFirestore();
  const routeDoc = await db.collection(ROUTES).doc(routeId).get();

  if (!routeDoc.exists) {
    throw Object.assign(new Error('Route not found'), { statusCode: 404 });
  }

  const data = routeDoc.data();
  const queueIds = data.driverQueueIds || [];

  // Enrich with driver info
  const enriched = [];
  for (const driverId of queueIds) {
    const driverDoc = await db.collection(DRIVERS).doc(driverId).get();
    const driverData = driverDoc.exists ? driverDoc.data() : {};

    const userDoc = await db.collection(USERS).doc(driverId).get();
    const userData = userDoc.exists ? userDoc.data() : {};

    let vehicleData = {};
    const vehicleId = (driverData.vehicleId || '').trim();
    if (vehicleId) {
      const vDoc = await db.collection(VEHICLES).doc(vehicleId).get();
      if (vDoc.exists) vehicleData = vDoc.data();
    }

    enriched.push({
      driverId,
      fullName: `${userData.firstName || ''} ${userData.lastName || ''}`.trim(),
      phone: userData.phone || '',
      plateNumber: vehicleData.plateNumber || '',
      vehicleType: vehicleData.type || 'bus',
      status: driverData.status || 'offline',
      isOnline: driverData.isOnline || false,
    });
  }

  return enriched;
}

/**
 * Queue all approved drivers for a route.
 */
async function queueAllDrivers(routeId) {
  const db = getFirestore();
  const routeRef = db.collection(ROUTES).doc(routeId);
  const routeDoc = await routeRef.get();

  if (!routeDoc.exists) {
    throw Object.assign(new Error('Route not found'), { statusCode: 404 });
  }

  // Get all approved online drivers for this route
  const driversSnap = await db.collection(DRIVERS)
    .where('routeId', '==', routeId)
    .where('isApproved', '==', true)
    .where('isOnline', '==', true)
    .get();

  const driverIds = driversSnap.docs.map(d => d.id);

  await routeRef.update({ driverQueueIds: driverIds });

  return { routeId, queuedDriverIds: driverIds };
}

/**
 * Clear the driver queue for a route.
 */
async function clearQueue(routeId) {
  const db = getFirestore();
  const routeRef = db.collection(ROUTES).doc(routeId);

  await routeRef.update({ driverQueueIds: [] });
  return { routeId, cleared: true };
}

/**
 * Add a single driver to the queue.
 */
async function addDriverToQueue(routeId, driverId) {
  const db = getFirestore();
  await db.collection(ROUTES).doc(routeId).update({
    driverQueueIds: admin.firestore.FieldValue.arrayUnion(driverId),
  });
  return { routeId, driverId, queued: true };
}

/**
 * Remove a single driver from the queue.
 */
async function removeDriverFromQueue(routeId, driverId) {
  const db = getFirestore();
  await db.collection(ROUTES).doc(routeId).update({
    driverQueueIds: admin.firestore.FieldValue.arrayRemove(driverId),
  });
  return { routeId, driverId, removed: true };
}

/**
 * Auto-assign the next driver from the queue to the first unassigned slot.
 * Optionally filter by vehicle type.
 */
async function assignNextFromQueue(routeId, vehicleType) {
  const db = getFirestore();
  const routeRef = db.collection(ROUTES).doc(routeId);
  const routeDoc = await routeRef.get();

  if (!routeDoc.exists) {
    throw Object.assign(new Error('Route not found'), { statusCode: 404 });
  }

  const data = routeDoc.data();
  const slots = data.scheduleSlots || [];
  const queue = data.driverQueueIds || [];

  if (queue.length === 0) {
    throw Object.assign(new Error('Driver queue is empty'), { statusCode: 400 });
  }

  // Find first unassigned slot (optionally matching vehicleType)
  const targetSlot = slots.find(slot => {
    const isUnassigned = !(slot.driverId || '').trim();
    const statusOk = (slot.status || 'scheduled') === 'scheduled';
    const typeOk = !vehicleType || (slot.vehicleType || 'bus') === vehicleType;
    return isUnassigned && statusOk && typeOk;
  });

  if (!targetSlot) {
    throw Object.assign(new Error('No unassigned slots available'), { statusCode: 400 });
  }

  // Take the first driver from the queue
  const driverId = queue[0];

  // Assign driver and remove from queue
  const updatedSlots = slots.map(slot => {
    if ((slot.slotId || '') === (targetSlot.slotId || '')) {
      return { ...slot, driverId };
    }
    return slot;
  });

  const updatedQueue = queue.filter(id => id !== driverId);

  await routeRef.update({
    scheduleSlots: updatedSlots,
    driverQueueIds: updatedQueue,
  });

  return {
    routeId,
    slotId: targetSlot.slotId,
    driverId,
    remainingQueue: updatedQueue.length,
  };
}

module.exports = {
  getSlots,
  addSlots,
  updateSlot,
  deleteSlot,
  assignDriverToSlot,
  getQueue,
  queueAllDrivers,
  clearQueue,
  addDriverToQueue,
  removeDriverFromQueue,
  assignNextFromQueue,
};
