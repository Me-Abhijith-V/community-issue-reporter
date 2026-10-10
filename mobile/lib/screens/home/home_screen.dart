import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/issue_service.dart';
import '../../services/location_service.dart';
import '../issue/issue_detail_screen.dart';

double _distanceInKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
    ) {
  const earthRadius = 6371.0;

  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;

  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
          math.cos(lat1 * math.pi / 180) *
              math.cos(lat2 * math.pi / 180) *
              math.sin(dLon / 2) *
              math.sin(dLon / 2);

  final c = 2 * math.atan2(
    math.sqrt(a),
    math.sqrt(1 - a),
  );

  return earthRadius * c;
}

String _timeAgo(String value) {
  final date = DateTime.tryParse(value);

  if (date == null) {
    return '';
  }

  final difference = DateTime.now().toUtc().difference(
    date.toUtc(),
  );

  if (difference.isNegative) {
    return 'Just now';
  }

  if (difference.inMinutes < 1) {
    return 'Just now';
  }

  if (difference.inHours < 1) {
    return '${difference.inMinutes}m ago';
  }

  if (difference.inDays < 1) {
    return '${difference.inHours}h ago';
  }

  if (difference.inDays < 30) {
    return '${difference.inDays}d ago';
  }

  if (difference.inDays < 365) {
    return '${difference.inDays ~/ 30}mo ago';
  }

  return '${difference.inDays ~/ 365}y ago';
}

class HomeScreen extends StatefulWidget {
  final VoidCallback onReportPressed;

  const HomeScreen({
    super.key,
    required this.onReportPressed,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final IssueService _issueService;

  final LocationService _locationService = LocationService();

  bool _isLoading = true;
  String? _errorMessage;

  List<Map<String, dynamic>> _issues = [];
  List<Map<String, dynamic>> _myIssues = [];

  double? _currentLatitude;
  double? _currentLongitude;

  bool _isLoadingLocation = false;

  @override
  void initState() {
    super.initState();

    _issueService = IssueService(
      authProvider: context.read<AuthProvider>(),
    );

    _loadHomeData();
  }

  Future<void> _loadHomeData() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authProvider = context.read<AuthProvider>();

      final accessToken = authProvider.accessToken;

      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('You are not logged in.');
      }

      await _loadCurrentLocation();

      // Fetch nearby issues (within 5 km) when GPS available,
      // otherwise fall back to all issues
      Future<List<Map<String, dynamic>>> issuesFuture;

      if (_currentLatitude != null && _currentLongitude != null) {
        issuesFuture = _issueService.getNearbyIssues(
          latitude: _currentLatitude!,
          longitude: _currentLongitude!,
          radiusKm: 5.0,
        );
      } else {
        issuesFuture = _issueService.getAllIssues(
          accessToken: accessToken,
        );
      }

      final results = await Future.wait([
        issuesFuture,
        _issueService.getMyIssues(
          accessToken: accessToken,
        ),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _issues = results[0];
        _myIssues = results[1];
        _isLoading = false;
      });
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

  Future<void> _loadCurrentLocation() async {
    if (_isLoadingLocation) {
      return;
    }

    _isLoadingLocation = true;

    try {
      final position =
      await _locationService.getCurrentLocation();

      if (!mounted) {
        return;
      }

      setState(() {
        _currentLatitude = position.latitude;
        _currentLongitude = position.longitude;
      });
    } catch (e) {
      debugPrint(
        'Home location unavailable: $e',
      );
    } finally {
      _isLoadingLocation = false;
    }
  }

  int get _resolvedCount {
    return _issues.where((issue) {
      return issue['status']?.toString().toLowerCase() ==
          'resolved';
    }).length;
  }

  int get _openCount {
    return _issues.where((issue) {
      final status =
      issue['status']?.toString().toLowerCase();

      return status != 'resolved' &&
          status != 'closed';
    }).length;
  }

  int get _myUpvotes {
    int total = 0;

    for (final issue in _myIssues) {
      final value = issue['upvote_count'];

      if (value is int) {
        total += value;
      } else if (value is num) {
        total += value.toInt();
      } else {
        total += int.tryParse(
          value?.toString() ?? '',
        ) ??
            0;
      }
    }

    return total;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadHomeData,
      child: SingleChildScrollView(
        physics:
        const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            const Text(
              'Welcome back!',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 6),

            Text(
              'Help make your community better.',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),

            const SizedBox(height: 24),

            // Report Issue Card
            InkWell(
              onTap: widget.onReportPressed,
              borderRadius:
              BorderRadius.circular(12),
              child: Card(
                elevation: 2,
                child: Padding(
                  padding:
                  const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        padding:
                        const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color:
                          Colors.blue.shade50,
                          borderRadius:
                          BorderRadius.circular(
                            14,
                          ),
                        ),
                        child: Icon(
                          Icons.campaign,
                          size: 32,
                          color:
                          Colors.blue.shade700,
                        ),
                      ),

                      const SizedBox(width: 16),

                      const Expanded(
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Report a Community Issue',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight:
                                FontWeight.bold,
                              ),
                            ),

                            SizedBox(height: 5),

                            Text(
                              'Report potholes, garbage, damaged roads and other problems.',
                              style: TextStyle(
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 8),

                      const Icon(
                        Icons.arrow_forward_ios,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              'Quick Overview',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child:
                  CircularProgressIndicator(),
                ),
              )
            else if (_errorMessage != null)
              _ErrorCard(
                message: _errorMessage!,
                onRetry: _loadHomeData,
              )
            else ...[
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        title: 'My Reports',
                        value:
                        _myIssues.length.toString(),
                        icon: Icons.assignment,
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: _StatCard(
                        title: 'Resolved',
                        value:
                        _resolvedCount.toString(),
                        icon: Icons.check_circle,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        title: 'Upvotes',
                        value:
                        _myUpvotes.toString(),
                        icon: Icons.thumb_up,
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: _StatCard(
                        title: 'Open Issues',
                        value:
                        _openCount.toString(),
                        icon:
                        Icons.pending_actions,
                      ),
                    ),
                  ],
                ),
              ],

            const SizedBox(height: 28),

            Row(
              mainAxisAlignment:
              MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Nearby Issues',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                if (_currentLatitude != null &&
                    _currentLongitude != null)
                  Text(
                    'Near you',
                    style: TextStyle(
                      fontSize: 12,
                      color:
                      Colors.grey.shade600,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            if (_isLoading)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child:
                    CircularProgressIndicator(),
                  ),
                ),
              )
            else if (_issues.isEmpty)
              const _EmptyIssuesCard()
            else
              ..._buildIssueCards(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildIssueCards() {
    final issuesToShow =
    _issues.take(5).toList();

    return issuesToShow.map((issue) {
      return Padding(
        padding:
        const EdgeInsets.only(bottom: 12),
        child: _HomeIssueCard(
          issue: issue,
          issueService: _issueService,
          currentLatitude: _currentLatitude,
          currentLongitude: _currentLongitude,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    IssueDetailScreen(
                      issue: issue,
                    ),
              ),
            );
          },
        ),
      );
    }).toList();
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 28,
              color: Colors.blue,
            ),

            const SizedBox(height: 12),

            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 4),

            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeIssueCard extends StatefulWidget {
  final Map<String, dynamic> issue;
  final VoidCallback onTap;
  final IssueService issueService;

  final double? currentLatitude;
  final double? currentLongitude;

  const _HomeIssueCard({
    required this.issue,
    required this.onTap,
    required this.issueService,
    required this.currentLatitude,
    required this.currentLongitude,
  });

  @override
  State<_HomeIssueCard> createState() =>
      _HomeIssueCardState();
}

