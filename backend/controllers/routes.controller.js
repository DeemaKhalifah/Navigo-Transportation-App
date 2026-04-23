const routesService = require('../services/routes.service');
const { success, error } = require('../utils/response');

/**
 * GET /api/routes
 */
async function getAllRoutes(req, res, next) {
  try {
    const routes = await routesService.getAllRoutes();
    return success(res, routes);
  } catch (err) {
    next(err);
  }
}

/**
 * GET /api/routes/:id
 */
async function getRouteById(req, res, next) {
  try {
    const route = await routesService.getRouteById(req.params.id);
    if (!route) {
      return error(res, 'Route not found', 404, 'NOT_FOUND');
    }
    return success(res, route);
  } catch (err) {
    next(err);
  }
}

/**
 * GET /api/routes/drivers?line=...
 */
async function getDriversForLine(req, res, next) {
  try {
    const { line } = req.query;
    const drivers = await routesService.getDriversForLine(line || '');
    return success(res, drivers);
  } catch (err) {
    next(err);
  }
}

module.exports = { getAllRoutes, getRouteById, getDriversForLine };
