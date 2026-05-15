String formatPrice(int price) {
  if (price >= 100000000) return '${(price / 100000000).round()}억원';
  if (price >= 10000) return '${(price / 10000).toStringAsFixed(0)}만원';
  return _commas(price) + '원';
}

String formatPriceFull(int price) => _commas(price) + '원';

String _commas(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
