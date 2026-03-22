/**
 * Readings API endpoints
 * Handles gas readings and worker vitals
 */

const express = require('express');
const router = express.Router();
const db = require('../database/db');

// ==================== GAS READINGS ====================

// Get latest readings for a session
router.get('/latest/:sessionId', async (req, res) => {
  try {
    const { sessionId } = req.params;
    const { limit = 100 } = req.query;

    const result = await db.query(
      `SELECT * FROM gas_readings 
       WHERE session_id = $1 
       ORDER BY timestamp DESC 
       LIMIT $2`,
      [sessionId, limit]
    );

    res.json({
      success: true,
      data: result.rows,
      count: result.rows.length
    });
  } catch (error) {
    req.logger.error('Error fetching readings:', error);
    res.status(500).json({ error: 'Failed to fetch readings' });
  }
});

// Get readings by time range
router.get('/range', async (req, res) => {
  try {
    const { start, end, sessionId, deviceId } = req.query;

    let query = 'SELECT * FROM gas_readings WHERE timestamp BETWEEN $1 AND $2';
    const params = [start, end];
    let paramIndex = 3;

    if (sessionId) {
      query += ` AND session_id = $${paramIndex}`;
      params.push(sessionId);
      paramIndex++;
    }

    if (deviceId) {
      query += ` AND device_id = $${paramIndex}`;
      params.push(deviceId);
    }

    query += ' ORDER BY timestamp ASC';

    const result = await db.query(query, params);

    res.json({
      success: true,
      data: result.rows,
      count: result.rows.length
    });
  } catch (error) {
    req.logger.error('Error fetching readings range:', error);
    res.status(500).json({ error: 'Failed to fetch readings' });
  }
});

// Get aggregated statistics for readings
router.get('/stats', async (req, res) => {
  try {
    const { sessionId, hours = 24 } = req.query;

    const result = await db.query(
      `SELECT 
         COUNT(*) as total_readings,
         AVG(h2s) as avg_h2s,
         MAX(h2s) as max_h2s,
         MIN(h2s) as min_h2s,
         AVG(o2) as avg_o2,
         MIN(o2) as min_o2,
         AVG(ch4) as avg_ch4,
         MAX(ch4) as max_ch4,
         AVG(co) as avg_co,
         MAX(co) as max_co,
         COUNT(CASE WHEN h2s > 10 THEN 1 END) as h2s_block_events,
         COUNT(CASE WHEN o2 < 19.5 THEN 1 END) as o2_block_events
       FROM gas_readings 
       WHERE timestamp > NOW() - ($1 || ' hours')::INTERVAL
       ${sessionId ? 'AND session_id = $2' : ''}`,
      sessionId ? [hours, sessionId] : [hours]
    );

    res.json({
      success: true,
      data: result.rows[0]
    });
  } catch (error) {
    req.logger.error('Error fetching reading stats:', error);
    res.status(500).json({ error: 'Failed to fetch statistics' });
  }
});

// Post new gas reading (from devices)
router.post('/', async (req, res) => {
  try {
    const {
      session_id,
      device_id,
      timestamp,
      h2s,
      ch4,
      co,
      o2,
      temperature,
      humidity,
      depth,
      probe_level
    } = req.body;

    // Validate required fields
    if (!session_id || !device_id) {
      return res.status(400).json({ 
        error: 'Missing required fields',
        message: 'session_id and device_id are required'
      });
    }

    const result = await db.query(
      `INSERT INTO gas_readings 
       (session_id, device_id, timestamp, h2s, ch4, co, o2, temperature, humidity, depth, probe_level)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
       RETURNING *`,
      [session_id, device_id, timestamp || new Date(), h2s, ch4, co, o2, temperature, humidity, depth, probe_level]
    );

    // Emit real-time update via Socket.IO
    req.io.to(`session_${session_id}`).emit('new-reading', result.rows[0]);
    
    // Also emit to control room for monitoring
    req.io.to('control').emit('live-reading', {
      session_id,
      reading: result.rows[0],
      timestamp: new Date()
    });

    // Check thresholds and create alerts if needed
    await checkThresholdsAndAlert(result.rows[0], req);

    res.status(201).json({
      success: true,
      data: result.rows[0]
    });
  } catch (error) {
    req.logger.error('Error saving reading:', error);
    res.status(500).json({ error: 'Failed to save reading' });
  }
});

