// fcm_dispatch_service.dart
// ---------------------------------------------------------------------------
// Feature 1 — FCM Push Notifications for SOS Dispatch & Alerts
// ---------------------------------------------------------------------------

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ---------------------------------------------------------------------------
// Background message handler — MUST be a top-level function
// ---------------------------------------------------------------------------

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background message: ${message.messageId}');
}

// ---------------------------------------------------------------------------
// Dispatch payload model
// ---------------------------------------------------------------------------

class DispatchPayload {
  final String incidentType;
  final int severity;
  final String severityLabel;
  final double distanceKm;
  final String location;
  final List<String> requiredSkills;
  final List<String> immediateActions;
  final String sosId;
  final DateTime receivedAt;

  const DispatchPayload({
    required this.incidentType,
    required this.severity,
    required this.severityLabel,
    required this.distanceKm,
    required this.location,
    required this.requiredSkills,
    required this.immediateActions,
    required this.sosId,
    required this.receivedAt,
  });

  Color get severityColor {
    switch (severity) {
      case 1:
      case 2:
        return const Color(0xFF1D9E75);
      case 3:
        return const Color(0xFFBA7517);
      case 4:
      case 5:
        return const Color(0xFFE24B4A);
      default:
        return const Color(0xFF6B6B6B);
    }
  }

  factory DispatchPayload.fromMessage(RemoteMessage msg) {
    final d = msg.data;
    return DispatchPayload(
      incidentType: d['incident_type'] as String? ?? 'Emergency',
      severity: int.tryParse(d['severity'] as String? ?? '3') ?? 3,
      severityLabel: d['severity_label'] as String? ?? 'Moderate',
      distanceKm: double.tryParse(d['distance_km'] as String? ?? '0.0') ?? 0.0,
      location: d['location'] as String? ?? 'Nearby',
      requiredSkills: (d['required_skills'] as String? ?? '')
          .split(',')
          .where((s) => s.isNotEmpty)
          .toList(),
      immediateActions: (d['immediate_actions'] as String? ?? '')
          .split('|')
          .where((s) => s.isNotEmpty)
          .toList(),
      sosId: d['sos_id'] as String? ?? '',
      receivedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'incident_type': incidentType,
        'severity': severity,
        'severity_label': severityLabel,
        'distance_km': distanceKm,
        'location': location,
        'required_skills': requiredSkills,
        'immediate_actions': immediateActions,
        'sos_id': sosId,
        'received_at': receivedAt.toIso8601String(),
      };
}

// ---------------------------------------------------------------------------
// FCMDispatchService  (singleton)
// ---------------------------------------------------------------------------

class FCMDispatchService {
  FCMDispatchService._();
  static final FCMDispatchService instance = FCMDispatchService._();

  final _messaging = FirebaseMessaging.instance;
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final FlutterLocalNotificationsPlugin _localNotifs =
      FlutterLocalNotificationsPlugin();

  final _dispatchController = StreamController<DispatchPayload>.broadcast();
  Stream<DispatchPayload> get dispatchStream => _dispatchController.stream;

  DispatchPayload? lastDispatch;

  bool _initialized = false;

  // StreamSubscription<String> is correct — onTokenRefresh emits String
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  // onMessageOpenedApp is Stream<RemoteMessage>, not nullable-typed
  StreamSubscription<RemoteMessage>? _openedAppSub;

  // ── Initialise ────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('[FCM] Permission: ${settings.authorizationStatus}');

    await _initLocalNotifications();
    await _refreshAndStoreToken();

    _tokenRefreshSub = _messaging.onTokenRefresh.listen(_storeToken);

    _foregroundSub =
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    _openedAppSub =
        FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    final initial = await _messaging.getInitialMessage();
    if (initial != null) _handleNotificationTap(initial);

    debugPrint('[FCM] Initialized ✅');
  }

