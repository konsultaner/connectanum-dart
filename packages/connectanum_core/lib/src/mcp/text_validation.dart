bool containsMcpWhitespaceOrControl(String value) {
  for (final rune in value.runes) {
    if (_isMcpWhitespaceOrControlRune(rune)) {
      return true;
    }
  }
  return false;
}

bool _isMcpWhitespaceOrControlRune(int rune) {
  return rune <= 0x20 ||
      (rune >= 0x7f && rune <= 0x9f) ||
      rune == 0xa0 ||
      rune == 0x1680 ||
      (rune >= 0x2000 && rune <= 0x200a) ||
      rune == 0x2028 ||
      rune == 0x2029 ||
      rune == 0x202f ||
      rune == 0x205f ||
      rune == 0x3000 ||
      rune == 0xfeff;
}
