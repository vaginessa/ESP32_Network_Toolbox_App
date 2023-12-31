import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:io';

import 'package:path/path.dart' as Path;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:date_format/date_format.dart';

import 'constants.dart';

Future<File?> localFile(String name, String ext) async {
  var res = await createDir();
  if (res == false) {
    makeToast("Folder does not exists");
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
      makeToast("file not created");
      return null;
    }
    return file;
  } else {
    makeToast("Folder does not exists");
    return null;
  }
}

void makeToast(msg) {
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
  if (await Permission.storage.request().isGranted) {
    Directory? baseDir = Directory("/storage/emulated/0/Documents/");
    String dirToBeCreated = "ESP32_Network_Toolbox";
    String finalDirStr = Path.join(baseDir.path, dirToBeCreated);
    fileDir = Directory(finalDirStr);
    if (!await Directory(finalDirStr).exists()) {
      makeToast("Data directory doesn't exists, creating it...");
      await fileDir!.create();
    }
  } else {
    debugPrint("Can't access to directory...");
    makeToast("Can't access to directory...");
    return false;
  }
  return true;
}

String uint8listToMacString(Uint8List lst) {
  return "${lst[0].toRadixString(16).padLeft(2, '0')}:${lst[1].toRadixString(16).padLeft(2, '0')}:${lst[2].toRadixString(16).padLeft(2, '0')}:${lst[3].toRadixString(16).padLeft(2, '0')}:${lst[4].toRadixString(16).padLeft(2, '0')}:${lst[5].toRadixString(16).padLeft(2, '0')}";
}

void mapNetworks(Map<String, String> pkt) {
  String type = pkt["TYPE"]!.split(": ")[1];
  String ssid = pkt["SSID"]!.split(": ")[1];
  String dstMac = pkt["MAC1"]!.split(": ")[1];
  String srcMac = pkt["MAC2"]!.split(": ")[1];
  String chan = pkt["CHANNEL"]!.split(": ")[1];
  if (type == "Mgmt-Beacon") {
    if (!networksMap.containsKey(ssid)) {
      networksMap[ssid] = {
        "BSSID": srcMac,
        "VENDOR": "",
        "CHANNEL": chan,
        "STAs": {"ff:ff:ff:ff:ff:ff": "None"}
      };
    } else if (!networksMap[ssid]["STAs"].containsKey("ff:ff:ff:ff:ff:ff")) {
      networksMap[ssid]["STAs"]["ff:ff:ff:ff:ff:ff"] = "None";
    }
  } else if (type == "Mgmt-Probe Response") {
    if (!networksMap.containsKey(ssid)) {
      networksMap[ssid] = {
        "BSSID": srcMac,
        "VENDOR": "",
        "CHANNEL": chan,
        "STAs": {dstMac: ""}
      };
    } else if (!networksMap[ssid]["STAs"].containsKey(dstMac)) {
      networksMap[ssid]["STAs"][dstMac] = "";
    }
  } else if (type == "Data-QoS Data" ||
      type == "Data-QoS Null(no data)" ||
      type == "Data-Null(No data)") {
    for (String key in networksMap.keys) {
      if (networksMap[key]["BSSID"] == dstMac) {
        bool check = false;
        for (String sta in networksMap[key]["STAs"].keys) {
          if (sta == srcMac) {
            check = true;
            break;
          }
        }
        if (check == false) {
          networksMap[key]["STAs"][srcMac] = "";
          break;
        }
      }
    }
  }
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
