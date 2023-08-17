import 'package:flutter/material.dart';
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

  ScrollController _scrollController = new ScrollController();

  @override
  void initState() {
    super.initState();
    usbListener();
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
            Text(
              "Start flash mode by pressing reset button on device.",
              style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500),
            ),
            (deviceConnected)
                ? TextButton.icon(
                    label: Text(
                      'Flash',
                      style: TextStyle(fontSize: 25, color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                    icon: Icon(
                      Icons.offline_bolt,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      // TODO check device is in reset mode
                      // FLASH
                    },
                  )
                : TextButton.icon(
                    label: Text(
                      'Flash',
                      style: TextStyle(fontSize: 25),
                      textAlign: TextAlign.center,
                    ),
                    icon: Icon(
                      Icons.offline_bolt,
                      color: Colors.grey,
                    ),
                    onPressed: () {},
                  ),
            Expanded(
                child: SingleChildScrollView(
              child: (Text(output)),
              controller: _scrollController,
            )),
          ],
        ),
      ),
    );
  }
}
