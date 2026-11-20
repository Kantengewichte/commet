import 'dart:async';

import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/atoms/tiny_pill.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/matrix/room_address_settings/matrix_room_add_local_alias_view.dart';
import 'package:flutter/material.dart';
import 'package:implicitly_animated_list/implicitly_animated_list.dart';
import 'package:tiamat/tiamat.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:intl/intl.dart';

class MatrixRoomAddressSettingsView extends StatefulWidget {
  const MatrixRoomAddressSettingsView(
    this.knownAliases, {
    this.mainAlias,
    this.userHomeserver,
    required this.mainAliasChangedStream,
    required this.isAliasAvailable,
    required this.canChangeMainAlias,
    required this.canAddLocalAlias,
    required this.createAlias,
    required this.deleteAlias,
    required this.setMainAlias,
    required this.publishAlias,
    required this.unpublishAlias,
    required this.publishedAliases,
    super.key,
  });
  final List<String> knownAliases;
  final List<String> publishedAliases;
  final String? mainAlias;
  final String? userHomeserver;
  final bool canChangeMainAlias;
  final bool canAddLocalAlias;
  final Stream<String?> mainAliasChangedStream;
  final Future<bool> Function(String alias) setMainAlias;
  final Future<bool> Function(String alias) deleteAlias;
  final Future<bool> Function(String alias) isAliasAvailable;
  final Future<String?> Function(String alias) createAlias;
  final Future<void> Function(String alias) publishAlias;
  final Future<void> Function(String alias) unpublishAlias;
  @override
  State<MatrixRoomAddressSettingsView> createState() =>
      _MatrixRoomAddressSettingsViewState();
}

