class WebSession {
  WebSession._();

  static bool get isIosSafari => false;

  static bool get isStandalone => false;

  static bool get shouldPromptHomeScreenInstall => false;

  static void reload() {}
}
