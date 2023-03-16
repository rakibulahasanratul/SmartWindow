import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'db/model/central_table_model.dart'; //central database model initialize
import 'db/service/database_service.dart'; // database serice with seperate sql query for different method

class DeviceScreen extends StatefulWidget {
  const DeviceScreen({Key? key, required this.device}) : super(key: key);

  final BluetoothDevice device;

  @override
  State<StatefulWidget> createState() {
    return _DeviceScreenPageState();
  }
}

class _DeviceScreenPageState extends State<DeviceScreen> {
  double _glassSliderValue = 0; //for Glass Controller, default is 0
  double centralBatterypercentage =
      0; // Initializing central battery percentage value
  var databaseService =
      DatabaseService.instance; //Database instance initialization
  bool isLoadingCentral = true; //Central data loader
  Timer? centraltimer; // Timer declaration for central voltage load

  List<CentralDBmodel> centralvoldataDateShow =
      []; //List declaration w.r.t central database model class

// Function for getting data from central table and view in the front end app.
  Future<void> getCentralFromDatabase() async {
    List<CentralDBmodel> centralFromDb = await databaseService
        .getLatestDataFromCentralTable(); //This line is loading the latest data from the central table. The row is configurable and changes is require in the database query
    setState(() {
      centralvoldataDateShow =
          centralFromDb; //loading the data in the declared list centralvoldataDateShow[]
      isLoadingCentral = false;
    });
  }

//This function calculating the difference of central voltage to the previous voltage.Datasource central voltage table
  Future<double> getcentralDifferenceValue(double centralvoltage) async {
    double difference = 0.0;
    List<CentralDBmodel> centralFromDb = await databaseService
        .getAllDataFromCentralTable(); //This line loading all the central data in the list for difference calculation
    int index = centralFromDb.length - 1;
    if (centralFromDb.isEmpty) {
      difference = centralvoltage -
          centralvoltage; //data table 1st row diffence calculation
    } else {
      difference = centralvoltage -
          double.parse(centralFromDb[index]
              .CV); //data table all row's diffence calculation except 1st row
    }
    return difference;
  }

//This function calculating the difference of peripheral voltage to the previous voltage. Datasource peripheral voltage table

//battery voltage initiation in the inistate so that voltage update happen instantly when page load
  @override
  void initState() {
    getBatteryVoltage();
    getCentralFromDatabase();
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    centraltimer!.cancel(); //central timer cancellation once app not in use
  }

//method to have central and peripheral table time
  String getCurrentDateTime() {
    var now = DateTime.now();
    //var month = now.month.toString().padLeft(2, '0');
    // var day = now.day.toString().padLeft(2, '0');
    var hour = now.hour.toString().padLeft(2, '0');
    var minute = now.minute.toString().padLeft(2, '0');
    var seconds = now.second.toString().padLeft(2, '0');
    var formattedDate = '$hour:$minute:$seconds';
    return formattedDate;
  }

//Method to get central voltage parameter from the remote device

  Future<int> getcvcharacter2Value(List<BluetoothService> services) async {
    List service4ListIntermediate =
        []; // create list to temporarily hold service4List data
    List service4List =
        []; // creates list to hold the final values of the service 4 characteristics
    int service4Characteristic1 =
        -1; // initializes the value of characteristic 2 (central voltage) of service 4
    bool isReading = false;

    // this if statement checks if there are four services and executes the for-loop if there are
    if (services.length >= 4) {
      BluetoothService service4 = services[3]; // assigns service 4
      var service4Characteristics = service4
          .characteristics; // places all the characteristics of service 4 into a Characteristics list
      // this for-loop obtains the value of each characteristic and puts it into a list called value
      if (isReading == false) {
        for (BluetoothCharacteristic c in service4Characteristics) {
          if (c.properties.read &&
              c.uuid == Guid('55441002-3322-1100-0000-000000000000')) {
            isReading = true;
            List<int> value = await c.read(); // adds the c value to the list
            service4ListIntermediate.add(value);
          }
        }
      }
      // at this point, there is likely at least two lists in service4ListIntermediate, one of which does not have all the data we need
      service4List = service4ListIntermediate[
          0]; // obtains the first list from the list of lists. This list has all the data we need
      //service4List = ["A1", 05, 6, 2];
      log('central service4List: ${service4List}');
      service4Characteristic1 = service4List.elementAt(0) * 256 +
          (service4List.elementAt(
              1)); // obtains the elements from the service 4 characteristics list. They is already in base 10. THe second element in the list is multiplied by 256 to give its true ADC measured value
      log('central service4Characteristic1: ${service4Characteristic1}');

      // this if-statement checks if the service4Characteristic1 received a value or not, and returns the service4Characteristic1 value if it did
      if (service4Characteristic1 != -1) {
        return service4Characteristic1;
      }
    } else {
      return -1;
    }
    return -1;
  }

