import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/auction_item.dart';
import '../services/api_service.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({Key? key}) : super(key: key);

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  bool _isFavorite = false;
  String? _hoveredLabel;

  AuctionItem? _item;
  bool _isLoading = true;
  String? _errorMessage;

  final Map<String, String> termDefinitions = {
    '세관명': '해당 물품을 관할하는 세관의 이름입니다. 공매 물품의 통관 처리를 담당하는 기관입니다.',
    '차수': '한 년도 내에서 진행되는 공매의 순서입니다. 예: 2026-01차는 2026년 첫 번째 공매를 의미합니다.',
    '회수': '한 번의 공매 행사 내에서 진행되는 회차입니다. 여러 회차로 나누어 공매가 진행될 수 있습니다.',
    '물품명': '공매에 나오는 물품의 이름이나 품목입니다.',
    '수량': '공매에 나오는 물품의 개수 또는 단위입니다.',
    '중량': '공매 물품의 무게입니다.',
    '공매예정가격': '세관에서 책정한 공매 물품의 예상 가격입니다. 입찰자들은 이 가격을 기준으로 입찰을 진행합니다.',
    '보세구역': '통관 전 물품을 임시 보관하는 지역입니다. 공매 물품이 현재 보관 중인 장소입니다.',
    '공매시작일시': '공매 입찰이 시작되는 날짜와 시간입니다. 이 시점부터 입찰에 참여할 수 있습니다.',
    '공매종료일시': '공매 입찰이 종료되는 날짜와 시간입니다. 이 시간 이후에는 입찰을 할 수 없습니다.',
    '분류': '시스템이 자동 분류한 물품 카테고리입니다.',
  };

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    // 이전 화면에서 AuctionItem을 arguments로 전달받음
    final passed = Get.arguments;
    if (passed is AuctionItem) {
      setState(() {
        _item = passed;
        _isFavorite = passed.isFavorite;
        _isLoading = false;
      });
      // 더 상세한 정보(보세구역 등)를 위해 API 재조회
      _refetchDetail(passed.pbacNo, passed.pbacSrno, passed.cmdtLnNo);
    } else {
      // arguments가 없으면 오류 표시
      setState(() {
        _errorMessage = '물품 정보가 전달되지 않았습니다.';
        _isLoading = false;
      });
    }
  }

  Future<void> _refetchDetail(String pbacNo, String pbacSrno, String cmdtLnNo) async {
    try {
      final detail = await ApiService.fetchItemDetail(pbacNo, pbacSrno, cmdtLnNo);
      if (mounted) {
        setState(() {
          detail.isFavorite = _isFavorite;
          _item = detail;
        });
      }
    } catch (_) {
      // 재조회 실패 시 전달받은 데이터 그대로 유지
    }
  }

  Future<void> _toggleFavorite() async {
    if (!ApiService.isLoggedIn) {
      Get.snackbar('로그인 필요', '찜하려면 로그인이 필요합니다',
          backgroundColor: Colors.orange, colorText: Colors.white);
      return;
    }
    final item = _item!;
    try {
      final nowLiked = await ApiService.toggleLike(
          item.pbacNo, item.pbacSrno, item.cmdtLnNo);
      if (mounted) setState(() => _isFavorite = nowLiked);
    } catch (e) {
      Get.snackbar('오류', e.toString().replaceFirst('Exception: ', ''),
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text(_errorMessage!, style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: () => Get.back(), child: const Text('돌아가기')),
                    ],
                  ),
                )
              : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final item = _item!;
    return Stack(
      children: [
        SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 상단 이미지 영역 (실 이미지 없으므로 아이콘 배경)
              Container(
                width: double.infinity,
                height: MediaQuery.of(context).size.height * 0.45,
                color: const Color(0xFFE8E8E8),
                child: const Center(
                  child: Icon(Icons.inventory_2_outlined, size: 80, color: Color(0xFFB0B3B8)),
                ),
              ),
              // 상세 정보 카드
              Transform.translate(
                offset: const Offset(0, -30),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 15,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 카테고리 + 물품명
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.categoryName ?? item.cstmName ?? '',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF3B82F6),
                              fontFamily: 'Noto Sans KR',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.cmdtNm,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1a1a2e),
                              fontFamily: 'Noto Sans KR',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // 공매예정가격 + 공매 상태
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'CURRENT PRICE',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFB0B0B8),
                                  fontFamily: 'Noto Sans KR',
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.pbacPrngPrc != null
                                    ? _formatPrice(item.pbacPrngPrc!)
                                    : '가격 미정',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF3B82F6),
                                  fontFamily: 'Noto Sans KR',
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'STATUS',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFB0B0B8),
                                  fontFamily: 'Noto Sans KR',
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.schedule,
                                    size: 16,
                                    color: item.isExpired
                                        ? Colors.grey
                                        : const Color(0xFF10B981),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    item.isExpired ? '종료됨' : '진행중',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: item.isExpired
                                          ? Colors.grey
                                          : const Color(0xFF10B981),
                                      fontFamily: 'Noto Sans KR',
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Lot Information 섹션
                      Row(
                        children: [
                          Container(
                            width: 4,
                            height: 20,
                            color: const Color(0xFF3B82F6),
                            margin: const EdgeInsets.only(right: 8),
                          ),
                          const Text(
                            'Lot Information',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1a1a2e),
                              fontFamily: 'Noto Sans KR',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow('세관명', item.cstmName ?? '-'),
                      _buildInfoRow('물품명', item.cmdtNm),
                      _buildInfoRow(
                        '수량',
                        item.cmdtQty != null
                            ? '${item.cmdtQty!.toStringAsFixed(item.cmdtQty! % 1 == 0 ? 0 : 2)} ${item.cmdtQtyUtCd ?? ''}'
                            : '-',
                      ),
                      _buildInfoRow(
                        '중량',
                        item.cmdtWght != null
                            ? '${item.cmdtWght!.toStringAsFixed(2)} ${item.cmdtWghtUtCd ?? ''}'
                            : '-',
                      ),
                      _buildInfoRow(
                        '공매예정가격',
                        item.pbacPrngPrc != null ? _formatPrice(item.pbacPrngPrc!) : '-',
                      ),
                      _buildInfoRow('보세구역', item.snarName ?? '-'),
                      _buildInfoRow('분류', item.categoryName ?? '-'),
                      _buildInfoRowWithHover(
                        '공매시작일시',
                        item.pbacStrtDttm != null
                            ? _formatDateTime(item.pbacStrtDttm!)
                            : '-',
                      ),
                      _buildInfoRowWithHover(
                        '공매종료일시',
                        item.pbacEndDttm != null
                            ? _formatDateTime(item.pbacEndDttm!)
                            : '-',
                      ),
                      const SizedBox(height: 24),
                      // 입찰 버튼
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: item.isExpired ? null : _showBiddingDialog,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1a1a2e),
                            disabledBackgroundColor: Colors.grey.shade300,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            item.isExpired ? '공매 종료' : 'Place Your Bid',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontFamily: 'Noto Sans KR',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
        // 뒤로가기 버튼
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 12,
          child: GestureDetector(
            onTap: () => Get.back(),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.arrow_back, color: Color(0xFF1a1a2e), size: 20),
            ),
          ),
        ),
        // 즐겨찾기 버튼
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          right: 12,
          child: GestureDetector(
            onTap: _toggleFavorite,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                _isFavorite ? Icons.favorite : Icons.favorite_border,
                color: _isFavorite ? const Color(0xFFEF4444) : const Color(0xFF999999),
                size: 20,
              ),
            ),
          ),
        ),
        // 용어 설명 팝업
        if (_hoveredLabel != null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 70,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1a1a2e),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _hoveredLabel ?? '',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF3B82F6),
                      fontFamily: 'Noto Sans KR',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    termDefinitions[_hoveredLabel] ?? '',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontFamily: 'Noto Sans KR',
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFB0B0B8),
              fontFamily: 'Noto Sans KR',
              fontWeight: FontWeight.w500,
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF1a1a2e),
                fontWeight: FontWeight.w600,
                fontFamily: 'Noto Sans KR',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRowWithHover(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onLongPressStart: (_) => setState(() => _hoveredLabel = label),
            onLongPressEnd: (_) => setState(() => _hoveredLabel = null),
            child: MouseRegion(
              onEnter: (_) => setState(() => _hoveredLabel = label),
              onExit: (_) => setState(() => _hoveredLabel = null),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: _hoveredLabel == label
                      ? const Color(0xFF3B82F6)
                      : const Color(0xFFB0B0B8),
                  fontFamily: 'Noto Sans KR',
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF1a1a2e),
                fontWeight: FontWeight.w600,
                fontFamily: 'Noto Sans KR',
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatPrice(int price) {
    final s = price.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final reverseIndex = s.length - i;
      buffer.write(s[i]);
      if (reverseIndex > 1 && reverseIndex % 3 == 1) {
        buffer.write(',');
      }
    }
    return '${buffer.toString()}원';
  }

  String _formatDateTime(String raw) {
    // DB 날짜 형식: "YYYY-MM-DDTHH:MM:SS.000Z" 또는 "YYYYMMDDHHMMSS"
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}';
    } catch (_) {
      return raw;
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  void _showBiddingDialog() {
    if (!ApiService.isLoggedIn) {
      Get.snackbar('로그인 필요', '입찰하려면 로그인이 필요합니다',
          backgroundColor: Colors.orange, colorText: Colors.white);
      return;
    }
    final item = _item!;
    final biddingController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '입찰금액을 입력하세요',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1a1a2e),
                  fontFamily: 'Noto Sans KR',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '공매예정가격: ${item.pbacPrngPrc != null ? _formatPrice(item.pbacPrngPrc!) : "-"}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF999999),
                  fontFamily: 'Noto Sans KR',
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: biddingController,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '입찰금액 입력 (원)',
                  hintStyle: const TextStyle(
                      color: Color(0xFF999999), fontFamily: 'Noto Sans KR'),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: Color(0xFF3B82F6), width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF4F4F5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      child: const Text(
                        '취소',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1a1a2e),
                          fontFamily: 'Noto Sans KR',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final raw = biddingController.text.trim();
                        final amount = int.tryParse(raw);
                        if (amount == null || amount <= 0) {
                          Get.snackbar('입력 오류', '올바른 입찰금액을 입력해주세요',
                              backgroundColor: Colors.red,
                              colorText: Colors.white);
                          return;
                        }
                        Navigator.pop(ctx);
                        try {
                          await ApiService.submitBid(
                              item.pbacNo, item.pbacSrno, item.cmdtLnNo,
                              amount);
                          Get.snackbar(
                            '입찰 완료',
                            '입찰이 성공적으로 완료되었습니다',
                            backgroundColor: const Color(0xFF3B82F6),
                            colorText: Colors.white,
                            duration: const Duration(seconds: 2),
                          );
                        } catch (e) {
                          Get.snackbar(
                              '입찰 실패',
                              e.toString().replaceFirst('Exception: ', ''),
                              backgroundColor: Colors.red,
                              colorText: Colors.white);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      child: const Text(
                        '입찰하기',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          fontFamily: 'Noto Sans KR',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
