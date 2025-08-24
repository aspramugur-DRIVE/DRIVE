import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Mini Uber',
        theme: ThemeData(useMaterial3: true),
        home: const EntryScreen(),
      ),
    );
  }
}

class AppState extends ChangeNotifier {
  String role = 'rider'; // rider/driver
  String name = 'Mugurel';
  String serverUrl = 'http://192.168.0.100:4000'; // îl schimbi la login
  IO.Socket? socket;
  bool registered = false;

  bool driverOnline = false;
  int? driverRideId; // <- important: id numeric
  Map<String, dynamic>? driverRide;
  Map<String, dynamic>? riderRide;
  Map<String, dynamic>? stats;

  void connect() {
    // închide orice conexiune veche
    socket?.dispose();
    socket = null;

    // normalizează URL: fără spații și fără slash la final
    final url = serverUrl.trim().replaceAll(RegExp(r'\/$'), '');

    // opțiuni valide pentru socket_io_client ^2.0.3+1
    final opts = IO.OptionBuilder()
        .setTransports(['websocket', 'polling']) // permite fallback
        .disableAutoConnect()
        .build();

    // ATENȚIE: doar 2 argumente (uri, options)
    socket = IO.io(url, opts);

    // ---- LISTENERS ----
    socket!.onConnect((_) {
      socket!.emit('register', {'role': role, 'name': name});
      notifyListeners();
    });

    socket!.onDisconnect((_) => notifyListeners());
    socket!.onConnectError((err) {
      debugPrint('connect_error: $err');
      notifyListeners();
    });
    socket!.onError((err) => debugPrint('socket_error: $err'));

    socket!.on('registered', (_) {
      registered = true;
      notifyListeners();
    });

    socket!.on('stats', (data) {
      stats = Map<String, dynamic>.from(data as Map);
      notifyListeners();
    });

    socket!.on('ride:update', (data) {
      riderRide = Map<String, dynamic>.from(data as Map);
      notifyListeners();
    });

    socket!.on('driver:rideOffer', (data) {
      driverRide = Map<String, dynamic>.from(data as Map);
      driverRideId = driverRide?['id'] as int?;
      notifyListeners();
    });

    socket!.on('driver:rideAssigned', (data) {
      driverRide = Map<String, dynamic>.from(data as Map);
      driverRideId = driverRide?['id'] as int?;
      notifyListeners();
    });

    socket!.on('driver:rideUpdate', (data) {
      driverRide = Map<String, dynamic>.from(data as Map);
      notifyListeners();
    });

    // pornește conexiunea abia după setarea listener-elor
    socket!.connect();
  }

  void setDriverOnline(bool v) {
    driverOnline = v;
    socket?.emit('driver:setOnline', v);
    notifyListeners();
  }

  void requestRide(String pickup, String drop) {
    socket?.emit('rider:requestRide', {'pickup': pickup, 'dropoff': drop});
  }

  void driverAccept() {
    if (driverRideId != null) {
      socket?.emit('driver:acceptRide', {'rideId': driverRideId});
    }
  }

  void startRide() {
    if (driverRideId != null) {
      socket?.emit('ride:start', {'rideId': driverRideId});
    }
  }

  void completeRide() {
    if (driverRideId != null) {
      socket?.emit('ride:complete', {'rideId': driverRideId});
    }
  }
}

class EntryScreen extends StatefulWidget {
  const EntryScreen({super.key});
  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  final nameCtrl = TextEditingController(text: 'Mugurel');
  final serverCtrl = TextEditingController(text: 'http://192.168.0.100:4000');
  String role = 'rider';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.registered) {
      return role == 'driver' ? const DriverHome() : const RiderHome();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Mini Uber – Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nume')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: role,
              items: const [
                DropdownMenuItem(value: 'rider', child: Text('Client (Rider)')),
                DropdownMenuItem(value: 'driver', child: Text('Șofer (Driver)')),
              ],
              onChanged: (v) => setState(() => role = v ?? 'rider'),
              decoration: const InputDecoration(labelText: 'Rol'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: serverCtrl,
              decoration: const InputDecoration(labelText: 'Server URL (ex: http://IP_PC:4000)'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                final st = context.read<AppState>();
                st.name = nameCtrl.text.trim().isEmpty ? 'Mugurel' : nameCtrl.text.trim();
                st.role = role;
                st.serverUrl = serverCtrl.text.trim();
                st.connect();
              },
              child: const Text('Intră în aplicație'),
            ),
            const SizedBox(height: 8),
            const Text('Telefonul și PC-ul trebuie pe același Wi-Fi.'),
          ],
        ),
      ),
    );
  }
}

class RiderHome extends StatefulWidget {
  const RiderHome({super.key});
  @override
  State<RiderHome> createState() => _RiderHomeState();
}

class _RiderHomeState extends State<RiderHome> {
  final pickupCtrl = TextEditingController(text: 'Primărie');
  final dropCtrl = TextEditingController(text: 'Gara');
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Client - Cere cursă'),
        actions: [
          if (app.stats != null)
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Center(child: Text('Șoferi online: ${app.stats!['driversOnline'] ?? 0}')),
            )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: pickupCtrl, decoration: const InputDecoration(labelText: 'Punct ridicare')),
            const SizedBox(height: 8),
            TextField(controller: dropCtrl, decoration: const InputDecoration(labelText: 'Destinație')),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: () => app.requestRide(pickupCtrl.text, dropCtrl.text), child: const Text('Cere cursă')),
            const SizedBox(height: 16),
            if (app.riderRide != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cursă #${app.riderRide!['id'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('Status: ${app.riderRide!['status']}'),
                      Text('Pickup: ${app.riderRide!['pickup']}'),
                      Text('Dropoff: ${app.riderRide!['dropoff']}'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class DriverHome extends StatelessWidget {
  const DriverHome({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final ride = app.driverRide;
    return Scaffold(
      appBar: AppBar(title: const Text('Șofer - Dispatcher')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('Online'),
              const SizedBox(width: 8),
              Switch(value: app.driverOnline, onChanged: (v) => app.setDriverOnline(v)),
            ]),
            const SizedBox(height: 8),
            if (app.stats != null) Text('Rideri: ${app.stats!['ridersTotal']}, Șoferi online: ${app.stats!['driversOnline']}'),
            const SizedBox(height: 16),
            if (ride == null) const Text('Aștept cerere...'),
            if (ride != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cerere #${ride['id']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('Pickup: ${ride['pickup']}'),
                      Text('Dropoff: ${ride['dropoff']}'),
                      const SizedBox(height: 12),
                      if (ride['status'] == null || ride['status'] == 'searching')
                        ElevatedButton(onPressed: app.driverAccept, child: const Text('Acceptă')),
                      if (ride['status'] == 'assigned')
                        ElevatedButton(onPressed: app.startRide, child: const Text('Pornire cursă')),
                      if (ride['status'] == 'in_progress')
                        ElevatedButton(onPressed: app.completeRide, child: const Text('Finalizează cursa')),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
