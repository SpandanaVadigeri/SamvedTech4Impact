const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const fs = require('fs');
const path = require('path');
const { v4: uuidv4 } = require('uuid');
const router = express.Router();

const DB_PATH = path.join(__dirname, '../database.json');
const JWT_SECRET = process.env.JWT_SECRET || 'super_secret_jwt_key_scssas';

// Helper to read DB
const readDB = () => {
    if (!fs.existsSync(DB_PATH)) {
        return { users: [] };
    }
    const data = fs.readFileSync(DB_PATH, 'utf8');
    try {
        return JSON.parse(data);
    } catch {
        return { users: [] };
    }
}

// Helper to write DB
const writeDB = (data) => {
    fs.writeFileSync(DB_PATH, JSON.stringify(data, null, 2));
}

// Middleware: Verify Token
const verifyToken = (req, res, next) => {
    const header = req.headers['authorization'];
    if (!header) return res.status(401).json({ error: "Access Denied: No Token" });
    
    const token = header.split(' ')[1];
    if (!token) return res.status(401).json({ error: "Access Denied: Invalid Token" });
    
    try {
        const verified = jwt.verify(token, JWT_SECRET);
        req.user = verified;
        next();
    } catch (err) {
        res.status(400).json({ error: "Invalid Token" });
    }
};

// Middleware: Check Admin Role
const checkAdmin = (req, res, next) => {
    if (req.user && req.user.role === 'admin') {
        next();
    } else {
        res.status(403).json({ error: "Access Denied: Admins Only" });
    }
};

// ==================== LOGIN ====================
router.post('/login', async (req, res) => {
    try {
        const { username, password } = req.body;
        if (!username || !password) return res.status(400).json({ error: "Missing required fields" });
        
        const db = readDB();
        const user = db.users.find(u => u.username === username);
        
        if (!user) return res.status(401).json({ error: "Invalid credentials" });
        
        const validPass = await bcrypt.compare(password, user.password_hash);
        if (!validPass) return res.status(401).json({ error: "Invalid credentials" });
        
        // Generate Token
        const token = jwt.sign(
            { id: user.id, username: user.username, role: user.role }, 
            JWT_SECRET, 
            { expiresIn: '24h' }
        );
        
        res.json({ token, role: user.role, user_id: user.id });
    } catch (err) {
        res.status(500).json({ error: "Internal Server Error" });
    }
});

// ==================== REGISTER (ADMIN ONLY) ====================
router.post('/register', verifyToken, checkAdmin, async (req, res) => {
    try {
        const { username, password, role } = req.body;
        if (!username || !password || !role) return res.status(400).json({ error: "Missing required fields" });
        
        if (!['worker', 'supervisor'].includes(role)) {
            return res.status(400).json({ error: "Invalid role specified. Only worker and supervisor are allowed." });
        }
        
        const db = readDB();
        if (db.users.find(u => u.username === username)) {
            return res.status(400).json({ error: "Username already exists" });
        }
        
        const salt = await bcrypt.genSalt(10);
        const password_hash = await bcrypt.hash(password, salt);
        
        const newUser = {
            id: uuidv4(),
            username,
            password_hash,
            role,
            created_at: new Date().toISOString()
        };
        
        db.users.push(newUser);
        writeDB(db);
        
        res.status(201).json({ message: "User created successfully", user_id: newUser.id });
    } catch (err) {
        res.status(500).json({ error: "Internal Server Error" });
    }
});

// ==================== LIST USERS (ADMIN ONLY) ====================
router.get('/users', verifyToken, checkAdmin, (req, res) => {
    try {
        const db = readDB();
        const users = db.users.map(u => ({
            id: u.id,
            username: u.username,
            role: u.role,
            created_at: u.created_at
        }));
        res.json(users);
    } catch (err) {
        res.status(500).json({ error: "Internal Server Error" });
    }
});

module.exports = router;