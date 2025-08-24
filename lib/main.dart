// lib/main.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const GewichtsApp());

// ===================== App Shell =====================
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
      home: const HomeScreen(),
    );
  }
}

// ===================== Datenmodell =====================
class Calib {
  // Volvo-Werte (x) & Real-Werte (y) für drei Zustände: leer / teil / voll
  double leerVZug = 0, leerRZug = 0, teilVZug = 0, teilRZug = 0, vollVZug = 0, vollRZug = 0;
  double leerVAuf = 0, leerRAuf = 0, teilVAuf = 0, teilRAuf = 0, vollVAuf = 0, vollRAuf = 0;

  (double a, double b)? axZug;
  (double a, double b)? axAuf;

  Calib();

  Calib.fromJson(Map<String, dynamic> j) {
    leerVZug = (j['leerVZug'] ?? 0).toDouble();
    leerRZug = (j['leerRZug'] ?? 0).toDouble();
    teilVZug = (j['teilVZug'] ?? 0).toDouble();
    teilRZug = (j['teilRZug'] ?? 0).toDouble();
    vollVZug = (j['vollVZug'] ?? 0).toDouble();
    vollRZug = (j['vollRZug'] ?? 0).toDouble();

    leerVAuf = (j['leerVAuf'] ?? 0).toDouble();
    leerRAuf = (j['leerRAuf'] ?? 0).toDouble();
    teilVAuf = (j['teilVAuf'] ?? 0).toDouble();
    teilRAuf = (j['teilRAuf'] ?? 0).toDouble();
    vollVAuf = (j['vollVAuf'] ?? 0).toDouble();
    vollRAuf = (j['vollRAuf'] ?? 0).toDouble();
  }

  Map<String, dynamic> toJson() => {
    'leerVZug': leerVZug, 'leerRZug': leerRZug, 'teilVZug': teilVZug, 'teilRZug': teilRZug, 'vollVZug': vollVZug, 'vollRZug': vollRZug,
    'leerVAuf': leerVAuf, 'leerRAuf': leerRAuf, 'teilVAuf': teilVAuf, 'teilRAuf': teilRAuf, 'vollVAuf': vollVAuf, 'vollRAuf': vollRAuf,
  };

  // Robust: 3-Punkt-Regression; fallback 2-Punkt; bei 1 Punkt -> a≈1, b so, dass Leer passt.
  void recompute() {
    (double, double) fit(List<(double x, double y)> pts) {
      if (pts.length >= 2) {
        final n = pts.length;
        final xm = pts.fold(0.0, (s, p) => s + p.$1) / n;
        final ym = pts.fold(0.0, (s, p) => s + p.$2) / n;
        double den = 0, num = 0;
        for (final p in pts) {
          den += (p.$1 - xm) * (p.$1 - xm);
          num += (p.$1 - xm) * (p.$2 - ym);
        }
        if (den.abs() < 1e-12) return (1.0, 0.0);
        final a = num / den;
        final b = ym - a * xm;
        return (a, b);
      } else if (pts.length == 1) {
        final p = pts.first;
        return (1.0, p.$2 - p.$1);
      }
      return (1.0, 0.0);
    }

    final ptsZ = <(double,double)>[];
    if (leerVZug>0 && leerRZug>0) ptsZ.add((leerVZug, leerRZug));
    if (teilVZug>0 && teilRZug>0) ptsZ.add((teilVZug, teilRZug));
    if (vollVZug>0 && vollRZug>0) ptsZ.add((vollVZug, vollRZug));
    axZug = fit(ptsZ);

    final ptsA = <(double,double)>[];
    if (leerVAuf>0 && leerRAuf>0) ptsA.add((leerVAuf, leerRAuf));
    if (teilVAuf>0 && teilRAuf>0) ptsA.add((teilVAuf, teilRAuf));
    if (vollVAuf>0 && vollRAuf>0) ptsA.add((vollVAuf, vollRAuf));
    axAuf = fit(ptsA);
  }
}

class PlateData {
  Calib calib;
  String notes;
  int tankMaxLiter;
  double dieselDichte; // kg/L
  int paletteKg;

  PlateData({
    Calib? calib,
    this.notes = '',
    this.tankMaxLiter = 400,
    this.dieselDichte = 0.8,
    this.paletteKg = 25,
  }) : calib = calib ?? Calib();

