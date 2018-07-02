import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:xml/xml.dart' as xml;

import 'package:google_sign_in/google_sign_in.dart' show GoogleSignIn, GoogleSignInAccount;

import 'package:http/http.dart';

import 'package:googleapis/youtube/v3.dart';

import 'package:NotifyTube/GoogleHttpClient.dart';
import 'package:NotifyTube/model/NotifyTubeDatabase.dart';
import 'package:NotifyTube/model/SubscriptionDataBase.dart';

import 'package:android_job_scheduler/android_job_scheduler.dart';

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications/initialization_settings.dart';
import 'package:flutter_local_notifications/notification_details.dart';
import 'package:flutter_local_notifications/platform_specifics/android/initialization_settings_android.dart';
import 'package:flutter_local_notifications/platform_specifics/android/notification_details_android.dart';
import 'package:flutter_local_notifications/platform_specifics/ios/initialization_settings_ios.dart';
import 'package:flutter_local_notifications/platform_specifics/ios/notification_details_ios.dart';
import 'package:cached_network_image/cached_network_image.dart';

GoogleSignIn _googleSignIn = new GoogleSignIn(
  scopes: <String>[
    'email',
    'https://www.googleapis.com/auth/youtube',
    'https://www.googleapis.com/auth/youtubepartner',
  ],
);

class NotifyTube extends StatefulWidget {
  @override
  State createState() => new NotifyTubeState();
}

class NotifyTubeState extends State<NotifyTube> {
  // state changing elements
  GoogleSignInAccount _currentUser;
  Map<int, Widget> subscriptionWidgetMap = new Map<int, Widget>();
  Map<int, Widget> notificationButtonMap = Map<int, Widget>();
  NotifyTubeDatabase database;

  List<int> _pendingJobs = new List<int>();
  int _timesCalled = 0;

  @override
  void initState() {
    super.initState();
    initDatabase().then((_) {
      initGoogleSignIn();
      initSubscriptionsWidgetMap();
      initNotifications();
    });
  }

  // --------------------------------- Init ------------------------------------
  Future initDatabase() async {
    database = NotifyTubeDatabase.get();
    await database.init();
  }

  void initGoogleSignIn() {
    _googleSignIn.onCurrentUserChanged.listen((GoogleSignInAccount account) {
      setState(() {
        _currentUser = account;
      });
    });
    _googleSignIn.signIn();
  }

  Future<Null> fetchYoutubeApiData() async {
    if (_currentUser != null) {
      //1. get subs
      List<Subscription> subscriptionListFromAPI = await getSubscriptionsFromYt();

      //2. update our database to the subs
      await SubscriptionDataBase.updateSubscriptionsFromYt(subscriptionListFromAPI).then((future) async => await initSubscriptionsWidgetMap());
    } else {
      print("No user connected...");
    }
  }

  Future initSubscriptionsWidgetMap() async {
    setState(() {
      subscriptionWidgetMap.clear();
    });

    List<SubscriptionDataBase> allSubscriptionFromDatabase = await SubscriptionDataBase.getAllSubscriptions(database);
    Map<int, Widget> widgetMap = await prepareSubscriptionDisplay(allSubscriptionFromDatabase);

    setState(() {
      debugPrint("initSub.allSub.len: " + allSubscriptionFromDatabase.length.toString());
      subscriptionWidgetMap.addAll(widgetMap);
      debugPrint("initSub.subscriptionWidgetMap.len: " + subscriptionWidgetMap.length.toString());
    });
  }
  // -------------------------------- /Init ------------------------------------

  // ------------------------------- gsignin -----------------------------------
  Future<Null> _handleSignIn() async {
    try {
      await _googleSignIn.signIn();
    } catch (error) {
      print(error);
    }
  }

  Future<Null> _handleSignOut() async {
    _googleSignIn.disconnect();
  }
  // ------------------------------ /gsignin -----------------------------------

  // ------------------------------ api calls ----------------------------------
  Future<List<Subscription>> getSubscriptionsFromYt() async {
    List<Subscription> subscriptionListFromAPI = new List();

    final authHeaders = _googleSignIn.currentUser.authHeaders;
    final httpClient = new GoogleHttpClient(await authHeaders);

    String nextPageToken = "";

    SubscriptionListResponse subscriptions = new SubscriptionListResponse();

    while (nextPageToken != null) {
      subscriptions = await callApi(httpClient, nextPageToken);
      nextPageToken = subscriptions.nextPageToken;
      subscriptionListFromAPI.addAll(subscriptions.items);
    }

    return subscriptionListFromAPI;
  }

