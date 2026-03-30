import serial
import numpy as np
import struct

# ── Cấu hình ──────────────────────────────────────────────────
PORT      = "COM3"       # Windows: COM3, COM4... / Linux: /dev/ttyUSB0
BAUDRATE  = 9600         # Phải khớp với uart_pkg.sv
N         = 8
IS_SIGNED = True         # Khớp với SW[0] trên board

ser = serial.Serial(PORT, BAUDRATE, timeout=5)

# ── Tạo ma trận test ──────────────────────────────────────────
if IS_SIGNED:
    A = np.random.randint(-128, 127, (N, N), dtype=np.int8)
    B = np.random.randint(-128, 127, (N, N), dtype=np.int8)
    dtype_send = np.int8
else:
    A = np.random.randint(0, 255, (N, N), dtype=np.uint8)
    B = np.random.randint(0, 255, (N, N), dtype=np.uint8)
    dtype_send = np.uint8

# ── Tính kết quả đúng trên PC để so sánh ─────────────────────
expected = A.astype(np.int32) @ B.astype(np.int32)

# ── Gửi dữ liệu lên FPGA ─────────────────────────────────────
payload = np.concatenate([A.flatten(), B.flatten()]).astype(dtype_send).tobytes()
print(f"Sending {len(payload)} bytes...")
ser.write(payload)

# ── Nhận kết quả từ FPGA ─────────────────────────────────────
num_bytes = N * N * 4   # 256 bytes
print(f"Waiting for {num_bytes} bytes...")
raw = ser.read(num_bytes)

if len(raw) != num_bytes:
    print(f"ERROR: received {len(raw)} bytes, expected {num_bytes}")
    ser.close()
    exit()

# ── Parse kết quả ─────────────────────────────────────────────
result = np.zeros((N, N), dtype=np.int32)
for i in range(N):
    for j in range(N):
        idx = (i * N + j) * 4
        result[i][j] = struct.unpack_from('<i', raw, idx)[0]  # little-endian int32

# ── So sánh ───────────────────────────────────────────────────
if np.array_equal(result, expected):
    print("✅ PASS — Kết quả khớp hoàn toàn!")
else:
    print("❌ FAIL")
    diff = result - expected
    print("Diff matrix:\n", diff)
    print("Expected:\n", expected)
    print("Got:\n", result)

ser.close()