  PlateData.fromJson(Map<String, dynamic> j)
      : calib = Calib.fromJson(j['calib'] ?? {}),
        notes = j['notes'] ?? '',
        tankMaxLiter = (j['tankMaxLiter'] ?? 400),
        dieselDichte = (j['dieselDichte'] ?? 0.8).toDouble(),
        paletteKg = (j['paletteKg'] ?? 25);

  Map<String, dynamic> toJson() => {
    'calib': calib.toJson(),
    'notes': notes,
    'tankMaxLiter': tankMaxLiter,
    'dieselDichte': dieselDichte,
    'paletteKg': paletteKg,
  };
}

class AppDB {
  final Map<String, PlateData> plates;
  String activePlate;
  String profile; // 'EU 40t' / 'EU 42t' / 'EU 44t'

  AppDB({Map<String, PlateData>? plates, this.activePlate = 'WL782GW', this.profile = 'EU 40t'})
      : plates = plates ?? {'WL782GW': PlateData()};

  Map<String, dynamic> toJson() => {
    'plates': plates.map((k, v) => MapEntry(k, v.toJson())),
    'activePlate': activePlate,
    'profile': profile,
  };

  static AppDB fromJson(Map<String, dynamic> j) {
    final platesJ = (j['plates'] ?? {}) as Map<String, dynamic>;
    final map = <String, PlateData>{};
    platesJ.forEach((k, v) => map[k] = PlateData.fromJson(Map<String, dynamic>.from(v)));
    return AppDB(
      plates: map.isEmpty ? {'WL782GW': PlateData()} : map,
      activePlate: j['activePlate'] ?? (map.isEmpty ? 'WL782GW' : map.keys.first),
      profile: j['profile'] ?? 'EU 40t',
    );
  }
}

// ===================== Storage (SharedPreferences) =====================
class DBStore {
  static const _k = 'gewichts_app_db_v1';
  static Future<AppDB> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_k);
    if (raw == null) {
      final db = AppDB();
      await save(db);
      return db;
    }
    try {
      return AppDB.fromJson(jsonDecode(raw));
    } catch (_) {
      final db = AppDB();
      await save(db);
      return db;
    }
  }

  static Future<void> save(AppDB db) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_k, jsonEncode(db.toJson()));
  }
}