  Future<SubscriptionListResponse> callApi(GoogleHttpClient httpClient, String nextPageToken) async {
    SubscriptionListResponse subscriptions = await new YoutubeApi(httpClient).subscriptions.list('snippet',
        mine: true,
        maxResults: 50,
        pageToken: nextPageToken,
        $fields: "etag,eventId,items,kind,nextPageToken,pageInfo,prevPageToken,tokenPagination,visitorId");
    return subscriptions;
  }
  // ----------------------------- /api calls ----------------------------------

  // --------------------------------- UI --------------------------------------

  final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();
  int _id;

  @override
  Widget build(BuildContext context) {
    return new DefaultTabController(length: 2, child: new Scaffold(key: _scaffoldKey, appBar: buildScaffoldAppBar(), body: buildScaffoldBody()));
  }

  Future<Map<int, Widget>> prepareSubscriptionDisplay(List<Subscription> subscriptionListFromAPI) async {
    Map<int, Widget> resultList = new Map<int, Widget>();
    int index = 0;

    if (subscriptionListFromAPI.isNotEmpty)
    {
      Iterator subListIterator = subscriptionListFromAPI.iterator;
      while (subListIterator.moveNext())
      {
        Subscription subYt = subListIterator.current;
        resultList[index] = await buildSubscriptionListTile(subYt, index++);
      }
    }
    else
    {
      resultList[index] = new Text("",textAlign: TextAlign.center);
      resultList[++index] = new Text("Tirez vers le bas pour actualiser vos abonnements !",textAlign: TextAlign.center, textScaleFactor: 1.6);
    }

    return resultList;
  }

  Future<Widget> buildSubscriptionListTile(Subscription sub, int index) async {
    ListTile result = new ListTile();

    if (sub != null) {
      SubscriptionDataBase subDb = await SubscriptionDataBase.getSubscriptionByYtId(sub.id, database);
      IconButton trailingButton = createNotifyButton(subDb, index);

      notificationButtonMap[index] = trailingButton;
      final String title = sub.snippet.title;
      final String desc = sub.snippet.description;
      final Image pp = new Image(image: new CachedNetworkImageProvider(sub.snippet.thumbnails.default_.url));

      result = new ListTile(
          title: new Text(title, style: new TextStyle(fontWeight: FontWeight.w500, fontSize: 20.0)),
          subtitle: new Text(
            desc,
            maxLines: 1,
          ),
          leading: pp,
          trailing: trailingButton,
          onTap: () {
            setState(() {
              _id = index; //if you want to assign the index somewhere to check
            });
            //_scaffoldKey.currentState.showSnackBar(new SnackBar(content: new Text("You clicked item number $_id")));
          });
    }
    return result;
  }

  Widget buildSubscriptionListTileFromUpdate(SubscriptionDataBase subDb, int index) {
    ListTile result = new ListTile();

    if (subDb != null) {
      IconButton trailingButton = createNotifyButton(subDb, index);

      notificationButtonMap[index] = trailingButton;
      final String title = subDb.snippet.title;
      final String desc = subDb.snippet.description;
      final Image pp = new Image.network(subDb.snippet.thumbnails.default_.url);
      result = new ListTile(
          title: new Text(title, style: new TextStyle(fontWeight: FontWeight.w500, fontSize: 20.0)),
          subtitle: new Text(
            desc,
            maxLines: 1,
          ),
          leading: pp,
          trailing: trailingButton,
          onTap: () {
            setState(() {
              _id = index; //if you want to assign the index somewhere to check
            });
            _scaffoldKey.currentState.showSnackBar(new SnackBar(content: new Text("You clicked item number $_id")));
          });
    }
    return result;
  }

  IconButton createNotifyButton(SubscriptionDataBase subDb, int index) {
    Color color = (subDb.notify ? Colors.red : Colors.grey);

    IconButton trailingButton = new IconButton(
      icon: new Icon(Icons.notifications),
      tooltip: 'Be notified !',
      onPressed: () {
        changeSubscriptionNotifyStatusInDB(subDb, index);
      },
      color: color,
      disabledColor: Colors.grey,
      highlightColor: Colors.red,
    );
    return trailingButton;
  }

