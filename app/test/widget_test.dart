import 'package:brainsnack/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats numbers and times', () {
    expect(compact(950), '950');
    expect(compact(1500), '1.5k');
    expect(clock(65000), '1:05');
  });
}
