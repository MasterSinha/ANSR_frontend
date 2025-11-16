// lib/home_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tansr/data_service.dart';
import 'package:tansr/login_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _dataService = DataService();
  late Future<Map<String, dynamic>> _homeDataFuture;

  final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
  final shortDate = DateFormat.MMMd();

  @override
  void initState() {
    super.initState();
    _homeDataFuture = _dataService.getHomeData();
  }

  Future<void> _refresh() async {
    setState(() {
      _homeDataFuture = _dataService.getHomeData();
    });
  }

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
          IconButton(icon: const Icon(Icons.notifications_none), onPressed: () {}),
          const CircleAvatar(backgroundImage: NetworkImage('https://picsum.photos/200')),
          const SizedBox(width: 16.0),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _homeDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No data available'));
          }

          final data = snapshot.data!;
          final income = data['income'] as double;
          final expense = data['expense'] as double;
          final recentTx = data['recentTx'] as List<Map<String, dynamic>>;
          final balance = income - expense;

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                const Text(
                  'Welcome!',
                  style: TextStyle(fontSize: 24.0, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16.0),
                _BalanceCard(balance: balance, income: income, expense: expense, currency: currency),
                const SizedBox(height: 16.0),
                const _ActionButtons(),
                const SizedBox(height: 16.0),
                const Text(
                  'Recent Transactions',
                  style: TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8.0),
                if (recentTx.isEmpty)
                  const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Text("No recent transactions"),
                      )),
                ...recentTx.map((t) {
                  final isIncome = (t['payment_type'] ?? '').toString().toLowerCase().contains('income');
                  final amount = t['amount'] is num
                      ? (t['amount'] as num).toDouble()
                      : double.tryParse(t['amount'].toString()) ?? 0;

                  return _TransactionItem(
                    icon: isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                    color: isIncome ? Colors.green : Colors.red,
                    title: (t['category'] ?? t['message'] ?? 'Transaction').toString(),
                    date: shortDate.format(DateTime.tryParse(t['created_at'].toString()) ?? DateTime.now()),
                    amount: (isIncome ? "+" : "-") + currency.format(amount.abs()),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.balance,
    required this.income,
    required this.expense,
    required this.currency,
  });

  final double balance;
  final double income;
  final double expense;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF2C3A47),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Total Balance', style: TextStyle(color: Colors.white70, fontSize: 16.0)),
            const SizedBox(height: 8.0),
            Text(currency.format(balance), style: const TextStyle(color: Colors.white, fontSize: 32.0, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Income', style: TextStyle(color: Colors.white70, fontSize: 14.0)),
                    const SizedBox(height: 4.0),
                    Text(currency.format(income), style: const TextStyle(color: Colors.green, fontSize: 16.0, fontWeight: FontWeight.bold)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Expense', style: TextStyle(color: Colors.white70, fontSize: 14.0)),
                    const SizedBox(height: 4.0),
                    Text(currency.format(expense), style: const TextStyle(color: Colors.red, fontSize: 16.0, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: const [
        _ActionButton(icon: Icons.send, label: 'Send'),
        _ActionButton(icon: Icons.receipt, label: 'Bill'),
        _ActionButton(icon: Icons.show_chart, label: 'Invest'),
        _ActionButton(icon: Icons.more_horiz, label: 'More'),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 24.0,
          backgroundColor: Colors.grey[200],
          child: Icon(icon, color: Colors.black, size: 24.0),
        ),
        const SizedBox(height: 8.0),
        Text(label, style: const TextStyle(fontSize: 12.0)),
      ],
    );
  }
}

class _TransactionItem extends StatelessWidget {
  const _TransactionItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.date,
    required this.amount,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String date;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(date),
        trailing: Text(amount, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0)),
      ),
    );
  }
}
