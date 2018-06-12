import 'dart:async';
import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:googleapis/youtube/v3.dart';

class SubscriptionDataBase extends Subscription {
  static final db_title = "title";
  static final db_local_id = "local_id";
  static final db_youtube_id = "youtube_id";
  static final db_description = "description";
  static final db_channel_id = "channel_id";
  static final db_thumbnail_url = "thumbnail_url";
  static final db_notify = "notify";

  int localId;

  SubscriptionDataBase(int localId, String youtubeId, String title, String channelId, String thumbnailUrl, String description) : super() {
    id = youtubeId;
    this.localId = localId;
    snippet = new SubscriptionSnippet();
    snippet.title = title;
    snippet.channelId = channelId;
    snippet.thumbnails = new ThumbnailDetails();
    snippet.thumbnails.default_ = new Thumbnail();
    snippet.thumbnails.default_.url = thumbnailUrl;
    snippet.description = description;
  }

  SubscriptionDataBase.fromMap(Map<String, dynamic> map)
      : this(
          map[db_local_id],
          map[db_youtube_id],
          map[db_title],
          map[db_channel_id],
          map[db_thumbnail_url],
          map[db_description],
        );
}

class NotifyTubeDatabase {
  static final NotifyTubeDatabase _subscriptionDatabase = new NotifyTubeDatabase._internal();

  final String subscriptionTableName = "Subscriptions";

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

    //await deleteDatabase(path);

    db = await openDatabase(path, version: 1, onCreate: (Database db, int version) async {
      // When creating the db, create the table
      await db.execute("CREATE TABLE $subscriptionTableName ("
          "${SubscriptionDataBase.db_local_id} INTEGER PRIMARY KEY, "
          "${SubscriptionDataBase.db_youtube_id} TEXT, "
          "${SubscriptionDataBase.db_channel_id} TEXT, "
          "${SubscriptionDataBase.db_title} TEXT, "
          "${SubscriptionDataBase.db_description} TEXT, "
          "${SubscriptionDataBase.db_thumbnail_url} TEXT, "
          "${SubscriptionDataBase.db_notify} TEXT) ");
    });
    didInit = true;
    print("DB INITED");
  }

  /// Get a subscription by its id, if there is not entry for that ID, returns null.
  Future<SubscriptionDataBase> getSubscription(String localId) async {
    var db = await _getDb();
    var result = await db.rawQuery('SELECT * FROM $subscriptionTableName WHERE ${SubscriptionDataBase.db_local_id} = "$localId"');
    if (result.length == 0) return null;
    return new SubscriptionDataBase.fromMap(result[0]);
  }

  /// Get a subscription by its id, if there is not entry for that ID, returns null.
  Future<SubscriptionDataBase> getSubscriptionFromYtId(String ytId) async {
    var db = await _getDb();
    var result = await db.rawQuery('SELECT * FROM $subscriptionTableName WHERE ${SubscriptionDataBase.db_youtube_id} = "$ytId"');
    if (result.length == 0) return null;
    return new SubscriptionDataBase.fromMap(result[0]);
  }

  /// Get all subscriptions with ids, will return a list with all the subscriptions found
  Future<List<SubscriptionDataBase>> getSubscriptions(List<String> ids) async {
    var db = await _getDb();
    // Building SELECT * FROM TABLE WHERE ID IN (id1, id2, ..., idn)
    var idsString = ids.map((it) => '"$it"').join(',');
    var result = await db.rawQuery('SELECT * FROM $subscriptionTableName WHERE ${SubscriptionDataBase.db_local_id} IN ($idsString)');
    List<SubscriptionDataBase> subscriptions = [];
    for (Map<String, dynamic> item in result) {
      subscriptions.add(new SubscriptionDataBase.fromMap(item));
    }
    return subscriptions;
  }

  Future<List<SubscriptionDataBase>> getAllSubscriptions() async {
    var db = await _getDb();
    var result = await db.rawQuery('SELECT * FROM $subscriptionTableName');
    List<SubscriptionDataBase> subscriptions = [];
    for (Map<String, dynamic> item in result) {
      subscriptions.add(new SubscriptionDataBase.fromMap(item));
    }
    return subscriptions;
  }

  //TODO escape not allowed characters eg. ' " '
  /// Replaces the subs.
  Future updateSubscription(SubscriptionDataBase subscription) async {
    Map<String, dynamic> values = new Map();
    values[SubscriptionDataBase.db_youtube_id] = subscription.id;
    values[SubscriptionDataBase.db_channel_id] = subscription.snippet.channelId;
    values[SubscriptionDataBase.db_title] = subscription.snippet.title;
    values[SubscriptionDataBase.db_description] = subscription.snippet.description;
    values[SubscriptionDataBase.db_thumbnail_url] = subscription.snippet.thumbnails.default_.url;

    await db.transaction((txn) async {
      await txn.update(subscriptionTableName, values, where: '${SubscriptionDataBase.db_local_id} = ?', whereArgs: [subscription.localId]);
    });

  }

  Future updateSubscriptionsFromYt(List<Subscription> subscriptions) async {
    // get what we have in db
    List<SubscriptionDataBase> subscriptionFromDatabase = await getAllSubscriptions();

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
        deleteSubscribe(subDb);
      }
    });

    subscriptions.forEach((subscription) async => await updateSubscriptionFromYt(subscription));
  }

  /// Inserts the subs.
  Future updateSubscriptionFromYt(Subscription subscription) async {

    SubscriptionDataBase previousEntry = await getSubscriptionFromYtId(subscription.id);

    if (previousEntry != null) {
      previousEntry.snippet.title = subscription.snippet.title;
      previousEntry.snippet.description = subscription.snippet.description;
      previousEntry.snippet.channelId = subscription.snippet.channelId;
      previousEntry.snippet.thumbnails.default_.url = subscription.snippet.thumbnails.default_.url;
      await updateSubscription(previousEntry);
    } else {
      Map<String, dynamic> values = new Map();
      values[SubscriptionDataBase.db_youtube_id] = subscription.id;
      values[SubscriptionDataBase.db_channel_id] = subscription.snippet.channelId;
      values[SubscriptionDataBase.db_title] = subscription.snippet.title;
      values[SubscriptionDataBase.db_description] = subscription.snippet.description;
      values[SubscriptionDataBase.db_thumbnail_url] = subscription.snippet.thumbnails.default_.url;
      await db.transaction((txn) async {
        await txn.insert(subscriptionTableName, values);
      });
    }
  }

  Future deleteSubscribe(SubscriptionDataBase subToDelete) async {
    await db.transaction((txn) async {
      await txn.delete(subscriptionTableName, where: '${SubscriptionDataBase.db_local_id} = ?', whereArgs: [subToDelete.localId]);
    });
  }

  Future close() async {
    var db = await _getDb();
    return db.close();
  }
}
