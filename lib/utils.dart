import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:io';

import 'package:ext_storage/ext_storage.dart';
import 'package:path/path.dart' as Path;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:date_format/date_format.dart';

import 'constants.dart';

Future<File> localFile(String name) async {
  await createDir();
  if (fileDir.existsSync()) {
    var now = new DateTime.now();
    String formattedDate =
        formatDate(now, [yyyy, '_', MM, '_', dd, '_', HH, '_', nn, '_', ss]);
    String filePath = '${fileDir.path}/${name}_$formattedDate.pcap';
    file = File(filePath);
    if (!file.existsSync()) {
      file.create();
    }
    return file;
  } else {
    return null;
  }
}

_makeToast(msg) {
  FlutterToast.showToast(
      msg: msg,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 3,
      backgroundColor: Colors.white,
      textColor: Colors.black,
      fontSize: 16.0);
}

createDir() async {
  if (await Permission.storage.request().isGranted) {
    String baseDir = await ExtStorage
        .getExternalStorageDirectory(); //works for both iOS and Android
    String dirToBeCreated = "ESP32_Network_Toolbox";
    String finalDir = Path.join(baseDir, dirToBeCreated);
    fileDir = Directory(finalDir);
    bool dirExists = await fileDir.exists();
    if (!dirExists) {
      fileDir.create();
    }
  } else {
    _makeToast("Can't access to directory...");
  }
}

String uint8listToMacString(Uint8List lst) {
  return "${lst[0].toRadixString(16).padLeft(2, '0')}:${lst[1].toRadixString(16).padLeft(2, '0')}:${lst[2].toRadixString(16).padLeft(2, '0')}:${lst[3].toRadixString(16).padLeft(2, '0')}:${lst[4].toRadixString(16).padLeft(2, '0')}:${lst[5].toRadixString(16).padLeft(2, '0')}";
}
