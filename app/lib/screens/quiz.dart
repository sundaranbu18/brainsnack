import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../ads.dart';
import '../api.dart';
import '../widgets.dart';

/// Quiz intro: details, top scores and the Start button.
class QuizScreen extends StatelessWidget {
  const QuizScreen({super.key, required this.slug});
  final String slug;

  Future<void> _start(BuildContext context, Json quiz) async {
    if (!session.signedIn && session.guestName.isEmpty) {
      final name = await showDialog<String>(context: context, builder: (_) => const _NameDialog());
      if (name == null) return;
      await session.setGuestName(name);
    }
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayScreen(quiz: quiz)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(),
      bottomNavigationBar: const BannerAdBox(),
      body: Loader(
        load: () => Api.get('/quizzes/$slug'),
        builder: (context, d, reload) {
          final q = d['quiz'] as Json;
          final cat = d['category'] as Json?;
          final top = (d['leaderboard'] as List).cast<Json>();
          final related = (d['related'] as List).cast<Json>();
          final count = (q['questions'] as List).length;
          return Column(children: [
            Expanded(
              child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 84,
                      height: 84,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: t.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(26)),
                      child: Text('${q['emoji']}', style: const TextStyle(fontSize: 44)),
                    ),
                    const SizedBox(height: 16),
                    Text('${q['title']}', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.15)),
                    const SizedBox(height: 8),
                    Text('${q['description']}', style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 14),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      if (cat != null) Pill('${cat['name']}', color: t.colorScheme.primary),
                      Pill('${q['difficulty']}'.toUpperCase(), color: difficultyColor(q['difficulty'] as String?)),
                      Pill('$count questions', icon: Icons.help_outline),
                      if ((q['plays'] as num) > 0) Pill('${compact(q['plays'] as num)} plays', icon: Icons.play_arrow_rounded),
                      if (q['avg'] != null) Pill('avg ${q['avg']}%', icon: Icons.bar_chart_rounded),
                      if (q['status'] != 'published') Pill('${q['status']}'.toUpperCase(), color: bad),
                    ]),
                    const SizedBox(height: 10),
                    Text('By ${q['authorName']}', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
                  ]),
                ),
                if (top.isNotEmpty) ...[
                  const SectionTitle('Top scores'),
                  for (var i = 0; i < top.length && i < 5; i++)
                    RankRow(
                      rank: i + 1,
                      name: '${top[i]['name']}',
                      score: top[i]['score'] as num,
                      sub: '${top[i]['correct']}/${top[i]['total']} correct · ${clock(top[i]['timeMs'] as num)}',
                    ),
                ],
                if (related.isNotEmpty) ...[
                  const SectionTitle('More like this'),
                  for (final r in related) QuizTile(r),
                ],
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _start(context, q),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start quiz'),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Pick a nickname'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('It appears next to your score on the leaderboard.'),
          const SizedBox(height: 14),
          TextField(
            controller: _c,
            autofocus: true,
            maxLength: 20,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Guest'),
            onSubmitted: (v) => Navigator.pop(context, v.trim().isEmpty ? 'Guest' : v.trim()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () => Navigator.pop(context, _c.text.trim().isEmpty ? 'Guest' : _c.text.trim()),
            child: const Text('Play'),
          ),
        ],
      );
}

