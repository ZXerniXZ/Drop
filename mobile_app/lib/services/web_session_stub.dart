class WebSession {
  WebSession._();

  static bool get isIosSafari => false;

  static bool get isStandalone => false;

  static bool get shouldPromptHomeScreenInstall => false;

  static void reload() {}

  static void open(String url) {}

  static void openExternal(String url) {}

  static void listenForInstallPrompt() {}

  static bool get canPromptInstall => false;

  static Future<void> promptInstall() async {}

  static void hideHtmlSplash() {}
}
