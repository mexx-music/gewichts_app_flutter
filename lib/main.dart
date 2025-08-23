// lib/main.dart
import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

// Kleine Wrapper-App, damit Tests mit `MyApp` weiter funktionieren.
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => const GewichtsApp();
}

class GewichtsApp extends StatelessWidget {
  const GewichtsApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gewichts App',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
      home: const GewichtHome(),
    );
  }
}

class GewichtHome extends StatefulWidget {
  const GewichtHome({super.key});
  @override
  State<GewichtHome> createState() => _GewichtHomeState();
}

class _GewichtHomeState extends State<GewichtHome> {
  final _form = GlobalKey<FormState>();

  // Profile
  final List<String> _profile = ['EU 40t', 'EU 42t', 'EU 44t'];
  String _selectedProfile = 'EU 40t';
  bool _showKg = false; // t/kg Umschalter

  // Eingaben (t), Zusatz in kg
  final _leerVolvoAntrieb = TextEditingController(text: '4.7');
  final _leerRealAntrieb = TextEditingController(text: '7.5');
  final _vollVolvoAntrieb = TextEditingController(text: '11.0');
  final _vollRealAntrieb = TextEditingController(text: '11.5');
  final _teilVolvoAntrieb = TextEditingController();
  final _teilRealAntrieb = TextEditingController();

  final _leerVolvoAuflieger = TextEditingController(text: '6.6');
  final _leerRealAuflieger = TextEditingController(text: '8.5');
  final _vollVolvoAuflieger = TextEditingController(text: '23.0');
  final _vollRealAuflieger = TextEditingController(text: '27.5');
  final _teilVolvoAuflieger = TextEditingController();
  final _teilRealAuflieger = TextEditingController();

  final _nowAntrieb = TextEditingController(text: '11.0');
  final _nowAuflieger = TextEditingController(text: '23.0');

  final _tankKg = TextEditingController(text: '0');
  final _palettenKg = TextEditingController(text: '0');

  // Ergebnisse
  double? _zugT, _auflT, _gesamtT, _gesamtMitZusatzT;
  double? _ueberAntriebKg, _ueberAntriebPct, _ueberGesamtKg, _ueberGesamtPct;

  @override
  void dispose() {
    for (final c in [
      _leerVolvoAntrieb, _leerRealAntrieb, _vollVolvoAntrieb, _vollRealAntrieb,
      _teilVolvoAntrieb, _teilRealAntrieb,
      _leerVolvoAuflieger, _leerRealAuflieger, _vollVolvoAuflieger, _vollRealAuflieger,
      _teilVolvoAuflieger, _teilRealAuflieger,
      _nowAntrieb, _nowAuflieger, _tankKg, _palettenKg
    ]) { c.dispose(); }
    super.dispose();
  }

  double _parse(TextEditingController c, {double fallback = 0}) =>
      double.tryParse(c.text.replaceAll(',', '.')) ?? fallback;

  // Liefert ein Dart-Record (a, b). Dart 3+ erforderlich (Flutter 3.35 hat Dart 3.9).
  (double a, double b) _calibrate(
      double v1, double r1, double v2, double r2, {double? optV, double? optR}
      ) {
    final use3 = (optV ?? 0) > 0 && (optR ?? 0) > 0;
    if (use3) {
      final x = [v1, optV!, v2];
      final y = [r1, optR!, r2];
      final xm = (x[0]+x[1]+x[2])/3.0, ym = (y[0]+y[1]+y[2])/3.0;
      final denom = (x[0]-xm)*(x[0]-xm) + (x[1]-xm)*(x[1]-xm) + (x[2]-xm)*(x[2]-xm);
      if (denom == 0) return (1.0, 0.0);
      final nume = (x[0]-xm)*(y[0]-ym) + (x[1]-xm)*(y[1]-ym) + (x[2]-xm)*(y[2]-ym);
      final a = nume/denom, b = ym - a*xm;
      return (a, b);
    } else {
      if (v2 == v1) return (1.0, 0.0);
      final a = (r2 - r1) / (v2 - v1);
      final b = r1 - a*v1;
      return (a, b);
    }
  }