// ===================== UI: Home (Kalibrierung versteckt) =====================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppDB? _db;
  bool _showKg = false;

  // Eingaben (aktuelle Volvo-Werte + Zusatz)
  final _nowZug = TextEditingController(text: '11.0');
  final _nowAuf = TextEditingController(text: '23.0');
  bool _useTank = false;
  double _tankPercent = 100;
  bool _usePallets = false;
  int _palCount = 0;

  // Ergebnisse
  double? _zugT, _aufT, _sumT, _sumPlusT;
  double? _overAxKg, _overSumKg;

  @override
  void initState() {
    super.initState();
    DBStore.load().then((db) => setState(() => _db = db));
  }

  @override
  void dispose() {
    for (final c in [_nowZug, _nowAuf]) { c.dispose(); }
    super.dispose();
  }

  PlateData get _plate => _db!.plates[_db!.activePlate]!;
  Calib get _calib => _plate.calib;

  double _parse(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.')) ?? 0.0;
  double _maxTotal() => switch (_db?.profile ?? 'EU 40t') { 'EU 42t' => 42.0, 'EU 44t' => 44.0, _ => 40.0 };

  double _tankKg() {
    if (!_useTank) return 0;
    final maxKg = _plate.tankMaxLiter * _plate.dieselDichte; // kg
    return maxKg * (_tankPercent / 100.0);
  }

  double _palletsKg() => !_usePallets ? 0 : _palCount * _plate.paletteKg.toDouble();

  void _compute() {
    _calib.recompute();
    final (a1,b1) = _calib.axZug ?? (1.0, 0.0);
    final (a2,b2) = _calib.axAuf ?? (1.0, 0.0);

    final realZug = _parse(_nowZug) * a1 + b1;
    final realAuf = _parse(_nowAuf) * a2 + b2;
    final realSum = realZug + realAuf;

    final zusatzT = (_tankKg() + _palletsKg()) / 1000.0;
    final sumPlus = realSum + zusatzT;

    const maxAx = 11.5;
    final overAkg  = (realZug > maxAx) ? (realZug - maxAx) * 1000.0 : 0.0;

    final maxSum = _maxTotal();
    final overGkg  = (sumPlus > maxSum) ? (sumPlus - maxSum) * 1000.0 : 0.0;

    setState(() {
      _zugT = realZug;
      _aufT = realAuf;
      _sumT = realSum;
      _sumPlusT = sumPlus;
      _overAxKg = overAkg;
      _overSumKg = overGkg;
    });
  }

  // ---------- Geheim-Menü (nur Long-Press) ----------
  Future<void> _openSecretMenu() async {
    await showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Kalibrierung bearbeiten'),
            subtitle: const Text('Leer / Teil / Voll – nur bei Bedarf'),
            onTap: () { Navigator.pop(context); _openCalibMenu(); },
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long),
            title: const Text('Papierwerte (Zulassungsschein) eingeben'),
            onTap: () { Navigator.pop(context); _openPaperInit(context); },
          ),
          ListTile(
            leading: const Icon(Icons.visibility_off),
            title: const Text('Messungs-Übersicht (versteckt)'),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => HiddenMeasurementsScreen(plate: _plate),
              ));
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _openCalibMenu() async {
    await showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.circle, color: Colors.green),
              title: const Text('Leer eingeben'),
              onTap: () { Navigator.pop(context); _openGuided(context, 'leer'); },
            ),
            ListTile(
              leading: const Icon(Icons.circle, color: Colors.amber),
              title: const Text('Teilbeladen eingeben'),
              onTap: () { Navigator.pop(context); _openGuided(context, 'teil'); },
            ),
            ListTile(
              leading: const Icon(Icons.circle, color: Colors.blue),
              title: const Text('Voll eingeben'),
              onTap: () { Navigator.pop(context); _openGuided(context, 'voll'); },
            ),
          ],
        ),
      ),
    );
  }

  // Hooks in bestehende Dialoge/Seiten
  Future<void> _openGuided(BuildContext context, String typ) async {
    await showModalBottomSheet(
      context: context, isScrollControlled: true,
      builder: (_) => GuidedCalibSheet(typ: typ, plate: _plate),
    );
    await DBStore.save(_db!);
    setState(() {});
  }

  Future<void> _openPaperInit(BuildContext context) async {
    // Wenn du später die „Papierwerte“-Variante ausbauen willst, hier implementieren
    // (oder die ausführliche Variante aus der anderen Datei verwenden).
  }

  void _showInfo(BuildContext context) {
    showDialog(context: context, builder: (_) => const AppInfoDialog());
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    if (_db == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final unit = _showKg ? 'kg' : 't';
    double toDisplay(double t) => _showKg ? t * 1000.0 : t;
    String fmt(double t) => _showKg ? toDisplay(t).toStringAsFixed(0) : toDisplay(t).toStringAsFixed(2);

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: _openSecretMenu, // ⬅️ nur so kommt man zur Kalibrierung
          child: const Text('Gewichts App'),
        ),
        actions: [
          _profileDropdown(),
          Row(children: [const Text('t/kg'), Switch(value: _showKg, onChanged: (v)=>setState(()=>_showKg=v))]),
          IconButton(icon: const Icon(Icons.info_outline), onPressed: () => _showInfo(context)),
          IconButton(
            tooltip: 'Kennzeichen verwalten',
            icon: const Icon(Icons.directions_car),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlateManagerScreen(db: _db!)));
              setState(() {}); await DBStore.save(_db!);
            },
          ),
          IconButton(
            tooltip: 'Export/Import',
            icon: const Icon(Icons.import_export),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExportImportScreen(db: _db!)));
              setState(() {}); await DBStore.save(_db!);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Kennzeichen + Notizen
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _db!.activePlate,
                decoration: const InputDecoration(labelText: 'Aktives Kennzeichen'),
                items: _db!.plates.keys.map((k)=>DropdownMenuItem(value:k, child: Text(k))).toList(),
                onChanged: (v) => setState(()=> _db!.activePlate = v!),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(tooltip: 'Notizen', icon: const Icon(Icons.notes), onPressed: ()=>_editNotes(context)),
          ]),
          const SizedBox(height: 12),

          // Aktuelle Volvo-Druckwerte
          const Text('Aktuelle Volvo-Druckwerte', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _num('Volvo jetzt Zug (t)', _nowZug)),
            const SizedBox(width: 8),
            Expanded(child: _num('Volvo jetzt Auflieger (t)', _nowAuf)),
          ]),

          const SizedBox(height: 12),
          _extrasCard(),

          const SizedBox(height: 8),
          Card(
            color: Colors.orange.shade50,
            child: const ListTile(
              dense: true,
              leading: Icon(Icons.warning_amber_rounded),
              title: Text('Bitte keine Überladungen zur Kalibrierung eingeben.'),
              subtitle: Text('Außerhalb der Achslasten (z. B. > 11.5 t Antrieb) wird die Sensor-Linearität schlechter.'),
            ),
          ),

          const SizedBox(height: 8),
          // Nur noch: Berechnen
          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _compute,
                icon: const Icon(Icons.calculate),
                label: const Text('Berechnen'),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (_sumPlusT != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _resultRow('Zugmaschine', fmt(_zugT!), unit),
                _bar(value: toDisplay(_zugT!), max: _showKg ? 11500 : 11.5, warn: (_overAxKg ?? 0) > 0, unit: unit),
                const SizedBox(height: 6),
                _resultRow('Auflieger', fmt(_aufT!), unit),
                _bar(value: toDisplay(_aufT!), max: _showKg ? (_maxTotal()*1000 - 11500) : (_maxTotal() - 11.5), warn: false, unit: unit),
                const Divider(height: 24),
                _resultRow('Gesamt (ohne Zusatz)', fmt(_sumT!), unit),
                _resultRow('Gesamt (mit Zusatz)', fmt(_sumPlusT!), unit),
                _bar(value: toDisplay(_sumPlusT!), max: _showKg ? _maxTotal()*1000 : _maxTotal(), warn: (_overSumKg ?? 0) > 0, unit: unit),
              ],
            ),
        ],
      ),
    );
  }

  // ---------- UI-Helper ----------
  Widget _profileDropdown() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _db!.profile,
          items: const ['EU 40t','EU 42t','EU 44t'].map((p)=>DropdownMenuItem(value:p, child:Text(p))).toList(),
          onChanged: (v) async { setState(()=> _db!.profile = v!); await DBStore.save(_db!); },
        ),
      ),
    );
  }

  Widget _num(String label, TextEditingController c) {
    return TextFormField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,]'))],
    );
  }

  Widget _extrasCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Zusatzoptionen (Tank & Paletten)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('⛽ Tankfüllstand berücksichtigen'),
            value: _useTank,
            onChanged: (v)=>setState(()=>_useTank=v),
          ),
          if (_useTank) ...[
            Row(children: [
              Expanded(child: Slider(
                value: _tankPercent, min: 0, max: 100, divisions: 10,
                label: '${_tankPercent.toStringAsFixed(0)}%',
                onChanged: (v)=>setState(()=>_tankPercent=v),
              )),
              const SizedBox(width: 12),
              Text('${_tankPercent.toStringAsFixed(0)}%'),
            ]),
            Row(children: [
              Expanded(child: _intField('Max Tank (L)', _plate.tankMaxLiter, (v) async {
                setState(()=> _plate.tankMaxLiter = v);
                await DBStore.save(_db!);
              })),
              const SizedBox(width: 8),
              Expanded(child: _doubleField('Diesel-Dichte (kg/L)', _plate.dieselDichte, (v) async {
                setState(()=> _plate.dieselDichte = v);
                await DBStore.save(_db!);
              })),
            ]),
          ],
          const Divider(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('📦 Paletten im Korb berücksichtigen'),
            value: _usePallets,
            onChanged: (v)=>setState(()=>_usePallets=v),
          ),
          if (_usePallets) ...[
            Row(children: [
              Expanded(child: _intField('Anzahl Paletten', _palCount, (v) => setState(()=>_palCount=v))),
              const SizedBox(width: 8),
              Expanded(child: _intField('kg pro Palette', _plate.paletteKg, (v) async {
                setState(()=> _plate.paletteKg = v);
                await DBStore.save(_db!);
              })),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _intField(String label, int value, Function(int) onChanged) {
    final c = TextEditingController(text: value.toString());
    return TextField(
      controller: c, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: label),
      onSubmitted: (s){ final v = int.tryParse(s) ?? value; onChanged(v); },
    );
  }
  Widget _doubleField(String label, double value, Function(double) onChanged) {
    final c = TextEditingController(text: value.toStringAsFixed(2));
    return TextField(
      controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: label),
      onSubmitted: (s){ final v = double.tryParse(s.replaceAll(',', '.')) ?? value; onChanged(v); },
    );
  }

  Widget _resultRow(String label, String value, String unit) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(label)),
        Text('$value $unit', style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _bar({required double value, required double max, required bool warn, required String unit}) {
    final p = (max <= 0) ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: p, minHeight: 10, color: warn ? Colors.red : null),
        const SizedBox(height: 4),
        Text('${value.toStringAsFixed(_showKg ? 0 : 2)} / ${max.toStringAsFixed(_showKg ? 0 : 2)} $unit',
            style: TextStyle(color: warn ? Colors.red.shade700 : null)),
      ],
    );
  }

  // ---------- Dialoge ----------
  Future<void> _editNotes(BuildContext context) async {
    final c = TextEditingController(text: _plate.notes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Notizen zum Kennzeichen'),
        content: TextField(controller: c, minLines: 3, maxLines: 6, decoration: const InputDecoration(hintText: 'z. B. Besonderheiten, Reifen …')),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(context,false), child: const Text('Abbrechen')),
          FilledButton(onPressed: ()=>Navigator.pop(context,true), child: const Text('Speichern')),
        ],
      ),
    );
    if (ok == true) { setState(()=> _plate.notes = c.text); await DBStore.save(_db!); }
  }
}

