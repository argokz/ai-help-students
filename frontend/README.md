# Lecture Assistant - Flutter App

Flutter мобильное приложение для записи и анализа лекций.

## Возможности

- **Запись аудио**: Запись лекций прямо с телефона
- **Список лекций**: Просмотр всех записанных лекций
- **Транскрипт**: Полный текст с таймкодами
- **Конспект**: Автоматически сгенерированные заметки
- **Чат**: Задавайте вопросы по содержимому лекции

## Требования

- Flutter 3.x
- Android SDK 21+
- Работающий бэкенд (см. `/backend`)

## Быстрый старт

### 1. Установка зависимостей

```bash
cd frontend
flutter pub get
```

### 2. Настройка API URL

Отредактируйте `lib/core/config/app_config.dart`:

```dart
class AppConfig {
  // Production server
  static const String apiBaseUrl = 'https://itwin.kz/ai-api/api';
  
  // Для локальной разработки (раскомментируйте нужный):
  // static const String apiBaseUrl = 'http://10.0.2.2:8000/api';  // Android emulator
  // static const String apiBaseUrl = 'http://localhost:8000/api'; // iOS simulator
}
```

### 3. Запуск

```bash
# Запустите бэкенд сначала
cd ../backend
uvicorn app.main:app --host 0.0.0.0 --port 8000

# Затем запустите приложение
cd ../frontend
flutter run
```

## Структура проекта

```
lib/
├── main.dart              # Точка входа
├── app/
│   ├── app.dart           # Основной виджет
│   └── routes.dart        # Маршрутизация
├── core/
│   └── theme/             # Тема приложения
├── data/
│   └── api_client.dart    # HTTP клиент
├── models/                # Модели данных
└── features/
    ├── recording/         # Экран записи
    ├── lectures/          # Список и детали лекций
    ├── transcript/        # Просмотр транскрипта
    ├── summary/           # Конспект
    └── chat/              # RAG чат
```

## Разрешения Android

Приложение запрашивает:
- `RECORD_AUDIO` - для записи лекций
- `INTERNET` - для связи с бэкендом
- `WRITE_EXTERNAL_STORAGE` - для сохранения записей

## Сборка APK

```bash
flutter build apk --release
```

APK будет в `build/app/outputs/flutter-apk/app-release.apk`
