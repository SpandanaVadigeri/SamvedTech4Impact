/**
 * Solapur Safety System - Main Backend Server
 * Express.js REST API + Socket.IO for real-time safety management
 *
 * KEY FIXES:
 *  ✅ Global AUTO/MANUAL mode — simulation STOPS when MANUAL is active
 *  ✅ Entry request/approval flow via socket
 *  ✅ Exposure history stored in JSON file
 *  ✅ Prediction engine (24h exposure-based)
 *  ✅ Per-device manual override map
 */

const express    = require('express');
const cors       = require('cors');
const helmet     = require('helmet');
const rateLimit  = require('express-rate-limit');
const dotenv     = require('dotenv');
const http       = require('http');
const socketIo   = require('socket.io');
const { createLogger, format, transports } = require('winston');
const fs         = require('fs');
const path       = require('path');

dotenv.config();

// ── Import modules ────────────────────────────────────────────────────────────
const db           = require('./database/db');
const readingsRouter = require('./api/readings');
const alertsRouter   = require('./api/alerts');
const syncRouter     = require('./api/sync');
const authRouter     = require('./api/auth');
const { authenticateToken } = require('./middleware/auth');

// ── Express + Socket.IO setup ─────────────────────────────────────────────────
const app    = express();
const server = http.createServer(app);
const io     = socketIo(server, {
  cors:      { origin: '*', methods: ['GET', 'POST'] },
  transports: ['websocket', 'polling'],
  allowEIO3: true,
});

// ── Logger ────────────────────────────────────────────────────────────────────
const logger = createLogger({
  level: 'info',
  format: format.combine(format.timestamp(), format.json()),
  transports: [
    new transports.File({ filename: 'error.log',    level: 'error' }),
    new transports.File({ filename: 'combined.log' }),
    new transports.Console({ format: format.simple() }),
  ],
});

// ── Rate limiting ─────────────────────────────────────────────────────────────
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5000,
  message: 'Too many requests from this IP',
});

// ── Middleware ────────────────────────────────────────────────────────────────
app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use('/api/', limiter);
app.use((req, _res, next) => { req.logger = logger; req.io = io; next(); });

// ── Routes ────────────────────────────────────────────────────────────────────
app.use('/api/auth', authRouter);

// =============================================================================
//  GLOBAL STATE
// =============================================================================

// ── AUTO / MANUAL mode (global) ───────────────────────────────────────────────
let mode = 'AUTO'; // 'AUTO' | 'MANUAL'
let manualData = { h2s: 0, ch4: 0, co: 0, o2: 20.9 };

// ── Per-device manual override (keeps legacy per-device support) ──────────────
const manualOverride   = {};
const latestManualData = {};

// ── Worker active status ──────────────────────────────────────────────────────
const workerActiveStatus = {};

// ── Global supervisor override ────────────────────────────────────────────────
let globalOverrideState = null; // 'BLOCK' | 'SAFE' | null

// ── Entry sessions (worker entry request/approval flow) ───────────────────────
// Map: sessionId → { workerId, manholeId, supervisorSocketId, workerSocketId, status }
const entrySessions = new Map();

// ── Socket ID tracking ─────────────────────────────────────────────────────────
// Map: userId → socketId (last connected)
const userSockets = new Map();

// ── Manholes DB (in-memory) ───────────────────────────────────────────────────
let manholesDB = [
  { id: 'MH-001', location: 'Main Street',  status: 'SAFE'    },
  { id: 'MH-002', location: 'North Avenue', status: 'CAUTION' },
];

// ── Assignments (in-memory) ───────────────────────────────────────────────────
let assignmentsDB = [];

// ── Worker sessions (in-memory) ──────────────────────────────────────────────
const workerSessions = new Map();
const panicLog       = [];

// =============================================================================
//  PERSISTENT EXPOSURE TRACKING
// =============================================================================

const exposureFile = path.join(__dirname, 'exposure.json');
const exposureMap  = new Map();

if (fs.existsSync(exposureFile)) {
  try {
    const raw    = fs.readFileSync(exposureFile);
    const parsed = JSON.parse(raw);
    for (const [key, val] of Object.entries(parsed)) {
      exposureMap.set(key, val);
    }
  } catch (_) {}
}

function saveExposure() {
  const obj = {};
  for (const [k, v] of exposureMap.entries()) obj[k] = v;
  try { fs.writeFileSync(exposureFile, JSON.stringify(obj, null, 2)); } catch (_) {}
}

