# Настройка Remote Worker для транскрибации

## Обзор

Система поддерживает распределённую транскрибацию:
- **Основной сервер** (backend) - обрабатывает запросы, использует локальный Whisper или отправляет на worker
- **Worker сервер** (удалённый ПК с GPU) - выполняет транскрибацию на GPU с моделью large-v3

## Настройка Worker на удалённом ПК (Ubuntu)

### 1. Установка зависимостей

```bash
# Обновление системы
sudo apt update
sudo apt upgrade -y

# Python и зависимости
sudo apt install python3-pip python3-venv git -y

# CUDA (если ещё не установлен)
# Следуйте инструкциям NVIDIA для вашей версии
# Для Ubuntu обычно:
# wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
# sudo dpkg -i cuda-keyring_1.1-1_all.deb
# sudo apt-get update
# sudo apt-get -y install cuda
```

### 2. Установка Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
# Запишите Tailscale IP (например, 100.115.128.128)
```

### 3. Клонирование и настройка Worker

```bash
# Создайте директорию для worker
mkdir -p ~/whisper-worker
cd ~/whisper-worker

# Скопируйте файлы worker из проекта:
# - worker/main.py
# - worker/requirements.txt
# - worker/README.md

# Создайте виртуальное окружение
python3 -m venv venv
source venv/bin/activate

# Установите зависимости
pip install --upgrade pip
pip install -r requirements.txt
```

### 4. Проверка GPU

```bash
# Проверьте что CUDA доступен
nvidia-smi

# Должен показать вашу GPU (1660 Ti)
```

### 5. Запуск Worker

```bash
# Активация venv
source venv/bin/activate

# Запуск (замените IP на ваш Tailscale IP)
export WORKER_PORT=8004
python main.py
```

Worker будет доступен по адресу: `http://100.115.128.128:8004`

### 6. Автозапуск через systemd

Создайте файл `/etc/systemd/system/whisper-worker.service`:

```ini
[Unit]
Description=Whisper Worker Service
After=network.target

[Service]
Type=simple
User=your_username
WorkingDirectory=/home/your_username/whisper-worker
Environment="PATH=/home/your_username/whisper-worker/venv/bin"
Environment="WORKER_PORT=8004"
ExecStart=/home/your_username/whisper-worker/venv/bin/python main.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Активируйте сервис:

```bash
sudo systemctl daemon-reload
sudo systemctl enable whisper-worker
sudo systemctl start whisper-worker
sudo systemctl status whisper-worker
```

## Настройка Backend (основной сервер)

### 1. Добавьте в `.env`:

```env
# Remote Worker (Tailscale IP)
WHISPER_WORKER_URL=http://100.115.128.128:8004
WHISPER_USE_REMOTE=true
```

### 2. Перезапустите backend

```bash
# Backend автоматически будет использовать worker если он доступен
# Если worker недоступен - fallback на локальную транскрибацию
```

## Проверка работы

### На Worker сервере:

```bash
# Health check
curl http://localhost:8004/health

# Должен вернуть:
# {"status":"healthy","model":"large-v3","device":"cuda","model_loaded":true}
```

### С основного сервера:

```bash
# Проверка доступности worker
curl http://100.115.128.128:8004/health
```

### Тест транскрибации:

```bash
# На worker сервере
curl -X POST "http://localhost:8004/transcribe?language=ru" \
  -F "file=@test_audio.mp3"
```

## Логи

### Worker логи:

```bash
# Если запущен через systemd
sudo journalctl -u whisper-worker -f

# Если запущен вручную - логи в консоли
```

### Backend логи:

Проверьте логи backend - должны быть сообщения:
- `Using remote worker for transcription: ...` - если worker используется
- `Remote worker failed: ..., falling back to local` - если worker недоступен
- `Using local transcription: ...` - если используется локальная транскрибация

## Производительность

- **Worker (GPU)**: ~10-30x быстрее чем CPU, использует large-v3 (лучшее качество)
- **Локальный (CPU)**: Медленнее, но работает если worker недоступен

## Безопасность

⚠️ **Важно**: Worker доступен только через Tailscale (приватная сеть). Не открывайте порт 8004 в публичном интернете!

## Troubleshooting

### Worker не отвечает:

1. Проверьте что Tailscale подключен: `tailscale status`
2. Проверьте что worker запущен: `sudo systemctl status whisper-worker`
3. Проверьте firewall: `sudo ufw status`
4. Проверьте логи: `sudo journalctl -u whisper-worker -n 50`

### CUDA ошибки:

1. Проверьте CUDA: `nvidia-smi`
2. Проверьте что faster-whisper видит GPU: `python -c "from faster_whisper import WhisperModel; m = WhisperModel('base', device='cuda'); print('OK')"`

### Медленная транскрибация:

1. Убедитесь что используется GPU: проверьте `nvidia-smi` во время транскрибации
2. Проверьте что модель large-v3 загружена (первый запуск может занять время)

