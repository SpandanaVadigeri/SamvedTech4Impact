from flask import Flask, request, jsonify
import json
import os
import random
import pickle

app = Flask(__name__)

# Try to load models, but fallback if they are empty or corrupt
try:
    with open('models/spike_predictor.pkl', 'rb') as f:
        spike_model = pickle.load(f)
except Exception as e:
    spike_model = None
    print(f"Warning: Could not load spike_predictor.pkl ({e}). Using mock inference.")

try:
    with open('models/anomaly_detector.pkl', 'rb') as f:
        anomaly_model = pickle.load(f)
except Exception as e:
    anomaly_model = None
    print(f"Warning: Could not load anomaly_detector.pkl ({e}). Using mock inference.")

# Predict Gas Spike
def predict_gas_spike(data):
    if spike_model:
        # Assuming the model expects a 2D array of features
        features = [[data.get('h2s', 0), data.get('ch4', 0), data.get('co', 0), data.get('o2', 20.9)]]
        try:
            prob = spike_model.predict_proba(features)[0][1]
            return prob > 0.5, prob
        except:
            pass
            
    # Fallback heuristic prediction
    h2s = data.get('h2s', 0)
    ch4 = data.get('ch4', 0)
    
    # Increase probability based on current levels
    prob = 0.05
    if h2s > 3.0: prob += 0.3
    if h2s > 7.0: prob += 0.4
    if ch4 > 0.5: prob += 0.2
    
    return prob > 0.5, round(prob, 2)

# Structural Anomaly detection
def detect_anomaly(data):
    if anomaly_model:
        features = [[data.get('vibration', 0), data.get('fall_detected', 0)]]
        try:
            score = anomaly_model.predict_proba(features)[0][1]
            return score > 0.5, score
        except:
            pass
            
    # Fallback heuristic
    vibration = data.get('vibration', 0)
    score = min(1.0, vibration / 20.0) # Assume 20 is high anomaly
    if data.get('fall_detected', False):
        score = 0.95
        
    return score > 0.6, round(score, 2)

# Flood Risk
def assess_flood_risk(data):
    water_level = data.get('water_level', 0)
    if water_level > 80:
        return "HIGH"
    elif water_level > 50:
        return "MEDIUM"
    return "LOW"

# Exposure Risk
def calculate_exposure(data):
    # concentration * time formula abstraction
    # For instant API check, we evaluate concentration
    h2s = data.get('h2s', 0)
    if h2s > 20: 
        return "HIGH"
    elif h2s > 5:
        return "MEDIUM"
    return "LOW"

@app.route('/predict', methods=['POST'])
def predict():
    data = request.json
    
    spike_risk, spike_probability = predict_gas_spike(data)
    anomaly, anomaly_score = detect_anomaly(data)
    flood_risk = assess_flood_risk(data)
    exposure_level = calculate_exposure(data)
    
    result = {
        "spike_risk": spike_risk,
        "spike_probability": spike_probability,
        "anomaly": anomaly,
        "anomaly_score": anomaly_score,
        "flood_risk": flood_risk,
        "exposure_level": exposure_level
    }
    
    # Log the response (mocking report generation backend)
    try:
        os.makedirs('reports', exist_ok=True)
        with open('reports/latest_predictions.json', 'w') as f:
            json.dump(result, f)
    except:
        pass
        
    return jsonify(result)

@app.route('/generate_report', methods=['POST'])
def generate_report():
    try:
        os.makedirs('reports', exist_ok=True)
        # Mocking PDF generation using a stub text file for simulation
        report_path = 'reports/daily_safety_report.pdf'
        with open(report_path, 'wb') as f:
            f.write(b"%PDF-1.4\n%Daily Safety Report Mock Context: Gas Trends, ML Predictions, High-Risk Alerts\n%%EOF")
        return jsonify({"message": "Daily report generated", "path": report_path})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    print("🚀 ML Predictive Pipeline Service running on port 5001")
    app.run(host='0.0.0.0', port=5001)
