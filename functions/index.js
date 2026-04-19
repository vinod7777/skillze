const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

// When a new call is added to the "calls" collection, notify the callee.
exports.sendCallNotification = functions.firestore
    .document("calls/{callId}")
    .onCreate(async (snap, context) => {
        const newValue = snap.data();
        const callId = context.params.callId;

        console.log(`New call created: ${callId}`);

        const callerName = newValue.callerName || "Unknown Caller";
        const callerAvatar = newValue.callerAvatar || "";
        const isVideo = newValue.isVideo || false;
        const calleeId = newValue.calleeId;
        const callerId = newValue.callerId;

        // Don't send notification back to the caller
        if (!calleeId) {
            console.log("No calleeId provided in call document.");
            return null;
        }

        try {
            // Get the callee's FCM token
            const userDoc = await admin.firestore().collection("users").doc(calleeId).get();
            if (!userDoc.exists) {
                console.log(`User ${calleeId} does not exist.`);
                return null;
            }

            const fcmToken = userDoc.data().fcmToken;
            if (!fcmToken) {
                console.log(`User ${calleeId} has no fcmToken registered.`);
                return null;
            }

            // Payload intended for flutter_callkit_incoming to wake up the device using HTTP v1 API
            const message = {
                token: fcmToken,
                data: {
                    type: "call",
                    callId: String(callId),
                    callerName: String(callerName),
                    callerAvatar: String(callerAvatar),
                    isVideo: String(isVideo),
                    callerId: String(callerId)
                },
                android: {
                    priority: "high"
                },
                apns: {
                    headers: {
                        "apns-priority": "10"
                    }
                }
            };

            console.log(`Sending call notification to ${calleeId} for call ${callId}`);
            const response = await admin.messaging().send(message);
            console.log("Successfully sent message:", response);
            return null;
        } catch (error) {
            console.error("Error sending call notification:", error);
            return null;
        }
    });

// Basic functionality to also handle normal chat message notifications
exports.sendChatNotification = functions.firestore
    .document("chats/{chatId}/messages/{messageId}")
    .onCreate(async (snap, context) => {
        const newValue = snap.data();
        const chatId = context.params.chatId;

        const senderId = newValue.senderId;
        const text = newValue.text || "Sent a message";
        
        try {
            const chatDoc = await admin.firestore().collection("chats").doc(chatId).get();
            const chatData = chatDoc.data();
            if (!chatData || !chatData.participants) return null;

            // Find receiver who is not the sender
            const receiverId = chatData.participants.find(id => id !== senderId);
            if (!receiverId) return null;

            // Get receiver's FCM token
            const userDoc = await admin.firestore().collection("users").doc(receiverId).get();
            if (!userDoc.exists || !userDoc.data().fcmToken) return null;

            // Get sender's name
            const senderDoc = await admin.firestore().collection("users").doc(senderId).get();
            const senderName = senderDoc.data()?.name || "Someone";

            const message = {
                token: userDoc.data().fcmToken,
                data: {
                    title: senderName,
                    body: text,
                    type: "chat",
                    chatId: String(chatId),
                    senderId: String(senderId)
                },
                android: {
                    priority: "high"
                },
                apns: {
                    payload: {
                        aps: {
                            alert: {
                                title: senderName,
                                body: text
                            },
                            category: "REPLY_CATEGORY"
                        }
                    }
                }
            };

            await admin.messaging().send(message);
            console.log("Message notification sent successfully.");
            return null;
        } catch (error) {
            console.error("Error sending chat notification:", error);
            return null;
        }
    });
