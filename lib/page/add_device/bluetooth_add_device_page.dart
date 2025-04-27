import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
// import 'package:astraval_smart/service/bluetooth_add_device_service.dart';

class BluetoothAddDevicePage extends StatefulWidget {
  const BluetoothAddDevicePage({super.key});

  @override
  State<BluetoothAddDevicePage> createState() => _BluetoothAddDevicePageState();
}

class _BluetoothAddDevicePageState extends State<BluetoothAddDevicePage> {
  final flutterReactiveBle = FlutterReactiveBle();
  final List<DiscoveredDevice> devices = [];
  DiscoveredDevice? selectedDevice;
  String ssid = 'loop';
  String password = 'cyber@123';
  String statusMessage = 'Ready';
  String receivedDid = '';
  StreamSubscription<DiscoveredDevice>? scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? connectionSubscription;
  QualifiedCharacteristic? characteristic;
  final ssidController = TextEditingController(text: 'loop');
  final passwordController = TextEditingController(text: 'cyber@123');

  // BLE UUIDs (must match ESP32)
  final serviceUuid = Uuid.parse('4fafc201-1fb5-459e-8fcc-c5c9c331914b');
  final characteristicUuid = Uuid.parse('beb5483e-36e1-4688-b7f5-ea07361b26a8');

  @override
  void initState() {
    super.initState();
    requestPermissions();
  }

  Future<void> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses =
        await [
          Permission.bluetooth,
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse,
        ].request();

    if (statuses.values.every((status) => status.isGranted)) {
      setState(() => statusMessage = 'Permissions granted');
    } else {
      setState(() => statusMessage = 'Permissions denied');
    }
  }

  void startScan() {
    setState(() {
      devices.clear();
      selectedDevice = null;
      statusMessage = 'Scanning...';
    });

    scanSubscription?.cancel();
    scanSubscription = flutterReactiveBle
        .scanForDevices(withServices: [serviceUuid])
        .listen(
          (device) {
            setState(() {
              // Add device to list if not already present
              if (!devices.any((d) => d.id == device.id)) {
                devices.add(device);
              }
              statusMessage = 'Found ${devices.length} device(s)';
            });
          },
          onError: (e) {
            setState(() => statusMessage = 'Scan error: $e');
          },
        );

    // Stop scanning after 10 seconds
    Timer(const Duration(seconds: 10), () {
      scanSubscription?.cancel();
      setState(() {
        statusMessage =
            devices.isEmpty
                ? 'No devices found'
                : 'Scan complete: ${devices.length} device(s) found';
      });
    });
  }

  Future<void> sendCredentials() async {
    if (selectedDevice == null) {
      setState(() => statusMessage = 'No device selected');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a device')));
      return;
    }
    if (ssid.isEmpty || password.isEmpty) {
      setState(() => statusMessage = 'Enter SSID and Password');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter SSID and Password')),
      );
      return;
    }

    setState(() => statusMessage = 'Connecting to ${selectedDevice!.name}...');

    connectionSubscription?.cancel();
    connectionSubscription = flutterReactiveBle
        .connectToDevice(
          id: selectedDevice!.id,
          servicesWithCharacteristicsToDiscover: {
            serviceUuid: [characteristicUuid],
          },
          connectionTimeout: const Duration(seconds: 10),
        )
        .listen(
          (connectionState) async {
            if (connectionState.connectionState ==
                DeviceConnectionState.connected) {
              setState(
                () => statusMessage = 'Connected to ${selectedDevice!.name}',
              );

              characteristic = QualifiedCharacteristic(
                serviceId: serviceUuid,
                characteristicId: characteristicUuid,
                deviceId: selectedDevice!.id,
              );

              // Subscribe to notifications for DID
              flutterReactiveBle
                  .subscribeToCharacteristic(characteristic!)
                  .listen(
                    (data) {
                      String did = utf8.decode(data);
                      setState(() {
                        receivedDid = did;
                        statusMessage = 'Credentials sent successfully';
                      });
                      // Show success message with DID
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Success: Received $did'),
                          duration: const Duration(seconds: 5),
                        ),
                      );
                      // insert the did into the users/user_id/devices collection {did:"high"} TODO
                      print(receivedDid);
                      // and if the device id is not in the `devices` collection {structure}
                    },
                    onError: (e) {
                      setState(() => statusMessage = 'Notification error: $e');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Notification error: $e')),
                      );
                    },
                  );

              // Send SSID,Password\n
              String credentials = '$ssid,$password\n';
              await flutterReactiveBle.writeCharacteristicWithResponse(
                characteristic!,
                value: utf8.encode(credentials),
              );
              setState(
                () =>
                    statusMessage =
                        'Credentials sent to ${selectedDevice!.name}',
              );
            } else if (connectionState.connectionState ==
                DeviceConnectionState.disconnected) {
              setState(
                () =>
                    statusMessage = 'Disconnected from ${selectedDevice!.name}',
              );
            }
          },
          onError: (e) {
            setState(() => statusMessage = 'Connection error: $e');
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Connection error: $e')));
          },
        );
  }

  @override
  void dispose() {
    scanSubscription?.cancel();
    connectionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ESP32 BLE Provisioning')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ssidController,
              decoration: const InputDecoration(labelText: 'SSID'),
              onChanged: (value) => ssid = value,
            ),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              onChanged: (value) => password = value,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: startScan,
                  child: const Text('Scan for Devices'),
                ),
                ElevatedButton(
                  onPressed: sendCredentials,
                  child: const Text('Send Credentials'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Status: $statusMessage'),
            if (receivedDid.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Received DID: $receivedDid',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
            const SizedBox(height: 20),
            const Text(
              'Discovered Devices:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Expanded(
              child:
                  devices.isEmpty
                      ? const Center(child: Text('No devices found'))
                      : ListView.builder(
                        itemCount: devices.length,
                        itemBuilder: (context, index) {
                          final device = devices[index];
                          return ListTile(
                            title: Text(
                              device.name.isEmpty
                                  ? 'Unknown Device'
                                  : device.name,
                            ),
                            subtitle: Text(device.id),
                            selected: selectedDevice?.id == device.id,
                            selectedTileColor: Colors.deepPurple.withOpacity(
                              0.1,
                            ),
                            onTap: () {
                              setState(() {
                                selectedDevice = device;
                                statusMessage =
                                    'Selected: ${device.name.isEmpty ? device.id : device.name}';
                              });
                            },
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
