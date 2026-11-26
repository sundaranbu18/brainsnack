import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  String _period = 'week';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Text('Leaderboard', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'week', label: Text('This week')),
              ButtonSegment(value: 'all', label: Text('All time')),
            ],
            selected: {_period},
            onSelectionChanged: (s) => setState(() => _period = s.first),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: Loader(
          key: ValueKey(_period),
          load: () => Api.get('/leaderboard?period=$_period'),
          builder: (context, d, reload) {
            final rows = (d['rows'] as List).cast<Json>();
            return RefreshIndicator(
              onRefresh: reload,
              child: ListenableBuilder(
                listenable: session,
                builder: (context, _) => ListView(padding: const EdgeInsets.only(top: 4, bottom: 24), children: [
                  if (rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(children: [
                        const Text('🏆', style: TextStyle(fontSize: 44)),
                        const SizedBox(height: 10),
                        Text('No scores yet', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('Sign in and finish a quiz to claim the top spot.',
                            textAlign: TextAlign.center, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.outline)),
                      ]),
                    ),
                  for (var i = 0; i < rows.length; i++)
                    RankRow(
                      rank: i + 1,
                      name: '${rows[i]['name']}',
                      score: rows[i]['score'] as num,
                      sub: '${rows[i]['played']} quiz${rows[i]['played'] == 1 ? '' : 'zes'}',
                      highlight: session.signedIn && rows[i]['name'] == session.user!['username'],
                    ),
                  if (!session.signedIn && rows.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text('Create a free account in the Profile tab to appear here.',
                          textAlign: TextAlign.center, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
                    ),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}
