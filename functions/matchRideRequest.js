const admin = require("firebase-admin");
const { HttpsError, onCall } = require("firebase-functions/v2/https"); // HTTP triggers
const { onDocumentCreated, onDocumentUpdated, onDocumentDeleted } = require("firebase-functions/v2/firestore"); // Firestore triggers
const { logger } = require("firebase-functions"); // For better logging

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
 * @param {string} targetUserId - The User ID of the recipient.
 * @param {string} title - The title of the notification.
 * @param {string} body - The body/content of the notification.
 * @param {object} dataPayload - Additional data to send with the notification.
 * @return {Promise<void>}
 */
async function sendFCMNotification(targetUserId, title, body, dataPayload) {
  const targetUserDoc = await admin.firestore().collection("users").doc(targetUserId).get(); // Renamed to avoid conflict
  if (!targetUserDoc.exists) {
    logger.warn(`User ${targetUserId} not found, cannot send notification.`);
    return;
  }
  const targetUserData = targetUserDoc.data();
  const fcmToken = targetUserData.fcmToken;

  if (fcmToken) {
    // Ensure all values in dataPayload are strings
    const stringifiedDataPayload = {};
    for (const key in dataPayload) {
      if (Object.prototype.hasOwnProperty.call(dataPayload, key)) {
        // Convert non-string values to string. Handle null/undefined gracefully.
        // You might need more specific conversions for complex objects (e.g., JSON.stringify for nested objects/arrays)
        stringifiedDataPayload[key] = dataPayload[key] == null ? "" : String(dataPayload[key]);
      }
    }

    const payload = {
      notification: {
        title: title,
        body: body,
      },
      data: stringifiedDataPayload, // Use the stringified version
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
      logger.log("Successfully sent FCM message to", targetUserId, "Response:", response);
    } catch (error) {
      logger.error("Error sending FCM message to", targetUserId, error);
    }
  } else {
    logger.warn(`User ${targetUserId} has no FCM token.`);
  }
}

/**
 * Cloud Function to match ride requests with available drivers
 */