// Post multiple readings (batch upload for offline sync)
router.post('/batch', async (req, res) => {
  try {
    const { readings, device_id, session_id } = req.body;

    if (!readings || !Array.isArray(readings) || readings.length === 0) {
      return res.status(400).json({ error: 'No readings provided' });
    }

    const insertedIds = [];
    const errors = [];

    // Use transaction for batch insert
    await db.transaction(async (client) => {
      for (const reading of readings) {
        try {
          const result = await client.query(
            `INSERT INTO gas_readings 
             (session_id, device_id, timestamp, h2s, ch4, co, o2, temperature, humidity, depth, probe_level)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
             RETURNING id`,
            [
              reading.session_id || session_id,
              reading.device_id || device_id,
              reading.timestamp || new Date(),
              reading.h2s,
              reading.ch4,
              reading.co,
              reading.o2,
              reading.temperature,
              reading.humidity,
              reading.depth,
              reading.probe_level
            ]
          );
          insertedIds.push(result.rows[0].id);
        } catch (e) {
          errors.push({ reading, error: e.message });
        }
      }
    });

    req.logger.info(`Batch inserted ${insertedIds.length} readings, ${errors.length} errors`);

    res.status(201).json({
      success: true,
      inserted: insertedIds.length,
      errors: errors.length,
      error_details: errors
    });
  } catch (error) {
    req.logger.error('Error in batch insert:', error);
    res.status(500).json({ error: 'Failed to process batch' });
  }
});

// ==================== WORKER VITALS ====================

// Get worker vitals
router.get('/vitals/:workerId', async (req, res) => {
  try {
    const { workerId } = req.params;
    const { limit = 100, start, end } = req.query;

    let query = 'SELECT * FROM worker_vitals WHERE worker_id = $1';
    const params = [workerId];
    let paramIndex = 2;

    if (start && end) {
      query += ` AND timestamp BETWEEN $${paramIndex} AND $${paramIndex + 1}`;
      params.push(start, end);
      paramIndex += 2;
    }

    query += ' ORDER BY timestamp DESC LIMIT $' + paramIndex;
    params.push(limit);

    const result = await db.query(query, params);

    res.json({
      success: true,
      data: result.rows,
      count: result.rows.length
    });
  } catch (error) {
    req.logger.error('Error fetching vitals:', error);
    res.status(500).json({ error: 'Failed to fetch vitals' });
  }
});

// Get latest vitals for all active workers
router.get('/vitals/current/all', async (req, res) => {
  try {
    const result = await db.query(
      `SELECT DISTINCT ON (wv.worker_id) 
         wv.*,
         u.full_name,
         u.worker_id as worker_code,
         s.session_id,
         s.manhole_id
       FROM worker_vitals wv
       JOIN users u ON wv.worker_id = u.id
       LEFT JOIN sessions s ON wv.session_id = s.id
       WHERE wv.timestamp > NOW() - INTERVAL '5 minutes'
       ORDER BY wv.worker_id, wv.timestamp DESC`
    );

    res.json({
      success: true,
      data: result.rows,
      count: result.rows.length
    });
  } catch (error) {
    req.logger.error('Error fetching current vitals:', error);
    res.status(500).json({ error: 'Failed to fetch current vitals' });
  }
});

// Get vitals statistics for a worker
router.get('/vitals/:workerId/stats', async (req, res) => {
  try {
    const { workerId } = req.params;
    const { days = 7 } = req.query;

    const result = await db.query(
      `SELECT 
         COUNT(*) as total_readings,
         AVG(heart_rate) as avg_heart_rate,
         MAX(heart_rate) as max_heart_rate,
         MIN(heart_rate) as min_heart_rate,
         COUNT(CASE WHEN fall_detected = true THEN 1 END) as fall_count,
         COUNT(CASE WHEN panic_pressed = true THEN 1 END) as panic_count,
         AVG(battery_level) as avg_battery,
         MIN(battery_level) as min_battery
       FROM worker_vitals 
       WHERE worker_id = $1 
         AND timestamp > NOW() - ($2 || ' days')::INTERVAL`,
      [workerId, days]
    );

    res.json({
      success: true,
      data: result.rows[0]
    });
  } catch (error) {
    req.logger.error('Error fetching vitals stats:', error);
    res.status(500).json({ error: 'Failed to fetch vitals statistics' });
  }
});

