import 'package:flutter/material.dart';

/// Bottom inset so list content clears FAB + bottom navigation on Android.
const double kShellListBottomPadding = 96;

EdgeInsets shellPagePadding({bool extraForFab = false}) => EdgeInsets.fromLTRB(
      16,
      16,
      16,
      extraForFab ? 168 : kShellListBottomPadding,
    );