  void changeSubscriptionNotifyStatusInDB(SubscriptionDataBase subDb, int index) {
    if (subDb.notify) {
      subDb.notify = false;
      subDb.update();
    } else {
      subDb.notify = true;
      subDb.update();
    }
    Color color = (subDb.notify ? Colors.red : Colors.grey);
    setState(() {
      notificationButtonMap[index] = new IconButton(
        icon: new Icon(Icons.notifications),
        tooltip: 'Be notified !',
        onPressed: () {
          changeSubscriptionNotifyStatusInDB(subDb, index);
        },
        color: color,
        disabledColor: Colors.grey,
        highlightColor: Colors.red,
      );
      subscriptionWidgetMap[index] = buildSubscriptionListTileFromUpdate(subDb, index);
    });
  }

  Widget buildPeertubeTab() {
    Column result = new Column();
    result = new Column(
      children: <Widget>[
        new Text("",textAlign: TextAlign.center),
        new Text("Travail en cours, prochaine version !",textAlign: TextAlign.center, textScaleFactor: 1.6),
      ],
    );

    return result;
  }

  Widget buildYoutubeTab() {
    Column result = new Column();
    if (_currentUser != null) {
      result = new Column(
        children: <Widget>[
          new Expanded(
            child: new RefreshIndicator(
                child: new ListView.builder(
                  itemBuilder: (BuildContext context, int index) => subscriptionWidgetMap[index],
                  itemCount: subscriptionWidgetMap.length,
                ),
                onRefresh: () => fetchYoutubeApiData()),
          ),
        ],
      );
    } else {
      print("_buildBody() : No user connected");
    }
    return result;
  }

  Widget buildScaffoldBody() {
    return new TabBarView(
      children: [
        new ConstrainedBox(
          constraints: const BoxConstraints.expand(),
          child: buildYoutubeTab(),
        ),
        new ConstrainedBox(
          constraints: const BoxConstraints.expand(),
          child: buildPeertubeTab(),
        ),
      ],
    );
  }

  Widget buildScaffoldAppBar() {
    return new AppBar(
      title: buildAppBarTitleWidget(),
      bottom: buildAppBarBottomWidget(),
    );
  }

  Widget buildAppBarTitleWidget() {
    return new Text("NotifyTube");
  }

  Widget buildAppBarBottomWidget() {
    return new TabBar(
      tabs: [
        new Row(
          children: <Widget>[
            new Expanded(
              child: new Text('YouTube', textAlign: TextAlign.center, style: new TextStyle(fontWeight: FontWeight.w500, fontSize: 20.0)),
            ),
            // FixMe: too early, crashes no identity
            //new GoogleUserCircleAvatar(
            //  identity: _currentUser,
            //),
          ],
        ),
        new Text('PeerTube', style: new TextStyle(fontWeight: FontWeight.w500, fontSize: 20.0)),
      ],
    );
  }
  // -------------------------------- /UI --------------------------------------

  // ------------------------------- Debug -------------------------------------
  Future printDbContent() async {
    SubscriptionDataBase.getAllSubscriptions(database).then((subs) => print("Number of subs: " + subs.length.toString()));
    SubscriptionDataBase.getAllSubscriptions(database).then((subs) =>
        subs.forEach((sub) => print(sub.localId.toString() + " : " + sub.snippet.title + " / " + sub.notify.toString() + " / " + sub.lastUpdate)));
  }
  // ------------------------------ /Debug -------------------------------------

  Future<Null> initNotifications() async {
    List<AndroidJobInfo> pendingJobs = await AndroidJobScheduler.getAllPendingJobs();
    Iterator pendingJobsIterator = pendingJobs.iterator;
    bool found = false;
    while (pendingJobsIterator.moveNext()) {
      AndroidJobInfo jobInfo = pendingJobsIterator.current;
      if (jobInfo.id == 42)
      {
        found = true;
        break;
      }
    }
    if (!found)
    {
      await AndroidJobScheduler.scheduleEvery(const Duration(hours: 1), 42, jobSchedulerCallback, persistentAcrossReboots: true);
    }
  }

  Future<Null> isJobPresent() async {
    List<AndroidJobInfo> pendingJobs = await AndroidJobScheduler.getAllPendingJobs();
    Iterator pendingJobsIterator = pendingJobs.iterator;
    bool found = false;
    while (pendingJobsIterator.moveNext()) {
      AndroidJobInfo jobInfo = pendingJobsIterator.current;
      if (jobInfo.id == 42)
      {
        found = true;
        break;
      }
    }
    if (!found)
    {
      print("NOT FOUND");
    }
    else
    {
      print("FOUND");
    }
  }

