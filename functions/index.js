/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const admin = require("firebase-admin");
admin.initializeApp();

// Import functions from matchRideRequest.js
const {
  matchRideRequest,
  updateRideRequest,
  deleteRideRequest,
  updateKijiweQueue,
  updateKijiwe,
} = require("./matchRideRequest");

// Export functions
exports.matchRideRequest = matchRideRequest;
exports.updateRideRequest = updateRideRequest;
exports.deleteRideRequest = deleteRideRequest;
exports.updateKijiweQueue = updateKijiweQueue;
exports.updateKijiwe = updateKijiwe;