// ── Exposure history log (for POST /exposure/save) ───────────────────────────
const exposureHistoryFile = path.join(__dirname, 'exposure_history.json');
let exposureHistory = [];

if (fs.existsSync(exposureHistoryFile)) {
  try { exposureHistory = JSON.parse(fs.readFileSync(exposureHistoryFile)); } catch (_) { exposureHistory = []; }
}

function saveExposureHistory() {
  try { fs.writeFileSync(exposureHistoryFile, JSON.stringify(exposureHistory, null, 2)); } catch (_) {}
}

// =============================================================================
//  BOUNDED MEMORY LOG
// =============================================================================

const MAX_LOGS  = 500;
const memoryLogs = [];

// =============================================================================
//  SAFETY EVALUATION ENGINE
// =============================================================================

function evaluateSafety(data, mlData) {
  let status = 'SAFE';
  let alerts = [];

  const h2s      = data.h2s      || 0;
  const ch4      = data.ch4      || 0;
  const co       = data.co       || 0;
  const o2       = data.o2       !== undefined ? data.o2 : 20.9;
  const workerId = data.worker_id || data.device_id || 'UNKNOWN';

  // Track exposure
  if (!exposureMap.has(workerId)) exposureMap.set(workerId, 0);
  const currentExposure = exposureMap.get(workerId) + (h2s * 0.1);
  exposureMap.set(workerId, currentExposure);
  saveExposure();

  const exposureLevel = mlData
    ? mlData.exposure_level
    : (currentExposure > 20 ? 'HIGH' : currentExposure > 5 ? 'MEDIUM' : 'LOW');

  // ML fusion
  if (mlData) {
    if (mlData.spike_risk === true) {
      status = 'CAUTION';
      alerts.push(`PREDICTED GAS SPIKE: ${Math.round(mlData.spike_probability * 100)}% risk`);
    }
    if (mlData.anomaly === true) {
      status = 'CAUTION';
      alerts.push(`STRUCTURAL/BEHAVIORAL ANOMALY: score ${mlData.anomaly_score}`);
    }
    if (mlData.flood_risk === 'HIGH') {
      status = 'BLOCK';
      alerts.push('PREDICTED FLOOD RISK: Evacuate immediately');
    }
    if (exposureLevel === 'HIGH') {
      status = 'BLOCK';
      alerts.push('EXPOSURE LIMIT REACHED: Evacuate immediately');
    }
  }

  // Deterministic rules — always override ML if worse
  if (h2s > 10 || o2 < 19.5 || ch4 > 2.0 || co > 35) {
    status = 'BLOCK';
    alerts.push('CRITICAL GAS SPIKE: Evacuate Immediately');
  } else if (status !== 'BLOCK' && (h2s > 5 || o2 < 20.0 || ch4 > 0.5 || co > 25)) {
    status = 'CAUTION';
    alerts.push('CAUTION: Gas levels rising');
  }

  if (data.panic === true)                   { status = 'BLOCK'; alerts.push('PANIC BUTTON TRIGGERED'); }
  if (data.fall  === true)                   { status = 'BLOCK'; alerts.push('WORKER FALL DETECTED'); }
  if (data.spo2  && data.spo2 < 92)         { status = 'BLOCK'; alerts.push('CRITICAL HYPOXIA: SpO2 levels danger zone!'); }
  if (data.water_level && data.water_level > 80) { status = 'BLOCK'; alerts.push('FLOOD WARNING: Elevated Water Level'); }

  // Global supervisor override
  if (globalOverrideState === 'BLOCK') {
    status = 'BLOCK';
    alerts.push('SUPERVISOR MANUAL OVERRIDE: BLOCK/EVACUATION IN EFFECT');
  } else if (globalOverrideState === 'SAFE') {
    globalOverrideState = null;
  }

  alerts = [...new Set(alerts)];
  return { status, alerts, exposure: currentExposure, ml_insights: mlData };
}

// =============================================================================
//  ML PIPELINE CALL (async)
// =============================================================================

function askMLPipeline(data) {
  return new Promise((resolve) => {
    const postData = JSON.stringify(data);
    const options = {
      hostname: '127.0.0.1', port: 5001, path: '/predict', method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(postData) },
    };
    const req = http.request(options, (res) => {
      let buf = '';
      res.on('data', (c) => buf += c);
      res.on('end', () => { try { resolve(JSON.parse(buf)); } catch (_) { resolve(null); } });
    });
    req.on('error', () => resolve(null));
    req.setTimeout(800, () => { req.destroy(); resolve(null); });
    req.write(postData);
    req.end();
  });
}

