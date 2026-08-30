bool isPlausibleTimeZoneIdentifier(String value) =>
    value == 'UTC' ||
    value == 'GMT' ||
    RegExp(r'^[A-Za-z0-9._+-]+/[A-Za-z0-9._+/-]+$').hasMatch(value);
