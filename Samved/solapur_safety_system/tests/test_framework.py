#!/usr/bin/env python3
"""
Solapur Safety System - Comprehensive Test Framework
Tests all requirements: latency, thresholds, emergency escalation, offline buffering
"""

import unittest
import sys
import os
import json
import time
import csv
import html
import datetime
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

class SolapurTestRunner:
    """Main test runner that discovers and executes all tests"""
    
    def __init__(self):
        self.start_time = None
        self.end_time = None
        self.results = {
            'summary': {
                'total': 0,
                'passed': 0,
                'failed': 0,
                'errors': 0,
                'skipped': 0,
                'success_rate': 0
            },
            'test_cases': [],
            'requirements_coverage': {},
            'performance_metrics': {}
        }
        
    def discover_tests(self):
        """Discover all test cases in test_cases directory"""
        test_dir = Path(__file__).parent / 'test_cases'
        test_files = test_dir.glob('test_*.py')
        
        test_suite = unittest.TestSuite()
        loader = unittest.TestLoader()
        
        for test_file in test_files:
            module_name = f"test_cases.{test_file.stem}"
            try:
                module = __import__(module_name, fromlist=[''])
                tests = loader.loadTestsFromModule(module)
                test_suite.addTests(tests)
            except Exception as e:
                print(f"❌ Failed to load {module_name}: {e}")
                
        return test_suite
    
    def run_tests(self):
        """Execute all tests and collect results"""
        self.start_time = time.time()
        
        # Create test suite
        suite = self.discover_tests()
        
        # Create test result collector
        result = unittest.TestResult()
        
        print("\n" + "="*80)
        print("🧪 SOLAPUR SAFETY SYSTEM - COMPREHENSIVE TEST SUITE")
        print("="*80)
        print(f"Started at: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print("-"*80)
        
        # Run tests
        suite.run(result)
        
        self.end_time = time.time()
        
        # Compile results
        self.results['summary']['total'] = result.testsRun
        self.results['summary']['passed'] = result.testsRun - len(result.failures) - len(result.errors)
        self.results['summary']['failed'] = len(result.failures)
        self.results['summary']['errors'] = len(result.errors)
        self.results['summary']['skipped'] = len(result.skipped)
        self.results['summary']['success_rate'] = (
            (self.results['summary']['passed'] / self.results['summary']['total'] * 100) 
            if self.results['summary']['total'] > 0 else 0
        )
        self.results['summary']['duration'] = self.end_time - self.start_time
        
        # Compile test case details
        for test, traceback in result.failures:
            self.results['test_cases'].append({
                'name': str(test),
                'status': 'FAILED',
                'message': str(traceback),
                'duration': getattr(test, '_duration', 0)
            })
            
        for test, traceback in result.errors:
            self.results['test_cases'].append({
                'name': str(test),
                'status': 'ERROR',
                'message': str(traceback),
                'duration': getattr(test, '_duration', 0)
            })
            
        for test in result.skipped:
            self.results['test_cases'].append({
                'name': str(test[0]),
                'status': 'SKIPPED',
                'message': str(test[1]),
                'duration': 0
            })
        
        # Calculate requirement coverage
        self.calculate_requirement_coverage()
        
        # Print summary
        self.print_summary()
        
        return self.results
    
    def calculate_requirement_coverage(self):
        """Calculate coverage of project requirements"""
        requirements = {
            'latency_3s': False,
            'pre_entry_decision': False,
            'alert_escalation_5s': False,
            'offline_buffering': False,
            'exposure_tracking': False,
            'multi_worker': False,
            'thresholds': False,
            'data_logging': False
        }
        
        # Check which tests passed
        for test in self.results['test_cases']:
            if test['status'] == 'PASSED':
                if 'latency' in test['name'].lower():
                    requirements['latency_3s'] = True
                elif 'threshold' in test['name'].lower():
                    requirements['thresholds'] = True
                    requirements['pre_entry_decision'] = True
                elif 'emergency' in test['name'].lower():
                    requirements['alert_escalation_5s'] = True
                elif 'offline' in test['name'].lower():
                    requirements['offline_buffering'] = True
                elif 'exposure' in test['name'].lower():
                    requirements['exposure_tracking'] = True
                elif 'multi' in test['name'].lower():
                    requirements['multi_worker'] = True
                elif 'logging' in test['name'].lower():
                    requirements['data_logging'] = True
        
        self.results['requirements_coverage'] = requirements
    
    def print_summary(self):
        """Print test summary to console"""
        print("\n" + "-"*80)
        print("📊 TEST SUMMARY")
        print("-"*80)
        print(f"Total Tests:     {self.results['summary']['total']}")
        print(f"✅ Passed:        {self.results['summary']['passed']}")
        print(f"❌ Failed:        {self.results['summary']['failed']}")
        print(f"⚠️ Errors:        {self.results['summary']['errors']}")
        print(f"⏭️ Skipped:       {self.results['summary']['skipped']}")
        print(f"📈 Success Rate:  {self.results['summary']['success_rate']:.1f}%")
        print(f"⏱️ Duration:      {self.results['summary']['duration']:.2f}s")
        
        print("\n📋 REQUIREMENTS COVERAGE:")
        for req, covered in self.results['requirements_coverage'].items():
            status = "✅" if covered else "❌"
            print(f"  {status} {req}")
        
        print("\n" + "="*80)
    
    def generate_html_report(self, output_file='reports/test_report.html'):
        """Generate detailed HTML test report"""
        report_dir = Path(__file__).parent / 'reports'
        report_dir.mkdir(exist_ok=True)
        
        html_content = f"""
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Solapur Safety System - Test Report</title>
            <style>
                body {{
                    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                    margin: 0;
                    padding: 20px;
                    background: #1a1a2e;
                    color: #ecf0f1;
                }}
                .container {{
                    max-width: 1200px;
                    margin: 0 auto;
                    background: #16213e;
                    border-radius: 15px;
                    padding: 30px;
                    box-shadow: 0 4px 6px rgba(0,0,0,0.1);
                }}
                h1, h2, h3 {{
                    color: #3498db;
                }}
                .summary-grid {{
                    display: grid;
                    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
                    gap: 20px;
                    margin: 20px 0;
                }}
                .stat-card {{
                    background: #0f3460;
                    padding: 20px;
                    border-radius: 10px;
                    text-align: center;
                }}
                .stat-value {{
                    font-size: 36px;
                    font-weight: bold;
                    margin: 10px 0;
                }}
                .stat-label {{
                    color: #bdc3c7;
                    font-size: 14px;
                }}
                .pass {{ color: #27ae60; }}
                .fail {{ color: #e74c3c; }}
                .warning {{ color: #f39c12; }}
                
                .progress-bar {{
                    width: 100%;
                    height: 20px;
                    background: #34495e;
                    border-radius: 10px;
                    overflow: hidden;
                    margin: 10px 0;
                }}
                .progress-fill {{
                    height: 100%;
                    background: #27ae60;
                    transition: width 0.3s ease;
                }}
                
                table {{
                    width: 100%;
                    border-collapse: collapse;
                    margin: 20px 0;
                }}
                th, td {{
                    padding: 12px;
                    text-align: left;
                    border-bottom: 1px solid #34495e;
                }}
                th {{
                    background: #0f3460;
                    color: #3498db;
                }}
                tr:hover {{
                    background: #1a1a2e;
                }}
                
                .requirement-grid {{
                    display: grid;
                    grid-template-columns: repeat(2, 1fr);
                    gap: 10px;
                    margin: 20px 0;
                }}
                .requirement-item {{
                    padding: 10px;
                    background: #0f3460;
                    border-radius: 5px;
                    display: flex;
                    align-items: center;
                    gap: 10px;
                }}
                
                .timestamp {{
                    color: #bdc3c7;
                    font-size: 14px;
                    text-align: right;
                    margin-top: 20px;
                }}
            </style>
        </head>
        <body>
            <div class="container">
                <h1>🧪 Solapur Safety System - Test Report</h1>
                <p>Generated on {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
                
                <div class="summary-grid">
                    <div class="stat-card">
                        <div class="stat-value {self._get_color_class('total')}">{self.results['summary']['total']}</div>
                        <div class="stat-label">Total Tests</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-value pass">{self.results['summary']['passed']}</div>
                        <div class="stat-label">Passed</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-value fail">{self.results['summary']['failed']}</div>
                        <div class="stat-label">Failed</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-value warning">{self.results['summary']['errors']}</div>
                        <div class="stat-label">Errors</div>
                    </div>
                </div>
                
                <div class="progress-bar">
                    <div class="progress-fill" style="width: {self.results['summary']['success_rate']}%"></div>
                </div>
                <p style="text-align: center;">Success Rate: {self.results['summary']['success_rate']:.1f}%</p>
                
                <h2>📋 Requirements Coverage</h2>
                <div class="requirement-grid">
        """
        
        for req, covered in self.results['requirements_coverage'].items():
            status = "✅" if covered else "❌"
            html_content += f"""
                    <div class="requirement-item">
                        <span>{status}</span>
                        <span>{req.replace('_', ' ').title()}</span>
                    </div>
            """
        
        html_content += f"""
                </div>
                
                <h2>📊 Test Results</h2>
                <table>
                    <thead>
                        <tr>
                            <th>Test Name</th>
                            <th>Status</th>
                            <th>Duration (s)</th>
                            <th>Message</th>
                        </tr>
                    </thead>
                    <tbody>
        """
        
        for test in self.results['test_cases']:
            status_class = {
                'PASSED': 'pass',
                'FAILED': 'fail',
                'ERROR': 'warning',
                'SKIPPED': 'warning'
            }.get(test['status'], '')
            
            html_content += f"""
                        <tr>
                            <td>{test['name']}</td>
                            <td class="{status_class}">{test['status']}</td>
                            <td>{test['duration']:.2f}</td>
                            <td>{test.get('message', '')[:100]}</td>
                        </tr>
            """
        
        html_content += f"""
                    </tbody>
                </table>
                
                <h2>⏱️ Performance Metrics</h2>
                <table>
                    <thead>
                        <tr>
                            <th>Metric</th>
                            <th>Value</th>
                            <th>Requirement</th>
                            <th>Status</th>
                        </tr>
                    </thead>
                    <tbody>
                        <tr>
                            <td>Response Latency</td>
                            <td>{self.results.get('performance_metrics', {}).get('avg_latency', 'N/A')} ms</td>
                            <td>&lt; 3000 ms</td>
                            <td>{'✅' if self.results.get('performance_metrics', {}).get('avg_latency', 9999) < 3000 else '❌'}</td>
                        </tr>
                        <tr>
                            <td>Alert Escalation</td>
                            <td>{self.results.get('performance_metrics', {}).get('avg_escalation', 'N/A')} s</td>
                            <td>&lt; 5 s</td>
                            <td>{'✅' if self.results.get('performance_metrics', {}).get('avg_escalation', 999) < 5 else '❌'}</td>
                        </tr>
                    </tbody>
                </table>
                
                <div class="timestamp">
                    Test Duration: {self.results['summary']['duration']:.2f} seconds
                </div>
            </div>
        </body>
        </html>
        """
        
        report_path = report_dir / output_file
        with open(report_path, 'w', encoding='utf-8') as f:
            f.write(html_content)
            
        print(f"\n📄 HTML report generated: {report_path}")
        return str(report_path)
    
    def _get_color_class(self, value_type):
        """Get color class for stat values"""
        if value_type == 'total':
            return ''
        return ''

def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description='Solapur Safety System Test Framework')
    parser.add_argument('--suite', choices=['all', 'latency', 'thresholds', 'emergency', 'offline'],
                       default='all', help='Test suite to run')
    parser.add_argument('--report', type=str, default='test_report.html',
                       help='Output HTML report filename')
    parser.add_argument('--verbose', '-v', action='store_true',
                       help='Verbose output')
    
    args = parser.parse_args()
    
    # Create test runner
    runner = SolapurTestRunner()
    
    # Run tests
    results = runner.run_tests()
    
    # Generate report
    report_path = runner.generate_html_report(args.report)
    
    # Return appropriate exit code
    if results['summary']['failed'] == 0 and results['summary']['errors'] == 0:
        print("\n✅ ALL TESTS PASSED!")
        return 0
    else:
        print(f"\n❌ {results['summary']['failed']} TESTS FAILED, {results['summary']['errors']} ERRORS")
        return 1

if __name__ == "__main__":
    import argparse
    sys.exit(main())