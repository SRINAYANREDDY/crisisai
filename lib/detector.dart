// detector.dart
// CrisisAI — AI Detector: Google ML Kit (on-device) + Gemini Vision (cloud)
// Pipeline:
//   1. google_mlkit_object_detection  → finds persons in the image on-device
//   2. google_mlkit_pose_detection    → body-pose distress classification
//   3. Gemini 2.0 Flash vision        → structured JSON risk assessment
// Live feed: CameraController snapshot every 2 s → same pipeline

// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart'; // ✅ FIX Bug 4: Added — needed for kIsWeb & debugPrint
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'package:path_provider/path_provider.dart';

import 'consts.dart';
import 'location_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Colour palette  (project-wide pattern: withOpacity, not withValues)
// ─────────────────────────────────────────────────────────────────────────────
class _C {
  static const Color bg = Color(0xFFF7F6F3);
  static const Color blue = Color(0xFF1D4ED8);
  static const Color blueLight = Color(0xFFEFF6FF);
  static const Color red = Color(0xFFE24B4A);
  static const Color redLight = Color(0xFFFCEBEB);
  static const Color teal = Color(0xFF1D9E75);
  static const Color tealLight = Color(0xFFE1F5EE);
  static const Color amber = Color(0xFFBA7517);
  static const Color amberLight = Color(0xFFFAEEDA);
  static const Color text = Color(0xFF1A1A1A);
  static const Color sub = Color(0xFF6B6B6B);
  static const Color border = Color(0xFFE8E8E8);
  static const Color white = Colors.white;
  static const Color thermal = Color(0xFFFF6B00);
  static const Color thermalBg = Color(0xFFFFF0E5);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Public result model
// ─────────────────────────────────────────────────────────────────────────────
class DetectedPerson {
  final String id;
  final String label;
  final String riskLevel; // 'critical' | 'high' | 'medium'
  final double lat;
  final double lng;
  final String locationName;
  final String detectedAt;
  final double confidence;
  final String footage;
  final String reason;
  final String
      detectionMethod; // 'mlkit+gemini' | 'mlkit+pose' | 'gemini-vision'

