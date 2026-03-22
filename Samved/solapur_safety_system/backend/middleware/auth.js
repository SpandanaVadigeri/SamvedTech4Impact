/**
 * Authentication middleware
 * JWT token validation and role-based access control
 */

const jwt = require('jsonwebtoken');
const db = require('../database/db');

// JWT secret from environment
const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key-change-in-production';
const JWT_EXPIRY = process.env.JWT_EXPIRY || '24h';

// Generate JWT token
const generateToken = (user) => {
  return jwt.sign(
    {
      id: user.id,
      username: user.username,
      role: user.role,
      worker_id: user.worker_id
    },
    JWT_SECRET,
    { expiresIn: JWT_EXPIRY }
  );
};

// Verify JWT token middleware
const authenticateToken = async (req, res, next) => {
  try {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1]; // Bearer TOKEN

    if (!token) {
      return res.status(401).json({ 
        error: 'Authentication required',
        message: 'No token provided'
      });
    }

    // Verify token
    const decoded = jwt.verify(token, JWT_SECRET);
    
    // Check if user still exists in database
    const user = await db.query(
      'SELECT id, username, role, worker_id, full_name, is_active FROM users WHERE id = $1',
      [decoded.id]
    );

    if (user.rows.length === 0 || !user.rows[0].is_active) {
      return res.status(401).json({ 
        error: 'Authentication failed',
        message: 'User not found or inactive'
      });
    }

    // Attach user to request
    req.user = user.rows[0];
    next();

  } catch (error) {
    if (error.name === 'TokenExpiredError') {
      return res.status(401).json({ 
        error: 'Token expired',
        message: 'Please login again'
      });
    }
    
    if (error.name === 'JsonWebTokenError') {
      return res.status(401).json({ 
        error: 'Invalid token',
        message: 'Authentication failed'
      });
    }

    req.logger.error('Auth middleware error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
};

// Role-based access control
const authorize = (...allowedRoles) => {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({ error: 'Authentication required' });
    }

    if (!allowedRoles.includes(req.user.role)) {
      return res.status(403).json({ 
        error: 'Access denied',
        message: `Required roles: ${allowedRoles.join(', ')}`
      });
    }

    next();
  };
};

// Check if user is accessing their own data
const authorizeSelf = (paramName = 'userId') => {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({ error: 'Authentication required' });
    }

    const targetUserId = req.params[paramName];
    
    // Admin can access any data
    if (req.user.role === 'admin' || req.user.role === 'control') {
      return next();
    }

    // Users can only access their own data
    if (req.user.id === targetUserId) {
      return next();
    }

    // Supervisors can access worker data in their sessions
    if (req.user.role === 'supervisor') {
      // Check if worker is in supervisor's session
      // This would require additional database query
      return next(); // Simplified for demo
    }

    return res.status(403).json({ error: 'Access denied' });
  };
};

// Session validation middleware
const validateSession = async (req, res, next) => {
  try {
    const sessionId = req.params.sessionId || req.body.session_id;

    if (!sessionId) {
      return next(); // No session to validate
    }

    const session = await db.query(
      `SELECT * FROM sessions WHERE session_id = $1 AND status = 'active'`,
      [sessionId]
    );

    if (session.rows.length === 0) {
      return res.status(404).json({ error: 'Session not found or inactive' });
    }

    req.session = session.rows[0];
    next();

  } catch (error) {
    req.logger.error('Session validation error:', error);
    res.status(500).json({ error: 'Failed to validate session' });
  }
};

// Device authentication middleware
const authenticateDevice = async (req, res, next) => {
  try {
    const deviceId = req.headers['x-device-id'];
    const deviceToken = req.headers['x-device-token'];

    if (!deviceId || !deviceToken) {
      return res.status(401).json({ error: 'Device credentials required' });
    }

    // Verify device
    const device = await db.query(
      'SELECT * FROM devices WHERE device_id = $1 AND is_active = true',
      [deviceId]
    );

    if (device.rows.length === 0) {
      return res.status(401).json({ error: 'Device not registered' });
    }

    // Verify token (simplified - in production use proper device auth)
    if (deviceToken !== `dev_${deviceId}_token`) {
      return res.status(401).json({ error: 'Invalid device token' });
    }

    req.device = device.rows[0];
    next();

  } catch (error) {
    req.logger.error('Device auth error:', error);
    res.status(500).json({ error: 'Device authentication failed' });
  }
};

// Rate limiting by user role
const getRateLimitForRole = (role) => {
  const limits = {
    worker: 100,
    supervisor: 200,
    control: 500,
    admin: 1000
  };
  return limits[role] || 100;
};

// Log user activity
const logActivity = (action) => {
  return async (req, res, next) => {
    const originalJson = res.json;
    
    res.json = function(data) {
      // Log after response is sent
      setImmediate(async () => {
        try {
          await db.query(
            `INSERT INTO audit_log (user_id, action, entity_type, entity_id, ip_address, user_agent)
             VALUES ($1, $2, $3, $4, $5, $6)`,
            [
              req.user?.id,
              action,
              req.params.entityType || 'unknown',
              req.params.id || data?.id,
              req.ip,
              req.get('user-agent')
            ]
          );
        } catch (error) {
          req.logger.error('Failed to log activity:', error);
        }
      });

      originalJson.call(this, data);
    };

    next();
  };
};

module.exports = {
  generateToken,
  authenticateToken,
  authorize,
  authorizeSelf,
  validateSession,
  authenticateDevice,
  getRateLimitForRole,
  logActivity,
  JWT_SECRET
};