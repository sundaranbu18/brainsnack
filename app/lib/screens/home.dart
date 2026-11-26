import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets.dart';
import 'browse.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onBrowse});
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    return Loader(
      load: () async {
        final d = await Api.get('/home');
        session.categories = d['categories'] as List;
        return d;
      },
      builder: (context, d, reload) {
        final t = Theme.of(context);
        final daily = d['daily'] as Json?;
        final featured = (d['featured'] as List).cast<Json>();
        final cats = (d['categories'] as List).cast<Json>().where((c) => (c['count'] as num) > 0).toList();
        final trending = (d['trending'] as List).cast<Json>();
        final stats = d['stats'] as Json;
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: ListenableBuilder(
                listenable: session,
                builder: (_, __) {
                  final streak = (session.user?['streak'] ?? 0) as num;
                  return Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Hi, ${session.displayName} 👋', style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.outline)),
                        Text('Ready for a snack?', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                      ]),
                    ),
                    if (streak > 0) Pill('🔥 $streak day${streak == 1 ? '' : 's'}', color: const Color(0xFFEA580C)),
                  ]);
                },
              ),
            ),
            if (daily != null) _DailyCard(daily),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Text(
                '${stats['quizzes']} quizzes · ${compact(stats['plays'] as num)} games played',
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
              ),
            ),
            if (featured.isNotEmpty) ...[
              const SectionTitle('Featured'),
              SizedBox(
                height: 168,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: featured.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => _FeatureCard(featured[i], tileColors[i % tileColors.length]),
                ),
              ),
            ],
            SectionTitle('Categories', action: 'See all', onAction: onBrowse),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.05,
                children: [for (var i = 0; i < cats.length && i < 6; i++) CategoryTile(cats[i], tileColors[i % tileColors.length])],
              ),
            ),
            const SectionTitle('Trending now'),
            for (final q in trending) QuizTile(q),
          ]),
        );
      },
    );
  }
}

class _DailyCard extends StatelessWidget {
  const _DailyCard(this.q);
  final Json q;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Material(
        borderRadius: BorderRadius.circular(26),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF5B3DF5), Color(0xFF9C4DF4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: InkWell(
            onTap: () => openQuiz(context, q['slug'] as String),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(99)),
                      child: const Text('⚡ DAILY QUIZ',
                          style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                    ),
                    const SizedBox(height: 12),
                    Text('${q['title']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800, height: 1.2)),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                      child: const Text('Play now', style: TextStyle(color: brand, fontWeight: FontWeight.w800)),
                    ),
                  ]),
                ),
                const SizedBox(width: 8),
                Text('${q['emoji']}', style: const TextStyle(fontSize: 64)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard(this.q, this.color);
  final Json q;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openQuiz(context, q['slug'] as String),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${q['emoji']}', style: const TextStyle(fontSize: 34)),
              const Spacer(),
              Text('${q['title']}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w800, height: 1.2)),
              const SizedBox(height: 6),
              Text('${q['count']} questions · ${q['difficulty']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
        ),
      ),
    );
  }
}

class CategoryTile extends StatelessWidget {
  const CategoryTile(this.c, this.color, {super.key});
  final Json c;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: color.withOpacity(dark ? 0.28 : 0.11),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => QuizListScreen(category: c))),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('${c['emoji']}', style: const TextStyle(fontSize: 30)),
            const SizedBox(height: 6),
            Text('${c['name']}',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.15, color: dark ? Colors.white : Color.lerp(color, Colors.black, 0.35))),
          ]),
        ),
      ),
    );
  }
}
