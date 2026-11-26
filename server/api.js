const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const rateLimit = require('express-rate-limit');
const { User, Quiz, Attempt, Message } = require('./models');
const categories = require('./categories');

const router = express.Router();
const JWT_SECRET = process.env.JWT_SECRET;
const ADMIN_EMAILS = (process.env.ADMIN_EMAILS || '')
  .split(',')
  .map((s) => s.trim().toLowerCase())
  .filter(Boolean);

const wrap = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
const bad = (res, msg, code = 400) => res.status(code).json({ error: msg });
const str = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const today = () => new Date().toISOString().slice(0, 10);
const isAdmin = (u) => !!u && ADMIN_EMAILS.includes(u.email);

const CARD = 'slug title description category difficulty emoji plays pctSum authorName createdAt';
const card = (q) => ({
  slug: q.slug,
  title: q.title,
  description: q.description,
  category: q.category,
  difficulty: q.difficulty,
  emoji: q.emoji,
  plays: q.plays,
  avg: q.plays ? Math.round(q.pctSum / q.plays) : null,
  authorName: q.authorName,
  count: q.count ?? (q.questions ? q.questions.length : undefined),
});
const withCount = (match, sort, limit, skip = 0) =>
  Quiz.aggregate([
    { $match: match },
    { $sort: sort },
    { $skip: skip },
    { $limit: limit },
    { $addFields: { count: { $size: '$questions' } } },
    { $project: { questions: 0 } },
  ]).then((r) => r.map(card));

const publicUser = (u) => ({
  id: u._id,
  username: u.username,
  email: u.email,
  totalScore: u.totalScore,
  quizzesPlayed: u.quizzesPlayed,
  streak: u.lastPlayedDay && daysBetween(u.lastPlayedDay, today()) <= 1 ? u.streak : 0,
  bestStreak: u.bestStreak,
  isAdmin: isAdmin(u),
});
function daysBetween(a, b) {
  return Math.round((Date.parse(b) - Date.parse(a)) / 86400000);
}

// ---------- auth ----------
const auth = (required) =>
  wrap(async (req, res, next) => {
    const h = req.headers.authorization || '';
    const token = h.startsWith('Bearer ') ? h.slice(7) : null;
    if (token) {
      try {
        const { id } = jwt.verify(token, JWT_SECRET);
        req.user = await User.findById(id);
      } catch (_) {
        /* invalid token -> treated as guest */
      }
    }
    if (required && !req.user) return bad(res, 'Please sign in first.', 401);
    next();
  });
const sign = (u) => jwt.sign({ id: u._id }, JWT_SECRET, { expiresIn: '60d' });

const authLimiter = rateLimit({ windowMs: 15 * 60 * 1000, limit: 30, standardHeaders: true, legacyHeaders: false });
const writeLimiter = rateLimit({ windowMs: 60 * 1000, limit: 40, standardHeaders: true, legacyHeaders: false });

router.post(
  '/auth/register',
  authLimiter,
  wrap(async (req, res) => {
    const username = str(req.body.username, 20);
    const email = str(req.body.email, 120).toLowerCase();
    const password = typeof req.body.password === 'string' ? req.body.password : '';
    if (!/^[A-Za-z0-9_]{3,20}$/.test(username)) return bad(res, 'Username must be 3-20 letters, numbers or underscores.');
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return bad(res, 'Enter a valid email address.');
    if (password.length < 8) return bad(res, 'Password must be at least 8 characters.');
    const clash = await User.findOne({ $or: [{ email }, { usernameLower: username.toLowerCase() }] });
    if (clash) return bad(res, clash.email === email ? 'That email is already registered.' : 'That username is taken.', 409);
    const user = await User.create({
      username,
      usernameLower: username.toLowerCase(),
      email,
      passwordHash: await bcrypt.hash(password, 11),
    });
    res.json({ token: sign(user), user: publicUser(user) });
  })
);

router.post(
  '/auth/login',
  authLimiter,
  wrap(async (req, res) => {
    const email = str(req.body.email, 120).toLowerCase();
    const password = typeof req.body.password === 'string' ? req.body.password : '';
    const user = await User.findOne({ email });
    if (!user || !(await bcrypt.compare(password, user.passwordHash))) return bad(res, 'Wrong email or password.', 401);
    res.json({ token: sign(user), user: publicUser(user) });
  })
);

