const admin = require("firebase-admin");
const Stripe = require("stripe");
const axios = require("axios");
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");

// Initialize Firebase Admin (only once)
admin.initializeApp();

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

/**
 * Make Firestore input safe:
 * - trim whitespace/newlines
 * - remove surrounding quotes
 * - if it's a URL, extract photo_reference
 * - if it contains photo_reference=..., extract it
 */
function normalizePhotoReference(input) {
  if (input == null) return null;

  let s = String(input).trim();

  // Strip surrounding quotes if stored like "...."
  if (
    (s.startsWith('"') && s.endsWith('"')) ||
    (s.startsWith("'") && s.endsWith("'"))
  ) {
    s = s.slice(1, -1).trim();
  }

  // If it's a URL, extract photo_reference
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

  // If it contains photo_reference=... somewhere inside
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

// ==========================================
// ✅ RESTAURANT PHOTO CACHING FUNCTIONS
// ==========================================

exports.cacheRestaurantPhoto = onCall(
  { region: "us-central1", secrets: [GOOGLE_API_KEY] },
  async (request) => {
    try {
      const { photoReference, restaurantId } = request.data;

      if (!photoReference || !restaurantId) {
        throw new HttpsError("invalid-argument", "photoReference and restaurantId are required");
      }

      const bucket = admin.storage().bucket();
      const fileName = `restaurant_photos/${restaurantId}.jpg`;
      const file = bucket.file(fileName);

      const [exists] = await file.exists();
      if (exists) {
        await file.makePublic();
        const publicUrl = `https://storage.googleapis.com/${bucket.name}/${fileName}`;
        return { photoUrl: publicUrl, cached: true, message: "Photo already cached" };
      }

      const apiKey = GOOGLE_API_KEY.value();

      // Normalize stored value
      const normalized = normalizePhotoReference(photoReference);
      const actualPhotoRef = await getPhotoReferenceFromPlaceId(normalized);

      if (!actualPhotoRef) {
        throw new HttpsError("failed-precondition", "No valid photo reference available.");
      }

      const safePhotoRef = encodeURIComponent(String(actualPhotoRef).trim());

      const googleUrl =
        `https://maps.googleapis.com/maps/api/place/photo?maxwidth=800` +
        `&photo_reference=${safePhotoRef}` +
        `&key=${encodeURIComponent(apiKey)}`;

      console.log(`Downloading image from Google Places API for ${restaurantId}...`);
      const response = await axios.get(googleUrl, {
        responseType: "arraybuffer",
        timeout: 15000,
        maxRedirects: 5,
        validateStatus: () => true, // we'll handle status
      });

      if (response.status >= 400) {
        const snippet = Buffer.from(response.data || "").toString("utf8").slice(0, 200);
        console.error(`Google photo error ${response.status} for ${restaurantId}: ${snippet}`);
        throw new Error(`Google HTTP ${response.status}`);
      }

      await file.save(Buffer.from(response.data), {
        metadata: {
          contentType: "image/jpeg",
          cacheControl: "public, max-age=31536000",
        },
      });

      await file.makePublic();

      const publicUrl = `https://storage.googleapis.com/${bucket.name}/${fileName}`;

      await admin.firestore().collection("Dining_wembley").doc(restaurantId).update({
        cachedPhotoUrl: publicUrl,
        photoReferenceActual: String(actualPhotoRef).trim(),
        photoCachedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return { photoUrl: publicUrl, cached: false, message: "Photo successfully cached" };
    } catch (error) {
      console.error("Error caching photo:", error);
      throw new HttpsError("internal", `Failed to cache photo: ${error.message}`);
    }
  }
);

exports.batchCacheRestaurantPhotos = onRequest(
  { region: "us-central1", secrets: [GOOGLE_API_KEY] },
  async (req, res) => {
    try {
      const snapshot = await admin
        .firestore()
        .collection("Dining_wembley")
        .where("photoReference", "!=", null)
        .get();

      let successCount = 0;
      let errorCount = 0;
      let skippedCount = 0;
      const errors = [];

      const promises = snapshot.docs.map(async (doc) => {
        const data = doc.data();

        if (data.cachedPhotoUrl) {
          skippedCount++;
          return;
        }

        try {
          const result = await cachePhotoInternal(data.photoReference, doc.id);
          if (result.success) successCount++;
          else {
            errorCount++;
            errors.push({ id: doc.id, reason: result.error || "unknown" });
          }
        } catch (err) {
          errorCount++;
          errors.push({ id: doc.id, reason: err?.message || "exception" });
        }
      });

      await Promise.all(promises);

      res.json({
        total: snapshot.size,
        success: successCount,
        errors: errorCount,
        skipped: skippedCount,
        message: "Batch caching completed",
        errorSamples: errors.slice(0, 10),
      });
    } catch (error) {
      console.error("Batch caching error:", error);
      res.status(500).json({ error: error.message });
    }
  }
);

async function getPhotoReferenceFromPlaceId(value) {
  const apiKey = GOOGLE_API_KEY.value();
  const raw = value == null ? "" : String(value);

  // Normalize again here for safety
  let clean = raw.trim().replace(/^google:/, "");

  // If it doesn't look like a Place ID, assume it's already a photo reference
  if (!clean.startsWith("ChIJ")) {
    const pr = normalizePhotoReference(clean);
    return pr ? pr.trim() : null;
  }

  // Place Details -> photos[0].photo_reference
  try {
    const detailsUrl =
      `https://maps.googleapis.com/maps/api/place/details/json` +
      `?place_id=${encodeURIComponent(clean)}` +
      `&fields=photos` +
      `&key=${encodeURIComponent(apiKey)}`;

    const response = await axios.get(detailsUrl, {
      timeout: 15000,
      validateStatus: () => true,
    });

    if (response.status >= 400) {
      console.error(`Place Details HTTP ${response.status} for ${clean}`);
      return null;
    }

    if (response.data.status === "OK" && response.data.result?.photos?.length > 0) {
      return response.data.result.photos[0].photo_reference;
    }

    console.log(`No photos for Place ID ${clean}, status=${response.data.status}`);
    return null;
  } catch (error) {
    console.error(`Error fetching place details: ${error.message}`);
    return null;
  }
}

async function cachePhotoInternal(photoReferenceInput, restaurantId) {
  try {
    const bucket = admin.storage().bucket();
    const fileName = `restaurant_photos/${restaurantId}.jpg`;
    const file = bucket.file(fileName);

    const [exists] = await file.exists();
    if (exists) return { success: true, cached: true };

    const normalized = normalizePhotoReference(photoReferenceInput);
    const actualPhotoRef = await getPhotoReferenceFromPlaceId(normalized);

    if (!actualPhotoRef) {
      return { success: false, error: "No photo available" };
    }

    const apiKey = GOOGLE_API_KEY.value();
    const safePhotoRef = encodeURIComponent(String(actualPhotoRef).trim());

    const googleUrl =
      `https://maps.googleapis.com/maps/api/place/photo?maxwidth=800` +
      `&photo_reference=${safePhotoRef}` +
      `&key=${encodeURIComponent(apiKey)}`;

    const response = await axios.get(googleUrl, {
      responseType: "arraybuffer",
      timeout: 15000,
      maxRedirects: 5,
      validateStatus: () => true,
    });

    if (response.status >= 400) {
      const snippet = Buffer.from(response.data || "").toString("utf8").slice(0, 200);
      return { success: false, error: `Google HTTP ${response.status}: ${snippet}` };
    }

    await file.save(Buffer.from(response.data), {
      metadata: {
        contentType: "image/jpeg",
        cacheControl: "public, max-age=31536000",
      },
    });

    await file.makePublic();

    const publicUrl = `https://storage.googleapis.com/${bucket.name}/${fileName}`;

    await admin.firestore().collection("Dining_wembley").doc(restaurantId).update({
      cachedPhotoUrl: publicUrl,
      photoReferenceActual: String(actualPhotoRef).trim(),
      photoCachedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true, cached: false };
  } catch (error) {
    return { success: false, error: error?.message || "unknown error" };
  }
}
