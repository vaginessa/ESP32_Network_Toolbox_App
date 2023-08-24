import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:usb_serial/transaction.dart';
import 'package:usb_serial/usb_serial.dart';

import 'constants.dart';

class TerminalPage extends StatefulWidget {
  TerminalPage({Key? key}) : super(key: key);

  @override
  _TerminalPageState createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  String output = "";
  TextEditingController? _controller;
  var subscription;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Terminal"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            Text(
              'Usefull commands are: "test", "version"',
            ),
            Row(children: [
              Text("\$: "),
              Expanded(
                  child: TextField(
                      enabled: deviceConnected,
                      controller: _controller,
                      onSubmitted: (String value) async {
                        if (subscription == null) {
                          Transaction<String> transaction =
                              Transaction.stringTerminated(
                                  usbPort!.inputStream!,
                                  Uint8List.fromList([13, 10]));
                          subscription =
                              transaction.stream.listen((String data) {
                            setState(() {
                              output += data + "\r\n";
                              _scrollController.animateTo(
                                  _scrollController.position.maxScrollExtent,
                                  duration: const Duration(milliseconds: 500),
                                  curve: Curves.easeOut);
                            });
                          });
                        }
                        usbPort!.write(
                            Uint8List.fromList(value.codeUnits + [13, 10]));
                      })),
            ]),
            Expanded(
                child: SingleChildScrollView(
              child: Text(output),
              controller: _scrollController,
            )),
          ],
        ),
      ),
    );
  }
}
