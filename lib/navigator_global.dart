import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'esp_ota.dart';

class GlobalNavigator {
  static showBuyDialog(String text, ProductDetails? product) {
    showDialog(
      barrierDismissible: false,
      context: navigatorKey.currentContext!,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Text(text),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
                buyProduct(product);
              },
              child: const Text('Buy'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('No Thanks'),
            ),
          ],
        );
      },
    );
  }
}
