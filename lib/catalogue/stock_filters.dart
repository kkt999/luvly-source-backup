const stockQuantityFilters = [
  'All quantities',
  'Positive total',
  'Zero total',
  'Not configured',
  'Custom order',
];
bool matchesStockQuantity(Map item, String filter) {
  final custom = item['size'] == 'Made to measure', quantity = item['quantity'];
  return switch (filter) {
    'All quantities' => true,
    'Positive total' => !custom && quantity is int && quantity > 0,
    'Zero total' => !custom && quantity == 0,
    'Not configured' => !custom && quantity == null,
    'Custom order' => custom,
    _ => false,
  };
}
