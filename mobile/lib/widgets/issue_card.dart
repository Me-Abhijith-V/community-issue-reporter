import 'package:flutter/material.dart';

import '../models/issue_model.dart';
import '../providers/auth_provider.dart';
import '../services/issue_service.dart';

class IssueCard extends StatefulWidget {
  final IssueModel issue;
  final VoidCallback? onTap;

  const IssueCard({
    super.key,
    required this.issue,
    this.onTap,
  });

  @override
  State<IssueCard> createState() => _IssueCardState();
}

class _IssueCardState extends State<IssueCard> {
  late int _upvoteCount;
  bool _isUpvoting = false;
  bool _hasUpvoted = false;

  @override
  void initState() {
    super.initState();
    _upvoteCount = widget.issue.upvoteCount;
  }

  Future<void> _upvote() async {
    if (_isUpvoting || _hasUpvoted) {
      return;
    }

    final authProvider = AuthProvider();
    final issueService = IssueService(
      authProvider: authProvider,
    );

    setState(() {
      _isUpvoting = true;
    });

    try {
      final result = await issueService.upvoteIssue(
        issueId: widget.issue.id,
      );

      final count = result['upvote_count'];

      if (!mounted) {
        return;
      }

      setState(() {
        if (count is int) {
          _upvoteCount = count;
        } else {
          _upvoteCount = int.tryParse(
            count?.toString() ?? '',
          ) ??
              _upvoteCount + 1;
        }

        _hasUpvoted = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Issue upvoted successfully.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
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

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'reported':
        return Colors.blue;
      case 'in_progress':
        return Colors.orange;
      case 'resolved':
        return Colors.green;
      case 'closed':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'low':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'high':
        return Colors.deepOrange;
      case 'critical':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatStatus(String status) {
    return status
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (word) => word.isEmpty
          ? word
          : '${word[0].toUpperCase()}${word.substring(1)}',
    )
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.issue.category.toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor(
                        widget.issue.status,
                      ).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _formatStatus(widget.issue.status),
                      style: TextStyle(
                        color: _statusColor(
                          widget.issue.status,
                        ),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Text(
                widget.issue.originalDescription,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                ),
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _severityColor(
                        widget.issue.severity,
                      ).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.issue.severity.toUpperCase(),
                      style: TextStyle(
                        color: _severityColor(
                          widget.issue.severity,
                        ),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const Spacer(),

                  Icon(
                    Icons.thumb_up_alt_outlined,
                    size: 18,
                    color: _hasUpvoted
                        ? Colors.blue
                        : Colors.grey.shade700,
                  ),

                  const SizedBox(width: 4),

                  Text(
                    '$_upvoteCount',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(width: 4),

                  if (_isUpvoting)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  else
                    IconButton(
                      onPressed:
                      _hasUpvoted ? null : _upvote,
                      icon: Icon(
                        _hasUpvoted
                            ? Icons.thumb_up
                            : Icons.thumb_up_outlined,
                      ),
                      tooltip: _hasUpvoted
                          ? 'Already upvoted'
                          : 'Upvote',
                      padding: EdgeInsets.zero,
                      constraints:
                      const BoxConstraints(),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}