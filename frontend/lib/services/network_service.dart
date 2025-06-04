import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:async';
import '../config.dart';

class NetworkService {
  static const List<String> commonPorts = ['5000', '8000', '8080'];
  static const List<String> commonIPRanges = [
    '192.168.1.',
    '192.168.0.',
    '10.0.0.',
    '172.16.0.',
  ];

  static String _formatUrl(String ip, String port) {
    // Remove any extra spaces and ensure proper URL format
    return 'http://${ip.trim()}:${port.trim()}';
  }

  static Future<String?> discoverBackendIP() async {
    print('Starting backend discovery...');

    // First try the configured IP
    String configuredUrl = Config.backendUrl.trim();
    if (await _testConnection(configuredUrl)) {
      print('Found backend at configured URL: $configuredUrl');
      return configuredUrl;
    }

    print('Configured URL not available, scanning network...');

    // Try common IP ranges
    for (String ipRange in commonIPRanges) {
      print('Scanning range: $ipRange');
      for (int i = 1; i <= 254; i++) {
        String ip = '$ipRange$i';
        for (String port in commonPorts) {
          String url = _formatUrl(ip, port);
          print('Trying: $url');
          if (await _testConnection(url)) {
            print('Found backend at: $url');
            return url;
          }
        }
      }
    }

    print('No backend found after scanning all ranges');
    return null;
  }

  static Future<bool> _testConnection(String url) async {
    try {
      // Ensure URL is properly formatted
      final uri = Uri.parse(url.trim());
      print('Testing connection to: $uri');

      final response = await http.get(uri).timeout(const Duration(seconds: 1));
      return response.statusCode == 200;
    } on SocketException catch (e) {
      print('Socket error testing $url: $e');
      return false;
    } on TimeoutException catch (e) {
      print('Timeout testing $url: $e');
      return false;
    } on FormatException catch (e) {
      print('Invalid URL format: $url - $e');
      return false;
    } catch (e) {
      print('Error testing $url: $e');
      return false;
    }
  }

  static Future<bool> isBackendReachable() async {
    try {
      final url = Config.statusUrl.trim();
      print('Testing backend reachability at: $url');

      final uri = Uri.parse(url);
      final response = await http
          .get(uri)
          .timeout(Duration(seconds: Config.connectionTimeout));

      print('Backend response: ${response.statusCode}');
      return response.statusCode == 200;
    } on SocketException catch (e) {
      print('Socket error checking backend: $e');
      return false;
    } on TimeoutException catch (e) {
      print('Timeout checking backend: $e');
      return false;
    } on FormatException catch (e) {
      print('Invalid URL format: ${Config.statusUrl} - $e');
      return false;
    } catch (e) {
      print('Error checking backend: $e');
      return false;
    }
  }

  static Future<void> updateBackendUrl(String newUrl) async {
    // Ensure the URL is properly formatted before updating
    final formattedUrl = newUrl.trim();
    print('Updating backend URL to: $formattedUrl');
    Config.backendUrl = formattedUrl;
  }

  static Future<http.Response> makeRequest(
    String url,
    String method, {
    Map<String, String>? headers,
    Object? body,
    int maxRetries = 3,
  }) async {
    int retryCount = 0;
    Duration delay = const Duration(seconds: 1);

    // Ensure URL is properly formatted
    final formattedUrl = url.trim();
    print('Making request to formatted URL: $formattedUrl');

    while (retryCount < maxRetries) {
      try {
        print(
            'Making $method request to $formattedUrl (attempt ${retryCount + 1}/$maxRetries)');

        final uri = Uri.parse(formattedUrl);
        http.Response response;

        switch (method.toUpperCase()) {
          case 'GET':
            response = await http
                .get(uri, headers: headers)
                .timeout(Duration(seconds: Config.connectionTimeout));
            break;
          case 'POST':
            response = await http
                .post(uri, headers: headers, body: body)
                .timeout(Duration(seconds: Config.connectionTimeout));
            break;
          default:
            throw Exception('Unsupported HTTP method: $method');
        }

        print('Response status: ${response.statusCode}');
        return response;
      } on SocketException catch (e) {
        print('Socket error on attempt ${retryCount + 1}: $e');
        if (retryCount == maxRetries - 1) rethrow;
      } on TimeoutException catch (e) {
        print('Timeout on attempt ${retryCount + 1}: $e');
        if (retryCount == maxRetries - 1) rethrow;
      } on FormatException catch (e) {
        print('Invalid URL format: $formattedUrl - $e');
        rethrow; // Don't retry on format errors
      } catch (e) {
        print('Error on attempt ${retryCount + 1}: $e');
        if (retryCount == maxRetries - 1) rethrow;
      }

      retryCount++;
      if (retryCount < maxRetries) {
        print('Retrying in ${delay.inSeconds} seconds...');
        await Future.delayed(delay);
        delay *= 2; // Exponential backoff
      }
    }

    throw Exception('Failed after $maxRetries attempts');
  }

  static Future<bool> checkInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }
}
