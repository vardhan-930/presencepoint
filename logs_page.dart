import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:intl/intl.dart';
//import 'dart:math'; // For max() and ceil() in pie chart calculation

//###########################################################################
// ATTENDANCE LOGS RELATED CODE (Map, Check-in/out, History Table)
//###########################################################################

// Simple model for individual attendance records (for the history table)
class AttendanceRecord {
  final String id;
  final DateTime attendanceDate;
  final DateTime? checkInTimestamp;
  final DateTime? checkOutTimestamp;
  final String status;
  final String? workingZone;
  // Added duration field to model (optional, but good for display)
  final int? durationMinutes;

  AttendanceRecord({
    required this.id,
    required this.attendanceDate,
    this.checkInTimestamp,
    this.checkOutTimestamp,
    required this.status,
    this.workingZone,
    this.durationMinutes, // Added
  });

  factory AttendanceRecord.fromMap(Map<String, dynamic> map) {
    // Helper to safely parse DateTime strings
    DateTime? tryParseDateTime(String? dateString) {
      if (dateString == null) return null;
      try { return DateTime.parse(dateString); }
      catch (e) { print("Error parsing date-time: $dateString, Error: $e"); return null; }
    }

    // Helper to safely parse Date strings (YYYY-MM-DD)
    DateTime? tryParseDateOnly(String? dateString) {
      if (dateString == null) return null;
      try { final datePart = dateString.split('T').first; return DateTime.parse(datePart); }
      catch (e) { print("Error parsing date only: $dateString, Error: $e"); return null; }
    }

    final attendanceDate = tryParseDateOnly(map['attendance_date'] as String?);
    if (attendanceDate == null) {
      print("Error: Invalid or missing attendance_date in record: ${map['id']}");
      return AttendanceRecord(
        id: map['id'] as String? ?? 'Invalid ID',
        attendanceDate: DateTime(1970), status: 'Error: Invalid Date',
      );
    }

    return AttendanceRecord(
      id: map['id'] as String? ?? 'N/A',
      attendanceDate: attendanceDate,
      checkInTimestamp: tryParseDateTime(map['checkin_timestamp'] as String?),
      checkOutTimestamp: tryParseDateTime(map['checkout_timestamp'] as String?),
      status: map['attendance_status'] as String? ?? 'Unknown',
      workingZone: map['working_zone'] as String?,
      // Safely parse duration_minutes (it might be null if not checked out yet)
      durationMinutes: map['duration_minutes'] as int?, // Added parsing
    );
  }
}


