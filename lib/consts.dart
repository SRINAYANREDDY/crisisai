// consts.dart
// Gemini API key pool with automatic rotation on quota exhaustion.

const List<String> kGeminiApiKeys = [
  "AIzaSyATeVMi710FJ60UiyRHwxx3nsh9FtRzTTg", // 0
  "AIzaSyBxF_0bnxsuPVfCmtZSUXZnV8PHteHrfjQ", // 1
  "AIzaSyBvAbfPOf8jSX1XEHddtEGdT92UukzRh1g", // 2
  "AIzaSyBiZ5NLwHHWlsLQeVhBvjtqvH5XMWCvKFM", // 3
  "AIzaSyAKn8eV27uS3ElUMcIeMOFP9-ylv-SGLdY", // 4
  "AIzaSyBiw3lu4MaSAOM3c0xkaCQwxENGUvRXwQQ", // 5
  "AIzaSyA71bwBAJkSN1yqux8IioNtzzuBnD_p2AQ", // 6
  "AIzaSyCMFR-f5_-UqOACTkgJeragcxlkmym4SRY", // 7
  "AIzaSyDEmkO8MkoDM7kxITlwjBrZ7h26X3-hTzw", // 8
  "AIzaSyDPuu5ysVjmwB83cz6roC9CNu_pAwKPv98", // 9
  "AIzaSyCubNhPvl0lNM9q26gOFXvhhrniisrpnP0", // 10
  "AIzaSyCBWzqR1DGS4flJZbW2IznxsAeUlmJYphg", // 11
  "AIzaSyBc_tlpVPWiv95XNoszwH2QBFMMBJyO35I", // 12
  "AIzaSyDyLzGdv5BrNg33tzHsXzbWfY6xJEOf7Mc", // 13
  "AIzaSyDbFy6znc7u9RJxcf8Ac9JQR7pmI-56l8Q", // 14
  "AIzaSyBJzAtkulAO4G4CUovH_nK_2AOqwQDmRe8", // 15
  "AIzaSyB9RSPr3wLzV6LoakqXxmI3FEM7YLq8zRQ", // 16
  "AIzaSyDsWrLwxIe8B_fUlDuGDuucWnUTO2FGRpA", // 17
  "AIzaSyBQdIs3H5Epl8eJrbczTNittQdI58JUGyI", // 18
  "AIzaSyB8hJS6nUk9Wb_WDibI3OE0UFQSbiwwHoA", // 19
  "AIzaSyA16iaGIUOeaeP_Jzg1RN0sD-2RKYcpDGI", // 20
  "AIzaSyA0GcYE7oTWmxMotXyw4hx5RKi7rYn2HME", // 21
  "AIzaSyAbdmKfHwO-GOs6ekH31CnCfUWmwgGigVI", // 22
];

// ---------------------------------------------------------------------------
// GeminiKeyManager — singleton that rotates keys on quota / 429 errors.
// ---------------------------------------------------------------------------

class GeminiKeyManager {
  GeminiKeyManager._();
  static final GeminiKeyManager instance = GeminiKeyManager._();

  int _index = 0;

  /// The currently active API key.
  String get currentKey => kGeminiApiKeys[_index];

  /// Gemini endpoint for a given model, using the current key.
  String endpoint(String model) =>
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$model:generateContent?key=$currentKey';

  /// Call this when you receive a 429 (quota exceeded) or 503 response.
  /// Returns true if a fresh key is now available, false if all are exhausted.
  bool rotateKey() {
    if (_index < kGeminiApiKeys.length - 1) {
      _index++;
      return true; // new key ready
    }
    return false; // all keys exhausted
  }

  /// Reset to first key (e.g. on app restart / next day).
  void reset() => _index = 0;

  int get totalKeys => kGeminiApiKeys.length;
  int get currentIndex => _index;
  bool get allExhausted => _index >= kGeminiApiKeys.length - 1;
}

// Keep a single legacy alias so any file that still references GEMINI_API_KEY
// without a number will compile (points to the manager's current key).
String get GEMINI_API_KEY => GeminiKeyManager.instance.currentKey;