  double _maxGesamt() => switch (_selectedProfile) {
    'EU 42t' => 42.0,
    'EU 44t' => 44.0,
    _ => 40.0,
  };

  void _berechnen() {
    if (!(_form.currentState?.validate() ?? false)) return;

    // Tuple entpacken
    final (a1, b1) = _calibrate(
      _parse(_leerVolvoAntrieb), _parse(_leerRealAntrieb),
      _parse(_vollVolvoAntrieb), _parse(_vollRealAntrieb),
      optV: _parse(_teilVolvoAntrieb), optR: _parse(_teilRealAntrieb),
    );
    final (a2, b2) = _calibrate(
      _parse(_leerVolvoAuflieger), _parse(_leerRealAuflieger),
      _parse(_vollVolvoAuflieger), _parse(_vollRealAuflieger),
      optV: _parse(_teilVolvoAuflieger), optR: _parse(_teilRealAuflieger),
    );

    // Reale Gewichte
    final realAntrieb  = _parse(_nowAntrieb)  * a1 + b1;
    final realAuflieger = _parse(_nowAuflieger) * a2 + b2;
    final realGesamt = realAntrieb + realAuflieger;

    // Zusatz (Tank/Paletten) in t
    final zusatzT = (_parse(_tankKg) + _parse(_palettenKg)) / 1000.0;
    final gesamtMitZusatz = realGesamt + zusatzT;

    // Grenzwerte
    const maxAntriebsachseT = 11.5;
    final ueberAkg  = (realAntrieb - maxAntriebsachseT) > 0 ? (realAntrieb - maxAntriebsachseT) * 1000 : 0.0;
    final ueberApct = (realAntrieb - maxAntriebsachseT) > 0 ? (realAntrieb - maxAntriebsachseT) / maxAntriebsachseT * 100 : 0.0;

    final maxGesamt = _maxGesamt();
    final ueberGkg  = (gesamtMitZusatz - maxGesamt) > 0 ? (gesamtMitZusatz - maxGesamt) * 1000 : 0.0;
    final ueberGpct = (gesamtMitZusatz - maxGesamt) > 0 ? (gesamtMitZusatz - maxGesamt) / maxGesamt * 100 : 0.0;

    setState(() {
      _zugT = realAntrieb;
      _auflT = realAuflieger;
      _gesamtT = realGesamt;
      _gesamtMitZusatzT = gesamtMitZusatz;
      _ueberAntriebKg = ueberAkg.toDouble();
      _ueberAntriebPct = ueberApct.toDouble();
      _ueberGesamtKg = ueberGkg.toDouble();
      _ueberGesamtPct = ueberGpct.toDouble();
    });
  }

