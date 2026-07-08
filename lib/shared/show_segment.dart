/// Daypart buckets (EAT). Matches Laravel IncomingController::segmentForTime.
class ShowSegmentUtils {
  ShowSegmentUtils._();

  static const morning = 'Morning period';
  static const afternoon = 'Afternoon period';
  static const evening = 'Evening period';
  static const night = 'Night period';

  static const allLabels = [morning, afternoon, evening, night];

  static String labelForLocal(DateTime dt) {
    final minutes = dt.hour * 60 + dt.minute;
    if (minutes >= 360 && minutes < 720) {
      return morning;
    }
    if (minutes >= 720 && minutes < 1080) {
      return afternoon;
    }
    if (minutes >= 1080 && minutes < 1320) {
      return evening;
    }
    return night;
  }
}
