import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'services/message_queue_service.dart';
import 'services/network_service.dart';
import 'config.dart';

List<CameraDescription>? cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MyApp());
}

// Added a splash screen to improve the app's initial user experience.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Future.delayed(const Duration(seconds: 3), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DestinationInputScreen()),
      );
    });

    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.navigation, size: 100, color: Colors.blue),
            SizedBox(height: 20),
            Text(
              'Welcome to Assistive Navigation',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// Updated the MyApp widget to use the SplashScreen as the initial screen.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Assistive Navigation',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const SplashScreen(),
    );
  }
}

class DestinationInputScreen extends StatefulWidget {
  const DestinationInputScreen({super.key});

  @override
  DestinationInputScreenState createState() => DestinationInputScreenState();
}

class DestinationInputScreenState extends State<DestinationInputScreen> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  late final MessageQueueService _messageQueueService;
  bool _isListening = false;
  String _destination = '';
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _messageQueueService = MessageQueueService(_flutterTts);
    _initializeSpeech();
  }

  Future<void> _initializeSpeech() async {
    bool available = await _speech.initialize();
    if (available) {
      setState(() => _isInitialized = true);
      await _messageQueueService.speakWithPause(
          'Welcome to Assistive Navigation. Please say your destination in Amharic or English.');
    } else {
      setState(() => _isInitialized = false);
      await _messageQueueService
          .speakWithPause('Speech recognition is not available.');
    }
  }

  Future<void> _startListening() async {
    if (!_isInitialized) {
      await _messageQueueService
          .speakWithPause('Speech recognition is not available.');
      return;
    }

    setState(() => _isListening = true);
    await _messageQueueService
        .speakWithPause('Please say your destination in Addis Ababa.');

    // Try Amharic first, then fall back to English if needed
    bool amharicAvailable = await _speech.initialize(
      onStatus: (status) => print('Speech recognition status: $status'),
      onError: (error) => print('Speech recognition error: $error'),
    );

    if (amharicAvailable) {
      await _speech.listen(
        onResult: (result) {
          setState(() {
            _destination = result.recognizedWords;
          });
        },
        localeId: 'am-ET', // Amharic language code
        listenFor: const Duration(seconds: 10),
        cancelOnError: true,
        partialResults: true,
      );
    } else {
      // Fallback to English if Amharic is not available
      await _speech.listen(
        onResult: (result) {
          setState(() {
            _destination = result.recognizedWords;
          });
        },
        localeId: 'en-US',
        listenFor: const Duration(seconds: 10),
      );
    }
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _isListening = false);
    if (_destination.isNotEmpty) {
      _messageQueueService
          .speakWithPause('Navigating to $_destination in Addis Ababa.');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => NavigationScreen(
            destination: _destination,
            onObjectDetected: (detection) async {
              await _messageQueueService.speakWithPause(
                  'Detected ${detection['label']} ${detection['distance']} meters ${detection['direction']}.');
            },
          ),
        ),
      );
    } else {
      _messageQueueService
          .speakWithPause('No destination detected. Please try again.');
    }
  }

  @override
  void dispose() {
    _messageQueueService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Destination'),
        backgroundColor: Colors.blue,
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mic, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            Text(
              _isListening
                  ? 'Listening... Speak your destination in Addis Ababa.'
                  : 'Press the button and speak your destination in Addis Ababa.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _isListening ? _stopListening : _startListening,
              icon: Icon(_isListening ? Icons.mic_off : Icons.mic),
              label: Text(_isListening ? 'Stop Listening' : 'Start Listening'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _isDetecting = false;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(cameras![0], ResolutionPreset.low);
    _controller!.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _detectObjects() async {
    if (_isDetecting) return;
    setState(() {
      _isDetecting = true;
    });

    final FlutterTts flutterTts = FlutterTts();

    try {
      final image = await _controller!.takePicture();
      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http.post(
        Uri.parse(
            'http://192.168.236.156:5000/detect_objects'), // Replace with your computer's IP
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'image': base64Image}),
      );

      if (response.statusCode == 200) {
        final detections = jsonDecode(response.body)['detections'];
        for (var detection in detections) {
          final label = detection['label'];
          final confidence = detection['confidence'];
          final distance = detection['distance'];
          final position = detection['position'];

          final message =
              'Detected $label with confidence $confidence. It is $distance meters away at position $position.';
          await flutterTts.speak(message);
        }
      } else {
        print('Error: ${response.body}');
      }
    } catch (e) {
      print('Error: $e');
    } finally {
      setState(() {
        _isDetecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller!.value.isInitialized) {
      return Container();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Camera Stream'),
      ),
      body: Stack(
        children: [
          CameraPreview(_controller!),
          Positioned(
            bottom: 20,
            left: 20,
            child: ElevatedButton(
              onPressed: _detectObjects,
              child: const Text('Detect Objects'),
            ),
          ),
        ],
      ),
    );
  }
}

class NavigationScreen extends StatefulWidget {
  final String destination;
  final Function(Map<String, dynamic>) onObjectDetected;

  const NavigationScreen({
    required this.destination,
    required this.onObjectDetected,
    super.key,
  });

  @override
  NavigationScreenState createState() => NavigationScreenState();
}

class NavigationScreenState extends State<NavigationScreen>
    with WidgetsBindingObserver {
  // Navigation state
  final FlutterTts _flutterTts = FlutterTts();
  late final MessageQueueService _messageQueueService;
  List<latlong.LatLng> _routeCoordinates = [];
  String _distance = '';
  String _duration = '';
  List<String> _instructions = [];
  String? _errorMessage;
  bool _isLoading = true;
  latlong.LatLng? _currentLocation;
  Timer? _connectionCheckTimer;
  Timer? _routeUpdateTimer;
  bool _isNavigating = false;
  final int _currentInstructionIndex = 0;
  bool _isConnected = false;

  // Camera and detection state
  CameraController? _cameraController;
  bool _isDetecting = false;
  Timer? _detectionTimer;
  final List<String> _detectionLog = [];
  bool _isCameraInitialized = false;
  DateTime? _lastUpdateTime;
  Timer? _criticalUpdateTimer;
  final double _lastAnnouncedDistance = 0.0;

  // Constants
  static const double CRITICAL_DISTANCE_THRESHOLD = 3.0;
  static const double SAFETY_DISTANCE_THRESHOLD = 8.0;
  static const Duration SAFETY_ANNOUNCEMENT_INTERVAL = Duration(seconds: 10);
  static const Duration MIN_DETECTION_INTERVAL = Duration(seconds: 3);
  static const int MAX_DETECTIONS_PER_MINUTE = 15;
  static const double PROXIMITY_THRESHOLD = 0.05;
  static const double ROUTE_UPDATE_DISTANCE = 10.0;
  static const int MAX_RECENT_DETECTIONS = 5;

  // Timers and tracking
  Timer? _safetyCheckTimer;
  Timer? _proximityCheckTimer;
  double _lastUpdateDistance = 0.0;
  DateTime? _lastDetectionTime;
  int _detectionCount = 0;
  DateTime? _detectionCountResetTime;
  final double _lastRouteUpdateDistance = 0.0;
  List<Map<String, dynamic>> _recentDetections = [];
  final Map<String, DateTime> _lastSafetyAnnouncements = {};

  // Safety reminders
  final List<String> _safetyReminders = [
    "Remember to stay on the sidewalk",
    "Watch for crossing pedestrians",
    "Be aware of your surroundings",
    "Use your cane if needed",
    "Stay alert for obstacles",
    "Check for traffic before crossing",
    "Keep your phone accessible",
    "Stay hydrated and take breaks if needed"
  ];
  int _lastSafetyReminderIndex = -1;

  @override
  void initState() {
    super.initState();
    _messageQueueService = MessageQueueService(_flutterTts);
    _initializeCamera();
    _initializeLocation();
    _initializeNetwork();
  }

  Future<void> _initializeTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    // Test TTS
    await _messageQueueService
        .speakWithPause("Navigation system initialized. Ready to assist you.");
  }

  Future<void> _initializeCamera() async {
    if (cameras == null || cameras!.isEmpty) {
      setState(() => _errorMessage = 'No camera available');
      return;
    }

    _cameraController = CameraController(
      cameras![0],
      ResolutionPreset.medium, // Changed to medium for better detection
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      setState(() => _isCameraInitialized = true);
      _startObjectDetection();

      // Test backend connection
      await _testBackendConnection();
    } catch (e) {
      setState(() => _errorMessage = 'Failed to initialize camera: $e');
    }
  }

  Future<void> _initializeNetwork() async {
    setState(() {
      _isLoading = true;
      _errorMessage = 'Searching for backend server...';
    });

    try {
      // Try to discover the backend IP
      String? discoveredUrl = await NetworkService.discoverBackendIP();

      if (discoveredUrl != null) {
        // Update the backend URL if a different one was found
        if (discoveredUrl != Config.backendUrl) {
          await NetworkService.updateBackendUrl(discoveredUrl);
        }

        setState(() {
          _isConnected = true;
          _errorMessage = null;
        });

        await _messageQueueService
            .speakWithPause('Connected to backend server at $discoveredUrl');
      } else {
        setState(() {
          _isConnected = false;
          _errorMessage =
              'Could not find backend server. Please check your network connection.';
        });

        await _messageQueueService.speakWithPause(
            'Warning: Could not connect to backend server. Some features may not work.');
      }
    } catch (e) {
      setState(() {
        _isConnected = false;
        _errorMessage = 'Error initializing network: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testBackendConnection() async {
    setState(() {
      _isLoading = true;
      _errorMessage = 'Testing connection...';
    });

    try {
      bool isReachable = await NetworkService.isBackendReachable();

      if (isReachable) {
        setState(() {
          _isConnected = true;
          _errorMessage = null;
        });
        await _messageQueueService
            .speakWithPause('Connected to object detection system');
      } else {
        // Try to rediscover the backend
        String? discoveredUrl = await NetworkService.discoverBackendIP();

        if (discoveredUrl != null) {
          await NetworkService.updateBackendUrl(discoveredUrl);
          setState(() {
            _isConnected = true;
            _errorMessage = null;
          });
          await _messageQueueService
              .speakWithPause('Reconnected to object detection system');
        } else {
          setState(() {
            _isConnected = false;
            _errorMessage = 'Lost connection to detection service';
          });
          await _messageQueueService
              .speakWithPause('Warning: Lost connection to detection service');
        }
      }
    } catch (e) {
      setState(() {
        _isConnected = false;
        _errorMessage = 'Error connecting to detection service: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _startObjectDetection() {
    print('Starting object detection with 3-second interval');
    _detectionTimer?.cancel();
    _detectionTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!_isDetecting && _isCameraInitialized) {
        _detectObjects();
      }
    });
  }

  Future<void> _detectObjects() async {
    if (_isDetecting || !_isCameraInitialized || !_isConnected) {
      print(
          'Detection skipped: isDetecting=$_isDetecting, isCameraInitialized=$_isCameraInitialized, isConnected=$_isConnected');
      return;
    }

    // Check rate limiting
    final now = DateTime.now();
    if (_lastDetectionTime != null) {
      final timeSinceLastDetection = now.difference(_lastDetectionTime!);
      if (timeSinceLastDetection < MIN_DETECTION_INTERVAL) {
        print('Skipping detection: Too soon since last detection');
        return;
      }
    }

    // Reset detection count if a minute has passed
    if (_detectionCountResetTime == null ||
        now.difference(_detectionCountResetTime!) >
            const Duration(minutes: 1)) {
      _detectionCount = 0;
      _detectionCountResetTime = now;
    }

    // Check if we've exceeded the maximum detections per minute
    if (_detectionCount >= MAX_DETECTIONS_PER_MINUTE) {
      print('Skipping detection: Maximum detections per minute reached');
      return;
    }

    setState(() {
      _isDetecting = true;
      _lastDetectionTime = now;
      _detectionCount++;
    });

    try {
      print('Taking picture for object detection');
      final image = await _cameraController!.takePicture();
      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);

      print('Sending detection request to backend');
      final response = await http
          .post(
            Uri.parse(Config.detectObjectsUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'image': base64Image}),
          )
          .timeout(const Duration(seconds: Config.requestTimeout));

      print('Detection response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('Detection data: $data');

        if (data['detections'] != null) {
          final detections = data['detections'] as List;
          print('Number of detections: ${detections.length}');

          // Process all detections within safety threshold
          final significantDetections = detections.where((detection) {
            final distance =
                double.tryParse(detection['distance'].toString()) ?? 0.0;
            return distance <= SAFETY_DISTANCE_THRESHOLD;
          }).toList();

          if (significantDetections.isNotEmpty) {
            // Update recent detections
            _recentDetections.addAll(significantDetections.map(
                (detection) => Map<String, dynamic>.from(detection as Map)));

            // Keep only the most recent detections
            if (_recentDetections.length > MAX_RECENT_DETECTIONS) {
              _recentDetections = _recentDetections
                  .sublist(_recentDetections.length - MAX_RECENT_DETECTIONS);
            }

            // Process detections and provide safety recommendations
            for (var detection in significantDetections) {
              String message = _formatDetectionMessage(detection);
              print('Announcing: $message');
              await _messageQueueService.speakWithPause(message,
                  priority: MessageQueueService.PRIORITY_OBJECT_DETECTION);
              widget.onObjectDetected(detection);
              _detectionLog.add(message);
            }

            // Provide safety recommendations based on all recent detections
            String safetyRecommendation = _getSafetyRecommendation();
            if (safetyRecommendation.isNotEmpty) {
              print('Providing safety recommendation: $safetyRecommendation');
              await _messageQueueService.speakWithPause(safetyRecommendation,
                  priority: MessageQueueService.PRIORITY_ENVIRONMENTAL);
            }
          } else {
            print('No significant detections within safety threshold');
          }
        } else {
          print('No detections in response: ${response.body}');
        }
      } else {
        print('Detection error: ${response.statusCode} - ${response.body}');
        await _messageQueueService.speakWithPause(
            'Warning: Object detection failed',
            priority: MessageQueueService.PRIORITY_OBJECT_DETECTION);
      }
    } catch (e) {
      print('Object detection error: $e');
      await _messageQueueService.speakWithPause(
          'Warning: Error detecting objects',
          priority: MessageQueueService.PRIORITY_OBJECT_DETECTION);
    } finally {
      setState(() => _isDetecting = false);
    }
  }

  Future<void> _initializeLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentLocation =
            latlong.LatLng(position.latitude, position.longitude);
      });
      _navigateToDestination();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error getting location: $e';
        _isLoading = false;
      });
    }
  }

  void _startConnectionCheck() {
    _connectionCheckTimer?.cancel();
    _connectionCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      (timer) async {
        if (!await _checkBackendConnection()) {
          setState(() {
            _isConnected = false;
            _errorMessage = 'Lost connection to navigation service';
          });
        }
      },
    );
  }

  Future<bool> _checkBackendConnection() async {
    try {
      final response = await http
          .get(Uri.parse(Config.statusUrl))
          .timeout(const Duration(seconds: Config.connectionTimeout));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _isConnected = data['status'] == 'ok';
        });
        return _isConnected;
      }
      return false;
    } catch (e) {
      print('Backend connection check failed: $e');
      return false;
    }
  }

  Future<void> _navigateToDestination() async {
    if (_currentLocation == null) {
      setState(() {
        _errorMessage = 'Getting your location...';
        _isLoading = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // First check internet connection
      bool hasInternet = await NetworkService.checkInternetConnection();
      if (!hasInternet) {
        throw Exception(
            'No internet connection. Please check your network settings.');
      }

      print('Starting navigation request...');
      print(
          'Current location: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}');
      print('Destination: ${widget.destination}');
      print('Backend URL: ${Config.navigateUrl}');

      // Validate coordinates
      if (_currentLocation!.latitude < -90 ||
          _currentLocation!.latitude > 90 ||
          _currentLocation!.longitude < -180 ||
          _currentLocation!.longitude > 180) {
        throw Exception('Invalid current location coordinates');
      }

      // Prepare request body
      final requestBody = {
        'destination': widget.destination,
        'current_lat': _currentLocation!.latitude,
        'current_lon': _currentLocation!.longitude,
        'country': 'Ethiopia',
        'city': 'Addis Ababa',
        'bounds': {'north': 9.1, 'south': 8.9, 'east': 38.9, 'west': 38.6}
      };

      print('Request body: $requestBody');

      // Make the request with retry mechanism
      final response = await NetworkService.makeRequest(
        Config.navigateUrl,
        'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
        maxRetries: 3,
      );

      print('Response status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Check for specific error messages
        if (data['error'] != null) {
          String errorMessage = data['error'];
          if (errorMessage.toLowerCase().contains('outside')) {
            errorMessage =
                'Destination is outside Addis Ababa. Please enter a location within Addis Ababa.';
          } else if (errorMessage.toLowerCase().contains('not found')) {
            errorMessage =
                'Destination not found. Please check the spelling and try again.';
          } else if (errorMessage.toLowerCase().contains('invalid')) {
            errorMessage =
                'Invalid destination. Please enter a valid location in Addis Ababa.';
          }
          throw Exception(errorMessage);
        }

        // Validate response data
        if (data['route'] == null || data['route'] is! List) {
          throw Exception('Invalid route data received from server');
        }

        if (data['distance'] == null || data['duration'] == null) {
          throw Exception('Missing distance or duration information');
        }

        // Process route data
        final routeData = data['route'] as List;
        if (routeData.isEmpty) {
          throw Exception('No route found to destination');
        }

        setState(() {
          _routeCoordinates = routeData
              .map((coord) => latlong.LatLng(
                    double.parse(coord[1].toString()),
                    double.parse(coord[0].toString()),
                  ))
              .toList();
          _distance = data['distance'];
          _duration = data['duration'];
          _instructions = List<String>.from(data['instructions'] ?? []);
          _isLoading = false;
          _isNavigating = true;
        });

        if (_instructions.isNotEmpty) {
          await _messageQueueService.speakWithPause(
              'Starting navigation in Addis Ababa. ${_instructions[0]}');
        } else {
          await _messageQueueService.speakWithPause(
              'No navigation instructions available. Please try a different location in Addis Ababa.');
        }
      } else {
        String errorMessage;
        try {
          final errorData = jsonDecode(response.body);
          errorMessage = errorData['error'] ?? 'Failed to calculate route';
        } catch (e) {
          errorMessage = 'Server error: ${response.statusCode}';
        }

        if (errorMessage.toLowerCase().contains('not found')) {
          errorMessage =
              'Destination not found in Addis Ababa. Please enter a valid location within Addis Ababa.';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      print('Navigation error: $e');
      String userMessage;

      if (e.toString().contains('SocketException')) {
        userMessage =
            'Network error. Please check your internet connection and try again.';
      } else if (e.toString().contains('TimeoutException')) {
        userMessage =
            'Request timed out. Please check your connection and try again.';
      } else if (e.toString().contains('No internet connection')) {
        userMessage =
            'No internet connection. Please check your network settings and try again.';
      } else {
        userMessage = e.toString().replaceAll('Exception: ', '');
      }

      setState(() {
        _errorMessage = userMessage;
        _isLoading = false;
      });

      await _messageQueueService.speakWithPause(
          'Error: $userMessage Please try again with a location in Addis Ababa.');
    }
  }

  void _startRouteUpdates() {
    _routeUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isNavigating && _instructions.isNotEmpty) {
        // Check if we've moved at least 10 meters since last update
        if (_lastUpdateDistance >= ROUTE_UPDATE_DISTANCE) {
          _provideRouteUpdate();
          _lastUpdateDistance = 0.0; // Reset the distance counter
        }
      }
    });
  }

  Future<void> _provideRouteUpdate() async {
    if (_instructions.isEmpty) return;

    String currentInstruction = _instructions[_currentInstructionIndex];
    String formattedInstruction =
        _formatNavigationInstruction(currentInstruction);

    // Create contextual update message
    String updateMessage = '';

    // Add current instruction with context
    if (formattedInstruction.contains('turn')) {
      updateMessage += 'Prepare to $formattedInstruction';
    } else {
      updateMessage += formattedInstruction;
    }

    // Add next instruction if available and relevant
    if (_currentInstructionIndex + 1 < _instructions.length) {
      String nextInstruction = _formatNavigationInstruction(
          _instructions[_currentInstructionIndex + 1]);
      if (nextInstruction.contains('turn')) {
        updateMessage += '. After that, $nextInstruction';
      }
    }

    // Add safety recommendations based on recent detections
    String safetyRecommendation = _getSafetyRecommendation();
    if (safetyRecommendation.isNotEmpty) {
      updateMessage += '. $safetyRecommendation';
    }

    // Add remaining distance if significant
    if (_distance.isNotEmpty) {
      updateMessage += '. $_distance remaining';
    }

    // Use direct TTS for now until we fix the message queue
    await _flutterTts.speak(updateMessage);
    _lastUpdateTime = DateTime.now();
  }

  String _formatNavigationInstruction(String instruction) {
    // Remove any technical terms and make the instruction more natural
    String formatted = instruction
        .replaceAll('Turn right', 'turn right')
        .replaceAll('Turn left', 'turn left')
        .replaceAll('Continue straight', 'continue straight')
        .replaceAll('kilometers', 'kilometers ahead')
        .replaceAll('meters', 'meters ahead');

    // Add context based on the type of instruction
    if (formatted.contains('turn')) {
      formatted += '. Watch for the turn signal';
    } else if (formatted.contains('straight')) {
      formatted += '. Stay in your lane';
    }

    return formatted;
  }

  String _getSafetyRecommendation() {
    if (_recentDetections.isEmpty) return '';

    final now = DateTime.now();
    List<String> recommendations = [];
    Map<String, int> objectCounts = {};

    // Count and analyze recent detections
    for (var detection in _recentDetections) {
      String label = detection['label'].toString().toLowerCase();
      double distance =
          double.tryParse(detection['distance'].toString()) ?? 0.0;

      // Only count objects within safety threshold
      if (distance <= SAFETY_DISTANCE_THRESHOLD) {
        objectCounts[label] = (objectCounts[label] ?? 0) + 1;
      }
    }

    // Check for vehicles and provide specific recommendations
    if (objectCounts.containsKey('car') || objectCounts.containsKey('truck')) {
      String key = 'vehicle';
      if (_canAnnounceSafety(key, now)) {
        if (objectCounts['car']! > 1 || objectCounts['truck']! > 1) {
          recommendations
              .add('Multiple vehicles. Use sidewalk and wait for clear path');
        } else {
          recommendations
              .add('Vehicle nearby. Stay on sidewalk and be ready to stop');
        }
        _lastSafetyAnnouncements[key] = now;
      }
    }

    // Check for pedestrians
    if (objectCounts.containsKey('person')) {
      String key = 'pedestrian';
      if (_canAnnounceSafety(key, now)) {
        if (objectCounts['person']! > 2) {
          recommendations
              .add('Crowd ahead. Keep right and maintain safe distance');
        } else {
          recommendations
              .add('People ahead. Keep distance and be ready to adjust path');
        }
        _lastSafetyAnnouncements[key] = now;
      }
    }

    // Check for bicycles
    if (objectCounts.containsKey('bicycle')) {
      String key = 'bicycle';
      if (_canAnnounceSafety(key, now)) {
        if (objectCounts['bicycle']! > 1) {
          recommendations.add('Multiple bikes. Stay left and be ready to stop');
        } else {
          recommendations
              .add('Bike ahead. Keep right and watch for sudden movements');
        }
        _lastSafetyAnnouncements[key] = now;
      }
    }

    // Check for obstacles
    if (objectCounts.containsKey('obstacle') ||
        objectCounts.containsKey('construction') ||
        objectCounts.containsKey('barrier')) {
      String key = 'obstacle';
      if (_canAnnounceSafety(key, now)) {
        if (objectCounts.containsKey('construction')) {
          recommendations
              .add('Construction ahead. Find alternate route and use cane');
        } else {
          recommendations
              .add('Obstacle ahead. Use cane and proceed with caution');
        }
        _lastSafetyAnnouncements[key] = now;
      }
    }

    // Add general safety recommendation if no specific hazards
    if (recommendations.isEmpty && _canAnnounceSafety('general', now)) {
      // Time-based recommendations
      DateTime currentTime = DateTime.now();
      if (currentTime.hour >= 5 && currentTime.hour < 7) {
        recommendations
            .add('Early morning. Use cane and watch for reduced visibility');
      } else if (currentTime.hour >= 7 && currentTime.hour < 9) {
        recommendations
            .add('Rush hour. Stay alert and watch for sudden traffic changes');
      } else if (currentTime.hour >= 17 && currentTime.hour < 19) {
        recommendations.add('Evening rush. Watch traffic and stay on sidewalk');
      } else if (currentTime.hour >= 19 || currentTime.hour < 5) {
        recommendations.add('Night time. Use cane and stay in well-lit areas');
      } else {
        recommendations.add('Clear path. Stay right and maintain awareness');
      }
      _lastSafetyAnnouncements['general'] = now;
    }

    return recommendations.join('. ');
  }

  bool _canAnnounceSafety(String key, DateTime now) {
    if (!_lastSafetyAnnouncements.containsKey(key)) return true;

    final lastAnnouncement = _lastSafetyAnnouncements[key]!;
    return now.difference(lastAnnouncement) >= SAFETY_ANNOUNCEMENT_INTERVAL;
  }

  String _formatDetectionMessage(Map<String, dynamic> detection) {
    String label = detection['label'].toString().toLowerCase();
    String distance = detection['distance'].toString();
    String direction = detection['direction'].toString();

    // Format the message based on the type of detection and distance
    double dist = double.tryParse(distance) ?? 0.0;

    // For very close objects (less than 3 meters)
    if (dist < 3.0) {
      if (label.contains('person')) {
        return 'Person close $direction';
      } else if (label.contains('car')) {
        return 'Vehicle close $direction';
      } else if (label.contains('bicycle')) {
        return 'Bike close $direction';
      } else {
        return '$label close $direction';
      }
    }
    // For medium distance objects (3-6 meters)
    else if (dist < 6.0) {
      if (label.contains('person')) {
        return 'Person ahead $direction';
      } else if (label.contains('car')) {
        return 'Vehicle ahead $direction';
      } else if (label.contains('bicycle')) {
        return 'Bike ahead $direction';
      } else {
        return '$label ahead $direction';
      }
    }
    // For far objects (more than 6 meters)
    else {
      if (label.contains('person')) {
        return 'Person far $direction';
      } else if (label.contains('car')) {
        return 'Vehicle far $direction';
      } else if (label.contains('bicycle')) {
        return 'Bike far $direction';
      } else {
        return '$label far $direction';
      }
    }
  }

  Future<void> _provideSafetyReminder() async {
    if (_safetyReminders.isEmpty) return;

    _lastSafetyReminderIndex =
        (_lastSafetyReminderIndex + 1) % _safetyReminders.length;
    String reminder = _safetyReminders[_lastSafetyReminderIndex];
    await _messageQueueService.speakWithPause(reminder,
        priority: MessageQueueService.PRIORITY_ENVIRONMENTAL);
  }

  Future<void> _checkProximityToNextTurn() async {
    if (_instructions.isEmpty ||
        _currentInstructionIndex >= _instructions.length) {
      return;
    }

    String currentInstruction = _instructions[_currentInstructionIndex];
    double? distance = _extractDistance(currentInstruction);

    if (distance != null && distance <= PROXIMITY_THRESHOLD) {
      String proximityMessage =
          'Approaching turn: ${_formatNavigationInstruction(currentInstruction)}';
      await _messageQueueService.speakWithPause(proximityMessage,
          priority: MessageQueueService.PRIORITY_NAVIGATION);
    }
  }

  void _startCriticalUpdates() {
    _criticalUpdateTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_isNavigating && _instructions.isNotEmpty) {
        _checkCriticalDistance();
      }
    });
  }

  void _startSafetyChecks() {
    _safetyCheckTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (_isNavigating) {
        _provideSafetyReminder();
      }
    });
  }

  void _startProximityChecks() {
    _proximityCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_isNavigating && _instructions.isNotEmpty) {
        _checkProximityToNextTurn();
      }
    });
  }

  double? _extractDistance(String instruction) {
    try {
      RegExp regex = RegExp(r'(\d+\.?\d*)\s*kilometers');
      Match? match = regex.firstMatch(instruction);
      if (match != null) {
        return double.parse(match.group(1)!);
      }
    } catch (e) {
      print('Error extracting distance: $e');
    }
    return null;
  }

  Future<void> _checkCriticalDistance() async {
    if (_recentDetections.isEmpty) return;

    // Check for any objects within critical distance
    for (var detection in _recentDetections) {
      double distance =
          double.tryParse(detection['distance'].toString()) ?? 0.0;
      if (distance <= CRITICAL_DISTANCE_THRESHOLD) {
        String message = _formatDetectionMessage(detection);
        await _messageQueueService.speakWithPause(
          'Warning! $message',
          priority: MessageQueueService.PRIORITY_OBJECT_DETECTION,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Stop all timers and detection
        _detectionTimer?.cancel();
        _isDetecting = false;
        _flutterTts.stop();
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Navigation'),
          backgroundColor: Colors.blue,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              // Stop all timers and detection
              _detectionTimer?.cancel();
              _isDetecting = false;
              _flutterTts.stop();
              Navigator.of(context).pop();
            },
          ),
          actions: [
            IconButton(
              icon: Icon(
                _isConnected ? Icons.cloud_done : Icons.cloud_off,
                color: _isConnected ? Colors.green : Colors.red,
              ),
              onPressed: _testBackendConnection,
            ),
          ],
        ),
        body: Stack(
          children: [
            // Map
            FlutterMap(
              options: MapOptions(
                initialCenter: _currentLocation ??
                    const latlong.LatLng(9.0320, 38.7489), // Addis Ababa
                initialZoom: 15.0,
                onTap: (_, __) =>
                    setState(() => _isNavigating = !_isNavigating),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                ),
                if (_routeCoordinates.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routeCoordinates,
                        strokeWidth: 4.0,
                        color: Colors.blue,
                      ),
                    ],
                  ),
                if (_currentLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _currentLocation!,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.red,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
              ],
            ),

            // Camera preview
            if (_isCameraInitialized)
              Positioned(
                top: 20,
                right: 20,
                width: 120,
                height: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CameraPreview(_cameraController!),
                ),
              ),

            // Loading indicator
            if (_isLoading)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),

            // Error message
            if (_errorMessage != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: Colors.red.withOpacity(0.8),
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

            // Navigation info panel
            if (!_isLoading && _routeCoordinates.isNotEmpty)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(20)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                        offset: Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Drag handle
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),

                      // Current instruction
                      if (_instructions.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.navigation, color: Colors.blue),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _instructions[_currentInstructionIndex],
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 16),

                      // Route info
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildInfoCard(
                            Icons.route,
                            'Distance',
                            _distance,
                          ),
                          _buildInfoCard(
                            Icons.timer,
                            'Duration',
                            _duration,
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Navigation controls
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildControlButton(
                            Icons.volume_up,
                            'Repeat',
                            () => _messageQueueService.speakWithPause(
                                _instructions[_currentInstructionIndex]),
                          ),
                          _buildControlButton(
                            Icons.stop,
                            'Stop',
                            () {
                              setState(() => _isNavigating = false);
                              _flutterTts.stop();
                            },
                          ),
                          _buildControlButton(
                            Icons.play_arrow,
                            'Resume',
                            () {
                              setState(() => _isNavigating = true);
                              _messageQueueService.speakWithPause(
                                  _instructions[_currentInstructionIndex]);
                            },
                          ),
                        ],
                      ),

                      // Object detection log
                      if (_detectionLog.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 16),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Recent Detections:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ..._detectionLog.reversed
                                  .take(3)
                                  .map((log) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 4),
                                        child: Text(log),
                                      )),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(IconData icon, String title, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.blue),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton(
      IconData icon, String label, VoidCallback onPressed) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _connectionCheckTimer?.cancel();
    _detectionTimer?.cancel();
    _routeUpdateTimer?.cancel();
    _criticalUpdateTimer?.cancel();
    _safetyCheckTimer?.cancel();
    _proximityCheckTimer?.cancel();
    _cameraController?.dispose();
    _flutterTts.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
