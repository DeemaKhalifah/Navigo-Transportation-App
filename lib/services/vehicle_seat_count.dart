/// Default seat counts by signup / UI vehicle type label.
int defaultSeatCountForVehicleType(String? type) {
  switch (type?.trim()) {
    case 'Bus':
      return 45;
    case 'Mini Bus':
      return 14;
    case 'Van':
      return 7;
    default:
      return 7;
  }
}