class _HomeIssueCardState
    extends State<_HomeIssueCard> {
  late int _upvoteCount;

  bool _isUpvoting = false;
  bool _hasUpvoted = false;

  @override
  void initState() {
    super.initState();

    final value =
    widget.issue['upvote_count'];

    if (value is int) {
      _upvoteCount = value;
    } else if (value is num) {
      _upvoteCount = value.toInt();
    } else {
      _upvoteCount =
          int.tryParse(
            value?.toString() ?? '',
          ) ??
              0;
    }

    // If the backend eventually provides
    // "upvoted", restore that state here.
    if (widget.issue['upvoted'] == true) {
      _hasUpvoted = true;
    }
  }

  Future<void> _upvoteIssue() async {
    if (_isUpvoting) {
      return;
    }

    setState(() {
      _isUpvoting = true;
    });

    try {
      final issueId =
      int.tryParse(
        widget.issue['id'].toString(),
      );

      if (issueId == null) {
        throw Exception(
          'Invalid issue ID.',
        );
      }

      final response =
      await widget.issueService.upvoteIssue(
        issueId: issueId,
      );

      if (!mounted) {
        return;
      }

      final value =
      response['upvote_count'];

      final count = value is int
          ? value
          : value is num
          ? value.toInt()
          : int.tryParse(
        value?.toString() ?? '',
      ) ??
          _upvoteCount;

      final upvoted =
          response['upvoted'] == true;

      setState(() {
        _upvoteCount = count;
        _hasUpvoted = upvoted;
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            upvoted
                ? 'Issue upvoted.'
                : 'Upvote removed.',
          ),
          duration:
          const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst(
              'Exception: ',
              '',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpvoting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final category =
        widget.issue['category']
            ?.toString() ??
            'other';

    final status =
        widget.issue['status']
            ?.toString() ??
            'reported';

    final description =
        widget.issue[
        'original_description']
            ?.toString() ??
            'Community issue';

    final severity =
    widget.issue['ai_severity']
        ?.toString();

    final createdAt =
        widget.issue['created_at']
            ?.toString() ??
            '';

    final reporterName =
    widget.issue['reporter_name']
        ?.toString();

    final reporterEmail =
    widget.issue['reporter_email']
        ?.toString();

    final reporter =
    reporterName != null &&
        reporterName.trim().isNotEmpty
        ? reporterName
        : reporterEmail != null &&
        reporterEmail
            .trim()
            .isNotEmpty
        ? reporterEmail
        : 'Community member';

    final distance =
    _getDistance();

    final timeAgo =
    _timeAgo(createdAt);

    final rawAddress = widget.issue['address']?.toString().trim();
    final address = (rawAddress != null && rawAddress.isNotEmpty) ? rawAddress : null;

    return Card(
      elevation: 1,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius:
        BorderRadius.circular(12),
        child: Padding(
          padding:
          const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                    const EdgeInsets.all(10),
                    decoration:
                    BoxDecoration(
                      color:
                      Colors.blue.shade50,
                      borderRadius:
                      BorderRadius.circular(
                        10,
                      ),
                    ),
                    child: Icon(
                      _categoryIcon(category),
                      color:
                      Colors.blue.shade700,
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatCategory(
                            category,
                          ),
                          style:
                          const TextStyle(
                            fontWeight:
                            FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),

                        const SizedBox(height: 5),

                        Text(
                          description,
                          maxLines: 2,
                          overflow:
                          TextOverflow
                              .ellipsis,
                          style: TextStyle(
                            color: Colors
                                .grey
                                .shade700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _StatusBadge(
                    text:
                    _formatStatus(status),
                    status: status,
                  ),

                  if (severity != null &&
                      severity.isNotEmpty)
                    _SeverityBadge(
                      text:
                      _formatStatus(
                        severity,
                      ),
                      severity: severity,
                    ),
                ],
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 16,
                    color:
                    Colors.grey.shade600,
                  ),

                  const SizedBox(width: 4),

                  Expanded(
                    child: Text(
                      reporter,
                      maxLines: 1,
                      overflow:
                      TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color:
                        Colors.grey.shade600,
                      ),
                    ),
                  ),

                  if (timeAgo.isNotEmpty) ...[
                    Icon(
                      Icons.access_time,
                      size: 15,
                      color:
                      Colors.grey.shade600,
                    ),

                    const SizedBox(width: 4),

                    Text(
                      timeAgo,
                      style: TextStyle(
                        fontSize: 12,
                        color:
                        Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),

              if (address != null || distance != null) ...[
                const SizedBox(height: 6),

                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color:
                      Colors.grey.shade600,
                    ),

                    const SizedBox(width: 4),

                    Expanded(
                      child: Text(
                        address != null && distance != null
                            ? '$address • ${_formatDistance(distance)}'
                            : (address ?? _formatDistance(distance!)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color:
                          Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 10),

              const Divider(height: 1),

              const SizedBox(height: 6),

              Row(
                children: [
                  Icon(
                    _hasUpvoted
                        ? Icons.thumb_up
                        : Icons.thumb_up_outlined,
                    size: 18,
                    color: _hasUpvoted
                        ? Colors.blue
                        : Colors.grey.shade700,
                  ),

                  const SizedBox(width: 5),

                  Text(
                    '$_upvoteCount',
                    style:
                    const TextStyle(
                      fontWeight:
                      FontWeight.w600,
                    ),
                  ),

                  const SizedBox(width: 8),

                  Text(
                    _upvoteCount == 1
                        ? 'upvote'
                        : 'upvotes',
                    style: TextStyle(
                      fontSize: 12,
                      color:
                      Colors.grey.shade600,
                    ),
                  ),

                  const Spacer(),

                  if (_isUpvoting)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child:
                      CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  else
                    TextButton.icon(
                      onPressed:
                      _upvoteIssue,
                      icon: Icon(
                        _hasUpvoted
                            ? Icons.thumb_up
                            : Icons
                            .thumb_up_outlined,
                        size: 16,
                      ),
                      label: Text(
                        _hasUpvoted
                            ? 'Remove Upvote'
                            : 'Upvote',
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  double? _getDistance() {
    if (widget.currentLatitude ==
        null ||
        widget.currentLongitude ==
            null) {
      return null;
    }

    final latitude =
    double.tryParse(
      widget.issue['latitude']
          ?.toString() ??
          '',
    );

    final longitude =
    double.tryParse(
      widget.issue['longitude']
          ?.toString() ??
          '',
    );

    if (latitude == null ||
        longitude == null) {
      return null;
    }

    return _distanceInKm(
      widget.currentLatitude!,
      widget.currentLongitude!,
      latitude,
      longitude,
    );
  }

  String _formatDistance(double km) {
    if (km < 1) {
      final meters =
      (km * 1000).round();

      return '$meters m away';
    }

    return '${km.toStringAsFixed(1)} km away';
  }

  IconData _categoryIcon(
      String category,
      ) {
    switch (category.toLowerCase()) {
      case 'pothole':
        return Icons.warning_amber_rounded;

      case 'streetlight':
        return Icons.lightbulb_outline;

      case 'garbage':
        return Icons.delete_outline;

      case 'water':
        return Icons.water_drop_outlined;

      default:
        return Icons
            .report_problem_outlined;
    }
  }

  String _formatCategory(String value) {
    if (value.isEmpty) {
      return value;
    }

    return value
        .split('_')
        .map(
          (word) => word.isEmpty
          ? word
          : word[0].toUpperCase() +
          word.substring(1),
    )
        .join(' ');
  }

  String _formatStatus(String value) {
    return _formatCategory(value);
  }
}

class _StatusBadge extends StatelessWidget {
  final String text;
  final String status;

  const _StatusBadge({
    required this.text,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final normalized =
    status.toLowerCase();

    Color backgroundColor;
    Color foregroundColor;

    switch (normalized) {
      case 'reported':
        backgroundColor =
            Colors.orange.shade50;
        foregroundColor =
            Colors.orange.shade800;
        break;

      case 'in_progress':
        backgroundColor =
            Colors.blue.shade50;
        foregroundColor =
            Colors.blue.shade800;
        break;

      case 'resolved':
        backgroundColor =
            Colors.green.shade50;
        foregroundColor =
            Colors.green.shade800;
        break;

      case 'closed':
        backgroundColor =
            Colors.grey.shade200;
        foregroundColor =
            Colors.grey.shade800;
        break;

      default:
        backgroundColor =
            Colors.grey.shade100;
        foregroundColor =
            Colors.grey.shade800;
    }

    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius:
        BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight:
          FontWeight.w600,
          color: foregroundColor,
        ),
      ),
    );
  }
}

class _SeverityBadge extends StatelessWidget {
  final String text;
  final String severity;

  const _SeverityBadge({
    required this.text,
    required this.severity,
  });

  @override
  Widget build(BuildContext context) {
    final normalized =
    severity.toLowerCase();

    Color backgroundColor;
    Color foregroundColor;

    switch (normalized) {
      case 'low':
        backgroundColor =
            Colors.green.shade50;
        foregroundColor =
            Colors.green.shade800;
        break;

      case 'medium':
        backgroundColor =
            Colors.orange.shade50;
        foregroundColor =
            Colors.orange.shade800;
        break;

      case 'high':
        backgroundColor =
            Colors.deepOrange.shade50;
        foregroundColor =
            Colors.deepOrange.shade800;
        break;

      case 'critical':
        backgroundColor =
            Colors.red.shade50;
        foregroundColor =
            Colors.red.shade800;
        break;

      default:
        backgroundColor =
            Colors.grey.shade100;
        foregroundColor =
            Colors.grey.shade800;
    }

    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius:
        BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight:
          FontWeight.w600,
          color: foregroundColor,
        ),
      ),
    );
  }
}

class _EmptyIssuesCard
    extends StatelessWidget {
  const _EmptyIssuesCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding:
        const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.location_on_outlined,
              size: 48,
              color: Colors.grey.shade500,
            ),

            const SizedBox(height: 10),

            const Text(
              'No community issues yet.',
              style: TextStyle(
                fontSize: 15,
                fontWeight:
                FontWeight.w500,
              ),
            ),

            const SizedBox(height: 5),

            Text(
              'Reported issues will appear here.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard
    extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding:
        const EdgeInsets.all(16),
        child: Column(
          children: [
            const Icon(
              Icons.error_outline,
              size: 40,
            ),

            const SizedBox(height: 8),

            Text(
              message,
              textAlign:
              TextAlign.center,
            ),

            const SizedBox(height: 12),

            OutlinedButton(
              onPressed: onRetry,
              child:
              const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}