import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:geolocator/geolocator.dart';
import 'dart:async';

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
  _DestinationInputScreenState createState() => _DestinationInputScreenState();
}

class _DestinationInputScreenState extends State<DestinationInputScreen> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  bool _isListening = false;
  String _destination = '';
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeSpeech();
  }

  Future<void> _initializeSpeech() async {
    bool available = await _speech.initialize();
    if (available) {
      setState(() => _isInitialized = true);
      await _speakWithPause(
          'Welcome to Assistive Navigation. Please say your destination in Amharic or English.');
    } else {
      setState(() => _isInitialized = false);
      await _speakWithPause('Speech recognition is not available.');
    }
  }

  Future<void> _speakWithPause(String text) async {
    await _flutterTts.speak(text);
    await Future.delayed(const Duration(seconds: 2));
  }

  Future<void> _startListening() async {
    if (!_isInitialized) {
      await _speakWithPause('Speech recognition is not available.');
      return;
    }

    setState(() => _isListening = true);
    await _speakWithPause('Please say your destination in Amharic or English.');

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
      _speakWithPause('Navigating to $_destination.');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => NavigationScreen(
            destination: _destination,
            onObjectDetected: (detection) async {
              await _speakWithPause(
                  'Detected ${detection['label']} ${detection['distance']} meters ${detection['direction']}.');
            },
          ),
        ),
      );
    } else {
      _speakWithPause('No destination detected. Please try again.');
    }
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
                  ? 'Listening... Speak your destination in Amharic or English.'
                  : 'Press the button and speak your destination in Amharic or English.',
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
            'http://192.168.43.156:5000/detect_objects'), // Replace with your computer's IP
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
  _NavigationScreenState createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen>
    with WidgetsBindingObserver {
  final FlutterTts _flutterTts = FlutterTts();
  List<latlong.LatLng> _routeCoordinates = [];
  String _distance = '';
  String _duration = '';
  List<String> _instructions = [];
  String? _errorMessage;
  bool _isLoading = true;
  latlong.LatLng? _currentLocation;
  final String _backendUrl = 'http://192.168.43.156:5000';
  Timer? _connectionCheckTimer;
  Timer? _routeUpdateTimer;
  bool _isNavigating = false;
  int _currentInstructionIndex = 0;
  CameraController? _cameraController;
  bool _isDetecting = false;
  Timer? _detectionTimer;
  List<String> _detectionLog = [];
  bool _isCameraInitialized = false;
  DateTime? _lastUpdateTime;
  Timer? _criticalUpdateTimer;
  double _lastAnnouncedDistance = 0.0;
  static const double CRITICAL_DISTANCE = 0.1; // 100 meters
  Timer? _safetyCheckTimer;
  Timer? _proximityCheckTimer;
  List<String> _safetyReminders = [
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
  static const double PROXIMITY_THRESHOLD = 0.05; // 50 meters

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeLocation();
    _initializeTts();
    _initializeCamera();
    _startConnectionCheck();
    _startRouteUpdates();
    _startCriticalUpdates();
    _startSafetyChecks();
    _startProximityChecks();
  }

  Future<void> _initializeTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    // Test TTS
    await _speakWithPause(
        "Navigation system initialized. Ready to assist you.");
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

  Future<void> _testBackendConnection() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_backendUrl/test_detection'),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          await _speakWithPause('Object detection system is ready');
        } else {
          setState(
              () => _errorMessage = 'Object detection system is not ready');
        }
      } else {
        setState(
            () => _errorMessage = 'Failed to connect to detection service');
      }
    } catch (e) {
      setState(
          () => _errorMessage = 'Error connecting to detection service: $e');
    }
  }

  void _startObjectDetection() {
    _detectionTimer?.cancel();
    _detectionTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!_isDetecting && _isCameraInitialized) {
        _detectObjects();
      }
    });
  }

  Future<void> _detectObjects() async {
    if (_isDetecting || !_isCameraInitialized) return;

    setState(() => _isDetecting = true);

    try {
      final image = await _cameraController!.takePicture();
      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http
          .post(
            Uri.parse('$_backendUrl/detect_objects'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'image': base64Image}),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['detections'] != null) {
          final detections = data['detections'] as List;
          for (var detection in detections) {
            widget.onObjectDetected(detection);
            final message =
                '${detection['label']} - ${detection['distance']}m ${detection['direction']}';
            _detectionLog.add(message);
            await _speakWithPause(message);
          }
        }
      } else {
        print('Object detection error: ${response.body}');
      }
    } catch (e) {
      print('Object detection error: $e');
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
    _connectionCheckTimer =
        Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!await _checkBackendConnection()) {
        setState(() {
          _errorMessage = 'Lost connection to navigation service';
        });
      }
    });
  }

  Future<bool> _checkBackendConnection() async {
    try {
      final response = await http
          .get(Uri.parse('$_backendUrl/status'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['status'] == 'ok';
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
      final response = await http.post(
        Uri.parse('$_backendUrl/navigate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'destination': widget.destination,
          'current_lat': _currentLocation!.latitude,
          'current_lon': _currentLocation!.longitude,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _routeCoordinates = (data['route'] as List)
              .map((coord) => latlong.LatLng(coord[1], coord[0]))
              .toList();
          _distance = data['distance'];
          _duration = data['duration'];
          _instructions = List<String>.from(data['instructions']);
          _isLoading = false;
          _isNavigating = true;
        });

        if (_instructions.isNotEmpty) {
          await _speakWithPause(_instructions[0]);
        }
      } else {
        final error = jsonDecode(response.body)['error'];
        setState(() {
          _errorMessage = error ?? 'Failed to calculate route';
          _isLoading = false;
        });
        await _speakWithPause('Error: $_errorMessage');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
      await _speakWithPause('Error calculating route. Please try again.');
    }
  }

  void _startRouteUpdates() {
    _routeUpdateTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      if (_isNavigating && _instructions.isNotEmpty) {
        _provideRouteUpdate();
      }
    });
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

  Future<void> _checkCriticalDistance() async {
    if (_instructions.isEmpty) return;

    // Extract distance from current instruction
    String currentInstruction = _instructions[_currentInstructionIndex];
    double? distance = _extractDistance(currentInstruction);

    if (distance != null &&
        distance <= CRITICAL_DISTANCE &&
        distance != _lastAnnouncedDistance) {
      String criticalMessage =
          'Warning: ${_instructions[_currentInstructionIndex]}';
      await _speakWithPause(criticalMessage);
      _lastAnnouncedDistance = distance;
    }
  }

  double? _extractDistance(String instruction) {
    try {
      // Look for patterns like "in X.X kilometers" or "for X.X kilometers"
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

  Future<void> _provideRouteUpdate() async {
    if (_instructions.isEmpty) return;

    // Get current instruction
    String currentInstruction = _instructions[_currentInstructionIndex];

    // Get next instruction if available
    String nextInstruction = '';
    if (_currentInstructionIndex + 1 < _instructions.length) {
      nextInstruction = _instructions[_currentInstructionIndex + 1];
    }

    // Create update message with more natural language
    String updateMessage = 'Navigation update: ';

    // Add current progress
    updateMessage += 'You are currently on track. ';

    // Add current instruction
    updateMessage += currentInstruction;

    // Add next instruction if available
    if (nextInstruction.isNotEmpty) {
      updateMessage += '. After that, $nextInstruction';
    }

    // Add remaining information
    updateMessage +=
        '. You have $_distance remaining, estimated time $_duration';

    // Add safety reminder
    updateMessage += '. Please stay alert and watch for obstacles.';

    // Add environmental awareness
    updateMessage += _getEnvironmentalContext();

    // Speak the update
    await _speakWithPause(updateMessage);
    _lastUpdateTime = DateTime.now();
  }

  String _getEnvironmentalContext() {
    // This could be enhanced with real-time weather and time data
    DateTime now = DateTime.now();
    String context = '';

    // Time-based context
    if (now.hour >= 5 && now.hour < 7) {
      context = '. It\'s early morning, watch for reduced visibility.';
    } else if (now.hour >= 7 && now.hour < 9) {
      context = '. It\'s rush hour, be extra careful with traffic.';
    } else if (now.hour >= 17 && now.hour < 19) {
      context = '. It\'s evening rush hour, stay alert.';
    } else if (now.hour >= 19 || now.hour < 5) {
      context = '. It\'s dark outside, be extra cautious.';
    }

    return context;
  }

  Future<void> _provideSafetyReminder() async {
    if (_safetyReminders.isEmpty) return;

    // Get a different reminder each time
    int newIndex;
    do {
      newIndex =
          DateTime.now().millisecondsSinceEpoch % _safetyReminders.length;
    } while (
        newIndex == _lastSafetyReminderIndex && _safetyReminders.length > 1);

    _lastSafetyReminderIndex = newIndex;
    String reminder = _safetyReminders[newIndex];
    await _speakWithPause("Safety reminder: $reminder");
  }

  Future<void> _checkProximityToNextTurn() async {
    if (_instructions.isEmpty) return;

    String currentInstruction = _instructions[_currentInstructionIndex];
    double? distance = _extractDistance(currentInstruction);

    if (distance != null && distance <= PROXIMITY_THRESHOLD) {
      String proximityMessage = 'Approaching turn: ${currentInstruction}';
      await _speakWithPause(proximityMessage);
    }
  }

  Future<void> _updateCurrentInstruction() async {
    if (_currentInstructionIndex < _instructions.length - 1) {
      setState(() {
        _currentInstructionIndex++;
      });
      await _speakWithPause(_instructions[_currentInstructionIndex]);
    }
  }

  Future<void> _speakWithPause(String text) async {
    try {
      await _flutterTts.stop(); // Stop any ongoing speech
      await _flutterTts.speak(text);
      await Future.delayed(const Duration(seconds: 2));
    } catch (e) {
      print('TTS error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigation'),
        backgroundColor: Colors.blue,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Map
          FlutterMap(
            options: MapOptions(
              initialCenter: _currentLocation ??
                  const latlong.LatLng(9.0320, 38.7489), // Addis Ababa
              initialZoom: 15.0,
              onTap: (_, __) => setState(() => _isNavigating = !_isNavigating),
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
              top: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red.shade900),
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
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                          () => _speakWithPause(
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
                            _speakWithPause(
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
                                      padding: const EdgeInsets.only(bottom: 4),
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
