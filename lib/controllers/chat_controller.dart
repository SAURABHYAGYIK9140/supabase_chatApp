import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'dart:io';
import 'package:flutter/foundation.dart'; // for kIsWeb
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;


class ChatController extends GetxController {
  final SupabaseClient supabase = Supabase.instance.client;
  final RxList<types.Message> messages = <types.Message>[].obs;
  String? currentConversationId;
  RealtimeChannel? _messageChannel;
  StreamSubscription<dynamic>? _realtimeSub;
  var isLoading = false.obs;
  var uploadProgress = 0.0.obs;

  @override
  void onInit() {
    super.onInit();
    // Removed fetchMessages() and subscribeToMessages() as they are no longer needed
  }

  /// 1. Start or get a direct conversation between two users
  Future<String?> startOrGetDirectConversation(String userId1, String userId2) async {
    // 1. Get all conversation_ids for both users
    final participants = await supabase
        .from('conversation_participants')
        .select('conversation_id, user_id')
        .inFilter('user_id', [userId1, userId2]);
    // 2. Group by conversation_id
    final Map<String, List<String>> convoToUsers = {};
    for (final p in participants) {
      final cid = p['conversation_id'] as String;
      final uid = p['user_id'] as String;
      convoToUsers.putIfAbsent(cid, () => []).add(uid);
    }
    // 3. Find a conversation_id where both users are present
    String? foundConvoId;
    convoToUsers.forEach((cid, uids) {
      if (uids.toSet().containsAll([userId1, userId2])) {
        foundConvoId = cid;
      }
    });
    if (foundConvoId != null) {
      // Check if this conversation is of type 'direct'
      final convo = await supabase
          .from('conversations')
          .select('id, type')
          .eq('id', foundConvoId!)
          .maybeSingle();

      if (convo != null && convo['type'] == 'direct') {
        return foundConvoId;
      }
    }
    // 4. Create new conversation if not found
    final convo = await supabase
        .from('conversations')
        .insert({
          'type': 'direct',
          'created_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();
    final convoId = convo['id'] as String;
    await supabase.from('conversation_participants').insert([
      {'conversation_id': convoId, 'user_id': userId1, 'role': 'user'},
      {'conversation_id': convoId, 'user_id': userId2, 'role': 'user'},
    ]);
    return convoId;
  }

  /// 2. Send a message in a conversation
  Future<void> sendMessage(String text, types.User user) async {
    if (currentConversationId == null) return;
    await supabase.from('messages').insert({
      'conversation_id': currentConversationId,
      'content': text,
      'sender_id': user.id,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
  Future<void> sendMediaMessage(BuildContext context, types.User user, {required String mediaType}) async {
    if (currentConversationId == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: mediaType == 'image'
          ? FileType.image
          : mediaType == 'video'
              ? FileType.video
              : FileType.any,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    final pickedFile = result.files.single;
    final uniqueName = '${const Uuid().v4()}_${pickedFile.name}';
    final storagePath = 'chat_media/$currentConversationId/$uniqueName';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Uploading...'),
        content: Row(
          children: const [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Please wait while your file is uploading.')),
          ],
        ),
      ),
    );
    try {
      if (kIsWeb) {
        if (pickedFile.bytes == null) {
          Navigator.of(context).pop();
          return;
        }
        await supabase.storage.from('chat-media').uploadBinary(
          storagePath,
          pickedFile.bytes!,
          fileOptions: const FileOptions(upsert: true),
        );
      } else {
        final file = File(pickedFile.path!);
        await supabase.storage.from('chat-media').upload(
          storagePath,
          file,
          fileOptions: const FileOptions(upsert: true),
        );
      }
      final publicUrl = supabase.storage.from('chat-media').getPublicUrl(storagePath);
      await supabase.from('messages').insert({
        'conversation_id': currentConversationId,
        'content': publicUrl,
        'sender_id': user.id,
        'created_at': DateTime.now().toIso8601String(),
        'type': mediaType,
      });
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload complete!')),
      );
    } catch (e) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    }
  }

  /// 3. Fetch messages for a conversation
  void fetchMessages(String conversationId) async {
    isLoading.value = true;
    final response = await supabase
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true);
    messages.assignAll(response.map<types.Message>((msg) => _fromMap(msg)).toList());
    currentConversationId = conversationId;
    subscribeToMessages(conversationId);
    isLoading.value = false;
  }

  void subscribeToMessages(String conversationId) {
    // Unsubscribe from previous channel if any
    _messageChannel?.unsubscribe();
    _messageChannel = supabase.channel('messages:$conversationId');
    _messageChannel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      filter: PostgresChangeFilter(
        column: 'conversation_id',
        value: conversationId,
        type: PostgresChangeFilterType.eq,
      ),
      callback: (payload) {
        final newMsg = _fromMap(payload.newRecord);
        messages.add(newMsg);
      },
    );
    _messageChannel!.subscribe();
  }

  @override
  void onClose() {
    _messageChannel?.unsubscribe();
    _realtimeSub?.cancel();
    super.onClose();
  }
  /// 4. List all conversations for the current user
  Future<List<Map<String, dynamic>>> fetchUserConversations(String userId) async {
    final convos = await supabase
        .from('conversation_participants')
        .select('conversation_id, conversations!inner(id, type, name, created_at)')
        .eq('user_id', userId);
    return convos.map<Map<String, dynamic>>((e) => e['conversations']).toList();
  }

  types.Message _fromMap(Map<String, dynamic> map) {
    final type = map['type'] ?? 'text';
    if (type == 'image') {
      return types.ImageMessage(
        id: map['id'].toString(),
        author: types.User(id: map['sender_id'] ?? ''),
        name: 'Image',
        size: 0,
        uri: map['content'] ?? '',
        createdAt: DateTime.parse(map['created_at']).millisecondsSinceEpoch,
      );
    } else if (type == 'video') {
      return types.FileMessage(
        id: map['id'].toString(),
        author: types.User(id: map['sender_id'] ?? ''),
        name: 'Video',
        size: 0,
        uri: map['content'] ?? '',
        mimeType: 'video/mp4',
        createdAt: DateTime.parse(map['created_at']).millisecondsSinceEpoch,
      );
    } else {
      return types.TextMessage(
        id: map['id'].toString(),
        author: types.User(id: map['sender_id'] ?? ''),
        text: map['content'] ?? '',
        createdAt: DateTime.parse(map['created_at']).millisecondsSinceEpoch,
      );
    }
  }

  /// Save or update user info in `users` table
  Future<void> saveUserToDb(User user) async {
    try {
      await supabase.from('users').upsert({
        'id': user.id,
        'name': user.userMetadata?['name'] ??
            user.userMetadata?['full_name'],
        'email': user.email,
        'avatar_url': user.userMetadata?['avatar_url'] ??
            user.userMetadata?['picture'],
      });
    } catch (e) {
      Get.snackbar('Error', 'Failed to save user: $e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }


}
