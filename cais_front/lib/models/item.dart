class AuctionItem {
  final int id;
  final String name;
  final String cat;
  final int price;
  final String customs;
  final String startDate;
  final String endDate;
  final String status;
  final String qty;
  final String wght;
  final String warehouse;
  final List<String> images;

  const AuctionItem({
    required this.id,
    required this.name,
    required this.cat,
    required this.price,
    required this.customs,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.qty = '-',
    this.wght = '-',
    this.warehouse = '-',
    this.images = const [],
  });

  DateTime get endDateTime {
    try {
      return DateTime.parse(endDate.replaceAll(' ', 'T'));
    } catch (_) {
      return DateTime.now();
    }
  }

  DateTime get endDay {
    final dt = endDateTime;
    return DateTime(dt.year, dt.month, dt.day);
  }
}
