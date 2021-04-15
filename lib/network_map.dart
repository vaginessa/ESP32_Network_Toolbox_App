import 'package:flutter/material.dart';

import 'package:http/http.dart';

import 'constants.dart';

class MapPage extends StatefulWidget {
  MapPage({Key key}) : super(key: key);

  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  bool fetchingVendors;

  @override
  void initState() {
    super.initState();
    fetchingVendors = false;
    getVendors();
  }

  void dispose() {
    super.dispose();
  }

  List<String> ssids =
      networksMap.keys.where((key) => key != "" && key != "None").toList();

  Future<String> fetchVendor(String mac) async {
    var response = await get('https://api.macvendors.com/$mac');
    if (response.statusCode == 200) {
      return response.body;
    }
    return "None";
  }

  void getVendors() async {
    if (mounted) {
      setState(() {
        fetchingVendors = true;
      });
    }
    for (String key in networksMap.keys) {
      int i = 0;
      if (networksMap[key]["VENDOR"] == "") {
        networksMap[key]["VENDOR"] =
            await fetchVendor(networksMap[key]["BSSID"]);
      }
      for (Map sta in networksMap[key]["STAs"]) {
        if (networksMap[key]["STAs"][i]["VENDOR"] == "") {
          networksMap[key]["STAs"][i]["VENDOR"] = await fetchVendor(sta["MAC"]);
        }
        i++;
      }
    }
    await Future.delayed(const Duration(seconds: 1), () {});
    if (mounted) {
      setState(() {
        fetchingVendors = false;
      });
    }
  }

  Widget ssidsBuilder() {
    return (fetchingVendors)
        ? Visibility(
            maintainSize: false,
            maintainAnimation: true,
            maintainState: true,
            visible: fetchingVendors,
            child: Container(
                margin: EdgeInsets.only(top: 50, bottom: 30),
                child: CircularProgressIndicator()))
        : Expanded(
            child: ListView.builder(
                itemBuilder: (context, ssidsPosition) {
                  return ExpansionTile(
                    title: Text(
                      "${ssids[ssidsPosition]} - chan: ${networksMap[ssids[ssidsPosition]]['CHANNEL']}",
                      style: TextStyle(
                          fontSize: 18.0, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                        "${networksMap[ssids[ssidsPosition]]['BSSID']} - ${networksMap[ssids[ssidsPosition]]['VENDOR']}"),
                    children: <Widget>[
                      ListView.separated(
                          separatorBuilder: (context, index) => Divider(
                                color: Colors.black,
                              ),
                          shrinkWrap: true,
                          itemBuilder: (context, stasPosition) {
                            return ListTile(
                              title: Text(
                                  networksMap[ssids[ssidsPosition]]["STAs"]
                                      [stasPosition]["MAC"],
                                  textAlign: TextAlign.center),
                              subtitle: Text(
                                  networksMap[ssids[ssidsPosition]]["STAs"]
                                      [stasPosition]["VENDOR"],
                                  textAlign: TextAlign.center),
                            );
                          },
                          itemCount:
                              networksMap[ssids[ssidsPosition]]["STAs"].length),
                    ],
                  );
                },
                itemCount: ssids.length));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text("NetworksMap"),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[ssidsBuilder()],
          ),
        ));
  }
}
