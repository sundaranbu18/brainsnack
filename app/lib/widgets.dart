import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/quiz.dart';

const brand = Color(0xFF5B3DF5);
const gold = Color(0xFFFFB020);
const good = Color(0xFF16A34A);
const bad = Color(0xFFDC2626);

/// Soft tile colours for categories, picked by position.
const tileColors = [
  Color(0xFF5B3DF5), Color(0xFF0EA5A4), Color(0xFFE5484D), Color(0xFF2F80ED),
  Color(0xFF7C3AED), Color(0xFF0F766E), Color(0xFFD97706), Color(0xFFDB2777),
  Color(0xFF15803D), Color(0xFFB91C1C), Color(0xFF4F46E5), Color(0xFF9A6700),
]; // prettier-ignore

Color difficultyColor(String? d) => switch (d) { 'easy' => good, 'hard' => bad, _ => const Color(0xFFD97706) };

String compact(num n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '$n';
}

String clock(num ms) {
  final s = (ms / 1000).round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}

void openQuiz(BuildContext context, String slug) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => QuizScreen(slug: slug)));

/// Loads data, showing a spinner, then either the content or a retry screen.
class Loader extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder});
  final Future<Json> Function() load;
  final Widget Function(BuildContext context, Json data, Future<void> Function() reload) builder;

  @override
  State<Loader> createState() => LoaderState();
}

class LoaderState extends State<Loader> {
  Json? _data;
  String? _error;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    if (_data == null) {
      setState(() {
        _error = null;
        _slow = false;
      });
    }
    Future.delayed(const Duration(seconds: 6), () {
      if (mounted && _data == null && _error == null) setState(() => _slow = true);
    });
    try {
      final d = await widget.load();
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } on ApiError catch (e) {
      if (!mounted) return;
      if (_data == null) {
        setState(() => _error = e.message);
      } else {
        toast(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (_data != null) return widget.builder(context, _data!, reload);
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: t.colorScheme.outline),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: t.textTheme.bodyLarge),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: reload, icon: const Icon(Icons.refresh), label: const Text('Try again')),
          ]),
        ),
      );
    }
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(),
        if (_slow) ...[
          const SizedBox(height: 16),
          Text('Waking up the server…', style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.outline)),
        ],
      ]),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.action, this.onAction});
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 12, 8),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ]),
      );
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color, this.icon});
  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: c), const SizedBox(width: 3)],
        Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
      ]),
    );
  }
}

/// Row-style quiz card used in lists.
class QuizTile extends StatelessWidget {
  const QuizTile(this.q, {super.key});
  final Json q;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final plays = (q['plays'] ?? 0) as num;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => openQuiz(context, q['slug'] as String),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: t.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(16)),
              child: Text('${q['emoji'] ?? '🧠'}', style: const TextStyle(fontSize: 26)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${q['title']}',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.2)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  Pill('${q['difficulty']}'.toUpperCase(), color: difficultyColor(q['difficulty'] as String?)),
                  if (q['count'] != null) Pill('${q['count']} Qs', icon: Icons.help_outline),
                  if (plays > 0) Pill('${compact(plays)} plays', icon: Icons.play_arrow_rounded),
                ]),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: t.colorScheme.outline),
          ]),
        ),
      ),
    );
  }
}

/// Podium-style ranking row.
class RankRow extends StatelessWidget {
  const RankRow({super.key, required this.rank, required this.name, required this.score, this.sub, this.highlight = false});
  final int rank;
  final String name;
  final num score;
  final String? sub;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final medal = switch (rank) { 1 => '🥇', 2 => '🥈', 3 => '🥉', _ => null };
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: highlight ? t.colorScheme.primaryContainer : t.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        SizedBox(
          width: 34,
          child: medal != null
              ? Text(medal, style: const TextStyle(fontSize: 20))
              : Text('$rank', style: t.textTheme.titleSmall?.copyWith(color: t.colorScheme.outline, fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            if (sub != null) Text(sub!, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
          ]),
        ),
        Text(compact(score), style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: t.colorScheme.primary)),
      ]),
    );
  }
}