class LogsPage extends StatefulWidget {
  const LogsPage({Key? key}) : super(key: key);

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  // --- State variables ---
  GoogleMapController? _mapController;
  Position? _currentPosition;
  String? _mapErrorMessage;
  String _workingZone = "Determining zone...";
  bool _isLoading = false;
  String? _currentAttendanceId;
  DateTime? _checkInTimestamp;
  String? _checkedInZone;
  String? _actionErrorMessage;
  List<AttendanceRecord> _attendanceHistory = [];
  bool _isHistoryLoading = false;
  String? _historyErrorMessage;
  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _initializePageData();
  }

  Future<void> _initializePageData() async {
    // Initializes location, checks current check-in status, and fetches history table data
    if (!mounted) return;
    setState(() { _isLoading = true; _mapErrorMessage = null; _actionErrorMessage = null; _historyErrorMessage = null; });

    try {
      await _determinePosition();
      if (_currentPosition != null) { await Future.wait([ _fetchOngoingAttendance(), _fetchAttendanceHistory() ]); }
      else { print("Skipping attendance fetch due to location error."); }
    } catch (e) {
      print("Error during page initialization: $e");
      if (mounted && _mapErrorMessage == null) { setState(() => _actionErrorMessage = "Failed to initialize page data."); }
    } finally {
      if (mounted) { setState(() { _isLoading = false; _isHistoryLoading = false; }); }
    }
  }


  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  // --- Location Fetching Logic ---
  Future<void> _determinePosition() async {
    if (!mounted) return;
    print("Attempting to determine position...");
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services are disabled.');
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) throw Exception('Location permission denied.');
      }
      if (permission == LocationPermission.deniedForever) throw Exception('Location permissions permanently denied.');
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      print("Position determined: ${pos.latitude}, ${pos.longitude}");
      if (mounted) {
        setState(() { _currentPosition = pos; _mapErrorMessage = null; _workingZone = (pos.latitude > 0) ? "North Zone" : "South Zone"; });
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 14.5));
      }
    } catch (e) {
      print("Error determining position: $e");
      if (mounted) { setState(() { _mapErrorMessage = "Location Error: ${e.toString()}"; _currentPosition = null; }); }
      rethrow;
    }
  }

  // --- Fetch Ongoing Attendance State ---
  Future<void> _fetchOngoingAttendance() async {
    if (!mounted) return;
    final user = supabase.auth.currentUser;
    if (user == null) { if(mounted) setState(() => _actionErrorMessage = "Not logged in."); return; }
    print("Checking for ongoing attendance...");
    try {
      final todayDate = DateTime.now().toIso8601String().split('T')[0];
      final response = await supabase.from('attendance').select('id, checkin_timestamp, working_zone').eq('user_id', user.id).eq('attendance_date', todayDate).isFilter('checkout_timestamp', null).limit(1).maybeSingle();
      if (!mounted) return;
      if (response != null) {
        final checkinTime = DateTime.tryParse(response['checkin_timestamp'] as String? ?? '');
        if (checkinTime != null) {
          setState(() { _currentAttendanceId = response['id'] as String?; _checkInTimestamp = checkinTime; _checkedInZone = response['working_zone'] as String? ?? _workingZone; _actionErrorMessage = null; });
        } else { print("Found record but couldn't parse checkin_timestamp"); _clearCheckInState(); }
      } else { _clearCheckInState(); }
    } catch (e) {
      print("Error fetching ongoing attendance: $e");
      if (mounted && _mapErrorMessage == null) { setState(() => _actionErrorMessage = "Couldn't verify attendance status."); }
      _clearCheckInState();
    }
  }

  // --- Fetch Attendance History ---
  Future<void> _fetchAttendanceHistory() async {
    if (!mounted) return;
    final user = supabase.auth.currentUser;
    if (user == null) { if(mounted) setState(() => _historyErrorMessage = "Not logged in."); return; }
    print("Fetching attendance history...");
    setState(() { _isHistoryLoading = true; _historyErrorMessage = null; });
    try {
      final response = await supabase
          .from('attendance')
      // Include duration_minutes in the select statement
          .select('id, attendance_date, checkin_timestamp, checkout_timestamp, attendance_status, working_zone, duration_minutes')
          .eq('user_id', user.id)
          .order('attendance_date', ascending: false).order('checkin_timestamp', ascending: false)
          .limit(15);
      if (!mounted) return;
      final List<dynamic> data = response as List<dynamic>;
      final List<AttendanceRecord> history = [];
      for (var item in data) {
        try { history.add(AttendanceRecord.fromMap(item as Map<String, dynamic>)); } // Uses updated fromMap
        catch (e) { print("Error parsing history record: $item, Error: $e"); }
      }
      setState(() { _attendanceHistory = history; });
    } on PostgrestException catch (e) {
      print("DB error fetching history: ${e.message}");
      if (mounted) setState(() { _historyErrorMessage = "DB Error: ${e.message}"; _attendanceHistory = []; });
    } catch (e) {
      print("Error fetching history: $e");
      if (mounted) setState(() { _historyErrorMessage = "Failed to load history."; _attendanceHistory = []; });
    } finally {
      if (mounted) setState(() { _isHistoryLoading = false; });
    }
  }

  // Helper to clear check-in state
  void _clearCheckInState() {
    if (!mounted) return;
    setState(() { _currentAttendanceId = null; _checkInTimestamp = null; _checkedInZone = null; });
  }

  // Map creation callback
  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    if (_currentPosition != null) {
      controller.animateCamera(CameraUpdate.newLatLngZoom(LatLng(_currentPosition!.latitude, _currentPosition!.longitude), 14.5));
    }
  }

  // Check-in action handler
  Future<void> _handleCheckIn() async {
    if (_currentPosition == null || _isLoading || _currentAttendanceId != null) {
      _showErrorSnackBar('Cannot check in. Location unavailable, action in progress, or already checked in.'); return; }
    setState(() { _isLoading = true; _actionErrorMessage = null; });
    final checkInTime = DateTime.now();
    try {
      bool isWithinZone = await _checkIfInZone(_currentPosition!, _workingZone);
      final userId = supabase.auth.currentUser?.id; if (userId == null) throw Exception("User not logged in.");
      final checkinData = { 'user_id': userId, 'attendance_date': checkInTime.toIso8601String().substring(0, 10), 'checkin_timestamp': checkInTime.toIso8601String(),
        if (_currentPosition != null) ...{ 'checkin_location': 'POINT(${_currentPosition!.longitude} ${_currentPosition!.latitude})', 'checkin_location_accuracy': _currentPosition!.accuracy, },
        'working_zone': _workingZone, 'is_within_zone_checkin': isWithinZone, 'attendance_status': 'CheckedIn',
        // Make sure duration is null on check-in
        'duration_minutes': null,
      };
      final response = await supabase.from('attendance').insert(checkinData).select('id').single();
      if (mounted) {
        setState(() { _currentAttendanceId = response['id']; _checkInTimestamp = checkInTime; _checkedInZone = _workingZone; });
        _showSuccessSnackBar('Checked In at $_checkedInZone'); _fetchAttendanceHistory();
      }
    } on PostgrestException catch (error){
      print('Check-in DB Error: ${error.code} - ${error.message}'); if(mounted) _showErrorSnackBar('Check-in failed: ${error.message}'); _clearCheckInState();
    } catch (error) {
      print('Check-in Error: $error'); if (mounted) _showErrorSnackBar('Check-in failed: ${error.toString()}'); _clearCheckInState();
    } finally { if (mounted) setState(() { _isLoading = false; }); }
  }

  // --- Check-out action handler (UPDATED with duration_minutes) ---
  Future<void> _handleCheckOut() async {
    if (_currentPosition == null || _isLoading || _currentAttendanceId == null) {
      _showErrorSnackBar('Cannot check out. Location unavailable, action in progress, or not checked in.'); return; }
    if (_checkInTimestamp == null) {
      _showErrorSnackBar('Error: Check-in time is missing. Cannot calculate duration.'); return; } // Exit if check-in time missing

    setState(() { _isLoading = true; _actionErrorMessage = null; });
    final checkOutTime = DateTime.now();
    try {
      bool isWithinZone = await _checkIfInZone(_currentPosition!, _checkedInZone ?? _workingZone);
      Duration workDuration = checkOutTime.difference(_checkInTimestamp!); // Calculate duration
      int durationInMinutes = workDuration.inMinutes; // Get total minutes

      // Determine attendance status based on duration threshold (if still needed)
      const lateThresholdMinutes = 35;
      String attendanceStatus = 'Present'; // Default to Present
      if (durationInMinutes > lateThresholdMinutes) {
        attendanceStatus = 'Late'; print("Duration ($durationInMinutes min) exceeds threshold ($lateThresholdMinutes min). Marking as Late.");
      } else { print("Duration ($durationInMinutes min) is within threshold. Marking as Present."); }

      final checkoutData = {
        'checkout_timestamp': checkOutTime.toIso8601String(),
        if (_currentPosition != null) ...{ 'checkout_location': 'POINT(${_currentPosition!.longitude} ${_currentPosition!.latitude})', 'checkout_location_accuracy': _currentPosition!.accuracy, },
        'is_within_zone_checkout': isWithinZone,
        'attendance_status': attendanceStatus, // Store determined status (Present/Late)
        // --- ADDED: Include the calculated duration in minutes ---
        'duration_minutes': durationInMinutes,
        // --- END ADDITION ---
      };

      // Update the record in Supabase
      await supabase.from('attendance').update(checkoutData).eq('id', _currentAttendanceId!);

      if (mounted) {
        _clearCheckInState(); // Clear state including _checkInTimestamp
        _showSuccessSnackBar('Checked Out as $attendanceStatus. Duration: $durationInMinutes min.'); // Updated message
        _fetchAttendanceHistory(); // Refresh table
      }
    } on PostgrestException catch (error){
      print('Check-out DB Error: ${error.code} - ${error.message}'); if(mounted) _showErrorSnackBar('Check-out failed: ${error.message}');
    } catch (error) {
      print('Check-out Error: $error'); if (mounted) _showErrorSnackBar('Check-out failed: ${error.toString()}');
    } finally { if (mounted) setState(() { _isLoading = false; }); }
  }
  // --- End of Updated Check-out Handler ---

  // Placeholder geofencing logic
  Future<bool> _checkIfInZone(Position currentPosition, String zoneId) async {
    print("Geofencing check: Pos (${currentPosition.latitude}, ${currentPosition.longitude}) in Zone '$zoneId'");
    await Future.delayed(const Duration(milliseconds: 50)); return true; // Placeholder
  }

  // Snackbar helpers
  void _showErrorSnackBar(String message) {
    if (!mounted) return; ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar( content: Text(message), backgroundColor: Theme.of(context).colorScheme.error, behavior: SnackBarBehavior.floating, margin: const EdgeInsets.all(10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), ));
  }
  void _showSuccessSnackBar(String message) {
    if (!mounted) return; ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar( content: Text(message), backgroundColor: Colors.green[600], behavior: SnackBarBehavior.floating, margin: const EdgeInsets.all(10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), ));
  }

  // --- Build Method ---
  @override
  Widget build(BuildContext context) {
    print("Building LogsPage - ... CheckInTime: $_checkInTimestamp ..."); // Debug print

    Widget mainContent;
    if (_isLoading && _currentPosition == null && _mapErrorMessage == null) { mainContent = const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: 16), Text("Initializing...")],),); }
    else if (_mapErrorMessage != null) { mainContent = _buildLocationErrorState(); }
    else { mainContent = Column( mainAxisAlignment: MainAxisAlignment.start, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Divider(height: 20, thickness: 1, indent: 16, endIndent: 16), // Separator
      Padding( padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0), child: _buildMapContent() ), // Map
      _buildActionSection(), // Actions
      if ((_isLoading || _isHistoryLoading) && _mapErrorMessage == null) const Padding( padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0), child: LinearProgressIndicator(minHeight: 2),), // Loader
      if (_actionErrorMessage != null) Padding( padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), child: Text(_actionErrorMessage!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 14)),), // Action Error
      Padding( padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), child: _buildAttendanceTable(),), // History Table
    ],); }

    // Overall structure
    return SafeArea( child: RefreshIndicator( onRefresh: _initializePageData, child: SingleChildScrollView( physics: const AlwaysScrollableScrollPhysics(), child: AnimatedSwitcher( duration: const Duration(milliseconds: 300), child: mainContent, ), ), ), );
  }

  // --- Extracted Build Widgets ---

  // Builds the Map Content
  Widget _buildMapContent() {
    if (_currentPosition == null) { return Card( elevation: 4.0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)), clipBehavior: Clip.antiAlias, child: SizedBox( height: 300, child: Center( child: Column( mainAxisSize: MainAxisSize.min, children: [ if (_isLoading) const CircularProgressIndicator.adaptive(), if (_isLoading) const SizedBox(height: 16), Text(_isLoading ? "Getting location..." : "Location unavailable"), ],),),), ); }
    return Card( elevation: 4.0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)), clipBehavior: Clip.antiAlias, child: SizedBox( height: 300, width: double.infinity, child: AbsorbPointer( absorbing: _isLoading, child: GoogleMap( onMapCreated: _onMapCreated, initialCameraPosition: CameraPosition( target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude), zoom: 14.5), myLocationEnabled: true, myLocationButtonEnabled: true, mapType: MapType.normal, zoomControlsEnabled: false, mapToolbarEnabled: false, padding: const EdgeInsets.only(bottom: 40.0, top: 10.0), ),),), );
  }

  // Builds the Action Section
  Widget _buildActionSection() {
    final theme = Theme.of(context); final bool isCheckedIn = _currentAttendanceId != null; final bool canPerformAction = _currentPosition != null && !_isLoading;
    return Padding( padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0), child: Column( crossAxisAlignment: CrossAxisAlignment.center, children: [
      Text(_currentPosition != null ? "You are in: $_workingZone" : "Determining zone...", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500), textAlign: TextAlign.center), const SizedBox(height: 20.0),
      Row( mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [ ElevatedButton.icon( icon: const Icon(Icons.login, size: 18), label: const Text('Check In'), onPressed: canPerformAction && !isCheckedIn ? _handleCheckIn : null, style: ElevatedButton.styleFrom( backgroundColor: canPerformAction && !isCheckedIn ? Colors.green : theme.disabledColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), ).copyWith(elevation: MaterialStateProperty.all(canPerformAction && !isCheckedIn ? 4 : 0))),
        ElevatedButton.icon( icon: const Icon(Icons.logout, size: 18), label: const Text('Check Out'), onPressed: canPerformAction && isCheckedIn ? _handleCheckOut : null, style: ElevatedButton.styleFrom( backgroundColor: canPerformAction && isCheckedIn ? Colors.orange : theme.disabledColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), ).copyWith(elevation: MaterialStateProperty.all(canPerformAction && isCheckedIn ? 4 : 0))), ]),
      AnimatedSwitcher( duration: const Duration(milliseconds: 300), transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: SizeTransition(sizeFactor: animation, axisAlignment: -1.0, child: child)),
        child: isCheckedIn && _checkInTimestamp != null ? Padding( key: const ValueKey('checkinDetails'), padding: const EdgeInsets.only(top: 24.0), child: Container( padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0), decoration: BoxDecoration( color: Colors.green.shade50, borderRadius: BorderRadius.circular(8.0), border: Border.all(color: Colors.green.shade200, width: 1.0)),
          child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Text( "Currently Checked In:", style: theme.textTheme.titleSmall?.copyWith( fontWeight: FontWeight.bold, color: Colors.green.shade800,)), const SizedBox(height: 8.0), _buildDetailRow(icon: Icons.access_time_filled, text: 'Time: ${DateFormat.jm().format(_checkInTimestamp!)}', color: Colors.green.shade700, theme: theme), const SizedBox(height: 4.0), _buildDetailRow(icon: Icons.location_on, text: 'Zone: ${_checkedInZone ?? 'N/A'}', color: Colors.green.shade700, theme: theme), ]), )) : const SizedBox.shrink(key: ValueKey('noCheckinDetails')), ),
    ]), );
  }

  // Builds the Attendance History DataTable (Updated to potentially show duration)
  Widget _buildAttendanceTable() {
    final DateFormat timeFormat = DateFormat.jm(); final DateFormat dateFormat = DateFormat.yMd(); Widget content;
    if (_isHistoryLoading) { content = const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("Loading history..."))); }
    else if (_attendanceHistory.isEmpty && _historyErrorMessage == null) { content = const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("No attendance records found."))); }
    else if (_historyErrorMessage != null) { content = Center( child: Padding( padding: const EdgeInsets.all(16.0), child: Text( _historyErrorMessage!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)))); }
    else { content = DataTableTheme( data: DataTableThemeData( headingRowColor: MaterialStateColor.resolveWith((states) => Colors.blueGrey.shade50), headingTextStyle: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.black87), dataRowMinHeight: 40, dataRowMaxHeight: 48, dividerThickness: 1, columnSpacing: 12, horizontalMargin: 8),
      child: SingleChildScrollView( scrollDirection: Axis.horizontal, child: DataTable( showCheckboxColumn: false, columns: const [ DataColumn(label: Text('Date')), DataColumn(label: Text('Check In')), DataColumn(label: Text('Check Out')), DataColumn(label: Text('Duration (min)')), DataColumn(label: Text('Zone')), DataColumn(label: Text('Status')), ], // Added Duration column header
        rows: _attendanceHistory.map((record) {
          Color statusColor = Colors.black87; FontWeight statusWeight = FontWeight.normal;
          if (record.status == 'Present') { statusColor = Colors.green.shade700; statusWeight = FontWeight.w500; }
          else if (record.status == 'Late') { statusColor = Colors.orange.shade700; statusWeight = FontWeight.w500; }
          else if (record.status == 'CheckedIn') { statusColor = Colors.blue.shade700; statusWeight = FontWeight.w500; }
          else if (record.status == 'Absent') { statusColor = Colors.red.shade700; statusWeight = FontWeight.w500; }

          // Format duration for display
          final durationText = record.durationMinutes != null ? record.durationMinutes.toString() : '---';

          return DataRow( cells: [
            DataCell(Text(dateFormat.format(record.attendanceDate))),
            DataCell(Text(record.checkInTimestamp != null ? timeFormat.format(record.checkInTimestamp!) : '---')),
            DataCell(Text(record.checkOutTimestamp != null ? timeFormat.format(record.checkOutTimestamp!) : '---')),
            DataCell(Text(durationText)), // Display duration
            DataCell(Text(record.workingZone ?? 'N/A', overflow: TextOverflow.ellipsis)),
            DataCell(Text(record.status, style: TextStyle(fontWeight: statusWeight, color: statusColor))),
          ]);
        }).toList(),
      ),),
    );
    }
    return Card( elevation: 2.0, margin: const EdgeInsets.symmetric(vertical: 8.0), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)), clipBehavior: Clip.antiAlias,
      child: Column( crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding( padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0), child: Text( "Recent Attendance Logs", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
        AnimatedSwitcher( duration: const Duration(milliseconds: 200), child: content),
        const SizedBox(height: 8),
      ]),
    );
  }

  // Helper for detail rows in check-in box
  Widget _buildDetailRow({required IconData icon, required String text, required Color color, required ThemeData theme}) {
    return Row( children: [ Icon(icon, size: 18.0, color: color), const SizedBox(width: 8.0), Expanded( child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: color.withOpacity(0.9)), softWrap: true)), ]);
  }

  // Builds the Location Error State UI
  Widget _buildLocationErrorState() {
    return LayoutBuilder( builder: (context, constraints) { return SingleChildScrollView( child: ConstrainedBox( constraints: BoxConstraints(minHeight: constraints.maxHeight), child: Center( child: Padding( padding: const EdgeInsets.all(20.0),
      child: Column( mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.location_off_outlined, size: 50, color: Colors.redAccent.shade100), const SizedBox(height: 16),
        Text("Location Unavailable", style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.grey[700]), textAlign: TextAlign.center), const SizedBox(height: 8),
        Text(_mapErrorMessage ?? 'Could not determine your current location.', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Colors.grey[600])), const SizedBox(height: 24),
        ElevatedButton.icon( icon: const Icon(Icons.refresh), label: const Text('Retry'), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)), onPressed: _initializePageData), // Retry init
      ]),
    ),),),);},);
  }

} // End of _LogsPageState


