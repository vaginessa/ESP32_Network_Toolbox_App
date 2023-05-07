import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:ninja_hex/ninja_hex.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:usb_serial/transaction.dart';
import 'package:draggable_scrollbar/draggable_scrollbar.dart';

import 'constants.dart';
import 'utils.dart';

class WifiDeautherPage extends StatefulWidget {
  WifiDeautherPage({Key? key}) : super(key: key);

  @override
  _WifiDeautherPageState createState() => _WifiDeautherPageState();
}

class _WifiDeautherPageState extends State<WifiDeautherPage> {
  bool? deauthing;
  IconData iconData = Icons.wifi_tethering;
  ScrollController _scrollController = new ScrollController();

  List<Uint8List> rawPacketsList = [];

  List<String> outputMacsList = macsList;
  List<String> outputSsidsList = ssidsList;
  List<String> outputTypesList = [""];

  String? ssidFieldValue;
  String? macFieldValue;
  String? channelFieldValue;
  String? typeFieldValue;
  bool eviltwinCheck = false;
  String reasonFieldValue = "Unspecified reason";
  int? delayFieldValue = 1000;

  @override
  void initState() {
    super.initState();
    packetsList = [];
    outputList = [];
    deauthing = false;
    channelFieldValue = channel;
    usbListener();
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

  int indexOfStr(Uint8List haystack, String needle, [int start = 0]) {
    if (needle.length == 0) return start;
    var first = needle.codeUnitAt(0);
    var end = haystack.length - needle.length;
    for (var i = start; i <= end; i++) {
      match:
      if (haystack[i] == first) {
        for (var j = 1; j < needle.length; j++) {
          if (haystack[i + j] != needle.codeUnitAt(j)) break match;
        }
        return i;
      }
    }
    return -1;
  }

  void parsePacket(Uint8List data) {
    if (data.length > 12) {
      int pktLen = data[12];
      if (data.length < 16 + pktLen) {
        return;
      }
      Uint8List rawPacket = data.sublist(16);
      String typeStr = pktsTypes[rawPacket[0] & 0xfc]!; // clear 2 first bits
      int toDS =
          (rawPacket[1] & 0x3) >> 0x1; // get the first of the 2 first bits
      int fromDS =
          (rawPacket[1] & 0x3) & 0x1; // get the last of the 2 first bits

      String mac1Mean = "";
      String mac2Mean = "";
      String mac3Mean = "";
      if (toDS == 0 && fromDS == 0) {
        mac1Mean = "RA=DA";
        mac2Mean = "TA=SA";
        mac3Mean = "BSSID";
      } else if (toDS == 0 && fromDS == 1) {
        mac1Mean = "RA=DA";
        mac2Mean = "TA=BSSID";
        mac3Mean = "SA";
      } else if (toDS == 1 && fromDS == 0) {
        mac1Mean = "RA=SSID";
        mac2Mean = "TA=SA";
        mac3Mean = "DA";
      } else if (toDS == 1 && fromDS == 1) {
        mac1Mean = "RA";
        mac2Mean = "TA";
        mac3Mean = "DA";
      }
      String mac1 = "";
      String mac2 = "";
      String mac3 = "";
      if (rawPacket.length > 24) {
        mac1 = uint8listToMacString(rawPacket.sublist(4, 10));
        if (!outputMacsList.contains(mac1)) {
          outputMacsList.add(mac1);
        }
        mac2 = uint8listToMacString(rawPacket.sublist(10, 16));
        if (!outputMacsList.contains(mac2)) {
          outputMacsList.add(mac2);
        }
        mac3 = uint8listToMacString(rawPacket.sublist(16, 24));
        if (!outputMacsList.contains(mac3)) {
          outputMacsList.add(mac3);
        }
      }
      String ssid = "None";
      String channel = "None";
      if (((typeStr == "Mgmt-Beacon") || (typeStr == "Mgmt-Probe Response")) &&
          rawPacket.length > 37 &&
          rawPacket[36] == 0 &&
          rawPacket.length >= 38 + rawPacket[37]) {
        Uint8List uSsid = rawPacket.sublist(38, 38 + rawPacket[37]);
        ssid = String.fromCharCodes(uSsid);
        if (rawPacket.length >= 66) {
          channel = rawPacket[65].toString();
        }
      } else if (typeStr == "Data-QoS Data") {
        int i = indexOfStr(rawPacket, "POST");
        if (i != -1) {
          typeStr = "EvilPass";
        }
      }
      if (!outputTypesList.contains(typeStr)) {
        outputTypesList.add(typeStr);
      }
      Map<String, String> pkt = {};
      pkt["SSID"] = "SSID: $ssid";
      pkt["TYPE"] = "TYPE: $typeStr";
      pkt["MAC1"] = "$mac1Mean: $mac1";
      pkt["MAC2"] = "$mac2Mean: $mac2";
      pkt["MAC3"] = "$mac3Mean: $mac3";
      pkt["CHANNEL"] = "CHAN: $channel";
      pkt["PKT"] = hexView(0, data, printAscii: true);
      // 0 crashes... Issue opened : https://github.com/ninja-dart/hex/issues/1
      // used modified version from https://github.com/EParisot/hex

      packetsList.add(pkt);
    }
  }

  Transaction<Uint8List>? pcapTransaction;
  Future<void> startDeauther() async {
    if (deauthing!) {
      // Stop Deauther
      pcapTransaction!.dispose();
      Transaction<String> transaction = Transaction.stringTerminated(
          usbPort!.inputStream!, Uint8List.fromList([13, 10]));
      await transaction.transaction(
          usbPort!,
          Uint8List.fromList(("stop").codeUnits + [13, 10]),
          Duration(seconds: 1));
      transaction.dispose();
      print("deauther stopped");
      if (mounted) {
        setState(() {
          iconData = Icons.wifi_tethering;
          deauthing = false;
        });
      }
      if (deauthing == false && packetsList.length == 0) {
        for (Uint8List pkt in rawPacketsList) {
          parsePacket(pkt);
        }
      }
      setState(() {
        outputList = packetsList;
      });
      rawPacketsList.clear();
    } else {
      usbPort!.close();
      await connectSerial(device!);
      // Start Sniffer
      setState(() {
        packetsList.clear();
        outputList.clear();
        outputTypesList = [""];
      });
      file = await localFile("Wifi_deauther", 'pcap');
      if (file != null) {
        if (currSSID.length == 0) {
          // Configure ESP deauther
          Transaction<String> transaction = Transaction.stringTerminated(
              usbPort!.inputStream!, Uint8List.fromList([13, 10]));
          var response = await transaction.transaction(
              usbPort!,
              Uint8List.fromList(
                  ("set country " + country!).codeUnits + [13, 10]),
              Duration(seconds: 1));
          print("received = $response");
          response = await transaction.transaction(
              usbPort!,
              Uint8List.fromList(
                  ("set channel " + channelFieldValue!).codeUnits + [13, 10]),
              Duration(seconds: 1));
          print("received = $response");
          transaction.dispose();
        }
        // Listen packets from serial and save
        pcapTransaction = Transaction.terminated(
            usbPort!.inputStream!, Uint8List.fromList("<STOP>".codeUnits));
        pcapTransaction!.stream.listen((Uint8List data) {
          file!.writeAsBytesSync(data, mode: FileMode.append, flush: true);
          rawPacketsList.add(data);
        });
        String apMac = networksMap[ssidFieldValue]["BSSID"];
        int reasonFieldIndex = reasonsList.indexOf(reasonFieldValue);
        String ssidCleanedValue = ssidFieldValue!.replaceAll(RegExp(' +'), '_');
        if (eviltwinCheck == false)
          await usbPort!.write(Uint8List.fromList(
              ("wifi_deauth $macFieldValue $apMac None ${delayFieldValue.toString()} ${reasonFieldIndex.toString()}")
                      .codeUnits +
                  [13, 10]));
        else
          await usbPort!.write(Uint8List.fromList(
              ("wifi_deauth $macFieldValue $apMac $ssidCleanedValue ${delayFieldValue.toString()} ${reasonFieldIndex.toString()}")
                      .codeUnits +
                  [13, 10]));
        if (mounted) {
          setState(() {
            iconData = Icons.portable_wifi_off;
            deauthing = true;
          });
        }
      }
    }
  }

  void execFilters() {
    setState(() {
      outputList = List.of(packetsList);
      if (ssidFieldValue != null &&
          ssidFieldValue != "None" &&
          ssidFieldValue != "") {
        outputList = outputList
            .where((pkt) => pkt["SSID"]!.contains(ssidFieldValue!))
            .toList();
      }
      if (macFieldValue != null &&
          macFieldValue != "None" &&
          macFieldValue != "") {
        outputList = outputList
            .where((pkt) =>
                pkt["MAC1"]!.contains(macFieldValue!) ||
                pkt["MAC2"]!.contains(macFieldValue!) ||
                pkt["MAC3"]!.contains(macFieldValue!))
            .toList();
      }
      if (typeFieldValue != null &&
          typeFieldValue != "None" &&
          typeFieldValue != "") {
        outputList = outputList
            .where((pkt) => pkt["TYPE"]!.contains(typeFieldValue!))
            .toList();
      }
    });
  }

  Widget buildOutputList() {
    return DraggableScrollbar.semicircle(
        controller: _scrollController,
        child: ListView.builder(
          controller: _scrollController,
          itemBuilder: (context, index) {
            return Container(
              padding: EdgeInsets.all(8.0),
              child: Material(
                elevation: 4.0,
                borderRadius: BorderRadius.circular(4.0),
                child: Center(
                    child: ExpansionTile(
                  title: Text(
                    "${outputList[index]["SSID"]} - ${outputList[index]["CHANNEL"]}\n${outputList[index]["TYPE"]}",
                    style: TextStyle(fontSize: 18.0),
                  ),
                  subtitle: Text(
                    "${outputList[index]["MAC1"]}\n${outputList[index]["MAC2"]}\n${outputList[index]["MAC3"]}",
                    style: TextStyle(fontSize: 16.0),
                    textAlign: TextAlign.right,
                  ),
                  children: [
                    FittedBox(
                      fit: BoxFit.fitWidth,
                      child: Text(outputList[index]["PKT"]!,
                          style: TextStyle(fontFeatures: [
                            FontFeature.tabularFigures(),
                          ])),
                    )
                  ],
                )),
              ),
            );
          },
          itemCount: outputList.length,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Deauther'),
        actions: <Widget>[
          IconButton(
            icon: Icon(iconData, size: 30.0),
            onPressed: (deviceConnected &&
                    macFieldValue != null &&
                    macFieldValue != "" &&
                    ssidFieldValue != null &&
                    ssidFieldValue != "" &&
                    ssidFieldValue != "None" &&
                    networksMap.containsKey(ssidFieldValue))
                ? startDeauther
                : null,
          )
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                Expanded(
                    flex: 5,
                    child: DropdownButton<String>(
                        isExpanded: true,
                        value: ssidFieldValue,
                        hint: Text("SSID",
                            style: TextStyle(
                              fontSize: 25,
                            )),
                        items: outputSsidsList.map((String value) {
                          return new DropdownMenuItem<String>(
                            value: value,
                            child: Text(value, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (deauthing!)
                            ? null
                            : (dynamic newValue) {
                                setState(() {
                                  ssidFieldValue =
                                      (newValue.length > 0) ? newValue : null;
                                  if (ssidFieldValue != null &&
                                      ssidFieldValue != "" &&
                                      ssidFieldValue != "None") {
                                    outputMacsList = [""];
                                    for (String key in networksMap.keys) {
                                      if (key == ssidFieldValue) {
                                        for (String sta
                                            in networksMap[key]["STAs"].keys) {
                                          if (!outputMacsList.contains(sta)) {
                                            outputMacsList.add(sta);
                                          }
                                        }
                                      }
                                    }
                                    if (!outputMacsList
                                        .contains("ff:ff:ff:ff:ff:ff")) {
                                      outputMacsList.add("ff:ff:ff:ff:ff:ff");
                                    }
                                  } else {
                                    outputMacsList = macsList;
                                  }
                                });
                                execFilters();
                              })),
                Expanded(
                    flex: 5,
                    child: DropdownButton(
                        value: macFieldValue,
                        hint: Text("MAC",
                            style: TextStyle(
                              fontSize: 25,
                            )),
                        items: outputMacsList.map((String value) {
                          return new DropdownMenuItem<String>(
                            value: value,
                            child: new Text(value),
                          );
                        }).toList(),
                        onChanged: (deauthing!)
                            ? null
                            : (dynamic newValue) {
                                setState(() {
                                  macFieldValue =
                                      (newValue.length > 0) ? newValue : null;
                                  if (macFieldValue != null &&
                                      macFieldValue != "" &&
                                      macFieldValue != "None") {
                                    outputSsidsList = [""];
                                    if (macFieldValue!.toLowerCase() ==
                                            "ff:ff:ff:ff:ff:ff" ||
                                        macFieldValue!.toLowerCase() ==
                                            "ff-ff-ff-ff-ff-ff") {
                                      outputSsidsList = ssidsList;
                                    } else {
                                      for (String key in networksMap.keys) {
                                        for (String sta
                                            in networksMap[key]["STAs"].keys) {
                                          if (sta.toLowerCase() ==
                                                  macFieldValue!
                                                      .toLowerCase() &&
                                              !outputSsidsList.contains(key)) {
                                            outputSsidsList.add(key);
                                            break;
                                          }
                                        }
                                      }
                                    }
                                  } else {
                                    outputSsidsList = ssidsList;
                                  }
                                });
                                execFilters();
                              })),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                    flex: 5,
                    child: DropdownButton<String>(
                        isExpanded: true,
                        value: typeFieldValue,
                        hint: Text("PKT TYPE",
                            style: TextStyle(
                              fontSize: 25,
                            )),
                        items: outputTypesList.map((String value) {
                          return new DropdownMenuItem<String>(
                            value: value,
                            child: new Text(value,
                                overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (deauthing!)
                            ? null
                            : (dynamic newValue) {
                                setState(() {
                                  typeFieldValue =
                                      (newValue.length > 0) ? newValue : null;
                                });
                                execFilters();
                              })),
                Expanded(
                    flex: 5,
                    child: Row(children: [
                      Padding(
                          padding: const EdgeInsets.only(left: 20.0),
                          child: Text("CHAN: ",
                              style: TextStyle(
                                  fontSize: 25, color: Colors.grey[700]))),
                      DropdownButton<String>(
                        value: channelFieldValue,
                        onChanged: (deauthing!)
                            ? null
                            : (String? newValue) {
                                setState(() {
                                  channelFieldValue = newValue;
                                });
                              },
                        items: channelsList
                            .map<DropdownMenuItem<String>>((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value, style: TextStyle(fontSize: 25)),
                          );
                        }).toList(),
                      )
                    ])),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                    flex: 5,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("REASON: ",
                              textAlign: TextAlign.left,
                              style: TextStyle(
                                  fontSize: 25, color: Colors.grey[700])),
                          DropdownButton<String>(
                              isExpanded: true,
                              value: reasonFieldValue,
                              items: reasonsList.map<DropdownMenuItem<String>>(
                                  (String value) {
                                return new DropdownMenuItem<String>(
                                    value: value,
                                    child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(children: [
                                          Text(value,
                                              overflow: TextOverflow.ellipsis),
                                        ])));
                              }).toList(),
                              onChanged: (deauthing!)
                                  ? null
                                  : (dynamic newValue) {
                                      setState(() {
                                        reasonFieldValue = (newValue.length > 0)
                                            ? newValue
                                            : null;
                                      });
                                    })
                        ])),
                Expanded(
                    flex: 3,
                    child: Column(children: [
                      Padding(
                          padding: const EdgeInsets.only(left: 20.0),
                          child: Text("DELAY: ",
                              style: TextStyle(
                                  fontSize: 20, color: Colors.grey[700]))),
                      DropdownButton<int>(
                        value: delayFieldValue,
                        onChanged: (deauthing!)
                            ? null
                            : (int? newValue) {
                                setState(() {
                                  delayFieldValue = newValue;
                                });
                              },
                        items:
                            delaysList.map<DropdownMenuItem<int>>((int value) {
                          return DropdownMenuItem<int>(
                            value: value,
                            child: Text(value.toString(),
                                style: TextStyle(fontSize: 25)),
                          );
                        }).toList(),
                      ),
                      Padding(
                          padding: const EdgeInsets.only(left: 20.0),
                          child: Text("ms",
                              style: TextStyle(
                                  fontSize: 20, color: Colors.grey[700]))),
                    ])),
                Expanded(
                  flex: 2,
                  child: Column(children: [
                    Text("EvilTwin",
                        style:
                            TextStyle(fontSize: 20, color: Colors.grey[700])),
                    CheckboxListTile(
                      value: eviltwinCheck,
                      onChanged: (bool? newValue) {
                        setState(() {
                          eviltwinCheck = newValue!;
                        });
                      },
                    )
                  ]),
                )
              ],
            ),
            (deauthing!)
                ? CircularProgressIndicator()
                : Expanded(
                    child:
                        (outputList.isNotEmpty) ? buildOutputList() : Text("")),
          ],
        ),
      ),
    );
  }
}
