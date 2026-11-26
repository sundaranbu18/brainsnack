import 'dart:async';

import 'package:flutter/material.dart';

import '../ads.dart';
import '../api.dart';
import '../widgets.dart';
import 'home.dart';

/// Browse tab: search box, all categories, and search results.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => setState(() => _query = v.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: TextField(
          controller: _search,
          onChanged: _changed,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search quizzes',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
        ),
      ),
      Expanded(
        child: _query.isEmpty
            ? Loader(
                load: () => Api.get('/home'),
                builder: (context, d, reload) {
                  final cats = (d['categories'] as List).cast<Json>();
                  return RefreshIndicator(
                    onRefresh: reload,
                    child: GridView.count(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      crossAxisCount: 3,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.05,
                      children: [for (var i = 0; i < cats.length; i++) CategoryTile(cats[i], tileColors[i % tileColors.length])],
                    ),
                  );
                },
              )
            : _Results(key: ValueKey(_query), path: '/quizzes?q=${Uri.encodeQueryComponent(_query)}'),
      ),
    ]);
  }
}

class _Results extends StatelessWidget {
  const _Results({super.key, required this.path, this.header});
  final String path;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return Loader(
      load: () => Api.get(path),
      builder: (context, d, reload) {
        final items = (d['items'] as List).cast<Json>();
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            if (header != null) header!,
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(48),
                child: Column(children: [
                  const Text('🔍', style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 8),
                  Text('No quizzes found', style: Theme.of(context).textTheme.titleMedium),
                ]),
              ),
            for (final q in items) QuizTile(q),
          ]),
        );
      },
    );
  }
}

/// All quizzes in one category.
class QuizListScreen extends StatefulWidget {
  const QuizListScreen({super.key, required this.category});
  final Json category;

  @override
  State<QuizListScreen> createState() => _QuizListScreenState();
}

class _QuizListScreenState extends State<QuizListScreen> {
  String _sort = 'popular';

  @override
  Widget build(BuildContext context) {
    final c = widget.category;
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('${c['emoji']}  ${c['name']}', style: const TextStyle(fontWeight: FontWeight.w800))),
      bottomNavigationBar: const BannerAdBox(),
      body: _Results(
        key: ValueKey(_sort),
        path: '/quizzes?category=${c['slug']}&sort=$_sort',
        header: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${c['blurb']}', style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.outline)),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'popular', label: Text('Most played')),
                ButtonSegment(value: 'new', label: Text('Newest')),
              ],
              selected: {_sort},
              onSelectionChanged: (s) => setState(() => _sort = s.first),
            ),
          ]),
        ),
      ),
    );
  }
}
