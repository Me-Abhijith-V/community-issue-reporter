import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../providers/auth_provider.dart';
import '../../services/issue_service.dart';
import '../../services/location_service.dart';
import '../issue/issue_detail_screen.dart';

class ReportIssueScreen extends StatefulWidget {
  const ReportIssueScreen({super.key});

  @override
  State<ReportIssueScreen> createState() =>
      _ReportIssueScreenState();
}

class _ReportIssueScreenState
    extends State<ReportIssueScreen> {
  late final IssueService _issueService;
  late final LocationService _locationService;

  final TextEditingController _descriptionController =
      TextEditingController();

  final ImagePicker _imagePicker = ImagePicker();

  final stt.SpeechToText _speech =
      stt.SpeechToText();

  File? _photo;

  double? _latitude;
  double? _longitude;
  String? _resolvedAddress;
  bool _isGettingLocation = true;
  bool _isResolvingAddress = false;
  String? _locationErrorMessage;

  bool _isListening = false;
  bool _speechAvailable = false;
  bool _wasVoiceInput = false;

  bool _isSubmitting = false;

  // AI results returned by backend after submission.
  String? _detectedLanguage;
  String? _translatedDescription;
  String? _aiCategory;
  String? _aiSeverity;
  String? _aiSeverityBasis;
  String? _aiSeverityReason;
  String? _aiValidationStatus;
  bool? _aiIsImageMatch;
  String? _aiImageMatchReason;
  String? _aiAnalysisError;
  bool? _aiIsDuplicate;
  String? _aiDuplicateReason;
  int? _aiDuplicateOf;
  bool _aiAnalysisFailed = false;

  // Success state — shown after a successful submit
  bool _submittedSuccessfully = false;
  int? _lastSubmittedIssueId;

  @override
  void initState() {
    super.initState();

    _issueService = IssueService(
      authProvider: context.read<AuthProvider>(),
    );

    _locationService = LocationService();

    _initializeSpeech();
    _getLocation();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _speech.stop();
    super.dispose();
  }

  // ============================================================
  // SPEECH INITIALIZATION
  // ============================================================

  Future<void> _initializeSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;

          setState(() {
            _isListening = status == 'listening';
          });
        },
        onError: (error) {
          if (!mounted) return;

          setState(() {
            _isListening = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Voice input error: ${error.errorMsg}',
              ),
            ),
          );
        },
      );

      if (!mounted) return;

      setState(() {
        _speechAvailable = available;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _speechAvailable = false;
      });
    }
  }

  // ============================================================
  // VOICE INPUT
  // ============================================================

  Future<void> _startVoiceInput() async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Voice input is not available on this device.',
          ),
        ),
      );
      return;
    }

    if (_isListening) {
      await _speech.stop();

      if (!mounted) return;

      setState(() {
        _isListening = false;
      });

      return;
    }

    _wasVoiceInput = true;

    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;

        setState(() {
          _descriptionController.text =
              result.recognizedWords;

          _descriptionController.selection =
              TextSelection.fromPosition(
            TextPosition(
              offset:
                  _descriptionController.text.length,
            ),
          );
        });
      },
      listenOptions: stt.SpeechListenOptions(
        listenFor: const Duration(minutes: 2),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
      ),
    );

    if (!mounted) return;

    setState(() {
      _isListening = true;
    });
  }

  // ============================================================
  // LOCATION
  // ============================================================

  Future<void> _getLocation() async {
    if (!mounted) return;

    setState(() {
      _isGettingLocation = true;
      _locationErrorMessage = null;
    });

    try {
      final position =
          await _locationService.getCurrentLocation();

      if (!mounted) return;

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _isGettingLocation = false;
        _isResolvingAddress = true;
      });

      // Attempt to resolve coordinates into human-readable address
      await _resolveAddress(position.latitude, position.longitude);
    } catch (e) {
      if (!mounted) return;

      final cleanError = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _isGettingLocation = false;
        _isResolvingAddress = false;
        _locationErrorMessage = cleanError;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to get location: $cleanError',
          ),
        ),
      );
    }
  }

  Future<void> _resolveAddress(double lat, double lng) async {
    if (!mounted) return;

    setState(() {
      _isResolvingAddress = true;
    });

    try {
      final address = await _locationService.reverseGeocode(
        latitude: lat,
        longitude: lng,
        issueService: _issueService,
      );

      if (!mounted) return;

      setState(() {
        _resolvedAddress = address;
        _isResolvingAddress = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _resolvedAddress = null;
        _isResolvingAddress = false;
      });
    }
  }

  // ============================================================
  // PHOTO
  // ============================================================

  Future<void> _pickPhoto(
    ImageSource source,
  ) async {
    try {
      final pickedFile =
          await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      if (!mounted) return;

      setState(() {
        _photo = File(pickedFile.path);
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to select photo: $e',
          ),
        ),
      );
    }
  }

  Future<void> _showPhotoOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.camera_alt,
                ),
                title: const Text(
                  'Take Photo',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickPhoto(
                    ImageSource.camera,
                  );
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library,
                ),
                title: const Text(
                  'Choose from Gallery',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickPhoto(
                    ImageSource.gallery,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // RESET FORM AFTER SUBMISSION
  // Keep latitude/longitude — do NOT re-acquire GPS.
  // ============================================================

  void _resetForm() {
    // Save current lat/lng and address before clearing
    final savedLat = _latitude;
    final savedLng = _longitude;
    final savedAddress = _resolvedAddress;

    setState(() {
      _descriptionController.clear();
      _photo = null;
      _wasVoiceInput = false;
      _isListening = false;

      _detectedLanguage = null;
      _translatedDescription = null;
      _aiCategory = null;
      _aiSeverity = null;
      _aiSeverityBasis = null;
      _aiSeverityReason = null;
      _aiValidationStatus = null;
      _aiIsImageMatch = null;
      _aiImageMatchReason = null;
      _aiAnalysisError = null;
      _aiIsDuplicate = null;
      _aiDuplicateReason = null;
      _aiDuplicateOf = null;
      _aiAnalysisFailed = false;

      // Restore GPS coordinates and address — do NOT reset or re-acquire
      _latitude = savedLat;
      _longitude = savedLng;
      _resolvedAddress = savedAddress;
      _isGettingLocation = false;
      _isResolvingAddress = false;
    });
  }

  // ============================================================
  // DUPLICATE WARNING DIALOG
  // ============================================================

  /// Returns true if citizen wants to submit anyway.
  /// Returns false if citizen wants to cancel/upvote existing.
  Future<bool> _showDuplicateWarning({
    required int duplicateId,
    required String? duplicateReason,
    required Map<String, dynamic>? duplicateIssue,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange.shade700,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Similar Issue Found',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI detected a similar issue (Issue #$duplicateId) nearby.',
                style: const TextStyle(
                    fontWeight: FontWeight.w600),
              ),
              if (duplicateReason != null &&
                  duplicateReason.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Reason: $duplicateReason',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 13,
                  ),
                ),
              ],
              if (duplicateIssue != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Colors.orange.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Category: ${_formatValue(duplicateIssue['category']?.toString())}',
                        style: const TextStyle(
                            fontSize: 12),
                      ),
                      Text(
                        'Status: ${_formatValue(duplicateIssue['status']?.toString())}',
                        style: const TextStyle(
                            fontSize: 12),
                      ),
                      Text(
                        'Upvotes: ${duplicateIssue['upvote_count'] ?? 0}',
                        style: const TextStyle(
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'You can upvote the existing issue or submit this as a new separate report.',
              ),
            ],
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.pop(ctx, false),
              icon: const Icon(Icons.thumb_up_outlined),
              label: const Text('View & Upvote Existing'),
            ),
            FilledButton.icon(
              onPressed: () =>
                  Navigator.pop(ctx, true),
              icon: const Icon(Icons.send),
              label: const Text('Submit Anyway'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  // ============================================================
  // DESCRIPTION - IMAGE MISMATCH DIALOG
  // ============================================================

  Future<String?> _showMismatchDialog({
    required String reason,
  }) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.red.shade700,
                size: 28,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Invalid — Mismatch',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Description and photo do not match:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade900,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  reason,
                  style: TextStyle(
                    color: Colors.red.shade900,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Please update the photo or edit your description without losing your entered data.',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'edit_description'),
              icon: const Icon(Icons.edit),
              label: const Text('Edit Description'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, 'change_photo'),
              icon: const Icon(Icons.photo_camera),
              label: const Text('Change Photo'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // UNCERTAIN MATCH CONFIRMATION DIALOG
  // ============================================================

  Future<bool> _showUncertainDialog({
    required String reason,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.help_outline,
                color: Colors.amber.shade800,
                size: 28,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Verify Photo & Description',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI could not fully verify the photo against your description:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.amber.shade900,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Text(
                  reason,
                  style: TextStyle(
                    color: Colors.amber.shade900,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Would you like to proceed anyway, or refine your photo/description?',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Review & Edit'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm & Submit'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  // ============================================================
  // SUBMIT ISSUE
  // CRITICAL: Never call Navigator.pop/push after success.
  // Stay on this screen. Reset form but keep GPS coordinates.
  // ============================================================

  Future<void> _submitForm() async {
    if (_isSubmitting) return;

    final authProvider =
        context.read<AuthProvider>();

    final accessToken =
        authProvider.accessToken;

    if (accessToken == null ||
        accessToken.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You are not logged in. Please login again.',
          ),
        ),
      );
      return;
    }

    final description =
        _descriptionController.text.trim();

    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please describe the problem.',
          ),
        ),
      );
      return;
    }

    if (_photo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please add a photo of the issue.',
          ),
        ),
      );
      return;
    }

    if (_latitude == null ||
        _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location is required. Please wait for GPS.',
          ),
        ),
      );
      return;
    }

    if (_isListening) {
      await _speech.stop();

      if (!mounted) return;

      setState(() {
        _isListening = false;
      });
    }

    setState(() {
      _isSubmitting = true;

      _detectedLanguage = null;
      _translatedDescription = null;
      _aiCategory = null;
      _aiSeverity = null;
      _aiSeverityBasis = null;
      _aiSeverityReason = null;
      _aiValidationStatus = null;
      _aiIsImageMatch = null;
      _aiImageMatchReason = null;
      _aiAnalysisError = null;
      _aiIsDuplicate = null;
      _aiDuplicateReason = null;
      _aiDuplicateOf = null;
      _submittedSuccessfully = false;
    });

    try {
      final roundedLatitude =
          double.parse(
        _latitude!.toStringAsFixed(6),
      );

      final roundedLongitude =
          double.parse(
        _longitude!.toStringAsFixed(6),
      );

      // -------------------------------------------------------
      // Step 1: Run AI classification with text + image
      // -------------------------------------------------------
      Map<String, dynamic>? classifyResult;
      String? aiWarningMessage;

      try {
        classifyResult = await _issueService.classifyIssue(
          description: description,
          photo: _photo,
          nearbyLatitude: roundedLatitude,
          nearbyLongitude: roundedLongitude,
        );
      } catch (err) {
        classifyResult = null;
        final errStr = err.toString().toLowerCase();
        if (errStr.contains('quota') ||
            errStr.contains('busy') ||
            errStr.contains('429') ||
            errStr.contains('resource exhausted')) {
          aiWarningMessage =
              'AI service is temporarily busy (quota limit). Your report will still be submitted.';
        } else if (errStr.contains('timeout') ||
            errStr.contains('timed out')) {
          aiWarningMessage =
              'AI analysis timed out. Your report will still be submitted.';
        } else if (errStr.contains('key') ||
            errStr.contains('credential') ||
            errStr.contains('401')) {
          aiWarningMessage =
              'AI service configuration issue. Your report will still be submitted.';
        } else {
          aiWarningMessage =
              'AI service is currently unavailable. Your report will still be submitted.';
        }
      }

      if (!mounted) return;

      // -------------------------------------------------------
      // Step 2: Validate description vs photo match
      // -------------------------------------------------------
      if (classifyResult != null) {
        final validationStatus =
            classifyResult['validation_status']?.toString();
        final matchReason = classifyResult['image_match_reason']?.toString() ??
            'The uploaded image does not appear to match the described issue.';

        if (validationStatus == 'mismatch') {
          setState(() {
            _isSubmitting = false;
          });
          final action = await _showMismatchDialog(reason: matchReason);
          if (!mounted) return;
          if (action == 'change_photo') {
            _showPhotoOptions();
          }
          return;
        }

        if (validationStatus == 'uncertain') {
          setState(() {
            _isSubmitting = false;
          });
          final proceed = await _showUncertainDialog(reason: matchReason);
          if (!mounted) return;
          if (!proceed) {
            return;
          }
          setState(() {
            _isSubmitting = true;
          });
        }
      }

      // -------------------------------------------------------
      // Step 3: Duplicate detection check
      // -------------------------------------------------------
      if (classifyResult != null &&
          classifyResult['is_duplicate'] == true) {
        final duplicateId =
            classifyResult['duplicate_of'];
        final duplicateReason =
            classifyResult['duplicate_reason']
                ?.toString();
        final duplicateIssue =
            classifyResult['duplicate_issue'] != null
                ? Map<String, dynamic>.from(
                    classifyResult['duplicate_issue'] as Map)
                : null;

        setState(() {
          _isSubmitting = false;
          _aiIsDuplicate = true;
          _aiDuplicateReason = duplicateReason;
          _aiDuplicateOf = duplicateId is int
              ? duplicateId
              : int.tryParse(
                  duplicateId?.toString() ?? '');
          _detectedLanguage =
              classifyResult!['detected_language']
                  ?.toString();
          _translatedDescription =
              classifyResult['translated_description']
                  ?.toString();
          _aiCategory =
              classifyResult['category']?.toString();
          _aiSeverity =
              classifyResult['severity']?.toString();
          _aiSeverityBasis =
              classifyResult['severity_basis']?.toString();
          _aiSeverityReason =
              classifyResult['severity_reason']?.toString();
          _aiValidationStatus =
              classifyResult['validation_status']?.toString();
          _aiIsImageMatch =
              classifyResult['is_image_match'] as bool?;
          _aiImageMatchReason =
              classifyResult['image_match_reason']?.toString();
        });

        final submitAnyway = await _showDuplicateWarning(
          duplicateId: duplicateId is int
              ? duplicateId
              : int.tryParse(
                      duplicateId?.toString() ?? '') ??
                  0,
          duplicateReason: duplicateReason,
          duplicateIssue: duplicateIssue,
        );

        if (!mounted) return;

        if (!submitAnyway) {
          // User chose to view/upvote existing — navigate to it
          if (duplicateIssue != null) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => IssueDetailScreen(
                  issue: duplicateIssue,
                ),
              ),
            );
          }
          return;
        }

        // User chose to submit anyway — resume submission
        setState(() {
          _isSubmitting = true;
        });
      }

      // -------------------------------------------------------
      // Step 4: Submit the issue (pass pre-classified AI data)
      // -------------------------------------------------------
      final issue = await _issueService.createIssue(
        description: description,
        photo: _photo!,
        latitude: roundedLatitude,
        longitude: roundedLongitude,
        address: _resolvedAddress,
        wasVoiceInput: _wasVoiceInput,
        aiSuggestedCategory: classifyResult?['category']?.toString(),
        aiSeverity: classifyResult?['severity']?.toString(),
        aiSeverityBasis: classifyResult?['severity_basis']?.toString(),
        aiSeverityReason: classifyResult?['severity_reason']?.toString(),
        aiValidationStatus: classifyResult?['validation_status']?.toString(),
        aiIsImageMatch: classifyResult?['is_image_match'] as bool?,
        aiImageMatchReason: classifyResult?['image_match_reason']?.toString(),
        detectedLanguage: classifyResult?['detected_language']?.toString(),
        translatedDescription:
            classifyResult?['translated_description']?.toString(),
        aiIsDuplicate: classifyResult?['is_duplicate'] as bool?,
        aiDuplicateOf: classifyResult?['duplicate_of'] as int?,
        aiDuplicateReason: classifyResult?['duplicate_reason']?.toString(),
      );

      if (!mounted) return;

      // -------------------------------------------------------
      // Step 5: Store AI results from server response
      // -------------------------------------------------------
      final serverLang = issue['detected_language']?.toString();
      final serverTranslated = issue['translated_description']?.toString();
      final serverSeverity = issue['ai_severity']?.toString();
      final serverSeverityBasis = issue['ai_severity_basis']?.toString();
      final serverSeverityReason = issue['ai_severity_reason']?.toString();
      final serverValidationStatus = issue['ai_validation_status']?.toString();
      final serverIsImageMatch = issue['ai_is_image_match'] as bool?;
      final serverImageMatchReason = issue['ai_image_match_reason']?.toString();
      final serverDuplicate = issue['ai_is_duplicate'];
      final serverDuplicateOf = issue['ai_duplicate_of'];
      final serverDuplicateReason =
          issue['ai_duplicate_reason']?.toString();

      final aiStatus = issue['ai_status']?.toString();
      final aiSuggestedCategory =
          issue['ai_suggested_category']?.toString();
      final isAiSuccess = aiStatus == 'success' ||
          (aiSuggestedCategory != null &&
              aiSuggestedCategory.isNotEmpty) ||
          (classifyResult != null && classifyResult['ai_success'] == true);

      // -------------------------------------------------------
      // CRITICAL: Do NOT call Navigator.pop, push, or replace.
      // Stay on ReportIssueScreen. Reset form fields but
      // keep _latitude and _longitude (no GPS re-acquire).
      // -------------------------------------------------------
      _resetForm();

      setState(() {
        _submittedSuccessfully = true;
        _lastSubmittedIssueId = issue['id'] is int
            ? issue['id'] as int
            : int.tryParse(issue['id']?.toString() ?? '');

        if (isAiSuccess) {
          _aiCategory = aiSuggestedCategory ??
              classifyResult?['category']?.toString();
          _aiSeverity = serverSeverity ??
              classifyResult?['severity']?.toString();
          _aiSeverityBasis = serverSeverityBasis ??
              classifyResult?['severity_basis']?.toString();
          _aiSeverityReason = serverSeverityReason ??
              classifyResult?['severity_reason']?.toString();
          _aiValidationStatus = serverValidationStatus ??
              classifyResult?['validation_status']?.toString();
          _aiIsImageMatch = serverIsImageMatch ??
              (classifyResult?['is_image_match'] as bool?);
          _aiImageMatchReason = serverImageMatchReason ??
              classifyResult?['image_match_reason']?.toString();
          _detectedLanguage = serverLang ??
              classifyResult?['detected_language']?.toString();
          _translatedDescription = serverTranslated ??
              classifyResult?['translated_description']?.toString();
          _aiDuplicateReason = serverDuplicateReason ??
              classifyResult?['duplicate_reason']?.toString();
          _aiAnalysisFailed = false;
          _aiAnalysisError = null;

          if (serverDuplicate is bool) {
            _aiIsDuplicate = serverDuplicate;
          } else if (classifyResult?['is_duplicate'] is bool) {
            _aiIsDuplicate = classifyResult!['is_duplicate'] as bool;
          }

          if (serverDuplicateOf != null) {
            _aiDuplicateOf = serverDuplicateOf is int
                ? serverDuplicateOf
                : int.tryParse(serverDuplicateOf.toString());
          } else if (classifyResult?['duplicate_of'] != null) {
            _aiDuplicateOf = classifyResult!['duplicate_of'] as int?;
          }
        } else {
          // AI classification failed or was unavailable
          _aiCategory = null;
          _aiSeverity = null;
          _aiSeverityBasis = null;
          _aiSeverityReason = null;
          _aiValidationStatus = null;
          _aiIsImageMatch = null;
          _aiImageMatchReason = null;
          _detectedLanguage = null;
          _translatedDescription = null;
          _aiIsDuplicate = null;
          _aiDuplicateOf = null;
          _aiDuplicateReason = null;
          _aiAnalysisFailed = true;
          _aiAnalysisError = aiWarningMessage ??
              'AI service is temporarily busy. Your report was submitted successfully.';
        }
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAiSuccess
                ? 'Issue #${_lastSubmittedIssueId ?? ''} reported successfully with AI analysis! ✓'
                : 'Issue #${_lastSubmittedIssueId ?? ''} reported successfully! (AI analysis unavailable)',
          ),
          backgroundColor:
              isAiSuccess ? Colors.green.shade700 : Colors.teal.shade700,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _submittedSuccessfully = false;
      });

      final errMsg = e.toString().replaceFirst('Exception: ', '');
      if (errMsg.toLowerCase().contains('do not match') ||
          errMsg.toLowerCase().contains('mismatch')) {
        await _showMismatchDialog(
          reason: errMsg,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errMsg),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  // ============================================================
  // FORMATTING
  // ============================================================

  String _formatValue(String? value) {
    if (value == null || value.isEmpty) {
      return 'Not available';
    }

    return value
        .split('_')
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}'
                  '${word.substring(1)}',
        )
        .join(' ');
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

  // ============================================================
  // SUCCESS BANNER
  // ============================================================

  Widget _buildSuccessBanner() {
    if (!_submittedSuccessfully) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle,
              color: Colors.green.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Issue${_lastSubmittedIssueId != null ? ' #$_lastSubmittedIssueId' : ''} submitted successfully! '
              'Fill in a new report or switch tabs.',
              style: TextStyle(
                color: Colors.green.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: Colors.green.shade700,
            onPressed: () {
              setState(() {
                _submittedSuccessfully = false;
              });
            },
          ),
        ],
      ),
    );
  }

  // ============================================================
  // AI RESULT CARD
  // ============================================================

  Widget _buildAiResults() {
    if (_aiAnalysisFailed) {
      return Card(
        margin: const EdgeInsets.only(top: 20),
        color: Colors.amber.shade50,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.amber.shade300),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Colors.amber.shade800),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Analysis Unavailable',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.amber.shade900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _aiAnalysisError ??
                          'AI service is temporarily busy. Your report was submitted successfully, but automated categorization and severity scoring could not be completed.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.amber.shade900,
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

    final hasResults =
        _detectedLanguage != null ||
            _translatedDescription != null ||
            _aiCategory != null ||
            _aiSeverity != null ||
            _aiIsDuplicate != null;

    if (!hasResults) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.only(
        top: 20,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: Colors.blue,
                ),
                SizedBox(width: 8),
                Text(
                  'AI Analysis',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            if (_detectedLanguage != null)
              _AiInfoRow(
                label: 'Detected language',
                value: _formatValue(
                  _detectedLanguage,
                ),
              ),

            if (_translatedDescription != null &&
                _translatedDescription!.isNotEmpty)
              _AiInfoRow(
                label: 'English description',
                value:
                    _translatedDescription!,
              ),

            if (_aiCategory != null)
              _AiInfoRow(
                label: 'Category',
                value: _formatValue(
                  _aiCategory,
                ),
              ),

            if (_aiSeverity != null) ...[
              _AiInfoRow(
                label: 'Severity (${_aiSeverityBasis == "text_and_image" ? "photo & text analyzed" : "text analyzed"})',
                value: _formatValue(
                  _aiSeverity,
                ),
                valueColor:
                    _severityColor(_aiSeverity),
              ),
              if (_aiSeverityReason != null && _aiSeverityReason!.isNotEmpty)
                _AiInfoRow(
                  label: 'Severity assessment',
                  value: _aiSeverityReason!,
                ),
            ],

            if (_aiValidationStatus != null || _aiIsImageMatch != null) ...[
              _AiInfoRow(
                label: 'Photo verification',
                value: _aiIsImageMatch == true
                    ? 'Verified match ✓'
                    : (_aiIsImageMatch == false
                        ? 'Mismatch'
                        : (_aiValidationStatus == 'valid'
                            ? 'Verified match ✓'
                            : 'Uncertain match')),
                valueColor: (_aiIsImageMatch == true || _aiValidationStatus == 'valid')
                    ? Colors.green.shade700
                    : Colors.amber.shade800,
              ),
              if (_aiImageMatchReason != null && _aiImageMatchReason!.isNotEmpty)
                _AiInfoRow(
                  label: 'Photo check reason',
                  value: _aiImageMatchReason!,
                ),
            ],

            if (_aiIsDuplicate != null)
              _AiInfoRow(
                label: 'Duplicate check',
                value: _aiIsDuplicate!
                    ? 'Similar issue found${_aiDuplicateOf != null ? ' (Issue #$_aiDuplicateOf)' : ''}'
                    : 'No similar issue found',
                valueColor: _aiIsDuplicate!
                    ? Colors.orange.shade800
                    : Colors.green.shade700,
              ),

            if (_aiDuplicateReason != null &&
                _aiDuplicateReason!.isNotEmpty)
              _AiInfoRow(
                label: 'Duplicate reason',
                value: _aiDuplicateReason!,
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Report Issue',
        ),
        automaticallyImplyLeading: false,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                // Success banner
                _buildSuccessBanner(),

                const Text(
                  'Report a Community Issue',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  'Describe the problem. AI will automatically '
                      'identify the language, category, severity '
                      'and possible duplicates.',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                  ),
                ),

                const SizedBox(height: 24),

                // ==================================================
                // DESCRIPTION
                // ==================================================

                Stack(
                  children: [
                    TextField(
                      controller:
                          _descriptionController,
                      minLines: 5,
                      maxLines: 8,
                      textInputAction:
                          TextInputAction.newline,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Describe the problem',
                        hintText:
                            'Type or speak your complaint...',
                        alignLabelWithHint: true,
                        border:
                            OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.fromLTRB(
                          16,
                          16,
                          64,
                          16,
                        ),
                      ),
                    ),

                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Material(
                        color: _isListening
                            ? Colors.red
                            : Colors.blue,
                        shape:
                            const CircleBorder(),
                        child: IconButton(
                          tooltip: _isListening
                              ? 'Stop listening'
                              : 'Speak',
                          color: Colors.white,
                          onPressed:
                              _startVoiceInput,
                          icon: Icon(
                            _isListening
                                ? Icons.stop
                                : Icons.mic,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                if (_isListening)
                  Padding(
                    padding:
                        const EdgeInsets.only(
                      top: 8,
                    ),
                    child: Text(
                      'Listening... Speak naturally.',
                      style: TextStyle(
                        color:
                            Colors.red.shade700,
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),
                  ),

                const SizedBox(height: 20),

                // ==================================================
                // PHOTO
                // ==================================================

                SizedBox(
                  width: double.infinity,
                  child:
                      OutlinedButton.icon(
                    onPressed:
                        _showPhotoOptions,
                    icon: const Icon(
                      Icons.camera_alt_outlined,
                    ),
                    label: Text(
                      _photo == null
                          ? 'Add Photo'
                          : 'Change Photo',
                    ),
                  ),
                ),

                if (_photo != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius:
                        BorderRadius.circular(12),
                    child: Image.file(
                      _photo!,
                      width: double.infinity,
                      height: 220,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // ==================================================
                // LOCATION
                // ==================================================

                Card(
                  child: ListTile(
                    leading: _isGettingLocation || _isResolvingAddress
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          )
                        : Icon(
                            _latitude != null && _longitude != null
                                ? (_resolvedAddress != null
                                    ? Icons.location_on
                                    : Icons.pin_drop_outlined)
                                : Icons.location_off_outlined,
                            color: _latitude != null && _longitude != null
                                ? (_resolvedAddress != null
                                    ? Colors.green
                                    : Colors.orange.shade800)
                                : Colors.red.shade700,
                          ),
                    title: Text(
                      _isGettingLocation
                          ? 'Getting GPS location...'
                          : _isResolvingAddress
                              ? 'Resolving address...'
                              : _latitude != null && _longitude != null
                                  ? (_resolvedAddress != null
                                      ? 'Address captured'
                                      : 'Location captured (GPS)')
                                  : 'Location unavailable',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _isGettingLocation
                          ? 'Acquiring high-accuracy device coordinates'
                          : _isResolvingAddress
                              ? 'Looking up street address...'
                              : _latitude != null && _longitude != null
                                  ? (_resolvedAddress != null
                                      ? _resolvedAddress!
                                      : 'Address unavailable (system will auto-resolve)')
                                  : (_locationErrorMessage ??
                                      'Tap refresh to enable GPS and retry'),
                      style: TextStyle(
                        fontSize: 12,
                        color: _resolvedAddress == null &&
                                (_latitude != null && _longitude != null)
                            ? Colors.amber.shade900
                            : Colors.grey.shade700,
                      ),
                    ),
                    trailing: _isGettingLocation || _isResolvingAddress
                        ? null
                        : IconButton(
                            tooltip: _latitude != null && _resolvedAddress == null
                                ? 'Retry address lookup'
                                : 'Refresh GPS location',
                            onPressed: () {
                              if (_latitude != null &&
                                  _longitude != null &&
                                  _resolvedAddress == null) {
                                _resolveAddress(_latitude!, _longitude!);
                              } else {
                                _getLocation();
                              }
                            },
                            icon: const Icon(Icons.refresh),
                          ),
                  ),
                ),

                // ==================================================
                // AI RESULTS
                // ==================================================

                _buildAiResults(),

                const SizedBox(height: 24),

                // ==================================================
                // SUBMIT
                // ==================================================

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child:
                      FilledButton.icon(
                    onPressed:
                        _isSubmitting
                            ? null
                            : _submitForm,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                              color:
                                  Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.send,
                          ),
                    label: Text(
                      _isSubmitting
                          ? 'Analysing & Submitting...'
                          : 'Submit Report',
                    ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),

          // ========================================================
          // SUBMISSION OVERLAY
          // ========================================================

          if (_isSubmitting)
            Container(
              color: Colors.black26,
              child: const Center(
                child: Card(
                  child: Padding(
                    padding:
                        EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize:
                          MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          'AI is analysing your report...',
                          style: TextStyle(
                            fontWeight:
                                FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Detecting language, category, '
                              'severity and duplicates.',
                          textAlign:
                              TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// AI INFORMATION ROW
// ============================================================

class _AiInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _AiInfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}