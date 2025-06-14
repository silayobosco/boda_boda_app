const admin = require("firebase-admin");
const { HttpsError, onCall } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { logger } = require("firebase-functions");

// Ensure Firebase Admin SDK is initialized (typically in your main index.js, but good to have a check here too)
if (admin.apps.length === 0) {
  admin.initializeApp();
}
const db = admin.firestore();

/**
 * Manages scheduled rides: edit or delete.
 * Callable Cloud Function.
 *
 * @param {object} data - The data passed to the function.
 * @param {string} data.action - The action to perform ('edit' or 'delete').
 * @param {string} data.rideId - The ID of the scheduled ride.
 * @param {object} [data.rideData] - The new data for the ride if action is 'edit'.
 * @param {object} context - The context of the function call.
 * @param {object} context.auth - Authentication information for the user.
 * @returns {Promise<object>} A promise that resolves with the result of the operation.
 */
exports.manageScheduledRide = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    logger.warn("manageScheduledRide: Unauthenticated access attempt.");
    throw new HttpsError("unauthenticated", "User must be authenticated.");
  }

  const { action, rideId, rideData } = request.data;

  if (!action || !rideId) {
    logger.error("manageScheduledRide: Missing action or rideId.", { uid, data: request.data });
    throw new HttpsError("invalid-argument", "Missing action or rideId.");
  }

  const scheduledRideRef = db.collection("scheduledRides").doc(rideId);

  try {
    const rideDoc = await scheduledRideRef.get();
    if (!rideDoc.exists) {
      logger.warn(`manageScheduledRide: Scheduled ride ${rideId} not found.`, { uid });
      throw new HttpsError("not-found", "Scheduled ride not found.");
    }
    if (rideDoc.data().customerId !== uid) {
      logger.warn(`manageScheduledRide: User ${uid} attempted to manage ride ${rideId} owned by ${rideDoc.data().customerId}.`);
      throw new HttpsError("permission-denied", "User does not own this scheduled ride.");
    }

    if (action === "edit") {
      if (!rideData) {
        logger.error("manageScheduledRide: Missing rideData for edit action.", { uid, rideId });
        throw new HttpsError("invalid-argument", "Missing rideData for edit action.");
      }

      const updatePayload = { ...rideData }; // Clone to avoid modifying original request.data

      // Convert client-side DateTime strings/objects to Firestore Timestamps
      if (updatePayload.scheduledDateTime && !(updatePayload.scheduledDateTime instanceof admin.firestore.Timestamp)) {
        const parsedDate = new Date(updatePayload.scheduledDateTime);
        if (isNaN(parsedDate.getTime())) {
          throw new HttpsError("invalid-argument", "Invalid scheduledDateTime format for edit.");
        }
        updatePayload.scheduledDateTime = admin.firestore.Timestamp.fromDate(parsedDate);
      }
      if (updatePayload.recurrenceEndDate && !(updatePayload.recurrenceEndDate instanceof admin.firestore.Timestamp)) {
        const parsedEndDate = new Date(updatePayload.recurrenceEndDate);
        if (isNaN(parsedEndDate.getTime())) {
          throw new HttpsError("invalid-argument", "Invalid recurrenceEndDate format for edit.");
        }
        updatePayload.recurrenceEndDate = admin.firestore.Timestamp.fromDate(parsedEndDate);
      }
      // Ensure GeoPoints are correctly formatted if they are part of rideData
      if (updatePayload.pickup && updatePayload.pickup.latitude && updatePayload.pickup.longitude && !(updatePayload.pickup instanceof admin.firestore.GeoPoint)) {
        updatePayload.pickup = new admin.firestore.GeoPoint(updatePayload.pickup.latitude, updatePayload.pickup.longitude);
      }
      if (updatePayload.dropoff && updatePayload.dropoff.latitude && updatePayload.dropoff.longitude && !(updatePayload.dropoff instanceof admin.firestore.GeoPoint)) {
        updatePayload.dropoff = new admin.firestore.GeoPoint(updatePayload.dropoff.latitude, updatePayload.dropoff.longitude);
      }
      if (updatePayload.stops && Array.isArray(updatePayload.stops)) {
        updatePayload.stops = updatePayload.stops.map((stop) => {
          if (stop.location && stop.location.latitude && stop.location.longitude && !(stop.location instanceof admin.firestore.GeoPoint)) {
            return { ...stop, location: new admin.firestore.GeoPoint(stop.location.latitude, stop.location.longitude) };
          }
          return stop;
        });
      }

      updatePayload.updatedAt = admin.firestore.FieldValue.serverTimestamp();

      await scheduledRideRef.update(updatePayload);
      logger.log(`Scheduled ride ${rideId} edited by user ${uid}.`);
      return { success: true, message: "Scheduled ride updated successfully." };
    } else if (action === "delete") {
      await scheduledRideRef.delete();
      logger.log(`Scheduled ride ${rideId} deleted by user ${uid}.`);
      // If it's a recurring ride master, you might want to delete generated instances.
      // This would require querying for instances linked to this masterId.
      return { success: true, message: "Scheduled ride deleted successfully." };
    } else {
      logger.error("manageScheduledRide: Invalid action specified.", { uid, action });
      throw new HttpsError("invalid-argument", "Invalid action specified.");
    }
  } catch (error) {
    logger.error(`Error in manageScheduledRide (rideId: ${rideId}, action: ${action}, uid: ${uid}):`, error);
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", "Could not manage scheduled ride.", error.message);
  }
});

