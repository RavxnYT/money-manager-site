import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

String friendlyErrorMessage(Object? error) {
  if (error == null) return 'Something went wrong. Please try again.';

  if (error is AuthApiException) {
    switch (error.code) {
      case 'over_email_send_rate_limit':
        return 'Too many email requests. Please wait a few minutes, then try again.';
      case 'email_address_not_authorized':
        return 'Sender email is not authorized in your SMTP provider. Verify your sender in Brevo.';
      case 'smtp_fail':
        return 'SMTP server rejected the email. Check Brevo SMTP username/password and sender email.';
      case 'validation_failed':
        return 'Email request validation failed. Check redirect URL and email settings.';
      case 'user_already_exists':
        return 'An account with this email already exists. Try signing in instead.';
      case 'invalid_credentials':
        return 'Email or password is incorrect.';
      case 'email_not_confirmed':
        return 'Please verify your email address before signing in.';
      case 'signup_disabled':
        return 'New account signup is currently disabled.';
      default:
        final message = error.message.trim();
        if (message.isNotEmpty) return message;
        return 'Authentication failed. Please check your details and try again.';
    }
  }

  if (error is PostgrestException) {
    final msg = (error.message).toLowerCase();
    if (msg.contains('insufficient balance')) {
      return 'Not enough balance in the selected account.';
    }
    if (msg.contains('account not found')) {
      return 'Selected account was not found. Please choose another account.';
    }
    if (msg.contains('savings goal not found')) {
      return 'Savings goal was not found. Please refresh and try again.';
    }
    if (msg.contains('violates foreign key constraint')) {
      return 'This item is still used by transactions. Update/delete related transactions first.';
    }
    return 'Database request failed. Please try again.';
  }

  if (error is SocketException) {
    return 'No internet connection. Please check your network and try again.';
  }

  return 'Something went wrong. Please try again.';
}
