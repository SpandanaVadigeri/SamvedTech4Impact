"""
BLE Simulator – Solapur Safety System
Simulates real wearable devices (Helmet, Vital Band, Gas Badge) and
environmental probes sending sensor data to the Node.js backend.

🔧 SETUP:
  1. Make sure the Node.js backend is running (npm start inside /backend)
  2. Set BACKEND_IP below to the IP of the machine running the backend:
       - Same machine  → 127.0.0.1  (default)
       - Another device on same WiFi → e.g. 192.168.1.10
  3. Run: python ble_simulator.py

The pipeline is:
  Python Simulator  →  POST /api/simulator  →  Node.js  →  Socket.IO emit
  →  Flutter receives 'sensor_update'  →  UI updates in real time
"""

import time
import random
import requests
import sys

# ──────────────────────────────────────────────────────────────────────────────
# ⚙️  CONFIGURE: Backend host & port
# ──────────────────────────────────────────────────────────────────────────────
BACKEND_IP   = "127.0.0.1"   # ← Change to your PC's LAN IP if backend is remote
BACKEND_PORT = 3000
URL          = f"http://{BACKEND_IP}:{BACKEND_PORT}/api/simulator"
# ──────────────────────────────────────────────────────────────────────────────

# ── Wearable / worker devices ─────────────────────────────────────────────────
WORKER_DEVICES = [
    "SOLAPUR_HELMET_001",   # Worker 001 – Helmet (gas sensor + vitals)
    "SOLAPUR_HELMET_002",   # Worker 002 – Helmet
    "SOLAPUR_BAND_001",     # Worker 001 – Vital Band (HR, SpO2)
    "SOLAPUR_BAND_002",     # Worker 002 – Vital Band
    "SOLAPUR_BADGE_001",    # Worker 001 – Gas Badge (location tag)
    "SOLAPUR_BADGE_002",    # Worker 002 – Gas Badge
    "SOLAPUR_PANIC_001",    # Panic device
]

# ── Environmental probes ──────────────────────────────────────────────────────
PROBE_DEVICES = [
    "SOLAPUR_PROBE_TOP",
    "SOLAPUR_PROBE_MID",
    "SOLAPUR_PROBE_BOTTOM",
]

ALL_DEVICES = PROBE_DEVICES + WORKER_DEVICES

current_scenario = "normal"
scenario_timer   = 0


def get_base_values(device_id: str) -> dict:
    """Base gas readings per probe depth (or ambient for wearables)."""
    if "BOTTOM" in device_id:
        return {"h2s": 2.0,  "ch4": 0.5, "co": 10.0, "o2": 20.1}
    elif "MID" in device_id:
        return {"h2s": 1.0,  "ch4": 0.2, "co":  5.0, "o2": 20.5}
    else:   # TOP / wearables – near-surface ambient levels
        return {"h2s": 0.0,  "ch4": 0.0, "co":  2.0, "o2": 20.9}


def apply_scenario(data: dict, scenario: str) -> dict:
    """Overlay scenario-specific deltas onto sensor readings."""
    if scenario == "gas_spike":
        data["h2s"]  += random.uniform(8, 15)
        data["ch4"]  += random.uniform(1.5, 3.0)
        if "spo2" in data:
            data["spo2"] = max(80, data["spo2"] - random.randint(5, 10))
    elif scenario == "flood":
        data["water_level"] = random.uniform(85, 100)
    elif scenario == "panic":
        data["panic"] = True
    elif scenario == "fall":
        data["fall"]      = True
        data["vibration"] = random.uniform(15, 25)
    elif scenario == "vibration":
        data["vibration"] = random.uniform(12, 18)
    elif scenario == "caution":
        data["h2s"]  += random.uniform(5.5, 8.0)
        data["o2"]   -= random.uniform(0.5, 1.0)
        if "spo2" in data:
            data["spo2"] = max(88, data["spo2"] - random.randint(2, 6))
    return data


