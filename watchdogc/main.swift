//
//	main.swift
//	watchdog
//
//	Created by Kaz Yoshikawa on 6/5/21.
//
//	This project demonstrate how to write command line tool for macOS.
//

import Foundation
import CoreServices

func error(_ string: String) {
	FileHandle.standardError.write(Data((string + "\r\n").utf8))
}

extension String {
	func appendingPathComponent(_ string: String) -> String {
		return (self as NSString).appendingPathComponent(string)
	}
	var standardizingPath: String {
		return (self as NSString).standardizingPath
	}
	func appendingPathExtension(_ string: String) -> String? {
		return (self as NSString).appendingPathExtension(string)
	}
	var deletingPathExtension: String {
		return (self as NSString).deletingPathExtension
	}
	var deletingLastPathComponent: String {
		return (self as NSString).deletingLastPathComponent
	}
	var pathExtension: String {
		return (self as NSString).pathExtension
	}
}

var iterator = CommandLine.arguments.dropFirst().makeIterator()
let command = "watchdog"

struct CommandOptions {
	var watchDirectory: String?
}

var commandOptions = CommandOptions()

while let argument = iterator.next() {
	switch argument {
	case "--help":
		help(); exit(0)
	case "--watch", "-w":
		if let directory = iterator.next() {
			let watchDirectory = directory.standardizingPath
			var isDir: ObjCBool = false
			if FileManager.default.fileExists(atPath: watchDirectory, isDirectory: &isDir) && isDir.boolValue {
				commandOptions.watchDirectory = watchDirectory
			}
			else { error("The watch directory `\(watchDirectory)` does not exist, or not a directory."); exit(1) }
		}
	default:
		error("Unknown parameter `\(argument)`"); exit(1)
	}
}

guard let watchDirectory = commandOptions.watchDirectory else { print("Not specified the watch directory. use `--watch` to specify."); exit(1) }
var dictionary = [String: Set<String>]()
do {
	let contents = try FileManager.default.contentsOfDirectory(atPath: watchDirectory)
	dictionary[watchDirectory] = Set(contents)
	print("watch directory:", watchDirectory)
}

//
guard let runLoop = CFRunLoopGetCurrent() else { print("Failed getting current run loop."); exit(1) }
let callback: FSEventStreamCallback = { (streamRef, callbackInfo, numEvents, eventPaths, eventFlags, streamEvent) in
	if let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] {
		for (path, _) in zip(paths, ((0..<numEvents).map { eventFlags[$0] })) {
			do {
				let path = path.standardizingPath
				let before = dictionary[path] ?? Set()
				let after = Set(try FileManager.default.contentsOfDirectory(atPath: path))
				let deleted = before.subtracting(after)
				let added = after.subtracting(before)
				if deleted.count > 0 {
					print( deleted.sorted().map { "- " + $0 }.joined(separator: "\r\n"))
				}
				if added.count > 0 {
					print( added.sorted().map { "+ " + $0 }.joined(separator: "\r\n"))
				}
				dictionary[path] = after
			}
			catch { print("\(error)") }
		}
	}
	else { error("Failed getting event paths"); exit(1) }
}

var context = FSEventStreamContext()
let pathsToWatch = [watchDirectory] as CFArray
//	print("watching directories:\r\n", pathsToWatch.compactMap { $0 as? String }.joined(separator: "\r\n"))
let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)
guard let eventStream = FSEventStreamCreate(nil, callback, &context, pathsToWatch as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags)
else { print("Failed create `FSEventStream`."); exit(1) }
FSEventStreamScheduleWithRunLoop(eventStream, runLoop, CFRunLoopMode.defaultMode.rawValue)
FSEventStreamStart(eventStream)
CFRunLoopRun()


func help() {
	print("""
	[Description]
	\(command) keeps watching a directory for adding or deleting any files or subdirectories and log them on the console.
	[Options]
	-w, --watch <watch-directory> directory to watch
	[Usage]
	\(command) --watch ~/Desktop
	""")
}

