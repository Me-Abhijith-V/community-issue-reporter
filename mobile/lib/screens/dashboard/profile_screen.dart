import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() =>
      _ProfileScreenState();
}

class _ProfileScreenState
    extends State<ProfileScreen> {
  static const String baseUrl =
      'http://127.0.0.1:8000/api';

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      headers: {
        'Accept': 'application/json',
      },
    ),
  );

  bool _isLoading = true;
  String? _error;

  Map<String, dynamic> _profile = {};
  Map<String, dynamic> _reputation = {};

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback(
          (_) {
        _loadProfile();
      },
    );
  }

  Future<Response<dynamic>> _requestWithRefresh({
    required Future<Response<dynamic>> Function(
        String token,
        )
    request,
  }) async {
    final authProvider =
    context.read<AuthProvider>();

    String? token = authProvider.accessToken;

    if (token == null || token.isEmpty) {
      throw Exception(
        'You are not logged in.',
      );
    }

    try {
      return await request(token);
    } on DioException catch (e) {
      if (e.response?.statusCode != 401) {
        rethrow;
      }

      final refreshed =
      await authProvider.refreshAccessToken();

      if (!refreshed) {
        throw Exception(
          'Your session has expired. Please login again.',
        );
      }

      token = authProvider.accessToken;

      if (token == null || token.isEmpty) {
        throw Exception(
          'Unable to refresh access token.',
        );
      }

      return await request(token);
    }
  }

  Future<void> _loadProfile() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final profileResponse =
      await _requestWithRefresh(
        request: (token) {
          return _dio.get(
            '/auth/me/',
            options: Options(
              headers: {
                'Authorization': 'Bearer $token',
              },
            ),
          );
        },
      );

      final reputationResponse =
      await _requestWithRefresh(
        request: (token) {
          return _dio.get(
            '/users/me/reputation/',
            options: Options(
              headers: {
                'Authorization': 'Bearer $token',
              },
            ),
          );
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        if (profileResponse.data is Map) {
          _profile =
          Map<String, dynamic>.from(
            profileResponse.data,
          );
        }

        if (reputationResponse.data is Map) {
          _reputation =
          Map<String, dynamic>.from(
            reputationResponse.data,
          );
        }

        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  String _displayName() {
    final fullName =
    _profile['full_name']?.toString();

    if (fullName != null &&
        fullName.trim().isNotEmpty) {
      return fullName;
    }

    final name =
    _profile['name']?.toString();

    if (name != null &&
        name.trim().isNotEmpty) {
      return name;
    }

    return 'Citizen';
  }

  String _email() {
    return _profile['email']?.toString() ??
        'Not available';
  }

  String _language() {
    final language =
    _profile['preferred_language']
        ?.toString();

    if (language == null ||
        language.isEmpty) {
      return 'English';
    }

    switch (language) {
      case 'en':
        return 'English';
      case 'ml':
        return 'Malayalam';
      case 'ta':
        return 'Tamil';
      case 'te':
        return 'Telugu';
      case 'kn':
        return 'Kannada';
      case 'hi':
        return 'Hindi';
      default:
        return language.toUpperCase();
    }
  }

  int _score() {
    return int.tryParse(
      _reputation['score']?.toString() ??
          _profile['reputation_score']
              ?.toString() ??
          '0',
    ) ??
        0;
  }

  String _level() {
    return _reputation['level']
        ?.toString() ??
        _profile['reputation_level']
            ?.toString() ??
        'normal';
  }

  String _levelLabel() {
    switch (_level()) {
      case 'low':
        return 'Low Trust';
      case 'trusted':
        return 'Trusted Citizen';
      case 'highly_trusted':
        return 'Highly Trusted';
      default:
        return 'Normal';
    }
  }

  IconData _levelIcon() {
    switch (_level()) {
      case 'low':
        return Icons.warning_amber;
      case 'trusted':
        return Icons.verified;
      case 'highly_trusted':
        return Icons.workspace_premium;
      default:
        return Icons.person;
    }
  }

  Color _levelColor() {
    switch (_level()) {
      case 'low':
        return Colors.grey;
      case 'trusted':
        return Colors.blue;
      case 'highly_trusted':
        return Colors.amber.shade700;
      default:
        return Colors.blueGrey;
    }
  }

  List<Map<String, dynamic>> _history() {
    final log = _reputation['log'];

    if (log is! List) {
      return [];
    }

    return log
        .whereType<Map>()
        .map(
          (item) =>
      Map<String, dynamic>.from(item),
    )
        .toList();
  }

  String _reasonLabel(String reason) {
    switch (reason) {
      case 'submitted':
        return 'Report submitted';
      case 'resolved':
        return 'Report resolved';
      case 'upvoted_5':
        return 'Report received 5 upvotes';
      case 'invalid':
        return 'Report marked invalid';
      case 'fake':
        return 'Report marked fake';
      case 'account_created':
        return 'Account created';
      default:
        return reason;
    }
  }

  String _formatTimestamp(String? value) {
    if (value == null || value.isEmpty) {
      return '';
    }

    try {
      final date =
      DateTime.parse(value).toLocal();

      return '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year} '
          '${date.hour.toString().padLeft(2, '0')}:'
          '${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return value;
    }
  }

  void _showHistory() {
    final history = _history();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height:
            MediaQuery.of(context).size.height *
                0.75,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'My Reputation History',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: history.isEmpty
                      ? const Center(
                    child: Text(
                      'No reputation history yet.',
                    ),
                  )
                      : ListView.separated(
                    padding:
                    const EdgeInsets.all(
                      16,
                    ),
                    itemCount: history.length,
                    separatorBuilder:
                        (_, _) =>
                    const Divider(),
                    itemBuilder:
                        (context, index) {
                      final item =
                      history[index];

                      final change =
                          int.tryParse(
                            item['change']
                                ?.toString() ??
                                '0',
                          ) ??
                              0;

                      final reason =
                          item['reason']
                              ?.toString() ??
                              '';

                      final issueId =
                      item['issue_id'];

                      return ListTile(
                        contentPadding:
                        EdgeInsets.zero,
                        leading:
                        CircleAvatar(
                          backgroundColor:
                          change >= 0
                              ? Colors
                              .green
                              .shade100
                              : Colors
                              .red
                              .shade100,
                          child: Icon(
                            change >= 0
                                ? Icons
                                .arrow_upward
                                : Icons
                                .arrow_downward,
                            color:
                            change >= 0
                                ? Colors
                                .green
                                : Colors
                                .red,
                          ),
                        ),
                        title: Text(
                          _reasonLabel(
                            reason,
                          ),
                        ),
                        subtitle: Text(
                          '${_formatTimestamp(
                            item['timestamp']
                                ?.toString(),
                          )}'
                              '${issueId != null ? '\nIssue #$issueId' : ''}',
                        ),
                        trailing: Text(
                          '${change >= 0 ? '+' : ''}$change',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight:
                            FontWeight.bold,
                            color:
                            change >= 0
                                ? Colors
                                .green
                                : Colors
                                .red,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _logout() async {
    await context
        .read<AuthProvider>()
        .logout();

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushNamedAndRemoveUntil(
      '/login',
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.red,
              ),
              const SizedBox(height: 12),
              const Text(
                'Unable to load profile.',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadProfile,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final score = _score();
    final levelColor = _levelColor();
    final history = _history();

    return RefreshIndicator(
      onRefresh: _loadProfile,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: CircleAvatar(
              radius: 42,
              child: Text(
                _displayName()
                    .isNotEmpty
                    ? _displayName()[0]
                    .toUpperCase()
                    : 'C',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          Center(
            child: Text(
              _displayName(),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(height: 4),

          Center(
            child: Text(
              _email(),
              style: TextStyle(
                color: Colors.grey.shade600,
              ),
            ),
          ),

          const SizedBox(height: 20),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Reputation',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Text(
                        '$score',
                        style: const TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              _levelIcon(),
                              color: levelColor,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _levelLabel(),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight:
                                  FontWeight.bold,
                                  color: levelColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  LinearProgressIndicator(
                    value:
                    (score.clamp(0, 100)) /
                        100,
                    minHeight: 8,
                  ),

                  const SizedBox(height: 8),

                  Text(
                    '$score / 100',
                    style: TextStyle(
                      color:
                      Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.language,
                  ),
                  title: const Text(
                    'Preferred Language',
                  ),
                  subtitle: Text(
                    _language(),
                  ),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.history,
                  ),
                  title: const Text(
                    'My Reputation History',
                  ),
                  subtitle: Text(
                    '${history.length} reputation record'
                        '${history.length == 1 ? '' : 's'}',
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                  ),
                  onTap: _showHistory,
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          Card(
            child: ListTile(
              leading: Icon(
                Icons.logout,
                color: Colors.red.shade700,
              ),
              title: const Text('Logout'),
              onTap: _logout,
            ),
          ),
        ],
      ),
    );
  }
}