// ===================== Geführte Kalibrierung (Sheet) =====================
class GuidedCalibSheet extends StatefulWidget {
  final String typ; // leer | teil | voll
  final PlateData plate;
  const GuidedCalibSheet({super.key, required this.typ, required this.plate});
  @override
  State<GuidedCalibSheet> createState() => _GuidedCalibSheetState();
}

class _GuidedCalibSheetState extends State<GuidedCalibSheet> {
  late final _vz = TextEditingController();
  late final _rz = TextEditingController();
  late final _va = TextEditingController();
  late final _ra = TextEditingController();

  @override
  void initState() {
    super.initState();
    final c = widget.plate.calib;
    switch (widget.typ) {
      case 'leer':
        _vz.text = c.leerVZug>0 ? c.leerVZug.toString() : '';
        _rz.text = c.leerRZug>0 ? c.leerRZug.toString() : '';
        _va.text = c.leerVAuf>0 ? c.leerVAuf.toString() : '';
        _ra.text = c.leerRAuf>0 ? c.leerRAuf.toString() : '';
        break;
      case 'teil':
        _vz.text = c.teilVZug>0 ? c.teilVZug.toString() : '';
        _rz.text = c.teilRZug>0 ? c.teilRZug.toString() : '';
        _va.text = c.teilVAuf>0 ? c.teilVAuf.toString() : '';
        _ra.text = c.teilRAuf>0 ? c.teilRAuf.toString() : '';
        break;
      case 'voll':
        _vz.text = c.vollVZug>0 ? c.vollVZug.toString() : '';
        _rz.text = c.vollRZug>0 ? c.vollRZug.toString() : '';
        _va.text = c.vollVAuf>0 ? c.vollVAuf.toString() : '';
        _ra.text = c.vollRAuf>0 ? c.vollRAuf.toString() : '';
        break;
    }
  }

