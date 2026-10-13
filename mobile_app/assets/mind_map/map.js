(function () {
  const svg = document.getElementById('map');
  const sheet = document.getElementById('sheet');
  const sheetTitle = document.getElementById('sheet-title');
  const sheetBody = document.getElementById('sheet-body');
  const sheetVisuals = document.getElementById('sheet-visuals');
  const sheetScroll = document.getElementById('sheet-scroll');
  const byId = new Map();
  let mm = null;
  let dark = false;

  // Su Android il WebView misura 0 le foreignObject di markmap: il layout
  // collassa e fit() manda l'albero fuori dallo schermo. Se la misura nativa
  // è vuota, stimiamo il testo e teniamo un rettangolo reale.
  (function installMeasureFallback() {
    const Markmap = window.markmap && window.markmap.Markmap;
    if (!Markmap || !Markmap.prototype || Markmap.prototype.__dropMeasured) return;
    Markmap.prototype.__dropMeasured = true;
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');
    const originalRelayout = Markmap.prototype._relayout;
    const originalFit = Markmap.prototype.fit;

    function measureText(text, maxWidth) {
      const raw = String(text || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim() || ' ';
      ctx.font = '300 16px sans-serif';
      const natural = ctx.measureText(raw).width;
      const limit = Math.max(48, maxWidth || 200);
      const width = Math.max(24, Math.min(natural + 12, limit));
      const lines = Math.max(1, Math.ceil(natural / width));
      return [Math.ceil(width), lines * 22];
    }

    function pinScroll(el, size) {
      try {
        Object.defineProperty(el, 'scrollWidth', {
          configurable: true,
          get: function () { return size[0]; },
        });
        Object.defineProperty(el, 'scrollHeight', {
          configurable: true,
          get: function () { return size[1]; },
        });
      } catch (error) {}
    }

    function layoutFallback(mm) {
      const data = mm.state && mm.state.data;
      if (!data) return;
      const gapX = (mm.options && mm.options.spacingHorizontal) || 80;
      const gapY = (mm.options && mm.options.spacingVertical) || 12;
      const maxWidth = (mm.options && mm.options.maxWidth) || 200;
      let y = 0;
      let maxRight = 0;
      function place(node, depth) {
        const size = measureText(node.content, maxWidth);
        const x = depth * gapX;
        node.state = node.state || {};
        node.state.size = size;
        node.state.rect = { x: x, y: y, width: size[0], height: size[1] };
        maxRight = Math.max(maxRight, x + size[0]);
        y += size[1] + gapY;
        const folded = node.payload && node.payload.fold;
        const children = folded ? [] : (node.children || []);
        children.forEach(function (child) { place(child, depth + 1); });
      }
      place(data, 0);
      mm.state.rect = { x1: 0, y1: 0, x2: Math.max(maxRight, 1), y2: Math.max(y, 1) };
    }

    Markmap.prototype._relayout = function () {
      const maxWidth = (this.options && this.options.maxWidth) || 200;
      if (this.g) {
        this.g.selectAll('foreignObject').each(function (d) {
          const inner = this.firstChild && this.firstChild.firstChild;
          const text = inner ? inner.textContent : (d && d.content) || '';
          const size = measureText(text, maxWidth);
          this.setAttribute('width', String(size[0]));
          this.setAttribute('height', String(size[1]));
          if (inner && !(inner.scrollWidth > 2 && inner.scrollHeight > 2)) {
            pinScroll(inner, size);
          }
        });
      }
      const result = originalRelayout.call(this);
      const rect = this.state && this.state.rect;
      const width = rect ? rect.x2 - rect.x1 : 0;
      const height = rect ? rect.y2 - rect.y1 : 0;
      if (!(width > 1) || !(height > 1)) layoutFallback(this);
      return result;
    };

    Markmap.prototype.fit = function (maxScale) {
      const rect = this.state && this.state.rect;
      const width = rect ? rect.x2 - rect.x1 : 0;
      const height = rect ? rect.y2 - rect.y1 : 0;
      if (!(width > 1) || !(height > 1)) return Promise.resolve();
      return originalFit.call(this, maxScale);
    };
  })();

  if (window.math && window.math.import) {
    window.math.import({
      import: function () { throw new Error('disabled'); },
      createUnit: function () { throw new Error('disabled'); },
      reviver: function () { throw new Error('disabled'); },
    }, { override: true });
  }

  function post(message) {
    const raw = JSON.stringify(message);
    if (window.DropBridge && typeof window.DropBridge.postMessage === 'function') {
      window.DropBridge.postMessage(raw);
    }
    if (window.parent && window.parent !== window) {
      window.parent.postMessage(raw, '*');
    }
  }

  function escapeHtml(text) {
    return String(text).replace(/[&<>"']/g, function (ch) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch];
    });
  }

  function sanitize(html) {
    const template = document.createElement('template');
    template.innerHTML = html;
    const blocked = { SCRIPT: 1, IFRAME: 1, OBJECT: 1, EMBED: 1, LINK: 1, META: 1, STYLE: 1 };
    template.content.querySelectorAll('*').forEach(function (el) {
      if (blocked[el.tagName]) {
        el.remove();
        return;
      }
      Array.from(el.attributes).forEach(function (attr) {
        const name = attr.name.toLowerCase();
        const value = attr.value.trim().toLowerCase();
        if (name.indexOf('on') === 0 || value.indexOf('javascript:') === 0) {
          el.removeAttribute(attr.name);
        }
      });
    });
    return template.innerHTML;
  }

  function applyTheme(isDark) {
    dark = !!isDark;
    document.documentElement.dataset.theme = dark ? 'dark' : 'light';
  }

  function lineColor() {
    return getComputedStyle(document.documentElement).getPropertyValue('--line').trim() || '#888';
  }

  function inkColor() {
    return getComputedStyle(document.documentElement).getPropertyValue('--ink').trim() || '#111';
  }

  function mutedColor() {
    return getComputedStyle(document.documentElement).getPropertyValue('--muted').trim() || '#888';
  }

  function panelColor() {
    return getComputedStyle(document.documentElement).getPropertyValue('--panel').trim() || '#fff';
  }

  function gridColor() {
    return getComputedStyle(document.documentElement).getPropertyValue('--grid').trim() || '#eee';
  }

  function options() {
    const wide = window.innerWidth >= 960;
    return {
      duration: 200,
      maxWidth: wide ? 420 : 200,
      spacingVertical: wide ? 18 : 10,
      spacingHorizontal: wide ? 140 : 56,
      paddingX: wide ? 16 : 8,
      initialExpandLevel: 2,
      scrollForPan: false,
      color: function () { return lineColor(); },
      lineWidth: function () { return 1.25; },
    };
  }

  function toNode(node, id) {
    byId.set(id, node);
    const children = Array.isArray(node.children) ? node.children : [];
    return {
      content: escapeHtml(node.title || ''),
      payload: { dropId: id },
      children: children.map(function (child, index) {
        return toNode(child, id + '.' + index);
      }),
    };
  }

  function toTree(data) {
    byId.clear();
    const nodes = Array.isArray(data && data.nodes) ? data.nodes : [];
    const root = {
      title: (data && data.title) || 'Mappa',
      body: '',
      visuals: [],
      children: nodes,
    };
    return toNode(root, 'root');
  }

  function syncVisualColumn() {
    sheetScroll.classList.toggle('has-visuals', !!sheetVisuals.querySelector('figure'));
  }

  function renderVisual(visual) {
    if (!window.DropPlot || !visual || typeof visual !== 'object') return;
    window.DropPlot.render(sheetVisuals, visual, { onChange: syncVisualColumn });
  }

  function closeSheet() {
    sheet.hidden = true;
    sheetVisuals.querySelectorAll('.plot').forEach(function (host) {
      if (window.Plotly) window.Plotly.purge(host);
    });
    sheetBody.innerHTML = '';
    sheetVisuals.innerHTML = '';
  }

  function openSheet(id) {
    const node = byId.get(id);
    if (!node) return;
    const body = (node.body || '').trim();
    const visuals = Array.isArray(node.visuals) ? node.visuals : [];
    if (!body && visuals.length === 0) return;
    sheetTitle.textContent = node.title || '';
    const html = body && window.marked ? window.marked.parse(body, { async: false, breaks: true }) : '';
    sheetBody.innerHTML = sanitize(typeof html === 'string' ? html : '');
    if (window.renderMathInElement) {
      window.renderMathInElement(sheetBody, {
        delimiters: [
          { left: '$$', right: '$$', display: true },
          { left: '$', right: '$', display: false },
        ],
        throwOnError: false,
        ignoredTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code', 'option'],
      });
    }
    sheetVisuals.innerHTML = '';
    sheetScroll.classList.toggle('has-visuals', visuals.length > 0);
    sheet.hidden = false;
    requestAnimationFrame(function () {
      visuals.forEach(renderVisual);
      syncVisualColumn();
    });
  }

  function fitSoon() {
    if (!mm) return;
    const rect = svg.getBoundingClientRect();
    if (rect.width < 8 || rect.height < 8) return;
    mm.fit();
  }

  window.DropMap = {
    render: function (data, isDark) {
      applyTheme(isDark);
      const tree = toTree(data || {});
      try {
        if (!mm) {
          mm = window.markmap.Markmap.create(svg, options(), tree);
          requestAnimationFrame(fitSoon);
        } else {
          mm.setData(tree, options()).then(fitSoon);
        }
      } catch (error) {
        post({ type: 'error', message: String(error && error.message || error) });
      }
      svg.style.setProperty('--markmap-text-color', inkColor());
      svg.style.setProperty('--markmap-circle-open-bg', panelColor());
    },
    fit: function () {
      fitSoon();
    },
  };

  if (window.ResizeObserver) {
    new ResizeObserver(fitSoon).observe(svg);
  }

  svg.addEventListener('click', function (event) {
    if (event.target.closest('circle')) return;
    const group = event.target.closest('g.markmap-node');
    if (!group) return;
    const datum = window.d3.select(group).datum();
    const id = datum && datum.payload && datum.payload.dropId;
    if (id) openSheet(id);
  });

  document.getElementById('sheet-close').addEventListener('click', closeSheet);
  document.addEventListener('keydown', function (event) {
    if (event.key === 'Escape' && !sheet.hidden) closeSheet();
  });
  window.addEventListener('resize', function () {
    if (sheet.hidden || !window.DropPlot) return;
    window.DropPlot.resize(sheetVisuals);
  });

  window.addEventListener('message', function (event) {
    let data = event.data;
    if (typeof data === 'string') {
      try { data = JSON.parse(data); } catch (error) { return; }
    }
    if (!data || typeof data !== 'object') return;
    if (data.type === 'render') window.DropMap.render(data.payload, data.dark);
    if (data.type === 'fit') window.DropMap.fit();
  });

  function announceReady(attempt) {
    post({ type: 'ready' });
    const bridged = window.DropBridge && typeof window.DropBridge.postMessage === 'function';
    const framed = window.parent && window.parent !== window;
    if (!bridged && !framed && attempt < 40) {
      setTimeout(function () { announceReady(attempt + 1); }, 50);
    }
  }
  announceReady(0);

  if (window.location.search.indexOf('demo=1') !== -1) {
    window.DropMap.render({
      title: 'Lezione',
      nodes: [
        {
          title: 'Paraboloide',
          body: 'La superficie è $z=x^2+y^2$.\n\n$$z = x^{2} + y^{2}$$',
          visuals: [
            { kind: 'plot2d', title: 'Sezione', expressions: ['x^2'], x: [-2, 2] },
            { kind: 'surface3d', title: 'Superficie', expression: 'x^2+y^2', x: [-2, 2], y: [-2, 2] },
          ],
          children: [
            { title: 'Elica', body: 'Una curva nello spazio.', visuals: [
              { kind: 'curve3d', title: 'Elica', x: 'cos(t)', y: 'sin(t)', z: 't/5', t: [0, 12.56] },
            ], children: [] },
          ],
        },
      ],
    }, window.matchMedia('(prefers-color-scheme: dark)').matches);
  }
})();
