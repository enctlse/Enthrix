import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/tor_service.dart';
import '../services/p2p_service.dart';

class TorSettingsScreen extends StatefulWidget {
  const TorSettingsScreen({super.key});

  @override
  State<TorSettingsScreen> createState() => _TorSettingsScreenState();
}

class _TorSettingsScreenState extends State<TorSettingsScreen> {
  final SettingsService _settingsService = SettingsService();
  final TorService _torService = TorService();
  bool _isEnabled = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _torService.addListener(_onTorStatusChanged);
    // Listen to P2P logs and contacts
    _torService.p2pService.logsStream.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
    _torService.p2pService.statusStream.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _torService.removeListener(_onTorStatusChanged);
    super.dispose();
  }

  void _onTorStatusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isEnabled = _settingsService.isTorEnabled;
      _isLoading = false;
    });
    
    // Initialize Tor service with saved settings
    await _torService.initialize(enabled: _isEnabled);
  }

  Future<void> _toggleTor(bool value) async {
    setState(() {
      _isEnabled = value;
    });
    
    await _settingsService.setTorEnabled(value);
    await _torService.setEnabled(value);
  }

  Future<void> _checkConnection() async {
    await _torService.checkConnection();
  }

  void _clearLogs() {
    // Logs are managed by TorService
    // This button could be used to scroll to bottom
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.security, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('О встроенном Tor'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHelpSection(
                'Что такое Tor?',
                'Tor (The Onion Router) - это сеть, которая позволяет вам анонимно использовать интернет, скрывая ваш IP-адрес и шифруя трафик.',
              ),
              const SizedBox(height: 16),
              _buildHelpSection(
                'Встроенный Tor',
                'Enthrix имеет встроенный Tor клиент (на базе Arti), который работает прямо в приложении. Не требуется установка Orbot или других приложений!',
              ),
              const SizedBox(height: 16),
              _buildHelpSection(
                'Как использовать',
                '1. Включите Tor в настройках\n'
                '2. Подождите 20-40 секунд для подключения к сети\n'
                '3. Когда статус изменится на "Подключено", Tor готов\n'
                '4. Нажмите "Проверить подключение" для проверки',
              ),
              const SizedBox(height: 16),
              _buildHelpSection(
                'Работа с VPN',
                'Встроенный Tor может работать даже при включенном VPN! Это обеспечивает дополнительный уровень безопасности.',
              ),
              const SizedBox(height: 16),
              _buildHelpSection(
                'Важно',
                'Tor значительно замедляет соединение (первое подключение занимает до 40 секунд). Некоторые функции могут работать медленнее при использовании Tor.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          content,
          style: const TextStyle(fontSize: 14),
        ),
      ],
    );
  }

  Color _getStatusColor() {
    if (!_isEnabled) return Colors.grey;
    if (_torService.isStarting) return Colors.orange;
    if (_torService.isChecking) return Colors.blue;
    if (_torService.isConnected) return Colors.green;
    return Colors.red;
  }

  IconData _getStatusIcon() {
    if (!_isEnabled) return Icons.power_off;
    if (_torService.isStarting) return Icons.sync;
    if (_torService.isChecking) return Icons.network_check;
    if (_torService.isConnected) return Icons.check_circle;
    return Icons.error;
  }
  
  String _getStatusTitle() {
    if (!_isEnabled) return 'Tor отключен';
    if (_torService.isStarting) return 'Запуск Tor...';
    if (_torService.isChecking) return 'Проверка...';
    if (_torService.isConnected) return 'Tor подключен';
    return 'Ошибка подключения';
  }

  Color _getP2pColor(dynamic status) {
    switch (status.toString()) {
      case 'P2pConnectionStatus.online':
        return Colors.green;
      case 'P2pConnectionStatus.connecting':
      case 'P2pConnectionStatus.pending':
        return Colors.orange;
      case 'P2pConnectionStatus.offline':
      default:
        return Colors.red;
    }
  }

  String _getP2pStatusText(dynamic status) {
    switch (status.toString()) {
      case 'P2pConnectionStatus.online':
        return 'В сети';
      case 'P2pConnectionStatus.connecting':
        return 'Подключение...';
      case 'P2pConnectionStatus.pending':
        return 'Ожидание подтверждения';
      case 'P2pConnectionStatus.offline':
      default:
        return 'Не в сети';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tor Settings'),
        actions: [
          IconButton(
            onPressed: _showHelpDialog,
            icon: const Icon(Icons.help_outline),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: theme.dividerTheme.color!),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: _getStatusColor().withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getStatusIcon(),
                        size: 40,
                        color: _getStatusColor(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _getStatusTitle(),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _torService.statusMessage,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_torService.errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _torService.errorMessage!,
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    // Progress bar when starting
                    if (_torService.isStarting) ...[
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _torService.bootstrapProgress / 100,
                          backgroundColor: Colors.grey.withOpacity(0.2),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _getStatusColor(),
                          ),
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_torService.bootstrapProgress.toInt()}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: _getStatusColor(),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    // Show port when connected
                    if (_torService.isConnected) ...[
                      const SizedBox(height: 8),
                      Text(
                        'SOCKS5 порт: ${_torService.socksPort}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    // Show onion address when connected
                    if (_torService.onionAddress != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.purple.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Ваш .onion адрес:',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.purple.shade700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: SelectableText(
                                    _torService.onionAddress!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.purple.shade700,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () {
                                    // Copy to clipboard - would need to add clipboard package
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Скопируйте ваш адрес: ${_torService.onionAddress}'),
                                        duration: const Duration(seconds: 3),
                                      ),
                                    );
                                  },
                                  child: Icon(
                                    Icons.copy,
                                    size: 16,
                                    color: Colors.purple.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Enable/Disable Switch
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: theme.dividerTheme.color!),
              ),
              child: SwitchListTile(
                value: _isEnabled,
                onChanged: _toggleTor,
                title: const Text('Включить Tor'),
                subtitle: const Text('Маршрутизировать трафик через Tor'),
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _isEnabled ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.security,
                    color: _isEnabled ? Colors.green : Colors.grey,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Check Connection Button
            if (_isEnabled)
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _torService.isChecking ? null : _checkConnection,
                  icon: _torService.isChecking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(_torService.isChecking ? 'Проверка...' : 'Проверить подключение'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),

            if (_isEnabled) const SizedBox(height: 24),

            // Logs Section
            if (_torService.logs.isNotEmpty)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: theme.dividerTheme.color!),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.terminal,
                            color: theme.colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Логи Tor',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 150,
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            '${_torService.logs}\n\n--- P2P Status ---\n${_torService.p2pService.contacts.map((c) => '${c.onionAddress}: ${c.status}').join('\n')}\n\n--- P2P Logs ---\n${_torService.p2pService.connectionLogs.join('\n')}',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_torService.p2pService.contacts.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('P2P Контакты', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        ..._torService.p2pService.contacts.map((contact) => ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _getP2pColor(contact.status),
                            radius: 12,
                          ),
                          title: Text(contact.displayName ?? contact.onionAddress.substring(0, 16)),
                          subtitle: Text(_getP2pStatusText(contact.status)),
                        )),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 24),

            // Info Section
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: theme.dividerTheme.color!),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Информация',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Встроенный Tor клиент работает прямо в приложении. Не требуется Orbot! Первое подключение занимает 20-40 секунд.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber,
                            color: Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Примечание: В текущей версии Tor работает только для дополнительных HTTP-запросов. Firebase трафик не маршрутизируется через Tor.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Help Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: OutlinedButton.icon(
                onPressed: _showHelpDialog,
                icon: const Icon(Icons.help_outline),
                label: const Text('Как настроить Tor'),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
