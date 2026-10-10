class IssueModel {
  final int id;
  final String originalDescription;
  final String translatedDescription;
  final String category;
  final String severity;
  final String status;
  final double latitude;
  final double longitude;
  final String address;
  final String? photo;
  final int upvoteCount;
  final bool wasVoiceInput;
  final String? detectedLanguage;
  final String? reporterName;
  final String? reporterEmail;
  final String createdAt;
  final String updatedAt;

  IssueModel({
    required this.id,
    required this.originalDescription,
    required this.translatedDescription,
    required this.category,
    required this.severity,
    required this.status,
    required this.latitude,
    required this.longitude,
    this.address = '',
    required this.photo,
    required this.upvoteCount,
    required this.wasVoiceInput,
    required this.detectedLanguage,
    required this.reporterName,
    required this.reporterEmail,
    required this.createdAt,
    required this.updatedAt,
  });

  factory IssueModel.fromJson(
      Map<String, dynamic> json,
      ) {
    return IssueModel(
      id: json['id'] is int
          ? json['id']
          : int.parse(json['id'].toString()),

      originalDescription:
      json['original_description']?.toString() ?? '',

      translatedDescription:
      json['translated_description']?.toString() ?? '',

      category:
      json['category']?.toString() ?? '',

      severity:
      json['severity']?.toString() ?? '',

      status:
      json['status']?.toString() ?? '',

      latitude: json['latitude'] is num
          ? (json['latitude'] as num).toDouble()
          : double.tryParse(
        json['latitude']?.toString() ?? '',
      ) ??
          0.0,

      longitude: json['longitude'] is num
          ? (json['longitude'] as num).toDouble()
          : double.tryParse(
        json['longitude']?.toString() ?? '',
      ) ??
          0.0,

      address: json['address']?.toString() ?? '',

      photo: json['photo']?.toString(),

      upvoteCount: json['upvote_count'] is int
          ? json['upvote_count']
          : int.tryParse(
        json['upvote_count']?.toString() ?? '',
      ) ??
          0,

      wasVoiceInput:
      json['was_voice_input'] == true,

      detectedLanguage:
      json['detected_language']?.toString(),

      reporterName:
      json['reporter_name']?.toString(),

      reporterEmail:
      json['reporter_email']?.toString(),

      createdAt:
      json['created_at']?.toString() ?? '',

      updatedAt:
      json['updated_at']?.toString() ?? '',
    );
  }
}