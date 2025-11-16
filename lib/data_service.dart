// lib/data_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class DataService {
  final _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> getHomeData() async {
    final res = await _supabase
        .from('transaction')
        .select('*')
        .order('created_at', ascending: false);

    if (res is! List) {
      return {'income': 0.0, 'expense': 0.0, 'recentTx': []};
    }

    double totalIncome = 0;
    double totalExpense = 0;

    for (var tx in res) {
      final amount = tx['amount'] is num
          ? (tx['amount'] as num).toDouble()
          : double.tryParse(tx['amount'].toString()) ?? 0;

      final type = (tx['payment_type'] ?? '').toString().toLowerCase();

      if (type == 'income' || type == 'in' || type == 'credit') {
        totalIncome += amount;
      } else {
        totalExpense += amount;
      }
    }

    return {
      'income': totalIncome,
      'expense': totalExpense,
      'recentTx': res.take(5).toList(),
    };
  }

  Future<List<Map<String, dynamic>>> getAllTransactions() async {
    final response = await _supabase
        .from('transaction')
        .select('transaction_id, created_at, day, amount, sender_name, payment_method, payment_type, anomaly, category, message, user_id')
        .order('created_at', ascending: true);

    if (response is List) {
      return response.map((item) => item as Map<String, dynamic>).toList();
    } else {
      return [];
    }
  }
}
