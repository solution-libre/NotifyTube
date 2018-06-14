import 'dart:async';
import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:NotifyTube/model/SubscriptionDataBase.dart';

class NotifyTubeDatabase {
  static final NotifyTubeDatabase _subscriptionDatabase = new NotifyTubeDatabase._internal();
  static final String dbFileName = "notifytube.db";

  Database db;
  bool didInit = false;

  static NotifyTubeDatabase get() {
    return _subscriptionDatabase;
  }

  static String getDbFileName() {
    return NotifyTubeDatabase.dbFileName;
  }

  NotifyTubeDatabase._internal();

  /// Use this method to access the database, because initialization of the database (it has to go through the method channel)
  Future<Database> _getDb() async {
    if (!didInit) await _init();
    return db;
  }

  Future init() async {
    return await _init();
  }

  Future _init() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, getDbFileName());

    db = await openDatabase(path, version: 1, onCreate: (Database db, int version) async {
      // ToDo: find a way to load the list of tables dynamically
      SubscriptionDataBase.createTable(db);
    });
    didInit = true;
  }

  Future close() async {
    var db = await _getDb();
    return db.close();
  }
}
