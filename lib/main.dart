import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/core/billing/business_entitlement_service.dart';
import 'src/core/notifications/notification_service.dart';
import 'src/core/ads/support_rewarded_ad_service.dart';
import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

  await BusinessEntitlementService.instance.initialize(
    user: Supabase.instance.client.auth.currentUser,
  );

  // Only initialize mobile ads on supported (mobile) platforms.
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    await MobileAds.instance.initialize();
    SupportRewardedAdService.instance.load();
  }

  await NotificationService.instance.init();

  runApp(const MoneyManagementApp());
}