  //Method to convert collected parament value into battery percentage and load percentage,time, voltage value to central table
  getCentralVoltage(BluetoothDevice device) async {
    List<BluetoothService> services = await device.discoverServices();
    try {
      int _cvcharacter2Value = await getcvcharacter2Value(
          services); // assigns the returned central voltage value to a variable
      var cv = (_cvcharacter2Value + 100) / 1000;
      print('mvcv = ${cv}');
      var cvmax = 4.4;
      var cvmin = 3;
      setState(() {
        centralBatterypercentage = ((cv - cvmin) / (cvmax - cvmin)) * 100;
      });
      log('central Battery Percentage: $centralBatterypercentage');
      double difference = await getcentralDifferenceValue(cv);
      await databaseService.addToCentralDatabase(
        cv.toString(),
        getCurrentDateTime(),
        centralBatterypercentage.toString(),
        difference.toString(),
      );
      await getCentralFromDatabase();
      print('Successfully central data loaded in the database');
      return centralBatterypercentage;
    } catch (err) {
      print('Caught Error: $err');
    }
  }

//Method to iniitate timer for central and peripheral voltage data for this page loading.
  getBatteryVoltage() {
    centraltimer = Timer.periodic(
        Duration(
          seconds: 65,
        ), (timer) {
      log("central Timer Working");
      getCentralVoltage(widget.device);
    });
  }

  List<DataRow> getCentraldetails() {
    List<DataRow> rows = [];
    for (var i = 0; i < centralvoldataDateShow.length; i++) {
      rows.add(
        DataRow(
          cells: <DataCell>[
            DataCell(Text(
              centralvoldataDateShow[i].CV,
              textAlign: TextAlign.center,
            )),
          ],
        ),
      );
    }
    return rows;
  }

// Method to send hex value to Char3 for PWM or Light Sensor control
  void sendHexValue({
    required List<BluetoothService> services,
    required int hexValue,
  }) {
    if (services.length >= 4) {
      BluetoothService service4 = services[3];
      if (service4.characteristics.isNotEmpty) {
        service4.characteristics[2].write([hexValue]);
        //Service id for control code characteristic '55441004-3322-1100-0000-000000000000'
        //log('Cha4 service UUID: ${service4.characteristics[2].uuid}');
      }
    }
  }

