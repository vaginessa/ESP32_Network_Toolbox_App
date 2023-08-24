import 'package:flutter/material.dart';
import 'package:draggable_scrollbar/draggable_scrollbar.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'wifi_sniffer.dart';
import 'network_map.dart';
import 'wifi_scanner.dart';
import 'wifi_deauther.dart';
import 'blt_scanner.dart';
import 'esp_ota.dart';
import 'terminal.dart';
import 'constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // AppCheck
  await FirebaseAppCheck.instance.activate(
    androidProvider: (kReleaseMode == true)
        ? AndroidProvider.playIntegrity
        : AndroidProvider.debug,
  );
  runApp(App());
}

class App extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 Network ToolBox',
      theme: ThemeData(
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'RobotoMono',
        colorScheme: ColorScheme.fromSwatch(primarySwatch: Colors.grey)
            .copyWith(secondary: Colors.lightGreen),
      ),
      darkTheme: ThemeData(
        hintColor: Colors.grey[700],
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'RobotoMono',
        colorScheme: ColorScheme.fromSwatch(primarySwatch: Colors.grey)
            .copyWith(
                secondary: Colors.lightGreen, brightness: Brightness.dark),
      ),
      home: HomePage(title: appName),
    );
  }
}

class HomePage extends StatefulWidget {
  HomePage({Key? key, required this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  ScrollController _scrollController = new ScrollController();

  @override
  void initState() {
    super.initState();
    getCountryPref();
    getChannelPref();
    usbListener();
  }

  void usbListener() {
    UsbSerial.usbEventStream!.listen((UsbEvent msg) async {
      await getDevices();
      if (msg.event == UsbEvent.ACTION_USB_ATTACHED) {
        connectSerial(msg.device!);
      } else if (msg.event == UsbEvent.ACTION_USB_DETACHED) {
        setState(() {
          device = null;
          deviceConnected = false;
        });
      }
    });
  }

  Future<void> getDevices() async {
    devicesList = await UsbSerial.listDevices();
    setState(() {
      devicesList = devicesList;
    });
  }

  Future<bool> connectSerial(UsbDevice selectedDevice) async {
    usbPort = (await selectedDevice.create())!;

    bool openResult = await usbPort!.open();
    if (!openResult) {
      return false;
    }

    setState(() {
      device = selectedDevice;
      deviceConnected = true;
    });

    await usbPort!.setDTR(true);
    await usbPort!.setRTS(true);

    usbPort!.setPortParameters(
        BAUD_RATE, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

    return true;
  }

  Future<void> setCountryPref(String newValue) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('wifi_country', newValue);
  }

  void handleCountryChange(String? newValue) {
    setState(() {
      country = newValue!;
      setCountryPref(newValue);
    });
  }

  Future<void> getCountryPref() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      country = prefs.getString('wifi_country') ?? "FR";
    });
  }

  Future<void> setChanPref(String newValue) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('wifi_channel', newValue);
  }

  void handleChannelChange(String? newValue) {
    setState(() {
      channel = newValue!;
      setChanPref(newValue);
    });
  }

  Future<void> getChannelPref() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      channel = prefs.getString('wifi_channel') ?? "ALL";
    });
  }

  Widget buildDevicesList() {
    return DraggableScrollbar.semicircle(
        controller: _scrollController,
        child: ListView.builder(
          shrinkWrap: true,
          controller: _scrollController,
          itemBuilder: (context, index) {
            return Container(
              padding: EdgeInsets.all(8.0),
              child: Material(
                elevation: 4.0,
                borderRadius: BorderRadius.circular(4.0),
                child: Center(
                    child: ListTile(
                        title: Text("${devicesList[index].productName}"),
                        subtitle: Text(devicesList[index].manufacturerName!),
                        trailing: Icon(
                            (deviceConnected &&
                                    device!.deviceId ==
                                        devicesList[index].deviceId)
                                ? Icons.link_off
                                : Icons.link,
                            size: 30.0),
                        onTap: () => connectSerial(devicesList[index]))),
              ),
            );
          },
          itemCount: devicesList.length,
        ));
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    getDevices();
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
        centerTitle: true,
        leading: Builder(builder: (context) {
          return IconButton(
              icon: Icon(
                Icons.wifi,
                color: Colors.lightGreen,
                size: 30,
              ),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              });
        }),
        actions: [
          Padding(
              padding: const EdgeInsets.only(right: 5.0),
              child: Builder(builder: (context) {
                return IconButton(
                    icon: Icon(
                      Icons.bluetooth,
                      color: Colors.lightBlue,
                      size: 30,
                    ),
                    onPressed: () => {Scaffold.of(context).openEndDrawer()});
              }))
        ],
      ),
      drawer: Drawer(
        child: ListView(
          children: [
            Padding(
                padding: const EdgeInsets.only(top: 20.0, bottom: 20.0),
                child: Container(
                  child: Text(
                    'Wifi Tools',
                    style: TextStyle(fontSize: 25, color: Colors.lightGreen),
                    textAlign: TextAlign.center,
                  ),
                  decoration: BoxDecoration(
                      border:
                          Border(bottom: BorderSide(color: Colors.black26))),
                )),
            Padding(
                padding: const EdgeInsets.only(top: 20.0),
                child: ListTile(
                  title: Text(
                    'Scan/Connect',
                    style: TextStyle(fontSize: 25),
                    textAlign: TextAlign.center,
                  ),
                  onTap: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => WifiScannerPage()));
                  },
                )),
            Padding(
                padding: const EdgeInsets.only(top: 20.0),
                child: ListTile(
                  title: Text(
                    'Sniffer',
                    style: TextStyle(fontSize: 25),
                    textAlign: TextAlign.center,
                  ),
                  onTap: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => WifiSnifferPage()));
                  },
                )),
            Padding(
                padding: const EdgeInsets.only(top: 20.0),
                child: ListTile(
                  title: Text(
                    'NetworksMap',
                    style: TextStyle(fontSize: 25),
                    textAlign: TextAlign.center,
                  ),
                  onTap: () {
                    Navigator.push(context,
                        MaterialPageRoute(builder: (context) => MapPage()));
                  },
                )),
            Padding(
                padding: const EdgeInsets.only(top: 20.0),
                child: ListTile(
                  title: Text(
                    'Deauther',
                    style: TextStyle(fontSize: 25),
                    textAlign: TextAlign.center,
                  ),
                  onTap: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => WifiDeautherPage()));
                  },
                )),
          ],
        ),
      ),
      endDrawer: Drawer(
          child: ListView(children: [
        Padding(
            padding: const EdgeInsets.only(top: 20.0, bottom: 20.0),
            child: Container(
              child: Text(
                'Bluetooth Tools',
                style: TextStyle(fontSize: 25, color: Colors.lightBlue),
                textAlign: TextAlign.center,
              ),
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.black26))),
            )),
        Padding(
            padding: const EdgeInsets.only(top: 20.0),
            child: ListTile(
              title: Text(
                'Scan',
                style: TextStyle(fontSize: 25),
                textAlign: TextAlign.center,
              ),
              onTap: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (context) => BltScannerPage()));
              },
            )),
      ])),
      body: SingleChildScrollView(
          child: Column(children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 20.0),
              child: Text(
                "WIFI Country: ",
                style: TextStyle(
                    fontSize: 25,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 20.0),
              child: DropdownButton<String>(
                value: country,
                onChanged: (String? newValue) {
                  handleCountryChange(newValue);
                },
                items:
                    countriesList.map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value, style: TextStyle(fontSize: 25)),
                  );
                }).toList(),
              ),
            )
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 20.0),
              child: Text(
                "WIFI Channel: ",
                style: TextStyle(
                    fontSize: 25,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 20.0),
              child: DropdownButton<String>(
                value: channel,
                onChanged: (String? newValue) {
                  handleChannelChange(newValue);
                },
                items:
                    channelsList.map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value, style: TextStyle(fontSize: 25)),
                  );
                }).toList(),
              ),
            )
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 20.0),
              child: Text(
                "USB ESP32: ",
                style: TextStyle(
                    fontSize: 25,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 20.0),
              child: IconButton(
                icon: Icon(Icons.refresh, size: 30.0),
                onPressed: () => getDevices(),
              ),
            )
          ],
        ),
        Padding(
            padding: const EdgeInsets.only(top: 20.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: <Widget>[
                Expanded(
                    child: (devicesList.isNotEmpty)
                        ? buildDevicesList()
                        : Text(
                            "No device Found",
                            style: TextStyle(fontSize: 20.0),
                            textAlign: TextAlign.center,
                          )),
              ],
            )),
        Padding(
          padding: const EdgeInsets.only(top: 50.0),
          child: TextButton.icon(
            label: Text(
              'ESP32 Terminal',
              style: TextStyle(
                  fontSize: 25,
                  color: (deviceConnected) ? Colors.white : Colors.grey),
              textAlign: TextAlign.center,
            ),
            icon: Icon(
              Icons.computer,
              color: (deviceConnected) ? Colors.white : Colors.grey,
            ),
            onPressed: (deviceConnected)
                ? () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => TerminalPage()));
                  }
                : () {},
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 50.0),
          child: TextButton.icon(
            label: Text(
              'Update ESP32',
              style: TextStyle(
                  fontSize: 25,
                  color: (deviceConnected) ? Colors.white : Colors.grey),
              textAlign: TextAlign.center,
            ),
            icon: Icon(
              Icons.offline_bolt,
              color: (deviceConnected) ? Colors.white : Colors.grey,
            ),
            onPressed: (deviceConnected)
                ? () {
                    Navigator.push(context,
                        MaterialPageRoute(builder: (context) => OTAPage()));
                  }
                : () {},
          ),
        ),
      ])),
    );
  }
}
