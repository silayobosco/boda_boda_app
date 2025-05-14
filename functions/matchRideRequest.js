const { onDocumentCreated, onDocumentUpdated, onDocumentDeleted } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

/**
 * Helper function to calculate distance (Haversine formula - simplified)
 * @param {number} lat1 - Latitude of point 1
 * @param {number} lon1 - Longitude of point 1
 * @param {number} lat2 - Latitude of point 2
 * @param {number} lon2 - Longitude of point 2
 * @return {number} Distance in kilometers
 */
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371; // Radius of the Earth in kilometers
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * Math.PI / 180) *
    Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon / 2) *
    Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  const d = R * c;
  return d; // Distance in kilometers
}

/**
 * Helper function to find the nearest Kijiwes based on an address.
 * This function uses the Geocoding API to convert the address to coordinates
 * and then finds the nearest Kijiwes.
 * @param {string} pickupAddress - Pickup address
 * @param {number} maxResults - Maximum results to return
 * @return {Promise<Array<string>>} Array of nearest Kijiwe IDs
 */
async function findNearestKijiwesByAddress(pickupAddress, maxResults = 3) {
  try {
    const geocodeResult = await admin.firestore().collection("geocoding").doc(pickupAddress).get();
    let pickupLocation;
    if (geocodeResult.exists && geocodeResult.data() && geocodeResult.data().latitude && geocodeResult.data().longitude) {
      pickupLocation = {
        latitude: geocodeResult.data().latitude,
        longitude: geocodeResult.data().longitude,
      };
    } else {
      // Geocoding API call to get coordinates from address
      const apiKey = process.env.GOOGLE_MAPS_API_KEY; // Ensure you have this environment variable set
      if (!apiKey) {
        console.error("Google Maps API key not found in environment variables.");
        return [];
      }
      const geocodingApiUrl = `https://maps.googleapis.com/maps/api/geocode/json?address=${encodeURIComponent(pickupAddress)}&key=${apiKey}`;
      const response = await fetch(geocodingApiUrl);
      const data = await response.json();

      if (data.results && data.results.length > 0) {
        const location = data.results[0].geometry.location;
        pickupLocation = {
          latitude: location.lat,
          longitude: location.lng,
        };
        // Cache the geocoding result
        await admin.firestore().collection("geocoding").doc(pickupAddress).set(pickupLocation, { merge: true });
      } else {
        console.error("Geocoding failed for address:", pickupAddress, data.status, data.error_message);
        return [];
      }
    }

    const kijiwesSnapshot = await admin.firestore().collection("Kijiwes").get();
    const kijiwes = [];
    kijiwesSnapshot.forEach((doc) => {
      const kijiwe = doc.data();
      if (kijiwe.location && pickupLocation) {
        const distance = calculateDistance(
          pickupLocation.latitude,
          pickupLocation.longitude,
          kijiwe.location.latitude,
          kijiwe.location.longitude,
        );
        kijiwes.push({ id: doc.id, distance });
      }
    });

    kijiwes.sort((a, b) => a.distance - b.distance);
    return kijiwes.slice(0, maxResults).map((k) => k.id);
  } catch (error) {
    console.error("Error finding nearest Kijiwes by address:", error);
    return [];
  }
}

/**
 * Send notification to driver via FCM
 * @param {string} userId - User ID to notify
 * @param {string} message - Notification message
 * @return {Promise<void>}
 */
async function sendDriverNotification(userId, message) {
  const userDoc = await admin.firestore().collection("Users").doc(userId).get();
  if (!userDoc.exists) {
    console.warn(`User ${userId} not found, cannot send notification.`);
    return;
  }
  const userData = userDoc.data();
  const fcmToken = userData.fcmToken;

  if (fcmToken) {
    const payload = {
      notification: {
        title: "Ride Request Update",
        body: message,
      },
      token: fcmToken,
    };

    try {
      const response = await admin.messaging().send(payload);
      console.log("Successfully sent message:", response);
    } catch (error) {
      console.error("Error sending message:", error);
    }
  } else {
    console.warn(`User ${userId} has no FCM token.`);
  }
}

/**
 * Cloud Function to match ride requests with available drivers
 */
