import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:table_calendar/table_calendar.dart';
import '../controllers/app_controller.dart';
import '../models/item.dart';
import '../services/api_service.dart';
import '../utils/format.dart';
import 'detail_screen.dart';
import 'login_screen.dart';

const _kPrimary = Color(0xFF3B82F6);
const _kPrimaryDark = Color(0xFF171A3B);
const _kSuccess = Color(0xFF10B981);

class MypageTab extends StatefulWidget {
  const MypageTab({super.key});

  @override
  State<MypageTab> createState() => _MypageTabState();
}

class _MypageTabState extends State<MypageTab> {
  DateTime _focusedDay = DateTime(2026, 3, 1);
  DateTime? _selectedDay;

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<AppController>();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('MY PAGE',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF1A1B33))),
            const SizedBox(height: 16),

            // Profile
            Row(
              children: [
                Container(
                  width: 60, height: 60,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFDBE7FF)),
                  child: const Icon(Icons.person, color: Color(0xFF3F7BE5), size: 30),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ApiService.userName.isNotEmpty ? ApiService.userName : '사용자',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    Text(ApiService.userEmail,
                        style: const TextStyle(color: Color(0xFF8B8D95), fontSize: 14)),
                  ],
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    ApiService.logout();
                    Get.offAll(() => const LoginScreen(), transition: Transition.fadeIn);
                  },
                  icon: const Icon(Icons.logout, size: 16, color: Color(0xFF9CA3AF)),
                  label: const Text('로그아웃',
                      style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Stats
            Obx(() => Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFECEEF2)),
              ),
              child: Row(
                children: [
                  _StatCell(value: '0', label: '입찰 참여', color: _kPrimary),
                  _StatCell(value: '0', label: '낙찰 성공', color: _kSuccess),
                  _StatCell(value: '${ctrl.wishlistIds.length}', label: '찜한 상품', color: _kPrimary),
                ],
              ),
            )),
            const SizedBox(height: 14),

            // Calendar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFECEEF2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.calendar_month, color: _kPrimary),
                      SizedBox(width: 8),
                      Text('공매 일정 캘린더',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Obx(() {
                    final wishIds = ctrl.wishlistIds.toList();
                    return TableCalendar<AuctionItem>(
                      firstDay: DateTime(2026, 1, 1),
                      lastDay: DateTime(2027, 12, 31),
                      focusedDay: _focusedDay,
                      selectedDayPredicate: (d) => isSameDay(_selectedDay, d),
                      eventLoader: ctrl.getItemsForDay,
                      onDaySelected: (selected, focused) {
                        setState(() {
                          _selectedDay = selected;
                          _focusedDay = focused;
                        });
                        final dayItems = ctrl.getItemsForDay(selected);
                        if (dayItems.isNotEmpty) _showDaySheet(context, selected, dayItems, wishIds);
                      },
                      onPageChanged: (focused) => setState(() => _focusedDay = focused),
                      calendarStyle: CalendarStyle(
                        todayDecoration: const BoxDecoration(color: _kPrimaryDark, shape: BoxShape.circle),
                        selectedDecoration: BoxDecoration(
                          color: _kPrimary.withOpacity(0.7),
                          shape: BoxShape.circle,
                        ),
                        markerDecoration: const BoxDecoration(color: Colors.transparent),
                        markersMaxCount: 2,
                      ),
                      calendarBuilders: CalendarBuilders(
                        markerBuilder: (context, day, events) {
                          if (events.isEmpty) return const SizedBox.shrink();
                          final hasWish = events.any((e) => wishIds.contains((e as AuctionItem).id));
                          return Positioned(
                            bottom: 2,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (hasWish) _dot(_kPrimary),
                                if (events.isNotEmpty) _dot(const Color(0xFFA78BFA)),
                              ],
                            ),
                          );
                        },
                      ),
                      headerStyle: const HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                        titleTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  // Legend
                  Row(
                    children: [
                      _LegendDot(color: _kPrimary, label: '찜한 공매 마감일'),
                      const SizedBox(width: 16),
                      _LegendDot(color: const Color(0xFFA78BFA), label: '일반 공매 마감일'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color color) => Container(
    width: 5, height: 5,
    margin: const EdgeInsets.symmetric(horizontal: 1),
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );

  void _showDaySheet(BuildContext context, DateTime day, List<AuctionItem> items, List<int> wishIds) {
    final sorted = [...items]..sort((a, b) {
      final aW = wishIds.contains(a.id) ? 0 : 1;
      final bW = wishIds.contains(b.id) ? 0 : 1;
      return aW - bW;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: const Color(0xFFD8D9DD), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A1B33)),
                  children: [
                    TextSpan(text: '${day.month}월 ${day.day}일 마감 물품 '),
                    TextSpan(text: '${items.length}건', style: const TextStyle(color: _kPrimary)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  children: sorted.map((item) {
                    final isWished = wishIds.contains(item.id);
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        Get.to(() => DetailScreen(item: item));
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isWished ? const Color(0xFFEEF3FF) : const Color(0xFFF8F8FA),
                          borderRadius: BorderRadius.circular(12),
                          border: isWished ? Border.all(color: _kPrimary, width: 1.5) : null,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: isWished ? const Color(0xFFDBEAFE) : const Color(0xFFE8E9EC),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                isWished ? Icons.favorite : Icons.inventory_2_outlined,
                                color: isWished ? _kPrimary : const Color(0xFFA6ABB4),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.name,
                                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14,
                                          color: isWished ? _kPrimary : const Color(0xFF1A1B33))),
                                  Text(item.customs, style: const TextStyle(color: Color(0xFF8E919D), fontSize: 12)),
                                ],
                              ),
                            ),
                            Text(formatPrice(item.price),
                                style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.w800, fontSize: 14)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _StatCell({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        child: Column(
          children: [
            Text(value, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.w800)),
            Text(label, style: const TextStyle(color: Color(0xFF8E919D), fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Color(0xFF8E919D), fontSize: 12)),
      ],
    );
  }
}