  Widget _numField(String label, TextEditingController c, {String? hint}) {
    return TextFormField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, hintText: hint),
      validator: (s) {
        final v = double.tryParse((s ?? '').replaceAll(',', '.'));
        if (v == null || v < 0) return 'Ungültig';
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final unit = _showKg ? 'kg' : 't';
    double show(double t) => _showKg ? t * 1000.0 : t;
    String fmt(double t) => _showKg ? show(t).toStringAsFixed(0) : show(t).toStringAsFixed(2);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gewichts App'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedProfile,
                items: _profile.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                onChanged: (v) => setState(() => _selectedProfile = v!),
              ),
            ),
          ),
          Row(children: [
            const Text('t/kg'),
            Switch(value: _showKg, onChanged: (v) => setState(() => _showKg = v)),
          ]),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const Text('Kalibrierung – Antriebsachse', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _numField('Leer Volvo (t)', _leerVolvoAntrieb)),
              const SizedBox(width: 8),
              Expanded(child: _numField('Leer Real (t)', _leerRealAntrieb)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _numField('Voll Volvo (t)', _vollVolvoAntrieb)),
              const SizedBox(width: 8),
              Expanded(child: _numField('Voll Real (t)', _vollRealAntrieb)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _numField('Teil Volvo (t, opt.)', _teilVolvoAntrieb)),
              const SizedBox(width: 8),
              Expanded(child: _numField('Teil Real (t, opt.)', _teilRealAntrieb)),
            ]),

            const SizedBox(height: 16),
            const Text('Kalibrierung – Auflieger', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _numField('Leer Volvo (t)', _leerVolvoAuflieger)),
              const SizedBox(width: 8),
              Expanded(child: _numField('Leer Real (t)', _leerRealAuflieger)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _numField('Voll Volvo (t)', _vollVolvoAuflieger)),
              const SizedBox(width: 8),
              Expanded(child: _numField('Voll Real (t)', _vollRealAuflieger)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _numField('Teil Volvo (t, opt.)', _teilVolvoAuflieger)),
              const SizedBox(width: 8),
              Expanded(child: _numField('Teil Real (t, opt.)', _teilRealAuflieger)),
            ]),

            const SizedBox(height: 16),
            const Text('Aktuelle Werte & Zusatz', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _numField('Volvo jetzt Zug (t)', _nowAntrieb)),
              const SizedBox(width: 8),
              Expanded(child: _numField('Volvo jetzt Auflieger (t)', _nowAuflieger)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _numField('Tank (kg)', _tankKg)),
              const SizedBox(width: 8),
              Expanded(child: _numField('Paletten (kg)', _palettenKg)),
            ]),

            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _berechnen,
              icon: const Icon(Icons.calculate),
              label: const Text('Berechnen'),
            ),

            const SizedBox(height: 16),
            if (_gesamtMitZusatzT != null)
              _ResultCard(
                showKg: _showKg,
                zugT: _zugT!, auflT: _auflT!,
                gesamtT: _gesamtT!, gesamtMitZusatzT: _gesamtMitZusatzT!,
                ueberAkg: _ueberAntriebKg!, ueberApct: _ueberAntriebPct!,
                ueberGkg: _ueberGesamtKg!, ueberGpct: _ueberGesamtPct!,
                fmt: fmt, unit: unit,
              ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final bool showKg;
  final double zugT, auflT, gesamtT, gesamtMitZusatzT;
  final double ueberAkg, ueberApct, ueberGkg, ueberGpct;
  final String Function(double) fmt;
  final String unit;
  const _ResultCard({
    required this.showKg,
    required this.zugT,
    required this.auflT,
    required this.gesamtT,
    required this.gesamtMitZusatzT,
    required this.ueberAkg,
    required this.ueberApct,
    required this.ueberGkg,
    required this.ueberGpct,
    required this.fmt,
    required this.unit,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final warnA = ueberAkg > 0;
    final warnG = ueberGkg > 0;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Ergebnis', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          _row('Zugmaschine', fmt(zugT), unit),
          _row('Auflieger', fmt(auflT), unit),
          _row('Gesamt (ohne Zusatz)', fmt(gesamtT), unit),
          _row('Gesamt (mit Zusatz)', fmt(gesamtMitZusatzT), unit),
          const Divider(),
          _row('Über Antriebsachse', ueberAkg.toStringAsFixed(0), 'kg', warn: warnA),
          _row('Über Gesamt', ueberGkg.toStringAsFixed(0), 'kg', warn: warnG),
          if (warnA || warnG)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Achtung: Grenzwerte überschritten (${warnA ? 'Antriebsachse ' : ''}${(warnA && warnG) ? ' & ' : ''}${warnG ? 'Gesamt' : ''}).',
                style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _row(String label, String value, String unit, {bool warn = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            '$value $unit',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: warn ? Colors.red.shade700 : null,
            ),
          ),
        ],
      ),
    );
  }
}
