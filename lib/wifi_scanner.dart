import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:usb_serial/transaction.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:csv/csv.dart';

import 'utils.dart';
import 'constants.dart';

class WifiScannerPage extends StatefulWidget {
  WifiScannerPage({Key? key}) : super(key: key);

  @override
  _WifiScannerPageState createState() => _WifiScannerPageState();
}

class _WifiScannerPageState extends State<WifiScannerPage> {
  List<Map<String, dynamic>> networksList = [];
  bool waitVisible = false;
  final passwordController = TextEditingController();
  bool scanning = false;
  var subscription;
  List<List> networks = [
    ["ssid", "bssid", "channel"]
  ];

  @override
  void initState() {
    super.initState();
    usbListener();
    scanNetworks();
  }

  void dispose() {
    super.dispose();
    if (subscription != null) {
      subscription.cancel();
    }
  }

  void usbListener() {
    UsbSerial.usbEventStream!.listen((UsbEvent msg) async {
      await getDevices();
      if (msg.event == UsbEvent.ACTION_USB_ATTACHED) {
        connectSerial(msg.device!);
      } else if (msg.event == UsbEvent.ACTION_USB_DETACHED) {
        if (mounted) {
          setState(() {
            device = null;
            deviceConnected = false;
          });
        }
      }
    });
  }

  Future<void> getDevices() async {
    devicesList = await UsbSerial.listDevices();
    if (mounted) {
      setState(() {
        devicesList = devicesList;
      });
    }
  }

