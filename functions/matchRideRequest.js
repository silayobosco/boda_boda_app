const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

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
 * Helper function to find the nearest Kijiwes
 * @param {object} pickupLocation - Pickup location with latitude/longitude
 * @param {string} currentKijiweId - Current Kijiwe ID to exclude
 * @param {number} maxResults - Maximum results to return
 * @return {Promise<Array<string>>} Array of nearest Kijiwe IDs
 */
async function findNearestKijiwes(
    pickupLocation,
    currentKijiweId,
    maxResults = 3,
) {
  const kijiwesSnapshot = await admin.firestore().collection("Kijiwes").get();
  const kijiwes = [];
  kijiwesSnapshot.forEach((doc) => {
    const kijiwe = doc.data();
    if (doc.id !== currentKijiweId) {
      // Don't include the current Kijiwe
      const distance = calculateDistance(
          pickupLocation.latitude,
          pickupLocation.longitude,
          kijiwe.location.latitude,
          kijiwe.location.longitude,
      );
      kijiwes.push({id: doc.id, distance});
    }
  });

  kijiwes.sort((a, b) => a.distance - b.distance); // Sort by distance
  return kijiwes.slice(0, maxResults).map((k) => k.id); // Return only the IDs
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
 * @type {functions.CloudFunction<functions.firestore.DocumentSnapshot>}
 */
exports.matchRideRequest = functions.firestore
    .document("/RideRequests/{rideRequestId}")
    .onCreate(async (snap, context) => {
      const rideRequestData = snap.data();
      let currentKijiweId = rideRequestData.kijiweId;
      let searchCount = 0;
      const MAX_SEARCH_KIJIWES = 3; // Limit the search

      while (searchCount < MAX_SEARCH_KIJIWES && currentKijiweId) {
        const kijiweQueueRef = admin
            .firestore()
            .collection("KijiweQueues")
            .doc(currentKijiweId);
        const kijiweQueueDoc = await kijiweQueueRef.get();

        if (kijiweQueueDoc.exists) {
          const driverIds = kijiweQueueDoc.data().driverIds || [];
          for (let i = 0; i < driverIds.length; i++) {
            // Explicitly iterate by index
            const userId = driverIds[i]; // (from Users collection)
            const userDoc = await admin.firestore()
                .collection("Users").doc(userId).get();

            if (
              userDoc.exists &&
              userDoc.data().role.includes("Driver") &&
              userDoc.data().driverDetails &&
              userDoc.data().driverDetails.available
            ) {
              // Match found!
              await snap.ref.update({
                status: "accepted",
                assignedDriverId: userId,
              });

              // Remove driver from queue (atomically)
              await kijiweQueueRef.update({
                driverIds: admin.firestore.FieldValue.arrayRemove(userId),
              });

              // Send notifications (using sendDriverNotification from above)
              try {
                await sendDriverNotification(
                    userId,
                    "You have a new ride request!",
                );
                // ... send customer notification (implement this function)
              } catch (error) {
                console.error("Error sending notifications:", error);
              }

              return; // Exit the function
            }
          }

          // No match in this Kijiwe - Notify Leader
          const kijiweDoc = await admin.firestore()
              .collection("Kijiwes")
              .doc(currentKijiweId)
              .get();
          if (kijiweDoc.exists) {
            const kijiweLeaderId = kijiweDoc.data().leaderId;
            if (kijiweLeaderId) {
              try {
                await sendDriverNotification(
                    kijiweLeaderId,
                    "No driver available for a ride request at your Kijiwe!",
                );
              } catch (error) {
                console.error("Error sending leader notification:", error);
              }
            }
          }

          // Calculate next nearest Kijiwe
          const nearestKijiwes = await findNearestKijiwes(
              rideRequestData.pickupLocation,
              currentKijiweId,
          );
          currentKijiweId =
            nearestKijiwes.length > 0 ? nearestKijiwes[0] : null;

          if (currentKijiweId) {
            searchCount++;
          } else {
            break; // No more Kijiwes to search
          }
        } else {
          break; // Kijiwe doesn't exist (error condition)
        }
      }

      // No match found after searching all Kijiwes
      await snap.ref.update({status: "pending"});
      // ... notify customer
    });

/**
 * Cloud Function to handle ride request updates
 * @type {functions.CloudFunction<functions.firestore.DocumentSnapshot>}
 */
exports.updateRideRequest = functions.firestore
    .document("/RideRequests/{rideRequestId}")
    .onUpdate(async (change, context) => {
      const beforeData = change.before.data();
      const afterData = change.after.data();

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
 * @type {functions.CloudFunction<functions.firestore.DocumentSnapshot>}
 */
exports.deleteRideRequest = functions.firestore
    .document("/RideRequests/{rideRequestId}")
    .onDelete(async (snap, context) => {
      const rideRequestData = snap.data();
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
exports.updateKijiweQueue = functions.firestore
    .document("/KijiweQueues/{kijiweId}")
    .onUpdate(async (change, context) => {
      const beforeData = change.before.data();
      const afterData = change.after.data();

      if (beforeData.driverIds.length !== afterData.driverIds.length) {
        // Handle driver queue changes
        if (afterData.driverIds.length > beforeData.driverIds.length) {
          // New driver added to the queue
          const newDriverId = afterData.driverIds[
              afterData.driverIds.length - 1
          ];
          await sendDriverNotification(
              newDriverId,
              "You have been added to the Kijiwe queue!",
          );
        } else {
          // Driver removed from the queue
          const removedDriverId = beforeData.driverIds[
              beforeData.driverIds.length - 1
          ];
          await sendDriverNotification(
              removedDriverId,
              "You have been removed from the Kijiwe queue!",
          );
        }
      }
    });

/**
 * Cloud Function to handle Kijiwe updates
 * @type {functions.CloudFunction<functions.firestore.DocumentSnapshot>}
 */
exports.updateKijiwe = functions.firestore
    .document("/Kijiwes/{kijiweId}")
    .onUpdate(async (change, context) => {
      const beforeData = change.before.data();
      const afterData = change.after.data();

      if (beforeData.leaderId !== afterData.leaderId) {
        // Handle Kijiwe leader change
        await sendDriverNotification(
            afterData.leaderId,
            "You are now the leader of this Kijiwe!",
        );
      }
    });