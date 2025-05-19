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
  onKijiweUpdate, // Changed from updateKijiwe to match the export from matchRideRequest.js
} = require("./matchRideRequest");

// Export functions
exports.matchRideRequest = matchRideRequest;
exports.updateRideRequest = updateRideRequest;
exports.deleteRideRequest = deleteRideRequest;
exports.onKijiweUpdate = onKijiweUpdate; // Exporting the renamed function
