import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komunika/core/extensions/snackbar_extension.dart';
import 'package:komunika/core/services/custom_bluetooth_service.dart';
import 'package:komunika/features/chat/domain/entities/message.dart';
import 'package:komunika/features/chat/domain/repositories/chat_repository.dart';
import 'package:komunika/features/chat/presentation/cubit/chat_cubit.dart';
import 'package:komunika/features/chat/presentation/widgets/message_bubble.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// TODO remove _lastMessageCount

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.roomId,
    required this.subSpaceName,
    super.key,
  });

  final int roomId;
  final String subSpaceName;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _sendMessage(BuildContext descendantContext) {
    final String text = _textController.text.trim();

    if (text.isNotEmpty) {
      // ? use the descendantContext to find the ChatCubit
      descendantContext.read<ChatCubit>().sendMessage(text);
      _textController.clear();
      // ? use the descendantContext for FocusScope as well
      FocusScope.of(descendantContext).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create:
          (blocContext) => ChatCubit(
            chatRepository: blocContext.read<ChatRepository>(),
            roomId: widget.roomId,
          ),
      child: Scaffold(
        appBar: AppBar(title: Text(widget.subSpaceName)),
        body: BlocListener<ChatCubit, ChatState>(
          listenWhen: (previousState, currentState) {
            return currentState is ChatLoaded &&
                previousState is ChatLoaded &&
                currentState.messages.length > previousState.messages.length;
          },
          listener: (context, state) {
            if (state is ChatLoaded) {
              final String? currentUserId =
                  Supabase.instance.client.auth.currentUser?.id;
              // if (state.messages.isNotEmpty &&
              //     state.messages.length > _lastMessageCount) {

              final Message latestMessage =
                  state.messages.first; //? check this could be got it flip
              if (latestMessage.senderId != currentUserId) {
                print(
                  "New message received from official, triggering BLE command!",
                );
                try {
                  // ? make sure to provide/use CustomBluetoothService
                  //?  and the device is connected.
                  final CustomBluetoothService bleService =
                      context.read<CustomBluetoothService>();
                  if (bleService.isConnected.value) {
                    //? check if connected
                    bleService.sendCommand(
                      "Vibrate",
                    ); //? "vibrate" for new message
                  } else {
                    print("BLE: Not connected, can't send command.");
                  }
                } catch (e) {
                  print("Error sending BLE command: $e");
                  // ? or show a less prentious error, e.g., a small toast
                  context.customShowSnackBar("Wristband not notified.");
                }
              }
              // }
              //? update the last message count for debugging
              _lastMessageCount = state.messages.length;
              print("Just updated message count to: $_lastMessageCount");
            }
          },
          //? Optional: listenWhen to optimize if needed, e.g.,
          //? listenWhen: (previous, current) =>
          // ?   current is ChatLoaded && previous is ChatLoaded && current.messages.length > previous.messages.length,
          child: Column(
            children: [
              Expanded(
                child: BlocBuilder<ChatCubit, ChatState>(
                  builder: (context, state) {
                    final String? currentUserId =
                        Supabase.instance.client.auth.currentUser?.id;
                    if (state is ChatLoading || state is ChatInitial) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (state is ChatError) {
                      return Center(
                        child: Text(
                          "Error: ${state.message}",
                          style: const TextStyle(color: Colors.red),
                        ),
                      );
                    } else if (state is ChatLoaded) {
                      if (state.messages.isEmpty) {
                        _lastMessageCount = 0; //? reset if messages empty
                        return const Center(
                          child: Text("No messages yet. Start chatting!"),
                        );
                      }
                      // ? here chat is loaded and not empty
                      return ListView.builder(
                        reverse: true,
                        itemCount: state.messages.length,
                        itemBuilder: (context, index) {
                          final Message message = state.messages[index];
                          final bool isMe = message.senderId == currentUserId;

                          return MessageBubble(message: message, isMe: isMe);
                        },
                      );
                    } else {
                      return const Center(child: Text("Something went wrong"));
                    }
                  },
                ),
              ),
              Builder(
                builder: (BuildContext descendantContext) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                    ),
                    padding: EdgeInsets.only(
                      top: 8.0,

                      bottom:
                          MediaQuery.of(context).viewInsets.bottom > 0
                              ? 8.0
                              : 32.0,
                      left: 8.0,
                      right: 8.0,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            maxLines: 6,
                            minLines: 1,
                            controller: _textController,
                            textCapitalization: TextCapitalization.sentences,
                            autocorrect: true,
                            enableSuggestions: true,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.grey[100],
                              hintText: "Type your message...",
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20.0),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                            ),
                            onSubmitted: (_) => _sendMessage(descendantContext),
                          ),
                        ),
                        const SizedBox(width: 8.0),
                        IconButton(
                          onPressed: () => _sendMessage(descendantContext),
                          tooltip: "Send Message",
                          icon: Icon(
                            Icons.send,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
