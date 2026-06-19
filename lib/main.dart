import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

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

// 定义工作类型枚举
enum WorkType { work, rest, leave, vacation }

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
    setState(() {
      _monthlyTotal = total;
    });
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) async {
    setState(() {
      _selectedDay = selectedDay;
      _focusedDay = focusedDay;
    });
    
    final dataChanged = await _showDetailDialog(selectedDay);
    
    if (dataChanged == true) {
      setState(() {
        _updateMonthlyTotal();
      });
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
      if (type == 'rest' || hours == 0) {
        finalHoursStr = '0.0';
        selectedType = 'rest';
      } else {
        finalHoursStr = hours.toString();
        selectedType = type;
      }
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
            
            _workData[dateStr] = {
              'type': selectedType,
              'hours': hours,
            };
            _saveData();
            Navigator.pop(ctx, true);
          }

          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('${date.month}月${date.day}日 工时详情', 
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children:[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children:[
                        Radio<String>(value: 'work', groupValue: selectedType, 
                          onChanged: (v) => setDialogState(() => selectedType = 'work')),
                        const Text('上班', style: TextStyle(fontSize: 18)),
                        Radio<String>(value: 'rest', groupValue: selectedType, 
                          onChanged: (v) => setDialogState(() => selectedType = 'rest')),
                        const Text('休息', style: TextStyle(fontSize: 18)),
                        Radio<String>(value: 'leave', groupValue: selectedType, 
                          onChanged: (v) => setDialogState(() => selectedType = 'leave')),
                        const Text('调休', style: TextStyle(fontSize: 18)),
                        Radio<String>(value: 'vacation', groupValue: selectedType, 
                          onChanged: (v) => setDialogState(() => selectedType = 'vacation')),
                        const Text('请假', style: TextStyle(fontSize: 18)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:[
                        const Text('🕒 工作时间范围（可选计算）', style: TextStyle(fontSize: 16)),
                        Row(
                          children:[
                            Expanded(child: _TimeInputField(initialText: startStr, onChanged: (v) => startStr = v)),
                            const SizedBox(width: 10),
                            const Text('至'),
                            const SizedBox(width: 10),
                            Expanded(child: _TimeInputField(initialText: endStr, onChanged: (v) => endStr = v)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text('☕ 中途休息 (小时)'),
                        _TimeInputField(initialText: breakStr, onChanged: (v) => breakStr = v, numeric: true),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEFF6FF), 
                              foregroundColor: const Color(0xFF3B82F6), 
                              textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            onPressed: calcHours,
                            child: const Text('计算并填入'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('或直接手动输入下方工时', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('✍ 确认最终工时', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: InputDecoration(
                      filled: true, fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), 
                        borderSide: const BorderSide(color: Color(0xFF3B82F6))),
                      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                    ),
                    controller: TextEditingController(text: finalHoursStr),
                    onChanged: (value) {
                      finalHoursStr = value;
                    },
                    style: const TextStyle(fontSize: 25, color: Color(0xFF3B82F6), fontWeight: FontWeight.bold),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 4),
                  const Text('小时（输入0表示休息）', style: TextStyle(fontSize: 14, color: Colors.grey)),
                ],
              ),
            ),
            actions:[
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6), 
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: save,
                  child: const Text('确认保存', 
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
          );
        },
      ),
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
          Text(
            '${day.day}',
            style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold,
              color: isOtherMonth ? const Color(0xFFCBD5E1) 
                  : isSelected ? const Color(0xFF3B82F6) 
                  : isToday ? const Color(0xFF3B82F6) 
                  : const Color(0xFF1E293B),
            ),
          ),
          if (data != null) ...[
            const SizedBox(height: 4),
            Text(
              _getStatusLabel(data),
              style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: _getStatusColor(data),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getStatusLabel(Map<String, dynamic> data) {
    final type = data['type'] as String;
    final hours = data['hours'] as double;
    
    switch (type) {
      case 'work':
        return '${hours.toStringAsFixed(1)}h';
      case 'rest':
        return '○';
      case 'leave':
        return '△';
      case 'vacation':
        return '×';
      default:
        return '';
    }
  }

  Color _getStatusColor(Map<String, dynamic> data) {
    final type = data['type'] as String;
    
    switch (type) {
      case 'work':
        return const Color(0xFF10B981);
      case 'rest':
        return const Color(0xFF94A3B8);
      case 'leave':
        return const Color(0xFF64748B);
      case 'vacation':
        return const Color(0xEF4444);
      default:
        return Colors.transparent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: Column(
          children:[
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
                  setState(() {
                    _focusedDay = focusedDay;
                    _updateMonthlyTotal();
                  });
                },
                locale: 'zh_CN',
                availableGestures: AvailableGestures.all,
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false, 
                  titleCentered: true,
                  titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  headerPadding: EdgeInsets.symmetric(vertical: 12),
                ),
                daysOfWeekStyle: const DaysOfWeekStyle(
                  weekdayStyle: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600, fontSize: 14),
                  weekendStyle: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600, fontSize: 14),
                ),
                calendarStyle: const CalendarStyle(
                  cellPadding: EdgeInsets.symmetric(vertical: 8),
                ),
                
                calendarBuilders: CalendarBuilders(
                  defaultBuilder: _buildCalendarCell,
                  selectedBuilder: _buildCalendarCell,
                  todayBuilder: _buildCalendarCell,
                  outsideBuilder: _buildCalendarCell,
                ),
                
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white, 
                borderRadius: BorderRadius.circular(20), 
                boxShadow: const[BoxShadow(color: Colors.black12, blurRadius: 10)],
              ),
              child: Column(
                children:[
                  const Text('本月累计总工时', style: TextStyle(fontSize: 16, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Text('${_monthlyTotal.toStringAsFixed(1)} 小时', 
                    style: const TextStyle(color: Color(0xFF3B82F6), fontSize: 35, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            // 导出按钮
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () => _exportAsTable(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      minimumSize: const Size(120, 48),
                    ),
                    child: const Text('导出表格', style: TextStyle(fontSize: 16)),
                  ),
                  ElevatedButton(
                    onPressed: () => _exportAsImage(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      minimumSize: const Size(120, 48),
                    ),
                    child: const Text('导出图片', style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 导出为Excel表格
  Future<void> _exportAsTable() async {
    try {
      // 1. 获取当前月份数据
      final currentDate = DateTime.now();
      final year = currentDate.year;
      final month = currentDate.month;
      final lastDay = DateTime(year, month + 1, 0).day;
      
      // 2. 创建Excel工作簿
      var excel = Excel.createExcel();
      var sheet = excel.worksheets[0];
      
      // 3. 设置表头
      sheet.cell(CellIndex.indexFromA1('A1')).value = '日期';
      sheet.cell(CellIndex.indexFromA1('B1')).value = '状态';
      sheet.cell(CellIndex.indexFromA1('C1')).value = '实际工作时长';
      sheet.cell(CellIndex.indexFromA1('D1')).value = '加班时长';
      
      // 4. 填充数据
      int totalWorkDays = 0;
      double totalHours = 0.0;
      
      for (int day = 1; day <= lastDay; day++) {
        final date = DateTime(year, month, day);
        final dateStr = _formatDate(date);
        final data = _workData[dateStr];
        final row = day + 1;
        
        // 日期
        sheet.cell(CellIndex.indexFromA1('A$day')).value = '${day}日';
        
        // 状态
        if (data != null) {
          String statusSymbol;
          switch (data['type']) {
            case 'work': statusSymbol = '√'; break;
            case 'rest': statusSymbol = '○'; break;
            case 'leave': statusSymbol = '△'; break;
            case 'vacation': statusSymbol = '×'; break;
            default: statusSymbol = '';
          }
          sheet.cell(CellIndex.indexFromA1('B$day')).value = statusSymbol;
          
          // 工作时长
          final hours = data['hours'] as double;
          sheet.cell(CellIndex.indexFromA1('C$day')).value = '${hours}h';
          
          // 加班时长
          final overtime = (hours > 8.0) ? (hours - 8.0) : 0.0;
          sheet.cell(CellIndex.indexFromA1('D$day')).value = '${overtime}h';
          
          // 统计
          if (data['type'] == 'work') {
            totalWorkDays++;
            totalHours += hours;
          }
        } else {
          sheet.cell(CellIndex.indexFromA1('B$day')).value = '';
          sheet.cell(CellIndex.indexFromA1('C$day')).value = '0.0h';
          sheet.cell(CellIndex.indexFromA1('D$day')).value = '0.0h';
        }
      }
      
      // 5. 添加统计行
      final totalRow = lastDay + 2;
      sheet.cell(CellIndex.indexFromA1('C$totalRow')).value = '出勤天数';
      sheet.cell(CellIndex.indexFromA1('D$totalRow')).value = '总工时';
      
      sheet.cell(CellIndex.indexFromA1('C${totalRow + 1}')).value = totalWorkDays;
      sheet.cell(CellIndex.indexFromA1('D${totalRow + 1}')).value = '${totalHours}h';
      
      // 6. 保存文件
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'attendance_${year}_${month}.xlsx';
      final filePath = '${dir.path}/$fileName';
      final bytes = excel.save();
      File(filePath).writeAsBytesSync(bytes);
      
      // 7. 提示用户
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('考勤表格导出成功！文件已保存至: $fileName')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出表格失败: $e')),
      );
    }
  }

  // 导出为图片
  Future<void> _exportAsImage() async {
    try {
      // 1. 获取当前月份数据
      final currentDate = DateTime.now();
      final year = currentDate.year;
      final month = currentDate.month;
      final lastDay = DateTime(year, month + 1, 0).day;
      
      // 2. 创建图片
      final imageWidth = 800;
      final imageHeight = 500 + (lastDay * 30);
      final image = img.Image(imageWidth, imageHeight);
      
      // 3. 绘制背景
      img.fill(image, const img.Color(0xFFFFFFFF));
      
      // 4. 绘制标题
      _drawText(image, '考勤表格 - ${year}年${month}月', 400, 40, 
        fontSize: 24, color: img.Color(0xFF3B82F6), align: 'center');
      
      // 5. 绘制表格
      final tableTop = 70;
      final cellHeight = 30;
      final cellWidth = imageWidth / 4;
      
      // 绘制表头
      _drawCell(image, '日期', 0, tableTop, cellWidth, cellHeight, 
        backgroundColor: img.Color(0xFF3B82F6), textColor: img.Color(0xFFFFFFFF));
      _drawCell(image, '状态', cellWidth, tableTop, cellWidth, cellHeight, 
        backgroundColor: img.Color(0xFF3B82F6), textColor: img.Color(0xFFFFFFFF));
      _drawCell(image, '实际工作时长', 2 * cellWidth, tableTop, cellWidth, cellHeight, 
        backgroundColor: img.Color(0xFF3B82F6), textColor: img.Color(0xFFFFFFFF));
      _drawCell(image, '加班时长', 3 * cellWidth, tableTop, cellWidth, cellHeight, 
        backgroundColor: img.Color(0xFF3B82F6), textColor: img.Color(0xFFFFFFFF));
      
      // 绘制数据行
      for (int day = 1; day <= lastDay; day++) {
        final date = DateTime(year, month, day);
        final dateStr = _formatDate(date);
        final data = _workData[dateStr] ?? {'type': 'work', 'hours': 0.0};
        final hours = data['hours'] as double;
        final overtime = (hours > 8.0) ? (hours - 8.0) : 0.0;
        
        String statusSymbol;
        switch (data['type']) {
          case 'work': statusSymbol = '√'; break;
          case 'rest': statusSymbol = '○'; break;
          case 'leave': statusSymbol = '△'; break;
          case 'vacation': statusSymbol = '×'; break;
          default: statusSymbol = '';
        }
        
        final rowTop = tableTop + cellHeight + (day - 1) * cellHeight;
        
        _drawCell(image, '${day}日', 0, rowTop, cellWidth, cellHeight);
        _drawCell(image, statusSymbol, cellWidth, rowTop, cellWidth, cellHeight);
        _drawCell(image, '${hours}h', 2 * cellWidth, rowTop, cellWidth, cellHeight);
        _drawCell(image, '${overtime}h', 3 * cellWidth, rowTop, cellWidth, cellHeight);
      }
      
      // 6. 绘制统计行
      final statsTop = tableTop + cellHeight + lastDay * cellHeight + 10;
      _drawCell(image, '', 0, statsTop, 2 * cellWidth, cellHeight);
      _drawCell(image, '出勤天数', 2 * cellWidth, statsTop, cellWidth, cellHeight);
      _drawCell(image, '总工时', 3 * cellWidth, statsTop, cellWidth, cellHeight);
      
      final statsTop2 = statsTop + cellHeight;
      _drawCell(image, '', 0, statsTop2, 2 * cellWidth, cellHeight);
      _drawCell(image, _getTotalWorkDays().toString(), 2 * cellWidth, statsTop2, cellWidth, cellHeight);
      _drawCell(image, '${_getTotalHours()}h', 3 * cellWidth, statsTop2, cellWidth, cellHeight);
      
      // 7. 保存图片
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'attendance_${year}_${month}.png';
      final filePath = '${dir.path}/$fileName';
      File(filePath).writeAsBytesSync(img.encodePng(image));
      
      // 8. 提示用户
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('考勤图片导出成功！文件已保存至: $fileName')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出图片失败: $e')),
      );
    }
  }
  
  // 辅助方法：绘制表格单元格
  void _drawCell(img.Image image, String text, double x, double y, double width, double height,
      {img.Color? backgroundColor, img.Color? textColor}) {
    // 绘制背景
    if (backgroundColor != null) {
      img.fillRect(image, 
        x.toInt(), y.toInt(), width.toInt(), height.toInt(),
        backgroundColor);
    }
    
    // 绘制边框
    img.drawRoundedRect(image, 
      x.toInt(), y.toInt(), width.toInt(), height.toInt(),
      2, img.Color(0xFF000000));
    
    // 绘制文本
    _drawText(image, text, x + width / 2, y + height / 2, 
      fontSize: 12, color: textColor ?? img.Color(0xFF000000), align: 'center');
  }
  
  // 辅助方法：绘制文本
  void _drawText(img.Image image, String text, double x, double y, 
      {double fontSize = 12, img.Color color = const img.Color(0xFF000000), String align = 'center'}) {
    final font = img.Font.ubuntu();
    final textWidth = font.widthOf(text) * fontSize / 12;
    
    if (align == 'center') {
      x -= textWidth / 2;
    } else if (align == 'right') {
      x -= textWidth;
    }
    
    img.drawString(image, font, x.toInt(), y.toInt(), 
      text, 
      fontSize: fontSize, 
      color: color);
  }
  
  // 获取总出勤天数
  int _getTotalWorkDays() {
    final currentDate = DateTime.now();
    final year = currentDate.year;
    final month = currentDate.month;
    final lastDay = DateTime(year, month + 1, 0).day;
    
    int count = 0;
    for (int day = 1; day <= lastDay; day++) {
      final date = DateTime(year, month, day);
      final dateStr = _formatDate(date);
      final data = _workData[dateStr];
      if (data != null && data['type'] == 'work') {
        count++;
      }
    }
    return count;
  }
  
  // 获取总工时
  double _getTotalHours() {
    final currentDate = DateTime.now();
    final year = currentDate.year;
    final month = currentDate.month;
    final lastDay = DateTime(year, month + 1, 0).day;
    
    double total = 0;
    for (int day = 1; day <= lastDay; day++) {
      final date = DateTime(year, month, day);
      final dateStr = _formatDate(date);
      final data = _workData[dateStr];
      if (data != null && data['type'] == 'work') {
        total += data['hours'] as double;
      }
    }
    return total;
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
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
