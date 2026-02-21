import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:table_calendar/table_calendar.dart';
// PEGA ESTOS AQUÍ:
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  runApp(const PetConnectApp());
}

class PetConnectApp extends StatelessWidget {
  const PetConnectApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'PetConnect Plus',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
      ),
      home: const WelcomeScreen(),
    );
  }
}

// --- BASE DE DATOS MODIFICADA ---
class SQLHelper {
  static Future<Database> db() async {
    return openDatabase(
      join(await getDatabasesPath(), 'petconnect_vfinal_system.db'),
      version: 2, // Incrementado versión para nueva columna
      onCreate: (db, version) async {
        await db.execute("""
          CREATE TABLE pets(
            id INTEGER PRIMARY KEY AUTOINCREMENT, 
            name TEXT, breed TEXT, weight TEXT, 
            height TEXT, birth TEXT, gender TEXT
          )
        """);
        await db.execute("""
          CREATE TABLE appointments(
            id INTEGER PRIMARY KEY AUTOINCREMENT, 
            title TEXT, date TEXT, type TEXT, petName TEXT,
            status TEXT DEFAULT 'activa'
          )
        """);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
              "ALTER TABLE appointments ADD COLUMN status TEXT DEFAULT 'activa'");
        }
      },
    );
  }

  static Future<int> createPet(
      String n, String r, String w, String h, String b, String g) async {
    final db = await SQLHelper.db();
    return await db.insert('pets', {
      'name': n,
      'breed': r,
      'weight': w,
      'height': h,
      'birth': b,
      'gender': g
    });
  }

  static Future<List<Map<String, dynamic>>> getPets() async {
    final db = await SQLHelper.db();
    return db.query('pets', orderBy: "id DESC");
  }

  static Future<void> deletePet(int id) async {
    final db = await SQLHelper.db();
    await db.delete('pets', where: "id = ?", whereArgs: [id]);
  }

  static Future<int> createAppointment(
      String title, DateTime date, String type, String petName) async {
    final db = await SQLHelper.db();
    String fmt =
        "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
    return await db.insert('appointments', {
      'title': title,
      'date': fmt,
      'type': type,
      'petName': petName,
      'status': 'activa'
    });
  }

  static Future<int> updateAppStatus(int id, String status) async {
    final db = await SQLHelper.db();
    return await db.update('appointments', {'status': status},
        where: "id = ?", whereArgs: [id]);
  }

  static Future<List<Map<String, dynamic>>> getAllApps() async {
    final db = await SQLHelper.db();
    return db.query('appointments');
  }

  static Future<void> deleteApp(int id) async {
    final db = await SQLHelper.db();
    await db.delete('appointments', where: "id = ?", whereArgs: [id]);
  }
}

// --- LAYOUT PRINCIPAL ---
class MainLayout extends StatefulWidget {
  const MainLayout({super.key});
  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  String _view = "Inicio";
  List<Map<String, dynamic>> _allPets = [];
  List<Map<String, dynamic>> _filteredPets = [];
  List<Map<String, dynamic>> _allApps = [];
  DateTime _selectedDay = DateTime.now();
  final TextEditingController _searchController = TextEditingController();

  Future<void> _generarPdfConsejos() async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(
                  level: 0, text: "PetConnect Pro - Guia de Cuidados Completa"),
              pw.SizedBox(height: 20),

