import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:googleapis/youtube/v3.dart';
import 'package:NotifyTube/model/NotifyTubeDatabase.dart';

class SubscriptionDataBase extends Subscription {
  static final String subscriptionTableName = "Subscriptions";

  static final db_title = "title";
  static final db_local_id = "local_id";
  static final db_youtube_id = "youtube_id";
  static final db_description = "description";
  static final db_resource_channel_id = "channel_id";
  static final db_thumbnail_url = "thumbnail_url";
  static final db_notify = "notify";
  static final db_last_update = "last_update";

  int localId;
  bool notify;
  String lastUpdate;


  NotifyTubeDatabase database;

  SubscriptionDataBase(int localId, String youtubeId, String title, String channelId, String thumbnailUrl, String description, bool notify, String lastUpdate) : super() {
    id = youtubeId;
    this.localId = localId;
    snippet = new SubscriptionSnippet();
    snippet.title = title;
    snippet.resourceId = new ResourceId();
    snippet.resourceId.channelId = channelId;
    snippet.thumbnails = new ThumbnailDetails();
    snippet.thumbnails.default_ = new Thumbnail();
    snippet.thumbnails.default_.url = thumbnailUrl;
    snippet.description = description;
    this.notify = notify;
    this.lastUpdate = lastUpdate;
    database = NotifyTubeDatabase.get();
  }

  SubscriptionDataBase.fromMap(Map<String, dynamic> map)
      : this(
    map[db_local_id],
    map[db_youtube_id],
    map[db_title],
    map[db_resource_channel_id],
    map[db_thumbnail_url],
    map[db_description],
    (map[db_notify]=="true"?true:false),
    map[db_last_update],
  );

  static Future createTable(Database db) async {
    //await db.execute("DROP TABLE ${SubscriptionDataBase.subscriptionTableName}");
    await db.execute("CREATE TABLE ${SubscriptionDataBase.subscriptionTableName} ("
        "${SubscriptionDataBase.db_local_id} INTEGER PRIMARY KEY, "
        "${SubscriptionDataBase.db_youtube_id} TEXT, "
        "${SubscriptionDataBase.db_resource_channel_id} TEXT, "
        "${SubscriptionDataBase.db_title} TEXT, "
        "${SubscriptionDataBase.db_description} TEXT, "
        "${SubscriptionDataBase.db_thumbnail_url} TEXT, "
        "${SubscriptionDataBase.db_notify} TEXT, "
        "${SubscriptionDataBase.db_last_update} TEXT) ");
  }

  Future deleteSubscribe() async {
    await database.db.transaction((txn) async {
      await txn.delete(subscriptionTableName, where: '${SubscriptionDataBase.db_local_id} = ?', whereArgs: [this.localId]);
    });
  }

  static Future<SubscriptionDataBase> getById(String localId, NotifyTubeDatabase database) async {
    var result;
    await database.db.transaction((txn) async {
      result = await txn.rawQuery('SELECT * FROM ${SubscriptionDataBase.subscriptionTableName} WHERE ${SubscriptionDataBase.db_local_id} = "$localId"');
    });
    if (result.length == 0) return null;
    return new SubscriptionDataBase.fromMap(result[0]);
  }

  static Future<SubscriptionDataBase> getSubscriptionByYtId(String ytId, NotifyTubeDatabase database) async {
    var result;
    await database.db.transaction((txn) async {
      result = await txn.rawQuery('SELECT * FROM ${SubscriptionDataBase.subscriptionTableName} WHERE ${SubscriptionDataBase.db_youtube_id} = "$ytId"');
    });
    if (result.length == 0) return null;
    return new SubscriptionDataBase.fromMap(result[0]);
  }

  static Future<List<SubscriptionDataBase>> getAllSubscriptions(NotifyTubeDatabase database) async {
    var result;
    await database.db.transaction((txn) async {
      result = await txn.rawQuery('SELECT * FROM ${SubscriptionDataBase.subscriptionTableName}');
    });
    List<SubscriptionDataBase> subscriptions = new List();
    for (Map<String, dynamic> item in result) {
      subscriptions.add(new SubscriptionDataBase.fromMap(item));
    }
    return subscriptions;
  }

