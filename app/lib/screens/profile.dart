import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../widgets.dart';

void _open(String path) => launchUrl(Uri.parse('$apiBase$path'), mode: LaunchMode.externalApplication);

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: session,
        builder: (context, _) => session.signedIn ? _Account(key: ValueKey(session.user!['id'])) : const _AuthForm(),
      );
}

class _LegalLinks extends StatelessWidget {
  const _LegalLinks();

  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        TextButton(onPressed: () => _open('/privacy'), child: const Text('Privacy Policy')),
        TextButton(onPressed: () => _open('/terms'), child: const Text('Terms of Use')),
      ]);
}

// ---------------------------------------------------------------- sign in

class _AuthForm extends StatefulWidget {
  const _AuthForm();

  @override
  State<_AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<_AuthForm> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.authenticate(
        register: _register,
        email: _email.text.trim(),
        password: _password.text,
        username: _username.text.trim(),
      );
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListView(padding: const EdgeInsets.fromLTRB(20, 28, 20, 24), children: [
      const Text('🧠', style: TextStyle(fontSize: 52)),
      const SizedBox(height: 8),
      Text(_register ? 'Create your free account' : 'Welcome back', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text('Keep your points, build a daily streak, climb the leaderboard and write your own quizzes.',
          style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.outline)),
      const SizedBox(height: 22),
      if (_register) ...[
        TextField(
          controller: _username,
          maxLength: 20,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newUsername],
          decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.alternate_email_rounded), counterText: ''),
        ),
        const SizedBox(height: 12),
      ],
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.email],
        decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _password,
        obscureText: true,
        onSubmitted: (_) => _submit(),
        autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
        decoration: InputDecoration(
          labelText: 'Password',
          helperText: _register ? 'At least 8 characters' : null,
          prefixIcon: const Icon(Icons.lock_outline_rounded),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, style: TextStyle(color: t.colorScheme.error, fontWeight: FontWeight.w600)),
      ],
      const SizedBox(height: 18),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: _busy
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
            : Text(_register ? 'Create account' : 'Sign in'),
      ),
      TextButton(
        onPressed: () => setState(() {
          _register = !_register;
          _error = null;
        }),
        child: Text(_register ? 'I already have an account' : 'Create a new account'),
      ),
      const SizedBox(height: 8),
      Text('You can play every quiz without an account.',
          textAlign: TextAlign.center, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
      const _LegalLinks(),
    ]);
  }
}

// ---------------------------------------------------------------- account

class _Account extends StatelessWidget {
  const _Account({super.key});