  // ── Local notifications setup ─────────────────────────────────────────────

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _localNotifs.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        if (details.payload != null && !_dispatchController.isClosed) {
          try {
            final map = jsonDecode(details.payload!) as Map<String, dynamic>;
            final payload = DispatchPayload(
              incidentType: map['incident_type'] as String? ?? 'Emergency',
              // toJson stores severity as int; guard both int and num
              severity: (map['severity'] as num?)?.toInt() ?? 3,
              severityLabel: map['severity_label'] as String? ?? 'Moderate',
              distanceKm: (map['distance_km'] as num?)?.toDouble() ?? 0.0,
              location: map['location'] as String? ?? '',
              requiredSkills: List<String>.from(
                map['required_skills'] as List? ?? [],
              ),
              immediateActions: List<String>.from(
                map['immediate_actions'] as List? ?? [],
              ),
              sosId: map['sos_id'] as String? ?? '',
              receivedAt: DateTime.now(),
            );
            lastDispatch = payload;
            _dispatchController.add(payload);
          } catch (e) {
            debugPrint('[FCM] Payload parse error: $e');
          }
        }
      },
    );

    // Create high-priority Android notification channel.
    // NOTE: `playSound` is not a constructor param for AndroidNotificationChannel
    // in flutter_local_notifications v17+; sound is controlled per-notification.
    const channel = AndroidNotificationChannel(
      'sos_dispatch',
      'SOS Dispatch',
      description: 'Urgent emergency dispatch alerts',
      importance: Importance.max,
      enableVibration: true,
    );

    await _localNotifs
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  // ── Token management ──────────────────────────────────────────────────────

  Future<void> _refreshAndStoreToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) await _storeToken(token);
    } catch (e) {
      debugPrint('[FCM] Token fetch failed: $e');
    }
  }

  Future<void> _storeToken(String token) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _firestore.collection('volunteers').doc(uid).set(
        {'fcmToken': token, 'fcmUpdatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      debugPrint('[FCM] Token stored for $uid');
    } catch (e) {
      debugPrint('[FCM] Token store failed: $e');
    }
  }

  // ── Message handlers ──────────────────────────────────────────────────────

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('[FCM] Foreground: ${message.data}');
    final payload = DispatchPayload.fromMessage(message);
    lastDispatch = payload;
    _dispatchController.add(payload);
    _showLocalNotification(payload, message.notification);
  }

  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('[FCM] Tapped: ${message.data}');
    final payload = DispatchPayload.fromMessage(message);
    lastDispatch = payload;
    _dispatchController.add(payload);
  }

  Future<void> _showLocalNotification(
    DispatchPayload payload,
    RemoteNotification? notification,
  ) async {
    final title = notification?.title ?? '🚨 ${payload.incidentType} Dispatch';
    final body = notification?.body ??
        '${payload.severityLabel} severity — ${payload.distanceKm.toStringAsFixed(1)} km away';

    final androidDetails = AndroidNotificationDetails(
      'sos_dispatch',
      'SOS Dispatch',
      channelDescription: 'Urgent emergency dispatch alerts',
      importance: Importance.max,
      priority: Priority.high,
      color: const Color(0xFFE24B4A),
      enableVibration: true,
      playSound: true,
      // fullScreenIntent was renamed to showWhen / visibility in v17;
      // use fullScreenIntent only on supported API levels via category
      fullScreenIntent: true,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifs.show(
      // Use a stable notification ID derived from sosId hash to avoid
      // flooding the tray when multiple dispatches arrive quickly.
      payload.sosId.isNotEmpty
          ? payload.sosId.hashCode.abs() % 100000
          : DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: jsonEncode(payload.toJson()),
    );
  }

  // ── Accept / Decline a dispatch ───────────────────────────────────────────

  Future<void> acceptDispatch(String sosId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || sosId.isEmpty) return;
    try {
      await _firestore.collection('sos_events').doc(sosId).update({
        'responses.$uid': {
          'status': 'accepted',
          'timestamp': FieldValue.serverTimestamp(),
        },
      });
      debugPrint('[FCM] Accepted dispatch $sosId');
    } catch (e) {
      debugPrint('[FCM] Accept failed: $e');
    }
  }

  Future<void> declineDispatch(String sosId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || sosId.isEmpty) return;
    try {
      await _firestore.collection('sos_events').doc(sosId).update({
        'responses.$uid': {
          'status': 'declined',
          'timestamp': FieldValue.serverTimestamp(),
        },
      });
      debugPrint('[FCM] Declined dispatch $sosId');
    } catch (e) {
      debugPrint('[FCM] Decline failed: $e');
    }
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _foregroundSub?.cancel();
    _openedAppSub?.cancel();
    _dispatchController.close();
    _initialized = false;
  }
}
