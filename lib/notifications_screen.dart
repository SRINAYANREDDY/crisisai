// notifications_screen.dart
// ---------------------------------------------------------------------------
// NotificationStore  — singleton that holds all in-app notifications and
//                      listens to FCMDispatchService for live dispatch alerts.
//
// NotificationsSheet — modal bottom sheet shown from the bell icon in
//                      home_screen.dart's app bar.
//
// Usage (in home_screen.dart _buildAppBar):
//   _buildIconBtn(Icons.notifications_outlined, _openNotifications, badge: _hasUnread)
//
//   void _openNotifications() {
//     showNotificationsSheet(context);
//     NotificationStore.instance.markAllRead();
//     setState(() {});
//   }
//
//   bool get _hasUnread => NotificationStore.instance.hasUnread;
// ---------------------------------------------------------------------------

import 'dart:async';
import 'package:flutter/material.dart';
import 'fcm_dispatch_service.dart'; // DispatchPayload, FCMDispatchService
import 'home_screen.dart'; // AppColors

// ============================================================================
//  Model
// ============================================================================

enum AppNotifType { dispatch, emergency, system, training, achievement }

class AppNotification {
  final String id;
  final AppNotifType type;
  final String title;
  final String body;
  final DateTime time;
  bool read;

  /// Optional extra payload — e.g. DispatchPayload for dispatch type
  final Object? extra;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.time,
    this.read = false,
    this.extra,
  });

  // ── Display helpers ──────────────────────────────────────────────────────

  IconData get icon {
    switch (type) {
      case AppNotifType.dispatch:
        return Icons.campaign_rounded;
      case AppNotifType.emergency:
        return Icons.warning_amber_rounded;
      case AppNotifType.system:
        return Icons.info_outline_rounded;
      case AppNotifType.training:
        return Icons.school_rounded;
      case AppNotifType.achievement:
        return Icons.emoji_events_rounded;
    }
  }

  Color get color {
    switch (type) {
      case AppNotifType.dispatch:
        return const Color(0xFFE24B4A);
      case AppNotifType.emergency:
        return const Color(0xFFBA7517);
      case AppNotifType.system:
        return const Color(0xFF4285F4);
      case AppNotifType.training:
        return const Color(0xFF1D9E75);
      case AppNotifType.achievement:
        return const Color(0xFFBA7517);
    }
  }

  String get typeLabel {
    switch (type) {
      case AppNotifType.dispatch:
        return 'Dispatch';
      case AppNotifType.emergency:
        return 'Emergency';
      case AppNotifType.system:
        return 'System';
      case AppNotifType.training:
        return 'Training';
      case AppNotifType.achievement:
        return 'Achievement';
    }
  }

  String get timeAgo {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ============================================================================
//  Store (singleton)
// ============================================================================

class NotificationStore {
  NotificationStore._();
  static final NotificationStore instance = NotificationStore._();

  final ValueNotifier<List<AppNotification>> notifier =
      ValueNotifier<List<AppNotification>>([]);

  StreamSubscription<DispatchPayload>? _dispatchSub;

  bool _listening = false;

  // ── Call once (e.g. in main.dart after FCMDispatchService.initialize()) ──
  void init() {
    if (_listening) return;
    _listening = true;

    // Seed with some realistic recent notifications
    _seedInitial();

    // Listen for live FCM dispatch payloads
    _dispatchSub =
        FCMDispatchService.instance.dispatchStream.listen(_onDispatch);
  }

  void dispose() {
    _dispatchSub?.cancel();
    notifier.dispose();
  }

  // ── Live dispatch → notification ─────────────────────────────────────────
  void _onDispatch(DispatchPayload p) {
    add(AppNotification(
      id: 'dispatch_${p.sosId}_${DateTime.now().millisecondsSinceEpoch}',
      type: AppNotifType.dispatch,
      title: '🚨 ${p.incidentType} Dispatch',
      body: '${p.severityLabel} severity • ${p.location} • '
          '${p.requiredSkills.take(2).join(", ")}',
      time: DateTime.now(),
      extra: p,
    ));
  }

  // ── Public API ────────────────────────────────────────────────────────────
  List<AppNotification> get all => notifier.value;

  bool get hasUnread => notifier.value.any((n) => !n.read);

  int get unreadCount => notifier.value.where((n) => !n.read).length;

  void add(AppNotification n) {
    notifier.value = [n, ...notifier.value];
  }

  void markRead(String id) {
    final list = [...notifier.value];
    for (final n in list) {
      if (n.id == id) n.read = true;
    }
    notifier.value = list;
  }

  void markAllRead() {
    final list = notifier.value.map((n) {
      n.read = true;
      return n;
    }).toList();
    notifier.value = list;
  }

  void remove(String id) {
    notifier.value = notifier.value.where((n) => n.id != id).toList();
  }

  void clearAll() {
    notifier.value = [];
  }

  // ── Seed with realistic sample notifications ─────────────────────────────
  void _seedInitial() {
    final now = DateTime.now();
    notifier.value = [
      AppNotification(
        id: 'seed_1',
        type: AppNotifType.dispatch,
        title: '🚨 Medical Emergency Dispatch',
        body: 'High severity • Near Bus Stand • CPR, First Aid required',
        time: now.subtract(const Duration(minutes: 4)),
        read: false,
      ),
      AppNotification(
        id: 'seed_2',
        type: AppNotifType.emergency,
        title: 'Flood Warning Issued',
        body: 'Authorities have issued a yellow alert for low-lying areas. '
            'Stay alert and monitor updates.',
        time: now.subtract(const Duration(minutes: 22)),
        read: false,
      ),
      AppNotification(
        id: 'seed_3',
        type: AppNotifType.achievement,
        title: '🏅 Achievement Unlocked',
        body:
            'First Responder — You completed your first emergency response. +120 XP',
        time: now.subtract(const Duration(hours: 2)),
        read: false,
      ),
      AppNotification(
        id: 'seed_4',
        type: AppNotifType.training,
        title: 'Daily Training Reminder',
        body:
            'You have 2 training tasks pending today. Complete them to earn 70 XP.',
        time: now.subtract(const Duration(hours: 5)),
        read: true,
      ),
      AppNotification(
        id: 'seed_5',
        type: AppNotifType.dispatch,
        title: '🚨 Fire Incident Dispatch',
        body: 'Moderate severity • Industrial Zone • Fire Safety, Evacuation',
        time: now.subtract(const Duration(hours: 8)),
        read: true,
      ),
      AppNotification(
        id: 'seed_6',
        type: AppNotifType.system,
        title: 'Forecast Updated',
        body:
            'Your 48-hour disaster risk forecast has been refreshed with new data.',
        time: now.subtract(const Duration(hours: 11)),
        read: true,
      ),
      AppNotification(
        id: 'seed_7',
        type: AppNotifType.achievement,
        title: '🔥 5-Day Streak!',
        body:
            'You\'ve been active for 5 days in a row. Keep it up to earn bonus XP.',
        time: now.subtract(const Duration(days: 1)),
        read: true,
      ),
      AppNotification(
        id: 'seed_8',
        type: AppNotifType.system,
        title: 'Profile Verified',
        body:
            'Your volunteer profile has been verified by your district coordinator.',
        time: now.subtract(const Duration(days: 2)),
        read: true,
      ),
    ];
  }
}

// ============================================================================
//  Helper — show the sheet
// ============================================================================

void showNotificationsSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const NotificationsSheet(),
  );
}

