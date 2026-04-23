const express = require('express');
const router = express.Router();
const { authMiddleware } = require('../middleware/auth');
const tripsController = require('../controllers/trips.controller');

// POST /api/trips/request — request a trip
router.post('/request', authMiddleware, tripsController.requestTrip);

// GET /api/trips/history — get trip history for current user
router.get('/history', authMiddleware, tripsController.getTripHistory);

// POST /api/trips/:id/cancel — cancel a trip
router.post('/:id/cancel', authMiddleware, tripsController.cancelTrip);

module.exports = router;
