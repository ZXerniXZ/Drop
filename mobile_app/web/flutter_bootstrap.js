{{flutter_js}}
{{flutter_build_config}}

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.getRegistrations().then((regs) => {
    for (const registration of regs) {
      registration.unregister();
    }
  });
}

const flutterHost = document.getElementById("flutter-host");
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
    ...(flutterHost ? { hostElement: flutterHost } : {}),
  },
});
