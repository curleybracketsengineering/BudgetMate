import UniformTypeIdentifiers

extension UTType {
    static var qbo: UTType {
        UTType(filenameExtension: "qbo") ?? .data
    }

    static var ofx: UTType {
        UTType(filenameExtension: "ofx") ?? .data
    }
}
