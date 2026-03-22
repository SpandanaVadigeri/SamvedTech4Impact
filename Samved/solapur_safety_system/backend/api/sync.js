/**
 * Sync API endpoints
 * Handles offline data synchronization from mobile app
 */

const express = require('express');
const router = express.Router();
const db = require('../database/db');
const { v4: uuidv4 } = require('uuid');

// ==================== SYNC CONFIGURATION ====================

const SYNC_BATCH_SIZE = 1000; // Max records per sync

// ==================== SYNC ENDPOINT ====================

// Main sync endpoint - handles batch upload from mobile
router.post('/', async (req, res) => {
  try {
    const {
      device_id,
      last_sync_time,
      readings,
      worker_vitals,
      alerts,
      decisions,
      sessions
    } = req.body;

    const startTime = Date.now();
    const syncId = uuidv4();

    req.logger.info(`📱 Sync started for device ${device_id}, syncId: ${syncId}`);

    // Start transaction
    const result = await db.transaction(async (client) => {
      const syncResults = {
        readings_synced: 0,
        vitals_synced: 0,
        alerts_synced: 0,
        decisions_synced: 0,
        sessions_synced: 0,
        errors: []
      };

      // 1. Sync gas readings
      if (readings && readings.length > 0) {
        for (const batch of chunkArray(readings, SYNC_BATCH_SIZE)) {
          try {
            const values = [];
            const placeholders = [];
            
            batch.forEach((r, i) => {
              const idx = i * 11;
              placeholders.push(`($${idx+1}, $${idx+2}, $${idx+3}, $${idx+4}, $${idx+5}, $${idx+6}, $${idx+7}, $${idx+8}, $${idx+9}, $${idx+10}, $${idx+11})`);
              values.push(
                r.session_id, r.device_id, r.timestamp,
                r.h2s, r.ch4, r.co, r.o2,
                r.temperature, r.humidity, r.depth, r.probe_level
              );
            });

            await client.query(
              `INSERT INTO gas_readings 
               (session_id, device_id, timestamp, h2s, ch4, co, o2, temperature, humidity, depth, probe_level)
               VALUES ${placeholders.join(',')}
               ON CONFLICT (id) DO NOTHING`,
              values
            );
            
            syncResults.readings_synced += batch.length;
          } catch (error) {
            syncResults.errors.push({ type: 'readings', error: error.message });
          }
        }
      }

      // 2. Sync worker vitals
      if (worker_vitals && worker_vitals.length > 0) {
        for (const batch of chunkArray(worker_vitals, SYNC_BATCH_SIZE)) {
          try {
            const values = [];
            const placeholders = [];
            
            batch.forEach((v, i) => {
              const idx = i * 13;
              placeholders.push(`($${idx+1}, $${idx+2}, $${idx+3}, $${idx+4}, $${idx+5}, $${idx+6}, $${idx+7}, $${idx+8}, $${idx+9}, $${idx+10}, $${idx+11}, $${idx+12}, $${idx+13})`);
              values.push(
                v.session_id, v.worker_id, v.device_id, v.timestamp,
                v.heart_rate, v.spo2, v.temperature,
                v.accel_x, v.accel_y, v.accel_z,
                v.fall_detected, v.panic_pressed, v.battery_level
              );
            });

            await client.query(
              `INSERT INTO worker_vitals 
               (session_id, worker_id, device_id, timestamp, heart_rate, spo2, temperature,
                accel_x, accel_y, accel_z, fall_detected, panic_pressed, battery_level)
               VALUES ${placeholders.join(',')}
               ON CONFLICT (id) DO NOTHING`,
              values
            );
            
            syncResults.vitals_synced += batch.length;
          } catch (error) {
            syncResults.errors.push({ type: 'vitals', error: error.message });
          }
        }
      }

      // 3. Sync alerts
      if (alerts && alerts.length > 0) {
        for (const batch of chunkArray(alerts, SYNC_BATCH_SIZE)) {
          try {
            const values = [];
            const placeholders = [];
            
            batch.forEach((a, i) => {
              const idx = i * 11;
              placeholders.push(`($${idx+1}, $${idx+2}, $${idx+3}, $${idx+4}, $${idx+5}, $${idx+6}, $${idx+7}, $${idx+8}, $${idx+9}, $${idx+10}, $${idx+11})`);
              values.push(
                a.session_id, a.worker_id, a.device_id, a.timestamp,
                a.alert_type, a.severity,
                a.current_value, a.threshold_value, a.message,
                a.acknowledged, a.resolved
              );
            });

            await client.query(
              `INSERT INTO alerts 
               (session_id, worker_id, device_id, timestamp, alert_type, severity,
                current_value, threshold_value, message, acknowledged, resolved)
               VALUES ${placeholders.join(',')}
               ON CONFLICT (id) DO NOTHING`,
              values
            );
            
            syncResults.alerts_synced += batch.length;
          } catch (error) {
            syncResults.errors.push({ type: 'alerts', error: error.message });
          }
        }
      }

      // 4. Sync decisions
      if (decisions && decisions.length > 0) {
        for (const batch of chunkArray(decisions, SYNC_BATCH_SIZE)) {
          try {
            const values = [];
            const placeholders = [];
            
            batch.forEach((d, i) => {
              const idx = i * 7;
              placeholders.push(`($${idx+1}, $${idx+2}, $${idx+3}, $${idx+4}, $${idx+5}, $${idx+6}, $${idx+7})`);
              values.push(
                d.session_id, d.timestamp, d.decision_type,
                d.decision, d.reason, d.made_by, d.overridden
              );
            });

            await client.query(
              `INSERT INTO decisions 
               (session_id, timestamp, decision_type, decision, reason, made_by, overridden)
               VALUES ${placeholders.join(',')}
               ON CONFLICT (id) DO NOTHING`,
              values
            );
            
            syncResults.decisions_synced += batch.length;
          } catch (error) {
            syncResults.errors.push({ type: 'decisions', error: error.message });
          }
        }
      }

      // 5. Sync sessions
      if (sessions && sessions.length > 0) {
        for (const session of sessions) {
          try {
            await client.query(
              `INSERT INTO sessions 
               (session_id, start_time, end_time, location_lat, location_lon, 
                manhole_id, depth_manhole, supervisor_id, worker1_id, worker2_id,
                pre_entry_decision, status)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
               ON CONFLICT (session_id) DO UPDATE SET
                end_time = EXCLUDED.end_time,
                status = EXCLUDED.status`,
              [session.session_id, session.start_time, session.end_time,
               session.location_lat, session.location_lon, session.manhole_id,
               session.depth_manhole, session.supervisor_id, session.worker1_id,
               session.worker2_id, session.pre_entry_decision, session.status]
            );
            
            syncResults.sessions_synced++;
          } catch (error) {
            syncResults.errors.push({ type: 'sessions', error: error.message });
          }
        }
      }

      // Update last sync time for device
      await client.query(
        `INSERT INTO device_sync_log (device_id, last_sync_time, sync_id, records_synced)
         VALUES ($1, NOW(), $2, $3)
         ON CONFLICT (device_id) DO UPDATE SET
          last_sync_time = NOW(),
          sync_id = EXCLUDED.sync_id,
          records_synced = EXCLUDED.records_synced`,
        [device_id, syncId, syncResults.readings_synced + syncResults.vitals_synced]
      );

      return syncResults;
    });

    const duration = Date.now() - startTime;
    req.logger.info(`✅ Sync completed in ${duration}ms`, result);

    // Get pending commands for device
    const commands = await db.query(
      `SELECT * FROM command_queue 
       WHERE device_id = $1 
         AND NOT delivered 
         AND (expiry IS NULL OR expiry > NOW())
       ORDER BY issued_at ASC`,
      [device_id]
    );

    res.json({
      success: true,
      sync_id: syncId,
      sync_time: new Date().toISOString(),
      stats: result,
      pending_commands: commands.rows,
      next_sync_recommended: new Date(Date.now() + 5 * 60000).toISOString() // 5 minutes
    });

  } catch (error) {
    req.logger.error('❌ Sync failed:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Sync failed',
      message: error.message 
    });
  }
});

