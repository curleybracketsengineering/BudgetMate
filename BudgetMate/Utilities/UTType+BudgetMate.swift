import UniformTypeIdentifiers

extension UTType {
    static var qbo: UTType {
        UTType(filenameExtension: "qbo") ?? UTType(filenameExtension: "ofx") ?? .data
    }
}
