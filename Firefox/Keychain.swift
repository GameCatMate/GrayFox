import Foundation
import Security

// Keep the source item unchanged and transfer only through a pipe to the importer.
let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,
 kSecAttrService as String:"org.openstvor.browser.passwords",
 kSecAttrAccount as String:"local-profile",
 kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
var result: CFTypeRef?
let status=SecItemCopyMatching(query as CFDictionary,&result)
if CommandLine.arguments.contains("--probe") {
 print("Keychain status: \(status)")
 if let message=SecCopyErrorMessageString(status,nil){print(message)}
 exit(status == errSecSuccess ? 0 : 1)
}
guard CommandLine.arguments == [CommandLine.arguments[0],"--transfer"],status==errSecSuccess,let data=result as? Data,
 let rows=try? JSONSerialization.jsonObject(with:data) as? [[String:Any]] else {
 FileHandle.standardError.write(Data("Keychain transfer unavailable (\(status))\n".utf8));exit(1)
}
guard rows.count<100000 else{exit(2)}
FileHandle.standardOutput.write(data)
