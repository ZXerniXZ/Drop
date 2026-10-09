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

  window.DropMap = {
    render: function (data, isDark) {
      applyTheme(isDark);
      const tree = toTree(data || {});
      if (!mm) {
        mm = window.markmap.Markmap.create(svg, options(), tree);
      } else {
        mm.setData(tree, options()).then(function () { mm.fit(); });
      }
      svg.style.setProperty('--markmap-text-color', inkColor());
      svg.style.setProperty('--markmap-circle-open-bg', panelColor());
    },
    fit: function () {
      if (mm) mm.fit();
    },
  };

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

  post({ type: 'ready' });

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
