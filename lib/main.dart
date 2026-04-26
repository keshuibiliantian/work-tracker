import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '记工时',
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN')],
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(
        fontFamily: 'sans-serif',
        colorSchemeSeed: const Color(0xFF3B82F6),
        useMaterial3: true,
      ),
      home: const WorkTrackerApp(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class WorkTrackerApp extends StatefulWidget {
  const WorkTrackerApp({super.key});

  @override
  State<WorkTrackerApp> createState() => _WorkTrackerAppState();
}

class _WorkTrackerAppState extends State<WorkTrackerApp> {
  Map<String, Map<String, dynamic>> _workData = {};
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  double _monthlyTotal = 0.0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _loadData() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/work_data.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        setState(() {
          _workData = Map<String, Map<String, dynamic>>.from(json.decode(content));
        });
      }
    } catch (_) {}
    _updateMonthlyTotal();
  }

  Future<void> _saveData() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/work_data.json');
    await file.writeAsString(json.encode(_workData));
  }

  void _updateMonthlyTotal() {
    final prefix = '${_focusedDay.year}-${_focusedDay.month.toString().padLeft(2, '0')}';
    double total = 0;
    for (var entry in _workData.entries) {
      if (entry.key.startsWith(prefix)) {
        total += (entry.value['hours'] as num).toDouble();
      }
    }
    setState(() => _monthlyTotal = total);
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) async {
    setState(() {
      _selectedDay = selectedDay;
      _focusedDay = focusedDay;
    });
    
    // ✅ 优化1：等待对话框返回结果后再刷新，移除Hack
    final result = await _showDetailDialog(selectedDay);
    if (result != null && mounted) {
      setState(() {
        _workData[_formatDate(selectedDay)] = result;
      });
      await _saveData();
      _updateMonthlyTotal();
    }
  }

  Future<Map<String, dynamic>?> _showDetailDialog(DateTime date) async {
    final dateStr = _formatDate(date);
    final existing = _workData[dateStr];
    
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => WorkDetailDialog(
        date: date,
        initialData: existing,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: const BoxDecoration(color: Color(0xFF3B82F6)),
              child: const Center(
                child: Text('记工时', 
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              ),
            ),
            Expanded(
              child: TableCalendar(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2035, 12, 31),
                focusedDay: _focusedDay,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                calendarFormat: _calendarFormat,
                onDaySelected: _onDaySelected,
                onPageChanged: (focusedDay) {
                  setState(() => _focusedDay = focusedDay);
                  _updateMonthlyTotal();
                },
                locale: 'zh_CN',
                availableGestures: AvailableGestures.all,
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false, 
                  titleCentered: true,
                  titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                daysOfWeekStyle: const DaysOfWeekStyle(
                  weekdayStyle: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                  weekendStyle: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600),
                ),
                calendarStyle: const CalendarStyle(
                  selectedDecoration: BoxDecoration(color: Color(0xFFDBEAFE), shape: BoxShape.circle),
                  selectedTextStyle: TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.bold),
                  todayDecoration: BoxDecoration(color: Color(0xFFDBEAFE), shape: BoxShape.circle),
                  todayTextStyle: TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.bold),
                  weekendTextStyle: TextStyle(color: Color(0xFF10B981)),
                  markerDecoration: BoxDecoration(),
                ),
                calendarBuilders: CalendarBuilders(
                  defaultBuilder: (context, day, focusedDay) {
                    final dateStr = _formatDate(day);
                    final isOtherMonth = day.month != focusedDay.month;
                    final isToday = isSameDay(day, DateTime.now());
                    final data = _workData[dateStr];

                    return Container(
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: isSameDay(day, _selectedDay) ? const Color(0xFFDBEAFE) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${day.day}',
                            style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold,
                              color: isOtherMonth ? const Color(0xFFCBD5E1) 
                                  : isToday ? const Color(0xFF3B82F6) 
                                  : const Color(0xFF1E293B),
                            ),
                          ),
                          if (data != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              data['type'] == 'work' && (data['hours'] as num) > 0 ? '${data['hours']}h' : '休',
                              style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600,
                                color: data['type'] == 'work' ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white, 
                borderRadius: BorderRadius.circular(20), 
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
              ),
              child: Column(
                children: [
                  const Text('本月累计总工时', style: TextStyle(fontSize: 16, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Text('${_monthlyTotal.toStringAsFixed(1)} 小时', 
                    style: const TextStyle(color: Color(0xFF3B82F6), fontSize: 35, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ✅ 优化2：改为StatefulWidget，避免Controller重复创建
class _TimeInputFieldState extends State<_TimeInputField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_TimeInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _controller.text = widget.text;
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      textAlign: TextAlign.center,
      keyboardType: widget.numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      ),
      style: const TextStyle(fontSize: 18),
    );
  }
}

class _TimeInputField extends StatefulWidget {
  final String text;
  final ValueChanged<String> onChanged;
  final bool numeric;
  
  const _TimeInputField({
    required this.text,
    required this.onChanged,
    this.numeric = false,
  });

  @override
  State<_TimeInputField> createState() => _TimeInputFieldState();
}

// 独立的对话框组件
class WorkDetailDialog extends StatefulWidget {
  final DateTime date;
  final Map<String, dynamic>? initialData;

  const WorkDetailDialog({
    super.key,
    required this.date,
    this.initialData,
  });

  @override
  State<WorkDetailDialog> createState() => _WorkDetailDialogState();
}

class _WorkDetailDialogState extends State<WorkDetailDialog> {
  late bool _isRest;
  late String _startStr;
  late String _endStr;
  late String _breakStr;
  late String _finalHoursStr;

  @override
  void initState() {
    super.initState();
    final existing = widget.initialData;
    if (existing != null) {
      _isRest = existing['type'] == 'rest';
      _finalHoursStr = _isRest ? '0.0' : (existing['hours'] as num).toString();
    } else {
      _isRest = false;
      _finalHoursStr = '0.0';
    }
    _startStr = '09:00';
    _endStr = '18:00';
    _breakStr = '1.0';
  }

  double _parseTime(String t) {
    final p = t.split(':');
    // ✅ 优化3：增强容错性，防止数组越界
    final hours = int.tryParse(p.isNotEmpty ? p[0] : '0') ?? 0;
    final minutes = int.tryParse(p.length > 1 ? p[1] : '0') ?? 0;
    return hours * 3600 + minutes * 60;
  }

  void _calculateHours() {
    double s = _parseTime(_startStr);
    double e = _parseTime(_endStr);
    double diff = e - s;
    if (diff < 0) diff += 86400;
    double h = diff / 3600.0 - (double.tryParse(_breakStr) ?? 0);
    setState(() {
      _finalHoursStr = h < 0 ? '0.0' : h.toStringAsFixed(1);
    });
  }

  void _save() {
    final result = {
      'type': _isRest ? 'rest' : 'work',
      'hours': _isRest ? 0 : (double.tryParse(_finalHoursStr) ?? 0),
    };
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('${widget.date.month}月${widget.date.day}日 工时详情', 
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Radio<bool>(value: false, groupValue: _isRest, 
                    onChanged: (v) => setState(() => _isRest = false)),
                  const Text('上班', style: TextStyle(fontSize: 18)),
                  Radio<bool>(value: true, groupValue: _isRest, 
                    onChanged: (v) => setState(() => _isRest = true)),
                  const Text('休息', style: TextStyle(fontSize: 18)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (!_isRest)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🕒 工作时间范围', style: TextStyle(fontSize: 16)),
                    Row(
                      children: [
                        Expanded(child: _TimeInputField(text: _startStr, onChanged: (v) => setState(() => _startStr = v))),
                        const SizedBox(width: 10),
                        const Text('至'),
                        const SizedBox(width: 10),
                        Expanded(child: _TimeInputField(text: _endStr, onChanged: (v) => setState(() => _endStr = v))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('☕ 中途休息 (小时)'),
                    _TimeInputField(text: _breakStr, onChanged: (v) => setState(() => _breakStr = v), numeric: true),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEFF6FF), 
                          foregroundColor: const Color(0xFF3B82F6), 
                          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        onPressed: _calculateHours,
                        child: const Text('计算并填入'),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            const Text('✍ 确认最终工时', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            TextField(
              readOnly: true,
              decoration: InputDecoration(
                filled: true, fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), 
                  borderSide: const BorderSide(color: Color(0xFF3B82F6))),
                contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              ),
              controller: TextEditingController(text: '$_finalHoursStr 小时'),
              style: const TextStyle(fontSize: 25, color: Color(0xFF3B82F6), fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6), 
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: _save,
            child: const Text('确认保存', 
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ),
      ],
    );
  }
}