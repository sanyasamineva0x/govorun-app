"""
Говорун Local — Python ASR Worker

Unix socket сервер для распознавания речи через GigaAM-v3 e2e_rnnt.
Общение со Swift-приложением по протоколу JSON через ~/.govorun/worker.sock.

Протокол (один request за connection):
  ASR:    {"wav_path": "/tmp/govorun_xxx.wav"} → {"text": "..."}
  Ping:   {"cmd": "ping"} → {"status": "ok", "version": "1"}
  Ошибки: {"error": "oom|file_not_found|internal", "message": "..."}

stdout используется как протокол для Swift (ASRWorkerManager парсит):
  LOADING model=gigaam-v3-e2e-rnnt vad=silero version=1
  LOADED 3.2s
  READY
"""

import atexit
import json
import os
import signal
import socket
import sys
import tempfile
import time
import traceback

SOCKET_PATH = os.path.expanduser("~/.govorun/worker.sock")

_version_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "VERSION")
with open(_version_path) as _f:
    VERSION = _f.read().strip()

_server_sock = None


def cleanup(signum=None, frame=None):
    """Закрыть listening socket и удалить socket файл при завершении."""
    try:
        if _server_sock is not None:
            _server_sock.close()
        if os.path.exists(SOCKET_PATH):
            os.unlink(SOCKET_PATH)
    except OSError:
        pass
    if signum is not None:
        sys.exit(0)


atexit.register(cleanup)


def main():
    # Создать директорию для socket (700 — доступ только владельцу)
    socket_dir = os.path.dirname(SOCKET_PATH)
    os.makedirs(socket_dir, mode=0o700, exist_ok=True)

    # Удалить старый socket (от предыдущего запуска / crash)
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)

    # Graceful shutdown: SIGTERM → cleanup → exit
    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)

    # Прогресс скачивания модели → stdout "DOWNLOADING XX%"
    # Monkey-patch snapshot_download ДО импорта onnx_asr
    import huggingface_hub._snapshot_download as _snap_mod
    import huggingface_hub

    _orig_snapshot_download = _snap_mod.snapshot_download

    import threading

    class _StdoutProgressTqdm:
        """Custom tqdm для вывода прогресса скачивания в stdout."""
        def __init__(self, *args, **kwargs):
            self.total = kwargs.get("total", 0)
            self.n = kwargs.get("initial", 0)
            self._last_printed = -1

        def update(self, n=1):
            self.n += n
            if self.total and self.total > 0:
                pct = min(int(self.n * 100 / self.total), 100)
                if pct != self._last_printed:
                    self._last_printed = pct
                    print(f"DOWNLOADING {pct}%", flush=True)

        def close(self): pass
        def refresh(self): pass
        def set_description(self, *a, **kw): pass
        def __enter__(self): return self
        def __exit__(self, *a): pass

        _lock = threading.Lock()

        @classmethod
        def get_lock(cls):
            return cls._lock

        @classmethod
        def set_lock(cls, lock):
            cls._lock = lock

    def _patched_snapshot_download(*args, **kwargs):
        kwargs["tqdm_class"] = _StdoutProgressTqdm
        return _orig_snapshot_download(*args, **kwargs)

    _snap_mod.snapshot_download = _patched_snapshot_download
    huggingface_hub.snapshot_download = _patched_snapshot_download

    # Отключить CoreML — GigaAM e2e_rnnt не поддерживается CoreML провайдером
    import onnxruntime as ort
    _orig_init = ort.InferenceSession.__init__
    def _cpu_only_init(self, *args, **kwargs):
        kwargs["providers"] = ["CPUExecutionProvider"]
        kwargs.pop("provider_options", None)
        _orig_init(self, *args, **kwargs)
    ort.InferenceSession.__init__ = _cpu_only_init

    import onnx_asr

    print(f"LOADING model=gigaam-v3-e2e-rnnt vad=silero version={VERSION}", flush=True)
    t0 = time.time()
    base_model = onnx_asr.load_model("gigaam-v3-e2e-rnnt")
    vad = onnx_asr.load_vad("silero")
    model = base_model.with_vad(vad)
    print(f"LOADED {time.time() - t0:.1f}s", flush=True)

    # Unix socket сервер
    global _server_sock
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    _server_sock = sock
    sock.bind(SOCKET_PATH)
    sock.listen(1)

    print("READY", flush=True)

    while True:
        conn, _ = sock.accept()
        try:
            # Читаем до закрытия write-стороны клиентом (shutdown SHUT_WR)
            chunks = []
            while True:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                chunks.append(chunk)
            data = b"".join(chunks).decode()
            if not data:
                continue

            request = json.loads(data)

            # Ping — проверка жизни worker
            if request.get("cmd") == "ping":
                conn.sendall(json.dumps({"status": "ok", "version": VERSION}).encode())
                continue

            # ASR — распознавание речи
            wav_path = request.get("wav_path")
            if not wav_path:
                conn.sendall(json.dumps({
                    "error": "internal",
                    "message": "Отсутствует wav_path"
                }).encode())
                continue

            # Path traversal protection: только tmp файлы
            # realpath разрешает /var → /private/var, поэтому нормализуем и prefixes
            real_path = os.path.realpath(wav_path)
            allowed_prefixes = (
                os.path.realpath(tempfile.gettempdir()),
                "/tmp/",
                "/private/tmp/",
            )
            if not any(real_path.startswith(p) for p in allowed_prefixes):
                conn.sendall(json.dumps({
                    "error": "internal",
                    "message": "Запрещённый путь"
                }).encode())
                continue

            if not os.path.exists(wav_path):
                conn.sendall(json.dumps({
                    "error": "file_not_found",
                    "message": f"Файл не найден: {wav_path}"
                }).encode())
                continue

            # Silero VAD нарезает на сегменты → GigaAM распознаёт каждый
            # model.with_vad(vad).recognize() → итератор SegmentResult(start, end, text)
            segments = list(model.recognize(wav_path))
            text = " ".join(seg.text for seg in segments if seg.text).strip()

            conn.sendall(json.dumps({"text": text}).encode())

        except MemoryError:
            try:
                conn.sendall(json.dumps({
                    "error": "oom",
                    "message": "Недостаточно памяти"
                }).encode())
            except Exception:
                pass
        except json.JSONDecodeError as e:
            try:
                conn.sendall(json.dumps({
                    "error": "internal",
                    "message": f"Неверный JSON: {e}"
                }).encode())
            except Exception:
                pass
        except Exception as e:
            tb = traceback.format_exc()
            print(f"ERROR: {tb}", file=sys.stderr, flush=True)
            try:
                conn.sendall(json.dumps({
                    "error": "internal",
                    "message": str(e)
                }).encode())
            except Exception:
                pass
        finally:
            conn.close()


if __name__ == "__main__":
    main()
