# MSI - Medical Simulated Instruments

![MSI Logo](assets/logo.png)

**MSI (Medical Simulated Instruments)** is a high-fidelity clinical simulation and telemetry monitoring application designed for medical professionals, students, and simulation centers. It allows for the real-time simulation of vital signs, clinical procedures, and communication between students and supervisors.

## 🚀 Core Features

### 1. Real-Time Vitals Dashboard
Monitor and control critical physiological parameters from a single interface:
*   **Heart Rate (HR):** BPM monitoring with physiological correlation.
*   **Oxygen Saturation (SpO2) & CO2:** Capnography and pulse oximetry.
*   **Respiratory Rate (FR):** Breaths per minute tracking.
*   **Blood Pressure (TA):** Systolic and Diastolic control with automatic ratio calculation.
*   **Temperature & Glucose:** Core temperature and blood sugar monitoring.

### 2. Clinical Presets & Scenarios
*   **Quick Setup:** Use presets like "Telemetría Avanzada" or "Control de Glucosa" to instantly configure the dashboard.
*   **Clinical Cases:** Run complex scenarios like **Cardiac Arrest (PCR)** or **Diabetic Ketoacidosis**.
*   **Dynamic Events:** Trigger clinical events (e.g., "Starting CPR", "Administering Adrenaline") that automatically shift patient vitals based on programmed health effects.

### 3. Advanced Audio System
*   **Directional Panning:** Play different medical sounds or instructions to the Left or Right ear independently.
*   **Push-To-Talk (PTT):** Real-time voice streaming using the custom `sound_stream` engine, allowing for a "Supervisor-to-Student" voice link without file I/O lag.
*   **Headset Sensitivity:** Automatic detection of wired or Bluetooth headsets to ensure proper audio routing.

### 4. Bluetooth Telemetry (BLE)
Synchronize with external medical hardware or tablets:
*   **ESP32 Integration:** Built-in support for ESP32 devices via UART (Nordic UART Service).
*   **JSON Protocol:** Transmits live vitals using a lightweight JSON payload over BLE.
*   **Manual/Auto Transmission:** Choose which parameters sync instantly and which require a "manual transmit" to simulate real-world instrument delays.

### 5. Smart Reporting & Logging
*   **Automatic Logs:** The system detects significant changes in vitals and logs them automatically.
*   **Session Narrative:** Records clinical actions, supervisor notes, and student performance.
*   **Persistent Storage:** Uses `SharedPreferences` to save configurations, custom presets, and theme preferences.

---

## 🛠 Technical Stack

*   **UI Framework:** [Flutter](https://flutter.dev)
*   **State Management:** [Provider](https://pub.dev/packages/provider)
*   **Bluetooth:** [flutter_reactive_ble](https://pub.dev/packages/flutter_reactive_ble)
*   **Audio Engine:** 
    *   [audioplayers](https://pub.dev/packages/audioplayers) (MP3 Handling)
    *   [audio_session](https://pub.dev/packages/audio_session) (Session Routing)
    *   **Custom Sound Stream:** Located in `plugins/sound_stream`, handling Low-latency PCM audio bridges.
*   **Icons:** [Lucide Icons](https://lucideicons.com/) via `lucide_icons`.

---

## 📁 Project Structure

```text
lib/
├── main.dart             # App entry point, Theme config, and Shell Navigation.
├── models/               # Data structures for Instruments, Presets, and Themes.
├── providers/            # SimulationState: The central engine of the app.
├── screens/              
│   ├── setup_screen.dart # Configuration before starting a simulation.
│   ├── hub_screen.dart   # Live dashboard during a simulation.
│   └── reports_screen.dart # Post-session logging and data review.
├── services/             
│   └── audio_service.dart # Handles panning, PTT, and audio session logic.
└── widgets/              # Reusable UI components and Modals.
plugins/
└── sound_stream/         # Custom plugin for real-time PCM audio streaming.
```

---

## 🔌 Hardware Integration (The "Ins and Outs")

The application acts as a central hub (Client) that looks for BLE peripherals.

### BLE Specifications:
*   **Service UUID:** `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` (UART)
*   **TX Characteristic:** `6E400003-B5A3-F393-E0A9-E50E24DCCA9E`
*   **RX Characteristic:** `6E400002-B5A3-F393-E0A9-E50E24DCCA9E`

### Data Payload (JSON):
Every 2 seconds (or on manual sync), the app sends a packet:
```json
{
  "hr": 72,
  "spo2": 98,
  "co2": 40,
  "resp": 14,
  "temp": 36.6,
  "glucose": 110,
  "sys": 120,
  "dia": 80
}
```

---

## 🛠 Setup & Installation

1.  **Prerequisites:** Install Flutter (Stable branch).
2.  **Clone the Repository:**
    ```bash
    git clone <repo-url>
    ```
3.  **Install Dependencies:**
    ```bash
    flutter pub get
    ```
4.  **Run with Custom Plugins:**
    Since this project uses a local plugin, ensure the paths in `pubspec.yaml` are correct:
    ```yaml
    sound_stream:
      path: ./plugins/sound_stream
    ```
5.  **Run the App:**
    ```bash
    flutter run
    ```

---

## 🎨 Theming
The app supports 6 dynamic themes accessible via the configuration menu:
*   **MSI Classic:** Professional medical blue.
*   **Cyber Dark:** High contrast black and gold.
*   **Médico Oscuro:** Modern dark mode.
*   **Esmeralda, Atardecer, & Púrpura Neón:** Vibrant color schemes for different environments.

---
*Developed for clinical excellence and medical simulation training.*