exports.matchRideRequest = onDocumentCreated("/RideRequests/{rideRequestId}", async (event) => {
  const snap = event.data;
  const rideRequestData = snap.data();
  const pickupAddress = rideRequestData.pickupAddress;
  let searchCount = 0;
  const MAX_SEARCH_KIJIWES = 3;

  const nearestKijiwes = await findNearestKijiwesByAddress(pickupAddress, MAX_SEARCH_KIJIWES);
  let kijiweIndex = 0;
  let assignedDriverId = null;

  while (kijiweIndex < nearestKijiwes.length && !assignedDriverId) {
    const currentKijiweId = nearestKijiwes[kijiweIndex];
    const kijiweQueueRef = admin.firestore().collection("KijiweQueues").doc(currentKijiweId);
    const kijiweQueueDoc = await kijiweQueueRef.get();

    if (kijiweQueueDoc.exists) {
      const driverIds = kijiweQueueDoc.data().driverIds || [];
      for (const userId of driverIds) {
        const userDoc = await admin.firestore().collection("Users").doc(userId).get();

        if (
          userDoc.exists &&
          userDoc.data().role.includes("Driver") &&
          userDoc.data().driverDetails &&
          userDoc.data().driverDetails.available
        ) {
          // Match found!
          assignedDriverId = userId;
          await snap.ref.update({
            status: "accepted",
            assignedDriverId: userId,
          });

          // Remove driver from queue
          await kijiweQueueRef.update({
            driverIds: admin.firestore.FieldValue.arrayRemove(userId),
          });

          // Send notifications
          try {
            await sendDriverNotification(userId, "You have a new ride request!");
            // ... send customer notification (implement this function)
          } catch (error) {
            console.error("Error sending notifications:", error);
          }
          break; // Exit the inner loop once a driver is assigned
        }
      }

       }
    kijiweIndex++;
  }

  // No match found after searching nearest Kijiwes
  if (!assignedDriverId) {
    await snap.ref.update({ status: "pending" });
    // ... notify customer about no available drivers
  }
});

/**
 * Cloud Function to handle ride request updates
 */
exports.updateRideRequest = onDocumentUpdated("/RideRequests/{rideRequestId}", async (event) => {
  const beforeData = event.data.before.data();
  const afterData = event.data.after.data();

  if (beforeData.status !== afterData.status) {
    // Handle status change
    if (afterData.status === "completed") {
      // Notify customer and driver about ride completion
      await sendDriverNotification(
          afterData.assignedDriverId,
          "Your ride has been completed!",
      );
      // ... notify customer
    }
  }
});

/**
 * Cloud Function to handle ride request deletions
 */
exports.deleteRideRequest = onDocumentDeleted("/RideRequests/{rideRequestId}", async (event) => {
  const rideRequestData = event.data;
  const assignedDriverId = rideRequestData.assignedDriverId;

  if (assignedDriverId) {
    // Notify driver about ride request deletion
    await sendDriverNotification(
        assignedDriverId,
        "Your ride request has been deleted!",
    );
  }
});

/**
 * Cloud Function to handle Kijiwe queue updates
 * @type {functions.CloudFunction<functions.firestore.DocumentSnapshot>}
 */
exports.updateKijiweQueue = onDocumentUpdated("/KijiweQueues/{kijiweId}", async (event) => {
  const beforeData = event.data.before.data();
  const afterData = event.data.after.data();

  if (beforeData.driverIds.length !== afterData.driverIds.length) {
    // Handle driver queue changes
    if (afterData.driverIds.length > beforeData.driverIds.length) {
      // New driver added to the queue
      const newDriverId = afterData.driverIds[afterData.driverIds.length - 1];
      await sendDriverNotification(
          newDriverId,
          "You have been added to the Kijiwe queue!",
      );
    } else {
      // Driver removed from the queue
      const removedDriverId = beforeData.driverIds[beforeData.driverIds.length - 1];
      await sendDriverNotification(
          removedDriverId,
          "You have been removed from the Kijiwe queue!",
      );
    }
  }
});

exports.updateKijiwe = onDocumentUpdated("/Kijiwes/{kijiweId}", async (event) => {
  const beforeData = event.data.before.data();
  const afterData = event.data.after.data();

  if (beforeData.leaderId !== afterData.leaderId) {
    // Handle Kijiwe leader change
    await sendDriverNotification(
        afterData.leaderId,
        "You are now the leader of this Kijiwe!",
    );
  }
});
// Add a blank line here