// ==================== GET PENDING SYNC DATA ====================

// Get data that hasn't been synced yet (for new devices)
router.get('/pending/:deviceId', async (req, res) => {
  try {
    const { deviceId } = req.params;
    const { since } = req.query;

    const sinceTime = since || new Date(0).toISOString();

    // Get device info
    const device = await db.query(
      `SELECT * FROM devices WHERE device_id = $1`,
      [deviceId]
    );

    if (device.rows.length === 0) {
      return res.status(404).json({ error: 'Device not registered' });
    }

    // Get recent data for this device
    const [readings, vitals, alerts, commands] = await Promise.all([
      db.query(
        `SELECT * FROM gas_readings 
         WHERE device_id = $1 AND timestamp > $2
         ORDER BY timestamp ASC
         LIMIT 10000`,
        [device.rows[0].id, sinceTime]
      ),
      db.query(
        `SELECT * FROM worker_vitals 
         WHERE device_id = $1 AND timestamp > $2
         ORDER BY timestamp ASC
         LIMIT 10000`,
        [device.rows[0].id, sinceTime]
      ),
      db.query(
        `SELECT * FROM alerts 
         WHERE device_id = $1 AND timestamp > $2
         ORDER BY timestamp ASC`,
        [device.rows[0].id, sinceTime]
      ),
      db.query(
        `SELECT * FROM command_queue 
         WHERE device_id = $1 AND NOT delivered
         ORDER BY issued_at ASC`,
        [device.rows[0].id]
      )
    ]);

    res.json({
      success: true,
      device: device.rows[0],
      data: {
        readings: readings.rows,
        vitals: vitals.rows,
        alerts: alerts.rows,
        pending_commands: commands.rows
      },
      counts: {
        readings: readings.rows.length,
        vitals: vitals.rows.length,
        alerts: alerts.rows.length,
        commands: commands.rows.length
      }
    });

  } catch (error) {
    req.logger.error('Error fetching pending data:', error);
    res.status(500).json({ error: 'Failed to fetch pending data' });
  }
});