  const DetectedPerson({
    required this.id,
    required this.label,
    required this.riskLevel,
    required this.lat,
    required this.lng,
    required this.locationName,
    required this.detectedAt,
    required this.confidence,
    required this.footage,
    required this.reason,
    this.detectionMethod = 'mlkit+gemini',
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  Pose distress classifier
// ─────────────────────────────────────────────────────────────────────────────
class _PoseDistressResult {
  final String riskLevel;
  final String reason;
  final double confidence;
  const _PoseDistressResult(this.riskLevel, this.reason, this.confidence);
}

class _PoseDistressClassifier {
  static _PoseDistressResult classify(Pose pose) {
    final Map<PoseLandmarkType, PoseLandmark> lm = pose.landmarks;

    final double? noseY = lm[PoseLandmarkType.nose]?.y;
    final double? lShoulderY = lm[PoseLandmarkType.leftShoulder]?.y;
    final double? rShoulderY = lm[PoseLandmarkType.rightShoulder]?.y;
    final double? lHipY = lm[PoseLandmarkType.leftHip]?.y;
    final double? rHipY = lm[PoseLandmarkType.rightHip]?.y;
    final double? lAnkleY = lm[PoseLandmarkType.leftAnkle]?.y;
    final double? rAnkleY = lm[PoseLandmarkType.rightAnkle]?.y;
    final double? lWristY = lm[PoseLandmarkType.leftWrist]?.y;
    final double? rWristY = lm[PoseLandmarkType.rightWrist]?.y;

    // Rule 1 — lying flat
    if (noseY != null && lAnkleY != null && rAnkleY != null) {
      final double ankleY = (lAnkleY + rAnkleY) / 2.0;
      if (lShoulderY != null && rShoulderY != null && ankleY > 0) {
        final double shoulderY = (lShoulderY + rShoulderY) / 2.0;
        final double span = (shoulderY - ankleY).abs() / ankleY;
        if (span < 0.15 && noseY / ankleY > 0.3) {
          return const _PoseDistressResult(
            'critical',
            'Prone position detected — possible unconsciousness',
            0.89,
          );
        }
      }
    }

    // Rule 2 — arms raised overhead
    if (lWristY != null && rWristY != null && noseY != null) {
      final double wristAvgY = (lWristY + rWristY) / 2.0;
      if (wristAvgY < noseY - (noseY * 0.05)) {
        return const _PoseDistressResult(
          'high',
          'Arms raised above head — possible distress signal',
          0.82,
        );
      }
    }

    // Rule 3 — crouched
    if (lHipY != null && rHipY != null && noseY != null && noseY > 0) {
      final double hipY = (lHipY + rHipY) / 2.0;
      final double ratio = (hipY - noseY).abs() / noseY;
      if (ratio < 0.12) {
        return const _PoseDistressResult(
          'high',
          'Crouched posture — possible injury or shelter position',
          0.76,
        );
      }
    }

    // Rule 4 — only upper body visible
    if (noseY != null &&
        (lShoulderY != null || rShoulderY != null) &&
        lAnkleY == null &&
        rAnkleY == null) {
      return const _PoseDistressResult(
        'medium',
        'Only upper body visible — possible entrapment',
        0.71,
      );
    }

    return const _PoseDistressResult(
      'medium',
      'Person detected — posture unclear, needs assessment',
      0.65,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  AI Detector Service
// ─────────────────────────────────────────────────────────────────────────────
class AIDetectorService {
  static const String _geminiModel = 'gemini-2.0-flash';

  ObjectDetector? _objectDetector;
  PoseDetector? _poseDetector;
  bool _mlKitReady = false;

  Future<void> initMLKit() async {
    if (_mlKitReady) return;
    try {
      _objectDetector = ObjectDetector(
        options: ObjectDetectorOptions(
          mode: DetectionMode.single,
          classifyObjects: true,
          multipleObjects: true,
        ),
      );
      _poseDetector = PoseDetector(options: PoseDetectorOptions());
      _mlKitReady = true;
    } catch (e) {
      debugPrint('[AIDetector] ML Kit init error: $e');
    }
  }

  void dispose() {
    _objectDetector?.close();
    _poseDetector?.close();
  }

  // ── Main analysis stream ───────────────────────────────────────────────────
  Stream<DetectedPerson> analyzeImage(
    File imageFile,
    String sourceLabel,
  ) async* {
    await initMLKit();

    final locationSvc = LocationService.instance;
    final lat = locationSvc.latitude ?? 13.0827;
    final lng = locationSvc.longitude ?? 80.2707;
    final locationName = locationSvc.shortLocality.isNotEmpty
        ? locationSvc.shortLocality
        : 'Your location';

    final inputImage = InputImage.fromFile(imageFile);

    // ── Step 1: Object detection ───────────────────────────────────────────
    List<DetectedObject> objects = [];
    if (_mlKitReady && _objectDetector != null) {
      try {
        objects = await _objectDetector!.processImage(inputImage);
      } catch (e) {
        debugPrint('[AIDetector] Object detection error: $e');
      }
    }

    final personObjects = objects.where((obj) {
      return obj.labels.any((l) {
        final t = l.text.toLowerCase();
        return t.contains('person') ||
            t.contains('human') ||
            t.contains('man') ||
            t.contains('woman');
      });
    }).toList();

    // No ML Kit persons → Gemini Vision fallback
    if (personObjects.isEmpty) {
      final result = await _analyzeWithGeminiVision(imageFile);
      if (result != null) {
        yield DetectedPerson(
          id: 'G${DateTime.now().millisecondsSinceEpoch}',
          label: _str(result, 'label', 'Person #1'),
          riskLevel: _normaliseRisk(_str(result, 'risk', null)),
          lat: lat + _jitter(),
          lng: lng + _jitter(),
          locationName: locationName,
          detectedAt: _timeNow(),
          confidence: _dbl(result, 'confidence', 0.72),
          footage: sourceLabel,
          reason: _str(result, 'reason', 'Gemini Vision analysis'),
          detectionMethod: 'gemini-vision',
        );
      }
      return;
    }

    // ── Step 2: Pose detection ─────────────────────────────────────────────
    List<Pose> poses = [];
    if (_mlKitReady && _poseDetector != null) {
      try {
        poses = await _poseDetector!.processImage(inputImage);
      } catch (e) {
        debugPrint('[AIDetector] Pose detection error: $e');
      }
    }

    // ── Step 3: Read bytes once for all Gemini calls ───────────────────────
    Uint8List? imageBytes;
    try {
      imageBytes = await imageFile.readAsBytes();
    } catch (e) {
      debugPrint('[AIDetector] Could not read bytes: $e');
    }

    // ── Emit one result per detected person ────────────────────────────────
    for (int i = 0; i < personObjects.length; i++) {
      await Future.delayed(const Duration(milliseconds: 600));

      final obj = personObjects[i];

      final double mlKitConf = obj.labels.isNotEmpty
          ? obj.labels.map((l) => l.confidence).reduce(math.max).toDouble()
          : 0.70;

      _PoseDistressResult? poseResult;
      if (i < poses.length) {
        poseResult = _PoseDistressClassifier.classify(poses[i]);
      }

      Map<String, dynamic>? geminiResult;
      if (imageBytes != null) {
        try {
          geminiResult = await _analyzePersonWithGeminiBytes(
            imageBytes,
            i + 1,
            obj.boundingBox,
          );
        } catch (e) {
          debugPrint('[AIDetector] Gemini error: $e');
        }
      }

      final riskLevel = _normaliseRisk(
        geminiResult != null
            ? _str(geminiResult, 'risk', null)
            : poseResult?.riskLevel,
      );
      final reason = geminiResult != null
          ? _str(geminiResult, 'reason', 'Person detected by ML Kit')
          : (poseResult?.reason ?? 'Person detected by ML Kit');
      final confidence = geminiResult != null
          ? _dbl(geminiResult, 'confidence', mlKitConf)
          : (poseResult?.confidence ?? mlKitConf);
      final method = geminiResult != null
          ? 'mlkit+gemini'
          : (poseResult != null ? 'mlkit+pose' : 'mlkit');

      yield DetectedPerson(
        id: 'P${DateTime.now().millisecondsSinceEpoch}_$i',
        label: 'Person #${i + 1}',
        riskLevel: riskLevel,
        lat: lat + _jitter(),
        lng: lng + _jitter(),
        locationName: locationName,
        detectedAt: _timeNow(),
        confidence: confidence.clamp(0.0, 1.0),
        footage: sourceLabel,
        reason: reason,
        detectionMethod: method,
      );
    }
  }

  // ── Gemini helpers ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _analyzeWithGeminiVision(File f) async {
    try {
      final bytes = await f.readAsBytes();
      return await _analyzePersonWithGeminiBytes(bytes, 1, null);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _analyzePersonWithGeminiBytes(
    Uint8List imageBytes,
    int personIndex,
    Rect? boundingBox,
  ) async {
    final manager = GeminiKeyManager.instance;
    for (int attempt = 0; attempt < manager.totalKeys; attempt++) {
      try {
        final result = await _callGeminiVision(
          imageBytes,
          personIndex,
          boundingBox,
        );
        if (result != null) return result;
      } catch (e) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('quota') ||
            msg.contains('429') ||
            msg.contains('503')) {
          if (!manager.rotateKey()) break;
          await Future.delayed(const Duration(milliseconds: 300));
          continue;
        }
        break;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _callGeminiVision(
    Uint8List imageBytes,
    int personIndex,
    Rect? boundingBox,
  ) async {
    final base64Image = base64Encode(imageBytes);

    final bboxNote = boundingBox != null
        ? 'Focus on the person near '
            'x=${boundingBox.left.toInt()}, '
            'y=${boundingBox.top.toInt()}, '
            'w=${boundingBox.width.toInt()}, '
            'h=${boundingBox.height.toInt()} px.'
        : 'Analyse any person visible in the image.';

    final prompt =
        'You are an AI integrated into a disaster response app used by '
        'NDRF/SDRF volunteers in India.\n'
        'Analyse the image and determine the risk level of any person visible.\n'
        '$bboxNote\n\n'
        'Respond ONLY with a valid JSON object — no markdown, no code fences.\n'
        'Schema:\n'
        '{\n'
        '  "label": "Person #$personIndex",\n'
        '  "risk": "critical|high|medium",\n'
        '  "confidence": 0.0,\n'
        '  "reason": "one concise sentence describing observable distress"\n'
        '}\n\n'
        'Risk levels:\n'
        '- critical: unconscious, not moving, possible cardiac/respiratory arrest\n'
        '- high: injured, unable to stand, or in immediate danger\n'
        '- medium: ambulatory but distressed or in a hazardous area';

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {'mime_type': 'image/jpeg', 'data': base64Image},
            },
          ],
        },
      ],
      'generationConfig': {'temperature': 0.1, 'maxOutputTokens': 256},
    });

    final uri = Uri.parse(GeminiKeyManager.instance.endpoint(_geminiModel));
    final response = await http
        .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 20));

    if (response.statusCode == 429 || response.statusCode == 503) {
      throw Exception('quota:${response.statusCode}');
    }
    if (response.statusCode != 200) {
      debugPrint('[AIDetector] Gemini HTTP ${response.statusCode}');
      return null;
    }

    Map<String, dynamic> decoded;
    try {
      final raw = jsonDecode(response.body);
      if (raw is! Map<String, dynamic>) return null;
      decoded = raw;
    } catch (_) {
      return null;
    }

    final errorBlock = decoded['error'];
    if (errorBlock is Map) {
      final msg = ((errorBlock['message'] ?? '') as String).toLowerCase();
      if (msg.contains('quota') || msg.contains('rate')) {
        throw Exception('quota:embed');
      }
    }

    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) return null;

