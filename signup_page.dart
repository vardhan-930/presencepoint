import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart'; // Used for generating unique file names
// Optional: For better MIME type detection
// import 'package:mime/mime.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController fullNameController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController emailController    = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();
  final TextEditingController _dobController = TextEditingController(); // Controller for DOB display

  // State variables
  DateTime? _selectedDob;
  int? _calculatedAge;
  File? _selectedImage;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _attemptedSignupWithoutImage = false; // To show validation message for image

  // Helpers
  final picker = ImagePicker();
  final supabase = Supabase.instance.client;

  // Animation (Optional but nice)
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500)
    );
    _fadeAnimation = CurvedAnimation(parent: _animationController, curve: Curves.easeIn);
    _animationController.forward();
  }

  @override
  void dispose() {
    fullNameController.dispose();
    usernameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    _dobController.dispose(); // Dispose DOB controller
    _animationController.dispose();
    super.dispose();
  }

  // Opens image picker for profile picture.
  Future<void> _pickImage() async {
    if (_isLoading) return; // Don't allow picking while loading
    try {
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
      if (picked != null) {
        setState(() {
          _selectedImage = File(picked.path);
          _attemptedSignupWithoutImage = false; // Reset validation on image selection
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Calculate age from DOB.
  int _calculateAge(DateTime dob) {
    final today = DateTime.now();
    int age = today.year - dob.year;
    if (today.month < dob.month || (today.month == dob.month && today.day < dob.day)) {
      age--;
    }
    return age;
  }

  // Uploads profile picture to Supabase Storage ('avatars' bucket assumed).
  Future<String?> _uploadAvatar(String userId) async {
    // Note: _selectedImage null check happens before calling _signUp
    if (_selectedImage == null) return null; // Should not happen if validation is correct

    try {
      // Generate a unique file name
      final fileExt = _selectedImage!.path.split('.').last;
      final fileName = '${userId}_${const Uuid().v4()}.$fileExt';
      final imageBytes = await _selectedImage!.readAsBytes();
      final filePath = fileName;
      final mimeType = lookupMimeType(_selectedImage!.path); // Get MIME type

      // Upload to 'avatars' bucket
      await supabase.storage.from('avatars').uploadBinary(
        filePath,
        imageBytes,
        fileOptions: FileOptions(contentType: mimeType, upsert: false), // Use detected MIME type
      );

      // Get the public URL for the uploaded file
      return supabase.storage.from('avatars').getPublicUrl(filePath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading avatar: $e'), backgroundColor: Colors.red),
        );
      }
      return null; // Return null if upload failed
    }
  }


  // Signup operation: Authenticates, uploads avatar, inserts into profiles table.
  Future<void> _signUp() async {
    setState(() {
      // Trigger validation for image if attempting signup
      _attemptedSignupWithoutImage = true;
    });

    // --- Step 1: Validate Form, DOB, and Compulsory Image ---
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid || _selectedDob == null || _selectedImage == null) {
      if (_selectedDob == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select your Date of Birth'), backgroundColor: Colors.orange),
        );
      }
      if (_selectedImage == null && mounted) {
        // Message handled by validation text below avatar now
        print("Profile picture is required.");
      }
      return; // Stop if validation fails or image/DOB missing
    }

    // Check if passwords match
    if (passwordController.text != confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Gather data from controllers
    final fullName = fullNameController.text.trim();
    final username = usernameController.text.trim();
    final email    = emailController.text.trim();
    final password = passwordController.text; // Used ONLY for auth signup
    final dob = _selectedDob!;
    final age = _calculateAge(dob);

    try {
      // --- Step 2: Sign up user with Supabase Auth ---
      final AuthResponse res = await supabase.auth.signUp(
        email: email,
        password: password,
        // data: {'full_name': fullName, 'username': username}, // Optional metadata
      );

      final User? user = res.user;

      if (user == null) {
        throw const AuthException('Signup completed but no user data received.');
      }

      // --- Step 3: Upload Compulsory Avatar ---
      final String? avatarUrl = await _uploadAvatar(user.id);

      // Although compulsory, check if upload failed unexpectedly
      if (avatarUrl == null) {
        throw Exception('Avatar upload failed. Please try again.');
      }

      // --- Step 4: Insert data into the public.profiles table ---
      final Map<String, dynamic> profileData = {
        'id': user.id, // Link tables using the auth user ID
        'full_name': fullName.isNotEmpty ? fullName : null,
        'username': username.isNotEmpty ? username : null,
        'email': email,
        'dob': dob.toIso8601String().split('T')[0], // Format YYYY-MM-DD
        'age': age,
        'avatar_url': avatarUrl, // Use the URL returned from storage
        // 'updated_at', 'created_at' handled by DB defaults/triggers
        // !!! password_insecure field intentionally OMITTED for security !!!
        // !!! Role 'Employee' handled by the DB trigger 'assign_default_employee_role' !!!
      };

      // Perform the insert
      await supabase.from('profiles').insert(profileData);

      // --- Step 5: Success Feedback & Navigation ---
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Signup successful!'),
            backgroundColor: Colors.green,
          ),
        );
        // Navigate back or to login page
        // Replace with your actual navigation logic if using named routes etc.
        if (Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }
        // else { Navigator.of(context).pushReplacementNamed('/login'); }
      }

    } on AuthException catch (error) {
      // Handle Supabase authentication errors
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Auth Error: ${error.message}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } on PostgrestException catch (error) {
      // Handle Supabase database errors (e.g., unique constraint violation, RLS issue)
      if (mounted) {
        print('Database Error: ${error.toString()}'); // Log for debugging
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Database Error: ${error.message} (code: ${error.code})'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        // TODO: Consider compensating action? e.g., inform user profile failed, maybe delete auth user? (Requires careful implementation)
      }
    } catch (error) {
      // Handle other unexpected errors (network, file read, etc.)
      if (mounted) {
        print('Unexpected Error: ${error.toString()}'); // Log for debugging
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An unexpected error occurred: ${error.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      // Ensure loading state is reset
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context); // Get theme for colors

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Create Account"),
          centerTitle: true,
          elevation: 0,
          // backgroundColor: theme.colorScheme.primary, // Use theme color
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // --- Profile Picture Upload ---
                GestureDetector(
                  onTap: _pickImage,
                  child: Column( // Wrap Avatar and validation text
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                        child: CircleAvatar(
                          key: ValueKey(_selectedImage?.path),
                          radius: 50,
                          backgroundColor: Colors.grey.shade300, // Slightly darker background
                          backgroundImage: _selectedImage != null ? FileImage(_selectedImage!) : null,
                          child: _selectedImage == null
                              ? Icon(Icons.camera_alt_outlined, size: 40, color: theme.colorScheme.primary)
                              : null,
                        ),
                      ),
                      // --- Validation Text for Compulsory Image ---
                      if (_attemptedSignupWithoutImage && _selectedImage == null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'Profile picture is required',
                            style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // --- Full Name Field ---
                TextFormField(
                  controller: fullNameController,
                  enabled: !_isLoading, // Disable when loading
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty ? 'Enter your full name' : null,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 14),

                // --- Username Field ---
                TextFormField(
                  controller: usernameController,
                  enabled: !_isLoading,
                  decoration: InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.alternate_email),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty ? 'Enter a username' : null,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 14),

                // --- DOB Picker with Age Display ---
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField( // Use controller fix for DOB display
                        controller: _dobController,
                        readOnly: true, // Keyboard won't appear
                        enabled: !_isLoading,
                        decoration: InputDecoration(
                          labelText: 'Date of Birth',
                          hintText: 'Select Date',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.calendar_today_outlined),
                        ),
                        onTap: () async {
                          if (_isLoading) return; // Prevent opening picker if loading
                          FocusScope.of(context).requestFocus(FocusNode()); // Hide keyboard just in case
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedDob ?? DateTime.now().subtract(const Duration(days: 365 * 18)),
                            firstDate: DateTime(1900),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            setState(() {
                              _selectedDob = picked;
                              _calculatedAge = _calculateAge(picked);
                              _dobController.text = '${picked.day}/${picked.month}/${picked.year}'; // Update display text
                            });
                          }
                        },
                        validator: (_) => _selectedDob == null ? 'Please select DOB' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: InputDecorator( // Using InputDecorator for consistent styling
                        decoration: InputDecoration(
                          labelText: 'Age',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(vertical: 18.0, horizontal: 12.0),
                        ),
                        child: Text(
                          _calculatedAge?.toString() ?? '--',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // --- Email Field ---
                TextFormField(
                  controller: emailController,
                  enabled: !_isLoading,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Enter your email';
                    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
                    if (!emailRegex.hasMatch(value.trim())) return 'Enter a valid email';
                    return null;
                  },
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 14),

                // --- Password Field ---
                TextFormField(
                  controller: passwordController,
                  enabled: !_isLoading,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                    ),
                  ),
                  validator: (value) => value == null || value.length < 6 ? 'Password must be at least 6 characters' : null,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 14),

                // --- Confirm Password Field ---
                TextFormField(
                  controller: confirmPasswordController,
                  enabled: !_isLoading,
                  obscureText: true, // Always obscure confirmation
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.lock_person_outlined), // Corrected icon
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Please confirm your password';
                    if (value != passwordController.text) return 'Passwords do not match';
                    return null;
                  },
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _isLoading ? null : _signUp(), // Allow signup on enter if not loading
                ),
                const SizedBox(height: 24),

                // --- Create Account Button ---
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text("Create Account", style: TextStyle(fontSize: 16)),
                    onPressed: _signUp, // Calls the updated signup logic
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      // backgroundColor: theme.colorScheme.primary, // Use theme color
                    ),
                  ),
                ),
                // Optional: Add link to login page if needed
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Helper function to lookup MIME type (basic implementation)
// Consider using the 'mime' package for a more robust solution:
// import 'package:mime/mime.dart';
String? lookupMimeType(String path) {
  final ext = path.split('.').last.toLowerCase();
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
  // Add more common image types if needed
    default:
      return null; // Let Supabase attempt to infer if not recognized
  }
}