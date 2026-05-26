import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TimeSeparator extends StatelessWidget {
  final DateTime time;

  const TimeSeparator({
    super.key,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.05),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _formatTime(time),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(time.year, time.month, time.day);

    final timeStr = DateFormat('HH:mm').format(time);

    if (messageDate == today) {
      return '今天 $timeStr';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return '昨天 $timeStr';
    } else if (time.year == now.year) {
      return DateFormat('M月d日 HH:mm').format(time);
    } else {
      return DateFormat('yyyy年M月d日 HH:mm').format(time);
    }
  }
}

bool shouldShowTimeSeparator(DateTime? currentMsgTime, DateTime? previousMsgTime) {
  if (currentMsgTime == null) return false;
  if (previousMsgTime == null) return true;

  final difference = currentMsgTime.difference(previousMsgTime);
  return difference.inMinutes >= 3;
}
