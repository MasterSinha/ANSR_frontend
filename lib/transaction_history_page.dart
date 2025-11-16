// lib/transaction_history_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tansr/data_service.dart';

// Model for a single transaction
class Transaction {
  final int id;
  final String title;
  final DateTime date;
  final double amount;
  final bool isDeposit;
  final String category;
  final String paymentMethod;
  final String message;

  Transaction({
    required this.id,
    required this.title,
    required this.date,
    required this.amount,
    required this.isDeposit,
    required this.category,
    required this.paymentMethod,
    required this.message,
  });
}

// Enum for filtering transactions
enum TxFilter { all, income, expense }

class TransactionHistoryPage extends StatefulWidget {
  const TransactionHistoryPage({super.key});

  @override
  State<TransactionHistoryPage> createState() => _TransactionHistoryPageState();
}

class _TransactionHistoryPageState extends State<TransactionHistoryPage> {
  final _dataService = DataService();
  late Future<List<Transaction>> _transactionsFuture;

  // Formatters
  final _dateFormatter = DateFormat.yMMMMd();
  final _shortDate = DateFormat.yMMMd();
  final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

  // Filter and search state
  String _search = '';
  TxFilter _txFilter = TxFilter.all;

  @override
  void initState() {
    super.initState();
    _transactionsFuture = _getTransactions();
  }

  Future<List<Transaction>> _getTransactions() async {
    final data = await _dataService.getAllTransactions();
    // Convert raw map data to Transaction objects
    return data.map((row) => _mapRowToTransaction(row)).whereType<Transaction>().toList();
  }

  // Refresh the data
  Future<void> _refresh() async {
    setState(() {
      _transactionsFuture = _getTransactions();
    });
  }

  // Helper to map a Supabase row to a Transaction object
  Transaction? _mapRowToTransaction(Map<String, dynamic> row) {
    try {
      final idRaw = row['transaction_id'];
      final id = idRaw is int ? idRaw : int.tryParse(idRaw?.toString() ?? '') ?? DateTime.now().millisecondsSinceEpoch;

      DateTime date;
      final created = row['created_at'];
      if (created != null) {
        date = DateTime.tryParse(created.toString()) ?? DateTime.now();
      } else if (row['day'] != null) {
        date = DateTime.tryParse(row['day'].toString()) ?? DateTime.now();
      } else {
        date = DateTime.now();
      }

      double amount = 0.0;
      final a = row['amount'];
      if (a is num) {
        amount = a.toDouble();
      } else if (a != null) {
        var s = a.toString().replaceAll(RegExp(r'[^\d\.\-]'), '');
        amount = double.tryParse(s) ?? 0.0;
      }

      final pt = (row['payment_type'] ?? '').toString().toLowerCase();
      final isDeposit = (pt == 'income' || pt == 'in' || pt == 'credit');

      final rawTitle = (row['message'] ?? row['category'] ?? row['sender_name'] ?? '').toString();
      final title = rawTitle.isEmpty ? (isDeposit ? 'Income' : 'Expense') : rawTitle;

      return Transaction(
        id: id,
        title: title,
        date: date,
        amount: amount,
        isDeposit: isDeposit,
        category: (row['category'] ?? '').toString(),
        paymentMethod: (row['payment_method'] ?? '').toString(),
        message: (row['message'] ?? '').toString(),
      );
    } catch (e) {
      debugPrint('mapRow error: $e');
      return null;
    }
  }

