import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:secure_messenger/ui/theme.dart';
import 'package:secure_messenger/widgets/glass_container.dart';
import 'package:secure_messenger/chat/chat_room_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> dummyChats = [
      {'name': 'Agent K', 'msg': 'Secure channel opened.', 'time': '10:42 AM'},
      {'name': 'Nexus Team', 'msg': 'Keys verified and synced.', 'time': '09:15 AM'},
      {'name': 'Commander', 'msg': 'Deploy the package.', 'time': 'Yesterday'},
    ];

    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppTheme.background, Color(0xFF1A1C29)],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'SECURE CHATS',
                        style: Theme.of(context).textTheme.displayLarge?.copyWith(
                          fontSize: 22,
                          letterSpacing: 1.5,
                          color: AppTheme.neonCyan,
                        ),
                      ).animate().fade().slideY(begin: -0.2),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.neonMagenta, width: 2),
                          image: const DecorationImage(
                            image: NetworkImage('https://i.pravatar.cc/150?img=11'),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ).animate().scale(),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    itemCount: dummyChats.length,
                    itemBuilder: (context, index) {
                      final chat = dummyChats[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: GlassContainer(
                          borderRadius: 16,
                          child: ListTile(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => ChatRoomScreen(
                                    contactName: chat['name']!,
                                  ),
                                ),
                              );
                            },
                            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.neonCyan.withOpacity(0.2),
                              foregroundColor: AppTheme.neonCyan,
                              child: Text(chat['name']![0]),
                            ),
                            title: Text(
                              chat['name']!,
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            subtitle: Text(
                              chat['msg']!,
                              style: const TextStyle(color: AppTheme.textSecondary),
                            ),
                            trailing: Text(
                              chat['time']!,
                              style: const TextStyle(color: AppTheme.neonCyan, fontSize: 12),
                            ),
                          ),
                        ).animate().fade(delay: (100 * index).ms).slideX(begin: 0.1),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: AppTheme.neonMagenta,
        child: const Icon(Icons.add_moderator, color: Colors.white),
      ).animate().scale(delay: 500.ms).shimmer(duration: 1.seconds),
    );
  }
}
