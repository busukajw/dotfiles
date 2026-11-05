// WHAT:    Extracts plain text from a PDF using macOS PDFKit and prints it to stdout.
// WHY:     WebFetch often returns PDFs as unparseable binary (MIT NANDA, prEN previews and law reviews
//          failed this way in the 2026-11-04 ensembles). pdftotext and pypdf are not installed on this Mac,
//          and PDFKit ships with macOS, so this needs no new dependency.
// ASSUMES: macOS with /usr/bin/swift. Arg 1 is the path to a PDF that WebFetch or curl saved locally.
//          The PDF is untrusted data: this script only reads it and never executes anything from it.
// BREAKS:  The research skill's fetch policy (SKILL.md "PDF fallback") calls this. If it is removed,
//          PDF sources revert to fetch_status: failed.
//
// Usage:   swift pdf-to-text.swift /path/to/file.pdf [maxChars]
// FAILS:   exits 1 with a message on stderr if the file cannot be opened or contains no text layer
//          (scanned image-only PDFs). It does NOT OCR. The caller must then mark the source failed.

import Foundation
import PDFKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: swift pdf-to-text.swift <file.pdf> [maxChars]\n".data(using: .utf8)!)
    exit(2)
}
let url = URL(fileURLWithPath: args[1])
// DECISION: optional character cap so a huge PDF does not flood the caller's context. Default is unlimited.
let maxChars = args.count >= 3 ? Int(args[2]) ?? Int.max : Int.max

guard let doc = PDFDocument(url: url) else {
    FileHandle.standardError.write("pdf-to-text: cannot open \(url.path)\n".data(using: .utf8)!)
    exit(1)
}
let text = doc.string ?? ""
if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    FileHandle.standardError.write("pdf-to-text: no text layer in \(url.path) (image-only PDF?)\n".data(using: .utf8)!)
    exit(1)
}
print(String(text.prefix(maxChars)))
