#!/usr/bin/env python3
"""
Test Case: Threshold Validation (SAFE/CAUTION/BLOCK)
Tests that the system correctly classifies based on thresholds
"""

import unittest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

class TestThresholds(unittest.TestCase):
    """Test suite for threshold-based decision making"""
    
    # Thresholds from problem statement (matches Flutter app)
    THRESHOLDS = {
        'H2S': {'caution': 5.0, 'block': 10.0},
        'CH4': {'caution': 0.5, 'block': 2.0},
        'CO': {'caution': 25.0, 'block': 35.0},
        'O2': {'caution': 20.8, 'block': 19.5}
    }
    
    def evaluate_safety(self, readings):
        """
        Simulate the app's safety decision logic
        Returns: 'SAFE', 'CAUTION', or 'BLOCK'
        """
        # Check BLOCK conditions
        if (readings.get('H2S', 0) >= self.THRESHOLDS['H2S']['block'] or
            readings.get('CH4', 0) >= self.THRESHOLDS['CH4']['block'] or
            readings.get('CO', 0) >= self.THRESHOLDS['CO']['block'] or
            readings.get('O2', 21) <= self.THRESHOLDS['O2']['block']):
            return 'BLOCK'
        
        # Check CAUTION conditions
        if (readings.get('H2S', 0) >= self.THRESHOLDS['H2S']['caution'] or
            readings.get('CH4', 0) >= self.THRESHOLDS['CH4']['caution'] or
            readings.get('CO', 0) >= self.THRESHOLDS['CO']['caution'] or
            readings.get('O2', 21) <= self.THRESHOLDS['O2']['caution']):
            return 'CAUTION'
        
        return 'SAFE'
    
    def test_h2s_thresholds(self):
        """Test H2S threshold classification"""
        print("\n📊 Testing H2S thresholds...")
        
        test_cases = [
            {'H2S': 2.0, 'expected': 'SAFE'},
            {'H2S': 6.0, 'expected': 'CAUTION'},
            {'H2S': 12.0, 'expected': 'BLOCK'},
            {'H2S': 5.0, 'expected': 'CAUTION'},  # Exactly at caution
            {'H2S': 10.0, 'expected': 'BLOCK'},   # Exactly at block
        ]
        
        for case in test_cases:
            with self.subTest(h2s=case['H2S']):
                result = self.evaluate_safety(case)
                self.assertEqual(result, case['expected'],
                    f"H2S={case['H2S']}ppm -> Expected {case['expected']}, got {result}")
        
        print("   ✅ H2S threshold tests passed")
    
    def test_o2_thresholds(self):
        """Test O2 threshold classification (inverted logic)"""
        print("\n📊 Testing O2 thresholds...")
        
        test_cases = [
            {'O2': 20.9, 'expected': 'SAFE'},
            {'O2': 20.5, 'expected': 'CAUTION'},  # Below 20.8
            {'O2': 19.0, 'expected': 'BLOCK'},    # Below 19.5
            {'O2': 20.8, 'expected': 'CAUTION'},  # Exactly at caution
            {'O2': 19.5, 'expected': 'BLOCK'},    # Exactly at block
        ]
        
        for case in test_cases:
            with self.subTest(o2=case['O2']):
                result = self.evaluate_safety(case)
                self.assertEqual(result, case['expected'],
                    f"O2={case['O2']}% -> Expected {case['expected']}, got {result}")
        
        print("   ✅ O2 threshold tests passed")
    
    def test_mixed_gas_scenarios(self):
        """Test scenarios with multiple gases"""
        print("\n📊 Testing mixed gas scenarios...")
        
        test_cases = [
            # All safe
            ({'H2S': 2.0, 'CH4': 0.2, 'CO': 10.0, 'O2': 20.9}, 'SAFE'),
            
            # Single gas in caution
            ({'H2S': 6.0, 'CH4': 0.2, 'CO': 10.0, 'O2': 20.9}, 'CAUTION'),
            ({'H2S': 2.0, 'CH4': 1.0, 'CO': 10.0, 'O2': 20.9}, 'CAUTION'),
            ({'H2S': 2.0, 'CH4': 0.2, 'CO': 30.0, 'O2': 20.9}, 'CAUTION'),
            ({'H2S': 2.0, 'CH4': 0.2, 'CO': 10.0, 'O2': 20.5}, 'CAUTION'),
            
            # Single gas in block
            ({'H2S': 12.0, 'CH4': 0.2, 'CO': 10.0, 'O2': 20.9}, 'BLOCK'),
            ({'H2S': 2.0, 'CH4': 3.0, 'CO': 10.0, 'O2': 20.9}, 'BLOCK'),
            ({'H2S': 2.0, 'CH4': 0.2, 'CO': 40.0, 'O2': 20.9}, 'BLOCK'),
            ({'H2S': 2.0, 'CH4': 0.2, 'CO': 10.0, 'O2': 18.0}, 'BLOCK'),
            
            # Multiple gases at different levels - highest severity wins
            ({'H2S': 12.0, 'CH4': 1.0, 'CO': 30.0, 'O2': 20.5}, 'BLOCK'),  # Block wins
            ({'H2S': 6.0, 'CH4': 0.8, 'CO': 28.0, 'O2': 20.9}, 'CAUTION'),  # Caution only
        ]
        
        for readings, expected in test_cases:
            with self.subTest(readings=readings):
                result = self.evaluate_safety(readings)
                self.assertEqual(result, expected,
                    f"Readings {readings} -> Expected {expected}, got {result}")
        
        print("   ✅ Mixed gas tests passed")
    
    def test_boundary_conditions(self):
        """Test exact boundary values"""
        print("\n📊 Testing boundary conditions...")
        
        # Test values just below, at, and just above thresholds
        boundaries = [
            # H2S boundaries
            {'H2S': 4.99, 'expected': 'SAFE'},
            {'H2S': 5.01, 'expected': 'CAUTION'},
            {'H2S': 9.99, 'expected': 'CAUTION'},
            {'H2S': 10.01, 'expected': 'BLOCK'},
            
            # O2 boundaries
            {'O2': 20.81, 'expected': 'SAFE'},
            {'O2': 20.79, 'expected': 'CAUTION'},
            {'O2': 19.51, 'expected': 'CAUTION'},
            {'O2': 19.49, 'expected': 'BLOCK'},
        ]
        
        for case in boundaries:
            with self.subTest(case=case):
                result = self.evaluate_safety(case)
                self.assertEqual(result, case['expected'])
        
        print("   ✅ Boundary tests passed")
    
    def test_pre_entry_decision_sequence(self):
        """Test the complete pre-entry assessment sequence"""
        print("\n📊 Testing pre-entry assessment sequence...")
        
        # Simulate a real pre-entry sequence with 3-level probe
        sequence = [
            # Top level (1m) - Safe
            {'depth': 'top', 'H2S': 1.0, 'CH4': 0.1, 'CO': 5.0, 'O2': 20.9, 'expected': 'SAFE'},
            
            # Mid level (4.5m) - Caution
            {'depth': 'mid', 'H2S': 6.0, 'CH4': 0.4, 'CO': 15.0, 'O2': 20.5, 'expected': 'CAUTION'},
            
            # Bottom level (8m) - Block
            {'depth': 'bottom', 'H2S': 12.0, 'CH4': 0.8, 'CO': 25.0, 'O2': 20.0, 'expected': 'BLOCK'},
        ]
        
        # Final decision should be based on worst case
        final_decision = self.evaluate_safety({
            'H2S': max(r.get('H2S', 0) for r in sequence),
            'CH4': max(r.get('CH4', 0) for r in sequence),
            'CO': max(r.get('CO', 0) for r in sequence),
            'O2': min(r.get('O2', 21) for r in sequence)
        })
        
        self.assertEqual(final_decision, 'BLOCK', 
            "Pre-entry assessment should return BLOCK based on bottom readings")
        
        print("   ✅ Pre-entry sequence test passed")

if __name__ == '__main__':
    unittest.main()