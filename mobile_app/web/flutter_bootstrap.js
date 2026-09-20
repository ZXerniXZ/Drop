{{flutter_js}}
{{flutter_build_config}}

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.getRegistrations().then((regs) => {
    for (const registration of regs) {
      registration.unregister();
    }
  });
}

function bootStatus(message) {
  const el = document.getElementById('boot-status');
  if (el) el.textContent = message;
}

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
  onEntrypointLoaded: async function (engineInitializer) {
    try {
      bootStatus('Avvio…');
      const host = document.getElementById('flutter-host');
      const appRunner = await engineInitializer.initializeEngine({
        hostElement: host || undefined,
      });
      await appRunner.runApp();
    } catch (err) {
      console.error(err);
      bootStatus('Drop non si e avviato. Ricarica la pagina.');
    }
  },
});
