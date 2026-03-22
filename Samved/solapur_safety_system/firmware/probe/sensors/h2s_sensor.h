/*
 * Solapur Safety System - H2S Sensor Header
 * For MQ-136 Hydrogen Sulfide Sensor
 */

#ifndef H2S_SENSOR_H
#define H2S_SENSOR_H

#include <Arduino.h>

class H2SSensor {
  private:
    int pin;
    float calibrationFactor;
    float rl;  // Load resistance in kΩ
    float ro;  // Sensor resistance in clean air in kΩ
    float temperature;  // For temperature compensation
    float humidity;     // For humidity compensation
    
  public:
    /**
     * Constructor for H2S sensor
     * @param sensorPin Analog pin connected to sensor AO
     * @param loadResistance Load resistance in kΩ (default 10.0kΩ)
     */
    H2SSensor(int sensorPin, float loadResistance = 10.0);
    
    /**
     * Calibrate sensor in clean air
     * Takes 100 samples and calculates Ro
     * Should be called after 24-48 hour warm-up
     */
    void calibrate();
    
    /**
     * Read current H2S concentration in ppm
     * @return H2S concentration in parts per million (ppm)
     */
    float readPPM();
    
    /**
     * Read raw sensor resistance
     * @return Sensor resistance Rs in kΩ
     */
    float readRaw();
    
    /**
     * Get the sensor resistance ratio (Rs/Ro)
     * @return Ratio value for diagnostic purposes
     */
    float getRatio();
    
    /**
     * Set calibration factor to adjust readings
     * @param factor Multiplier for raw readings (default 1.0)
     */
    void setCalibrationFactor(float factor);
    
    /**
     * Get stored Ro value (sensor resistance in clean air)
     * @return Ro in kΩ
     */
    float getRo();
    
    /**
     * Set environmental conditions for compensation
     * @param temp Temperature in °C
     * @param hum Relative humidity in %
     */
    void setEnvironment(float temp, float hum);
    
    /**
     * Check if H2S level is in CAUTION zone (>5ppm)
     * @return true if in CAUTION zone
     */
    bool isCautionZone();
    
    /**
     * Check if H2S level is in BLOCK zone (>10ppm)
     * @return true if in BLOCK zone
     */
    bool isBlockZone();
    
    /**
     * Get the current sensor status as string
     * @return "SAFE", "CAUTION", or "BLOCK"
     */
    String getStatus();
    
    /**
     * Perform a quick functionality test
     * @return true if sensor is responding
     */
    bool selfTest();
};

#endif