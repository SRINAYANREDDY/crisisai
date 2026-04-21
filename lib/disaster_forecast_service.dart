// lib/disaster_forecast_service.dart
// Feature 4 — Disaster Probability Forecast Service
//
// APIs used (all free, no key needed except Gemini):
//   Open-Meteo  → weather forecast (48h hourly)
//   USGS        → significant earthquake feed (past 7 days)
//   Open-Meteo Air Quality → UV index & dust/smoke (bonus context)
//   Gemini 1.5 Flash → AI risk classification

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'consts.dart';           // GeminiKeyManager
import 'offline_ai_service.dart'; // NetworkChecker
import 'location_service.dart'; // LocationService

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

enum RiskLevel { low, moderate, high, critical }

class ZoneRisk {
  final String zone;
  final String riskType;
  final int probabilityPct;
  final String reason;
  final RiskLevel level;
  final Color color;

  const ZoneRisk({
    required this.zone,
    required this.riskType,
    required this.probabilityPct,
    required this.reason,
    required this.level,
    required this.color,
  });

  factory ZoneRisk.fromJson(Map<String, dynamic> json) {
    final pct =
        (json['probabilityPercent'] as num?)?.toInt().clamp(0, 100) ?? 0;
    return ZoneRisk(
      zone: json['zone'] as String? ?? 'Unknown Zone',
      riskType: json['riskType'] as String? ?? 'General',
      probabilityPct: pct,
      reason: json['reason'] as String? ?? '',
      level: _levelFromPct(pct),
      color: _hexToColor(json['color'] as String? ?? '#888888'),
    );
  }

  static RiskLevel _levelFromPct(int pct) {
    if (pct >= 75) return RiskLevel.critical;
    if (pct >= 50) return RiskLevel.high;
    if (pct >= 25) return RiskLevel.moderate;
    return RiskLevel.low;
  }

  static Color _hexToColor(String hex) {
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return const Color(0xFF888888);
    }
  }

  String get levelLabel {
    switch (level) {
      case RiskLevel.low:      return 'Low';
      case RiskLevel.moderate: return 'Moderate';
      case RiskLevel.high:     return 'High';
      case RiskLevel.critical: return 'Critical';
    }
  }

  IconData get icon {
    final t = riskType.toLowerCase();
    if (t.contains('flood') || t.contains('water') || t.contains('inundation'))
      return Icons.water_rounded;
    if (t.contains('wind') || t.contains('gale'))
      return Icons.air_rounded;
    if (t.contains('quake') || t.contains('seismic') || t.contains('tremor'))
      return Icons.vibration_rounded;
    if (t.contains('storm') || t.contains('surge') || t.contains('cyclone'))
      return Icons.cyclone_rounded;
    if (t.contains('thunder') || t.contains('lightning'))
      return Icons.thunderstorm_rounded;
    if (t.contains('heat') || t.contains('heatwave'))
      return Icons.thermostat_rounded;
    if (t.contains('chemical') || t.contains('industrial') || t.contains('toxic'))
      return Icons.science_rounded;
    if (t.contains('fire') || t.contains('wildfire'))
      return Icons.local_fire_department_rounded;
    if (t.contains('landslide') || t.contains('erosion'))
      return Icons.landscape_rounded;
    if (t.contains('drought'))
      return Icons.water_drop_outlined;
    return Icons.warning_amber_rounded;
  }

  /// For Google Maps polygon fill
  Color get mapFillColor   => color.withOpacity(0.35);
  Color get mapStrokeColor => color.withOpacity(0.8);
}

class WeatherSummary {
  final double maxPrecipPct;
  final double maxWindKph;
  final double maxTemp;
  final double minTemp;
  /// Highest hourly precipitation probability in the next 6 hours (imminent risk)
  final double next6hPrecipPct;
  final double maxPrecipMm;    // actual rain accumulation estimate

  const WeatherSummary({
    required this.maxPrecipPct,
    required this.maxWindKph,
    required this.maxTemp,
    required this.minTemp,
    this.next6hPrecipPct = 0,
    this.maxPrecipMm = 0,
  });
}

