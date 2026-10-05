
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/issue_service.dart';
import '../../services/location_service.dart';
import '../issue/issue_detail_screen.dart';

class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key});

  @override
  State<MyReportsScreen> createState() =>
      _MyReportsScreenState();
}

class _MyReportsScreenState
    extends State<MyReportsScreen> {
  late final IssueService _issueService;
  final LocationService _locationService =
      LocationService();

  static const String _baseUrl =
      'http://127.0.0.1:8000/api';

  List<Map<String, dynamic>> _issues = [];

  Map<String, dynamic> _reputation = {};

  /// Cache of issue-id → reverse-geocoded address
  final Map<int, String> _addressCache = {};

  bool _isLoading = true;

  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _issueService = IssueService(
      authProvider: context.read<AuthProvider>(),
    );

    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadMyReports(),
      _loadReputation(),
    ]);
  }

  Future<void> _loadMyReports() async {
    final authProvider =
        context.read<AuthProvider>();

    final accessToken = authProvider.accessToken;

    if (accessToken == null ||
        accessToken.isEmpty) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = 'You are not logged in.';
      });

      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final issues =
          await _issueService.getMyIssues(
        accessToken: accessToken,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _issues = issues;
        _isLoading = false;
      });

      // Start background address resolution
      _resolveAddresses(issues);
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = e
            .toString()
            .replaceFirst('Exception: ', '');
      });
    }
  }

  /// Resolve lat/lng → address for each issue in background.
  Future<void> _resolveAddresses(
    List<Map<String, dynamic>> issues,
  ) async {
    for (final issue in issues) {
      final id = issue['id'];
      if (id == null) continue;

      final idInt = id is int
          ? id
          : int.tryParse(id.toString());
      if (idInt == null) continue;

      if (_addressCache.containsKey(idInt)) {
        continue;
      }

      final lat = double.tryParse(
        issue['latitude']?.toString() ?? '',
      );

      final lng = double.tryParse(
        issue['longitude']?.toString() ?? '',
      );

      if (lat == null || lng == null) continue;

      final address =
          await _locationService.reverseGeocode(
        latitude: lat,
        longitude: lng,
      );

      if (!mounted) return;

      if (address != null) {
        setState(() {
          _addressCache[idInt] = address;
        });
      }
    }
  }

  Future<void> _loadReputation() async {
    try {
      final authProvider =
          context.read<AuthProvider>();

      final accessToken =
          authProvider.accessToken;

      if (accessToken == null ||
          accessToken.isEmpty) {
        return;
      }

      final dio = Dio(
        BaseOptions(
          baseUrl: _baseUrl,
          headers: {
            'Accept': 'application/json',
          },
        ),
      );

      Response<dynamic> response;

      try {
        response = await dio.get(
          '/users/me/reputation/',
          options: Options(
            headers: {
              'Authorization':
                  'Bearer $accessToken',
            },
          ),
        );
      } on DioException catch (e) {
        if (e.response?.statusCode != 401) {
          rethrow;
        }

        final refreshed = await authProvider
            .refreshAccessToken();

        if (!refreshed) {
          throw Exception(
            'Your session has expired. '
                'Please login again.',
          );
        }

        final newToken =
            authProvider.accessToken;

        if (newToken == null ||
            newToken.isEmpty) {
          throw Exception(
            'Unable to refresh access token.',
          );
        }

        response = await dio.get(
          '/users/me/reputation/',
          options: Options(
            headers: {
              'Authorization':
                  'Bearer $newToken',
            },
          ),
        );
      }

      if (!mounted) {
        return;
      }

      if (response.data is Map) {
        setState(() {
          _reputation =
              Map<String, dynamic>.from(
            response.data as Map,
          );
        });
      }
    } catch (_) {}
  }

  String _locationDisplay(
    Map<String, dynamic> issue,
  ) {
    final id = issue['id'];
    final idInt = id is int
        ? id
        : int.tryParse(id?.toString() ?? '');

    if (idInt != null &&
        _addressCache.containsKey(idInt)) {
      return _addressCache[idInt]!;
    }

    final lat = issue['latitude'];
    final lng = issue['longitude'];

    if (lat != null && lng != null) {
      // Show coords while resolving
      return '${double.tryParse(lat.toString())?.toStringAsFixed(5) ?? lat}, '
          '${double.tryParse(lng.toString())?.toStringAsFixed(5) ?? lng}';
    }

    return 'Unknown location';
  }

  // ============================================================
  // HELPER FORMATTERS
  // ============================================================

  String _categoryLabel(String? category) {
    switch (category) {
      case 'pothole':
        return 'Pothole';
      case 'streetlight':
        return 'Streetlight';
      case 'garbage':
        return 'Garbage';
      case 'water':
        return 'Water';
      case 'other':
        return 'Other';
      default:
        return category ?? 'Unknown';
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'reported':
        return 'Reported';
      case 'in_progress':
        return 'In Progress';
      case 'resolved':
        return 'Resolved';
      case 'closed':
        return 'Closed';
      default:
        return status ?? 'Unknown';
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'reported':
        return Colors.orange;
      case 'in_progress':
        return Colors.blue;
      case 'resolved':
        return Colors.green;
      case 'closed':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _severityLabel(String? severity) {
    if (severity == null || severity.isEmpty) {
      return 'Assessing...';
    }
    return severity[0].toUpperCase() +
        severity.substring(1);
  }

  Color _severityColor(String? severity) {
    switch (severity?.toLowerCase()) {
      case 'critical':
        return Colors.red.shade900;
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }


  String _formatDate(String? value) {
    if (value == null || value.isEmpty) {
      return '';
    }

    try {
      final date =
          DateTime.parse(value).toLocal();

      return '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year}';
    } catch (_) {
      return value;
    }
  }

  // ============================================================
  // STATS
  // ============================================================

  int _totalSubmitted() => _issues.length;

  int _resolvedCount() => _issues
      .where(
        (i) => i['status'] == 'resolved',
      )
      .length;

  int _pendingCount() => _issues
      .where(
        (i) =>
            i['status'] != 'resolved' &&
            i['status'] != 'closed',
      )
      .length;

  int _reputationScore() =>
      int.tryParse(
        _reputation['score']?.toString() ?? '50',
      ) ??
      50;

  String _reputationLevel() =>
      _reputation['level']?.toString() ?? 'normal';

  String _reputationLabel() {
    switch (_reputationLevel()) {
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

  IconData _reputationIcon() {
    switch (_reputationLevel()) {
      case 'low':
        return Icons.warning_amber_outlined;
      case 'trusted':
        return Icons.verified_outlined;
      case 'highly_trusted':
        return Icons.workspace_premium_outlined;
      default:
        return Icons.person_outline;
    }
  }

  Color _reputationColor() {
    switch (_reputationLevel()) {
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
    if (log is! List) return [];
    return log
        .whereType<Map>()
        .map(
          (item) => Map<String, dynamic>.from(item),
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

  // ============================================================
  // REPUTATION HISTORY SHEET
  // ============================================================

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
                          itemCount:
                              history.length,
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
                                        : Colors.red
                                            .shade100,
                                child: Icon(
                                  change >= 0
                                      ? Icons
                                          .arrow_upward
                                      : Icons
                                          .arrow_downward,
                                  color: change >= 0
                                      ? Colors.green
                                      : Colors.red,
                                ),
                              ),
                              title: Text(
                                _reasonLabel(
                                  reason,
                                ),
                              ),
                              subtitle: Text(
                                '${_formatTimestamp(item['timestamp']?.toString())}'
                                '${issueId != null ? '\nIssue #$issueId' : ''}',
                              ),
                              trailing: Text(
                                '${change >= 0 ? '+' : ''}$change',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight:
                                      FontWeight
                                          .bold,
                                  color: change >= 0
                                      ? Colors.green
                                      : Colors.red,
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

  // ============================================================
  // STAT CARD
  // ============================================================

  Widget _statCard(
    String title,
    String value,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey.shade100,
      ),
      child: Column(
        children: [
          Icon(icon, size: 24),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            style:
                const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DASHBOARD HEADER
  // ============================================================

  Widget _buildDashboardHeader() {
    final total = _totalSubmitted();
    final resolved = _resolvedCount();
    final pending = _pendingCount();
    final score = _reputationScore().clamp(0, 100);
    final reputationColor = _reputationColor();

    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Text(
                  'My Reports',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _statCard(
                        'Submitted',
                        total.toString(),
                        Icons.assignment_outlined,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _statCard(
                        'Resolved',
                        resolved.toString(),
                        Icons.check_circle_outline,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _statCard(
                        'Pending',
                        pending.toString(),
                        Icons.pending_outlined,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'My Reputation',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ),
                    Icon(
                      _reputationIcon(),
                      color: reputationColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _reputationLabel(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: reputationColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$score',
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding:
                          const EdgeInsets.only(
                        bottom: 7,
                      ),
                      child: Text(
                        '/ 100',
                        style: TextStyle(
                          color:
                              Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: score / 100,
                  minHeight: 8,
                  color: reputationColor,
                ),
                const SizedBox(height: 8),
                Text(
                  '$score / 100',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: _showHistory,
                  icon: const Icon(Icons.history),
                  label: const Text(
                    'My Reputation History',
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Submitted Issues',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        const SizedBox(height: 8),
      ],
    );
  }

  // ============================================================
  // ISSUE CARD — shows reverse-geocoded address + AI status
  // ============================================================

  Widget _buildIssueCard(
    Map<String, dynamic> issue,
  ) {
    final description =
        issue['original_description']?.toString() ??
            'No description';

    final category = issue['category']?.toString();
    final status = issue['status']?.toString();
    final severity = issue['ai_severity']?.toString();
    final aiCategory =
        issue['ai_suggested_category']?.toString();
    final upvotes = issue['upvote_count'] ?? 0;
    final createdAt = issue['created_at']?.toString();
    final photo = issue['photo']?.toString();
    final detectedLanguage =
        issue['detected_language']?.toString();
    final aiIsDuplicate = issue['ai_is_duplicate'];
    final translatedDescription =
        issue['translated_description']?.toString();

    // Reverse-geocoded address
    final locationText = _locationDisplay(issue);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (photo != null && photo.isNotEmpty)
            SizedBox(
              height: 180,
              width: double.infinity,
              child: Image.network(
                photo,
                fit: BoxFit.cover,
                errorBuilder:
                    (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey.shade200,
                    child: const Center(
                      child: Icon(
                        Icons
                            .broken_image_outlined,
                        size: 48,
                      ),
                    ),
                  );
                },
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                // ── Description ──
                Text(
                  description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                // ── English translation if non-English ──
                if (translatedDescription != null &&
                    translatedDescription.isNotEmpty &&
                    translatedDescription !=
                        description) ...[
                  const SizedBox(height: 4),
                  Text(
                    '🌐 $translatedDescription',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // ── Status + Category chips ──
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      avatar: Icon(
                        Icons.category_outlined,
                        size: 18,
                      ),
                      label: Text(
                        _categoryLabel(
                          aiCategory ?? category,
                        ),
                      ),
                      labelStyle:
                          const TextStyle(
                            fontSize: 12,
                          ),
                      padding: EdgeInsets.zero,
                    ),
                    Chip(
                      avatar: Icon(
                        Icons.flag_outlined,
                        size: 18,
                        color: _statusColor(status),
                      ),
                      label: Text(
                        _statusLabel(status),
                      ),
                      labelStyle:
                          const TextStyle(
                            fontSize: 12,
                          ),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // ── Severity ──
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_outlined,
                      size: 16,
                      color: _severityColor(severity),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Severity: ${_severityLabel(severity)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: _severityColor(
                          severity,
                        ),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),

                // ── Language ──
                if (detectedLanguage != null &&
                    detectedLanguage.isNotEmpty &&
                    detectedLanguage != 'en') ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.language,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Language detected: ${detectedLanguage.toUpperCase()}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],

                // ── Duplicate flag ──
                if (aiIsDuplicate == true) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius:
                          BorderRadius.circular(6),
                      border: Border.all(
                        color:
                            Colors.purple.shade200,
                      ),
                    ),
                    child: Text(
                      '🔁 AI flagged as possible duplicate',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.purple.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 8),

                // ── Location (reverse-geocoded) ──
                Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        locationText,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // ── Upvotes + Date ──
                Row(
                  children: [
                    const Icon(
                      Icons.thumb_up_outlined,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text('$upvotes upvotes'),
                    const Spacer(),
                    Text(
                      _formatDate(createdAt),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  Widget _buildReportList() {
    return Column(
      children: [
        for (final issue in _issues)
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => IssueDetailScreen(
                    issue: issue,
                  ),
                ),
              );
            },
            child: _buildIssueCard(issue),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 100),
          const Icon(
            Icons.error_outline,
            size: 64,
          ),
          const SizedBox(height: 16),
          const Text(
            'Unable to load your reports',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loadData,
            child: const Text('Retry'),
          ),
        ],
      );
    }

    if (_issues.isEmpty) {
      return ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _buildDashboardHeader(),
          const SizedBox(height: 40),
          const Icon(
            Icons.assignment_outlined,
            size: 72,
          ),
          const SizedBox(height: 16),
          const Text(
            'No reports yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Issues you report will appear here.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _buildDashboardHeader(),
        _buildReportList(),
      ],
    );
  }
}
