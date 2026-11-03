/// Formats whole rupees with Indian digit grouping, e.g. `₹15,00,000`.
String formatRupees(int amount) {
  final negative = amount < 0;
  var digits = amount.abs().toString();
  if (digits.length > 3) {
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    digits = '${groups.join(',')},$last3';
  }
  return '${negative ? '-' : ''}₹$digits';
}
