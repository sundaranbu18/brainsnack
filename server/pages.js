// Small static pages served by the API host: the Play Store listing needs a
// privacy policy URL and an account-deletion URL, and AdMob needs a website.
const CONTACT = process.env.CONTACT_EMAIL || 'support@example.com';

const page = (title, body) => `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title} - BrainSnack</title>
<style>
  body{font:16px/1.65 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;color:#1c1b2e;background:#f6f5fb;margin:0}
  main{max-width:720px;margin:0 auto;padding:40px 22px 80px}
  h1{font-size:30px;margin:0 0 6px} h2{font-size:19px;margin:32px 0 6px}
  a{color:#5b3df5} nav{margin-bottom:28px;font-size:14px} nav a{margin-right:14px}
  .muted{color:#6b6a80;font-size:14px}
</style></head><body><main>
<nav><a href="/">BrainSnack</a><a href="/privacy">Privacy</a><a href="/terms">Terms</a><a href="/delete-account">Delete account</a></nav>
<h1>${title}</h1>
${body}
</main></body></html>`;

exports.home = page(
  'BrainSnack',
  `<p>BrainSnack is a free quiz app: bite-size trivia across science, history, geography, movies and more, with leaderboards and daily streaks.</p>
   <p>The app is free and supported by advertising.</p>
   <p class="muted">Contact: <a href="mailto:${CONTACT}">${CONTACT}</a></p>`
);

exports.privacy = page(
  'Privacy Policy',
  `<p class="muted">Last updated: 27 November 2026</p>
   <p>This policy explains what the BrainSnack mobile app collects and why.</p>
   <h2>Information you give us</h2>
   <p>You can play without an account. If you create one, we store your username, email address and a hashed (irreversibly scrambled) version of your password. If you play as a guest, we store only the nickname you type for the leaderboard.</p>
   <h2>Information created when you play</h2>
   <p>We store your quiz results (score, number of correct answers, time taken), your total score and your daily streak. Usernames, nicknames and scores are shown publicly on leaderboards. Quizzes you write are shown publicly once approved.</p>
   <h2>Advertising</h2>
   <p>BrainSnack shows ads through Google AdMob. Google and its partners may collect and use device identifiers (such as the advertising ID), approximate location derived from IP address, and information about how you interact with ads, in order to show and measure ads, including personalised ads where you have consented. See <a href="https://policies.google.com/technologies/partner-sites">how Google uses information from apps that use its services</a>. You can reset or delete your advertising ID in your device settings, and where the law requires it the app asks for your consent before showing personalised ads.</p>
   <h2>How we use information</h2>
   <p>To run the game, show leaderboards, keep your progress, prevent abuse and show ads. We do not sell your personal information.</p>
   <h2>Where it is kept</h2>
   <p>Data is stored with our hosting and database providers (Render and MongoDB Atlas) and is transmitted over encrypted connections (HTTPS).</p>
   <h2>Keeping and deleting your data</h2>
   <p>We keep account data until you delete your account. You can delete your account and its data at any time in the app (Profile &gt; Delete account) or by following the steps on the <a href="/delete-account">account deletion page</a>.</p>
   <h2>Children</h2>
   <p>BrainSnack is not directed at children under 13, and we do not knowingly collect personal information from them.</p>
   <h2>Contact</h2>
   <p>Questions about this policy: <a href="mailto:${CONTACT}">${CONTACT}</a>.</p>`
);

exports.terms = page(
  'Terms of Use',
  `<p class="muted">Last updated: 27 November 2026</p>
   <p>By using BrainSnack you agree to these terms.</p>
   <h2>Using the app</h2>
   <p>BrainSnack is provided free of charge for personal, non-commercial use. Do not cheat, automate play, interfere with the service or attempt to access other people's accounts.</p>
   <h2>Content you submit</h2>
   <p>Usernames, nicknames and quizzes you submit must be your own work, accurate to the best of your knowledge, and must not be offensive, hateful, sexual, infringing or unlawful. Submitted quizzes are reviewed before publication and may be edited, rejected or removed. You give us a non-exclusive licence to display the quizzes you submit within the app.</p>
   <h2>No warranty</h2>
   <p>Quiz content is for entertainment and general education. We try to keep it accurate but make no guarantees, and the app is provided "as is". To the extent the law allows, we are not liable for losses arising from use of the app.</p>
   <h2>Changes</h2>
   <p>We may update the app and these terms. Continued use after a change means you accept the updated terms.</p>
   <h2>Contact</h2>
   <p><a href="mailto:${CONTACT}">${CONTACT}</a></p>`
);

exports.deleteAccount = page(
  'Delete your account',
  `<p>You can permanently delete your BrainSnack account and its data at any time.</p>
   <h2>In the app</h2>
   <p>Open BrainSnack, go to <b>Profile</b>, tap <b>Delete account</b>, enter your password and confirm.</p>
   <h2>By email</h2>
   <p>If you can no longer access the app, email <a href="mailto:${CONTACT}">${CONTACT}</a> from the address registered on your account and ask for deletion. We complete requests within 30 days.</p>
   <h2>What is deleted</h2>
   <p>Your username, email address, password hash, scores, streaks, play history and any unpublished quizzes are deleted. Quizzes of yours that were already published stay available but are no longer linked to you. Guest leaderboard entries are not linked to any account.</p>`
);
