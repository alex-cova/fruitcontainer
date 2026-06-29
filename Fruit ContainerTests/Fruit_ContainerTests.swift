//
//  Fruit_ContainerTests.swift
//  Fruit ContainerTests
//
//  Created by Alejandro Covarrubias on 25/06/26.
//

import Testing
import Foundation
@testable import Fruit_Container

struct Fruit_ContainerTests {

    @Test func commandRunnerWritesStandardInput() async throws {
        let runner = CommandRunner()
        let result = try await runner.run(
            CLICommand(
                executable: "/bin/cat",
                standardInput: Data("registry-token".utf8),
                timeout: 5
            )
        )

        #expect(result.stdout == "registry-token")
        #expect(result.exitCode == 0)
    }

    @Test func commandRunnerDrainsLargeStandardOutputBeforeProcessExit() async throws {
        let runner = CommandRunner()
        let result = try await runner.run(
            CLICommand(
                executable: "/bin/sh",
                arguments: ["-c", "i=0; while [ $i -lt 3000 ]; do printf 'abcdefghijklmnopqrstuvwxyz0123456789'; i=$((i + 1)); done"],
                timeout: 5
            )
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.count == 108_000)
    }

    @Test func semanticVersionParsing() {
        #expect(SemanticVersion.parse(from: "container 1.2.3") == SemanticVersion(major: 1, minor: 2, patch: 3))
        #expect(SemanticVersion.parse(from: "not-a-version") == nil)
    }

    @Test func currentVersionPolicyAcceptsZeroNineAndOneX() {
        let adapter = ContainerCLIAdapter(commandRunner: CommandRunner())

        #expect(isSupported(adapter.evaluateCompatibilityForTesting("0.9.0")))
        #expect(isSupported(adapter.evaluateCompatibilityForTesting("0.9.8")))
        #expect(isSupported(adapter.evaluateCompatibilityForTesting("1.0.0")))
        #expect(isSupported(adapter.evaluateCompatibilityForTesting("1.4.2")))
    }

    @Test func currentVersionPolicyRejectsInvalidAndBelowMinimum() {
        let adapter = ContainerCLIAdapter(commandRunner: CommandRunner())

        #expect(isUnsupported(adapter.evaluateCompatibilityForTesting("invalid")))
        #expect(isUnsupported(adapter.evaluateCompatibilityForTesting("0.8.9")))
    }

    @Test func currentVersionPolicyMarksFutureMajorUntested() {
        let adapter = ContainerCLIAdapter(commandRunner: CommandRunner())

        guard case .untestedNewerMajor = adapter.evaluateCompatibilityForTesting("2.0.0") else {
            Issue.record("Expected future major version to be marked untested.")
            return
        }
    }

    @Test func commandHelpDiscoveryFiltersUnsupportedOutput() {
        #expect(ContainerCLIAdapter.commandHelpIndicatesSupported("Usage: container build [OPTIONS] PATH", path: ["build"]))
        #expect(ContainerCLIAdapter.commandHelpIndicatesSupported("  machine, m              Manage container machines", path: ["machine"]))
        #expect(!ContainerCLIAdapter.commandHelpIndicatesSupported("Usage: container [--debug] <subcommand>", path: ["nosuch"]))
        #expect(!ContainerCLIAdapter.commandHelpIndicatesSupported("Error: unknown command \"build\" for \"container\""))
        #expect(!ContainerCLIAdapter.commandHelpIndicatesSupported(""))
    }

    @Test func containerListUsesAllJSONFormatArguments() {
        #expect(ContainerCLIAdapter.containerListArguments == ["list", "--all", "--format", "json"])
    }

