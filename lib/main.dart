import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';

import 'package:google_sign_in/google_sign_in.dart'
    show GoogleSignIn, GoogleSignInAccount;

import 'package:googleapis/youtube/v3.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications/initialization_settings.dart';
import 'package:flutter_local_notifications/notification_details.dart';
import 'package:flutter_local_notifications/platform_specifics/android/initialization_settings_android.dart';
import 'package:flutter_local_notifications/platform_specifics/android/notification_details_android.dart';
import 'package:flutter_local_notifications/platform_specifics/android/styles/big_text_style_information.dart';
import 'package:flutter_local_notifications/platform_specifics/android/styles/default_style_information.dart';
import 'package:flutter_local_notifications/platform_specifics/android/styles/inbox_style_information.dart';
import 'package:flutter_local_notifications/platform_specifics/ios/initialization_settings_ios.dart';
import 'package:flutter_local_notifications/platform_specifics/ios/notification_details_ios.dart';

import 'package:android_alarm_manager/android_alarm_manager.dart';

import 'package:NotifyTube/GoogleHttpClient.dart';
import 'package:NotifyTube/NotifyTubeDatabase.dart';
import 'package:NotifyTube/SecondScreen.dart';

GoogleSignIn _googleSignIn = new GoogleSignIn(
  scopes: <String>[
    'email',
    'https://www.googleapis.com/auth/youtube',
    'https://www.googleapis.com/auth/youtubepartner',
  ],
);

void main() {
  runApp(
    new MaterialApp(
      title: 'NotifyTube',
      home: new NotifyTube(),
    ),
  );
}

class NotifyTube extends StatefulWidget {
  @override
  State createState() => new NotifyTubeState();
}

class NotifyTubeState extends State<NotifyTube> {
  // state changing elements
  GoogleSignInAccount _currentUser;
  String _subText = "";
  List<Widget> subscriptionWidgetList = new List();
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;
  NotifyTubeDatabase database;

