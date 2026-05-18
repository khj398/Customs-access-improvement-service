import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/item.dart';
import '../services/api_service.dart';
import '../services/api_config.dart';
import '../widgets/item_card.dart';

class NewDropsScreen extends StatefulWidget {
  const NewDropsScreen({super.key});

  @override
  State<NewDropsScreen> createState() => _NewDropsScreenState();
}

class _NewDropsScreenState extends State<NewDropsScreen> {
  final _api = ApiService();
  final _items = <AuctionItem>[];
  bool _loading = true;
  bool _hasMore = true;
  int _page = 1;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadItems();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200 &&
        !_loading && _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    try {
      final result = await _api.fetchItems(
        page: 1,
        limit: ApiConfig.defaultPageSize,
      );
      setState(() {
        _items
          ..clear()
          ..addAll(result);
        _page = 1;
        _hasMore = result.length >= ApiConfig.defaultPageSize;
      });
    } catch (_) {
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loading = true);
    try {
      final next = _page + 1;
      final result = await _api.fetchItems(
        page: next,
        limit: ApiConfig.defaultPageSize,
      );
      setState(() {
        _items.addAll(result);
        _page = next;
        _hasMore = result.length >= ApiConfig.defaultPageSize;
      });
    } catch (_) {
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('이번 주 새로 등록된 공매',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1B33),
        elevation: 0,
        surfaceTintColor: Colors.white,
      ),
      backgroundColor: const Color(0xFFF4F5F8),
      body: _loading && _items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(
                  child: Text('진행 중인 공매가 없습니다',
                      style: TextStyle(color: Color(0xFF9DA0AD), fontSize: 15)),
                )
              : RefreshIndicator(
                  onRefresh: _loadItems,
                  child: GridView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: 320,
                    ),
                    itemCount: _items.length + (_hasMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == _items.length) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return ItemCard(item: _items[i], imageHeight: 200);
                    },
                  ),
                ),
    );
  }
}
