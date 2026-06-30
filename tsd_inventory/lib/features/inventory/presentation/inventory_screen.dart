import 'package:flutter/material.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key, required this.docCode});
  final String docCode;
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('inventory (Task 18)')));
}
