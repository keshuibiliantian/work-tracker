import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';
import 'package:csv/csv.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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
  
  // 用于截图的 GlobalKey
  final GlobalKey _exportTableKey = GlobalKey();

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
      if (entry.key.startsWith(prefix) && entry.value['type'] == 'work') {
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
    final dataChanged = await _showDetailDialog(selectedDay);
    if (dataChanged == true) {
      setState(() => _updateMonthlyTotal());
    }
  }

  Future<bool?> _showDetailDialog(DateTime date) async {
    final dateStr = _formatDate(date);
    final existing = _workData[dateStr];
    
    String startStr = '08:00';
    String endStr = '17:00';
    String breakStr = '1.0';
    String finalHoursStr = '0.0';
    String selectedType = 'work';

    if (existing != null) {
      final hours = existing['hours'] as num;
      final type = existing['type'] as String;
      selectedType = type;
      finalHoursStr = (type == 'rest' || hours == 0) ? '0.0' : hours.toString();
    }

    return await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          double parseTime(String t) {
            if (t.isEmpty) return 0;
            final p = t.split(':');
            final h = (int.tryParse(p[0]) ?? 0) * 3600.0;
            final m = p.length > 1 ? (int.tryParse(p[1]) ?? 0) * 60.0 : 0.0;
            return h + m;
          }

          void calcHours() {
            double s = parseTime(startStr);
            double e = parseTime(endStr);
            double diff = e - s;
            if (diff < 0) diff += 86400; 
            double h = diff / 3600.0 - (double.tryParse(breakStr) ?? 0);
            finalHoursStr = h < 0 ? '0.0' : h.toStringAsFixed(1);
            setDialogState(() {});
          }

          void save() {
            final hours = double.tryParse(finalHoursStr) ?? 0.0;
            // 如果选了上班但没填时间，默认按0处理；如果选了其他状态，强制按0处理（除非手动填了）
            final realType = (selectedType == 'work' && hours > 0) ? 'work' : 
                             (selectedType == 'work' ? 'rest' : selectedType);
            final realHours = realType == 'work' ? hours : 0.0;

            _workData[dateStr] = {'type': realType, 'hours': realHours};
            _saveData();
            Navigator.pop(ctx, true);
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('${date.month}月${date.day}日 工时详情', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children:[
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: [
                      _buildRadio('上班', 'work', selectedType, setDialogState),
                      _buildRadio('休息', 'rest', selectedType, setDialogState),
                      _buildRadio('调休', 'leave', selectedType, setDialogState),
                      _buildRadio('请假', 'vacation', selectedType, setDialogState),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (selectedType == 'work') ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children:[
                          const Text('🕒 工作时间范围', style: TextStyle(fontSize: 16)),
                          Row(children:[
                            Expanded(child: _TimeInputField(initialText: startStr, onChanged: (v) => startStr = v)),
                            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('至')),
                            Expanded(child: _TimeInputField(initialText: endStr, onChanged: (v) => endStr = v)),
                          ]),
                          const SizedBox(height: 12),
                          const Text('☕ 中途休息 (小时)'),
                          _TimeInputField(initialText: breakStr, onChanged: (v) => breakStr = v, numeric: true),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity, height: 50,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEFF6FF), foregroundColor: const Color(0xFF3B82F6)),
                              onPressed: calcHours, child: const Text('计算并填入', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const Text('✍ 确认最终工时', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: InputDecoration(
                      filled: true, fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    controller: TextEditingController(text: finalHoursStr),
                    onChanged: (value) => finalHoursStr = value,
                    style: const TextStyle(fontSize: 25, color: Color(0xFF3B82F6), fontWeight: FontWeight.bold),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ],
              ),
            ),
            actions:[
              SizedBox(
                width: double.infinity, height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B82F6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: save,
                  child: const Text('确认保存', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRadio(String label, String value, String groupValue, StateSetter setState) {
    return ChoiceChip(
      label: Text(label),
      selected: groupValue == value,
      onSelected: (selected) {
        if (selected) setState(() => groupValue = value); // 这里有个闭包问题，直接改外部变量
      },
      selectedColor: const Color(0xFFDBEAFE),
      labelStyle: TextStyle(color: groupValue == value ? const Color(0xFF3B82F6) : Colors.black),
    );
  }

  Widget _buildCalendarCell(BuildContext context, DateTime day, DateTime focusedDay) {
    final dateStr = _formatDate(day);
    final isOtherMonth = day.month != focusedDay.month;
    final isToday = isSameDay(day, DateTime.now());
    final isSelected = isSameDay(day, _selectedDay);
    final data = _workData[dateStr];

    return Container(
      margin: const EdgeInsets.all(2),
      constraints: const BoxConstraints(minHeight: 60),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFDBEAFE) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isToday && !isSelected ? Border.all(color: const Color(0xFF3B82F6), width: 1.5) : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children:[
          Text('${day.day}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
              color: isOtherMonth ? const Color(0xFFCBD5E1) : isSelected ? const Color(0xFF3B82F6) : isToday ? const Color(0xFF3B82F6) : const Color(0xFF1E293B))),
          if (data != null) ...[
            const SizedBox(height: 4),
            Text(_getStatusLabel(data), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _getStatusColor(data))),
          ],
        ],
      ),
    );
  }

  String _getStatusLabel(Map<String, dynamic> data) {
    final type = data['type'] as String;
    final hours = data['hours'] as double;
    switch (type) {
      case 'work': return '${hours.toStringAsFixed(1)}h';
      case 'rest': return '○';
      case 'leave': return '△';
      case 'vacation': return '×';
      default: return '';
    }
  }

  Color _getStatusColor(Map<String, dynamic> data) {
    switch (data['type']) {
      case 'work': return const Color(0xFF10B981);
      case 'rest': return const Color(0xFF94A3B8);
      case 'leave': return const Color(0xFF64748B);
      case 'vacation': return const Color(0xFFEF4444);
      default: return Colors.transparent;
    }
  }

  // --- 导出功能 ---
  
  Future<void> _requestPermission() async {
    await Permission.storage.request();
    await Permission.manageExternalStorage.request();
  }

  Future<void> _exportAsTable() async {
    await _requestPermission();
    final year = _focusedDay.year;
    final month = _focusedDay.month;
    final lastDay = DateTime(year, month + 1, 0).day;
    
    List<List<dynamic>> rows = [];
    rows.add(['日期', '状态', '实际工作时长', '加班时长']);
    
    int totalWorkDays = 0;
    double totalHours = 0.0;

    for (int day = 1; day <= lastDay; day++) {
      final dateStr = _formatDate(DateTime(year, month, day));
      final data = _workData[dateStr];
      String status = '';
      double hours = 0.0;
      double overtime = 0.0;

      if (data != null) {
        switch (data['type']) {
          case 'work': status = '√'; hours = data['hours']; totalWorkDays++; totalHours += hours; break;
          case 'rest': status = '○'; break;
          case 'leave': status = '△'; break;
          case 'vacation': status = '×'; break;
        }
        if (hours > 8.0) overtime = hours - 8.0;
      }
      rows.add(['${day}日', status, '${hours.toStringAsFixed(1)}h', '${overtime.toStringAsFixed(1)}h']);
    }
    
    rows.add([]);
    rows.add(['统计', '出勤天数: $totalWorkDays天', '总工时: ${totalHours.toStringAsFixed(1)}h', '']);

    String csv = const ListToCsvConverter().convert(rows);
    
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/考勤表_${year}年${month}月.csv');
    // 添加 BOM 头防止 Excel 打开中文乱码
    await file.writeAsBytes([0xEF, 0xBB, 0xBF] + utf8.encode(csv));
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('表格已保存至: ${file.path}')));
      OpenFile.open(file.path);
    }
  }

  Future<void> _exportAsImage() async {
    await _requestPermission();
    try {
      // 强制渲染隐藏的表格
      await Future.delayed(const Duration(milliseconds: 500));
      
      RenderRepaintBoundary boundary = _exportTableKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();
      
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/考勤表_${_focusedDay.year}年${_focusedDay.month}月.png');
      await file.writeAsBytes(pngBytes);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('图片已保存至: ${file.path}')));
        OpenFile.open(file.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出图片失败: $e')));
      }
    }
  }

  // 构建用于截图的隐藏表格 Widget
  Widget _buildExportTableWidget() {
    final year = _focusedDay.year;
    final month = _focusedDay.month;
    final lastDay = DateTime(year, month + 1, 0).day;
    
    int totalWorkDays = 0;
    double totalHours = 0.0;

    return Container(
      width: 800,
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('考勤表格 - ${year}年${month}月', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF3B82F6))),
          const SizedBox(height: 20),
          Table(
            border: TableBorder.all(color: Colors.black, width: 1),
            columnWidths: const {
              0: FlexColumnWidth(1),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(2),
              3: FlexColumnWidth(2),
            },
            children: [
              _buildTableRow(['日期', '状态', '实际工作时长', '加班时长'], isHeader: true),
              ...List.generate(lastDay, (index) {
                final day = index + 1;
                final dateStr = _formatDate(DateTime(year, month, day));
                final data = _workData[dateStr];
                String status = '';
                double hours = 0.0;
                double overtime = 0.0;

                if (data != null) {
                  switch (data['type']) {
                    case 'work': status = '√'; hours = data['hours']; totalWorkDays++; totalHours += hours; break;
                    case 'rest': status = '○'; break;
                    case 'leave': status = '△'; break;
                    case 'vacation': status = '×'; break;
                  }
                  if (hours > 8.0) overtime = hours - 8.0;
                }
                return _buildTableRow(['${day}日', status, '${hours.toStringAsFixed(1)}h', '${overtime.toStringAsFixed(1)}h']);
              }),
              _buildTableRow(['统计', '出勤: $totalWorkDays天', '总工时: ${totalHours.toStringAsFixed(1)}h', ''], isHeader: true),
            ],
          ),
        ],
      ),
    );
  }

  TableRow _buildTableRow(List<String> cells, {bool isHeader = false}) {
    return TableRow(
      decoration: isHeader ? const BoxDecoration(color: Color(0xFFDBEAFE)) : null,
      children: cells.map((cell) {
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(cell, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: isHeader ? FontWeight.bold : FontWeight.normal)),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children:[
                Container(
                  width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: const BoxDecoration(color: Color(0xFF3B82F6)),
                  child: const Center(child: Text('记工时', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
                ),
                Expanded(
                  child: TableCalendar(
                    firstDay: DateTime.utc(2020, 1, 1), lastDay: DateTime.utc(2035, 12, 31),
                    focusedDay: _focusedDay, selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                    calendarFormat: _calendarFormat, onDaySelected: _onDaySelected,
                    onPageChanged: (focusedDay) { setState(() { _focusedDay = focusedDay; _updateMonthlyTotal(); }); },
                    locale: 'zh_CN', availableGestures: AvailableGestures.all,
                    headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true, titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    daysOfWeekStyle: const DaysOfWeekStyle(weekdayStyle: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600), weekendStyle: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
                    calendarStyle: const CalendarStyle(cellPadding: EdgeInsets.symmetric(vertical: 8)),
                    calendarBuilders: CalendarBuilders(
                      defaultBuilder: _buildCalendarCell, selectedBuilder: _buildCalendarCell,
                      todayBuilder: _buildCalendarCell, outsideBuilder: _buildCalendarCell,
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 10, 20, 10), padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)]),
                  child: Column(children:[
                    const Text('本月累计总工时', style: TextStyle(fontSize: 16, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Text('${_monthlyTotal.toStringAsFixed(1)} 小时', style: const TextStyle(color: Color(0xFF3B82F6), fontSize: 35, fontWeight: FontWeight.bold)),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(child: ElevatedButton(onPressed: _exportAsTable, style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, minimumSize: const Size(0, 48)), child: const Text('导出表格', style: TextStyle(color: Colors.white)))),
                      const SizedBox(width: 20),
                      Expanded(child: ElevatedButton(onPressed: _exportAsImage, style: ElevatedButton.styleFrom(backgroundColor: Colors.green, minimumSize: const Size(0, 48)), child: const Text('导出图片', style: TextStyle(color: Colors.white)))),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
            // 隐藏的截图区域 (放在屏幕外)
            Positioned(
              left: -9999, top: 0,
              child: RepaintBoundary(
                key: _exportTableKey,
                child: _buildExportTableWidget(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeInputField extends StatefulWidget {
  final String initialText;
  final ValueChanged<String> onChanged;
  final bool numeric;
  const _TimeInputField({required this.initialText, required this.onChanged, this.numeric = false});
  @override
  State<_TimeInputField> createState() => _TimeInputFieldState();
}

class _TimeInputFieldState extends State<_TimeInputField> {
  late TextEditingController _controller;
  @override
  void initState() { super.initState(); _controller = TextEditingController(text: widget.initialText); }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller, onChanged: widget.onChanged, textAlign: TextAlign.center,
      keyboardType: widget.numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
      style: const TextStyle(fontSize: 18),
    );
  }
}