class _MatrixRoomAddressSettingsViewState
    extends State<MatrixRoomAddressSettingsView> {
  String? errorMessage;
  StreamSubscription? subscription;

  @override
  void initState() {
    subscription = widget.mainAliasChangedStream.listen(onMainAliasChanged);

    super.initState();
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  void onMainAliasChanged(String? value) {
    setState(() {});
  }

  String get labelRoomAddresses => Intl.message(
    "Room Addresses",
    desc: "Label for the room addresses settings page",
    name: "labelRoomAddresses",
  );

  @override
  Widget build(BuildContext context) {
    return Panel(
      header: labelRoomAddresses,
      mode: TileType.surfaceContainerLow,
      child: Column(
        children: [
          if (widget.knownAliases.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
              child: mainAliasSelector(),
            ),
          aliasList(),
        ],
      ),
    );
  }

  String get labelOtherAddresses => Intl.message(
    "Other Addresses:",
    name: "labelOtherAddresses",
    desc: "Label for the other addresses section in the room addresses settings page",
  );

  String get labelnolocalAddresses => Intl.message(
    "This room does not currently have any local Addresses",
    name: "labelnolocalAddresses",
    desc: "Label for when a room has no local addresses in the room addresses settings page",
  );

  String get labelunpublishAddress => Intl.message(
    "Unpublish Address",
    name: "labelunpublishAddress",
    desc: "Label for the unpublish address tooltip in the room addresses settings page",
  );

  String get labelpublishAddress => Intl.message(
    "Publish Address",
    name: "labelpublishAddress",
    desc: "Label for the publish address tooltip in the room addresses settings page",
  );

  String get labeldeletelocalAddress => Intl.message(
    "Delete Local Address",
    name: "labeldeletelocalAddress",
    desc: "Label for the delete local address tooltip in the room addresses settings page",
  );

  String get labeladdlocalAddress => Intl.message(
    "Add Local Address",
    name: "labeladdlocalAddress",
    desc: "Label for the add local address tooltip in the room addresses settings page",
  );

  Widget aliasList() {
    double boxSize = MediaQuery.of(context).mobile ? 40 : 30;
    double iconSize = MediaQuery.of(context).mobile ? 25 : 20;
    return Panel(
      mode: TileType.surfaceContainer,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          tiamat.Text.labelLow(labelOtherAddresses),
          if (widget.knownAliases.isEmpty)
            SizedBox(
              height: 50,
              child: Center(child: tiamat.Text.labelLow(labelnolocalAddresses)),
            ),
          ImplicitlyAnimatedList(
            shrinkWrap: true,
            itemData: widget.knownAliases,
            itemBuilder: (context, data) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IgnorePointer(
                        ignoring: isEditable(data) == false,
                        child: SizedBox(
                          width: boxSize,
                          height: boxSize,
                          child: tiamat.Tooltip(
                            text: isPublished(data)
                                ? labelunpublishAddress
                                : labelpublishAddress,
                            child: tiamat.IconToggle(
                              icon: Icons.public,
                              size: iconSize,
                              state: isPublished(data),
                              onPressed: (newState) {
                                if (newState) {
                                  widget.publishAlias(data);
                                } else {
                                  widget.unpublishAlias(data);
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: tiamat.Text.label(data),
                        ),
                      ),
                      if (data == widget.mainAlias) const TinyPill("Main"),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: boxSize,
                      height: boxSize,
                      child: isEditable(data)
                          ? tiamat.Tooltip(
                              text: labeldeletelocalAddress,
                              child: tiamat.IconButton(
                                icon: Icons.close,
                                size: iconSize,
                                onPressed: () => deleteAlias(data),
                                iconColor: Theme.of(context).colorScheme.error,
                              ),
                            )
                          : Container(),
                    ),
                  ),
                ],
              );
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              errorMessage == null
                  ? Container()
                  : tiamat.Text.error(errorMessage!),
              SizedBox(
                width: 40,
                height: 40,
                child: tiamat.Tooltip(
                  preferredDirection: AxisDirection.left,
                  text: labeladdlocalAddress,
                  child: tiamat.CircleButton(
                    icon: Icons.add,
                    onPressed: showAddAliasDialog,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void showAddAliasDialog() {
    AdaptiveDialog.show(
      context,
      title: labeladdlocalAddress,
      builder: (context) {
        return MatrixRoomAddLocalAliasView(
          widget.userHomeserver!,
          widget.isAliasAvailable,
          widget.createAlias,
        );
      },
    );
  }

  String get labelSelectMainAddress => Intl.message(
    "Select a main room address",
    name: "labelSelectMainAddress",
    desc: "Label for the select main address tooltip in the room addresses settings page",
  );

  String get labelThisRoomDoesNotHaveAMainAddress => Intl.message(
    "This room does not have a set main address",
    name: "labelThisRoomDoesNotHaveAMainAddress",
    desc: "Label for when a room does not have a main address in the room addresses settings page",
  );

  Widget mainAliasSelector() {
    return IgnorePointer(
      ignoring: widget.canChangeMainAlias == false,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          tiamat.DropdownSelector(
            items: widget.knownAliases,
            value: widget.mainAlias,
            itemHeight: 60,
            hint: tiamat.Text.labelLow(
              widget.canChangeMainAlias
                  ? labelSelectMainAddress
                  : labelThisRoomDoesNotHaveAMainAddress,
            ),
            onItemSelected: (item) => widget.setMainAlias(item!),
            itemBuilder: (item) {
              return Row(
                children: [
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: tiamat.Text.label(item!),
                    ),
                  ),
                  if (item == widget.mainAlias) const TinyPill("Main"),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String labelAreYouSureYouWantToDeleteThisAddress(String item) => Intl.message(
    'Are you sure you want to delete the address $item?',
    name: "labelAreYouSureYouWantToDeleteThisAddress",
    desc: "Label for the confirmation dialog when deleting a local address in the room addresses settings page",
    args: [item],
  );

  String labelYouDoNotHavePermissionToDeleteThisAddress(String item) =>
      Intl.message(
        "You do not have permission to delete '$item'",
        name: "labelYouDoNotHavePermissionToDeleteThisAddress",
        desc: "Label for the error message when trying to delete a local address without permission in the room addresses settings page",
        args: [item],
      );

  Future<void> deleteAlias(String item) async {
    var confirmation = await AdaptiveDialog.confirmation(
      context,
      prompt: labelAreYouSureYouWantToDeleteThisAddress(item),
    );

    if (confirmation != true) {
      return;
    }

    var result = await widget.deleteAlias(item);

    if (result == false) {
      setState(() {
        errorMessage = labelYouDoNotHavePermissionToDeleteThisAddress(item);
      });
    }
  }

  bool isEditable(String item) {
    if (item.split(":").last == widget.userHomeserver) {
      return true;
    }

    return false;
  }

  bool isPublished(String item) {
    return widget.publishedAliases.contains(item);
  }
}
