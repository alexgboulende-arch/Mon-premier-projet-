/// Formats français : dates, cotes, pourcentages, prix.
library;

const _nnbsp = ' ';

const _days = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const _daysShort = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
const _months = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];
const _monthsShort = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

String capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// « Mardi 13 octobre »
String longDate(DateTime d) => capitalize('${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}');

/// « Mar. 13 oct. »
String shortDate(DateTime d) => capitalize('${_daysShort[d.weekday - 1]} ${d.day} ${_monthsShort[d.month - 1]}');

/// « 13 octobre »
String dayMonth(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// 1.5 → « 1,50 »
String odds(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

/// 0.742 → « 74,2 % » ; avec [signed], 0.08 → « +8 % ».
String percent(double x, {bool signed = false}) {
  final v = (x * 1000).round() / 10;
  var s = v == v.roundToDouble() ? v.round().toString() : v.toString();
  s = s.replaceAll('.', ',').replaceAll('-', '−');
  return '${signed && v > 0 ? '+' : ''}$s$_nnbsp%';
}

/// 2900 → « 2 900 FCFA »
String fcfa(int n) => '${_group(n)}${_nnbsp}FCFA';

/// 4,49 → « 4,49 € »
String euros(String v) => '$v$_nnbsp€';

String _group(int n) {
  final s = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(_nnbsp);
    out.write(s[i]);
  }
  return out.toString();
}

/// 230 minutes → « 3 h 50 »
String hoursMinutes(int minutes) => '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';

/// 1263 → « 21:03 »
String clock(int minutes) =>
    '${(minutes ~/ 60 % 24).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

String plural(int n, String word) => '$n $word${n > 1 ? 's' : ''}';
