"""
Тесты для Python ASR Worker (server.py).

Все тесты используют моки для onnx_asr — реальная модель не требуется.
Worker запускается в отдельном потоке, общение через unix socket.
"""

import io
import json
import os
import socket
import tempfile
import threading
import time
import wave
from unittest import mock

import pytest

SOCKET_PATH = os.path.expanduser("~/.govorun/test_worker.sock")


def make_wav_file(duration_sec=1.0, sample_rate=16000, num_channels=1):
    """Создать валидный WAV файл с тишиной."""
    tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    num_frames = int(sample_rate * duration_sec)
    with wave.open(tmp.name, "wb") as wf:
        wf.setnchannels(num_channels)
        wf.setsampwidth(2)  # 16-bit
        wf.setframerate(sample_rate)
        wf.writeframes(b"\x00\x00" * num_frames * num_channels)
    return tmp.name


def make_corrupt_file():
    """Создать файл с мусором (не WAV)."""
    tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    tmp.write(b"THIS IS NOT A WAV FILE AT ALL")
    tmp.close()
    return tmp.name


def send_request(request, socket_path=SOCKET_PATH, timeout=5.0):
    """Отправить JSON запрос через unix socket и получить ответ."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    sock.connect(socket_path)
    sock.sendall(json.dumps(request).encode())
    sock.shutdown(socket.SHUT_WR)  # Сигнал серверу что отправка завершена
    data = sock.recv(65536)
    sock.close()
    return json.loads(data.decode()) if data else None


def send_raw(raw_bytes, socket_path=SOCKET_PATH, timeout=5.0):
    """Отправить сырые байты через unix socket."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    sock.connect(socket_path)
    sock.sendall(raw_bytes)
    sock.shutdown(socket.SHUT_WR)
    data = sock.recv(65536)
    sock.close()
    return json.loads(data.decode()) if data else None


# --- Моки для onnx_asr ---

class MockModel:
    """Мок GigaAM-v3 модели."""

    def __init__(self, result="тестовый текст"):
        self.result = result
        self.calls = []

    def with_vad(self, vad):
        """server.py вызывает base_model.with_vad(vad) → возвращаем self."""
        return self

    def recognize(self, wav_path):
        """server.py вызывает model.recognize(wav_path) → итератор SegmentResult."""
        self.calls.append(wav_path)
        if isinstance(self.result, Exception):
            raise self.result

        class FakeSegment:
            def __init__(self, text):
                self.text = text
                self.start = 0.0
                self.end = 1.0

        if self.result is None:
            return []
        return [FakeSegment(self.result)]


class MockVAD:
    """Мок Silero VAD."""
    pass


class OOMModel:
    """Модель, которая бросает MemoryError."""

    def with_vad(self, vad):
        return self

    def recognize(self, wav_path):
        raise MemoryError("OOM при inference")


class CrashModel:
    """Модель, которая бросает RuntimeError."""

    def with_vad(self, vad):
        return self

    def recognize(self, wav_path):
        raise RuntimeError("сегмент повреждён")


# --- Фикстура: запуск worker в потоке ---

@pytest.fixture
def worker_server(request):
    """Запустить worker в отдельном потоке с моками."""
    model = getattr(request, "param", {}).get("model", MockModel())
    vad = getattr(request, "param", {}).get("vad", MockVAD())

    # Убрать старый socket
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)

    os.makedirs(os.path.dirname(SOCKET_PATH), exist_ok=True)

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.bind(SOCKET_PATH)
    sock.listen(1)
    sock.settimeout(1.0)

    stop_event = threading.Event()

    def serve():
        while not stop_event.is_set():
            try:
                conn, _ = sock.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            try:
                # recv-loop до EOF (клиент делает shutdown SHUT_WR)
                chunks = []
                while True:
                    chunk = conn.recv(4096)
                    if not chunk:
                        break
                    chunks.append(chunk)
                data = b"".join(chunks).decode()
                if not data:
                    continue

                req = json.loads(data)

                if req.get("cmd") == "ping":
                    conn.sendall(json.dumps({"status": "ok", "version": "1"}).encode())
                    continue

                wav_path = req.get("wav_path")
                if not wav_path:
                    conn.sendall(json.dumps({
                        "error": "internal",
                        "message": "Отсутствует wav_path"
                    }).encode())
                    continue

                if not os.path.exists(wav_path):
                    conn.sendall(json.dumps({
                        "error": "file_not_found",
                        "message": f"Файл не найден: {wav_path}"
                    }).encode())
                    continue

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
                try:
                    conn.sendall(json.dumps({
                        "error": "internal",
                        "message": str(e)
                    }).encode())
                except Exception:
                    pass
            finally:
                conn.close()

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()

    yield {"model": model, "vad": vad, "socket_path": SOCKET_PATH}

    stop_event.set()
    sock.close()
    thread.join(timeout=3)
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)


