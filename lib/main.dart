import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'theme_notifier.dart';
import 'firebase_options.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';

class LocaleNotifier extends ChangeNotifier {
  Locale? _locale;
  Locale? get locale => _locale;
  void setLanguageCode(String code) {
    _locale = Locale(code);
    notifyListeners();
  }
}

final localeNotifier = LocaleNotifier();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kIsWeb) {
    // Reduce potential IndexedDB/persistence issues on web
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );
  }
  // Load saved language (defaults to English)
  final prefs = await SharedPreferences.getInstance();
  final code = prefs.getString('language_code') ?? 'en';
  localeNotifier.setLanguageCode(code);
  runApp(
    ChangeNotifierProvider(create: (_) => ThemeNotifier(), child: MyApp()),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
      builder: (context, notifier, child) => AnimatedBuilder(
        animation: localeNotifier,
        builder: (context, _) => MaterialApp(
          onGenerateTitle: (ctx) => AppLocalizations.of(ctx).t('app_title'),
          theme: ThemeData(
            primarySwatch: Colors.blue,
            fontFamily: 'Arial',
            brightness: Brightness.light,
          ),
          darkTheme: ThemeData(
            primarySwatch: Colors.blue,
            fontFamily: 'Arial',
            brightness: Brightness.dark,
          ),
          themeMode: notifier.darkTheme ? ThemeMode.dark : ThemeMode.light,
          home: AuthGate(),
          debugShowCheckedModeBanner: false,
          locale: localeNotifier.locale,
          supportedLocales: const [Locale('en'), Locale('fr')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            AppLocalizationsDelegate(),
          ],
        ),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) {
          final user = snapshot.data!;
          // Route admin to the secret admin panel
          if ((user.email ?? '').toLowerCase() == 'admin@gmail.com') {
            return AdminPanel();
          }
          return HomeScreen();
        }
        return SignInScreen();
      },
    );
  }
}

class TeamAvatar extends StatelessWidget {
  final String teamCode;
  final Color color;

  const TeamAvatar({super.key, required this.teamCode, required this.color});

  @override
  Widget build(BuildContext context) {
    final logoPath = 'logos/clubs/${teamCode.toLowerCase()}.png';
    return CircleAvatar(
      radius: 30,
      backgroundColor: Colors.transparent,
      child: Image.asset(
        logoPath,
        errorBuilder: (context, error, stackTrace) {
          return CircleAvatar(
            radius: 30,
            backgroundColor: color,
            child: Text(
              teamCode,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          );
        },
      ),
    );
  }
}

class AdminPanel extends StatefulWidget {
  const AdminPanel({super.key});

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  bool _loading = false;
  String? _error;
  List<String> _fixtures = [];
  final Map<String, bool> _selected = {};

  @override
  void initState() {
    super.initState();
    _loadFixtures();
  }

  Future<void> _loadFixtures() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fixturesSnap = await FirebaseFirestore.instance
          .collection('fixtures')
          .orderBy('orderIndex')
          .get()
          .timeout(const Duration(seconds: 8));
      final matchesSnap = await FirebaseFirestore.instance
          .collection('matches')
          .get();

      final fixtures = fixturesSnap.docs
          .map((d) {
            final data = d.data();
            return (data['line'] as String?) ?? '';
          })
          .where((line) => line.isNotEmpty)
          .toList();

      final Set<String> matchIds = matchesSnap.docs
          .map((doc) => doc.id)
          .toSet();

      final newSelected = <String, bool>{};
      for (final fixtureLine in fixtures) {
        final id = _fixtureLineToId(fixtureLine);
        if (id != null && matchIds.contains(id)) {
          newSelected[fixtureLine] = true;
        }
      }

