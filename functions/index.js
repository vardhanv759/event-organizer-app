const admin = require("firebase-admin");
admin.initializeApp();

const Stripe = require("stripe");
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");

// ✅ Secrets (stored in Google Secret Manager)
const STRIPE_SECRET = defineSecret("STRIPE_SECRET");
const STRIPE_WEBHOOK_SECRET = defineSecret("STRIPE_WEBHOOK_SECRET");

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
 * Callable: createCheckoutSession
 * Input: { bookingId }
 * Output: { url, sessionId }
 */
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

    // ✅ Your booking docs use userId (not user_uid)
    if (booking.userId !== uid) {
      throw new HttpsError("permission-denied", "Not your booking.");
    }

    if (booking.status !== "pending_payment") {
      throw new HttpsError("failed-precondition", "Booking not pending payment.");
    }

    // Optional expiry check
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

    // ✅ Snapshot pricing into booking (server-side truth)
    await bookingRef.update({
      hourlyRateSnapshot: hourlyRate,
      totalAmountSnapshot: totalAmountPence / 100,
      currency: "gbp",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const title = String(space.title || "Private Parking");

    // ✅ No Firebase Hosting needed. We return to our Cloud Function endpoints.
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

/**
 * Stripe Webhook
 * IMPORTANT:
 * - Stripe endpoint must be: https://us-central1-event-discrovery-app.cloudfunctions.net/stripeWebhook
 * - Secret must match the webhook signing secret from Stripe for that endpoint.
 */
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

/**
 * Success + Cancel return endpoints.
 * These are used by Stripe after payment.
 * We redirect to a custom scheme that the WebView intercepts and closes.
 */
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
