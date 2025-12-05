import 'package:flutter/material.dart';

import '../services/history_manager.dart';
import '../widgets/mini_player.dart';

/// 打卡日历页面
class CalendarPage extends StatefulWidget {
  final int dailyGoal;

  const CalendarPage({super.key, required this.dailyGoal});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  Map<String, int> _dateMinutes = {}; // date -> minutes
  bool _loading = true;
  DateTime _selectedMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadCalendarData();
  }

  Future<void> _loadCalendarData() async {
    setState(() => _loading = true);
    final historyByDate = await HistoryManager.getHistoryByDate();
    final dateMinutes = <String, int>{};

    for (final entry in historyByDate.entries) {
      final totalSeconds = entry.value.fold<int>(
        0,
        (sum, h) => sum + h.durationSeconds,
      );
      dateMinutes[entry.key] = (totalSeconds / 60).floor();
    }

    setState(() {
      _dateMinutes = dateMinutes;
      _loading = false;
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
        1,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('打卡日历'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('说明'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('已达标'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.orange[300],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('未达标（有播放）'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('未播放'),
                        ],
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('确定'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 月份选择器
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => _changeMonth(-1),
                      ),
                      Text(
                        '${_selectedMonth.year}年${_selectedMonth.month}月',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => _changeMonth(1),
                      ),
                    ],
                  ),
                ),
                // 星期标题
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: ['日', '一', '二', '三', '四', '五', '六']
                        .map(
                          (day) => Expanded(
                            child: Center(
                              child: Text(
                                day,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 8),
                // 日历网格
                Expanded(child: _buildCalendarGrid()),
                // 统计信息
                _buildStatistics(),
              ],
            ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }

  Widget _buildCalendarGrid() {
    final firstDay = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final lastDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final daysInMonth = lastDay.day;
    final firstWeekday = firstDay.weekday == 7 ? 0 : firstDay.weekday;

    final List<Widget> dayWidgets = [];

    // 填充月初空白
    for (int i = 0; i < firstWeekday; i++) {
      dayWidgets.add(Container());
    }

    // 填充每一天
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_selectedMonth.year, _selectedMonth.month, day);
      final dateKey =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final minutes = _dateMinutes[dateKey] ?? 0;
      final reached = minutes >= widget.dailyGoal;

      final isToday =
          DateTime.now().year == date.year &&
          DateTime.now().month == date.month &&
          DateTime.now().day == date.day;

      Color bgColor;
      if (minutes == 0) {
        bgColor = Colors.grey[300]!;
      } else if (reached) {
        bgColor = Colors.green;
      } else {
        bgColor = Colors.orange[300]!;
      }

      dayWidgets.add(
        GestureDetector(
          onTap: minutes > 0
              ? () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('$day日'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('播放时长：$minutes 分钟'),
                          Text('目标：${widget.dailyGoal} 分钟'),
                          const SizedBox(height: 8),
                          Text(
                            reached ? '✅ 已达标' : '⏳ 未达标',
                            style: TextStyle(
                              color: reached ? Colors.green : Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('确定'),
                        ),
                      ],
                    ),
                  );
                }
              : null,
          child: Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              border: isToday ? Border.all(color: Colors.blue, width: 2) : null,
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$day',
                    style: TextStyle(
                      color: minutes > 0 ? Colors.white : Colors.grey[600],
                      fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  if (minutes > 0)
                    Text(
                      '$minutes\'',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 7,
      padding: const EdgeInsets.all(8),
      children: dayWidgets,
    );
  }

  Widget _buildStatistics() {
    final monthDays = _dateMinutes.entries.where((entry) {
      final date = DateTime.parse(entry.key);
      return date.year == _selectedMonth.year &&
          date.month == _selectedMonth.month;
    }).toList();

    final totalMinutes = monthDays.fold<int>(0, (sum, e) => sum + e.value);
    final reachedDays = monthDays
        .where((e) => e.value >= widget.dailyGoal)
        .length;
    final playedDays = monthDays.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('本月已播放', '$playedDays 天'),
              _buildStatItem('已达标', '$reachedDays 天'),
              _buildStatItem('总时长', '$totalMinutes 分钟'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}