      setState(() {
        _fixtures = fixtures;
        _selected.clear();
        _selected.addAll(newSelected);
        _loading = false;
      });
    } on TimeoutException {
      setState(() {
        _loading = false;
        _error =
            'Timed out fetching fixtures. On web, this can be due to network restrictions. Try again, or run the app on mobile/desktop to scrape first.';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load fixtures: $e';
      });
    }
  }

  String? _fixtureLineToId(String line) {
    if (line.startsWith('(')) return null;
    final parts = line.split('/');
    if (parts.length != 5) return null;
    final date = parts[0];
    final homeTeam = parts[3];
    final awayTeam = parts[4];
    return '${date}_${homeTeam.replaceAll(' ', '_')}_${awayTeam.replaceAll(' ', '_')}'
        .toLowerCase();
  }

  Future<void> _onFixtureToggled(String fixtureLine, bool isSelected) async {
    setState(() {
      _selected[fixtureLine] = isSelected;
    });

    final id = _fixtureLineToId(fixtureLine);
    if (id == null) return;

    final docRef = FirebaseFirestore.instance.collection('matches').doc(id);

    try {
      if (isSelected) {
        final parts = fixtureLine.split('/');
        final date = parts[0];
        var time = parts[1];
        if (time == 'TBA') {
          time = '12:00'; // Default time for TBA matches
        }
        final homeTeam = parts[3];
        final awayTeam = parts[4];

        await docRef.set({
          'homeTeam': homeTeam,
          'awayTeam': awayTeam,
          'homeTeamCode': _teamCode(homeTeam),
          'awayTeamCode': _teamCode(awayTeam),
          'league': 'Premier League',
          'timeUtc': Timestamp.fromDate(DateTime.parse('${date}T$time:00Z')),
          'time': time,
        }, SetOptions(merge: true));
      } else {
        await docRef.delete();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating match: $e')));
      }
    }
  }

  String _teamCode(String name) {
    const map = {
      'Arsenal': 'ars',
      'Arsenal B': 'ars',
      'AFC Bournemouth': 'bou',
      'Aston Villa': 'avl',
      'Bournemouth': 'bou',
      'Brentford': 'bre',
      'Brighton & Hove Albion': 'bha',
      'Brighton': 'bha',
      'Chelsea': 'che',
      'Crystal Palace': 'cry',
      'Everton': 'eve',
      'Fulham': 'ful',
      'Ipswich Town': 'ips',
      'Leicester City': 'lei',
      'Liverpool': 'liv',
      'Manchester City': 'mci',
      'Manchester United': 'mun',
      'Newcastle United': 'new',
      'Nottingham Forest': 'nfo',
      'Southampton': 'sou',
      'Tottenham Hotspur': 'tot',
      'West Ham United': 'whu',
      'Wolverhampton Wanderers': 'wol',
    };

    final result =
        map[name] ??
        name
            .toLowerCase()
            .replaceAll(RegExp(r'[^\w\s]'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim()
            .split(' ')
            .where((w) => w.isNotEmpty)
            .map((w) => w.substring(0, 1))
            .take(3)
            .join();

    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _fixtures.length,
                      itemBuilder: (context, index) {
                        final fixture = _fixtures[index];
                        return CheckboxListTile(
                          value: _selected[fixture] ?? false,
                          onChanged: (val) =>
                              _onFixtureToggled(fixture, val ?? false),
                          title: Text(fixture),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _rememberMe = false;
  bool _isLoading = false;
  String? _errorText;
  bool _isAutoLoggingIn = true;

  @override
  void initState() {
    super.initState();
    _loadRememberedAndAutoLogin();
  }

  Future<void> _loadRememberedAndAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('remember_email');
    final password = prefs.getString('remember_password');

    if (email != null && password != null) {
      setState(() {
        _emailController.text = email;
        _passwordController.text = password;
        _rememberMe = true;
        _isAutoLoggingIn = true;
      });

      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } catch (e) {
        await prefs.remove('remember_password');
        setState(() {
          _isAutoLoggingIn = false;
          _errorText = AppLocalizations.of(context).t('auto_login_failed');
        });
      }
    } else {
      setState(() {
        _isAutoLoggingIn = false;
      });
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString('remember_email', _emailController.text.trim());
        await prefs.setString('remember_password', _passwordController.text);
      } else {
        await prefs.remove('remember_email');
        await prefs.remove('remember_password');
      }
    } on FirebaseAuthException catch (e) {
      final email = _emailController.text.trim().toLowerCase();
      final password = _passwordController.text;
      if (e.code == 'user-not-found' &&
          email == 'admin@gmail.com' &&
          password == '111111') {
        try {
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
          // After creating, sign in implicitly via auth state change
          final prefs = await SharedPreferences.getInstance();
          if (_rememberMe) {
            await prefs.setString('remember_email', email);
            await prefs.setString('remember_password', password);
          } else {
            await prefs.remove('remember_email');
            await prefs.remove('remember_password');
          }
        } on FirebaseAuthException catch (e2) {
          // If the email already exists, try to sign in (will surface wrong-password if mismatched)
          if (e2.code == 'email-already-in-use') {
            try {
              await FirebaseAuth.instance.signInWithEmailAndPassword(
                email: email,
                password: password,
              );
            } on FirebaseAuthException catch (e3) {
              _setAuthErrorFromCode(e3.code, fallbackMessage: e3.message);
            }
          } else {
            _setAuthErrorFromCode(e2.code, fallbackMessage: e2.message);
          }
        }
      } else {
        _setAuthErrorFromCode(e.code, fallbackMessage: e.message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _setAuthErrorFromCode(String code, {String? fallbackMessage}) {
    String key;
    switch (code) {
      case 'invalid-email':
        key = 'auth_invalid_email';
        break;
      case 'missing-password':
        key = 'auth_missing_password';
        break;
      case 'user-not-found':
        key = 'auth_user_not_found';
        break;
      case 'wrong-password':
        key = 'auth_wrong_password';
        break;
      case 'invalid-credential':
        // Newer Firebase returns this for wrong password/invalid credential
        key = 'auth_wrong_password';
        break;
      case 'user-disabled':
        key = 'auth_user_disabled';
        break;
      case 'too-many-requests':
        key = 'auth_too_many_requests';
        break;
      case 'network-request-failed':
        key = 'auth_network_error';
        break;
      case 'email-already-in-use':
        key = 'auth_email_in_use';
        break;
      case 'operation-not-allowed':
        key = 'auth_operation_not_allowed';
        break;
      default:
        key = 'auth_unknown_error';
    }
    setState(() {
      final base = AppLocalizations.of(context).t(key);
      _errorText = fallbackMessage != null && key == 'auth_unknown_error'
          ? '$base\n$fallbackMessage'
          : base;
    });
  }

  Future<void> _register() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('remember_email', _emailController.text.trim());
      await prefs.setString(
        'remember_password',
        _passwordController.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorText = e.message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isAutoLoggingIn) {
      return Scaffold(
        backgroundColor: Colors.grey[100],
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(AppLocalizations.of(context).t('auto_signing_in')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          AppLocalizations.of(context).t('sign_in'),
          style: const TextStyle(color: Colors.black),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  TextField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context).t('email'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context).t('password'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Checkbox(
                        value: _rememberMe,
                        onChanged: (v) =>
                            setState(() => _rememberMe = v ?? false),
                      ),
                      Text(
                        AppLocalizations.of(context).t('remember_me'),
                        style: TextStyle(
                          color: Colors.green[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () async {
                          if (_emailController.text.trim().isEmpty) return;
                          await FirebaseAuth.instance.sendPasswordResetEmail(
                            email: _emailController.text.trim(),
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppLocalizations.of(
                                  context,
                                ).t('password_reset_email_sent'),
                              ),
                            ),
                          );
                        },
                        child: Text(
                          AppLocalizations.of(context).t('forgot_password'),
                        ),
                      ),
                    ],
                  ),
                  if (_errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _errorText!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _signIn,
                    child: _isLoading
                        ? const CircularProgressIndicator()
                        : Text(AppLocalizations.of(context).t('sign_in')),
                  ),
                  TextButton(
                    onPressed: _isLoading ? null : _register,
                    child: Text(
                      AppLocalizations.of(context).t('create_account'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            height: 60,
            alignment: Alignment.center,
            color: Colors.grey[300],
            child: const Text('Ad Space'),
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final Map<String, int> _predictedHome = {};
  final Map<String, int> _predictedAway = {};

  List<Map<String, dynamic>> matches = [];
  bool _loadingMatches = true;

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  Future<void> _loadMatches() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('matches')
          .orderBy('timeUtc')
          .limit(3)
          .get();
      final firestoreMatches = snapshot.docs
          .map((d) => {'id': d.id, ...d.data()})
          .toList();

      setState(() {
        matches = firestoreMatches.cast<Map<String, dynamic>>();
        _loadingMatches = false;
      });
    } catch (e) {
      setState(() {
        matches = [];
        _loadingMatches = false;
      });
    }
  }

  List<Map<String, dynamic>> _todaysMatches() {
    final now = DateTime.now().toUtc();
    return matches.where((m) {
      final Timestamp ts = m['timeUtc'];
      final dt = ts.toDate().toUtc();
      return dt.year == now.year && dt.month == now.month && dt.day == now.day;
    }).toList();
  }

  Map<String, dynamic>? _latestMatch() {
    if (matches.isEmpty) return null;
    final now = DateTime.now().toUtc();
    Map<String, dynamic>? latest;
    DateTime? latestDt;
    for (final m in matches) {
      final Timestamp ts = m['timeUtc'];
      final dt = ts.toDate().toUtc();
      if (dt.isAfter(now)) continue; // only past or now
      if (latest == null || (latestDt != null && dt.isAfter(latestDt))) {
        latest = m;
        latestDt = dt;
      }
    }
    return latest;
  }

  void _changePrediction(String matchId, String side, int delta) {
    setState(() {
      if (side == 'home') {
        _predictedHome[matchId] = (_predictedHome[matchId] ?? 0) + delta;
        if (_predictedHome[matchId]! < 0) _predictedHome[matchId] = 0;
      } else {
        _predictedAway[matchId] = (_predictedAway[matchId] ?? 0) + delta;
        if (_predictedAway[matchId]! < 0) _predictedAway[matchId] = 0;
      }
    });
  }

  Future<void> _submitPredictions() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final predictedMatchIds = {..._predictedHome.keys, ..._predictedAway.keys};
    if (predictedMatchIds.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).t('please_make_prediction'),
          ),
        ),
      );
      return;
    }

    final batch = FirebaseFirestore.instance.batch();
    bool hasWrites = false;

    for (final match in _todaysMatches()) {
      final id = match['id'] as String;

      if (predictedMatchIds.contains(id)) {
        final home = _predictedHome[id] ?? 0;
        final away = _predictedAway[id] ?? 0;

        final ref = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('predictions')
            .doc(id);

        batch.set(ref, {
          'matchId': id,
          'homeScore': home,
          'awayScore': away,
          'createdAt': FieldValue.serverTimestamp(),
          'lockAt': match['timeUtc'],
          'homeTeam': match['homeTeam'],
          'awayTeam': match['awayTeam'],
          'homeTeamCode': match['homeTeamCode'],
          'awayTeamCode': match['awayTeamCode'],
        }, SetOptions(merge: true));
        hasWrites = true;
      }
    }

    if (!hasWrites) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).t('please_make_prediction'),
          ),
        ),
      );
      return;
    }

    try {
      await batch.commit();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error committing batch: $e')));
      return;
    }

    setState(() {
      _predictedHome.clear();
      _predictedAway.clear();
    });

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => PredictionsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.menu, color: Colors.blue, size: 30),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Image.asset(
          'assets/var6_logo.png',
          height: 80, // Doubled the size from 40 to 80
          errorBuilder: (context, error, stackTrace) => Text(
            AppLocalizations.of(context).t('image_not_found'),
            style: TextStyle(color: Colors.red, fontSize: 16),
          ),
        ),
        centerTitle: true,
      ),
      drawer: _buildDrawer(),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${AppLocalizations.of(context).t('hello')} Andrei,',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            Text(
              AppLocalizations.of(
                context,
              ).t('place_your_predictions_for_todays_match_ups'),
              style: TextStyle(fontSize: 16, color: Colors.blue),
            ),
            SizedBox(height: 30),
            Text(
              AppLocalizations.of(context).t('latest_match'),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            SizedBox(height: 20),
            _loadingMatches
                ? Center(child: CircularProgressIndicator())
                : (_latestMatch() != null)
                ? _buildStyledMatchCard(_latestMatch()!)
                : Center(
                    child: Text(
                      AppLocalizations.of(
                        context,
                      ).t('no_more_match_to_predict'),
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    ),
                  ),
            SizedBox(height: 40),
            Text(
              AppLocalizations.of(context).t('todays_matches'),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            SizedBox(height: 20),
            _loadingMatches
                ? SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _todaysMatches().isNotEmpty
                ? Column(
                    children: _todaysMatches()
                        .map((match) => _buildEditableMatchCard(match))
                        .toList(),
                  )
                : SizedBox(
                    height: 100,
                    child: Center(
                      child: Text(
                        AppLocalizations.of(
                          context,
                        ).t('no_more_match_to_predict'),
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ),
                  ),
            SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _submitPredictions,
                child: Text(
                  AppLocalizations.of(context).t('submit'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              height: 60,
              alignment: Alignment.center,
              color: Colors.grey[300],
              child: const Text('Ad Space'),
            ),
          ],
        ),
      ),
    );
  }

  // Updated: show formatted date and time
  Widget _buildStyledMatchCard(Map<String, dynamic> match) {
    final String homeCode = match['homeTeamCode'] ?? 'H';
    final String awayCode = match['awayTeamCode'] ?? 'A';

    String dateTimeText = _formatMatchDateTime(match);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.green[200]!, width: 2),
      ),
      margin: EdgeInsets.symmetric(vertical: 8),
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              children: [
                TeamAvatar(teamCode: homeCode, color: Colors.blue),
                SizedBox(height: 8),
                Text(
                  match['homeTeam'] ?? 'Home',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                SizedBox(height: 8),
                Text(
                  (match['homeScore'] ?? '-').toString(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
            Column(
              children: [
                Text(
                  'vs',
                  style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                ),
                SizedBox(height: 8),
                Text(
                  match['league'] ?? '',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                SizedBox(height: 8),
                Text(
                  dateTimeText,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            Column(
              children: [
                TeamAvatar(teamCode: awayCode, color: Colors.red),
                SizedBox(height: 8),
                Text(
                  match['awayTeam'] ?? 'Away',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                SizedBox(height: 8),
                Text(
                  (match['awayScore'] ?? '-').toString(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Updated: show formatted date and time
  Widget _buildEditableMatchCard(Map<String, dynamic> match) {
    final String id = match['id'];
    final String homeCode = match['homeTeamCode'] ?? 'H';
    final String awayCode = match['awayTeamCode'] ?? 'A';
    final int home = _predictedHome[id] ?? 0;
    final int away = _predictedAway[id] ?? 0;

    String dateTimeText = _formatMatchDateTime(match);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.green[200]!, width: 2),
      ),
      margin: EdgeInsets.symmetric(vertical: 8),
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              children: [
                TeamAvatar(teamCode: homeCode, color: Colors.blue),
                SizedBox(height: 8),
                Text(
                  match['homeTeam'] ?? 'Home',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => _changePrediction(id, 'home', -1),
                      icon: Icon(Icons.remove_circle_outline),
                    ),
                    Text(
                      '$home',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _changePrediction(id, 'home', 1),
                      icon: Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ],
            ),
            Column(
              children: [
                Text(
                  'vs',
                  style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                ),
                SizedBox(height: 8),
                Text(
                  match['league'] ?? '',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                SizedBox(height: 8),
                Text(
                  dateTimeText,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            Column(
              children: [
                TeamAvatar(teamCode: awayCode, color: Colors.red),
                SizedBox(height: 8),
                Text(
                  match['awayTeam'] ?? 'Away',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => _changePrediction(id, 'away', -1),
                      icon: Icon(Icons.remove_circle_outline),
                    ),
                    Text(
                      '$away',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _changePrediction(id, 'away', 1),
                      icon: Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatMatchDateTime(Map<String, dynamic> match) {
    try {
      final dynamic timeObj = match['timeUtc'];
      if (timeObj is Timestamp) {
        final dt = timeObj.toDate().toLocal();
        // Example formatting: Tue, Aug 12 • 15:00
        return DateFormat('EEE, MMM d • HH:mm').format(dt);
      } else if (timeObj is DateTime) {
        final dt = timeObj.toLocal();
        return DateFormat('EEE, MMM d • HH:mm').format(dt);
      } else {
        // fallback to provided 'time' field or empty
        if (match['time'] != null) return match['time'].toString();
      }
    } catch (_) {
      // ignore formatting errors and fallback
      if (match['time'] != null) return match['time'].toString();
    }
    return '';
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Container(
        color: Colors.grey[50],
        child: Column(
          children: [
            Container(
              height: 100,
              padding: EdgeInsets.only(left: 16, top: 50),
              alignment: Alignment.centerLeft,
              child: Text(
                AppLocalizations.of(context).t('menu'),
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildDrawerItem(
                    Icons.home,
                    AppLocalizations.of(context).t('home'),
                    () => Navigator.pop(context),
                  ),
                  _buildDrawerItem(
                    Icons.flash_on,
                    AppLocalizations.of(context).t('check_predictions'),
                    () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PredictionsScreen(),
                        ),
                      );
                    },
                  ),
                  _buildDrawerItem(
                    Icons.settings,
                    AppLocalizations.of(context).t('settings'),
                    () {
                      Navigator.of(context).pop(); // Close the drawer
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                  _buildDrawerItem(
                    Icons.rule,
                    AppLocalizations.of(context).t('game_rules'),
                    () {
                      Navigator.of(context).pop(); // Close the drawer
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => GameRulesScreen(),
                        ),
                      );
                    },
                  ),
                  SizedBox(height: 40),
                  _buildDrawerItem(
                    Icons.logout,
                    AppLocalizations.of(context).t('log_out'),
                    () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove('remember_email');
                      await prefs.remove('remember_password');

                      await FirebaseAuth.instance.signOut();
                      if (!mounted) return;
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => AuthGate()),
                        (route) => false,
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, VoidCallback onTap) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.green[100]!)),
      ),
      child: ListTile(
        leading: Icon(icon, color: Colors.blue, size: 28),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 20,
            color: Colors.green[700],
            fontWeight: FontWeight.bold,
          ),
        ),
        onTap: onTap,
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
    );
  }
}

class GameRulesScreen extends StatelessWidget {
  const GameRulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: Colors.blue),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          AppLocalizations.of(context).t('official_game_rules'),
          style: TextStyle(
            color: Colors.black,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRuleText(
                      AppLocalizations.of(context).t('rules_intro_1'),
                    ),
                    SizedBox(height: 16),
                    _buildRuleText(
                      AppLocalizations.of(context).t('rules_intro_2'),
                    ),
                    SizedBox(height: 16),
                    _buildRuleText(
                      AppLocalizations.of(context).t('rules_intro_3'),
                    ),
                    SizedBox(height: 16),
                    _buildRuleText(
                      AppLocalizations.of(context).t('rules_intro_4'),
                    ),
                    SizedBox(height: 16),
                    _buildRuleText(
                      AppLocalizations.of(context).t('rules_prizes_intro'),
                    ),
                    SizedBox(height: 8),
                    Padding(
                      padding: EdgeInsets.only(left: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context).t('prize1'),
                            style: TextStyle(fontSize: 16),
                          ),
                          Text(
                            AppLocalizations.of(context).t('prize2'),
                            style: TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 20),
                    _buildRuleText(
                      AppLocalizations.of(context).t('rules_contact'),
                    ),
                    SizedBox(height: 30),
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        AppLocalizations.of(context).t('rules_disclaimer'),
                        style: TextStyle(
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey[700],
                        ),
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

  Widget _buildRuleText(String text) {
    return Text(text, style: TextStyle(fontSize: 16, height: 1.5));
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _changePassword(BuildContext context) async {
    final current = TextEditingController();
    final next = TextEditingController();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Change password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: current,
              obscureText: true,
              decoration: InputDecoration(labelText: 'Current password'),
            ),
            TextField(
              controller: next,
              obscureText: true,
              decoration: InputDecoration(labelText: 'New password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Update'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: current.text,
      );
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(next.text);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Password updated')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _changeLanguage(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    String selected = prefs.getString('language_code') ?? 'en';
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateSB) => Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocalizations.of(context).t('choose_language'),
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              RadioListTile<String>(
                value: 'en',
                groupValue: selected,
                onChanged: (v) => setStateSB(() => selected = v ?? 'en'),
                title: Text(AppLocalizations.of(context).t('english')),
              ),
              RadioListTile<String>(
                value: 'fr',
                groupValue: selected,
                onChanged: (v) => setStateSB(() => selected = v ?? 'fr'),
                title: Text(AppLocalizations.of(context).t('french')),
              ),
              SizedBox(height: 8),
              ElevatedButton(
                onPressed: () async {
                  await prefs.setString('language_code', selected);
                  localeNotifier.setLanguageCode(selected);
                  if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                },
                child: Text(AppLocalizations.of(context).t('save')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateEmail(BuildContext context) async {
    final currentPassword = TextEditingController();
    final newEmail = TextEditingController();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Update Email'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: newEmail,
              decoration: InputDecoration(labelText: 'New email'),
            ),
            TextField(
              controller: currentPassword,
              obscureText: true,
              decoration: InputDecoration(labelText: 'Current password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Update'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword.text,
      );
      await user.reauthenticateWithCredential(cred);
      await user.updateEmail(newEmail.text.trim());
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Email updated')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final currentPassword = TextEditingController();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('This action is irreversible.'),
            TextField(
              controller: currentPassword,
              obscureText: true,
              decoration: InputDecoration(labelText: 'Confirm password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword.text,
      );
      await user.reauthenticateWithCredential(cred);
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final preds = await userRef.collection('predictions').get();
      for (final d in preds.docs) {
        await d.reference.delete();
      }
      await user.delete();
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => AuthGate()),
        (route) => false,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Image.asset(
          'assets/var6_logo.png',
          height: 80,
          errorBuilder: (context, error, stackTrace) => Text(
            AppLocalizations.of(context).t('image_not_found'),
            style: TextStyle(color: Colors.red, fontSize: 16),
          ),
        ),
      ),
      body: Column(
        children: [
          _buildSettingsItem(
            Icons.vpn_key,
            AppLocalizations.of(context).t('change_password'),
            onTap: () => _changePassword(context),
          ),
          _buildSettingsItem(
            Icons.language,
            AppLocalizations.of(context).t('change_language'),
            onTap: () => _changeLanguage(context),
          ),
          _buildSettingsItem(
            Icons.email,
            AppLocalizations.of(context).t('update_email'),
            hasDropdown: true,
            onTap: () => _updateEmail(context),
          ),
          _buildSettingsItem(
            Icons.delete,
            AppLocalizations.of(context).t('delete_account'),
            onTap: () => _deleteAccount(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsItem(
    IconData icon,
    String title, {
    bool hasDropdown = false,
    VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.green[100]!)),
        color: Colors.transparent,
      ),
      child: ListTile(
        leading: Icon(icon, color: Colors.blue, size: 28),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 20,
            color: Colors.green[700],
            fontWeight: FontWeight.bold,
          ),
        ),
        trailing: hasDropdown
            ? Icon(Icons.keyboard_arrow_down, color: Colors.green[700])
            : null,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: onTap,
      ),
    );
  }
}

class PredictionsScreen extends StatelessWidget {
  const PredictionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Image.asset(
          'assets/var6_logo.png',
          height: 80,
          errorBuilder: (context, error, stackTrace) => Text(
            AppLocalizations.of(context).t('image_not_found'),
            style: TextStyle(color: Colors.red, fontSize: 16),
          ),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${AppLocalizations.of(context).t('hello')} Andrei,',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            Text(
              AppLocalizations.of(context).t('check_submitted_predictions'),
              style: TextStyle(fontSize: 16, color: Colors.blue),
            ),
            SizedBox(height: 30),
            Text(
              AppLocalizations.of(context).t('your_predictions'),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            SizedBox(height: 20),
            Expanded(
              child: user == null
                  ? Center(
                      child: Text(
                        AppLocalizations.of(context).t('not_signed_in'),
                      ),
                    )
                  : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .collection('predictions')
                          .orderBy('createdAt', descending: true)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Center(child: CircularProgressIndicator());
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return Center(
                            child: Text(
                              AppLocalizations.of(context).t('no_predictions'),
                            ),
                          );
                        }

                        final predictionDocs = snapshot.data!.docs;

                        return ListView.builder(
                          itemCount: predictionDocs.length,
                          itemBuilder: (context, index) {
                            final p = predictionDocs[index].data();

                            return Container(
                              margin: EdgeInsets.only(bottom: 16),
                              padding: EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.green,
                                  width: 2,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildTeamColumn(
                                    p['homeTeamCode'] ?? 'H',
                                    p['homeTeam'] ?? 'Home',
                                    '${p['homeScore']}',
                                    Colors.blue,
                                  ),
                                  Text(
                                    AppLocalizations.of(context).t('vs'),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  _buildTeamColumn(
                                    p['awayTeamCode'] ?? 'A',
                                    p['awayTeam'] ?? 'Away',
                                    '${p['awayScore']}',
                                    Colors.red,
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamColumn(String code, String name, String score, Color color) {
    return Column(
      children: [
        TeamAvatar(teamCode: code, color: color),
        SizedBox(height: 8),
        Text(name, style: TextStyle(fontWeight: FontWeight.bold)),
        SizedBox(height: 4),
        Text(
          score,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
      ],
    );
  }
}
