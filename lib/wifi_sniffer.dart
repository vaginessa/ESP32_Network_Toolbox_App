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

class WifiSnifferPage extends StatefulWidget {
  WifiSnifferPage({Key? key}) : super(key: key);

  @override
  _WifiSnifferPageState createState() => _WifiSnifferPageState();
}

class _WifiSnifferPageState extends State<WifiSnifferPage> {
  bool? sniffing;
  IconData iconData = Icons.wifi_tethering;
  ScrollController _scrollController = new ScrollController();

  List<Uint8List> rawPacketsList = [];

  Map<String, String?> filtersList = {
    "SSID": "",
    "MAC": "",
    "TYPE": "",
    "CHANNEL": ""
  };

  List<String> outputMacsList = macsList;
  List<String> outputSsidsList = ssidsList;
  List<String> outputTypesList = typesList;

  String? macFieldValue;
  String? ssidFieldValue;
  String? typeFieldValue;
  String? channelFieldValue;

  @override
  void initState() {
    super.initState();
    sniffing = false;
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
        if (!macsList.contains(mac1)) {
          macsList.add(mac1);
          outputMacsList.add(mac1);
        }
        mac2 = uint8listToMacString(rawPacket.sublist(10, 16));
        if (!macsList.contains(mac2)) {
          macsList.add(mac2);
          outputMacsList.add(mac2);
        }
        mac3 = uint8listToMacString(rawPacket.sublist(16, 24));
        if (!macsList.contains(mac3)) {
          macsList.add(mac3);
          outputMacsList.add(mac3);
        }
      }
      String ssid = "None";
      String channel = "None";
      if (((typeStr == "Mgmt-Beacon") || (typeStr == "Mgmt-Probe Response")) &&
          pktLen > 37 &&
          rawPacket[36] == 0 &&
          pktLen >= 38 + rawPacket[37]) {
        Uint8List uSsid = rawPacket.sublist(38, 38 + rawPacket[37]);
        ssid = String.fromCharCodes(uSsid);
        // get channel
        int chanPos = 38 + rawPacket[37];
        if (rawPacket[chanPos] == 0x01) {
          int supportedRatesLen = rawPacket[chanPos + 1];
          chanPos = chanPos + supportedRatesLen + 2;
        }
        if (rawPacket[chanPos] == 0x32) {
          int extendedSupportedRatesLen = rawPacket[chanPos + 1];
          chanPos = chanPos + extendedSupportedRatesLen + 2;
        }
        if (rawPacket.length >= chanPos + 2 &&
            rawPacket[chanPos] == 0x03 &&
            rawPacket[chanPos + 1] == 0x01) {
          channel = rawPacket[chanPos + 2].toString();
        }
      } else if (typeStr == "Data-QoS Data") {
        if (indexOfStr(rawPacket, "POST") != -1) {
          typeStr = "Data-QoS Data POST";
        } else if (indexOfStr(rawPacket, "GET") != -1) {
          typeStr = "Data-QoS Data GET";
        } else if (rawPacket.length >= 33 &&
            rawPacket[32] == 0x88 &&
            rawPacket[33] == 0x8e) {
          typeStr = "Data-QoS Data KEY";
        }
      }
      if (!ssidsList.contains(ssid)) {
        ssidsList.add(ssid);
        outputSsidsList.add(ssid);
      }
      if (!typesList.contains(typeStr)) {
        typesList.add(typeStr);
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
      mapNetworks(pkt);
      packetsList.add(pkt);
    }
  }

  void execFilters() {
    if (sniffing == false && packetsList.length == 0) {
      for (Uint8List pkt in rawPacketsList) {
        parsePacket(pkt);
      }
    }
    if (mounted) {
      setState(() {
        outputList = packetsList;
        Map<String, String> ssidToRssid = {};
        for (String key in networksMap.keys) {
          ssidToRssid[key] = networksMap[key]["BSSID"];
        }
        for (String key in ["SSID", "MAC", "TYPE", "CHANNEL"]) {
          if (filtersList[key] != null) {
            outputList = outputList
                .where((pkt) =>
                    (key == "SSID" &&
                            ssidToRssid.keys.contains(filtersList[key]) &&
                            pkt["MAC1"]!.toLowerCase().contains(
                                ssidToRssid[filtersList[key]]!.toLowerCase()) ||
                        (ssidToRssid.keys.contains(filtersList[key]) &&
                            pkt["MAC2"]!.toLowerCase().contains(
                                ssidToRssid[filtersList[key]]!
                                    .toLowerCase())) ||
                        (ssidToRssid.keys.contains(filtersList[key]) &&
                            pkt["MAC3"]!.toLowerCase().contains(
                                ssidToRssid[filtersList[key]]!
                                    .toLowerCase()))) ||
                    pkt[(key == "MAC") ? "MAC1" : key]!
                        .toLowerCase()
                        .contains(filtersList[key]!.toLowerCase()) ||
                    pkt[(key == "MAC") ? "MAC2" : key]!
                        .toLowerCase()
                        .contains(filtersList[key]!.toLowerCase()) ||
                    pkt[(key == "MAC") ? "MAC3" : key]!
                        .toLowerCase()
                        .contains(filtersList[key]!.toLowerCase()))
                .toList();
          }
        }
      });
    }
  }

  Transaction<Uint8List>? pcapTransaction;
  Future<void> startSniffer() async {
    if (sniffing!) {
      // Stop Sniffer
      pcapTransaction!.dispose();
      Transaction<String> transaction = Transaction.stringTerminated(
          usbPort!.inputStream!, Uint8List.fromList([13, 10]));
      await transaction.transaction(
          usbPort!,
          Uint8List.fromList(("stop").codeUnits + [13, 10]),
          Duration(seconds: 1));
      transaction.dispose();
      if (mounted) {
        setState(() {
          iconData = Icons.wifi_tethering;
          sniffing = false;
        });
      }
      execFilters();
      rawPacketsList.clear();
    } else {
      usbPort!.close();
      await connectSerial(device!);
      // Start Sniffer
      setState(() {
        packetsList.clear();
        outputList.clear();
        ssidsList = [""];
        outputSsidsList = [""];
        ssidFieldValue = null;
        macsList = [""];
        outputMacsList = [""];
        macFieldValue = null;
        typesList = [""];
        outputTypesList = [""];
        typeFieldValue = null;
      });
      file = await localFile("Wifi_sniffer", "pcap");

      if (currSSID.length == 0) {
        // Configure ESP sniffer
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
      bool first = true;
      pcapTransaction = Transaction.terminated(
          usbPort!.inputStream!, Uint8List.fromList("<STOP>".codeUnits));
      pcapTransaction!.stream.listen((Uint8List data) {
        if (file != null) {
          file!.writeAsBytesSync(data, mode: FileMode.append, flush: true);
        } else {
          debugPrint("Error creating file\n");
        }
        if (first) {
          first = false;
        } else {
          rawPacketsList.add(data);
        }
      });
      await usbPort!
          .write(Uint8List.fromList(("wifi_sniff").codeUnits + [13, 10]));
      if (mounted) {
        setState(() {
          iconData = Icons.portable_wifi_off;
          sniffing = true;
        });
      }
    }
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
        title: Text('Sniffer'),
        actions: <Widget>[
          IconButton(
            icon: Icon(iconData, size: 30.0),
            onPressed: deviceConnected ? startSniffer : null,
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
                        hint: Text(
                          "SSID",
                          style: TextStyle(
                            fontSize: 25,
                          ),
                        ),
                        items: outputSsidsList.map((String value) {
                          return new DropdownMenuItem<String>(
                            value: value,
                            child: Text(value, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (sniffing!)
                            ? null
                            : (dynamic newValue) {
                                setState(() {
                                  ssidFieldValue =
                                      (newValue.length > 0) ? newValue : null;
                                  filtersList["SSID"] = ssidFieldValue;
                                  execFilters();
                                  if (ssidFieldValue != null) {
                                    outputMacsList = macsList
                                        .where((string) => outputList.any(
                                            (element) =>
                                                element["MAC1"]!
                                                    .toLowerCase()
                                                    .contains(
                                                        string.toLowerCase()) ||
                                                element["MAC2"]!
                                                    .toLowerCase()
                                                    .contains(
                                                        string.toLowerCase()) ||
                                                element["MAC3"]!
                                                    .toLowerCase()
                                                    .contains(
                                                        string.toLowerCase())))
                                        .toList();
                                    outputTypesList = typesList
                                        .where((string) => outputList.any(
                                            (element) => element["TYPE"]!
                                                .contains(string)))
                                        .toList();
                                  } else {
                                    outputMacsList = macsList;
                                    outputTypesList = typesList;
                                  }
                                });
                              })),
                Expanded(
                    flex: 5,
                    child: DropdownButton<String>(
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
                        onChanged: (sniffing!)
                            ? null
                            : (dynamic newValue) {
                                setState(() {
                                  ssidFieldValue = null;
                                  macFieldValue =
                                      (newValue.length > 0) ? newValue : null;
                                  filtersList["MAC"] = macFieldValue;
                                  execFilters();
                                  if (macFieldValue != null) {
                                    outputSsidsList = ssidsList
                                        .where((string) => outputList.any(
                                            (element) => element["SSID"]!
                                                .contains(string)))
                                        .toList();
                                    outputTypesList = typesList
                                        .where((string) => outputList.any(
                                            (element) => element["TYPE"]!
                                                .contains(string)))
                                        .toList();
                                  } else {
                                    outputSsidsList = ssidsList;
                                    outputTypesList = typesList;
                                  }
                                });
                              })),
              ],
            ),
            Row(
              children: [
                Expanded(
                  flex: 5,
                  child: DropdownButton<String>(
                      value: typeFieldValue,
                      hint: Text("PKT TYPE",
                          style: TextStyle(
                            fontSize: 25,
                          )),
                      items: outputTypesList.map((String value) {
                        return new DropdownMenuItem<String>(
                          value: value,
                          child: new Text(value,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: (value == "Data-QoS Data POST" ||
                                          value == "Data-QoS Data GET" ||
                                          value == "Data-QoS Data KEY")
                                      ? Colors.red
                                      : Colors.white)),
                        );
                      }).toList(),
                      onChanged: (sniffing!)
                          ? null
                          : (dynamic newValue) {
                              setState(() {
                                ssidFieldValue = null;
                                typeFieldValue =
                                    (newValue.length > 0) ? newValue : null;
                                filtersList["TYPE"] = typeFieldValue;
                                execFilters();
                                if (macFieldValue != null) {
                                  outputSsidsList = ssidsList
                                      .where((string) => outputList.any(
                                          (element) => element["SSID"]!
                                              .contains(string)))
                                      .toList();
                                  outputMacsList = macsList
                                      .where((string) => outputList.any(
                                          (element) =>
                                              element["MAC1"]!
                                                  .toLowerCase()
                                                  .contains(
                                                      string.toLowerCase()) ||
                                              element["MAC2"]!
                                                  .toLowerCase()
                                                  .contains(
                                                      string.toLowerCase()) ||
                                              element["MAC3"]!
                                                  .toLowerCase()
                                                  .contains(
                                                      string.toLowerCase())))
                                      .toList();
                                } else {
                                  outputSsidsList = ssidsList;
                                  outputMacsList = macsList;
                                }
                              });
                            }),
                ),
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
                        onChanged: (sniffing!)
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
            (sniffing!)
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
