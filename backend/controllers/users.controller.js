const usersService = require('../services/users.service');
const { success, error } = require('../utils/response');

/**
 * GET /api/users/profile
 */
async function getProfile(req, res, next) {
  try {
    const { uid } = req.user;
    const profile = await usersService.getProfile(uid);

    if (!profile) {
      return error(res, 'User not found', 404, 'NOT_FOUND');
    }

    return success(res, profile);
  } catch (err) {
    next(err);
  }
}

/**
 * PUT /api/users/profile
 */
async function updateProfile(req, res, next) {
  try {
    const { uid } = req.user;
    const { firstName, lastName, phone } = req.body;

    const updated = await usersService.updateProfile(uid, {
      firstName, lastName, phone,
    });

    return success(res, updated, 'Profile updated');
  } catch (err) {
    next(err);
  }
}

/**
 * PUT /api/users/settings/language
 */
async function updateLanguage(req, res, next) {
  try {
    const { uid } = req.user;
    const { language } = req.body;

    if (!language || !['en', 'ar'].includes(language)) {
      return error(res, 'Language must be "en" or "ar"', 400, 'VALIDATION');
    }

    await usersService.updateLanguage(uid, language);
    return success(res, { language }, 'Language updated');
  } catch (err) {
    next(err);
  }
}

module.exports = { getProfile, updateProfile, updateLanguage };
