// offline_ai_screen.dart
// CrisisAI — Offline-First AI Guide Screen
//
// This screen is the user-facing interface for the offline AI system.
// It provides:
//   1. Connectivity status banner (auto-updates)
//   2. Quick-access protocol browser (by category)
//   3. Free-text AI query with offline fallback
//   4. SOS triage card (offline-capable)
//   5. Cache status + prewarm control
//
// How to add to your app:
//   • In home_screen.dart, add a nav item (bottom bar or drawer) pointing here.
//   • In main.dart, call OfflineCacheManager.prewarm() after GeminiService.init().
//   • Replace any critical GeminiService.generateContent() calls with
//     OfflineAIService.generate() for offline resilience.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'home_screen.dart'; // AppColors
import 'offline_ai_service.dart';

// Local amber colour constant used in this file
// (AppColors in home_screen.dart may not define amber/gemini)
const Color _kAmber = Color(0xFFBA7517);
const Color _kGemini = Color(0xFF8B5CF6);
const Color _kGeminiLight = Color(0xFFF5F0FF);

// ══════════════════════════════════════════════════════════════════════════════
//  OFFLINE AI SCREEN — main entry point
// ══════════════════════════════════════════════════════════════════════════════

class OfflineAIScreen extends StatefulWidget {
  const OfflineAIScreen({super.key});

  @override
  State<OfflineAIScreen> createState() => _OfflineAIScreenState();
}

