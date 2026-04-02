// ProwlCLI/Commands/GlobalOptions.swift
// Shared output options.

import ArgumentParser

struct GlobalOptions: ParsableArguments {
  @Flag(name: .long, help: "Output in JSON format matching schema contracts.")
  var json = false

  var outputMode: OutputMode {
    json ? .json : .text
  }
}