    @Test func imageListDecodesCurrentContainerJSONShape() {
        let adapter = ContainerCLIAdapter(commandRunner: CommandRunner())
        let output = """
        [
          {
            "configuration": {
              "creationDate": "2026-06-24T01:21:58Z",
              "descriptor": {
                "digest": "sha256:ec4ed8b5299e5e90694af7750eb6dffd2627317d30544d056b0371f8082f7bce",
                "mediaType": "application/vnd.oci.image.index.v1+json",
                "size": 10229
              },
              "name": "docker.io/library/nginx:latest"
            },
            "id": "ec4ed8b5299e5e90694af7750eb6dffd2627317d30544d056b0371f8082f7bce",
            "variants": [
              {
                "config": {
                  "architecture": "arm64",
                  "created": "2026-06-24T01:21:58.377973076Z",
                  "os": "linux"
                },
                "digest": "sha256:3b2371e667437fb3b406f090081775daf1ebcdb981d19bc497703b150f49e356",
                "size": 63122392
              }
            ]
          }
        ]
        """

        guard case .parsed(let images, let diagnostics) = adapter.decodeImageListForTesting(output) else {
            Issue.record("Expected image list to decode.")
            return
        }

        #expect(diagnostics.droppedRecords == 0)
        #expect(images.count == 1)
        #expect(images.first?.reference == "docker.io/library/nginx:latest")
        #expect(images.first?.id == "ec4ed8b5299e5e90694af7750eb6dffd2627317d30544d056b0371f8082f7bce")
        #expect(images.first?.size == "10229")
        #expect(images.first?.created == "2026-06-24T01:21:58Z")
    }

    @Test func containerListDecodesCurrentContainerJSONShape() {
        let adapter = ContainerCLIAdapter(commandRunner: CommandRunner())
        let output = """
        [
          {
            "configuration": {
              "creationDate": "1970-01-01T00:00:00Z",
              "id": "monguichi",
              "image": {
                "descriptor": {
                  "digest": "sha256:1d5791cb98f26aa8e537efdaede63dfc2cb6d4dee9a6ac2fedb7a226b6197847",
                  "mediaType": "application/vnd.oci.image.index.v1+json",
                  "size": 1609
                },
                "reference": "docker.io/mongodb/atlas:latest"
              },
              "initProcess": {
                "arguments": ["-f", "/dev/null"],
                "environment": ["container=oci"],
                "executable": "tail",
                "workingDirectory": "/"
              },
              "labels": {},
              "networks": [
                {
                  "network": "default",
                  "options": {
                    "hostname": "monguichi",
                    "mtu": 1280
                  }
                }
              ],
              "platform": {
                "architecture": "arm64",
                "os": "linux"
              },
              "publishedPorts": [
                {
                  "containerPort": 27017,
                  "count": 1,
                  "hostAddress": "0.0.0.0",
                  "hostPort": 27017,
                  "proto": "tcp"
                }
              ],
              "readOnly": false,
              "resources": {
                "cpuOverhead": 1,
                "cpus": 4,
                "memoryInBytes": 1073741824
              },
              "rosetta": false
            },
            "id": "monguichi",
            "status": {
              "networks": [],
              "state": "stopped"
            }
          }
        ]
        """

        guard case .parsed(let containers, let diagnostics) = adapter.decodeContainerListForTesting(output) else {
            Issue.record("Expected container list to decode.")
            return
        }

        #expect(diagnostics.droppedRecords == 0)
        #expect(containers.count == 1)
        #expect(containers.first?.id == "monguichi")
        #expect(containers.first?.name == "monguichi")
        #expect(containers.first?.state == "stopped")
        #expect(containers.first?.image == "docker.io/mongodb/atlas:latest")
        #expect(containers.first?.platform == "linux/arm64")
        #expect(containers.first?.hostname == "monguichi")
        #expect(containers.first?.cpuCount == 4)
        #expect(containers.first?.memoryInBytes == 1_073_741_824)
        #expect(containers.first?.publishedPorts == ["0.0.0.0:27017->27017/tcp"])
        #expect(containers.first?.command == "tail -f /dev/null")
        #expect(containers.first?.rosetta == false)
    }