  @override
  void dispose() { for (final x in [_vz,_rz,_va,_ra]) { x.dispose(); } super.dispose(); }

  double _p(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.')) ?? 0.0;

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.typ) { 'leer'=>'🟢 Leer', 'teil'=>'🟡 Teilbeladen', _=>'🔵 Voll' };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$title eingeben', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _num('Volvo Zug (t)', _vz)), const SizedBox(width: 8),
            Expanded(child: _num('Waage Zug (t)', _rz)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _num('Volvo Auflieger (t)', _va)), const SizedBox(width: 8),
            Expanded(child: _num('Waage Auflieger (t)', _ra)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            OutlinedButton(onPressed: ()=>Navigator.pop(context), child: const Text('Schließen')),
            const SizedBox(width: 8),
            FilledButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('Speichern'),
              onPressed: () {
                final vz = _p(_vz), rz = _p(_rz), va = _p(_va), ra = _p(_ra);

                // Plausibilitäts-Checks (Überladung vermeiden)
                const maxAx = 11.5;
                if (rz > maxAx) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Überladung erkannt (> 11.5 t Antriebsachse) – Messung nicht gespeichert.')),
                  );
                  return;
                }
                if (ra > 34.0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Unplausibler Auflieger-Wert – bitte prüfen.')),
                  );
                  return;
                }

                final c = widget.plate.calib;
                if (widget.typ == 'leer') {
                  if (vz>0) c.leerVZug = vz; if (rz>0) c.leerRZug = rz;
                  if (va>0) c.leerVAuf = va; if (ra>0) c.leerRAuf = ra;
                } else if (widget.typ == 'teil') {
                  if (vz>0) c.teilVZug = vz; if (rz>0) c.teilRZug = rz;
                  if (va>0) c.teilVAuf = va; if (ra>0) c.teilRAuf = ra;
                } else {
                  if (vz>0) c.vollVZug = vz; if (rz>0) c.vollRZug = rz;
                  if (va>0) c.vollVAuf = va; if (ra>0) c.vollRAuf = ra;
                }
                c.recompute();
                Navigator.pop(context);
              },
            ),
          ]),
          const SizedBox(height: 6),
          const Text('Hinweis: Werte nur im legalen Bereich verwenden (keine Überladungen).'),
        ]),
      ),
    );
  }

  Widget _num(String label, TextEditingController c) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,]'))],
    );
  }
}

