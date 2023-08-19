import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:typed_data';
import 'package:usb_serial/transaction.dart';
import 'package:usb_serial/usb_serial.dart';

import 'constants.dart';

class FlashPage extends StatefulWidget {
  FlashPage({Key? key}) : super(key: key);

  @override
  _FlashPageState createState() => _FlashPageState();
}

class _FlashPageState extends State<FlashPage> {
  String output = "";
  var subscription;
  bool otaStarted = false;
  bool pktOK = false;
  int otaBufSize = 4096;
  TextEditingController? _controller;

  ScrollController _scrollController = new ScrollController();

  @override
  void initState() {
    super.initState();
    usbListener();
  }

  void dispose() {
    super.dispose();
    if (_controller != null) {
      _controller!.dispose();
    }
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

  void printScreen(String txt) {
    setState(() {
      output += txt;
      _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 50,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Flash ESP32"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            Expanded(
                child: SingleChildScrollView(
              child: (Text(output)),
              controller: _scrollController,
            )),
            TextButton.icon(
              label: Text(
                'Flash',
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
                  ? () async {
                      // setup uart in subscription
                      if (subscription == null) {
                        Transaction<String> transaction =
                            Transaction.stringTerminated(usbPort!.inputStream!,
                                Uint8List.fromList([13, 10])); // \r\n
                        subscription = transaction.stream.listen((String data) {
                          // filter and print incoming data
                          if (data == "esp_ota_begin succeeded ") {
                            otaStarted = true;
                          } else if (data == "OK" ||
                              data == "OTA Update has Ended ") {
                            pktOK = true;
                          } else {
                            printScreen(data + "\r\n");
                          }
                        });
                      }
                      printScreen("Starting Flash procedure\r\n");
                      // TMP read file from assets
                      var bytes = await rootBundle
                          .load('assets/esp32_network_toolbox.bin');
                      int size = bytes.buffer.lengthInBytes;
                      printScreen("Firmware size: $size\r\n");
                      // send command with size
                      await usbPort!.write(Uint8List.fromList(
                          ("ota_flash $size\r\n").codeUnits));
                      printScreen("Command sent\r\n");
                      // wait device ready
                      while (otaStarted == false) {
                        await Future.delayed(
                            const Duration(milliseconds: 200), () {});
                      }
                      printScreen("Sending data\r\n");
                      // BIN to USB
                      for (int i = 0; i < size; i += otaBufSize) {
                        // final case
                        if (i + otaBufSize > size) {
                          await usbPort!
                              .write(bytes.buffer.asUint8List().sublist(i));
                          break;
                        }
                        // send
                        await usbPort!.write(bytes.buffer
                            .asUint8List()
                            .sublist(i, i + otaBufSize));
                        // wait confirm
                        while (pktOK == false) {
                          await Future.delayed(
                              const Duration(milliseconds: 200), () {});
                        }
                        pktOK = false;
                      }
                    }
                  : () {
                      printScreen("Disconnected device\r\n");
                    },
            )
          ],
        ),
      ),
    );
  }
}
