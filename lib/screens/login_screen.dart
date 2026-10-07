// lib/screens/login_screen.dart

import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/user_service.dart';
import '../models/app_user.dart';
import '../main.dart';

class LoginScreen extends StatefulWidget {
  final void Function(AppUser) onLoginSuccess;

  const LoginScreen({
    super.key,
    required this.onLoginSuccess,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  // Main login
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();

  // Forgot username
  final forgotEmailController = TextEditingController();
  final forgotArbaController = TextEditingController();

  // Forgot password
  final forgotPasswordUsernameController = TextEditingController();
  final forgotPasswordArbaController = TextEditingController();

  String? errorMessage;
  bool loading = false;

  // --------------------------------------------------
  // LOGIN HANDLER
  // --------------------------------------------------
  Future<void> login() async {
    if (!_formKey.currentState!.validate()) return;

    final username = usernameController.text.trim();
    final password = passwordController.text.trim();

    setState(() {
      loading = true;
      errorMessage = null;
    });

    try {
      // 1) LOOK UP USER BY USERNAME (DB)
      final user = await UserService.getUserByUsername(username);

      if (user == null) {
        setState(() {
          loading = false;
          errorMessage = "Invalid username or password.";
        });
        return;
      }

      print("🔍 LOGIN USING EMAIL: ${user.email}");

      final account = Account(UserService.client);

      // 2) FORCE DELETE ALL EXISTING SESSIONS (iOS FIX)
      try {
        final sessions = await account.listSessions();
        for (final s in sessions.sessions) {
          await account.deleteSession(sessionId: s.$id);
        }
      } catch (_) {}

      // 3) CREATE FRESH SESSION
      final session = await appwriteAccount.get();
        final appwriteUserId = session.$id;

        await Supabase.instance.client.auth.signInWithIdToken(
          provider: OAuthProvider.custom,
          idToken: appwriteUserId,
        );

      final appwriteUser = await AppwriteService.getCurrentUser();

      final supaUser = await UserService.ensureUser(
        appwriteId: appwriteUser.$id,
        email: appwriteUser.email,
      );

      widget.onLoginSuccess(AppUser.fromMap(supaUser));

      // 4) SAVE USER LOCALLY
      UserService.currentLoggedInUser = user;

      setState(() => loading = false);
      widget.onLoginSuccess(user);

    } catch (e) {
      print("❌ LOGIN ERROR RAW: $e");

      setState(() {
        loading = false;
        errorMessage = e.toString();
      });
    }
  }

  // --------------------------------------------------
  // FORGOT USERNAME (email + ARBA required)
  // --------------------------------------------------
  Future<void> showForgotUsernameDialog() async {
    forgotEmailController.clear();
    forgotArbaController.clear();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Forgot Username"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: forgotEmailController,
              decoration: const InputDecoration(labelText: "Email"),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: forgotArbaController,
              decoration: const InputDecoration(labelText: "ARBA Number"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = forgotEmailController.text.trim();
              final arba = forgotArbaController.text.trim();

              Navigator.pop(context);

              if (email.isEmpty || arba.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Email and ARBA number are required."),
                  ),
                );
                return;
              }

              final username = await UserService.usernameFromEmailAndArba(
                email: email,
                arbaNumber: arba,
              );

              if (username == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "No account found with that email and ARBA number.",
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Your username is: $username"),
                  ),
                );
              }
            },
            child: const Text("Lookup Username"),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------
  // FORGOT PASSWORD (username + ARBA required)
  // --------------------------------------------------
  Future<void> showForgotPasswordDialog() async {
    forgotPasswordUsernameController.clear();
    forgotPasswordArbaController.clear();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Forgot Password"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: forgotPasswordUsernameController,
              decoration: const InputDecoration(labelText: "Username"),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: forgotPasswordArbaController,
              decoration: const InputDecoration(labelText: "ARBA Number"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final username =
                  forgotPasswordUsernameController.text.trim();
              final arba =
                  forgotPasswordArbaController.text.trim();

              Navigator.pop(context);

              if (username.isEmpty || arba.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Username and ARBA number are required.",
                    ),
                  ),
                );
                return;
              }

              try {
                // ✅ 1) LOOK UP USER BY USERNAME
                final user =
                    await UserService.getUserByUsername(username);

                if (user == null ||
                    user.arbaNumber != arba) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Unable to find account with that username and ARBA number.",
                      ),
                    ),
                  );
                  return;
                }

              
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      "Unable to send reset email: $e",
                    ),
                  ),
                );
              }
            },
            child: const Text("Send Reset Link"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Login")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: usernameController,
                decoration: const InputDecoration(
                  labelText: "Username",
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (v) =>
                    v != null && v.isNotEmpty ? null : "Enter username",
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "Password",
                  prefixIcon: Icon(Icons.lock),
                ),
                validator: (v) =>
                    v != null && v.isNotEmpty ? null : "Enter password",
              ),
              const SizedBox(height: 20),

              loading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: login,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text("Login"),
                    ),

              const SizedBox(height: 16),

              TextButton(
                onPressed: () {
                  Navigator.pushNamed(context, "/register");
                },
                child: const Text(
                  "Create an Account",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),

              const SizedBox(height: 8),

              TextButton(
                onPressed: showForgotPasswordDialog,
                child: const Text("Forgot Password?"),
              ),
              TextButton(
                onPressed: showForgotUsernameDialog,
                child: const Text("Forgot Username?"),
              ),

              if (errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