// =============================================================================
//  REST ENDPOINTS
// =============================================================================

// Health check
app.get('/health', (_req, res) =>
  res.json({ status: 'OK', timestamp: new Date().toISOString(), uptime: process.uptime() })
);

// GET /api/mode — current global mode
app.get('/api/mode', (_req, res) => {
  res.json({ mode, manualData });
});

// ── Simulator ingest ──────────────────────────────────────────────────────────
// app.post('/api/simulator', async (req, res) => {
//   const deviceId = req.body.device_id;
//   let data = req.body;

//   // ✅ CRITICAL: If MANUAL mode is globally active, OVERRIDE incoming data
//   // but continue the loop so the graph updates in real-time.
//   if (mode === 'MANUAL') {
//     data = {
//       ...data,
//       h2s: manualData.h2s,
//       ch4: manualData.ch4,
//       co:  manualData.co,
//       o2:  manualData.o2,
//       source: 'manual'
//     };
//   } else {
//     data = { ...data, source: 'auto' };
    
//     // Per-device override check (legacy support)
//     if (manualOverride[deviceId]) {
//       const overrides = latestManualData[deviceId] || manualData;
//       data = {
//         ...data,
//         h2s: overrides.h2s,
//         ch4: overrides.ch4,
//         co:  overrides.co,
//         o2:  overrides.o2,
//         source: 'manual'
//       };
//     }
//   }

  

//   const mlData   = await askMLPipeline(data);
//   const evaluation = evaluateSafety(data, mlData);

//   const response = {
//     ...data,
//     status:      evaluation.status,
//     alerts:      evaluation.alerts,
//     exposure:    evaluation.exposure,
//     ml_insights: evaluation.ml_insights,
//     timestamp:   data.timestamp || Date.now(),
//   };

//   io.emit('sensor_update', response);
//   io.emit('sensor-data',   response);

//   memoryLogs.push(response);
//   if (memoryLogs.length > MAX_LOGS) memoryLogs.shift();
//   try { fs.appendFileSync('data.csv', JSON.stringify(response) + '\n'); } catch (_) {}

//   console.log(`[SOCKET EMIT] sensor_update device=${deviceId} status=${evaluation.status} clients=${io.engine.clientsCount}`);
//   res.json(response);
// });


app.post('/api/simulator', async (req, res) => {

  // 🚨 HARD BLOCK simulator when MANUAL mode
  if (mode === 'MANUAL') {
    return res.json({
      success: true,
      ignored: true,
      reason: 'Manual mode active'
    });
  }

  const deviceId = req.body.device_id;
  let data = { ...req.body, source: 'auto' };

  const mlData = await askMLPipeline(data);
  const evaluation = evaluateSafety(data, mlData);

  const response = {
    ...data,
    status: evaluation.status,
    alerts: evaluation.alerts,
    exposure: evaluation.exposure,
    ml_insights: evaluation.ml_insights,
    timestamp: data.timestamp || Date.now(),
    source: 'auto'
  };

  io.emit('sensor_update', response);

  res.json(response);
});
// Latest readings
app.get('/api/simulator/latest', (_req, res) => {
  res.json({ readings: memoryLogs.slice(-50), count: Math.min(memoryLogs.length, 50), timestamp: Date.now() });
});

// ── Global mode switch (REST) ─────────────────────────────────────────────────
app.post('/api/simulation/mode', (req, res) => {
  const { mode: newMode } = req.body;
  if (newMode === 'manual') {
    mode = 'MANUAL';
    console.log('[SIMULATION MODE] Switched to MANUAL — simulation paused');
  } else {
    mode = 'AUTO';
    console.log('[SIMULATION MODE] Switched to AUTO — simulation resumed');
  }
  io.emit('mode_changed', { mode });

  // 🚨 Immediately push manual values when switching
  if (mode === 'MANUAL') {
    io.emit('sensor_update', {
      ...manualData,
      source: 'manual',
      timestamp: Date.now()
    });
  }
  
  res.json({ success: true, mode });
});

