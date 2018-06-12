import 'dart:async';
import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

import 'package:googleapis/youtube/v3.dart';
import 'package:NotifyTube/model/SubscriptionDataBase.dart';



class NotifyTubeDatabase {
  static final NotifyTubeDatabase _subscriptionDatabase = new NotifyTubeDatabase._internal();

  Database db;

  bool didInit = false;

  static NotifyTubeDatabase get() {
    return _subscriptionDatabase;
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
    // Get a location using path_provider
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, "notifytube.db");

    db = await openDatabase(path, version: 1, onCreate: (Database db, int version) async {
      // When creating the db, create the table
      await db.execute("CREATE TABLE ${SubscriptionDataBase.subscriptionTableName} ("
          "${SubscriptionDataBase.db_local_id} INTEGER PRIMARY KEY, "
          "${SubscriptionDataBase.db_youtube_id} TEXT, "
          "${SubscriptionDataBase.db_channel_id} TEXT, "
          "${SubscriptionDataBase.db_title} TEXT, "
          "${SubscriptionDataBase.db_description} TEXT, "
          "${SubscriptionDataBase.db_thumbnail_url} TEXT, "
          "${SubscriptionDataBase.db_notify} TEXT) ");
    });
    didInit = true;
  }

  Future updateSubscriptionsFromYt(List<Subscription> subscriptions) async {
    // get what we have in db
    List<SubscriptionDataBase> subscriptionFromDatabase = await SubscriptionDataBase.getAllSubscriptions(NotifyTubeDatabase.get());

    bool found;
    // For each element in db we look if it exists in the list from api
    subscriptionFromDatabase.forEach((subDb) {
      found = false;
      Iterator subDbIterator = subscriptions.iterator;
      while (subDbIterator.moveNext()) {
        Subscription subYt = subDbIterator.current;
        if (subDb.id == subYt.id) {
          found = true;
          break;
        }
      }
      if (!found) {
        subDb.deleteSubscribe();
      }
    });

    Iterator subYtIterator = subscriptions.iterator;
    while (subYtIterator.moveNext()) {
      Subscription subYt = subYtIterator.current;
      await updateOrInsertSubscriptionFromYt(subYt);
    }
  }

  Future updateOrInsertSubscriptionFromYt(Subscription subscription) async {

    SubscriptionDataBase previousEntry = await SubscriptionDataBase.getSubscriptionByYtId(subscription.id,NotifyTubeDatabase.get());

    if (previousEntry != null) {
      previousEntry.snippet.title = subscription.snippet.title;
      previousEntry.snippet.description = subscription.snippet.description;
      previousEntry.snippet.channelId = subscription.snippet.channelId;
      previousEntry.snippet.thumbnails.default_.url = subscription.snippet.thumbnails.default_.url;
      await previousEntry.update();
    } else {
      SubscriptionDataBase subToInsert = new SubscriptionDataBase(
          null,
          subscription.id,
          subscription.snippet.title,
          subscription.snippet.channelId,
          subscription.snippet.thumbnails.default_.url,
          subscription.snippet.description,
          false);
      await subToInsert.insert();
    }
  }

  Future close() async {
    var db = await _getDb();
    return db.close();
  }
}
