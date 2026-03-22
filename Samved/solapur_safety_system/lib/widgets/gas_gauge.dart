import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

class GasGaugeWidget extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final double max;
  final double cautionThreshold;
  final double blockThreshold;
  final bool invertedSafe;

  const GasGaugeWidget({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.max,
    required this.cautionThreshold,
    required this.blockThreshold,
    this.invertedSafe = false,
  });

  @override
  Widget build(BuildContext context) {
    List<GaugeRange> ranges = [
      if (!invertedSafe) ...[
        GaugeRange(startValue: 0, endValue: cautionThreshold, color: Colors.green),
        GaugeRange(startValue: cautionThreshold, endValue: blockThreshold, color: Colors.orange),
        GaugeRange(startValue: blockThreshold, endValue: max, color: Colors.red),
      ] else ...[
        GaugeRange(startValue: 0, endValue: blockThreshold, color: Colors.red),
        GaugeRange(startValue: blockThreshold, endValue: cautionThreshold, color: Colors.orange),
        GaugeRange(startValue: cautionThreshold, endValue: max, color: Colors.green),
      ]
    ];

    return SfRadialGauge(
      title: GaugeTitle(
        text: label,
        textStyle: const TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold, color: Colors.white),
      ),
      axes: <RadialAxis>[
        RadialAxis(
          minimum: 0,
          maximum: max,
          ranges: ranges,
          axisLineStyle: const AxisLineStyle(thickness: 0.1, thicknessUnit: GaugeSizeUnit.factor),
          pointers: <GaugePointer>[
            NeedlePointer(
              value: value,
              enableAnimation: true,
              needleColor: Colors.white70,
              knobStyle: const KnobStyle(color: Colors.white),
              needleEndWidth: 4,
              needleLength: 0.7,
            )
          ],
          annotations: <GaugeAnnotation>[
            GaugeAnnotation(
              widget: Text(
                '${value.toStringAsFixed(1)}\n$unit',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              angle: 90,
              positionFactor: 0.8,
            )
          ],
        )
      ],
    );
  }
}
