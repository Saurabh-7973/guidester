import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What the auth events add up to, for the router and the session overlay.
class SessionState extends ChangeNotifier {
  bool _hadSession = false;
  bool _loggingOut = false;

  /// Signed out without asking to be (§5.6 row 14): the page stays and a
  /// login sits over it, instead of a redirect that loses the page.
  bool expired = false;

  /// Between opening a password-reset link and saving the new password.
  bool recovering = false;

  /// The address to offer when asking to log back in.
  String? lastEmail;

  void onEvent(AuthChangeEvent event, String? email) {
    if (email != null) lastEmail = email;
    switch (event) {
      case AuthChangeEvent.signedIn ||
          AuthChangeEvent.tokenRefreshed ||
          AuthChangeEvent.initialSession ||
          AuthChangeEvent.userUpdated:
        if (email != null) _hadSession = true;
        expired = false;
      case AuthChangeEvent.passwordRecovery:
        _hadSession = true;
        recovering = true;
      case AuthChangeEvent.signedOut:
        expired = _hadSession && !_loggingOut;
        recovering = false;
        _loggingOut = false;
        if (!expired) _hadSession = false;
      default:
    }
    notifyListeners();
  }

  /// Call before a sign-out the user asked for.
  void loggingOut() {
    _loggingOut = true;
    expired = false;
  }

  void recoveryFinished() {
    recovering = false;
    notifyListeners();
  }
}