  @override
  void initState() {
    super.initState();
    initDatabase().then((plop) {
      initGoogleSignIn();
      initSubscriptions();
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

  Future fetchYoutubeApiData() async {
    setState(() {
      _subText = "Loading users subscriptions from Yt...";
    });

    if (_currentUser != null) {

      //1. get subs
      List<Subscription> subscriptionListFromAPI =
          await getSubscriptionsFromYt();

      //2. update our database to the subs
      database.updateSubscriptionsFromYt(subscriptionListFromAPI).then((future) async => await initSubscriptions());

    } else {
      setState(() {
        _subText = "No user connected...";
      });
    }
  }

  Future initSubscriptions() async {
    setState(() {
      _subText = "Loading users subscriptions from Database...";
      subscriptionWidgetList.clear();
    });

    List<SubscriptionDataBase> allSubscriptionFromDatabase = await database.getAllSubscriptions();

    print ("initSub.allSub.len: " + allSubscriptionFromDatabase.length.toString());

    setState(() {
      subscriptionWidgetList = prepareSubscriptionDisplay(allSubscriptionFromDatabase);
      _subText = "";
    });
  }

  // -------------------------------- /Init ------------------------------------

  Future<List<Subscription>> getSubscriptionsFromYt() async {
    List<Subscription> subscriptionListFromAPI = new List();
    List<Widget> resultList = new List();

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

  Future<SubscriptionListResponse> callApi(
      GoogleHttpClient httpClient, String nextPageToken) async {
    SubscriptionListResponse subscriptions = await new YoutubeApi(httpClient)
        .subscriptions
        .list('snippet',
            mine: true,
            maxResults: 50,
            pageToken: nextPageToken,
            $fields:
                "etag,eventId,items,kind,nextPageToken,pageInfo,prevPageToken,tokenPagination,visitorId");
    return subscriptions;
  }

  List<Widget> prepareSubscriptionDisplay(List<Subscription> subscriptionListFromAPI) {
    List<Widget> resultList = new List();
    subscriptionListFromAPI.forEach((subscription) => resultList.add(buildListElement(subscription)));
    return resultList;
  }

  Widget buildListElement(Subscription sub ) {
    if (sub != null) {
      final String title = sub.snippet.title;
      final String desc = sub.snippet.description;
      final Image pp = new Image.network(sub.snippet.thumbnails.default_.url);
      return new ListTile(
        title: new Text(title,
            style:
            new TextStyle(fontWeight: FontWeight.w500, fontSize: 20.0)),
        subtitle: new Text(
          desc,
          maxLines: 1,
        ),
        leading: pp,
        trailing: new Icon(
          Icons.notifications,
          color: Colors.grey[500],
        ),
      );
    }
  }

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

  Widget _buildBody() {
    if (_currentUser != null) {
      return new Column(
        children: <Widget>[
          //const Text("Signed in successfully."),
          new Text(_subText),

          new Expanded(
            child: new ListView.builder(
              itemBuilder: (BuildContext context, int index) =>
                  subscriptionWidgetList[index],
              itemCount: subscriptionWidgetList.length,
            ),
          ),
          new Row(
            children: <Widget>[
              new RaisedButton(
                child: const Text('SIGN OUT'),
                onPressed: _handleSignOut,
              ),
              new RaisedButton(
                child: const Text('SYNC'),
                onPressed: () {
                  fetchYoutubeApiData();
                },
              ),
              new RaisedButton(
                child: const Text('NOTIF'),
                onPressed: () {
                  _showNotification();
                },
              ),
              new RaisedButton(
                child: const Text('DB_CONTENT'),
                onPressed: () {
                  printDbContent();
                },
              ),
            ],
          ),
        ],
      );
    } else {
      print("No user connected");
    }
  }

  @override
  Widget build(BuildContext context) {
    return new DefaultTabController(
        length: 2,
        child: new Scaffold(
            appBar: new AppBar(
              title: new Text("NotifyTube"),
              bottom: new TabBar(
                tabs: [
                  new Row(
                    children: <Widget>[
                      new Expanded(
                        child: new Text('YouTube',
                            textAlign: TextAlign.center,
                            style: new TextStyle(
                                fontWeight: FontWeight.w500, fontSize: 20.0)),
                      ),
                      // FixMe: too early, crashes no identity
                      //new GoogleUserCircleAvatar(
                      //  identity: _currentUser,
                      //),
                    ],
                  ),
                  new Text('PeerTube',
                      style: new TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 20.0)),
                ],
              ),
            ),
            body: new TabBarView(
              children: [
                new ConstrainedBox(
                  constraints: const BoxConstraints.expand(),
                  child: _buildBody(),
                ),
                new Text('Work in progress'),
              ],
            )));
  }

  // --------------------------- Notifications ---------------------------------
  Future<Null> initNotifications() async {
    flutterLocalNotificationsPlugin = new FlutterLocalNotificationsPlugin();
    InitializationSettingsAndroid initializationSettingsAndroid =
        new InitializationSettingsAndroid("@mipmap/ic_launcher");
    InitializationSettingsIOS initializationSettingsIOS =
        new InitializationSettingsIOS();
    InitializationSettings initializationSettings = new InitializationSettings(
        initializationSettingsAndroid, initializationSettingsIOS);
    flutterLocalNotificationsPlugin.initialize(initializationSettings,
        selectNotification: onSelectNotification);

    //final int helloAlarmID = 0;

    //await AndroidAlarmManager.periodic(const Duration(minutes: 1), helloAlarmID, printHello);
  }

  Future onSelectNotification(String payload) async {
    if (payload != null) {
      debugPrint('notification payload: ' + payload);
    }

    await Navigator.push(
      this.context,
      new MaterialPageRoute(builder: (context) => new SecondScreen(payload)),
    );
  }

  Future _showNotification() async {
    var androidPlatformChannelSpecifics = new NotificationDetailsAndroid(
        'your channel id', 'your channel name', 'your channel description',
        importance: Importance.Max, priority: Priority.High);
    var iOSPlatformChannelSpecifics = new NotificationDetailsIOS();
    var platformChannelSpecifics = new NotificationDetails(
        androidPlatformChannelSpecifics, iOSPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(0, 'Une jolie notif',
        'On peut même cliquer dessus oO', platformChannelSpecifics,
        payload: 'item x');
  }

  Future printDbContent() async {
    database
        .getAllSubscriptions()
        .then((subs) => print("Number of subs: " + subs.length.toString()));
    database.getAllSubscriptions().then((subs) => subs.forEach(
        (sub) => print(sub.localId.toString() + " : " + sub.snippet.title)));
  }
}

void printHello() {
  final DateTime now = new DateTime.now();
  final int isolateId = Isolate.current.hashCode;
  print("[$now] Hello, world! isolate=$isolateId function='$printHello'");
}
// --------------------------- /Notifications ----------------------------------
