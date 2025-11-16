import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tansr/login_page.dart';
import 'package:tansr/signup_page.dart';
import 'package:tansr/main_navigation_page.dart';
import 'package:tansr/analysis_page.dart';
import 'package:tansr/transaction_history_page.dart';

/// Global keys to allow safe navigation and snackbars from background callbacks.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: ".env");

  // small delay to avoid plugin startup races on some devices
  await Future.delayed(const Duration(milliseconds: 300));

  // request notification permission (best-effort)
  try {
    await Permission.notification.request();
  } catch (_) {}

  // initialize Supabase
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANNON_KEY']!,
    debug: false,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final seed = Colors.teal;

    return MaterialApp(
      title: 'Tansr',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: seed)),
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      initialRoute: '/',
      routes: {
        '/': (_) => const Root(),
        '/login': (_) => const LoginPage(),
        '/signup': (_) => const SignupPage(),
        '/home': (_) => const MainNavigationPage(),
        '/analysis': (_) => const AnalysisPage(),
        '/history': (_) => const TransactionHistoryPage(),
      },
    );
  }
}

/// Root: tiny splash that redirects based on auth session. Uses safe navigation (navigatorKey)
class Root extends StatefulWidget {
  const Root({super.key});

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  final SupabaseClient _supabase = Supabase.instance.client;
  StreamSubscription<AuthState>? _authSub;
  bool _redirected = false;

  @override
  void initState() {
    super.initState();

    // Initial redirect once UI has mounted
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialRedirect());

    // Subscribe to auth state changes and navigate safely using navigatorKey
    _authSub = _supabase.auth.onAuthStateChange.listen((event) {
      final nav = navigatorKey.currentState;
      if (nav == null) return;

      final e = event.event;
      if (e == AuthChangeEvent.signedIn || e == AuthChangeEvent.userUpdated) {
        nav.pushNamedAndRemoveUntil('/home', (route) => false);
        scaffoldMessengerKey.currentState?.showSnackBar(const SnackBar(content: Text('Signed in')));
      } else if (e == AuthChangeEvent.signedOut) {
        nav.pushNamedAndRemoveUntil('/login', (route) => false);
        scaffoldMessengerKey.currentState?.showSnackBar(const SnackBar(content: Text('Signed out')));
      }
    });
  }

  Future<void> _initialRedirect() async {
    if (_redirected) return;
    _redirected = true;

    // small delay for smoother startup
    await Future.delayed(const Duration(milliseconds: 50));

    final user = _supabase.auth.currentUser;
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    if (user != null) {
      nav.pushNamedAndRemoveUntil('/home', (route) => false);
    } else {
      nav.pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // simple splash UI while redirect runs
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