class SeismicSummary {
  final int quakesThisWeek;
  final double? nearestMagnitude;
  final double? nearestKm;
  final String? nearestPlace;

  const SeismicSummary({
    required this.quakesThisWeek,
    this.nearestMagnitude,
    this.nearestKm,
    this.nearestPlace,
  });
}

class ForecastSnapshot {
  final List<ZoneRisk> zones;
  final DateTime fetchedAt;
  final bool wasOffline;
  final WeatherSummary weather;
  final SeismicSummary seismic;

  /// Human-readable location name, e.g. "Ranipet, Tamil Nadu"
  final String locationName;

  /// The coordinates used for this forecast
  final double lat;
  final double lon;

  const ForecastSnapshot({
    required this.zones,
    required this.fetchedAt,
    required this.wasOffline,
    required this.weather,
    required this.seismic,
    required this.locationName,
    required this.lat,
    required this.lon,
  });

  ZoneRisk get worstZone => zones.isEmpty
      ? ZoneRisk(
          zone: 'No data',
          riskType: 'Unknown',
          probabilityPct: 0,
          reason: '',
          level: RiskLevel.low,
          color: const Color(0xFF888888),
        )
      : zones.reduce((a, b) => a.probabilityPct >= b.probabilityPct ? a : b);

  int get overallRiskPct => zones.isEmpty
      ? 0
      : (zones.map((z) => z.probabilityPct).reduce((a, b) => a + b) /
                zones.length)
            .round();

  String get freshnessLabel {
    final diff = DateTime.now().difference(fetchedAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

// ---------------------------------------------------------------------------
// Service (singleton)
// ---------------------------------------------------------------------------

class DisasterForecastService {
  DisasterForecastService._();
  static final DisasterForecastService instance = DisasterForecastService._();

  static const _usgsSignificantWeek =
      'https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/significant_week.geojson';
  // Also fetch 2.5+ magnitude quakes within roughly 1000 km for regional context
  static const _usgsAll25Week =
      'https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/2.5_week.geojson';

  // ── Resolve current GPS location, waiting up to [maxWait] for it ─────────
  Future<({double lat, double lon, String locationName})> _resolveLocation({
    Duration maxWait = const Duration(seconds: 8),
  }) async {
    final loc = LocationService.instance;

    // If already ready, return immediately
    if (loc.isReady && loc.latitude != null && loc.longitude != null) {
      return _locRecord(loc);
    }

    // Kick off initialisation if not started
    if (!loc.isLoading) {
      unawaited(loc.initialize());
    }

    // Poll until ready or timeout
    final deadline = DateTime.now().add(maxWait);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 400));
      if (loc.isReady && loc.latitude != null) return _locRecord(loc);
    }

    // Hard fallback — GPS unavailable
    debugPrint('[Forecast] GPS timeout — using device default');
    return (lat: 12.9249, lon: 79.3233, locationName: 'Ranipet, Tamil Nadu');
  }

  ({double lat, double lon, String locationName}) _locRecord(
    LocationService loc,
  ) {
    final name = loc.shortLocality.isNotEmpty
        ? loc.shortLocality
        : loc.address.isNotEmpty
        ? loc.address
        : '${loc.latitude!.toStringAsFixed(4)}, ${loc.longitude!.toStringAsFixed(4)}';
    return (lat: loc.latitude!, lon: loc.longitude!, locationName: name);
  }

  String _openMeteoUrl(double lat, double lon) =>
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$lat&longitude=$lon'
      '&hourly=precipitation_probability,precipitation,windspeed_10m,'
      'windgusts_10m,temperature_2m,weathercode,relativehumidity_2m'
      '&daily=precipitation_sum,windspeed_10m_max,temperature_2m_max,'
      'temperature_2m_min,weathercode'
      '&forecast_days=3&timezone=Asia%2FKolkata';

  ForecastSnapshot? _cache;
  DateTime? _lastFetch;
  static const _ttl = Duration(minutes: 30);

  bool get hasCached => _cache != null;
  ForecastSnapshot? get cached => _cache;

  // -------------------------------------------------------------------------
  // Public fetch
  // -------------------------------------------------------------------------

