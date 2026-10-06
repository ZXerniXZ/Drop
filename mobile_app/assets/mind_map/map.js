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

  function compileExpr(source) {
    if (typeof source !== 'string' || /[;=`]|import\b/i.test(source)) {
      throw new Error('rejected');
    }
    return window.math.compile(source);
  }

  function finite(value) {
    const number = typeof value === 'number' ? value : Number(value);
    return Number.isFinite(number) ? number : null;
  }

  function linspace(span, steps) {
    const values = [];
    const low = span[0];
    const high = span[1];
    for (let i = 0; i < steps; i += 1) {
      values.push(low + (high - low) * (steps === 1 ? 0 : i / (steps - 1)));
    }
    return values;
  }

  function isWide() {
    return window.innerWidth >= 960;
  }

  function plotBox(host) {
    const width = Math.max(1, Math.floor(host.clientWidth || host.parentElement.clientWidth || 280));
    const height = isWide()
      ? Math.round(Math.min(460, Math.max(300, window.innerHeight * 0.5)))
      : Math.round(Math.min(210, Math.max(150, window.innerHeight * 0.3)));
    host.style.height = height + 'px';
    return { width: width, height: height };
  }

  function axisStyle() {
    return {
      color: mutedColor(),
      gridcolor: gridColor(),
      zerolinecolor: gridColor(),
      automargin: true,
      tickfont: { size: isWide() ? 12 : 10, color: mutedColor() },
    };
  }

  function plotLayout() {
    const ink = inkColor();
    const paper = panelColor();
    const margin = isWide()
      ? { l: 48, r: 16, t: 16, b: 40 }
      : { l: 28, r: 6, t: 8, b: 24 };
    return {
      paper_bgcolor: paper,
      plot_bgcolor: paper,
      font: { color: ink, family: 'sans-serif', size: isWide() ? 13 : 11 },
      margin: margin,
      xaxis: axisStyle(),
      yaxis: axisStyle(),
      legend: {
        font: { color: ink, size: 11 },
        bgcolor: 'rgba(0,0,0,0)',
        orientation: 'h',
        x: 0,
        y: 1,
        xanchor: 'left',
        yanchor: 'top',
      },
    };
  }

  function sceneAxes() {
    const ink = inkColor();
    const size = isWide() ? 11 : 9;
    const axis = {
      color: ink,
      gridcolor: gridColor(),
      backgroundcolor: panelColor(),
      tickfont: { size: size, color: ink },
      titlefont: { size: size, color: ink },
      showspikes: false,
    };
    return {
      xaxis: axis,
      yaxis: Object.assign({}, axis),
      zaxis: Object.assign({}, axis),
      bgcolor: panelColor(),
      aspectmode: 'cube',
    };
  }

  function showPlot(host, figure, layout) {
    const box = plotBox(host);
    layout.width = box.width;
    layout.height = box.height;
    window.Plotly.newPlot(host, figure, layout, {
      displayModeBar: false,
      responsive: false,
      scrollZoom: false,
      staticPlot: false,
    });
  }

  function plotCard(title, draw) {
    const figure = document.createElement('figure');
    if (title) {
      const caption = document.createElement('figcaption');
      caption.textContent = title;
      figure.appendChild(caption);
    }
    const host = document.createElement('div');
    host.className = 'plot';
    figure.appendChild(host);
    sheetVisuals.appendChild(figure);
    try {
      draw(host);
    } catch (error) {
      host.className = 'plot-error';
      host.textContent = 'Grafico non disponibile';
    }
  }

  function renderPlot2d(visual) {
    plotCard(visual.title, function (host) {
      const xs = linspace(visual.x, 80);
      const ink = inkColor();
      const traces = visual.expressions.map(function (expression, index) {
        const compiled = compileExpr(expression);
        return {
          type: 'scatter',
          mode: 'lines',
          name: expression,
          x: xs,
          y: xs.map(function (x) { return finite(compiled.evaluate({ x: x })); }),
          line: { color: index === 0 ? ink : mutedColor(), width: 1.5 },
        };
      });
      const layout = plotLayout();
      layout.showlegend = traces.length > 1;
      showPlot(host, traces, layout);
    });
  }

  function renderSurface(visual) {
    plotCard(visual.title, function (host) {
      const compiled = compileExpr(visual.expression);
      const xs = linspace(visual.x, 28);
      const ys = linspace(visual.y, 28);
      const z = ys.map(function (y) {
        return xs.map(function (x) { return finite(compiled.evaluate({ x: x, y: y })); });
      });
      const ink = inkColor();
      const layout = plotLayout();
      layout.scene = sceneAxes();
      layout.margin = { l: 0, r: 0, t: 0, b: 0 };
      showPlot(host, [{
        type: 'surface',
        x: xs,
        y: ys,
        z: z,
        colorscale: [[0, dark ? '#3f3f46' : '#d4d4d8'], [1, ink]],
        showscale: false,
      }], layout);
    });
  }

  function renderCurve(visual) {
    plotCard(visual.title, function (host) {
      const xExpr = compileExpr(visual.x);
      const yExpr = compileExpr(visual.y);
      const zExpr = compileExpr(visual.z);
      const ts = linspace(visual.t, 160);
      const layout = plotLayout();
      const ink = inkColor();
      layout.scene = sceneAxes();
      layout.margin = { l: 0, r: 0, t: 0, b: 0 };
      showPlot(host, [{
        type: 'scatter3d',
        mode: 'lines',
        x: ts.map(function (t) { return finite(xExpr.evaluate({ t: t })); }),
        y: ts.map(function (t) { return finite(yExpr.evaluate({ t: t })); }),
        z: ts.map(function (t) { return finite(zExpr.evaluate({ t: t })); }),
        line: { color: ink, width: 4 },
      }], layout);
    });
  }

  function renderChart(visual) {
    plotCard(visual.title, function (host) {
      const ink = inkColor();
      const traces = (visual.series || []).map(function (serie, index) {
        const color = index === 0 ? ink : mutedColor();
        if (visual.type === 'line') {
          return {
            type: 'scatter',
            mode: 'lines+markers',
            name: serie.name,
            x: visual.labels,
            y: serie.values,
            line: { color: color, width: 1.5 },
            marker: { color: color, size: 6 },
          };
        }
        return {
          type: 'bar',
          name: serie.name,
          x: visual.labels,
          y: serie.values,
          marker: { color: color },
        };
      });
      const layout = plotLayout();
      layout.showlegend = traces.length > 1;
      layout.barmode = 'group';
      showPlot(host, traces, layout);
    });
  }

  function renderVisual(visual) {
    if (!visual || typeof visual !== 'object') return;
    if (visual.kind === 'plot2d') renderPlot2d(visual);
    else if (visual.kind === 'surface3d') renderSurface(visual);
    else if (visual.kind === 'curve3d') renderCurve(visual);
    else if (visual.kind === 'chart') renderChart(visual);
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
    if (sheet.hidden || !window.Plotly) return;
    sheetVisuals.querySelectorAll('.plot').forEach(function (host) {
      if (!host.data) return;
      const box = plotBox(host);
      window.Plotly.relayout(host, { width: box.width, height: box.height });
    });
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
