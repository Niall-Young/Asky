import Foundation

public struct ConversionResult: Sendable, Equatable {
    public var input: Double
    public var fromSymbol: String
    public var value: Double
    public var toSymbol: String
    public var formattedValue: String {
        if value != 0, abs(value) < 1e-6 || abs(value) >= 1e15 { return String(format: "%.8g", value) }
        return Calculator.format((value * 1e6).rounded() / 1e6)
    }
    public var display: String { "\(Calculator.format(input)) \(fromSymbol) = \(formattedValue) \(toSymbol)" }
}

/// Length, mass, temperature and volume conversion, e.g. "10 km mi", "5 kg to lb", "100 °F in C".
public enum UnitConverter {
    static let units: [String: Dimension] = {
        var m: [String: Dimension] = [:]
        func add(_ unit: Dimension, _ names: String...) { names.forEach { m[$0] = unit } }
        // Length
        add(UnitLength.millimeters, "mm", "毫米")
        add(UnitLength.centimeters, "cm", "厘米")
        add(UnitLength.meters, "m", "米", "meter", "meters")
        add(UnitLength.kilometers, "km", "公里", "千米")
        add(UnitLength.inches, "in", "inch", "inches", "英寸")
        add(UnitLength.feet, "ft", "foot", "feet", "英尺")
        add(UnitLength.yards, "yd", "yard", "yards")
        add(UnitLength.miles, "mi", "mile", "miles", "英里")
        // Mass
        add(UnitMass.milligrams, "mg", "毫克")
        add(UnitMass.grams, "g", "克")
        add(UnitMass.kilograms, "kg", "公斤", "千克")
        add(UnitMass.ounces, "oz", "盎司")
        add(UnitMass.pounds, "lb", "lbs", "磅")
        add(UnitMass.metricTons, "t", "吨")
        add(UnitMass(symbol: "斤", converter: UnitConverterLinear(coefficient: 0.5)), "斤")
        add(UnitMass(symbol: "两", converter: UnitConverterLinear(coefficient: 0.05)), "两")
        // Temperature
        add(UnitTemperature.celsius, "c", "°c", "℃", "摄氏度")
        add(UnitTemperature.fahrenheit, "f", "°f", "℉", "华氏度")
        add(UnitTemperature.kelvin, "k", "kelvin")
        // Volume
        add(UnitVolume.milliliters, "ml", "毫升")
        add(UnitVolume.liters, "l", "升")
        add(UnitVolume.gallons, "gal", "gallon", "gallons")
        add(UnitVolume.fluidOunces, "floz", "fl oz")
        add(UnitVolume.cups, "cup", "cups")
        return m
    }()

    public static func convert(_ input: String) -> ConversionResult? {
        guard let (amount, from, to) = QuantityParser.parse(input) else { return nil }
        guard let fu = units[from.lowercased()], let tu = units[to.lowercased()] else { return nil }
        guard type(of: fu) == type(of: tu) || (fu is UnitMass && tu is UnitMass) else { return nil }
        let value = Measurement(value: amount, unit: fu).converted(to: tu).value
        guard value.isFinite else { return nil }
        return ConversionResult(input: amount, fromSymbol: from, value: value, toSymbol: to)
    }
}

/// Parses "<number> <unitA> [to|in|=|→|转|换成] <unitB>".
enum QuantityParser {
    static func parse(_ input: String) -> (Double, String, String)? {
        var s = input.trimmingCharacters(in: .whitespaces)
        for sep in ["=", "→", "->", " 转 ", "转", "换成"] {
            s = s.replacingOccurrences(of: sep, with: " ")
        }
        s = s.replacingOccurrences(of: "fl oz", with: "floz")
        // Split number prefix from the rest ("10km mi" → "10", "km mi").
        var idx = s.startIndex
        // Restrict digits to those accepted by Double; Chinese mass unit “两” is also isNumber.
        while idx < s.endIndex, (s[idx].isASCII && s[idx].isNumber) || s[idx] == "." || s[idx] == "," || (idx == s.startIndex && s[idx] == "-") {
            idx = s.index(after: idx)
        }
        let numStr = s[s.startIndex..<idx].replacingOccurrences(of: ",", with: "")
        guard !numStr.isEmpty, let amount = Double(numStr), amount.isFinite else { return nil }
        let rest = s[idx...].split(whereSeparator: \.isWhitespace).map(String.init)
        if rest.count == 3, ["to", "in"].contains(rest[1].lowercased()) { return (amount, rest[0], rest[2]) }
        guard rest.count == 2 else { return nil }
        return (amount, rest[0], rest[1])
    }
}