  Future<void> _delete(BuildContext context) async {
    final c = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete account?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('This permanently deletes your account, scores, streak and history. It cannot be undone.'),
          const SizedBox(height: 14),
          TextField(controller: c, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm your password')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: Text('Delete forever', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    if (password == null || !context.mounted) return;
    try {
      await Api.delete('/auth/me', {'password': password});
      await session.logout();
      if (context.mounted) toast(context, 'Your account has been deleted.');
    } on ApiError catch (e) {
      if (context.mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Loader(
      load: () async {
        final d = await Api.get('/auth/me');
        session.user = d['user'] as Json;
        return d;
      },
      builder: (context, d, reload) {
        final u = d['user'] as Json;
        final history = (d['history'] as List).cast<Json>();
        final mine = (d['quizzes'] as List).cast<Json>();
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: t.colorScheme.primary,
                  child: Text('${u['username']}'.substring(0, 1).toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${u['username']}', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    Text('${u['email']}', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
                  ]),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: Row(children: [
                _StatCard('⭐', compact(u['totalScore'] as num), 'Points'),
                const SizedBox(width: 10),
                _StatCard('🎯', '${u['quizzesPlayed']}', 'Played'),
                const SizedBox(width: 10),
                _StatCard('🔥', '${u['streak']}', 'Day streak'),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: FilledButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateQuizScreen()));
                  reload();
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create a quiz'),
              ),
            ),
            if (u['isAdmin'] == true)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminScreen())),
                  icon: const Icon(Icons.verified_user_outlined),
                  label: const Text('Review submitted quizzes'),
                ),
              ),
            if (mine.isNotEmpty) ...[
              const SectionTitle('My quizzes'),
              for (final q in mine)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  leading: Text('${q['emoji']}', style: const TextStyle(fontSize: 26)),
                  title: Text('${q['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(q['status'] == 'published' ? '${q['plays']} plays' : 'Status: ${q['status']}'),
                  trailing: Pill('${q['status']}'.toUpperCase(),
                      color: switch (q['status']) { 'published' => good, 'rejected' => bad, _ => const Color(0xFFD97706) }),
                  onTap: () => openQuiz(context, q['slug'] as String),
                ),
            ],
            const SectionTitle('Recent games'),
            if (history.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('Nothing yet. Play a quiz to see it here.', style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.outline)),
              ),
            for (final h in history)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                dense: true,
                title: Text('${h['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                subtitle: Text('${h['correct']}/${h['total']} correct'),
                trailing: Text('+${h['score']}', style: t.textTheme.titleMedium?.copyWith(color: t.colorScheme.primary, fontWeight: FontWeight.w800)),
                onTap: () => openQuiz(context, h['slug'] as String),
              ),
            const SizedBox(height: 16),
            const Divider(indent: 20, endIndent: 20),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Sign out'),
              onTap: session.logout,
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: Icon(Icons.delete_outline_rounded, color: t.colorScheme.error),
              title: Text('Delete account', style: TextStyle(color: t.colorScheme.error)),
              onTap: () => _delete(context),
            ),
            const _LegalLinks(),
          ]),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.emoji, this.value, this.label);
  final String emoji;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: t.colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          Text(value, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          Text(label, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- create

class _Draft {
  final text = TextEditingController();
  final explanation = TextEditingController();
  final options = List.generate(4, (_) => TextEditingController());
  int answer = 0;

  void dispose() {
    text.dispose();
    explanation.dispose();
    for (final o in options) {
      o.dispose();
    }
  }
}

class CreateQuizScreen extends StatefulWidget {
  const CreateQuizScreen({super.key});

  @override
  State<CreateQuizScreen> createState() => _CreateQuizScreenState();
}

class _CreateQuizScreenState extends State<CreateQuizScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _drafts = List.generate(5, (_) => _Draft());
  List<Json> _cats = session.categories.cast<Json>();
  String? _category;
  String _difficulty = 'medium';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (_cats.isEmpty) {
      Api.get('/home').then((d) {
        if (mounted) setState(() => _cats = (d['categories'] as List).cast<Json>());
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final questions = <Json>[];
    for (var i = 0; i < _drafts.length; i++) {
      final d = _drafts[i];
      final filled = [for (final o in d.options) o.text.trim()];
      final options = filled.where((o) => o.isNotEmpty).toList();
      if (d.text.text.trim().isEmpty || options.length < 2) return toast(context, 'Question ${i + 1} needs text and at least two options.');
      if (filled[d.answer].isEmpty) return toast(context, 'Question ${i + 1}: the option marked correct is empty.');
      questions.add({
        'text': d.text.text.trim(),
        'options': options,
        'answer': options.indexOf(filled[d.answer]),
        'explanation': d.explanation.text.trim(),
      });
    }
    setState(() => _busy = true);
    try {
      final r = await Api.post('/quizzes', {
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'category': _category ?? '',
        'difficulty': _difficulty,
        'questions': questions,
      });
      if (!mounted) return;
      toast(context, r['status'] == 'published' ? 'Your quiz is live!' : 'Submitted! It will appear once it has been reviewed.');
      Navigator.of(context).pop();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Create a quiz', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        TextField(controller: _title, maxLength: 90, decoration: const InputDecoration(labelText: 'Title', counterText: '')),
        const SizedBox(height: 12),
        TextField(
            controller: _description,
            maxLength: 300,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Short description', counterText: '')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _category,
          decoration: const InputDecoration(labelText: 'Category'),
          items: [for (final c in _cats) DropdownMenuItem(value: c['slug'] as String, child: Text('${c['emoji']}  ${c['name']}'))],
          onChanged: (v) => setState(() => _category = v),
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'easy', label: Text('Easy')),
            ButtonSegment(value: 'medium', label: Text('Medium')),
            ButtonSegment(value: 'hard', label: Text('Hard')),
          ],
          selected: {_difficulty},
          onSelectionChanged: (s) => setState(() => _difficulty = s.first),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _drafts.length; i++)
          Card(
            margin: const EdgeInsets.only(top: 14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('Question ${i + 1}', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                  if (_drafts.length > 5)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => setState(() => _drafts.removeAt(i).dispose()),
                    ),
                ]),
                const SizedBox(height: 8),
                TextField(
                    controller: _drafts[i].text,
                    maxLength: 300,
                    maxLines: null,
                    decoration: InputDecoration(hintText: 'Type the question', counterText: '', fillColor: t.colorScheme.surface)),
                const SizedBox(height: 8),
                Text('Options — select the correct one', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
                for (var o = 0; o < 4; o++)
                  Row(children: [
                    Radio<int>(value: o, groupValue: _drafts[i].answer, onChanged: (v) => setState(() => _drafts[i].answer = v!)),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: TextField(
                          controller: _drafts[i].options[o],
                          maxLength: 120,
                          decoration: InputDecoration(
                              hintText: 'Option ${String.fromCharCode(65 + o)}${o > 1 ? ' (optional)' : ''}',
                              counterText: '',
                              isDense: true,
                              fillColor: t.colorScheme.surface),
                        ),
                      ),
                    ),
                  ]),
                const SizedBox(height: 4),
                TextField(
                    controller: _drafts[i].explanation,
                    maxLength: 400,
                    maxLines: null,
                    decoration: InputDecoration(hintText: 'Explanation (optional)', counterText: '', isDense: true, fillColor: t.colorScheme.surface)),
              ]),
            ),
          ),
        const SizedBox(height: 14),
        if (_drafts.length < 20)
          OutlinedButton.icon(
              onPressed: () => setState(() => _drafts.add(_Draft())), icon: const Icon(Icons.add_rounded), label: const Text('Add question')),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('Submit for review'),
        ),
        const SizedBox(height: 10),
        Text('Quizzes are checked before they go public. Keep it original, accurate and friendly.',
            textAlign: TextAlign.center, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
      ]),
    );
  }
}

