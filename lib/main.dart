import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'smartwatch_service.dart';

void main() {
  runApp(const GameFitApp());
}

class GameFitApp extends StatelessWidget {
  const GameFitApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF10131F);
    return MaterialApp(
      title: 'GameFit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB8F36B),
          brightness: Brightness.dark,
          surface: const Color(0xFF1A1E2D),
        ),
        fontFamily: 'Roboto',
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _watch = SmartwatchService.instance;
  StreamSubscription<int>? _heartRateSubscription;
  Timer? _workoutTimer;
  int _heartRate = 0;
  final Stopwatch _workoutStopwatch = Stopwatch();
  late final Future<void> _statsReady;
  int _todayPoints = 0;
  int _todayMinutes = 0;
  int _completedWorkouts = 0;
  bool _isWorkingOut = false;
  bool _isConnecting = false;

  int get _elapsedSeconds => _workoutStopwatch.elapsed.inSeconds;
  int get _sessionPoints => _elapsedSeconds * 10 ~/ 60;

  @override
  void initState() {
    super.initState();
    _statsReady = _loadTodayStats();
    _heartRateSubscription = _watch.heartRate.listen((value) {
      if (mounted) setState(() => _heartRate = value);
    });
  }

  String _todayStorageKey(String metric) {
    final today = DateTime.now();
    final date = '${today.year}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    return 'gamefit_${date}_$metric';
  }

  Future<void> _loadTodayStats() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _todayPoints = preferences.getInt(_todayStorageKey('points')) ?? 0;
        _todayMinutes = preferences.getInt(_todayStorageKey('minutes')) ?? 0;
        _completedWorkouts =
            preferences.getInt(_todayStorageKey('workouts')) ?? 0;
      });
    } catch (error) {
      if (mounted) _showMessage('Não foi possível carregar seus pontos: $error');
    }
  }

  Future<void> _saveTodayStats() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final savedPoints = await preferences.setInt(
        _todayStorageKey('points'),
        _todayPoints,
      );
      final savedMinutes = await preferences.setInt(
        _todayStorageKey('minutes'),
        _todayMinutes,
      );
      final savedWorkouts = await preferences.setInt(
        _todayStorageKey('workouts'),
        _completedWorkouts,
      );
      if (!savedPoints || !savedMinutes || !savedWorkouts) {
        throw StateError('O armazenamento local recusou os dados do treino.');
      }
    } catch (error) {
      if (mounted) _showMessage('Não foi possível salvar seus pontos: $error');
    }
  }

  @override
  void dispose() {
    _workoutTimer?.cancel();
    _heartRateSubscription?.cancel();
    super.dispose();
  }

  Future<void> _findWatch() async {
    setState(() => _isConnecting = true);
    try {
      await _watch.startScan();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: const Color(0xFF1A1E2D),
        showDragHandle: true,
        builder: (context) => _WatchPicker(
          service: _watch,
          onConnect: (device) async {
            Navigator.pop(context);
            try {
              await _watch.connect(device);
              if (mounted) _showMessage('Relógio conectado.');
            } catch (error) {
              if (mounted) _showMessage(error.toString());
            }
          },
        ),
      );
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _toggleWatchConnection() async {
    if (_watch.connectedDevice == null) {
      await _findWatch();
      return;
    }

    try {
      await _watch.disconnect();
      if (mounted) _showMessage('Smartwatch desconectado.');
    } catch (error) {
      if (mounted) _showMessage('Não foi possível desconectar: $error');
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleWorkout() async {
    await _statsReady;
    if (!mounted) return;

    if (_isWorkingOut) {
      _workoutTimer?.cancel();
      setState(() {
        _isWorkingOut = false;
        _todayPoints += _sessionPoints;
        _todayMinutes += _elapsedSeconds ~/ 60;
        if (_elapsedSeconds > 0) _completedWorkouts++;
      });
      _workoutStopwatch
        ..stop()
        ..reset();
      unawaited(_saveTodayStats());
      _showMessage('Treino finalizado. Pontos adicionados ao seu dia!');
      return;
    }

    setState(() {
      _isWorkingOut = true;
    });
    _workoutStopwatch
      ..reset()
      ..start();
    _workoutTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _duration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = seconds ~/ 60 % 60;
    final remainingSeconds = seconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${remainingSeconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final connectedName = _watch.connectedDevice?.platformName;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFB8F36B),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.bolt_rounded,
                    color: Color(0xFF10131F),
                    size: 27,
                  ),
                ),
                const SizedBox(width: 11),
                const Text(
                  'gamefit',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                IconButton.filledTonal(
                  onPressed: _isConnecting ? null : _toggleWatchConnection,
                  tooltip: connectedName == null
                      ? 'Conectar smartwatch'
                      : 'Relógio conectado: $connectedName',
                  icon: _isConnecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          connectedName == null
                              ? Icons.bluetooth_searching_rounded
                              : Icons.bluetooth_connected_rounded,
                        ),
                ),
              ],
            ),
            const SizedBox(height: 27),
            Text(
              'OLÁ, VAMOS NOS MEXER?',
              style: TextStyle(
                color: Colors.white.withOpacity(0.62),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Seu movimento vale pontos.',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            _ScoreCard(
              points: _todayPoints + (_isWorkingOut ? _sessionPoints : 0),
              minutes:
                  _todayMinutes + (_isWorkingOut ? _elapsedSeconds ~/ 60 : 0),
              workouts: _completedWorkouts,
            ),
            const SizedBox(height: 15),
            _HeartRateCard(
              heartRate: _heartRate,
              connectedName: connectedName,
              onConnect: _findWatch,
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Treino livre',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                  ),
                ),
                if (_isWorkingOut)
                  Text(
                    '+$_sessionPoints pts',
                    style: const TextStyle(
                      color: Color(0xFFB8F36B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _WorkoutCard(
              duration: _duration(_elapsedSeconds),
              isWorkingOut: _isWorkingOut,
              onPressed: _toggleWorkout,
            ),
            const SizedBox(height: 13),
            Text(
              'Você ganha 10 pontos por minuto de treino registrado.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({
    required this.points,
    required this.minutes,
    required this.workouts,
  });

  final int points;
  final int minutes;
  final int workouts;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(21),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF283343), Color(0xFF20273A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'PONTOS DE HOJE',
                  style: TextStyle(
                    color: Color(0xFFCFD5E2),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              const Icon(Icons.stars_rounded, color: Color(0xFFB8F36B)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$points',
                style: const TextStyle(
                  fontSize: 54,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 8, bottom: 9),
                child: Text(
                  'pts',
                  style: TextStyle(color: Color(0xFFB8F36B), fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          Container(height: 1, color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 15),
          Row(
            children: [
              _ScoreStat(label: 'Minutos ativos', value: '$minutes min'),
              const Spacer(),
              _ScoreStat(label: 'Treinos', value: '$workouts'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScoreStat extends StatelessWidget {
  const _ScoreStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.58),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _HeartRateCard extends StatelessWidget {
  const _HeartRateCard({
    required this.heartRate,
    required this.connectedName,
    required this.onConnect,
  });

  final int heartRate;
  final String? connectedName;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final connected = connectedName != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1E2D),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B7F).withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.favorite_rounded,
              color: Color(0xFFFF7184),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Frequência cardíaca',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  connected ? connectedName! : 'Conecte um relógio compatível',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            heartRate > 0 ? '$heartRate' : '--',
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 4),
          Text(
            'bpm',
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 11,
            ),
          ),
          if (!connected)
            IconButton(
              onPressed: onConnect,
              icon: const Icon(Icons.add_circle_outline_rounded),
              tooltip: 'Conectar relógio',
            ),
        ],
      ),
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({
    required this.duration,
    required this.isWorkingOut,
    required this.onPressed,
  });

  final String duration;
  final bool isWorkingOut;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1E2D),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFB8F36B).withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.directions_run_rounded,
              color: Color(0xFFB8F36B),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isWorkingOut ? 'Treino em andamento' : 'Pronto para começar?',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  duration,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.58),
                    fontSize: 13,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: isWorkingOut
                  ? const Color(0xFFEF6B74)
                  : const Color(0xFFB8F36B),
              foregroundColor: const Color(0xFF10131F),
              padding: const EdgeInsets.symmetric(horizontal: 17),
            ),
            child: Text(isWorkingOut ? 'Finalizar' : 'Iniciar'),
          ),
        ],
      ),
    );
  }
}

class _WatchPicker extends StatelessWidget {
  const _WatchPicker({required this.service, required this.onConnect});

  final SmartwatchService service;
  final ValueChanged<BluetoothDevice> onConnect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 5, 22, 12),
              child: Text(
                'Conectar smartwatch',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<ScanResult>>(
                stream: service.scanResults,
                builder: (context, snapshot) {
                  final results = snapshot.data ?? [];
                  if (results.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Procurando relógios próximos…\n'
                          'Verifique se o Bluetooth está ligado.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.65),
                          ),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final result = results[index];
                      final name = result.device.platformName.isNotEmpty
                          ? result.device.platformName
                          : result.advertisementData.advName;
                      return ListTile(
                        leading: const Icon(Icons.watch_rounded),
                        title: Text(
                          name.isNotEmpty ? name : 'Dispositivo sem nome',
                        ),
                        subtitle: Text('Sinal Bluetooth: ${result.rssi} dBm'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => onConnect(result.device),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
              child: Text(
                'Compatível com relógios que transmitem frequência cardíaca '
                'pelo perfil Bluetooth padrão.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}