  static Future<List<SubscriptionDataBase>> getAllSubscriptionsWithNotify(NotifyTubeDatabase database) async {
    var result;
    await database.db.transaction((txn) async {
      result = await txn.rawQuery('SELECT * FROM ${SubscriptionDataBase.subscriptionTableName} WHERE ${SubscriptionDataBase.db_notify} = "true"');
    });
    List<SubscriptionDataBase> subscriptions = new List();
    for (Map<String, dynamic> item in result) {
      subscriptions.add(new SubscriptionDataBase.fromMap(item));
    }
    return subscriptions;
  }

  /// Replaces the sub in DB.
  Future update() async {
    Map<String, dynamic> values = new Map();
    values[SubscriptionDataBase.db_youtube_id] = this.id;
    values[SubscriptionDataBase.db_resource_channel_id] = this.snippet.resourceId.channelId;
    values[SubscriptionDataBase.db_title] = this.snippet.title;
    values[SubscriptionDataBase.db_description] = this.snippet.description;
    values[SubscriptionDataBase.db_thumbnail_url] = this.snippet.thumbnails.default_.url;
    values[SubscriptionDataBase.db_notify] = this.notify.toString();
    values[SubscriptionDataBase.db_last_update] = this.lastUpdate;

    await database.db.transaction((txn) async {
      await txn.update(SubscriptionDataBase.subscriptionTableName, values, where: '${SubscriptionDataBase.db_local_id} = ?', whereArgs: [this.localId]);
    });
  }

  Future insert() async {
    Map<String, dynamic> values = new Map();
    values[SubscriptionDataBase.db_youtube_id] = this.id;
    values[SubscriptionDataBase.db_resource_channel_id] = this.snippet.resourceId.channelId;
    values[SubscriptionDataBase.db_title] = this.snippet.title;
    values[SubscriptionDataBase.db_description] = this.snippet.description;
    values[SubscriptionDataBase.db_thumbnail_url] = this.snippet.thumbnails.default_.url;
    values[SubscriptionDataBase.db_notify] = this.notify.toString();
    values[SubscriptionDataBase.db_last_update] = this.lastUpdate;
    await database.db.transaction((txn) async {
      await txn.insert(subscriptionTableName, values);
    });
  }

  static Future updateSubscriptionsFromYt(List<Subscription> subscriptions) async {
    Iterator subYtIterator;
    // get what we have in db
    List<SubscriptionDataBase> subscriptionFromDatabase = await SubscriptionDataBase.getAllSubscriptions(NotifyTubeDatabase.get());

    bool found;
    // For each element in db we look if it exists in the list from api
    subscriptionFromDatabase.forEach((subDb) {
      found = false;
      subYtIterator = subscriptions.iterator;
      while (subYtIterator.moveNext()) {
        Subscription subYt = subYtIterator.current;
        if (subDb.id == subYt.id) {
          found = true;
          break;
        }
      }
      if (!found) {
        subDb.deleteSubscribe();
      }
    });

    subYtIterator = subscriptions.iterator;
    while (subYtIterator.moveNext()) {
      Subscription subYt = subYtIterator.current;
      await updateOrInsertSubscriptionFromYt(subYt);
    }
  }

  static Future updateOrInsertSubscriptionFromYt(Subscription subscription) async {

    SubscriptionDataBase previousEntry = await SubscriptionDataBase.getSubscriptionByYtId(subscription.id,NotifyTubeDatabase.get());

    if (previousEntry != null) {
      previousEntry.snippet.title = subscription.snippet.title;
      previousEntry.snippet.description = subscription.snippet.description;
      previousEntry.snippet.resourceId.channelId = subscription.snippet.resourceId.channelId;
      previousEntry.snippet.thumbnails.default_.url = subscription.snippet.thumbnails.default_.url;
      await previousEntry.update();
    } else {
      SubscriptionDataBase subToInsert = new SubscriptionDataBase(
          null,
          subscription.id,
          subscription.snippet.title,
          subscription.snippet.resourceId.channelId,
          subscription.snippet.thumbnails.default_.url,
          subscription.snippet.description,
          false,
          DateTime.now().toUtc().toString());
      await subToInsert.insert();
    }
  }
}