import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../controllers/chat_controller.dart';

class ChatScreen extends StatefulWidget {
  final dynamic user;
  const ChatScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatController controller = Get.put(ChatController());

  @override
  void initState() {
    super.initState();
    _listenAuthChanges();
  }

  void _listenAuthChanges() {
    Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      final session = data.session;
      if (session?.user != null) {
        await controller.saveUserToDb(session!.user);
      }
    });
  }

  Future<void> _handleLogin() async {
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.myapp://login-callback',
      );
    } catch (e) {
      Get.snackbar('Error', 'Login failed: $e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _handleLogout() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      Get.snackbar('Error', 'Logout failed: $e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Login to Chat')),
        body: Center(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.login),
            label: const Text('Sign in with Google'),
            onPressed: _handleLogin,
          ),
        ),
      );
    }

    final chatUser = types.User(
      id: currentUser.id,
      firstName: currentUser.userMetadata?['name'] ??
          currentUser.userMetadata?['full_name'],
      imageUrl: currentUser.userMetadata?['avatar_url'] ??
          currentUser.userMetadata?['picture'],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.user['name'] ?? widget.user['email'] ?? 'Chat'),
        actions: [
          // IconButton(
          //   icon: const Icon(Icons.logout),
          //   onPressed: _handleLogout,
          // ),
        ],
      ),

      body: Obx(() => controller.isLoading.value
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Upload progress bar
                Obx(() {
                  final progress = controller.uploadProgress.value;
                  if (progress > 0 && progress < 1) {
                    return Column(
                      children: [
                        LinearProgressIndicator(value: progress),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text('${(progress * 100).toStringAsFixed(0)}% uploading...'),
                        ),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                }),
                Expanded(

                  child: Chat(

                    messages: controller.messages.reversed.toList(),
                    onSendPressed: (partial) {
                      controller.sendMessage(partial.text, chatUser);

                      // for(int i=0;i<partial.text.length;i++){
                      //
                      // }
                    }
                       ,
                    user: chatUser,
                    showUserAvatars: false,
                    showUserNames: true,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.image),
                      tooltip: 'Send Image',
                      onPressed: () => controller.sendMediaMessage(context, chatUser, mediaType: 'image'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.videocam),
                      tooltip: 'Send Video',
                      onPressed: () => controller.sendMediaMessage(context, chatUser, mediaType: 'video'),
                    ),
                  ],
                ),
              ],
            )),
    );
  }
}
