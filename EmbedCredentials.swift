import Foundation
import CryptoKit

/// Companion tool to generate encrypted credentials for SecureNetworkSetup
/// 
/// Usage:
///   swift run EmbedCredentials <your-admin-password>
///
/// This will output the Base64-encoded values to paste into SecureNetworkSetup.swift
@main
struct EmbedCredentials {
    
    
    static func main() {
        guard CommandLine.arguments.count > 1 else {
            print("Usage: \(CommandLine.arguments[0]) <admin-password>")
            print()
            print("This tool generates encrypted credentials for SecureNetworkSetup")
            exit(1)
        }
        
        let password = CommandLine.arguments[1]
        
        do {
            // Generate random salt
            var saltBytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes)
            guard status == errSecSuccess else {
                throw NSError(domain: "Crypto", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to generate random salt"
                ])
            }
            let salt = Data(saltBytes)
            
            // Get machine UUID
            guard let machineUUID = getMachineUUID() else {
                throw NSError(domain: "System", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to get machine UUID"
                ])
            }
            
            // Derive encryption key
            let encryptionKey = deriveEncryptionKey(machineUUID: machineUUID, salt: salt)
            
            // Encrypt password
            let passwordData = Data(password.utf8)
            let sealedBox = try AES.GCM.seal(passwordData, using: encryptionKey)
            
            // Combine nonce + ciphertext + tag
            var encryptedData = Data()
            encryptedData.append(sealedBox.nonce.withUnsafeBytes { Data($0) })
            encryptedData.append(sealedBox.ciphertext)
            encryptedData.append(sealedBox.tag)
            
            // Read the network setup script from Script.sh
            guard let scriptContent = readScript() else {
                throw NSError(domain: "EmbedCredentials", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to read Script.sh"
                ])
            }
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("Script Content")
            print("\(scriptContent)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            // Sign the script
            let signingKey = deriveSigningKey(machineUUID: machineUUID, salt: salt)
            let scriptData = Data(scriptContent.utf8)
            let signature = HMAC<SHA256>.authenticationCode(for: scriptData, using: signingKey)
            
            // Output the results
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("✓ Credentials encrypted successfully")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print()
            print("Machine UUID: \(machineUUID)")
            print()
            print("⚠️  IMPORTANT: These values are bound to THIS machine only")
            print("   The binary will only work on: \(getMachineName() ?? "this Mac")")
            print()
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("Copy these values into SecureNetworkSetup.swift:")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print()
            print("// KDF Salt")
            print("let base64 = \"\(salt.base64EncodedString())\"")
            print()
            print("// Encrypted Password")
            print("let base64 = \"\(encryptedData.base64EncodedString())\"")
            print()
            print("// Script Signature")
            print("let base64 = \"\(Data(signature).base64EncodedString())\"")
            print()
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print()
            print("Security Notes:")
            print("  • Password is encrypted with AES-256-GCM")
            print("  • Encryption key is derived from machine UUID + salt")
            print("  • Even if extracted, data is useless on other machines")
            print()
            
        } catch {
            print("❌ Error: \(error.localizedDescription)")
            exit(1)
        }
    }
    
    // MARK: - Helper Functions
    
    private static func deriveEncryptionKey(machineUUID: String, salt: Data) -> SymmetricKey {
        let inputKeyMaterial = Data((machineUUID + "NETWORK_SETUP_ENCRYPTION").utf8)
        
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: inputKeyMaterial),
            salt: salt,
            info: Data("password-encryption".utf8),
            outputByteCount: 32
        )
    }
    
    private static func deriveSigningKey(machineUUID: String, salt: Data) -> SymmetricKey {
        let inputKeyMaterial = Data((machineUUID + "NETWORK_SETUP_SIGNING").utf8)
        
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: inputKeyMaterial),
            salt: salt,
            info: Data("script-signing".utf8),
            outputByteCount: 32
        )
    }
    
    private static func getMachineUUID() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        task.arguments = ["-rd1", "-c", "IOPlatformExpertDevice"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            
            // Parse: "IOPlatformUUID" = "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
            let pattern = #""IOPlatformUUID"\s*=\s*"([^"]+)""#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
               let range = Range(match.range(at: 1), in: output) {
                return String(output[range])
            }
        } catch {
            print("Error getting UUID: \(error)")
        }
        
        return nil
    }
    
    private static func getMachineName() -> String? {
        ProcessInfo.processInfo.hostName
    }
    
    /// Read the script content from Script.sh file
    private static func readScriptFile() -> String? {
        let scriptPath = "Script.sh"
        
        do {
            let scriptContent = try String(contentsOfFile: scriptPath, encoding: .utf8)
            
            // Extract just the main() function content (the actual script logic)
            // We want to skip the variable declarations at the top and just get the executable script
            let lines = scriptContent.split(separator: "\n", omittingEmptySubsequences: false)
            var scriptLines: [String] = []
            var inMainFunction = false
            var braceCount = 0
            
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                
                // Skip comments and variable declarations before main()
                if trimmed.hasPrefix("#") && !inMainFunction {
                    if trimmed.hasPrefix("#!/bin/sh") || trimmed.hasPrefix("#!/bin/bash") {
                        scriptLines.append("#!/bin/sh")  // Normalize shebang
                    }
                    continue
                }
                
                // Detect main() function start
                if trimmed.starts(with: "main()") || trimmed.starts(with: "main ()") {
                    inMainFunction = true
                    continue
                }
                
                // Track braces to know when main() ends
                if inMainFunction {
                    for char in line {
                        if char == "{" { braceCount += 1 }
                        if char == "}" { braceCount -= 1 }
                    }
                    
                    // Skip the opening brace line
                    if braceCount == 1 && trimmed == "{" {
                        continue
                    }
                    
                    // Stop at closing brace of main()
                    if braceCount == 0 && trimmed == "}" {
                        break
                    }
                    
                    // Add the line (with original indentation preserved)
                    scriptLines.append(String(line))
                }
            }
            
            // Remove common leading whitespace (dedent)
            let dedented = dedentScript(scriptLines.joined(separator: "\n"))
            
            // Ensure it starts with shebang and set -euo pipefail
            var finalScript = "#!/bin/sh\nset -euo pipefail\n\n"
            
            // Add the dedented content
            let contentWithoutShebang = dedented
                .replacingOccurrences(of: "#!/bin/sh", with: "")
                .replacingOccurrences(of: "#!/bin/bash", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            finalScript += contentWithoutShebang
            
            return finalScript
            
        } catch {
            print("Error reading Script.sh: \(error)")
            return nil
        }
    }
    
    /// Remove common leading whitespace from script
    private static func dedentScript(_ script: String) -> String {
        let lines = script.split(separator: "\n", omittingEmptySubsequences: false)
        
        // Find minimum indentation (excluding empty lines)
        let minIndent = lines
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { line in
                line.prefix(while: { $0 == " " }).count
            }
            .min() ?? 0
        
        // Remove that amount of leading spaces from each line
        let dedented = lines.map { line -> String in
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                return ""
            }
            let indent = line.prefix(while: { $0 == " " }).count
            if indent >= minIndent {
                return String(line.dropFirst(minIndent))
            }
            return String(line)
        }
        
        return dedented.joined(separator: "\n")
    }
    
    private static func readScript() -> String? {
        let scriptPath = "Script.sh"
        
        do {
            let scriptContent = try String(contentsOfFile: scriptPath, encoding: .utf8)
        
            return scriptContent
            
        } catch {
            print("Error reading Script.sh: \(error)")
            return nil
        }
    }
}
