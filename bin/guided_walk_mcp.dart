import 'dart:convert';
import 'dart:io';

// Relative, so the script runs where no package is resolved, as in a dependency's checkout in the
// pub cache: the server needs nothing but Dart.
// ignore: avoid_relative_lib_imports
import '../lib/src/mcp/walk_mcp.dart';

/// The walk's folder as an MCP server over standard input and output, started by the agent:
///
///     dart run <this repository>/bin/guided_walk_mcp.dart <the walk's folder>
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: guided_walk_mcp <the walk\'s folder>');
    exitCode = 64;
    return;
  }
  // Started by hand in a terminal, it would wait in silence for an agent that never speaks.
  if (stdin.hasTerminal) stderr.writeln(handStarted(Directory(arguments.single).absolute.path));
  final input = stdin.transform(utf8.decoder).transform(const LineSplitter());
  await WalkMcpServer(Directory(arguments.single)).serve(input, stdout);
}
