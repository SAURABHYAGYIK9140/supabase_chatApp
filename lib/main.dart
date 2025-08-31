import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/chat_screen.dart';
import 'screens/users_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://cbcceiglkhdsxdptjqdu.supabase.co', // TODO: Replace with your Supabase project URL
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNiY2NlaWdsa2hkc3hkcHRqcWR1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTYyMjQzOTEsImV4cCI6MjA3MTgwMDM5MX0.TEbq_pELcCqHPQ5ZMIgZCFp6kIr6RzZ0BBqH1ZQEAVs', // TODO: Replace with your Supabase anon key
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      debugShowCheckedModeBanner:   false,
      title: 'Supabase Chat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: UsersScreen(),
    );
  }
}
