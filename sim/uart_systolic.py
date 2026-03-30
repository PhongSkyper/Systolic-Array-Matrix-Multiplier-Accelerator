import serial
import random
import time
import struct

# ================= CẤU HÌNH =================
COM_PORT = 'COM3'  # QUAN TRỌNG: Sửa số 3 thành cổng COM của board DE10 trên máy bạn
BAUD_RATE = 9600   # Bắt buộc phải khớp với số BAUD_DIVISOR trong file final.sv
# ============================================

def main():
    try:
        # Mở kết nối với FPGA
        ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=5)
        print(f"[*] Đã kết nối thành công với Board DE10 qua {COM_PORT} (Baud: {BAUD_RATE}).")
        
        # 1. Sinh ngẫu nhiên Ma trận A và B (kích thước 4x4, giá trị từ 0 đến 15)
        matrix_a = [[random.randint(0, 15) for _ in range(4)] for _ in range(4)]
        matrix_b = [[random.randint(0, 15) for _ in range(4)] for _ in range(4)]
        
        print("\n[+] ĐÃ TẠO MA TRẬN A:")
        for row in matrix_a: print(["{:4d}".format(x) for x in row])
        
        print("\n[+] ĐÃ TẠO MA TRẬN B:")
        for row in matrix_b: print(["{:4d}".format(x) for x in row])
        
        # 2. Đóng gói dữ liệu thành mảng Byte (16 byte A + 16 byte B = 32 bytes)
        tx_data = bytearray()
        for row in matrix_a:
            for val in row: tx_data.append(val)
        for row in matrix_b:
            for val in row: tx_data.append(val)
                
        # 3. Bắn dữ liệu xuống FPGA
        print("\n[*] Đang bơm dữ liệu qua UART xuống FPGA...")
        ser.write(tx_data)
        
        # 4. Hứng kết quả từ FPGA (Chờ nhận đủ 64 bytes)
        print("[*] Đang chờ mạch Systolic Array tính toán...")
        rx_data = ser.read(64)
        
        if len(rx_data) == 64:
            print("\n[✓] THÀNH CÔNG: Đã nhận đủ 64 bytes. KẾT QUẢ MA TRẬN C (A x B):")
            
            # Giải mã 64 bytes thành 16 số nguyên 32-bit (Little Endian)
            matrix_c = []
            for i in range(0, 64, 4):
                val = struct.unpack('<I', rx_data[i:i+4])[0]
                matrix_c.append(val)
            
            # In ra màn hình dạng ma trận vuông 4x4
            print("-" * 35)
            for i in range(4):
                row = matrix_c[i*4:(i+1)*4]
                print("| " + " | ".join(["{:6d}".format(x) for x in row]) + " |")
            print("-" * 35)
        else:
            print(f"\n[!] LỖI: FPGA chỉ trả về {len(rx_data)}/64 bytes. Bị Timeout!")
            
        ser.close() # Đóng cổng COM
        
    except serial.SerialException as e:
        print(f"\n[!] KHÔNG THỂ MỞ CỔNG SERIAL!")
        print("-> Cách xử lý:")
        print("  1. Kiểm tra lại xem cắm cáp chưa và COM_PORT có đúng không.")
        print("  2. CHẮC CHẮN RẰNG bạn đã TẮT phần mềm Hercules (vì cổng COM chỉ cho 1 app dùng cùng lúc).")
        print(f"Chi tiết lỗi: {e}")

if __name__ == "__main__":
    main()