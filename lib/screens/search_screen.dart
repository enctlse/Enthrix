import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'chat_screen.dart';
import '../services/auth_service.dart';

class SearchScreen extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  const SearchScreen({
    super.key,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  final _firestore = FirebaseFirestore.instance;
  final _authService = AuthService();
  bool _isSearching = false;
  List<String> _recentSearches = [];
  List<Map<String, dynamic>> _searchResults = [];
  bool _isLoading = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onSearchChanged(String query) async {
    setState(() {
      _isSearching = query.isNotEmpty;
      _isLoading = true;
    });

    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isLoading = false;
      });
      return;
    }

    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final nameQuery = await _firestore
          .collection('users')
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThanOrEqualTo: query + '\uf8ff')
          .limit(10)
          .get();

      final usernameQuery = await _firestore
          .collection('users')
          .where('username', isGreaterThanOrEqualTo: query.toLowerCase())
          .where(
            'username',
            isLessThanOrEqualTo: query.toLowerCase() + '\uf8ff',
          )
          .limit(10)
          .get();

      final resultsMap = <String, Map<String, dynamic>>{};

      for (final doc in nameQuery.docs) {
        if (doc.id != currentUser.uid) {
          resultsMap[doc.id] = {
            'uid': doc.id,
            'name': doc['name'] ?? '',
            'username': doc['username'] ?? '',
            'status': doc['status'] ?? 'offline',
          };
        }
      }

      for (final doc in usernameQuery.docs) {
        if (doc.id != currentUser.uid) {
          resultsMap[doc.id] = {
            'uid': doc.id,
            'name': doc['name'] ?? '',
            'username': doc['username'] ?? '',
            'status': doc['status'] ?? 'offline',
          };
        }
      }

      setState(() {
        _searchResults = resultsMap.values.toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _isSearching = false;
      _searchResults = [];
    });
  }

  void _removeRecentSearch(String search) {
    setState(() {
      _recentSearches.remove(search);
    });
  }

  void _performSearch(String query) {
    if (query.isNotEmpty && !_recentSearches.contains(query)) {
      setState(() {
        _recentSearches.insert(0, query);
        if (_recentSearches.length > 10) {
          _recentSearches.removeLast();
        }
      });
    }
  }

  void _openChat(Map<String, dynamic> user) {
    print('Opening chat with user: ${user['name']}, uid: ${user['uid']}');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          userName: user['name'],
          otherUserId: user['uid'],
          isDarkMode: widget.isDarkMode,
          onToggleTheme: widget.onToggleTheme,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          onChanged: _onSearchChanged,
          onSubmitted: _performSearch,
          decoration: InputDecoration(
            hintText: 'Search users by name or username...',
            hintStyle: TextStyle(
              color: theme.iconTheme.color?.withOpacity(0.5),
            ),
            border: InputBorder.none,
            suffixIcon: _isSearching
                ? IconButton(
                    onPressed: _clearSearch,
                    icon: const Icon(Icons.close),
                  )
                : null,
          ),
          style: theme.textTheme.titleMedium,
        ),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.filter_list_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isSearching
          ? _buildSearchResults(theme)
          : _buildRecentSearches(theme),
    );
  }

  Widget _buildRecentSearches(ThemeData theme) {
    if (_recentSearches.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 80,
              color: theme.iconTheme.color?.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Start searching',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: theme.iconTheme.color?.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Find users by name or username',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.iconTheme.color?.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Recent Searches', style: theme.textTheme.titleLarge),
            TextButton(
              onPressed: () {
                setState(() {
                  _recentSearches.clear();
                });
              },
              child: const Text('Clear All'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ..._recentSearches.map(
          (search) => ListTile(
            leading: Icon(
              Icons.history,
              color: theme.iconTheme.color?.withOpacity(0.5),
            ),
            title: Text(search),
            trailing: IconButton(
              onPressed: () => _removeRecentSearch(search),
              icon: const Icon(Icons.close, size: 20),
            ),
            onTap: () {
              _searchController.text = search;
              _onSearchChanged(search);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResults(ThemeData theme) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: theme.colorScheme.primary),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 80,
              color: theme.iconTheme.color?.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No users found',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: theme.iconTheme.color?.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try different name or username',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.iconTheme.color?.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Users', style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        ..._searchResults.map(
          (user) => ListTile(
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withOpacity(0.8),
                    const Color(0xFF8B5CF6).withOpacity(0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  user['name'].isNotEmpty ? user['name'][0] : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            title: Text(user['name']),
            subtitle: Text(user['username']),
            trailing: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: user['status'] == 'online' ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
            onTap: () => _openChat(user),
          ),
        ),
      ],
    );
  }
}

