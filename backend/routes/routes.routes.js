const express = require('express');
const router = express.Router();
const { authMiddleware } = require('../middleware/auth');
const routesController = require('../controllers/routes.controller');

// GET /api/routes — list all routes
router.get('/', routesController.getAllRoutes);

// GET /api/routes/drivers — get available drivers (query: ?line=...)
router.get('/drivers', routesController.getDriversForLine);

// GET /api/routes/:id — get single route
router.get('/:id', routesController.getRouteById);

module.exports = router;