// Post new worker vitals
router.post('/vitals', async (req, res) => {
  try {
    const {
      session_id,
      worker_id,
      device_id,
      timestamp,
      heart_rate,
      spo2,
      temperature,
      accel_x,
      accel_y,
      accel_z,
      fall_detected,
      panic_pressed,
      battery_level
    } = req.body;

    // Validate required fields
    if (!worker_id) {
      return res.status(400).json({ 
        error: 'Missing required fields',
        message: 'worker_id is required'
      });
    }

    const result = await db.query(
      `INSERT INTO worker_vitals 
       (session_id, worker_id, device_id, timestamp, heart_rate, spo2, temperature, 
        accel_x, accel_y, accel_z, fall_detected, panic_pressed, battery_level)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
       RETURNING *`,
      [
        session_id, 
        worker_id, 
        device_id, 
        timestamp || new Date(), 
        heart_rate, 
        spo2, 
        temperature,
        accel_x, 
        accel_y, 
        accel_z, 
        fall_detected || false, 
        panic_pressed || false, 
        battery_level
      ]
    );

    // Emit real-time update
    if (session_id) {
      req.io.to(`session_${session_id}`).emit('new-vitals', result.rows[0]);
    }
    req.io.to('control').emit('worker-status-update', {
      worker_id,
      vitals: result.rows[0]
    });

    // Check for emergencies
    if (fall_detected || panic_pressed) {
      await createEmergencyAlert({
        session_id,
        worker_id,
        type: fall_detected ? 'fall_detected' : 'panic_button',
        severity: 'critical',
        message: fall_detected ? 'Worker fall detected!' : 'Panic button pressed!',
        current_value: fall_detected ? 1 : 0,
        threshold_value: 0
      }, req);
    }

    // Check for abnormal heart rate
    if (heart_rate > 120) {
      await createAlert({
        session_id,
        worker_id,
        type: 'heart_rate_high',
        severity: 'warning',
        current_value: heart_rate,
        threshold_value: 120,
        message: `High heart rate: ${heart_rate} bpm`
      }, req);
    } else if (heart_rate < 40 && heart_rate > 0) {
      await createAlert({
        session_id,
        worker_id,
        type: 'heart_rate_low',
        severity: 'warning',
        current_value: heart_rate,
        threshold_value: 40,
        message: `Low heart rate: ${heart_rate} bpm`
      }, req);
    }

    res.status(201).json({
      success: true,
      data: result.rows[0]
    });
  } catch (error) {
    req.logger.error('Error saving vitals:', error);
    res.status(500).json({ error: 'Failed to save vitals' });
  }
});

// Post multiple vitals (batch upload for offline sync)
router.post('/vitals/batch', async (req, res) => {
  try {
    const { vitals, worker_id, session_id } = req.body;

    if (!vitals || !Array.isArray(vitals) || vitals.length === 0) {
      return res.status(400).json({ error: 'No vitals provided' });
    }

    const insertedIds = [];
    const errors = [];

    await db.transaction(async (client) => {
      for (const vital of vitals) {
        try {
          const result = await client.query(
            `INSERT INTO worker_vitals 
             (session_id, worker_id, device_id, timestamp, heart_rate, spo2, temperature, 
              accel_x, accel_y, accel_z, fall_detected, panic_pressed, battery_level)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
             RETURNING id`,
            [
              vital.session_id || session_id,
              vital.worker_id || worker_id,
              vital.device_id,
              vital.timestamp || new Date(),
              vital.heart_rate,
              vital.spo2,
              vital.temperature,
              vital.accel_x,
              vital.accel_y,
              vital.accel_z,
              vital.fall_detected || false,
              vital.panic_pressed || false,
              vital.battery_level
            ]
          );
          insertedIds.push(result.rows[0].id);
        } catch (e) {
          errors.push({ vital, error: e.message });
        }
      }
    });

    req.logger.info(`Batch inserted ${insertedIds.length} vitals, ${errors.length} errors`);

    res.status(201).json({
      success: true,
      inserted: insertedIds.length,
      errors: errors.length,
      error_details: errors
    });
  } catch (error) {
    req.logger.error('Error in vitals batch insert:', error);
    res.status(500).json({ error: 'Failed to process vitals batch' });
  }
});

// ==================== COMBINED DATA ====================

