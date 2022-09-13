import 'dart:io';

import 'package:usb_serial/usb_serial.dart';
import 'package:country_code/country_code.dart';

String appName = "ESP32 Network ToolBox";
const int BAUD_RATE = 115200;

const int scanDelay = 10;

Directory? fileDir;
File? file;

UsbPort? usbPort;
List<UsbDevice> devicesList = [];
UsbDevice? device;
bool deviceConnected = false;
String currSSID = "";
List<Map<String, dynamic>> bltDevicesList = [];

List<Map<String, String>> packetsList = [];
List<Map<String, String>> outputList = [];

List<String> ssidsList = [""];
List<String> macsList = [""];
List<String> typesList = [""];

String? channel;
String? country;

Map<String, dynamic> networksMap = {};

List<String> countriesList =
    CountryCode.values.map<String>((c) => c.alpha2).toList();

List<String> channelsList = [
  "ALL",
  "1",
  "2",
  "3",
  "4",
  "5",
  "6",
  "7",
  "8",
  "9",
  "10",
  "11",
  "12",
  "13",
  "14"
];

Map<int, String> pktsTypes = {
  0x0: "Mgmt-Association Request", // 00000000
  0x10: "Mgmt-Association Response", // 00010000
  0x20: "Mgmt-Reassociation Request", // 00100000
  0x30: "Mgmt-Reassociation Response", // 00110000
  0x40: "Mgmt-Probe Request", // 01000000
  0x50: "Mgmt-Probe Response", // 01010000
  0x60: "Mgmt-Timing Advertisement", // 01100000
  0x70: "Mgmt-Reserved", // 01110000
  0x80: "Mgmt-Beacon", // 10000000
  0x90: "Mgmt-ATIM", // 10010000
  0xa0: "Mgmt-Disassociation", // 10100000
  0xb0: "Mgmt-Authentication", // 10110000
  0xc0: "Mgmt-Deauthentication", // 11000000
  0xd0: "Mgmt-Action", // 11010000
  0xe0: "Mgmt-Action No Ack (NACK)", // 11100000
  0x4: "Ctrl-Reserved", // 00000100
  0x14: "Ctrl-Reserved", // 00010100
  0x24: "Ctrl-Trigger", // 00100100
  0x34: "Ctrl-TACK", // 00110100
  0x44: "Ctrl-Beamforming Report Poll", // 01000100
  0x54: "Ctrl-VHT/HE NDP Announcement", // 01010100
  0x64: "Ctrl-Control Frame Extension", // 01100100
  0x74: "Ctrl-Control Wrapper", // 01110100
  0x84: "Ctrl-Block Ack Request (BAR)", // 10000100
  0x94: "Ctrl-Block Ack (BA)", // 10010100
  0xa4: "Ctrl-PS-Poll", // 10100100
  0xb4: "Ctrl-RTS", // 10110100
  0xc4: "Ctrl-CTS", // 11000100
  0xd4: "Ctrl-ACK", // 11010100
  0xe4: "Ctrl-CF-End", // 11100100
  0xf4: "Ctrl-CF-End + CF-ACK", // 11110100
  0x8: "Data-Data", // 00001000
  0x18: "Data-Data + CF-ACK", // 00011000
  0x28: "Data-Data + CF-Poll", // 00101000
  0x38: "Data-Data + CF-ACK + CF-Poll", // 00111000
  0x48: "Data-Null (no data)", // 01001000
  0x58: "Data-CF-ACK (no data)", // 01011000
  0x68: "Data-CF-Poll (no data)", // 01101000
  0x78: "Data-CF-ACK + CF-Poll (no data)", // 01111000
  0x88: "Data-QoS Data", // 10001000
  0x98: "Data-QoS Data + CF-ACK", // 10011000
  0xa8: "Data-QoS Data + CF-Poll", // 10101000
  0xb8: "Data-QoS Data + CF-ACK + CF-Poll", // 10111000
  0xc8: "Data-QoS Null (no data)", // 11001000
  0xd8: "Data-Reserved", // 11011000
  0xe8: "Data-QoS CF-Poll (no data)", // 11101000
  0xf8: "Data-QoS CF-ACK + CF-Poll (no data)", // 11111000
  0xc: "Ext-DMG Beacon", // 00001100
  0x1c: "Ext-S1G Beacon", // 00011100
  0x2c: "Ext-Reserved", // 00101100
  0xfc: "Ext-Reserved", // 11111100
};
