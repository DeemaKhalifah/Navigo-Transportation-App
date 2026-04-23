const tripsService = require('../services/trips.service');
const { success, error, created } = require('../utils/response');

/**
 * POST /api/trips/request
 */
async function requestTrip(req, res, next) {
  try {
    const { uid } = req.user;
    const {
      driverId, routeId, scheduleId, seatsRequested,
      lineLabel, startPoint, endPoint, pickupDescription,
    } = req.body;

    if (!driverId || !routeId) {
      return error(res, 'Driver ID and Route ID are required', 400, 'VALIDATION');
    }

    const result = await tripsService.createTripRequest({
      passengerId: uid,
      driverId,
      routeId,
      scheduleId: scheduleId || '',
      seatsRequested: seatsRequested || 1,
      lineLabel: lineLabel || '',
      startPoint: startPoint || '',
      endPoint: endPoint || '',
      pickupDescription: pickupDescription || '',
    });

    return created(res, result, 'Trip request created');
  } catch (err) {
    next(err);
  }
}

/**
 * GET /api/trips/history
 */
async function getTripHistory(req, res, next) {
  try {
    const { uid } = req.user;
    const history = await tripsService.getTripHistory(uid);
    return success(res, history);
  } catch (err) {
    next(err);
  }
}

/**
 * POST /api/trips/:id/cancel
 */
async function cancelTrip(req, res, next) {
  try {
    const { uid } = req.user;
    const { id } = req.params;

    await tripsService.cancelTrip(uid, id);
    return success(res, null, 'Trip cancelled');
  } catch (err) {
    next(err);
  }
}

module.exports = { requestTrip, getTripHistory, cancelTrip };