exports.matchRideRequest = onDocumentCreated("/rideRequests/{rideRequestId}", async (event) => {
  logger.log("matchRideRequest triggered for ride ID:", event.params.rideRequestId);
  const snap = event.data;
  if (!snap) {
    logger.log("No data associated with the event.");
    return;
  }
  const rideRequestData = snap.data();
  const rideRequestId = event.params.rideRequestId;

  // --- Denormalize Customer Data onto Ride Request ---
  const customerId = rideRequestData.customerId;
  let customerName = "Customer";
  let customerProfileImageUrl = null;
  let customerGender = "Unknown";
  let customerAgeRange = "Unknown";
  let customerAverageRating = 0.0;

  if (customerId) {
    const customerDoc = await admin.firestore().collection("users").doc(customerId).get();
    if (customerDoc.exists) {
      const customerData = customerDoc.data();
      customerName = customerData.name || "Customer";
      customerProfileImageUrl = customerData.profileImageUrl || null;
      customerGender = customerData.gender || "Unknown";

      if (customerData.dob) {
        // DOB can be a string or a Firestore Timestamp. Handle both.
        let birthDate;
        if (customerData.dob instanceof admin.firestore.Timestamp) {
          birthDate = customerData.dob.toDate();
        } else if (typeof customerData.dob === "string") {
          birthDate = new Date(customerData.dob);
        }

        if (birthDate && !isNaN(birthDate.getTime())) { // Check if birthDate is valid
          const currentDate = new Date();
          let age = currentDate.getFullYear() - birthDate.getFullYear();
          const m = currentDate.getMonth() - birthDate.getMonth();
          if (m < 0 || (m === 0 && currentDate.getDate() < birthDate.getDate())) {
            age--;
          }
          if (age >= 0) {
            customerAgeRange = `${Math.floor(age / 10) * 10}s`;
          }
        } // End of valid birthDate check
      }

      const customerProfile = customerData.customerProfile;
      if (customerProfile) {
        const sumOfRatings = customerProfile.sumOfRatingsReceived || 0;
        const totalRatings = customerProfile.totalRatingsReceivedCount || 0;
        if (totalRatings > 0) {
          customerAverageRating = sumOfRatings / totalRatings;
        }
      }
    }
  }

  const detailsParts = [];
  if (customerGender !== "Unknown") {
    detailsParts.push(customerGender); // Just the value
  }
  if (customerAgeRange !== "Unknown") {
    detailsParts.push(customerAgeRange); // Just the value, e.g., "20s"
  }
  if (customerAverageRating > 0.0) { // Only show rating if it's not the default 0.0
    detailsParts.push(`Rating: ${customerAverageRating.toFixed(1)}`);
  }
  let customerDetailsString;
  if (detailsParts.length === 0) {
    customerDetailsString = "Customer details not available.";
  } else {
    customerDetailsString = detailsParts.join(", ");
  }

  const denormalizedCustomerData = {
    customerName: customerName,
    customerProfileImageUrl: customerProfileImageUrl,
    customerDetails: customerDetailsString,
  };
  // Update the ride request with these denormalized details
  await snap.ref.update(denormalizedCustomerData);
  // --- End Denormalization ---

  // --- Calculate Estimated Fare (for driver notification) ---
  let estimatedFare = 0;
  let fareConfig;
  try {
    const fareConfigDoc = await admin.firestore().collection("appConfiguration").doc("fareSettings").get();
    if (!fareConfigDoc.exists) {
      logger.error("Fare configuration not found in Firestore for estimated fare calculation!");
      // Fallback to default values
      fareConfig = { minimumFare: 1250, startingFare: 300, farePerKilometer: 350, farePerMinuteDriving: 60, farePerMinuteWaiting: 60, commissionRate: 0.20, roundingIncrement: 500, currency: "TZS" };
    } else {
      fareConfig = fareConfigDoc.data();
    }
  } catch (error) {
    logger.error("Error fetching fare configuration for estimated fare:", error);
    // Fallback to default values
    fareConfig = { minimumFare: 1250, startingFare: 300, farePerKilometer: 350, farePerMinuteDriving: 60, farePerMinuteWaiting: 60, commissionRate: 0.20, roundingIncrement: 500, currency: "TZS" };
  }

  const estimatedDistanceKm = rideRequestData.estimatedDistanceKm || 0;
  const estimatedDurationMinutes = rideRequestData.estimatedDurationMinutes || 0;

  const baseFare = fareConfig.startingFare || 0;
  const perKmRate = fareConfig.farePerKilometer || 0;
  const perMinRate = fareConfig.farePerMinuteDriving || 0; // Use driving rate for estimation
  const minFare = fareConfig.minimumFare || 0;
  const roundingInc = fareConfig.roundingIncrement || 0;

  let calculatedEstimatedFare = baseFare + (estimatedDistanceKm * perKmRate) + (estimatedDurationMinutes * perMinRate);
  calculatedEstimatedFare = Math.max(calculatedEstimatedFare, minFare);

  // Apply rounding (same logic as customer app)
  if (roundingInc > 0) {
    const base = Math.floor(calculatedEstimatedFare / roundingInc) * roundingInc;
    const diff = calculatedEstimatedFare - base;
    if (diff === 0) {
      estimatedFare = calculatedEstimatedFare;
    } else if (diff <= roundingInc / 2 && roundingInc / 2 > 0) {
      estimatedFare = base + (roundingInc / 2);
    } else {
      estimatedFare = base + roundingInc;
    }
  } else {
    estimatedFare = calculatedEstimatedFare;
  }
  // --- End of function's own estimated fare calculation ---

  // Determine the fare to send in the notification
  // Prioritize customer's calculation if available and valid, otherwise use the function's calculation.
  let fareToSendToDriverInNotification;
  if (rideRequestData.customerCalculatedEstimatedFare != null && typeof rideRequestData.customerCalculatedEstimatedFare === "number") {
    fareToSendToDriverInNotification = rideRequestData.customerCalculatedEstimatedFare.toFixed(2);
  } else {
    fareToSendToDriverInNotification = estimatedFare.toFixed(2); // 'estimatedFare' is the functionCalculatedEstimatedFare
  }
  // --- End Estimated Fare Calculation ---
  // Ensure pickup location is present
  if (!rideRequestData.pickup || !rideRequestData.pickup.latitude || !rideRequestData.pickup.longitude) {
    logger.error("Ride request is missing pickup GeoPoint:", rideRequestId, rideRequestData);
    await snap.ref.update({ status: "matching_error_missing_pickup" });
    return;
  }
  const pickupGeoPoint = rideRequestData.pickup;
  const MAX_SEARCH_KIJIWES = 7;
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
        logger.warn(`Kijiwe ${doc.id} is missing valid position.geoPoint data.`);
      }
    });
  } catch (error) {
    logger.error("Error fetching Kijiwes:", error);
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
    logger.log(`Checking Kijiwe: ${kijiwe.name} (ID: ${kijiwe.id}), Distance: ${kijiwe.distance.toFixed(2)}km`);

    const kijiweQueue = kijiwe.docData.queue || []; // Queue is an array of driver IDs
    if (kijiweQueue.length === 0) {
      logger.log(`Kijiwe ${kijiwe.name} queue is empty.`);
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
          const rideRequestRef = snap.ref; // Reference to the current rideRequest document
          const driverUserRef = admin.firestore().collection("users").doc(assignedDriverId);

          // Update RideRequest
          batch.update(rideRequestRef, {
            status: "pending_driver_acceptance", // This status indicates it's offered to a driver
            driverId: assignedDriverId, // Use 'driverId' as per your structure
            kijiweId: assignedKijiweId,
          });
          // Update Driver's profile status
          batch.update(driverUserRef, {
            "driverProfile.status": "pending_ride_acceptance",
          });
          await batch.commit();

          // Send notifications
          try {
            const rideDetailsForNotification = {
              rideRequestId: rideRequestId,
              status: "pending_driver_acceptance",
              click_action: "FLUTTER_NOTIFICATION_CLICK",
              customerId: customerId,
              customerName: customerName,
              customerProfileImageUrl: customerProfileImageUrl || "",
              customerDetails: customerDetailsString,
              pickupAddressName: rideRequestData.pickupAddressName || "",
              dropoffAddressName: rideRequestData.dropoffAddressName || "",
              pickupLat: rideRequestData.pickup.latitude.toString(),
              pickupLng: rideRequestData.pickup.longitude.toString(),
              dropoffLat: rideRequestData.dropoff.latitude.toString(),
              dropoffLng: rideRequestData.dropoff.longitude.toString(),
              customerNoteToDriver: rideRequestData.customerNoteToDriver || "",
              estimatedFare: fareToSendToDriverInNotification, // Send the determined estimated fare
            };

            // Handle stops: stringify the array of stops or critical parts of it
            // For simplicity, let's stringify the whole stops array.
            // Your client will need to parse this JSON string.
            if (rideRequestData.stops && Array.isArray(rideRequestData.stops)) {
              rideDetailsForNotification.stops = JSON.stringify(rideRequestData.stops.map((stop) => ({
                ...stop, // Keep other stop properties
                location: `${stop.location.latitude},${stop.location.longitude}`, // Convert GeoPoint to string
              })));
            }
            // ... and for dropoff and stops if they are GeoPoints
            await sendFCMNotification(assignedDriverId, "New Ride Request!", "You have a new ride assignment.", rideDetailsForNotification);
            logger.log(`Assigned ride ${rideRequestId} to driver ${assignedDriverId} from Kijiwe ${assignedKijiweId}`);
            // TODO: Send customer notification that a driver is being assigned
          } catch (error) {
            logger.error("Error sending notifications:", error);
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
    logger.log(`No available driver found for ride ${rideRequestId} after checking ` +
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
 * Callable Cloud Function for drivers to manage ride actions.
 */
exports.handleDriverRideAction = onCall(async (request) => {
  const driverUid = request.auth?.uid;
  if (!driverUid) {
    throw new HttpsError("unauthenticated", "The function must be called while authenticated.");
  }

  const { rideRequestId, action, rating, comment } = request.data; // 'action' can be 'accept', 'decline', 'arrived', 'start', 'complete', 'cancel', 'rateCustomer'

  if (!rideRequestId || !action) {
    throw new HttpsError("invalid-argument", "Missing rideRequestId or action.");
  }

  const driverDoc = await admin.firestore().collection("users").doc(driverUid).get();
  if (!driverDoc.exists || driverDoc.data().role !== "Driver") {
    throw new HttpsError("permission-denied", "User is not authorized to perform this action (not a Driver).");
  }

  const rideRequestRef = admin.firestore().collection("rideRequests").doc(rideRequestId);
  const rideRequestSnap = await rideRequestRef.get();

  if (!rideRequestSnap.exists) {
    throw new HttpsError("not-found", `Ride request ${rideRequestId} not found.`);
  }
  const rideData = rideRequestSnap.data();
  const customerId = rideData.customerId; // Needed for some actions

  const batch = admin.firestore().batch();
  // Fetch fare configuration
  let fareConfig;
  try {
    const fareConfigDoc = await admin.firestore().collection("appConfiguration").doc("fareSettings").get();
    if (!fareConfigDoc.exists) {
      logger.error("Fare configuration not found in Firestore!");
      // Fallback to default values or throw an error
      // For now, let's use some defaults to prevent complete failure, but log an error.
      fareConfig = { minimumFare: 1250, startingFare: 300, farePerKilometer: 350, farePerMinuteDriving: 60, farePerMinuteWaiting: 60, commissionRate: 0.20, roundingIncrement: 500, currency: "TZS" };
    } else {
      fareConfig = fareConfigDoc.data();
    }
  } catch (error) {
    logger.error("Error fetching fare configuration:", error);
    // Fallback to default values or throw an error
    fareConfig = { minimumFare: 1250, startingFare: 300, farePerKilometer: 350, farePerMinuteDriving: 60, farePerMinuteWaiting: 60, commissionRate: 0.20, roundingIncrement: 500, currency: "TZS" };
  }

  logger.log("Using Fare Configuration:", fareConfig);

  const driverUserRef = admin.firestore().collection("users").doc(driverUid);
  const customerUserRef = customerId ? admin.firestore().collection("users").doc(customerId) : null;
  const kijiweId = driverDoc.data().driverProfile?.kijiweId; // Driver's current kijiwe

  try {
    switch (action) {
      case "accept": { // Added block scope
        if (rideData.driverId !== driverUid || rideData.status !== "pending_driver_acceptance") {
          throw new HttpsError("failed-precondition", "Ride cannot be accepted by this driver or is not in the correct state.");
        }

        // Denormalize driver details for the customer
        const driverDataForDenorm = driverDoc.data();
        logger.log(`[handleDriverRideAction - accept] Raw driver data for denorm (driverId: ${driverUid}):`, JSON.stringify(driverDataForDenorm));


        const driverGender = driverDataForDenorm.gender || "Unknown"; // Changed to const
        let driverAgeGroup = "Unknown";
        const driverName = driverDataForDenorm.name || "Driver";
        const driverProfileImageUrl = driverDataForDenorm.profileImageUrl || null;
        const driverVehicleType = driverDataForDenorm.driverProfile?.vehicleType || "N/A"; // Example: Denormalize vehicle type too

        if (driverDataForDenorm.dob) {
          let birthDate;
          logger.log(`[handleDriverRideAction - accept] Driver DOB found:`, driverDataForDenorm.dob, typeof driverDataForDenorm.dob);
          if (driverDataForDenorm.dob instanceof admin.firestore.Timestamp) {
            birthDate = driverDataForDenorm.dob.toDate();
          } else if (typeof driverDataForDenorm.dob === "string") {
            birthDate = new Date(driverDataForDenorm.dob);
          }
          if (birthDate && !isNaN(birthDate.getTime())) {
            const currentDate = new Date();
            let age = currentDate.getFullYear() - birthDate.getFullYear();
            const m = currentDate.getMonth() - birthDate.getMonth();
            if (m < 0 || (m === 0 && currentDate.getDate() < birthDate.getDate())) {
              age--;
            }
            if (age >= 0 && age >= 18) { // Only show for 18+
              driverAgeGroup = `${Math.floor(age / 10) * 10}s`;
            }
          }
        }
        const driverLicenseNumber = driverDataForDenorm.driverProfile?.licenseNumber || "N/A";
        logger.log(`[handleDriverRideAction - accept] Denormalized values calculated:`, {
          gender: driverGender,
          ageGroup: driverAgeGroup,
          license: driverLicenseNumber,
          name: driverName,
          profileImageUrl: driverProfileImageUrl,
          vehicleType: driverVehicleType,
        });

        batch.update(rideRequestRef, {
          status: "accepted", // Or "goingToPickup"
          acceptedTime: admin.firestore.FieldValue.serverTimestamp(),
          driverName: driverName,
          driverProfileImageUrl: driverProfileImageUrl,
          // Add new denormalized driver details
          driverGender: driverGender,
          driverAgeGroup: driverAgeGroup,
          driverLicenseNumber: driverLicenseNumber,
          driverVehicleType: driverVehicleType, // Store denormalized vehicle type
        });
        batch.update(driverUserRef, { "driverProfile.status": "goingToPickup" });
        if (rideData.kijiweId) { // Remove from the kijiwe queue the ride was matched from
          const kijiweRef = admin.firestore().collection("kijiwe").doc(rideData.kijiweId);
          batch.update(kijiweRef, { queue: admin.firestore.FieldValue.arrayRemove(driverUid) });
        }

        // Commit Firestore changes BEFORE sending notification
        await batch.commit();
        logger.log(`[handleDriverRideAction - accept] Firestore batch committed for ride ${rideRequestId}.`);

        // Notify customer
        if (customerId) {
          const notificationPayloadToCustomer = {
            rideRequestId: rideRequestId,
            status: "accepted",
            driverName: driverName,
            driverProfileImageUrl: driverProfileImageUrl || "", // Ensure string for FCM
            driverGender: driverGender,
            driverAgeGroup: driverAgeGroup,
            driverLicenseNumber: driverLicenseNumber,
            driverVehicleType: driverVehicleType,
            customerNoteToDriver: rideData.customerNoteToDriver || "", // Include note for customer
            pickupAddressName: rideData.pickupAddressName || "",
            dropoffAddressName: rideData.dropoffAddressName || "",
            click_action: "FLUTTER_NOTIFICATION_CLICK", // Important for Flutter
            // Add any other info the customer app might need directly from the notification
          };
          await sendFCMNotification(customerId, "Driver Found!", `${driverName} is on the way to pick you up.`, notificationPayloadToCustomer);
          logger.log(`[handleDriverRideAction - accept] Sent FCM to customer ${customerId} for ride ${rideRequestId}.`);
        }
        break;
      }

      case "decline": { // Added block scope
        if (rideData.driverId !== driverUid || rideData.status !== "pending_driver_acceptance") {
          throw new HttpsError("failed-precondition", "Ride cannot be declined.");
        }
        batch.update(rideRequestRef, { status: "declined_by_driver", driverId: driverUid }); // Keep driverId to know who declined
        batch.update(driverUserRef, {
          "driverProfile.status": "waitingForRide",
          "driverProfile.declinedByDriverCount": admin.firestore.FieldValue.increment(1),
        });
        await batch.commit();
        logger.log(`[handleDriverRideAction - decline] Firestore batch committed for ride ${rideRequestId}.`);
        if (customerId) {
          // Note: Re-matching logic should ideally be triggered here if desired,
          // or the customer app can prompt to search again.
          await sendFCMNotification(customerId, "Ride Update", "The driver declined the ride. Please try requesting again.", {
            rideRequestId: rideRequestId,
            status: "declined_by_driver",
            click_action: "FLUTTER_NOTIFICATION_CLICK",
          });
          logger.log(`[handleDriverRideAction - decline] Sent FCM to customer ${customerId} for ride ${rideRequestId}.`);
        }
        break;
      } // Closed block scope

      case "arrivedAtPickup": { // Added block scope
        if (rideData.driverId !== driverUid || rideData.status !== "accepted") { // Or "goingToPickup"
          throw new HttpsError("failed-precondition", "Cannot confirm arrival. Ride not accepted by this driver or not in 'accepted' state.");
        }
        const driverNameForArrival = driverDoc.data().name || "Your driver";
        batch.update(rideRequestRef, { status: "arrivedAtPickup" });
        batch.update(driverUserRef, { "driverProfile.status": "arrivedAtPickup" });
        await batch.commit();
        logger.log(`[handleDriverRideAction - arrivedAtPickup] Firestore batch committed for ride ${rideRequestId}.`);
        if (customerId) {
          await sendFCMNotification(customerId, "Driver Arrived!", `${driverNameForArrival} has arrived at your pickup location.`, {
            rideRequestId: rideRequestId,
            status: "arrivedAtPickup",
            driverName: driverNameForArrival,
            click_action: "FLUTTER_NOTIFICATION_CLICK",
          });
          logger.log(`[handleDriverRideAction - arrivedAtPickup] Sent FCM to customer ${customerId} for ride ${rideRequestId}.`);
        }
        break;
      } // Closed block scope

      case "startRide": { // Added block scope
        if (rideData.driverId !== driverUid || rideData.status !== "arrivedAtPickup") {
          throw new HttpsError("failed-precondition", "Cannot start ride. Ride not at pickup or not assigned to this driver.");
        }
        const driverNameForStart = driverDoc.data().name || "Your driver";
        batch.update(rideRequestRef, { status: "onRide" });
        batch.update(driverUserRef, { "driverProfile.status": "onRide" });
        await batch.commit();
        logger.log(`[handleDriverRideAction - startRide] Firestore batch committed for ride ${rideRequestId}.`);
        if (customerId) {
          await sendFCMNotification(customerId, "Ride Started", `Your ride with ${driverNameForStart} has started.`, {
            rideRequestId: rideRequestId,
            status: "onRide",
            click_action: "FLUTTER_NOTIFICATION_CLICK",
          });
          logger.log(`[handleDriverRideAction - startRide] Sent FCM to customer ${customerId} for ride ${rideRequestId}.`);
        }
        break;
      } // Closed block scope

      case "completeRide": { // Added block scope
        if (rideData.driverId !== driverUid || rideData.status !== "onRide") {
          throw new HttpsError("failed-precondition", "Cannot complete ride.");
        }

        // Extract actual ride data from the request if provided by the driver app
        const {
          actualDistanceKm: requestedActualDistanceKm,
          actualDrivingDurationMinutes: requestedActualDrivingDurationMinutes,
          actualTotalWaitingTimeMinutes: requestedActualTotalWaitingTimeMinutes,
        } = request.data;

        logger.log(`[completeRide - ${rideRequestId}] Received actuals from client:`, {
          requestedActualDistanceKm,
          requestedActualDrivingDurationMinutes,
          requestedActualTotalWaitingTimeMinutes,
        });
        logger.log(`[completeRide - ${rideRequestId}] Ride data from Firestore:`, rideData);

        // --- FARE CALCULATION ---
        let fareBeforeCommission;
        let subtotal; // Declare subtotal here

        if (requestedActualDistanceKm != null && requestedActualDrivingDurationMinutes != null) {
          // Case 1: Actuals provided by driver app - Calculate fare based on actuals
          logger.log(`[completeRide - ${rideRequestId}] Using actuals from client:`, { requestedActualDistanceKm, requestedActualDrivingDurationMinutes });
          const actualDistanceKm = requestedActualDistanceKm;
          const actualDrivingDurationMinutes = requestedActualDrivingDurationMinutes;
          const actualTotalWaitingTimeMinutes = requestedActualTotalWaitingTimeMinutes ?? 0;
          const distanceFare = actualDistanceKm * fareConfig.farePerKilometer;
          const drivingTimeFare = actualDrivingDurationMinutes * fareConfig.farePerMinuteDriving;
          const waitingTimeFare = actualTotalWaitingTimeMinutes * fareConfig.farePerMinuteWaiting;
          subtotal = fareConfig.startingFare + distanceFare + drivingTimeFare + waitingTimeFare; // Assign to outer scope subtotal
          fareBeforeCommission = Math.max(subtotal, fareConfig.minimumFare);
          logger.log(`[completeRide - ${rideRequestId}] Fare calculated from actuals. Subtotal: ${subtotal}, FareBeforeCommission: ${fareBeforeCommission}`);
        } else if (rideData.customerCalculatedEstimatedFare != null && typeof rideData.customerCalculatedEstimatedFare === "number") {
          // Case 2: No actuals, but customer's estimated fare is available - Use it directly
          fareBeforeCommission = rideData.customerCalculatedEstimatedFare;
          subtotal = fareBeforeCommission; // For logging consistency, assign fareBeforeCommission to subtotal
          logger.log(`[completeRide - ${rideRequestId}] No actuals from client. Using customerCalculatedEstimatedFare: ${fareBeforeCommission}`);
        } else {
          // Case 3: No actuals, no customer estimate - Fallback to function's calculation based on stored estimates (which might be 0)
          const estimatedDistanceKm = rideData.estimatedDistanceKm || 0; // Default to 0 if null/undefined
          const estimatedDurationMinutes = rideData.estimatedDurationMinutes || 0; // Default to 0
          logger.log(`[completeRide - ${rideRequestId}] No actuals or customer estimate. Using stored estimates:`, { estimatedDistanceKm, estimatedDurationMinutes });

          const distanceFare = estimatedDistanceKm * fareConfig.farePerKilometer;
          const drivingTimeFare = estimatedDurationMinutes * fareConfig.farePerMinuteDriving;
          // Assuming no waiting time for this fallback estimate
          subtotal = fareConfig.startingFare + distanceFare + drivingTimeFare; // Assign to outer scope subtotal
          fareBeforeCommission = Math.max(subtotal, fareConfig.minimumFare);
          logger.log(`[completeRide - ${rideRequestId}] Fare calculated from stored estimates. Subtotal: ${subtotal}, FareBeforeCommission: ${fareBeforeCommission}`);
        }

        logger.log(`[completeRide - ${rideRequestId}] Fare config used:`, fareConfig);
        const commissionAmount = fareBeforeCommission * fareConfig.commissionRate;
        const driverEarnings = fareBeforeCommission - commissionAmount; // Declare driverEarnings

        // Rounding logic for final customer fare
        let finalCustomerFare;
        const roundingInc = fareConfig.roundingIncrement; // e.g., 500
        if (roundingInc > 0) {
          const base = Math.floor(fareBeforeCommission / roundingInc) * roundingInc;
          const diff = fareBeforeCommission - base;
          if (diff === 0) {
            finalCustomerFare = fareBeforeCommission;
          } else if (diff <= roundingInc / 2 && roundingInc / 2 > 0) { // e.g., if diff <= 250 for roundingIncrement 500
            finalCustomerFare = base + (roundingInc / 2);
          } else {
            finalCustomerFare = base + roundingInc;
          }
        } else {
          finalCustomerFare = fareBeforeCommission;
        }
        logger.log(
            `[completeRide - ${rideRequestId}] Subtotal: ${subtotal}, ` +
            `FareBeforeCommission: ${fareBeforeCommission}, ` +
            `FinalCustomerFare: ${finalCustomerFare}, ` +
            `Commission: ${commissionAmount}, ` +
            `DriverEarnings: ${driverEarnings}`,
        );

        // --- END FARE CALCULATION ---

        batch.update(rideRequestRef, {
          fareConfigUsed: fareConfig, // Save the fare config used for this ride
          status: "completed",
          completedTime: admin.firestore.FieldValue.serverTimestamp(),
          fare: finalCustomerFare,
          commissionAmount: commissionAmount, // Storing commission amount
          // Store the actual tracked data (or the estimates used if actuals were missing)
          actualDistanceKm: requestedActualDistanceKm ?? rideData.estimatedDistanceKm ?? 0,
          actualDrivingDurationMinutes: requestedActualDrivingDurationMinutes ?? rideData.estimatedDurationMinutes ?? 0,
          actualTotalWaitingTimeMinutes: requestedActualTotalWaitingTimeMinutes ?? rideData.estimatedWaitingMinutes ?? 0,
          driverEarnings: driverEarnings, // storing driverEarnings if needed
        });
        batch.update(driverUserRef, {
          "driverProfile.status": "waitingForRide",
          "driverProfile.completedRidesCount": admin.firestore.FieldValue.increment(1),
        });
        if (customerUserRef) {
          batch.update(customerUserRef, { "customerProfile.completedRidesCount": admin.firestore.FieldValue.increment(1) });
        }
        if (kijiweId) { // Add driver back to their current kijiwe's queue
          const kijiweRef = admin.firestore().collection("kijiwe").doc(kijiweId);
          batch.update(kijiweRef, { queue: admin.firestore.FieldValue.arrayUnion(driverUid) });
        }
        await batch.commit();
        logger.log(`[handleDriverRideAction - completeRide] Firestore batch committed for ride ${rideRequestId}.`);
        if (customerId) {
          await sendFCMNotification(customerId, "Ride Completed!", "Your ride has been completed. Thank you!", {
            rideRequestId: rideRequestId,
            status: "completed",
            fare: finalCustomerFare.toString(), // Send the newly calculated fare
            click_action: "FLUTTER_NOTIFICATION_CLICK",
          });
          logger.log(`[handleDriverRideAction - completeRide] Sent FCM to customer ${customerId} for ride ${rideRequestId}.`);
        }
        break;
      } // Closed block scope

      case "cancelRideByDriver": {
        // Added block scope
        if (rideData.driverId !== driverUid || ["accepted", "arrivedAtPickup"].indexOf(rideData.status) === -1) {
          throw new HttpsError("failed-precondition", "Ride cannot be cancelled by driver at this stage.");
        }
        batch.update(rideRequestRef, { status: "cancelled_by_driver" });
        batch.update(driverUserRef, {
          "driverProfile.status": "waitingForRide",
          "driverProfile.cancelledByDriverCount": admin.firestore.FieldValue.increment(1),
        });
        if (customerUserRef) {
          batch.update(customerUserRef, { "customerProfile.ridesCancelledByDriverForCustomerCount": admin.firestore.FieldValue.increment(1) });
        }
        if (kijiweId) { // Add driver back to queue
          const kijiweRef = admin.firestore().collection("kijiwe").doc(kijiweId);
          batch.update(kijiweRef, { queue: admin.firestore.FieldValue.arrayUnion(driverUid) });
        }
        await batch.commit();
        logger.log(`[handleDriverRideAction - cancelRideByDriver] Firestore batch committed for ride ${rideRequestId}.`);

        if (customerId) {
          const driverNameForCancel = driverDoc.data().name || "The driver";
          await sendFCMNotification(
              customerId,
              "Ride Cancelled",
              `Your ride has been cancelled by ${driverNameForCancel}.`,
              {
                rideRequestId: rideRequestId,
                status: "cancelled_by_driver",
                click_action: "FLUTTER_NOTIFICATION_CLICK",
              },
          );
          logger.log(`[handleDriverRideAction - cancelRideByDriver] Sent FCM to customer ${customerId} for ride ${rideRequestId}.`);
        }
        break;
      } // Closed block scope

      case "rateCustomer": { // Added block scope
        if (rideData.driverId !== driverUid || rideData.status !== "completed") {
          throw new HttpsError("failed-precondition", "Cannot rate customer for this ride.");
        }
        if (typeof rating !== "number" || rating < 1 || rating > 5) {
          throw new HttpsError("invalid-argument", "Rating must be between 1 and 5.");
        }
        batch.update(rideRequestRef, {
          driverRatingToCustomer: rating,
          driverCommentToCustomer: comment || null,
        } );
        if (customerUserRef) {
          batch.update(customerUserRef, {
            "customerProfile.sumOfRatingsReceived": admin.firestore.FieldValue.increment(rating),
            "customerProfile.totalRatingsReceivedCount": admin.firestore.FieldValue.increment(1),
          } );
        }
        // No direct FCM to customer needed for this action, but batch commit is important.
        await batch.commit();
        logger.log(`[handleDriverRideAction - rateCustomer] Firestore batch committed for ride ${rideRequestId}.`);
        break;
      } // Closed block scope
      default:
        throw new HttpsError("invalid-argument", "Unknown action specified.");
    }
    logger.log(`Driver ${driverUid} performed action '${action}' on ride ${rideRequestId}.`);
    return { success: true, message: `Action '${action}' successful.` };
  } catch (error) {
    logger.error(`Error performing action '${action}' for driver ${driverUid} on ride ${rideRequestId}:`, error);
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError("internal", "An internal error occurred.", error.message);
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
    logger.log(`Ride request ${event.params.rideRequestId} status changed from ${beforeData.status} ` +
        `to ${afterData.status}`);
    if (afterData.status === "completed") {
      if (afterData.assignedDriverId) {
        // Example: Send a generic completion notification to driver
        // You might want a more specific payload for completion
        // await sendFCMNotification(afterData.assignedDriverId, "Ride Completed", "Your ride is complete.", {
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
  logger.log(`Ride request ${event.params.rideRequestId} deleted. Data:`, deletedData);
  // if (deletedData && deletedData.assignedDriverId) {
  //   // Notify driver about ride request deletion
  //   // await sendFCMNotification(deletedData.assignedDriverId, "Ride Deleted", "A ride was deleted.", {
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
    logger.log(`Kijiwe ${event.params.kijiweId} queue updated.`);
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