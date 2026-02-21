import 'package:flutter/services.dart';

class JalaliDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // فقط عدد نگه دار
    String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.length > 8) digits = digits.substring(0, 8);

    String result = '';
    if (digits.length >= 1) result = digits.substring(0, digits.length.clamp(0, 4));
    if (digits.length > 4) result += '/${digits.substring(4, digits.length.clamp(4, 6))}';
    if (digits.length > 6) result += '/${digits.substring(6, digits.length.clamp(6, 8))}';

    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }
}
