import '../models/audio_note.dart';

class UsageStats {
  const UsageStats({
    required this.minutesThisMonth,
    required this.monthlyGoalMinutes,
    required this.estimatedApiCostUsd,
    required this.notesThisMonth,
  });

  final double minutesThisMonth;
  final int monthlyGoalMinutes;
  final double estimatedApiCostUsd;
  final int notesThisMonth;

  double get progress =>
      monthlyGoalMinutes <= 0 ? 0 : minutesThisMonth / monthlyGoalMinutes;

  int get progressPercent => (progress.clamp(0.0, 1.0) * 100).round();
}

class UsageStatsService {
  UsageStatsService._();

  static const int defaultMonthlyGoalMinutes = 120;

  /// Stima indicativa: ~\$0.003/min (trascrizione + riepilogo via OpenRouter).
  static const double _costPerMinuteUsd = 0.003;

  static UsageStats compute(List<AudioNote> notes) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);

    final monthNotes = notes.where((n) => !n.dateTime.isBefore(monthStart));
    final totalSeconds = monthNotes.fold<int>(
      0,
      (sum, n) => sum + n.durationSeconds,
    );
    final minutes = totalSeconds / 60.0;

    return UsageStats(
      minutesThisMonth: minutes,
      monthlyGoalMinutes: defaultMonthlyGoalMinutes,
      estimatedApiCostUsd: minutes * _costPerMinuteUsd,
      notesThisMonth: monthNotes.length,
    );
  }
}