  Future<ForecastSnapshot> fetch({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cache != null &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < _ttl) {
      return _cache!;
    }

    final online = await NetworkChecker.check();
    if (!online) return _offlineFallback();

    // Wait for GPS — more patient than before
    final loc = await _resolveLocation();

    try {
      final results = await Future.wait([
        _fetchWeather(loc.lat, loc.lon),
        _fetchSeismic(_usgsSignificantWeek),
        _fetchSeismic(_usgsAll25Week),
      ]);
      final wData  = results[0];
      final sigSeis = results[1];
      final allSeis = results[2];

      final ws = _summariseWeather(wData);
      final ss = _summariseSeismic(sigSeis, allSeis, loc.lat, loc.lon);

      final zones = await _callGeminiWithRotation(
        ws, ss, wData, loc.lat, loc.lon, loc.locationName,
      );

      final snap = ForecastSnapshot(
        zones: zones,
        fetchedAt: DateTime.now(),
        wasOffline: false,
        weather: ws,
        seismic: ss,
        locationName: loc.locationName,
        lat: loc.lat,
        lon: loc.lon,
      );
      _cache = snap;
      _lastFetch = DateTime.now();
      return snap;
    } catch (e) {
      debugPrint('[Forecast] $e — fallback');
      // If we at least have weather, return a partial offline forecast
      return _offlineFallback(lat: loc.lat, lon: loc.lon, name: loc.locationName);
    }
  }

  // -------------------------------------------------------------------------
  // API fetchers
  // -------------------------------------------------------------------------

