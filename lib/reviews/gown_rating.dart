class GownRating {
  const GownRating({required this.average, required this.count});
  final double average;
  final int count;
  bool get rated => count > 0;
  String get label =>
      !rated ? 'No reviews yet' : '${average.toStringAsFixed(1)} ($count)';
}

Map<String, GownRating> catalogueRatings(Map<String, dynamic> feed) {
  final result = <String, GownRating>{};
  for (final value in feed['ratings'] as List) {
    final row = Map<String, dynamic>.from(value);
    final id = row['dressId'] as String;
    final count = row['count'] as int;
    final average = (row['average'] as num).toDouble();
    if (id.isEmpty ||
        result.containsKey(id) ||
        count < 0 ||
        !average.isFinite ||
        (count == 0 ? average != 0 : average < 1 || average > 5)) {
      throw const FormatException('Invalid catalogue rating');
    }
    result[id] = GownRating(average: average, count: count);
  }
  return result;
}
