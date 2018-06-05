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

  @override
  void initState() {
    super.initState();
    _googleSignIn.onCurrentUserChanged.listen((GoogleSignInAccount account) {
      setState(() {
        _currentUser = account;
      });
      if (_currentUser != null) {
        _handleGetSubscriptions();
      }
    });
    _googleSignIn.signInSilently();
  }

  Future<Null> _handleGetSubscriptions() async {
    setState(() {
      _subText = "Loading users subscriptions...";
    });
    final http.Response response = await http.get(
      'https://www.googleapis.com/youtube/v3/subscriptions?part=snippet&mine=true',
      headers: await _currentUser.authHeaders,
    );
    if (response.statusCode != 200) {
      setState(() {
        _subText = "Youtube API gave a ${response.statusCode} "
            "response. Check logs for details.";
      });
      print('Youtube API ${response.statusCode} response: ${response.body}');
      return;
    }
    final Map<String, dynamic> data = json.decode(response.body);
    final String subscription = _pickFirstSubscription(data);
    setState(() {
      if (subscription != null) {
        _subText = "I see you know $subscription!";
      } else {
        _subText = "No sub to display.";
      }
    });
  }

  String _pickFirstSubscription(Map<String, dynamic> data) {
    final List<dynamic> subscriptions = data['items'];
    final Map<String, dynamic> sub = subscriptions?.firstWhere(
          (dynamic sub) => sub['snippet'] != null,
      orElse: () => null,
    );
    if (sub != null) {
      final String title = sub['snippet']['title'];
      if (title != null) {
        return title;
      }
    }
    return null;
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
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          new ListTile(
            leading: new GoogleUserCircleAvatar(
              identity: _currentUser,
            ),
            title: new Text(_currentUser.displayName),
            subtitle: new Text(_currentUser.email),
          ),
          const Text("Signed in successfully."),
          new Text(_subText),
          new RaisedButton(
            child: const Text('SIGN OUT'),
            onPressed: _handleSignOut,
          ),
          new RaisedButton(
            child: const Text('REFRESH'),
            onPressed: _handleGetSubscriptions,
          ),
        ],
      );
    } else {
      return new Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          const Text("You are not currently signed in."),
          new RaisedButton(
            child: const Text('SIGN IN'),
            onPressed: _handleSignIn,
          ),
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
        appBar: new AppBar(
          title: const Text('NotifyTube'),
        ),
        body: new ConstrainedBox(
          constraints: const BoxConstraints.expand(),
          child: _buildBody(),
        ));
  }
}