  initFileWatcher() async {
    Timer.periodic(const Duration(seconds: 10), updateCallBackTimesCalled);
  }

  updateCallBackTimesCalled([Timer _]) async {
    final file = await getCommonStateFile();
    var timesCalled;
    if (!await file.exists()) {
      timesCalled = 0;
    } else {
      timesCalled = int.parse(await file.readAsString());
    }
    setState(() {
      _timesCalled = timesCalled;
    });
  }

  updatePendingJobs() async {
    final jobs = await AndroidJobScheduler.getAllPendingJobs();
    setState(() {
      _pendingJobs = jobs.map((AndroidJobInfo i) => i.id).toList();
    });
  }
}

// ------------------------- Background activity -------------------------------
FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = new FlutterLocalNotificationsPlugin();
InitializationSettingsAndroid initializationSettingsAndroid = new InitializationSettingsAndroid("@mipmap/ic_launcher");
InitializationSettingsIOS initializationSettingsIOS = new InitializationSettingsIOS();
InitializationSettings initializationSettings = new InitializationSettings(initializationSettingsAndroid, initializationSettingsIOS);
Client httpClient = new Client();

Future<File> getCommonStateFile() async {
  final targetDir = await getApplicationDocumentsDirectory();
  return new File("${targetDir.path}/times_called.txt");
}

Future _showNotification(Map<String, Map<int, String>> updates) async {
  flutterLocalNotificationsPlugin.initialize(initializationSettings, selectNotification: onSelectNotification);
  var androidPlatformChannelSpecifics =
      new NotificationDetailsAndroid('42', 'NotifyTube', 'Be notified from your subscriptions', importance: Importance.Max, priority: Priority.High);
  var iOSPlatformChannelSpecifics = new NotificationDetailsIOS();
  var platformChannelSpecifics = new NotificationDetails(androidPlatformChannelSpecifics, iOSPlatformChannelSpecifics);
  await flutterLocalNotificationsPlugin.show(0, 'Nouvelles Vidéos !', updates.toString(), platformChannelSpecifics);
}

Future onSelectNotification(String payload) async {
  print("Notif");
}

void jobSchedulerCallback() async {
  NotifyTubeDatabase database = NotifyTubeDatabase.get();
  await database.init();


  Map<String, Map<int, String>> channelUpdatesMap = new Map<String, Map<int, String>>();

  List<SubscriptionDataBase> subs = await SubscriptionDataBase.getAllSubscriptionsWithNotify(database);
  print("Number of subs: " + subs.length.toString());

  Iterator subsIterator = subs.iterator;

  String httpGetResult;
  while (subsIterator.moveNext()) {
    SubscriptionDataBase sub = subsIterator.current;
    print("NotifyTube : " + sub.localId.toString() + " : " + sub.snippet.title + " / " + sub.notify.toString()+ " / " + sub.lastUpdate);

    httpGetResult = await httpClient.read("https://www.youtube.com/feeds/videos.xml?channel_id=" + sub.snippet.resourceId.channelId);


    xml.XmlDocument channelXML = xml.parse(httpGetResult);
    var videoMap = channelXML.findAllElements("entry");
    List<xml.XmlElement> videoList = videoMap.toList();
    Map<int, String> newVideoMap = new Map<int, String>();
    int videoIndex = 0;
    videoList.forEach((video) {
      DateTime published = DateTime.parse(video.findElements("published").first.text);
      print("Published : " + published.toString());
      DateTime lastUpdate = DateTime.parse(sub.lastUpdate);

      if (lastUpdate.isBefore(published)) {
        print("Video plus récente !");
        newVideoMap[videoIndex++] = video.findElements("title").first.text;
      }
    });
    if (newVideoMap.length > 0) {
      channelUpdatesMap[sub.snippet.title] = newVideoMap;
      sub.lastUpdate = DateTime.now().toUtc().toString();
      sub.update();
    }
  }

  if (channelUpdatesMap.length > 0) {
    await _showNotification(channelUpdatesMap);
  }

  //await _showNotification();
  //print('Yolo executing');
}
// ------------------------ /Background activity -------------------------------