              // SECCIÓN: NUTRICIÓN
              pw.Text("1. Nutricion Saludable",
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Bullet(text: "Evita alimentos procesados."),
              pw.Bullet(text: "No des sobras de comida humana."),
              pw.Bullet(text: "Controla las porciones diarias."),
              pw.SizedBox(height: 15),

              // SECCIÓN: SALUD PREVENTIVA
              pw.Text("2. Salud Preventiva",
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Bullet(text: "Manten las vacunas al dia."),
              pw.Bullet(text: "Desparasita cada 3 meses."),
              pw.Bullet(text: "Limpia sus oidos regularmente."),
              pw.SizedBox(height: 15),

              // SECCIÓN: BIENESTAR MENTAL
              pw.Text("3. Bienestar Mental",
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Bullet(text: "Usa juguetes de estimulacion."),
              pw.Bullet(text: "Dedica tiempo al juego diario."),
              pw.Bullet(text: "Cambia la ruta de sus paseos."),
              pw.SizedBox(height: 15),

              pw.Text("4. Higiene y Estética",
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Bullet(text: "Cepillado diario de pelo."),
              pw.Bullet(text: "Corte de uñas mensual."),
              pw.Bullet(text: "Baño cada 3 o 4 semanas."),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
        bytes: bytes, filename: 'guia_completa_petconnect.pdf');
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() async {
    final p = await SQLHelper.getPets();
    final all = await SQLHelper.getAllApps();
    if (mounted) {
      setState(() {
        _allPets = p;
        _filteredPets = p;
        _allApps = all;
      });
    }
  }

  void _filterPets(String query) {
    setState(() {
      _filteredPets = _allPets
          .where(
              (pet) => pet['name'].toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("PetConnect Pro"),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                "Inicio",
                "Calendario",
                "Recordatorios",
                "Consejos",
                "Emergencia"
              ]
                  .map((v) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: ChoiceChip(
                            label: Text(v),
                            selected: _view == v,
                            onSelected: (s) => setState(() => _view = v)),
                      ))
                  .toList(),
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: _buildBody(),
        ),
      ),
      floatingActionButton: (_view == "Inicio" || _view == "Calendario")
          ? FloatingActionButton(
              onPressed: () => _view == "Inicio" ? _addPet() : _addApp(),
              child: const Icon(Icons.add))
          : null,
    );
  }

  Widget _buildBody() {
    switch (_view) {
      case "Inicio":
        return _buildHome();
      case "Calendario":
        return _buildCal();
      case "Recordatorios":
        return _buildReminders();
      case "Consejos":
        return _buildTips();
      case "Emergencia":
        return _buildEmergency();
      default:
        return Center(child: Text("Sección de $_view"));
    }
  }

  Widget _buildHome() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(children: [
          Expanded(
              child: _mainStatCard(
                  "${_allApps.length}", "Total Citas", Colors.indigo)),
          const SizedBox(width: 15),
          Expanded(
              child: _mainStatCard(
                  "${_allPets.length}", "Mascotas", Colors.orange)),
        ]),
        const SizedBox(height: 25),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                const BoxShadow(color: Colors.black12, blurRadius: 6)
              ]),
          child: TextField(
            controller: _searchController,
            onChanged: _filterPets,
            decoration: const InputDecoration(
                icon: Icon(Icons.search),
                hintText: "Buscar mascota...",
                border: InputBorder.none),
          ),
        ),
        const SizedBox(height: 20),
        const Text("Mis Mascotas",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ..._filteredPets.map((p) => Card(
              child: ListTile(
                leading: const Icon(Icons.pets, color: Colors.indigo),
                title: Text(p['name']),
                subtitle: Text(p['breed']),
                onTap: () => navigatorKey.currentState
                    ?.push(MaterialPageRoute(
                        builder: (_) => PetDetailScreen(pet: p)))
                    .then((_) => _refresh()),
              ),
            )),
      ],
    );
  }

  Widget _buildCal() {
    String selStr =
        "${_selectedDay.year}-${_selectedDay.month.toString().padLeft(2, '0')}-${_selectedDay.day.toString().padLeft(2, '0')}";
    List<Map<String, dynamic>> dayEvents =
        _allApps.where((a) => a['date'] == selStr).toList();

    return Column(
      children: [
        TableCalendar(
          focusedDay: _selectedDay,
          firstDay: DateTime(2024),
          lastDay: DateTime(2030),
          headerStyle: const HeaderStyle(
              formatButtonVisible: false, titleCentered: true),
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          onDaySelected: (s, f) => setState(() => _selectedDay = s),
          calendarStyle: CalendarStyle(
            selectedDecoration: const BoxDecoration(
                color: Colors.indigo, shape: BoxShape.circle),
            todayDecoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.5), shape: BoxShape.circle),
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text("Próximos Eventos (${dayEvents.length})",
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        Expanded(
          child: dayEvents.isEmpty
              ? const Center(child: Text("No hay eventos para este día"))
              : ListView.builder(
                  itemCount: dayEvents.length,
                  itemBuilder: (context, index) =>
                      _reminderItem(dayEvents[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildReminders() {
    List<Map<String, dynamic>> appsActivas =
        _allApps.where((a) => a['status'] == 'activa').toList();
    List<Map<String, dynamic>> appsInactivas =
        _allApps.where((a) => a['status'] == 'inactiva').toList();
    List<Map<String, dynamic>> appsIncumplidas =
        _allApps.where((a) => a['status'] == 'incumplida').toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text("Recordatorios",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const Text("Gestión de alertas", style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
                child: _statMiniCard("Activos", "${appsActivas.length}",
                    Icons.notifications_active, Colors.blue)),
            const SizedBox(width: 10),
            Expanded(
                child: _statMiniCard("Inactivos", "${appsInactivas.length}",
                    Icons.check_circle, Colors.green)),
            const SizedBox(width: 10),
            Expanded(
                child: _statMiniCard("Incumplidas", "${appsIncumplidas.length}",
                    Icons.warning, Colors.red)),
          ],
        ),
        const SizedBox(height: 25),
        const Text("Listado de Citas",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        if (_allApps.isEmpty)
          const Center(child: Text("No hay recordatorios registrados"))
        else
          ..._allApps.map((app) => _reminderItem(app)),
      ],
    );
  }

  // Los widgets de Tips y Emergencia se mantienen igual que en tu código original
  Widget _buildTips() {
    final List<Map<String, dynamic>> tipCategories = [
      {
        "t": "Nutrición Saludable",
        "d":
            "La base de una vida larga es una dieta equilibrada según la edad.",
        "tips": [
          "Evita alimentos procesados.",
          "No des sobras de comida humana.",
          "Controla las porciones diarias."
        ],
        "i": Icons.restaurant,
        "c": Colors.orange
      },
      {
        "t": "Salud Preventiva",
        "d": "Prevenir enfermedades es mejor que curarlas.",
        "tips": [
          "Mantén las vacunas al día.",
          "Desparasita cada 3 meses.",
          "Limpia sus oídos regularmente."
        ],
        "i": Icons.health_and_safety,
        "c": Colors.red
      },
      {
        "t": "Bienestar Mental",
        "d": "Una mascota aburrida puede volverse ansiosa.",
        "tips": [
          "Usa juguetes de estimulación.",
          "Dedica tiempo al juego diario.",
          "Cambia la ruta de sus paseos."
        ],
        "i": Icons.psychology,
        "c": Colors.purple
      },
      {
        "t": "Higiene y Estética",
        "d": "El aseo es fundamental para su piel y pelaje.",
        "tips": [
          "Cepillado diario de pelo.",
          "Corte de uñas mensual.",
          "Baño cada 3 o 4 semanas."
        ],
        "i": Icons.content_cut,
        "c": Colors.blue
      },
    ];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text("Guía de Cuidados",
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const Text("Todo para que sea feliz",
            style: TextStyle(color: Colors.grey, fontSize: 16)),
        const SizedBox(height: 20),

        // ... código anterior (línea 422 a 425)
        const Text("Todo para que sea feliz",
            style: TextStyle(color: Colors.grey, fontSize: 16)), // Text
        const SizedBox(height: 20),

// --- PEGA EL BOTÓN AQUÍ ---
        ElevatedButton.icon(
          onPressed: _generarPdfConsejos,
          icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
          label: const Text("Descargar Guía en PDF"),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orangeAccent, // Color acorde a tu app
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
// --------------------------

        const SizedBox(height: 20),
        ...tipCategories.map((cat) => Container(
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.05), blurRadius: 10)
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: cat['c'].withOpacity(0.1),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Row(
                      children: [
                        Icon(cat['i'], color: cat['c'], size: 28),
                        const SizedBox(width: 12),
                        Text(cat['t'],
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: cat['c'])),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cat['d'],
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                        const SizedBox(height: 12),
                        const Divider(),
                        ...cat['tips']
                            .map<Widget>((item) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Icon(Icons.check_circle_outline,
                                          size: 16, color: cat['c']),
                                      const SizedBox(width: 10),
                                      Expanded(
                                          child: Text(item,
                                              style: const TextStyle(
                                                  fontSize: 13))),
                                    ],
                                  ),
                                ))
                            .toList(),
                      ],
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildEmergency() {
    final List<Map<String, dynamic>> emergencySteps = [
      {
        "t": "Mantén la calma",
        "d": "Tu mascota percibe tu estrés. Respira y actúa con firmeza."
      },
      {
        "t": "Evalúa riesgos",
        "d": "Asegura el área para que ni tú ni tu mascota sufran más daños."
      },
      {
        "t": "No automediques",
        "d": "Nunca des analgésicos humanos (como ibuprofeno), son mortales."
      },
    ];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Column(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 60, color: Colors.red),
              const SizedBox(height: 10),
              const Text("CENTRO DE EMERGENCIAS",
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.red)),
              const Text("Asistencia inmediata 24/7",
                  style: TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                  elevation: 5,
                ),
                icon: const Icon(Icons.phone_forwarded),
                label: const Text("LLAMAR A URGENCIAS AHORA",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 25),
        const Text("¿Cuándo es una emergencia?",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.5,
          children: [
            _emergencyChip("Dificultad respiratoria", Icons.air),
            _emergencyChip("Convulsiones", Icons.flash_on),
            _emergencyChip("Ingesta de tóxicos", Icons.biotech),
            _emergencyChip("Traumatismo grave", Icons.personal_injury),
          ],
        ),
        const SizedBox(height: 30),
        const Text("Protocolo de Acción",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        ...emergencySteps.asMap().entries.map((entry) {
          int idx = entry.key + 1;
          var step = entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 5)
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.red.shade100,
                  radius: 15,
                  child: Text("$idx",
                      style: TextStyle(
                          color: Colors.red.shade900,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(step['t'],
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(step['d'],
                          style: const TextStyle(
                              fontSize: 13, color: Colors.black54)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _emergencyChip(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.redAccent),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _statMiniCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [const BoxShadow(color: Colors.black12, blurRadius: 4)]),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Icon(icon, color: color, size: 18)
        ]),
        const SizedBox(height: 5),
        Align(
            alignment: Alignment.centerLeft,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.grey))),
      ]),
    );
  }

  // --- ITEM DE RECORDATORIO MODIFICADO CON ESTADOS ---
  Widget _reminderItem(Map<String, dynamic> app) {
    String status = app['status'] ?? 'activa';

    // Lógica para detectar incumplimiento visual (Si la fecha ya pasó y sigue activa)
    DateTime appDate = DateTime.parse(app['date']);
    bool isPast =
        appDate.isBefore(DateTime.now().subtract(const Duration(days: 0)));
    if (isPast && status == 'activa') status = 'incumplida';

    Color statusColor = status == 'activa'
        ? Colors.blue
        : (status == 'inactiva' ? Colors.green : Colors.red);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: Colors.blue,
            width: 2.0,
          ),
        ),
      ),
      child: Row(children: [
        CircleAvatar(
            backgroundColor: statusColor.withOpacity(0.1),
            child: Icon(
                app['type'] == "Vacuna"
                    ? Icons.vaccines
                    : app['type'] == "Baño"
                        ? Icons.bathtub
                        : Icons.event,
                color: statusColor)),
        const SizedBox(width: 15),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(app['title'],
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text("${app['petName']} • ${app['date']}",
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Text(status.toUpperCase(),
                style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          )
        ])),
        // MENÚ PARA MODIFICAR ESTADO
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (String newStatus) async {
            await SQLHelper.updateAppStatus(app['id'], newStatus);
            _refresh();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
                value: 'activa', child: Text("Marcar como Activa")),
            const PopupMenuItem(
                value: 'inactiva', child: Text("Marcar como Finalizada")),
            const PopupMenuItem(
                value: 'incumplida', child: Text("Marcar como Incumplida")),
            const PopupMenuDivider(),
            PopupMenuItem(
              onTap: () async {
                await SQLHelper.deleteApp(app['id']);
                _refresh();
              },
              child: const Text("Eliminar cita",
                  style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ]),
    );
  }

  void _addPet() {
    final n = TextEditingController();
    final r = TextEditingController();
    final w = TextEditingController();
    final h = TextEditingController();
    final b = TextEditingController();
    String g = "Hembra";
    showDialog(
      context: navigatorKey.currentContext!,
      builder: (_) => StatefulBuilder(
          builder: (__, setSt) => AlertDialog(
                title: const Text("Nueva Mascota"),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: n,
                          decoration:
                              const InputDecoration(labelText: "Nombre")),
                      TextField(
                          controller: r,
                          decoration: const InputDecoration(labelText: "Raza")),
                      TextField(
                          controller: w,
                          decoration:
                              const InputDecoration(labelText: "Peso (kg)")),
                      TextField(
                          controller: h,
                          decoration:
                              const InputDecoration(labelText: "Altura (cm)")),
                      TextField(
                          controller: b,
                          decoration:
                              const InputDecoration(labelText: "Nacimiento")),
                      const SizedBox(height: 10),
                      DropdownButton<String>(
                        value: g,
                        isExpanded: true,
                        items: ["Macho", "Hembra"]
                            .map((e) =>
                                DropdownMenuItem(value: e, child: Text(e)))
                            .toList(),
                        onChanged: (v) => setSt(() => g = v!),
                      )
                    ]),
                  ),
                ),
                actions: [
                  ElevatedButton(
                      onPressed: () async {
                        await SQLHelper.createPet(
                            n.text, r.text, w.text, h.text, b.text, g);
                        _refresh();
                        navigatorKey.currentState?.pop();
                      },
                      child: const Text("Guardar"))
                ],
              )),
    );
  }

  void _addApp() {
    final t = TextEditingController();
    String pName = _allPets.isNotEmpty ? _allPets[0]['name'] : "General";
    String selectedType = "Chequeo";

    showDialog(
      context: navigatorKey.currentContext!,
      builder: (_) => StatefulBuilder(
          builder: (__, setSt) => AlertDialog(
                title: Text(
                    "Agendar para ${_selectedDay.day}/${_selectedDay.month}"),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: t,
                        decoration: const InputDecoration(
                            labelText: "Título del Evento")),
                    const SizedBox(height: 15),
                    const Align(
                        alignment: Alignment.centerLeft,
                        child: Text("Tipo de evento:",
                            style:
                                TextStyle(fontSize: 12, color: Colors.grey))),
                    DropdownButton<String>(
                      value: selectedType,
                      isExpanded: true,
                      items: [
                        "Chequeo",
                        "Vacuna",
                        "Baño",
                        "Peluquería",
                        "Desparasitante"
                      ]
                          .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => setSt(() => selectedType = v!),
                    ),
                    const SizedBox(height: 15),
                    const Align(
                        alignment: Alignment.centerLeft,
                        child: Text("Seleccionar mascota:",
                            style:
                                TextStyle(fontSize: 12, color: Colors.grey))),
                    if (_allPets.isNotEmpty)
                      DropdownButton<String>(
                        value: pName,
                        isExpanded: true,
                        items: _allPets
                            .map((e) => DropdownMenuItem(
                                value: e['name'].toString(),
                                child: Text(e['name'])))
                            .toList(),
                        onChanged: (v) => setSt(() => pName = v!),
                      )
                    else
                      const Text("No hay mascotas registradas",
                          style: TextStyle(color: Colors.red, fontSize: 12)),
                  ]),
                ),
                actions: [
                  ElevatedButton(
                      onPressed: () async {
                        if (t.text.isNotEmpty) {
                          await SQLHelper.createAppointment(
                              t.text, _selectedDay, selectedType, pName);
                          _refresh();
                          navigatorKey.currentState?.pop();
                        }
                      },
                      child: const Text("Confirmar"))
                ],
              )),
    );
  }

  Widget _mainStatCard(String v, String l, Color c) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: c.withOpacity(0.2))),
      child: Column(children: [
        Text(v,
            style:
                TextStyle(fontSize: 24, color: c, fontWeight: FontWeight.bold)),
        Text(l)
      ]),
    );
  }
}