// ── Manual override update (REST) ─────────────────────────────────────────────
app.post('/api/simulation/update', (req, res) => {
  const { h2s, ch4, co, o2 } = req.body;
  if (h2s !== undefined) manualData.h2s = h2s;
  if (ch4 !== undefined) manualData.ch4 = ch4;
  if (co  !== undefined) manualData.co  = co;
  if (o2  !== undefined) manualData.o2  = o2;

  const response = {
    device_id: 'MANUAL_OVERRIDE',
    ...manualData,
    source: 'manual',
    timestamp: Date.now()
  };

  // 🚨 Emit MULTIPLE TIMES to dominate UI
  for (let i = 0; i < 3; i++) {
    io.emit('sensor_update', response);
  }

  res.json({ success: true, manualData });

  // const synthData  = { device_id: 'SOLAPUR_PROBE_BOTTOM', ...manualData, timestamp: Date.now() };
  // const evaluation = evaluateSafety(synthData, null);
  // const response   = { ...synthData, status: evaluation.status, alerts: evaluation.alerts, exposure: evaluation.exposure };

  // io.emit('sensor_update', response);
  // io.emit('sensor-data',   response);
  // res.json({ success: true, manualData });
});

// ── Force status override ─────────────────────────────────────────────────────
app.post('/api/simulation/force-status', (req, res) => {
  const { status } = req.body;
  if (!['SAFE', 'CAUTION', 'BLOCK'].includes(status)) {
    return res.status(400).json({ error: 'Invalid status' });
  }
  globalOverrideState = status;
  const synthData = {
    device_id: 'SOLAPUR_PROBE_BOTTOM', ...manualData,
    status, alerts: status === 'BLOCK' ? ['SUPERVISOR OVERRIDE: BLOCK/EVACUATION IN EFFECT'] : [],
    timestamp: Date.now(),
  };
  io.emit('sensor_update', synthData);
  io.emit('sensor-data',   synthData);
  res.json({ success: true, globalOverrideState });
});

// ── Worker status ─────────────────────────────────────────────────────────────
app.get('/api/worker/status/:workerId', (req, res) => {
  const { workerId }   = req.params;
  const exposureScore  = exposureMap.get(workerId) || 0;
  const exposureLevel  = exposureScore > 20 ? 'HIGH' : exposureScore > 5 ? 'MEDIUM' : 'LOW';
  const session        = workerSessions.get(workerId) || {};
  let entryStatus      = 'ALLOWED';
  let safetyStatus     = 'SAFE';
  let alertMessage     = null;

  if (globalOverrideState === 'BLOCK') {
    entryStatus  = 'BLOCKED';
    safetyStatus = 'DANGER';
    alertMessage = 'SUPERVISOR OVERRIDE: Entry Blocked. Evacuate immediately.';
  } else if (exposureLevel === 'HIGH') {
    safetyStatus = 'DANGER';
    alertMessage = 'EXPOSURE LIMIT REACHED: Leave the area immediately.';
  } else if (exposureLevel === 'MEDIUM') {
    safetyStatus = 'CAUTION';
    alertMessage = 'Exposure level is rising. Monitor closely.';
  }

  res.json({
    workerId,
    manholeId:      session.manholeId    || 'MH-SOLAPUR-01',
    supervisorName: session.supervisorName || 'On-Duty Supervisor',
    sessionStatus:  session.scanStatus   || 'IDLE',
    sessionStart:   session.sessionStart || null,
    safetyStatus,
    exposureTime:   Math.round(exposureScore),
    exposureLevel,
    entryStatus,
    alertMessage,
    timestamp: Date.now(),
  });
});

// GET /api/sessions/worker/:workerId (alias)
app.get('/api/sessions/worker/:workerId', (req, res) => {
  req.params.workerId = req.params.workerId;
  const { workerId }  = req.params;
  const session       = workerSessions.get(workerId);
  const exposureScore = exposureMap.get(workerId) || 0;
  const exposureLevel = exposureScore > 20 ? 'HIGH' : exposureScore > 5 ? 'MEDIUM' : 'LOW';

  if (!session) {
    return res.json({
      workerId,
      sessionStatus: 'NO_SESSION',
      exposureTime:  Math.round(exposureScore),
      exposureLevel,
      safetyStatus:  globalOverrideState === 'BLOCK' ? 'DANGER' : 'SAFE',
      entryStatus:   globalOverrideState === 'BLOCK' ? 'BLOCKED' : 'ALLOWED',
      timestamp: Date.now(),
    });
  }

  res.json({
    workerId,
    manholeId:      session.manholeId    || 'MH-SOLAPUR-01',
    supervisorName: session.supervisorName || 'On-Duty Supervisor',
    sessionStatus:  session.scanStatus   || 'IDLE',
    sessionStart:   session.sessionStart || null,
    safetyStatus:   globalOverrideState === 'BLOCK' ?  'DANGER' : exposureLevel === 'HIGH' ? 'DANGER' : 'SAFE',
    exposureTime:   Math.round(exposureScore),
    exposureLevel,
    entryStatus:    globalOverrideState === 'BLOCK' ? 'BLOCKED' : 'ALLOWED',
    alertMessage:   globalOverrideState === 'BLOCK' ? 'SUPERVISOR OVERRIDE: Entry Blocked.' : null,
    timestamp: Date.now(),
  });
});

