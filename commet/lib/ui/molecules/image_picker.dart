import 'dart:typed_data';

import 'package:commet/utils/picker_utils.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart';
import 'package:intl/intl.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class ImagePickerButton extends StatefulWidget {
  const ImagePickerButton({
    super.key,
    this.currentImage,
    this.onImagePicked,
    this.onImageRead,
    this.size = 128,
    this.cropAspectRatio,
    this.withData = false,
    this.icon,
  });
  final ImageProvider? currentImage;
  final bool withData;
  final double? cropAspectRatio;
  final double size;
  final IconData? icon;
  final Function(String filepath)? onImagePicked;
  final Function(Uint8List bytes, String? mimeType, String filePath)?
  onImageRead;

  @override
  State<ImagePickerButton> createState() => _ImagePickerButtonState();
}

class _ImagePickerButtonState extends State<ImagePickerButton> {
  ImageProvider? image;

  @override
  void initState() {
    image = widget.currentImage;
    super.initState();
  }

  String get pickImagePrompt => Intl.message(
    "Pick Image",
    name: "pickImagePrompt",
    desc: "Button text for picking an image",
  );

  @override
  Widget build(BuildContext context) {
    return tiamat.Tooltip(
      text: pickImagePrompt,
      preferredDirection: AxisDirection.down,
      child: ImageButton(
        icon: image == null ? widget.icon : null,
        size: widget.size,
        image: image,
        onTap: pickImage,
      ),
    );
  }

  void pickImage() async {
    var result = await PickerUtils.pickImageAndCrop(
      context,
      aspectRatio: widget.cropAspectRatio,
    );

    if (result == null) return;

    setState(() {
      image = Image.memory(result).image;
    });

    widget.onImageRead?.call(result, null, "");
  }
}
