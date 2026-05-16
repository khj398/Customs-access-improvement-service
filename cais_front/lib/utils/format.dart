/// 공매번호를 '041-26-01-900014-1' 형식으로 변환 (3-2-2-6-1)
String formatPbacNo(String raw) {
  final s = raw.padLeft(14, '0');
  if (s.length < 14) return raw;
  return '${s.substring(0, 3)}-${s.substring(3, 5)}-'
      '${s.substring(5, 7)}-${s.substring(7, 13)}-${s.substring(13)}';
}

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
