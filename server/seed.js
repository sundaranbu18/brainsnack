// Inserts the starter quizzes. Safe to re-run: existing quizzes (matched by slug) are left untouched.
const mongoose = require('mongoose');
const { Quiz } = require('./models');
const categories = require('./categories');
const data = require('./seed-data');

async function seed() {
  const ops = data.map((d) => ({
    updateOne: {
      filter: { slug: d.slug },
      update: {
        $setOnInsert: {
          slug: d.slug,
          title: d.title,
          description: d.description,
          category: d.category,
          difficulty: d.difficulty,
          emoji: categories.find((c) => c.slug === d.category).emoji,
          featured: !!d.featured,
          status: 'published',
          authorName: 'BrainSnack',
          questions: d.q.map(([text, options, answer, explanation]) => ({ text, options, answer, explanation })),
        },
      },
      upsert: true,
    },
  }));
  const r = await Quiz.bulkWrite(ops);
  return r.upsertedCount;
}

module.exports = { seed };

if (require.main === module) {
  require('dotenv').config({ path: require('path').join(__dirname, '..', '.env'), quiet: true });
  const dbName = process.env.DB_NAME || 'brainsnack';
  if (dbName.toLowerCase() === 'klar') throw new Error('Refusing to seed the "klar" database.');
  mongoose
    .connect(process.env.MONGODB_URI, { dbName })
    .then(seed)
    .then((n) => console.log(`Added ${n} new quizzes to "${dbName}"`))
    .finally(() => mongoose.disconnect());
}
