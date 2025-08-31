import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../controllers/chat_controller.dart';
import 'chat_screen.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({Key? key}) : super(key: key);

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final supabase = Supabase.instance.client;
  List<dynamic> users = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchAuthUsers();
  }

  Future<void> fetchAuthUsers() async {
    try {
      final response = await supabase
          .from('users')
          .select('id, name, email, avatar_url');

      setState(() {
        users = (response as List)
            .map((e) => e as Map<String, dynamic>)
            .toList();
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      Get.snackbar('Error', 'Failed to fetch users: $e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('All Users'),actions: [
        IconButton(
          icon: const Icon(Icons.logout),
          onPressed: () async {
            final controller = Get.isRegistered<ChatController>() ? Get.find<ChatController>() : Get.put(ChatController());

            await controller.saveUserToDb(Supabase.instance.client.auth.currentUser!);

          },
        ),
      ],),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: users.length,
              itemBuilder: (context, index) {
                final user = users[index];
                return ListTile(
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundImage: user['avatar_url'] != null && user['avatar_url'].toString().isNotEmpty
                        ? NetworkImage(user['avatar_url'])
                        : null,
                    child: (user['avatar_url'] == null || user['avatar_url'].toString().isEmpty)
                        ? const Icon(Icons.person, size: 20)
                        : null,
                  ),
                  title: Text(user['name'] ?? user['email']),
                  subtitle: Text(user['email'] ?? ''),
                  trailing: ElevatedButton(
                    child: const Text('Chat'),
                    onPressed: () async {
                      final currentUser = Supabase.instance.client.auth.currentUser;
                      if (currentUser == null) {
                        Get.snackbar('Error', 'You must be logged in to chat', snackPosition: SnackPosition.BOTTOM);
                        return;
                      }
                      final controller = Get.isRegistered<ChatController>() ? Get.find<ChatController>() : Get.put(ChatController());
                      final convoId = await controller.startOrGetDirectConversation(currentUser.id, user['id']);
                      if (convoId != null) {

                        controller.messages.clear();
                        controller.fetchMessages(convoId);
                        Get.to(() => ChatScreen(user: user));
                      } else {
                        Get.snackbar('Error', 'Could not start chat', snackPosition: SnackPosition.BOTTOM);
                      }
                    },
                  ),
                );
              },
            ),
    );
  }
}
