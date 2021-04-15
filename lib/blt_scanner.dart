import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:usb_serial/transaction.dart';
import 'package:usb_serial/usb_serial.dart';

import 'constants.dart';

class BltScannerPage extends StatefulWidget {
  BltScannerPage({Key key}) : super(key: key);

  @override
  _BltScannerPageState createState() => _BltScannerPageState();
}

class _BltScannerPageState extends State<BltScannerPage> {
  bool waitVisible = false;
  final passwordController = TextEditingController();
  bool scanning = false;
  var subscription;

  @override
  void initState() {
    super.initState();
    bltDevicesList = [];
    usbListener();
    scanDevices();
  }

  void dispose() {
    super.dispose();
    if (subscription != null) {
      subscription.cancel();
    }
  }

  void usbListener() {
    UsbSerial.usbEventStream.listen((UsbEvent msg) async {
      await getDevices();
      if (msg.event == UsbEvent.ACTION_USB_ATTACHED) {
        connectSerial(msg.device);
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

    bool openResult = await usbPort.open();
    if (!openResult) {
      return false;
    }

    if (mounted) {
      setState(() {
        device = selectedDevice;
        deviceConnected = true;
      });
    }

    await usbPort.setDTR(true);
    await usbPort.setRTS(true);

    usbPort.setPortParameters(
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

  Future<void> scanDevices() async {
    if (mounted) {
      setState(() {
        waitVisible = true;
        scanning = true;
        bltDevicesList.clear();
      });
    }

    Transaction<String> transaction = Transaction.stringTerminated(
        usbPort.inputStream, Uint8List.fromList([13, 10]));
    subscription = transaction.stream.listen((String data) {
      if (data.isNotEmpty) {
        Map<String, dynamic> device = jsonDecode(data);
        if (mounted &&
            device.containsKey("MAC") &&
            !bltDevicesList.any(
                (deviceFromList) => device["MAC"] == deviceFromList["MAC"])) {
          setState(() {
            bltDevicesList.add(device);
          });
        }
        data = null;
      }
    });

    usbPort.write(Uint8List.fromList("blt_scan".codeUnits + [13, 10]));
    await Future.delayed(const Duration(seconds: 10), () {});
    subscription.cancel();
    if (mounted) {
      setState(() {
        waitVisible = false;
        scanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text('Bluetooth Devices'),
          actions: <Widget>[
            IconButton(
              icon: Icon(Icons.refresh, size: 30.0),
              onPressed:
                  (deviceConnected && scanning == false) ? scanDevices : null,
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
                  onRefresh: scanDevices,
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
                                      bltDevicesList[position]["NAME"] ??
                                          "None",
                                      style: TextStyle(
                                          fontSize: 22.0,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        12.0, 12.0, 12.0, 6.0),
                                    child: Text(
                                      bltDevicesList[position]["MAC"] ?? "None",
                                      style: TextStyle(fontSize: 18.0),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        12.0, 6.0, 12.0, 12.0),
                                    child: FittedBox(
                                        fit: BoxFit.fitWidth,
                                        child: Text(
                                          bltDevicesList[position]["TYPE"] ??
                                              "None",
                                          style: TextStyle(fontSize: 16.0),
                                        )),
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
                                      "rssi: " +
                                          bltDevicesList[position]["RSSI"]
                                              .toString(),
                                      style: TextStyle(color: Colors.grey),
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
                    itemCount: bltDevicesList.length,
                  ),
                ),
              )
            ],
          ),
        ));
  }
}
