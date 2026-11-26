import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdMob ad unit IDs.
///
/// 1. Create the app in the AdMob console, then create one Banner, one
///    Interstitial and one Rewarded ad unit and paste their IDs below.
/// 2. Put the AdMob *App* ID in android/app/src/main/AndroidManifest.xml
///    (and ios/Runner/Info.plist for iOS).
///
/// While an ID below is empty, and always in debug builds, Google's public
/// test units are used, so you can never click your own live ads by accident
/// (which gets AdMob accounts suspended).
class AdIds {
  static const _androidBanner = '';
  static const _androidInterstitial = '';
  static const _androidRewarded = '';
  static const _iosBanner = '';
  static const _iosInterstitial = '';
  static const _iosRewarded = '';

  static String _pick(String android, String ios, String testAndroid, String testIos) {
    final prod = Platform.isIOS ? ios : android;
    if (kDebugMode || prod.isEmpty) return Platform.isIOS ? testIos : testAndroid;
    return prod;
  }

  static String get banner =>
      _pick(_androidBanner, _iosBanner, 'ca-app-pub-3940256099942544/9214589741', 'ca-app-pub-3940256099942544/2435281174');
  static String get interstitial => _pick(
      _androidInterstitial, _iosInterstitial, 'ca-app-pub-3940256099942544/1033173712', 'ca-app-pub-3940256099942544/4411468910');
  static String get rewarded =>
      _pick(_androidRewarded, _iosRewarded, 'ca-app-pub-3940256099942544/5224354917', 'ca-app-pub-3940256099942544/1712485313');
}

class Ads {
  static final ready = ValueNotifier<bool>(false);
  static InterstitialAd? _interstitial;
  static RewardedAd? _rewarded;
  static int _finished = 0;

  /// Asks for consent where the law requires it (GDPR etc.), then starts the SDK.
  static void init() {
    void start() async {
      if (ready.value) return;
      try {
        if (!await ConsentInformation.instance.canRequestAds()) return;
        await MobileAds.instance.initialize();
        ready.value = true;
        _loadInterstitial();
        _loadRewarded();
      } catch (e) {
        debugPrint('Ads unavailable: $e');
      }
    }

    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () => ConsentForm.loadAndShowConsentFormIfRequired((_) => start()),
        (_) => start(),
      );
    } catch (_) {
      start();
    }
  }

  static void _loadInterstitial() {
    InterstitialAd.load(
      adUnitId: AdIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (_) => _interstitial = null,
      ),
    );
  }

  static void _loadRewarded() {
    RewardedAd.load(
      adUnitId: AdIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewarded = ad,
        onAdFailedToLoad: (_) => _rewarded = null,
      ),
    );
  }

  /// Shows a full-screen ad after every second finished quiz, at a natural
  /// break (never mid-question). Completes when the ad is closed or skipped.
  static Future<void> afterQuiz() {
    _finished++;
    final ad = _interstitial;
    if (!ready.value || ad == null || _finished.isOdd) return Future.value();
    final done = Completer<void>();
    void finish(Ad a) {
      a.dispose();
      _interstitial = null;
      _loadInterstitial();
      if (!done.isCompleted) done.complete();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: finish,
      onAdFailedToShowFullScreenContent: (a, _) => finish(a),
    );
    ad.show();
    return done.future;
  }

  static bool get rewardedReady => ready.value && _rewarded != null;

  /// Plays a rewarded video. Returns true if the reward was earned, or if no
  /// ad was available (we don't punish the player for that).
  static Future<bool> showRewarded() {
    final ad = _rewarded;
    if (!ready.value || ad == null) return Future.value(true);
    final done = Completer<bool>();
    var earned = false;
    void finish(Ad a) {
      a.dispose();
      _rewarded = null;
      _loadRewarded();
      if (!done.isCompleted) done.complete(earned);
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: finish,
      onAdFailedToShowFullScreenContent: (a, _) {
        earned = true;
        finish(a);
      },
    );
    ad.show(onUserEarnedReward: (_, __) => earned = true);
    return done.future;
  }
}

/// Adaptive banner. Takes no space until an ad has actually loaded.
class BannerAdBox extends StatefulWidget {
  const BannerAdBox({super.key});

  @override
  State<BannerAdBox> createState() => _BannerAdBoxState();
}

class _BannerAdBoxState extends State<BannerAdBox> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    Ads.ready.addListener(_load);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    if (_requested || !Ads.ready.value || !mounted) return;
    _requested = true;
    final width = MediaQuery.sizeOf(context).width.truncate();
    final size = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
    if (size == null || !mounted) return;
    final ad = BannerAd(
      adUnitId: AdIds.banner,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) => ad.dispose(),
      ),
    );
    _ad = ad;
    ad.load();
  }

  @override
  void dispose() {
    Ads.ready.removeListener(_load);
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: Container(
        alignment: Alignment.center,
        color: Theme.of(context).colorScheme.surface,
        width: double.infinity,
        height: ad.size.height.toDouble(),
        child: SizedBox(width: ad.size.width.toDouble(), height: ad.size.height.toDouble(), child: AdWidget(ad: ad)),
      ),
    );
  }
}
