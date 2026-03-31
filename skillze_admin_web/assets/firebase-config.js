/**
 * Skillze Admin Proxy Configuration
 * PASTE YOUR FIREBASE CONFIGURATION HERE
 */

const firebaseConfig = {
  apiKey: "AIzaSyDbj1g-gkr6HsFmLfGrfyj8EbTwDdNPxQ0",
  authDomain: "feed-609dd.firebaseapp.com",
  projectId: "feed-609dd",
  storageBucket: "feed-609dd.firebasestorage.app",
  messagingSenderId: "536909553761",
  appId: "1:536909553761:web:a8aa2abed135e59e4e8a20",
  measurementId: "G-KDW9K2MME0"
};

// --- INITIALIZE FIREBASE (Requires CDN script in HTML) ---

import { initializeApp } from "https://www.gstatic.com/firebasejs/10.7.2/firebase-app.js";
import { 
  getFirestore, 
  collection, 
  getDocs, 
  doc, 
  onSnapshot, 
  query, 
  orderBy, 
  limit,
  updateDoc,
  deleteDoc,
  setDoc,
  addDoc,
  serverTimestamp,
  where
} from "https://www.gstatic.com/firebasejs/10.7.2/firebase-firestore.js";

import { getAuth, onAuthStateChanged, signInWithEmailAndPassword, signOut, createUserWithEmailAndPassword } from "https://www.gstatic.com/firebasejs/10.7.2/firebase-auth.js";

const app = initializeApp(firebaseConfig);
const db = getFirestore(app);
const auth = getAuth(app);

export { 
  db, 
  auth, 
  collection, 
  getDocs, 
  onSnapshot, 
  doc, 
  query, 
  orderBy, 
  limit, 
  updateDoc,
  deleteDoc,
  setDoc,
  addDoc,
  serverTimestamp,
  where,
  signInWithEmailAndPassword, 
  signOut,
  createUserWithEmailAndPassword
};

console.log("Skillze Firebase Interface: Fully Active ✅");