// ============================================================================
//  NotificationsSheet
// ============================================================================

class NotificationsSheet extends StatefulWidget {
  const NotificationsSheet({super.key});

  @override
  State<NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<NotificationsSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // ── Drag handle ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),

            // ── Header ─────────────────────────────────────────────────────
            _buildHeader(),

            // ── Tab bar ────────────────────────────────────────────────────
            _buildTabBar(),

            // ── Body ───────────────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _NotifList(
                    filter: null,
                    scrollController: scrollController,
                  ),
                  _NotifList(
                    filter: (n) => !n.read,
                    emptyMessage: 'All caught up! No unread notifications.',
                    emptyIcon: Icons.done_all_rounded,
                    scrollController: scrollController,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
      child: Row(
        children: [
          const Text(
            'Notifications',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          // Live unread badge
          ValueListenableBuilder<List<AppNotification>>(
            valueListenable: NotificationStore.instance.notifier,
            builder: (_, list, __) {
              final count = list.where((n) => !n.read).length;
              if (count == 0) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.red,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              );
            },
          ),
          const Spacer(),
          // Mark all read button
          ValueListenableBuilder<List<AppNotification>>(
            valueListenable: NotificationStore.instance.notifier,
            builder: (_, list, __) {
              final hasUnread = list.any((n) => !n.read);
              if (!hasUnread) return const SizedBox.shrink();
              return TextButton(
                onPressed: () {
                  NotificationStore.instance.markAllRead();
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.teal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
                child: const Text(
                  'Mark all read',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              );
            },
          ),
          // Close button
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
            color: AppColors.textSecondary,
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() => Container(
        margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: TabBar(
          controller: _tabs,
          labelColor: AppColors.red,
          unselectedLabelColor: AppColors.textSecondary,
          indicator: BoxDecoration(
            color: AppColors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.red.withOpacity(0.3)),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          labelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          unselectedLabelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Unread'),
          ],
        ),
      );
}

// ============================================================================
//  Notification list tab
// ============================================================================

class _NotifList extends StatelessWidget {
  final bool Function(AppNotification)? filter;
  final String emptyMessage;
  final IconData emptyIcon;
  final ScrollController scrollController;

  const _NotifList({
    this.filter,
    this.emptyMessage = 'No notifications yet.',
    this.emptyIcon = Icons.notifications_none_rounded,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<AppNotification>>(
      valueListenable: NotificationStore.instance.notifier,
      builder: (_, all, __) {
        final items = filter != null ? all.where(filter!).toList() : all;

        if (items.isEmpty) {
          return _buildEmpty(context);
        }

        // Group into Today / Earlier
        final now = DateTime.now();
        final today =
            items.where((n) => now.difference(n.time).inHours < 24).toList();
        final earlier =
            items.where((n) => now.difference(n.time).inHours >= 24).toList();

        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            if (today.isNotEmpty) ...[
              _sectionLabel('TODAY'),
              const SizedBox(height: 8),
              ...today.map((n) => _NotifTile(notif: n)),
            ],
            if (earlier.isNotEmpty) ...[
              const SizedBox(height: 16),
              _sectionLabel('EARLIER'),
              const SizedBox(height: 8),
              ...earlier.map((n) => _NotifTile(notif: n)),
            ],
            // Clear all button at bottom if there are items
            if (items.isNotEmpty) ...[
              const SizedBox(height: 16),
              Center(
                child: TextButton.icon(
                  onPressed: () => NotificationStore.instance.clearAll(),
                  icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                  label:
                      const Text('Clear all', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _sectionLabel(String label) => Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 1.2,
        ),
      );

  Widget _buildEmpty(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                ),
                child:
                    Icon(emptyIcon, size: 32, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
}

// ============================================================================
//  Individual notification tile
// ============================================================================

class _NotifTile extends StatelessWidget {
  final AppNotification notif;
  const _NotifTile({required this.notif});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(notif.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.red.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_rounded, color: AppColors.red, size: 22),
      ),
      onDismissed: (_) => NotificationStore.instance.remove(notif.id),
      child: GestureDetector(
        onTap: () {
          NotificationStore.instance.markRead(notif.id);
          _handleTap(context);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: notif.read ? AppColors.white : notif.color.withOpacity(0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  notif.read ? AppColors.border : notif.color.withOpacity(0.25),
              width: notif.read ? 0.8 : 1.2,
            ),
            boxShadow: notif.read
                ? null
                : [
                    BoxShadow(
                      color: notif.color.withOpacity(0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon bubble
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: notif.color.withOpacity(notif.read ? 0.08 : 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  notif.icon,
                  color:
                      notif.read ? notif.color.withOpacity(0.7) : notif.color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),

              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            notif.title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: notif.read
                                  ? FontWeight.w500
                                  : FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        // Unread dot
                        if (!notif.read) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.only(top: 4),
                            decoration: BoxDecoration(
                              color: notif.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      notif.body,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: notif.color.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            notif.typeLabel,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: notif.color,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          notif.timeAgo,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleTap(BuildContext context) {
    // For dispatch notifications, show a detail expansion
    if (notif.type == AppNotifType.dispatch && notif.extra is DispatchPayload) {
      _showDispatchDetail(context, notif.extra as DispatchPayload);
    }
  }

  void _showDispatchDetail(BuildContext context, DispatchPayload p) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: p.severityColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    Icons.campaign_rounded,
                    color: p.severityColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DISPATCH ALERT',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        p.incidentType,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: p.severityColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: p.severityColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: p.severityColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    p.severityLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: p.severityColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Location
            _detailRow(
                Icons.location_on_rounded, p.location, AppColors.textSecondary),
            const SizedBox(height: 8),
            // Distance
            _detailRow(
              Icons.near_me_rounded,
              '${p.distanceKm.toStringAsFixed(1)} km from your location',
              AppColors.blue,
            ),
            // Skills
            if (p.requiredSkills.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'REQUIRED SKILLS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: p.requiredSkills
                    .map((s) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: p.severityColor.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: p.severityColor.withOpacity(0.25)),
                          ),
                          child: Text(
                            s,
                            style: TextStyle(
                                fontSize: 11,
                                color: p.severityColor,
                                fontWeight: FontWeight.w600),
                          ),
                        ))
                    .toList(),
              ),
            ],
            // Immediate actions
            if (p.immediateActions.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'IMMEDIATE ACTIONS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              ...p.immediateActions.take(3).map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.bolt_rounded,
                            size: 14, color: p.severityColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            a,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textPrimary,
                                height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
            const SizedBox(height: 20),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      FCMDispatchService.instance.declineDispatch(p.sosId);
                      Navigator.pop(context);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Decline',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      FCMDispatchService.instance.acceptDispatch(p.sosId);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Responding to dispatch…'),
                          backgroundColor: AppColors.teal,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          margin: const EdgeInsets.all(16),
                        ),
                      );
                    },
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Respond',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: p.severityColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String text, Color color) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: color),
            ),
          ),
        ],
      );
}