router.get(
  '/auth/me',
  auth(true),
  wrap(async (req, res) => {
    const [history, mine] = await Promise.all([
      Attempt.find({ user: req.user._id }).sort({ createdAt: -1 }).limit(20).lean(),
      Quiz.find({ author: req.user._id }).sort({ createdAt: -1 }).select('slug title status plays emoji').lean(),
    ]);
    res.json({
      user: publicUser(req.user),
      history: history.map((a) => ({
        slug: a.quizSlug,
        title: a.quizTitle,
        score: a.score,
        correct: a.correct,
        total: a.total,
        at: a.createdAt,
      })),
      quizzes: mine,
    });
  })
);

// Permanently delete the signed-in account (required by Google Play for apps with sign-up).
router.delete(
  '/auth/me',
  auth(true),
  wrap(async (req, res) => {
    const password = typeof req.body.password === 'string' ? req.body.password : '';
    if (!(await bcrypt.compare(password, req.user.passwordHash))) return bad(res, 'Wrong password.', 401);
    await Attempt.deleteMany({ user: req.user._id });
    await Quiz.updateMany({ author: req.user._id }, { author: null, authorName: 'Former member' });
    await Quiz.deleteMany({ author: null, authorName: 'Former member', status: { $ne: 'published' } });
    await User.deleteOne({ _id: req.user._id });
    res.json({ ok: true });
  })
);

// ---------- browse ----------
async function dailyQuiz() {
  const n = await Quiz.countDocuments({ status: 'published' });
  if (!n) return null;
  const day = Math.floor(Date.now() / 86400000);
  const [q] = await withCount({ status: 'published' }, { _id: 1 }, 1, day % n);
  return q;
}

router.get(
  '/home',
  wrap(async (req, res) => {
    const pub = { status: 'published' };
    const [counts, featured, trending, newest, daily, plays, players] = await Promise.all([
      Quiz.aggregate([{ $match: pub }, { $group: { _id: '$category', n: { $sum: 1 } } }]),
      withCount({ ...pub, featured: true }, { plays: -1 }, 6),
      withCount(pub, { plays: -1, _id: 1 }, 8),
      withCount(pub, { createdAt: -1, _id: -1 }, 8),
      dailyQuiz(),
      Attempt.estimatedDocumentCount(),
      User.estimatedDocumentCount(),
    ]);
    const byCat = Object.fromEntries(counts.map((c) => [c._id, c.n]));
    res.json({
      categories: categories.map((c) => ({ ...c, count: byCat[c.slug] || 0 })),
      featured,
      trending,
      newest,
      daily,
      stats: { quizzes: counts.reduce((s, c) => s + c.n, 0), plays, players },
    });
  })
);

router.get(
  '/quizzes',
  wrap(async (req, res) => {
    const match = { status: 'published' };
    const cat = str(req.query.category, 40);
    const q = str(req.query.q, 60);
    const diff = str(req.query.difficulty, 10);
    if (cat) match.category = cat;
    if (['easy', 'medium', 'hard'].includes(diff)) match.difficulty = diff;
    if (q) match.title = { $regex: q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), $options: 'i' };
    const sort = req.query.sort === 'new' ? { createdAt: -1, _id: -1 } : { plays: -1, _id: 1 };
    const page = Math.max(1, parseInt(req.query.page, 10) || 1);
    const limit = 24;
    const [items, total] = await Promise.all([withCount(match, sort, limit, (page - 1) * limit), Quiz.countDocuments(match)]);
    res.json({
      items,
      total,
      page,
      pages: Math.max(1, Math.ceil(total / limit)),
      category: categories.find((c) => c.slug === cat) || null,
    });
  })
);

const board = (rows) => rows.map((a) => ({ name: a.name, score: a.score, correct: a.correct, total: a.total, timeMs: a.timeMs }));

router.get(
  '/quizzes/:slug',
  auth(false),
  wrap(async (req, res) => {
    const quiz = await Quiz.findOne({ slug: req.params.slug }).lean();
    const canSee = quiz && (quiz.status === 'published' || isAdmin(req.user) || (req.user && String(quiz.author) === String(req.user._id)));
    if (!canSee) return bad(res, 'Quiz not found.', 404);
    const [top, related] = await Promise.all([
      Attempt.find({ quiz: quiz._id }).sort({ score: -1, timeMs: 1 }).limit(10).lean(),
      withCount({ status: 'published', category: quiz.category, _id: { $ne: quiz._id } }, { plays: -1 }, 4),
    ]);
    res.json({
      quiz: {
        ...card(quiz),
        status: quiz.status,
        questions: quiz.questions.map((q) => ({ text: q.text, options: q.options })),
      },
      category: categories.find((c) => c.slug === quiz.category) || null,
      leaderboard: board(top),
      related,
    });
  })
);

