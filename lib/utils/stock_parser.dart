List<Map<String, String>> parseInsufficientStock(String message) {
  final stockPart = message.replaceFirst('insufficient_stock: ', '');
  return stockPart.split('; ').map((item) {
    final regex = RegExp(r'^(.*?): required ([\d.]+), stock ([\d.]+)$');
    final match = regex.firstMatch(item.trim());
    final cleanName = (match?.group(1) ?? item).replaceAll(
      RegExp(r'\s*\(ITM\d+\)'),
      '',
    );
    return {
      'name': cleanName,
      'required': match?.group(2) ?? '-',
      'stock': match?.group(3) ?? '-',
    };
  }).toList();
}
