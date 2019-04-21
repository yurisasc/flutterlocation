import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Background Location Notifier',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(title: 'Background Location Notifier'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  Location _locationService  = new Location();


  @override
  void initState() {
    super.initState();


  }

  static void backgroundCallback(List<LocationData> locations) async {
    print('Sample app received data location: $locations');

    FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = new FlutterLocalNotificationsPlugin();
    var initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    var initializationSettingsIOS = IOSInitializationSettings();
    var initializationSettings = InitializationSettings(initializationSettingsAndroid, initializationSettingsIOS);
    flutterLocalNotificationsPlugin.initialize(initializationSettings);

    var androidPlatformChannelSpecifics = new AndroidNotificationDetails(
        'location_update', 'Location Updates', 'You will receive location updates here',
        importance: Importance.Max, priority: Priority.High);
    var iOSPlatformChannelSpecifics = new IOSNotificationDetails();
    var platformChannelSpecifics = new NotificationDetails(
        androidPlatformChannelSpecifics, iOSPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(
        0, 'New Location Received !', "${locations[0].latitude}, ${locations[0].longitude}", platformChannelSpecifics);

  }

  void _registerListener() async {
    bool _permission = await _locationService.requestPermission();
    print("Permission: $_permission");
    if (_permission) {
      bool statusBackgroundLocation = await _locationService.registerBackgroundLocation(backgroundCallback);
      print("statusBackgroundLocation: $statusBackgroundLocation");
    } else {
      print("Permission denied");
    }
    
  }

  void _removeListener() async {
    await _locationService.removeBackgroundLocation();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(8.0),
          child: Column(
            children: <Widget>[
              RaisedButton(
                onPressed: () {_registerListener();},
                child: const Text('Register background service'),
              ),
              RaisedButton(
                onPressed: () {_removeListener();},
                child: const Text('Remove background service'),
              ),
            ],
          ),
        )
      ),
    );
  }
}
