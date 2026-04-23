const express = require('express');
const router = express.Router();
const { authMiddleware } = require('../middleware/auth');
const driversController = require('../controllers/drivers.controller');

// GET /api/drivers/profile — get current driver profile
router.get('/profile', authMiddleware, driversController.getProfile);

// PUT /api/drivers/status — go online/offline
router.put('/status', authMiddleware, driversController.updateStatus);

// PUT /api/drivers/location — update GPS coordinates
router.put('/location', authMiddleware, driversController.updateLocation);

// POST /api/drivers/trip/complete — complete a trip
router.post('/trip/complete', authMiddleware, driversController.completeTrip);

module.exports = router;