// Get combined data for a session (readings + vitals)
router.get('/combined/:sessionId', async (req, res) => {
  try {
    const { sessionId } = req.params;
    const { limit = 100 } = req.query;

    const [readings, vitals] = await Promise.all([
      db.query(
        `SELECT * FROM gas_readings 
         WHERE session_id = $1 
         ORDER BY timestamp DESC 
         LIMIT $2`,
        [sessionId, limit]
      ),
      db.query(
        `SELECT * FROM worker_vitals 
         WHERE session_id = $1 
         ORDER BY timestamp DESC 
         LIMIT $2`,
        [sessionId, limit]
      )
    ]);

    res.json({
      success: true,
      data: {
        readings: readings.rows,
        vitals: vitals.rows
      },
      counts: {
        readings: readings.rows.length,
        vitals: vitals.rows.length
      }
    });
  } catch (error) {
    req.logger.error('Error fetching combined data:', error);
    res.status(500).json({ error: 'Failed to fetch combined data' });
  }
});

// ==================== HELPER FUNCTIONS ====================

async function checkThresholdsAndAlert(reading, req) {
  const thresholds = {
    h2s: { caution: 5.0, block: 10.0 },
    ch4: { caution: 0.5, block: 2.0 },
    co: { caution: 25.0, block: 35.0 },
    o2: { caution: 20.8, block: 19.5 }
  };

  // Check H2S
  if (reading.h2s >= thresholds.h2s.block) {
    await createAlert({
      session_id: reading.session_id,
      device_id: reading.device_id,
      type: 'gas_h2s_high',
      severity: 'critical',
      current_value: reading.h2s,
      threshold_value: thresholds.h2s.block,
      message: `🚨 CRITICAL: H2S level ${reading.h2s} ppm exceeds BLOCK threshold ${thresholds.h2s.block} ppm`
    }, req);
  } else if (reading.h2s >= thresholds.h2s.caution) {
    await createAlert({
      session_id: reading.session_id,
      device_id: reading.device_id,
      type: 'gas_h2s_high',
      severity: 'warning',
      current_value: reading.h2s,
      threshold_value: thresholds.h2s.caution,
      message: `⚠️ WARNING: H2S level ${reading.h2s} ppm exceeds CAUTION threshold ${thresholds.h2s.caution} ppm`
    }, req);
  }

  // Check CH4
  if (reading.ch4 >= thresholds.ch4.block) {
    await createAlert({
      session_id: reading.session_id,
      device_id: reading.device_id,
      type: 'gas_ch4_high',
      severity: 'critical',
      current_value: reading.ch4,
      threshold_value: thresholds.ch4.block,
      message: `🚨 CRITICAL: CH4 level ${reading.ch4}% LEL exceeds BLOCK threshold ${thresholds.ch4.block}% LEL`
    }, req);
  } else if (reading.ch4 >= thresholds.ch4.caution) {
    await createAlert({
      session_id: reading.session_id,
      device_id: reading.device_id,
      type: 'gas_ch4_high',
      severity: 'warning',
      current_value: reading.ch4,
      threshold_value: thresholds.ch4.caution,
      message: `⚠️ WARNING: CH4 level ${reading.ch4}% LEL exceeds CAUTION threshold ${thresholds.ch4.caution}% LEL`
    }, req);
  }

  // Check CO
  if (reading.co >= thresholds.co.block) {
    await createAlert({
      session_id: reading.session_id,
      device_id: reading.device_id,
      type: 'gas_co_high',
      severity: 'critical',
      current_value: reading.co,
      threshold_value: thresholds.co.block,
      message: `🚨 CRITICAL: CO level ${reading.co} ppm exceeds BLOCK threshold ${thresholds.co.block} ppm`
    }, req);
  } else if (reading.co >= thresholds.co.caution) {
    await createAlert({
      session_id: reading.session_id,
      device_id: reading.device_id,
      type: 'gas_co_high',
      severity: 'warning',
      current_value: reading.co,
      threshold_value: thresholds.co.caution,
      message: `⚠️ WARNING: CO level ${reading.co} ppm exceeds CAUTION threshold ${thresholds.co.caution} ppm`
    }, req);
  }

  // Check O2
  if (reading.o2 <= thresholds.o2.block) {
    await createAlert({
      session_id: reading.session_id,
      device_id: reading.device_id,
      type: 'gas_o2_low',
      severity: 'critical',
      current_value: reading.o2,
      threshold_value: thresholds.o2.block,
      message: `🚨 CRITICAL: O2 level ${reading.o2}% is below BLOCK threshold ${thresholds.o2.block}%`
    }, req);
  } else if (reading.o2 <= thresholds.o2.caution) {
    await createAlert({
      session_id: reading.session_id,
      device_id: reading.device_id,
      type: 'gas_o2_low',
      severity: 'warning',
      current_value: reading.o2,
      threshold_value: thresholds.o2.caution,
      message: `⚠️ WARNING: O2 level ${reading.o2}% is below CAUTION threshold ${thresholds.o2.caution}%`
    }, req);
  }
}

