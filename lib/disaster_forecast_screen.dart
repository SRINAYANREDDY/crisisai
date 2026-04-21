// lib/disaster_forecast_screen.dart
// Feature 4 — Disaster Probability Forecast UI
//
// Exports:
//   DisasterForecastScreen   — full-page screen (from map.dart FAB or nav)
//   ForecastHomeCard         — compact "48-Hour Risk" card for home_screen.dart

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'home_screen.dart'; // AppColors, AppData
import 'disaster_forecast_service.dart';
import 'location_service.dart';

// ============================================================================
//  FULL-PAGE SCREEN
// ============================================================================

class DisasterForecastScreen extends StatefulWidget {
  const DisasterForecastScreen({super.key});

  @override
  State<DisasterForecastScreen> createState() => _DisasterForecastScreenState();
}

class _DisasterForecastScreenState extends State<DisasterForecastScreen>
    with SingleTickerProviderStateMixin {
  final _service = DisasterForecastService.instance;
  ForecastSnapshot? _snap;
  bool _loading = true;
  String? _error;
  late TabController _tabs;
  GoogleMapController? _mapCtrl;
  Set<Polygon> _polygons = {};

  // Status messages shown while loading
  final List<String> _statusMessages = [
    'Acquiring your GPS location…',
    'Fetching live weather data…',
    'Loading seismic data from USGS…',
    'Running AI risk analysis…',
    'Generating zone-by-zone forecast…',
  ];
  int _statusIndex = 0;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _startStatusCycle();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _mapCtrl?.dispose();
    _statusTimer?.cancel();
    super.dispose();
  }

  void _startStatusCycle() {
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && _loading) {
        setState(() {
          _statusIndex = (_statusIndex + 1) % _statusMessages.length;
        });
      }
    });
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      _statusIndex = 0;
    });
    _startStatusCycle();
    try {
      final snap = await _service.fetch(forceRefresh: force);
      _statusTimer?.cancel();
      setState(() {
        _snap = snap;
        _loading = false;
        _polygons = _buildPolygons(snap.zones);
      });
    } catch (e) {
      _statusTimer?.cancel();
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [_buildAppBar()],
        body: _loading
            ? _buildLoader()
            : _error != null
                ? _buildError()
                : _buildContent(),
      ),
    );
  }

  SliverAppBar _buildAppBar() => SliverAppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        pinned: true,
        expandedHeight: 120,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          color: AppColors.textPrimary,
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_snap != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextButton.icon(
                onPressed: () => _load(force: true),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(
                  _snap!.freshnessLabel,
                  style: const TextStyle(fontSize: 11),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                ),
              ),
            ),
        ],
        flexibleSpace: FlexibleSpaceBar(
          titlePadding: const EdgeInsets.fromLTRB(56, 0, 16, 16),
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '48-Hour Risk Forecast',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              Row(
                children: [
                  Icon(
                    Icons.location_on_rounded,
                    size: 10,
                    color:
                        _snap != null ? AppColors.red : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    _snap?.locationName ?? _currentLocationLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.red,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.red,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(text: 'Risk Zones'),
            Tab(text: 'Heat Map'),
          ],
        ),
      );

  /// Shows live GPS location name while loading if available, else "Locating…"
  String get _currentLocationLabel {
    final loc = LocationService.instance;
    if (loc.shortLocality.isNotEmpty)
      return '${loc.shortLocality} · AI-powered';
    if (loc.address.isNotEmpty) return '${loc.address} · AI-powered';
    return 'Locating… · AI-powered';
  }

  Widget _buildLoader() => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _GeminiLoader(),
              const SizedBox(height: 20),
              // Live status message
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Text(
                  _statusMessages[_statusIndex],
                  key: ValueKey(_statusIndex),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Show current GPS location if we have it
              ValueListenableBuilder<String>(
                valueListenable: LocationService.instance.localityNotifier,
                builder: (_, loc, __) => Text(
                  loc.isNotEmpty ? '📍 $loc' : '📍 Acquiring GPS…',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Step progress dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_statusMessages.length, (i) {
                  final active = i == _statusIndex;
                  final done = i < _statusIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: done
                          ? AppColors.teal
                          : active
                              ? AppColors.red
                              : AppColors.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      );

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 16),
              const Text(
                'Could not load forecast',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildContent() {
    final snap = _snap!;
    return TabBarView(
      controller: _tabs,
      children: [_buildRiskZonesTab(snap), _buildHeatMapTab(snap)],
    );
  }

  // -------------------------------------------------------------------------
  // Tab 1: Risk Zones
  // -------------------------------------------------------------------------

  Widget _buildRiskZonesTab(ForecastSnapshot snap) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (snap.wasOffline) _buildOfflineBanner(),
          _buildLocationBadge(snap),
          const SizedBox(height: 12),
          _buildSummaryHeader(snap),
          const SizedBox(height: 16),
          _buildWeatherSeismicRow(snap),
          const SizedBox(height: 20),
          _buildSectionLabel('ZONE-BY-ZONE RISK BREAKDOWN'),
          const SizedBox(height: 10),
          ...snap.zones.map(
            (z) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ZoneRiskCard(zone: z),
            ),
          ),
          const SizedBox(height: 8),
          _buildDataSourceFooter(snap),
        ],
      );

  /// Small pill showing actual GPS coordinates and location name
  Widget _buildLocationBadge(ForecastSnapshot snap) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.gps_fixed_rounded,
                size: 13, color: AppColors.teal),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${snap.locationName}  ·  '
                '${snap.lat.toStringAsFixed(4)}°N, ${snap.lon.toStringAsFixed(4)}°E',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (!snap.wasOffline) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.teal.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: AppColors.teal,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _buildSummaryHeader(ForecastSnapshot snap) {
    final worst = snap.worstZone;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            worst.color.withOpacity(0.15),
            worst.color.withOpacity(0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: worst.color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          _RiskGauge(percent: snap.overallRiskPct, color: worst.color),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Overall Risk: ${snap.overallRiskPct}%',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: worst.color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Highest threat: ${worst.zone}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  worst.riskType,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                _LevelPill(level: worst.level, color: worst.color),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherSeismicRow(ForecastSnapshot snap) {
    // Show actual precipitation mm if non-zero, otherwise show probability
    final precipValue = snap.weather.maxPrecipMm > 0
        ? '${snap.weather.maxPrecipMm.toStringAsFixed(0)}mm'
        : '${snap.weather.maxPrecipPct.toStringAsFixed(0)}%';
    final precipLabel =
        snap.weather.maxPrecipMm > 0 ? '48h rain total' : 'max probability';

    return Row(
      children: [
        Expanded(
          child: _MeteoCard(
            icon: Icons.water_drop_rounded,
            label: 'Precip',
            value: precipValue,
            sublabel: precipLabel,
            color: AppColors.blue,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MeteoCard(
            icon: Icons.air_rounded,
            label: 'Wind',
            value: '${snap.weather.maxWindKph.toStringAsFixed(0)}',
            sublabel: 'km/h max',
            color: AppColors.teal,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MeteoCard(
            icon: Icons.vibration_rounded,
            label: snap.seismic.nearestKm != null ? 'Quake' : 'Quakes',
            value: snap.seismic.nearestKm != null
                ? 'M${snap.seismic.nearestMagnitude?.toStringAsFixed(1)}'
                : '${snap.seismic.quakesThisWeek}',
            sublabel: snap.seismic.nearestKm != null
                ? '${snap.seismic.nearestKm!.toStringAsFixed(0)}km away'
                : 'significant/week',
            color: AppColors.amber,
          ),
        ),
      ],
    );
  }

  Widget _buildDataSourceFooter(ForecastSnapshot snap) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 14,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Sources: Open-Meteo (weather) · USGS (seismic) · Gemini AI (analysis)\n'
                'Location: ${snap.locationName} · '
                'Updated: ${snap.fetchedAt.hour.toString().padLeft(2, '0')}:'
                '${snap.fetchedAt.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      );

  // -------------------------------------------------------------------------
  // Tab 2: Heat Map  — centred on actual device location
  // -------------------------------------------------------------------------

  Widget _buildHeatMapTab(ForecastSnapshot snap) => Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(snap.lat, snap.lon),
              zoom: 11.5,
            ),
            onMapCreated: (ctrl) {
              setState(() => _mapCtrl = ctrl);
              // Animate to actual location once map is ready
              ctrl.animateCamera(
                CameraUpdate.newLatLngZoom(LatLng(snap.lat, snap.lon), 11.5),
              );
            },
            polygons: _polygons,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            mapType: MapType.normal,
          ),
          // Legend overlay
          Positioned(top: 16, right: 16, child: _buildMapLegend()),
          // My location button (custom)
          Positioned(
            top: 16,
            left: 16,
            child: GestureDetector(
              onTap: () => _mapCtrl?.animateCamera(
                CameraUpdate.newLatLngZoom(LatLng(snap.lat, snap.lon), 12),
              ),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.my_location_rounded,
                    size: 20, color: AppColors.teal),
              ),
            ),
          ),
          // Floating zone summary at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildMapBottomSheet(snap),
          ),
        ],
      );

  Widget _buildMapLegend() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Risk Level',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            ...[
              ('Critical', const Color(0xFF7B0000)),
              ('High', const Color(0xFFE24B4A)),
              ('Moderate', const Color(0xFFBA7517)),
              ('Low', const Color(0xFF1D9E75)),
            ].map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: e.$2.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: e.$2, width: 1.5),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      e.$1,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildMapBottomSheet(ForecastSnapshot snap) => Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
                color: Colors.black12, blurRadius: 16, offset: Offset(0, -4)),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildSectionLabel(
                'DISTRICT RISK SUMMARY · ${snap.locationName.toUpperCase()}'),
            const SizedBox(height: 10),
            SizedBox(
              height: 88,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: snap.zones.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _ZoneMiniCard(zone: snap.zones[i]),
              ),
            ),
          ],
        ),
      );

  // -------------------------------------------------------------------------
  // Map polygons: generated around actual device location
  // -------------------------------------------------------------------------

  Set<Polygon> _buildPolygons(List<ZoneRisk> zones) {
    final lat = _snap?.lat ?? 12.9249;
    final lon = _snap?.lon ?? 79.3233;
    const d = 0.06; // ~6–7 km grid step

    final tiles = [
      [lat + d, lat + 2 * d, lon - d, lon + d], // North
      [lat - d, lat + d, lon - d, lon + d], // Central
      [lat - 2 * d, lat - d, lon - d, lon + d], // South
      [lat, lat + 2 * d, lon - 2 * d, lon - d], // West
      [lat - d, lat + 2 * d, lon + d, lon + 2 * d], // East / Coastal
      [lat + d, lat + 2 * d, lon - 2 * d, lon], // Industrial / NW
    ];

    final Set<Polygon> polys = {};
    for (var i = 0; i < zones.length && i < tiles.length; i++) {
      final zone = zones[i];
      final t = tiles[i];
      final pts = [
        LatLng(t[0], t[2]),
        LatLng(t[0], t[3]),
        LatLng(t[1], t[3]),
        LatLng(t[1], t[2]),
      ];
      polys.add(
        Polygon(
          polygonId: PolygonId(zone.zone),
          points: pts,
          fillColor: zone.mapFillColor,
          strokeColor: zone.mapStrokeColor,
          strokeWidth: 2,
          consumeTapEvents: true,
          onTap: () => _showZonePopup(zone),
        ),
      );
    }
    return polys;
  }

  void _showZonePopup(ZoneRisk zone) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
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
            Row(
              children: [
                Icon(zone.icon, color: zone.color, size: 20),
                const SizedBox(width: 8),
                Text(
                  zone.zone,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                _LevelPill(level: zone.level, color: zone.color),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              zone.riskType,
              style: TextStyle(
                color: zone.color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              zone.reason,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            _SeverityBar(percent: zone.probabilityPct, color: zone.color),
            const SizedBox(height: 6),
            Text(
              '${zone.probabilityPct}% probability',
              style: TextStyle(
                color: zone.color,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Shared helpers
  // -------------------------------------------------------------------------

  Widget _buildOfflineBanner() => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.amber.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.amber.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.wifi_off_rounded, size: 14, color: AppColors.amber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'OFFLINE — Showing historical risk model. Connect for live AI forecast.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.amber,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildSectionLabel(String label) => Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 1.2,
        ),
      );
}

// ============================================================================
//  HOME CARD — drop into home_screen.dart
// ============================================================================

class ForecastHomeCard extends StatefulWidget {
  const ForecastHomeCard({super.key});

  @override
  State<ForecastHomeCard> createState() => _ForecastHomeCardState();
}

class _ForecastHomeCardState extends State<ForecastHomeCard> {
  final _service = DisasterForecastService.instance;
  ForecastSnapshot? _snap;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await _service.fetch();
      if (mounted)
        setState(() {
          _snap = snap;
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DisasterForecastScreen()),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: _loading
            ? _buildSkeleton()
            : _snap == null
                ? _buildEmpty()
                : _buildLoaded(_snap!),
      ),
    );
  }

  Widget _buildLoaded(ForecastSnapshot snap) {
    final worst = snap.worstZone;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: worst.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(Icons.radar_rounded, color: worst.color, size: 18),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '48-Hour Risk Forecast',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        size: 9,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        snap.locationName,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        snap.wasOffline
                            ? '· Offline model'
                            : '· ${snap.freshnessLabel}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Risk bar row
          Row(
            children: snap.zones.take(6).map((z) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    children: [
                      Container(
                        height: 36,
                        decoration: BoxDecoration(
                          color: z.color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: z.color.withOpacity(0.4), width: 1),
                        ),
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            FractionallySizedBox(
                              heightFactor: z.probabilityPct / 100,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: z.color.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${z.probabilityPct}%',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: z.color,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          // Zone labels
          Row(
            children: snap.zones.take(6).map((z) {
              return Expanded(
                child: Text(
                  z.zone.split(' ').first,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 7.5, color: AppColors.textSecondary),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          // Alert pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: worst.color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: worst.color.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(worst.icon, size: 13, color: worst.color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${worst.zone}: ${worst.riskType} — ${worst.levelLabel} risk',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: worst.color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Rainfall info strip if available
          if (!snap.wasOffline && snap.weather.maxPrecipMm > 10) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.water_drop_rounded,
                    size: 11, color: AppColors.blue),
                const SizedBox(width: 4),
                Text(
                  '${snap.weather.maxPrecipMm.toStringAsFixed(0)}mm rain forecast · '
                  '${snap.weather.maxWindKph.toStringAsFixed(0)}km/h winds',
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textSecondary),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSkeleton() => const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Shimmer(width: 160, height: 14),
            SizedBox(height: 16),
            Row(
              children: [
                _Shimmer(width: 40, height: 40),
                SizedBox(width: 8),
                _Shimmer(width: 40, height: 40),
                SizedBox(width: 8),
                _Shimmer(width: 40, height: 40),
                SizedBox(width: 8),
                _Shimmer(width: 40, height: 40),
                SizedBox(width: 8),
                _Shimmer(width: 40, height: 40),
                SizedBox(width: 8),
                _Shimmer(width: 40, height: 40),
              ],
            ),
            SizedBox(height: 10),
            _Shimmer(width: double.infinity, height: 36),
          ],
        ),
      );

  Widget _buildEmpty() => Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_rounded,
                color: AppColors.textSecondary, size: 20),
            const SizedBox(width: 10),
            const Text(
              'Forecast unavailable',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const Spacer(),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
}

// ============================================================================
//  Sub-widgets
// ============================================================================

class _ZoneRiskCard extends StatelessWidget {
  final ZoneRisk zone;
  const _ZoneRiskCard({required this.zone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: zone.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(zone.icon, color: zone.color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      zone.zone,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      zone.riskType,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${zone.probabilityPct}%',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: zone.color,
                    ),
                  ),
                  _LevelPill(level: zone.level, color: zone.color),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SeverityBar(percent: zone.probabilityPct, color: zone.color),
          const SizedBox(height: 10),
          Text(
            zone.reason,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoneMiniCard extends StatelessWidget {
  final ZoneRisk zone;
  const _ZoneMiniCard({required this.zone});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: zone.color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: zone.color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(zone.icon, color: zone.color, size: 16),
          Text(
            zone.zone,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${zone.probabilityPct}%',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: zone.color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MeteoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String sublabel;
  final Color color;

  const _MeteoCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.sublabel,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: color),
          ),
          Text(
            sublabel,
            style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _LevelPill extends StatelessWidget {
  final RiskLevel level;
  final Color color;
  const _LevelPill({required this.level, required this.color});

  String get _label {
    switch (level) {
      case RiskLevel.low:
        return 'LOW';
      case RiskLevel.moderate:
        return 'MODERATE';
      case RiskLevel.high:
        return 'HIGH';
      case RiskLevel.critical:
        return 'CRITICAL';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SeverityBar extends StatelessWidget {
  final int percent;
  final Color color;
  const _SeverityBar({required this.percent, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: percent / 100,
        minHeight: 6,
        backgroundColor: color.withOpacity(0.12),
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}

class _RiskGauge extends StatelessWidget {
  final int percent;
  final Color color;
  const _RiskGauge({required this.percent, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: percent / 100,
            strokeWidth: 6,
            backgroundColor: color.withOpacity(0.12),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
          Text(
            '$percent%',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _GeminiLoader extends StatefulWidget {
  const _GeminiLoader();
  @override
  State<_GeminiLoader> createState() => _GeminiLoaderState();
}

class _GeminiLoaderState extends State<_GeminiLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Transform.rotate(
        angle: _ctrl.value * 2 * math.pi,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              colors: [AppColors.gemini.withOpacity(0.0), AppColors.gemini],
            ),
          ),
          child: Center(
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.background,
              ),
              child: const Icon(
                Icons.psychology_rounded,
                color: AppColors.gemini,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Shimmer extends StatelessWidget {
  final double width;
  final double height;
  const _Shimmer({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
