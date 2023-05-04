import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'constants.dart';

class MapPage extends StatefulWidget {
  MapPage({Key? key}) : super(key: key);

  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  @override
  void initState() {
    super.initState();
  }

  void dispose() {
    super.dispose();
  }

  List<String> ssids =
      networksMap.keys.where((key) => key != "" && key != "None").toList();

  Future<String> fetchVendor(String mac) async {
    var response = await get(Uri.parse('https://api.macvendors.com/$mac'));
    if (response.statusCode == 200) {
      return response.body;
    }
    return "None";
  }

  Widget ssidsBuilder() {
    ScrollController _controller = new ScrollController();
    return Expanded(
        child: ListView.builder(
            itemBuilder: (context, ssidsPosition) {
              return ExpansionTile(
                title: Text(
                  "${ssids[ssidsPosition]} - chan: ${networksMap[ssids[ssidsPosition]]['CHANNEL']}",
                  style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  "${networksMap[ssids[ssidsPosition]]['BSSID']} - ${networksMap[ssids[ssidsPosition]]['VENDOR']}",
                  overflow: TextOverflow.ellipsis,
                ),
                controlAffinity: ListTileControlAffinity.leading,
                trailing: IconButton(
                  icon: Icon(
                    (networksMap[ssids[ssidsPosition]]['VENDOR'] != "")
                        ? Icons.devices_other
                        : Icons.device_unknown,
                    size: 20.0,
                    color: Colors.lightGreen,
                  ),
                  onPressed: () async {
                    //  action
                    networksMap[ssids[ssidsPosition]]['VENDOR'] =
                        await fetchVendor(
                            networksMap[ssids[ssidsPosition]]['BSSID']);
                    setState(() {});
                  },
                ),
                children: <Widget>[
                  ListView.separated(
                      controller: _controller,
                      separatorBuilder: (context, index) => Divider(
                            color: Colors.black,
                          ),
                      shrinkWrap: true,
                      itemBuilder: (context, stasPosition) {
                        String sta = networksMap[ssids[ssidsPosition]]["STAs"]
                            .keys
                            .elementAt(stasPosition);
                        return ListTile(
                          title: Text(
                            sta,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                              networksMap[ssids[ssidsPosition]]["STAs"][sta],
                              textAlign: TextAlign.center),
                          trailing: IconButton(
                            icon: Icon(
                              (networksMap[ssids[ssidsPosition]]["STAs"][sta] !=
                                      "")
                                  ? Icons.devices_other
                                  : Icons.device_unknown,
                              size: 20.0,
                              color: Colors.lightGreen,
                            ),
                            onPressed: () async {
                              //  action
                              networksMap[ssids[ssidsPosition]]["STAs"][sta] =
                                  await fetchVendor(sta);
                              setState(() {});
                            },
                          ),
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
