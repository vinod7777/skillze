/**
 * Skillze Admin Data Service
 * Centralized logic for fetching live Firestore data and populating the UI.
 */
import { 
  db, collection, getDocs, onSnapshot, query, orderBy, limit, doc, 
  updateDoc, deleteDoc, setDoc, addDoc, serverTimestamp 
} from './firebase-config.js';

// --- DASHBOARD ANALYTICS ---
export function trackDashboardStats(callback) {
  let stats = { users: 0, posts: 0, stories: 0, reports: 0 };
  
  // Real-time listener for users
  onSnapshot(collection(db, "users"), (snapshot) => {
    stats.users = snapshot.size;
    callback({...stats});
  });

  // Real-time listener for posts
  onSnapshot(collection(db, "posts"), (snapshot) => {
    stats.posts = snapshot.size;
    callback({...stats});
  });

  // Real-time listener for active stories
  onSnapshot(collection(db, "stories"), (snapshot) => {
    stats.stories = snapshot.size;
    callback({...stats});
  });

  // Real-time listener for reports
  onSnapshot(collection(db, "reports"), (snapshot) => {
    stats.reports = snapshot.size;
    callback({...stats});
  });
}

// --- USER MANAGEMENT ---
export function listenToUsers(callback) {
  const usersRef = collection(db, "users");
  
  return onSnapshot(usersRef, (snapshot) => {
    const users = snapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data()
    }));
    callback(users);
  }, (error) => {
    console.error("User List Error:", error);
  });
}

// --- POST/CONTENT MANAGEMENT ---
export function listenToPosts(callback) {
  const postsRef = collection(db, "posts");
  
  return onSnapshot(postsRef, (snapshot) => {
    const posts = snapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data(),
      type: 'post'
    }));
    callback(posts);
  }, (error) => {
    console.error("Post Feed Error:", error);
  });
}

/**
 * Real-time listener for comments on a specific post
 */
export function listenToComments(postId, callback) {
  const commentsRef = collection(db, "posts", postId, "comments");
  const q = query(commentsRef, orderBy("timestamp", "desc"));
  
  return onSnapshot(q, (snapshot) => {
    const comments = snapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data()
    }));
    callback(comments);
  }, (error) => {
    console.error(`Comments Load Error for ${postId}:`, error);
  });
}

// --- STORY MANAGEMENT ---
export function listenToStories(callback) {
  const storiesRef = collection(db, "stories");
  
  return onSnapshot(storiesRef, (snapshot) => {
    const stories = snapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data(),
      type: 'story'
    }));
    callback(stories);
  }, (error) => {
    console.error("Story Feed Error:", error);
  });
}

// --- ADMINISTRATIVE ACTIONS ---

/**
 * Update user basic status (block/unblock)
 */
export async function updateUserStatus(userId, isBlocked) {
  const userRef = doc(db, "users", userId);
  try {
    await updateDoc(userRef, { isBlocked: isBlocked });
    return true;
  } catch (e) {
    console.error("Block operation failed:", e);
    throw e;
  }
}

/**
 * Verify a user (Blue Badge status)
 */
export async function verifyUser(userId, status = true) {
  const userRef = doc(db, "users", userId);
  try {
    await updateDoc(userRef, { isVerified: status });
    return true;
  } catch (e) {
    console.error("Verification failed:", e);
    throw e;
  }
}

/**
 * Delete content (Post or Story)
 */
export async function deleteContent(type, id) {
  const collectionName = type === 'story' ? 'stories' : 'posts';
  const contentRef = doc(db, collectionName, id);
  try {
    await deleteDoc(contentRef);
    return true;
  } catch (e) {
    console.error(`Deletion of ${type} failed:`, e);
    throw e;
  }
}

/**
 * Delete a specific comment from a post
 */
export async function deleteComment(postId, commentId) {
  const commentRef = doc(db, "posts", postId, "comments", commentId);
  try {
    await deleteDoc(commentRef);
    // Note: We might want to decrement commentsCount on the post here if needed
    return true;
  } catch (e) {
    console.error("Comment deletion failed:", e);
    throw e;
  }
}

/**
 * Dispatch a global broadcast notification
 */
export async function dispatchBroadcast(title, body, actionLink) {
  try {
    await addDoc(collection(db, "notifications"), {
      title,
      body,
      actionLink,
      type: 'broadcast',
      createdAt: serverTimestamp(),
      isGlobal: true
    });
    return true;
  } catch (e) {
    console.error("Broadcast dispatch failed:", e);
    throw e;
  }
}

/**
 * Moderate a report (dismiss or take action)
 */
export async function resolveReport(reportId, actionTaken = true) {
  const reportRef = doc(db, "reports", reportId);
  try {
    await updateDoc(reportRef, { 
      status: 'resolved', 
      resolvedAt: new Date(),
      actionTaken: actionTaken 
    });
    return true;
  } catch (e) {
    console.error("Resolve report failed:", e);
    throw e;
  }
}

// --- CHAT & SAFETY MONITORING ---

/**
 * Global listener for all active chat rooms
 */
export function listenToChats(callback) {
  const chatsRef = collection(db, "chats");
  
  // We use a simple listener to avoid index requirements for unordered docs,
  // then we sort in memory to ensure 100% visibility of all chats.
  return onSnapshot(chatsRef, (snapshot) => {
    const chats = snapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data()
    }));
    
    // Sort by last active timestamp (handles multiple possible field names)
    chats.sort((a, b) => {
      const tsA = a.updatedAt?.seconds || a.lastMessageTimestamp?.seconds || a.createdAt?.seconds || 0;
      const tsB = b.updatedAt?.seconds || b.lastMessageTimestamp?.seconds || b.createdAt?.seconds || 0;
      return tsB - tsA;
    });

    callback(chats);
  }, (error) => {
    console.error("Chats Synchronization Error:", error);
  });
}

/**
 * Message listener for a SPECIFIC chat room subcollection
 */
export function listenToChatMessages(chatId, callback) {
  const messagesRef = collection(db, "chats", chatId, "messages");
  const q = query(messagesRef, orderBy("timestamp", "asc"));
  
  return onSnapshot(q, (snapshot) => {
    const messages = snapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data()
    }));
    callback(messages);
  }, (error) => {
    console.error(`Message Load Error for ${chatId}:`, error);
  });
}

/**
 * Global listener for taxonomies / categories
 */
export function listenToTaxonomies(callback) {
  const taxRef = collection(db, "taxonomies");
  
  return onSnapshot(taxRef, (snapshot) => {
    callback(snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })));
  }, (error) => {
    console.error("Taxonomy Load Error:", error);
  });
}

/**
 * Global listener for broadcast history
 */
export function listenToNotifications(callback) {
  const notifRef = collection(db, "notifications");
  const q = query(notifRef, orderBy("createdAt", "desc"));
  
  return onSnapshot(q, (snapshot) => {
    const notifs = snapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data()
    }));
    callback(notifs);
  }, (error) => {
    console.error("Notification Audit Error:", error);
  });
}

// --- UI HELPERS ---
export function formatTimestamp(ts) {
  if (!ts) return "---";
  const date = ts.toDate ? ts.toDate() : new Date(ts);
  const now = new Date();
  if (date.toDateString() === now.toDateString()) {
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  }
  return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
}