  // Apply local search and filter to the list of transactions
  List<Transaction> _getFilteredTransactions(List<Transaction> transactions) {
    final q = _search.trim().toLowerCase();
    return transactions.where((t) {
      if (_txFilter == TxFilter.income && !t.isDeposit) return false;
      if (_txFilter == TxFilter.expense && t.isDeposit) return false;

      if (q.isEmpty) return true;
      return t.title.toLowerCase().contains(q) ||
          t.category.toLowerCase().contains(q) ||
          t.paymentMethod.toLowerCase().contains(q) ||
          _currency.format(t.amount).toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction History'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh)],
      ),
      body: FutureBuilder<List<Transaction>>(
        future: _transactionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No transactions found'));
          }

          final transactions = snapshot.data!;
          final filtered = _getFilteredTransactions(transactions);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: Column(
              children: [
                _HeaderCard(transactions: transactions, currency: _currency),
                _FilterBar(
                  onSearchChanged: (val) => setState(() => _search = val),
                  filter: _txFilter,
                  onFilterChanged: (val) => setState(() => _txFilter = val),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      return _TransactionRow(
                        t: filtered[index],
                        currency: _currency,
                        shortDate: _shortDate,
                        onTap: () => _showDetails(filtered[index]),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showDetails(Transaction t) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Wrap(
            children: [
              Center(child: Container(width: 40, height: 4, color: Colors.black12)),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Text(t.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                Text('${t.isDeposit ? '+' : '-'}${_currency.format(t.amount.abs())}',
                    style: TextStyle(color: t.isDeposit ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 8),
              Text(_dateFormatter.format(t.date), style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 16),
              ListTile(leading: const Icon(Icons.category), title: Text(t.category.isEmpty ? '—' : t.category)),
              ListTile(leading: const Icon(Icons.payment), title: Text(t.paymentMethod.isEmpty ? '—' : t.paymentMethod)),
              ListTile(leading: const Icon(Icons.note), title: Text(t.message.isEmpty ? '—' : t.message)),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                  onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close), label: const Text('Close')),
            ],
          ),
        );
      },
    );
  }
}

// --- UI Helper Widgets ---

class _HeaderCard extends StatelessWidget {
  final List<Transaction> transactions;
  final NumberFormat currency;

  const _HeaderCard({required this.transactions, required this.currency});

  @override
  Widget build(BuildContext context) {
    final income = transactions.where((t) => t.isDeposit).fold<double>(0.0, (p, e) => p + e.amount);
    final expense = transactions.where((t) => !t.isDeposit).fold<double>(0.0, (p, e) => p + e.amount);
    final balance = income - expense;

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Balance', style: TextStyle(fontSize: 14, color: Colors.black54)),
                  const SizedBox(height: 6),
                  Text(currency.format(balance), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(children: [
                    _miniStat(Colors.green, '+${currency.format(income)}', 'Income'),
                    const SizedBox(width: 12),
                    _miniStat(Colors.redAccent, '-${currency.format(expense)}', 'Expense'),
                  ])
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniStat(Color color, String amount, String label) {
    return Row(children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(amount, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54))
      ])
    ]);
  }
}

class _FilterBar extends StatelessWidget {
  final ValueChanged<String> onSearchChanged;
  final TxFilter filter;
  final ValueChanged<TxFilter> onFilterChanged;

  const _FilterBar({required this.onSearchChanged, required this.filter, required this.onFilterChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search transactions...',
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
              onChanged: onSearchChanged,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: DropdownButton<TxFilter>(
              value: filter,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: TxFilter.all, child: Text('All')),
                DropdownMenuItem(value: TxFilter.income, child: Text('Income')),
                DropdownMenuItem(value: TxFilter.expense, child: Text('Expense')),
              ],
              onChanged: (v) => onFilterChanged(v ?? TxFilter.all),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final Transaction t;
  final NumberFormat currency;
  final DateFormat shortDate;
  final VoidCallback onTap;

  const _TransactionRow({required this.t, required this.currency, required this.shortDate, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      child: Card(
        elevation: 1.2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: t.isDeposit ? Colors.green.shade50 : Colors.orange.shade50,
                  child: Icon(t.isDeposit ? Icons.arrow_downward : Icons.arrow_upward,
                      color: t.isDeposit ? Colors.green : Colors.orange),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Row(children: [
                        if (t.category.isNotEmpty)
                          Text(t.category, style: const TextStyle(color: Colors.black45, fontSize: 12)),
                        if (t.category.isNotEmpty) const SizedBox(width: 6),
                        Text(shortDate.format(t.date), style: const TextStyle(color: Colors.black45, fontSize: 12)),
                        if (t.paymentMethod.isNotEmpty) const SizedBox(width: 6),
                        if (t.paymentMethod.isNotEmpty)
                          Text('• ${t.paymentMethod}', style: const TextStyle(color: Colors.black45, fontSize: 12)),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${t.isDeposit ? '+' : '-'}${currency.format(t.amount.abs())}',
                        style: TextStyle(color: t.isDeposit ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 6),
                    const Icon(Icons.chevron_right, color: Colors.black26, size: 18),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
