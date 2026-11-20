import 'package:commet/utils/common_strings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' as material;
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart';
import 'package:intl/intl.dart';

class EditableLabel extends StatefulWidget {
  const EditableLabel({
    super.key,
    required this.initialText,
    this.type = TextType.label,
    this.onTextConfirmed,
  });
  final TextType type;
  final Function(String? newText)? onTextConfirmed;
  final String initialText;

  @override
  State<EditableLabel> createState() => _EditableLabelState();
}

class _EditableLabelState extends State<EditableLabel> {
  bool editingName = false;
  late TextEditingController nameController;
  late String text;

  @override
  void initState() {
    text = widget.initialText;
    nameController = TextEditingController(text: text);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [nameEditor(), toggleNameEdit()]);
  }

  void _confirmName() {
    var name = nameController.text.trim();
    if (name.isEmpty) return;

    widget.onTextConfirmed?.call(name);

    setState(() {
      text = nameController.text;
      editingName = false;
    });
  }

  Widget nameEditor() {
    return material.Material(
      color: material.Colors.transparent,
      child: editingName
          ? SizedBox(
              width: 200,
              child: TextInput(
                maxLines: 1,
                controller: nameController,
                onSubmitted: (_) => _confirmName(),
              ),
            )
          : tiamat.Text(text, type: widget.type),
    );
  }

  String get changeTooltip => Intl.message(
    "Change text",
    name: 'changeTooltip',
    desc: 'Tooltip for changing the text of an editable label',
  );

  Widget toggleNameEdit() {
    return editingName
        ? Tooltip(
            text: CommonStrings.promptConfirm,
            preferredDirection: AxisDirection.right,
            child: tiamat.IconButton(
              icon: material.Icons.check,
              onPressed: () => _confirmName(),
            ),
          )
        : Tooltip(
            text: changeTooltip,
            preferredDirection: AxisDirection.right,
            child: tiamat.IconButton(
              icon: material.Icons.edit,
              onPressed: () {
                setState(() {
                  editingName = true;
                });
              },
            ),
          );
  }
}
