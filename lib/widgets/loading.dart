import 'package:flutter/material.dart';

class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({super.key, required this.show, required this.child});

  final bool show;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (show)
          const ModalBarrier(
            dismissible: false,
            color: Color(0x33000000),
          ),
        if (show) const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
