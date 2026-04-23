const express = require('express');
const router = express.Router();
const { authMiddleware } = require('../middleware/auth');
const authController = require('../controllers/auth.controller');

// POST /api/auth/login — verify token and return user profile + role
router.post('/login', authMiddleware, authController.login);

// POST /api/auth/register/passenger — register a new passenger
router.post('/register/passenger', authMiddleware, authController.registerPassenger);

// POST /api/auth/register/driver — register a new driver
router.post('/register/driver', authMiddleware, authController.registerDriver);

// GET /api/auth/profile — get current user profile
router.get('/profile', authMiddleware, authController.getProfile);

module.exports = router;
