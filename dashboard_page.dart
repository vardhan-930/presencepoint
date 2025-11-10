import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

// Import the other dashboard section pages
import 'calendar_page.dart';
import 'logs_page.dart';

// Import main.dart for themeNotifier and setTheme
import '../../main.dart'; // Adjust the path if needed

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final SupabaseClient supabase = Supabase.instance.client;

  int _selectedIndex = 1;

  bool _isLoadingProfile = true;
  bool _profileInitialized = false;
  String? _avatarUrl;
  String? _fullName;
  String? _username;
  String? _role;
  DateTime? _dob;
  int? _age;
  String? _profileErrorMessage;

  final List<Widget> _staticSections = [
    const CalendarPage(),
    const SizedBox.shrink(),
    const LogsPage(),
  ];

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initializeProfileData();
  }

  Future<void> _initializeProfileData() async {
    if (_profileInitialized || !mounted) return;

    final arguments = ModalRoute.of(context)?.settings.arguments;
    Map<String, dynamic>? profileDataFromArgs;

    if (arguments is Map<String, dynamic>) {
      profileDataFromArgs = arguments;
    }

    if (profileDataFromArgs != null) {
      try {
        _parseAndSetProfileState(profileDataFromArgs, null);
        _profileInitialized = true;
        await _fetchUserRole();
      } catch (e) {
        setState(() {
          _isLoadingProfile = false;
          _profileErrorMessage = "Error loading profile from login data.";
          _profileInitialized = true;
        });
      }
    } else {
      await _fetchUserProfileData();
      _profileInitialized = true;
    }
  }

  Future<void> _fetchUserProfileData() async {
    if (!mounted) return;
    if (_fullName == null || _profileErrorMessage != null) {
      setState(() => _isLoadingProfile = true);
    }
    _profileErrorMessage = null;

    final user = supabase.auth.currentUser;
    if (user == null) {
      _handleLogout();
      return;
    }

    try {
      final profileResponse = await supabase
          .from('profiles')
          .select('full_name, username, dob, age, avatar_url')
          .eq('id', user.id)
          .single();

      String? fetchedRole;
      try {
        final roleResponse = await supabase
            .from('user_roles')
            .select('role')
            .eq('user_id', user.id)
            .maybeSingle();
        fetchedRole = roleResponse?['role'] as String?;
      } catch (roleError) {
        fetchedRole = null;
      }

      if (!mounted) return;
      _parseAndSetProfileState(profileResponse, fetchedRole);
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(() {
          _isLoadingProfile = false;
          _profileErrorMessage = 'Failed to load profile: ${error.message}';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoadingProfile = false;
          _profileErrorMessage = 'An unexpected error occurred.';
        });
      }
    }
  }

  Future<void> _fetchUserRole() async {
    if (!mounted) return;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final roleResponse = await supabase
          .from('user_roles')
          .select('role')
          .eq('user_id', user.id)
          .maybeSingle();
      final fetchedRole = roleResponse?['role'] as String?;

      if (mounted && fetchedRole != _role) {
        setState(() {
          _role = fetchedRole;
        });
      }
    } catch (roleError) {}
  }

  void _parseAndSetProfileState(Map<String, dynamic>? profileData, String? roleData) {
    if (!mounted || profileData == null) {
      setState(() {
        _isLoadingProfile = false;
        _profileErrorMessage = _profileErrorMessage ?? "Profile data not available.";
      });
      return;
    }

    final dobString = profileData['dob'] as String?;
    DateTime? parsedDob = dobString != null ? DateTime.tryParse(dobString) : null;

    setState(() {
      _avatarUrl = profileData['avatar_url'] as String?;
      _fullName = profileData['full_name'] as String?;
      _username = profileData['username'] as String?;
      _dob = parsedDob;
      _age = profileData['age'] as int?;
      _role = roleData ?? _role;
      _isLoadingProfile = false;
      _profileErrorMessage = null;
    });
  }

  void _onItemTapped(int index) {
    if (!mounted) return;
    if (index == 1 && !_profileInitialized) {
      _initializeProfileData();
    } else if (index == 1 && _profileErrorMessage != null) {
    }
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _handleLogout() async {
    if (!mounted) return;
    try {
      await supabase.auth.signOut();
      Navigator.pushReplacementNamed(context, '/login');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing out: ${error.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _getAppBarTitle(int index) {
    switch (index) {
      case 0:
        return 'Calendar';
      case 1:
        return 'My Profile';
      case 2:
        return 'Logs';
      default:
        return 'Dashboard';
    }
  }

  Widget _buildProfileTabContent(BuildContext context) {
    if (_isLoadingProfile) {
      return const Center(child: CircularProgressIndicator());
    } else if (_profileErrorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 50),
              const SizedBox(height: 16),
              Text(_profileErrorMessage!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Load'),
                onPressed: _fetchUserProfileData,
              ),
            ],
          ),
        ),
      );
    } else {
      return _buildDetailedProfileViewUI(context);
    }
  }

  Widget _buildDetailedProfileViewUI(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    const double avatarRadius = 65.0;
    const double avatarDiameter = avatarRadius * 2;
    const double placeholderIconSize = avatarRadius;

    return RefreshIndicator(
      onRefresh: _fetchUserProfileData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      spreadRadius: 1,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: CircleAvatar(
                  radius: avatarRadius,
                  backgroundColor: theme.colorScheme.surfaceVariant,
                  child: ClipOval(
                    child: CachedNetworkImage(
                      key: ValueKey(_avatarUrl ?? 'profile_placeholder'),
                      imageUrl: _avatarUrl ?? '',
                      placeholder: (context, url) => Icon(Icons.person_outline, size: placeholderIconSize, color: theme.colorScheme.onSurfaceVariant),
                      errorWidget: (context, url, error) => Icon(Icons.person_outline, size: placeholderIconSize, color: theme.colorScheme.onSurfaceVariant),
                      fit: BoxFit.cover,
                      width: avatarDiameter,
                      height: avatarDiameter,
                      fadeInDuration: const Duration(milliseconds: 300),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _fullName ?? 'N/A',
                style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6.0,
                runSpacing: 4.0,
                children: [
                  if (_username != null && _username!.isNotEmpty)
                    Text(
                      '@$_username',
                      style: textTheme.titleMedium?.copyWith(color: Colors.grey.shade700),
                    ),
                  if (_username != null && _username!.isNotEmpty && _role != null && _role!.isNotEmpty)
                    Text('•', style: textTheme.titleMedium?.copyWith(color: Colors.grey.shade700)),
                  if (_role != null && _role!.isNotEmpty)
                    Chip(
                      label: Text(_formatRole(_role), style: TextStyle(color: colorScheme.onSecondary, fontWeight: FontWeight.w500)),
                      backgroundColor: colorScheme.secondary,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit Profile'),
                onPressed: () {
                  _showNotImplementedSnackBar(context);
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
          Card(
            margin: const EdgeInsets.symmetric(vertical: 8.0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Details", style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  _buildInfoRow(
                    icon: Icons.email_outlined,
                    label: 'Email',
                    value: supabase.auth.currentUser?.email ?? 'N/A',
                    context: context,
                  ),
                  const Divider(height: 24),
                  _buildInfoRow(
                    icon: Icons.cake_outlined,
                    label: 'Born',
                    value: _formatDate(_dob),
                    context: context,
                  ),
                  const Divider(height: 24),
                  _buildInfoRow(
                    icon: Icons.numbers,
                    label: 'Age',
                    value: _formatAge(_age),
                    context: context,
                  ),
                ],
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(vertical: 8.0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                _buildProfileMenuItem(
                    context: context,
                    title: "Settings",
                    icon: Icons.settings_outlined,
                    onPress: () => _showNotImplementedSnackBar(context),
                    showDivider: true),
                _buildProfileMenuItem(
                    context: context,
                    title: "App Information",
                    icon: Icons.info_outline,
                    onPress: () => _showNotImplementedSnackBar(context),
                    showDivider: true),
              ],
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(vertical: 8.0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: _buildProfileMenuItem(
              context: context,
              title: "Logout",
              icon: Icons.logout,
              textColor: Colors.red.shade700,
              iconColor: Colors.red.shade700,
              onPress: _handleLogout,
              endIcon: false,
              showDivider: false,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildInfoRow({required IconData icon, required String label, required String value, required BuildContext context}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 22),
          const SizedBox(width: 16),
          Text(
            '$label:',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.textTheme.bodySmall?.color),
              textAlign: TextAlign.end,
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileMenuItem({
    required BuildContext context,
    required String title,
    required IconData icon,
    required VoidCallback onPress,
    bool endIcon = true,
    Color? textColor,
    Color? iconColor,
    bool showDivider = false,
  }) {
    final theme = Theme.of(context);
    final itemColor = textColor ?? theme.textTheme.bodyLarge?.color;
    final effectiveIconColor = iconColor ?? theme.iconTheme.color ?? theme.colorScheme.primary;
    return Column(
      children: [
        ListTile(
          onTap: onPress,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(100),
              color: effectiveIconColor.withOpacity(0.1),
            ),
            child: Icon(icon, color: effectiveIconColor),
          ),
          title: Text(title, style: theme.textTheme.bodyLarge?.copyWith(color: itemColor, fontWeight: FontWeight.w500)),
          trailing: endIcon ? Icon(Icons.chevron_right, size: 22.0, color: Colors.grey.shade400) : null,
          dense: true,
        ),
        if (showDivider) const Divider(height: 0.5, indent: 72, endIndent: 16),
      ],
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Not Provided';
    try {
      return DateFormat.yMMMMd().format(date);
    } catch (e) {
      return 'Invalid Date';
    }
  }

  String _formatAge(int? age) {
    if (age == null) return 'Not Provided';
    return age.toString();
  }

  String _formatRole(String? role) {
    if (role == null || role.isEmpty) return 'Not Specified';
    return role[0].toUpperCase() + role.substring(1).toLowerCase();
  }

  void _showNotImplementedSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Feature not implemented yet.'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final List<Widget> currentDashboardSections = [
      _staticSections[0],
      _buildProfileTabContent(context),
      _staticSections[2],
    ];

    // --- DARK MODE TOGGLE ADDED HERE ---
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, _) {
        final bool isDarkMode = currentMode == ThemeMode.dark;
        return Scaffold(
          appBar: AppBar(
            title: Text(_getAppBarTitle(_selectedIndex)),
            elevation: 1,
            backgroundColor: theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface,
            foregroundColor: theme.appBarTheme.foregroundColor ?? theme.colorScheme.onSurface,
            actions: [
              Icon(isDarkMode ? Icons.nightlight_round : Icons.wb_sunny),
              Switch(
                value: isDarkMode,
                onChanged: (value) {
                  setTheme(value);
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: IndexedStack(
            index: _selectedIndex,
            children: currentDashboardSections,
          ),
          bottomNavigationBar: BottomNavigationBar(
            items: const <BottomNavigationBarItem>[
              BottomNavigationBarItem(icon: Icon(Icons.calendar_today_outlined), activeIcon: Icon(Icons.calendar_today), label: 'Calendar'),
              BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profile'),
              BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), activeIcon: Icon(Icons.receipt_long), label: 'Logs'),
            ],
            currentIndex: _selectedIndex,
            selectedItemColor: theme.colorScheme.primary,
            unselectedItemColor: Colors.grey.shade600,
            onTap: _onItemTapped,
            backgroundColor: theme.bottomAppBarTheme.color ?? theme.cardColor,
            type: BottomNavigationBarType.fixed,
            elevation: 8.0,
          ),
        );
      },
    );
  }
}