  Future<Map<String, dynamic>> _fetchWeather(double lat, double lon) async {
    final r = await http
        .get(Uri.parse(_openMeteoUrl(lat, lon)))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('Open-Meteo ${r.statusCode}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _fetchSeismic(String url) async {
    final r = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('USGS ${r.statusCode}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  // -------------------------------------------------------------------------
  // Summarisers
  // -------------------------------------------------------------------------

  WeatherSummary _summariseWeather(Map<String, dynamic> data) {
    final h = data['hourly'] as Map<String, dynamic>? ?? {};

    List<num> vals(String key, {int take = 48}) =>
        List<num>.from((h[key] as List? ?? []).take(take));

    num maxOf(String key, {int take = 48}) {
      final list = vals(key, take: take);
      return list.isEmpty ? 0 : list.reduce((a, b) => a > b ? a : b);
    }

    num minOf(String key, {int take = 48}) {
      final list = vals(key, take: take);
      return list.isEmpty ? 0 : list.reduce((a, b) => a < b ? a : b);
    }

    // Precipitation accumulation: sum of hourly precip (mm) over 48h
    final precipList = vals('precipitation', take: 48);
    final totalPrecipMm =
        precipList.isEmpty ? 0.0 : precipList.fold<double>(0.0, (a, b) => a + b.toDouble());

    return WeatherSummary(
      maxPrecipPct:    maxOf('precipitation_probability').toDouble(),
      maxWindKph:      maxOf('windspeed_10m').toDouble(),
      maxTemp:         maxOf('temperature_2m').toDouble(),
      minTemp:         minOf('temperature_2m').toDouble(),
      next6hPrecipPct: maxOf('precipitation_probability', take: 6).toDouble(),
      maxPrecipMm:     totalPrecipMm.toDouble(),
    );
  }

  SeismicSummary _summariseSeismic(
    Map<String, dynamic> sigData,
    Map<String, dynamic> allData,
    double lat,
    double lon,
  ) {
    // First scan significant quakes for a nearby one
    double? nearMag, nearDist;
    String? nearPlace;

    void scan(Map<String, dynamic> data, {double maxKm = 1500}) {
      for (final f in (data['features'] as List? ?? [])) {
        final props  = f['properties'] as Map<String, dynamic>? ?? {};
        final coords = f['geometry']?['coordinates'] as List?;
        if (coords == null || coords.length < 2) continue;
        final dist = _haversine(
          lat, lon,
          (coords[1] as num).toDouble(),
          (coords[0] as num).toDouble(),
        );
        if (dist > maxKm) continue;
        final mag = (props['mag'] as num?)?.toDouble() ?? 0.0;
        if (nearDist == null || dist < nearDist!) {
          nearDist  = dist;
          nearMag   = mag;
          nearPlace = props['place'] as String?;
        }
      }
    }

    scan(sigData, maxKm: 3000); // significant quakes anywhere
    if (nearDist == null) scan(allData, maxKm: 800); // regional 2.5+ if none found

    return SeismicSummary(
      quakesThisWeek:    (sigData['features'] as List? ?? []).length,
      nearestMagnitude:  nearMag,
      nearestKm:         nearDist,
      nearestPlace:      nearPlace,
    );
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.pow(math.sin(dLon / 2), 2);
    return r * 2 * math.asin(math.sqrt(a.toDouble()));
  }

  double _rad(double d) => d * math.pi / 180;

  // -------------------------------------------------------------------------
  // Gemini with automatic key rotation
  // -------------------------------------------------------------------------

  Future<List<ZoneRisk>> _callGeminiWithRotation(
    WeatherSummary ws,
    SeismicSummary ss,
    Map<String, dynamic> rawWeather,
    double lat,
    double lon,
    String locationName,
  ) async {
    final manager    = GeminiKeyManager.instance;
    final totalKeys  = manager.totalKeys;

    for (int attempt = 0; attempt < totalKeys; attempt++) {
      try {
        return await _callGemini(ws, ss, rawWeather, lat, lon, locationName);
      } on _QuotaExceededException catch (e) {
        debugPrint(
          '[Forecast] Key #${manager.currentIndex} quota exceeded — rotating. ($e)',
        );
        final hasNext = manager.rotateKey();
        if (!hasNext) {
          debugPrint('[Forecast] All Gemini keys exhausted.');
          rethrow;
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    throw Exception('All Gemini API keys exhausted for Forecast.');
  }

  Future<List<ZoneRisk>> _callGemini(
    WeatherSummary ws,
    SeismicSummary ss,
    Map<String, dynamic> rawWeather,
    double lat,
    double lon,
    String locationName,
  ) async {
    final h      = rawWeather['hourly'] as Map<String, dynamic>? ?? {};
    final daily  = rawWeather['daily']  as Map<String, dynamic>? ?? {};

    // ── 12-hour hour-by-hour table ─────────────────────────────────────────
    final times   = (h['time']                       as List? ?? []).take(12).toList();
    final precip  = (h['precipitation_probability']  as List? ?? []).take(12).toList();
    final rain    = (h['precipitation']              as List? ?? []).take(12).toList();
    final wind    = (h['windspeed_10m']              as List? ?? []).take(12).toList();
    final gusts   = (h['windgusts_10m']              as List? ?? []).take(12).toList();
    final temp    = (h['temperature_2m']             as List? ?? []).take(12).toList();
    final humidity= (h['relativehumidity_2m']        as List? ?? []).take(12).toList();
    final wcode   = (h['weathercode']                as List? ?? []).take(12).toList();

    final table = List.generate(
      times.length,
      (i) => '${times[i]}: precip_prob=${precip[i]}%, rain=${rain[i]}mm, '
             'wind=${wind[i]}km/h(gusts ${gusts[i]}km/h), '
             'temp=${temp[i]}°C, rh=${humidity[i]}%, wmo=${wcode[i]}',
    ).join('\n');

    // ── 3-day daily summary ────────────────────────────────────────────────
    final dTimes  = (daily['time']                as List? ?? []).take(3).toList();
    final dRain   = (daily['precipitation_sum']   as List? ?? []).take(3).toList();
    final dWind   = (daily['windspeed_10m_max']   as List? ?? []).take(3).toList();
    final dTmax   = (daily['temperature_2m_max']  as List? ?? []).take(3).toList();
    final dTmin   = (daily['temperature_2m_min']  as List? ?? []).take(3).toList();
    final dailyTable = List.generate(
      dTimes.length,
      (i) => 'Day ${i+1} (${dTimes[i]}): rain=${dRain[i]}mm, '
             'wind_max=${dWind[i]}km/h, temp=${dTmin[i]}–${dTmax[i]}°C',
    ).join('\n');

    // ── Seismic note ───────────────────────────────────────────────────────
    final quakeNote = ss.nearestKm != null
        ? 'Nearest notable quake: M${ss.nearestMagnitude?.toStringAsFixed(1)} '
          '${ss.nearestPlace != null ? "(${ss.nearestPlace}) " : ""}'
          'at ${ss.nearestKm?.toStringAsFixed(0)}km from $locationName. '
          'Significant global quakes this week: ${ss.quakesThisWeek}.'
        : 'No significant quakes detected within 1500km of $locationName this week. '
          'Global significant count: ${ss.quakesThisWeek}.';

    // ── Imminent alert flag ────────────────────────────────────────────────
    final imminentRain = ws.next6hPrecipPct > 60
        ? 'WARNING: ${ws.next6hPrecipPct.toStringAsFixed(0)}% chance of rain in next 6 hours.'
        : 'No imminent heavy rain in next 6 hours (${ws.next6hPrecipPct.toStringAsFixed(0)}% max).';

    final prompt = '''
You are an expert disaster risk AI for emergency services in India. Analyse the real-time meteorological and seismic data below and produce a calibrated, location-specific disaster risk JSON assessment.

== DEVICE LOCATION ==
$locationName
Coordinates: ${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}
(This is the volunteer's actual GPS location — all zone names must reference real localities near these coordinates.)

== 12-HOUR HOUR-BY-HOUR FORECAST ==
$table

== 3-DAY DAILY SUMMARY ==
$dailyTable

== 48-HOUR SUMMARY ==
Max precipitation probability : ${ws.maxPrecipPct.toStringAsFixed(0)}%
Total estimated rainfall       : ${ws.maxPrecipMm.toStringAsFixed(1)} mm
Max sustained wind             : ${ws.maxWindKph.toStringAsFixed(0)} km/h
Temperature range              : ${ws.minTemp.toStringAsFixed(1)}°C – ${ws.maxTemp.toStringAsFixed(1)}°C
$imminentRain

== SEISMIC DATA (USGS) ==
$quakeNote

== ANALYSIS INSTRUCTIONS ==
1. Consider the terrain: is $locationName coastal, riverine, hilly, urban, industrial, or on a flood plain?
2. Consider seasonal context for the Indian subcontinent (monsoon, cyclone seasons, heat waves).
3. Use actual rain volume (mm) — not just probability — when calibrating flood risk.
4. For wind > 60 km/h, raise cyclone/storm risk. For wind > 90 km/h, mark high/critical.
5. If total rain > 100 mm in 48h, flood risk should be high or critical.
6. Seismic risk in peninsular India is low unless a quake is within 400 km.
7. Industrial/chemical zones should reflect secondary hazard from flooding.

== ZONE GENERATION RULES ==
- Generate exactly 6 zones using REAL sub-localities, directions ("North $locationName"), or well-known area names near these coordinates.
- Do NOT invent generic names like "Zone A". Use realistic local geography.
- Sort zones from highest to lowest probabilityPercent.
- Each "reason" must be 1-2 sentences referencing actual weather values or geographic facts.

Return ONLY a valid JSON array. No markdown. No preamble. No trailing text.

[
  {
    "zone": "<real local zone name>",
    "riskType": "<primary hazard type>",
    "probabilityPercent": <0-100 integer>,
    "reason": "<evidence-based, location-specific explanation citing actual data values>",
    "color": "<exactly one of: #1D9E75 | #BA7517 | #E24B4A | #7B0000>"
  }
]

Color guide: #1D9E75 = Low (0-24%), #BA7517 = Moderate (25-49%), #E24B4A = High (50-74%), #7B0000 = Critical (75-100%).
''';

    final geminiUrl = GeminiKeyManager.instance.endpoint('gemini-1.5-flash');

    final res = await http
        .post(
          Uri.parse(geminiUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': prompt},
                ],
              },
            ],
            'generationConfig': {
              'temperature': 0.05,   // Near-deterministic for risk data
              'maxOutputTokens': 1200,
            },
          }),
        )
        .timeout(const Duration(seconds: 25));

    if (res.statusCode == 429 || res.statusCode == 503) {
      throw _QuotaExceededException('HTTP ${res.statusCode}');
    }
    if (res.statusCode != 200) {
      throw Exception('Gemini HTTP ${res.statusCode}');
    }

    final decoded   = jsonDecode(res.body) as Map<String, dynamic>;
    final errorMsg  = (decoded['error']?['message'] as String? ?? '').toLowerCase();
    if (errorMsg.contains('quota') || errorMsg.contains('rate')) {
      throw _QuotaExceededException(errorMsg);
    }

    final raw =
        (decoded['candidates'] as List?)
                ?.firstOrNull?['content']?['parts']
                ?.firstOrNull?['text']
            as String? ??
        '[]';

    final cleaned = raw.replaceAll(RegExp(r'```json|```'), '').trim();

    // Extract first JSON array even if model adds surrounding text
    final arrayMatch = RegExp(r'\[[\s\S]*\]').firstMatch(cleaned);
    final jsonStr = arrayMatch?.group(0) ?? cleaned;

    final list = jsonDecode(jsonStr) as List;
    return (list
        .map((e) => ZoneRisk.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.probabilityPct.compareTo(a.probabilityPct)));
  }

  // -------------------------------------------------------------------------
  // Offline fallback — uses live GPS if available
  // -------------------------------------------------------------------------

  ForecastSnapshot _offlineFallback({
    double? lat,
    double? lon,
    String? name,
  }) {
    final loc = LocationService.instance;
    final useLat  = lat  ?? (loc.isReady ? loc.latitude  : null) ?? 12.9249;
    final useLon  = lon  ?? (loc.isReady ? loc.longitude : null) ?? 79.3233;
    final useName = name ?? (loc.isReady && loc.shortLocality.isNotEmpty
        ? loc.shortLocality
        : 'Your Location');

    final zones = [
      _zone('Coastal / Low-lying Area', 'Storm Surge & Flooding', 60,
          RiskLevel.high, '#E24B4A',
          'Coastal and low-lying zones near $useName carry elevated flood/surge risk. Offline — live data unavailable.'),
      _zone('North $useName', 'Flooding', 45,
          RiskLevel.moderate, '#BA7517',
          'Northern zones near $useName have historically seen waterlogging during heavy rainfall.'),
      _zone('Industrial Zone', 'Chemical / Flood Hazard', 40,
          RiskLevel.moderate, '#BA7517',
          'Industrial areas near $useName carry secondary flood-triggered hazard risk.'),
      _zone('South $useName', 'Waterlogging', 35,
          RiskLevel.moderate, '#BA7517',
          'Residential zones south of $useName with limited drainage infrastructure.'),
      _zone('Central $useName', 'Strong Winds', 25,
          RiskLevel.moderate, '#BA7517',
          'Urban corridors in central $useName can experience wind channelling during storms.'),
      _zone('West $useName', 'General', 15,
          RiskLevel.low, '#1D9E75',
          'Inland areas west of $useName are generally lower risk. Monitor for updates.'),
    ];

    return ForecastSnapshot(
      zones:        zones,
      fetchedAt:    DateTime.now(),
      wasOffline:   true,
      weather:      const WeatherSummary(
        maxPrecipPct: 0, maxWindKph: 0, maxTemp: 0, minTemp: 0,
      ),
      seismic:      const SeismicSummary(quakesThisWeek: 0),
      locationName: useName,
      lat:          useLat,
      lon:          useLon,
    );
  }

  ZoneRisk _zone(
    String zone, String type, int pct, RiskLevel level, String hex, String reason,
  ) => ZoneRisk(
    zone: zone, riskType: type, probabilityPct: pct,
    reason: reason, level: level, color: ZoneRisk._hexToColor(hex),
  );
}

// ignore: avoid_void_async
void unawaited(Future<void> future) {}

// ---------------------------------------------------------------------------
// Internal exception used only for key rotation signalling
// ---------------------------------------------------------------------------
class _QuotaExceededException implements Exception {
  final String message;
  const _QuotaExceededException(this.message);
  @override
  String toString() => '_QuotaExceededException: $message';
}