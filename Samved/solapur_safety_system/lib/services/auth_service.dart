import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService extends ChangeNotifier {
  static const String baseUrl = 'http://10.131.3.221:3000/api/auth';
  
  String? _token;
  String? _role;
  String? _userId;

  String? get token => _token;
  String? get role => _role;
  String? get userId => _userId;
  bool get isAuthenticated => _token != null;

  Future<void> loadSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dataStr = prefs.getString('auth_data');
      if (dataStr != null) {
        final data = jsonDecode(dataStr);
        _token = data['token'];
        _role = data['role'];
        _userId = data['userId'];
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Could not load session: $e");
    }
  }

  Future<void> _saveSession(String token, String role, String userId) async {
    _token = token;
    _role = role;
    _userId = userId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_data', jsonEncode({
        'token': token,
        'role': role,
        'userId': userId
      }));
      notifyListeners();
    } catch (e) {
      debugPrint("Could not save session: $e");
    }
  }

  Future<void> logout() async {
    _token = null;
    _role = null;
    _userId = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_data');
      notifyListeners();
    } catch (e) {
      debugPrint("Could not logout session: $e");
    }
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        await _saveSession(data['token'], data['role'], data['user_id']?.toString() ?? '');
        return {'success': true, 'role': data['role']};
      } else {
        return {'success': false, 'error': data['error'] ?? 'Login failed'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network connection failed'};
    }
  }

  Future<Map<String, dynamic>> registerUser(String username, String password, String role) async {
    if (_token == null) return {'success': false, 'error': 'Not authenticated'};
    try {
      final response = await http.post(Uri.parse('$baseUrl/register'), 
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
          body: jsonEncode({'username': username, 'password': password, 'role': role}));
      final data = jsonDecode(response.body);
      if (response.statusCode == 201) return {'success': true, 'message': data['message']};
      return {'success': false, 'error': data['error'] ?? 'Registration failed'};
    } catch (e) {
      return {'success': false, 'error': 'Network connection failed'};
    }
  }

  Future<List<dynamic>> fetchUsers() async {
    if (_token == null) return [];
    try {
      final response = await http.get(Uri.parse('$baseUrl/users'), headers: {'Authorization': 'Bearer $_token'});
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (e) {
      debugPrint("Fetch users error: $e");
    }
    return [];
  }
}
