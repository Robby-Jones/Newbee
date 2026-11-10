import Foundation

/// A small RFC 4180 CSV reader: quoted fields, doubled quotes inside them, commas and line
/// breaks inside quotes, CRLF or LF line endings, and a leading byte order mark.
public enum CSVTable {
    /// Every record in `text`, each a list of fields. Blank lines are dropped.
    public static func parse(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var fieldWasQuoted = false

        var scalars = text.unicodeScalars[...]
        if scalars.first == "\u{FEFF}" { scalars = scalars.dropFirst() }
        var iterator = scalars.makeIterator()
        var pending: Unicode.Scalar? = iterator.next()

        func endField() {
            record.append(field)
            field = ""
            fieldWasQuoted = false
        }
        func endRecord() {
            endField()
            if !(record.count == 1 && record[0].isEmpty) {
                records.append(record)
            }
            record = []
        }

        while let scalar = pending {
            pending = iterator.next()
            if inQuotes {
                if scalar == "\"" {
                    if pending == "\"" {
                        field.unicodeScalars.append("\"")
                        pending = iterator.next()
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.unicodeScalars.append(scalar)
                }
                continue
            }
            switch scalar {
            case "\"" where field.isEmpty && !fieldWasQuoted:
                inQuotes = true
                fieldWasQuoted = true
            case ",":
                endField()
            case "\r":
                if pending == "\n" { pending = iterator.next() }
                endRecord()
            case "\n":
                endRecord()
            default:
                field.unicodeScalars.append(scalar)
            }
        }
        if !field.isEmpty || !record.isEmpty || fieldWasQuoted {
            endRecord()
        }
        return records
    }
}
