import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/issue_service.dart';
import '../../services/location_service.dart';
import 'issue_detail_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late final IssueService _issueService;

  final LocationService _locationService = LocationService();

  GoogleMapController? _mapController;

  List<Map<String, dynamic>> _issues = [];

  Set<Marker> _markers = {};
  Set<Heatmap> _heatmaps = {};
  Set<ClusterManager> _clusterManagers = {};

  LatLng? _currentLocation;

  bool _isLoading = true;
  String? _errorMessage;

  String _mapMode = 'pin';

  static const LatLng _defaultLocation = LatLng(
    8.5241,
    76.9366,
  );

  @override
  void initState() {
    super.initState();

    _issueService = IssueService(
      authProvider: context.read<AuthProvider>(),
    );

    _loadMapData();
  }

  // ============================================================
  // LOAD MAP DATA
  // ============================================================

  Future<void> _loadMapData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _getCurrentLocation();

      _issues = await _issueService.getMapIssues();

      _buildMapObjects();

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = e
            .toString()
            .replaceFirst(
          'Exception: ',
          '',
        );
      });
    }
  }

  // ============================================================
  // CURRENT LOCATION
  // ============================================================

  Future<void> _getCurrentLocation() async {
    try {
      final position = await _locationService.getCurrentLocation();

      if (!mounted) return;

      final location = LatLng(
        position.latitude,
        position.longitude,
      );

      setState(() {
        _currentLocation = location;
      });

      if (_mapController != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            location,
            15,
          ),
        );
      }
    } catch (_) {
      _currentLocation = _defaultLocation;
    }
  }

  // ============================================================
  // BUILD MARKERS, HEATMAP AND CLUSTERS
  // ============================================================

  void _buildMapObjects() {
    final markers = <Marker>{};

    final heatPoints = <WeightedLatLng>[];

    final managers = <ClusterManager>{};

    final managerIds = <String, ClusterManagerId>{};

    for (final issue in _issues) {
      final latitude = double.tryParse(
        issue['latitude']?.toString() ?? '',
      );

      final longitude = double.tryParse(
        issue['longitude']?.toString() ?? '',
      );

      if (latitude == null || longitude == null) {
        continue;
      }

      final position = LatLng(
        latitude,
        longitude,
      );

      final issueId =
          issue['id']?.toString() ??
              '${latitude}_$longitude';

      final category =
          issue['category']?.toString() ?? 'other';

      final status =
          issue['status']?.toString() ?? 'reported';

      final severity =
          issue['ai_severity']?.toString().toLowerCase() ??
              'low';

      final upvotes =
          int.tryParse(
            issue['upvote_count']?.toString() ?? '0',
          ) ??
              0;

      // One cluster manager for each category.
      final managerId = managerIds.putIfAbsent(
        category,
            () => ClusterManagerId(
          'cluster_$category',
        ),
      );

      final color = _markerHue(status);

      final address = issue['address']?.toString().trim();
      final hasAddress = address != null && address.isNotEmpty;

      markers.add(
        Marker(
          markerId: MarkerId(issueId),
          position: position,
          clusterManagerId: managerId,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            color,
          ),
          infoWindow: InfoWindow(
            title: _categoryLabel(category),
            snippet: hasAddress
                ? '$address • ${_statusLabel(status)}'
                : '${_statusLabel(status)} • ${_upvotesLabel(upvotes)}',
          ),
          onTap: () {
            _openIssue(issue);
          },
        ),
      );

      // Only active issues contribute to the heatmap.
      if (status != 'resolved' && status != 'closed') {
        double weight = 1.0;

        if (severity == 'critical') {
          weight += 1.0;
        } else if (severity == 'high') {
          weight += 0.5;
        }

        if (upvotes > 10) {
          weight += 0.3;
        }

        heatPoints.add(
          WeightedLatLng(
            position,
            weight: weight,
          ),
        );
      }
    }

    // Create cluster managers.
    for (final entry in managerIds.entries) {
      managers.add(
        ClusterManager(
          clusterManagerId: entry.value,
          onClusterTap: (cluster) {
            _mapController?.animateCamera(
              CameraUpdate.newLatLngZoom(
                cluster.position,
                16,
              ),
            );
          },
        ),
      );
    }

    // Create heatmap.
    final heatmaps = <Heatmap>{};

    if (heatPoints.isNotEmpty) {
      heatmaps.add(
        Heatmap(
          heatmapId: const HeatmapId(
            'issues_heatmap',
          ),
          data: heatPoints,
          radius: const HeatmapRadius.fromPixels(
            40,
          ),
          opacity: 0.75,
        ),
      );
    }

    if (!mounted) return;

    setState(() {
      _markers = markers;
      _heatmaps = heatmaps;
      _clusterManagers = managers;
    });
  }

  // ============================================================
  // OPEN ISSUE DETAILS
  // ============================================================

  void _openIssue(
      Map<String, dynamic> issue,
      ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IssueDetailScreen(
          issue: issue,
        ),
      ),
    );
  }

  // ============================================================
  // MARKER COLORS
  // ============================================================

  double _markerHue(String status) {
    switch (status.toLowerCase()) {
      case 'resolved':
        return BitmapDescriptor.hueGreen;

      case 'in_progress':
        return BitmapDescriptor.hueOrange;

      case 'closed':
        return BitmapDescriptor.hueAzure;

      case 'reported':
      default:
        return BitmapDescriptor.hueRed;
    }
  }

  // ============================================================
  // CATEGORY LABEL
  // ============================================================

  String _categoryLabel(String value) {
    switch (value.toLowerCase()) {
      case 'pothole':
        return 'Pothole';

      case 'streetlight':
        return 'Streetlight';

      case 'garbage':
        return 'Garbage';

      case 'water':
        return 'Water';

      case 'other':
      default:
        return 'Other';
    }
  }

  // ============================================================
  // STATUS LABEL
  // ============================================================

  String _statusLabel(String value) {
    switch (value.toLowerCase()) {
      case 'reported':
        return 'Reported';

      case 'in_progress':
        return 'In Progress';

      case 'resolved':
        return 'Resolved';

      case 'closed':
        return 'Closed';

      default:
        return value;
    }
  }

  // ============================================================
  // UPVOTE LABEL
  // ============================================================

  String _upvotesLabel(int count) {
    return '$count upvotes';
  }

  // ============================================================
  // MAP CREATED
  // ============================================================

  void _onMapCreated(
      GoogleMapController controller,
      ) {
    _mapController = controller;

    if (_currentLocation != null) {
      controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          _currentLocation!,
          15,
        ),
      );
    }
  }

  // ============================================================
  // MOVE TO CURRENT LOCATION
  // ============================================================

  Future<void> _moveToCurrentLocation() async {
    if (_currentLocation == null) {
      await _getCurrentLocation();
    }

    if (_currentLocation == null) {
      return;
    }

    await _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        _currentLocation!,
        15,
      ),
    );
  }

  // ============================================================
  // VISIBLE MARKERS
  // ============================================================

  Set<Marker> get _visibleMarkers {
    if (_mapMode == 'heat') {
      return {};
    }

    if (_mapMode == 'cluster') {
      return _markers;
    }

    return _markers
        .map(
          (marker) => marker.copyWith(
        clusterManagerIdParam: null,
      ),
    )
        .toSet();
  }

  // ============================================================
  // VISIBLE CLUSTERS
  // ============================================================

  Set<ClusterManager> get _visibleClusters {
    if (_mapMode == 'cluster') {
      return _clusterManagers;
    }

    return {};
  }

  // ============================================================
  // VISIBLE HEATMAPS
  // ============================================================

  Set<Heatmap> get _visibleHeatmaps {
    if (_mapMode == 'heat') {
      return _heatmaps;
    }

    return {};
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return RefreshIndicator(
        onRefresh: _loadMapData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 120),

            const Icon(
              Icons.map_outlined,
              size: 64,
            ),

            const SizedBox(height: 16),

            const Text(
              'Unable to load map',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
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
              onPressed: _loadMapData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final initialLocation =
        _currentLocation ?? _defaultLocation;

    return Stack(
      children: [
        // ======================================================
        // GOOGLE MAP
        // ======================================================

        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: initialLocation,
            zoom: 14,
          ),
          onMapCreated: _onMapCreated,
          myLocationEnabled: _currentLocation != null,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          markers: _visibleMarkers,
          clusterManagers: _visibleClusters,
          heatmaps: _visibleHeatmaps,
        ),

        // ======================================================
        // MAP MODE SELECTOR
        // ======================================================

        Positioned(
          left: 12,
          right: 12,
          top: 12,
          child: Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: _ModeButton(
                      label: 'Pin',
                      icon: Icons.location_on,
                      selected: _mapMode == 'pin',
                      onTap: () {
                        setState(() {
                          _mapMode = 'pin';
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: _ModeButton(
                      label: 'Heatmap',
                      icon: Icons.local_fire_department,
                      selected: _mapMode == 'heat',
                      onTap: () {
                        setState(() {
                          _mapMode = 'heat';
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: _ModeButton(
                      label: 'Cluster',
                      icon: Icons.bubble_chart,
                      selected: _mapMode == 'cluster',
                      onTap: () {
                        setState(() {
                          _mapMode = 'cluster';
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ======================================================
        // REFRESH BUTTON
        // ======================================================

        Positioned(
          right: 16,
          top: 78,
          child: FloatingActionButton.small(
            heroTag: 'refresh_map',
            onPressed: _loadMapData,
            child: const Icon(
              Icons.refresh,
            ),
          ),
        ),

        // ======================================================
        // MY LOCATION BUTTON
        // ======================================================

        Positioned(
          right: 16,
          bottom: 24,
          child: FloatingActionButton(
            heroTag: 'my_location',
            onPressed: _moveToCurrentLocation,
            child: const Icon(
              Icons.my_location,
            ),
          ),
        ),

        // ======================================================
        // ISSUE COUNT
        // ======================================================

        Positioned(
          left: 16,
          bottom: 24,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              child: Text(
                '${_issues.length} issues',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}

// ================================================================
// MAP MODE BUTTON
// ================================================================

class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? Colors.blue.shade50
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 10,
            horizontal: 6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected
                    ? Colors.blue
                    : Colors.grey.shade700,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}