/**
 * Processes scheduled rides that are due to become active.
 * Runs on a schedule (e.g., every 5 minutes).
 * This function will also handle generating instances of recurring rides.
 */
exports.processScheduledRides = onSchedule("every 5 minutes", async (event) => {
  logger.log("processScheduledRides function triggered by scheduler.", { eventTime: event.time });

  const now = admin.firestore.Timestamp.now();
  const activationWindowStart = now;
  // Activate rides scheduled in the next 15 minutes
  const activationWindowEnd = admin.firestore.Timestamp.fromMillis(now.toMillis() + 15 * 60 * 1000);
  // Generate recurring instances for the next, e.g., 7 days
  const recurrenceGenerationCutoff = admin.firestore.Timestamp.fromMillis(now.toMillis() + 7 * 24 * 60 * 60 * 1000);

  const batch = db.batch();
  let ridesActivatedCount = 0;
  let recurringInstancesGenerated = 0; // This will be incremented, so 'let' is correct.

  try {
    // --- 1. Activate Due Non-Recurring Scheduled Rides ---
    const dueNonRecurringQuery = db.collection("scheduledRides")
        .where("status", "==", "scheduled")
        .where("isRecurring", "==", false) // Explicitly non-recurring
        .where("scheduledDateTime", ">=", activationWindowStart)
        .where("scheduledDateTime", "<=", activationWindowEnd);

    const dueNonRecurringSnapshot = await dueNonRecurringQuery.get();

    dueNonRecurringSnapshot.forEach((doc) => {
      const scheduledRide = doc.data();
      const scheduledRideId = doc.id;
      logger.log(`Activating non-recurring scheduled ride: ${scheduledRideId}`);

      const newRideRequestRef = db.collection("rideRequests").doc();
      batch.set(newRideRequestRef, {
        customerId: scheduledRide.customerId,
        pickup: scheduledRide.pickup,
        dropoff: scheduledRide.dropoff,
        stops: scheduledRide.stops || [],
        pickupAddressName: scheduledRide.pickupAddressName,
        dropoffAddressName: scheduledRide.dropoffAddressName,
        customerNoteToDriver: scheduledRide.customerNoteToDriver,
        status: "pending_match", // Initial status for a new ride request
        requestTime: admin.firestore.FieldValue.serverTimestamp(),
        scheduledRideParentId: scheduledRideId, // Link to the original scheduled ride
        title: scheduledRide.title, // Carry over title
      });
      batch.update(doc.ref, {
        status: "activated",
        actualRideRequestId: newRideRequestRef.id,
      });
      ridesActivatedCount++;
    });

    // --- 2. Generate Instances for Recurring Rides ---
    const masterRecurringQuery = db.collection("scheduledRides")
        .where("isRecurring", "==", true)
        .where("status", "==", "scheduled"); // Only process active recurring masters

    const masterRecurringSnapshot = await masterRecurringQuery.get();

    masterRecurringSnapshot.forEach((masterDoc) => {
      const masterRide = masterDoc.data();
      const masterRideId = masterDoc.id;

      if (!masterRide.recurrenceType || !masterRide.recurrenceEndDate || masterRide.recurrenceEndDate.toMillis() < now.toMillis()) {
        logger.log(`Recurring ride ${masterRideId} has ended or is misconfigured. Skipping instance generation.`);
        return;
      }

      const nextScheduledTime = masterRide.scheduledDateTime.toDate(); // Use const as it's not reassigned
      const recurrenceEndDate = masterRide.recurrenceEndDate.toDate();
      const lastInstanceGenerated = masterRide.lastInstanceGeneratedUpTo ? masterRide.lastInstanceGeneratedUpTo.toDate() : new Date(0);

      const currentDate = new Date(Math.max(nextScheduledTime.getTime(), lastInstanceGenerated.getTime() + (24 * 60 * 60 * 1000 - 1)));
      currentDate.setHours(nextScheduledTime.getHours(), nextScheduledTime.getMinutes(), 0, 0);

      let instancesForThisMaster = 0; // To track if we generated any for this master

      while (currentDate <= recurrenceEndDate && currentDate <= recurrenceGenerationCutoff.toDate()) { // Use recurrenceGenerationCutoff
        let shouldCreateInstance = false;
        if (masterRide.recurrenceType === "Daily") {
          shouldCreateInstance = true;
        } else if (masterRide.recurrenceType === "Weekly") {
          const dayOfWeek = currentDate.getDay();
          const dayAbbreviationMap = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
          if (masterRide.recurrenceDaysOfWeek && masterRide.recurrenceDaysOfWeek.includes(dayAbbreviationMap[dayOfWeek])) {
            shouldCreateInstance = true;
          }
        }

        if (shouldCreateInstance) {
          const instanceScheduledDateTime = admin.firestore.Timestamp.fromDate(currentDate);
          const newInstanceRef = db.collection("scheduledRides").doc();
          batch.set(newInstanceRef, {
            ...masterRide,
            isRecurring: false,
            recurrenceType: null,
            recurrenceDaysOfWeek: null,
            recurrenceEndDate: null,
            masterRecurringRideId: masterRideId,
            scheduledDateTime: instanceScheduledDateTime,
            status: "scheduled",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            lastInstanceGeneratedUpTo: null,
          });
          recurringInstancesGenerated++; // Increment the counter
          instancesForThisMaster++;
          logger.log(`Generated instance for master ${masterRideId} on ${currentDate.toISOString()}`);
        }
        currentDate.setDate(currentDate.getDate() + 1);
      }
      if (instancesForThisMaster > 0 || masterRide.lastInstanceGeneratedUpTo == null || recurrenceGenerationCutoff.toMillis() > lastInstanceGenerated.getTime()) {
        const newLastGeneratedDate = new Date(
            Math.min(recurrenceGenerationCutoff.toDate().getTime(), recurrenceEndDate.getTime()),
        );
        batch.update(masterDoc.ref,
            { lastInstanceGeneratedUpTo: admin.firestore.Timestamp.fromDate(newLastGeneratedDate) });
      }
    });

    if (ridesActivatedCount > 0 || recurringInstancesGenerated > 0) {
      await batch.commit();
      logger.log(`ProcessScheduledRides: Activated ${ridesActivatedCount} rides. Generated ${recurringInstancesGenerated} recurring instances.`);
    } else {
      logger.log("ProcessScheduledRides: No rides to activate and no new recurring instances generated in this run.");
    }

    return null;
  } catch (error) {
    logger.error("Error in processScheduledRides:", error);
    return null;
  }
});