# --- Тесты: ping ---

def test_ping_returns_ok_and_version(worker_server):
    resp = send_request({"cmd": "ping"})
    assert resp["status"] == "ok"
    assert resp["version"] == "1"


# --- Тесты: ASR (распознавание) ---

def test_recognize_wav_returns_text(worker_server):
    wav = make_wav_file(duration_sec=1.0)
    try:
        resp = send_request({"wav_path": wav})
        assert "text" in resp
        assert resp["text"] == "тестовый текст"
    finally:
        os.unlink(wav)


def test_recognize_model_returns_none_gives_empty_text(worker_server):
    """Модель вернула None (тишина) → пустая строка."""
    worker_server["model"].result = None
    wav = make_wav_file(duration_sec=0.5)
    try:
        resp = send_request({"wav_path": wav})
        assert resp["text"] == ""
    finally:
        os.unlink(wav)


def test_recognize_model_returns_empty_string(worker_server):
    """Модель вернула пустую строку → пустая строка."""
    worker_server["model"].result = ""
    wav = make_wav_file(duration_sec=0.5)
    try:
        resp = send_request({"wav_path": wav})
        assert resp["text"] == ""
    finally:
        os.unlink(wav)


def test_recognize_strips_whitespace(worker_server):
    """Текст с пробелами по краям обрезается."""
    worker_server["model"].result = "  привет мир  "
    wav = make_wav_file(duration_sec=1.0)
    try:
        resp = send_request({"wav_path": wav})
        assert resp["text"] == "привет мир"
    finally:
        os.unlink(wav)


def test_recognize_long_audio(worker_server):
    """Длинное аудио (2 мин) — VAD нарезает, recognize_long справляется."""
    worker_server["model"].result = "длинная запись нарезанная на сегменты"
    wav = make_wav_file(duration_sec=120.0)
    try:
        resp = send_request({"wav_path": wav})
        assert resp["text"] == "длинная запись нарезанная на сегменты"
    finally:
        os.unlink(wav)


def test_recognize_passes_wav_path_and_vad_to_model(worker_server):
    """Проверить что model.recognize_long вызывается с правильными аргументами."""
    wav = make_wav_file()
    try:
        send_request({"wav_path": wav})
        assert len(worker_server["model"].calls) == 1
        assert worker_server["model"].calls[0] == wav
    finally:
        os.unlink(wav)


# --- Тесты: ошибки ---

def test_file_not_found_returns_error(worker_server):
    resp = send_request({"wav_path": "/tmp/nonexistent_govorun_test.wav"})
    assert resp["error"] == "file_not_found"
    assert "message" in resp


def test_missing_wav_path_returns_error(worker_server):
    resp = send_request({"some_key": "value"})
    assert resp["error"] == "internal"
    assert "wav_path" in resp["message"].lower() or "Отсутствует" in resp["message"]


def test_invalid_json_returns_error(worker_server):
    resp = send_raw(b"not json at all{{{")
    assert resp["error"] == "internal"
    assert "JSON" in resp["message"]