// --- PANTALLA DETALLE ---
class PetDetailScreen extends StatelessWidget {
  final Map<String, dynamic> pet;
  const PetDetailScreen({super.key, required this.pet});

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = screenWidth > 600 ? 4 : 2;

    return Scaffold(
      appBar: AppBar(title: Text("Perfil de ${pet['name']}")),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              const CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.indigo,
                  child: Icon(Icons.pets, size: 50, color: Colors.white)),
              const SizedBox(height: 20),
              Text(pet['name'],
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.bold)),
              Text("${pet['breed']} • ID: ${pet['id']}",
                  style: const TextStyle(color: Colors.grey, fontSize: 16)),
              const SizedBox(height: 25),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.edit),
                      label: const Text("Editar")),
                  const SizedBox(width: 10),
                  IconButton(
                      onPressed: () async {
                        await SQLHelper.deletePet(pet['id']);
                        navigatorKey.currentState?.pop();
                      },
                      icon: const Icon(Icons.delete, color: Colors.red)),
                ],
              ),
              const SizedBox(height: 30),
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 15,
                mainAxisSpacing: 15,
                childAspectRatio: 1.3,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _figmaCard("Peso", "${pet['weight']} kg", Icons.scale,
                      const Color(0xFFE3F2FD)),
                  _figmaCard("Altura", "${pet['height']} cm", Icons.straighten,
                      const Color(0xFFF3E5F5)),
                  _figmaCard("Nacimiento", pet['birth'], Icons.calendar_month,
                      const Color(0xFFE8F5E9)),
                  _figmaCard("Género", pet['gender'], Icons.favorite,
                      const Color(0xFFFFF3E0)),
                ],
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _figmaCard(String label, String value, IconData icon, Color bg) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.black54, size: 20),
            const SizedBox(height: 8),
            Text(label,
                style: const TextStyle(color: Colors.black54, fontSize: 12)),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ]),
    );
  }
}

// --- BIENVENIDA ---
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
            gradient:
                LinearGradient(colors: [Color(0xFF667EEA), Color(0xFF764BA2)])),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.pets, size: 80, color: Colors.white),
          const Text("PetConnect Plus",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 35,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: () => navigatorKey.currentState?.pushReplacement(
                MaterialPageRoute(builder: (_) => const MainLayout())),
            child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                child: Text("INGRESAR")),
          ),
        ]),
      ),
    );
  }
}
