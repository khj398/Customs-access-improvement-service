import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/auction_item.dart';
import '../services/api_service.dart';

class ItemCard extends StatefulWidget {
  final AuctionItem item;
  final Function(bool) onFavoriteToggle;
  final bool isHorizontalScroll;

  const ItemCard({
    required this.item,
    required this.onFavoriteToggle,
    required this.isHorizontalScroll,
  });

  @override
  State<ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<ItemCard> {
  late bool _isFavorite;
  bool _isToggling = false; // 중복 탭 방지

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.item.isFavorite;
  }

  Future<void> _toggleFavorite() async {
    // 로그인 확인
    if (!ApiService.isLoggedIn) {
      Get.snackbar(
        '로그인 필요',
        '찜하기는 로그인 후 이용할 수 있습니다',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
      return;
    }

    // 이미 처리 중이면 무시
    if (_isToggling) return;
    _isToggling = true;

    // 낙관적 UI 업데이트 (즉시 반영)
    final previous = _isFavorite;
    setState(() => _isFavorite = !_isFavorite);

    try {
      final result = await ApiService.toggleLike(
        widget.item.pbacNo,
        widget.item.pbacSrno,
        widget.item.cmdtLnNo,
      );
      // 서버 응답 기준으로 최종 상태 확정
      if (mounted) {
        setState(() => _isFavorite = result);
        widget.onFavoriteToggle(result);
      }
    } catch (_) {
      // 실패 시 원래 상태로 롤백
      if (mounted) setState(() => _isFavorite = previous);
    } finally {
      _isToggling = false;
    }
  }

  String _formatPrice(int price) {
    if (price >= 10000000) {
      return '${(price / 1000000).toStringAsFixed(0)}M원';
    } else if (price >= 1000000) {
      return '${(price / 1000000).toStringAsFixed(1)}M원'.replaceAll('.0M', 'M');
    } else if (price >= 100000) {
      return '${(price / 10000).toStringAsFixed(0)}만원';
    } else {
      return '${price}원';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardWidth = widget.isHorizontalScroll ? 160.0 : double.infinity;
    final imageHeight = widget.isHorizontalScroll ? 200.0 : 180.0;

    return Container(
      width: cardWidth,
      height: imageHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // 배경: 이미지 없으므로 카테고리별 색상 배경
            Container(
              width: double.infinity,
              height: double.infinity,
              color: Color(0xFFF0F2F5),
              child: Center(
                child: Icon(
                  Icons.inventory_2_outlined,
                  color: Color(0xFFB0B3B8),
                  size: 40,
                ),
              ),
            ),
            // 그라데이션 오버레이 (하단)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 140,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0),
                      Colors.black.withOpacity(0.7),
                    ],
                  ),
                ),
              ),
            ),
            // 텍스트 정보 (하단 오버레이)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Padding(
                padding: EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 카테고리
                    Text(
                      widget.item.categoryName ?? widget.item.cstmName ?? '',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.7),
                        fontFamily: 'Noto Sans KR',
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 3),
                    // 물품명
                    Text(
                      widget.item.cmdtNm,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        fontFamily: 'Noto Sans KR',
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 5),
                    // 공매예정가격
                    Text(
                      widget.item.pbacPrngPrc != null
                          ? _formatPrice(widget.item.pbacPrngPrc!)
                          : '가격 미정',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF5B9CF5),
                        fontFamily: 'Noto Sans KR',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            // 좋아요 버튼 (상단 우측)
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: _toggleFavorite,
                child: Container(
                  padding: EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: _isFavorite ? Color(0xFFEF4444) : Color(0xFFD0D0D0),
                    size: 18,
                  ),
                ),
              ),
            ),
            // 마감임박 배지
            if (widget.item.isDeadlineImminent)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Color(0xFFEF4444).withOpacity(0.9),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Text(
                    '마감임박',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      fontFamily: 'Noto Sans KR',
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
