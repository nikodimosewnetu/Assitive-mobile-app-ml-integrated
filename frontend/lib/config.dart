class Config {
  // Default backend URL - Your computer's IP address
  static String _backendUrl =
      'http://192.168.138.156:5000'; // Your computer's IP

  // Getter and setter for backendUrl to ensure proper formatting
  static String get backendUrl => _backendUrl.trim();
  static set backendUrl(String value) {
    _backendUrl = value.trim();
  }

  // API endpoints
  static String get detectObjectsUrl => '$backendUrl/detect_objects';
  static String get navigateUrl => '$backendUrl/navigate';
  static String get statusUrl => '$backendUrl/status';

  // Connection settings
  static const int connectionTimeout = 10; // seconds
  static const int requestTimeout = 5; // seconds
  static const int retryAttempts = 3;
  static const int discoveryTimeout = 2; // Timeout for network discovery

  // Detection settings
  static const double minConfidence = 0.25;
  static const int maxDetectionsPerMinute = 15;
  static const Duration detectionInterval = Duration(seconds: 3);
}