    @Test func containerInspectDecodesCurrentContainerJSONShape() {
        let adapter = ContainerCLIAdapter(commandRunner: CommandRunner())
        let output = """
        [
          {
            "configuration": {
              "creationDate": "1970-01-01T00:00:00Z",
              "id": "monguichi",
              "image": {
                "descriptor": {
                  "digest": "sha256:1d5791cb98f26aa8e537efdaede63dfc2cb6d4dee9a6ac2fedb7a226b6197847",
                  "mediaType": "application/vnd.oci.image.index.v1+json",
                  "size": 1609
                },
                "reference": "docker.io/mongodb/atlas:latest"
              },
              "initProcess": {
                "arguments": ["-f", "/dev/null"],
                "environment": [
                  "container=oci",
                  "MONGODB_ATLAS_IS_CONTAINERIZED=true",
                  "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
                ],
                "executable": "tail",
                "workingDirectory": "/"
              },
              "labels": {},
              "mounts": [],
              "networks": [
                {
                  "network": "default",
                  "options": {
                    "hostname": "monguichi",
                    "mtu": 1280
                  }
                }
              ],
              "platform": {
                "architecture": "arm64",
                "os": "linux"
              },
              "publishedPorts": [
                {
                  "containerPort": 27017,
                  "count": 1,
                  "hostAddress": "0.0.0.0",
                  "hostPort": 27017,
                  "proto": "tcp"
                }
              ],
              "readOnly": false,
              "resources": {
                "cpuOverhead": 1,
                "cpus": 4,
                "memoryInBytes": 1073741824
              },
              "rosetta": false,
              "runtimeHandler": "container-runtime-linux"
            },
            "id": "monguichi",
            "status": {
              "networks": [],
              "state": "stopped"
            }
          }
        ]
        """

        let snapshot = adapter.decodeContainerInspectForTesting(id: "monguichi", output: output)

        #expect(snapshot.containerID == "monguichi")
        #expect(snapshot.state == "stopped")
        #expect(snapshot.imageReference == "docker.io/mongodb/atlas:latest")
        #expect(snapshot.hostname == "monguichi")
        #expect(snapshot.platform == "linux/arm64")
        #expect(snapshot.command == "tail -f /dev/null")
        #expect(snapshot.environment.contains("MONGODB_ATLAS_IS_CONTAINERIZED=true"))
        #expect(snapshot.cpuCount == 4)
        #expect(snapshot.memoryBytes == 1_073_741_824)
        #expect(snapshot.publishedPorts == ["0.0.0.0:27017->27017/tcp"])
        #expect(snapshot.rosetta == false)
        #expect(snapshot.readOnly == false)
        #expect(snapshot.runtimeHandler == "container-runtime-linux")
        #expect(snapshot.configuredNetworkNames == ["default"])
        #expect(snapshot.rawJSON.contains("\"configuration\""))
    }

    @Test func containerStatsDecodesCurrentJSONShape() {
        let adapter = ContainerCLIAdapter(commandRunner: CommandRunner())
        let capturedAt = Date(timeIntervalSince1970: 1_719_337_200)
        let output = """
        [
          {
            "blockReadBytes": 11325440,
            "blockWriteBytes": 0,
            "cpuUsageUsec": 134906,
            "id": "monguichi",
            "memoryLimitBytes": 1073741824,
            "memoryUsageBytes": 11956224,
            "networkRxBytes": 93601,
            "networkTxBytes": 602,
            "numProcesses": 1
          }
        ]
        """

        let samples = adapter.decodeContainerStatsForTesting(output, capturedAt: capturedAt)

        #expect(samples.count == 1)
        #expect(samples.first?.containerID == "monguichi")
        #expect(samples.first?.cpuUsageUsec == 134_906)
        #expect(samples.first?.memoryUsageBytes == 11_956_224)
        #expect(samples.first?.memoryLimitBytes == 1_073_741_824)
        #expect(samples.first?.networkRxBytes == 93_601)
        #expect(samples.first?.networkTxBytes == 602)
        #expect(samples.first?.blockReadBytes == 11_325_440)
        #expect(samples.first?.blockWriteBytes == 0)
        #expect(samples.first?.processCount == 1)
        #expect(samples.first?.capturedAt == capturedAt)
    }

