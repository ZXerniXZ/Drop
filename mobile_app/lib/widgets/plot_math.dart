import 'dart:math' as math;

/// Valuta le espressioni dei grafici (sintassi math.js ridotta) senza WebView.
class PlotFunction {
  const PlotFunction._(this._eval);

  final double? Function(Map<String, double> vars) _eval;

  double? eval(Map<String, double> vars) {
    try {
      final value = _eval(vars);
      if (value == null || !value.isFinite || value.abs() > 1e12) return null;
      return value;
    } catch (_) {
      return null;
    }
  }

  static PlotFunction? tryParse(String source) {
    final text = normalizePlotExpr(source);
    if (text.isEmpty || text.contains(';') || text.contains('`')) return null;
    if (RegExp(r'import\b', caseSensitive: false).hasMatch(text)) return null;
    try {
      final parser = _Parser(text);
      final eval = parser.parse();
      return PlotFunction._(eval);
    } catch (_) {
      return null;
    }
  }
}

String normalizePlotExpr(String source) {
  var text = source.trim();
  final eq = text.lastIndexOf('=');
  if (eq >= 0) {
    final prev = eq > 0 ? text[eq - 1] : '';
    if (prev != '<' && prev != '>' && prev != '!') {
      text = text.substring(eq + 1);
    }
  }
  text = text
      .replaceAll(r'$', '')
      .replaceAll(RegExp(r'\\cdot|\\times'), '*')
      .replaceAll(RegExp(r'\\left|\\right'), '')
      .replaceAllMapped(
        RegExp(r'\\(sin|cos|tan|log|ln|exp|sqrt|pi)\b'),
        (match) => match.group(1)!,
      )
      .replaceAll(RegExp('[−–—]'), '-')
      .replaceAll(RegExp('[×·∙⋅]'), '*')
      .replaceAll('÷', '/')
      .replaceAll('π', 'pi')
      .replaceAllMapped(RegExp(r'√\s*\('), (_) => 'sqrt(')
      .replaceAllMapped(RegExp(r'√\s*([a-zA-Z0-9.]+)'), (m) => 'sqrt(${m[1]})')
      .replaceAll('²', '^2')
      .replaceAll('³', '^3')
      .replaceAll('**', '^')
      .replaceAll('{', '(')
      .replaceAll('}', ')')
      .replaceAllMapped(RegExp(r'\|([^|]+)\|'), (m) => 'abs(${m[1]})');
  const aliases = {
    'ln': 'log',
    'sen': 'sin',
    'tg': 'tan',
    'arcsin': 'asin',
    'arccos': 'acos',
    'arctan': 'atan',
    'arctg': 'atan',
  };
  text = text.replaceAllMapped(RegExp(r'\b([a-zA-Z]+)\s*\('), (match) {
    final alias = aliases[match.group(1)!.toLowerCase()];
    return alias == null ? match.group(0)! : '$alias(';
  });
  return text.trim();
}

typedef _Eval = double? Function(Map<String, double> vars);

class _Parser {
  _Parser(this.source);

  final String source;
  int index = 0;

  _Eval parse() {
    final eval = _expr();
    _skip();
    if (index != source.length) {
      throw const FormatException('trailing');
    }
    return eval;
  }

  void _skip() {
    while (index < source.length && source[index].trim().isEmpty) {
      index++;
    }
  }

  String _peek() {
    _skip();
    if (index >= source.length) return '';
    return source[index];
  }

  bool _eat(String op) {
    if (_peek() != op) return false;
    index++;
    return true;
  }

  _Eval _expr() {
    var left = _term();
    while (true) {
      final op = _peek();
      if (op != '+' && op != '-') break;
      index++;
      final right = _term();
      final lhs = left;
      left = (vars) {
        final a = lhs(vars);
        final b = right(vars);
        if (a == null || b == null) return null;
        return op == '+' ? a + b : a - b;
      };
    }
    return left;
  }

  _Eval _term() {
    var left = _unary();
    while (true) {
      final op = _peek();
      if (op != '*' && op != '/') break;
      index++;
      final right = _unary();
      final lhs = left;
      left = (vars) {
        final a = lhs(vars);
        final b = right(vars);
        if (a == null || b == null || (op == '/' && b == 0)) return null;
        return op == '*' ? a * b : a / b;
      };
    }
    return left;
  }

