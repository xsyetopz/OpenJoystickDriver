import Darwin
import Foundation
import Testing

@testable import OpenJoystickDriverCLI

struct CLIOutputWriteTests {
  @Test
  func writeToClosedDescriptorReturnsBadDescriptor() {
    let pipe = Pipe()
    let descriptor = dup(pipe.fileHandleForWriting.fileDescriptor)
    close(descriptor)
    let writer = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)

    let failure = CLIOutput.send(Data("status\n".utf8), to: writer)

    #expect(failure == EBADF)
  }

  @Test
  func writeToPipeWithoutReaderReturnsBrokenPipe() throws {
    let pipe = Pipe()
    try pipe.fileHandleForReading.close()
    let previous = signal(SIGPIPE, SIG_IGN)
    defer { signal(SIGPIPE, previous) }

    let failure = CLIOutput.send(Data("status\n".utf8), to: pipe.fileHandleForWriting)

    #expect(failure == EPIPE)
  }

  @Test
  func writeToOpenPipeDeliversData() throws {
    let pipe = Pipe()

    let failure = CLIOutput.send(Data("status\n".utf8), to: pipe.fileHandleForWriting)
    try pipe.fileHandleForWriting.close()

    #expect(failure == nil)
    #expect(try pipe.fileHandleForReading.readToEnd() == Data("status\n".utf8))
  }
}