    @Test func containerResourceConfigurationParsesManagedContainerValues() {
        let text = """
        [build]
        cpus = 2

        [container]
        cpus = 8
        memory = "4g"

        [dns]
        domain = "test"
        """

        let configuration = ContainerResourceConfigurationStore.parse(text)

        #expect(configuration == ContainerResourceConfiguration(cpus: 8, memory: "4g"))
    }

    @Test func containerResourceConfigurationRenderPreservesUnmanagedContent() {
        let text = """
        # user notes
        [build]
        cpus = 2

        [container]
        # keep this comment
        cpus = 4
        memory = "2g"
        rosetta = true

        [dns]
        domain = "test"
        """

        let rendered = ContainerResourceConfigurationStore.render(
            ContainerResourceConfiguration(cpus: 6, memory: "3gb"),
            preserving: text
        )

        #expect(rendered.contains("# user notes"))
        #expect(rendered.contains("[build]\ncpus = 2"))
        #expect(rendered.contains("# keep this comment"))
        #expect(rendered.contains("cpus = 6"))
        #expect(rendered.contains("memory = \"3gb\""))
        #expect(rendered.contains("rosetta = true"))
        #expect(rendered.contains("[dns]\ndomain = \"test\""))
    }

    @Test func containerResourceConfigurationRenderCreatesContainerTable() {
        let rendered = ContainerResourceConfigurationStore.render(
            ContainerResourceConfiguration(cpus: 8, memory: "4g"),
            preserving: "[dns]\ndomain = \"test\""
        )

        #expect(rendered.contains("[dns]\ndomain = \"test\""))
        #expect(rendered.contains("[container]\ncpus = 8\nmemory = \"4g\""))
    }

    @Test func containerResourceConfigurationRenderRemovesBlankManagedKeys() {
        let text = """
        [container]
        cpus = 8
        memory = "4g"
        rosetta = true
        """

        let rendered = ContainerResourceConfigurationStore.render(.empty, preserving: text)

        #expect(!rendered.contains("cpus = 8"))
        #expect(!rendered.contains("memory = \"4g\""))
        #expect(rendered.contains("rosetta = true"))
    }

    @Test func activityLogStoreRoundTripsRecords() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("activity-log.json", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let queuedAt = Date(timeIntervalSince1970: 1_719_337_200)
        let record = ActivityRecord(
            title: "Pull nginx:latest",
            commandDescription: "container image pull nginx:latest",
            section: .images,
            kind: .image,
            status: .succeeded,
            queuedAt: queuedAt,
            finishedAt: queuedAt.addingTimeInterval(5),
            summary: "Pulled image.",
            outputLog: "done\n"
        )

        ActivityLogStore.save([record], to: url)
        let loaded = ActivityLogStore.load(from: url)

        #expect(loaded.count == 1)
        #expect(loaded.first?.id == record.id)
        #expect(loaded.first?.title == "Pull nginx:latest")
        #expect(loaded.first?.status == .succeeded)
        #expect(loaded.first?.queuedAt == queuedAt)
        #expect(loaded.first?.outputLog == "done\n")
    }

    @Test func activityLogStoreLoadReturnsEmptyForMissingFile() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)/missing.json")
        #expect(ActivityLogStore.load(from: url).isEmpty)
    }

    @Test func activityLogStoreCapsToMaximumRecords() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("activity-log.json", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let overflow = ActivityLogStore.maximumRecords + 50
        let records = (0..<overflow).map { index in
            ActivityRecord(
                title: "Operation \(index)",
                commandDescription: "echo \(index)",
                section: .containers,
                kind: .container
            )
        }

        ActivityLogStore.save(records, to: url)
        let loaded = ActivityLogStore.load(from: url)

        #expect(loaded.count == ActivityLogStore.maximumRecords)
        // The most recent records (the front of the list) are retained.
        #expect(loaded.first?.title == "Operation 0")
    }

    private func isSupported(_ state: ContainerCompatibilityState) -> Bool {
        if case .supported = state { return true }
        return false
    }

    private func isUnsupported(_ state: ContainerCompatibilityState) -> Bool {
        if case .unsupported = state { return true }
        return false
    }
}
