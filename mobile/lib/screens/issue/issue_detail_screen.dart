import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/status_update_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/issue_service.dart';
import '../../widgets/status_timeline.dart';

class IssueDetailScreen extends StatefulWidget {
  final Map<String, dynamic> issue;

  const IssueDetailScreen({
    super.key,
    required this.issue,
  });

  @override
  State<IssueDetailScreen> createState() =>
      _IssueDetailScreenState();
}

class _IssueDetailScreenState
    extends State<IssueDetailScreen> {
  late final IssueService _issueService;

  late Future<List<StatusUpdateModel>>
  _statusHistoryFuture;

  Map<String, dynamic> _issue = {};

  bool _isLoadingIssue = true;
  String? _issueLoadError;

  @override
  void initState() {
    super.initState();

    _issueService = IssueService(
      authProvider: context.read<AuthProvider>(),
    );

    // Initially use the issue supplied by the caller.
    // This allows the screen to display immediately.
    _issue = Map<String, dynamic>.from(
      widget.issue,
    );

    final issueId = int.tryParse(
      widget.issue['id'].toString(),
    );

    if (issueId != null) {
      _statusHistoryFuture =
          _issueService.getStatusHistory(
            issueId: issueId,
          );

      // Fetch the complete issue.
      // This is important when opening from the map,
      // because the map endpoint returns lightweight data.
      _loadFullIssue(issueId);
    } else {
      _statusHistoryFuture = Future.error(
        Exception('Invalid issue ID.'),
      );

      _isLoadingIssue = false;
      _issueLoadError = 'Invalid issue ID.';
    }
  }

  // ============================================================
  // LOAD COMPLETE ISSUE
  // ============================================================

  Future<void> _loadFullIssue(int issueId) async {
    try {
      final fullIssue =
      await _issueService.getIssueById(
        issueId: issueId,
      );

      if (!mounted) return;

      setState(() {
        _issue = fullIssue;
        _isLoadingIssue = false;
        _issueLoadError = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoadingIssue = false;
        _issueLoadError = e
            .toString()
            .replaceFirst(
          'Exception: ',
          '',
        );
      });
    }
  }

  // ============================================================
  // STATUS
  // ============================================================

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
        return Colors.blueGrey;
    }
  }

  // ============================================================
  // LOCATION
  // ============================================================

  String _locationText() {
    final latitude = _issue['latitude'];
    final longitude = _issue['longitude'];

    if (latitude == null ||
        longitude == null) {
      return 'Location unavailable';
    }

    return '$latitude, $longitude';
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final issue = _issue;

    final status =
    issue['status']?.toString();

    final category =
        issue['category']?.toString() ??
            'other';

    final description =
        issue['original_description']
            ?.toString() ??
            '';

    final translatedDescription =
        issue['translated_description']
            ?.toString() ??
            '';

    final photo =
    issue['photo']?.toString();

    final severity =
        issue['ai_severity']?.toString() ??
            '';

    final aiCategory =
        issue['ai_suggested_category']
            ?.toString() ??
            '';

    final isDuplicate =
        issue['ai_is_duplicate'] == true;

    final upvoteCount =
        int.tryParse(
          issue['upvote_count']
              ?.toString() ??
              '0',
        ) ??
            0;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Issue #${issue['id'] ?? ''}',
        ),
      ),

      body: Stack(
        children: [
          SingleChildScrollView(
            padding:
            const EdgeInsets.all(16),

            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,

              children: [
                // ==================================================
                // PHOTO
                // ==================================================

                if (photo != null &&
                    photo.isNotEmpty)
                  ClipRRect(
                    borderRadius:
                    BorderRadius.circular(12),

                    child: Image.network(
                      photo,
                      width:
                      double.infinity,
                      height: 220,
                      fit: BoxFit.cover,

                      errorBuilder:
                          (
                          context,
                          error,
                          stackTrace,
                          ) {
                        return Container(
                          height: 220,
                          width:
                          double.infinity,
                          color:
                          Colors.grey.shade200,
                          child:
                          const Center(
                            child: Icon(
                              Icons
                                  .broken_image,
                              size: 50,
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                // Show a useful message if map data
                // did not contain a photo and the
                // full issue request failed.
                if (!_isLoadingIssue &&
                    photo == null &&
                    _issueLoadError != null)
                  Container(
                    width:
                    double.infinity,
                    height: 180,
                    decoration:
                    BoxDecoration(
                      color:
                      Colors.grey.shade200,
                      borderRadius:
                      BorderRadius.circular(
                        12,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment:
                      MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons
                              .image_not_supported,
                          size: 50,
                          color:
                          Colors.grey.shade600,
                        ),
                        const SizedBox(
                          height: 8,
                        ),
                        Text(
                          'Unable to load issue image',
                          style: TextStyle(
                            color:
                            Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),

                // ==================================================
                // STATUS + CATEGORY
                // ==================================================

                Row(
                  children: [
                    Expanded(
                      child: _InfoCard(
                        title: 'Status',
                        value:
                        _statusLabel(
                          status,
                        ),
                        icon:
                        Icons.flag,
                        color:
                        _statusColor(
                          status,
                        ),
                      ),
                    ),

                    const SizedBox(
                      width: 12,
                    ),

                    Expanded(
                      child: _InfoCard(
                        title: 'Category',
                        value: category,
                        icon:
                        Icons.category,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ==================================================
                // AI SEVERITY
                // ==================================================

                if (severity.isNotEmpty)
                  _InfoCard(
                    title:
                    'AI Severity',
                    value: severity,
                    icon:
                    Icons.warning_amber,
                  ),

                const SizedBox(height: 16),

                // ==================================================
                // DESCRIPTION
                // ==================================================

                _DetailCard(
                  title: 'Description',
                  child: Text(
                    description.isEmpty
                        ? 'No description available.'
                        : description,
                    style:
                    const TextStyle(
                      fontSize: 15,
                    ),
                  ),
                ),

                // ==================================================
                // TRANSLATED DESCRIPTION
                // ==================================================

                if (translatedDescription
                    .isNotEmpty &&
                    translatedDescription !=
                        description) ...[
                  const SizedBox(
                    height: 12,
                  ),

                  _DetailCard(
                    title:
                    'Translated Description',
                    child: Text(
                      translatedDescription,
                      style:
                      const TextStyle(
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // ==================================================
                // LOCATION
                // ==================================================

                _DetailCard(
                  title: 'Location',
                  child: Row(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 20,
                      ),

                      const SizedBox(
                        width: 8,
                      ),

                      Expanded(
                        child: Text(
                          _locationText(),
                          style:
                          const TextStyle(
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ==================================================
                // AI CATEGORY
                // ==================================================

                if (aiCategory.isNotEmpty)
                  _DetailCard(
                    title:
                    'AI Suggested Category',
                    child: Text(
                      aiCategory,
                      style:
                      const TextStyle(
                        fontSize: 15,
                      ),
                    ),
                  ),

                const SizedBox(height: 12),

                // ==================================================
                // COMMUNITY ACTIVITY
                // ==================================================

                _DetailCard(
                  title:
                  'Community Activity',
                  child: Row(
                    children: [
                      const Icon(
                        Icons.thumb_up,
                      ),

                      const SizedBox(
                        width: 8,
                      ),

                      Text(
                        '$upvoteCount upvote'
                            '${upvoteCount == 1 ? '' : 's'}',
                        style:
                        const TextStyle(
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),

                // ==================================================
                // DUPLICATE
                // ==================================================

                if (isDuplicate) ...[
                  const SizedBox(
                    height: 12,
                  ),

                  _DetailCard(
                    title:
                    'Duplicate Issue',
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning,
                          color: Colors
                              .orange
                              .shade700,
                        ),

                        const SizedBox(
                          width: 8,
                        ),

                        const Expanded(
                          child: Text(
                            'This issue has been '
                                'identified as a possible '
                                'duplicate.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // ==================================================
                // STATUS HISTORY
                // ==================================================

                const Text(
                  'Status History',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight:
                    FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 12),

                FutureBuilder<
                    List<
                        StatusUpdateModel>>(
                  future:
                  _statusHistoryFuture,

                  builder: (
                      context,
                      snapshot,
                      ) {
                    if (snapshot
                        .connectionState ==
                        ConnectionState
                            .waiting) {
                      return const Card(
                        child:
                        Padding(
                          padding:
                          EdgeInsets.all(
                            20,
                          ),
                          child: Center(
                            child:
                            CircularProgressIndicator(),
                          ),
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return Card(
                        child: Padding(
                          padding:
                          const EdgeInsets
                              .all(
                            16,
                          ),
                          child: Row(
                            crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                            children: [
                              Icon(
                                Icons
                                    .error_outline,
                                color: Colors
                                    .red
                                    .shade700,
                              ),

                              const SizedBox(
                                width: 10,
                              ),

                              Expanded(
                                child: Text(
                                  'Unable to load '
                                      'status history.\n'
                                      '${snapshot.error}',
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final updates =
                        snapshot.data ??
                            [];

                    return StatusTimeline(
                      updates: updates,
                    );
                  },
                ),

                const SizedBox(
                  height: 24,
                ),
              ],
            ),
          ),

          // ========================================================
          // LOADING COMPLETE ISSUE
          // ========================================================

          if (_isLoadingIssue)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                minHeight: 3,
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// INFO CARD
// ============================================================

class _InfoCard
    extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color? color;

  const _InfoCard({
    required this.title,
    required this.value,
    required this.icon,
    this.color,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Card(
      child: Padding(
        padding:
        const EdgeInsets.all(14),

        child: Row(
          crossAxisAlignment:
          CrossAxisAlignment.start,

          children: [
            Icon(
              icon,
              color: color,
            ),

            const SizedBox(
              width: 10,
            ),

            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,

                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors
                          .grey
                          .shade600,
                    ),
                  ),

                  const SizedBox(
                    height: 4,
                  ),

                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight:
                      FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// DETAIL CARD
// ============================================================

class _DetailCard
    extends StatelessWidget {
  final String title;
  final Widget child;

  const _DetailCard({
    required this.title,
    required this.child,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Card(
      child: Padding(
        padding:
        const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,

          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight:
                FontWeight.bold,
              ),
            ),

            const SizedBox(
              height: 10,
            ),

            child,
          ],
        ),
      ),
    );
  }
}