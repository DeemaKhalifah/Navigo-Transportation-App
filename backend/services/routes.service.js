const { getFirestore } = require('../config/firebase');

const ROUTES = 'route';
const DRIVERS = 'drivers';
const USERS = 'users';
const VEHICLES = 'vehicles';

/**
 * Get all routes with schedule info.
 */
async function getAllRoutes() {
  const db = getFirestore();
  const snap = await db.collection(ROUTES).get();
  const routes = [];

  for (const doc of snap.docs) {
    const data = doc.data();
    const startPoint = (data.startPoint || data.startpoint || data.from || '').toString().trim();
    const endPoint = (data.endPoint || data.endpoint || data.to || '').toString().trim();

    if (!startPoint || !endPoint) continue;

    routes.push({
      routeId: data.routeId || doc.id,
      startPoint,
      endPoint,
      price: data.price || 0,
      vehicleTypes: data.vehicleTypes || [],
      scheduleSlots: (data.scheduleSlots || []).map(slot => ({
        slotId: slot.slotId || '',
        routeId: slot.routeId || doc.id,
        departureAt: slot.departureAt ? slot.departureAt.toDate().toISOString() : null,
        arrivalAt: slot.arrivalAt ? slot.arrivalAt.toDate().toISOString() : null,
        capacity: slot.capacity || 0,
        vehicleType: slot.vehicleType || 'bus',
        driverId: slot.driverId || '',
        passengersIds: slot.passengersIds || [],
        status: slot.status || 'scheduled',
        price: slot.price || null,
        etaMinutes: slot.etaMinutes || null,
        etaText: slot.etaText || '',
        distanceMeters: slot.distanceMeters || null,
        distanceText: slot.distanceText || '',
        routeModule: slot.routeModule || null,
      })),
      driverQueueIds: data.driverQueueIds || [],
      etaMinutes: data.etaMinutes || null,
      etaText: data.etaText || '',
      distanceMeters: data.distanceMeters || null,
      distanceText: data.distanceText || '',
      routePath: data.routePath || data.path || [],
      routeModule: data.routeModule || null,
    });
  }

  routes.sort((a, b) =>
    `${a.startPoint} <-----> ${a.endPoint}`.localeCompare(`${b.startPoint} <-----> ${b.endPoint}`)
  );

  return routes;
}

/**
 * Get a route by ID.
 */
async function getRouteById(routeId) {
  const db = getFirestore();
  const doc = await db.collection(ROUTES).doc(routeId).get();
  if (!doc.exists) return null;

  const data = doc.data();
  return {
    routeId: data.routeId || doc.id,
    startPoint: data.startPoint || '',
    endPoint: data.endPoint || '',
    price: data.price || 0,
    vehicleTypes: data.vehicleTypes || [],
    scheduleSlots: (data.scheduleSlots || []).map(slot => ({
      slotId: slot.slotId || '',
      routeId: slot.routeId || doc.id,
      departureAt: slot.departureAt ? slot.departureAt.toDate().toISOString() : null,
      arrivalAt: slot.arrivalAt ? slot.arrivalAt.toDate().toISOString() : null,
      capacity: slot.capacity || 0,
      vehicleType: slot.vehicleType || 'bus',
      driverId: slot.driverId || '',
      passengersIds: slot.passengersIds || [],
      status: slot.status || 'scheduled',
      etaMinutes: slot.etaMinutes || null,
      etaText: slot.etaText || '',
      distanceMeters: slot.distanceMeters || null,
      distanceText: slot.distanceText || '',
      routeModule: slot.routeModule || null,
    })),
    etaMinutes: data.etaMinutes || null,
    etaText: data.etaText || '',
    distanceMeters: data.distanceMeters || null,
    distanceText: data.distanceText || '',
    routePath: data.routePath || data.path || [],
    routeModule: data.routeModule || null,
  };
}

/**
 * Get available drivers for a line (or all drivers if line is empty).
 * Mirrors the Flutter PassengerTripRepository logic.
 */
