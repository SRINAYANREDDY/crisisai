// functions/index.js
// ---------------------------------------------------------------------------
// Firebase Cloud Functions — SOS Dispatch FCM Notification
//
// SETUP
// ─────
// 1.  cd functions && npm install
// 2.  firebase deploy --only functions
//
// TRIGGER
// ───────
// Fires on every new document in `sos_events/{sosId}`.
// Reads matched_volunteer_ids[], looks up each volunteer's fcmToken,
// and sends a high-priority FCM data message.
//
// FIRESTORE  `sos_events` DOCUMENT SCHEMA
// ────────────────────────────────────────
// {
//   incident_type:         "Fire",
//   severity:              4,
//   severity_label:        "High",
//   required_skills:       ["firefighting","rescue","first_aid"],
//   immediate_actions:     ["Evacuate...","Call fire dept..."],
//   location_text:         "Near Ranipet Bus Stand",
//   location_geopoint:     GeoPoint,
//   reporter_uid:          "abc123",
//   matched_volunteer_ids: ["uid1","uid2","uid3"],   ← written by your app
//   responses:             {},                        ← filled by volunteers
//   created_at:            Timestamp,
// }
//
// npm packages needed (package.json already lists them):
//   firebase-admin, firebase-functions
// ---------------------------------------------------------------------------

const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { initializeApp }     = require('firebase-admin/app');
const { getFirestore }      = require('firebase-admin/firestore');
const { getMessaging }      = require('firebase-admin/messaging');

initializeApp();

const db  = getFirestore();
const fcm = getMessaging();

// ---------------------------------------------------------------------------
// Trigger: new SOS event created
// ---------------------------------------------------------------------------

exports.dispatchSOSNotification = onDocumentCreated(
  'sos_events/{sosId}',
  async (event) => {
    const sosId = event.params.sosId;
    const data  = event.data?.data();

    if (!data) {
      console.log(`[Dispatch] No data for ${sosId}`);
      return null;
    }

    const volunteerIds = data.matched_volunteer_ids ?? [];
    if (volunteerIds.length === 0) {
      console.log(`[Dispatch] No matched volunteers for ${sosId}`);
      return null;
    }

    console.log(`[Dispatch] SOS ${sosId} → ${volunteerIds.length} volunteers`);

    // ── Fetch FCM tokens for matched volunteers ───────────────────────────
    const tokenDocs = await Promise.all(
      volunteerIds.map((uid) =>
        db.collection('volunteers').doc(uid).get()
      )
    );

    const messages = [];

    for (const doc of tokenDocs) {
      if (!doc.exists) continue;
      const vData = doc.data();
      const token = vData?.fcmToken;
      if (!token) continue;

      // Distance is unknown at function level; write 0.0 — the app can
      // recalculate from location_geopoint if needed.
      const distanceKm = '0.0'; // future: compute server-side with haversine

      messages.push({
        token,
        // ── Android high-priority ──────────────────────────────────────
        android: {
          priority: 'high',
          notification: {
            channelId: 'sos_dispatch',
            title: `🚨 ${data.incident_type ?? 'Emergency'} Dispatch`,
            body: `${data.severity_label ?? 'Moderate'} severity — respond now`,
            color: '#E24B4A',
          },
          data: buildPayload(data, sosId, distanceKm),
        },
        // ── iOS high-priority ──────────────────────────────────────────
        apns: {
          headers: { 'apns-priority': '10' },
          payload: {
            aps: {
              alert: {
                title: `🚨 ${data.incident_type ?? 'Emergency'} Dispatch`,
                body: `${data.severity_label ?? 'Moderate'} severity — respond now`,
              },
              sound: 'default',
              badge: 1,
              'content-available': 1,
            },
            ...buildPayload(data, sosId, distanceKm),
          },
        },
        // ── Web / other ────────────────────────────────────────────────
        data: buildPayload(data, sosId, distanceKm),
      });
    }

    if (messages.length === 0) {
      console.log(`[Dispatch] No FCM tokens found for SOS ${sosId}`);
      return null;
    }

    // ── Send in batches of 500 (FCM limit) ───────────────────────────────
    const BATCH = 500;
    let successCount = 0;
    let failCount    = 0;

    for (let i = 0; i < messages.length; i += BATCH) {
      const batch = messages.slice(i, i + BATCH);
      const response = await fcm.sendEach(batch);

      successCount += response.successCount;
      failCount    += response.failureCount;

      // Clean up stale tokens
      for (let j = 0; j < response.responses.length; j++) {
        const r = response.responses[j];
        if (!r.success) {
          const errCode = r.error?.code ?? '';
          if (
            errCode === 'messaging/invalid-registration-token' ||
            errCode === 'messaging/registration-token-not-registered'
          ) {
            const uid = volunteerIds[i + j];
            if (uid) {
              await db.collection('volunteers').doc(uid).update({
                fcmToken: null,
              });
              console.log(`[Dispatch] Removed stale token for ${uid}`);
            }
          }
        }
      }
    }

    console.log(
      `[Dispatch] SOS ${sosId}: ${successCount} sent, ${failCount} failed`
    );

    // ── Update SOS doc with dispatch timestamp ────────────────────────────
    await event.data.ref.update({
      dispatched_at:   new Date(),
      dispatch_count:  successCount,
    });

    return null;
  }
);

// ---------------------------------------------------------------------------
// Helper: build FCM data payload (all values must be strings for FCM data)
// ---------------------------------------------------------------------------

function buildPayload(data, sosId, distanceKm) {
  return {
    sos_id:           sosId,
    incident_type:    String(data.incident_type    ?? 'Emergency'),
    severity:         String(data.severity         ?? 3),
    severity_label:   String(data.severity_label   ?? 'Moderate'),
    distance_km:      String(distanceKm),
    location:         String(data.location_text    ?? 'Nearby'),
    required_skills:  (data.required_skills   ?? []).join(','),
    immediate_actions:(data.immediate_actions ?? []).join('|'),
  };
}
