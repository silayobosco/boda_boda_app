class Validation {
  static String? validateEmailPhoneNida({
    String? email,
    String? phone,
    String? nida,
  }) {
    // Email validation (must contain "@" and ".")
    final RegExp emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    if (email != null) {
      if (email.isEmpty) {
        return "Email is required.";
      } else if (!emailRegex.hasMatch(email)) {
        return "Invalid email format. Example: user@example.com";
      }
    }

    // Phone number validation (must start with "+" and have 10-15 digits)
    final RegExp phoneRegex = RegExp(r'^\+\d{10,13}$');
    if (phone != null) {
      if (phone.isEmpty) {
        return "Phone number is required.";
      } else if (!phoneRegex.hasMatch(phone)) {
        return "Invalid phone number. Example: +255712345678";
      }
    }

    // NIDA validation (must be exactly 20 digits and follow format)
    if (nida != null) {
      if (nida.isEmpty) {
        return "NIDA number is required.";
      } else if (!RegExp(r'^\d{20}$').hasMatch(nida)) {
        return "Invalid NIDA format. It must be exactly 20 digits.";
      }

      // Extract year, month, and day
      int birthYear = int.parse(nida.substring(0, 4));
      int birthMonth = int.parse(nida.substring(4, 6));
      int birthDay = int.parse(nida.substring(6, 8));
      int currentYear = DateTime.now().year;
      int minYear = 1800;
      int maxYear = currentYear - 18; // Must be at least 18 years old

      if (birthYear < minYear || birthYear > maxYear) {
        return "Invalid NIDA: Year out of range.";
      }
      if (birthMonth < 1 || birthMonth > 12) {
        return "Invalid NIDA: Month out of range.";
      }
      if (birthDay < 1 || birthDay > 31) {
        return "Invalid NIDA: Day out of range.";
      }
    }

    return null; // ✅ No error, all inputs are valid
  }
}
