const { getFirestore } = require('../config/firebase');

const USERS = 'users';

/**
 * Get user profile.
 */
async function getProfile(uid) {
  const db = getFirestore();
  const doc = await db.collection(USERS).doc(uid).get();

  if (!doc.exists) return null;

  const data = doc.data();
  return {
    uid: doc.id,
    firstName: data.firstName || '',
    lastName: data.lastName || '',
    phone: data.phone || '',
    role: data.role || 'passenger',
    image: data.image || null,
    isVerified: data.isVerified || false,
    language: data.language || 'en',
  };
}

/**
 * Update user profile.
 */
async function updateProfile(uid, { firstName, lastName, phone }) {
  const db = getFirestore();
  const updates = {};

  if (firstName !== undefined) updates.firstName = firstName;
  if (lastName !== undefined) updates.lastName = lastName;
  if (phone !== undefined) updates.phone = phone;
  updates.updatedAt = new Date();

  await db.collection(USERS).doc(uid).update(updates);

  return { uid, ...updates };
}

/**
 * Update user language preference.
 */
async function updateLanguage(uid, language) {
  const db = getFirestore();
  await db.collection(USERS).doc(uid).update({
    language,
    updatedAt: new Date(),
  });
}

module.exports = { getProfile, updateProfile, updateLanguage };
