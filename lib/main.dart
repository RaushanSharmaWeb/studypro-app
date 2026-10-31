import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StudyProApp());
}

// ==========================================
// 1. FIREBASE CONFIG & SERVICE (education-921c2)
// ==========================================
class FirebaseConfig {
  static const String apiKey = "AIzaSyA-8OSQlYP091sHcZQfCJmFFXsKxJxDC8Q";
  static const String dbUrl = "https://education-921c2-default-rtdb.firebaseio.com";
}

class AppService {
  static Future> fetchAllBatches() async {
    try {
      final res = await http.get(Uri.parse("${FirebaseConfig.dbUrl}/batches.json"));
      if (res.statusCode == 200 && res.body != "null") {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {};
  }

  static Future<void> saveBatch(String id, Map<String, dynamic> data) async {
    await http.patch(
      Uri.parse("${FirebaseConfig.dbUrl}/batches/$id.json"),
      body: jsonEncode(data),
    );
  }

  static Future<String> getAdminPin() async {
    try {
      final res = await http.get(Uri.parse("${FirebaseConfig.dbUrl}/settings/adminPin.json"));
      if (res.statusCode == 200 && res.body != "null") {
        return jsonDecode(res.body).toString();
      }
    } catch (_) {}
    return "1234";
  }

  static Future<String?> authenticate({
    required String email,
    required String password,
    required bool isSignUp,
  }) async {
    final endpoint = isSignUp ? "signUp" : "signInWithPassword";
    final url = Uri.parse(
        "https://identitytoolkit.googleapis.com/v1/accounts:$endpoint?key=${FirebaseConfig.apiKey}");
    try {
      final res = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "email": email.trim(),
          "password": password.trim(),
          "returnSecureToken": true,
        }),
      );
      if (res.statusCode == 200) {
        return null;
      } else {
        return await _fallbackDbAuth(email.trim(), password.trim(), isSignUp);
      }
    } catch (_) {
      return await _fallbackDbAuth(email.trim(), password.trim(), isSignUp);
    }
  }

  static Future<String?> _fallbackDbAuth(String email, String password, bool isSignUp) async {
    final safeKey = base64Url.encode(utf8.encode(email.toLowerCase())).replaceAll('=', '');
    final userUrl = Uri.parse("${FirebaseConfig.dbUrl}/app_users/$safeKey.json");
    try {
      final res = await http.get(userUrl);
      final existing = res.body != "null" ? jsonDecode(res.body) : null;
      if (isSignUp) {
        if (existing != null) return "यह ईमेल पहले से रजिस्टर है। कृपया Login करें।";
        await http.put(
          userUrl,
          body: jsonEncode({
            "email": email,
            "password": password,
            "createdAt": DateTime.now().millisecondsSinceEpoch
          }),
        );
        return null;
      } else {
        if (existing == null) return "अकाउंट नहीं मिला। कृपया पहले Sign Up करें।";
        if (existing["password"] != password) return "गलत पासवर्ड! कृपया सही पासवर्ड डालें।";
        return null;
      }
    } catch (e) {
      return "नेटवर्क त्रुटि: $e";
    }
  }
}

// ==========================================
// 2. MAIN APP & THEME CONTROLLER
// ==========================================
class StudyProApp extends StatefulWidget {
  const StudyProApp({super.key});

  @override
  State<StudyProApp> createState() => _StudyProAppState();
}

class _StudyProAppState extends State<StudyProApp> {
  bool _isDark = true;
  bool _isLoading = true;
  String? _loggedInEmail;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDark = prefs.getBool('is_dark') ?? true;
      _loggedInEmail = prefs.getString('user_email');
      _isLoading = false;
    });
  }

  Future<void> _toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _isDark = !_isDark);
    await prefs.setBool('is_dark', _isDark);
  }

  Future<void> _onLoginSuccess(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_email', email);
    setState(() => _loggedInEmail = email);
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_email');
    setState(() => _loggedInEmail = null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StudyPro',
      debugShowCheckedModeBanner: false,
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0F19),
        cardColor: const Color(0xFF151C2C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFF8B5CF6),
          surface: Color(0xFF151C2C),
        ),
        useMaterial3: true,
      ),
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        cardColor: Colors.white,
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF4F46E5),
          secondary: Color(0xFF7C3AED),
          surface: Colors.white,
        ),
        useMaterial3: true,
      ),
      home: _isLoading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _loggedInEmail == null
              ? AuthScreen(onAuthenticated: _onLoginSuccess)
              : MainDashboardScreen(
                  userEmail: _loggedInEmail!,
                  isDark: _isDark,
                  onToggleTheme: _toggleTheme,
                  onLogout: _logout,
                ),
    );
  }
}

