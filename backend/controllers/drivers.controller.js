const driversService = require('../services/drivers.service');
const { success, error } = require('../utils/response');

/**
 * GET /api/drivers/profile
 */
async function getProfile(req, res, next) {
  try {
    const { uid } = req.user;
    const profile = await driversService.getDriverProfile(uid);

    if (!profile) {
      return error(res, 'Driver not found', 404, 'NOT_FOUND');
    }

    return success(res, profile);
  } catch (err) {
    next(err);
  }
}

/**
 * PUT /api/drivers/status
 * Body: { status: 'online' | 'offline' }
 */
async function updateStatus(req, res, next) {
  try {
    const { uid } = req.user;
    const { status } = req.body;

    if (!status || !['online', 'offline'].includes(status)) {
      return error(res, 'Status must be "online" or "offline"', 400, 'VALIDATION');
    }

    const result = await driversService.updateStatus(uid, status);
    return success(res, result, `Driver is now ${status}`);
  } catch (err) {
    next(err);
  }
}

/**
 * PUT /api/drivers/location
 * Body: { latitude: number, longitude: number }
 */
async function updateLocation(req, res, next) {
  try {
    const { uid } = req.user;
    const { latitude, longitude } = req.body;

    if (latitude == null || longitude == null) {
      return error(res, 'Latitude and longitude are required', 400, 'VALIDATION');
    }

    const result = await driversService.updateLocation(uid, latitude, longitude);
    return success(res, result);
  } catch (err) {
    next(err);
  }
}

/**
 * POST /api/drivers/trip/complete
 * Body: { routeId: string, slotId: string }
 */
async function completeTrip(req, res, next) {
  try {
    const { uid } = req.user;
    const { routeId, slotId } = req.body;

    if (!routeId || !slotId) {
      return error(res, 'Route ID and Slot ID are required', 400, 'VALIDATION');
    }

    const result = await driversService.completeTrip(uid, routeId, slotId);
    return success(res, result, 'Trip completed');
  } catch (err) {
    next(err);
  }
}

module.exports = { getProfile, updateStatus, updateLocation, completeTrip };
