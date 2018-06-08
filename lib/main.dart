import 'dart:async';
import 'dart:convert' show json;

import "package:http/http.dart" as http;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
  GoogleSignInAccount _currentUser;
  String _subText;
  List<Widget> subscriptionList;
  void fetchData() {
    subscriptionList.clear();
    setState(() {
      _handleGetSubscriptions();
    });
  }

  @override
  void initState() {
    super.initState();
    subscriptionList = new List();
    _googleSignIn.onCurrentUserChanged.listen((GoogleSignInAccount account) {
      setState(() {
        _currentUser = account;
        if (_currentUser != null) {
          fetchData();
        }
      });
    });
    _googleSignIn.signInSilently();
  }

  Future<Null> _handleGetSubscriptions({String nextPageToken: ""}) async {
    setState(() {
      _subText = "Loading users subscriptions...";
    });
    print("Before request npt: " + nextPageToken);
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
          new RaisedButton(
            child: const Text('SIGN OUT'),
            onPressed: _handleSignOut,
          ),
          new RaisedButton(
            child: const Text('REFRESH'),
            onPressed: () {
              fetchData();
            },
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
                      new GoogleUserCircleAvatar(
                        identity: _currentUser,
                      ),
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
}
