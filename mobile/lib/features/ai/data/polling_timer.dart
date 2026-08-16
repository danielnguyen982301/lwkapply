import 'dart:async';

/// A small, non-Riverpod polling helper wrapping [Timer.periodic].
/// Shared by ResumeAnalysisDetailController/AtsScoreDetailController —
/// both need the exact same "poll every few seconds, give up after a
/// cap" bookkeeping, kept here once rather than duplicated twice.
/// Deliberately not in `core/` — AI is the only current consumer, and
/// this codebase avoids generalizing before a second consumer actually
/// exists.
///
/// Interval/attempt cap match
/// webapp/src/stores/resumeAnalyses.ts's constants exactly, so polling
/// behavior is consistent across clients: 3s interval, 40 attempts
/// (~2 minutes) before giving up.
class PollingTimer {
  Timer? _handle;
  int _attempts = 0;

  static const _interval = Duration(seconds: 3);
  static const _maxAttempts = 40;

  bool get isActive => _handle != null;

  /// Starts polling: calls [onTick] every 3 seconds. [onTick] owns
  /// deciding when polling is actually done — it's responsible for
  /// calling [stop] itself once it observes a terminal status; this
  /// class has no opinion on what "done" means for the caller's data.
  /// If [onTick] hasn't stopped the timer within 40 attempts, polling
  /// stops itself and calls [onTimeout] instead.
  void start({
    required Future<void> Function() onTick,
    required void Function() onTimeout,
  }) {
    stop();
    _attempts = 0;
    _handle = Timer.periodic(_interval, (_) {
      _attempts += 1;
      if (_attempts > _maxAttempts) {
        stop();
        onTimeout();
        return;
      }
      onTick();
    });
  }

  void stop() {
    _handle?.cancel();
    _handle = null;
    _attempts = 0;
  }
}
