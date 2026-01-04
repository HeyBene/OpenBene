#!/usr/bin/env python3
"""
OpenBot 测试服务器 - 用于验证手机应用连接
"""
import asyncio
import websockets
import json
from datetime import datetime

connected_clients = set()

async def handle_client(websocket):
    """处理客户端连接"""
    client_id = f"{websocket.remote_address[0]}:{websocket.remote_address[1]}"
    print(f"\n✅ 新客户端连接: {client_id}")
    connected_clients.add(websocket)
    
    try:
        async for message in websocket:
            try:
                data = json.loads(message)
                msg_type = data.get('type', 'unknown')
                
                if msg_type == 'video_frame':
                    frame_size = len(data.get('data', ''))
                    timestamp = data.get('timestamp', 0)
                    print(f"📹 收到视频帧: {frame_size} bytes, 时间: {timestamp}")
                
                elif msg_type == 'sensor_data':
                    sensor = data.get('data', {})
                    accel = sensor.get('accelerometer', {})
                    gyro = sensor.get('gyroscope', {})
                    battery = sensor.get('batteryLevel', 0)
                    print(f"📊 传感器数据:")
                    print(f"   加速度: X={accel.get('x', 0):.2f}, Y={accel.get('y', 0):.2f}, Z={accel.get('z', 0):.2f} m/s²")
                    print(f"   陀螺仪: X={gyro.get('x', 0):.2f}, Y={gyro.get('y', 0):.2f}, Z={gyro.get('z', 0):.2f} rad/s")
                    print(f"   电池: {battery*100:.0f}%")
                
                elif msg_type == 'ping':
                    # 回复心跳
                    await websocket.send(json.dumps({'type': 'pong', 'timestamp': data.get('timestamp')}))
                    print(f"💓 心跳")
                
            except json.JSONDecodeError:
                print(f"⚠️  无效的 JSON 消息")
            except Exception as e:
                print(f"❌ 处理消息错误: {e}")
    
    except websockets.exceptions.ConnectionClosed:
        print(f"\n❌ 客户端断开: {client_id}")
    finally:
        connected_clients.remove(websocket)

async def main():
    """启动服务器"""
    host = "0.0.0.0"
    port = 8765
    
    print("="*60)
    print("🤖 OpenBot 测试服务器")
    print("="*60)
    print(f"📡 监听地址: {host}:{port}")
    print(f"⏰ 启动时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("\n等待手机应用连接...\n")
    
    async with websockets.serve(handle_client, host, port):
        await asyncio.Future()  # 永久运行

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n\n👋 服务器已停止")
