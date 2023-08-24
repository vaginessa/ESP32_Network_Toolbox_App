import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:usb_serial/transaction.dart';
import 'package:usb_serial/usb_serial.dart';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:google_sign_in/google_sign_in.dart';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';

import 'package:internet_connection_checker/internet_connection_checker.dart';

import 'constants.dart';

void buyProduct(ProductDetails? product) {
  if (product != null) {
    debugPrint("Buying ${product.id}");
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
    InAppPurchase.instance.buyNonConsumable(purchaseParam: purchaseParam);
    // From here the purchase flow will be handled by the underlying store.
    // Updates will be delivered to the `InAppPurchase.instance.purchaseStream`.
  } else {
    showDialog(
      barrierDismissible: false,
      context: navigatorKey.currentContext!,
      builder: (BuildContext context) {
        return AlertDialog(
          content: const Text(
              "Error connecting to Store, \nPlease check your Internet Connexion."),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Ok'),
            ),
          ],
        );
      },
    );
  }
}

class OTAPage extends StatefulWidget {
  OTAPage({Key? key}) : super(key: key);

  @override
  _OTAPageState createState() => _OTAPageState();
}

// show BUY dialog
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class _OTAPageState extends State<OTAPage> {
  // ###########################  PURCHASE stuff ##############################

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;

  late StreamSubscription purchasesSubscription;
  late StreamSubscription<GoogleSignInAccount?> googleSignInSubscription;

  List<ProductDetails> _products = <ProductDetails>[];

  static const String _kUpgradeId = 'premium';
  static const List<String> _kProductIds = <String>[
    _kUpgradeId,
  ];

  FirebaseFunctions functions = FirebaseFunctions.instance;
  HttpsCallable findOrCreateUserFct =
      FirebaseFunctions.instance.httpsCallable('findOrCreateUser');
  HttpsCallable deliverProductFct =
      FirebaseFunctions.instance.httpsCallable('deliverProduct');
  HttpsCallable verifyPurchaseFct =
      FirebaseFunctions.instance.httpsCallable('verifyPurchase');

  // Auto-consume must be true on iOS.
  // To try without auto-consume on another platform, change `true` to `false` here.
  final bool _kAutoConsume = Platform.isIOS || true;

  Future<void> initStoreInfo() async {
    final bool isAvailable = await _inAppPurchase.isAvailable();
    if (!isAvailable) {
      setState(() {
        _products = <ProductDetails>[];
      });
      debugPrint("Store unavailable");
      return;
    }

    if (Platform.isIOS) {
      final InAppPurchaseStoreKitPlatformAddition iosPlatformAddition =
          _inAppPurchase
              .getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
      await iosPlatformAddition.setDelegate(ExamplePaymentQueueDelegate());
    }

    final ProductDetailsResponse productDetailResponse =
        await _inAppPurchase.queryProductDetails(_kProductIds.toSet());
    if (productDetailResponse.error != null) {
      setState(() {
        _products = productDetailResponse.productDetails;
      });
      String detail = productDetailResponse.error!.message.toString();
      debugPrint("Error productDetailResponse: $detail");
      return;
    }

    if (productDetailResponse.productDetails.isEmpty) {
      setState(() {
        _products = productDetailResponse.productDetails;
      });
      debugPrint("empty products");
      return;
    }

    setState(() {
      _products = productDetailResponse.productDetails;
    });
    debugPrint("products loaded");
  }

  Future<bool> waitNetwork() async {
    while (true) {
      int count = 0;
      while (count < 5) {
        bool result = await InternetConnectionChecker().hasConnection;
        if (result == true) {
          debugPrint("Network found");
          return true;
        } else {
          count++;
          await Future.delayed(const Duration(seconds: 1));
        }
      }
      if (count >= 5) {
        debugPrint("No network");
        return false;
      }
    }
  }

  void purchase_setup() async {
    // wait for connexion
    debugPrint("Waiting Network...");
    if (await waitNetwork()) {
      // Google SignIn stream
      if (Platform.isAndroid) {
        final GoogleSignIn googleSignIn = GoogleSignIn();
        GoogleSignInAccount? currentGoogleUser;
        googleSignInSubscription = googleSignIn.onCurrentUserChanged
            .listen((GoogleSignInAccount? account) {
          setState(() async {
            currentGoogleUser = account;
            if (currentGoogleUser != null) {
              await signInFirebaseFromGoogle(currentGoogleUser);
            }
          });
        });
        // actual signin
        GoogleSignInAccount? account;
        try {
          final GoogleSignIn googleSignIn = GoogleSignIn();
          account = await googleSignIn.signIn();
        } on PlatformException catch (e) {
          debugPrint("GoogleSignIn exception ${e.code}: ${e.message}");
        }
        if (account != null) {
          debugPrint("GoogleSignIn success");
          await signInFirebaseFromGoogle(account);
        } else {
          debugPrint("GoogleSignIn failed");
        }
      } else {
        // TODO Apple SignIn
      }
      // Purchases stream
      final Stream purchaseUpdated = InAppPurchase.instance.purchaseStream;
      purchasesSubscription = purchaseUpdated.listen((purchaseDetailsList) {
        _listenToPurchaseUpdated(purchaseDetailsList);
      }, onDone: () {
        purchasesSubscription.cancel();
      }, onError: (error) {
        // handle error here.
        debugPrint("Purchase Stream Error: ${error.toString()}");
      });

      await initStoreInfo();
    }
  }

  UserCredential? _firebaseCreds;
  late bool _userIsPremium = false;
  late String provider = "";

  // SignIn Google Firebase
  Future<void> signInFirebaseFromGoogle(GoogleSignInAccount? googleUser) async {
    debugPrint("Signin in Google");
    provider = "google";
    // Obtain the auth details from the request
    final GoogleSignInAuthentication? googleAuth =
        await googleUser?.authentication;

    // Create a new credential
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth?.accessToken,
      idToken: googleAuth?.idToken,
    );
    debugPrint("Signin in Firebase");
    try {
      _firebaseCreds =
          await FirebaseAuth.instance.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      debugPrint("FirebaseAuthException: ${e.code}: ${e.message}");
    }
    if (_firebaseCreds != null) {
      debugPrint("Signin in Firebase OK");
      await findOrCreateUser(_firebaseCreds!, provider);
    } else {
      debugPrint("Signin in Firebase Error");
    }
  }

  Future<void> findOrCreateUser(
      UserCredential firebaseCreds, String provider) async {
    debugPrint("findOrCreateUser");
    try {
      final resp = await findOrCreateUserFct.call(<String, dynamic>{
        "uid": "${firebaseCreds.user!.uid}",
        "email": firebaseCreds.user!.email
      });
      if (resp.data["error"] == false) {
        if (resp.data["is_premium"] == true) {
          _userIsPremium = true;
        } else {
          _userIsPremium = false;
        }
      } else {
        debugPrint("Error: ${resp.data["errorMsg"]}");
        _userIsPremium = false;
      }
    } on FirebaseFunctionsException catch (error) {
      debugPrint("Error findOrCreateUser code: ${error.code}");
      debugPrint("Error findOrCreateUser details: ${error.details}");
      debugPrint("Error findOrCreateUser msg: ${error.message}");
    }
  }

  // ###########################  APP stuff ##############################

  String output = "";
  var subscription;
  bool otaStarted = false;
  bool pktOK = false;
  int otaBufSize = 4096;
  String version = "";
  bool runningOTA = false;
  TextEditingController? _controller;

  ScrollController _scrollController = new ScrollController();

  @override
  void initState() {
    usbListener();

    purchase_setup();

    super.initState();
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

  // ########################## PURCHASE functions ###########################

  Future<void> deliverProduct(PurchaseDetails purchaseDetails,
      UserCredential firebaseCreds, String provider) async {
    // IMPORTANT!! Always verify purchase details before delivering the product.
    if (purchaseDetails.productID == _kUpgradeId) {
      try {
        final resp = await deliverProductFct.call(<String, dynamic>{
          "uid": "${firebaseCreds.user!.uid}",
          "purchase_token":
              purchaseDetails.verificationData.serverVerificationData,
          "purchase_date": purchaseDetails.transactionDate
        });
        if (resp.data["error"] == false) {
          _userIsPremium = true;
        } else {
          _userIsPremium = false;
          debugPrint("Error ${resp.data["errorMsg"]}");
        }
      } on FirebaseFunctionsException catch (error) {
        debugPrint("Error deliverProduct code: ${error.code}");
        debugPrint("Error deliverProduct details: ${error.details}");
        debugPrint("Error deliverProduct msg: ${error.message}");
      }
    }
  }

  void handleError(IAPError error) {
    showDialog(
      barrierDismissible: false,
      context: navigatorKey.currentContext!,
      builder: (BuildContext context) {
        return AlertDialog(
          content: const Text("Pruchase Error.\nPurchase have been canceled."),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Ok'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> verifyPurchase(PurchaseDetails purchaseDetails,
      UserCredential firebaseCreds, String provider) async {
    // IMPORTANT!! Always verify a purchase before delivering the product.
    // check purchase is unique or with correct user
    Future<bool> res = Future<bool>.value(false);
    try {
      final resp = await verifyPurchaseFct.call(<String, dynamic>{
        "uid": "${firebaseCreds.user!.uid}",
        "purchase_token":
            purchaseDetails.verificationData.serverVerificationData,
        "purchase_date": purchaseDetails.transactionDate
      });
      if (resp.data["error"] == false) {
        res = Future<bool>.value(true);
      } else {
        debugPrint("Error ${resp.data["errorMsg"]}");
      }
    } on FirebaseFunctionsException catch (error) {
      debugPrint("Error verifyPurchase code: ${error.code}");
      debugPrint("Error verifyPurchase details: ${error.details}");
      debugPrint("Error verifyPurchase msg: ${error.message}");
    }
    return res;
  }

  void _handleInvalidPurchase(PurchaseDetails purchaseDetails) {
    showDialog(
      barrierDismissible: false,
      context: navigatorKey.currentContext!,
      builder: (BuildContext context) {
        return AlertDialog(
          content: const Text("Pruchase Error.\nPurchase have been canceled."),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Ok'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _listenToPurchaseUpdated(
      List<PurchaseDetails> purchaseDetailsList) async {
    if (_firebaseCreds != null) {
      for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
        if (purchaseDetails.status == PurchaseStatus.pending) {
          // wait
        } else {
          if (purchaseDetails.status == PurchaseStatus.error) {
            handleError(purchaseDetails.error!);
          } else if (purchaseDetails.status == PurchaseStatus.purchased ||
              purchaseDetails.status == PurchaseStatus.restored) {
            final bool valid = await verifyPurchase(
                purchaseDetails, _firebaseCreds!, provider);
            if (valid) {
              deliverProduct(purchaseDetails, _firebaseCreds!, provider);
            } else {
              _handleInvalidPurchase(purchaseDetails);
              return;
            }
          }
          if (Platform.isAndroid) {
            if (!_kAutoConsume && purchaseDetails.productID == _kUpgradeId) {
              final InAppPurchaseAndroidPlatformAddition androidAddition =
                  _inAppPurchase.getPlatformAddition<
                      InAppPurchaseAndroidPlatformAddition>();
              await androidAddition.consumePurchase(purchaseDetails);
            }
          }
          if (purchaseDetails.pendingCompletePurchase) {
            await _inAppPurchase.completePurchase(purchaseDetails);
          }
        }
      }
    }
  }

  Future<Uint8List?> downloadFirebaseFile(String fileName) async {
    try {
      Uint8List? data = await FirebaseStorage.instance.ref(fileName).getData();
      return data;
    } on FirebaseException catch (e) {
      debugPrint("Error loading $fileName File: $e");
      rethrow;
    }
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
              child: Text(output),
              controller: _scrollController,
            )),
            (!_userIsPremium)
                ? ElevatedButton(
                    child: const Text(
                      'Buy',
                      textAlign: TextAlign.center,
                      style: TextStyle(),
                    ),
                    style: TextButton.styleFrom(backgroundColor: Colors.white),
                    onPressed: () {
                      if (_products.length == 1 &&
                          _products[0].id == "premium") {
                        buyProduct(
                            (_products.isNotEmpty) ? _products[0] : null);
                      }
                    },
                  )
                : Container(),
            TextButton.icon(
              label: Text(
                'Flash Update',
                style: TextStyle(
                    fontSize: 25,
                    color: (deviceConnected) ? Colors.white : Colors.grey),
                textAlign: TextAlign.center,
              ),
              icon: Icon(
                Icons.offline_bolt,
                color: (deviceConnected) ? Colors.white : Colors.grey,
              ),
              onPressed: (deviceConnected && runningOTA == false)
                  ? () async {
                      runningOTA = true;
                      if (_userIsPremium == false) {
                        printScreen(
                            "You must buy the premium access to go further.");
                        if (_products.length == 1 &&
                            _products[0].id == "premium") {
                          buyProduct(
                              (_products.isNotEmpty) ? _products[0] : null);
                        }
                        runningOTA = false;
                        return;
                      }
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
                          } else if (data.startsWith('{"VERSION":')) {
                            Map<String, dynamic> versionMap = jsonDecode(data);
                            data = versionMap["VERSION"];
                            version = data;
                          } else {
                            printScreen(data + "\r\n");
                          }
                        });
                      }
                      version = "";
                      printScreen("Checking version\r\n");
                      // get version from firebase
                      Uint8List? firebase_version =
                          await downloadFirebaseFile("version.txt");
                      if (firebase_version == null) {
                        printScreen("Error getting version from firebase.\r\n");
                        runningOTA = false;
                        return;
                      }
                      await usbPort!
                          .write(Uint8List.fromList(("version\r\n").codeUnits));
                      while (version.length == 0) {
                        await Future.delayed(
                            const Duration(milliseconds: 200), () {});
                      }
                      if (double.parse(
                              String.fromCharCodes(firebase_version)) >=
                          double.parse(version)) {
                        printScreen(
                            "New version available ! New ${String.fromCharCodes(firebase_version)} >= device $version), proceeding...\r\n");
                      } else {
                        printScreen("No new version available. aborting.");
                        return;
                      }
                      // read file from firebase
                      Uint8List? firmware = await downloadFirebaseFile(
                          "esp32_network_toolbox.bin");
                      if (firmware == null) {
                        printScreen("Error getting firmware.\r\n");
                        runningOTA = false;
                        return;
                      }
                      int size = firmware.length;
                      printScreen("Firmware size: $size\r\n");
                      printScreen("Starting Flash procedure\r\n");
                      // send command with size
                      await usbPort!.write(Uint8List.fromList(
                          ("ota_flash $size\r\n").codeUnits));
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
                          await usbPort!.write(firmware.sublist(i));
                          break;
                        }
                        // send
                        await usbPort!
                            .write(firmware.sublist(i, i + otaBufSize));
                        // wait confirm
                        while (pktOK == false) {
                          await Future.delayed(
                              const Duration(milliseconds: 200), () {});
                        }
                        pktOK = false;
                      }
                      runningOTA = false;
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

class ExamplePaymentQueueDelegate implements SKPaymentQueueDelegateWrapper {
  @override
  bool shouldContinueTransaction(
      SKPaymentTransactionWrapper transaction, SKStorefrontWrapper storefront) {
    return true;
  }

  @override
  bool shouldShowPriceConsent() {
    return false;
  }
}
