import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/molecules/user_list.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:intl/intl.dart';

class RoomMembersListWidget extends StatefulWidget {
  const RoomMembersListWidget(this.room, {super.key});
  final Room room;

  @override
  State<RoomMembersListWidget> createState() => _RoomMembersListWidgetState();
}

class _RoomMembersListWidgetState extends State<RoomMembersListWidget> {
  late bool isDirectMessage;
  @override
  void initState() {
    isDirectMessage =
        widget.room.client
            .getComponent<DirectMessagesComponent>()
            ?.isRoomDirectMessage(widget.room) ??
        false;
    super.initState();
  }

  String get labelRoomMembers => Intl.message(
    "Room Members",
    name: "labelRoomMembers",
    desc: "Label for the room members list in the room members list widget",
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isDirectMessage) tiamat.Text.labelLow(labelRoomMembers),
        Expanded(
          child: SizedBox(
            width: MediaQuery.of(context).desktop
                ? isDirectMessage
                      ? 300
                      : 200
                : null,
            child: RoomMemberList(
              key: ValueKey("room-participant-list-key-${widget.room.localId}"),
              widget.room,
            ),
          ),
        ),
      ],
    );
  }
}
