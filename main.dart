import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

void main() {
  runApp(const MyApp());
}

class AppState extends ChangeNotifier {
  String role = 'rider'; // or 'driver'
  String name = '';
  IO.Socket? socket;
  bool isRegistered = false;

  // driver state
  bool driverOnline = false;
  String? driverCurrentRideId;
  Map<String, dynamic>? driverAssignedRide;

  // rider state
  String? riderCurrentRideId;
  Map<String, dynamic>? riderRide;

  Map<String, dynamic>? stats;

  void connect(String baseUrl, String role_, String name_) {
    role = role_;
    name = name_;
    socket = IO.io(baseUrl, IO.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .build());
    socket!.connect();
    socket!.onConnect((_) {
      socket!.emit('register', {'role': role, 'name': name});
    });
    socket!.on('registered', (data) {
      isRegistered = true;
      notifyListeners();
    });
    socket!.on('stats', (data) {
      stats = Map<String, dynamic>.from(data);
      notifyListeners();
    });
    // Rider events
    socket!.on('ride:update', (data) {
      riderRide = Map<String, dynamic>.from(data);
      riderCurrentRideId = riderRide!['id'];
      notifyListeners();
    });
    // Driver events
    socket!.on('driver:rideOffer', (data) {
      driverAssignedRide = Map<String, dynamic>.from(data);
      notifyListeners();
    });
    socket!.on('driver:rideAssigned', (data) {
      driverAssignedRide = Map<String, dynamic>.from(data);
      driverCurrentRideId = driverAssignedRide!['id'];
      notifyListeners();
    });
    socket!.on('driver:rideUpdate', (data) {
      driverAssignedRide = Map<String, dynamic>.from(data);
      notifyListeners();
    });
  }

  void setDriverOnline(bool v) {
    driverOnline = v;
    socket?.emit('driver:setOnline', v);
    notifyListeners();
  }

  void requestRide(String pickup, String dropoff) {
    socket?.emit('rider:requestRide', {'pickup': pickup, 'dropoff': dropoff});
  }

  void driverAcceptRide(String rideId) {
    socket?.emit('driver:acceptRide', {'rideId': rideId});
  }

  void startRide(String rideId) {
    socket?.emit('ride:start', {'rideId': rideId});
  }

  void completeRide(String rideId) {
    socket?.emit('ride:complete', {'rideId': rideId});
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'Mini Uber',
        home: const EntryScreen(),
        theme: ThemeData(useMaterial3: true),
      ),
    );
  }
}

class EntryScreen extends StatefulWidget {
  const EntryScreen({super.key});
  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  final nameCtrl = TextEditingController(text: 'Mugurel');
  String role = 'rider';
  final serverCtrl = TextEditingController(text: 'http://localhost:4000');

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.isRegistered) {
      return role == 'driver' ? const DriverHome() : const RiderHome();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Mini Uber – Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nume'),
            ),
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
              decoration: const InputDecoration(labelText: 'Server URL (Socket.IO)'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                context.read<AppState>().connect(serverCtrl.text.trim(), role, nameCtrl.text.trim());
              },
              child: const Text('Intră în aplicație'),
            ),
            const SizedBox(height: 16),
            const Text('Instrucțiuni: pornește mai întâi serverul Node.js.'),
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
        title: const Text('Client – Cere cursă'),
        actions: [
          if (app.stats != null)
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Center(child: Text('Șoferi online: ${app.stats!['driversOnline']}')),
            )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: pickupCtrl,
              decoration: const InputDecoration(labelText: 'Punct ridicare (text)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: dropCtrl,
              decoration: const InputDecoration(labelText: 'Destinație (text)'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                app.requestRide(pickupCtrl.text.trim(), dropCtrl.text.trim());
              },
              child: const Text('Cere cursă'),
            ),
            const SizedBox(height: 16),
            if (app.riderRide != null) RideCard(ride: app.riderRide!),
          ],
        ),
      ),
    );
  }
}

class RideCard extends StatelessWidget {
  final Map<String, dynamic> ride;
  const RideCard({super.key, required this.ride});

  @override
  Widget build(BuildContext context) {
    final status = ride['status'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cursă #${ride['id']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('De la: ${ride['pickup']}'),
            Text('La: ${ride['dropoff']}'),
            Text('Status: $status'),
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
    final assigned = app.driverAssignedRide;
    final currentId = app.driverCurrentRideId;

    return Scaffold(
      appBar: AppBar(title: const Text('Șofer – Dispatcher')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Online'),
                const SizedBox(width: 8),
                Switch(
                  value: app.driverOnline,
                  onChanged: (v) => app.setDriverOnline(v),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (app.stats != null) Text('Rideri: ${app.stats!['ridersTotal']}, Șoferi online: ${app.stats!['driversOnline']}'),
            const SizedBox(height: 16),
            if (assigned != null && currentId == null) OfferCard(offer: assigned),
            if (assigned != null && currentId != null) ActiveRideCard(),
          ],
        ),
      ),
    );
  }
}

class OfferCard extends StatelessWidget {
  final Map<String, dynamic> offer;
  const OfferCard({super.key, required this.offer});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cerere nouă', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Client: ${offer['riderName']}'),
            Text('Pickup: ${offer['pickup']}'),
            Text('Dropoff: ${offer['dropoff']}'),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () => app.driverAcceptRide(offer['id']),
                  child: const Text('Acceptă'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class ActiveRideCard extends StatelessWidget {
  const ActiveRideCard({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final ride = app.driverAssignedRide ?? {};
    final status = ride['status'];
    final id = ride['id'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cursă activă #$id', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Pickup: ${ride['pickup']}'),
            Text('Dropoff: ${ride['dropoff']}'),
            Text('Status: $status'),
            const SizedBox(height: 12),
            if (status == 'assigned')
              ElevatedButton(
                onPressed: () => app.startRide(id),
                child: const Text('Pornire cursă'),
              ),
            if (status == 'in_progress')
              ElevatedButton(
                onPressed: () => app.completeRide(id),
                child: const Text('Finalizează cursa'),
              ),
          ],
        ),
      ),
    );
  }
}