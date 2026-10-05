class StatusUpdateModel {
  final int id;
  final int issue;
  final int? updatedBy;
  final String? updatedByName;
  final String oldStatus;
  final String newStatus;
  final String note;
  final String timestamp;

  StatusUpdateModel({
    required this.id,
    required this.issue,
    this.updatedBy,
    this.updatedByName,
    required this.oldStatus,
    required this.newStatus,
    required this.note,
    required this.timestamp,
  });

  factory StatusUpdateModel.fromJson(
      Map<String, dynamic> json,
      ) {
    return StatusUpdateModel(
      id: json['id'] is int
          ? json['id']
          : int.parse(json['id'].toString()),
      issue: json['issue'] is int
          ? json['issue']
          : int.parse(json['issue'].toString()),
      updatedBy: json['updated_by'] == null
          ? null
          : (json['updated_by'] is int
          ? json['updated_by']
          : int.tryParse(
        json['updated_by'].toString(),
      )),
      updatedByName:
      json['updated_by_name']?.toString(),
      oldStatus:
      json['old_status']?.toString() ?? '',
      newStatus:
      json['new_status']?.toString() ?? '',
      note:
      json['note']?.toString() ?? '',
      timestamp:
      json['timestamp']?.toString() ?? '',
    );
  }
}