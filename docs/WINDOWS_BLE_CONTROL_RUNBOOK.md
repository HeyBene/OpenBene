# Windows BLE Control Runbook

This runbook is for the temporary manual control path:

```text
Windows Python -> BLE -> ESP32 -> motors
```

The iPhone capture app stays separate and only handles mapping data upload.

## 1. Install the BLE dependency

In Windows PowerShell:

```powershell
cd C:\Users\jiken\Desktop\OpenBene\openbene_sdk
python -m pip install -e .[ble]
```

If your shell treats brackets specially, use:

```powershell
python -m pip install -e ".[ble]"
```

## 2. Confirm the ESP32 firmware is advertising

Use the existing diagnostic tool first if needed:

```powershell
cd C:\Users\jiken\Desktop\OpenBene\openbene_sdk\examples
python esp32_ble_debug.py
```

Expected BLE identifiers from the current firmware:

- service UUID: `61653dc3-4021-4d1e-ba83-8b4eec61d613`
- RX UUID: `06386c14-86ea-4d71-811c-48f97c58f8c9`
- TX UUID: `9bf1103b-834c-47cf-b149-c9e4bcf778a7`

## 3. Start beginner keyboard drive

```powershell
cd C:\Users\jiken\Desktop\OpenBene\openbene_sdk\examples
python keyboard_ble_drive.py
```

If multiple devices are found, choose the correct index.

## 4. Keyboard controls

- `w`: forward
- `s`: reverse
- `a`: turn left
- `d`: turn right
- `q`: forward-left arc
- `e`: forward-right arc
- `space` or `x`: stop
- `h`: print help
- `Esc`: quit

The tool is hold-by-repeat:

- keep pressing / holding a key to continue motion
- stop pressing and the command expires automatically
- a BLE heartbeat is also sent so the MCU can stop on timeout

## 5. Useful options

Example with a known BLE address:

```powershell
python keyboard_ble_drive.py --address AA:BB:CC:DD:EE:FF
```

Lower speed for safer first tests:

```powershell
python keyboard_ble_drive.py --drive-pwm 60 --turn-pwm 70
```

Show telemetry:

```powershell
python keyboard_ble_drive.py --verbose-telemetry
```
