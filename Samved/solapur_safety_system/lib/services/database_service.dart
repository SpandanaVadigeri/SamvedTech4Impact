import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/sensor_data.dart';
import '../providers/app_state.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('solapur_safety.db');
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
    const idType = 'TEXT NOT NULL';
    const textType = 'TEXT NOT NULL';
    const boolType = 'BOOLEAN NOT NULL';
    const integerType = 'INTEGER NOT NULL';
    const realType = 'REAL NOT NULL';

    await db.execute('''
CREATE TABLE gas_readings (
  _id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp $textType,
  device_id $idType,
  h2s $realType,
  ch4 $realType,
  co $realType,
  o2 $realType,
  location $textType,
  depth $textType
)
''');

    await db.execute('''
CREATE TABLE worker_vitals (
  _id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp $textType,
  worker_id $idType,
  heart_rate $integerType,
  fall_detected $boolType,
  panic $boolType,
  battery $integerType
)
''');

    await db.execute('''
CREATE TABLE decisions (
  _id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp $textType,
  decision $textType,
  reason $textType,
  operator_id $idType
)
''');

    await db.execute('''
CREATE TABLE alerts (
  _id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp $textType,
  type $textType,
  severity $textType,
  acknowledged $boolType
)
''');
  }

  Future<void> insertGasReading(SensorData data, String deviceId, String location, String depth) async {
    final db = await instance.database;
    await db.insert('gas_readings', {
      'timestamp': data.timestamp.toIso8601String(),
      'device_id': deviceId,
      'h2s': data.h2s,
      'ch4': data.ch4,
      'co': data.co,
      'o2': data.o2,
      'location': location,
      'depth': depth,
    });
  }

  Future<void> insertWorkerVitals(SensorData data, String workerId, int battery) async {
    final db = await instance.database;
    await db.insert('worker_vitals', {
      'timestamp': data.timestamp.toIso8601String(),
      'worker_id': workerId,
      'heart_rate': data.heartRate,
      'fall_detected': data.fallDetected ? 1 : 0,
      'panic': data.panicPressed ? 1 : 0,
      'battery': battery,
    });
  }

  Future<void> insertDecision(String decision, String reason, String operatorId) async {
    final db = await instance.database;
    await db.insert('decisions', {
      'timestamp': DateTime.now().toIso8601String(),
      'decision': decision,
      'reason': reason,
      'operator_id': operatorId,
    });
  }

  Future<void> insertAlert(AlertMessage alert) async {
    final db = await instance.database;
    await db.insert('alerts', {
      'timestamp': alert.timestamp.toIso8601String(),
      'type': alert.message,
      'severity': alert.severity.toString(),
      'acknowledged': alert.isAcknowledged ? 1 : 0,
    });
  }

  Future<List<Map<String, dynamic>>> getAllGasReadings() async {
    final db = await instance.database;
    return await db.query('gas_readings', orderBy: 'timestamp DESC');
  }

  Future<String> exportToCSV() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> readings = await db.query('gas_readings');
    
    String csvData = "ID,Timestamp,DeviceID,H2S,CH4,CO,O2,Location,Depth\n";
    for (var row in readings) {
      csvData += "${row['_id']},${row['timestamp']},${row['device_id']},${row['h2s']},${row['ch4']},${row['co']},${row['o2']},${row['location']},${row['depth']}\n";
    }

    final directory = await getApplicationDocumentsDirectory();
    final path = "${directory.path}/gas_readings_export.csv";
    final file = File(path);
    await file.writeAsString(csvData);
    
    // Using share_plus
    await Share.shareXFiles([XFile(path)], text: 'Gas Readings Export');
    return path;
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
