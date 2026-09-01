abstract interface class Clock {
  DateTime now();
}

final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

String formatUtcIsoSeconds(DateTime value) {
  final utc = value.toUtc();
  return '${_fourDigits(utc.year)}-${_twoDigits(utc.month)}-'
      '${_twoDigits(utc.day)}T${_twoDigits(utc.hour)}:'
      '${_twoDigits(utc.minute)}:${_twoDigits(utc.second)}Z';
}

String formatLocalDate(DateTime value) {
  return '${_fourDigits(value.year)}-${_twoDigits(value.month)}-'
      '${_twoDigits(value.day)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String _fourDigits(int value) => value.toString().padLeft(4, '0');
