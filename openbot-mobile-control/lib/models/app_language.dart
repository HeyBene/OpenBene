enum AppLanguage {
  english,
  chinese,
}

extension AppLanguageExtension on AppLanguage {
  String get displayName {
    switch (this) {
      case AppLanguage.english:
        return 'English';
      case AppLanguage.chinese:
        return '中文';
    }
  }

  String get code {
    switch (this) {
      case AppLanguage.english:
        return 'en';
      case AppLanguage.chinese:
        return 'zh';
    }
  }
}
