/*
 * Solapur Safety System - H2S Sensor Driver
 * For MQ-136 Hydrogen Sulfide Sensor
 * Complete implementation matching the header file
 */

 #include "sensors/h2s_sensor.h"


// Constructor
H2SSensor::H2SSensor(int sensorPin, float loadResistance) {
  pin = sensorPin;
  rl = loadResistance;
  calibrationFactor = 1.0;
  temperature = 25.0;  // Default room temperature
  humidity = 50.0;      // Default humidity
  ro = 0.0;             // Will be set during calibration
  pinMode(pin, INPUT);
}

// Calibrate sensor in clean air
void H2SSensor::calibrate() {
  Serial.println("🔧 Calibrating H2S sensor...");
  
  float sum = 0;
  for(int i = 0; i < 100; i++) {
    sum += analogRead(pin);
    delay(10);
  }
  
  float avg = sum / 100;
  float rs = ((4095.0 / avg) - 1) * rl;
  
  // For MQ-136, Rs/Ro in clean air is approximately 3.6
  ro = rs / 3.6;
  
  Serial.print("✅ H2S sensor calibrated. Ro = ");
  Serial.print(ro);
  Serial.println(" kΩ");
}

// Read raw sensor resistance
float H2SSensor::readRaw() {
  int raw = analogRead(pin);
  float rs = ((4095.0 / raw) - 1) * rl;
  return rs;
}

// Get resistance ratio
float H2SSensor::getRatio() {
  float rs = readRaw();
  if (ro == 0) {
    Serial.println("⚠️ Warning: Sensor not calibrated!");
    return 0;
  }
  return rs / ro;
}

// Read H2S concentration in ppm
float H2SSensor::readPPM() {
  if (ro == 0) {
    Serial.println("⚠️ Warning: Sensor not calibrated! Run calibrate() first.");
    return 0;
  }
  
  float ratio = getRatio();
  
  // Apply temperature and humidity compensation
  // Temperature effect: Rs decreases as temperature increases
  float tempComp = 1.0 + 0.02 * (temperature - 25.0);
  
  // Humidity effect: Rs decreases as humidity increases
  float humComp = 1.0 + 0.01 * (humidity - 50.0);
  
  float compensatedRatio = ratio / (tempComp * humComp);
  
  // MQ-136 sensitivity curve from datasheet
  // log(ppm) = 1.8 - 2.0 * log(ratio)
  float logPpm = 1.8 - 2.0 * log10(compensatedRatio);
  float ppm = pow(10, logPpm);
  
  // Apply calibration factor and clamp to reasonable range
  ppm = ppm * calibrationFactor;
  
  // Clamp to sensor's range (0-100 ppm typical)
  if (ppm < 0) ppm = 0;
  if (ppm > 100) ppm = 100;
  
  return ppm;
}

// Set calibration factor
void H2SSensor::setCalibrationFactor(float factor) {
  calibrationFactor = factor;
}

// Get Ro value
float H2SSensor::getRo() {
  return ro;
}

// Set environmental conditions
void H2SSensor::setEnvironment(float temp, float hum) {
  temperature = temp;
  humidity = hum;
}

// Check if in CAUTION zone (5-10 ppm)
bool H2SSensor::isCautionZone() {
  float ppm = readPPM();
  return (ppm >= 5.0 && ppm < 10.0);
}

// Check if in BLOCK zone (>10 ppm)
bool H2SSensor::isBlockZone() {
  float ppm = readPPM();
  return (ppm >= 10.0);
}

// Get status string
String H2SSensor::getStatus() {
  float ppm = readPPM();
  if (ppm >= 10.0) {
    return "BLOCK";
  } else if (ppm >= 5.0) {
    return "CAUTION";
  } else {
    return "SAFE";
  }
}

// Self-test functionality
bool H2SSensor::selfTest() {
  Serial.println("🔍 Running H2S sensor self-test...");
  
  // Check if sensor is connected
  int raw = analogRead(pin);
  if (raw == 0 || raw == 4095) {
    Serial.println("❌ H2S sensor not responding (reading at rail)");
    return false;
  }
  
  // Check if Ro is reasonable (typical range 10-200 kΩ)
  if (ro < 1.0 || ro > 500.0) {
    Serial.print("⚠️ H2S sensor Ro value unusual: ");
    Serial.print(ro);
    Serial.println(" kΩ");
    return false;
  }
  
  // Quick response test
  float ppm1 = readPPM();
  delay(100);
  float ppm2 = readPPM();
  
  if (abs(ppm2 - ppm1) > 20) {
    Serial.println("⚠️ H2S sensor reading unstable");
    return false;
  }
  
  Serial.println("✅ H2S sensor self-test passed");
  return true;
}