router.post(
  '/quizzes/:slug/check',
  writeLimiter,
  wrap(async (req, res) => {
    const quiz = await Quiz.findOne({ slug: req.params.slug }).select('questions').lean();
    const q = quiz && quiz.questions[Number(req.body.index)];
    if (!q) return bad(res, 'Question not found.', 404);
    res.json({ correct: Number(req.body.answer) === q.answer, answer: q.answer, explanation: q.explanation });
  })
);

// 50/50 hint: returns two wrong options the app can hide.
router.post(
  '/quizzes/:slug/hint',
  writeLimiter,
  wrap(async (req, res) => {
    const quiz = await Quiz.findOne({ slug: req.params.slug }).select('questions').lean();
    const q = quiz && quiz.questions[Number(req.body.index)];
    if (!q) return bad(res, 'Question not found.', 404);
    const wrong = q.options.map((_, i) => i).filter((i) => i !== q.answer);
    while (wrong.length > Math.max(1, q.options.length - 2)) wrong.splice(Math.floor(Math.random() * wrong.length), 1);
    res.json({ hide: q.options.length > 2 ? wrong : [] });
  })
);

router.post(
  '/quizzes/:slug/submit',
  writeLimiter,
  auth(false),
  wrap(async (req, res) => {
    const quiz = await Quiz.findOne({ slug: req.params.slug });
    if (!quiz) return bad(res, 'Quiz not found.', 404);
    const answers = Array.isArray(req.body.answers) ? req.body.answers : [];
    const total = quiz.questions.length;
    const review = quiz.questions.map((q, i) => ({
      text: q.text,
      options: q.options,
      answer: q.answer,
      picked: Number.isInteger(answers[i]) ? answers[i] : -1,
      explanation: q.explanation,
    }));
    const correct = review.filter((r) => r.picked === r.answer).length;
    // Clamp time so impossible speeds earn no extra bonus.
    const timeMs = Math.min(Math.max(Number(req.body.timeMs) || 0, total * 1500), total * 60000);
    const speed = Math.max(0, 1 - timeMs / (total * 20000));
    const score = correct * 100 + Math.round(correct * 50 * speed);
    const pct = Math.round((correct / total) * 100);

    let result = { score, correct, total, pct, timeMs, review, saved: false };
    if (quiz.status === 'published') {
      const name = req.user ? req.user.username : str(req.body.name, 20).replace(/[<>]/g, '') || 'Guest';
      await Attempt.create({
        quiz: quiz._id,
        quizSlug: quiz.slug,
        quizTitle: quiz.title,
        user: req.user ? req.user._id : null,
        name,
        score,
        correct,
        total,
        timeMs,
      });
      await Quiz.updateOne({ _id: quiz._id }, { $inc: { plays: 1, pctSum: pct } });
      const [better, all, top] = await Promise.all([
        Attempt.countDocuments({ quiz: quiz._id, score: { $gt: score } }),
        Attempt.countDocuments({ quiz: quiz._id }),
        Attempt.find({ quiz: quiz._id }).sort({ score: -1, timeMs: 1 }).limit(10).lean(),
      ]);
      result = {
        ...result,
        saved: true,
        name,
        rank: better + 1,
        players: all,
        beat: all > 1 ? Math.round(((all - better - 1) / (all - 1)) * 100) : 100,
        leaderboard: board(top),
      };
      if (req.user) {
        const u = req.user;
        const t = today();
        if (u.lastPlayedDay !== t) {
          u.streak = u.lastPlayedDay && daysBetween(u.lastPlayedDay, t) === 1 ? u.streak + 1 : 1;
          u.bestStreak = Math.max(u.bestStreak, u.streak);
          u.lastPlayedDay = t;
        }
        u.totalScore += score;
        u.quizzesPlayed += 1;
        await u.save();
        result.user = publicUser(u);
      }
    }
    res.json(result);
  })
);