// ── Entry scan ────────────────────────────────────────────────────────────────
app.post('/api/worker/entry-scan', (req, res) => {
  const { workerId, manholeId } = req.body;
  if (!workerId) return res.status(400).json({ error: 'workerId required' });
  const existing = workerSessions.get(workerId) || {};
  workerSessions.set(workerId, {
    ...existing,
    manholeId:      manholeId || existing.manholeId || 'MH-SOLAPUR-01',
    scanStatus:     'SCANNING',
    sessionStart:   existing.sessionStart || new Date().toISOString(),
    supervisorName: existing.supervisorName || 'On-Duty Supervisor',
  });
  io.emit('worker-scan-request', { workerId, manholeId, timestamp: Date.now() });
  res.json({ success: true, scanStatus: 'SCANNING' });
});

// ── Worker panic ──────────────────────────────────────────────────────────────
app.post('/api/worker/panic', (req, res) => {
  const { workerId, manholeId } = req.body;
  if (!workerId) return res.status(400).json({ error: 'workerId required' });
  const panicEvent = {
    id:        `PANIC_${Date.now()}`,
    workerId,
    manholeId: manholeId || 'UNKNOWN',
    timestamp: new Date().toISOString(),
    type:      'PANIC_BUTTON',
    message:   `🚨 PANIC BUTTON: Worker ${workerId} needs IMMEDIATE HELP at ${manholeId || 'unknown location'}!`,
  };
  panicLog.push(panicEvent);
  globalOverrideState = 'BLOCK';
  io.emit('sensor-data', { device_id: workerId, worker_id: workerId, panic: true, status: 'BLOCK', alerts: [panicEvent.message], timestamp: Date.now() });
  io.emit('panic-alert', panicEvent);
  res.json({ success: true, panicId: panicEvent.id });
});

// ── Active workers ────────────────────────────────────────────────────────────
app.get('/api/workers/active', (_req, res) => {
  const active = [];
  for (const [workerId, session] of workerSessions.entries()) {
    const exposureScore = exposureMap.get(workerId) || 0;
    active.push({ workerId, ...session, exposureTime: Math.round(exposureScore), exposureLevel: exposureScore > 20 ? 'HIGH' : exposureScore > 5 ? 'MEDIUM' : 'LOW' });
  }
  res.json({ workers: active, count: active.length });
});

// ── Prediction engine ─────────────────────────────────────────────────────────
app.get('/api/worker/predict/:workerId', (req, res) => {
  const { workerId }  = req.params;
  const totalExposure = exposureMap.get(workerId) || 0;

  let prediction, color;
  if (totalExposure > 300)       { prediction = 'BLOCK';   color = 'RED';    }
  else if (totalExposure > 150)  { prediction = 'CAUTION'; color = 'ORANGE'; }
  else                           { prediction = 'SAFE';    color = 'GREEN';  }

  res.json({ workerId, prediction, color, totalExposure: Math.round(totalExposure), timestamp: Date.now() });
});

// ── Exposure history save ─────────────────────────────────────────────────────
app.post('/exposure/save', (req, res) => {
  const { workerId, manholeId, startTime, endTime, duration, avgGas, maxGas } = req.body;
  if (!workerId) return res.status(400).json({ error: 'workerId required' });

  const entry = { workerId, manholeId, startTime, endTime, duration, avgGas, maxGas, savedAt: new Date().toISOString() };
  exposureHistory.push(entry);
  if (exposureHistory.length > 1000) exposureHistory.shift(); // cap at 1000 records
  saveExposureHistory();

  res.json({ success: true, entry });
});

// GET /exposure/history/:workerId
app.get('/exposure/history/:workerId', (req, res) => {
  const { workerId } = req.params;
  const records = exposureHistory.filter((e) => e.workerId === workerId);
  res.json({ workerId, records, count: records.length });
});

// ── Session lifecycle ─────────────────────────────────────────────────────────
app.post('/session/start', (req, res) => {
  const { workerId, manholeId, supervisorId } = req.body;
  const sessionId = `SESSION_${Date.now()}_${workerId || 'W'}`;
  res.json({ success: true, sessionId, workerId, manholeId, supervisorId, timestamp: Date.now() });
});

