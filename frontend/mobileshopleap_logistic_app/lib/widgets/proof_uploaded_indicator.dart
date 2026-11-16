import 'package:flutter/material.dart';

class ProofUploadedIndicator extends StatelessWidget {
  const ProofUploadedIndicator({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(top: 4),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.verified_outlined, size: 14),
        SizedBox(width: 4),
        Flexible(child: Text('Proof uploaded', style: TextStyle(fontSize: 12))),
      ],
    ),
  );
}
