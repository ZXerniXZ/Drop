{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
  onEntrypointLoaded: async function (engineInitializer) {
    try {
      const appRunner = await engineInitializer.initializeEngine();
      const loading = document.getElementById('loading');
      if (loading) loading.remove();
      // Do not await runApp: a later Dart timeout must not wipe the page.
      appRunner.runApp();
    } catch (err) {
      console.error(err);
      const loading = document.getElementById('loading');
      if (loading) {
        loading.innerHTML = '<p>Drop non si e avviato. Ricarica la pagina.</p>';
      }
    }
  },
});

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.getRegistration().then((registration) => {
    if (!registration) return;
    registration.addEventListener('updatefound', () => {
      const installing = registration.installing;
      if (!installing) return;
      installing.addEventListener('statechange', () => {
        if (installing.state === 'installed' && navigator.serviceWorker.controller) {
          const bar = document.getElementById('sw-update');
          if (bar) bar.hidden = false;
        }
      });
    });
  });
  document.getElementById('sw-reload')?.addEventListener('click', () => {
    window.location.reload();
  });
}
