import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import for TextInput Autofill
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
// import 'dart:ui'; // Not strictly needed unless using ImageFilter directly

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  // Optional: Static route helper
  // static Route<void> route() {
  //   return MaterialPageRoute(builder: (context) => const LoginPage());
  // }

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final FocusNode _emailFocusNode = FocusNode();

  final SupabaseClient supabase = Supabase.instance.client;

  // State for avatar display
  String? _avatarUrl;
  // String? _previousAvatarUrl; // Can be removed if not needed for complex transitions
  bool _isLoadingAvatar = false; // For avatar loading indicator

  // State for login process
  bool _obscurePassword = true;
  bool _isLoggingIn = false; // Tracks login button state

  @override
  void initState() {
    super.initState();
    _emailFocusNode.addListener(_onEmailFocusChange);
    _emailController.addListener(_clearAvatarOnTextChange);
  }

  @override
  void dispose() {
    _emailController.removeListener(_clearAvatarOnTextChange);
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.removeListener(_onEmailFocusChange);
    _emailFocusNode.dispose();
    super.dispose();
  }

  // Clears avatar state when email text is manually modified.
  void _clearAvatarOnTextChange() {
    // If text is being actively changed, clear the displayed avatar.
    if (_avatarUrl != null || _isLoadingAvatar) {
      setState(() {
        // _previousAvatarUrl = _avatarUrl ?? _previousAvatarUrl; // Keep track if needed
        _avatarUrl = null;
        _isLoadingAvatar = false;
      });
    }
  }

  // Triggered when the email field gains or loses focus. Fetches avatar on loss if conditions met.
  void _onEmailFocusChange() {
    if (!_emailFocusNode.hasFocus) { // When focus is lost
      final email = _emailController.text.trim();
      // Only fetch if email seems valid, avatar isn't already loaded, and not currently loading
      if (email.isNotEmpty && email.contains('@') && _avatarUrl == null && !_isLoadingAvatar) {
        _fetchAvatar(email);
      } else if (email.isEmpty || !email.contains('@')) {
        // Clear avatar if email becomes invalid/empty on focus loss
        setState(() {
          // _previousAvatarUrl = _avatarUrl ?? _previousAvatarUrl;
          _avatarUrl = null;
          _isLoadingAvatar = false;
        });
      }
    }
  }

  // Fetches the avatar URL from the 'profiles' table based on email.
  Future<void> _fetchAvatar(String email) async {
    if (_isLoadingAvatar || !mounted) return; // Prevent multiple fetches
    print("Starting avatar fetch for email: $email");

    setState(() => _isLoadingAvatar = true);

    try {
      // *** CORRECTED: Query the 'profiles' table ***
      final response = await supabase
          .from('profiles') // Corrected table name
          .select('avatar_url')
          .eq('email', email)
          .maybeSingle(); // Use maybeSingle as email *should* be unique

      if (!mounted) return; // Check if widget is still mounted after async call

      final fetchedUrl = response?['avatar_url'] as String?;

      // Only update state if the URL actually changed to avoid unnecessary rebuilds
      if (fetchedUrl != _avatarUrl) {
        print("Successfully fetched avatar_url: $fetchedUrl");
        setState(() {
          // _previousAvatarUrl = _avatarUrl; // Keep if needed for transitions
          _avatarUrl = fetchedUrl;
        });
      } else {
        print("Fetched URL is the same as current or null, no state change.");
      }
    } catch (e) {
      // Catch potential PostgrestErrors or other exceptions
      print("Error fetching avatar: $e");
      if (mounted) {
        _showSnackBar('Could not fetch avatar info.', isError: true);
        // Optionally clear avatar on error
        setState(() {
          // _previousAvatarUrl = _avatarUrl;
          _avatarUrl = null;
        });
      }
    } finally {
      if (mounted) {
        print("Finished avatar fetch attempt.");
        setState(() => _isLoadingAvatar = false); // Ensure loading state is reset
      }
    }
  }

  // --- LOGIN FUNCTION ---
  Future<void> _login() async {
    if (_isLoggingIn) return; // Prevent multiple login attempts

    // Hide keyboard
    FocusScope.of(context).unfocus();

    final email = _emailController.text.trim();
    final password = _passwordController.text; // Don't trim password

    // Basic validation
    if (email.isEmpty || password.isEmpty) {
      _showSnackBar('Please enter both email and password', isError: true);
      return;
    }

    setState(() => _isLoggingIn = true); // Show loading indicator on button

    try {
      // --- Step 1: Attempt Supabase Auth Login ---
      final AuthResponse authResponse = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (!mounted) return; // Check after await

      // --- Step 2: Fetch Profile Data on Successful Login ---
      // Use the user ID from the successful auth response
      final userId = authResponse.user?.id;
      if (userId == null) {
        // Should not happen if signInWithPassword succeeded without error, but check anyway
        throw const AuthException('Login successful but user ID not found.');
      }

      print("Login successful, fetching profile for user ID: $userId");
      Map<String, dynamic>? profileData; // Variable to hold profile

      try {
        final profileResponse = await supabase
            .from('profiles') // Target the correct table
            .select() // Select all columns for the profile
            .eq('id', userId)
            .single(); // Expect exactly one profile matching the user ID

        profileData = profileResponse; // Direct assignment since .single() returns the map or throws
        print("Profile data fetched: $profileData");

      } on PostgrestException catch (profileError) {
        // Handle error fetching profile specifically
        print("Error fetching profile after login: ${profileError.message}");
        if (mounted) {
          // Decide how to proceed: Allow login but show warning? Or treat as failure?
          // Option: Allow login, show warning, navigate without profile data
          _showSnackBar('Login successful, but failed to fetch profile: ${profileError.message}', isError: true);
          // Set profileData to null or empty map if needed downstream
          profileData = null;
          // Proceed to navigation below, but dashboard needs to handle null profileData
        }
      }
      // --- End Profile Fetch ---


      // --- Step 3: Handle Autofill and Navigate ---
      // IMPORTANT: Notify Autofill service on successful context completion [1]
      TextInput.finishAutofillContext(shouldSave: true); // Prompt user to save credentials

      if (mounted) {
        _showSnackBar('Login successful!', isError: false); // Use isError: false for green

        // Navigate to Dashboard, passing the fetched profile data (or null if fetch failed)
        Navigator.pushReplacementNamed(
            context,
            '/dashboard', // Your target route after login
            arguments: profileData // Pass the profile map as arguments [2]
        );
      }

    } on AuthException catch (e) {
      // Handle Supabase authentication errors
      if (mounted) {
        _showSnackBar('Login Failed: ${e.message}', isError: true);
      }
    } catch (e) {
      // Handle other unexpected errors (network, profile fetch exception etc.)
      if (mounted) {
        print("Unexpected login error: $e");
        _showSnackBar('An unexpected error occurred: ${e.toString()}', isError: true);
      }
    } finally {
      // Ensure loading state is reset regardless of outcome
      if (mounted) {
        setState(() => _isLoggingIn = false);
      }
    }
  }

  // --- Helper for showing Snackbars ---
  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar(); // Remove previous snackbar
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError
          ? Theme.of(context).colorScheme.error
          : Colors.green[600], // Use theme error color or green for success
      behavior: SnackBarBehavior.floating, // Optional: Make it float
    ));
  }


  // --- BUILD METHOD ---
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    const double avatarRadius = 80.0; // Adjusted size
    const double avatarDiameter = avatarRadius * 2;
    const double placeholderIconSize = avatarRadius * 0.8; // Adjust icon size relative to radius
    const Duration fadeDuration = Duration(milliseconds: 400);

    // Placeholder widget definition
    final Widget placeholderWidget = Container(
      width: avatarDiameter,
      height: avatarDiameter,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: _isLoadingAvatar
            ? const CircularProgressIndicator(strokeWidth: 2.5, color: Colors.grey)
            : Icon(Icons.person_outline, size: placeholderIconSize, color: Colors.grey.shade500),
      ),
    );

    return Scaffold(
      // Avoid resizing when keyboard appears
      // resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // --- Background Gradient ---
          Container(
            decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.teal.shade50, // Lighter shades
                    Colors.purple.shade50,
                    Colors.blue.shade50,
                  ],
                  stops: const [0.1, 0.5, 0.9],
                )
            ),
          ),

          // --- Main Content ---
          SafeArea(
            child: Center(
              child: SingleChildScrollView( // Allows scrolling if content overflows
                padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 20.0), // Adjusted padding
                // *** Wrap the form fields in AutofillGroup for context *** [1]
                child: AutofillGroup(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // --- Avatar Display ---
                      Container(
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                  offset: const Offset(0, 4)
                              )
                            ]
                        ),
                        child: CircleAvatar(
                          radius: avatarRadius,
                          backgroundColor: Colors.grey.shade300, // Background for the circle
                          child: ClipOval(
                            child: AnimatedSwitcher(
                              duration: fadeDuration,
                              child: CachedNetworkImage(
                                // Use URL or a unique placeholder key
                                key: ValueKey<String>(_avatarUrl ?? 'placeholder_${_isLoadingAvatar.toString()}'),
                                imageUrl: _avatarUrl ?? '', // Provide empty string if null
                                placeholder: (context, url) => placeholderWidget,
                                fadeInDuration: fadeDuration,
                                errorWidget: (context, url, error) {
                                  print("CachedNetworkImage Error: $error for URL: $url");
                                  return placeholderWidget; // Show placeholder on error
                                },
                                fit: BoxFit.cover,
                                width: avatarDiameter,
                                height: avatarDiameter,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24), // Spacing

                      // --- Welcome Text ---
                      Text(
                        'Welcome Back!',
                        style: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600, color: Colors.grey.shade800), // Slightly smaller headline
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Login to continue',
                        style: textTheme.titleMedium?.copyWith(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 30), // Spacing before form

                      // --- Email Field ---
                      TextFormField(
                        controller: _emailController,
                        focusNode: _emailFocusNode,
                        enabled: !_isLoggingIn, // Disable when logging in
                        decoration: _inputDecoration( // Using helper for style
                          label: 'Email Address',
                          hint: 'you@example.com',
                          icon: Icons.alternate_email,
                        ),
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        // *** Add autofillHints for email/username *** [1]
                        autofillHints: const [AutofillHints.email, AutofillHints.username],
                        onEditingComplete: () => FocusScope.of(context).nextFocus(), // Move focus on 'next'
                      ),
                      const SizedBox(height: 16),

                      // --- Password Field ---
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        enabled: !_isLoggingIn,
                        decoration: _inputDecoration( // Using helper for style
                          label: 'Password',
                          hint: 'Enter your password',
                          icon: Icons.lock_outline,
                          suffixIcon: IconButton(
                              icon: Icon(
                                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  color: Colors.grey.shade600
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword)
                          ),
                        ),
                        textInputAction: TextInputAction.done,
                        // *** Add autofillHints for password *** [1]
                        autofillHints: const [AutofillHints.password],
                        // Trigger login on 'done' action from keyboard
                        onFieldSubmitted: (_) => _isLoggingIn ? null : _login(),
                      ),
                      const SizedBox(height: 24),

                      // --- Login Button ---
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.primary, // Theme color
                            foregroundColor: colorScheme.onPrimary, // Text color on button
                            elevation: 3,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 16), // Taller button
                          ),
                          onPressed: _isLoggingIn ? null : _login, // Disable button when loading
                          child: _isLoggingIn
                              ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text('Sign In', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.onPrimary)),
                        ),
                      ),
                      const SizedBox(height: 20), // Spacing

                      // --- Redirect to Signup ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("Don't have an account?", style: TextStyle(color: Colors.grey.shade700)),
                          TextButton(
                              onPressed: _isLoggingIn ? null : () {
                                // Replace with your actual signup route name if different
                                Navigator.pushReplacementNamed(context, '/signup');
                              },
                              style: TextButton.styleFrom(
                                  foregroundColor: colorScheme.primary,
                                  padding: const EdgeInsets.symmetric(horizontal: 6)
                              ),
                              child: Text('Sign up Now', style: TextStyle(fontWeight: FontWeight.bold))
                          )
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Helper for consistent InputDecoration ---
  InputDecoration _inputDecoration({required String label, String? hint, IconData? icon, Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, color: Colors.grey.shade600) : null,
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none // No visible border initially
      ),
      enabledBorder: OutlineInputBorder( // Border when enabled but not focused
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
      ),
      focusedBorder: OutlineInputBorder( // Border when focused
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
      ),
      filled: true,
      fillColor: Colors.white.withOpacity(0.9), // Slightly transparent white fill
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
    );
  }
}
