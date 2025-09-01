const admin = require("firebase-admin");
const { HttpsError, onCall } = require("firebase-functions/v2/https");
const { logger } = require("firebase-functions");

if (admin.apps.length === 0) {
  admin.initializeApp();
}

/**
 * Deletes a user's account from Firestore and Firebase Authentication.
 */
exports.deleteUserAccount = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "The function must be called while authenticated.");
  }

  logger.log(`User ${uid} has requested account deletion.`);

  try {
    // Delete user document from Firestore
    await admin.firestore().collection("users").doc(uid).delete();
    logger.log(`Successfully deleted Firestore document for user ${uid}.`);

    // Delete user from Firebase Authentication
    await admin.auth().deleteUser(uid);
    logger.log(`Successfully deleted user ${uid} from Firebase Authentication.`);

    // TODO: Add logic to clean up other user-related data if necessary (e.g., profile images from Storage).

    return { success: true, message: "Account deleted successfully." };
  } catch (error) {
    logger.error("Error deleting account for user ${uid}:", error);
    if (error.code === "auth/user-not-found") {
      logger.warn("User ${uid} was not found in Firebase Auth, but Firestore doc was deleted.");
      return { success: true, message: "Account data cleared." };
    }
    throw new HttpsError("internal", "An error occurred while deleting your account. Please contact support.", error.message);
  }
});