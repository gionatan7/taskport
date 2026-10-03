import Darwin
import Foundation
import Testing
@testable import TaskportControl

struct OccupiedPortsTests {
    @Test func commandAcceptsNoTaskSelectorsOrMutationOptions() throws {
        #expect(try CLIArguments.parse(["ports", "list"]).operation == "ports.list")
        #expect(try CLIArguments.parse(["ports", "list", "--json"]).operation == "ports.list")
        for arguments in [["ports"], ["ports", "stop"], ["ports", "list", UUID().uuidString],
                          ["ports", "list", "--all"], ["ports", "list", "--name", "Web"],
                          ["ports", "list", "--env-file", "/nonexistent"]] {
            #expect(throws: ControlError.self) { try CLIArguments.parse(arguments) }
        }
    }

    @Test func sortsAndDeduplicatesListenersAcrossAddressesAndFamilies() throws {
        let output = """
        p123
        f4
        n[::1]:8080
        f5
        n127.0.0.1:3000
        p456
        f0
        n*:8080
        f8
        n[fe80::1%lo0]:9000
        f10
        n127.0.0.1:3000
        """
        #expect(try OccupiedPorts.parse(output, exitStatus: 0) == [3000, 8080, 9000])
        #expect(try OccupiedPorts.parse("", exitStatus: 1).isEmpty)
        var response = ControlResponse()
        response.ports = try OccupiedPorts.parse(output, exitStatus: 0)
        let encoded = try JSONEncoder().encode(response)
        #expect(try JSONDecoder().decode(ControlResponse.self, from: encoded).ports == [3000, 8080, 9000])
    }

    @Test func refusesDiagnosticsAndMalformedSnapshotsInsteadOfReportingFreePorts() {
        for output in ["", "\n", "p123\n", "lsof: Operation not permitted",
                       "p123\nn*:3000\nlsof: WARNING: incomplete snapshot",
                       "n*:3000", "p0\nn*:3000", "p123\nf-1\nn*:3000", "p123\nn*:invalid",
                       "p123\nn*:65536", "p123\nn*:0", "p123\nnlocalhost",
                       "p123\nn127.0.0.1:55000->127.0.0.1:3000"] {
            #expect(throws: ControlError.self) { try OccupiedPorts.parse(output, exitStatus: 0) }
        }
        for status: Int32 in [1, 2, 15] {
            #expect(throws: ControlError.self) { try OccupiedPorts.parse("lsof: denied", exitStatus: status) }
            #expect(throws: ControlError.self) { try OccupiedPorts.parse("p123\nn*:3000", exitStatus: status) }
        }
    }

    @Test(arguments: [AF_INET, AF_INET6]) func detectsListenerOutsideTaskport(_ family: Int32) throws {
        // A raw test socket, not a web server: the kernel chooses a loopback-only port.
        let fd = socket(family, SOCK_STREAM, 0)
        #expect(fd >= 0)
        guard fd >= 0 else { return }
        defer { close(fd) }
        let port: UInt16
        if family == AF_INET {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            try withUnsafeMutablePointer(to: &address) {
                try $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    try #require(Darwin.bind(fd, $0, length) == 0)
                    try #require(getsockname(fd, $0, &length) == 0)
                }
            }
            port = UInt16(bigEndian: address.sin_port)
        } else {
            var address = sockaddr_in6()
            address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            address.sin6_family = sa_family_t(AF_INET6)
            address.sin6_addr = in6addr_loopback
            var length = socklen_t(MemoryLayout<sockaddr_in6>.size)
            try withUnsafeMutablePointer(to: &address) {
                try $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    try #require(Darwin.bind(fd, $0, length) == 0)
                    try #require(getsockname(fd, $0, &length) == 0)
                }
            }
            port = UInt16(bigEndian: address.sin6_port)
        }
        try #require(listen(fd, 1) == 0)
        #expect(try OccupiedPorts.scan().contains(Int(port)))
    }
}
