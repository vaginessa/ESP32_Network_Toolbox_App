import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as Path;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:date_format/date_format.dart';

import 'constants.dart';

Future<File?> localFile(String name, String ext) async {
  var res = await createDir();
  if (res == false) {
    return null;
  }
  if (fileDir!.existsSync()) {
    var now = new DateTime.now();
    String formattedDate =
        formatDate(now, [yyyy, '_', MM, '_', dd, '_', HH, '_', nn, '_', ss]);
    String filePath = '${fileDir!.path}/${name}_$formattedDate.$ext';
    file = File(filePath);
    if (!file!.existsSync()) {
      file!.create();
    } else {
      return null;
    }
    return file;
  } else {
    return null;
  }
}

_makeToast(msg) {
  Fluttertoast.showToast(
      msg: msg,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 3,
      backgroundColor: Colors.white,
      textColor: Colors.black,
      fontSize: 16.0);
}

createDir() async {
  if (await Permission.manageExternalStorage.request().isGranted) {
    Directory? baseDir = await getExternalStorageDirectory();
    baseDir = baseDir!.parent.parent.parent.parent;
    String dirToBeCreated = "ESP32_Network_Toolbox";
    String finalDirStr = Path.join(baseDir.path, dirToBeCreated);
    fileDir = Directory(finalDirStr);
    if (!await Directory(finalDirStr).exists()) {
      _makeToast("Data directory doesn't exists, creating it...");
      fileDir!.create();
    }
  } else {
    debugPrint("Can't access to Images directory...");
    _makeToast("Can't access to directory...");
    return false;
  }
  return true;
}

String uint8listToMacString(Uint8List lst) {
  return "${lst[0].toRadixString(16).padLeft(2, '0')}:${lst[1].toRadixString(16).padLeft(2, '0')}:${lst[2].toRadixString(16).padLeft(2, '0')}:${lst[3].toRadixString(16).padLeft(2, '0')}:${lst[4].toRadixString(16).padLeft(2, '0')}:${lst[5].toRadixString(16).padLeft(2, '0')}";
}
