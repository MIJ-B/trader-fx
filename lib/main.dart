import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper.instance.database;
  runApp(const TradeAnalyzerApp());
}

class TradeAnalyzerApp extends StatelessWidget {
  const TradeAnalyzerApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trade Analyzer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.purple,
        brightness: Brightness.dark,
      ),
      home: const TradeHomePage(),
    );
  }
}

// ==================== DATABASE HELPER ====================
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('trades.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE trades (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        description TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        id INTEGER PRIMARY KEY,
        initial_fund REAL NOT NULL,
        currency TEXT NOT NULL
      )
    ''');

    // Insérer les paramètres par défaut
    await db.insert('settings', {
      'id': 1,
      'initial_fund': 1000.0,
      'currency': 'USD',
    });
  }

  // CRUD pour les trades
  Future<int> insertTrade(Trade trade) async {
    final db = await database;
    return await db.insert('trades', trade.toMap());
  }

  Future<List<Trade>> getAllTrades() async {
    final db = await database;
    final result = await db.query('trades', orderBy: 'date DESC');
    return result.map((json) => Trade.fromMap(json)).toList();
  }

  Future<int> deleteTrade(String id) async {
    final db = await database;
    return await db.delete('trades', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateTrade(Trade trade) async {
    final db = await database;
    return await db.update(
      'trades',
      trade.toMap(),
      where: 'id = ?',
      whereArgs: [trade.id],
    );
  }

  // Settings
  Future<Map<String, dynamic>> getSettings() async {
    final db = await database;
    final result = await db.query('settings', where: 'id = ?', whereArgs: [1]);
    return result.first;
  }

  Future<int> updateSettings(double initialFund, String currency) async {
    final db = await database;
    return await db.update(
      'settings',
      {'initial_fund': initialFund, 'currency': currency},
      where: 'id = ?',
      whereArgs: [1],
    );
  }

  // Backup et Restore
  Future<String> exportToJson() async {
    final trades = await getAllTrades();
    final settings = await getSettings();

    final data = {
      'trades': trades.map((t) => t.toMap()).toList(),
      'settings': settings,
      'export_date': DateTime.now().toIso8601String(),
    };

    return json.encode(data);
  }

  Future<void> importFromJson(String jsonString) async {
    final db = await database;
    final data = json.decode(jsonString);

    // Clear existing data
    await db.delete('trades');

    // Import trades
    for (var tradeMap in data['trades']) {
      await db.insert('trades', tradeMap);
    }

    // Import settings
    if (data['settings'] != null) {
      await db.update(
        'settings',
        {
          'initial_fund': data['settings']['initial_fund'],
          'currency': data['settings']['currency'],
        },
        where: 'id = ?',
        whereArgs: [1],
      );
    }
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}

// ==================== TRADE MODEL ====================
class Trade {
  final String id;
  final DateTime date;
  final double amount;
  final String type;
  final String description;

  Trade({
    required this.id,
    required this.date,
    required this.amount,
    required this.type,
    required this.description,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'amount': amount,
      'type': type,
      'description': description,
    };
  }

  factory Trade.fromMap(Map<String, dynamic> map) {
    return Trade(
      id: map['id'],
      date: DateTime.parse(map['date']),
      amount: map['amount'],
      type: map['type'],
      description: map['description'] ?? '',
    );
  }
}

// ==================== HOME PAGE ====================
class TradeHomePage extends StatefulWidget {
  const TradeHomePage({Key? key}) : super(key: key);

  @override
  State<TradeHomePage> createState() => _TradeHomePageState();
}

class _TradeHomePageState extends State<TradeHomePage> {
  List<Trade> trades = [];
  double initialFund = 1000.0;
  String currency = 'USD';
  bool showAddTrade = false;
  int selectedTab = 0;

  final TextEditingController amountController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  DateTime selectedDate = DateTime.now();
  String selectedType = 'profit';

  Map<String, String> currencySymbols = {
    'USD': '\$',
    'EUR': '€',
    'MGA': 'Ar',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final loadedTrades = await DatabaseHelper.instance.getAllTrades();
    final settings = await DatabaseHelper.instance.getSettings();

    setState(() {
      trades = loadedTrades;
      initialFund = settings['initial_fund'];
      currency = settings['currency'];
    });
  }

  Future<void> addTrade() async {
    if (amountController.text.isNotEmpty) {
      final trade = Trade(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        date: selectedDate,
        amount: double.parse(amountController.text),
        type: selectedType,
        description: descriptionController.text,
      );

      await DatabaseHelper.instance.insertTrade(trade);
      await _loadData();

      amountController.clear();
      descriptionController.clear();
      selectedDate = DateTime.now();
      selectedType = 'profit';
      setState(() {
        showAddTrade = false;
      });
    }
  }

  Future<void> deleteTrade(String id) async {
    await DatabaseHelper.instance.deleteTrade(id);
    await _loadData();
  }

  Future<void> updateSettings() async {
    await DatabaseHelper.instance.updateSettings(initialFund, currency);
  }

  double getTotalBalance() {
    double total = initialFund;
    for (var trade in trades) {
      if (trade.type == 'profit') {
        total += trade.amount;
      } else {
        total -= trade.amount;
      }
    }
    return total;
  }

  String getWeekNumber(DateTime date) {
    int dayOfYear = int.parse(DateFormat("D").format(date));
    int weekNumber = ((dayOfYear - date.weekday + 10) / 7).floor();
    return '${date.year}-S$weekNumber';
  }

  String getMonthYear(DateTime date) {
    return DateFormat('yyyy-MM').format(date);
  }

  Map<String, Map<String, dynamic>> getWeeklyStats() {
    Map<String, Map<String, dynamic>> stats = {};

    for (var trade in trades) {
      String week = getWeekNumber(trade.date);
      if (!stats.containsKey(week)) {
        stats[week] = {
          'profit': 0.0,
          'loss': 0.0,
          'net': 0.0,
          'count': 0,
        };
      }

      if (trade.type == 'profit') {
        stats[week]!['profit'] += trade.amount;
        stats[week]!['net'] += trade.amount;
      } else {
        stats[week]!['loss'] += trade.amount;
        stats[week]!['net'] -= trade.amount;
      }
      stats[week]!['count']++;
    }

    return stats;
  }

  Map<String, Map<String, dynamic>> getMonthlyStats() {
    Map<String, Map<String, dynamic>> stats = {};

    for (var trade in trades) {
      String month = getMonthYear(trade.date);
      if (!stats.containsKey(month)) {
        stats[month] = {
          'profit': 0.0,
          'loss': 0.0,
          'net': 0.0,
          'count': 0,
        };
      }

      if (trade.type == 'profit') {
        stats[month]!['profit'] += trade.amount;
        stats[month]!['net'] += trade.amount;
      } else {
        stats[month]!['loss'] += trade.amount;
        stats[month]!['net'] -= trade.amount;
      }
      stats[month]!['count']++;
    }

    return stats;
  }

  Future<void> _exportData() async {
    try {
      final jsonData = await DatabaseHelper.instance.exportToJson();
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'trade_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(jsonData);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Backup de Trade Analyzer',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup créé avec succès!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _importData() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null) {
        final file = File(result.files.single.path!);
        final jsonString = await file.readAsString();
        await DatabaseHelper.instance.importFromJson(jsonString);
        await _loadData();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Import réussi!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur d\'import: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      appBar: AppBar(
        title: const Text('Trade Analyzer'),
        backgroundColor: const Color(0xFF16213e),
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'export') {
                _exportData();
              } else if (value == 'import') {
                _importData();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.upload, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Exporter les données'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.download, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Importer les données'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedTab,
        onTap: (index) {
          setState(() {
            selectedTab = index;
          });
        },
        backgroundColor: const Color(0xFF16213e),
        selectedItemColor: Colors.purple,
        unselectedItemColor: Colors.white54,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Accueil'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Graphiques'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Historique'),
        ],
      ),
      body: selectedTab == 0
          ? _buildHomeTab()
          : selectedTab == 1
              ? _buildChartsTab()
              : _buildHistoryTab(),
    );
  }

  Widget _buildHomeTab() {
    final weeklyStats = getWeeklyStats();
    final monthlyStats = getMonthlyStats();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Configuration
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF16213e),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Fonds Initial',
                              style: TextStyle(color: Colors.white70)),
                          const SizedBox(height: 8),
                          TextField(
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white10,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onChanged: (value) {
                              setState(() {
                                initialFund = double.tryParse(value) ?? 1000;
                              });
                              updateSettings();
                            },
                            controller: TextEditingController(
                                text: initialFund.toString()),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Devise',
                              style: TextStyle(color: Colors.white70)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: currency,
                            dropdownColor: const Color(0xFF16213e),
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white10,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            items: ['USD', 'EUR', 'MGA'].map((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                currency = value!;
                              });
                              updateSettings();
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: getTotalBalance() >= initialFund
                          ? [const Color(0xFF2ecc71), const Color(0xFF27ae60)]
                          : [const Color(0xFFe74c3c), const Color(0xFFc0392b)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Balance Actuel',
                          style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 4),
                      Text(
                        '${currencySymbols[currency]}${getTotalBalance().toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${getTotalBalance() >= initialFund ? '+' : ''}${currencySymbols[currency]}${(getTotalBalance() - initialFund).toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Bouton ajouter trade
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                showAddTrade = !showAddTrade;
              });
            },
            icon: Icon(showAddTrade ? Icons.close : Icons.add),
            label: Text(showAddTrade ? 'Annuler' : 'Ajouter un Trade'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          // Formulaire d'ajout
          if (showAddTrade) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF16213e),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Montant',
                      labelStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: Colors.white10,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Description',
                      labelStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: Colors.white10,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedType,
                          dropdownColor: const Color(0xFF16213e),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Type',
                            labelStyle: const TextStyle(color: Colors.white70),
                            filled: true,
                            fillColor: Colors.white10,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'profit', child: Text('Profit')),
                            DropdownMenuItem(
                                value: 'loss', child: Text('Perte')),
                          ],
                          onChanged: (value) {
                            setState(() {
                              selectedType = value!;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            final DateTime? picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) {
                              setState(() {
                                selectedDate = picked;
                              });
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white10,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: Text(
                            DateFormat('dd/MM/yyyy').format(selectedDate),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: addTrade,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      minimumSize: const Size(double.infinity, 45),
                    ),
                    child: const Text('Enregistrer'),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Statistiques hebdomadaires
          const Text(
            'Statistiques Hebdomadaires',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...weeklyStats.entries.toList().reversed.take(4).map((entry) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF16213e),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.key,
                      style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '+${currencySymbols[currency]}${entry.value['profit'].toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.green),
                          ),
                          Text(
                            '-${currencySymbols[currency]}${entry.value['loss'].toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                      Text(
                        '${entry.value['net'] >= 0 ? '+' : ''}${currencySymbols[currency]}${entry.value['net'].toStringAsFixed(2)}',
                        style: TextStyle(
                          color: entry.value['net'] >= 0
                              ? Colors.green
                              : Colors.red,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${entry.value['count']} trades',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            );
          }).toList(),

          const SizedBox(height: 24),

          // Statistiques mensuelles
          const Text(
            'Statistiques Mensuelles',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...monthlyStats.entries.toList().reversed.take(4).map((entry) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF16213e),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.key,
                      style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '+${currencySymbols[currency]}${entry.value['profit'].toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.green),
                          ),
                          Text(
                            '-${currencySymbols[currency]}${entry.value['loss'].toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                      Text(
                        '${entry.value['net'] >= 0 ? '+' : ''}${currencySymbols[currency]}${entry.value['net'].toStringAsFixed(2)}',
                        style: TextStyle(
                          color: entry.value['net'] >= 0
                              ? Colors.green
                              : Colors.red,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${entry.value['count']} trades',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildChartsTab() {
    final monthlyStats = getMonthlyStats();

    if (trades.isEmpty) {
      return const Center(
        child: Text(
          'Aucune donnée pour afficher les graphiques',
          style: TextStyle(color: Colors.white54, fontSize: 16),
        ),
      );
    }

    // Préparer les données pour le graphique
    List<FlSpot> balanceSpots = [];
    List<BarChartGroupData> barGroups = [];

    double runningBalance = initialFund;
    List<Trade> sortedTrades = List.from(trades)
      ..sort((a, b) => a.date.compareTo(b.date));

    for (int i = 0; i < sortedTrades.length; i++) {
      if (sortedTrades[i].type == 'profit') {
        runningBalance += sortedTrades[i].amount;
      } else {
        runningBalance -= sortedTrades[i].amount;
      }
      balanceSpots.add(FlSpot(i.toDouble(), runningBalance));
    }

    // Préparer les données mensuelles pour le bar chart
    int index = 0;
    for (var entry in monthlyStats.entries.toList().reversed.take(6).toList().reversed) {
      barGroups.add(
        BarChartGroupData(
          x: index,
          barRods: [
            BarChartRodData(
              toY: entry.value['profit'],
              color: Colors.green,
              width: 12,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
            BarChartRodData(
              toY: entry.value['loss'],
              color: Colors.red,
              width: 12,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
          ],
        ),
      );
      index++;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Évolution de la Balance',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 250,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF16213e),
              borderRadius: BorderRadius.circular(12),
            ),
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true, drawVerticalLine: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                          ),
                        );
                      },
                    ),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: balanceSpots,
                    isCurved: true,
                    color: Colors.purple,
                    barWidth: 3,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.purple.withOpacity(0.2),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Profits vs Pertes (6 derniers mois)',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 300,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF16213e),
              borderRadius: BorderRadius.circular(12),
            ),
            child: barGroups.isEmpty
                ? const Center(
                    child: Text(
                      'Pas assez de données',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: barGroups.fold(
                            0.0,
                            (max, group) => group.barRods.fold(
                              max,
                              (m, rod) => rod.toY > m ? rod.toY : m,
                            ),
                          ) *
                          1.2,
                      barGroups: barGroups,
                      gridData: FlGridData(show: true, drawVerticalLine: false),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            getTitlesWidget: (value, meta) {
                              return Text(
                                value.toInt().toString(),
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10,
                                ),
                              );
                            },
                          ),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              if (value.toInt() >= monthlyStats.length) {
                                return const Text('');
                              }
                              final monthKey = monthlyStats.keys
                                  .toList()
                                  .reversed
                                  .take(6)
                                  .toList()
                                  .reversed
                                  .toList()[value.toInt()];
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  monthKey.substring(5),
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 10,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                    ),
                  ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Statistiques Globales',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildStatsCard(),
        ],
      ),
    );
  }

  Widget _buildStatsCard() {
    double totalProfit = 0;
    double totalLoss = 0;
    int winCount = 0;
    int lossCount = 0;

    for (var trade in trades) {
      if (trade.type == 'profit') {
        totalProfit += trade.amount;
        winCount++;
      } else {
        totalLoss += trade.amount;
        lossCount++;
      }
    }

    double winRate = trades.isEmpty ? 0 : (winCount / trades.length) * 100;
    double profitFactor = totalLoss == 0 ? totalProfit : totalProfit / totalLoss;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16213e),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildStatRow('Total Profits', '+${currencySymbols[currency]}${totalProfit.toStringAsFixed(2)}', Colors.green),
          const Divider(color: Colors.white10),
          _buildStatRow('Total Pertes', '-${currencySymbols[currency]}${totalLoss.toStringAsFixed(2)}', Colors.red),
          const Divider(color: Colors.white10),
          _buildStatRow('Net', '${totalProfit - totalLoss >= 0 ? '+' : ''}${currencySymbols[currency]}${(totalProfit - totalLoss).toStringAsFixed(2)}', totalProfit - totalLoss >= 0 ? Colors.green : Colors.red),
          const Divider(color: Colors.white10),
          _buildStatRow('Taux de Réussite', '${winRate.toStringAsFixed(1)}%', Colors.blue),
          const Divider(color: Colors.white10),
          _buildStatRow('Profit Factor', profitFactor.toStringAsFixed(2), Colors.orange),
          const Divider(color: Colors.white10),
          _buildStatRow('Total Trades', '${trades.length}', Colors.purple),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (trades.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 80, color: Colors.white24),
            const SizedBox(height: 16),
            const Text(
              'Aucun trade enregistré',
              style: TextStyle(color: Colors.white54, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ajoutez votre premier trade!',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: trades.length,
      itemBuilder: (context, index) {
        final trade = trades[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF16213e),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
              backgroundColor: trade.type == 'profit'
                  ? Colors.green.withOpacity(0.2)
                  : Colors.red.withOpacity(0.2),
              child: Icon(
                trade.type == 'profit' ? Icons.arrow_upward : Icons.arrow_downward,
                color: trade.type == 'profit' ? Colors.green : Colors.red,
              ),
            ),
            title: Text(
              DateFormat('dd MMMM yyyy').format(trade.date),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            subtitle: trade.description.isNotEmpty
                ? Text(
                    trade.description,
                    style: const TextStyle(color: Colors.white54),
                  )
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${trade.type == 'profit' ? '+' : '-'}${currencySymbols[currency]}${trade.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: trade.type == 'profit' ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: const Color(0xFF16213e),
                        title: const Text('Confirmation', style: TextStyle(color: Colors.white)),
                        content: const Text(
                          'Voulez-vous vraiment supprimer ce trade?',
                          style: TextStyle(color: Colors.white70),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Annuler'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      await deleteTrade(trade.id);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    amountController.dispose();
    descriptionController.dispose();
    super.dispose();
  }