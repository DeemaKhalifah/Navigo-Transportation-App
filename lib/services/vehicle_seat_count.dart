int defaultSeatCountForVehicleType(String? type) {
  final value = (type ?? '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s_-]+'), '');

  if (value == 'bus45') return 45;
  if (value == 'bus14') return 14;
  if (value == 'microbus7' || value == 'micro7') return 7;

  if (value == 'bus') return 45;
  if (value.contains('micro')) return 7;

  return 7;
}