  _Eval _unary() {
    if (_eat('-')) {
      final inner = _unary();
      return (vars) {
        final value = inner(vars);
        return value == null ? null : -value;
      };
    }
    if (_eat('+')) return _unary();
    return _power();
  }

  _Eval _power() {
    final base = _primary();
    if (!_eat('^')) return base;
    final exponent = _unary();
    return (vars) {
      final a = base(vars);
      final b = exponent(vars);
      if (a == null || b == null) return null;
      return _pow(a, b);
    };
  }

  _Eval _primary() {
    _skip();
    if (index >= source.length) throw const FormatException('end');
    if (_eat('(')) {
      final inner = _expr();
      if (!_eat(')')) throw const FormatException('paren');
      return inner;
    }
    if (_isDigit(source[index]) || source[index] == '.') {
      return _number();
    }
    if (_isIdentStart(source[index])) {
      return _ident();
    }
    throw const FormatException('token');
  }

  _Eval _number() {
    final start = index;
    while (index < source.length && _isDigit(source[index])) {
      index++;
    }
    if (index < source.length && source[index] == '.') {
      index++;
      while (index < source.length && _isDigit(source[index])) {
        index++;
      }
    }
    if (index < source.length &&
        (source[index] == 'e' || source[index] == 'E')) {
      final mark = index;
      index++;
      if (index < source.length &&
          (source[index] == '+' || source[index] == '-')) {
        index++;
      }
      final expStart = index;
      while (index < source.length && _isDigit(source[index])) {
        index++;
      }
      if (index == expStart) index = mark;
    }
    final raw = source.substring(start, index);
    final number = double.tryParse(raw);
    if (number == null) throw const FormatException('number');
    return (_) => number;
  }

  _Eval _ident() {
    final start = index;
    index++;
    while (index < source.length && _isIdentPart(source[index])) {
      index++;
    }
    final name = source.substring(start, index);
    if (_eat('(')) {
      final args = <_Eval>[];
      if (_peek() != ')') {
        while (true) {
          args.add(_expr());
          if (_eat(',')) continue;
          break;
        }
      }
      if (!_eat(')')) throw const FormatException('call');
      final fn = _functions[name.toLowerCase()];
      if (fn == null || args.length != 1) {
        throw FormatException('fn $name');
      }
      final arg = args.single;
      return (vars) {
        final value = arg(vars);
        if (value == null) return null;
        return fn(value);
      };
    }
    final constant = _constants[name.toLowerCase()];
    if (constant != null) return (_) => constant;
    return (vars) => vars[name] ?? vars[name.toLowerCase()] ?? 1;
  }

  static bool _isDigit(String ch) =>
      ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57;

  static bool _isIdentStart(String ch) {
    final code = ch.codeUnitAt(0);
    return (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        ch == '_';
  }

  static bool _isIdentPart(String ch) => _isIdentStart(ch) || _isDigit(ch);
}

double? _pow(double base, double exponent) {
  if (exponent == exponent.roundToDouble()) {
    final n = exponent.round();
    if (n >= 0 && n <= 32) {
      var result = 1.0;
      for (var i = 0; i < n; i++) {
        result *= base;
      }
      return result;
    }
  }
  if (base < 0) return null;
  if (base == 0) return exponent < 0 ? null : 0;
  return math.pow(base, exponent).toDouble();
}

final Map<String, double> _constants = {'pi': math.pi, 'e': math.e};

final Map<String, double? Function(double)> _functions = {
  'sin': math.sin,
  'cos': math.cos,
  'tan': (x) {
    final c = math.cos(x);
    if (c.abs() < 1e-8) return null;
    return math.sin(x) / c;
  },
  'asin': (x) => x < -1 || x > 1 ? null : math.asin(x),
  'acos': (x) => x < -1 || x > 1 ? null : math.acos(x),
  'atan': math.atan,
  'sinh': (x) => (math.exp(x) - math.exp(-x)) / 2,
  'cosh': (x) => (math.exp(x) + math.exp(-x)) / 2,
  'tanh': (x) {
    final a = math.exp(x);
    final b = math.exp(-x);
    return (a + b) == 0 ? null : (a - b) / (a + b);
  },
  'sqrt': (x) => x < 0 ? null : math.sqrt(x),
  'log': (x) => x <= 0 ? null : math.log(x),
  'exp': math.exp,
  'abs': (x) => x.abs(),
};