async function createAlert(alertData, req) {
  try {
    // Get worker info if available
    let workerInfo = null;
    if (alertData.worker_id) {
      const workerResult = await db.query(
        'SELECT full_name, worker_id FROM users WHERE id = $1',
        [alertData.worker_id]
      );
      if (workerResult.rows.length > 0) {
        workerInfo = workerResult.rows[0];
      }
    }

    const result = await db.query(
      `INSERT INTO alerts 
       (session_id, device_id, worker_id, alert_type, severity, current_value, threshold_value, message, timestamp)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())
       RETURNING *`,
      [
        alertData.session_id, 
        alertData.device_id, 
        alertData.worker_id,
        alertData.type, 
        alertData.severity,
        alertData.current_value, 
        alertData.threshold_value, 
        alertData.message
      ]
    );

    const alert = result.rows[0];
    
    // Add worker info to alert
    if (workerInfo) {
      alert.worker_name = workerInfo.full_name;
      alert.worker_code = workerInfo.worker_id;
    }

    // Emit alert via Socket.IO to different rooms based on severity
    req.io.to('supervisor').emit('new-alert', alert);
    
    // If critical, also notify control center and possibly emergency services
    if (alertData.severity === 'critical') {
      req.io.to('control').emit('critical-alert', alert);
      
      // Log critical alert for audit
      req.logger.warn(`🚨 CRITICAL ALERT: ${alertData.message}`);
      
      // Check if this alert needs immediate escalation
      scheduleEscalation(alert.id, alertData.severity, req);
    } else {
      req.logger.info(`📢 Alert created: ${alertData.message}`);
    }

    return alert;
  } catch (error) {
    req.logger.error('Error creating alert:', error);
    throw error;
  }
}

async function createEmergencyAlert(alertData, req) {
  // Emergency alerts are always critical
  alertData.severity = 'critical';
  return createAlert(alertData, req);
}

function scheduleEscalation(alertId, severity, req) {
  // Schedule escalation if not acknowledged within time limits
  // Level 1: 5 seconds (supervisor)
  // Level 2: 10 seconds (control center)
  // Level 3: 15 seconds (emergency services)
  
  setTimeout(async () => {
    try {
      // Check if alert still not acknowledged
      const result = await db.query(
        'SELECT * FROM alerts WHERE id = $1 AND acknowledged = false',
        [alertId]
      );
      
      if (result.rows.length > 0) {
        const alert = result.rows[0];
        
        // Escalate to level 2
        await db.query(
          'UPDATE alerts SET level = 2 WHERE id = $1',
          [alertId]
        );
        
        req.io.to('control').emit('alert-escalated', {
          alertId,
          level: 2,
          message: 'Alert not acknowledged by supervisor'
        });
        
        req.logger.warn(`⚠️ Alert ${alertId} escalated to level 2`);
        
        // Level 3 escalation after another 10 seconds
        setTimeout(async () => {
          try {
            const level2Result = await db.query(
              'SELECT * FROM alerts WHERE id = $1 AND acknowledged = false AND level = 2',
              [alertId]
            );
            
            if (level2Result.rows.length > 0) {
              await db.query(
                'UPDATE alerts SET level = 3 WHERE id = $1',
                [alertId]
              );
              
              req.io.to('emergency').emit('emergency-activated', {
                alertId,
                level: 3,
                message: 'EMERGENCY - No acknowledgment received'
              });
              
              req.logger.error(`🚨 EMERGENCY: Alert ${alertId} escalated to level 3`);
              
              // Here you would trigger SMS/call to emergency services
              // await triggerEmergencyServices(alert);
            }
          } catch (error) {
            req.logger.error('Error in level 3 escalation:', error);
          }
        }, 10000); // 10 seconds for level 3
      }
    } catch (error) {
      req.logger.error('Error in escalation:', error);
    }
  }, 5000); // 5 seconds for level 2
}

// Export cleanup function
router.cleanup = function() {
  // Any cleanup needed
};

module.exports = router;