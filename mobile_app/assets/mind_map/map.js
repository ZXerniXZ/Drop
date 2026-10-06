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

  const FUNCTION_ALIASES = {
    ln: 'log',
    sen: 'sin',
    tg: 'tan',
    arcsin: 'asin',
    arccos: 'acos',
    arctan: 'atan',
    arctg: 'atan',
    sh: 'sinh',
    ch: 'cosh',
    th: 'tanh',
  };

  const KNOWN_SYMBOLS = { x: 1, y: 1, t: 1, pi: 1, e: 1, PI: 1, E: 1, Infinity: 1 };

  function normalizeExpr(source) {
    let text = String(source == null ? '' : source).trim();
    const eq = text.lastIndexOf('=');
    if (eq >= 0 && text[eq - 1] !== '<' && text[eq - 1] !== '>' && text[eq - 1] !== '!') {
      text = text.slice(eq + 1);
    }
    text = text
      .replace(/\$/g, '')
      .replace(/\\cdot|\\times/g, '*')
      .replace(/\\left|\\right/g, '')
      .replace(/\\(sin|cos|tan|log|ln|exp|sqrt|pi)\b/g, '$1')
      .replace(/[−–—]/g, '-')
      .replace(/[×·∙⋅]/g, '*')
      .replace(/÷/g, '/')
      .replace(/π/g, 'pi')
      .replace(/√\s*\(/g, 'sqrt(')
      .replace(/√\s*([a-zA-Z0-9.]+)/g, 'sqrt($1)')
      .replace(/²/g, '^2')
      .replace(/³/g, '^3')
      .replace(/\*\*/g, '^')
      .replace(/\{/g, '(')
      .replace(/\}/g, ')')
      .replace(/\|([^|]+)\|/g, 'abs($1)');
    text = text.replace(/\b([a-zA-Z]+)\s*\(/g, function (match, name) {
      const alias = FUNCTION_ALIASES[name.toLowerCase()];
      return alias ? alias + '(' : match;
    });
    return text.trim();
  }

  function compileExpr(source) {
    if (typeof source !== 'string' || /[;`]|import\b/i.test(source)) {
      throw new Error('rejected');
    }
    const text = normalizeExpr(source);
    if (!text) throw new Error('empty');
    const node = window.math.parse(text);
    const scope = {};
    node.traverse(function (child, path, parent) {
      if (child.type !== 'SymbolNode') return;
      const isCall = parent && parent.type === 'FunctionNode' && path === 'fn';
      if (isCall || KNOWN_SYMBOLS[child.name]) return;
      if (typeof window.math[child.name] === 'function') return;
      if (child.name in window.math) return;
      scope[child.name] = 1;
    });
    const compiled = node.compile();
    return {
      evaluate: function (vars) {
        try {
          return compiled.evaluate(Object.assign({}, scope, vars));
        } catch (error) {
          return null;
        }
      },
    };
  }

  function finite(value) {
    if (value == null) return null;
    if (typeof value === 'object' && typeof value.re === 'number') {
      if (Math.abs(value.im || 0) > 1e-9) return null;
      value = value.re;
    }
    const number = typeof value === 'number' ? value : Number(value);
    if (!Number.isFinite(number) || Math.abs(number) > 1e12) return null;
    return number;
  }

  function hasValues(values) {
    return values.some(function (value) { return value !== null; });
  }

  let webglState = null;

  function hasWebGL() {
    if (webglState !== null) return webglState;
    try {
      const canvas = document.createElement('canvas');
      webglState = !!(canvas.getContext('webgl') || canvas.getContext('experimental-webgl'));
    } catch (error) {
      webglState = false;
    }
    return webglState;
  }

  function span(value, fallback) {
    if (!Array.isArray(value) || value.length < 2) return fallback;
    let low = Number(value[0]);
    let high = Number(value[1]);
    if (!Number.isFinite(low) || !Number.isFinite(high) || low === high) return fallback;
    if (low > high) {
      const swap = low;
      low = high;
      high = swap;
    }
    return [low, high];
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
    const result = window.Plotly.newPlot(host, figure, layout, {
      displayModeBar: false,
      responsive: false,
      scrollZoom: false,
      staticPlot: false,
    });
    return result && typeof result.then === 'function' ? result : Promise.resolve();
  }

  function plotCard(title, attempts) {
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

    function fail() {
      if (window.Plotly) {
        try { window.Plotly.purge(host); } catch (error) { /* already empty */ }
      }
      figure.remove();
      syncVisualColumn();
    }

    function attempt(index) {
      if (index >= attempts.length) {
        fail();
        return;
      }
      let pending;
      try {
        pending = attempts[index](host);
      } catch (error) {
        if (window.Plotly) {
          try { window.Plotly.purge(host); } catch (ignored) { /* nothing drawn */ }
        }
        host.innerHTML = '';
        attempt(index + 1);
        return;
      }
      Promise.resolve(pending).catch(function () {
        if (window.Plotly) {
          try { window.Plotly.purge(host); } catch (ignored) { /* nothing drawn */ }
        }
        host.innerHTML = '';
        attempt(index + 1);
      });
    }

    if (!window.Plotly || !window.math) {
      fail();
      return;
    }
    attempt(0);
  }

  function expressionList(visual) {
    const raw = Array.isArray(visual.expressions)
      ? visual.expressions
      : (visual.expression != null ? [visual.expression] : []);
    return raw.filter(function (item) { return typeof item === 'string' && item.trim(); });
  }

  function renderPlot2d(visual) {
    const xs = linspace(span(visual.x, [-5, 5]), 160);
    plotCard(visual.title, [function (host) {
      const ink = inkColor();
      const traces = [];
      expressionList(visual).forEach(function (expression) {
        let compiled;
        try {
          compiled = compileExpr(expression);
        } catch (error) {
          return;
        }
        const ys = xs.map(function (x) { return finite(compiled.evaluate({ x: x })); });
        if (!hasValues(ys)) return;
        traces.push({
          type: 'scatter',
          mode: 'lines',
          name: expression,
          x: xs,
          y: ys,
          connectgaps: false,
          line: { color: traces.length === 0 ? ink : mutedColor(), width: 1.5 },
        });
      });
      if (traces.length === 0) throw new Error('no data');
      const layout = plotLayout();
      layout.showlegend = traces.length > 1;
      return showPlot(host, traces, layout);
    }]);
  }

  function surfaceGrid(visual) {
    const compiled = compileExpr(visual.expression);
    const xs = linspace(span(visual.x, [-2, 2]), 32);
    const ys = linspace(span(visual.y, [-2, 2]), 32);
    const z = ys.map(function (y) {
      return xs.map(function (x) { return finite(compiled.evaluate({ x: x, y: y })); });
    });
    if (!z.some(hasValues)) throw new Error('no data');
    return { xs: xs, ys: ys, z: z };
  }

  function renderSurface(visual) {
    const ink = inkColor();
    const colors = [[0, dark ? '#3f3f46' : '#d4d4d8'], [1, ink]];
    const grid = surfaceGrid(visual);
    const draw3d = function (host) {
      if (!hasWebGL()) throw new Error('no webgl');
      const layout = plotLayout();
      layout.scene = sceneAxes();
      layout.margin = { l: 0, r: 0, t: 0, b: 0 };
      return showPlot(host, [{
        type: 'surface',
        x: grid.xs,
        y: grid.ys,
        z: grid.z,
        colorscale: colors,
        showscale: false,
      }], layout);
    };
    const drawSlices = function (host) {
      const picks = [0, 8, 16, 24, 31];
      const traces = picks.map(function (row, index) {
        const y = grid.ys[row];
        return {
          type: 'scatter',
          mode: 'lines',
          name: 'y = ' + (Math.round(y * 100) / 100),
          x: grid.xs,
          y: grid.z[row],
          line: { color: index === 2 ? ink : mutedColor(), width: index === 2 ? 1.8 : 1.1 },
        };
      }).filter(function (trace) { return hasValues(trace.y); });
      if (traces.length === 0) throw new Error('no data');
      const layout = plotLayout();
      layout.showlegend = true;
      return showPlot(host, traces, layout);
    };
    plotCard(visual.title, [draw3d, drawSlices]);
  }

  function renderCurve(visual) {
    const ink = inkColor();
    const ts = linspace(span(visual.t, [0, 2 * Math.PI]), 240);
    const xExpr = compileExpr(visual.x);
    const yExpr = compileExpr(visual.y);
    const zExpr = compileExpr(visual.z);
    const xs = ts.map(function (t) { return finite(xExpr.evaluate({ t: t })); });
    const ys = ts.map(function (t) { return finite(yExpr.evaluate({ t: t })); });
    const zs = ts.map(function (t) { return finite(zExpr.evaluate({ t: t })); });
    if (!hasValues(xs) || !hasValues(ys)) throw new Error('no data');
    const draw3d = function (host) {
      if (!hasWebGL() || !hasValues(zs)) throw new Error('no webgl');
      const layout = plotLayout();
      layout.scene = sceneAxes();
      layout.margin = { l: 0, r: 0, t: 0, b: 0 };
      return showPlot(host, [{
        type: 'scatter3d',
        mode: 'lines',
        x: xs,
        y: ys,
        z: zs,
        line: { color: ink, width: 4 },
      }], layout);
    };
    const drawFlat = function (host) {
      const layout = plotLayout();
      layout.yaxis.scaleanchor = 'x';
      return showPlot(host, [{
        type: 'scatter',
        mode: 'lines',
        x: xs,
        y: ys,
        line: { color: ink, width: 1.5 },
      }], layout);
    };
    plotCard(visual.title, [draw3d, drawFlat]);
  }

  function chartNumber(value) {
    if (typeof value === 'number') return finite(value);
    if (typeof value !== 'string') return null;
    const cleaned = value.replace(/[^0-9,.\-eE]/g, '').replace(',', '.');
    return finite(cleaned === '' ? null : Number(cleaned));
  }

  function renderChart(visual) {
    const ink = inkColor();
    const labels = Array.isArray(visual.labels) ? visual.labels.map(String) : [];
    const rawSeries = Array.isArray(visual.series) ? visual.series : [];
    const series = rawSeries
      .map(function (serie, index) {
        const values = Array.isArray(serie && serie.values) ? serie.values.map(chartNumber) : [];
        return {
          name: (serie && serie.name) ? String(serie.name) : 'Serie ' + (index + 1),
          values: values,
        };
      })
      .filter(function (serie) { return hasValues(serie.values); });
    if (series.length === 0) throw new Error('no data');
    const count = Math.max.apply(null, series.map(function (serie) { return serie.values.length; }));
    const xs = [];
    for (let i = 0; i < count; i += 1) xs.push(labels[i] != null ? labels[i] : String(i + 1));
    plotCard(visual.title, [function (host) {
      const traces = series.map(function (serie, index) {
        const color = index === 0 ? ink : mutedColor();
        if (visual.type === 'line') {
          return {
            type: 'scatter',
            mode: 'lines+markers',
            name: serie.name,
            x: xs,
            y: serie.values,
            line: { color: color, width: 1.5 },
            marker: { color: color, size: 6 },
          };
        }
        return {
          type: 'bar',
          name: serie.name,
          x: xs,
          y: serie.values,
          marker: { color: color },
        };
      });
      const layout = plotLayout();
      layout.showlegend = traces.length > 1;
      layout.barmode = 'group';
      layout.xaxis.type = 'category';
      return showPlot(host, traces, layout);
    }]);
  }

  function syncVisualColumn() {
    sheetScroll.classList.toggle('has-visuals', !!sheetVisuals.querySelector('figure'));
  }

  function renderVisual(visual) {
    if (!visual || typeof visual !== 'object') return;
    try {
      if (visual.kind === 'plot2d') renderPlot2d(visual);
      else if (visual.kind === 'surface3d') renderSurface(visual);
      else if (visual.kind === 'curve3d') renderCurve(visual);
      else if (visual.kind === 'chart') renderChart(visual);
    } catch (error) {
      /* a visual that cannot be drawn is left out */
    }
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