  Future<bool> connectSerial(UsbDevice selectedDevice) async {
    usbPort = await selectedDevice.create();

    bool openResult = await usbPort!.open();
    if (!openResult) {
      return false;
    }

    if (mounted) {
      setState(() {
        device = selectedDevice;
        deviceConnected = true;
      });
    }

    await usbPort!.setDTR(true);
    await usbPort!.setRTS(true);

    usbPort!.setPortParameters(
        BAUD_RATE, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

    return true;
  }

  loadProgress() {
    if (waitVisible == true) {
      if (mounted) {
        setState(() {
          waitVisible = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          waitVisible = true;
        });
      }
    }
  }

  Future<void> connectNetwork(context, String ssid, String pass) async {
    Transaction<String> transaction = Transaction.stringTerminated(
        usbPort!.inputStream!, Uint8List.fromList([13, 10]));
    subscription = transaction.stream.listen((String data) {
      if (data.isNotEmpty) {
        Map<String, dynamic> ip = jsonDecode(data);
        if (ip.containsKey("IP") && ip["IP"] != "None") {
          int i;
          for (i = 0; i < networksList.length; ++i) {
            if (networksList[i]["SSID"] == ip["SSID"]) {
              currSSID = ip["SSID"];
              break;
            }
          }
          if (mounted) {
            setState(() {
              networksList[i]["CONNECTED"] = true;
              waitVisible = false;
            });
          }
        }
      }
    });
    currSSID = "";
    String creds = "wifi_connect " + ssid + " " + pass;
    usbPort!.write(Uint8List.fromList(creds.codeUnits + [13, 10]));
    await Future.delayed(const Duration(seconds: scanDelay), () {});
    subscription.cancel();
    if (mounted) {
      setState(() {
        waitVisible = false;
      });
    }
  }

  Future<void> scanNetworks() async {
    if (mounted) {
      setState(() {
        waitVisible = true;
        scanning = true;
        networksList.clear();
        networks = [
          ["ssid", "bssid", "channel"]
        ];
      });
    }

    Transaction<String> transaction = Transaction.stringTerminated(
        usbPort!.inputStream!, Uint8List.fromList([13, 10]));
    subscription = transaction.stream.listen((String data) {
      if (data.isNotEmpty) {
        Map<String, dynamic> network = jsonDecode(data);
        if (network.containsKey("SSID") && mounted) {
          setState(() {
            if (currSSID.length != 0 && network["SSID"] == currSSID) {
              network["CONNECTED"] = true;
            } else {
              network["CONNECTED"] = false;
            }
            networksList.add(network);
            networks
                .add([network["SSID"], network["BSSID"], network["CHANNEL"]]);
            if (!ssidsList.contains(network["SSID"])) {
              ssidsList.add(network["SSID"]);
            }
            if (!networksMap.keys.contains(network["SSID"])) {
              networksMap[network["SSID"]] = {
                "BSSID": network["BSSID"],
                "VENDOR": "",
                "CHANNEL": network["CHANNEL"],
                "STAs": {
                  "ff:ff:ff:ff:ff:ff": "None",
                }
              };
            }
          });
        }
        data = "";
      }
    });

    usbPort!.write(Uint8List.fromList("wifi_scan".codeUnits + [13, 10]));
    await Future.delayed(const Duration(seconds: 10), () {});
    subscription.cancel();
    if (mounted) {
      setState(() {
        waitVisible = false;
        scanning = false;
      });
    }
    String csv = const ListToCsvConverter().convert(networks);
    final file = await localFile("Wifi_Scanner", "csv");
    await file!.writeAsString(csv);
  }

  void _openPopup(String ssid, BuildContext context) {
    int i;
    for (i = 0; i < networksList.length; ++i) {
      if (networksList[i]["SSID"] == ssid) {
        break;
      }
    }
    if (networksList[i]["CONNECTED"]) {
      connectNetwork(context, ssid, "");
      if (mounted) {
        setState(() {
          networksList[i]["CONNECTED"] = false;
        });
      }
    } else {
      showDialog(
          context: context,
          builder: (context) => AlertDialog(
                  title: Text("Connect to " + ssid),
                  content: TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      icon: Icon(Icons.lock),
                      labelText: 'Password',
                    ),
                  ),
                  actions: [
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          waitVisible = true;
                        });
                        connectNetwork(context, ssid, passwordController.text);
                        Navigator.pop(context);
                      },
                      child: Text(
                        "Connect",
                        style: TextStyle(color: Colors.white, fontSize: 20),
                      ),
                    )
                  ]));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text('Wifi Networks'),
          actions: <Widget>[
            IconButton(
              icon: Icon(Icons.refresh, size: 30.0),
              onPressed:
                  (deviceConnected && scanning == false) ? scanNetworks : null,
            ),
          ],
        ),
        body: Center(
          child: Column(
            children: <Widget>[
              if (deviceConnected)
                Visibility(
                    maintainSize: false,
                    maintainAnimation: true,
                    maintainState: true,
                    visible: waitVisible,
                    child: Container(
                        margin: EdgeInsets.only(top: 50, bottom: 30),
                        child: CircularProgressIndicator())),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: scanNetworks,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemBuilder: (context, position) {
                      return Column(
                        children: <Widget>[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        12.0, 12.0, 12.0, 6.0),
                                    child: Text(
                                      networksList[position]["SSID"] ?? "None",
                                      style: TextStyle(
                                          fontSize: 22.0,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        12.0, 12.0, 12.0, 6.0),
                                    child: Text(
                                      networksList[position]["BSSID"] ?? "None",
                                      style: TextStyle(fontSize: 18.0),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        12.0, 6.0, 12.0, 12.0),
                                    child: Text(
                                      networksList[position]["AUTH_MODE"] ??
                                          "None",
                                      style: TextStyle(fontSize: 18.0),
                                    ),
                                  ),
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: <Widget>[
                                    Text(
                                      "chan: " +
                                          networksList[position]["CHANNEL"]
                                              .toString(),
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                    Text(
                                      "rssi: " +
                                          networksList[position]["RSSI"]
                                              .toString(),
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: new IconButton(
                                        icon: new Icon((networksList[position]
                                                ["CONNECTED"])
                                            ? Icons.wifi_off
                                            : Icons.wifi),
                                        onPressed: (scanning == false)
                                            ? () {
                                                _openPopup(
                                                    networksList[position]
                                                        ["SSID"],
                                                    context);
                                              }
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Divider(
                            height: 2.0,
                            color: Colors.grey,
                          )
                        ],
                      );
                    },
                    itemCount: networksList.length,
                  ),
                ),
              )
            ],
          ),
        ));
  }
}