// ── Manholes ──────────────────────────────────────────────────────────────────
app.get('/api/manholes', (_req, res) => res.json(manholesDB));
app.post('/api/manholes', (req, res) => {
  const { id, location } = req.body;
  if (!id || !location) return res.status(400).json({ error: 'Manhole ID and Location are required' });
  if (manholesDB.find((m) => m.id === id)) {
    return res.status(400).json({ error: `Manhole ID '${id}' already exists` });
  }
  const newMH = { id, location, status: 'SAFE' };
  manholesDB.push(newMH);
  res.json({ success: true, manhole: newMH });
});
app.delete('/api/manholes/:id', (req, res) => {
  manholesDB    = manholesDB.filter((m) => m.id !== req.params.id);
  assignmentsDB = assignmentsDB.filter((a) => a.zoneId !== req.params.id);
  res.json({ success: true });
});

// ── Assignments ───────────────────────────────────────────────────────────────
app.get('/api/assignments', (_req, res) => res.json(assignmentsDB));
app.post('/api/assignments', (req, res) => {
  const { supervisorId, workerId, zoneId } = req.body;
  if (supervisorId && zoneId) {
    assignmentsDB.push({ type: 'supervisor_zone', supervisorId, zoneId });
  } else if (workerId && supervisorId) {
    assignmentsDB.push({ type: 'worker_supervisor', workerId, supervisorId });
  } else {
    return res.status(400).json({ error: 'Invalid assignment parameters' });
  }
  res.json({ success: true });
});

// =============================================================================
//  SOCKET.IO — REAL-TIME EVENTS
// =============================================================================

