class ExposureTracker {
  // tracks ppm-minutes of exposure for each worker UUID
  final Map<String, double> _h2sExposure = {};
  final Map<String, double> _coExposure = {};

  // Recommended limits
  // H2S: 15 ppm for 15 minutes = 225 ppm-minutes (STEL)
  // CO: 200 ppm for 15 minutes = 3000 ppm-minutes (STEL)

  // This should be called repeatedly, e.g., every 5 seconds
  // durationMinutes is the time since last update (e.g., 5/60)
  void addReading(String workerId, double h2sPpm, double coPpm, double durationMinutes) {
    _h2sExposure.putIfAbsent(workerId, () => 0.0);
    _coExposure.putIfAbsent(workerId, () => 0.0);

    _h2sExposure[workerId] = _h2sExposure[workerId]! + (h2sPpm * durationMinutes);
    _coExposure[workerId] = _coExposure[workerId]! + (coPpm * durationMinutes);
  }

  double getH2SExposure(String workerId) {
    return _h2sExposure[workerId] ?? 0.0;
  }

  double getCOExposure(String workerId) {
    return _coExposure[workerId] ?? 0.0;
  }

  bool isApproachingH2SLimit(String workerId) {
    return getH2SExposure(workerId) > 200; // Warning threshold
  }

  bool isApproachingCOLimit(String workerId) {
    return getCOExposure(workerId) > 2500; // Warning threshold
  }
}
