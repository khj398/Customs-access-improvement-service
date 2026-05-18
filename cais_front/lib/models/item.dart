class AuctionItem {
  final int id;
  final String pbacNoStr; // 원본 공매번호 문자열 (앞자리 0 보존)
  final int pbacSrno;     // 공매회차
  final int cmdtLnNo;     // 물품연번
  final String name;
  final String cat;
  final int price;
  final String customs;
  final String cstmSgn;
  final String startDate;
  final String endDate;
  final String status;
  final String qty;
  final String wght;
  final String warehouse;
  final List<String> images;

  const AuctionItem({
    required this.id,
    required this.pbacNoStr,
    required this.pbacSrno,
    required this.cmdtLnNo,
    required this.name,
    required this.cat,
    required this.price,
    required this.customs,
    this.cstmSgn = '',
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
    String? tempStatus;
    try {
      tempStatus =
          DateTime.parse(endDate.replaceAll(' ', 'T')).isAfter(DateTime.now())
          ? '진행중'
          : '마감';
    } catch (_) {}
    final status = tempStatus ?? '마감';

    final qty = json['cmdtQty'] != null
        ? '${json['cmdtQty']} ${json['cmdtQtyUtCd'] ?? ''}'.trim()
        : '-';
    final wght = json['cmdtWght'] != null
        ? '${json['cmdtWght']} ${json['cmdtWghtUtCd'] ?? ''}'.trim()
        : '-';

    final pbacNoStr = (json['pbacNo'] ?? '').toString();

    return AuctionItem(
      id: int.tryParse(pbacNoStr) ?? 0,
      pbacNoStr: pbacNoStr,
      pbacSrno: _toInt(json['pbacSrno']),
      cmdtLnNo: _toInt(json['cmdtLnNo']),
      name: json['cmdtNm'] ?? '',
      cat: json['categoryName'] ?? '기타',
      price: (json['pbacPrngPrc'] is num)
          ? (json['pbacPrngPrc'] as num).toInt()
          : int.tryParse((json['pbacPrngPrc'] ?? '0').toString()) ?? 0,
      customs: json['cstmName'] ?? '',
      cstmSgn: (json['cstmSgn'] ?? '').toString(),
      startDate: (json['pbacStrtDttm'] ?? '').toString(),
      endDate: endDate,
      status: status,
      qty: qty,
      wght: wght,
      warehouse: json['snarName'] ?? '-',
      images: (json['imageUrls'] as String?)
              ?.split('|')
              .where((s) => s.isNotEmpty)
              .toList() ??
          const [],
    );
  }

  static int _toInt(dynamic v) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

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

  /// DB의 (pbacNo, pbacSrno, cmdtLnNo) 복합키를 단일 문자열로 표현
  String get likeKey => '${pbacNoStr}_${pbacSrno}_$cmdtLnNo';
}