// ---------- leaderboard ----------
router.get(
  '/leaderboard',
  wrap(async (req, res) => {
    if (req.query.period === 'week') {
      const since = new Date(Date.now() - 7 * 86400000);
      const rows = await Attempt.aggregate([
        { $match: { createdAt: { $gte: since }, user: { $ne: null } } },
        { $group: { _id: '$user', name: { $last: '$name' }, score: { $sum: '$score' }, played: { $sum: 1 } } },
        { $sort: { score: -1 } },
        { $limit: 50 },
      ]);
      return res.json({ rows: rows.map((r) => ({ name: r.name, score: r.score, played: r.played })) });
    }
    const users = await User.find({ quizzesPlayed: { $gt: 0 } }).sort({ totalScore: -1 }).limit(50).lean();
    res.json({ rows: users.map((u) => ({ name: u.username, score: u.totalScore, played: u.quizzesPlayed, streak: u.bestStreak })) });
  })
);

// ---------- create ----------
const slugify = (s) =>
  s
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60);

router.post(
  '/quizzes',
  writeLimiter,
  auth(true),
  wrap(async (req, res) => {
    const title = str(req.body.title, 90);
    const description = str(req.body.description, 300);
    const category = str(req.body.category, 40);
    if (title.length < 8) return bad(res, 'Give your quiz a title of at least 8 characters.');
    if (!categories.some((c) => c.slug === category)) return bad(res, 'Pick a category.');
    const raw = Array.isArray(req.body.questions) ? req.body.questions.slice(0, 20) : [];
    const questions = [];
    for (const q of raw) {
      const text = str(q && q.text, 300);
      const options = (Array.isArray(q && q.options) ? q.options : []).map((o) => str(o, 120)).filter(Boolean);
      const answer = Number(q && q.answer);
      if (!text || options.length < 2 || options.length > 4 || !Number.isInteger(answer) || answer < 0 || answer >= options.length)
        return bad(res, 'Every question needs text, 2-4 options and a correct answer.');
      questions.push({ text, options, answer, explanation: str(q.explanation, 400) });
    }
    if (questions.length < 5) return bad(res, 'Add at least 5 questions.');
    const pending = await Quiz.countDocuments({ author: req.user._id, status: 'pending' });
    if (pending >= 5) return bad(res, 'You already have 5 quizzes waiting for review.', 429);
    let slug = slugify(title) || 'quiz';
    if (await Quiz.exists({ slug })) slug = `${slug}-${Date.now().toString(36)}`;
    const cat = categories.find((c) => c.slug === category);
    const quiz = await Quiz.create({
      slug,
      title,
      description,
      category,
      difficulty: ['easy', 'medium', 'hard'].includes(req.body.difficulty) ? req.body.difficulty : 'medium',
      emoji: cat.emoji,
      questions,
      author: req.user._id,
      authorName: req.user.username,
      status: isAdmin(req.user) ? 'published' : 'pending',
    });
    res.json({ slug: quiz.slug, status: quiz.status });
  })
);

// ---------- admin ----------
const adminOnly = [auth(true), (req, res, next) => (isAdmin(req.user) ? next() : bad(res, 'Admins only.', 403))];

router.get(
  '/admin/pending',
  adminOnly,
  wrap(async (req, res) => {
    const [quizzes, messages] = await Promise.all([
      Quiz.find({ status: 'pending' }).sort({ createdAt: 1 }).lean(),
      Message.find().sort({ createdAt: -1 }).limit(30).lean(),
    ]);
    res.json({ quizzes, messages });
  })
);

router.post(
  '/admin/quizzes/:id/:action',
  adminOnly,
  wrap(async (req, res) => {
    const status = { approve: 'published', reject: 'rejected' }[req.params.action];
    if (!status) return bad(res, 'Unknown action.');
    await Quiz.updateOne({ _id: req.params.id }, { status });
    res.json({ ok: true });
  })
);

// ---------- contact ----------
router.post(
  '/contact',
  rateLimit({ windowMs: 60 * 60 * 1000, limit: 5 }),
  wrap(async (req, res) => {
    const message = str(req.body.message, 3000);
    if (message.length < 10) return bad(res, 'Please write a slightly longer message.');
    await Message.create({ name: str(req.body.name, 80), email: str(req.body.email, 120), message });
    res.json({ ok: true });
  })
);

router.use((req, res) => bad(res, 'Not found.', 404));
// eslint-disable-next-line no-unused-vars
router.use((err, req, res, next) => {
  if (err.name === 'CastError') return bad(res, 'Not found.', 404);
  console.error(err);
  bad(res, 'Something went wrong. Please try again.', 500);
});

module.exports = router;
