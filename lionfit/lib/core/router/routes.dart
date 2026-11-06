/// Every URL in the app, in one place.
abstract final class Routes {
  static const landing = '/';
  static const login = '/login';
  static const signUp = '/signup';

  /// The onboarding survey. Signed-in users are sent here until it is done.
  static const welcome = '/welcome';

  // The five tabs, in navigation-bar order.
  static const home = '/home';
  static const history = '/history';
  static const logWorkout = '/log';
  static const muscleMap = '/map';
  static const profile = '/profile';

  /// Admin tools. Only for `profiles.role = 'admin'`; members are redirected.
  static const admin = '/admin';

  /// What LionFit does with Health Connect data. Health Connect links here
  /// from its permission screen (via MainActivity.kt).
  static const healthPrivacy = '/health-privacy';

  /// Routes a signed-out visitor may see. A signed-in user is sent from any
  /// of these to [home] - the landing page is for signed-out visitors only.
  static const public = {landing, login, signUp};

  /// Routes anyone may see, signed in or out, survey done or not. A privacy
  /// policy has to be readable before anyone agrees to anything.
  static const open = {healthPrivacy};

  static const tabs = [home, history, logWorkout, muscleMap, profile];
}
