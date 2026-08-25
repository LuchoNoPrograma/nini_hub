import 'package:intl/intl.dart';
import 'package:nini_hub/core/currency_catalog.dart';

final _dateFormat = DateFormat('d MMM yyyy', 'es');
final _fullDateFormat = DateFormat('EEEE d MMM yyyy', 'es');
final _dateTimeFormat = DateFormat('d MMM, HH:mm', 'es');
final _monthFormat = DateFormat('MMMM yyyy', 'es');
final _integerFormat = NumberFormat.decimalPattern('es');

String formatDate(DateTime? value, {String empty = 'Sin fecha'}) =>
    value == null ? empty : _dateFormat.format(value.toLocal());

String formatFullDate(DateTime? value, {String empty = 'Sin fecha'}) {
  if (value == null) return empty;
  final result = _fullDateFormat.format(value.toLocal());
  return '${result[0].toUpperCase()}${result.substring(1)}';
}

String formatDateTime(DateTime? value, {String empty = 'Nunca'}) =>
    value == null ? empty : _dateTimeFormat.format(value.toLocal());

String formatMonth(DateTime value) {
  final result = _monthFormat.format(value.toLocal());
  return '${result[0].toUpperCase()}${result.substring(1)}';
}

String formatCompactInt(int value) {
  final absolute = value.abs();
  if (absolute < 1000) return _integerFormat.format(value);
  if (absolute < 999500) return _scaledNumber(value, 1000, 'K');
  if (absolute < 999500000) return _scaledNumber(value, 1000000, 'M');
  return _scaledNumber(value, 1000000000, 'B');
}

String formatInteger(int value) => _integerFormat.format(value);

String formatTokenDetails(int value) {
  final compact = formatCompactInt(value);
  final exact = formatInteger(value);
  if (compact == exact) return '$exact tokens';
  return '$compact tokens\n$exact tokens exactos';
}

String _scaledNumber(int value, int divisor, String suffix) {
  final scaled = value / divisor;
  final nearWhole = (scaled - scaled.roundToDouble()).abs() < .05;
  final digits = scaled.abs() >= 100 || nearWhole ? 0 : 1;
  return '${NumberFormat.decimalPatternDigits(locale: 'es', decimalDigits: digits).format(scaled)} $suffix';
}

String formatMoney(int amountMinor, String currency) {
  if (amountMinor == 0) return 'Sin importe';
  final resolvedCurrency = currencyByCode(currency);
  final amount = amountMinor / currencyMinorFactor(resolvedCurrency.code);
  return NumberFormat.currency(
    locale: 'es',
    name: resolvedCurrency.code,
    decimalDigits: resolvedCurrency.decimalDigits,
  ).format(amount);
}

String formatDurationMinutes(int? minutes) {
  if (minutes == null || minutes <= 0) return 'Ventana';
  if (minutes < 60) return '$minutes min';
  if (minutes < 1440) return '${minutes ~/ 60} h';
  return '${minutes ~/ 1440} d';
}

String formatQuotaWindowLabel(int? minutes, String windowType) {
  if (minutes == null || minutes <= 0) {
    return windowType == 'secondary' ? 'Límite secundario' : 'Límite principal';
  }
  if (minutes == 1440) return 'Límite diario';
  if (minutes >= 10080 && minutes % 10080 == 0) {
    final weeks = minutes ~/ 10080;
    return weeks == 1 ? 'Límite semanal' : 'Límite de $weeks semanas';
  }
  return 'Ventana de ${formatDurationMinutes(minutes)}';
}

String formatTimeRemaining(DateTime value, {DateTime? from}) {
  final delta = value.toLocal().difference((from ?? DateTime.now()).toLocal());
  if (delta <= Duration.zero) return 'ahora';
  final days = delta.inDays;
  final hours = delta.inHours.remainder(24);
  final minutes = delta.inMinutes.remainder(60);
  if (days > 0) return hours > 0 ? '$days d $hours h' : '$days d';
  if (hours > 0) return minutes > 0 ? '$hours h $minutes min' : '$hours h';
  return '${minutes < 1 ? 1 : minutes} min';
}

String relativeTime(DateTime? value) {
  if (value == null) return 'Nunca';
  final delta = DateTime.now().difference(value.toLocal());
  if (delta.isNegative) return formatDateTime(value);
  if (delta.inMinutes < 1) return 'Ahora';
  if (delta.inHours < 1) return 'Hace ${delta.inMinutes} min';
  if (delta.inDays < 1) return 'Hace ${delta.inHours} h';
  if (delta.inDays < 7) return 'Hace ${delta.inDays} d';
  return formatDate(value);
}
