import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:fl_chart/fl_chart.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  Map<DateTime, Map<String, dynamic>> _attendanceDetails = {};
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _fetchAttendanceData();
  }

  Future<void> _fetchAttendanceData() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;

    if (userId == null) return;

    final start = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final end = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);

    final response = await supabase
        .from('attendance')
        .select('attendance_date, attendance_status, checkin_timestamp, checkout_timestamp, working_zone')
        .eq('user_id', userId)
        .gte('attendance_date', start.toIso8601String())
        .lte('attendance_date', end.toIso8601String());

    final Map<DateTime, Map<String, dynamic>> map = {};

    for (final record in response as List) {
      final dateStr = record['attendance_date'] as String?;
      final status = (record['attendance_status'] as String?)?.toLowerCase();

      if (dateStr != null && status != null) {
        final date = DateTime.parse(dateStr);
        final normalized = DateTime.utc(date.year, date.month, date.day);

        final details = {
          'status': status,
          'checkin': record['checkin_timestamp'],
          'checkout': record['checkout_timestamp'],
          'zone': record['working_zone'],
        };

        map[normalized] = details;
      }
    }

    setState(() {
      _attendanceDetails = map;
    });
  }

  Color _getColor(String? status) {
    switch (status) {
      case 'present':
        return Colors.green;
      case 'absent':
        return Colors.red;
      case 'late':
        return Colors.brown;
      default:
        return Colors.grey[300]!;
    }
  }

  Color _getTextColor(String? status) {
    switch (status) {
      case 'present':
      case 'absent':
      case 'late':
        return Colors.white;
      default:
        return Colors.black;
    }
  }

  Widget _buildLegend(Color color, String label) {
    return Row(
      children: [
        Container(width: 14, height: 14, color: color),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }

  Widget _buildWeekSummary() {
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final Map<int, String?> weekdayStatus = {};

    final sortedDates = _attendanceDetails.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final date in sortedDates) {
      final weekday = date.weekday;
      if (!weekdayStatus.containsKey(weekday)) {
        weekdayStatus[weekday] = _attendanceDetails[date]?['status'];
      }
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(7, (index) {
        final weekdayIndex = index + 1;
        final label = weekdays[index];
        final status = weekdayStatus[weekdayIndex];
        final circleColor = _getColor(status);

        return Column(
          children: [
            Text(label),
            const SizedBox(height: 4),
            CircleAvatar(radius: 10, backgroundColor: circleColor),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Attendance Calendar"),
        backgroundColor: Colors.deepPurple,
      ),
      body: RefreshIndicator(
        onRefresh: _fetchAttendanceData,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildLegend(Colors.green, 'Present'),
                  _buildLegend(Colors.red, 'Absent'),
                  _buildLegend(Colors.brown, 'Late'),
                  _buildLegend(Colors.grey[300]!, 'No Record'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TableCalendar(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2100, 12, 31),
              focusedDay: _focusedDay,
              calendarFormat: CalendarFormat.month,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (selected, focused) {
                setState(() {
                  _selectedDay = selected;
                  _focusedDay = focused;
                });

                final key = DateTime.utc(selected.year, selected.month, selected.day);
                final data = _attendanceDetails[key];

                showModalBottomSheet(
                  context: context,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  builder: (context) {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('EEEE, MMM d, y').format(selected),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Text("Status: ${data?['status']?.toUpperCase() ?? 'No Record'}"),
                          Text("Check-in: ${data?['checkin'] ?? '--'}"),
                          Text("Check-out: ${data?['checkout'] ?? '--'}"),
                          Text("Zone: ${data?['zone'] ?? '--'}"),
                        ],
                      ),
                    );
                  },
                );
              },
              onPageChanged: (focusedDay) {
                setState(() {
                  _focusedDay = focusedDay;
                });
                _fetchAttendanceData();
              },
              calendarBuilders: CalendarBuilders(
                defaultBuilder: (context, day, focusedDay) {
                  final key = DateTime.utc(day.year, day.month, day.day);
                  final status = _attendanceDetails[key]?['status'];
                  return Container(
                    margin: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _getColor(status),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        color: _getTextColor(status),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
                todayBuilder: (context, day, focusedDay) {
                  final key = DateTime.utc(day.year, day.month, day.day);
                  final status = _attendanceDetails[key]?['status'];
                  return Container(
                    margin: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _getColor(status),
                      border: Border.all(color: Colors.black, width: 1.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        color: _getTextColor(status),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            const Center(child: Text("Weekly Summary", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            const SizedBox(height: 8),
            _buildWeekSummary(),
            const SizedBox(height: 24),
            const AttendanceChartCard(),
            const SizedBox(height: 80), // Empty section at bottom for padding

          ],

        ),
      ),
    );
  }
}

//###########################################################################
// ATTENDANCE SUMMARY PIE CHART COMPONENT
//###########################################################################

class AttendanceChartCard extends StatefulWidget {
  const AttendanceChartCard({Key? key}) : super(key: key);
  @override
  State<AttendanceChartCard> createState() => _AttendanceChartCardState();
}

class _AttendanceChartCardState extends State<AttendanceChartCard> {
  final int totalClasses = 60;
  final double attendanceRequirement = 0.75;
  int presentCount = 0;
  int lateCount = 0;
  int absentCount = 0;
  bool isLoading = true;
  String? errorMessage;
  int touchedIndex = -1;
  String? selectedSliceLabel;
  double? selectedSlicePercentage;
  int? remainingClassesNeeded;
  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _fetchAttendanceSummary();
  }

  Future<void> _fetchAttendanceSummary() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() {
        isLoading = false;
        errorMessage = "User not logged in.";
      });
      return;
    }
    try {
      final response = await supabase
          .from('attendance')
          .select('attendance_status')
          .eq('user_id', userId);
      if (!mounted) return;
      int tempPresent = 0;
      int tempLate = 0;
      int tempAbsent = 0;
      final List<dynamic> data = response as List<dynamic>;
      for (var record in data) {
        final status = record['attendance_status'] as String?;
        switch (status?.trim().toLowerCase()) {
          case 'present':
          case 'checkedin':
            tempPresent++;
            break;
          case 'late':
            tempLate++;
            break;
          case 'absent':
            tempAbsent++;
            break;
        }
      }
      setState(() {
        presentCount = tempPresent;
        lateCount = tempLate;
        absentCount = tempAbsent;
        isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        isLoading = false;
        errorMessage = "An unexpected error occurred.";
      });
    }
  }

  void _calculateDetails(String label, int count, int totalRecorded) {
    if (totalRecorded == 0) {
      selectedSlicePercentage = 0.0;
    } else {
      selectedSlicePercentage = (count / totalRecorded) * 100;
    }
    int totalAttended = presentCount + lateCount;
    int targetAttendedClasses = (totalClasses * attendanceRequirement).ceil();
    remainingClassesNeeded = (targetAttendedClasses - totalAttended).clamp(0, totalClasses);
    selectedSliceLabel = label;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2.0,
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Attendance Summary", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            if (isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator())),
            if (!isLoading && errorMessage != null)
              Center(child: Padding(padding: const EdgeInsets.all(8.0), child: Text(errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error), textAlign: TextAlign.center))),
            if (!isLoading && errorMessage == null) _buildChartAndDetails(),
          ],
        ),
      ),
    );
  }

  Widget _buildChartAndDetails() {
    final int totalRecorded = presentCount + lateCount + absentCount;
    if (totalRecorded == 0 && !isLoading) {
      return const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 20.0), child: Text("No attendance summary data yet.")));
    }
    return Column(
      children: [
        SizedBox(
          height: 180,
          child: PieChart(
            PieChartData(
              pieTouchData: PieTouchData(touchCallback: (FlTouchEvent event, PieTouchResponse? pieTouchResponse) {
                setState(() {
                  if (!event.isInterestedForInteractions || pieTouchResponse == null || pieTouchResponse.touchedSection == null) {
                    touchedIndex = -1;
                    selectedSliceLabel = null;
                    return;
                  }
                  touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                  String label;
                  int count;
                  switch (touchedIndex) {
                    case 0:
                      label = 'Present';
                      count = presentCount;
                      break;
                    case 1:
                      label = 'Late';
                      count = lateCount;
                      break;
                    case 2:
                      label = 'Absent';
                      count = absentCount;
                      break;
                    default:
                      touchedIndex = -1;
                      selectedSliceLabel = null;
                      return;
                  }
                  _calculateDetails(label, count, totalRecorded);
                });
              }),
              borderData: FlBorderData(show: false),
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              sections: _buildChartSections(totalRecorded),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (selectedSliceLabel != null) _buildDetailsSection(),
        const SizedBox(height: 8),
        _buildLegend(),
      ],
    );
  }

  List<PieChartSectionData> _buildChartSections(int totalRecorded) {
    final List<PieChartSectionData> sections = [];
    final isTouched = (int index) => index == touchedIndex;
    final double radius = 45;
    final double enlarged = 55;

    if (presentCount > 0) {
      sections.add(PieChartSectionData(
        color: Colors.green.shade400,
        value: presentCount.toDouble(),
        title: '${((presentCount / totalRecorded) * 100).toStringAsFixed(0)}%',
        radius: isTouched(0) ? enlarged : radius,
        titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
      ));
    }
    if (lateCount > 0) {
      sections.add(PieChartSectionData(
        color: Colors.orange.shade400,
        value: lateCount.toDouble(),
        title: '${((lateCount / totalRecorded) * 100).toStringAsFixed(0)}%',
        radius: isTouched(1) ? enlarged : radius,
        titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
      ));
    }
    if (absentCount > 0) {
      sections.add(PieChartSectionData(
        color: Colors.red.shade400,
        value: absentCount.toDouble(),
        title: '${((absentCount / totalRecorded) * 100).toStringAsFixed(0)}%',
        radius: isTouched(2) ? enlarged : radius,
        titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
      ));
    }

    if (sections.isEmpty) {
      sections.add(PieChartSectionData(
        color: Colors.grey.shade300,
        value: 1,
        title: '0%',
        radius: radius,
        titleStyle: TextStyle(fontSize: 13, color: Colors.grey.shade600),
      ));
    }

    return sections;
  }

  Widget _buildDetailsSection() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 14.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Status: $selectedSliceLabel', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Percentage of Recorded: ${selectedSlicePercentage?.toStringAsFixed(1)}%', style: theme.textTheme.bodySmall),
          const Divider(height: 12, thickness: 0.5),
          Text('Target: ${(attendanceRequirement * 100).toStringAsFixed(0)}% of $totalClasses classes', style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
          const SizedBox(height: 4),
          Text('Classes Needed for Target: $remainingClassesNeeded', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _indicator(Colors.green.shade400, 'Present ($presentCount)'),
        const SizedBox(width: 12),
        _indicator(Colors.orange.shade400, 'Late ($lateCount)'),
        const SizedBox(width: 12),
        _indicator(Colors.red.shade400, 'Absent ($absentCount)'),
      ],
    );
  }

  Widget _indicator(Color color, String text) {
    return Row(
      children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 4),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

}
