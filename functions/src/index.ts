import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

admin.initializeApp();
const db = admin.firestore();

/**
 * Automatically delete expired messages
 * Runs every hour to clean up messages older than 7 days
 */
export const cleanupExpiredMessages = functions.pubsub
  .schedule('every 1 hours')
  .onRun(async (context) => {
    const now = admin.firestore.Timestamp.now();
    let deletedCount = 0;

    try {
      // Get all users with messages
      const usersSnapshot = await db.collection('messages').get();

      for (const userDoc of usersSnapshot.docs) {
        // Get expired messages for this user
        const expiredMessages = await db
          .collection('messages')
          .doc(userDoc.id)
          .collection('incoming')
          .where('expiresAt', '<=', now)
          .get();

        for (const messageDoc of expiredMessages.docs) {
          await messageDoc.ref.delete();
          deletedCount++;
        }
      }

      if (deletedCount > 0) {
        console.log(`Deleted ${deletedCount} expired messages`);
      } else {
        console.log('No expired messages found');
      }

      return null;
    } catch (error) {
      console.error('Error cleaning up expired messages:', error);
      return null;
    }
  });

/**
 * Delete message from server immediately after it's marked as delivered
 */
export const onMessageDelivered = functions.firestore
  .document('messages/{userId}/incoming/{messageId}')
  .onUpdate(async (change, context) => {
    const after = change.after.data();
    const before = change.before.data();

    // If message was just marked as delivered
    if (after.delivered === true && before.delivered === false) {
      try {
        // Wait 2 seconds to ensure client received it, then delete
        await new Promise(resolve => setTimeout(resolve, 2000));
        await change.after.ref.delete();
        console.log(`Deleted delivered message ${context.params.messageId}`);
      } catch (error) {
        console.error('Error deleting delivered message:', error);
      }
    }

    return null;
  });
