// lib/analysis_filter_notifier.dart
import 'package:flutter/material.dart';

enum FilterType { all, income, expense }

class AnalysisFilterNotifier extends ChangeNotifier {
  FilterType _filterType = FilterType.all;
  String _selectedCategory = 'All';
  int _rangeDays = 30;

  FilterType get filterType => _filterType;
  String get selectedCategory => _selectedCategory;
  int get rangeDays => _rangeDays;

  void updateFilterType(FilterType type) {
    _filterType = type;
    notifyListeners();
  }

  void updateSelectedCategory(String category) {
    _selectedCategory = category;
    notifyListeners();
  }

  void updateRangeDays(int days) {
    _rangeDays = days;
    notifyListeners();
  }
}
