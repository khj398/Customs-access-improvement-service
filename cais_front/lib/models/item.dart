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

  factory AuctionItem.fromJson(Map<String, dynamic> json) {
    final endDate = (json['pbacEndDttm'] ?? '').toString();
    final String status;
    try {
      status = DateTime.parse(endDate.replaceAll(' ', 'T')).isAfter(DateTime.now())
          ? '진행중'
          : '마감';
    } catch (_) {
      status = '마감';
    }

    final qty = json['cmdtQty'] != null
        ? '${json['cmdtQty']} ${json['cmdtQtyUtCd'] ?? ''}'.trim()
        : '-';
    final wght = json['cmdtWght'] != null
        ? '${json['cmdtWght']} ${json['cmdtWghtUtCd'] ?? ''}'.trim()
        : '-';

    return AuctionItem(
      id: (json['pbacNo'] as num?)?.toInt() ?? 0,
      name: json['cmdtNm'] ?? '',
      cat: json['categoryName'] ?? '기타',
      price: (json['pbacPrngPrc'] as num?)?.toInt() ?? 0,
      customs: json['cstmName'] ?? '',
      startDate: (json['pbacStrtDttm'] ?? '').toString(),
      endDate: endDate,
      status: status,
      qty: qty,
      wght: wght,
      warehouse: json['snarName'] ?? '-',
      images: const [],
    );
  }

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
