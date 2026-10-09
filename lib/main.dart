import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/app_config.dart';
import 'services/auth_service.dart';
import 'services/family_service.dart';
import 'theme/app_theme.dart';
import 'widgets/app_shell.dart';
import 'screens/login_screen.dart';
import 'screens/ring_dashboard.dart';
import 'screens/animal_list_screen.dart';
import 'screens/add_animal_screen.dart';
import 'screens/animal_detail_screen.dart';
import 'screens/edit_animal_screen.dart';
import 'screens/weight_history_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseKey,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'RingMaster Breeder',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    builder: (context, child) => StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) =>
          Supabase.instance.client.auth.currentSession == null
          ? child ?? const SizedBox.shrink()
          : AppShell(child: child ?? const SizedBox.shrink()),
    ),
    home: const AuthRoot(),
    routes: {
      '/animals': (context) {
        final args =
            ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
        return AnimalListScreen(
          ringId: args['ringId'],
          ringName: args['ringName'],
        );
      },
      '/add-animal': (context) {
        final args =
            ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
        return AddAnimalScreen(
          ringId: args['ringId'],
          ringName: args['ringName'],
        );
      },
      '/animal-detail': (context) => AnimalDetailScreen(
        animalId: ModalRoute.of(context)!.settings.arguments as String,
      ),
      '/edit-animal': (context) => EditAnimalScreen(
        animalId: ModalRoute.of(context)!.settings.arguments as String,
      ),
      '/weight-history': (context) {
        final args =
            ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
        return WeightHistoryScreen(
          animalId: args['animalId'],
          status: args['status'],
        );
      },
    },
  );
}

class AuthRoot extends StatefulWidget {
  const AuthRoot({super.key});
  @override
  State<AuthRoot> createState() => _AuthRootState();
}

class _AuthRootState extends State<AuthRoot> {
  StreamSubscription<AuthState>? _subscription;
  final _client = Supabase.instance.client;
  @override
  void initState() {
    super.initState();
    _subscription = _client.auth.onAuthStateChange.listen((state) {
      if (!mounted) return;
      if (state.session == null) {
        FamilyService.clear();
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _client.auth.currentSession == null
      ? LoginScreen(auth: AuthService(_client))
      : RingDashboard(
          key: ValueKey(_client.auth.currentUser!.id),
          userId: _client.auth.currentUser!.id,
        );
}
