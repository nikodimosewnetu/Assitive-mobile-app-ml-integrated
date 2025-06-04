class Config {
  // Default backend URL - Update this with your computer's IP address
  static String _backendUrl =
      'http://192.168.188.156:5000'; // Replace with your IP

  // Getter and setter for backendUrl to ensure proper formatting
  static String get backendUrl => _backendUrl.trim();
  static set backendUrl(String value) {
    _backendUrl = value.trim();
  }

  // API endpoints
  static String get detectObjectsUrl => '$backendUrl/detect_objects';
  static String get testDetectionUrl => '$backendUrl/test_detection';
  static String get statusUrl => '$backendUrl/status';
  static String get navigateUrl => '$backendUrl/navigate';

  // Connection settings
  static const int connectionTimeout = 5; // seconds
  static const int requestTimeout = 2; // seconds
  static const int retryAttempts = 3;

  // Detection settings
  static const double minConfidence = 0.25;
  static const int maxDetectionsPerMinute = 15;
  static const Duration detectionInterval = Duration(seconds: 3);
}