    final cand0 = candidates[0];
    if (cand0 is! Map<String, dynamic>) return null;

    final content = cand0['content'];
    if (content is! Map<String, dynamic>) return null;

    final parts = content['parts'];
    if (parts is! List || parts.isEmpty) return null;

    final part0 = parts[0];
    if (part0 is! Map<String, dynamic>) return null;

    final text = part0['text'];
    if (text is! String || text.isEmpty) return null;

    final cleaned = text.replaceAll(RegExp(r'```json|```'), '').trim();
    if (cleaned.isEmpty) return null;

    try {
      final parsed = jsonDecode(cleaned);
      return parsed is Map<String, dynamic> ? parsed : null;
    } catch (e) {
      debugPrint('[AIDetector] JSON parse: $e  raw: $cleaned');
      return null;
    }
  }

  // ── Tiny utilities ─────────────────────────────────────────────────────────

  static String _normaliseRisk(String? raw) {
    switch ((raw ?? '').toLowerCase().trim()) {
      case 'critical':
        return 'critical';
      case 'high':
        return 'high';
      default:
        return 'medium';
    }
  }

  static String _str(Map<String, dynamic> m, String key, String? fallback) {
    final v = m[key];
    return (v is String && v.isNotEmpty) ? v : (fallback ?? '');
  }

  static double _dbl(Map<String, dynamic> m, String key, double fallback) {
    final v = m[key];
    return v is num ? v.toDouble() : fallback;
  }

  double _jitter() => (math.Random().nextDouble() - 0.5) * 0.002;

  static String _timeNow() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:'
        '${n.minute.toString().padLeft(2, '0')}:'
        '${n.second.toString().padLeft(2, '0')}';
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  DETECTOR SCREEN
// ═════════════════════════════════════════════════════════════════════════════
class DetectorScreen extends StatefulWidget {
  const DetectorScreen({super.key});