// ==================== CONFLICT RESOLUTION ====================

// Resolve sync conflicts
router.post('/resolve-conflict', async (req, res) => {
  try {
    const { conflicts } = req.body;

    const resolution = await db.transaction(async (client) => {
      const results = [];

      for (const conflict of conflicts) {
        const { table, record_id, client_version, server_version, resolution_strategy } = conflict;

        let resolvedRecord;

        switch (resolution_strategy) {
          case 'server_wins':
            resolvedRecord = server_version;
            break;
          case 'client_wins':
            resolvedRecord = client_version;
            // Update server with client version
            await updateRecord(client, table, client_version);
            break;
          case 'merge':
            resolvedRecord = { ...server_version, ...client_version };
            await updateRecord(client, table, resolvedRecord);
            break;
          default:
            throw new Error(`Unknown resolution strategy: ${resolution_strategy}`);
        }

        // Log conflict resolution
        await client.query(
          `INSERT INTO conflict_log (table_name, record_id, client_version, server_version, resolution_strategy, resolved_at)
           VALUES ($1, $2, $3, $4, $5, NOW())`,
          [table, record_id, JSON.stringify(client_version), JSON.stringify(server_version), resolution_strategy]
        );

        results.push({
          record_id,
          resolved: resolvedRecord
        });
      }

      return results;
    });

    res.json({
      success: true,
      resolutions: resolution
    });

  } catch (error) {
    req.logger.error('Error resolving conflicts:', error);
    res.status(500).json({ error: 'Failed to resolve conflicts' });
  }
});

// ==================== HELPER FUNCTIONS ====================

// Split array into chunks
function chunkArray(array, size) {
  const chunks = [];
  for (let i = 0; i < array.length; i += size) {
    chunks.push(array.slice(i, i + size));
  }
  return chunks;
}

// Update record helper
async function updateRecord(client, table, record) {
  const keys = Object.keys(record);
  const values = Object.values(record);
  
  const setClause = keys.map((key, i) => `${key} = $${i + 2}`).join(', ');
  
  await client.query(
    `UPDATE ${table} SET ${setClause} WHERE id = $1`,
    [record.id, ...values]
  );
}

// ==================== SYNC STATUS ====================

// Get sync status for all devices
router.get('/status', async (req, res) => {
  try {
    const result = await db.query(
      `SELECT d.device_id, d.device_name, d.device_type,
              dsl.last_sync_time, dsl.sync_id, dsl.records_synced,
              EXTRACT(EPOCH FROM (NOW() - dsl.last_sync_time)) as seconds_since_sync
       FROM devices d
       LEFT JOIN device_sync_log dsl ON d.id = dsl.device_id
       WHERE d.is_active = true
       ORDER BY dsl.last_sync_time DESC NULLS LAST`
    );

    res.json({
      success: true,
      data: result.rows,
      summary: {
        total_devices: result.rows.length,
        synced_last_5min: result.rows.filter(r => r.seconds_since_sync < 300).length,
        synced_last_hour: result.rows.filter(r => r.seconds_since_sync < 3600).length,
        never_synced: result.rows.filter(r => !r.last_sync_time).length
      }
    });

  } catch (error) {
    req.logger.error('Error fetching sync status:', error);
    res.status(500).json({ error: 'Failed to fetch sync status' });
  }
});

module.exports = router;