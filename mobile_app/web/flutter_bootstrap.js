{{flutter_js}}
{{flutter_build_config}}

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.getRegistrations().then((regs) => {
    for (const registration of regs) {
      registration.unregister();
    }
  });
}

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
  onEntrypointLoaded: async function (engineInitializer) {
    try {
      const appRunner = await engineInitializer.initializeEngine();
      const running = appRunner.runApp();
      if (running && typeof running.then === 'function') {
        running.catch(function (err) {
          console.error(err);
        });
      }
    } catch (err) {
      console.error(err);
      const loading = document.getElementById('loading');
      if (loading) {
        loading.innerHTML = '<p>Drop non si e avviato. Ricarica la pagina.</p>';
      }
    }
  },
});
