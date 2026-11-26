require('dotenv').config({ path: require('path').join(__dirname, '..', '.env'), quiet: true });
const express = require('express');
const mongoose = require('mongoose');
const helmet = require('helmet');
const compression = require('compression');
const { Quiz } = require('./models');
const pages = require('./pages');

const PORT = process.env.PORT || 5050;
const DB_NAME = process.env.DB_NAME || 'brainsnack';
const ADMOB_PUBLISHER = (process.env.ADMOB_PUBLISHER_ID || '').trim(); // e.g. pub-1234567890123456

// Safety: this app shares a cluster with another product. Never use its database.
if (DB_NAME.toLowerCase() === 'klar') {
  console.error('DB_NAME must not be "klar" - that database belongs to another app.');
  process.exit(1);
}
if (!process.env.MONGODB_URI || !process.env.JWT_SECRET) {
  console.error('Missing MONGODB_URI or JWT_SECRET environment variable.');
  process.exit(1);
}

const app = express();
app.set('trust proxy', 1);
app.use(helmet());
app.use(compression());
app.use(express.json({ limit: '200kb' }));

app.get('/healthz', (req, res) => res.json({ ok: mongoose.connection.readyState === 1 }));
app.use('/api', require('./api'));

// Pages the Play Store listing and AdMob need to link to.
app.get('/', (req, res) => res.type('html').send(pages.home));
app.get('/privacy', (req, res) => res.type('html').send(pages.privacy));
app.get('/terms', (req, res) => res.type('html').send(pages.terms));
app.get('/delete-account', (req, res) => res.type('html').send(pages.deleteAccount));
// AdMob verifies this file on the developer website listed in Google Play.
app.get('/app-ads.txt', (req, res) => {
  if (!ADMOB_PUBLISHER) return res.status(404).type('text/plain').send('');
  res.type('text/plain').send(`google.com, ${ADMOB_PUBLISHER.replace(/^ca-app-/, '')}, DIRECT, f08c47fec0942fa0\n`);
});

mongoose
  .connect(process.env.MONGODB_URI, { dbName: DB_NAME, serverSelectionTimeoutMS: 15000 })
  .then(async () => {
    console.log(`MongoDB connected (database: ${mongoose.connection.name})`);
    if ((await Quiz.estimatedDocumentCount()) === 0) {
      const n = await require('./seed').seed();
      console.log(`Seeded ${n} starter quizzes`);
    }
    app.listen(PORT, () => console.log(`BrainSnack API listening on port ${PORT}`));
  })
  .catch((e) => {
    console.error('Could not start:', e.message);
    process.exit(1);
  });
