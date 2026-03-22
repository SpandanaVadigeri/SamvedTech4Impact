#!/usr/bin/env python3
"""
Test Case: Offline Buffering and Sync
Tests that data is properly stored locally when offline and synced when connection restored
"""

import unittest
import time
import random
import json
import sqlite3
import os
import tempfile
import shutil
import threading
from pathlib import Path
from datetime import datetime, timedelta

class TestOfflineBuffering(unittest.TestCase):
    """Test suite for offline data buffering and synchronization"""
    
    @classmethod
    def setUpClass(cls):
        """Set up test environment"""
        print("\n🔧 Setting up Offline Buffering Tests...")
        cls.test_dir = tempfile.mkdtemp()
        cls.db_path = os.path.join(cls.test_dir, 'test_safety.db')
        
    def setUp(self):
        """Set up each test with fresh database"""
        self.conn = sqlite3.connect(self.db_path)
        self.cursor = self.conn.cursor()
        self.create_tables()
        self.synced_data = []
        self.buffered_data = []
        
    def create_tables(self):
        """Create test database tables (matching Flutter app schema)"""
        self.cursor.execute('''
            CREATE TABLE IF NOT EXISTS gas_readings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                h2s REAL,
                ch4 REAL,
                co REAL,
                o2 REAL,
                device_id TEXT,
                worker_id TEXT,
                synced INTEGER DEFAULT 0
            )
        ''')
        
        self.cursor.execute('''
            CREATE TABLE IF NOT EXISTS worker_vitals (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                worker_id TEXT,
                heart_rate INTEGER,
                fall_detected INTEGER,
                panic_pressed INTEGER,
                synced INTEGER DEFAULT 0
            )
        ''')
        
        self.cursor.execute('''
            CREATE TABLE IF NOT EXISTS sync_queue (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                table_name TEXT NOT NULL,
                record_id INTEGER NOT NULL,
                operation TEXT NOT NULL,
                data TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                synced INTEGER DEFAULT 0
            )
        ''')
        
        self.conn.commit()
    
    def tearDown(self):
        """Clean up after each test"""
        self.conn.close()
    
    @classmethod
    def tearDownClass(cls):
        """Remove test directory"""
        shutil.rmtree(cls.test_dir)
    
    def insert_gas_reading(self, readings, synced=0):
        """Insert a gas reading into local database"""
        timestamp = datetime.now().isoformat()
        self.cursor.execute('''
            INSERT INTO gas_readings 
            (timestamp, h2s, ch4, co, o2, device_id, worker_id, synced)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            timestamp,
            readings.get('h2s', 0),
            readings.get('ch4', 0),
            readings.get('co', 0),
            readings.get('o2', 20.9),
            readings.get('device_id', 'TEST_001'),
            readings.get('worker_id', 'W001'),
            synced
        ))
        self.conn.commit()
        return self.cursor.lastrowid
    
    def insert_worker_vital(self, vital, synced=0):
        """Insert worker vital into local database"""
        timestamp = datetime.now().isoformat()
        self.cursor.execute('''
            INSERT INTO worker_vitals 
            (timestamp, worker_id, heart_rate, fall_detected, panic_pressed, synced)
            VALUES (?, ?, ?, ?, ?, ?)
        ''', (
            timestamp,
            vital.get('worker_id', 'W001'),
            vital.get('heart_rate', 70),
            1 if vital.get('fall_detected', False) else 0,
            1 if vital.get('panic_pressed', False) else 0,
            synced
        ))
        self.conn.commit()
        return self.cursor.lastrowid
    
    def add_to_sync_queue(self, table, record_id, operation, data):
        """Add an item to sync queue"""
        self.cursor.execute('''
            INSERT INTO sync_queue (table_name, record_id, operation, data, timestamp, synced)
            VALUES (?, ?, ?, ?, ?, 0)
        ''', (table, record_id, operation, json.dumps(data), datetime.now().isoformat()))
        self.conn.commit()
    
    def get_pending_sync_count(self):
        """Get number of items waiting to sync"""
        self.cursor.execute('SELECT COUNT(*) FROM sync_queue WHERE synced = 0')
        return self.cursor.fetchone()[0]
    
    def get_unsynced_readings_count(self):
        """Get number of unsynced gas readings"""
        self.cursor.execute('SELECT COUNT(*) FROM gas_readings WHERE synced = 0')
        return self.cursor.fetchone()[0]
    
    def simulate_network_outage(self, duration_ms=5000):
        """Simulate network outage for given duration"""
        print(f"   🌐 Network outage for {duration_ms/1000}s")
        time.sleep(duration_ms / 1000)
    
    def simulate_sync(self):
        """Simulate syncing data to cloud"""
        # Get unsynced readings
        self.cursor.execute('SELECT * FROM gas_readings WHERE synced = 0')
        readings = self.cursor.fetchall()
        
        # Mark as synced
        for reading in readings:
            self.cursor.execute('UPDATE gas_readings SET synced = 1 WHERE id = ?', (reading[0],))
            self.synced_data.append(reading)
        
        # Get unsynced vitals
        self.cursor.execute('SELECT * FROM worker_vitals WHERE synced = 0')
        vitals = self.cursor.fetchall()
        
        # Mark as synced
        for vital in vitals:
            self.cursor.execute('UPDATE worker_vitals SET synced = 1 WHERE id = ?', (vital[0],))
            self.synced_data.append(vital)
        
        # Process sync queue
        self.cursor.execute('SELECT * FROM sync_queue WHERE synced = 0')
        queue_items = self.cursor.fetchall()
        
        for item in queue_items:
            self.cursor.execute('UPDATE sync_queue SET synced = 1 WHERE id = ?', (item[0],))
        
        self.conn.commit()
        
        return len(readings) + len(vitals) + len(queue_items)
    
    def test_offline_data_storage(self):
        """Test that data is stored locally when offline"""
        print("\n📊 Testing offline data storage...")
        
        # Simulate offline operation
        readings_count = 50
        
        for i in range(readings_count):
            # Insert gas reading
            reading = {
                'h2s': random.uniform(0, 15),
                'ch4': random.uniform(0, 3),
                'co': random.uniform(0, 40),
                'o2': random.uniform(18, 21),
                'device_id': f'HELMET_{i%3+1:03d}',
                'worker_id': f'W{i%2+1:03d}'
            }
            self.insert_gas_reading(reading, synced=0)
            
            # Insert worker vital every 5 readings
            if i % 5 == 0:
                vital = {
                    'worker_id': f'W{i%2+1:03d}',
                    'heart_rate': random.randint(60, 100),
                    'fall_detected': random.random() < 0.05,
                    'panic_pressed': random.random() < 0.02
                }
                self.insert_worker_vital(vital, synced=0)
        
        # Verify data was stored
        unsynced_readings = self.get_unsynced_readings_count()
        self.assertEqual(unsynced_readings, readings_count + readings_count//5,
                        f"Expected {readings_count + readings_count//5} unsynced records, got {unsynced_readings}")
        
        print(f"   ✅ Stored {unsynced_readings} records while offline")
    
    def test_sync_after_reconnect(self):
        """Test that data syncs when connection is restored"""
        print("\n📊 Testing sync after reconnect...")
        
        # Store offline data
        for i in range(30):
            reading = {
                'h2s': random.uniform(0, 15),
                'device_id': 'HELMET_001'
            }
            self.insert_gas_reading(reading, synced=0)
        
        # Verify data is unsynced
        unsynced_before = self.get_unsynced_readings_count()
        self.assertGreater(unsynced_before, 0, "Should have unsynced data")
        
        # Simulate connection restored and sync
        synced_count = self.simulate_sync()
        
        # Verify data is now synced
        unsynced_after = self.get_unsynced_readings_count()
        self.assertEqual(unsynced_after, 0, "All data should be synced")
        self.assertEqual(synced_count, unsynced_before, 
                        f"Synced {synced_count} records, expected {unsynced_before}")
        
        print(f"   ✅ Synced {synced_count} records after reconnection")
    
    def test_priority_sync(self):
        """Test that critical alerts sync first"""
        print("\n📊 Testing priority sync...")
        
        # Add normal readings
        for i in range(20):
            reading = {
                'h2s': random.uniform(1, 4),
                'device_id': 'HELMET_001'
            }
            rid = self.insert_gas_reading(reading, synced=0)
            self.add_to_sync_queue('gas_readings', rid, 'INSERT', reading)
        
        # Add critical alert
        critical_reading = {
            'h2s': 15.0,  # Above BLOCK threshold
            'device_id': 'HELMET_001'
        }
        rid = self.insert_gas_reading(critical_reading, synced=0)
        self.add_to_sync_queue('gas_readings', rid, 'INSERT', critical_reading)
        
        # Add panic alert
        panic_vital = {
            'worker_id': 'W001',
            'panic_pressed': True
        }
        vid = self.insert_worker_vital(panic_vital, synced=0)
        self.add_to_sync_queue('worker_vitals', vid, 'INSERT', panic_vital)
        
        # Get queue items ordered by priority
        self.cursor.execute('''
            SELECT * FROM sync_queue 
            WHERE synced = 0 
            ORDER BY 
                CASE 
                    WHEN json_extract(data, '$.h2s') > 10 THEN 1
                    WHEN json_extract(data, '$.panic_pressed') = 1 THEN 1
                    ELSE 2
                END,
                timestamp ASC
        ''')
        
        queue = self.cursor.fetchall()
        
        # First item should be critical or panic
        first_item = json.loads(queue[0][4])
        self.assertTrue(
            first_item.get('h2s', 0) > 10 or first_item.get('panic_pressed', False),
            "Critical alerts should be first in sync queue"
        )
        
        print(f"   ✅ Priority ordering verified - critical alerts first")
    
    def test_offline_with_multiple_workers(self):
        """Test offline buffering with multiple concurrent workers"""
        print("\n📊 Testing offline buffering with multiple workers...")
        
        import threading
        import queue
        
        def worker_thread(worker_id, result_queue):
            """Simulate a worker generating data offline"""
            local_buffer = []
            for i in range(20):  # 20 readings per worker
                reading = {
                    'h2s': random.uniform(0, 15),
                    'worker_id': worker_id,
                    'device_id': f'HELMET_{worker_id}'
                }
                rid = self.insert_gas_reading(reading, synced=0)
                local_buffer.append(rid)
                time.sleep(0.01)  # Simulate reading interval
            result_queue.put(len(local_buffer))
        
        # Test with 5 concurrent workers
        num_workers = 5
        result_queue = queue.Queue()
        threads = []
        
        for i in range(num_workers):
            t = threading.Thread(target=worker_thread, args=(f'W{i+1:03d}', result_queue))
            threads.append(t)
            t.start()
        
        for t in threads:
            t.join()
        
        # Calculate total records
        total_records = 0
        while not result_queue.empty():
            total_records += result_queue.get()
        
        # Verify all data was stored
        unsynced = self.get_unsynced_readings_count()
        self.assertEqual(unsynced, total_records,
                        f"Expected {total_records} unsynced records, got {unsynced}")
        
        print(f"   ✅ Stored {unsynced} records from {num_workers} concurrent workers")
    
    def test_data_integrity_after_offline(self):
        """Test that data integrity is maintained after offline period"""
        print("\n📊 Testing data integrity after offline period...")
        
        # Store original data
        original_data = []
        for i in range(100):
            reading = {
                'h2s': round(random.uniform(0, 15), 2),
                'ch4': round(random.uniform(0, 3), 2),
                'co': round(random.uniform(0, 40), 1),
                'o2': round(random.uniform(18, 21), 1),
                'timestamp': datetime.now().isoformat()
            }
            rid = self.insert_gas_reading(reading, synced=0)
            original_data.append((rid, reading))
        
        # Simulate sync
        synced_count = self.simulate_sync()
        
        # Verify synced data matches original
        self.assertEqual(len(self.synced_data), len(original_data),
                        "Synced data count should match original")
        
        # Check a few random records for integrity
        import random as rnd
        for _ in range(10):
            idx = rnd.randint(0, len(original_data)-1)
            rid, original = original_data[idx]
            
            # Find in synced data
            synced = next((s for s in self.synced_data if s[0] == rid), None)
            self.assertIsNotNone(synced, f"Record {rid} missing from synced data")
            
            # Compare values (approximate due to floating point)
            self.assertAlmostEqual(synced[2], original['h2s'], places=1,msg=f"H2S value mismatch for record {rid}")
                                 
        
        print(f"   ✅ Data integrity maintained for {synced_count} records")
    
    def test_sync_queue_persistence(self):
        """Test that sync queue persists across app restarts"""
        print("\n📊 Testing sync queue persistence...")
        
        # Add items to queue
        for i in range(25):
            reading = {'h2s': random.uniform(0, 15)}
            rid = self.insert_gas_reading(reading, synced=0)
            self.add_to_sync_queue('gas_readings', rid, 'INSERT', reading)
        
        # Get queue count
        queue_before = self.get_pending_sync_count()
        self.assertGreater(queue_before, 0, "Queue should have items")
        
        # Simulate app restart (close and reopen connection)
        self.conn.close()
        self.conn = sqlite3.connect(self.db_path)
        self.cursor = self.conn.cursor()
        
        # Verify queue still exists
        queue_after = self.get_pending_sync_count()
        self.assertEqual(queue_before, queue_after,
                        "Sync queue should persist after app restart")
        
        print(f"   ✅ Sync queue persisted with {queue_after} items")
    
    def test_offline_exposure_tracking(self):
        """Test that exposure is tracked correctly while offline"""
        print("\n📊 Testing offline exposure tracking...")
        
        # Simulate 1 hour of offline operation with varying H2S levels
        exposure_total = 0
        readings_count = 3600  # 1 hour at 1-second intervals
        
        for i in range(readings_count):
            h2s = random.uniform(0, 12)
            reading = {
                'h2s': h2s,
                'timestamp': (datetime.now() - timedelta(seconds=readings_count-i)).isoformat()
            }
            self.insert_gas_reading(reading, synced=0)
            
            # Calculate exposure (ppm * minutes)
            exposure_total += h2s / 60.0  # Convert to ppm-minutes
        
        # Verify exposure data is stored
        self.cursor.execute('SELECT COUNT(*) FROM gas_readings')
        count = self.cursor.fetchone()[0]
        self.assertEqual(count, readings_count, "All exposure readings should be stored")
        
        print(f"   ✅ Stored {readings_count} exposure readings offline")
        print(f"   📊 Total exposure: {exposure_total:.2f} ppm-minutes")
    
    def test_conflict_resolution(self):
        """Test conflict resolution when same data exists on server"""
        print("\n📊 Testing conflict resolution...")
        
        # Simulate data that exists both locally and on server
        reading = {
            'h2s': 5.5,
            'timestamp': datetime.now().isoformat(),
            'device_id': 'HELMET_001'
        }
        
        # Insert locally
        local_id = self.insert_gas_reading(reading, synced=0)
        
        # Simulate server having newer data
        server_reading = reading.copy()
        server_reading['h2s'] = 6.2  # Updated value
        server_reading['timestamp'] = (datetime.now() + timedelta(seconds=10)).isoformat()
        
        # Conflict resolution: server wins if newer
        local_time = datetime.fromisoformat(reading['timestamp'])
        server_time = datetime.fromisoformat(server_reading['timestamp'])
        
        if server_time > local_time:
            # Update local with server data
            self.cursor.execute('''
                UPDATE gas_readings 
                SET h2s = ?, timestamp = ?
                WHERE id = ?
            ''', (server_reading['h2s'], server_reading['timestamp'], local_id))
            self.conn.commit()
        
        # Verify resolution
        self.cursor.execute('SELECT h2s FROM gas_readings WHERE id = ?', (local_id,))
        resolved_h2s = self.cursor.fetchone()[0]
        self.assertEqual(resolved_h2s, server_reading['h2s'],
                        "Should resolve to server data (newer timestamp)")
        
        print(f"   ✅ Conflict resolution successful - newer data preserved")

if __name__ == '__main__':
    unittest.main()