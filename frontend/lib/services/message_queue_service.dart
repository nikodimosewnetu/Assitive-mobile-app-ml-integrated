import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';

class MessageQueueService {
  static const int PRIORITY_OBJECT_DETECTION = 1;
  static const int PRIORITY_ENVIRONMENTAL = 2;
  static const int PRIORITY_NAVIGATION = 3;

  final FlutterTts _flutterTts;
  final List<Map<String, dynamic>> _messageQueue = [];
  bool _isSpeaking = false;
  Completer<void>? _currentSpeechCompleter;

  MessageQueueService(this._flutterTts);

  Future<void> speakWithPause(String text,
      {int priority = PRIORITY_NAVIGATION}) async {
    // Don't add to queue if the same message was recently spoken
    if (_messageQueue.isNotEmpty &&
        _messageQueue.last['text'] == text &&
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(
                _messageQueue.last['timestamp'])) <
            const Duration(seconds: 2)) {
      return;
    }

    // Add message to queue with priority
    _messageQueue.add({
      'text': text,
      'priority': priority,
      'timestamp': DateTime.now().millisecondsSinceEpoch
    });

    // Sort queue by priority
    _messageQueue.sort((a, b) => a['priority'].compareTo(b['priority']));

    // If we're not currently speaking, start processing the queue
    if (!_isSpeaking) {
      await _processMessageQueue();
    }
  }

  Future<void> _processMessageQueue() async {
    if (_isSpeaking || _messageQueue.isEmpty) return;

    try {
      _isSpeaking = true;
      _currentSpeechCompleter = Completer<void>();

      while (_messageQueue.isNotEmpty && _isSpeaking) {
        Map<String, dynamic> currentMessage = _messageQueue.first;
        String text = currentMessage['text'];

        // Stop any ongoing speech
        await _flutterTts.stop();

        // Wait a brief moment to ensure previous speech has stopped
        await Future.delayed(const Duration(milliseconds: 100));

        // Create a completer for the current message
        Completer<void> messageCompleter = Completer<void>();

        // Set up completion handler
        _flutterTts.setCompletionHandler(() {
          if (!messageCompleter.isCompleted) {
            messageCompleter.complete();
          }
        });

        // Speak the message
        await _flutterTts.speak(text);

        // Wait for the message to complete
        await messageCompleter.future;

        // Remove the processed message from the queue
        _messageQueue.removeAt(0);

        // Add a pause between messages
        if (_messageQueue.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      _currentSpeechCompleter?.complete();
    } catch (e) {
      print('TTS error: $e');
      _currentSpeechCompleter?.completeError(e);
    } finally {
      _isSpeaking = false;
      _currentSpeechCompleter = null;

      // If there are more messages in the queue, process them
      if (_messageQueue.isNotEmpty) {
        await _processMessageQueue();
      }
    }
  }

  Future<void> stop() async {
    _isSpeaking = false;
    _messageQueue.clear();
    await _flutterTts.stop();
  }
}
