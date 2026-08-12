import UniformTypeIdentifiers

extension UTType {
    /// Anki deck packages have no system type, so the app declares one in `Info.plist`
    /// (`UTImportedTypeDeclarations`) and refers to it here (spec §A9.5).
    ///
    /// Falls back to `.zip` if the declaration is ever lost: an `.apkg` really is a ZIP, so
    /// the picker still shows the file rather than silently offering nothing.
    static var ankiPackage: UTType {
        UTType(importedAs: "org.ankiweb.apkg", conformingTo: .zip)
    }
}
