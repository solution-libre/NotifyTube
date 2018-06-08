import 'dart:async';
import 'dart:convert' show json;

import "package:http/http.dart" as http;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
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

import 'package:NotifyTube/SecondScreen.dart';

GoogleSignIn _googleSignIn = new GoogleSignIn(
  scopes: <String>[
    'email',
    'https://www.googleapis.com/auth/contacts.readonly',
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
  String _subText;
  List<Widget> subscriptionList;
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

  void fetchYoutubeApiData() {
    subscriptionList.clear();
    setState(() {
      _handleGetSubscriptions();
    });
  }

  @override
  void initState() {
    super.initState();
    initSubscriptions();
    initGoogleSignIn();
    initNotifications();
  }

  // --------------------------------- Init ------------------------------------

  void initSubscriptions() {
    subscriptionList = new List();
  }

  void initGoogleSignIn() {
    _googleSignIn.onCurrentUserChanged.listen((GoogleSignInAccount account) {
      setState(() {
        _currentUser = account;
        if (_currentUser != null) {
          fetchYoutubeApiData();
        }
      });
    });
    _googleSignIn.signInSilently();
  }

  // -------------------------------- /Init ------------------------------------

  Future<Null> _handleGetSubscriptions({String nextPageToken: ""}) async {
    setState(() {
      _subText = "Loading users subscriptions...";
    });
    final String request =
        "https://www.googleapis.com/youtube/v3/subscriptions?part=snippet"
            "&mine=true"
            "&fields=etag%2CeventId%2Citems%2Ckind%2CnextPageToken%2CpageInfo%2CprevPageToken%2CtokenPagination%2CvisitorId"
            "&maxResults=50" +
            nextPageToken;
    print("Request: " + request);
    final http.Response response = await http.get(
      request,
      headers: await _currentUser.authHeaders,
    );
    if (response.statusCode != 200) {
      setState(() {
        _subText = "Youtube API gave a ${response.statusCode} "
            "response. Check logs for details.";
      });
      print('Youtube API ${response.statusCode} response: ${response.body}');
      return;
    } else {
      final Map<String, dynamic> data = json.decode(response.body);
      setState(() {
        getSubscriptions(data);
      });
    }
  }

  void getSubscriptions(Map<String, dynamic> data) {
    List<Widget> resultList = new List();
    final List<dynamic> subscriptions = data['items'];
    final String nextPageToken = data['nextPageToken'];

    for (var i = 0; i < subscriptions.length; i++) {
      final Map<String, dynamic> sub = subscriptions[i];
      if (sub != null) {
        final String title = sub['snippet']['title'];
        final String desc = sub['snippet']['description'];
        final Image pp = new Image.network(sub['snippet']['thumbnails']['default']['url']);
        buildListElement(pp, title, desc, resultList);
      }
    }

    if (nextPageToken != "" && nextPageToken != null) {
      print("&nextPageToken=" + nextPageToken);
      _handleGetSubscriptions(nextPageToken: "&pageToken=" + nextPageToken);
    } else {
      setState(() {
        _subText = "";
      });
    }
    subscriptionList.addAll(resultList);
    print("subscriptionList length: " + subscriptionList.length.toString());
  }

  void buildListElement(Image pp, String title, String desc, List<Widget> resultList) {
    if (title != null) {
      resultList.add(
        new ListTile(
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
                  subscriptionList[index],
              itemCount: subscriptionList.length,
            ),
          ),
          new Row(
            children: <Widget>[
              new RaisedButton(
                child: const Text('SIGN OUT'),
                onPressed: _handleSignOut,
              ),
              new RaisedButton(
                child: const Text('REFRESH'),
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
            ],
          ),

        ],
      );
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
  void initNotifications() {
    flutterLocalNotificationsPlugin = new FlutterLocalNotificationsPlugin();
    InitializationSettingsAndroid initializationSettingsAndroid =
    new InitializationSettingsAndroid("@mipmap/ic_launcher");
    InitializationSettingsIOS initializationSettingsIOS =
    new InitializationSettingsIOS();
    InitializationSettings initializationSettings = new InitializationSettings(
        initializationSettingsAndroid, initializationSettingsIOS);
    flutterLocalNotificationsPlugin.initialize(initializationSettings,
        selectNotification: onSelectNotification);
  }

  Future onSelectNotification(String payload) async {
    if (payload != null) {
      debugPrint('notification payload: ' + payload);
    }

    await Navigator.push(
      context,
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
    await flutterLocalNotificationsPlugin.show(
        0, 'Une jolie notif', 'On peut même cliquer dessus oO', platformChannelSpecifics,
        payload: 'item x');
  }
}

// --------------------------- /Notifications ----------------------------------
