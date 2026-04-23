const { getAuth } = require('../config/firebase');

/**
 * Authentication middleware.
 * Verifies the Firebase ID token from the Authorization header.
 * Attaches the decoded user info to req.user.
 */
async function authMiddleware(req, res, next) {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({
      success: false,
      error: 'No authentication token provided',
      code: 'AUTH_MISSING',
    });
  }

  const token = authHeader.split('Bearer ')[1];

  try {
    const decodedToken = await getAuth().verifyIdToken(token);
    req.user = {
      uid: decodedToken.uid,
      email: decodedToken.email || null,
      phone: decodedToken.phone_number || null,
    };
    next();
  } catch (error) {
    console.error('Token verification failed:', error.message);
    return res.status(401).json({
      success: false,
      error: 'Invalid or expired authentication token',
      code: 'AUTH_INVALID',
    });
  }
}

module.exports = { authMiddleware };
