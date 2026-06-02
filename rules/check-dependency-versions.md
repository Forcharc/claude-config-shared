---
paths:
  # Gradle (Android, JVM, Kotlin Multiplatform)
  - "**/build.gradle"
  - "**/build.gradle.kts"
  - "**/settings.gradle"
  - "**/settings.gradle.kts"
  - "**/gradle.properties"
  - "**/gradle/libs.versions.toml"
  - "**/buildSrc/**/*.kt"
  - "**/build-logic/**/*.kt"
  - "**/version-catalog/**"
  # npm / Node.js
  - "**/package.json"
  # Python
  - "**/requirements*.txt"
  - "**/pyproject.toml"
  - "**/setup.py"
  - "**/setup.cfg"
  # Rust
  - "**/Cargo.toml"
  # Go
  - "**/go.mod"
  # Ruby
  - "**/Gemfile"
  # iOS / Swift
  - "**/Podfile"
  - "**/*.podspec"
  - "**/Package.swift"
  # Flutter / Dart
  - "**/pubspec.yaml"
  # PHP
  - "**/composer.json"
  # .NET / C#
  - "**/*.csproj"
  - "**/Directory.Build.props"
  - "**/Directory.Packages.props"
  # Maven
  - "**/pom.xml"
---

# Dependency Version Check

При добавлении или обновлении зависимостей **обязательно проверить актуальную версию** через WebSearch.

- Не указывать версию по памяти — проверить на официальном сайте или репозитории
- Искать latest stable release, не alpha/beta/RC (если явно не просят)
- Если версия устарела — сообщить и предложить обновление
- Для Gradle: предпочитать version catalog (`libs.versions.toml`) вместо хардкода в build.gradle
