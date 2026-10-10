import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/issue_service.dart';
import '../../services/location_service.dart';
import '../issue/issue_detail_screen.dart';

class UpvotedIssuesScreen extends StatefulWidget {
  const UpvotedIssuesScreen({super.key});

  @override
  State<UpvotedIssuesScreen> createState() =>
      _UpvotedIssuesScreenState();
}

class _UpvotedIssuesScreenState
    extends State<UpvotedIssuesScreen> {
  late final IssueService _issueService;
  final LocationService _locationService = LocationService();

  List<Map<String, dynamic>> _issues = [];
  final Map<int, String> _addressCache = {};

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _issueService = IssueService(
      authProvider: context.read<AuthProvider>(),
    );
    _loadUpvotedIssues();
  }

  Future<void> _loadUpvotedIssues() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final issues = await _issueService.getUpvotedIssues();
      if (!mounted) return;
      setState(() {
        _issues = issues;
        _isLoading = false;
      });
      _resolveAddresses(issues);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage =
            e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _resolveAddresses(
    List<Map<String, dynamic>> issues,
  ) async {
    for (final issue in issues) {
      final id = issue['id'] as int?;
      if (id == null) continue;

      final storedAddr = issue['address']?.toString().trim();
      if (storedAddr != null && storedAddr.isNotEmpty) {
        _addressCache[id] = storedAddr;
        continue;
      }

      if (_addressCache.containsKey(id)) continue;

      final lat = double.tryParse(
        issue['latitude']?.toString() ?? '',
      );
      final lng = double.tryParse(
        issue['longitude']?.toString() ?? '',
      );

      if (lat == null || lng == null) continue;

      try {
        final address =
            await _locationService.reverseGeocode(
          latitude: lat,
          longitude: lng,
          issueService: _issueService,
        );
        if (mounted) {
          setState(() {
            _addressCache[id] = (address != null && address.isNotEmpty)
                ? address
                : 'Address unavailable';
          });
        }
      } catch (_) {}
    }
  }

  /// Remove the current user's upvote on [issueId].
  Future<void> _removeUpvote(int issueId) async {
    try {
      await _issueService.removeUpvote(issueId: issueId);
      if (!mounted) return;
      setState(() {
        _issues.removeWhere((i) => i['id'] == issueId);
        _addressCache.remove(issueId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upvote removed.'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ── helpers ──────────────────────────────────────────────────

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

  Color _severityColor(String? severity) {
    switch (severity) {
      case 'critical':
        return Colors.red;
      case 'high':
        return Colors.deepOrange;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _categoryIcon(String? category) {
    switch (category) {
      case 'pothole':
        return Icons.dangerous_outlined;
      case 'streetlight':
        return Icons.lightbulb_outline;
      case 'garbage':
        return Icons.delete_outline;
      case 'water':
        return Icons.water_drop_outlined;
      default:
        return Icons.report_problem_outlined;
    }
  }

  // ── build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 56,
                color: colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: colorScheme.error),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadUpvotedIssues,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_issues.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.thumb_up_off_alt,
                size: 72,
                color: colorScheme.primary.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 20),
              Text(
                'No upvoted issues',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Issues you upvote will appear here.\n'
                'You can track their progress and remove upvotes.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _loadUpvotedIssues,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadUpvotedIssues,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: _issues.length,
        itemBuilder: (context, index) {
          final issue = _issues[index];
          return _UpvotedIssueCard(
            issue: issue,
            address: (issue['address'] != null &&
                    issue['address'].toString().trim().isNotEmpty)
                ? issue['address'].toString().trim()
                : _addressCache[issue['id'] as int?],
            statusColor: _statusColor(issue['status'] as String?),
            severityColor:
                _severityColor(issue['ai_severity'] as String?),
            categoryIcon:
                _categoryIcon(issue['category'] as String?),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => IssueDetailScreen(
                    issue: issue,
                  ),
                ),
              );
              // Refresh after returning in case status changed
              _loadUpvotedIssues();
            },
            onRemoveUpvote: () =>
                _removeUpvote(issue['id'] as int),
          );
        },
      ),
    );
  }
}

// ── Upvoted Issue Card ─────────────────────────────────────────

class _UpvotedIssueCard extends StatelessWidget {
  final Map<String, dynamic> issue;
  final String? address;
  final Color statusColor;
  final Color severityColor;
  final IconData categoryIcon;
  final VoidCallback onTap;
  final VoidCallback onRemoveUpvote;

  const _UpvotedIssueCard({
    required this.issue,
    required this.address,
    required this.statusColor,
    required this.severityColor,
    required this.categoryIcon,
    required this.onTap,
    required this.onRemoveUpvote,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final status = issue['status'] as String? ?? 'reported';
    final severity = issue['ai_severity'] as String?;
    final category = issue['category'] as String? ?? 'other';
    final description = (issue['translated_description'] as String?)
            ?.isNotEmpty ==
        true
        ? issue['translated_description'] as String
        : issue['original_description'] as String? ?? '';
    final upvoteCount = issue['upvote_count'] as int? ?? 0;
    final issueId = issue['id'] as int? ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: statusColor.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── header row ──────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:
                          colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      categoryIcon,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          '#$issueId · ${category[0].toUpperCase()}${category.substring(1)}',
                          style: theme.textTheme.labelMedium
                              ?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            // Status chip
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor
                                    .withValues(alpha: 0.15),
                                borderRadius:
                                    BorderRadius.circular(999),
                                border: Border.all(
                                  color: statusColor
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              child: Text(
                                status
                                    .replaceAll('_', ' ')
                                    .toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: statusColor,
                                ),
                              ),
                            ),
                            if (severity != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: severityColor
                                      .withValues(alpha: 0.15),
                                  borderRadius:
                                      BorderRadius.circular(
                                          999),
                                  border: Border.all(
                                    color: severityColor
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Text(
                                  '⚠ ${severity.toUpperCase()}',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: severityColor,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Remove upvote button
                  IconButton(
                    tooltip: 'Remove upvote',
                    icon: Icon(
                      Icons.thumb_up,
                      color: colorScheme.primary,
                      size: 22,
                    ),
                    onPressed: () => _confirmRemove(context),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ── description ─────────────────────────────────
              if (description.isNotEmpty)
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color:
                        colorScheme.onSurface.withValues(alpha: 0.8),
                    height: 1.4,
                  ),
                ),

              const SizedBox(height: 10),

              // ── footer row ──────────────────────────────────
              Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 13,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      address ?? 'Locating…',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurface
                            .withValues(alpha: 0.55),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.thumb_up_outlined,
                    size: 13,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '$upvoteCount',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color:
                        colorScheme.onSurface.withValues(alpha: 0.35),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmRemove(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove upvote?'),
        content: const Text(
          'This issue will be removed from your Upvoted list '
          'and your upvote count on this issue will decrease.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx, true);
              onRemoveUpvote();
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}
