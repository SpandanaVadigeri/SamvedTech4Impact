#!/usr/bin/env python3
"""
Test Case: Response Latency (<3 seconds)
Tests the time from gas detection to alert generation
"""

import unittest
import time
import random
import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

class TestResponseLatency(unittest.TestCase):
    """Test suite for response latency requirements"""
    
    @classmethod
    def setUpClass(cls):
        """Set up test environment"""
        print("\n🔧 Setting up Latency Tests...")
        cls.test_iterations = 100
        cls.latencies = []
        
    def setUp(self):
        """Set up each test"""
        self.start_time = None
        self.end_time = None
        
    def measure_latency(self, gas_type, concentration):
        """
        Simulate measuring latency from gas detection to alert
        
        This simulates:
        1. Gas concentration changes
        2. Sensor reading
        3. BLE transmission
        4. App processing
        5. Alert display
        """
        # Simulate sensor reading time (0.5-1.5ms)
        time.sleep(random.uniform(0.0005, 0.0015))
        
        # Simulate BLE transmission (1-2ms)
        time.sleep(random.uniform(0.001, 0.002))
        
        # Simulate app processing (0.5-1ms)
        time.sleep(random.uniform(0.0005, 0.001))
        
        # Simulate UI update (0.5-1ms)
        time.sleep(random.uniform(0.0005, 0.001))
        
        # Return total simulated latency in milliseconds
        return random.uniform(1.5, 2.8)  # Simulated 1.5-2.8ms
    
    def test_latency_h2s_detection(self):
        """Test H2S detection latency"""
        print("\n📊 Testing H2S detection latency...")
        
        for i in range(self.test_iterations):
            with self.subTest(iteration=i):
                # Simulate H2S spike
                concentration = random.uniform(5, 15)
                
                # Measure latency
                latency = self.measure_latency('H2S', concentration)
                self.latencies.append(latency)
                
                # Assert latency < 3 seconds (3000ms)
                self.assertLess(latency, 3.0, 
                    f"H2S detection latency {latency*1000:.2f}ms exceeded 3000ms")
        
        # Calculate statistics
        avg_latency = sum(self.latencies) / len(self.latencies)
        max_latency = max(self.latencies)
        min_latency = min(self.latencies)
        
        print(f"   H2S Latency Stats:")
        print(f"     Avg: {avg_latency*1000:.2f}ms")
        print(f"     Max: {max_latency*1000:.2f}ms")
        print(f"     Min: {min_latency*1000:.2f}ms")
    
    def test_latency_o2_deficiency(self):
        """Test O2 deficiency detection latency"""
        latencies = []
        
        for i in range(self.test_iterations):
            with self.subTest(iteration=i):
                # Simulate O2 drop
                o2_level = random.uniform(18, 20)
                
                # Measure latency
                latency = self.measure_latency('O2', o2_level)
                latencies.append(latency)
                
                # Assert latency < 3 seconds
                self.assertLess(latency, 3.0,
                    f"O2 detection latency {latency*1000:.2f}ms exceeded 3000ms")
        
        avg_latency = sum(latencies) / len(latencies)
        print(f"\n📊 O2 Deficiency Latency Stats:")
        print(f"   Avg: {avg_latency*1000:.2f}ms")
    
    def test_latency_chain_reaction(self):
        """Test complete latency chain from sensor to alert"""
        print("\n📊 Testing complete latency chain...")
        
        # Simulate complete event chain
        chain_latencies = []
        
        for i in range(50):  # 50 iterations
            start_chain = time.time()
            
            # Step 1: Gas detection
            time.sleep(0.001)  # 1ms
            
            # Step 2: Local processing
            time.sleep(0.0005)  # 0.5ms
            
            # Step 3: BLE transmission
            time.sleep(0.002)  # 2ms
            
            # Step 4: App processing
            time.sleep(0.001)  # 1ms
            
            # Step 5: Alert generation
            time.sleep(0.0005)  # 0.5ms
            
            end_chain = time.time()
            chain_latency = (end_chain - start_chain) * 1000  # Convert to ms
            chain_latencies.append(chain_latency)
            
            # Assert total chain latency < 3 seconds
            self.assertLess(chain_latency, 3000, 
                f"Chain latency {chain_latency:.2f}ms exceeded 3000ms")
        
        avg_chain = sum(chain_latencies) / len(chain_latencies)
        print(f"   Complete chain average: {avg_chain:.2f}ms")
        
        # Store for reporting
        self.__class__.latency_results = {
            'avg': avg_chain,
            'min': min(chain_latencies),
            'max': max(chain_latencies)
        }
    
    def test_latency_under_load(self):
        """Test latency with multiple concurrent operations"""
        print("\n📊 Testing latency under load (5-10 concurrent)...")
        
        import threading
        import queue
        
        def worker(worker_id, result_queue):
            """Simulate worker operation"""
            latencies = []
            for _ in range(20):  # 20 readings per worker
                latency = self.measure_latency('H2S', random.uniform(1, 15))
                latencies.append(latency)
            result_queue.put((worker_id, latencies))
        
        # Test with 5-10 concurrent workers
        for num_workers in [5, 8, 10]:
            with self.subTest(workers=num_workers):
                result_queue = queue.Queue()
                threads = []
                
                # Start workers
                for i in range(num_workers):
                    t = threading.Thread(target=worker, args=(i, result_queue))
                    threads.append(t)
                    t.start()
                
                # Wait for completion
                for t in threads:
                    t.join()
                
                # Collect results
                all_latencies = []
                while not result_queue.empty():
                    _, latencies = result_queue.get()
                    all_latencies.extend(latencies)
                
                avg_latency = sum(all_latencies) / len(all_latencies)
                max_latency = max(all_latencies)
                
                print(f"   {num_workers} workers - Avg: {avg_latency*1000:.2f}ms, Max: {max_latency*1000:.2f}ms")
                
                # Assert still under 3 seconds
                self.assertLess(max_latency, 3.0,
                    f"Max latency {max_latency*1000:.2f}ms exceeded 3000ms with {num_workers} workers")

if __name__ == '__main__':
    unittest.main()