// ===================== Kennzeichen-Manager =====================
class PlateManagerScreen extends StatefulWidget {
  final AppDB db;
  const PlateManagerScreen({super.key, required this.db});
  @override
  State<PlateManagerScreen> createState() => _PlateManagerScreenState();
}

class _PlateManagerScreenState extends State<PlateManagerScreen> {
  late TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.db.activePlate);
  }

  @override
  void dispose() { _name.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kennzeichen verwalten')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: widget.db.activePlate,
                decoration: const InputDecoration(labelText: 'Auswahl'),
                items: widget.db.plates.keys.map((k)=>DropdownMenuItem(value:k, child:Text(k))).toList(),
                onChanged: (v)=>setState(()=> widget.db.activePlate = v!),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Neu / Umbenennen'))),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Anlegen / Wechseln'),
              onPressed: () async {
                final n = _name.text.trim();
                if (n.isEmpty) return;
                widget.db.plates.putIfAbsent(n, ()=>PlateData());
                widget.db.activePlate = n;
                await DBStore.save(widget.db);
                setState(() {});
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.drive_file_rename_outline),
              label: const Text('Umbenennen'),
              onPressed: () async {
                final old = widget.db.activePlate;
                final n = _name.text.trim();
                if (n.isEmpty || widget.db.plates.containsKey(n)) return;
                final data = widget.db.plates.remove(old)!;
                widget.db.plates[n] = data;
                widget.db.activePlate = n;
                await DBStore.save(widget.db);
                setState(() {});
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('Löschen'),
              onPressed: () async {
                final k = widget.db.activePlate;
                if (widget.db.plates.length <= 1) return; // mindestens eins behalten
                widget.db.plates.remove(k);
                widget.db.activePlate = widget.db.plates.keys.first;
                await DBStore.save(widget.db);
                setState(() {});
              },
            ),
          ]),
          const SizedBox(height: 16),
          const Text('Hinweis: Kalibrierungen, Tank/Paletten-Parameter und Notizen werden pro Kennzeichen gespeichert.'),
        ]),
      ),
    );
  }
}

// ===================== Export/Import =====================
class ExportImportScreen extends StatefulWidget {
  final AppDB db;
  const ExportImportScreen({super.key, required this.db});
  @override
  State<ExportImportScreen> createState() => _ExportImportScreenState();
}