  @override
  State<DetectorScreen> createState() => _DetectorScreenState();
}

class _DetectorScreenState extends State<DetectorScreen>
    with TickerProviderStateMixin {
  _InputMode _mode = _InputMode.none;
  _FootageType _footageType = _FootageType.normal;
  _AnalysisState _analysisState = _AnalysisState.idle;

  File? _pickedImageFile;
  Uint8List? _pickedImageBytes;
  String? _pickedFileName;

  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _cameraReady = false;
  bool _isLiveActive = false;
  bool _isAnalysing = false;
  Timer? _liveFrameTimer;

  final List<DetectedPerson> _detected = [];
  StreamSubscription<DetectedPerson>? _detectionSub;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;
  late AnimationController _scanLineCtrl;
  late Animation<double> _scanLine;

  late AIDetectorService _aiService;
  final ImagePicker _picker = ImagePicker();

  // Google Maps
  GoogleMapController? _googleMapController;
  Set<Marker> _googleMarkers = {};

  // ── Life cycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _aiService = AIDetectorService();
    _aiService.initMLKit();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulse = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _scanLineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _scanLine = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _scanLineCtrl, curve: Curves.linear));
  }

  @override
  void dispose() {
    _detectionSub?.cancel();
    _liveFrameTimer?.cancel();
    _cameraController?.dispose();
    _googleMapController?.dispose();
    _pulseCtrl.dispose();
    _scanLineCtrl.dispose();
    _aiService.dispose();
    super.dispose();
  }

  // ── Image picker ───────────────────────────────────────────────────────────
  // ✅ FIX Bug 1: Save XFile bytes to a real temp file so File() always works.
  // XFile.path on web/some Android content URIs is not a real FS path.
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? xfile = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1280,
      );
      if (xfile == null) return; // User cancelled

      Uint8List bytes;
      try {
        bytes = await xfile.readAsBytes();
      } catch (e) {
        _showError('Could not read image bytes. Please try a different image.');
        return;
      }

      if (bytes.isEmpty) {
        _showError('Selected image appears to be empty. Please try another.');
        return;
      }

      // Save to a stable temp file that ML Kit and File() can access reliably
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/crisis_pick_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(bytes);

      // Verify the file was written and is readable
      final written = await tempFile.length();
      if (written == 0) {
        _showError('Image save failed — file is empty. Please try again.');
        return;
      }

      if (!mounted) return;
      setState(() {
        _pickedImageFile = tempFile;
        _pickedImageBytes = bytes;
        _pickedFileName = xfile.name.isNotEmpty
            ? xfile.name
            : 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
        _analysisState = _AnalysisState.idle;
        _detected.clear();
      });
    } on Exception catch (e) {
      final msg = e.toString();
      if (msg.contains('photo_access_denied') || msg.contains('permission')) {
        _showError(
            'Gallery permission denied. Please allow photo access in Settings.');
      } else if (msg.contains('camera_access_denied')) {
        _showError(
            'Camera permission denied. Please allow camera access in Settings.');
      } else {
        _showError('Could not load image. Please try again. ($e)');
      }
    }
  }

  // ── Live camera ────────────────────────────────────────────────────────────
  Future<void> _startLiveCamera() async {
    try {
      // Fetch available cameras — may fail on emulators or devices without cameras
      List<CameraDescription> cams;
      try {
        cams = await availableCameras();
      } catch (e) {
        _showError(
          'Camera hardware not available on this device. '
          'Use the Gallery or Camera Photo option instead.',
        );
        return;
      }

      if (cams.isEmpty) {
        _showError(
          'No cameras detected on this device. '
          'Please use Gallery upload to analyse images.',
        );
        return;
      }

      _cameras = cams;
      final backCam = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _cameraController = CameraController(
        backCam,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      try {
        await _cameraController!.initialize();
      } catch (e) {
        _cameraController?.dispose();
        _cameraController = null;
        _showError(
          'Could not initialise camera: $e. '
          'Try closing other apps using the camera, or use Gallery upload.',
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        _cameraReady = true;
        _isLiveActive = true;
      });

      // Take a frame every 2 s and pipe it through the AI pipeline
      _liveFrameTimer =
          Timer.periodic(const Duration(seconds: 2), (Timer t) async {
        if (!_isLiveActive || _isAnalysing) return;
        final ctrl = _cameraController;
        if (ctrl == null || !ctrl.value.isInitialized) return;
        try {
          final XFile img = await ctrl.takePicture();
          final bytes = await img.readAsBytes();
          if (bytes.isEmpty) return;
          final tempDir = await getTemporaryDirectory();
          final tempFile = File(
            '${tempDir.path}/live_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
          await tempFile.writeAsBytes(bytes);
          if (_isLiveActive && mounted) {
            _startImageAnalysis(tempFile, 'Live Camera');
          }
        } catch (e) {
          debugPrint('[LiveCamera] frame capture error: $e');
        }
      });
    } catch (e) {
      _showError('Unexpected camera error: $e');
    }
  }

  void _stopLiveCamera() {
    _liveFrameTimer?.cancel();
    _liveFrameTimer = null;
    _detectionSub?.cancel();
    _detectionSub = null;
    _cameraController?.dispose();
    _cameraController = null;
    if (mounted) {
      setState(() {
        _cameraReady = false;
        _isLiveActive = false;
        _isAnalysing = false;
        _analysisState = _AnalysisState.idle;
      });
    }
  }

  // ── Analysis launcher ──────────────────────────────────────────────────────
  void _startImageAnalysis(File file, String sourceLabel) {
    if (_isAnalysing) return;
    _detectionSub?.cancel();

    setState(() {
      _isAnalysing = true;
      if (!_isLiveActive) _detected.clear();
      _analysisState = _AnalysisState.scanning;
    });

    if (!_scanLineCtrl.isAnimating) _scanLineCtrl.repeat();

    _detectionSub = _aiService.analyzeImage(file, sourceLabel).listen(
      (DetectedPerson person) {
        if (mounted) {
          setState(() => _detected.add(person));
          _showDetectionSnackbar(person);
          // ✅ FIX Bug 3: Move map to first detected person's real location
          if (_detected.length == 1) {
            _googleMapController?.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: LatLng(person.lat, person.lng),
                  zoom: 15.0,
                ),
              ),
            );
          }
          // Rebuild markers
          setState(() {
            _googleMarkers = _buildGoogleMarkers();
          });
        }
      },
      onDone: () {
        if (mounted) {
          _scanLineCtrl.stop();
          setState(() {
            _isAnalysing = false;
            _analysisState =
                _isLiveActive ? _AnalysisState.idle : _AnalysisState.done;
            _googleMarkers = _buildGoogleMarkers();
          });
        }
      },
      onError: (Object err) {
        if (mounted) {
          _scanLineCtrl.stop();
          setState(() {
            _isAnalysing = false;
            _analysisState = _AnalysisState.idle;
          });
          _showError('Detection error: $err');
        }
      },
    );
  }

  // ── Colour helpers ─────────────────────────────────────────────────────────
  Color _riskColor(String risk) {
    switch (risk) {
      case 'critical':
        return _C.red;
      case 'high':
        return _C.amber;
      default:
        return _C.teal;
    }
  }

  Color _riskBg(String risk) {
    switch (risk) {
      case 'critical':
        return _C.redLight;
      case 'high':
        return _C.amberLight;
      default:
        return _C.tealLight;
    }
  }

  // ── Snackbars ──────────────────────────────────────────────────────────────
  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: _C.red));
  }

  void _showDetectionSnackbar(DetectedPerson p) {
    if (!mounted) return;
    final color = _riskColor(p.riskLevel);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.person_pin_circle, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${p.label} (${p.riskLevel.toUpperCase()}) — ${p.locationName}\n'
                '${p.reason}',
                style: const TextStyle(fontSize: 11),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E1E2E),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusBanner(),
            const SizedBox(height: 16),
            _buildMLKitBadge(),
            const SizedBox(height: 16),
            _buildFootageTypeSelector(),
            const SizedBox(height: 20),
            _buildInputSection(),
            const SizedBox(height: 20),
            _buildVideoPreview(),
            const SizedBox(height: 20),
            if (_analysisState != _AnalysisState.idle) ...[
              _buildAnalysisOverlay(),
              const SizedBox(height: 20),
            ],
            if (_detected.isNotEmpty) ...[
              _buildDetectionResults(),
              const SizedBox(height: 20),
              _buildMapView(), // ✅ Now shows real flutter_map
              const SizedBox(height: 20),
              _buildActionButtons(),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────
  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: _C.blue,
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
      title: const Row(
        children: [
          Icon(Icons.radar, color: Colors.white, size: 22),
          SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Crisis AI Detector',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              Text(
                'ML Kit · Pose Detection · Gemini Vision',
                style: TextStyle(fontSize: 10, color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
      actions: [
        if (_analysisState == _AnalysisState.scanning)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (BuildContext ctx, Widget? child) {
                return Transform.scale(
                  scale: _pulse.value,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _C.red,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, color: Colors.white, size: 8),
                        SizedBox(width: 4),
                        Text(
                          'ANALYSING',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  // ── ML Kit badge ───────────────────────────────────────────────────────────
  Widget _buildMLKitBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _C.tealLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _C.teal.withOpacity(0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.verified_rounded, color: _C.teal, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Powered by Google ML Kit Object & Pose Detection + Gemini Vision',
              style: TextStyle(fontSize: 11, color: _C.teal, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  // ── Status banner ──────────────────────────────────────────────────────────
  Widget _buildStatusBanner() {
    final String msg;
    final Color color;
    final Color bg;
    final IconData icon;

    switch (_analysisState) {
      case _AnalysisState.scanning:
        msg =
            'ML Kit detecting persons... Gemini Vision assessing risk in real-time.';
        color = _C.red;
        bg = _C.redLight;
        icon = Icons.manage_search_rounded;
        break;
      case _AnalysisState.done:
        final methods =
            _detected.map((p) => p.detectionMethod).toSet().join(' · ');
        msg = 'Analysis complete. ${_detected.length} person(s) detected.'
            '${methods.isNotEmpty ? ' Method: $methods.' : ''}';
        color = _C.teal;
        bg = _C.tealLight;
        icon = Icons.check_circle_outline;
        break;
      default:
        msg = 'Select an image or start live feed. ML Kit detects persons '
            'on-device; Gemini Vision assesses distress risk.';
        color = _C.blue;
        bg = _C.blueLight;
        icon = Icons.info_outline;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(fontSize: 12, color: color, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  // ── Footage type selector ──────────────────────────────────────────────────
  Widget _buildFootageTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Footage Type',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _C.text,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _footageTypeBtn(
                _FootageType.thermal,
                Icons.thermostat_rounded,
                'Thermal',
                'Heat signature detection',
                _C.thermal,
                _C.thermalBg,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _footageTypeBtn(
                _FootageType.normal,
                Icons.videocam_rounded,
                'Normal / Drone',
                'Optical / visible light',
                _C.blue,
                _C.blueLight,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _footageTypeBtn(
    _FootageType type,
    IconData icon,
    String label,
    String sub,
    Color color,
    Color bg,
  ) {
    final bool sel = _footageType == type;
    return GestureDetector(
      onTap: () => setState(() => _footageType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sel ? color : _C.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: sel ? color : _C.border,
            width: sel ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: sel ? Colors.white : color, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: sel ? Colors.white : _C.text,
              ),
            ),
            Text(
              sub,
              style: TextStyle(
                fontSize: 10,
                color: sel ? Colors.white70 : _C.sub,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Input section ──────────────────────────────────────────────────────────
  Widget _buildInputSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Image / Video Source',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _C.text,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _modeBtn(
                _InputMode.upload,
                Icons.upload_file_rounded,
                'Gallery',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _modeBtn(
                _InputMode.camera,
                Icons.camera_alt_rounded,
                'Camera',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _modeBtn(
                _InputMode.live,
                Icons.live_tv_rounded,
                'Live Feed',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_mode == _InputMode.upload) _buildUploadArea(),
        if (_mode == _InputMode.camera) _buildCameraPickArea(),
        if (_mode == _InputMode.live) _buildLiveFeedArea(),
      ],
    );
  }

  Widget _modeBtn(_InputMode mode, IconData icon, String label) {
    final bool sel = _mode == mode;
    return GestureDetector(
      onTap: () => setState(() => _mode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: sel ? _C.blue : _C.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: sel ? _C.blue : _C.border,
            width: sel ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: sel ? Colors.white : _C.sub),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                color: sel ? Colors.white : _C.sub,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadArea() {
    final bool hasImage =
        _pickedImageBytes != null && _pickedImageBytes!.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: _C.blueLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasImage ? _C.teal.withOpacity(0.4) : _C.blue.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          // Thumbnail preview when image is loaded
          if (hasImage) ...[
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              child: Image.memory(
                _pickedImageBytes!,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                frameBuilder: (ctx, child, frame, sync) =>
                    (sync || frame != null)
                        ? child
                        : Container(
                            height: 160,
                            color: _C.blueLight,
                            child: const Center(
                              child: CircularProgressIndicator(
                                  color: _C.blue, strokeWidth: 2),
                            ),
                          ),
                errorBuilder: (ctx, err, _) => Container(
                  height: 160,
                  color: _C.redLight,
                  child: const Center(
                    child: Icon(Icons.broken_image_rounded,
                        color: _C.red, size: 36),
                  ),
                ),
              ),
            ),
          ],
          // Bottom action area
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (!hasImage) ...[
                  const Icon(Icons.cloud_upload_rounded,
                      color: _C.blue, size: 36),
                  const SizedBox(height: 8),
                  const Text(
                    'Tap to select image from gallery',
                    style: TextStyle(
                      fontSize: 12,
                      color: _C.blue,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Supports JPG, PNG, HEIC',
                    style: TextStyle(fontSize: 10, color: _C.sub),
                  ),
                  const SizedBox(height: 12),
                ],
                if (hasImage) ...[
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          color: _C.teal, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _pickedFileName ?? 'Image loaded',
                          style: const TextStyle(
                            fontSize: 11,
                            color: _C.teal,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _pickImage(ImageSource.gallery),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: hasImage ? _C.white : _C.blue,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: hasImage ? _C.border : _C.blue,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.photo_library_rounded,
                                size: 15,
                                color: hasImage ? _C.sub : _C.white,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                hasImage ? 'Change Image' : 'Open Gallery',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: hasImage ? _C.sub : _C.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (hasImage) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _startImageAnalysis(
                              _pickedImageFile!, 'Gallery Upload'),
                          icon: const Icon(Icons.search, size: 15),
                          label: const Text('Analyse Now'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _C.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPickArea() {
    return GestureDetector(
      onTap: () => _pickImage(ImageSource.camera),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F4FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _C.blue.withOpacity(0.3), width: 1.5),
        ),
        child: Column(
          children: [
            Icon(
              _pickedImageFile != null
                  ? Icons.check_circle_rounded
                  : Icons.camera_alt_rounded,
              color: _pickedImageFile != null ? _C.teal : _C.blue,
              size: 36,
            ),
            const SizedBox(height: 8),
            Text(
              _pickedImageFile != null
                  ? (_pickedFileName ?? 'Photo captured')
                  : 'Tap to take photo with camera',
              style: TextStyle(
                fontSize: 12,
                color: _pickedImageFile != null ? _C.teal : _C.blue,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_pickedImageFile != null) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () =>
                    _startImageAnalysis(_pickedImageFile!, 'Camera Photo'),
                icon: const Icon(Icons.search, size: 16),
                label: const Text('Analyse Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _C.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLiveFeedArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.redLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.red.withOpacity(0.3), width: 1.5),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.live_tv_rounded, color: _C.red, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Live Camera Feed\nML Kit analyses frames every 2 seconds',
                  style: TextStyle(
                    fontSize: 12,
                    color: _C.red,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (_cameraReady && _cameraController != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 200,
                child: CameraPreview(_cameraController!),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLiveActive ? _stopLiveCamera : _startLiveCamera,
              icon: Icon(
                _isLiveActive ? Icons.stop_rounded : Icons.play_arrow_rounded,
                size: 20,
              ),
              label: Text(_isLiveActive ? 'Stop Live Feed' : 'Start Live Feed'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isLiveActive ? _C.sub : _C.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Video / image preview ──────────────────────────────────────────────────
  Widget _buildVideoPreview() {
    // Always use Image.memory — bytes are already in RAM from _pickImage.
    // Image.file() fails on Android content URIs and Android 13+ scoped storage.
    if (_pickedImageBytes != null && _pickedImageBytes!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.memory(
          _pickedImageBytes!,
          height: 200,
          width: double.infinity,
          fit: BoxFit.cover,
          // Show a loading spinner while the image decodes
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) return child;
            return Container(
              height: 200,
              color: _C.blueLight,
              child: const Center(
                child:
                    CircularProgressIndicator(color: _C.blue, strokeWidth: 2),
              ),
            );
          },
          // Show a clear error instead of a blank widget
          errorBuilder: (context, error, stackTrace) {
            return Container(
              height: 200,
              decoration: BoxDecoration(
                color: _C.redLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _C.red.withOpacity(0.3)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.broken_image_rounded,
                      color: _C.red, size: 36),
                  const SizedBox(height: 8),
                  const Text(
                    'Image could not be displayed',
                    style: TextStyle(
                        fontSize: 12,
                        color: _C.red,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.refresh_rounded,
                        size: 16, color: _C.blue),
                    label: const Text('Try Again',
                        style: TextStyle(fontSize: 12, color: _C.blue)),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }
    return AnimatedBuilder(
      animation: _scanLine,
      builder: (BuildContext ctx, Widget? child) {
        return SizedBox(
          height: 200,
          width: double.infinity,
          child: CustomPaint(
            size: Size.infinite,
            painter: _VideoFramePainter(
              footageType: _footageType,
              detectedCount: _detected.length,
              scanProgress: _analysisState == _AnalysisState.scanning
                  ? _scanLine.value
                  : -1,
            ),
          ),
        );
      },
    );
  }

  // ── Analysis overlay ───────────────────────────────────────────────────────
  Widget _buildAnalysisOverlay() {
    final bool isDone = _analysisState == _AnalysisState.done;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              isDone
                  ? const Icon(
                      Icons.check_circle_rounded,
                      color: _C.teal,
                      size: 20,
                    )
                  : const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: _C.blue,
                      ),
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isDone
                      ? 'Analysis complete — ${_detected.length} person(s) found'
                      : 'ML Kit scanning · Gemini Vision reasoning...',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _C.text,
                  ),
                ),
              ),
            ],
          ),
          if (_detected.isNotEmpty && !isDone) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: (_detected.length / 5.0).clamp(0.0, 1.0),
              backgroundColor: _C.border,
              color: _C.blue,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ],
      ),
    );
  }

  // ── Detection results ──────────────────────────────────────────────────────
  Widget _buildDetectionResults() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Detected Persons',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _C.text,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _C.red,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_detected.length}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._detected.map(_buildPersonCard),
      ],
    );
  }

  Widget _buildPersonCard(DetectedPerson p) {
    final color = _riskColor(p.riskLevel);
    final bg = _riskBg(p.riskLevel);
    final methodIcon = p.detectionMethod.contains('gemini')
        ? Icons.auto_awesome_rounded
        : Icons.device_hub_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  p.riskLevel.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  p.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _C.text,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(methodIcon, size: 14, color: _C.sub),
              const SizedBox(width: 4),
              Text(
                p.detectionMethod,
                style: const TextStyle(fontSize: 10, color: _C.sub),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            p.reason,
            style: const TextStyle(fontSize: 12, color: _C.sub, height: 1.4),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.location_on_rounded, size: 12, color: _C.sub),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${p.locationName}  (${p.lat.toStringAsFixed(4)}, ${p.lng.toStringAsFixed(4)})',
                  style: const TextStyle(fontSize: 11, color: _C.sub),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'Conf: ${(p.confidence * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 11,
                  color: _C.sub,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Detected ${p.detectedAt} · ${p.footage}',
            style: const TextStyle(fontSize: 10, color: _C.sub),
          ),
        ],
      ),
    );
  }

  // ── Map view — Google Maps with real device GPS ─────────────────────────────
  // ✅ FIX Bug 3: Replaced fake CustomPaint with a real interactive map.

  // Each DetectedPerson is pinned at their actual lat/lng.
  /// Build a fresh Set<Marker> from _detected for Google Maps.
  Set<Marker> _buildGoogleMarkers() {
    return _detected.asMap().entries.map((entry) {
      final p = entry.value;
      final color = p.riskLevel == 'critical'
          ? BitmapDescriptor.hueRed
          : p.riskLevel == 'high'
              ? BitmapDescriptor.hueOrange
              : BitmapDescriptor.hueCyan;
      return Marker(
        markerId: MarkerId(p.id),
        position: LatLng(p.lat, p.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(color),
        infoWindow: InfoWindow(
          title: p.label,
          snippet:
              '${p.riskLevel.toUpperCase()} · ${(p.confidence * 100).toStringAsFixed(0)}% · ${p.reason}',
        ),
      );
    }).toSet();
  }

  Widget _buildMapView() {
    // Use real GPS from LocationService, fall back to Chennai coords
    final centerLat = _detected.isNotEmpty
        ? _detected.first.lat
        : (LocationService.instance.latitude ?? 13.0827);
    final centerLng = _detected.isNotEmpty
        ? _detected.first.lng
        : (LocationService.instance.longitude ?? 80.2707);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Detection Map',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _C.text,
              ),
            ),
            const SizedBox(width: 8),
            _legendDot(_C.red, 'Critical'),
            const SizedBox(width: 8),
            _legendDot(_C.amber, 'High'),
            const SizedBox(width: 8),
            _legendDot(_C.teal, 'Medium'),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          height: 280,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _C.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: GoogleMap(
              onMapCreated: (GoogleMapController controller) {
                _googleMapController = controller;
              },
              initialCameraPosition: CameraPosition(
                target: LatLng(centerLat, centerLng),
                zoom: 15.0,
              ),
              markers: _googleMarkers,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: true,
              mapToolbarEnabled: false,
              compassEnabled: true,
              mapType: MapType.normal,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${_detected.length} person(s) pinned — tap markers for details',
          style: const TextStyle(fontSize: 10, color: _C.sub),
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(fontSize: 10, color: _C.sub)),
      ],
    );
  }

  // ── Action buttons ─────────────────────────────────────────────────────────
  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _showDispatchDialog,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Dispatch Rescue'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _C.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _detected.clear();
                _analysisState = _AnalysisState.idle;
                _isAnalysing = false;
                _pickedImageFile = null;
                _pickedImageBytes = null;
                _pickedFileName = null;
              });
            },
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('New Scan'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _C.sub,
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: _C.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Dispatch dialog ────────────────────────────────────────────────────────
  void _showDispatchDialog() {
    final critical = _detected.where((p) => p.riskLevel == 'critical').length;
    final high = _detected.where((p) => p.riskLevel == 'high').length;
    final medium = _detected.where((p) => p.riskLevel == 'medium').length;

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.send_rounded, color: _C.red),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Dispatch Rescue Team',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _C.red,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Send rescue teams to ${_detected.length} location(s)?\n\n'
            'Critical: $critical\n'
            'High Risk: $high\n'
            'Medium: $medium',
            style: const TextStyle(fontSize: 13, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel', style: TextStyle(color: _C.sub)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogCtx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '✓ Rescue teams dispatched to '
                      '${_detected.length} locations.',
                    ),
                    backgroundColor: _C.teal,
                    duration: const Duration(seconds: 4),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _C.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Dispatch',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// _PersonMapPin removed — Google Maps InfoWindow handles marker tap details.

// ─────────────────────────────────────────────────────────────────────────────
//  Enums
// ─────────────────────────────────────────────────────────────────────────────
enum _InputMode { none, upload, camera, live }

enum _FootageType { thermal, normal }

enum _AnalysisState { idle, scanning, done }

// ─────────────────────────────────────────────────────────────────────────────
//  Video frame painter (still used for the "no image" placeholder)
// ─────────────────────────────────────────────────────────────────────────────
class _VideoFramePainter extends CustomPainter {
  final _FootageType footageType;
  final int detectedCount;
  final double scanProgress;

  const _VideoFramePainter({
    required this.footageType,
    required this.detectedCount,
    this.scanProgress = -1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(42);

    if (footageType == _FootageType.thermal) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFF0A0A1A),
      );
      for (int i = 0; i < 8; i++) {
        canvas.drawCircle(
          Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height),
          15.0 + rng.nextDouble() * 30,
          Paint()
            ..color = Color.lerp(
              const Color(0xFF001AFF),
              const Color(0xFFFF4400),
              rng.nextDouble(),
            )!
                .withOpacity(0.6)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
        );
      }
      final gridPaint = Paint()
        ..color = Colors.white.withOpacity(0.06)
        ..strokeWidth = 0.5;
      for (double x = 0; x < size.width; x += 20) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }
      for (double y = 0; y < size.height; y += 20) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    } else {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFF2A3A2A),
      );
      for (int i = 0; i < 12; i++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              rng.nextDouble() * size.width,
              rng.nextDouble() * size.height,
              20 + rng.nextDouble() * 60,
              10 + rng.nextDouble() * 30,
            ),
            const Radius.circular(4),
          ),
          Paint()
            ..color = Color.lerp(
              const Color(0xFF2A4A2A),
              const Color(0xFF6A7A5A),
              rng.nextDouble(),
            )!,
        );
      }
      final roadPaint = Paint()
        ..color = const Color(0xFF888880)
        ..strokeWidth = 8;
      canvas.drawLine(
        Offset(0, size.height * 0.55),
        Offset(size.width, size.height * 0.55),
        roadPaint,
      );
      canvas.drawLine(
        Offset(size.width * 0.38, 0),
        Offset(size.width * 0.38, size.height),
        roadPaint,
      );
    }

    if (scanProgress >= 0) {
      final scanY = scanProgress * size.height;
      canvas.drawLine(
        Offset(0, scanY),
        Offset(size.width, scanY),
        Paint()
          ..color = const Color(0xFF00FF88).withOpacity(0.7)
          ..strokeWidth = 2,
      );
      final bp = Paint()
        ..color = const Color(0xFF00FF88)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      const double br = 20.0;
      canvas.drawLine(const Offset(0, 0), const Offset(br, 0), bp);
      canvas.drawLine(const Offset(0, 0), Offset(0, br), bp);
      canvas.drawLine(Offset(size.width - br, 0), Offset(size.width, 0), bp);
      canvas.drawLine(Offset(size.width, 0), Offset(size.width, br), bp);
      canvas.drawLine(Offset(0, size.height - br), Offset(0, size.height), bp);
      canvas.drawLine(Offset(0, size.height), Offset(br, size.height), bp);
      canvas.drawLine(
        Offset(size.width - br, size.height),
        Offset(size.width, size.height),
        bp,
      );
      canvas.drawLine(
        Offset(size.width, size.height - br),
        Offset(size.width, size.height),
        bp,
      );
    }
  }

  @override
  bool shouldRepaint(_VideoFramePainter old) =>
      old.footageType != footageType ||
      old.detectedCount != detectedCount ||
      old.scanProgress != scanProgress;
}
