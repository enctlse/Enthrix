import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const UserProfileScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final AuthService _authService = AuthService();
  final SettingsService _settingsService = SettingsService();
  UserModel? _user;
  bool _isLoading = true;
  String? _customContactName;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _loadContactName();
  }

  Future<void> _loadUser() async {
    try {
      final user = await _authService.getUserData(widget.userId);
      if (mounted) {
        setState(() {
          _user = user;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadContactName() async {
    final savedName = await _settingsService.getContactName(widget.userId);
    if (savedName != null && mounted) {
      setState(() {
        _customContactName = savedName;
      });
    }
  }

  String get displayName => _customContactName ?? _user?.name ?? widget.userName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOnline = _user?.status == 'online';

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _user == null
              ? Center(child: Text('User not found'))
              : SafeArea(
                  child: Column(
                    children: [
                      // Top buttons
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: Icon(Icons.arrow_back, size: 24),
                              onPressed: () => Navigator.pop(context),
                            ),
                            PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert, size: 24),
                              onSelected: (value) {
                                if (value == 'edit_name') {
                                  _showEditContactNameDialog();
                                } else if (value == 'edit_profile' && _isCurrentUser) {
                                  _showEditProfileDialog();
                                }
                              },
                              itemBuilder: (context) => [
                                if (!_isCurrentUser)
                                  PopupMenuItem(
                                    value: 'edit_name',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit, size: 20),
                                        SizedBox(width: 8),
                                        Text('Edit name'),
                                      ],
                                    ),
                                  ),
                                if (_isCurrentUser)
                                  PopupMenuItem(
                                    value: 'edit_profile',
                                    child: Row(
                                      children: [
                                        Icon(Icons.person, size: 20),
                                        SizedBox(width: 8),
                                        Text('Edit profile'),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            children: [
                              SizedBox(height: 20),
                              
                              // Avatar - circular and smaller
                              Container(
                                width: 90,
                                height: 90,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    displayName[0].toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 40,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              
                              SizedBox(height: 16),
                              
                              // Name with status indicator
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    displayName,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: isOnline ? Colors.green : Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ),
                              
                              SizedBox(height: 4),
                              
                              // Online status text
                              Text(
                                isOnline ? 'online' : 'offline',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isOnline ? Colors.green : Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              
                              SizedBox(height: 30),
                              
                              // Call buttons - no glow
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildCallButton(
                                    icon: Icons.phone,
                                    color: Colors.green,
                                    onTap: () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Audio call coming soon')),
                                      );
                                    },
                                  ),
                                  SizedBox(width: 20),
                                  _buildCallButton(
                                    icon: Icons.videocam,
                                    color: Colors.blue,
                                    onTap: () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Video call coming soon')),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              
                              SizedBox(height: 40),
                              
                              // Info section - similar to settings
                              Card(
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(color: theme.dividerTheme.color!),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Column(
                                    children: [
                                      _buildInfoTile(
                                        icon: Icons.alternate_email,
                                        title: 'username',
                                        value: _user!.username,
                                      ),
                                      if (_user!.bio != null && _user!.bio!.isNotEmpty) ...[
                                        Divider(height: 1),
                                        _buildInfoTile(
                                          icon: Icons.info_outline,
                                          title: 'bio',
                                          value: _user!.bio!,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              
                              SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildCallButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey,
        ),
      ),
      subtitle: Text(
        value,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  bool get _isCurrentUser => _user?.uid == _authService.currentUser?.uid;

  void _showEditProfileDialog() {
    final nameController = TextEditingController(text: _user?.name ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit profile'),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Profile updated')),
              );
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showEditContactNameDialog() {
    final nameController = TextEditingController(text: displayName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit contact name'),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              if (newName.isNotEmpty) {
                await _settingsService.setContactName(widget.userId, newName);
                setState(() {
                  _customContactName = newName;
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Contact name updated')),
                );
              }
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }
}
