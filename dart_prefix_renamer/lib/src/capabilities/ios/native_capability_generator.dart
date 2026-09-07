import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../model/capability_manifest.dart';

class NativeCapabilityGenerator {
  NativeCapabilityGenerator({required this.projectRoot});

  final String projectRoot;

  static const supportedCapabilities = {
    'device',
    'network',
    'secure_storage',
    'crypto',
    'diagnostics',
    'performance',
  };
  static const _podfileBegin =
      '# dart-prefix-renamer:native-capabilities:begin';
  static const _podfileEnd = '# dart-prefix-renamer:native-capabilities:end';

  Future<NativeGenerationReport> generate(
    NativeCapabilityManifest manifest,
  ) async {
    final root = Directory(p.join(projectRoot, 'ios', 'NativeCapabilities'));
    await root.create(recursive: true);
    final generated = <String>[];
    final enabled =
        manifest.native.entries
            .where(
              (entry) =>
                  entry.value.enabled &&
                  supportedCapabilities.contains(entry.key),
            )
            .map((entry) => entry.key)
            .toList()
          ..sort();

    generated.add(
      await _write(root, 'NativeCapability.swift', _protocolSource()),
    );
    for (final capability in enabled) {
      generated.add(
        await _write(
          root,
          '${_pascal(capability)}Capability.swift',
          _sourceFor(capability),
        ),
      );
    }
    generated.add(
      await _write(
        root,
        'NativeCapabilityManager.swift',
        _managerSource(enabled),
      ),
    );
    generated.add(
      await _write(
        root,
        'NativeCapabilityBridge.swift',
        _bridgeSource(enabled),
      ),
    );
    generated.add(
      await _write(root, 'NativeCapabilities.podspec', _podspecSource()),
    );
    await _wirePodfile();
    final manifestPath = await _write(
      root,
      'native_capability_manifest.json',
      '${const JsonEncoder.withIndent('  ').convert({
        'schema_version': 1,
        'enabled': enabled,
        'providers': {for (final name in enabled) name: manifest.native[name]!.provider},
      })}\n',
    );
    generated.add(manifestPath);
    final digest = sha256.convert(
      utf8.encode(
        generated
            .map((path) => File(path).readAsStringSync())
            .join('\n--native-capability-file--\n'),
      ),
    );
    return NativeGenerationReport(
      enabled: enabled,
      generatedFiles: generated,
      contentHash: digest.toString(),
    );
  }

  Future<void> _wirePodfile() async {
    final podfile = File(p.join(projectRoot, 'ios', 'Podfile'));
    if (!podfile.existsSync()) {
      throw StateError('Native capability generation requires ios/Podfile.');
    }
    final source = await podfile.readAsString();
    final block = '''$_podfileBegin
  pod 'NativeCapabilities', :path => './NativeCapabilities'
$_podfileEnd''';
    if (source.contains(_podfileBegin)) {
      final pattern = RegExp(
        '${RegExp.escape(_podfileBegin)}[\\s\\S]*?${RegExp.escape(_podfileEnd)}',
      );
      await podfile.writeAsString(source.replaceFirst(pattern, block));
      return;
    }
    const anchor = "target 'Runner' do";
    if (!source.contains(anchor)) {
      throw StateError("ios/Podfile does not contain target 'Runner' do.");
    }
    await podfile.writeAsString(source.replaceFirst(anchor, '$anchor\n$block'));
  }

  String _podspecSource() => '''
Pod::Spec.new do |spec|
  spec.name = 'NativeCapabilities'
  spec.version = '1.0.0'
  spec.summary = 'Generated native capability providers.'
  spec.homepage = 'https://invalid.local/native-capabilities'
  spec.license = { :type => 'Proprietary', :text => 'Generated source' }
  spec.author = { 'dart_prefix_renamer' => 'noreply@invalid.local' }
  spec.source = { :path => '.' }
  spec.source_files = '**/*.swift'
  spec.platform = :ios, '13.0'
  spec.swift_version = '5.0'
  spec.dependency 'Flutter'
  spec.frameworks = 'Foundation', 'UIKit', 'Network', 'Security', 'CryptoKit'
end
''';

  Future<String> _write(Directory root, String name, String content) async {
    final file = File(p.join(root.path, name));
    if (!file.existsSync() || await file.readAsString() != content) {
      await file.writeAsString(content);
    }
    return file.path;
  }

  String _protocolSource() => '''
import Foundation
import Security

protocol NativeCapability {
    static var capabilityName: String { get }
    func diagnostics() -> [String: Any]
}
''';

  String _managerSource(List<String> enabled) {
    final properties = enabled
        .map((name) => '    let ${_camel(name)} = ${_pascal(name)}Capability()')
        .join('\n');
    final diagnostics = enabled
        .map(
          (name) =>
              '            ${_pascal(name)}Capability.capabilityName: ${_camel(name)}.diagnostics(),',
        )
        .join('\n');
    return '''
import Foundation

final class NativeCapabilityManager {
$properties

    func allDiagnostics() -> [String: Any] {
        return [
$diagnostics
        ]
    }
}
''';
  }

  String _sourceFor(String capability) => switch (capability) {
    'device' =>
      '''
import Foundation
import UIKit

final class DeviceCapability: NativeCapability {
    static let capabilityName = "device"
    func snapshot() -> [String: String] {
        return ["model": UIDevice.current.model,
                "systemVersion": UIDevice.current.systemVersion,
                "locale": Locale.current.identifier]
    }
    func diagnostics() -> [String: Any] { snapshot() }
}
''',
    'network' =>
      '''
import Foundation
import Network

final class NetworkCapability: NativeCapability {
    static let capabilityName = "network"
    private let monitor = NWPathMonitor()
    private var currentPath: NWPath?
    init() {
        monitor.pathUpdateHandler = { [weak self] path in self?.currentPath = path }
        monitor.start(queue: DispatchQueue(label: "native.capability.network"))
    }
    func snapshot() -> [String: Any] {
        guard let path = currentPath else { return ["available": false] }
        return ["available": path.status == .satisfied,
                "expensive": path.isExpensive,
                "constrained": path.isConstrained]
    }
    func diagnostics() -> [String: Any] { snapshot() }
}
''',
    'secure_storage' =>
      '''
import Foundation
import Security

final class SecureStorageCapability: NativeCapability {
    static let capabilityName = "secure_storage"
    func set(_ value: Data, for key: String) -> OSStatus {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = value
        return SecItemAdd(insert as CFDictionary, nil)
    }
    func get(_ key: String) -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrAccount as String: key,
                                   kSecReturnData as String: true,
                                   kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
            ? result as? Data : nil
    }
    func delete(_ key: String) -> OSStatus {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrAccount as String: key] as CFDictionary)
    }
    func diagnostics() -> [String: Any] { ["provider": "keychain"] }
}
''',
    'crypto' =>
      '''
import CryptoKit
import Foundation

final class CryptoCapability: NativeCapability {
    static let capabilityName = "crypto"
    func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", \$0) }.joined()
    }
    func diagnostics() -> [String: Any] { ["algorithm": "sha256"] }
}
''',
    'diagnostics' =>
      '''
import Foundation

final class DiagnosticsCapability: NativeCapability {
    static let capabilityName = "diagnostics"
    func snapshot() -> [String: Any] {
        let process = ProcessInfo.processInfo
        return ["systemVersion": process.operatingSystemVersionString,
                "processorCount": process.processorCount,
                "lowPowerMode": process.isLowPowerModeEnabled]
    }
    func diagnostics() -> [String: Any] { snapshot() }
}
''',
    'performance' =>
      '''
import Foundation
import os

final class PerformanceCapability: NativeCapability {
    static let capabilityName = "performance"
    private let log = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "capability")
    func mark(_ name: String) {
        os_signpost(.event, log: log, name: "capability_mark", "%{public}s", name)
    }
    func diagnostics() -> [String: Any] { ["provider": "os_signpost"] }
}
''',
    _ => throw ArgumentError.value(capability, 'capability'),
  };

  String _bridgeSource(List<String> enabled) =>
      '''
import Foundation

public final class NativeCapabilityBridge {
    private let manager = NativeCapabilityManager()
    public init() {}

    ${enabled.contains('device') ? 'public func deviceInfo() throws -> String { try json(manager.device.snapshot()) }' : ''}
    ${enabled.contains('network') ? 'public func networkState() throws -> String { try json(manager.network.snapshot()) }' : ''}
    ${enabled.contains('diagnostics') ? 'public func diagnostics() throws -> String { try json(manager.diagnostics.snapshot()) }' : ''}
    ${enabled.contains('crypto') ? 'public func crypto(_ data: Data) -> String { manager.crypto.sha256(data) }' : ''}
    ${enabled.contains('performance') ? 'public func performance(_ name: String) { manager.performance.mark(name) }' : ''}
    ${enabled.contains('secure_storage') ? '''public func secureStorage(operation: String, key: String, value: String?) throws -> String? {
        switch operation {
        case "get": return manager.secureStorage.get(key).flatMap { String(data: \$0, encoding: .utf8) }
        case "set":
            guard let value else { throw BridgeError.invalidArgument }
            guard manager.secureStorage.set(Data(value.utf8), for: key) == errSecSuccess else { throw BridgeError.operationFailed }
            return value
        case "delete":
            let status = manager.secureStorage.delete(key)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw BridgeError.operationFailed }
            return nil
        default: throw BridgeError.invalidArgument
        }
    }''' : ''}

    private func json(_ value: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard let result = String(data: data, encoding: .utf8) else { throw BridgeError.operationFailed }
        return result
    }

    private enum BridgeError: String, Error { case invalidArgument, operationFailed }
}
''';

  String _pascal(String value) => value
      .split('_')
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join();

  String _camel(String value) {
    final pascal = _pascal(value);
    return '${pascal[0].toLowerCase()}${pascal.substring(1)}';
  }
}

class NativeGenerationReport {
  const NativeGenerationReport({
    required this.enabled,
    required this.generatedFiles,
    required this.contentHash,
  });

  final List<String> enabled;
  final List<String> generatedFiles;
  final String contentHash;
}
