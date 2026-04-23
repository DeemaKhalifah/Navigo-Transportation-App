const scheduleService = require('../services/schedule.service');
const { success, error, created } = require('../utils/response');

/**
 * GET /api/schedule/:routeId/slots
 */
async function getSlots(req, res, next) {
  try {
    const { routeId } = req.params;
    const slots = await scheduleService.getSlots(routeId);

    if (slots === null) {
      return error(res, 'Route not found', 404, 'NOT_FOUND');
    }

    return success(res, slots);
  } catch (err) {
    next(err);
  }
}

/**
 * POST /api/schedule/:routeId/slots
 * Body: { slots: [ { departureAt, arrivalAt, capacity, vehicleType, ... } ] }
 */
async function addSlots(req, res, next) {
  try {
    const { routeId } = req.params;
    const { slots } = req.body;

    if (!slots || !Array.isArray(slots) || slots.length === 0) {
      return error(res, 'At least one slot is required', 400, 'VALIDATION');
    }

    const result = await scheduleService.addSlots(routeId, slots);
    return created(res, result, 'Slots added');
  } catch (err) {
    next(err);
  }
}

/**
 * PUT /api/schedule/:routeId/slots/:slotId
 * Body: partial slot updates
 */
async function updateSlot(req, res, next) {
  try {
    const { routeId, slotId } = req.params;
    const updates = req.body;

    const result = await scheduleService.updateSlot(routeId, slotId, updates);
    return success(res, result, 'Slot updated');
  } catch (err) {
    next(err);
  }
}

/**
 * DELETE /api/schedule/:routeId/slots/:slotId
 */
async function deleteSlot(req, res, next) {
  try {
    const { routeId, slotId } = req.params;
    const result = await scheduleService.deleteSlot(routeId, slotId);
    return success(res, result, 'Slot deleted');
  } catch (err) {
    next(err);
  }
}

/**
 * POST /api/schedule/:routeId/slots/:slotId/assign
 * Body: { driverId: string }
 */
async function assignDriver(req, res, next) {
  try {
    const { routeId, slotId } = req.params;
    const { driverId } = req.body;

    if (!driverId) {
      return error(res, 'Driver ID is required', 400, 'VALIDATION');
    }

    const result = await scheduleService.assignDriverToSlot(routeId, slotId, driverId);
    return success(res, result, 'Driver assigned');
  } catch (err) {
    next(err);
  }
}

/**
 * GET /api/schedule/:routeId/queue
 */
async function getQueue(req, res, next) {
  try {
    const { routeId } = req.params;
    const queue = await scheduleService.getQueue(routeId);
    return success(res, queue);
  } catch (err) {
    next(err);
  }
}

/**
 * POST /api/schedule/:routeId/queue/all — queue all available drivers
 */
async function queueAllDrivers(req, res, next) {
  try {
    const { routeId } = req.params;
    const result = await scheduleService.queueAllDrivers(routeId);
    return success(res, result, 'All drivers queued');
  } catch (err) {
    next(err);
  }
}

/**
 * DELETE /api/schedule/:routeId/queue — clear queue
 */
async function clearQueue(req, res, next) {
  try {
    const { routeId } = req.params;
    const result = await scheduleService.clearQueue(routeId);
    return success(res, result, 'Queue cleared');
  } catch (err) {
    next(err);
  }
}

/**
 * POST /api/schedule/:routeId/queue/:driverId — add driver to queue
 */
async function addDriverToQueue(req, res, next) {
  try {
    const { routeId, driverId } = req.params;
    const result = await scheduleService.addDriverToQueue(routeId, driverId);
    return success(res, result, 'Driver queued');
  } catch (err) {
    next(err);
  }
}

/**
 * DELETE /api/schedule/:routeId/queue/:driverId — remove driver from queue
 */
async function removeDriverFromQueue(req, res, next) {
  try {
    const { routeId, driverId } = req.params;
    const result = await scheduleService.removeDriverFromQueue(routeId, driverId);
    return success(res, result, 'Driver removed from queue');
  } catch (err) {
    next(err);
  }
}

/**
 * POST /api/schedule/:routeId/assign-next
 * Body: { vehicleType?: string }
 */
async function assignNextFromQueue(req, res, next) {
  try {
    const { routeId } = req.params;
    const { vehicleType } = req.body || {};

    const result = await scheduleService.assignNextFromQueue(routeId, vehicleType);
    return success(res, result, 'Next driver assigned');
  } catch (err) {
    next(err);
  }
}

module.exports = {
  getSlots,
  addSlots,
  updateSlot,
  deleteSlot,
  assignDriver,
  getQueue,
  queueAllDrivers,
  clearQueue,
  addDriverToQueue,
  removeDriverFromQueue,
  assignNextFromQueue,
};