// ==========================================
// 3. LOGIN & SIGN-UP GATE SCREEN
// ==========================================
class AuthScreen extends StatefulWidget {
  final ValueChanged<String> onAuthenticated;
  const AuthScreen({super.key, required this.onAuthenticated});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isSignUp = false;
  bool _loading = false;
  String? _error;
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = "कृपया सही Email एड्रेस डालें।");
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = "पासवर्ड कम से कम 6 अक्षरों का होना चाहिए।");
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    final err = await AppService.authenticate(
      email: email,
      password: pass,
      isSignUp: _isSignUp,
    );

    if (!mounted) return;
    setState(() => _loading = false);
    if (err != null) {
      setState(() => _error = err);
    } else {
      widget.onAuthenticated(email);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.school_rounded, size: 36, color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isSignUp ? "Create StudyPro Account" : "Welcome to StudyPro",
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Distraction-Free Personal Study Portal",
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                    ),
                    const SizedBox(height: 24),
                    if (_error != null)
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.redAccent),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_error!,
                                  style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    if (_isSignUp) ...[
                      TextField(
                        controller: _nameCtrl,
                        decoration: InputDecoration(
                          labelText: "Your Name",
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: "Email Address",
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: "Password",
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              )
                            : Text(
                                _isSignUp ? "Sign Up & Start Studying" : "Login to StudyPro",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: () => setState(() {
                        _isSignUp = !_isSignUp;
                        _error = null;
                      }),
                      child: Text(
                        _isSignUp
                            ? "Already have an account? Login"
                            : "Don't have an account? Sign Up",
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 4. MAIN DASHBOARD (BATCHES + POMODORO + NAV)
// ==========================================
class MainDashboardScreen extends StatefulWidget {
  final String userEmail;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final VoidCallback onLogout;

  const MainDashboardScreen({
    super.key,
    required this.userEmail,
    required this.isDark,
    required this.onToggleTheme,
    required this.onLogout,
  });

  @override
  State<MainDashboardScreen> createState() => _MainDashboardScreenState();
}

class _MainDashboardScreenState extends State<MainDashboardScreen> {
  Map<String, dynamic> _batches = {};
  bool _loading = true;
  String _searchQuery = "";

  int _pomoSeconds = 25 * 60;
  bool _pomoRunning = false;
  Timer? _pomoTimer;
  Map<String, dynamic>? _resumeData;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _pomoTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final batches = await AppService.fetchAllBatches();
    final prefs = await SharedPreferences.getInstance();
    final resumeStr = prefs.getString('study_resume_state');
    if (!mounted) return;
    setState(() {
      _batches = batches;
      if (resumeStr != null) {
        try {
          _resumeData = jsonDecode(resumeStr);
        } catch (_) {}
      }
      _loading = false;
    });
  }

  void _togglePomodoro() {
    if (_pomoRunning) {
      _pomoTimer?.cancel();
      setState(() => _pomoRunning = false);
    } else {
      setState(() => _pomoRunning = true);
      _pomoTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_pomoSeconds > 0) {
          setState(() => _pomoSeconds--);
        } else {
          timer.cancel();
          setState(() {
            _pomoRunning = false;
            _pomoSeconds = 25 * 60;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("🎉 25m Study Session Complete! Take a 5m break.")),
          );
        }
      });
    }
  }

  void _resetPomodoro() {
    _pomoTimer?.cancel();
    setState(() {
      _pomoRunning = false;
      _pomoSeconds = 25 * 60;
    });
  }

  String _formatPomo(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return "$m:$sec";
  }

  Future<void> _openAdminPanel() async {
    final pinCtrl = TextEditingController();
    final realPin = await AppService.getAdminPin();
    if (!mounted) return;

    final unlocked = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Admin Access"),
        content: TextField(
          controller: pinCtrl,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: "Enter Admin PIN (Default: 1234)",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              if (pinCtrl.text.trim() == realPin) {
                Navigator.pop(ctx, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Invalid PIN!")),
                );
              }
            },
            child: const Text("Unlock"),
          ),
        ],
      ),
    );

    if (unlocked == true && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AdminPanelScreen(batches: _batches, onUpdated: _loadData),
        ),
      );
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final batchEntries = _batches.entries.where((e) {
      final b = Map<String, dynamic>.from(e.value as Map);
      final name = (b['name'] ?? '').toString().toLowerCase();
      final exam = (b['targetExam'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase()) ||
          exam.contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.school, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 8),
            const Text("StudyPro", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatPomo(_pomoSeconds),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: _togglePomodoro,
                    child: Icon(
                      _pomoRunning ? Icons.pause_circle_filled : Icons.play_circle_fill,
                      size: 20,
                      color: const Color(0xFF6366F1),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: _resetPomodoro,
                    child: const Icon(Icons.refresh, size: 16),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode, size: 20),
            onPressed: widget.onToggleTheme,
          ),
          IconButton(
            icon: const Icon(Icons.admin_panel_settings_outlined, size: 22),
            onPressed: _openAdminPanel,
          ),
          IconButton(
            icon: const Icon(Icons.logout, size: 20),
            onPressed: widget.onLogout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_resumeData != null && _batches.containsKey(_resumeData!['batchId']))
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF6366F1).withOpacity(0.25),
                      const Color(0xFF8B5CF6).withOpacity(0.25),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.history, color: Color(0xFF6366F1)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Resume \"${_resumeData!['videoTitle'] ?? 'Last Lecture'}\"",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                      ),
                      onPressed: () {
                        final bId = _resumeData!['batchId'];
                        final bMap = Map<String, dynamic>.from(_batches[bId] as Map);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BatchClassroomScreen(
                              batchId: bId,
                              batchData: bMap,
                              initialResume: _resumeData,
                            ),
                          ),
                        ).then((_) => _loadData());
                      },
                      child: const Text("Resume", style: TextStyle(fontSize: 12)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('study_resume_state');
                        setState(() => _resumeData = null);
                      },
                    ),
                  ],
                ),
              ),
            TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: "Search batches or target exams...",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (batchEntries.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    children: [
                      const Icon(Icons.video_library_outlined, size: 54, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text("No batches found. Add a batch from the Admin Panel!"),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _openAdminPanel,
                        icon: const Icon(Icons.add),
                        label: const Text("Open Admin Panel"),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...batchEntries.map((entry) {
                final bId = entry.key;
                final b = Map<String, dynamic>.from(entry.value as Map);
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BatchClassroomScreen(batchId: bId, batchData: b),
                        ),
                      ).then((_) => _loadData());
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (b['thumbnail'] != null && b['thumbnail'].toString().isNotEmpty)
                          AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Image.network(
                              b['thumbnail'].toString(),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: Colors.indigo.withOpacity(0.2),
                                child: const Icon(Icons.play_lesson, size: 48),
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF6366F1).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      (b['targetExam'] ?? 'JEE / NEET').toString(),
                                      style: const TextStyle(
                                        color: Color(0xFF6366F1),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.teal.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      (b['language'] ?? 'Hinglish').toString(),
                                      style: const TextStyle(
                                        color: Colors.teal,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                (b['name'] ?? 'Untitled Batch').toString(),
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              if (b['description'] != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  b['description'].toString(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                                ),
                              ],
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF6366F1),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            BatchClassroomScreen(batchId: bId, batchData: b),
                                      ),
                                    ).then((_) => _loadData());
                                  },
                                  icon: const Icon(Icons.play_circle_fill, size: 18),
                                  label: const Text("Study Now"),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 5. CLASSROOM SCREEN (SUBJECTS + NATIVE PLAYER + NOTES)
// ==========================================
class LectureItem {
  final String videoId;
  final String title;
  final String subjectName;
  LectureItem({required this.videoId, required this.title, required this.subjectName});
}

class BatchClassroomScreen extends StatefulWidget {
  final String batchId;
  final Map<String, dynamic> batchData;
  final Map<String, dynamic>? initialResume;

  const BatchClassroomScreen({
    super.key,
    required this.batchId,
    required this.batchData,
    this.initialResume,
  });

  @override
  State<BatchClassroomScreen> createState() => _BatchClassroomScreenState();
}

class _BatchClassroomScreenState extends State<BatchClassroomScreen> {
  String? _selectedSubjectId;
  List<LectureItem> _lectures = [];
  bool _loadingPlaylist = false;

  LectureItem? _activeLecture;
  int _initialSeekSeconds = 0;

  Set<String> _completedVideos = {};
  List> _notes = [];
  final _noteCtrl = TextEditingController();
  int _currentPlaybackSeconds = 0;
  final GlobalKey<_NativeStudyPlayerState> _playerKey = GlobalKey<_NativeStudyPlayerState>();

  @override
  void initState() {
    super.initState();
    _initClassroom();
  }

  Future<void> _initClassroom() async {
    final prefs = await SharedPreferences.getInstance();
    final compList = prefs.getStringList('completed_${widget.batchId}') ?? [];
    _completedVideos = compList.toSet();

    final subjectsMap = widget.batchData['subjects'] as Map?;
    if (subjectsMap != null && subjectsMap.isNotEmpty) {
      final firstSubId =
          widget.initialResume?['subjectId']?.toString() ?? subjectsMap.keys.first.toString();
      await _selectSubject(firstSubId);
    } else if (widget.batchData['playlistId'] != null &&
        widget.batchData['playlistId'].toString().isNotEmpty) {
      await _loadPlaylistVideos(widget.batchData['playlistId'].toString(), "General");
    }

    if (widget.initialResume != null) {
      final rVid = widget.initialResume!['videoId']?.toString();
      final rTitle = widget.initialResume!['videoTitle']?.toString() ?? "Resumed Lecture";
      final rSec = (widget.initialResume!['timestamp'] as num?)?.toInt() ?? 0;
      if (rVid != null && rVid.isNotEmpty) {
        _playLecture(
          LectureItem(videoId: rVid, title: rTitle, subjectName: _selectedSubjectId ?? "Study"),
          startSeconds: rSec,
        );
      }
    }
  }

  Future<void> _selectSubject(String subjectId) async {
    setState(() {
      _selectedSubjectId = subjectId;
      _lectures = [];
      _loadingPlaylist = true;
    });

    final subjectsMap = Map<String, dynamic>.from(widget.batchData['subjects'] as Map);
    if (!subjectsMap.containsKey(subjectId)) {
      setState(() => _loadingPlaylist = false);
      return;
    }
    final sub = Map<String, dynamic>.from(subjectsMap[subjectId] as Map);
    final subName = (sub['name'] ?? subjectId).toString();
    final contents = sub['contents'] as Map?;

    final List<LectureItem> loaded = [];
    final ytExplode = yt.YoutubeExplode();

    try {
      if (contents != null) {
        for (final entry in contents.entries) {
          final item = Map<String, dynamic>.from(entry.value as Map);
          final type = (item['type'] ?? 'video').toString();
          final targetId =
              (item['ytId'] ?? item['playlistId'] ?? item['videoId'] ?? '').toString();
          final customTitle = (item['title'] ?? 'Lecture').toString();

          if (type == 'playlist' && targetId.isNotEmpty) {
            await for (final video in ytExplode.playlists.getVideos(targetId)) {
              loaded.add(LectureItem(
                videoId: video.id.value,
                title: video.title,
                subjectName: subName,
              ));
            }
          } else if (targetId.isNotEmpty) {
            final cleanVid = _extractVideoId(targetId);
            loaded.add(LectureItem(
              videoId: cleanVid,
              title: customTitle,
              subjectName: subName,
            ));
          }
        }
      }
    } catch (_) {
    } finally {
      ytExplode.close();
    }

    if (!mounted) return;
    setState(() {
      _lectures = loaded;
      _loadingPlaylist = false;
      if (_activeLecture == null && loaded.isNotEmpty) {
        _playLecture(loaded.first);
      }
    });
  }

  Future<void> _loadPlaylistVideos(String playlistId, String subjectName) async {
    setState(() => _loadingPlaylist = true);
    final List<LectureItem> loaded = [];
    final ytExplode = yt.YoutubeExplode();
    try {
      await for (final v in ytExplode.playlists.getVideos(playlistId)) {
        loaded.add(LectureItem(videoId: v.id.value, title: v.title, subjectName: subjectName));
      }
    } catch (_) {
    } finally {
      ytExplode.close();
    }
    if (!mounted) return;
    setState(() {
      _lectures = loaded;
      _loadingPlaylist = false;
      if (_activeLecture == null && loaded.isNotEmpty) {
        _playLecture(loaded.first);
      }
    });
  }

  Future<void> _playLecture(LectureItem item, {int startSeconds = 0}) async {
    final prefs = await SharedPreferences.getInstance();
    final rawNotes = prefs.getString('notes_${widget.batchId}_${item.videoId}');
    List> loadedNotes = [];
    if (rawNotes != null) {
      loadedNotes = List>.from(jsonDecode(rawNotes));
    }
    setState(() {
      _activeLecture = item;
      _initialSeekSeconds = startSeconds;
      _notes = loadedNotes;
    });
  }

  Future<void> _toggleCompleted(String videoId) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_completedVideos.contains(videoId)) {
        _completedVideos.remove(videoId);
      } else {
        _completedVideos.add(videoId);
      }
    });
    await prefs.setStringList('completed_${widget.batchId}', _completedVideos.toList());
  }

  Future<void> _saveNote() async {
    final text = _noteCtrl.text.trim();
    if (text.isEmpty || _activeLecture == null) return;
    final note = {
      "time": _currentPlaybackSeconds,
      "text": text,
    };
    setState(() {
      _notes.insert(0, note);
      _noteCtrl.clear();
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'notes_${widget.batchId}_${_activeLecture!.videoId}',
      jsonEncode(_notes),
    );
  }

  Future<void> _saveResumeProgress(int seconds) async {
    _currentPlaybackSeconds = seconds;
    if (_activeLecture == null || seconds < 3) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'study_resume_state',
      jsonEncode({
        "batchId": widget.batchId,
        "subjectId": _selectedSubjectId,
        "videoId": _activeLecture!.videoId,
        "videoTitle": _activeLecture!.title,
        "timestamp": seconds,
        "updatedAt": DateTime.now().millisecondsSinceEpoch,
      }),
    );
  }

  String _formatClock(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  static String _extractVideoId(String input) {
    final reg = RegExp(r'(?:v=|\/)([0-9A-Za-z_-]{11}).*');
    final match = reg.firstMatch(input.trim());
    if (match != null && match.groupCount >= 1) return match.group(1)!;
    return input.trim();
  }

  @override
  Widget build(BuildContext context) {
    final subjectsMap = widget.batchData['subjects'] as Map?;
    final totalCount = _lectures.length;
    final doneCount = _lectures.where((l) => _completedVideos.contains(l.videoId)).length;
    final progressPct = totalCount == 0 ? 0 : ((doneCount / totalCount) * 100).round();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (widget.batchData['name'] ?? 'Batch').toString(),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            Text(
              "Progress: $progressPct% ($doneCount/$totalCount)",
              style: const TextStyle(fontSize: 11, color: Colors.tealAccent),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_activeLecture != null)
            NativeStudyPlayer(
              key: _playerKey,
              videoId: _activeLecture!.videoId,
              videoTitle: _activeLecture!.title,
              initialSeekSeconds: _initialSeekSeconds,
              onProgress: _saveResumeProgress,
            )
          else
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: Colors.black,
                child: Center(
                  child: _loadingPlaylist
                      ? const CircularProgressIndicator()
                      : const Text(
                          "Select a Subject or Lecture below to start studying",
                          style: TextStyle(color: Colors.white70),
                        ),
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                if (subjectsMap != null && subjectsMap.isNotEmpty) ...[
                  SizedBox(
                    height: 46,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: subjectsMap.entries.map((entry) {
                        final sId = entry.key.toString();
                        final sData = Map<String, dynamic>.from(entry.value as Map);
                        final isSelected = _selectedSubjectId == sId;
                        return Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: ChoiceChip(
                            selected: isSelected,
                            selectedColor: const Color(0xFF6366F1),
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : null,
                              fontWeight: FontWeight.bold,
                            ),
                            label: Text((sData['name'] ?? sId).toString()),
                            onSelected: (_) => _selectSubject(sId),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (_activeLecture != null)
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _activeLecture!.title,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _toggleCompleted(_activeLecture!.videoId),
                              icon: Icon(
                                _completedVideos.contains(_activeLecture!.videoId)
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: _completedVideos.contains(_activeLecture!.videoId)
                                    ? Colors.greenAccent
                                    : null,
                              ),
                              label: Text(
                                _completedVideos.contains(_activeLecture!.videoId)
                                    ? "Completed ✅"
                                    : "Mark Completed",
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.bookmark_added, size: 18, color: Color(0xFF6366F1)),
                            SizedBox(width: 8),
                            Text("My Timestamped Notes",
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _noteCtrl,
                          decoration: InputDecoration(
                            hintText: "Write a formula or key point...",
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _saveNote,
                            icon: const Icon(Icons.access_time, size: 16),
                            label: Text("Save at [${_formatClock(_currentPlaybackSeconds)}]"),
                          ),
                        ),
                        if (_notes.isNotEmpty) ...[
                          const Divider(height: 20),
                          ..._notes.map((n) {
                            final sec = (n['time'] as num).toInt();
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: ActionChip(
                                backgroundColor: const Color(0xFF6366F1).withOpacity(0.2),
                                label: Text(
                                  "[${_formatClock(sec)}]",
                                  style: const TextStyle(
                                    color: Color(0xFF6366F1),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                                onPressed: () => _playerKey.currentState?.seekToSeconds(sec),
                              ),
                              title: Text(n['text'].toString()),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text("Course Lectures",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                if (_loadingPlaylist)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  ..._lectures.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final lec = entry.value;
                    final isPlaying = _activeLecture?.videoId == lec.videoId;
                    final isDone = _completedVideos.contains(lec.videoId);
                    return Card(
                      color: isPlaying ? const Color(0xFF6366F1).withOpacity(0.18) : null,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        onTap: () => _playLecture(lec),
                        leading: CircleAvatar(
                          backgroundColor: isPlaying
                              ? const Color(0xFF6366F1)
                              : Colors.grey.withOpacity(0.2),
                          child: Icon(
                            isPlaying ? Icons.equalizer : Icons.play_arrow,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          "${idx + 1}. ${lec.title}",
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            isDone ? Icons.check_circle : Icons.check_circle_outline,
                            color: isDone ? Colors.greenAccent : Colors.grey,
                          ),
                          onPressed: () => _toggleCompleted(lec.videoId),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 6. 100% NATIVE CUSTOM VIDEO PLAYER (ZERO YOUTUBE BRANDING)
// ==========================================
class NativeStudyPlayer extends StatefulWidget {
  final String videoId;
  final String videoTitle;
  final int initialSeekSeconds;
  final ValueChanged<int> onProgress;

  const NativeStudyPlayer({
    super.key,
    required this.videoId,
    required this.videoTitle,
    required this.initialSeekSeconds,
    required this.onProgress,
  });

  @override
  State<NativeStudyPlayer> createState() => _NativeStudyPlayerState();
}

class _NativeStudyPlayerState extends State<NativeStudyPlayer> {
  VideoPlayerController? _controller;
  bool _loadingStream = true;
  String? _errorMsg;

  Map<String, String> _qualityUrls = {};
  String _selectedQuality = "Auto";

  double _playbackSpeed = 1.0;
  double _preHoldSpeed = 1.0;
  bool _isHolding2x = false;
  bool _showControls = true;
  bool _zoomToFill = false;
  String? _seekRippleText;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _extractAndPlay(widget.videoId, startAt: widget.initialSeekSeconds);
  }

  @override
  void didUpdateWidget(covariant NativeStudyPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId) {
      _extractAndPlay(widget.videoId, startAt: widget.initialSeekSeconds);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _extractAndPlay(String videoId, {int startAt = 0}) async {
    setState(() {
      _loadingStream = true;
      _errorMsg = null;
    });

    final ytExplode = yt.YoutubeExplode();
    try {
      final manifest = await ytExplode.videos.streamsClient.getManifest(videoId);
      final Map<String, String> qualities = {};

      for (final s in manifest.muxed.sortByVideoQuality()) {
        qualities[s.qualityLabel] = s.url.toString();
      }

      if (qualities.isEmpty) {
        throw Exception("No playable stream found for this video.");
      }

      final defaultQuality = qualities.keys.first;
      _qualityUrls = qualities;
      _selectedQuality = defaultQuality;

      await _initializeVideoUrl(qualities[defaultQuality]!, seekToSec: startAt);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingStream = false;
          _errorMsg = "Stream error: Check internet or video ID.";
        });
      }
    } finally {
      ytExplode.close();
    }
  }

  Future<void> _initializeVideoUrl(String url, {int seekToSec = 0}) async {
    final old = _controller;
    final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = ctrl;

    await ctrl.initialize();
    if (old != null) await old.dispose();

    if (seekToSec > 0) {
      await ctrl.seekTo(Duration(seconds: seekToSec));
    }
    await ctrl.setPlaybackSpeed(_playbackSpeed);
    await ctrl.play();

    ctrl.addListener(() {
      if (!mounted || !ctrl.value.isInitialized) return;
      widget.onProgress(ctrl.value.position.inSeconds);
      setState(() {});
    });

    if (mounted) {
      setState(() => _loadingStream = false);
      _resetHideTimer();
    }
  }

  Future<void> _changeQuality(String qualityLabel) async {
    final url = _qualityUrls[qualityLabel];
    if (url == null || _controller == null) return;
    final currentPos = _controller!.value.position.inSeconds;
    setState(() {
      _selectedQuality = qualityLabel;
      _loadingStream = true;
    });
    await _initializeVideoUrl(url, seekToSec: currentPos);
  }

  void _setSpeed(double speed) {
    setState(() => _playbackSpeed = speed);
    _controller?.setPlaybackSpeed(speed);
  }

  void seekToSeconds(int sec) {
    _controller?.seekTo(Duration(seconds: sec));
  }

  void _skipSeconds(int delta) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final int target = (ctrl.value.position.inSeconds + delta)
        .clamp(0, ctrl.value.duration.inSeconds)
        .toInt();
    ctrl.seekTo(Duration(seconds: target));
    setState(() => _seekRippleText = delta > 0 ? "+${delta}s ⏩" : "⏪ ${delta}s");
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _seekRippleText = null);
    });
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    setState(() => _showControls = true);
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() => _showControls = false);
      }
    });
  }

  void _openFullScreen() async {
    if (_controller == null) return;
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: _buildPlayerBody(isFullScreen: true),
        ),
      ),
    );

    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? "$h:$m:$s" : "$m:$s";
  }

  Widget _buildPlayerBody({required bool isFullScreen}) {
    final ctrl = _controller;
    final isReady = ctrl != null && ctrl.value.isInitialized && !_loadingStream;
    final double maxSec = isReady && ctrl.value.duration.inSeconds > 0
        ? ctrl.value.duration.inSeconds.toDouble()
        : 1.0;
    final double posSec = isReady
        ? ctrl.value.position.inSeconds.toDouble().clamp(0.0, maxSec).toDouble()
        : 0.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_showControls) {
          setState(() => _showControls = false);
        } else {
          _resetHideTimer();
        }
      },
      onDoubleTapDown: (details) {
        final width = MediaQuery.of(context).size.width;
        if (details.localPosition.dx < width * 0.4) {
          _skipSeconds(-10);
        } else if (details.localPosition.dx > width * 0.6) {
          _skipSeconds(10);
        }
      },
      onLongPressStart: (_) {
        if (!isReady) return;
        _preHoldSpeed = _playbackSpeed;
        ctrl.setPlaybackSpeed(2.0);
        setState(() => _isHolding2x = true);
      },
      onLongPressEnd: (_) {
        if (!isReady) return;
        ctrl.setPlaybackSpeed(_preHoldSpeed);
        setState(() => _isHolding2x = false);
      },
      child: Container(
        width: double.infinity,
        height: isFullScreen ? double.infinity : null,
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isReady)
              ClipRect(
                child: Transform.scale(
                  scale: _zoomToFill ? 1.24 : 1.0,
                  child: AspectRatio(
                    aspectRatio: ctrl.value.aspectRatio,
                    child: VideoPlayer(ctrl),
                  ),
                ),
              ),
            if (_loadingStream || (isReady && ctrl.value.isBuffering))
              Container(
                width: 52,
                height: 52,
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Color(0xFF6366F1),
                ),
              ),
            if (_errorMsg != null)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
                  const SizedBox(height: 8),
                  Text(_errorMsg!, style: const TextStyle(color: Colors.white, fontSize: 13)),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => _extractAndPlay(widget.videoId),
                    child: const Text("Retry"),
                  ),
                ],
              ),
            if (_isHolding2x)
              Positioned(
                top: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt, color: Colors.amber, size: 18),
                      SizedBox(width: 4),
                      Text(
                        "2X Speed",
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            if (_seekRippleText != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  _seekRippleText!,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            if (_showControls && isReady)
              Container(
                color: Colors.black45,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          if (isFullScreen)
                            IconButton(
                              icon: const Icon(Icons.arrow_back, color: Colors.white),
                              onPressed: () => Navigator.pop(context),
                            ),
                          Expanded(
                            child: Text(
                              widget.videoTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _circleControlBtn(
                          icon: Icons.replay_10_rounded,
                          size: 42,
                          onTap: () => _skipSeconds(-10),
                        ),
                        const SizedBox(width: 28),
                        _circleControlBtn(
                          icon: ctrl.value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 56,
                          bgColor: const Color(0xFF6366F1),
                          onTap: () {
                            if (ctrl.value.isPlaying) {
                              ctrl.pause();
                            } else {
                              ctrl.play();
                            }
                            _resetHideTimer();
                          },
                        ),
                        const SizedBox(width: 28),
                        _circleControlBtn(
                          icon: Icons.forward_10_rounded,
                          size: 42,
                          onTap: () => _skipSeconds(10),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(
                                "${_fmtDuration(ctrl.value.position)} / ${_fmtDuration(ctrl.value.duration)}",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3,
                                    thumbShape:
                                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                                    overlayShape:
                                        const RoundSliderOverlayShape(overlayRadius: 12),
                                  ),
                                  child: Slider(
                                    activeColor: const Color(0xFF6366F1),
                                    inactiveColor: Colors.white30,
                                    min: 0.0,
                                    max: maxSec,
                                    value: posSec,
                                    onChanged: (val) {
                                      ctrl.seekTo(Duration(seconds: val.toInt()));
                                      _resetHideTimer();
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: Icon(
                                  ctrl.value.volume > 0 ? Icons.volume_up : Icons.volume_off,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                onPressed: () {
                                  ctrl.setVolume(ctrl.value.volume > 0 ? 0.0 : 1.0);
                                  _resetHideTimer();
                                },
                              ),
                              Row(
                                children: [
                                  PopupMenuButton<double>(
                                    onSelected: _setSpeed,
                                    itemBuilder: (_) => [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
                                        .map((s) => PopupMenuItem<double>(
                                            value: s, child: Text("${s}x Speed")))
                                        .toList(),
                                    child: _pillBadge("${_playbackSpeed}x"),
                                  ),
                                  const SizedBox(width: 8),
                                  PopupMenuButton<String>(
                                    onSelected: _changeQuality,
                                    itemBuilder: (_) => _qualityUrls.keys
                                        .map((q) =>
                                            PopupMenuItem<String>(value: q, child: Text(q)))
                                        .toList(),
                                    child: _pillBadge(_selectedQuality),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () => setState(() => _zoomToFill = !_zoomToFill),
                                    child: _pillBadge(_zoomToFill ? "Zoomed" : "Fit"),
                                  ),
                                  const SizedBox(width: 10),
                                  InkWell(
                                    onTap: () {
                                      if (isFullScreen) {
                                        Navigator.pop(context);
                                      } else {
                                        _openFullScreen();
                                      }
                                    },
                                    child: Icon(
                                      isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _circleControlBtn({
    required IconData icon,
    required double size,
    required VoidCallback onTap,
    Color bgColor = Colors.black54,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.55),
      ),
    );
  }

  Widget _pillBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: _buildPlayerBody(isFullScreen: false),
    );
  }
}

// ==========================================
// 7. IN-APP ADMIN PANEL
// ==========================================
class AdminPanelScreen extends StatefulWidget {
  final Map<String, dynamic> batches;
  final VoidCallback onUpdated;

  const AdminPanelScreen({super.key, required this.batches, required this.onUpdated});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final _batchNameCtrl = TextEditingController();
  final _examCtrl = TextEditingController(text: "JEE");
  final _descCtrl = TextEditingController();
  final _thumbCtrl = TextEditingController();

  String? _selectedBatchId;
  final _subjectNameCtrl = TextEditingController();

  String? _selectedSubjectId;
  String _contentType = "playlist";
  final _contentTitleCtrl = TextEditingController();
  final _contentUrlCtrl = TextEditingController();

  Future<void> _createBatch() async {
    if (_batchNameCtrl.text.trim().isEmpty) return;
    final id = "batch_${DateTime.now().millisecondsSinceEpoch}";
    final data = {
      "id": id,
      "name": _batchNameCtrl.text.trim(),
      "targetExam": _examCtrl.text.trim(),
      "language": "Hinglish",
      "thumbnail": _thumbCtrl.text.trim(),
      "description": _descCtrl.text.trim(),
      "createdAt": DateTime.now().millisecondsSinceEpoch,
    };
    await AppService.saveBatch(id, data);
    _batchNameCtrl.clear();
    _descCtrl.clear();
    _thumbCtrl.clear();
    widget.onUpdated();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Batch Saved!")));
      Navigator.pop(context);
    }
  }

  Future<void> _addSubject() async {
    if (_selectedBatchId == null || _subjectNameCtrl.text.trim().isEmpty) return;
    final subId = "sub_${DateTime.now().millisecondsSinceEpoch}";
    await http.patch(
      Uri.parse("${FirebaseConfig.dbUrl}/batches/$_selectedBatchId/subjects/$subId.json"),
      body: jsonEncode({"id": subId, "name": _subjectNameCtrl.text.trim()}),
    );
    _subjectNameCtrl.clear();
    widget.onUpdated();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Subject Added!")));
    }
  }

  Future<void> _addContentToSubject() async {
    if (_selectedBatchId == null ||
        _selectedSubjectId == null ||
        _contentUrlCtrl.text.trim().isEmpty) return;
    final cId = "cnt_${DateTime.now().millisecondsSinceEpoch}";
    final rawUrl = _contentUrlCtrl.text.trim();
    String extractedId = rawUrl;
    if (_contentType == 'playlist' && rawUrl.contains('list=')) {
      extractedId = Uri.parse(rawUrl).queryParameters['list'] ?? rawUrl;
    }

    await http.patch(
      Uri.parse(
          "${FirebaseConfig.dbUrl}/batches/$_selectedBatchId/subjects/$_selectedSubjectId/contents/$cId.json"),
      body: jsonEncode({
        "id": cId,
        "type": _contentType,
        "title": _contentTitleCtrl.text.trim().isEmpty
            ? "Chapter Playlist"
            : _contentTitleCtrl.text.trim(),
        "ytId": extractedId,
      }),
    );
    _contentTitleCtrl.clear();
    _contentUrlCtrl.clear();
    widget.onUpdated();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Playlist / Video Added to Subject!")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final batchKeys = widget.batches.keys.toList();
    Map<String, dynamic> subjectsOfSelected = {};
    if (_selectedBatchId != null && widget.batches[_selectedBatchId] != null) {
      final b = Map<String, dynamic>.from(widget.batches[_selectedBatchId] as Map);
      if (b['subjects'] != null) {
        subjectsOfSelected = Map<String, dynamic>.from(b['subjects'] as Map);
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Admin Course Architect")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("1. Create New Batch",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _batchNameCtrl,
                    decoration:
                        const InputDecoration(labelText: "Batch Name (e.g., Target JEE 2027)"),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _examCtrl,
                    decoration: const InputDecoration(labelText: "Target Exam (JEE / NEET)"),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _thumbCtrl,
                    decoration:
                        const InputDecoration(labelText: "Thumbnail Image URL (Optional)"),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descCtrl,
                    decoration: const InputDecoration(labelText: "Batch Description"),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child:
                        ElevatedButton(onPressed: _createBatch, child: const Text("Save Batch")),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("2. Add Subject Inside Batch",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedBatchId,
                    hint: const Text("Select Batch"),
                    items: batchKeys.map((k) {
                      final b = Map<String, dynamic>.from(widget.batches[k] as Map);
                      return DropdownMenuItem<String>(
                          value: k, child: Text((b['name'] ?? k).toString()));
                    }).toList(),
                    onChanged: (v) => setState(() {
                      _selectedBatchId = v;
                      _selectedSubjectId = null;
                    }),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _subjectNameCtrl,
                    decoration:
                        const InputDecoration(labelText: "Subject Name (e.g., Physics, Math)"),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child:
                        ElevatedButton(onPressed: _addSubject, child: const Text("Add Subject")),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "3. Add Playlist or Video to Subject",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedSubjectId,
                    hint: const Text("Select Subject"),
                    items: subjectsOfSelected.entries.map((e) {
                      final s = Map<String, dynamic>.from(e.value as Map);
                      return DropdownMenuItem<String>(
                          value: e.key, child: Text((s['name'] ?? e.key).toString()));
                    }).toList(),
                    onChanged: (v) => setState(() => _selectedSubjectId = v),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _contentType,
                    items: const [
                      DropdownMenuItem<String>(value: "playlist", child: Text("YouTube Playlist")),
                      DropdownMenuItem<String>(value: "video", child: Text("Single Video")),
                    ],
                    onChanged: (v) => setState(() => _contentType = v ?? "playlist"),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _contentTitleCtrl,
                    decoration: const InputDecoration(labelText: "Chapter / Lecture Title"),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _contentUrlCtrl,
                    decoration:
                        const InputDecoration(labelText: "YouTube Playlist or Video URL / ID"),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _addContentToSubject,
                      child: const Text("Save Playlist / Video"),
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
}