const admin = require("firebase-admin");
const Stripe = require("stripe");
const axios = require("axios");
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");

// ==========================================
// ✅ INITIALIZE FIREBASE FIRST!
// ==========================================
admin.initializeApp();

// ==========================================
// ✅ NOW get db and messaging
// ==========================================
const db = admin.firestore();
const messaging = admin.messaging();

// ==========================================
// ✅ SECRETS (Google Secret Manager)
// ==========================================
const STRIPE_SECRET = defineSecret("STRIPE_SECRET");
const STRIPE_WEBHOOK_SECRET = defineSecret("STRIPE_WEBHOOK_SECRET");
const GOOGLE_API_KEY = defineSecret("GOOGLE_API_KEY");

// ==========================================
// HELPER FUNCTIONS
// ==========================================
function toPence(amountGbp) {
  return Math.round(Number(amountGbp) * 100);
}

function getFunctionsBaseUrl() {
  const project =
    process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || "event-discrovery-app";
  const region = process.env.FUNCTION_REGION || "us-central1";
  return `https://${region}-${project}.cloudfunctions.net`;
}

function normalizePhotoReference(input) {
  if (input == null) return null;

  let s = String(input).trim();

  if (
    (s.startsWith('"') && s.endsWith('"')) ||
    (s.startsWith("'") && s.endsWith("'"))
  ) {
    s = s.slice(1, -1).trim();
  }

  if (/^https?:\/\//i.test(s)) {
    try {
      const u = new URL(s);
      const pr = u.searchParams.get("photo_reference");
      if (pr) return pr.trim();
      return null;
    } catch (_) {
      return null;
    }
  }

  const m = s.match(/photo_reference=([^&\s]+)/i);
  if (m && m[1]) {
    try {
      return decodeURIComponent(m[1]).trim();
    } catch (_) {
      return m[1].trim();
    }
  }

  return s;
}

// ==========================================
// NOTIFICATION HELPER FUNCTIONS
// ==========================================

async function getUserTokens(userId) {
  const tokensSnap = await db
    .collection('users')
    .doc(userId)
    .collection('fcmTokens')
    .get();
  
  return tokensSnap.docs.map(doc => doc.data().token);
}

async function getUserPreferences(userId) {
  const doc = await db
    .collection('users')
    .doc(userId)
    .collection('settings')
    .doc('notifications')
    .get();
  
  if (!doc.exists) {
    return {
      events: { dailyDigest: true, reminders: true, preArrival: true },
      messages: { zoneChat: true, requests: true, posts: false },
      parking: { confirmations: true, reminders: true },
      moderation: { reports: true, appeals: true },
      quietHours: { enabled: true, start: '22:00', end: '08:00' },
    };
  }
  
  return doc.data();
}

function isInQuietHours(preferences) {
  if (!preferences.quietHours?.enabled) return false;
  
  const now = new Date();
  const londonTime = new Date(now.toLocaleString('en-US', { timeZone: 'Europe/London' }));
  const hour = londonTime.getHours();
  const minute = londonTime.getMinutes();
  const currentMinutes = hour * 60 + minute;
  
  const [startHour, startMin] = preferences.quietHours.start.split(':').map(Number);
  const [endHour, endMin] = preferences.quietHours.end.split(':').map(Number);
  const startMinutes = startHour * 60 + startMin;
  const endMinutes = endHour * 60 + endMin;
  
  if (startMinutes > endMinutes) {
    return currentMinutes >= startMinutes || currentMinutes < endMinutes;
  } else {
    return currentMinutes >= startMinutes && currentMinutes < endMinutes;
  }
}

async function sendNotification(userId, notification, data = {}) {
  try {
    const tokens = await getUserTokens(userId);
    if (tokens.length === 0) {
      console.log(`No FCM tokens for user ${userId}`);
      return;
    }
    
    const preferences = await getUserPreferences(userId);
    
    if (!data.critical && isInQuietHours(preferences)) {
      console.log(`User ${userId} is in quiet hours, skipping notification`);
      return;
    }
    
    const message = {
      notification: {
        title: notification.title,
        body: notification.body,
        imageUrl: notification.imageUrl || null,
      },
      data: {
        ...data,
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      android: {
        priority: 'high',
        notification: {
          channelId: data.channelId || 'default',
          sound: 'default',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
          },
        },
      },
      tokens: tokens,
    };
    
    const response = await messaging.sendEachForMulticast(message);
    console.log(`Sent notification to ${response.successCount} devices`);
    
    return response;
  } catch (error) {
    console.error('Error sending notification:', error);
    return null;
  }
}