  Widget _buildServiceTiles(List<BluetoothService> services) {
    return Column(
      children: [
        ElevatedButton(
          child: Text('Boost Coverter', style: TextStyle(fontSize: 26)),
          onPressed: () {},
        ),
        SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              child: Text('OFF', style: TextStyle(fontSize: 16)),
              onPressed: () {
                sendHexValue(services: services, hexValue: 0x01);
                log('0x01 hex value successfully sent to central');
              },
              style: ButtonStyle(
                backgroundColor: MaterialStateProperty.resolveWith<Color>(
                  (Set<MaterialState> states) {
                    if (states.contains(MaterialState.pressed))
                      return Colors.green;
                    return Colors.blue;
                  },
                ),
              ),
            ),
            SizedBox(width: 50),
            ElevatedButton(
              child: Text('ON', style: TextStyle(fontSize: 16)),
              onPressed: () {
                sendHexValue(services: services, hexValue: 0x02);
                log('0x02 hex value successfully sent to central');
              },
              style: ButtonStyle(
                backgroundColor: MaterialStateProperty.resolveWith<Color>(
                  (Set<MaterialState> states) {
                    if (states.contains(MaterialState.pressed))
                      return Colors.green;
                    return Colors.blue;
                  },
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 30),
        Container(
          child: Text("Operating Voltage", style: TextStyle(fontSize: 20)),
        ),
        Slider(
            value: _glassSliderValue,
            onChanged:
                (value) {}, //Not in use but its mandatory field of slider widget.
            onChangeEnd: (double value) {
              setState(() {
                _glassSliderValue = value;
                log('Glass Controller value changed: $value');
                if (services.length >= 4) {
                  BluetoothService service4 = services[3];
                  if (service4.characteristics.isNotEmpty) {
                    service4.characteristics[0].write([value.toInt()]);
                    //Service id for control code characteristic '55441001-3322-1100-0000-000000000000'
                    log('Char1 service UUID: ${service4.characteristics[0].uuid}');
                  }
                }
              });
            },
            min: 0.0,
            max: 22.0,
            divisions: 22,
            thumbColor: Colors.deepPurple,
            label: '$_glassSliderValue'),
        SizedBox(height: 30),
        isLoadingCentral
            ? Center(
                child: CircularProgressIndicator(),
              )
            : DataTable(
                columnSpacing: 30,
                columns: const <DataColumn>[
                  DataColumn(
                    label: Expanded(
                      child: Text(
                        'Operated Voltage',
                        style: TextStyle(fontSize: 20),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
                rows: getCentraldetails(),
              ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.name),
        actions: <Widget>[
          StreamBuilder<BluetoothDeviceState>(
            stream: widget.device.state,
            initialData: BluetoothDeviceState.connecting,
            builder: (c, snapshot) {
              VoidCallback? onPressed;
              String text;
              switch (snapshot.data) {
                case BluetoothDeviceState.connected:
                  onPressed = () => widget.device.disconnect();
                  text = 'DISCONNECT';
                  break;
                case BluetoothDeviceState.disconnected:
                  onPressed = () => widget.device.connect();
                  text = 'CONNECT';
                  break;
                default:
                  onPressed = null;
                  text = snapshot.data.toString().substring(21).toUpperCase();
                  break;
              }
              return TextButton(
                  onPressed: onPressed,
                  child: Text(
                    text,
                    style: Theme.of(context)
                        .primaryTextTheme
                        .button
                        ?.copyWith(color: Colors.blue),
                  ));
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Image.asset(
                  'assets/images/AMIlogoWEBP.webp',
                  height: 60,
                  width: 60,
                ),
              ],
            ),
            StreamBuilder<BluetoothDeviceState>(
              stream: widget.device.state,
              initialData: BluetoothDeviceState.connecting,
              builder: (c, snapshot) => ListTile(
                leading: (snapshot.data == BluetoothDeviceState.connected)
                    ? Icon(Icons.bluetooth_connected)
                    : Icon(Icons.bluetooth_disabled),
                title: Text(
                    'Device is ${snapshot.data.toString().split('.')[1]}.'),
                subtitle: Text('${widget.device.id}'),
                trailing: StreamBuilder<bool>(
                  stream: widget.device.isDiscoveringServices,
                  initialData: false,
                  builder: (c, snapshot) => IndexedStack(
                    index: snapshot.data! ? 1 : 0,
                    children: <Widget>[
                      IconButton(
                        icon: SizedBox(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation(Colors.grey),
                          ),
                          width: 18.0,
                          height: 18.0,
                        ),
                        onPressed: null,
                      )
                    ],
                  ),
                ),
              ),
            ),
            StreamBuilder<List<BluetoothService>>(
              stream: widget.device.services,
              initialData: [],
              builder: (c, snapshot) {
                return _buildServiceTiles(snapshot.data!);
              },
            ),
          ],
        ),
      ),
      floatingActionButton: Image.asset(
        'assets/images/Miami_OH_JPG.jpg',
        height: 60,
        width: 60,
      ),
    );
  }
}
