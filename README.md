# BrainSnack

A free quiz app for Android (Flutter) with a Node/Express API and MongoDB. It earns money from Google AdMob ads.

- `server/` – the API. Uses its own `brainsnack` database on the Atlas cluster and refuses to start if pointed at `klar`.
- `app/` – the Flutter app (package `com.brainsnack.quiz`).
- `render.yaml` – one-click Render deployment for the API.

## Run it locally

```bash
npm install
npm run dev
```

```bash
cd app && flutter run
```

Debug builds talk to `http://10.0.2.2:5050` (your computer, as seen from the Android emulator) and always show Google's test ads.

## 1. Deploy the API to Render

1. Push this folder to a GitHub repository (`.env` is git-ignored; never commit it).
2. In Render: **New > Blueprint**, choose the repository. It reads `render.yaml`.
3. Fill in the environment variables it asks for:
   - `MONGODB_URI` – the Atlas connection string
   - `ADMIN_EMAILS` – your account email, so you can approve user-submitted quizzes in the app
   - `ADMOB_PUBLISHER_ID` – `pub-…` from AdMob (serves `/app-ads.txt`)
   - `CONTACT_EMAIL` – shown on the privacy policy
4. In Atlas > Network Access, make sure Render can connect (allow `0.0.0.0/0`, as the Klar API already needs).
5. Note the service URL, e.g. `https://brainsnack-api.onrender.com`. Check `<url>/healthz`.

The free Render plan sleeps after 15 minutes without traffic and takes up to a minute to wake; the app shows "Waking up the server…" while it waits. Upgrade the plan once you have regular users.

## 2. Set up AdMob

1. In the [AdMob console](https://apps.admob.com) add a new Android app, then create three ad units: Banner, Interstitial, Rewarded.
2. Put the **App ID** (`ca-app-pub-…~…`) in `app/android/app/src/main/AndroidManifest.xml`, replacing the test ID.
3. Put the three **ad unit IDs** in `app/lib/ads.dart` (`_androidBanner`, `_androidInterstitial`, `_androidRewarded`).
4. In AdMob > Privacy & messaging, create a GDPR consent message (the app already shows it where required).

Until those IDs are filled in, release builds also use test ads. Never tap your own live ads.

## 3. Build for Google Play

Create an upload key once (keep the file and passwords safe and backed up):

```bash
keytool -genkey -v -keystore app/android/app/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Create `app/android/key.properties` (git-ignored):

```properties
storePassword=<your password>
keyPassword=<your password>
keyAlias=upload
storeFile=upload-keystore.jks
```

Build the bundle, pointing it at your Render URL:

```bash
cd app && flutter build appbundle --release --dart-define=API_BASE=https://YOUR-SERVICE.onrender.com
```

Upload `app/build/app/outputs/bundle/release/app-release.aab` in the Play Console. For the listing you will need:

- **Privacy policy URL:** `https://YOUR-SERVICE.onrender.com/privacy`
- **Account deletion URL:** `https://YOUR-SERVICE.onrender.com/delete-account`
- **Ads:** declare "Contains ads"
- **Data safety:** email address and username (account), app activity (scores), device/advertising ID (ads)
- An app icon (replace `app/android/app/src/main/res/mipmap-*/ic_launcher.png`), feature graphic and screenshots

Raise `version:` in `app/pubspec.yaml` for every upload.

## Adding quizzes

Add entries to `server/seed-data.js` and run `npm run seed` (existing quizzes are left untouched), or sign in to the app with an `ADMIN_EMAILS` account and use **Profile > Create a quiz**. Quizzes from other users wait in **Profile > Review submitted quizzes**.