// ---------------------------------------------------------------- admin

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Review queue', style: TextStyle(fontWeight: FontWeight.w800))),
      body: Loader(
        load: () => Api.get('/admin/pending'),
        builder: (context, d, reload) {
          final quizzes = (d['quizzes'] as List).cast<Json>();
          final messages = (d['messages'] as List).cast<Json>();
          Future<void> act(Json q, String action) async {
            try {
              await Api.post('/admin/quizzes/${q['_id']}/$action');
              await reload();
            } on ApiError catch (e) {
              if (context.mounted) toast(context, e.message);
            }
          }

          return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            if (quizzes.isEmpty)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Nothing waiting for review 🎉'))),
            for (final q in quizzes)
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ExpansionTile(
                  shape: const Border(),
                  title: Text('${q['title']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${q['category']} · by ${q['authorName']} · ${(q['questions'] as List).length} questions'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ('${q['description']}'.isNotEmpty) Text('${q['description']}'),
                    for (final (i, qq) in (q['questions'] as List).cast<Json>().indexed) ...[
                      const SizedBox(height: 10),
                      Text('${i + 1}. ${qq['text']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      for (final (j, o) in (qq['options'] as List).indexed)
                        Text('${j == qq['answer'] ? '✓' : '•'} $o', style: TextStyle(color: j == qq['answer'] ? good : null)),
                    ],
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: OutlinedButton(onPressed: () => act(q, 'reject'), child: const Text('Reject'))),
                      const SizedBox(width: 10),
                      Expanded(child: FilledButton(onPressed: () => act(q, 'approve'), child: const Text('Approve'))),
                    ]),
                  ],
                ),
              ),
            if (messages.isNotEmpty) const SectionTitle('Messages'),
            for (final m in messages)
              ListTile(
                title: Text('${m['message']}'),
                subtitle: Text('${m['name']} · ${m['email']}', style: t.textTheme.bodySmall),
              ),
          ]);
        },
      ),
    );
  }
}