class _OfflineAIScreenState extends State<OfflineAIScreen>
    with TickerProviderStateMixin {
  bool _isOnline = true;
  late StreamSubscription<bool> _connectivitySub;
  late AnimationController _bannerController;
  late Animation<double> _bannerFade;

  @override
  void initState() {
    super.initState();
    _bannerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
    _bannerFade = CurvedAnimation(
      parent: _bannerController,
      curve: Curves.easeOut,
    );
    _checkConnectivity();
    _connectivitySub = NetworkChecker.connectivityStream.listen((online) {
      if (mounted && online != _isOnline) {
        setState(() => _isOnline = online);
        _bannerController
          ..reset()
          ..forward();
      }
    });
  }

  Future<void> _checkConnectivity() async {
    final online = await NetworkChecker.check();
    if (mounted) setState(() => _isOnline = online);
  }

  @override
  void dispose() {
    _connectivitySub.cancel();
    _bannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          color: AppColors.textPrimary,
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _isOnline
                    ? _kGemini.withOpacity(0.12)
                    : AppColors.red.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _isOnline ? Icons.auto_awesome : Icons.wifi_off_rounded,
                size: 16,
                color: _isOnline ? _kGemini : AppColors.red,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Emergency Guide',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  _isOnline
                      ? 'Online — Gemini AI active'
                      : 'Offline — Local protocols active',
                  style: TextStyle(
                    fontSize: 11,
                    color: _isOnline ? AppColors.teal : AppColors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_done_rounded, size: 20),
            color: AppColors.textSecondary,
            tooltip: 'Cache status',
            onPressed: () => _showCacheStatus(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Connectivity banner
          FadeTransition(
            opacity: _bannerFade,
            child: _ConnectivityBanner(isOnline: _isOnline),
          ),
          // Main content
          Expanded(child: _OfflineAIBody(isOnline: _isOnline)),
        ],
      ),
    );
  }

  void _showCacheStatus(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CacheStatusSheet(),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
//  CONNECTIVITY BANNER
// ──────────────────────────────────────────────────────────────────────────────

class _ConnectivityBanner extends StatelessWidget {
  final bool isOnline;
  const _ConnectivityBanner({required this.isOnline});

  @override
  Widget build(BuildContext context) {
    if (isOnline) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.red.withOpacity(0.08),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 16, color: AppColors.red),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'No internet — running on offline emergency protocols. All critical guidance is available.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.red,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'OFFLINE',
              style: TextStyle(
                fontSize: 10,
                color: Colors.white,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
//  MAIN BODY — tab layout
// ──────────────────────────────────────────────────────────────────────────────

class _OfflineAIBody extends StatefulWidget {
  final bool isOnline;
  const _OfflineAIBody({required this.isOnline});

  @override
  State<_OfflineAIBody> createState() => _OfflineAIBodyState();
}

class _OfflineAIBodyState extends State<_OfflineAIBody>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: AppColors.background,
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.red,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.red,
            indicatorWeight: 2,
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            tabs: const [
              Tab(text: 'Ask AI'),
              Tab(text: 'Protocols'),
              Tab(text: 'SOS Triage'),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _AskAITab(isOnline: widget.isOnline),
              const _ProtocolBrowserTab(),
              const _SOSTriageTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  TAB 1 — ASK AI
// ══════════════════════════════════════════════════════════════════════════════

class _AskAITab extends StatefulWidget {
  final bool isOnline;
  const _AskAITab({required this.isOnline});

  @override
  State<_AskAITab> createState() => _AskAITabState();
}

class _AskAITabState extends State<_AskAITab> {
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<_ChatEntry> _messages = [];
  bool _isThinking = false;

  // Quick prompt suggestions
  static const List<String> _quickPrompts = [
    'CPR steps for cardiac arrest',
    'Flood evacuation — what to do',
    'Severe bleeding control',
    'Choking — Heimlich maneuver',
    'Earthquake response',
    'Snakebite first aid',
    'Heat stroke treatment',
    'Mass casualty triage',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    _ctrl.clear();
    FocusScope.of(context).unfocus();

    setState(() {
      _messages.add(_ChatEntry(text: text, isUser: true));
      _isThinking = true;
    });
    _scrollDown();

    final response = await OfflineAIService.generate(text, 'medical');

    if (mounted) {
      setState(() {
        _isThinking = false;
        _messages.add(
          _ChatEntry(
            text: response.content,
            isUser: false,
            source: response.sourceLabel,
            isOffline: response.isOffline,
          ),
        );
      });
      _scrollDown();
    }
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 120), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  itemCount: _messages.length + (_isThinking ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (_isThinking && i == _messages.length) {
                      return _ThinkingBubble(isOnline: widget.isOnline);
                    }
                    return _MessageBubble(entry: _messages[i]);
                  },
                ),
        ),
        _buildInputRow(),
      ],
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      children: [
        // Status card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: widget.isOnline
                ? _kGeminiLight
                : AppColors.red.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.isOnline
                  ? _kGemini.withOpacity(0.2)
                  : AppColors.red.withOpacity(0.2),
            ),
          ),
          child: Row(
            children: [
              Icon(
                widget.isOnline ? Icons.auto_awesome : Icons.security_rounded,
                color: widget.isOnline ? _kGemini : AppColors.red,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.isOnline
                          ? 'Gemini AI + Offline Protocols'
                          : 'Offline Protocols Active',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: widget.isOnline ? _kGemini : AppColors.red,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.isOnline
                          ? 'Ask any emergency question. Works offline too.'
                          : '${OfflineProtocolDB.protocolCount} protocols loaded. No internet needed.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Quick questions',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _quickPrompts
              .map(
                (p) => GestureDetector(
                  onTap: () => _send(p),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      p,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildInputRow() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
        color: AppColors.white,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              style: const TextStyle(fontSize: 14),
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: _send,
              decoration: InputDecoration(
                hintText: widget.isOnline
                    ? 'Ask anything — Gemini AI + offline backup…'
                    : 'Ask offline (${OfflineProtocolDB.protocolCount} protocols ready)…',
                hintStyle: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
                filled: true,
                fillColor: AppColors.background,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _send(_ctrl.text),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: widget.isOnline ? _kGemini : AppColors.red,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                widget.isOnline ? Icons.send_rounded : Icons.send_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Chat bubbles ───────────────────────────────────────────────────────────

class _ChatEntry {
  final String text;
  final bool isUser;
  final String? source;
  final bool isOffline;
  const _ChatEntry({
    required this.text,
    required this.isUser,
    this.source,
    this.isOffline = false,
  });
}

class _MessageBubble extends StatelessWidget {
  final _ChatEntry entry;
  const _MessageBubble({required this.entry});

  @override
  Widget build(BuildContext context) {
    if (entry.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12, left: 60),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.red,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(
            entry.text,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white,
              height: 1.5,
            ),
          ),
        ),
      );
    }

    // AI response bubble
    return Container(
      margin: const EdgeInsets.only(bottom: 16, right: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Source badge
          if (entry.source != null)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: entry.isOffline
                    ? AppColors.red.withOpacity(0.1)
                    : _kGeminiLight,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    entry.isOffline
                        ? Icons.wifi_off_rounded
                        : Icons.auto_awesome,
                    size: 10,
                    color: entry.isOffline ? AppColors.red : _kGemini,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    entry.source!,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: entry.isOffline ? AppColors.red : _kGemini,
                    ),
                  ),
                ],
              ),
            ),
          // Message body
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
              border: Border.all(
                color: entry.isOffline
                    ? AppColors.red.withOpacity(0.15)
                    : AppColors.border,
              ),
            ),
            child: _MarkdownText(text: entry.text),
          ),
          // Copy button
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: entry.text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copied to clipboard'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 4, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.copy_rounded,
                      size: 11,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'Copy',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThinkingBubble extends StatefulWidget {
  final bool isOnline;
  const _ThinkingBubble({required this.isOnline});

  @override
  State<_ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<_ThinkingBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color:
              widget.isOnline ? _kGeminiLight : AppColors.red.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeTransition(
              opacity: _anim,
              child: Icon(
                widget.isOnline ? Icons.auto_awesome : Icons.security_rounded,
                size: 13,
                color: widget.isOnline ? _kGemini : AppColors.red,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              widget.isOnline
                  ? 'Gemini is thinking…'
                  : 'Searching offline protocols…',
              style: TextStyle(
                fontSize: 12,
                color: widget.isOnline ? _kGemini : AppColors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  TAB 2 — PROTOCOL BROWSER
// ══════════════════════════════════════════════════════════════════════════════

class _ProtocolBrowserTab extends StatefulWidget {
  const _ProtocolBrowserTab();

  @override
  State<_ProtocolBrowserTab> createState() => _ProtocolBrowserTabState();
}

class _ProtocolBrowserTabState extends State<_ProtocolBrowserTab> {
  String _selectedCategory = 'all';

  static const Map<String, Map<String, dynamic>> _categoryMeta = {
    'all': {
      'label': 'All',
      'icon': Icons.grid_view_rounded,
      'color': 0xFF1A1A1A,
    },
    'medical': {
      'label': 'Medical',
      'icon': Icons.medical_services_outlined,
      'color': 0xFFE24B4A,
    },
    'fire': {
      'label': 'Fire',
      'icon': Icons.local_fire_department_outlined,
      'color': 0xFFBA7517,
    },
    'rescue': {
      'label': 'Rescue',
      'icon': Icons.water_outlined,
      'color': 0xFF1D4ED8,
    },
    'disaster': {
      'label': 'Disaster',
      'icon': Icons.warning_amber_outlined,
      'color': 0xFF9B59B6,
    },
    'triage': {
      'label': 'Triage',
      'icon': Icons.sort_outlined,
      'color': 0xFF1D9E75,
    },
    'general': {
      'label': 'General',
      'icon': Icons.help_outline_rounded,
      'color': 0xFF6B6B6B,
    },
  };

  @override
  Widget build(BuildContext context) {
    final categories = ['all', ...OfflineProtocolDB.allCategories];
    final protocols = _selectedCategory == 'all'
        ? OfflineProtocolDB.allCategories
            .expand((c) => OfflineProtocolDB.getByCategory(c))
            .toList()
        : OfflineProtocolDB.getByCategory(_selectedCategory);

    return Column(
      children: [
        // Category chips
        SizedBox(
          height: 54,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            itemCount: categories.length,
            itemBuilder: (ctx, i) {
              final cat = categories[i];
              final meta = _categoryMeta[cat] ?? _categoryMeta['general']!;
              final selected = cat == _selectedCategory;
              final color = Color(meta['color'] as int);
              return GestureDetector(
                onTap: () => setState(() => _selectedCategory = cat),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? color : AppColors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected ? color : AppColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        meta['icon'] as IconData,
                        size: 14,
                        color: selected ? Colors.white : color,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        meta['label'] as String,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color:
                              selected ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        // Protocol list
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: protocols.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) {
              final p = protocols[i];
              return _ProtocolCard(protocol: p);
            },
          ),
        ),
      ],
    );
  }
}

class _ProtocolCard extends StatelessWidget {
  final Map<String, dynamic> protocol;
  const _ProtocolCard({required this.protocol});

  Color get _severityColor => switch (protocol['severity']) {
        'critical' => AppColors.red,
        'high' => const Color(0xFFBA7517),
        'medium' => const Color(0xFF1D4ED8),
        _ => AppColors.teal,
      };

  @override
  Widget build(BuildContext context) {
    final steps = (protocol['steps'] as List).length;
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _ProtocolDetailScreen(protocol: protocol),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _severityColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _getCategoryIcon(protocol['category'] as String),
                color: _severityColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (protocol['title'] as String).replaceAll(
                      ' (Offline Protocol)',
                      '',
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      _Pill(
                        label: (protocol['severity'] as String).toUpperCase(),
                        color: _severityColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$steps steps',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String cat) {
    return switch (cat) {
      'medical' => Icons.medical_services_outlined,
      'fire' => Icons.local_fire_department_outlined,
      'rescue' => Icons.water_outlined,
      'disaster' => Icons.warning_amber_outlined,
      'triage' => Icons.sort_outlined,
      _ => Icons.help_outline_rounded,
    };
  }
}

// ── Protocol detail screen ──────────────────────────────────────────────────

class _ProtocolDetailScreen extends StatelessWidget {
  final Map<String, dynamic> protocol;
  const _ProtocolDetailScreen({required this.protocol});

  Color get _severityColor => switch (protocol['severity']) {
        'critical' => AppColors.red,
        'high' => const Color(0xFFBA7517),
        'medium' => const Color(0xFF1D4ED8),
        _ => AppColors.teal,
      };

  @override
  Widget build(BuildContext context) {
    final steps = protocol['steps'] as List;
    final warnings = protocol['warnings'] as List;
    final tips = protocol['tips'] as List;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          color: AppColors.textPrimary,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          (protocol['title'] as String).replaceAll(' (Offline Protocol)', ''),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          // Severity badge
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _severityColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              (protocol['severity'] as String).toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _severityColor,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Offline badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.teal.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.teal.withOpacity(0.2)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.offline_bolt_rounded,
                  size: 14,
                  color: AppColors.teal,
                ),
                SizedBox(width: 8),
                Text(
                  'Available offline — no internet required',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.teal,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Steps
          const _SectionHeader(
            label: 'IMMEDIATE STEPS',
            icon: Icons.list_rounded,
          ),
          const SizedBox(height: 10),
          ...steps.asMap().entries.map(
                (e) => _StepTile(
                  number: e.key + 1,
                  text: e.value as String,
                  isFirst: e.key == 0,
                  isLast: e.key == steps.length - 1,
                ),
              ),
          const SizedBox(height: 20),

          // Warnings
          if (warnings.isNotEmpty) ...[
            const _SectionHeader(
              label: 'CRITICAL WARNINGS',
              icon: Icons.warning_amber_rounded,
              color: _kAmber,
            ),
            const SizedBox(height: 10),
            ...warnings.map((w) => _WarningTile(text: w as String)),
            const SizedBox(height: 20),
          ],

          // Tips
          if (tips.isNotEmpty) ...[
            const _SectionHeader(
              label: 'FIELD TIPS',
              icon: Icons.lightbulb_outline_rounded,
              color: AppColors.teal,
            ),
            const SizedBox(height: 10),
            ...tips.map((t) => _TipTile(text: t as String)),
            const SizedBox(height: 20),
          ],

          // Emergency numbers
          _EmergencyNumbers(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _SectionHeader({
    required this.label,
    required this.icon,
    this.color = AppColors.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _StepTile extends StatelessWidget {
  final int number;
  final String text;
  final bool isFirst;
  final bool isLast;
  const _StepTile({
    required this.number,
    required this.text,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(
                    color: AppColors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$number',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: AppColors.red.withOpacity(0.15),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: 8, bottom: isLast ? 0 : 12),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningTile extends StatelessWidget {
  final String text;
  const _WarningTile({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kAmber.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kAmber.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 14,
            color: _kAmber,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TipTile extends StatelessWidget {
  final String text;
  const _TipTile({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.teal.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.teal.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lightbulb_outline_rounded,
            size: 14,
            color: AppColors.teal,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmergencyNumbers extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final numbers = [
      {'num': '112', 'label': 'All emergencies'},
      {'num': '108', 'label': 'Ambulance'},
      {'num': '101', 'label': 'Fire'},
      {'num': '100', 'label': 'Police'},
      {'num': '1070', 'label': 'TN Disaster'},
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'EMERGENCY HELPLINES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: numbers
                .map(
                  (n) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.red.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.red.withOpacity(0.15),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          n['num']!,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.red,
                          ),
                        ),
                        Text(
                          n['label']!,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  TAB 3 — SOS TRIAGE
// ══════════════════════════════════════════════════════════════════════════════

class _SOSTriageTab extends StatefulWidget {
  const _SOSTriageTab();

  @override
  State<_SOSTriageTab> createState() => _SOSTriageTabState();
}

class _SOSTriageTabState extends State<_SOSTriageTab> {
  final TextEditingController _ctrl = TextEditingController();
  OfflineTriageResult? _result;
  bool _isAnalysing = false;

  Future<void> _analyse() async {
    if (_ctrl.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _isAnalysing = true);
    final result = await OfflineAIService.triage(_ctrl.text.trim());
    if (mounted) {
      setState(() {
        _result = result;
        _isAnalysing = false;
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.red.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.red.withOpacity(0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.sos_rounded, color: AppColors.red, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Describe the incident in plain words. Works fully offline.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Input
          TextField(
            controller: _ctrl,
            maxLines: 4,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText:
                  'e.g. "Person collapsed, not breathing, no pulse, 45-year-old male"',
              hintStyle: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
              filled: true,
              fillColor: AppColors.white,
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.red, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Analyse button
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: _isAnalysing ? null : _analyse,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: _isAnalysing
                      ? AppColors.red.withOpacity(0.5)
                      : AppColors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: _isAnalysing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.bolt_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Analyse Incident',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Triage result card
          if (_result != null) _TriageResultCard(result: _result!),
        ],
      ),
    );
  }
}

class _TriageResultCard extends StatelessWidget {
  final OfflineTriageResult result;
  const _TriageResultCard({required this.result});

  Color get _severityColor => switch (result.severity) {
        'critical' => AppColors.red,
        'high' => const Color(0xFFBA7517),
        'medium' => const Color(0xFF1D4ED8),
        _ => AppColors.teal,
      };

  String get _severityLabel => switch (result.severity) {
        'critical' => '🔴 CRITICAL',
        'high' => '🟠 HIGH',
        'medium' => '🟡 MEDIUM',
        _ => '🟢 LOW',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _severityColor.withOpacity(0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _severityColor.withOpacity(0.08),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.incidentType.replaceAll(
                          ' (Offline Protocol)',
                          '',
                        ),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _severityLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _severityColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.teal.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${(result.confidence * 100).toInt()}% match',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.teal,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Immediate actions
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'IMMEDIATE ACTIONS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 10),
                ...result.immediateActions.asMap().entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: _severityColor,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${e.key + 1}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                e.value,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textPrimary,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                // Call buttons
                const SizedBox(height: 8),
                const Text(
                  'CALL NOW',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: result.callNumbers
                      .map(
                        (n) => GestureDetector(
                          onTap: () {
                            // In real app: launch_url tel:$n
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Calling $n...')),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.red,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.call_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  n,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),

                // View full protocol
                if (result.protocolId != null) ...[
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () {
                      final p = OfflineProtocolDB.getById(result.protocolId!);
                      if (p != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _ProtocolDetailScreen(protocol: p),
                          ),
                        );
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.article_outlined,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'View full protocol',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  CACHE STATUS BOTTOM SHEET
// ══════════════════════════════════════════════════════════════════════════════

class _CacheStatusSheet extends StatefulWidget {
  const _CacheStatusSheet();

  @override
  State<_CacheStatusSheet> createState() => _CacheStatusSheetState();
}

class _CacheStatusSheetState extends State<_CacheStatusSheet> {
  int _cachedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCacheCount();
    // Listen to prewarm progress
    OfflineCacheManager.prewarmProgressNotifier.addListener(_onProgress);
  }

  @override
  void dispose() {
    OfflineCacheManager.prewarmProgressNotifier.removeListener(_onProgress);
    super.dispose();
  }

  void _onProgress() {
    if (mounted) {
      _loadCacheCount();
      setState(() {});
    }
  }

  Future<void> _loadCacheCount() async {
    final count = await OfflineCacheManager.getCachedCount();
    if (mounted) setState(() => _cachedCount = count);
  }

  @override
  Widget build(BuildContext context) {
    final progress = OfflineCacheManager.prewarmProgressNotifier.value;
    final isPrewarming = OfflineCacheManager.isPrewarming;
    final total = OfflineCacheManager.totalTopics;
    final offlineProtocols = OfflineProtocolDB.protocolCount;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            'Offline Readiness',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),

          // Hard-coded protocols
          _CacheRow(
            icon: Icons.offline_bolt_rounded,
            color: AppColors.teal,
            label: 'Built-in protocols',
            value: '$offlineProtocols / $offlineProtocols',
            subtitle: 'Always available — no internet needed',
            progressFraction: 1.0,
          ),
          const SizedBox(height: 12),

          // Gemini cache
          _CacheRow(
            icon: Icons.auto_awesome,
            color: _kGemini,
            label: 'Gemini AI cache',
            value: '$_cachedCount / $total',
            subtitle: isPrewarming
                ? 'Pre-downloading AI responses…'
                : _cachedCount == total
                    ? 'Fully cached — works offline'
                    : 'Some responses not yet cached',
            progressFraction: total > 0 ? _cachedCount / total : 0,
          ),

          if (isPrewarming) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation<Color>(_kGemini),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Caching ${(progress * total).toInt()} of $total topics…',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Force re-cache button
          GestureDetector(
            onTap: isPrewarming
                ? null
                : () async {
                    await OfflineCacheManager.prewarm(force: true);
                    _loadCacheCount();
                  },
            child: Container(
              width: double.infinity,
              height: 46,
              decoration: BoxDecoration(
                color: isPrewarming ? _kGemini.withOpacity(0.4) : _kGemini,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  isPrewarming
                      ? 'Caching in progress…'
                      : 'Re-cache all AI responses',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          const Text(
            'Re-cache while on Wi-Fi to ensure AI responses are available during a disaster.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 8),
        ],
      ),
    );
  }
}

class _CacheRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String subtitle;
  final double progressFraction;
  const _CacheRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.progressFraction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progressFraction,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SHARED HELPERS
// ══════════════════════════════════════════════════════════════════════════════

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Renders basic Markdown-style bold (**text**) and newlines
class _MarkdownText extends StatelessWidget {
  final String text;
  const _MarkdownText({required this.text});

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    final regex = RegExp(r'\*\*(.*?)\*\*|_(.*?)_');
    int lastEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      if (match.group(1) != null) {
        spans.add(
          TextSpan(
            text: match.group(1),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else if (match.group(2) != null) {
        spans.add(
          TextSpan(
            text: match.group(2),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      }
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 13,
          color: AppColors.textPrimary,
          height: 1.6,
        ),
        children: spans,
      ),
    );
  }
}
