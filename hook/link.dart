import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await link(args, (input, output) async {
    for (final asset in input.assets.code) {
      output.assets.code.add(asset);
    }
  });
}
