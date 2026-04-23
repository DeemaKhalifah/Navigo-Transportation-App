const admin = require('firebase-admin');

/**
 * Initialize Firebase Admin SDK.
 * 
 * Option 1: Use service account JSON file (recommended for local dev).
 *   Set GOOGLE_APPLICATION_CREDENTIALS env var to the path of
 *   your service account key JSON file.
 * 
 * Option 2: Use default credentials (for deployed environments
 *   like Cloud Functions, Cloud Run, etc.)
 */
function initializeFirebase() {
  if (admin.apps.length > 0) return;

  try {
    if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
      // Option 1: Service account key file
      admin.initializeApp({
        credential: admin.credential.applicationDefault(),
      });
      console.log('Firebase Admin initialized with service account credentials');
    } else {
      // Option 2: Default credentials (deployed environments)
      admin.initializeApp();
      console.log('Firebase Admin initialized with default credentials');
    }
  } catch (error) {
    console.error('Firebase Admin initialization error:', error.message);
    console.log('Continuing without Firebase — set GOOGLE_APPLICATION_CREDENTIALS in .env');
  }
}

/**
 * Get Firestore instance.
 */
function getFirestore() {
  return admin.firestore();
}

/**
 * Get Auth instance.
 */
function getAuth() {
  return admin.auth();
}

module.exports = { initializeFirebase, getFirestore, getAuth };
