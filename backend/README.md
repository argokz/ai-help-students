# Lecture Assistant Backend

FastAPI бэкенд для ассистента лекций с ASR, RAG и генерацией конспектов.

## Возможности

- **ASR (Speech-to-Text)**: Транскрибация аудио с faster-whisper
  - Локальная транскрибация (CPU)
  - **Remote Worker** (GPU через Tailscale) - быстрая транскрибация на удалённом ПК с GPU
- **RAG Chat**: Умный чат по содержимому лекции
- **Конспекты**: Автоматическая генерация структурированных конспектов (детальный и краткий)
- **Мультиязычность**: Поддержка русского, казахского и английского языков

## Быстрый старт

### 0. PostgreSQL

Нужна база PostgreSQL. Локально или через Docker:

```bash
# Локально: создайте БД
createdb lecture_assistant

# Или через Docker
docker run -d --name pg -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=lecture_assistant -p 5432:5432 postgres:16-alpine
```

В `.env` укажите:
```
DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:5432/lecture_assistant
JWT_SECRET=ваш-секретный-ключ
```

### 1. Установка зависимостей

```bash
cd backend
python -m venv venv
source venv/bin/activate  # Linux/Mac
# или: venv\Scripts\activate  # Windows

pip install -r requirements.txt
```

### 2. Настройка переменных окружения

```bash
cp .env.example .env
# Добавьте GEMINI_API_KEY, JWT_SECRET, при необходимости GOOGLE_CLIENT_ID
```

### 3. Запуск сервера

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### 4. Проверка

Откройте http://localhost:8000/docs для интерактивной документации API.

## Docker

```bash
docker-compose up -d
```

## Google Sign-In

1. В [Google Cloud Console](https://console.cloud.google.com/) создайте проект (или выберите существующий).
2. **APIs & Services → Credentials** → Create Credentials → **OAuth 2.0 Client ID**.
3. Тип приложения: **Web application**. Скопируйте **Client ID** (это и есть `GOOGLE_CLIENT_ID` для бэкенда).
4. Для Android: создайте ещё один OAuth Client ID типа **Android**, укажите package name и SHA-1 (из `keytool -list -v -keystore ~/.android/debug.keystore`).
5. В `.env`: `GOOGLE_CLIENT_ID=ваш-web-client-id.apps.googleusercontent.com`
6. Во Flutter в `lib/core/config/app_config.dart` укажите тот же Web Client ID в `googleClientId`.

Бэкенд проверяет ID-токен от клиента и создаёт/находит пользователя по email.

## API Эндпоинты

| Метод | Путь | Описание |
|-------|------|----------|
| POST | `/api/auth/register` | Регистрация |
| POST | `/api/auth/login` | Вход по паролю |
| POST | `/api/auth/google` | Вход через Google (тело: `{"id_token": "..."}`) |
| GET | `/api/auth/me` | Текущий пользователь (Bearer) |
| POST | `/api/lectures/upload` | Загрузка аудиофайла |
| GET | `/api/lectures` | Список всех лекций |
| GET | `/api/lectures/{id}` | Информация о лекции |
| GET | `/api/lectures/{id}/transcript` | Транскрипт с таймкодами |
| GET | `/api/lectures/{id}/summary` | Структурированный конспект |
| POST | `/api/lectures/{id}/chat` | RAG-чат по лекции |
| DELETE | `/api/lectures/{id}` | Удаление лекции |

## Структура проекта

```
backend/
├── app/
│   ├── main.py              # FastAPI приложение
│   ├── config.py            # Настройки
│   ├── models/              # Pydantic модели
│   ├── routers/             # API эндпоинты
│   └── services/            # Бизнес-логика
├── data/                    # Данные (аудио, транскрипты)
├── requirements.txt
└── docker-compose.yml
```

## Remote Worker (GPU транскрибация)

Для использования удалённого GPU worker через Tailscale:

1. **Настройте worker на удалённом ПК** (см. `REMOTE_WORKER_SETUP.md` или `worker/README.md`)
2. **Добавьте в `.env`**:
   ```env
   WHISPER_WORKER_URL=http://100.115.128.128:8004  # Tailscale IP worker
   WHISPER_USE_REMOTE=true
   ```

Backend автоматически будет использовать worker если он доступен, иначе fallback на локальную транскрибацию.

**Преимущества:**
- 🚀 В 10-30 раз быстрее (GPU vs CPU)
- 🎯 Лучшее качество (large-v3 vs medium)
- 🔄 Автоматический fallback если worker недоступен

## Переменные окружения

| Переменная | Описание | По умолчанию |
|------------|----------|--------------|
| `LLM_PROVIDER` | Провайдер LLM | `gemini` |
| `GEMINI_API_KEY` | API ключ Google Gemini | - |
| `GEMINI_MODEL` | Модель Gemini | `gemini-2.5-flash` |
| `OPENAI_API_KEY` | API ключ OpenAI (опционально) | - |
| `OPENAI_MODEL` | Модель OpenAI | `gpt-4o-mini` |
| `WHISPER_MODEL` | Модель Whisper (локальная) | `medium` |
| `WHISPER_DEVICE` | Устройство (cpu/cuda) | `cpu` |
| `WHISPER_WORKER_URL` | URL remote worker (Tailscale IP) | - |
| `WHISPER_USE_REMOTE` | Использовать remote worker если доступен | `true` |
| `WHISPER_COMPUTE_TYPE` | Точность на GPU (float16/int8) | `int8` |
| `WHISPER_BEAM_SIZE` | Размер beam (1 — быстрее, 5 — качество) | `1` |
| `WHISPER_CONDITION_ON_PREVIOUS_TEXT` | Учёт предыдущего текста (False быстрее) | `false` |

### Ускорение загрузки и обработки

- **Загрузка**: файл пишется на диск чанками (стриминг), без загрузки целиком в память.
- **ASR быстрее**: в `.env` задайте `WHISPER_MODEL=small` или `base`, при наличии GPU — `WHISPER_DEVICE=cuda` и `WHISPER_COMPUTE_TYPE=float16`. Уже включены `beam_size=1` и `condition_on_previous_text=False` для скорости.

## Смена LLM провайдера

Чтобы переключиться между Gemini и OpenAI, измените `LLM_PROVIDER` в `.env`:

```bash
# Для Gemini (по умолчанию)
LLM_PROVIDER=gemini
GEMINI_API_KEY=your-key
GEMINI_MODEL=gemini-2.5-flash

# Для OpenAI
LLM_PROVIDER=openai
OPENAI_API_KEY=your-key
OPENAI_MODEL=gpt-4o-mini
```


