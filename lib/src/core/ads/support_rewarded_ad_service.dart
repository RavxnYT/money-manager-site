import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class SupportRewardedAdService {
  SupportRewardedAdService._();

  static final SupportRewardedAdService instance = SupportRewardedAdService._();

  static const _testRewardedAdUnitId = 'ca-app-pub-3940256099942544/5224354917';
  static const _androidRewardedAdUnitId =
      'ca-app-pub-7145004668953814/5622127496';

  RewardedAd? _rewardedAd;
  bool _isLoading = false;

  String get _adUnitId {
    if (kDebugMode) return _testRewardedAdUnitId;
    return _androidRewardedAdUnitId;
  }

  Future<void> load() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    if (_isLoading || _rewardedAd != null) return;
    _isLoading = true;
    await RewardedAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isLoading = false;
        },
        onAdFailedToLoad: (_) {
          _rewardedAd = null;
          _isLoading = false;
        },
      ),
    );
  }

  Future<void> showSupportAd({
    required VoidCallback onRewarded,
    required VoidCallback onNotReady,
    required void Function(String message) onFailedToShow,
  }) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      onFailedToShow('Support ads are only available on mobile devices.');
      return;
    }
    final ad = _rewardedAd;
    if (ad == null) {
      onNotReady();
      await load();
      return;
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        load();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _rewardedAd = null;
        onFailedToShow('Could not show support ad: ${error.message}');
        load();
      },
    );

    await ad.show(
      onUserEarnedReward: (_, __) => onRewarded(),
    );
  }
}