class _ExportImportScreenState extends State<ExportImportScreen> {
  late final TextEditingController _exportC;
  final _importC = TextEditingController();

  @override
  void initState() {
    super.initState();
    _exportC = TextEditingController(text: const JsonEncoder.withIndent('  ').convert(widget.db.toJson()));
  }

  @override
  void dispose() { _exportC.dispose(); _importC.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export / Import (JSON)')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text('Export', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextField(controller: _exportC, minLines: 8, maxLines: 16, readOnly: true),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('In Zwischenablage kopieren'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _exportC.text));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSON kopiert')));
              },
            ),
          ]),
          const Divider(height: 32),
          const Text('Import', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextField(
            controller: _importC, minLines: 6, maxLines: 12,
            decoration: const InputDecoration(hintText: 'Hier JSON einfügen …'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('Importieren (mergen)'),
            onPressed: () async {
              try {
                final incoming = jsonDecode(_importC.text) as Map<String, dynamic>;
                final newDb = AppDB.fromJson(incoming);
                // Weiches Mergen: bestehende Keys behalten Vorrang
                widget.db.plates.addAll(newDb.plates);
                await DBStore.save(widget.db);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import erfolgreich')));
                setState(() {
                  _exportC.text = const JsonEncoder.withIndent('  ').convert(widget.db.toJson());
                });
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
              }
            },
          ),
        ],
      ),
    );
  }
}

// ===================== Versteckte Messungs-Übersicht =====================
class HiddenMeasurementsScreen extends StatelessWidget {
  final PlateData plate;
  const HiddenMeasurementsScreen({super.key, required this.plate});

  Widget _row(String typ, String achse, double v, double r) {
    String fmt(double t) => t==0 ? '—' : t.toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(children: [
        SizedBox(width: 80, child: Text(typ, style: const TextStyle(fontWeight: FontWeight.w600))),
        SizedBox(width: 90, child: Text(achse)),
        Expanded(child: Text('Volvo: ${fmt(v)} t')),
        Expanded(child: Text('Waage: ${fmt(r)} t')),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = plate.calib;
    return Scaffold(
      appBar: AppBar(title: const Text('Messungs-Übersicht (versteckt)')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text('Leer', style: TextStyle(fontWeight: FontWeight.bold)),
          _row('Leer','Zug', c.leerVZug, c.leerRZug),
          _row('Leer','Auflieger', c.leerVAuf, c.leerRAuf),
          const Divider(),
          const Text('Teilbeladen', style: TextStyle(fontWeight: FontWeight.bold)),
          _row('Teil','Zug', c.teilVZug, c.teilRZug),
          _row('Teil','Auflieger', c.teilVAuf, c.teilRAuf),
          const Divider(),
          const Text('Voll', style: TextStyle(fontWeight: FontWeight.bold)),
          _row('Voll','Zug', c.vollVZug, c.vollRZug),
          _row('Voll','Auflieger', c.vollVAuf, c.vollRAuf),
          const SizedBox(height: 12),
          const Text('Hinweis: Übersicht ist nur über das versteckte Menü (Long-Press auf Titel) erreichbar.'),
        ],
      ),
    );
  }
}

// ===================== App-Info =====================
class AppInfoDialog extends StatelessWidget {
  const AppInfoDialog({super.key});
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ℹ️ App-Info / Anleitung'),
      content: const SingleChildScrollView(
        child: Text(
          'Was kann die App?\n'
              '• Schätzt dein aktuelles Gesamtgewicht aus den Volvo-Anzeigen (Zug + Auflieger).\n'
              '• Unterstützt Tankfüllstand & Paletten als Zusatzgewicht.\n'
              '• Warnung bei Überschreitung der Achslast (11.5 t) oder des Gesamtgewichts (EU 40/42/44 t).\n\n'
              'Kalibrierung (empfohlen):\n'
              '1) Leer auf die Waage → Werte speichern\n'
              '2) Voll (z. B. 39.3 t reicht) → speichern\n'
              '3) Optional Teilbeladung → erhöht Genauigkeit\n\n'
              'Kalibrierungen werden pro Kennzeichen gespeichert.\n'
              'Versteckte Funktionen: Long-Press auf den App-Titel.',
        ),
      ),
      actions: [TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Schließen'))],
    );
  }
}
