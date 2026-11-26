const mongoose = require('mongoose');
const { Schema } = mongoose;

const userSchema = new Schema(
  {
    username: { type: String, required: true, unique: true, trim: true, minlength: 3, maxlength: 20 },
    usernameLower: { type: String, required: true, unique: true },
    email: { type: String, required: true, unique: true, lowercase: true, trim: true },
    passwordHash: { type: String, required: true },
    totalScore: { type: Number, default: 0, index: true },
    quizzesPlayed: { type: Number, default: 0 },
    streak: { type: Number, default: 0 },
    bestStreak: { type: Number, default: 0 },
    lastPlayedDay: { type: String, default: '' }, // YYYY-MM-DD (UTC)
  },
  { timestamps: true }
);

const questionSchema = new Schema(
  {
    text: { type: String, required: true, maxlength: 300 },
    options: { type: [String], validate: (v) => v.length >= 2 && v.length <= 4 },
    answer: { type: Number, required: true, min: 0, max: 3 },
    explanation: { type: String, default: '', maxlength: 400 },
  },
  { _id: false }
);

const quizSchema = new Schema(
  {
    slug: { type: String, required: true, unique: true },
    title: { type: String, required: true, maxlength: 90 },
    description: { type: String, default: '', maxlength: 300 },
    category: { type: String, required: true, index: true },
    difficulty: { type: String, enum: ['easy', 'medium', 'hard'], default: 'medium' },
    emoji: { type: String, default: '🧠' },
    questions: { type: [questionSchema], default: [] },
    author: { type: Schema.Types.ObjectId, ref: 'User', default: null },
    authorName: { type: String, default: 'BrainSnack' },
    status: { type: String, enum: ['published', 'pending', 'rejected'], default: 'pending', index: true },
    featured: { type: Boolean, default: false },
    plays: { type: Number, default: 0 },
    pctSum: { type: Number, default: 0 }, // sum of percentage scores, for average
  },
  { timestamps: true }
);
quizSchema.index({ title: 'text', description: 'text' });

const attemptSchema = new Schema(
  {
    quiz: { type: Schema.Types.ObjectId, ref: 'Quiz', required: true },
    quizSlug: String,
    quizTitle: String,
    user: { type: Schema.Types.ObjectId, ref: 'User', default: null, index: true },
    name: { type: String, default: 'Guest' },
    score: { type: Number, required: true },
    correct: Number,
    total: Number,
    timeMs: Number,
  },
  { timestamps: true }
);
attemptSchema.index({ quiz: 1, score: -1, timeMs: 1 });
attemptSchema.index({ createdAt: -1 });

const messageSchema = new Schema(
  { name: String, email: String, message: { type: String, maxlength: 3000 } },
  { timestamps: true }
);

module.exports = {
  User: mongoose.model('User', userSchema),
  Quiz: mongoose.model('Quiz', quizSchema),
  Attempt: mongoose.model('Attempt', attemptSchema),
  Message: mongoose.model('Message', messageSchema),
};
