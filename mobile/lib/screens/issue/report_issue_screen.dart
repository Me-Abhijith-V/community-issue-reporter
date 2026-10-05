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

  bool _isListening = false;
  bool _speechAvailable = false;
  bool _wasVoiceInput = false;

  bool _isGettingLocation = true;
  bool _isSubmitting = false;

  // AI results returned by backend after submission.
  String? _detectedLanguage;
  String? _translatedDescription;
  String? _aiCategory;
  String? _aiSeverity;
  bool? _aiIsDuplicate;
  String? _aiDuplicateReason;
  int? _aiDuplicateOf;

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
    });

    try {
      final position =
          await _locationService.getCurrentLocation();

      if (!mounted) return;

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _isGettingLocation = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isGettingLocation = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to get location: ${e.toString()}',
          ),
        ),
      );
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
    // Save current lat/lng before clearing
    final savedLat = _latitude;
    final savedLng = _longitude;

    setState(() {
      _descriptionController.clear();
      _photo = null;
      _wasVoiceInput = false;
      _isListening = false;

      _detectedLanguage = null;
      _translatedDescription = null;
      _aiCategory = null;
      _aiSeverity = null;
      _aiIsDuplicate = null;
      _aiDuplicateReason = null;
      _aiDuplicateOf = null;

      // Restore GPS coordinates — do NOT reset or re-acquire
      _latitude = savedLat;
      _longitude = savedLng;
      _isGettingLocation = false;
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
      // Step 1: Run AI classification first (pre-submit check)
      // -------------------------------------------------------
      Map<String, dynamic>? classifyResult;
      try {
        classifyResult = await _issueService.classifyIssue(
          description: description,
          nearbyLatitude: roundedLatitude,
          nearbyLongitude: roundedLongitude,
        );
      } catch (_) {
        // Classify is optional — if it fails, proceed anyway
        classifyResult = null;
      }

      if (!mounted) return;

      // -------------------------------------------------------
      // Step 2: If AI detected a duplicate, warn the user
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
      // Step 3: Submit the issue
      // -------------------------------------------------------
      final issue =
          await _issueService.createIssue(
        description: description,
        photo: _photo!,
        latitude: roundedLatitude,
        longitude: roundedLongitude,
        wasVoiceInput: _wasVoiceInput,
      );

      if (!mounted) return;

      // -------------------------------------------------------
      // Step 4: Store AI results from server response
      // -------------------------------------------------------
      final serverLang =
          issue['detected_language']?.toString();
      final serverTranslated =
          issue['translated_description']?.toString();
      final serverCategory =
          issue['category']?.toString();
      final serverSeverity =
          issue['ai_severity']?.toString();
      final serverDuplicate =
          issue['ai_is_duplicate'];
      final serverDuplicateOf =
          issue['ai_duplicate_of'];

      // -------------------------------------------------------
      // CRITICAL: Do NOT call Navigator.pop, push, or replace.
      // Stay on ReportIssueScreen. Reset form fields but
      // keep _latitude and _longitude (no GPS re-acquire).
      // -------------------------------------------------------

      _resetForm();

      setState(() {
        _isSubmitting = false;
        _submittedSuccessfully = true;
        _lastSubmittedIssueId =
            issue['id'] is int
                ? issue['id'] as int
                : int.tryParse(
                    issue['id']?.toString() ?? '');

        // Show AI results from server
        _detectedLanguage = serverLang;
        _translatedDescription = serverTranslated;
        _aiCategory = serverCategory;
        _aiSeverity = serverSeverity;

        if (serverDuplicate is bool) {
          _aiIsDuplicate = serverDuplicate;
        }

        if (serverDuplicateOf != null) {
          _aiDuplicateOf = serverDuplicateOf is int
              ? serverDuplicateOf
              : int.tryParse(
                  serverDuplicateOf.toString());
        }
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Issue #${_lastSubmittedIssueId ?? ''} reported successfully! ✓',
          ),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSubmitting = false;
        _submittedSuccessfully = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst(
              'Exception: ',
              '',
            ),
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
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

            if (_aiSeverity != null)
              _AiInfoRow(
                label: 'Severity',
                value: _formatValue(
                  _aiSeverity,
                ),
                valueColor:
                    _severityColor(_aiSeverity),
              ),

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
                label: 'AI reason',
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
                    leading: Icon(
                      _latitude != null &&
                              _longitude != null
                          ? Icons.location_on
                          : Icons
                              .location_searching,
                      color: _latitude != null &&
                              _longitude != null
                          ? Colors.green
                          : Colors.orange,
                    ),
                    title: Text(
                      _isGettingLocation
                          ? 'Getting location...'
                          : _latitude != null &&
                                  _longitude != null
                              ? 'Location captured'
                              : 'Location unavailable',
                    ),
                    subtitle:
                        _latitude != null &&
                                _longitude != null
                            ? Text(
                                '${_latitude!.toStringAsFixed(6)}, '
                                '${_longitude!.toStringAsFixed(6)}',
                              )
                            : null,
                    trailing:
                        _isGettingLocation
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : IconButton(
                                onPressed:
                                    _getLocation,
                                icon:
                                    const Icon(
                                  Icons.refresh,
                                ),
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