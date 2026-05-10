/// Radio dayparts (EAT). Matches Laravel [IncomingController::segmentForTime] and portal filters.
class ShowSegmentUtils {
  ShowSegmentUtils._();

  static const morning = 'Morning show';
  static const afternoon = 'Afternoon show';
  static const evening = 'Evening show';
  static const night = 'Night show';

  static const allLabels = [morning, afternoon, evening, night];

  /// Uses the device's local clock (studio handset should be set to Tanzania / EAT).
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
