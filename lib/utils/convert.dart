import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String formatIDR(num number) {
  return number.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (Match m) => '${m[1]}.',
  );
}

String convertIDR(num number) {
  return "Rp ${formatIDR(number)}";
}

String getInitials(String name) {
  if (name.trim().isEmpty) return "";

  List<String> parts = name.trim().split(RegExp(r"\s+"));
  String initials = "";

  for (var p in parts) {
    if (p.isNotEmpty) {
      initials += p[0];
    }
    if (initials.length == 2) break;
  }

  return initials.toUpperCase();
}

Color baseColor(String name) {
  if (name.isEmpty) return Colors.grey;

  final colors = [
    Colors.red,
    Colors.orange,
    Colors.blue,
    Colors.green,
    Colors.purple,
    Colors.teal,
    Colors.indigo,
    Colors.pink,
  ];

  // hash sederhana dari nama
  final bytes = utf8.encode(name);
  final hash = bytes.fold(0, (prev, b) => prev + b);

  return colors[hash % colors.length];
}

// 2. Second color (base color tapi dibuat lebih terang / keputihan)
Color secondColor(String name) {
  Color base = baseColor(name);

  // campur dengan putih supaya lebih terang
  return Color.lerp(
    base,
    Colors.white,
    0.4,
  )!; // 0.0 = sama dengan base, 1.0 = putih
}

String formatDate(String isoDate) {
  if (isoDate.isEmpty) return '-';

  final dateTime = DateTime.parse(isoDate).toLocal();

  final formatter = DateFormat('dd MMM yyyy', 'en_US');
  return formatter.format(dateTime);
}

String formatDateTime(String isoDate) {
  if (isoDate.isEmpty) return '-';
  final dateTime = DateTime.parse(isoDate);
  final formatter = DateFormat('dd MMM yyyy HH:mm', 'en_US');
  return formatter.format(dateTime);
}
