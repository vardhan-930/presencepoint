import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Corrected import paths based on the file structure image [1]
import 'auth_wrapper.dart'; // Assuming auth_wrapper.dart is in the same directory or adjust path
import 'screens/landing_page.dart'; // Adjust path if needed
import 'screens/login_page.dart'; // Adjust path if needed
import 'screens/signup_page.dart'; // Adjust path if needed
import 'screens/dashboard/dashboard_page.dart'; // Adjust path if needed

// --- Theme Management ---

// Global ValueNotifier to hold the current theme mode
// Initializes with light mode, but will be updated from preferences
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

// Function to change the theme and persist the preference
Future<void> setTheme(bool isDark) async {
  final prefs = await SharedPreferences.getInstance();
  // Update the notifier, which will trigger the ValueListenableBuilder in MyApp
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  // Save the preference for future app launches
  await prefs.setBool('isDarkMode', isDark);
}

// --- Main Application Entry Point ---

void main() async {
  // Ensure Flutter bindings are initialized before any async operations
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase client
  await Supabase.initialize(
    url: 'https://ixlbdwgqogaqimeirqli.supabase.co', // Your Supabase project URL
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml4bGJkd2dxb2dhcWltZWlycWxpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI3NzI1OTgsImV4cCI6MjA3ODM0ODU5OH0.W8d2e0FwCNVs33EZYBCYeCUqmMaSeUOObnR0tmqVJQg', // Your Supabase anon key
  );

  // Load the theme preference from SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  // Get the saved preference, default to false (light mode) if not found
  final isDark = prefs.getBool('isDarkMode') ?? false;
  // Set the initial theme based on the loaded preference BEFORE running the app
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;

  // Run the Flutter application
  runApp(const MyApp());
}

// --- Root Application Widget ---

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Use ValueListenableBuilder to reactively rebuild MaterialApp when the theme changes
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          title: 'PresencePoint', // Your application title
          debugShowCheckedModeBanner: false, // Hide the debug banner

          // Theme configuration based on the notifier's value
          themeMode: currentMode, // Controls which theme (light/dark) is active
          theme: ThemeData.light(useMaterial3: true), // Your light theme definition
          darkTheme: ThemeData.dark(useMaterial3: true), // Your dark theme definition

          // The AuthWrapper determines whether to show the login/landing page or the dashboard
          home: const AuthWrapper(),

          // Named routes for navigation
          routes: {
            '/landing': (_) => const LandingPage(),
            '/login': (_) => const LoginPage(),
            '/signup': (_) => const SignupPage(),
            '/dashboard': (_) => const DashboardPage(),
            // Add other routes as needed
          },
        );
      },
    );
  }
}