io.on('connection', (socket) => {
  console.log(`[SOCKET] ✅ New client: ${socket.id} (total: ${io.engine.clientsCount})`);
  logger.info(`New client connected: ${socket.id}`);

  // Send current mode state immediately
  socket.emit('mode_changed', { mode, manualData });

  // Send latest cached readings immediately
  if (memoryLogs.length > 0) {
    const lastReadings = {};
    for (const log of memoryLogs) {
      if (log.device_id) lastReadings[log.device_id] = log;
    }
    for (const reading of Object.values(lastReadings)) {
      socket.emit('sensor_update', reading);
      socket.emit('sensor-data',   reading);
    }
  }

  // ── Join room ─────────────────────────────────────────────────────────────
  socket.on('join', ({ role, userId } = {}) => {
    if (role)   socket.join(role);
    if (userId) {
      socket.join(`user_${userId}`);
      userSockets.set(userId, socket.id);
    }
    console.log(`[SOCKET] ${socket.id} joined room=${role} userId=${userId}`);
  });

  // ── Worker identifies itself ──────────────────────────────────────────────
  socket.on('worker_identify', ({ workerId } = {}) => {
    if (!workerId) return;
    userSockets.set(workerId, socket.id);
    socket.join(`worker_${workerId}`);
    console.log(`[SOCKET] Worker identified: ${workerId} → ${socket.id}`);
  });

  // ── Supervisor identifies itself ──────────────────────────────────────────
  socket.on('supervisor_identify', ({ supervisorId } = {}) => {
    if (!supervisorId) return;
    userSockets.set(supervisorId, socket.id);
    socket.join(`supervisor_${supervisorId}`);
    socket.join('supervisor');
    console.log(`[SOCKET] Supervisor identified: ${supervisorId} → ${socket.id}`);
  });

  // =========================================================================
  //  ENTRY REQUEST FLOW (Worker → Supervisor → Worker)
  // =========================================================================

  // STEP 2: Worker sends entry request
  socket.on('entry_request', (data) => {
    const { sessionId, workerId, manholeId } = data || {};
    console.log(`[ENTRY REQUEST] session=${sessionId} worker=${workerId} manhole=${manholeId}`);

    // Store socket ID for later routing
    if (workerId) userSockets.set(workerId, socket.id);

    // Forward to ALL supervisor clients (or specific one if tracked)
    io.to('supervisor').emit('new_entry_request', {
      sessionId,
      workerId,
      manholeId,
      requestTime: Date.now(),
    });

    // Also broadcast to all (in case supervisor isn't in room)
    socket.broadcast.emit('new_entry_request', {
      sessionId, workerId, manholeId, requestTime: Date.now(),
    });

    socket.emit('entry_request_received', { sessionId, status: 'PENDING' });
  });

  // STEP 4a: Supervisor approves
  socket.on('approve_entry', (data) => {
    const { sessionId, workerId } = data || {};
    console.log(`[ENTRY APPROVE] session=${sessionId} worker=${workerId}`);

    globalOverrideState = null; // clear block

    // Emit directly to the specific worker socket
    const workerSocketId = workerId ? userSockets.get(workerId) : null;
    if (workerSocketId) {
      io.to(workerSocketId).emit('entry_approved', { sessionId, workerId, timestamp: Date.now() });
    }

    // Also broadcast widely so worker picks it up regardless
    io.emit('entry_status_update', { workerId: workerId || 'ALL', status: 'APPROVED', sessionId, timestamp: Date.now() });

    logger.info(`Supervisor APPROVED ENTRY for worker=${workerId}`);
  });

  // STEP 4b: Supervisor blocks
  socket.on('block_entry', (data) => {
    const { sessionId, workerId } = data || {};
    console.log(`[ENTRY BLOCK] session=${sessionId} worker=${workerId}`);

    globalOverrideState = 'BLOCK';

    const workerSocketId = workerId ? userSockets.get(workerId) : null;
    if (workerSocketId) {
      io.to(workerSocketId).emit('entry_blocked', { sessionId, workerId, timestamp: Date.now() });
    }

    io.emit('entry_status_update', { workerId: workerId || 'ALL', status: 'BLOCKED', sessionId, timestamp: Date.now() });

    logger.info(`Supervisor BLOCKED ENTRY for worker=${workerId}`);
  });

  // =========================================================================
  //  MANUAL SENSOR OVERRIDE
  // =========================================================================

  // ── Set MANUAL mode globally ──────────────────────────────────────────────
  socket.on('set_manual_mode', (data) => {
    mode = 'MANUAL';
    if (data) manualData = { h2s: data.h2s || 0, ch4: data.ch4 || 0, co: data.co || 0, o2: data.o2 !== undefined ? data.o2 : 20.9 };
    console.log(`[MODE] MANUAL activated with data: ${JSON.stringify(manualData)}`);

    const synthData  = { device_id: 'SOLAPUR_PROBE_BOTTOM', ...manualData, timestamp: Date.now() };
    const evaluation = evaluateSafety(synthData, null);
    const broadcast  = { ...synthData, status: evaluation.status, alerts: evaluation.alerts, exposure: evaluation.exposure };

    io.emit('sensor_update', broadcast);
    io.emit('sensor-data',   broadcast);
    io.emit('mode_changed',  { mode: 'MANUAL', manualData });
  });

  // ── Update live manual values ─────────────────────────────────────────────
  socket.on('update_manual_values', (data) => {
    if (mode !== 'MANUAL') return;
    if (data.h2s !== undefined) manualData.h2s = data.h2s;
    if (data.ch4 !== undefined) manualData.ch4 = data.ch4;
    if (data.co  !== undefined) manualData.co  = data.co;
    if (data.o2  !== undefined) manualData.o2  = data.o2;

    const synthData  = { device_id: 'SOLAPUR_PROBE_BOTTOM', ...manualData, timestamp: Date.now() };
    const evaluation = evaluateSafety(synthData, null);
    const broadcast  = { ...synthData, status: evaluation.status, alerts: evaluation.alerts, exposure: evaluation.exposure };

    io.emit('sensor_update', broadcast);
    io.emit('sensor-data',   broadcast);
    console.log(`[MANUAL UPDATE] h2s=${manualData.h2s} ch4=${manualData.ch4} co=${manualData.co} o2=${manualData.o2} status=${evaluation.status}`);
  });

  // ── Switch back to AUTO ───────────────────────────────────────────────────
  socket.on('set_auto_mode', () => {
    mode       = 'AUTO';
    manualData = { h2s: 0, ch4: 0, co: 0, o2: 20.9 };
    console.log('[MODE] AUTO — simulation resumed');
    io.emit('mode_changed', { mode: 'AUTO', manualData: null });
  });

  // ── Per-device manual sensor update (legacy supervisor slider) ────────────
  socket.on('manual_sensor_update', async (data) => {
    const { deviceId, h2s, ch4, co, o2 } = data || {};
    if (!deviceId) return;

    // Also set global mode to MANUAL
    mode = 'MANUAL';
    manualOverride[deviceId]   = true;
    latestManualData[deviceId] = { h2s: h2s || 0, ch4: ch4 || 0, co: co || 0, o2: o2 || 20.9, timestamp: Date.now() };

    // Update global manualData as well
    manualData = { h2s: h2s || 0, ch4: ch4 || 0, co: co || 0, o2: o2 !== undefined ? o2 : 20.9 };

    const synthData  = { device_id: deviceId, h2s: h2s || 0, ch4: ch4 || 0, co: co || 0, o2: o2 || 20.9, timestamp: Date.now() };
    const evaluation = evaluateSafety(synthData, null);
    const broadcast  = { ...synthData, status: evaluation.status, alerts: evaluation.alerts, exposure: evaluation.exposure };

    io.emit('sensor_update', broadcast);
    io.emit('sensor-data',   broadcast);
    io.emit('mode_changed',  { mode: 'MANUAL', manualData });
    console.log(`[MANUAL SENSOR] device=${deviceId} status=${evaluation.status}`);
  });

  // ── Per-device mode change (legacy) ──────────────────────────────────────
  socket.on('mode_change', ({ deviceId, mode: newMode } = {}) => {
    if (!deviceId) return;
    if (newMode === 'MANUAL') {
      manualOverride[deviceId] = true;
      mode = 'MANUAL';
      console.log(`[MODE] Device ${deviceId} → MANUAL (global mode also set to MANUAL)`);
    } else {
      manualOverride[deviceId] = false;
      delete latestManualData[deviceId];
      // Only switch global back to AUTO if no other device is in manual
      const anyManual = Object.values(manualOverride).some((v) => v);
      if (!anyManual) {
        mode = 'AUTO';
        console.log('[MODE] All devices → AUTO, global mode restored');
      }
    }
    io.emit('mode_changed', { mode, deviceId });
  });

  // ── Emergency evacuation ──────────────────────────────────────────────────
  socket.on('manual_evacuate', ({ reason } = {}) => {
    logger.info(`CRITICAL: Supervisor triggered MANUAL EVACUATION. Reason: ${reason}`);
    globalOverrideState = 'BLOCK';
    const payload = { status: 'BLOCK', alerts: ['🚨 SUPERVISOR EMERGENCY: EVACUATE IMMEDIATELY'], device_id: 'SYSTEM', timestamp: Date.now() };
    io.emit('evacuation_order', { reason });
    io.emit('sensor_update',    payload);
    io.emit('sensor-data',      payload);
  });

  // ── Worker assignment ─────────────────────────────────────────────────────
  socket.on('assign_worker', ({ workerId } = {}) => {
    for (const key of Object.keys(workerActiveStatus)) workerActiveStatus[key] = 'INACTIVE';
    if (workerId) workerActiveStatus[workerId] = 'ACTIVE';
    io.emit('worker_assignment_update', { activeWorkerId: workerId, timestamp: Date.now() });
    console.log(`[WORKER ASSIGN] Active worker: ${workerId}`);
  });

  // ── Alert acknowledge ─────────────────────────────────────────────────────
  socket.on('alert-acknowledge', ({ alertId } = {}) => {
    io.to('supervisor').emit('alert-updated', { alertId, acknowledged: true });
  });

  // ── Disconnect ────────────────────────────────────────────────────────────
  socket.on('disconnect', (reason) => {
    console.log(`[SOCKET] ❌ Client disconnected: ${socket.id} reason=${reason}`);
    // Clean up userSockets map
    for (const [uid, sid] of userSockets.entries()) {
      if (sid === socket.id) userSockets.delete(uid);
    }
    logger.info(`Client disconnected: ${socket.id}`);
  });

  socket.on('error', (err) => console.error(`[SOCKET] Error on ${socket.id}:`, err));
});

// =============================================================================
//  ERROR HANDLING
// =============================================================================

app.use((err, _req, res, _next) => {
  logger.error(err.stack);
  res.status(500).json({ error: 'Internal Server Error', message: process.env.NODE_ENV === 'development' ? err.message : undefined });
});

app.use((_req, res) => res.status(404).json({ error: 'Route not found' }));

// =============================================================================
//  START SERVER
// =============================================================================

const PORT = process.env.PORT || 3000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`\n🚀 Solapur Safety System backend running on http://0.0.0.0:${PORT}`);
  console.log(`📡 Socket.IO ready | Mode: ${mode}`);
});

process.on('SIGTERM', () => {
  logger.info('SIGTERM received — shutting down gracefully');
  server.close(() => {
    try { db.end(); } catch (_) {}
    logger.info('Server closed');
    process.exit(0);
  });
});

module.exports = app;