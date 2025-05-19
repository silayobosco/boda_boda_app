const admin = require("firebase-admin");
const { onDocumentCreated, onDocumentUpdated, onDocumentDeleted } = require("firebase-functions/v2/firestore");


// Initialize Firebase Admin SDK if not already initialized (typically done once at the top of your index.js)
if (admin.apps.length === 0) {
  admin.initializeApp();
}

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
 * Send notification to driver via FCM
 * @param {string} driverId - Driver's User ID to notify
 * @param {object} rideDetails - Ride details for the notification payload
 * @return {Promise<void>}
 */
async function sendDriverNotification(driverId, rideDetails) {
  const userDoc = await admin.firestore().collection("users").doc(driverId).get(); // Use 'users' collection
  if (!userDoc.exists) {
    console.warn(`Driver ${driverId} not found, cannot send notification.`);
    return;
  }
  const userData = userDoc.data();
  const fcmToken = userData.fcmToken;

  if (fcmToken) {
    const payload = {
      notification: {
        title: "New Ride Request!",
        body: "You have a new ride assignment. Tap to view details.",
      },
      data: { // Custom data payload for your app to handle
        rideRequestId: rideDetails.id,
        customerId: rideDetails.customerId,
        pickupLat: rideDetails.pickup.latitude.toString(),
        pickupLng: rideDetails.pickup.longitude.toString(),
        dropoffLat: rideDetails.dropoff.latitude.toString(),
        dropoffLng: rideDetails.dropoff.longitude.toString(),
        status: "pending_driver_acceptance", // Status when driver receives it
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      token: fcmToken,
      android: {
        priority: "high", // Sets the FCM message priority for Android devices
        notification: {
          sound: "default", // Specifies the sound for the notification on Android
          click_action: "FLUTTER_NOTIFICATION_CLICK", // Ensures notification tap opens the app correctly
        },
      },
      apns: { // Apple Push Notification Service specific configuration
        payload: {
          aps: {
            sound: "default", // Specifies the sound for the notification on iOS
          },
        },
      },
    };

    try {
      const response = await admin.messaging().send(payload);
      console.log("Successfully sent message:", response);
    } catch (error) {
      console.error("Error sending message:", error);
    }
  } else {
    console.warn(`Driver ${driverId} has no FCM token.`);
  }
}

/**
 * Cloud Function to match ride requests with available drivers
 */
exports.matchRideRequest = onDocumentCreated("/rideRequests/{rideRequestId}", async (event) => {
  console.log("matchRideRequest triggered for ride ID:", event.params.rideRequestId);
  const snap = event.data;
  if (!snap) {
    console.log("No data associated with the event.");
    return;
  }
  const rideRequestData = snap.data();
  const rideRequestId = event.params.rideRequestId;

  // Ensure pickup location is present
  if (!rideRequestData.pickup || !rideRequestData.pickup.latitude || !rideRequestData.pickup.longitude) {
    console.error("Ride request is missing pickup GeoPoint:", rideRequestId, rideRequestData);
    await snap.ref.update({ status: "matching_error_missing_pickup" });
    return;
  }

  const pickupGeoPoint = rideRequestData.pickup;
  const MAX_SEARCH_KIJIWES = 3;
  const kijiwesWithDistance = [];

  // 1. Fetch all Kijiwes and calculate distance
  try {
    const kijiwesSnapshot = await admin.firestore().collection("kijiwe").get();
    kijiwesSnapshot.forEach((doc) => {
      const kijiwe = doc.data();
      // Ensure kijiwe has position and geoPoint
      if (kijiwe.position && kijiwe.position.geoPoint &&
          kijiwe.position.geoPoint.latitude && kijiwe.position.geoPoint.longitude) {
        const distance = calculateDistance(
            pickupGeoPoint.latitude,
            pickupGeoPoint.longitude,
            kijiwe.position.geoPoint.latitude,
            kijiwe.position.geoPoint.longitude,
        );
        kijiwesWithDistance.push({ id: doc.id, name: kijiwe.name, distance, docData: kijiwe });
      } else {
        console.warn(`Kijiwe ${doc.id} is missing valid position.geoPoint data.`);
      }
    });
  } catch (error) {
    console.error("Error fetching Kijiwes:", error);
    await snap.ref.update({ status: "matching_error_kijiwe_fetch" });
    return;
  }

  if (kijiwesWithDistance.length === 0) {
    console.log("No Kijiwes found in the database or none with valid location data.");
    await snap.ref.update({ status: "no_kijiwes_nearby" }); // Or a more specific status
    return;
  }

  // Sort Kijiwes by distance
  kijiwesWithDistance.sort((a, b) => a.distance - b.distance);

  let assignedDriverId = null;
  let assignedKijiweId = null;

  // 2. Iterate through nearest Kijiwes and their queues
  for (let i = 0; i < Math.min(kijiwesWithDistance.length, MAX_SEARCH_KIJIWES); i++) {
    const kijiwe = kijiwesWithDistance[i];
    console.log(`Checking Kijiwe: ${kijiwe.name} (ID: ${kijiwe.id}), Distance: ${kijiwe.distance.toFixed(2)}km`);

    const kijiweQueue = kijiwe.docData.queue || []; // Queue is an array of driver IDs
    if (kijiweQueue.length === 0) {
      console.log(`Kijiwe ${kijiwe.name} queue is empty.`);
      continue; // Try next Kijiwe
    }

    for (const driverId of kijiweQueue) {
      const driverDoc = await admin.firestore().collection("users").doc(driverId).get();

      if (driverDoc.exists) {
        const driverData = driverDoc.data();
        const driverProfile = driverData.driverProfile;
        // Check if driver is online and waiting for a ride
        if (driverProfile && driverProfile.isOnline === true && driverProfile.status === "waitingForRide") {
          // Match found!
          assignedDriverId = driverId;
          assignedKijiweId = kijiwe.id;

          const batch = admin.firestore().batch();
          // Update RideRequest
          await snap.ref.update({
            status: "pending_driver_acceptance",
            assignedDriverId: assignedDriverId,
            kijiweId: assignedKijiweId,
          });
          // Update Driver's profile status
          batch.update(admin.firestore().collection("users").doc(assignedDriverId), {
            "driverProfile.status": "pending_ride_acceptance",
          });
          await batch.commit();

          // Send notifications
          try {
            // Construct rideDetails for notification
            const rideDetailsForNotification = { ...rideRequestData, id: rideRequestId };
            await sendDriverNotification(assignedDriverId, rideDetailsForNotification);
            console.log(`Assigned ride ${rideRequestId} to driver ${assignedDriverId} from Kijiwe ${assignedKijiweId}`);
            // TODO: Send customer notification that a driver is being assigned
          } catch (error) {
            console.error("Error sending notifications:", error);
          }
          break; // Exit the inner loop once a driver is assigned
        }
      }
    }
    if (assignedDriverId) {
      break; // Exit the Kijiwe loop once a driver is assigned
    }
  }

  // 3. No match found after searching
  if (!assignedDriverId) {
    console.log(`No available driver found for ride ${rideRequestId} after checking ` +
        `${Math.min(kijiwesWithDistance.length, MAX_SEARCH_KIJIWES)} Kijiwes.`);
    const statusUpdate = { status: "no_drivers_available" };
    if (kijiwesWithDistance.length > 0 && kijiwesWithDistance[0].id) {
      // If at least one Kijiwe was checked, assign its ID to the ride request
      statusUpdate.kijiweId = kijiwesWithDistance[0].id;
    }
    await snap.ref.update(statusUpdate);
    // TODO: Notify customer about no available drivers
  }
});

/**
 * Cloud Function to handle ride request updates
 */
exports.updateRideRequest = onDocumentUpdated("/RideRequests/{rideRequestId}", async (event) => {
  // This function might need more specific logic based on which status changes you want to react to.
  // For now, it's a placeholder.
  const beforeData = event.data.before.data();
  const afterData = event.data.after.data();

  if (beforeData.status !== afterData.status) {
    console.log(`Ride request ${event.params.rideRequestId} status changed from ${beforeData.status} ` +
        `to ${afterData.status}`);
    if (afterData.status === "completed") {
      if (afterData.assignedDriverId) {
        // Example: Send a generic completion notification to driver
        // You might want a more specific payload for completion
        // await sendDriverNotification(afterData.assignedDriverId, {
        //  id: event.params.rideRequestId, /* other details */ });
        console.log(`Ride ${event.params.rideRequestId} completed by driver ${afterData.assignedDriverId}.`);
      }
      // TODO: Notify customer about ride completion
    }
  }
});

/**
 * Cloud Function to handle ride request deletions
 * Note: Your security rules prevent deletion, so this might not trigger often from client.
 */
exports.deleteRideRequest = onDocumentDeleted("/RideRequests/{rideRequestId}", async (event) => {
  const deletedData = event.data.data(); // Get the data of the deleted document
  console.log(`Ride request ${event.params.rideRequestId} deleted. Data:`, deletedData);
  // if (deletedData && deletedData.assignedDriverId) {
  //   // Notify driver about ride request deletion
  //   // await sendDriverNotification(deletedData.assignedDriverId, {
  //  id: event.params.rideRequestId, /* other details */ });
  // }
});

/**
 * Cloud Function to handle Kijiwe queue updates
 * @type {functions.CloudFunction<functions.firestore.DocumentSnapshot>}
 * This function needs to be adapted because KijiweQueues collection is not used.
 * Queue is now an array within the Kijiwe document.
 */
// exports.updateKijiweQueue = onDocumentUpdated("/KijiweQueues/{kijiweId}", async (event) => {
//   // ... logic would need to change to monitor /kijiwe/{kijiweId} and compare the 'queue' array.
// });

exports.onKijiweUpdate = onDocumentUpdated("/kijiwe/{kijiweId}", async (event) => {
  const beforeData = event.data.before.data();
  const afterData = event.data.after.data();

  // Example: Detect changes in the queue array
  const beforeQueue = beforeData.queue || [];
  const afterQueue = afterData.queue || [];

  if (JSON.stringify(beforeQueue) !== JSON.stringify(afterQueue)) {
    console.log(`Kijiwe ${event.params.kijiweId} queue updated.`);
    // You could add logic here to notify drivers if they are added/removed,
    // but this might be noisy if client already handles this.
    // For example, finding the difference in drivers:
    // const addedDrivers = afterQueue.filter(d => !beforeQueue.includes(d));
    // const removedDrivers = beforeQueue.filter(d => !afterQueue.includes(d));
  }

  // Example: Detect changes in adminId (if you had a leaderId field, you'd use that)
  if (beforeData.adminId !== afterData.adminId) {
    console.log(`Kijiwe ${event.params.kijiweId} admin changed from ${beforeData.adminId} ` +
        `to ${afterData.adminId}.`);
    // if (afterData.adminId) {
    //   await sendDriverNotification(afterData.adminId, {
    //  message: `You are now the admin of Kijiwe ${afterData.name || event.params.kijiweId}.` });
    // }
  }
});