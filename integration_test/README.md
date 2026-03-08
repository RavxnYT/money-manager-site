# Integration Test Automation

Run the full end-to-end flow on a connected Android phone:

`flutter test integration_test/e2e_max_flow_test.dart -d <device-id> --dart-define=E2E_EMAIL=<your-email> --dart-define=E2E_PASSWORD=<your-password> --dart-define=E2E_APP_LOCK_PASSCODE=<passcode-if-enabled>`

If app lock is not enabled, you can omit `E2E_APP_LOCK_PASSCODE`.

Find your device id with:

`flutter devices`
