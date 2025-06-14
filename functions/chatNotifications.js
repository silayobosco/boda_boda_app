const admin = require("firebase-admin");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { logger } = require("firebase-functions");

// Ensure Firebase Admin SDK is initialized (typically done in index.js, but good practice)
if (admin.apps.length === 0) {
  admin.initializeApp();
}

/**
 * Sends an FCM notification to a target user.
 * @param {string} targetUserId The UID of the user to send the notification to.
 * @param {string} title The title of the notification.
 * @param {string} body The body of the notification.
 * @param {object} dataPayload Additional data to send with the notification.
 * @return {Promise<void>}
 */
async function sendFCMNotificationToUser(targetUserId, title, body, dataPayload) {
  const targetUserDoc = await admin.firestore().collection("users").doc(targetUserId).get();
  if (!targetUserDoc.exists) {
    logger.warn(`User ${targetUserId} not found, cannot send chat notification.`);
    return;
  }
  const fcmToken = targetUserDoc.data().fcmToken;

  if (fcmToken) {
    const stringifiedDataPayload = {};
    for (const key in dataPayload) {
      if (Object.prototype.hasOwnProperty.call(dataPayload, key)) {
        stringifiedDataPayload[key] = dataPayload[key] == null ? "" : String(dataPayload[key]);
      }
    }

    const payload = {
      notification: { title, body },
      data: {
        ...stringifiedDataPayload,
        click_action: "FLUTTER_NOTIFICATION_CLICK", // Essential for Flutter
        type: "chat_message", // Custom type to identify chat notifications
      },
      token: fcmToken,
      android: {
        priority: "high",
        notification: { sound: "default" },
      },
      apns: {
        payload: { aps: { sound: "default", badge: 1 } }, // Increment badge on iOS
      },
    };

    try {
      await admin.messaging().send(payload);
      logger.log("Successfully sent chat FCM message to", targetUserId);
    } catch (error) {
      logger.error("Error sending chat FCM message to", targetUserId, error);
    }
  } else {
    logger.warn(`User ${targetUserId} has no FCM token for chat notification.`);
  }
}

exports.onChatMessageCreated = onDocumentCreated("/rideChats/{rideRequestId}/messages/{messageId}", async (event) => {
  const messageSnap = event.data;
  if (!messageSnap) {
    logger.log("No data associated with the chat message event.");
    return null;
  }

  const messageData = messageSnap.data();
  const rideRequestId = event.params.rideRequestId;
  const senderId = messageData.senderId;
  const messageText = messageData.text;

  logger.log(`New chat message for ride ${rideRequestId} from ${senderId}: ${messageText}`);

  // 1. Fetch the ride request to find customerId and driverId
  const rideRequestRef = admin.firestore().collection("rideRequests").doc(rideRequestId);
  const rideRequestSnap = await rideRequestRef.get();

  if (!rideRequestSnap.exists) {
    logger.error(`Ride request ${rideRequestId} not found. Cannot determine chat recipient.`);
    return null;
  }
  const rideData = rideRequestSnap.data();
  const customerId = rideData.customerId;
  const driverId = rideData.driverId;

  // 2. Determine the recipient
  let recipientId;
  if (senderId === customerId && driverId) {
    recipientId = driverId;
  } else if (senderId === driverId && customerId) {
    recipientId = customerId;
  } else {
    logger.warn(`Could not determine recipient for message in ride ${rideRequestId}. Sender: ${senderId}, Customer: ${customerId}, Driver: ${driverId}`);
    return null;
  }

  // 3. Send notification to the recipient
  const senderName = messageData.senderRole === "Customer" ? (rideData.customerName || "Customer") : (rideData.driverName || "Driver");
  await sendFCMNotificationToUser(recipientId, `New message from ${senderName}`, messageText, { rideRequestId: rideRequestId, senderId: senderId });
  return null;
});