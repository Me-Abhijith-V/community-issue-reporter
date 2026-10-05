import 'package:flutter/material.dart';

import '../models/status_update_model.dart';

class StatusTimeline extends StatelessWidget {
  final List<StatusUpdateModel> updates;

  const StatusTimeline({
    super.key,
    required this.updates,
  });

  String _statusLabel(String status) {
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
        return status;
    }
  }

  Color _statusColor(String status) {
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

  String _formatDate(String value) {
    if (value.isEmpty) {
      return 'Unknown time';
    }

    try {
      final date = DateTime.parse(value).toLocal();

      return '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year} '
          '${date.hour.toString().padLeft(2, '0')}:'
          '${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (updates.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.history,
                color: Colors.grey.shade600,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No status changes recorded yet.',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: List.generate(
            updates.length,
                (index) {
              final update = updates[index];
              final isLast =
                  index == updates.length - 1;

              final color =
              _statusColor(update.newStatus);

              return Row(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      CircleAvatar(
                        radius: 13,
                        backgroundColor: color,
                        child: const Icon(
                          Icons.check,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),

                      if (!isLast)
                        Container(
                          width: 2,
                          height: 90,
                          color: Colors.grey.shade300,
                        ),
                    ],
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Padding(
                      padding:
                      const EdgeInsets.only(
                        bottom: 20,
                      ),
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Text(
                            _statusLabel(
                              update.newStatus,
                            ),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight:
                              FontWeight.bold,
                              color: color,
                            ),
                          ),

                          const SizedBox(height: 4),

                          Text(
                            '${_statusLabel(update.oldStatus)} '
                                '→ '
                                '${_statusLabel(update.newStatus)}',
                            style: TextStyle(
                              color:
                              Colors.grey.shade700,
                            ),
                          ),

                          const SizedBox(height: 6),

                          Text(
                            _formatDate(
                              update.timestamp,
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              color:
                              Colors.grey.shade600,
                            ),
                          ),

                          if (update.updatedByName !=
                              null &&
                              update.updatedByName!
                                  .isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Updated by: '
                                  '${update.updatedByName}',
                              style: TextStyle(
                                fontSize: 13,
                                color:
                                Colors.grey.shade600,
                              ),
                            ),
                          ],

                          if (update.note.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding:
                              const EdgeInsets.all(
                                10,
                              ),
                              decoration:
                              BoxDecoration(
                                color:
                                Colors.grey.shade100,
                                borderRadius:
                                BorderRadius.circular(
                                  8,
                                ),
                              ),
                              child: Text(
                                update.note,
                                style:
                                const TextStyle(
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}