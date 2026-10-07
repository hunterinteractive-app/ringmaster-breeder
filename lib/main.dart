import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:appwrite/appwrite.dart';

import 'screens/login_screen.dart';
import 'screens/ring_dashboard.dart';
import 'screens/animal_list_screen.dart';
import 'screens/add_animal_screen.dart';
import 'screens/animal_detail_screen.dart';
import 'screens/edit_animal_screen.dart';
import 'screens/weight_history_screen.dart';

import 'models/app_user.dart';

/// ======================================================
/// GLOBAL APPWRITE CLIENTS
/// ======================================================
late Client appwriteClient;
late Account appwriteAccount;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  /// -------------------------
  /// Supabase init (DATA)
  /// -------------------------
  await Supabase.initialize(
    url: 'https://aqfsrolvaewcpkdkttiz.supabase.co',
    anonKey: 'sb_publishable_zQjtjtIkiJuxXeXOFe468Q_fe68wSbI',
  );

  /// -------------------------
  /// Appwrite init (AUTH)
  /// -------------------------
  appwriteClient = Client()
    ..setEndpoint('https://sfo.cloud.appwrite.io/v1')
    ..setProject('690694870030987a84e5')
    ..setSelfSigned(status: false);

  appwriteAccount = Account(appwriteClient);

  runApp(const MyApp());
}

/// ======================================================
/// ROOT APP
/// ======================================================
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String? userId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RingMaster Breeder',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),

      /// --------------------------------------------------
      /// AUTH GATE
      /// --------------------------------------------------
      home: userId == null
          ? LoginScreen(
              onLoginSuccess: (id) {
                setState(() => userId = id);
              },
            )
          : RingDashboard(userId: userId!),

      /// --------------------------------------------------
      /// ROUTES
      /// --------------------------------------------------
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

        '/animal-detail': (context) {
          final animalId =
              ModalRoute.of(context)!.settings.arguments as String;

          return AnimalDetailScreen(animalId: animalId);
        },

        '/edit-animal': (context) {
          final animalId =
              ModalRoute.of(context)!.settings.arguments as String;

          return EditAnimalScreen(animalId: animalId);
        },

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
}