def generate_payload(device_id: str, scenario: str) -> dict:
    """
    Build a full sensor payload for the given device and scenario.
    Payload follows the schema expected by the backend /api/simulator route:
    {
        "device_id": "SOLAPUR_HELMET_001",
        "worker_id": "SOLAPUR_HELMET_001",
        "type": "helmet",          # hint for the frontend
        "h2s": 0.5, "ch4": 0.1, "co": 2.0, "o2": 20.8,
        "hr": 72, "spo2": 98,     # only for wearable devices
        "water_level": 3.0,
        "vibration": 0.5,
        "panic": false,
        "fall": false,
        "timestamp": 1712345678000
    }
    """
    base = get_base_values(device_id)
    is_worker = any(tag in device_id for tag in ["HELMET", "BAND", "BADGE", "PANIC"])

    # Determine device type tag for frontend routing
    if "HELMET" in device_id:   dtype = "helmet"
    elif "BAND"  in device_id:  dtype = "band"
    elif "BADGE" in device_id:  dtype = "badge"
    elif "PANIC" in device_id:  dtype = "panic"
    elif "PROBE" in device_id:  dtype = "probe"
    else:                        dtype = "unknown"

    payload = {
        "device_id":    device_id,
        "worker_id":    device_id,   # 1-to-1 mapping: device ↔ worker
        "type":         dtype,
        "h2s":          max(0, round(base["h2s"] + random.uniform(-0.5,  0.5),  2)),
        "ch4":          max(0, round(base["ch4"] + random.uniform(-0.1,  0.1),  2)),
        "co":           max(0, round(base["co"]  + random.uniform(-1.0,  1.0),  2)),
        "o2":           min(21.0, max(0, round(base["o2"] + random.uniform(-0.1, 0.1), 2))),
        "water_level":  round(random.uniform(0, 10), 1),
        "vibration":    round(random.uniform(0,  2),  1),
        "panic":        False,
        "fall":         False,
        "timestamp":    int(time.time() * 1000),
    }

    # Vitals are only sent by wearable devices
    if is_worker:
        payload["hr"]   = random.randint(70, 90)
        payload["spo2"] = random.randint(95, 100)

    # Apply scenario overlays
    if "PANIC" in device_id and scenario == "panic":
        payload = apply_scenario(payload, "panic")
    elif "HELMET" in device_id and scenario == "fall":
        payload = apply_scenario(payload, "fall")
    elif "PROBE" in device_id:
        if scenario in {"gas_spike", "caution"}:
            payload = apply_scenario(payload, scenario)
        if scenario == "flood" and "BOTTOM" in device_id:
            payload = apply_scenario(payload, "flood")
    else:
        if scenario in {"gas_spike", "caution"}:
            payload = apply_scenario(payload, scenario)

    return payload


# ── Scenario rotation ─────────────────────────────────────────────────────────
SCENARIOS = ["normal", "normal", "normal", "caution", "gas_spike", "flood", "fall", "panic"]

print("=" * 70)
print("🚀  BLE Real-World Simulator  –  Solapur Safety System")
print(f"📡  Backend  : {URL}")
print(f"📟  Devices  : {len(ALL_DEVICES)} total  ({len(PROBE_DEVICES)} probes + {len(WORKER_DEVICES)} wearables)")
print("=" * 70)
print("\nPipeline: Simulator → POST /api/simulator → Socket.IO → Flutter app\n")

cycle = 0

# ── Main Loop ─────────────────────────────────────────────────────────────────
while True:
    cycle += 1

    # ── Scenario rotation ─────────────────────────────────────────────────────
    if scenario_timer <= 0:
        current_scenario  = random.choice(SCENARIOS)
        scenario_timer    = random.randint(10, 20)
        print(f"\n{'='*60}")
        print(f"  ⚠️  SCENARIO → {current_scenario.upper()}  ({scenario_timer} cycles)")
        print(f"{'='*60}\n")

    scenario_timer -= 1

    success_count = 0
    error_count   = 0

    for device in ALL_DEVICES:
        payload = generate_payload(device, current_scenario)
        try:
            resp = requests.post(URL, json=payload, timeout=3)
            if resp.status_code == 200:
                result  = resp.json()
                status  = result.get("status", "?")
                alerts  = result.get("alerts", [])
                h2s_val = payload.get("h2s", "-")
                alert_s = f"  ⚠️  {alerts[0]}" if alerts else ""
                print(f"  ✅ [{device:30s}]  H2S={h2s_val:5}  →  {status}{alert_s}")
                success_count += 1
            else:
                print(f"  ❌ HTTP {resp.status_code} for {device}")
                error_count   += 1

        except requests.exceptions.ConnectionError:
            print(f"  ❌ [CONN ERROR] Cannot reach {URL}  –  Is the backend running?")
            error_count += 1
            time.sleep(2)   # Brief pause to avoid log spam
            break           # Skip remaining devices this cycle

        except requests.exceptions.Timeout:
            print(f"  ⏱️  [TIMEOUT] {device}")
            error_count += 1

        except Exception as exc:
            print(f"  ❌ [ERROR] {device}: {exc}")
            error_count += 1

    print(f"\n  📊  Cycle #{cycle:04d}  |  Scenario={current_scenario.upper()}  "
          f"|  ✅ {success_count}/{len(ALL_DEVICES)}  |  ❌ {error_count}  "
          f"|  Sleeping 2 s …\n")
    time.sleep(2)   # 2-second telemetry cycle