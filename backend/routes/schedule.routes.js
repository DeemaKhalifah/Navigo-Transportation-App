const express = require('express');
const router = express.Router();
const { authMiddleware } = require('../middleware/auth');
const scheduleController = require('../controllers/schedule.controller');

// GET /api/schedule/:routeId/slots — list slots
router.get('/:routeId/slots', authMiddleware, scheduleController.getSlots);

// POST /api/schedule/:routeId/slots — add slot(s)
router.post('/:routeId/slots', authMiddleware, scheduleController.addSlots);

// PUT /api/schedule/:routeId/slots/:slotId — update a slot
router.put('/:routeId/slots/:slotId', authMiddleware, scheduleController.updateSlot);

// DELETE /api/schedule/:routeId/slots/:slotId — delete a slot
router.delete('/:routeId/slots/:slotId', authMiddleware, scheduleController.deleteSlot);

// POST /api/schedule/:routeId/slots/:slotId/assign — assign driver to slot
router.post('/:routeId/slots/:slotId/assign', authMiddleware, scheduleController.assignDriver);

// GET /api/schedule/:routeId/queue — get driver queue
router.get('/:routeId/queue', authMiddleware, scheduleController.getQueue);

// POST /api/schedule/:routeId/queue/all — queue all available drivers
router.post('/:routeId/queue/all', authMiddleware, scheduleController.queueAllDrivers);

// DELETE /api/schedule/:routeId/queue — clear queue
router.delete('/:routeId/queue', authMiddleware, scheduleController.clearQueue);

// POST /api/schedule/:routeId/queue/:driverId — add driver to queue
router.post('/:routeId/queue/:driverId', authMiddleware, scheduleController.addDriverToQueue);

// DELETE /api/schedule/:routeId/queue/:driverId — remove driver from queue
router.delete('/:routeId/queue/:driverId', authMiddleware, scheduleController.removeDriverFromQueue);

// POST /api/schedule/:routeId/assign-next — auto-assign next unassigned slot
router.post('/:routeId/assign-next', authMiddleware, scheduleController.assignNextFromQueue);

module.exports = router;