function formatEventTitle(event) {
  return event.title || 'Event';
}

function formatEventVenue(event) {
  if (event.venueName) return event.venueName;
  if (event.area) return event.area;
  return 'Wembley';
}

function formatEventTime(timestamp) {
  const date = timestamp.toDate();
  const options = {
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
    timeZone: 'Europe/London',
  };
  return date.toLocaleString('en-GB', options);
}

function formatEventDate(timestamp) {
  const date = timestamp.toDate();
  const options = {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    timeZone: 'Europe/London',
  };
  return date.toLocaleString('en-GB', options);
}

// ==========================================
// STRIPE PAYMENT FUNCTIONS
// ==========================================

exports.createCheckoutSession = onCall(
  { region: "us-central1", secrets: [STRIPE_SECRET] },
  async (request) => {
    const uid = request.auth?.uid || null;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const bookingId = request.data?.bookingId ? String(request.data.bookingId) : null;
    if (!bookingId) throw new HttpsError("invalid-argument", "bookingId is required.");

    const stripe = new Stripe(STRIPE_SECRET.value(), { apiVersion: "2024-06-20" });

    const bookingRef = admin.firestore().collection("parking_bookings").doc(bookingId);
    const bookingSnap = await bookingRef.get();
    if (!bookingSnap.exists) throw new HttpsError("not-found", "Booking not found.");

    const booking = bookingSnap.data() || {};

    if (booking.userId !== uid) {
      throw new HttpsError("permission-denied", "Not your booking.");
    }

    if (booking.status !== "pending_payment") {
      throw new HttpsError("failed-precondition", "Booking not pending payment.");
    }

    const expiresAt =
      booking.expiresAt && typeof booking.expiresAt.toDate === "function"
        ? booking.expiresAt.toDate()
        : null;

    if (expiresAt && expiresAt.getTime() < Date.now()) {
      await bookingRef.update({
        status: "expired",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      throw new HttpsError("deadline-exceeded", "Booking expired.");
    }

    const spaceId = String(booking.spaceId || "").trim();
    const hours = Number(booking.hours || 0);

    if (!spaceId) throw new HttpsError("invalid-argument", "spaceId missing on booking.");
    if (!Number.isFinite(hours) || hours <= 0 || hours > 24) {
      throw new HttpsError("invalid-argument", "Invalid hours.");
    }

    const spaceSnap = await admin.firestore().collection("parking_spaces").doc(spaceId).get();
    if (!spaceSnap.exists) throw new HttpsError("not-found", "Parking space not found.");

    const space = spaceSnap.data() || {};
    const statusLc = String(space.status_lc || "").toLowerCase();
    if (statusLc !== "approved") {
      throw new HttpsError("failed-precondition", "Space not approved for booking.");
    }

    const hourlyRate = Number(space.hourly_rate_gbp || 0);
    if (!Number.isFinite(hourlyRate) || hourlyRate <= 0) {
      throw new HttpsError("failed-precondition", "Invalid hourly rate.");
    }

    const unitAmount = toPence(hourlyRate);
    const totalAmountPence = toPence(hourlyRate * hours);

    await bookingRef.update({
      hourlyRateSnapshot: hourlyRate,
      totalAmountSnapshot: totalAmountPence / 100,
      currency: "gbp",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const title = String(space.title || "Private Parking");

    const base = getFunctionsBaseUrl();
    const successUrl = `${base}/stripeSuccess?bookingId=${encodeURIComponent(bookingId)}`;
    const cancelUrl = `${base}/stripeCancel?bookingId=${encodeURIComponent(bookingId)}`;

    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      payment_method_types: ["card"],
      line_items: [
        {
          price_data: {
            currency: "gbp",
            unit_amount: unitAmount,
            product_data: {
              name: `${title} (Hourly Parking)`,
              description: `Booking for ${hours} hour(s)`,
            },
          },
          quantity: hours,
        },
      ],
      success_url: successUrl,
      cancel_url: cancelUrl,
      metadata: {
        bookingId,
        spaceId,
        uid,
        hours: String(hours),
        totalPence: String(totalAmountPence),
      },
    });

    await bookingRef.update({
      stripeSessionId: session.id,
      stripeCheckoutUrl: session.url,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { url: session.url, sessionId: session.id };
  }
);

exports.stripeWebhook = onRequest(
  { region: "us-central1", secrets: [STRIPE_SECRET, STRIPE_WEBHOOK_SECRET] },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    const stripe = new Stripe(STRIPE_SECRET.value(), { apiVersion: "2024-06-20" });

    let event;
    try {
      const sig = req.headers["stripe-signature"];
      event = stripe.webhooks.constructEvent(req.rawBody, sig, STRIPE_WEBHOOK_SECRET.value());
    } catch (err) {
      res.status(400).send(`Webhook Error: ${err.message}`);
      return;
    }

    try {
      if (event.type === "checkout.session.completed") {
        const session = event.data.object;
        const bookingId = session?.metadata?.bookingId || null;

        if (bookingId) {
          await admin.firestore().collection("parking_bookings").doc(bookingId).update({
            status: "confirmed",
            paymentStatus: "paid",
            paidAt: admin.firestore.FieldValue.serverTimestamp(),
            stripeSessionId: session.id,
            paymentIntentId: session.payment_intent || null,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      }

      if (event.type === "checkout.session.expired") {
        const session = event.data.object;
        const bookingId = session?.metadata?.bookingId || null;

        if (bookingId) {
          await admin.firestore().collection("parking_bookings").doc(bookingId).update({
            status: "expired",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      }

      res.json({ received: true });
    } catch (e) {
      res.status(500).send(`Handler Error: ${e.message}`);
    }
  }
);

exports.stripeSuccess = onRequest({ region: "us-central1" }, async (req, res) => {
  const bookingId = String(req.query.bookingId || "");
  const redirectUrl = `eventdiscovery://payment-success?bookingId=${encodeURIComponent(bookingId)}`;
  res.redirect(303, redirectUrl);
});

exports.stripeCancel = onRequest({ region: "us-central1" }, async (req, res) => {
  const bookingId = String(req.query.bookingId || "");
  const redirectUrl = `eventdiscovery://payment-cancel?bookingId=${encodeURIComponent(bookingId)}`;
  res.redirect(303, redirectUrl);
});

exports.fetchDiningPlaces = onCall(
  { region: "us-central1", secrets: [GOOGLE_API_KEY] },
  async (request) => {
    const keyword = request.data?.keyword || "";
    const types = request.data?.types || ["restaurant"];

    if (!keyword && (!types || types.length === 0)) {
      throw new HttpsError("invalid-argument", "Must provide keyword or types");
    }

    const apiKey = GOOGLE_API_KEY.value();
    if (!apiKey) {
      throw new HttpsError("internal", "Google API Key not configured");
    }

    const lat = 51.5560;
    const lng = -0.2795;
    const radius = 3000;
    const location = `${lat},${lng}`;

    const params = {
      location,
      radius: String(radius),
      key: apiKey,
    };

    if (keyword) {
      params.keyword = keyword;
    }
    if (types && types.length > 0) {
      params.type = types.join("|");
    }

    const url = "https://maps.googleapis.com/maps/api/place/nearbysearch/json";

    try {
      const response = await axios.get(url, { params });
      const data = response.data || {};

      if (data.status !== "OK" && data.status !== "ZERO_RESULTS") {
        console.error("Places API error:", data.status, data.error_message);
        throw new HttpsError("internal", `Places API: ${data.status}`);
      }

      if (!data.results || data.results.length === 0) {
        return { places: [] };
      }

      const places = data.results.map((p) => {
        let photoRef = null;
        if (p.photos && p.photos.length > 0 && p.photos[0].photo_reference) {
          photoRef = p.photos[0].photo_reference;
        }

        return {
          place_id: p.place_id || "",
          name: p.name || "",
          vicinity: p.vicinity || "",
          rating: typeof p.rating === "number" ? p.rating : null,
          user_ratings_total:
            typeof p.user_ratings_total === "number" ? p.user_ratings_total : null,
          price_level: typeof p.price_level === "number" ? p.price_level : null,
          types: Array.isArray(p.types) ? p.types : [],
          photoReference: photoRef,
        };
      });

      return { places };
    } catch (err) {
      console.error("fetchDiningPlaces error:", err);
      if (err instanceof HttpsError) {
        throw err;
      }
      throw new HttpsError("internal", `Failed to fetch places: ${err.message}`);
    }
  }
);

exports.getPhotoUrl = onCall(
  { region: "us-central1", secrets: [GOOGLE_API_KEY] },
  async (request) => {
    let rawPhotoRef = request.data?.photoReference;

    if (!rawPhotoRef) {
      throw new HttpsError("invalid-argument", "photoReference is required");
    }

    const cleaned = normalizePhotoReference(rawPhotoRef);
    if (!cleaned) {
      throw new HttpsError("invalid-argument", "Could not parse photo_reference");
    }

    const apiKey = GOOGLE_API_KEY.value();
    if (!apiKey) {
      throw new HttpsError("internal", "Google API Key not configured");
    }

    const maxwidth = 800;
    const url = `https://maps.googleapis.com/maps/api/place/photo?maxwidth=${maxwidth}&photo_reference=${encodeURIComponent(
      cleaned
    )}&key=${apiKey}`;

    return { photoUrl: url };
  }
);

// ==========================================
// NOTIFICATION CLOUD FUNCTIONS (v2 syntax)
// ==========================================

// Daily Event Digest (9 AM)
exports.dailyEventDigest = onSchedule(
  {
    schedule: '0 9 * * *',
    timeZone: 'Europe/London',
    region: 'us-central1',
  },
  async (event) => {
    console.log('Running daily event digest at 9 AM');
    
    try {
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      const tomorrow = new Date(today);
      tomorrow.setDate(tomorrow.getDate() + 1);
      
      const eventsSnap = await db
        .collection('events_wembley')
        .where('startDateTime', '>=', admin.firestore.Timestamp.fromDate(today))
        .where('startDateTime', '<', admin.firestore.Timestamp.fromDate(tomorrow))
        .orderBy('startDateTime', 'asc')
        .get();
      
      if (eventsSnap.empty) {
        console.log('No events today');
        return null;
      }
      
      const events = eventsSnap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
      const usersSnap = await db.collection('users').get();
      
      const promises = usersSnap.docs.map(async (userDoc) => {
        const userId = userDoc.id;
        const preferences = await getUserPreferences(userId);
        
        if (!preferences.events?.dailyDigest) {
          return null;
        }
        
        const eventCount = events.length;
        const firstEvent = events[0];
        
        let body;
        if (eventCount === 1) {
          body = `${formatEventTitle(firstEvent)} at ${formatEventTime(firstEvent.startDateTime)}`;
        } else if (eventCount === 2) {
          body = `${formatEventTitle(events[0])} and 1 other event today`;
        } else {
          body = `${formatEventTitle(firstEvent)} and ${eventCount - 1} other events today`;
        }
        
        return sendNotification(userId, {
          title: `📅 ${eventCount} event${eventCount > 1 ? 's' : ''} at Wembley today`,
          body: body,
          imageUrl: firstEvent.imageUrl,
        }, {
          type: 'daily_digest',
          eventCount: String(eventCount),
          channelId: 'events',
        });
      });
      
      await Promise.all(promises);
      console.log('Daily digest sent');
      return null;
      
    } catch (error) {
      console.error('Error in daily digest:', error);
      return null;
    }
  }
);

// Event Reminder (1 Hour Before)
exports.eventReminder1Hour = onSchedule(
  {
    schedule: 'every 5 minutes',
    timeZone: 'Europe/London',
    region: 'us-central1',
  },
  async (event) => {
    console.log('Checking for events starting in 1 hour');
    
    try {
      const now = new Date();
      const oneHourFromNow = new Date(now.getTime() + 60 * 60 * 1000);
      const oneHourFiveMinFromNow = new Date(now.getTime() + 65 * 60 * 1000);
      
      const eventsSnap = await db
        .collection('events_wembley')
        .where('startDateTime', '>=', admin.firestore.Timestamp.fromDate(oneHourFromNow))
        .where('startDateTime', '<', admin.firestore.Timestamp.fromDate(oneHourFiveMinFromNow))
        .get();
      
      if (eventsSnap.empty) {
        console.log('No events starting in 1 hour');
        return null;
      }
      
      const events = eventsSnap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
      console.log(`Found ${events.length} events starting in 1 hour`);
      
      const promises = events.map(async (event) => {
        const savedBySnap = await db
          .collection('users')
          .where('savedEvents', 'array-contains', event.id)
          .get();
        
        if (savedBySnap.empty) {
          console.log(`No users saved event ${event.id}`);
          return null;
        }
        
        const userPromises = savedBySnap.docs.map(async (userDoc) => {
          const userId = userDoc.id;
          const preferences = await getUserPreferences(userId);
          
          if (!preferences.events?.reminders) {
            return null;
          }
          
          return sendNotification(userId, {
            title: `🎫 Event Starting Soon!`,
            body: `${formatEventTitle(event)} starts in 1 hour at ${formatEventVenue(event)}`,
            imageUrl: event.imageUrl,
          }, {
            type: 'event_reminder',
            eventId: event.id,
            timeUntil: '1hour',
            channelId: 'events',
          });
        });
        
        return Promise.all(userPromises);
      });
      
      await Promise.all(promises);
      console.log('Event reminders sent');
      return null;
      
    } catch (error) {
      console.error('Error in event reminder:', error);
      return null;
    }
  }
);

// Pre-Arrival Info (6 PM Day Before)
exports.preArrivalInfo = onSchedule(
  {
    schedule: '0 18 * * *',
    timeZone: 'Europe/London',
    region: 'us-central1',
  },
  async (event) => {
    console.log('Sending pre-arrival info at 6 PM');
    
    try {
      const tomorrow = new Date();
      tomorrow.setDate(tomorrow.getDate() + 1);
      tomorrow.setHours(0, 0, 0, 0);
      const dayAfter = new Date(tomorrow);
      dayAfter.setDate(dayAfter.getDate() + 1);
      
      const eventsSnap = await db
        .collection('events_wembley')
        .where('startDateTime', '>=', admin.firestore.Timestamp.fromDate(tomorrow))
        .where('startDateTime', '<', admin.firestore.Timestamp.fromDate(dayAfter))
        .orderBy('startDateTime', 'asc')
        .get();
      
      if (eventsSnap.empty) {
        console.log('No events tomorrow');
        return null;
      }
      
      const events = eventsSnap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
      console.log(`Found ${events.length} events tomorrow`);
      
      const promises = events.map(async (event) => {
        const savedBySnap = await db
          .collection('users')
          .where('savedEvents', 'array-contains', event.id)
          .get();
        
        if (savedBySnap.empty) {
          return null;
        }
        
        const userPromises = savedBySnap.docs.map(async (userDoc) => {
          const userId = userDoc.id;
          const preferences = await getUserPreferences(userId);
          
          if (!preferences.events?.preArrival) {
            return null;
          }
          
          const eventTime = formatEventTime(event.startDateTime);
          const venue = formatEventVenue(event);
          
          return sendNotification(userId, {
            title: `📍 Event Tomorrow`,
            body: `${formatEventTitle(event)} at ${eventTime}\nVenue: ${venue}`,
            imageUrl: event.imageUrl,
          }, {
            type: 'pre_arrival',
            eventId: event.id,
            channelId: 'events',
          });
        });
        
        return Promise.all(userPromises);
      });
      
      await Promise.all(promises);
      console.log('Pre-arrival info sent');
      return null;
      
    } catch (error) {
      console.error('Error in pre-arrival info:', error);
      return null;
    }
  }
);

// When User Saves Event
exports.onEventSaved = onDocumentCreated(
  {
    document: 'users/{userId}/savedEvents/{eventId}',
    region: 'us-central1',
  },
  async (event) => {
    const userId = event.params.userId;
    const eventId = event.params.eventId;
    
    console.log(`User ${userId} saved event ${eventId}`);
    
    try {
      const eventDoc = await db.collection('events_wembley').doc(eventId).get();
      
      if (!eventDoc.exists) {
        console.log('Event not found');
        return null;
      }
      
      const evt = { id: eventDoc.id, ...eventDoc.data() };
      
      await sendNotification(userId, {
        title: `✅ Event Saved`,
        body: `${formatEventTitle(evt)} on ${formatEventDate(evt.startDateTime)}`,
        imageUrl: evt.imageUrl,
      }, {
        type: 'event_saved',
        eventId: evt.id,
        channelId: 'events',
      });
      
      return null;
    } catch (error) {
      console.error('Error in onEventSaved:', error);
      return null;
    }
  }
);

// Zone Chat Message
exports.onZoneMessage = onDocumentCreated(
  {
    document: 'zones/{zoneId}/messages/{messageId}',
    region: 'us-central1',
  },
  async (event) => {
    const message = event.data.data();
    const zoneId = event.params.zoneId;
    
    console.log(`New message in zone ${zoneId}`);
    
    try {
      const zoneDoc = await db.collection('zones').doc(zoneId).get();
      if (!zoneDoc.exists) {
        console.log('Zone not found');
        return null;
      }
      
      const zoneName = zoneDoc.data().name || 'Community';
      
      const membersSnap = await db
        .collection('zones')
        .doc(zoneId)
        .collection('members')
        .where('uid', '!=', message.senderId)
        .get();
      
      if (membersSnap.empty) {
        console.log('No other members in zone');
        return null;
      }
      
      const promises = membersSnap.docs.map(async (memberDoc) => {
        const member = memberDoc.data();
        const userId = member.uid;
        
        const preferences = await getUserPreferences(userId);
        if (!preferences.messages?.zoneChat) {
          return null;
        }
        
        return sendNotification(userId, {
          title: `🏘️ ${message.senderName} in ${zoneName}`,
          body: message.text,
        }, {
          type: 'zone_message',
          zoneId: zoneId,
          messageId: event.data.id,
          senderId: message.senderId,
          channelId: 'messages',
        });
      });
      
      await Promise.all(promises);
      console.log('Zone message notifications sent');
      return null;
      
    } catch (error) {
      console.error('Error in onZoneMessage:', error);
      return null;
    }
  }
);

// Parking Booking Confirmation
exports.onParkingBooked = onDocumentCreated(
  {
    document: 'parking_bookings/{bookingId}',
    region: 'us-central1',
  },
  async (event) => {
    const booking = event.data.data();
    
    console.log(`New parking booking for user ${booking.userId}`);
    
    try {
      const bookingDate = booking.bookingDate.toDate();
      const dateStr = bookingDate.toLocaleDateString('en-GB', {
        weekday: 'short',
        month: 'short',
        day: 'numeric',
        timeZone: 'Europe/London',
      });
      const timeStr = booking.bookingTime || '';
      
      await sendNotification(booking.userId, {
        title: `🅿️ Parking Confirmed`,
        body: `Your spot at ${booking.location || 'Wembley'} is booked for ${dateStr} ${timeStr}`,
      }, {
        type: 'parking_confirmed',
        bookingId: event.data.id,
        critical: true,
        channelId: 'parking',
      });
      
      return null;
    } catch (error) {
      console.error('Error in onParkingBooked:', error);
      return null;
    }
  }
);

// Provider Report Alert
exports.onReportCreated = onDocumentCreated(
  {
    document: 'zones/{zoneId}/reports/{reportId}',
    region: 'us-central1',
  },
  async (event) => {
    const report = event.data.data();
    const zoneId = event.params.zoneId;
    
    console.log(`New report in zone ${zoneId}`);
    
    try {
      const providersSnap = await db
        .collection('zones')
        .doc(zoneId)
        .collection('members')
        .where('role', '==', 'provider')
        .get();
      
      if (providersSnap.empty) {
        console.log('No providers in zone');
        return null;
      }
      
      const zoneDoc = await db.collection('zones').doc(zoneId).get();
      const zoneName = zoneDoc.data()?.name || 'Community';
      
      const promises = providersSnap.docs.map(async (providerDoc) => {
        const provider = providerDoc.data();
        
        const preferences = await getUserPreferences(provider.uid);
        if (!preferences.moderation?.reports) {
          return null;
        }
        
        return sendNotification(provider.uid, {
          title: `🚩 New Report in ${zoneName}`,
          body: `User reported for ${report.reason}`,
        }, {
          type: 'provider_report',
          zoneId: zoneId,
          reportId: event.data.id,
          critical: true,
          channelId: 'moderation',
        });
      });
      
      await Promise.all(promises);
      console.log('Provider report alerts sent');
      return null;
      
    } catch (error) {
      console.error('Error in onReportCreated:', error);
      return null;
    }
  }
);