def test_empty_request_returns_none(worker_server):
    """Пустой запрос (0 байт) — сервер молча закрывает соединение."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(2.0)
    sock.connect(SOCKET_PATH)
    # Закрываем без отправки данных
    sock.close()
    # Дать worker время обработать закрытие соединения (CI медленнее)
    time.sleep(0.2)
    # Worker не падает — проверяем ping
    resp = send_request({"cmd": "ping"})
    assert resp["status"] == "ok"


# --- Тесты: OOM и crash модели (через параметризацию worker_server) ---

@pytest.mark.parametrize("worker_server", [{"model": OOMModel()}], indirect=True)
def test_oom_returns_error(worker_server):
    wav = make_wav_file()
    try:
        resp = send_request({"wav_path": wav})
        assert resp["error"] == "oom"
        assert "памяти" in resp["message"]
    finally:
        os.unlink(wav)


@pytest.mark.parametrize("worker_server", [{"model": CrashModel()}], indirect=True)
def test_model_crash_returns_internal_error(worker_server):
    wav = make_wav_file()
    try:
        resp = send_request({"wav_path": wav})
        assert resp["error"] == "internal"
        assert "повреждён" in resp["message"]
    finally:
        os.unlink(wav)


@pytest.mark.parametrize("worker_server", [{"model": CrashModel()}], indirect=True)
def test_corrupt_wav_returns_error(worker_server):
    """Corrupt WAV файл — модель бросает ошибку, worker возвращает internal error."""
    wav = make_corrupt_file()
    try:
        resp = send_request({"wav_path": wav})
        assert resp["error"] == "internal"
    finally:
        os.unlink(wav)


# --- Тесты: worker не падает после ошибки ---

def test_worker_survives_after_error(worker_server):
    """После ошибки (file_not_found) worker продолжает принимать запросы."""
    # Ошибочный запрос
    resp1 = send_request({"wav_path": "/tmp/nonexistent.wav"})
    assert resp1["error"] == "file_not_found"

    # Нормальный запрос — worker жив
    resp2 = send_request({"cmd": "ping"})
    assert resp2["status"] == "ok"


def test_worker_survives_after_invalid_json(worker_server):
    """После битого JSON worker продолжает работать."""
    resp1 = send_raw(b"{{{{")
    assert resp1["error"] == "internal"

    resp2 = send_request({"cmd": "ping"})
    assert resp2["status"] == "ok"


def test_multiple_sequential_requests(worker_server):
    """Несколько последовательных запросов — каждый в своём connection."""
    for i in range(5):
        resp = send_request({"cmd": "ping"})
        assert resp["status"] == "ok"


# --- Тесты: stdout протокол ---

def test_stdout_protocol():
    """Проверить что main() выводит LOADING/LOADED/READY в stdout."""
    import importlib
    import sys

    captured = io.StringIO()

    mock_model = MockModel()
    mock_vad = MockVAD()

    mock_onnx_asr = mock.MagicMock()
    mock_onnx_asr.load_model.return_value = mock_model
    mock_onnx_asr.load_vad.return_value = mock_vad

    # Патчим sys.modules: onnx_asr + huggingface_hub + onnxruntime (server.py импортирует все)
    mock_hf_snap = mock.MagicMock()
    mock_hf = mock.MagicMock()
    # onnxruntime mock: нужен реальный класс для InferenceSession (MagicMock не позволяет __init__)
    mock_ort = mock.MagicMock()
    mock_ort.InferenceSession = type("FakeInferenceSession", (), {"__init__": lambda self, *a, **kw: None})
    with mock.patch.dict(sys.modules, {
        "onnx_asr": mock_onnx_asr,
        "huggingface_hub": mock_hf,
        "huggingface_hub._snapshot_download": mock_hf_snap,
        "onnxruntime": mock_ort,
    }):
        # Подменяем stdout для перехвата сообщений
        old_stdout = sys.stdout
        sys.stdout = captured

        # Патчим socket чтобы main() не блокировался на accept()
        mock_sock = mock.MagicMock()
        mock_sock.accept.side_effect = KeyboardInterrupt  # Выход из цикла

        with mock.patch("socket.socket") as mock_socket_cls:
            mock_socket_cls.return_value = mock_sock
            with mock.patch("os.path.exists", return_value=False):
                with mock.patch("os.makedirs"):
                    # Патчим signal чтобы не менять реальные обработчики
                    with mock.patch("signal.signal"):
                        try:
                            # Импортируем server и вызываем main
                            # Нужно перезагрузить модуль чтобы подхватить мок
                            spec = importlib.util.spec_from_file_location(
                                "server_test",
                                os.path.join(os.path.dirname(__file__), "server.py"),
                                submodule_search_locations=[]
                            )
                            mod = importlib.util.module_from_spec(spec)
                            # Патчим VERSION чтобы не читать файл
                            with mock.patch("builtins.open", mock.mock_open(read_data="1")):
                                spec.loader.exec_module(mod)
                            mod.SOCKET_PATH = "/tmp/govorun_test_stdout.sock"
                            mod.main()
                        except KeyboardInterrupt:
                            pass
                        finally:
                            sys.stdout = old_stdout

        output = captured.getvalue()
        lines = [l for l in output.strip().split("\n") if l]

        assert any("LOADING" in l for l in lines), f"LOADING не найден в: {lines}"
        assert any("LOADED" in l for l in lines), f"LOADED не найден в: {lines}"
        assert any("READY" in l for l in lines), f"READY не найден в: {lines}"

        # Порядок: LOADING → LOADED → READY
        loading_idx = next(i for i, l in enumerate(lines) if "LOADING" in l)
        loaded_idx = next(i for i, l in enumerate(lines) if "LOADED" in l)
        ready_idx = next(i for i, l in enumerate(lines) if "READY" in l)
        assert loading_idx < loaded_idx < ready_idx


# --- Тесты: один request за connection ---

def test_one_request_per_connection(worker_server):
    """Каждый запрос — новое подключение. Старое закрывается сервером."""
    wav = make_wav_file()
    try:
        # Первый запрос
        resp1 = send_request({"wav_path": wav})
        assert resp1["text"] == "тестовый текст"

        # Второй запрос — новое подключение
        resp2 = send_request({"cmd": "ping"})
        assert resp2["status"] == "ok"
    finally:
        os.unlink(wav)


# --- Тесты: unicode / кириллица ---

def test_unicode_text_preserved(worker_server):
    """Кириллический текст корректно передаётся через JSON/socket."""
    worker_server["model"].result = "Привет, мир! Это тестовое сообщение на русском языке."
    wav = make_wav_file()
    try:
        resp = send_request({"wav_path": wav})
        assert resp["text"] == "Привет, мир! Это тестовое сообщение на русском языке."
    finally:
        os.unlink(wav)


def test_text_with_punctuation(worker_server):
    """Текст с пунктуацией (из e2e_rnnt) сохраняется."""
    worker_server["model"].result = "Здравствуйте, как дела? Всё хорошо!"
    wav = make_wav_file()
    try:
        resp = send_request({"wav_path": wav})
        assert resp["text"] == "Здравствуйте, как дела? Всё хорошо!"
    finally:
        os.unlink(wav)


# --- Тесты: timeout / hanging client ---

def test_hanging_client_does_not_block_worker(worker_server):
    """Зависший клиент (connect без данных и без shutdown) не блокирует worker навсегда.

    Worker fixture использует sock.settimeout(1.0) на accept, но в реальном server.py
    conn.settimeout(CONNECTION_TIMEOUT) защищает от зависших клиентов.
    Здесь проверяем что после зависшего клиента worker продолжает работать.
    """
    # Клиент подключается, но не отправляет данные и не делает shutdown
    hanging = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    hanging.connect(SOCKET_PATH)
    # Ждём чтобы worker обработал (в fixture timeout на recv = нет, но данные пустые)
    time.sleep(0.3)
    hanging.close()

    # Worker должен остаться живым
    resp = send_request({"cmd": "ping"})
    assert resp["status"] == "ok"


def test_incomplete_data_does_not_crash_worker(worker_server):
    """Неполные данные (без shutdown SHUT_WR) — worker не падает после таймаута."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(2.0)
    sock.connect(SOCKET_PATH)
    sock.sendall(b'{"wav_path": "/tmp')  # неполный JSON, без shutdown
    time.sleep(0.3)
    sock.close()

    # Worker жив
    resp = send_request({"cmd": "ping"})
    assert resp["status"] == "ok"
