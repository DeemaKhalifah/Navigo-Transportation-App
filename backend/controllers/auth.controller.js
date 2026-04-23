const authService = require('../services/auth.service');
const { success, error, created } = require('../utils/response');

/**
 * POST /api/auth/login
 * Verify token and return user profile with role.
 */
async function login(req, res, next) {
  try {
    const { uid } = req.user;
    const userData = await authService.getUserByUid(uid);

    if (!userData) {
      return error(res, 'User not found', 404, 'USER_NOT_FOUND');
    }

    return success(res, userData, 'Login successful');
  } catch (err) {
    next(err);
  }
}

/**
 * POST /api/auth/register/passenger
 */
async function registerPassenger(req, res, next) {
  try {
    const { uid } = req.user;
    const { fullName, phone } = req.body;

    if (!fullName || !phone) {
      return error(res, 'Full name and phone are required', 400, 'VALIDATION');
    }

    const names = fullName.trim().split(' ');
    const firstName = names[0] || '';
    const lastName = names.length > 1 ? names.slice(1).join(' ') : '';

    const result = await authService.createPassenger({
      uid,
      firstName,
      lastName,
      phone: phone.trim(),
    });

    return created(res, result, 'Passenger account created');
  } catch (err) {
    next(err);
  }
}

/**
 * POST /api/auth/register/driver
 */
async function registerDriver(req, res, next) {
  try {
    const { uid } = req.user;
    const { fullName, phone, routeId, plateNumber, vehicleType, licenseNumber } = req.body;

    if (!fullName || !phone) {
      return error(res, 'Full name and phone are required', 400, 'VALIDATION');
    }

    const names = fullName.trim().split(' ');
    const firstName = names[0] || '';
    const lastName = names.length > 1 ? names.slice(1).join(' ') : '';

    const result = await authService.createDriver({
      uid,
      firstName,
      lastName,
      phone: phone.trim(),
      routeId: routeId || '',
      plateNumber: plateNumber || '',
      vehicleType: vehicleType || 'bus',
      licenseNumber: licenseNumber || '',
    });

    return created(res, result, 'Driver account created — pending approval');
  } catch (err) {
    next(err);
  }
}

/**
 * GET /api/auth/profile
 */
async function getProfile(req, res, next) {
  try {
    const { uid } = req.user;
    const userData = await authService.getUserByUid(uid);

    if (!userData) {
      return error(res, 'User not found', 404, 'USER_NOT_FOUND');
    }

    return success(res, userData);
  } catch (err) {
    next(err);
  }
}

module.exports = { login, registerPassenger, registerDriver, getProfile };
