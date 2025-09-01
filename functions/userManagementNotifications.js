const admin = require("firebase-admin");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { logger } = require("firebase-functions");

// Ensure Firebase Admin SDK is initialized
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
    logger.warn(`User ${targetUserId} not found, cannot send notification.`);
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
        type: "user_management_notification", // Custom type to identify notifications
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
      logger.log("Successfully sent FCM message to", targetUserId);
    } catch (error) {
      logger.error("Error sending FCM message to", targetUserId, error);
    }
  } else {
    logger.warn(`User ${targetUserId} has no FCM token for notification.`);
  }
}

exports.onUserNotificationCreated = onDocumentCreated("/notifications/{userId}/{notificationId}", async (event) => {
  const notificationSnap = event.data;
  if (!notificationSnap) {
    logger.log("No data associated with the notification event.");
    return null;
  }

  const notificationData = notificationSnap.data();
  const userId = event.params.userId;

  const { title, body } = notificationData;

  logger.log(`New notification for user ${userId}: ${title}`);

  await sendFCMNotificationToUser(userId, title, body, { notificationId: event.params.notificationId });
  return null;
});