async function getDriversForLine(lineFilter) {
  const db = getFirestore();
  const routes = await getAllRoutes();

  // Build routes map
  const routesById = {};
  for (const route of routes) {
    routesById[route.routeId] = route;
  }

  // If line is provided, filter to matching route
  let targetRoutes = routes;
  if (lineFilter && lineFilter.trim()) {
    targetRoutes = routes.filter(r =>
      `${r.startPoint} <-----> ${r.endPoint}` === lineFilter.trim()
    );
  }

  const targetRouteIds = new Set(targetRoutes.map(r => r.routeId));

  // Get approved drivers
  const driversSnap = await db.collection(DRIVERS)
    .where('isApproved', '==', true)
    .get();

  const result = [];

  for (const driverDoc of driversSnap.docs) {
    const driverData = driverDoc.data();
    const routeId = (driverData.routeId || '').toString().trim();
    const route = routesById[routeId];

    if (!route) continue;
    if (lineFilter && lineFilter.trim() && !targetRouteIds.has(routeId)) continue;

    // Get driver location
    const lat = driverData.latitude;
    const lng = driverData.longitude;
    if (lat == null || lng == null) {
      // Check nested location
      const loc = driverData.location;
      if (!loc || !loc.lat || !loc.lng) continue;
    }

    const driverLat = lat || (driverData.location && driverData.location.lat);
    const driverLng = lng || (driverData.location && driverData.location.lng);
    if (!driverLat || !driverLng) continue;

    // Find an available slot for this driver
    const slot = findOfferSlot(route, driverDoc.id);
    if (!slot) continue;

    const availableSeats = slot.capacity - (slot.passengersIds || []).length;

    // Get user info
    const userId = driverData.userId || driverDoc.id;
    const userDoc = await db.collection(USERS).doc(userId).get();
    const userData = userDoc.exists ? userDoc.data() : {};

    // Get vehicle info
    const vehicleId = (driverData.vehicleId || '').toString().trim();
    let vehicleData = {};
    if (vehicleId) {
      const vDoc = await db.collection(VEHICLES).doc(vehicleId).get();
      if (vDoc.exists) vehicleData = vDoc.data();
    }

    const driverName = `${userData.firstName || ''} ${userData.lastName || ''}`.trim();

    result.push({
      id: driverDoc.id,
      routeId: route.routeId,
      slotId: slot.slotId,
      scheduleId: slot.slotId,
      name: driverName || `Driver ${driverDoc.id.substring(0, 6)}`,
      busNumber: (vehicleData.plateNumber || 'N/A').toString(),
      line: `${route.startPoint} <-----> ${route.endPoint}`,
      from: route.startPoint,
      to: route.endPoint,
      availableSeats,
      price: `${route.price} NIS`,
      eta: slot.etaText || route.etaText || 'Live',
      etaMinutes: slot.etaMinutes || route.etaMinutes || null,
      phone: (userData.phone || 'N/A').toString(),
      vehicleType: (vehicleData.type || 'Bus').toString(),
      lat: driverLat,
      lng: driverLng,
    });
  }

  return result;
}

/**
 * Find an available schedule slot for a driver.
 */
function findOfferSlot(route, driverDocId) {
  const now = new Date();
  const candidates = [];

  for (const slot of route.scheduleSlots || []) {
    if ((slot.driverId || '').trim() !== driverDocId.trim()) continue;

    const status = normalizeStatus(slot.status);
    if (status !== 'onTrip' && status !== 'scheduled') continue;

    const available = slot.capacity - (slot.passengersIds || []).length;
    if (available < 1) continue;

    candidates.push(slot);
  }

  if (candidates.length === 0) return null;

  // Sort by departure
  candidates.sort((a, b) => {
    const da = a.departureAt ? new Date(a.departureAt) : new Date();
    const db2 = b.departureAt ? new Date(b.departureAt) : new Date();
    return da - db2;
  });

  return candidates[0];
}

function normalizeStatus(raw) {
  if (!raw) return 'scheduled';
  const s = raw.toString().trim().toLowerCase().replace(/[\s_-]+/g, '');
  if (s === 'ongoing' || s === 'ontrip' || s === 'inprogress') return 'onTrip';
  if (s === 'completed') return 'completed';
  if (s === 'cancelled') return 'cancelled';
  return 'scheduled';
}

module.exports = { getAllRoutes, getRouteById, getDriversForLine };