/// One question at a time, with instant feedback.
class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key, required this.quiz});
  final Json quiz;

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  late final List<Json> _questions = (widget.quiz['questions'] as List).cast<Json>();
  late final List<int> _answers = List.filled(_questions.length, -1);
  final _watch = Stopwatch()..start();
  Timer? _ticker;

  int _index = 0;
  int _correctCount = 0;
  int? _picked; // option tapped for the current question
  Json? _feedback; // {correct, answer, explanation} once checked
  Set<int> _hidden = {};
  bool _hintUsed = false;
  bool _busy = false;

  String get _slug => widget.quiz['slug'] as String;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _pick(int option) async {
    if (_picked != null || _busy) return;
    setState(() {
      _picked = option;
      _busy = true;
    });
    _watch.stop(); // don't charge the player for network time
    try {
      final r = await Api.post('/quizzes/$_slug/check', {'index': _index, 'answer': option});
      if (!mounted) return;
      _answers[_index] = option;
      if (r['correct'] == true) _correctCount++;
      setState(() => _feedback = r);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _picked = null);
      _watch.start();
      toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _hint() async {
    if (_hintUsed || _picked != null || _busy) return;
    final watch = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('50/50 hint'),
        content: Text(Ads.rewardedReady
            ? 'Watch a short video to remove two wrong answers. You get one hint per quiz.'
            : 'Remove two wrong answers? You get one hint per quiz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No thanks')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(Ads.rewardedReady ? 'Watch video' : 'Use hint')),
        ],
      ),
    );
    if (watch != true || !mounted) return;
    _watch.stop();
    setState(() => _busy = true);
    try {
      if (await Ads.showRewarded()) {
        final r = await Api.post('/quizzes/$_slug/hint', {'index': _index});
        if (mounted) {
          setState(() {
            _hidden = (r['hide'] as List).cast<int>().toSet();
            _hintUsed = true;
          });
        }
      }
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
      if (_picked == null) _watch.start();
    }
  }

  Future<void> _next() async {
    if (_index < _questions.length - 1) {
      setState(() {
        _index++;
        _picked = null;
        _feedback = null;
        _hidden = {};
      });
      _watch.start();
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await Api.post('/quizzes/$_slug/submit', {
        'answers': _answers,
        'timeMs': _watch.elapsedMilliseconds,
        'name': session.guestName,
      });
      session.updateUser(result['user'] as Json?);
      await Ads.afterQuiz();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ResultScreen(quiz: widget.quiz, result: result)));
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, e.message);
    }
  }

  Future<bool> _confirmQuit() async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Quit this quiz?'),
          content: const Text('Your progress will be lost.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep playing')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Quit')),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final q = _questions[_index];
    final options = (q['options'] as List).cast<String>();
    final answer = _feedback?['answer'] as int?;
    final last = _index == _questions.length - 1;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmQuit()) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).maybePop()),
          title: Text('Question ${_index + 1} of ${_questions.length}', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Pill(clock(_watch.elapsedMilliseconds), icon: Icons.timer_outlined, color: t.colorScheme.primary),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(value: (_index + (_feedback != null ? 1 : 0)) / _questions.length, minHeight: 6),
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 16), children: [
                Row(children: [
                  Pill('✓ $_correctCount correct', color: good),
                  const Spacer(),
                  if (!_hintUsed && options.length > 2)
                    ActionChip(
                      avatar: const Icon(Icons.lightbulb_outline_rounded, size: 18),
                      label: const Text('50/50'),
                      onPressed: _picked == null && !_busy ? _hint : null,
                    ),
                ]),
                const SizedBox(height: 18),
                Text('${q['text']}', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.25)),
                const SizedBox(height: 24),
                for (var i = 0; i < options.length; i++)
                  _Option(
                    letter: String.fromCharCode(65 + i),
                    text: options[i],
                    state: _hidden.contains(i)
                        ? _OptionState.hidden
                        : answer == null
                            ? (_picked == i ? _OptionState.pending : _OptionState.idle)
                            : i == answer
                                ? _OptionState.correct
                                : (i == _picked ? _OptionState.wrong : _OptionState.dimmed),
                    onTap: () => _pick(i),
                  ),
                if (_feedback != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: (_feedback!['correct'] == true ? good : bad).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_feedback!['correct'] == true ? 'Correct! 🎉' : 'Not quite',
                          style: t.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800, color: _feedback!['correct'] == true ? good : bad)),
                      if ('${_feedback!['explanation'] ?? ''}'.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('${_feedback!['explanation']}', style: t.textTheme.bodyMedium),
                      ],
                    ]),
                  ),
                ],
              ]),
            ),
            if (_feedback != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _next,
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : Text(last ? 'See my results' : 'Next question'),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

enum _OptionState { idle, pending, correct, wrong, dimmed, hidden }

class _Option extends StatelessWidget {
  const _Option({required this.letter, required this.text, required this.state, required this.onTap});
  final String letter;
  final String text;
  final _OptionState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final (Color border, Color fill, Color fg) = switch (state) {
      _OptionState.correct => (good, good.withOpacity(0.12), good),
      _OptionState.wrong => (bad, bad.withOpacity(0.12), bad),
      _OptionState.pending => (s.primary, s.primaryContainer, s.primary),
      _ => (s.outlineVariant, s.surfaceContainerLow, s.onSurface),
    };
    final faded = state == _OptionState.dimmed || state == _OptionState.hidden;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: state == _OptionState.hidden ? 0.25 : (faded ? 0.55 : 1),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: fill,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: border, width: 1.5)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: state == _OptionState.idle ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: fg.withOpacity(0.12), shape: BoxShape.circle),
                  child: Text(letter, style: TextStyle(fontWeight: FontWeight.w800, color: fg)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(text, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: s.onSurface))),
                if (state == _OptionState.correct) const Icon(Icons.check_circle_rounded, color: good),
                if (state == _OptionState.wrong) const Icon(Icons.cancel_rounded, color: bad),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Score, rank, answer review and what to play next.
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.quiz, required this.result});
  final Json quiz;
  final Json result;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final correct = result['correct'] as int;
    final total = result['total'] as int;
    final pct = result['pct'] as num;
    final saved = result['saved'] == true;
    final review = (result['review'] as List).cast<Json>();
    final top = ((result['leaderboard'] ?? []) as List).cast<Json>();
    final (emoji, headline) = pct == 100
        ? ('🏆', 'Perfect score!')
        : pct >= 75
            ? ('🎉', 'Great job!')
            : pct >= 50
                ? ('👍', 'Not bad!')
                : ('💪', 'Keep practising!');

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst)),
        title: Text('${quiz['title']}', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ),
      bottomNavigationBar: const BannerAdBox(),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF5B3DF5), Color(0xFF9C4DF4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(children: [
            Text(emoji, style: const TextStyle(fontSize: 54)),
            Text(headline, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('$correct of $total correct', style: const TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 18),
            Row(children: [
              _Stat('${result['score']}', 'points'),
              _Stat(clock(result['timeMs'] as num), 'time'),
              if (saved) _Stat('#${result['rank']}', 'of ${result['players']}'),
            ]),
            if (saved && (result['players'] as num) > 1) ...[
              const SizedBox(height: 16),
              Text('You beat ${result['beat']}% of players', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Share.share(
                    'I scored $correct/$total on "${quiz['title']}" in BrainSnack 🧠 Can you beat me?\nhttps://play.google.com/store/apps/details?id=com.brainsnack.quiz'),
                icon: const Icon(Icons.share_rounded),
                label: const Text('Share'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PlayScreen(quiz: quiz))),
                icon: const Icon(Icons.replay_rounded),
                label: const Text('Play again'),
              ),
            ),
          ]),
        ),
        if (!session.signedIn)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Text('Tip: create a free account in the Profile tab to keep your points and build a daily streak.',
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
          ),
        const SectionTitle('Your answers'),
        for (var i = 0; i < review.length; i++) _ReviewTile(i + 1, review[i]),
        if (top.isNotEmpty) ...[
          const SectionTitle('Top scores'),
          for (var i = 0; i < top.length; i++)
            RankRow(
              rank: i + 1,
              name: '${top[i]['name']}',
              score: top[i]['score'] as num,
              sub: '${top[i]['correct']}/${top[i]['total']} correct · ${clock(top[i]['timeMs'] as num)}',
              highlight: i + 1 == result['rank'] && top[i]['name'] == result['name'],
            ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: FilledButton.tonal(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
            child: const Text('Find another quiz'),
          ),
        ),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
        ]),
      );
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile(this.number, this.r);
  final int number;
  final Json r;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final options = (r['options'] as List).cast<String>();
    final picked = r['picked'] as int;
    final answer = r['answer'] as int;
    final ok = picked == answer;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded, color: ok ? good : bad),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$number. ${r['text']}', style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              if (!ok && picked >= 0 && picked < options.length)
                Text('Your answer: ${options[picked]}', style: t.textTheme.bodyMedium?.copyWith(color: bad)),
              Text('Answer: ${options[answer]}', style: t.textTheme.bodyMedium?.copyWith(color: good, fontWeight: FontWeight.w600)),
              if ('${r['explanation'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('${r['explanation']}', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
