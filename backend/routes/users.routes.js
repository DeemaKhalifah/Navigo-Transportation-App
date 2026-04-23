const express = require('express');
const router = express.Router();
const { authMiddleware } = require('../middleware/auth');
const usersController = require('../controllers/users.controller');

// GET /api/users/profile — get current user profile
router.get('/profile', authMiddleware, usersController.getProfile);

// PUT /api/users/profile — update current user profile
router.put('/profile', authMiddleware, usersController.updateProfile);

// PUT /api/users/settings/language — update language preference
router.put('/settings/language', authMiddleware, usersController.updateLanguage);

module.exports = router;
